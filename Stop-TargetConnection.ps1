#requires -Version 5.1

<#
.SYNOPSIS
核對程序與端點後，關閉一條明確指定的 IPv4 TCP 連線。
.DESCRIPTION
所有目標欄位皆必填，僅接受 Established 連線；不終止程序、不新增防火牆規則。
預設要求確認。WhatIf 僅查詢與預覽，不載入原生 helper、不寫報告、不送斷線要求。
確認後重新核對程序啟動時間、名稱、PID、端點與連線建立時間，避免使用過期快照。
.PARAMETER LocalAddress
精確的本機 IPv4 位址，不接受 IPv6 或主機名稱。
.PARAMETER LocalPort
精確的本機埠號，範圍 1–65535。
.PARAMETER RemoteAddress
精確的遠端 IPv4 位址，不接受 IPv6 或主機名稱。
.PARAMETER RemotePort
精確的遠端埠號，範圍 1–65535。
.PARAMETER TargetProcessId
擁有該連線的 PID；不以 PID 單獨選擇目標。
.PARAMETER ExpectedProcessName
預期的程序名稱，須與 Get-Process 的 ProcessName 完全相同（不分大小寫，無 .exe）。
.PARAMETER OutputRoot
操作紀錄目錄，預設腳本旁的 Reports。僅在同意實際操作後寫入獨立 JSON 檔。
.EXAMPLE
Get-Help .\Stop-TargetConnection.ps1 -Full
查看說明，不查詢或中斷連線。
.EXAMPLE
.\Stop-TargetConnection.ps1 -LocalAddress 192.0.2.10 -LocalPort 50000 -RemoteAddress 198.51.100.20 -RemotePort 443 -TargetProcessId 1234 -ExpectedProcessName msedge -WhatIf
以文件範例位址預覽；使用時須先替換為 Get-NetTCPConnection 查到的實際值。
.EXAMPLE
.\Stop-TargetConnection.ps1 -LocalAddress 192.0.2.10 -LocalPort 50000 -RemoteAddress 198.51.100.20 -RemotePort 443 -TargetProcessId 1234 -ExpectedProcessName msedge -Confirm
確認目標後才送出斷線要求；實際操作通常需要系統管理員 PowerShell。
.INPUTS
無。不接受管線輸入。
.OUTPUTS
PSCustomObject。含 Status、端點、TargetProcessId、Win32Result、ReportPath。
NotFound 表示沒有符合連線；Skipped 表示 WhatIf 或取消；Closed 表示 API 成功且
後續未見同一 Established 連線；StillEstablished 表示仍存在。失敗會拋出錯誤。
.NOTES
Windows PowerShell 5.1 / PowerShell 7；需要 Get-NetTCPConnection 與 Windows IP Helper。
SetTcpEntry 不接受 PID，最後一次核對與 API 呼叫間仍有無法完全消除的競態。
程式可能自動重連，本工具不提供持續封鎖。查詢或身分核對失敗時不送斷線要求。
若 API 執行後寫入報告失敗，不能據此推論斷線未發生，應重新查詢連線。
.LINK
Docs/Connections.md
.LINK
https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-settcpentry
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork })]
    [Net.IPAddress]$LocalAddress,

    [Parameter(Mandatory = $true)][ValidateRange(1,65535)][int]$LocalPort,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork })]
    [Net.IPAddress]$RemoteAddress,

    [Parameter(Mandatory = $true)][ValidateRange(1,65535)][int]$RemotePort,
    [Parameter(Mandatory = $true)][ValidateRange(1,2147483647)][int]$TargetProcessId,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ExpectedProcessName,
    [ValidateNotNullOrEmpty()][string]$OutputRoot = (Join-Path $PSScriptRoot 'Reports')
)

$ErrorActionPreference = 'Stop'
$localText = $LocalAddress.ToString()
$remoteText = $RemoteAddress.ToString()

function Get-ExactConnection {
    # 先取得表格再篩選，區分「無符合資料」與 CIM 查詢失敗。
    @(Get-NetTCPConnection -ErrorAction Stop | Where-Object {
        $_.State -eq 'Established' -and
        $_.LocalAddress -eq $localText -and $_.LocalPort -eq $LocalPort -and
        $_.RemoteAddress -eq $remoteText -and $_.RemotePort -eq $RemotePort -and
        $_.OwningProcess -eq $TargetProcessId
    })
}

function Get-ExpectedProcess {
    $owner = Get-Process -Id $TargetProcessId -ErrorAction Stop
    if ($owner.ProcessName -ne $ExpectedProcessName) {
        throw 'Process name does not match; no connection closed.'
    }
    if ($null -eq $owner.StartTime) {
        throw 'Cannot verify process start time; no connection closed.'
    }
    return $owner
}

$record = [pscustomobject]@{
    TimeUtc = [DateTime]::UtcNow.ToString('o')
    Status = 'NotFound'
    LocalAddress = $localText
    LocalPort = $LocalPort
    RemoteAddress = $remoteText
    RemotePort = $RemotePort
    TargetProcessId = $TargetProcessId
    ExpectedProcessName = $ExpectedProcessName
    ProcessStartedUtc = $null
    ConnectionCreated = $null
    Win32Result = $null
    Error = $null
    ReportPath = $null
}

$candidates = @(Get-ExactConnection)
if ($candidates.Count -eq 0) { return $record }
if ($candidates.Count -ne 1) { throw 'Target is not unique; no connection closed.' }
$initialConnection = $candidates[0]
if ($null -eq $initialConnection.CreationTime) {
    throw 'Cannot verify connection creation time; no connection closed.'
}
$owner = Get-ExpectedProcess
$started = $owner.StartTime.ToUniversalTime()
$record.ProcessStartedUtc = $started.ToString('o')
$record.ConnectionCreated = $initialConnection.CreationTime
$target = '{0}:{1} -> {2}:{3} (PID {4}, {5})' -f $localText, $LocalPort, $remoteText, $RemotePort, $TargetProcessId, $ExpectedProcessName

if (-not $PSCmdlet.ShouldProcess($target, 'Close this IPv4 TCP connection')) {
    $record.Status = 'Skipped'
    return $record
}

# 完成確認後才載入原生方法及建立紀錄，確保 WhatIf 沒有這些副作用。
if (-not ('ProcessFix.Network.TcpNative' -as [type])) {
    $nativeSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Scripts\TcpNative.cs') -Raw -Encoding UTF8
    Add-Type -TypeDefinition $nativeSource
}
$null = New-Item -ItemType Directory -Path $OutputRoot -Force
$reportName = 'connection-stop-{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'), [guid]::NewGuid().ToString('N')
$record.ReportPath = Join-Path $OutputRoot $reportName
$record.Status = 'Prepared'
$record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $record.ReportPath -Encoding UTF8

try {
    # 先核對紀錄、再呼叫 API；使用者確認期間連線與 PID 都可能已被重用。
    $current = @(Get-ExactConnection)
    $currentOwner = Get-ExpectedProcess
    if ($current.Count -ne 1 -or
        $current[0].CreationTime -ne $initialConnection.CreationTime -or
        $currentOwner.StartTime.ToUniversalTime() -ne $started) {
        throw 'Connection or process changed during confirmation; no connection closed.'
    }

    $record.Win32Result = [ProcessFix.Network.TcpNative]::Close($localText, $LocalPort, $remoteText, $RemotePort)
    if ($record.Win32Result -ne 0) {
        throw "SetTcpEntry failed with Win32 code $($record.Win32Result). Actual closure requires an elevated administrator shell."
    }

    $record.Status = 'Requested'
    $remaining = @(Get-ExactConnection | Where-Object { $_.CreationTime -eq $initialConnection.CreationTime })
    $record.Status = if ($remaining.Count -eq 0) { 'Closed' } else { 'StillEstablished' }
    $record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $record.ReportPath -Encoding UTF8
    return $record
} catch {
    $record.Status = 'Failed'
    $record.Error = $_.Exception.Message
    try {
        $record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $record.ReportPath -Encoding UTF8
    } catch {
        Write-Warning "Unable to update operation report: $($_.Exception.Message)"
    }
    throw
}
