#requires -Version 5.1

<#
.SYNOPSIS
離線驗證 Get-Help、檔案盤點與指定連線處理的保護條件。
.DESCRIPTION
使用 TestOutput 的獨立測試資料夾；TCP 查詢、程序查詢與原生斷線皆為替身，
不呼叫真實 SetTcpEntry。請在新的 PowerShell 程序執行，避免與已載入類別衝突。
.EXAMPLE
powershell -NoProfile -File .\Tests\Test-Scripts.ps1
.OUTPUTS
System.String。通過訊息與測試產物路徑；失敗時拋出錯誤。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $projectRoot ('TestOutput\scripts-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$collectScript = Join-Path $projectRoot 'Collect-Investigation.ps1'
$stopScript = Join-Path $projectRoot 'Stop-TargetConnection.ps1'
$optimizeScript = Join-Path $projectRoot 'Optimize-SqliteDatabase.ps1'

function Assert-True($condition, $message) {
    if (-not $condition) { throw "FAIL: $message" }
}

<#
    讀取 JSON 陣列。Windows PowerShell 5.1 的 ConvertFrom-Json 會把整個陣列當成
    單一管線物件，@() 會算成 1 筆；先取值再展開才能讓兩個版本一致。
#>
function Read-JsonArray {
    param([string]$Path)
    $value = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -eq $value) { return @() }
    return @($value)
}

$helpChecks = @(
    @{ Path = $collectScript; Synopsis = 'Windows' },
    @{ Path = $stopScript; Synopsis = 'IPv4' },
    @{ Path = $optimizeScript; Synopsis = 'SQLite' }
)
foreach ($entry in $helpChecks) {
    $path = $entry.Path
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "Syntax: $path"
    $help = Get-Help $path -Full
    Assert-True ($help.Synopsis -match $entry.Synopsis) "Synopsis: $path"
    Assert-True (@($help.examples.example).Count -ge 3) "Examples: $path"
    $command = Get-Command $path
    foreach ($parameter in $command.Parameters.Values) {
        if ($parameter.Name -in @('Verbose','Debug','ErrorAction','WarningAction','InformationAction',
            'ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable',
            'OutBuffer','PipelineVariable','WhatIf','Confirm')) { continue }
        $documented = @($help.parameters.parameter | Where-Object { $_.name -eq $parameter.Name })
        Assert-True ($documented.Count -eq 1 -and $documented[0].description) "Parameter help: $($parameter.Name)"
    }
}

# SQLite 壓縮測試使用真實的臨時資料庫；必須在 Get-Process 替身定義前執行。
$sqliteHelper = Join-Path $projectRoot 'Scripts\SqliteNative.cs'
if ('ProcessFix.Sqlite.SqliteNative' -as [type]) {
    throw 'Run tests in a fresh PowerShell process; SQLite helper already loaded.'
}
Add-Type -Path $sqliteHelper
$sqlite = [ProcessFix.Sqlite.SqliteNative]
$sqliteRoot = Join-Path $testRoot 'sqlite'
$null = New-Item -ItemType Directory -Path $sqliteRoot
$sqliteDb = Join-Path $sqliteRoot 'items.db'
$null = $sqlite::Execute($sqliteDb, 'CREATE TABLE items(id INTEGER PRIMARY KEY, payload TEXT);')
$null = $sqlite::Execute($sqliteDb, 'WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x < 4000) INSERT INTO items(payload) SELECT hex(randomblob(120)) FROM c;')
$null = $sqlite::Execute($sqliteDb, 'DELETE FROM items WHERE id % 20 <> 0;')

$sqliteCount = [int64]($sqlite::Query($sqliteDb, 'SELECT count(*) FROM items')[0][0])
$sqliteBefore = (Get-Item -LiteralPath $sqliteDb).Length
$sqliteHash = (Get-FileHash -LiteralPath $sqliteDb).Hash

$check = & $optimizeScript -DatabasePath $sqliteDb -CheckOnly
Assert-True ($check.Status -eq 'Checked') 'SQLite CheckOnly status'
Assert-True ((Get-FileHash -LiteralPath $sqliteDb).Hash -eq $sqliteHash) 'SQLite CheckOnly must not modify the database'

$sqliteBackup = Join-Path $sqliteRoot 'backup'
$preview = & $optimizeScript -DatabasePath $sqliteDb -BackupDirectory $sqliteBackup -WhatIf
Assert-True ($preview.Status -eq 'Checked') 'SQLite WhatIf status'
Assert-True (-not (Test-Path -LiteralPath $sqliteBackup)) 'SQLite WhatIf must not create the backup directory'

$selfName = (Get-Process -Id $PID).ProcessName
$blocked = $false
try { & $optimizeScript -DatabasePath $sqliteDb -BackupDirectory $sqliteBackup -OwnerProcess $selfName } catch { $blocked = $true }
Assert-True $blocked 'SQLite OwnerProcess guard must abort'

$compacted = & $optimizeScript -DatabasePath $sqliteDb -BackupDirectory $sqliteBackup -VerifyTables items -Confirm:$false
Assert-True ($compacted.Status -eq 'Compacted') 'SQLite compact status'
Assert-True ($compacted.VerifyCounts.items -eq $sqliteCount) 'SQLite verify count must match'
Assert-True ((Get-Item -LiteralPath $sqliteDb).Length -lt $sqliteBefore) 'SQLite file must shrink'
Assert-True (Test-Path -LiteralPath $compacted.BackupPath) 'SQLite backup must exist'
Assert-True ([int64]($sqlite::Query($sqliteDb, 'PRAGMA freelist_count')[0][0]) -eq 0) 'SQLite freelist must be zero'
Assert-True ([string]($sqlite::Query($sqliteDb, 'PRAGMA integrity_check')[0][0]) -eq 'ok') 'SQLite integrity must pass'

$missing = $false
try { & $optimizeScript -DatabasePath (Join-Path $sqliteRoot 'missing.db') -CheckOnly } catch { $missing = $true }
Assert-True $missing 'SQLite missing database must fail'

$absent = $false
try { & $optimizeScript -DatabasePath $sqliteDb -BackupDirectory $sqliteBackup -VerifyTables absent -Confirm:$false } catch { $absent = $true }
Assert-True $absent 'SQLite unknown verify table must fail'

$fixtures = Join-Path $testRoot 'files with spaces'
$null = New-Item -ItemType Directory -Path $fixtures
foreach ($name in @('recent.txt','old.txt','Fiz_writer_1.qnq')) {
    Set-Content -LiteralPath (Join-Path $fixtures $name) -Value $name -Encoding UTF8
}
foreach ($name in @('old.txt','Fiz_writer_1.qnq')) {
    $file = Get-Item -LiteralPath (Join-Path $fixtures $name)
    $file.CreationTimeUtc = [DateTime]::UtcNow.AddDays(-40)
    $file.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-40)
}
$reports = Join-Path $testRoot 'reports'
$first = & $collectScript -Roots $fixtures -SkipSystem -OutputRoot $reports -HashFiles
$files = @(Read-JsonArray -Path (Join-Path $first 'files.json'))
Assert-True ($files.Count -eq 1 -and $files[0].Path.EndsWith('recent.txt')) 'Default must not include old case-specific names.'
Assert-True ($files[0].SHA256 -eq (Get-FileHash -LiteralPath (Join-Path $fixtures 'recent.txt')).Hash) 'File hash must match.'
$second = & $collectScript -Roots $fixtures -SkipSystem -OutputRoot $reports -IncludePathPattern 'Fiz_writer_1|\.qnq$'
$files = @(Read-JsonArray -Path (Join-Path $second 'files.json'))
Assert-True ($files.Count -eq 2) 'Explicit pattern must include old matching file plus recent file.'
$manifest = Get-Content -LiteralPath (Join-Path $second 'manifest.json') -Raw | ConvertFrom-Json
Assert-True ($manifest.IncludePathPattern -eq 'Fiz_writer_1|\.qnq$') 'Manifest must preserve pattern.'
$badOutput = Join-Path $testRoot 'invalid-pattern'
$failed = $false
try { & $collectScript -Roots $fixtures -SkipSystem -OutputRoot $badOutput -IncludePathPattern '[' }
catch { $failed = $true }
Assert-True ($failed -and -not (Test-Path -LiteralPath $badOutput)) 'Invalid regex must fail before writing reports.'

# 測試替身只有計數器，沒有 P/Invoke，不可能中斷真實連線。
if ('ProcessFix.Network.TcpNative' -as [type]) {
    throw 'Run tests in a fresh PowerShell process; native helper already loaded.'
}
Add-Type -TypeDefinition @'
namespace ProcessFix.Network {
    public static class TcpNative {
        public static int Calls;
        public static uint Result;
        public static uint Close(string local, int port, string remote, int remotePort) {
            Calls++;
            return Result;
        }
    }
}
'@

$testState = @{ Scenario = ''; QueryCount = 0; ProcessCount = 0 }
$testState.QueryCount = 0
$testState.ProcessCount = 0
function Get-NetTCPConnection {
    [CmdletBinding()]
    param()
    $testState.QueryCount++
    if ($testState.Scenario -eq 'query-error') { throw 'Simulated query failure' }
    if ($testState.Scenario -eq 'missing' -or ($testState.Scenario -eq 'success' -and $testState.QueryCount -ge 3)) { return }
    $created = [datetime]'2026-01-01T00:00:00Z'
    if ($testState.Scenario -eq 'connection-replaced' -and $testState.QueryCount -ge 2) { $created = $created.AddSeconds(1) }
    $row = [pscustomobject]@{
        State = 'Established'
        LocalAddress = '192.0.2.10'
        LocalPort = 50000
        RemoteAddress = '198.51.100.20'
        RemotePort = 443
        OwningProcess = 1234
        CreationTime = $created
    }
    if ($testState.Scenario -eq 'wrong-pid') { $row.OwningProcess = 9999 }
    if ($testState.Scenario -eq 'wrong-port') { $row.LocalPort = 50001 }
    $row
    if ($testState.Scenario -eq 'duplicate') { $row }
}

function Get-Process {
    [CmdletBinding()]
    param([int]$Id)
    $testState.ProcessCount++
    $started = [datetime]'2026-01-01T00:00:00Z'
    if ($testState.Scenario -eq 'process-replaced' -and $testState.ProcessCount -ge 2) { $started = $started.AddSeconds(1) }
    $name = if ($testState.Scenario -eq 'wrong-name') { 'other' } else { 'example' }
    [pscustomobject]@{ Id = $Id; ProcessName = $name; StartTime = $started }
}

$target = @{
    LocalAddress = '192.0.2.10'
    LocalPort = 50000
    RemoteAddress = '198.51.100.20'
    RemotePort = 443
    TargetProcessId = 1234
    ExpectedProcessName = 'example'
}

foreach ($case in @('whatif','missing','wrong-pid','wrong-port','wrong-name','duplicate','query-error',
    'connection-replaced','process-replaced','success','still-present','native-error')) {
    $testState.Scenario = $case
    $testState.QueryCount = 0
    $testState.ProcessCount = 0
    [ProcessFix.Network.TcpNative]::Calls = 0
    [ProcessFix.Network.TcpNative]::Result = if ($case -eq 'native-error') { 5 } else { 0 }
    $caseOutput = Join-Path $testRoot $case
    $failed = $false
    $result = $null
    try {
        if ($case -eq 'whatif') {
            $result = & $stopScript @target -OutputRoot $caseOutput -WhatIf
        } else {
            $result = & $stopScript @target -OutputRoot $caseOutput -Confirm:$false
        }
    } catch { $failed = $true }

    $expectsNative = $case -in @('success','still-present','native-error')
    $expectsFailure = $case -in @('wrong-name','duplicate','query-error','connection-replaced','process-replaced','native-error')
    Assert-True ($failed -eq $expectsFailure) "Failure behavior: $case"
    Assert-True ([ProcessFix.Network.TcpNative]::Calls -eq [int]$expectsNative) "Native call boundary: $case calls=$([ProcessFix.Network.TcpNative]::Calls) expected=$expectsNative queries=$($testState.QueryCount) result=$($result.Status)"
    if ($case -in @('whatif','missing','wrong-pid','wrong-port')) {
        Assert-True (-not (Test-Path -LiteralPath $caseOutput)) "No report for preview or unmatched target: $case"
    }
    if ($case -eq 'whatif') { Assert-True ($result.Status -eq 'Skipped') 'WhatIf result' }
    if ($case -eq 'success') { Assert-True ($result.Status -eq 'Closed') 'Closed result' }
    if ($case -eq 'still-present') { Assert-True ($result.Status -eq 'StillEstablished') 'StillEstablished result' }
    if ($case -eq 'native-error') {
        $logFile = Get-ChildItem -LiteralPath $caseOutput -Filter '*.json'
        $record = Get-Content -LiteralPath $logFile.FullName -Raw | ConvertFrom-Json
        Assert-True ($record.Status -eq 'Failed' -and $record.Win32Result -eq 5) 'Failed native result must be logged.'
    }
}

$failed = $false
$ipv6Target = $target.Clone()
$ipv6Target.RemoteAddress = '::1'
try { & $stopScript @ipv6Target -WhatIf }
catch { $failed = $true }
Assert-True $failed 'IPv6 must be rejected.'
Write-Output "PASS: help, collection, pattern/hash, WhatIf, exact matching, identity changes, errors, results, SQLite compaction. Artifacts: $testRoot"
