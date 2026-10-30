using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ProcessFix.KeyboardState
{
    /// <summary>讀取全域按鍵狀態並僅補送 key-up；不記錄輸入內容。</summary>
    internal static class KeyboardNative
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct KeyboardInput
        {
            internal ushort Key, Scan;
            internal uint Flags, Time;
            internal UIntPtr Extra;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct MouseInput
        {
            internal int X, Y;
            internal uint Data, Flags, Time;
            internal UIntPtr Extra;
        }

        // 保留 MOUSEINPUT 大小，使 INPUT 在 x86 / x64 上皆符合原生佈局。
        [StructLayout(LayoutKind.Explicit)]
        internal struct InputUnion
        {
            [FieldOffset(0)] internal KeyboardInput Keyboard;
            [FieldOffset(0)] internal MouseInput Mouse;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct Input
        {
            internal uint Type;
            internal InputUnion Data;
        }

        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint count, Input[] inputs, int size);
        [DllImport("user32.dll")]
        private static extern uint MapVirtualKey(uint code, uint mapType);

        internal static bool CanObserve { get { return GetForegroundWindow() != IntPtr.Zero; } }

        internal static bool IsDown(int key)
        {
            return (GetAsyncKeyState(key) & 0x8000) != 0;
        }

        internal static bool IsKeyboardKey(int key)
        {
            // 左右修飾鍵已有各自狀態，不重複列出彙總碼；也排除滑鼠鍵。
            return key >= 8 && key <= 254 && key != 16 && key != 17 && key != 18;
        }

        internal static int[] ReadDownKeys()
        {
            return Enumerable.Range(8, 247).Where(IsKeyboardKey).Where(IsDown).ToArray();
        }

        internal static string Name(int key)
        {
            switch (key)
            {
                case 8: return "Backspace（退格）";
                case 91: return "左 Windows";
                case 92: return "右 Windows";
                case 160: return "左 Shift";
                case 161: return "右 Shift";
                case 162: return "左 Ctrl";
                case 163: return "右 Ctrl";
                case 164: return "左 Alt";
                case 165: return "右 Alt";
                case 234: return "OEM 自訂鍵（0xEA）";
            }
            if (key >= 48 && key <= 57) return ((char)key).ToString();
            if (key >= 233 && key <= 245) return "OEM 自訂鍵";
            return Enum.GetName(typeof(Keys), key) ?? "未命名虛擬鍵";
        }

        /// <summary>建立只有 KEYUP 的事件；無掃描碼的 OEM 鍵仍以虛擬鍵碼送出。</summary>
        /// <param name="key">單一鍵碼，排除滑鼠及彙總修飾鍵。</param>
        /// <param name="mappedScan">MapVirtualKey 回傳的掃描碼與延伸前綴。</param>
        /// <returns>供 SendInput 使用的鍵盤事件。</returns>
        /// <exception cref="ArgumentOutOfRangeException">不支援的鍵碼。</exception>
        internal static Input CreateRelease(int key, uint mappedScan)
        {
            if (!IsKeyboardKey(key)) throw new ArgumentOutOfRangeException("key");
            bool extended = (mappedScan & 0xFF00) == 0xE000 ||
                key == 91 || key == 92 || key == 163 || key == 165;
            return new Input
            {
                Type = 1,
                Data = new InputUnion
                {
                    Keyboard = new KeyboardInput
                    {
                        Key = (ushort)key,
                        Scan = (ushort)(mappedScan & 0xFF),
                        Flags = 2u | (extended ? 1u : 0u)
                    }
                }
            };
        }

        /// <summary>補送一次 key-up，呼叫者須重新取樣確認是否解除。</summary>
        /// <param name="key">待釋放鍵碼。</param>
        /// <returns>成功送入為 1，遭阻擋為 0。</returns>
        internal static uint Release(int key)
        {
            var input = CreateRelease(key, MapVirtualKey((uint)key, 4));
            return SendInput(1, new[] { input }, Marshal.SizeOf(typeof(Input)));
        }
    }

    /// <summary>以單調時鐘累積連續按住時長；放開即移除，不保存輸入歷史。</summary>
    internal sealed class HeldTracker
    {
        private readonly Dictionary<int, double> since = new Dictionary<int, double>();
        internal const double SuspectSeconds = 3;

        /// <summary>更新目前按住集合；放開後再按下會重新計時。</summary>
        /// <param name="down">本次取樣的按鍵。</param>
        /// <param name="now">單調時鐘秒數。</param>
        internal void Update(IEnumerable<int> down, double now)
        {
            var current = new HashSet<int>(down);
            foreach (int key in since.Keys.Where(key => !current.Contains(key)).ToArray())
                since.Remove(key);
            foreach (int key in current)
                if (!since.ContainsKey(key)) since.Add(key, now);
        }

        internal double Duration(int key, double now)
        {
            return since.ContainsKey(key) ? Math.Max(0, now - since[key]) : 0;
        }

        internal int[] Suspects(double now)
        {
            return since.Keys.Where(key => Duration(key, now) >= SuspectSeconds).OrderBy(key => key).ToArray();
        }
    }
}
