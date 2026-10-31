# ProcessFix — Windows 本機診斷與異常排查工具集

整理 Windows 電腦端的程序、連線、檔案與輸入狀態檢查工具，協助先觀察異常，再依明確目標採取處理。專案從實際排查案例出發，後續逐步補充可重複使用的工具與說明。

目前不是自動修復套件或防毒軟體；各工具的用途、是否改變狀態及限制分開說明。

## 目前工具

| 工具 | 用途 | 執行影響 |
| --- | --- | --- |
| [Collect-Investigation.ps1](Collect-Investigation.ps1) | 盤點檔案，蒐集程序、TCP、Defender、啟動項、服務與排程 | 讀取資訊並寫入報告，不主動修復 |
| [Stop-TargetConnection.ps1](Stop-TargetConnection.ps1) | 核對端點與程序後關閉指定 IPv4 TCP 連線 | 確認後會中斷連線，支援 `-WhatIf` |
| [KeyboardState](KeyboardState/README.md) | 查看按住狀態、辨識疑似卡鍵並手動補送釋放 | 按下釋放按鈕才送出 key-up |

## 查看 PowerShell 用法

支援 Windows PowerShell 5.1 與 PowerShell 7。在專案根目錄執行：

```powershell
Get-Help .\Collect-Investigation.ps1 -Full
Get-Help .\Collect-Investigation.ps1 -Examples
Get-Help .\Stop-TargetConnection.ps1 -Full
Get-Help .\Stop-TargetConnection.ps1 -Examples
Get-Help .\KeyboardState\Build.ps1 -Full
```

`Get-Help` 只顯示說明，不會執行腳本。工具不會自動更改執行原則或提升權限。

## 資訊蒐集

```powershell
.\Collect-Investigation.ps1 -Roots 'C:\Temp' -Days 3 -SkipSystem
```

預設掃描使用者與 Windows Temp，並蒐集系統快照；上述範例只盤點指定目錄。每次輸出獨立報告至 `Reports`。自訂線索可用 `-IncludePathPattern`，預設不套用個案名稱。

[完整說明、輸出與限制](Docs/Investigation.md)

## 指定連線處理

先用 `Get-NetTCPConnection` 與 `Get-Process` 確認目標，再提供完整端點、PID 與程序名稱。先執行 `-WhatIf` 預覽；實際處理預設要求確認，通常需要系統管理員 PowerShell。

[查詢、預覽與操作範例](Docs/Connections.md)

## 按鍵工具建置

```powershell
powershell -NoProfile -File .\KeyboardState\Build.ps1
.\KeyboardState\KeyboardState.exe
```

採原始碼與本機建置腳本交付，EXE 不納入 Git，目前不設 CI 產物發布。修改原始碼後請先關閉工具，再重新建置。

[按鍵工具使用與建置說明](KeyboardState/README.md)

## 開發與紀錄

雙擊 `change_log.cmd` 使用本機安裝的 Changelogkit；它不是上述診斷工具的執行依賴。

- [開發歷史](Docs/ChangeHistory.md)
- [紀錄流程](Docs/ChangelogWorkflow.md)
- [腳本驗證](Tests/README.md)

Git 提交訊息使用中文。報告、測試產物、記憶體分析檔與 EXE 不納入版本控制。
