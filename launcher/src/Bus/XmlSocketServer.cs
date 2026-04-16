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
        private Action<string> _uiDataHandler; // U 前缀：UI 数据透传

        // 每次新连接递增，用于 ReadLoop 检测自己是否已被替换
        private int _generation;

        // 业务就绪标记：policy 握手完成后的首条业务消息时触发
        private volatile bool _clientReady;

        /// <summary>业务就绪事件：Flash policy 握手完成后、首条业务消息到达时触发。</summary>
        public event Action OnClientReady;

        /// <summary>客户端断连事件：仅当前 generation 的 ReadLoop 退出时触发。</summary>
        public event Action OnClientDisconnected;

        public int Port { get; private set; }
        public bool HasClient { get { return _client != null && _client.Connected; } }
        public bool IsClientReady { get { return _clientReady && _client != null && _client.Connected; } }

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

        /// <summary>注入 U 前缀处理器（UI 数据透传到 WebView2）。</summary>
        public void SetUiDataHandler(Action<string> handler)
        {
            _uiDataHandler = handler;
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
                        _clientReady = false;
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

            // Phase 1e (5a)：回调必须在锁外触发，防止订阅者 handler 内调用 Send/Close
            // 等同锁 API 造成重入/死锁（见 plan Phase 1e 锁语义约束 1）
            Action dcHandler = null;
            lock (_clientLock)
            {
                if (_generation == gen)
                {
                    CloseClientLocked();
                    dcHandler = OnClientDisconnected;  // 快照，锁外 Fire
                }
            }
            if (dcHandler != null)
            {
                try { dcHandler(); }
                catch (Exception dcEx)
                {
                    LogManager.Log("[XmlSocket] OnClientDisconnected error: " + dcEx.Message);
                }
            }

            // 始终关闭自己的本地引用
            try { localStream.Close(); } catch { }
            try { localClient.Close(); } catch { }
        }

        private void HandleMessage(string message)
        {
            // === 业务就绪信号 ===
            // policy request 不走快车道（它是 XML 文本），所以首条快车道或 JSON 消息
            // 意味着 policy 握手已完成、Flash 业务层已就绪。
            // 放在最前面确保无论走快车道还是 JSON 路由都能触发。
            if (!_clientReady && message.Length > 0 && !FlashPolicyHandler.IsPolicyRequest(message))
            {
                _clientReady = true;
                if (OnClientReady != null)
                {
                    try { OnClientReady(); }
                    catch (Exception ex) { LogManager.Log("[XmlSocket] OnClientReady error: " + ex.Message); }
                }
            }

            // === 快车道：前缀协议，绕过 JSON 解析 ===
            if (message.Length > 0)
            {
                char prefix = message[0];

                if (prefix == 'F')
                {
                    // Frame 快车道：F{cam}\x01{hn}[\x02{fps}][\x03{uiState}][\x04{inputPayload}]
                    if (_frameTask == null) return;

                    // 1) 先提取 \x04 输入数据段（始终在消息最末尾）
                    string inputPayload = null;
                    string fMsg = message;
                    int sep4 = message.IndexOf('\x04', 1);
                    if (sep4 >= 0)
                    {
                        inputPayload = (sep4 < message.Length - 1) ? message.Substring(sep4 + 1) : "";
                        fMsg = message.Substring(0, sep4);
                    }

                    // 2) 提取 \x03 UI 状态段
                    string uiState = null;
                    string body = fMsg;
                    int sep3 = fMsg.IndexOf('\x03', 1);
                    if (sep3 >= 0)
                    {
                        uiState = (sep3 < fMsg.Length - 1) ? fMsg.Substring(sep3 + 1) : "";
                        body = fMsg.Substring(0, sep3);
                    }

                    // 3) 解析 cam / hn / fps
                    int sep1 = body.IndexOf('\x01', 1);
                    string cam, hn, fps;
                    if (sep1 > 1)
                    {
                        cam = body.Substring(1, sep1 - 1);
                        int sep2 = body.IndexOf('\x02', sep1 + 1);
                        if (sep2 >= 0)
                        {
                            hn = body.Substring(sep1 + 1, sep2 - sep1 - 1);
                            fps = (sep2 < body.Length - 1) ? body.Substring(sep2 + 1) : "";
                        }
                        else
                        {
                            hn = (sep1 < body.Length - 1) ? body.Substring(sep1 + 1) : "";
                            fps = "";
                        }
                    }
                    else
                    {
                        cam = body.Substring(1);
                        hn = "";
                        fps = "";
                    }
                    _frameTask.HandleRaw(cam, hn, fps, inputPayload);
                    // UI 状态段透传到 WebView2（与帧渲染同步）
                    if (uiState != null && uiState.Length > 0)
                    {
                        LogManager.Log("[Frame:UI] " + uiState);
                        if (_uiDataHandler != null)
                            _uiDataHandler(uiState);
                        if (uiState.StartsWith("bench:"))
                        {
                            string token = uiState.Substring("bench:".Length);
                            long recvUs = BenchTrace.NowUs();
                            string kPayload = ((char)0x20).ToString() + "\x01\x02" + token;
                            long sendUs = BenchTrace.NowUs();
                            BenchTrace.LogEcho("frame_ui_k", token, recvUs, sendUs);
                            Send("K" + kPayload + "\0");
                        }
                    }
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
                    // SFX 快车道：同步分发（单线程，与 ReadLoop 串行）。
                    // Flash 侧已将 S 消息调序到 F 之前发送，确保同批次内音效优先处理。
                    CF7Launcher.Tasks.AudioTask.HandleSfxFastLane(message);
                    return;
                }

                if (prefix == 'B')
                {
                    // Benchmark fast-lane echo. Returns via existing K prefix so
                    // AS2 smoke tests can observe the ack without production code
                    // changes. Payload is mirrored into K.hints.
                    string token = (message.Length > 1) ? message.Substring(1) : "";
                    long recvUs = BenchTrace.NowUs();
                    string kPayload = ((char)0x20).ToString() + "\x01\x02" + token;
                    long sendUs = BenchTrace.NowUs();
                    BenchTrace.LogEcho("raw_b_k", token, recvUs, sendUs);
                    Send("K" + kPayload + "\0");
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
                        // wave|total|mmss|state[|enemyCount]
                        string[] parts = payload.Split('|');
                        if (parts.Length >= 4)
                        {
                            string wave = parts[0];
                            string total = parts[1];
                            string timer = parts[2];
                            string state = parts[3];
                            string enemies = (parts.Length >= 5) ? parts[4] : "";

                            string text;
                            System.Drawing.Color accent;
                            if (state == "\u8BA1\u65F6") // 计时
                            {
                                // ⚔ 波次 3/10 · 剩余 01:23 · 敌人 5
                                text = "\u2694 \u6CE2\u6B21 " + wave + "/" + total + " \u00B7 \u5269\u4F59 " + timer;
                                accent = System.Drawing.Color.FromArgb(255, 200, 80);
                            }
                            else
                            {
                                // ⚔ 波次 3/10 · 歼灭模式
                                text = "\u2694 \u6CE2\u6B21 " + wave + "/" + total + " \u00B7 \u6B7C\u706D\u6A21\u5F0F";
                                accent = System.Drawing.Color.FromArgb(100, 200, 255);
                            }
                            if (enemies.Length > 0 && enemies != "0")
                                text += " \u00B7 \u6B8B\u654C " + enemies; // · 残敌 N
                            _notchOverlay.SetStatusItem("wave_timer", text, "", accent);
                        }
                    }
                    return;
                }

                if (prefix == 'U')
                {
                    // UI 数据快车道：U{type}|{payload...}
                    // 零解析，整条 payload 转发给 WebView2 层
                    if (_uiDataHandler != null)
                        _uiDataHandler(message.Substring(1));
                    return;
                }

                if (prefix == 'D')
                {
                    // DFA 数据同步：D{moduleId}\x01{json}
                    if (_frameTask == null) return;
                    string dPayload = message.Substring(1);
                    int dSep = dPayload.IndexOf('\x01');
                    if (dSep >= 0)
                    {
                        string moduleId = dPayload.Substring(0, dSep);
                        string dataJson = (dSep < dPayload.Length - 1) ? dPayload.Substring(dSep + 1) : "";
                        LogManager.Log("[XmlSocket:D] Received DFA module=" + moduleId + " jsonLen=" + dataJson.Length);
                        _frameTask.LoadInputModule(moduleId, dataJson);
                    }
                    else
                    {
                        LogManager.Log("[XmlSocket:D] Parse error: no \\x01 separator in D message, len=" + dPayload.Length);
                    }
                    return;
                }
            }

            // === 通用路由：JSON 消息 ===
            if (message.Length < 500)
                LogManager.Log("[XmlSocket:JSON] " + message);
            else
                LogManager.Log("[XmlSocket:JSON] (len=" + message.Length + ") " + message.Substring(0, 120) + "...");

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
        /// 带返回值的发送：Write+Flush 成功返回 true，异常或未连接返回 false。
        /// 注意：true 仅代表本地写入成功，不等于 Flash 已收到（best-effort 语义）。
        /// </summary>
        public bool TrySend(string data)
        {
            lock (_clientLock)
            {
                if (_stream == null || _client == null || !_client.Connected)
                    return false;

                try
                {
                    byte[] bytes = Encoding.UTF8.GetBytes(data);
                    _stream.Write(bytes, 0, bytes.Length);
                    _stream.Flush();
                    return true;
                }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] TrySend error: " + ex.Message);
                    return false;
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

        // ==================== Phase 1e (5b) 状态机配套 API ====================

        /// <summary>
        /// 强制关闭当前客户端：触发 ReadLoop 退出 + OnClientDisconnected。
        /// 锁语义约束 3：关流/关 client 在锁内，Fire 回调在锁外。
        /// 调用方（GameLaunchFlow.Reset）若已订阅 OnClientDisconnected + 在等待 dcGate，
        /// 强关后 ReadLoop 退出时 handler 会被 Fire，即便当前没有处于 ReadLoop 阻塞中
        /// 也可由本方法直接 Fire 一次（两种路径对订阅者语义一致：至少通知一次）。
        /// </summary>
        public void ForceCloseCurrentClient()
        {
            Action dcHandler = null;
            lock (_clientLock)
            {
                if (_client == null && _stream == null) return;
                CloseClientLocked();
                dcHandler = OnClientDisconnected;  // 快照，锁外 Fire
            }
            LogManager.Log("[XmlSocket] ForceCloseCurrentClient");
            if (dcHandler != null)
            {
                try { dcHandler(); }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] ForceCloseCurrentClient handler error: " + ex.Message);
                }
            }
        }

        /// <summary>
        /// 原子订阅断连事件：返回 false 表示当前已无连接（不应订阅 + 不应等 dcGate）。
        /// 锁内 HasClient 判断 + 订阅 一条原子 API，避免"先判有连接后订阅"之间的 race。
        /// </summary>
        public bool TrySubscribeOnClientDisconnected(Action handler)
        {
            if (handler == null) return false;
            lock (_clientLock)
            {
                if (_client == null || !_client.Connected) return false;
                OnClientDisconnected += handler;
                return true;
            }
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
