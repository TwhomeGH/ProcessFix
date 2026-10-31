# 本機資訊蒐集

`Collect-Investigation.ps1` 產生供人工排查的檔案與系統快照，不進行惡意程式判定或自動修復。

```powershell
Get-Help .\Collect-Investigation.ps1 -Full
Get-Help .\Collect-Investigation.ps1 -Examples
.\Collect-Investigation.ps1 -Roots 'C:\Temp' -Days 3 -SkipSystem
.\Collect-Investigation.ps1 -Days 30 -HashFiles -MaxHashMB 16
```

預設掃描目前使用者 Temp 與 Windows Temp 中最近 7 天建立或修改的檔案；同時蒐集 Defender、程序、TCP 連線、啟動項、服務及排程工作。`-SkipSystem` 略過所有系統快照。指定 `-Roots` 只改變檔案掃描範圍，不會自動略過系統快照。

## 個案線索

不再預設掃描某個個案資料夾或比對特定名稱。若需要重現先前的個案範圍，明確提供：

```powershell
.\Collect-Investigation.ps1 -Roots @($env:TEMP, "$env:SystemRoot\Temp", "$env:ProgramData\Fiz_writer_1") -IncludePathPattern 'Fiz_writer_1|Peesreack|\.qnq$'
```

`IncludePathPattern` 是對完整路徑比對的、不分大小寫的 .NET 正規表示式。命中者即使較舊仍納入；不是排除其他近期檔案的過濾器。單次比對逾時會記入 issues，可能遺漏符合條件的舊檔案。

## 輸出

每次建立獨立 `Reports/<UTC 時間>-<隨機碼>` 目錄；可用 `-OutputRoot` 指定其他位置。

| 檔案 | 用途 |
| --- | --- |
| `manifest.json` | 執行時間、參數、上限、數量與腳本 SHA-256 |
| `files.json` | 路徑、大小、建立及修改時間、選填雜湊 |
| `timeline.json` | 檔案與 Defender 事件時間線 |
| `defender-*.json` | Defender 狀態、偵測及事件（未略過系統時） |
| `processes.json`、`tcp.json` | 程序與 TCP 快照 |
| `startup.json`、`services.json`、`tasks.json` | 啟動項、服務與排程工作 |
| `coverage.json`、`issues.json` | 涵蓋範圍、讀取失敗與限制 |
| `SUMMARY.md`、`report-hashes.json` | 摘要與報告完整性雜湊 |

## 限制與讀取行為

一般權限即可開始，無權讀取的部分會記錄缺漏。最多檢視 100000 個目錄項目（檔案與資料夾合計），Defender 事件最多 10000 筆，可用參數調整。不追蹤 reparse point、連結或接合點。

預設不讀取樣本內容；`-HashFiles` 才對不超過 `-MaxHashMB` 的檔案計算 SHA-256。腳本自身與產生的報告則固定計算雜湊。讀取可能觸發防毒掃描或影響存取中繼資料，並非離線鑑識映像。

這些報告可能包含私人路徑、命令列及網路位址。檔案時間可被修改；名稱、副檔名或時間相近都不是感染判定。即時快照也不能重建所有歷史事件或證明系統完全正常。
