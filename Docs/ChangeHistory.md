# ProcessFix 開發歷史

以下日期採 Asia/Taipei；這是開發里程碑紀錄，不代表已建立 Git tag 或正式發行版本。

## 2026.11.11 03:23 新增 SQLite 資料庫壓縮工具

**類型**: 新增 · **檔案**: `Optimize-SqliteDatabase.ps1`, `Scripts/SqliteNative.cs`, `Docs/SqliteMaintenance.md`, `README.md`, `Tests/Test-Scripts.ps1`, `Tests/README.md`

### 問題 - OpenCode 的 opencode.db 成長到 7.95 GiB，實際使用頁只有 2.74 GiB；檔案空間沒有還給作業系統

### 根因 - SQLite 刪除資料只把頁面標成 free page，必須重建資料庫才會縮小。先前的處理腳本依賴 Python，且固定 OpenCode 路徑與服務命令，無法重複使用

### 修改 - 新增通用 Optimize-SqliteDatabase.ps1：以 VACUUM INTO 產生副本，驗證 integrity 與指定資料表筆數後才替換，失敗會回滾

- 新增 Scripts/SqliteNative.cs，直接 P/Invoke Windows 內建 winsqlite3.dll，移除 Python 依賴。
- 補齊 Get-Help、Docs/SqliteMaintenance.md、README 工具表與測試；修正測試在 Windows PowerShell 5.1 解析 JSON 陣列的差異。

**相關文件**:

- [SQLite 資料庫壓縮](SqliteMaintenance.md)
- [測試說明](../Tests/README.md)

---

## 2026.10.31 將專案定位為 Windows 診斷工具集並整理 PowerShell 工具

**類型**: 改善 · **檔案**: `README.md`, `Collect-Investigation.ps1`, `Stop-TargetConnection.ps1`, `Scripts/TcpNative.cs`, `Tests/Test-Scripts.ps1`

### 問題 - 個案腳本缺乏可重複使用的入口與說明

原 README 側重單一調查案例；蒐集腳本預設比對個案名稱，斷線腳本則寫死端點、PID 與程序名稱，兩者缺少完整 Get-Help。

### 修改 - 明確區分資訊蒐集與狀態修改

- 主 README 改為 Windows 本機程序、連線、檔案與輸入異常排查工具集總覽，提供各工具入口與執行影響。
- 兩支腳本補齊中文 Get-Help 的用途、參數、範例、輸出與限制，以 UTF-8 BOM 支援 Windows PowerShell 5.1。
- 蒐集工具移除預設個案目錄與名稱比對，新增選填 IncludePathPattern，並將線索與上限寫入 manifest；保留舊案例的顯式參數範例。
- 斷線工具要求完整 IPv4 端點、PID 與預期程序名稱，支援 WhatIf / Confirm；確認後重新核對程序及連線建立時間，操作紀錄使用唯一檔名。
- 將原生 TCP helper 獨立為 Scripts/TcpNative.cs；未確認前不載入、不寫報告，也不呼叫斷線 API。
- PowerShell 7 離線測試通過：Get-Help、檔案篩選與雜湊、正規表示式驗證、WhatIf、目標不符、程序／連線替換、查詢與 API 失敗及回傳結果。
- Windows PowerShell 5.1 語法、中文 Get-Help 與原生 helper 編譯通過；完整腳本執行被本機執行原則阻擋，未改變執行原則。未執行真實斷線端到端測試。

**相關文件**:

- [資訊蒐集](Investigation.md)
- [指定連線處理](Connections.md)
- [測試說明](../Tests/README.md)

---

## 2026.10.30 整理原始碼提交與本機 EXE 建置流程

**類型**: 開發流程 · **檔案**: `README.md`, `KeyboardState/README.md`, `.gitignore`, `Docs/ChangelogWorkflow.md`

### 問題 - 新取得專案時不能假設已有 EXE

需要明確定義產物交付方式，避免文件連到未提交的 EXE，或每次建置都產生二進位 Git 變更。

### 修改 - 提交原始碼與建置指引，保留 EXE 在本機

- 沿用 `.gitignore` 的 `*.exe` 規則，不刪除本機產物。
- 首次使用先執行 `KeyboardState/Build.ps1`，再開啟產生的 `KeyboardState.exe`；重新建置前關閉工具。
- 暫不設定 CI 產物或 Release；日後有直接下載需求時再加入。
- 確認目前已建立 Git 儲存庫，更新開發流程說明。早期接入紀錄中的非 Git 狀態為當時情況。
- 本次提交聚焦按鍵工具、建置文件與 Changelogkit 接入，既有調查腳本與調查報告未納入。

**相關文件**: [建置說明](../KeyboardState/README.md)

---

## 2026.10.30 接入本機 Changelogkit 並建立開發紀錄入口

**類型**: 開發流程 · **檔案**: `.changelog.toml`, `change_log.cmd`, `Docs/ChangeHistory.md`, `Docs/ChangelogWorkflow.md`

### 問題 - 初版工具需要可持續維護的開發歷史

將功能、設計原因、已完成驗證與未完成驗證集中記錄，避免只留在對話中。

### 根因 - 專案尚未設定 Changelogkit

ProcessFix 目前不是 Git 儲存庫；不能把這份文字紀錄當成 Git 提交歷史。

### 修改 - 使用本機已安裝的 Changelogkit 接入

- `.changelog.toml` 指向本檔並設定文件分類，排除調查輸出與建置產物的索引。
- `change_log.cmd` 呼叫 PATH 中已安裝的 `changelogkit`，固定工作目錄為本專案；雙擊啟動本機 GUI，預設連接埠 8711。ChangeLogTools 僅作為原始碼與用法參考。
- 同一入口支援 `list`、`show`、`add` 等指令；僅在子程序啟用 UTF-8，不安裝套件或變更全域 Python 設定。
- 已驗證：安裝版 CLI 正常讀取兩筆歷史。文件索引檢查因資料夾不是 Git 儲存庫而失敗，尚未驗證完整開發索引頁；未自動建立 Git 儲存庫。

**相關文件**: [紀錄流程](ChangelogWorkflow.md)

---

## 2026.10.30 完成 KeyboardState 按鍵檢查與釋放工具初版

**類型**: 新增 · **檔案**: `KeyboardState/KeyboardCore.cs`, `KeyboardState/KeyboardWindow.cs`, `KeyboardState/Build.ps1`, `KeyboardState/CoreTests.cs`

### 問題 - 英數字與 Backspace 無法正常操作

調查曾讀到右 Ctrl、右 Windows 鍵、F3 與 OEM 鍵碼 0xEA 的持續按住狀態。後續確認拔除鍵盤後，右 Windows 鍵與 0xEA 仍保持按住。逐一補送 key-up 後，約 5 秒的 12 次取樣均未偵測到按住的鍵。

### 根因 - 已確認系統按鍵狀態殘留，事件來源尚未確定

無法單憑 GetAsyncKeyState 判斷是硬體、驅動、按鍵映射或其他軟體產生。輸入法程序顯示有回應，也不能據此完全排除輸入法問題。0xEA 屬於 OEM 自訂範圍，不代表鍵盤上必定存在對應按鍵。

### 修改 - 提供可重複使用的桌面檢查與手動釋放介面

- 每 100 ms 取樣，顯示按鍵名稱、虛擬鍵碼與連續按住秒數；滿 3 秒標為「疑似卡住」，正常長按也可能符合。
- 支援釋放勾選按鍵或全部疑似卡鍵，倒數 3 秒可取消；僅對選定且仍按住的鍵送出 key-up，2 秒後驗證。
- 提供不存檔的英數字及 Backspace 輸入測試框，不自動清理或記錄輸入歷史。
- Build.ps1 使用 Windows .NET Framework C# 編譯器，將 KeyboardCore.cs 與 KeyboardWindow.cs 編譯為 KeyboardState.exe。
- 已驗證：建置成功；核心測試涵蓋計時門檻、放開與重按、OEM 鍵碼、延伸鍵旗標、原生 INPUT 大小，以及所有事件均為 key-up。
- 已驗證：實際開啟 GUI，讀到「目前未偵測到按住的鍵」，確認按鈕與輸入框存在。
- 尚未完整驗證：透過 GUI 操作的端到端釋放流程、實體鍵盤輸入與 Backspace 測試、多 DPI 配置。
- 先前即時修復使用 keybd_event；工具實作使用 SendInput。前者的成功不能當成後者端到端流程已通過。

**相關文件**:

- [工具使用與限制](../KeyboardState/README.md)
- [建置腳本](../KeyboardState/Build.ps1)
- [核心測試](../KeyboardState/CoreTests.cs)

---
