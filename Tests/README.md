# 腳本驗證

從專案根目錄，以獨立 PowerShell 程序執行：

```powershell
powershell -NoProfile -File .\Tests\Test-Scripts.ps1
pwsh -NoProfile -File .\Tests\Test-Scripts.ps1
```

不需要額外測試套件。測試會在 `TestOutput/scripts-<隨機碼>` 建立測試檔案與報告，保留供檢查。

涵蓋 Get-Help 參數／範例、近期檔案與個案線索篩選、SHA-256、無效正規表示式、WhatIf 無副作用、端點與程序核對、確認期間程序或連線被替換、API 失敗及操作結果。SQLite 壓縮測試使用臨時資料庫，涵蓋 CheckOnly、WhatIf、程序檢查、筆數驗證、實際替換與完整性檢查。

TCP 與程序查詢使用替身，原生斷線方法也以只有計數器的類別替換，不會中斷真實連線。這些測試不代表已完成提升權限後的實際斷線端到端測試。

本機驗證：PowerShell 7 完整測試通過；Windows PowerShell 5.1 已驗證語法、Get-Help 中文內容與原生 helper 編譯，但完整腳本被該環境的執行原則阻擋。測試流程不會自行修改執行原則。
