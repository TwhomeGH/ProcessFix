# ProcessFix 調查工具

開發歷史：雙擊 `change_log.cmd` 開啟本機 Changelogkit，或直接閱讀 [變更歷史](Docs/ChangeHistory.md) 與 [紀錄流程](Docs/ChangelogWorkflow.md)。

按鍵工具採原始碼交付，EXE 不納入 Git。在專案根目錄執行：

```powershell
powershell -NoProfile -File .\KeyboardState\Build.ps1
.\KeyboardState\KeyboardState.exe
```

即可查看按鍵狀態並補送釋放事件，詳見 [使用與建置說明](KeyboardState/README.md)。目前不設 CI 自動產出或發布 EXE。

Windows PowerShell 5.1／PowerShell 7 的本機蒐證工具。針對這次 `Fiz_writer_1`、`Peesreack.he` 與 `.qnq` 線索建立檔案清單及 Defender 時間線；不根據前一段對話直接認定樣本功能。

## 使用

在此資料夾開啟 PowerShell：

```powershell
.\Collect-Investigation.ps1
```

預設查看最近 7 天建立或修改的檔案，递迴列出目前使用者 Temp、Windows Temp 和 ProgramData 下的 Fiz_writer_1。名稱符合本案線索的檔案不受日期篩選限制。可指定範圍並選擇計算 SHA-256：

```powershell
.\Collect-Investigation.ps1 -Days 30 -HashFiles
```

每次執行產生獨立 `Reports` 子目錄。預設不讀取樣本內容；`-HashFiles` 會讀取最多 64 MB 的檔案以計算雜湊，可用 `-MaxHashMB` 調整。不執行、刪除、隔離或上傳樣本，也不變更防護設定。讀取仍可能觸發防毒反應或影響存取時間，這是即時系統蒐證而非鑑識磁碟映像。

一般權限即可開始；讀不到的資料會記在 `issues.json`。若需補齊受限紀錄，可自行以系統管理員開啟 PowerShell 重跑。工具不會自動提升權限或變更執行原則。

## 輸出

- `manifest.json`：蒐集時間、時區、範圍與工具雜湊。
- `files.json`：路徑、大小、建立／修改 UTC 時間、待查原因與可選雜湊。
- `timeline.json`：檔案時間與 Defender 事件，依 UTC 排序。
- `defender-*.json`：Defender 狀態、偵測清單及事件 XML。
- `processes.json`、`tcp.json`：執行中程序與 TCP 連線快照。
- `startup.json`、`services.json`、`tasks.json`：啟動項目、服務與排程工作。
- `coverage.json`、`issues.json`：蒐集狀態、無法存取項目及上限提示。
- `report-hashes.json`：輸出檔案的 SHA-256，不包含自身；用於後續檢查檔案是否改變，不提供可信時間戳或簽章。

報告保留原始字串於 JSON，避免可疑內容作為 HTML 或試算表公式執行。報告可能含私人路徑、命令列及 IP，分享前請確認內容。

## 解讀限制

副檔名、名稱與時間接近僅是調查線索。檔案時間可能被修改，不能單獨證明執行、下載來源或感染先後。Defender 偵測清單保留其原始時間表示；統一 UTC 的事件時間線來自事件記錄。程序與連線只代表蒐集當下。找不到紀錄不代表沒有感染，也不能直接判定挖礦、竊密或遠控。

不追蹤 reparse points（連結／接合點）。預設最多檢視 100,000 個目錄項目與 10,000 筆 Defender 事件；达到上限會留下提示。檔案清單只包含符合條件的檔案，不包含空目錄或已刪除檔案。不蒐集瀏覽器密碼、Cookie 或其他憑證內容。

可用 `-Roots <路徑陣列> -SkipSystem` 僅調查指定資料夾。此選項也用於隔離的測試資料驗證。
