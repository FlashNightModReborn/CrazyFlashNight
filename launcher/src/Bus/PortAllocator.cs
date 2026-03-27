using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;

namespace CF7Launcher.Bus
{
    /// <summary>
    /// 端口提取算法 — 精确复刻 ports.js 和 ServerManager.as。
    /// 硬编码种子 "1192433993"，与 AS2 侧和 Node.js 侧三方一致。
    /// </summary>
    public class PortAllocator
    {
        private static readonly string EyeOf119 = "1192433993";

        private readonly List<int> _portList;
        private readonly HashSet<int> _usedPorts;

        public PortAllocator()
        {
            _portList = ExtractPorts();
            _usedPorts = new HashSet<int>();
        }

        public List<int> PortList { get { return _portList; } }

        private static List<int> ExtractPorts()
        {
            List<int> ports = new List<int>();
            HashSet<int> seen = new HashSet<int>();

            // 提取 4 位子串
            for (int i = 0; i <= EyeOf119.Length - 4; i++)
            {
                int port = int.Parse(EyeOf119.Substring(i, 4));
                if (IsValidPort(port) && seen.Add(port))
                    ports.Add(port);
            }

            // 提取 5 位子串
            for (int j = 0; j <= EyeOf119.Length - 5; j++)
            {
                int port = int.Parse(EyeOf119.Substring(j, 5));
                if (IsValidPort(port) && seen.Add(port))
                    ports.Add(port);
            }

            // 确保 3000 在列表中
            if (seen.Add(3000))
                ports.Add(3000);

            return ports;
        }

        private static bool IsValidPort(int port)
        {
            return port >= 1024 && port <= 65535;
        }

        /// <summary>
        /// 尝试绑定端口，返回第一个可用的端口号。
        /// 跳过已被 usedPorts 标记的端口。
        /// </summary>
        public int ClaimPort()
        {
            foreach (int port in _portList)
            {
                if (_usedPorts.Contains(port))
                    continue;

                if (IsPortAvailable(port))
                {
                    _usedPorts.Add(port);
                    return port;
                }
            }
            return -1;
        }

        public void MarkUsed(int port)
        {
            _usedPorts.Add(port);
        }

        private static bool IsPortAvailable(int port)
        {
            TcpListener listener = null;
            try
            {
                listener = new TcpListener(IPAddress.Loopback, port);
                listener.Start();
                return true;
            }
            catch
            {
                return false;
            }
            finally
            {
                if (listener != null)
                    listener.Stop();
            }
        }
    }
}
