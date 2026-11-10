# Edge 擴充功能來源調查（2026-11-08）

**狀態**：未結案 — 無法判定回裝來源
**調查日期**：2026-11-08（Asia/Taipei）
**目標**：Adblock for Youtube 1.1.2，識別碼 `icoikfohehmhjhckkepdjbfehlpimobi`

## 結論

現有證據不能判定為 Edge bug，也不能證明當天曾重新安裝。現存安裝資料指向 2026-10-18 22:15:35。擴充功能同步已開啟，且同步資料庫含此擴充功能，因此同步還原是合理候選來源；無法從這些紀錄分辨手動安裝、其他裝置同步或舊設定還原。仍需對照使用者上次移除的時間。

## 本機觀察

- 設定檔：`%LOCALAPPDATA%\Microsoft\Edge\User Data\Default`
- Secure Preferences：`first_install_time` 與 `last_update_time` 均為 `13436806535216534`，換算台灣時間 2026-10-18 22:15:35。
- 擴充功能 `1.1.2_0` 資料夾建立時間：2026-10-18 22:15:34.927 +08:00；最後寫入 22:15:35.090。
- `blacklist_state=1`、`acknowledged_blocklist_state=1`、`disable_reasons=[256]`；與使用者看到的封鎖停用提示相符。未以執行階段檢查確認背景程序。
- `location=1`、`was_installed_by_default=false`、`was_installed_by_oem=false`；未見此目標為強制原則安裝的設定。
- `manifest.update_url=https://edge.microsoft.com/extensionwebstorebase/v1/crx`，為 Edge 更新端點；更新端點不代表安全背書，也不能證明安裝發起者。
- Preferences：`sync.extensions=true`、`sync.keep_everything_synced=true`、`sync.has_setup_completed=true`。
- `Sync Data\LevelDB\006701.ldb` 可讀取到此 ID、名稱、1.1.2 與 Edge 更新網址。僅證明存在同步紀錄，未解析出來源裝置或安裝觸發。
- 唯讀檢查 HKCU/HKLM `Software\Policies\Microsoft\Edge`：皆不存在。
- HKCU `Software\Microsoft\Edge\Extensions` 存在，但未列出子項或設定值；HKLM 對應位置與 WOW6432Node 對應位置皆不存在。
- 權限包含 `https://*/*`，內容腳本在 `<all_urls>` 載入，範圍不限 YouTube。此為權限觀察，不等於已證明竊取資料。

## 外部資料

Chrome-Stats 第三方歷史頁記載此 ID 於 2026-04-25 自 Edge 商店移除，版本為 1.1.2。此資訊不是 Microsoft 公布的下架原因，不能單獨用來判定惡意行為。

<https://chrome-stats.com/d/icoikfohehmhjhckkepdjbfehlpimobi>

## 限制與下一步

- 沒有先前移除事件、同步來源裝置紀錄或持續監控，無法證明「移除後又回來」。
- REA 靜態分析於 30 秒逾時，未據此對程式行為作出結論。部分觀察參考：`ev_25974b65f9144eb03566e920f97f1686d34bec1d40125bebd45ce96831c27660`。
- 本次沒有刪除擴充功能、停用同步或修改 Edge 設定。
- 若要排除同步回裝，可先暫停擴充功能同步、透過 Edge 移除此項，並檢查其他同步裝置；重新啟動後確認是否復現。若關閉同步仍復現，再調查外部安裝程式或背景工作。
