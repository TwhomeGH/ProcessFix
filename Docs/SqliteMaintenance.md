# SQLite 資料庫壓縮

`Optimize-SqliteDatabase.ps1` 用 `VACUUM INTO` 產生壓縮副本，驗證完整性與筆數後才替換原始檔。適合處理「檔案很大，實際資料不多」的 SQLite 資料庫。

## 什麼時候用

- 刪除或改寫大量資料後，檔案大小沒有下降
- 應用程式長期使用，free page 佔比很高
- 更換或備份前想先縮小檔案
- 想先確認可回收空間，再決定要不要處理（`-CheckOnly`）

## 原理

SQLite 刪除資料時只把頁面標成 free page，不會把空間還給作業系統。要真正縮小檔案，必須重建資料庫。

| 做法 | 需求 | 風險 |
| --- | --- | --- |
| 就地 `VACUUM` | 約等於檔案大小的暫存空間 | 中途失敗可能留下不完整的資料庫 |
| `VACUUM INTO`（本工具） | 約等於**實際使用頁**大小的空間 | 先產生新檔，原檔在驗證通過前不動 |

本工具選擇後者，因此備份磁碟不需要和原始檔案一樣大，替換前也能先驗證副本。

## 空間估算

```text
used = (page_count - freelist_count) × page_size
need = used × 1.2 + 1 GiB
```

`need` 是備份目錄需要的可用空間，含 20% 餘裕。`-CheckOnly` 會直接印出這兩個數字；也可以自己查：

```sql
PRAGMA page_size;
PRAGMA page_count;
PRAGMA freelist_count;
```

## 使用

### 只量測

```powershell
.\Optimize-SqliteDatabase.ps1 -DatabasePath 'D:\app\data.db' -CheckOnly
```

不建立副本、不改檔案，也不需要獨佔鎖定，所以使用中的資料庫也能先量測；實際執行才會要求程式停止。

### 預覽

```powershell
.\Optimize-SqliteDatabase.ps1 -DatabasePath 'D:\app\data.db' -BackupDirectory 'E:\db-backup' -WhatIf
```

和實際執行相同的檢查與空間估算，但不建立目錄、不寫入任何檔案。

### 實際執行

```powershell
.\Optimize-SqliteDatabase.ps1 -DatabasePath 'D:\app\data.db' -BackupDirectory 'E:\db-backup' -VerifyTables session,message,part
```

預設要求確認（`ConfirmImpact = High`）。完成後原始檔被替換，備份目錄保留一份已驗證的壓縮副本。

### OpenCode 範例

OpenCode 的 session 資料在 `~/.local/share/opencode/opencode.db`。先停服務，壓縮後再啟動：

```powershell
opencode service stop
.\Optimize-SqliteDatabase.ps1 `
    -DatabasePath "$env:USERPROFILE\.local\share\opencode\opencode.db" `
    -BackupDirectory 'D:\opencode-backup' `
    -VerifyTables session,message,part,todo `
    -OwnerProcess opencode
opencode service start
```

## 參數

| 參數 | 必填 | 說明 |
| --- | --- | --- |
| `-DatabasePath` | 是 | 要壓縮的 SQLite 檔案 |
| `-BackupDirectory` | 實際執行時必填 | 壓縮副本與備份位置；會檢查可用空間 |
| `-VerifyTables` | 否 | 替換前後要比對筆數的資料表 |
| `-OwnerProcess` | 否 | 偵測到同名程序執行中就中止（可省略 `.exe`） |
| `-CheckOnly` | 否 | 只量測，不改檔案；此時不需要 `-BackupDirectory` |
| `-WhatIf` | 否 | 顯示計畫，不建立目錄、不寫入 |

## 安全機制

1. **獨佔鎖定**：以 `PRAGMA locking_mode = EXCLUSIVE` 嘗試取得寫入鎖，失敗即中止。
2. **程序檢查**：`-OwnerProcess` 指定的程序存在就不執行。
3. **驗證後才替換**：副本必須通過 `PRAGMA integrity_check`，且 `-VerifyTables` 的筆數與原檔一致。
4. **失敗回滾**：替換途中出錯時，把已驗證的副本放回原位。
5. **備份保留**：成功後副本留在備份目錄，是唯一回滾來源，確認無誤前不要刪除。

## 輸出

`PSCustomObject`，`Status` 為 `Checked`、`Compacted` 或 `Skipped`。

| 欄位 | 說明 |
| --- | --- |
| `DatabasePath` | 原始檔案路徑 |
| `BackupPath` | 壓縮副本路徑（`Compacted` 時） |
| `BeforeBytes` / `AfterBytes` / `ReclaimedBytes` | 替換前後大小與回收量 |
| `UsedBytes` / `FreePageBytes` | 實際使用頁與 free page |
| `PageSize` / `PageCount` / `Freelist` | SQLite 頁面統計 |
| `JournalMode` | `wal` 或 `delete` |
| `Tables` | 一般資料表數量 |
| `VerifyCounts` | 各驗證表的筆數 |
| `SqliteVersion` | 使用的 SQLite 版本 |

## 限制

- 需要 Windows 內建的 `winsqlite3.dll`（Windows 10 以後）。
- SQLite 需 3.27 以上才支援 `VACUUM INTO`。
- 不支援加密資料庫。
- 需要獨佔存取；鎖定檢查與實際替換之間仍有競態，替換期間請勿讓其他程式開啟該資料庫。
- 若資料庫沒有 free page，壓縮後檔案大小可能幾乎不變。

## 驗證

```powershell
powershell -NoProfile -File .\Tests\Test-Scripts.ps1
```

測試會建立可拋棄的 SQLite 資料庫，涵蓋 `-CheckOnly`、`-WhatIf`、程序檢查、筆數驗證、實際壓縮、`integrity_check`、遺失檔案與不存在的驗證表。
