# 按鍵狀態檢查與釋放

本專案提交原始碼與建置腳本，EXE 不納入 Git，也不由 CI 發布。適用 Windows 與 .NET Framework 4.x 編譯器；目前使用的 Windows 環境已內建所需編譯器。

首次取得專案後，在專案根目錄開啟 PowerShell 執行：

```powershell
powershell -NoProfile -File .\KeyboardState\Build.ps1
.\KeyboardState\KeyboardState.exe
```

成功後會產生 `KeyboardState/KeyboardState.exe`。之後直接雙擊該檔即可；修改 C# 原始碼後需重新建置。重新建置前請先關閉正在執行的工具，以免 EXE 被占用。

1. 先放開所有按鍵，觀察 3 秒。
2. 清單顯示目前按住的按鍵、虛擬鍵碼及連續取樣時長。滿 3 秒標為「疑似卡住」，正常長按也會出現此標記。
3. 勾選後按「釋放勾選按鍵」，或按「釋放全部疑似卡鍵」。倒數 3 秒期間可以取消。
4. 只對選定且屆時仍按住的鍵補送一次 key-up，不送 key-down。2 秒後顯示驗證結果。
5. 在下方輸入框試打 `abc123`，再按 Backspace 測試刪字。

不自動釋放、不開機啟動、不修改登錄、不重新啟動輸入法、不記錄或上傳打字內容。關閉視窗即停止。輸入測試區不存檔。

## 解讀限制

- 「未偵測到按住的鍵」只代表取樣當下，不等於排除硬體、輸入法或應用程式問題。
- 每 100 ms 取樣，快速按下又放開可能不會出現在清單，不適合測試每一個短促按鍵事件。
- 無法從全域鍵碼辨識是哪把鍵盤、驅動或程式產生事件。拔掉鍵盤後殘留狀態也可能來自先前漏送的 key-up。
- `0xEA` 屬於 OEM 自訂鍵碼，不必然對應實體按鍵。
- Shift / Ctrl / Alt 只列左右鍵，不重複列彙總碼；不處理滑鼠鍵。Caps Lock / Num Lock 的鎖定燈不代表按住。
- 一般權限執行。鎖定桌面、UAC、安全桌面或權限隔離時可能無法讀取或送入事件；無法取得前景視窗時顯示不可讀並中止待處理操作。API 無法保證所有隔離情況都能辨識。
- 系統接收事件不保證目標程式已處理，也不保證硬體或軟體不會再次送出按下事件。釋放 Windows / Alt 等鍵可能觸發系統或程式的放開動作。

## 重新建置

在專案根目錄執行 `powershell -NoProfile -File .\KeyboardState\Build.ps1`。來源是 UTF-8，編譯明確使用 code page 65001。建置不會自動執行程式或更改 PowerShell 執行原則。

建置使用 `KeyboardCore.cs` 與 `KeyboardWindow.cs`；`CoreTests.cs` 是測試程式，不會包進工具 EXE。若找不到 .NET Framework 編譯器，腳本會報錯而非自動下載。

目前先維持本機建置。日後需要提供一般使用者直接下載時，再考慮以版本標籤觸發 CI 建置並將 EXE 放到 Release 附件，仍不提交二進位檔到原始碼儲存庫。

Microsoft 文件：[GetAsyncKeyState](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getasynckeystate)、[SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)、[虛擬鍵碼](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes)。
