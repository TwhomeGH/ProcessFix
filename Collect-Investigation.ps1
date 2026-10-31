#requires -Version 5.1

<#
.SYNOPSIS
蒐集 Windows 本機檔案、程序與系統事件，產生可供排查的 JSON 報告。
.DESCRIPTION
遞迴盤點指定目錄中最近建立或修改的檔案，並可蒐集 Defender、程序、TCP、
啟動項、服務與排程工作。只蒐集資訊及寫入報告，不執行樣本或進行修復。
不追蹤 reparse point。預設不套用任何個案名稱，也不計算樣本雜湊。
.PARAMETER Days
檔案時間與 Defender 事件的回溯天數，預設 7，範圍 1–3650。
.PARAMETER Roots
待盤點的目錄陣列，預設使用者 Temp 與 Windows Temp。支援中文及空白路徑。
.PARAMETER OutputRoot
報告父目錄，預設為腳本旁的 Reports；每次建立不同的時間戳與隨機識別子目錄。
.PARAMETER MaxEntries
所有 Roots 共用的目錄項目上限，包含檔案與資料夾，預設 100000。
.PARAMETER MaxEvents
Defender 事件數上限，預設 10000；達到上限會記錄可能缺漏。
.PARAMETER HashFiles
對納入的檔案計算 SHA-256；會讀取檔案內容，可能觸發防毒軟體。
.PARAMETER MaxHashMB
單一可雜湊檔案的大小上限，單位 MiB，預設 64。僅搭配 HashFiles 生效。
.PARAMETER SkipSystem
略過所有系統快照，只盤點 Roots。適合指定目錄檢查或隔離測試。
.PARAMETER IncludePathPattern
選填的 .NET 正規表示式，對完整檔案路徑不分大小寫比對。
命中者不受 Days 篩選限制，標記 ReferencedName；其他近期檔案仍會納入。
未指定時不比對個案名稱。無效表示式會在建立報告前被拒絕。
.EXAMPLE
Get-Help .\Collect-Investigation.ps1 -Full
查看完整參數與限制，不執行蒐集。
.EXAMPLE
.\Collect-Investigation.ps1 -Roots 'C:\Temp' -Days 3 -SkipSystem
只盤點指定資料夾的近期檔案。
.EXAMPLE
.\Collect-Investigation.ps1 -Days 30 -HashFiles -MaxHashMB 16
蒐集最近 30 天資訊，雜湊大小不超過 16 MiB 的檔案。
.EXAMPLE
.\Collect-Investigation.ps1 -Roots 'C:\Temp' -IncludePathPattern 'sample-name|\.example$' -SkipSystem
另將符合自訂線索的較舊檔案納入，並非只顯示命中檔案。
.INPUTS
無。不接受管線輸入。
.OUTPUTS
System.String。新產生報告資料夾的路徑。
.NOTES
支援 Windows PowerShell 5.1 與 PowerShell 7。一般權限可開始；讀取失敗記於
issues.json，涵蓋範圍記於 coverage.json。檔案時間與名稱不是惡意程式判定。
報告可能包含路徑、命令列及網路位址。無法建立報告等致命錯誤會中止執行。
.LINK
Docs/Investigation.md
#>
[CmdletBinding()]
param(
    [ValidateRange(1,3650)][int]$Days = 7,
    [ValidateNotNullOrEmpty()][string[]]$Roots = @($env:TEMP, "$env:SystemRoot\Temp"),
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'Reports'),
    [ValidateRange(1,1000000)][int]$MaxEntries = 100000,
    [ValidateRange(1,100000)][int]$MaxEvents = 10000,
    [switch]$HashFiles,
    [ValidateRange(1,4096)][int]$MaxHashMB = 64,
    [switch]$SkipSystem,
    [ValidateNotNullOrEmpty()][string]$IncludePathPattern
)
$ErrorActionPreference = 'Stop'
# 先驗證自訂線索，避免參數錯誤時留下不完整的報告資料夾。
$pathMatcher = $null
if ($PSBoundParameters.ContainsKey('IncludePathPattern')) {
    $pathMatcher = New-Object System.Text.RegularExpressions.Regex -ArgumentList @(
        $IncludePathPattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase,
        [TimeSpan]::FromSeconds(1)
    )
}
$start = [DateTime]::UtcNow
$since = $start.AddDays(-$Days)
$out = Join-Path $OutputRoot ($start.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$null = New-Item -ItemType Directory -Path $out
$outFull = [IO.Path]::GetFullPath($out).TrimEnd('\') + '\'
$issues = New-Object 'System.Collections.Generic.List[object]'
$files = New-Object 'System.Collections.Generic.List[object]'
$timeline = New-Object 'System.Collections.Generic.List[object]'
$coverage = New-Object 'System.Collections.Generic.List[object]'
function Issue($source, $message) {
    $issues.Add([pscustomobject]@{Source=$source; Message=[string]$message})
}

function SaveJson($name, $data) {
    ConvertTo-Json -InputObject @($data) -Depth 12 | Set-Content -LiteralPath (Join-Path $out "$name.json") -Encoding UTF8
}

function Snapshot($name, [scriptblock]$action) {
    <#
    .SYNOPSIS
    蒐集一個來源的快照，記錄失敗而不中止其他來源的蒐集。
    .PARAMETER name
    報告檔名及 coverage 的來源識別。
    .PARAMETER action
    回傳可序列化資料的查詢區塊。
    .OUTPUTS
    無；寫入 JSON 並更新 coverage / issues。
    #>
    try {
        $data = @(& $action)
        SaveJson $name $data
        $coverage.Add([pscustomobject]@{Source=$name; Status='Collected'; Count=$data.Count})
    } catch {
        Issue $name $_.Exception.Message
        $coverage.Add([pscustomobject]@{Source=$name; Status='Failed'; Count=0})
    }
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$visited = 0
foreach ($root in ($Roots | Select-Object -Unique)) {
    $before = $files.Count
    $issueBefore = $issues.Count
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    try {
        $item = Get-Item -LiteralPath $root -Force
        if (!$item.PSIsContainer) { throw 'Root must be a directory.' }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse-point root skipped.' }
        $queue.Enqueue($item.FullName)
    } catch { Issue $root $_.Exception.Message }
    while ($queue.Count -gt 0 -and $visited -lt $MaxEntries) {
        $dir = $queue.Dequeue()
        if (!$seen.Add($dir)) { continue }
        if (($dir.TrimEnd('\') + '\').StartsWith($outFull, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $enumErrors = @()
        $children = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue -ErrorVariable enumErrors)
        foreach ($err in $enumErrors) { Issue $dir $err.Exception.Message }
        foreach ($f in $children) {
            if ($visited -ge $MaxEntries) { break }
            $visited++
            if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) { Issue $f.FullName 'Reparse point skipped'; continue }
            if ($f.PSIsContainer) { $queue.Enqueue($f.FullName); continue }
            $known = $false
            if ($null -ne $pathMatcher) {
                try { $known = $pathMatcher.IsMatch($f.FullName) }
                catch [Text.RegularExpressions.RegexMatchTimeoutException] {
                    Issue $f.FullName 'IncludePathPattern timed out; older matching files may be omitted.'
                }
            }
            if (!$known -and $f.CreationTimeUtc -lt $since -and $f.LastWriteTimeUtc -lt $since) { continue }
            $reasons = @()
            if ($known) { $reasons += 'ReferencedName' }
            if ($f.Extension -match '^(?i)\.(exe|dll|scr|com|ps1|bat|cmd|vbs|js|hta|he|qnq)$') { $reasons += 'ReviewExtension' }
            $hash = $null; $hashStatus = 'NotRequested'
            if ($HashFiles) {
                if ($f.Length -gt ($MaxHashMB * 1MB)) { $hashStatus = 'SizeLimit' }
                else {
                    try {
                        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
                        $after = Get-Item -LiteralPath $f.FullName -Force
                        $hashStatus = 'Collected'
                        if ($after.Length -ne $f.Length -or $after.LastWriteTimeUtc -ne $f.LastWriteTimeUtc) { $hashStatus = 'ChangedDuringRead' }
                    } catch { $hashStatus = 'Failed'; Issue $f.FullName $_.Exception.Message }
                }
            }
            $files.Add([pscustomobject]@{Path=$f.FullName;Bytes=$f.Length;CreationUtc=$f.CreationTimeUtc.ToString('o');WriteUtc=$f.LastWriteTimeUtc.ToString('o');ReviewReasons=($reasons -join ';');SHA256=$hash;HashStatus=$hashStatus})
            foreach ($kind in @('CreationTimeUtc','LastWriteTimeUtc')) {
                $timeline.Add([pscustomobject]@{TimeUtc=$f.$kind.ToString('o');Source='Filesystem';Kind=$kind;Detail=$f.FullName})
            }
        }
    }
    $status = 'Collected'
    if ($issues.Count -gt $issueBefore) { $status = 'PartialOrUnavailable' }
    if ($visited -ge $MaxEntries) { $status = 'EntryLimitReached'; Issue $root 'Global entry limit reached; inventory may be incomplete.' }
    $coverage.Add([pscustomobject]@{Source=$root;Status=$status;Count=($files.Count-$before)})
}
if (!$SkipSystem) {
    Snapshot 'defender-detections' { Get-MpThreatDetection | Select-Object ThreatID,InitialDetectionTime,LastThreatStatusChangeTime,ActionSuccess,Resources,ProcessName }
    Snapshot 'defender-status' { Get-MpComputerStatus | Select-Object AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureLastUpdated,QuickScanEndTime,FullScanEndTime }
    Snapshot 'defender-events' {
        $events = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational';StartTime=$since.ToLocalTime()} -MaxEvents $MaxEvents)
        if ($events.Count -eq $MaxEvents) { Issue 'defender-events' 'Event limit reached; older events may be omitted.' }
        foreach ($e in $events) {
            $timeline.Add([pscustomobject]@{TimeUtc=$e.TimeCreated.ToUniversalTime().ToString('o');Source='Defender';Kind=[string]$e.Id;Detail=$e.Message})
            [pscustomobject]@{TimeUtc=$e.TimeCreated.ToUniversalTime().ToString('o');Id=$e.Id;RecordId=$e.RecordId;Message=$e.Message;Xml=$e.ToXml()}
        }
    }
    Snapshot 'processes' { Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate }
    Snapshot 'tcp' { Get-NetTCPConnection | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess }
    Snapshot 'startup' { Get-CimInstance Win32_StartupCommand | Select-Object Name,Command,Location,User }
    Snapshot 'services' { Get-CimInstance Win32_Service | Select-Object Name,State,StartMode,PathName,ProcessId }
    Snapshot 'tasks' { Get-ScheduledTask | Select-Object TaskPath,TaskName,State,Actions,Triggers }
} else { $coverage.Add([pscustomobject]@{Source='SystemSnapshots';Status='SkippedByOption';Count=0}) }
SaveJson 'files' $files.ToArray()
SaveJson 'timeline' @($timeline | Sort-Object TimeUtc)
SaveJson 'coverage' $coverage.ToArray()
SaveJson 'issues' $issues.ToArray()
$manifest = [pscustomobject]@{
    StartedUtc = $start.ToString('o')
    CompletedUtc = [DateTime]::UtcNow.ToString('o')
    SinceUtc = $since.ToString('o')
    Computer = $env:COMPUTERNAME
    TimeZone = [TimeZoneInfo]::Local.Id
    Roots = $Roots
    IncludePathPattern = $IncludePathPattern
    MaxEntries = $MaxEntries
    MaxEvents = $MaxEvents
    MaxHashMB = $MaxHashMB
    Files = $files.Count
    EntriesVisited = $visited
    Issues = $issues.Count
    HashFiles = [bool]$HashFiles
    SkipSystem = [bool]$SkipSystem
    ScriptSHA256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
}
SaveJson 'manifest' $manifest
@"
# Investigation collection

Files inventoried: $($files.Count)
Collection issues: $($issues.Count)
Started UTC: $($start.ToString('o'))

Review coverage.json and issues.json before drawing conclusions.
ReviewReasons are triage hints, not malware verdicts.
File timestamps do not prove execution, download origin, or infection order.
Live snapshots cannot establish historical activity or prove a clean system.
No sample execution, upload, deletion, or security-setting changes are performed by this script.
Reading files can trigger security software and affect access metadata.
Reports may contain private paths, command lines and network addresses.
"@ | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.md') -Encoding UTF8
Get-ChildItem -LiteralPath $out -File | ForEach-Object { Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 | Select-Object @{n='File';e={[IO.Path]::GetFileName($_.Path)}},Hash } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'report-hashes.json') -Encoding UTF8
Write-Output $out
