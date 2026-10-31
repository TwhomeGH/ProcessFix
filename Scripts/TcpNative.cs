using System;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;

namespace ProcessFix.Network
{
    /// <summary>以 Windows IP Helper API 關閉精確指定的 IPv4 TCP 連線。</summary>
    public static class TcpNative
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct TcpRow
        {
            internal uint State, LocalAddress, LocalPort, RemoteAddress, RemotePort;
        }

        [DllImport("iphlpapi.dll")]
        private static extern uint SetTcpEntry(ref TcpRow row);

        private static uint Address(string value)
        {
            IPAddress address = IPAddress.Parse(value);
            if (address.AddressFamily != AddressFamily.InterNetwork)
                throw new ArgumentException("Only IPv4 addresses are supported.", "value");
            return BitConverter.ToUInt32(address.GetAddressBytes(), 0);
        }

        private static uint Port(int value)
        {
            if (value < 1 || value > 65535) throw new ArgumentOutOfRangeException("value");
            // MIB_TCPROW 使用 DWORD 欄位，但埠號必須以網路位元組順序填入。
            return (uint)(((value & 255) << 8) | (value >> 8));
        }

        /// <summary>送出 DELETE_TCB；呼叫前須由呼叫者確認權限、擁有者與使用者意圖。</summary>
        /// <param name="localAddress">本機 IPv4 位址。</param>
        /// <param name="localPort">本機埠號，1–65535。</param>
        /// <param name="remoteAddress">遠端 IPv4 位址。</param>
        /// <param name="remotePort">遠端埠號，1–65535。</param>
        /// <returns>原生 Win32 回傳碼，0 表示 API 成功。</returns>
        /// <exception cref="FormatException">位址格式錯誤。</exception>
        /// <exception cref="ArgumentException">位址非 IPv4 或埠號不在範圍。</exception>
        /// <remarks>需要提升權限；API 不接受 PID，仍存在檢查後連線被替換的競態。</remarks>
        public static uint Close(string localAddress, int localPort, string remoteAddress, int remotePort)
        {
            var row = new TcpRow
            {
                State = 12,
                LocalAddress = Address(localAddress),
                LocalPort = Port(localPort),
                RemoteAddress = Address(remoteAddress),
                RemotePort = Port(remotePort)
            };
            return SetTcpEntry(ref row);
        }
    }
}
