# 指定 TCP 連線處理

`Stop-TargetConnection.ps1` 僅處理一條明確指定的 Established IPv4 TCP 連線。它不終止程序、不改防火牆，程式仍可能重連。

## 先查目標與用法

```powershell
Get-Help .\Stop-TargetConnection.ps1 -Full
Get-Help .\Stop-TargetConnection.ps1 -Examples
Get-NetTCPConnection -State Established |
    Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,OwningProcess,CreationTime
Get-Process -Id 1234 | Select-Object Id,ProcessName,StartTime
```

以下為文件範例位址；執行前替換成實際查得的資料，程序名稱不帶 `.exe`：

```powershell
$target = @{
    LocalAddress = '192.0.2.10'
    LocalPort = 50000
    RemoteAddress = '198.51.100.20'
    RemotePort = 443
    TargetProcessId = 1234
    ExpectedProcessName = 'msedge'
}
.\Stop-TargetConnection.ps1 @target -WhatIf
```

`-WhatIf` 會查詢並核對目標，但不載入原生 helper、不寫報告、不送出斷線要求。沒找到精確目標會回傳 `NotFound`。

確定需要中斷時，於系統管理員 PowerShell 再核對最新目標後執行：

```powershell
.\Stop-TargetConnection.ps1 @target -Confirm
```

預設即要求確認；`-Confirm:$false` 可明確略過提示，應只用於已確認目標的自動化。腳本不自行提升權限。

## 核對與結果

- 必須提供本機／遠端 IP 與 Port、PID、預期程序名稱，拒絕 IPv6。
- 確認後重新比對連線建立時間與程序啟動時間，避免確認期間程序或連線被替換。
- 實際操作前先在 `Reports` 建立唯一的 `connection-stop-*.json`；紀錄無法建立就不送出要求。
- `Skipped`：預覽或拒絕確認。`Closed`：API 成功且後續未見原 Established 連線。`StillEstablished`：API 成功但同一連線仍在後續取樣中存在。
- API／核對／驗證錯誤會拋出；操作紀錄若已建立則嘗試更新為 `Failed`。查詢、取消或目標不存在不會產生操作紀錄。
- API 執行後若驗證或寫入報告失敗，並不表示連線沒有被中斷。請看 Win32Result 並重新查詢。

Windows `SetTcpEntry` 只處理 IPv4，實際操作需要提升的管理員權限。該 API 不接受 PID，因此核對與呼叫間仍有很短的競態，不能保證連線永不被替換。[Microsoft 文件](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-settcpentry)

原生宣告在 `Scripts/TcpNative.cs`，只於使用者同意操作後以 Add-Type 載入；不需要預先建置 EXE。
