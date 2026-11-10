#requires -Version 5.1

<#
.SYNOPSIS
壓縮 SQLite 資料庫檔案，先驗證副本再替換。

.DESCRIPTION
SQLite 刪除或改寫資料後，只會把頁面標成 free page，不會把空間還給作業系統。
本工具用 VACUUM INTO 在指定目錄產生一份壓縮副本，驗證完整性與指定資料表的
筆數後，才替換原始檔案；失敗時會把副本放回原位。

不會就地 VACUUM，因此備份所在磁碟只需要「實際使用頁」大小的空間，不需要
與原始檔案等量的空間。預設要求確認；-WhatIf 只顯示計畫，-CheckOnly 只量測。

執行前請先停止使用該資料庫的程式。工具會嘗試取得獨佔鎖定，失敗即中止；
-OwnerProcess 可再加一道程序名稱檢查。

.PARAMETER DatabasePath
要壓縮的 SQLite 資料庫檔案路徑。必需存在，且建議先停止寫入該檔案的程式。

.PARAMETER BackupDirectory
壓縮副本與備份的放置目錄。必需有足夠空間，且不能與原始檔同一條路徑。
替換成功後副本會保留，作為回滾來源。

.PARAMETER VerifyTables
替換前後要比對筆數的資料表名稱。任一表不存在或筆數不同就中止，不做替換。

.PARAMETER OwnerProcess
額外檢查的程序名稱（可省略 .exe）。偵測到執行中就中止，避免壓縮正在寫入的資料庫。

.PARAMETER CheckOnly
只量測檔案大小、頁面使用量、free page、journal 模式與資料表筆數，不改動任何檔案，
也不會嘗試取得獨佔鎖定，因此可以在程式執行中先查看。此時不需要 BackupDirectory。

.EXAMPLE
Get-Help .\Optimize-SqliteDatabase.ps1 -Full
查看說明，不讀取或修改任何資料庫。

.EXAMPLE
.\Optimize-SqliteDatabase.ps1 -DatabasePath 'D:\app\data.db' -CheckOnly
只量測，不建立副本；適合先確認可回收空間與所需備份空間。

.EXAMPLE
opencode service stop
.\Optimize-SqliteDatabase.ps1 -DatabasePath "$env:USERPROFILE\.local\share\opencode\opencode.db" -BackupDirectory 'D:\opencode-backup' -VerifyTables session,message,part,todo -OwnerProcess opencode
opencode service start
停止 OpenCode 服務後壓縮其資料庫，驗證指定資料表的筆數，再自行啟動服務。

.INPUTS
無。不接受管線輸入。

.OUTPUTS
PSCustomObject。Status 為 Checked、Compacted 或 Skipped，並含檔案大小、頁面統計、
BackupPath 與 VerifyCounts。失敗會拋出錯誤。

.NOTES
Windows PowerShell 5.1 / PowerShell 7；需要 Windows 內建的 winsqlite3.dll（Windows 10 以後）。
SQLite 需 3.27 以上才支援 VACUUM INTO。只支援一般 SQLite 檔案，不支援加密資料庫。
獨佔鎖定檢查與實際替換之間仍有競態；替換期間請勿讓其他程式開啟該資料庫。
備份副本是唯一回滾來源，確認資料無誤前不要刪除。

.LINK
Docs/SqliteMaintenance.md
#>
[CmdletBinding(DefaultParameterSetName = 'Optimize', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Check')]
    [Parameter(Mandatory = $true, ParameterSetName = 'Optimize')]
    [string]$DatabasePath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Optimize')]
    [string]$BackupDirectory,

    [Parameter(ParameterSetName = 'Check')]
    [Parameter(ParameterSetName = 'Optimize')]
    [string[]]$VerifyTables,

    [Parameter(ParameterSetName = 'Check')]
    [Parameter(ParameterSetName = 'Optimize')]
    [string[]]$OwnerProcess,

    [Parameter(Mandatory = $true, ParameterSetName = 'Check')]
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host ('[step] ' + $Message) -ForegroundColor Cyan
}

<#
    以人類可讀單位輸出位元組數；小檔案不出現 0.00 GiB。
#>
function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GiB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MiB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KiB' -f ($Bytes / 1KB))
}

<#
    讀取單一 PRAGMA 值。PRAGMA 名稱由本檔固定提供，不接收外部輸入。
#>
function Get-PragmaValue {
    param(
        [string]$Path,
        [string]$Pragma
    )
    $rows = [ProcessFix.Sqlite.SqliteNative]::Query($Path, ('PRAGMA ' + $Pragma))
    if ($rows.Count -eq 0 -or $rows[0].Count -eq 0) {
        throw ('PRAGMA ' + $Pragma + ' returned no value.')
    }
    return [string]$rows[0][0]
}

<#
    取得指定資料表的筆數；資料表名稱先以參數化方式確認存在，再以雙引號跳脫。
#>
function Get-TableCount {
    param(
        [string]$Path,
        [string]$Table
    )
    $literal = $Table.Replace("'", "''")
    $exists = [ProcessFix.Sqlite.SqliteNative]::Query(
        $Path,
        ("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = '" + $literal + "' COLLATE NOCASE")
    )
    if ($exists.Count -eq 0 -or [int64]$exists[0][0] -eq 0) {
        throw ('Verify table not found: ' + $Table)
    }
    $quoted = $Table.Replace('"', '""')
    $rows = [ProcessFix.Sqlite.SqliteNative]::Query($Path, ('SELECT count(*) FROM "' + $quoted + '"'))
    return [int64]$rows[0][0]
}

# --- 前置檢查 --------------------------------------------------------------

$dbPath = [System.IO.Path]::GetFullPath($DatabasePath)
if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
    throw ('Database not found: ' + $dbPath)
}

$helperPath = Join-Path $PSScriptRoot 'Scripts\SqliteNative.cs'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw ('Missing native helper: ' + $helperPath)
}
if (-not ('ProcessFix.Sqlite.SqliteNative' -as [type])) {
    Add-Type -Path $helperPath
}
$sqlite = [ProcessFix.Sqlite.SqliteNative]
$sqliteVersion = $sqlite::Version()
if ($sqlite::VersionNumber() -lt 3027000) {
    throw ('SQLite ' + $sqliteVersion + ' does not support VACUUM INTO; 3.27 or newer is required.')
}

foreach ($name in $OwnerProcess) {
    $clean = $name.Trim()
    if ($clean.ToLowerInvariant().EndsWith('.exe')) {
        $clean = $clean.Substring(0, $clean.Length - 4)
    }
    $running = @(Get-Process -Name $clean -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $ids = ($running | ForEach-Object { $_.Id }) -join ', '
        throw ('Process ' + $clean + ' is running (PID ' + $ids + '). Stop it before compacting its database.')
    }
}

$walPath = $dbPath + '-wal'
$shmPath = $dbPath + '-shm'
$beforeBytes = (Get-Item -LiteralPath $dbPath).Length
$walBytes = 0
if (Test-Path -LiteralPath $walPath) {
    $walBytes = (Get-Item -LiteralPath $walPath).Length
}

if ($PSCmdlet.ParameterSetName -eq 'Optimize') {
    try {
        $null = $sqlite::Execute(
            $dbPath,
            'PRAGMA locking_mode = EXCLUSIVE; BEGIN EXCLUSIVE; ROLLBACK; PRAGMA locking_mode = NORMAL;'
        )
    }
    catch {
        throw ('Cannot lock the database exclusively, so another process is probably using it. Stop that application first. ' + $_.Exception.Message)
    }
}

$pageSize = [int64](Get-PragmaValue -Path $dbPath -Pragma 'page_size')
$pageCount = [int64](Get-PragmaValue -Path $dbPath -Pragma 'page_count')
$freelist = [int64](Get-PragmaValue -Path $dbPath -Pragma 'freelist_count')
$journalMode = Get-PragmaValue -Path $dbPath -Pragma 'journal_mode'
$usedBytes = ($pageCount - $freelist) * $pageSize
$freePageBytes = $freelist * $pageSize

$tableRows = @($sqlite::Query($dbPath, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"))
$tables = @($tableRows | ForEach-Object { $_[0] })

$sourceCounts = @{}
foreach ($table in $VerifyTables) {
    $sourceCounts[$table] = Get-TableCount -Path $dbPath -Table $table
}

Write-Host ''
Write-Host ('Database : ' + $dbPath)
Write-Host ('File size: ' + (Format-Bytes $beforeBytes))
Write-Host ('WAL      : ' + (Format-Bytes $walBytes))
Write-Host ('Used     : ' + (Format-Bytes $usedBytes) + '   Free pages: ' + (Format-Bytes $freePageBytes))
Write-Host ('Journal  : ' + $journalMode)
Write-Host ('Tables   : {0}' -f $tables.Count)
if ($sourceCounts.Count -gt 0) {
    $pairs = @($sourceCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Key + '=' + $_.Value })
    Write-Host ('Verify   : ' + ($pairs -join ', '))
}
Write-Host ('SQLite   : ' + $sqliteVersion)

$backupFull = $null
$needBytes = [int64]($usedBytes * 1.2) + 1GB
if ($PSCmdlet.ParameterSetName -eq 'Optimize') {
    $backupFull = [System.IO.Path]::GetFullPath($BackupDirectory)
    $backupRoot = [System.IO.Path]::GetPathRoot($backupFull)
    try {
        $backupDrive = New-Object System.IO.DriveInfo($backupRoot)
        $backupFree = $backupDrive.AvailableFreeSpace
    }
    catch {
        throw ('Cannot read free space for ' + $backupRoot + ': ' + $_.Exception.Message)
    }
    Write-Host ('Backup   : ' + $backupFull + '  (free ' + (Format-Bytes $backupFree) +
            ', need about ' + (Format-Bytes $needBytes) + ')')
    if ($backupFree -lt $needBytes) {
        throw ('Not enough free space in ' + $backupFull + ': need about ' +
            (Format-Bytes $needBytes) + ', have ' + (Format-Bytes $backupFree) + '.')
    }
}

$result = [pscustomobject]@{
    Status        = 'Checked'
    DatabasePath  = $dbPath
    BackupPath    = $backupFull
    BeforeBytes   = $beforeBytes
    UsedBytes     = $usedBytes
    FreePageBytes = $freePageBytes
    PageSize      = $pageSize
    PageCount     = $pageCount
    Freelist      = $freelist
    JournalMode   = $journalMode
    Tables        = $tables.Count
    VerifyCounts  = [pscustomobject]$sourceCounts
    SqliteVersion = $sqliteVersion
}

if ($CheckOnly -or $WhatIfPreference) {
    Write-Host ''
    if ($CheckOnly) {
        Write-Step 'Check only: no files changed'
    }
    else {
        Write-Step 'WhatIf: no files changed'
    }
    return $result
}

if (-not $PSCmdlet.ShouldProcess($dbPath, ('Compact SQLite database into ' + $backupFull))) {
    $result.Status = 'Skipped'
    return $result
}

# --- 壓縮與替換 ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $backupFull)) {
    $null = New-Item -ItemType Directory -Path $backupFull -Force
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($dbPath)
$backupPath = Join-Path $backupFull ($baseName + '-compacted-' + $stamp + '.db')
$suffix = 1
while (Test-Path -LiteralPath $backupPath) {
    $backupPath = Join-Path $backupFull ($baseName + '-compacted-' + $stamp + '-' + $suffix + '.db')
    $suffix++
}

$replacementStarted = $false
try {
    Write-Step ('Creating a compacted copy at ' + $backupPath)
    try {
        $null = $sqlite::Execute($dbPath, 'PRAGMA wal_checkpoint(TRUNCATE)')
    }
    catch {
        Write-Warning ('WAL checkpoint skipped: ' + $_.Exception.Message)
    }
    $escapedBackup = $backupPath.Replace("'", "''")
    $null = $sqlite::Execute($dbPath, ("VACUUM INTO '" + $escapedBackup + "'"))

    Write-Step 'Verifying the compacted copy'
    $integrity = [string]($sqlite::Query($backupPath, 'PRAGMA integrity_check')[0][0])
    if ($integrity -ne 'ok') {
        throw ('Integrity check failed on the compacted copy: ' + $integrity)
    }
    $backupFreelist = [int64](Get-PragmaValue -Path $backupPath -Pragma 'freelist_count')
    if ($backupFreelist -ne 0) {
        throw ('The compacted copy still has ' + $backupFreelist + ' free pages.')
    }
    foreach ($table in $sourceCounts.Keys) {
        $after = Get-TableCount -Path $backupPath -Table $table
        if ($after -ne $sourceCounts[$table]) {
            throw ('Row count mismatch for ' + $table + ': before=' +
                $sourceCounts[$table] + ' after=' + $after)
        }
    }

    Write-Step 'Replacing the original database'
    $replacementStarted = $true
    Remove-Item -LiteralPath $dbPath -Force
    if (Test-Path -LiteralPath $walPath) { Remove-Item -LiteralPath $walPath -Force }
    if (Test-Path -LiteralPath $shmPath) { Remove-Item -LiteralPath $shmPath -Force }
    Copy-Item -LiteralPath $backupPath -Destination $dbPath

    foreach ($table in $sourceCounts.Keys) {
        $copied = Get-TableCount -Path $dbPath -Table $table
        if ($copied -ne $sourceCounts[$table]) {
            throw ('Verification after copy failed for ' + $table +
                '. A verified copy is at ' + $backupPath)
        }
    }

    $afterBytes = (Get-Item -LiteralPath $dbPath).Length
    $result.Status = 'Compacted'
    $result | Add-Member -NotePropertyName BackupPath -NotePropertyValue $backupPath -Force
    $result | Add-Member -NotePropertyName AfterBytes -NotePropertyValue $afterBytes -Force
    $result | Add-Member -NotePropertyName ReclaimedBytes -NotePropertyValue ($beforeBytes - $afterBytes) -Force

    Write-Host ''
    Write-Host ('Done: ' + (Format-Bytes $beforeBytes) + ' -> ' + (Format-Bytes $afterBytes) +
            ' (freed ' + (Format-Bytes ($beforeBytes - $afterBytes)) + ')') -ForegroundColor Green
    Write-Host ('Backup (verified copy): ' + $backupPath)

    return $result
}
catch {
    if ($replacementStarted -and (Test-Path -LiteralPath $backupPath)) {
        Write-Warning 'Restoring the verified copy over the replaced database.'
        Copy-Item -LiteralPath $backupPath -Destination $dbPath -Force
    }
    throw
}
