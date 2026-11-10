# 開發歷史紀錄流程

## 開啟

雙擊專案根目錄的 `change_log.cmd`，開啟 Changelogkit 本機 GUI，預設為 `http://127.0.0.1:8711`。啟動視窗需保持開啟；按 Ctrl+C 停止服務。若連接埠被占用，可從終端執行 ` .\change_log.cmd serve --port 8712`。

入口呼叫 PATH 中本機已安裝的 `changelogkit`，工作目錄固定為 ProcessFix，不需要重新安裝套件。`ChangeLogTools` 僅作為原始碼與用法參考，不是啟動依賴；本次不修改該專案。入口在子程序設定 UTF-8，避免中文路徑與內容受系統編碼影響。

## 查詢與新增

在 ProcessFix 根目錄的 PowerShell 執行：

```powershell
.\change_log.cmd list
.\change_log.cmd show 2
.\change_log.cmd add "修正按鍵清單更新" --type 修復 --file KeyboardState/KeyboardWindow.cs --problem "描述重現症狀" --cause "填入已確認原因；不確定就明寫未知" --change "描述實際改動與驗證結果"
```

也可直接在 GUI 新增或編輯。資料以 UTF-8 存於 `Docs/ChangeHistory.md`，新紀錄在上方。相對文件連結以 `Docs` 為基準。

每筆記錄應包含問題、已確認原因、改動、相關檔案，以及已完成和未完成的驗證。日期使用 Asia/Taipei；若工具執行主機的日期不同，新增時明確提供 `--date YYYY.MM.DD --time HH:MM`。

`--problem`、`--cause`、`--change` 的首行會直接成為標題，結尾不要加句號或其他標點（markdownlint MD026）；詳細說明放在後續段落或 `--change-detail`。

## 與 Git 的關係

ProcessFix 已建立 Git 儲存庫。Changelogkit 紀錄與 Git 提交分開維護；啟動入口不會自動 commit、tag 或發布網站。提交訊息使用中文。EXE 與調查輸出由 `.gitignore` 排除；按鍵工具由 `KeyboardState/Build.ps1` 在本機建置。

## 驗證設定

```powershell
.\change_log.cmd list
```

執行 `.\change_log.cmd docs --check --summary` 驗證文件分類。

目前以按鍵工具初版與 Changelogkit 接入作為起始紀錄，不回推未查證的其他專案歷史。
