using System;
using System.Linq;
using System.Runtime.InteropServices;

namespace ProcessFix.KeyboardState
{
    /// <summary>不注入按鍵的離線測試：驗證狀態生命週期與原生事件佈局。</summary>
    internal static class CoreTests
    {
        private static void Assert(bool passed, string message)
        {
            if (!passed) throw new Exception(message);
        }

        private static void Main()
        {
            var tracker = new HeldTracker();
            tracker.Update(new[] { 92, 234 }, 10);
            Assert(tracker.Suspects(12.9).Length == 0, "Short holds must not be suspects.");
            Assert(tracker.Suspects(13).SequenceEqual(new[] { 92, 234 }), "Threshold must include both keys.");
            tracker.Update(new[] { 234 }, 14);
            Assert(tracker.Suspects(14).SequenceEqual(new[] { 234 }), "Released keys must disappear.");
            tracker.Update(new[] { 92 }, 15);
            Assert(tracker.Duration(92, 15) == 0, "Re-press must restart timing.");
            tracker.Update(new int[0], 16);
            Assert(tracker.Suspects(20).Length == 0, "Empty sample must reset state.");
            Assert(Marshal.SizeOf(typeof(KeyboardNative.Input)) == (IntPtr.Size == 8 ? 40 : 28), "Wrong INPUT size.");
            var win = KeyboardNative.CreateRelease(92, 0xE05C);
            Assert(win.Type == 1 && win.Data.Keyboard.Flags == 3 && win.Data.Keyboard.Scan == 0x5C, "Right Win requires extended key-up.");
            var oem = KeyboardNative.CreateRelease(234, 0);
            Assert(oem.Data.Keyboard.Key == 234 && oem.Data.Keyboard.Flags == 2, "Unmapped OEM key must use virtual key-up.");
            Assert(KeyboardNative.CreateRelease(8, 14).Data.Keyboard.Flags == 2, "Backspace must not be extended.");
            Assert(!KeyboardNative.IsKeyboardKey(1) && !KeyboardNative.IsKeyboardKey(17), "Exclude mouse and aggregate modifiers.");
            foreach (int key in Enumerable.Range(8, 247).Where(KeyboardNative.IsKeyboardKey))
                Assert((KeyboardNative.CreateRelease(key, 0).Data.Keyboard.Flags & 2) != 0, "Every event must be key-up.");
            Console.WriteLine("PASS: timing, release/reset, OEM key, extended flags, INPUT layout, key-up-only events.");
        }
    }
}
