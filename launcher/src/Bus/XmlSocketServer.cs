using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using CF7Launcher.Guardian;

namespace CF7Launcher.Bus
{
    /// <summary>
    /// XMLSocket TCP 服务器。
    /// 协议：\0 分割的消息，单客户端。
    ///
    /// 消息分发采用双通道：
    ///   1. 快车道（前缀协议）：首字节 'F' → FrameTask.HandleRaw（每帧，绕过 JSON 解析）
    ///                         首字节 'R' → FrameTask.HandleReset（场景切换）
    ///   2. 通用路由（JSON）：其余消息 → MessageRouter.ProcessMessage（JObject.Parse）
    ///
    /// 快车道在 HandleMessage 最前端判断，零 GC 分配，不经过 MessageRouter。
    /// </summary>
    public class XmlSocketServer : IDisposable
    {
        private TcpListener _listener;
        private TcpClient _client;
        private NetworkStream _stream;
        private Thread _acceptThread;
        private volatile bool _running;
        private readonly MessageRouter _router;
        private readonly object _clientLock = new object();

        // 快车道处理器（由 Program.cs 在构造后注入）
        private CF7Launcher.Tasks.FrameTask _frameTask;
        private CF7Launcher.Guardian.INotchSink _notchOverlay;

        // 每次新连接递增，用于 ReadLoop 检测自己是否已被替换
        private int _generation;

        public int Port { get; private set; }
        public bool HasClient { get { return _client != null && _client.Connected; } }

        public XmlSocketServer(MessageRouter router)
        {
            _router = router;
        }

        /// <summary>
        /// 注入快车道处理器。必须在 FrameTask 构造完成后调用。
        /// 注入前收到的 F/R 前缀消息将静默丢弃（启动时序保护）。
        /// </summary>
        public void SetFrameHandler(CF7Launcher.Tasks.FrameTask frameTask)
        {
            _frameTask = frameTask;
        }

        public void SetNotchHandler(CF7Launcher.Guardian.INotchSink notch)
        {
            _notchOverlay = notch;
        }

        public bool Start(int port)
        {
            try
            {
                _listener = new TcpListener(IPAddress.Loopback, port);
                _listener.Start();
                Port = port;
                _running = true;

                _acceptThread = new Thread(AcceptLoop);
                _acceptThread.IsBackground = true;
                _acceptThread.Start();

                LogManager.Log("[XmlSocket] Listening on port " + port);
                return true;
            }
            catch (Exception ex)
            {
                LogManager.Log("[XmlSocket] Failed to start on port " + port + ": " + ex.Message);
                return false;
            }
        }

        private void AcceptLoop()
        {
            while (_running)
            {
                try
                {
                    TcpClient client = _listener.AcceptTcpClient();
                    client.NoDelay = true; // 禁用 Nagle：frame 消息需要低延迟
                    LogManager.Log("[XmlSocket] Client connected (NoDelay=true)");

                    int gen;
                    lock (_clientLock)
                    {
                        // 关闭旧连接
                        CloseClientLocked();

                        _generation++;
                        gen = _generation;
                        _client = client;
                        _stream = client.GetStream();
                    }

                    // 捕获本地引用，ReadLoop 只操作自己的 client/stream
                    TcpClient localClient = client;
                    NetworkStream localStream = _stream;

                    Thread readThread = new Thread(delegate()
                    {
                        ReadLoop(localClient, localStream, gen);
                    });
                    readThread.IsBackground = true;
                    readThread.Start();
                }
                catch (SocketException)
                {
                    // listener stopped
                    break;
                }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] Accept error: " + ex.Message);
                }
            }
        }

        private void ReadLoop(TcpClient localClient, NetworkStream localStream, int gen)
        {
            StringBuilder buffer = new StringBuilder();
            byte[] readBuf = new byte[8192];

            try
            {
                while (_running)
                {
                    int bytesRead = localStream.Read(readBuf, 0, readBuf.Length);
                    if (bytesRead == 0)
                        break;

                    string chunk = Encoding.UTF8.GetString(readBuf, 0, bytesRead);
                    buffer.Append(chunk);

                    // 按 \0 分割消息
                    string data = buffer.ToString();
                    int nullIdx;
                    while ((nullIdx = data.IndexOf('\0')) >= 0)
                    {
                        string message = data.Substring(0, nullIdx);
                        data = data.Substring(nullIdx + 1);

                        if (message.Length > 0)
                            HandleMessage(message);
                    }

                    buffer.Clear();
                    if (data.Length > 0)
                        buffer.Append(data);
                }
            }
            catch (IOException)
            {
                // Client disconnected
            }
            catch (Exception ex)
            {
                LogManager.Log("[XmlSocket] Read error: " + ex.Message);
            }

            LogManager.Log("[XmlSocket] Client disconnected");

            // 只有当自己仍是当前连接时才清理共享字段
            lock (_clientLock)
            {
                if (_generation == gen)
                {
                    CloseClientLocked();
                }
            }

            // 始终关闭自己的本地引用
            try { localStream.Close(); } catch { }
            try { localClient.Close(); } catch { }
        }

        private void HandleMessage(string message)
        {
            // === 快车道：前缀协议，绕过 JSON 解析 ===
            if (message.Length > 0)
            {
                char prefix = message[0];

                if (prefix == 'F')
                {
                    // Frame 快车道：F{cam}\x01{hn}\x02{fps}
                    // \x02{fps} 可选，仅在有新 FPS 采样时存在
                    if (_frameTask == null) return; // 启动时序保护：FrameTask 尚未注入
                    int sep1 = message.IndexOf('\x01', 1);
                    string cam, hn, fps;
                    if (sep1 > 1)
                    {
                        cam = message.Substring(1, sep1 - 1);
                        int sep2 = message.IndexOf('\x02', sep1 + 1);
                        if (sep2 >= 0)
                        {
                            hn = message.Substring(sep1 + 1, sep2 - sep1 - 1);
                            fps = (sep2 < message.Length - 1) ? message.Substring(sep2 + 1) : "";
                        }
                        else
                        {
                            hn = (sep1 < message.Length - 1) ? message.Substring(sep1 + 1) : "";
                            fps = "";
                        }
                    }
                    else
                    {
                        // 无 \x01 分隔符：整条（去掉 F）当作 cam，hn/fps 为空
                        cam = message.Substring(1);
                        hn = "";
                        fps = "";
                    }
                    _frameTask.HandleRaw(cam, hn, fps);
                    return;
                }

                if (prefix == 'R')
                {
                    // hn_reset 快车道
                    if (_frameTask == null) return;
                    _frameTask.HandleReset();
                    return;
                }

                if (prefix == 'S')
                {
                    // SFX 快车道：S{soundId}\x01{volume}
                    CF7Launcher.Tasks.AudioTask.HandleSfxFastLane(message);
                    return;
                }

                if (prefix == 'N')
                {
                    // Notice 快车道：N{category}|{colorHex}|{text}
                    // 例如 Nperf|ffcc00|⚡ 性能等级: [2] 26 FPS
                    if (_notchOverlay == null) return;
                    string nPayload = message.Substring(1);
                    int sep1n = nPayload.IndexOf('|');
                    if (sep1n > 0)
                    {
                        string nCategory = nPayload.Substring(0, sep1n);
                        int sep2n = nPayload.IndexOf('|', sep1n + 1);
                        if (sep2n > sep1n && sep2n < nPayload.Length - 1)
                        {
                            string hexColor = nPayload.Substring(sep1n + 1, sep2n - sep1n - 1);
                            string nText = nPayload.Substring(sep2n + 1);
                            int rgb;
                            if (int.TryParse(hexColor, System.Globalization.NumberStyles.HexNumber, null, out rgb))
                            {
                                System.Drawing.Color c = System.Drawing.Color.FromArgb(
                                    (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
                                _notchOverlay.AddNotice(nCategory, nText, c);
                            }
                        }
                    }
                    return;
                }

                if (prefix == 'W')
                {
                    // Wave timer 快车道：W{wave}|{total}|{mmss}|{state} 或 W隐藏
                    if (_notchOverlay == null) return;
                    string payload = message.Substring(1);
                    if (payload == "\u9690\u85CF") // "隐藏"
                    {
                        _notchOverlay.ClearStatusItem("wave_timer");
                    }
                    else
                    {
                        // wave|total|mmss|state
                        string[] parts = payload.Split('|');
                        if (parts.Length >= 4)
                        {
                            string wave = parts[0];
                            string total = parts[1];
                            string timer = parts[2];   // "01:23" or ""
                            string state = parts[3];   // "计时" or "波次"

                            string text;
                            System.Drawing.Color accent;
                            if (state == "\u8BA1\u65F6") // 计时
                            {
                                // ⚔ 波次 3/10 · 剩余 01:23
                                text = "\u2694 \u6CE2\u6B21 " + wave + "/" + total + " \u00B7 \u5269\u4F59 " + timer;
                                accent = System.Drawing.Color.FromArgb(255, 200, 80);
                            }
                            else
                            {
                                // ⚔ 波次 3/10 · 歼灭模式
                                text = "\u2694 \u6CE2\u6B21 " + wave + "/" + total + " \u00B7 \u6B7C\u706D\u6A21\u5F0F";
                                accent = System.Drawing.Color.FromArgb(100, 200, 255);
                            }
                            _notchOverlay.SetStatusItem("wave_timer", text, "", accent);
                        }
                    }
                    return;
                }
            }

            // === 通用路由：JSON 消息 ===

            // Flash 策略请求
            if (FlashPolicyHandler.IsPolicyRequest(message))
            {
                Send(FlashPolicyHandler.GetPolicyResponse());
                return;
            }

            // 路由到 MessageRouter
            string response = _router.ProcessMessage(message, delegate(string asyncResp)
            {
                // 异步响应回调
                if (asyncResp != null)
                    Send(asyncResp + "\0");
            });

            if (response != null)
                Send(response + "\0");
        }

        public void Send(string data)
        {
            lock (_clientLock)
            {
                if (_stream == null || _client == null || !_client.Connected)
                    return;

                try
                {
                    byte[] bytes = Encoding.UTF8.GetBytes(data);
                    _stream.Write(bytes, 0, bytes.Length);
                    _stream.Flush();
                }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] Send error: " + ex.Message);
                }
            }
        }

        /// <summary>
        /// 向 AS2 推送消息（用于 console 命令）。
        /// </summary>
        public void PushToClient(string json)
        {
            Send(json + "\0");
        }

        /// <summary>
        /// 必须在 _clientLock 内调用。
        /// </summary>
        private void CloseClientLocked()
        {
            if (_stream != null)
            {
                try { _stream.Close(); } catch { }
                _stream = null;
            }
            if (_client != null)
            {
                try { _client.Close(); } catch { }
                _client = null;
            }
        }

        public void Dispose()
        {
            _running = false;
            if (_listener != null)
            {
                try { _listener.Stop(); } catch { }
                _listener = null;
            }
            lock (_clientLock)
            {
                CloseClientLocked();
            }
            LogManager.Log("[XmlSocket] Stopped");
        }
    }
}
