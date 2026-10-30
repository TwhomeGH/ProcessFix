using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace ProcessFix.KeyboardState
{
    internal sealed class KeyboardWindow : Form
    {
        private readonly HeldTracker tracker = new HeldTracker();
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly Timer timer = new Timer { Interval = 100 };
        private readonly ListView keys = new ListView();
        private readonly Label status = new Label();
        private readonly Label result = new Label();
        private readonly Button releaseSelected = new Button();
        private readonly Button releaseSuspects = new Button();
        private readonly Button cancel = new Button();
        private readonly Dictionary<int, string> sent = new Dictionary<int, string>();
        private int[] pending;
        private double actionAt;
        private bool verifying;

        internal KeyboardWindow()
        {
            Text = "Keyboard State · 按鍵狀態檢查與釋放";
            Font = new Font("Microsoft JhengHei UI", 10F);
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(920, 650);
            MinimumSize = new Size(760, 600);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(245, 247, 250);

            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(20), ColumnCount = 1, RowCount = 7 };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 50));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 86));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 90));
            Controls.Add(layout);

            status.Dock = DockStyle.Fill;
            status.Font = new Font(Font.FontFamily, 16F, FontStyle.Bold);
            layout.Controls.Add(status);
            layout.Controls.Add(new Label
            {
                Dock = DockStyle.Fill,
                Text = "先放開鍵盤，觀察 3 秒。持續按住只代表疑似卡住，也可能是你正在長按。\n工具只在按下釋放按鈕後送出 key-up；不自動清理、不記錄或上傳打字內容。"
            });
            keys.Dock = DockStyle.Fill;
            keys.View = View.Details;
            keys.CheckBoxes = true;
            keys.FullRowSelect = true;
            keys.HideSelection = false;
            keys.Columns.Add("勾選 / 按鍵", 270);
            keys.Columns.Add("虛擬鍵碼", 110);
            keys.Columns.Add("按住秒數", 110);
            keys.Columns.Add("判斷", 260);
            layout.Controls.Add(keys);

            var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(0, 6, 0, 0) };
            ConfigureButton(releaseSelected, "釋放勾選按鍵", delegate { Schedule(false); });
            ConfigureButton(releaseSuspects, "釋放全部疑似卡鍵", delegate { Schedule(true); });
            ConfigureButton(cancel, "取消", delegate { CancelRelease("已取消，沒有補送釋放事件。"); });
            cancel.Enabled = false;
            actions.Controls.AddRange(new Control[] { releaseSelected, releaseSuspects, cancel });
            layout.Controls.Add(actions);

            result.Dock = DockStyle.Fill;
            result.Text = "只顯示目前按住的鍵。Caps Lock / Num Lock 的開關狀態不代表卡鍵。\n0xEA 是 OEM 自訂鍵碼，無法單憑此碼判斷是哪個裝置或程式造成。";
            layout.Controls.Add(result);
            layout.Controls.Add(new Label { Dock = DockStyle.Fill, Text = "輸入測試：試打 abc123，再按 Backspace 刪字（不會存檔）" });
            layout.Controls.Add(new TextBox { Dock = DockStyle.Fill, Multiline = true, ScrollBars = ScrollBars.Vertical });

            timer.Tick += delegate { RefreshState(); };
            Shown += delegate { RefreshState(); timer.Start(); };
            FormClosed += delegate { timer.Stop(); timer.Dispose(); };
        }

        private static void ConfigureButton(Button button, string text, EventHandler action)
        {
            button.Text = text;
            button.AutoSize = true;
            button.Padding = new Padding(8, 3, 8, 3);
            button.Click += action;
        }

        private void RefreshState()
        {
            double now = clock.Elapsed.TotalSeconds;
            if (!KeyboardNative.CanObserve)
            {
                status.Text = "目前無法讀取桌面按鍵狀態";
                status.ForeColor = Color.DarkOrange;
                tracker.Update(new int[0], now);
                keys.Items.Clear();
                if (pending != null) CancelRelease("桌面狀態不可讀，已停止操作；請回到解鎖後的桌面重試。");
                releaseSelected.Enabled = releaseSuspects.Enabled = false;
                return;
            }

            int[] down = KeyboardNative.ReadDownKeys();
            tracker.Update(down, now);
            UpdateRows(down, now);
            int suspectCount = tracker.Suspects(now).Length;
            status.Text = down.Length == 0 ? "目前未偵測到按住的鍵" :
                string.Format("{0} 個按鍵按住 · {1} 個疑似卡住", down.Length, suspectCount);
            status.ForeColor = down.Length == 0 ? Color.SeaGreen : Color.DarkOrange;
            releaseSelected.Enabled = pending == null && down.Length > 0;
            releaseSuspects.Enabled = pending == null && suspectCount > 0;
            if (pending == null) return;
            if (now < actionAt)
            {
                if (!verifying)
                    result.Text = string.Format("{0} 秒後釋放：{1}\n請放開所有按鍵；只處理這次選定且屆時仍按住的鍵。",
                        Math.Ceiling(actionAt - now), string.Join("、", pending.Select(KeyboardNative.Name)));
                return;
            }
            if (!verifying) SendReleases(now);
            else FinishVerification();
        }

        private void UpdateRows(int[] down, double now)
        {
            keys.BeginUpdate();
            foreach (ListViewItem row in keys.Items.Cast<ListViewItem>().ToArray())
                if (!down.Contains((int)row.Tag)) keys.Items.Remove(row);
            foreach (int key in down)
            {
                ListViewItem row = keys.Items.Cast<ListViewItem>().FirstOrDefault(item => (int)item.Tag == key);
                if (row == null)
                {
                    row = new ListViewItem(new[] { KeyboardNative.Name(key), string.Format("0x{0:X2}", key), "", "" }) { Tag = key };
                    keys.Items.Add(row);
                }
                double duration = tracker.Duration(key, now);
                row.SubItems[2].Text = duration.ToString("F1");
                row.SubItems[3].Text = duration >= HeldTracker.SuspectSeconds ? "疑似卡住（或正在長按）" : "目前按住";
                row.ForeColor = duration >= HeldTracker.SuspectSeconds ? Color.Firebrick : Color.Black;
            }
            keys.EndUpdate();
        }

        private void Schedule(bool allSuspects)
        {
            pending = allSuspects ? tracker.Suspects(clock.Elapsed.TotalSeconds) :
                keys.CheckedItems.Cast<ListViewItem>().Select(item => (int)item.Tag).ToArray();
            if (pending.Length == 0)
            {
                pending = null;
                result.Text = "請先勾選要釋放的按鍵，或等待疑似卡鍵出現。";
                return;
            }
            actionAt = clock.Elapsed.TotalSeconds + 3;
            verifying = false;
            cancel.Enabled = true;
            releaseSelected.Enabled = releaseSuspects.Enabled = false;
            RefreshState();
        }

        private void SendReleases(double now)
        {
            sent.Clear();
            foreach (int key in pending)
            {
                if (!KeyboardNative.IsDown(key)) sent[key] = "已自行放開，未送事件";
                else sent[key] = KeyboardNative.Release(key) == 1 ? "已送出" : "送出失敗（可能受權限或系統限制）";
            }
            verifying = true;
            cancel.Enabled = false;
            actionAt = now + 2;
            result.Text = "已完成補送，等待 2 秒確認是否仍按住。";
        }

        private void FinishVerification()
        {
            string[] details = pending.Select(key => string.Format("{0}：{1}；{2}",
                KeyboardNative.Name(key), sent[key], KeyboardNative.IsDown(key) ? "仍按住 / 再次按住" : "目前已放開")).ToArray();
            string summary = string.Join("\n", details);
            CancelRelease(details.Length <= 3 ? summary : string.Join("\n", details.Take(2)) + "\n其餘結果見詳細視窗。");
            if (details.Length > 3) MessageBox.Show(this, summary, "釋放驗證結果");
        }

        private void CancelRelease(string message)
        {
            pending = null;
            verifying = false;
            cancel.Enabled = false;
            result.Text = message;
        }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new KeyboardWindow());
        }
    }
}
