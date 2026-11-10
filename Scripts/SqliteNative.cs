using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace ProcessFix.Sqlite
{
    /// <summary>以 Windows 內建的 winsqlite3.dll 存取 SQLite 資料庫。</summary>
    /// <remarks>
    /// 只包裝本工具需要的呼叫：開檔、執行、查詢與版本。每個連線都會關閉，
    /// 每個 prepared statement 都會 finalize；錯誤訊息取自 sqlite3_errmsg。
    /// 不支援加密資料庫；winsqlite3.dll 需存在（Windows 10 以後內建）。
    /// </remarks>
    public static class SqliteNative
    {
        private const string Library = "winsqlite3.dll";
        private const int SqliteOk = 0;
        private const int SqliteRow = 100;
        private const int SqliteDone = 101;
        private const int OpenReadWrite = 2;
        private const int OpenCreate = 4;
        private const int BusyTimeoutMs = 10000;

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr sqlite3_libversion();

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_libversion_number();

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_open_v2(byte[] filename, out IntPtr database, int flags, IntPtr vfs);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_close_v2(IntPtr database);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_busy_timeout(IntPtr database, int milliseconds);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr sqlite3_errmsg(IntPtr database);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_exec(IntPtr database, byte[] sql, IntPtr callback, IntPtr argument, out IntPtr errorMessage);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern void sqlite3_free(IntPtr pointer);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_prepare_v2(IntPtr database, byte[] sql, int byteCount, out IntPtr statement, IntPtr tail);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_step(IntPtr statement);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_column_count(IntPtr statement);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_column_type(IntPtr statement, int index);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr sqlite3_column_text(IntPtr statement, int index);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_column_bytes(IntPtr statement, int index);

        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_finalize(IntPtr statement);

        /// <summary>回傳連結的 SQLite 版本字串，例如 3.53.4。</summary>
        public static string Version()
        {
            IntPtr pointer = sqlite3_libversion();
            if (pointer == IntPtr.Zero) return "unknown";
            return Marshal.PtrToStringAnsi(pointer);
        }

        /// <summary>回傳 SQLite 的數字版本，例如 3053004。</summary>
        public static int VersionNumber()
        {
            return sqlite3_libversion_number();
        }

        /// <summary>執行一或多個以分號分隔的 SQL 敘述。</summary>
        /// <param name="path">資料庫檔案路徑。</param>
        /// <param name="sql">要執行的 SQL。</param>
        /// <exception cref="InvalidOperationException">SQLite 拒絕該敘述。</exception>
        public static void Execute(string path, string sql)
        {
            IntPtr database = Open(path, true);
            IntPtr error = IntPtr.Zero;
            try
            {
                int result = sqlite3_exec(database, Utf8(sql), IntPtr.Zero, IntPtr.Zero, out error);
                if (result != SqliteOk)
                {
                    string message = error == IntPtr.Zero ? Error(database) : Marshal.PtrToStringAnsi(error);
                    throw new InvalidOperationException(message);
                }
            }
            finally
            {
                if (error != IntPtr.Zero) sqlite3_free(error);
                sqlite3_close_v2(database);
            }
        }

        /// <summary>執行單一查詢，並把每一列以文字欄位回傳。</summary>
        /// <param name="path">資料庫檔案路徑。</param>
        /// <param name="sql">只含一個敘述的查詢。</param>
        /// <returns>列集合；NULL 欄位以 null 表示。</returns>
        /// <exception cref="InvalidOperationException">SQLite 拒絕該查詢。</exception>
        public static string[][] Query(string path, string sql)
        {
            IntPtr database = Open(path, false);
            IntPtr statement = IntPtr.Zero;
            try
            {
                int result = sqlite3_prepare_v2(database, Utf8(sql), -1, out statement, IntPtr.Zero);
                if (result != SqliteOk) throw new InvalidOperationException(Error(database));
                if (statement == IntPtr.Zero) return new string[0][];

                var rows = new List<string[]>();
                while (true)
                {
                    result = sqlite3_step(statement);
                    if (result == SqliteDone) break;
                    if (result != SqliteRow) throw new InvalidOperationException(Error(database));
                    int columns = sqlite3_column_count(statement);
                    var row = new string[columns];
                    for (int i = 0; i < columns; i++)
                    {
                        // SQLITE_NULL 保留為 null，讓呼叫端能區分 NULL 與空字串。
                        if (sqlite3_column_type(statement, i) == 5) continue;
                        row[i] = Text(statement, i);
                    }
                    rows.Add(row);
                }
                return rows.ToArray();
            }
            finally
            {
                if (statement != IntPtr.Zero) sqlite3_finalize(statement);
                sqlite3_close_v2(database);
            }
        }

        /// <summary>開啟連線；create 為 true 時允許建立新檔案。</summary>
        private static IntPtr Open(string path, bool create)
        {
            IntPtr database;
            int flags = create ? (OpenReadWrite | OpenCreate) : OpenReadWrite;
            int result = sqlite3_open_v2(Utf8(path), out database, flags, IntPtr.Zero);
            if (result != SqliteOk)
            {
                string message = database == IntPtr.Zero
                    ? "sqlite3_open_v2 failed with code " + result
                    : Error(database);
                if (database != IntPtr.Zero) sqlite3_close_v2(database);
                throw new InvalidOperationException(message);
            }
            sqlite3_busy_timeout(database, BusyTimeoutMs);
            return database;
        }

        private static byte[] Utf8(string value)
        {
            return Encoding.UTF8.GetBytes(value + "\0");
        }

        private static string Error(IntPtr database)
        {
            return Marshal.PtrToStringAnsi(sqlite3_errmsg(database));
        }

        private static string Text(IntPtr statement, int index)
        {
            IntPtr pointer = sqlite3_column_text(statement, index);
            if (pointer == IntPtr.Zero) return null;
            int length = sqlite3_column_bytes(statement, index);
            byte[] buffer = new byte[length];
            Marshal.Copy(pointer, buffer, 0, length);
            return Encoding.UTF8.GetString(buffer);
        }
    }
}
