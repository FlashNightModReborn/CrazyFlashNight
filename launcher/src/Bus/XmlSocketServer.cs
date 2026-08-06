using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;

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
        private TcpListener _listener;    // IPv4 loopback (127.0.0.1)
        private TcpListener _listener6;   // IPv6 loopback (::1)，IPv6 不可用时为 null
        private TcpClient _client;
        private NetworkStream _stream;
        private Thread _acceptThread;
        private Thread _acceptThread6;
        private volatile bool _running;
        private readonly MessageRouter _router;
        private readonly IXmlSocketPeerAuthority
            _peerAuthority;
        private readonly object _clientLock = new object();
        // Total-order barrier for externally observable connection transitions.  Always acquire
        // this before _clientLock.  Ready/disconnect callbacks run without _clientLock but while
        // this barrier is held, so consumers can never observe old disconnect after new ready.
        private readonly object _acceptTransitionLock = new object();

        // 快车道处理器（由 Program.cs 在构造后注入）
        private CF7Launcher.Tasks.FrameTask _frameTask;
        private CF7Launcher.Guardian.INotchSink _notchOverlay;
        private Action<string> _uiDataHandler; // U 前缀：UI 数据透传

        // 每次新连接递增，用于 ReadLoop 检测自己是否已被替换。
        private volatile int _generation;
        private int _lastDisconnectedGeneration;
        // 业务就绪标记：policy 握手完成后的首条业务消息时触发
        private volatile bool _clientReady;

        private int _frameUiLogCount;
        private int _frameUiLastLogTick;
        private const int FRAME_UI_LOG_INTERVAL_MS = 5000;

        /// <summary>业务就绪事件：Flash policy 握手完成后、首条业务消息到达时触发。</summary>
        public event Action OnClientReady;
        public event Action<int> OnClientReadyForGeneration;

        /// <summary>客户端断连事件：每个 generation 至多一次，并先于下一代 ready。</summary>
        public event Action OnClientDisconnected;
        public event Action<int> OnClientDisconnectedForGeneration;

        // Deterministic race hook used only by Launcher.Tests. It runs after a complete frame is
        // decoded but before that frame enters the connection-transition barrier.
        internal Action<int> BeforeMessageTransitionForTests;
        // Deterministic replacement-order hooks used only by Launcher.Tests.  The first runs
        // immediately before accept enters the transition barrier; the second runs inside that
        // barrier after generation ownership advances but before disconnect publication.
        internal Action BeforeAcceptTransitionForTests;
        internal Action<int, int> AfterReplacementGenerationReservedForTests;

        public int Port { get; private set; }
        public bool HasClient { get { return _client != null && _client.Connected; } }
        public bool IsClientReady { get { return _clientReady && _client != null && _client.Connected; } }

        public XmlSocketServer(MessageRouter router)
            : this(
                router,
                DenyAllXmlSocketPeerAuthority.Instance)
        {
        }

        internal XmlSocketServer(
            MessageRouter router,
            IXmlSocketPeerAuthority peerAuthority)
        {
            _router = router
                ?? throw new ArgumentNullException(
                    nameof(router));
            _peerAuthority = peerAuthority
                ?? throw new ArgumentNullException(
                    nameof(peerAuthority));
        }

        public int CurrentGeneration { get { return _generation; } }

        /// <summary>
        /// Executes a short connection-sensitive state transition under the same total-order
        /// barrier used by accept, EOF, force-close, ready publication, and message dispatch.
        /// Callers must acquire their own state lock only inside <paramref name="action"/>; the
        /// global lock order is connection-transition -> caller state -> client lock.
        /// </summary>
        internal bool RunWithConnectionTransitionFence(Func<bool> action)
        {
            if (action == null) return false;
            lock (_acceptTransitionLock) return action();
        }

        /// <summary>
        /// Atomically captures the generation of the current business-ready client.  Pair the
        /// result with TrySendIfGen/ForceCloseCurrentClientIfGen to avoid crossing reconnects.
        /// </summary>
        public bool TryGetReadyGeneration(out int generation)
        {
            lock (_clientLock)
            {
                generation = _generation;
                return _clientReady && _client != null && _client.Connected;
            }
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
                // 双 loopback 监听：IPv4 127.0.0.1 + IPv6 ::1。
                // 历史隐患：旧实现只绑 IPAddress.Loopback(仅 IPv4)，而现代 Windows 默认把
                // "localhost" 优先解析到 ::1。实测多数 Flash/系统会回退到 127.0.0.1 故不发病
                // (真机日志 WaitingConnect->WaitingHandshake 正常)，但为兼容"只试 ::1 不回退"
                // 的环境，这里同时在两个 loopback 地址上监听。仍仅限 loopback，不绑 IPv6Any，
                // 避免把端口暴露到外部网络。
                _listener = new TcpListener(IPAddress.Loopback, port);
                _listener.Start();
                Port = port;
                _running = true;

                _acceptThread = new Thread(delegate() { AcceptLoop(_listener); });
                _acceptThread.IsBackground = true;
                _acceptThread.Start();

                // IPv6 loopback 监听（可选）：IPv6 被禁用的系统会抛异常，降级为仅 IPv4。
                try
                {
                    _listener6 = new TcpListener(IPAddress.IPv6Loopback, port);
                    _listener6.Start();
                    _acceptThread6 = new Thread(delegate() { AcceptLoop(_listener6); });
                    _acceptThread6.IsBackground = true;
                    _acceptThread6.Start();
                    LogManager.Log("[XmlSocket] Listening on port " + port + " (IPv4 127.0.0.1 + IPv6 ::1)");
                }
                catch (Exception ex6)
                {
                    _listener6 = null;
                    LogManager.Log("[XmlSocket] IPv6 loopback unavailable, IPv4-only on port " + port + " (" + ex6.Message + ")");
                }

                return true;
            }
            catch (Exception ex)
            {
                LogManager.Log("[XmlSocket] Failed to start on port " + port + ": " + ex.Message);
                return false;
            }
        }

        private void AcceptLoop(TcpListener listener)
        {
            while (_running)
            {
                try
                {
                    TcpClient client = listener.AcceptTcpClient();
                    HandleAcceptedClient(client);
                }
                catch (SocketException)
                {
                    // listener stopped
                    break;
                }
                catch (ObjectDisposedException)
                {
                    // listener disposed during shutdown
                    break;
                }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] Accept error: " + ex.Message);
                }
            }
        }

        // 单客户端模型：无论连接来自 IPv4 还是 IPv6 loopback accept 循环，
        // 都经此入口；_clientLock 内 CloseClientLocked 保证新连接替换旧连接。
        private void HandleAcceptedClient(TcpClient client)
        {
            Action beforeAcceptTransition = BeforeAcceptTransitionForTests;
            if (beforeAcceptTransition != null)
            {
                try { beforeAcceptTransition(); }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] accept transition test hook error: "
                        + ex.GetType().Name);
                }
            }

            // IPv4/IPv6 accept loops may enter concurrently. Serialize the complete replacement
            // transition while still firing callbacks outside _clientLock: old generation detach
            // must be claimed exactly once and observed before the replacement can become ready.
            lock (_acceptTransitionLock)
            {
                if (!_running)
                {
                    try { client.Close(); } catch { }
                    return;
                }
                bool authorized;
                string authorizationReason;
                try
                {
                    authorized =
                        _peerAuthority.TryAuthorize(
                            client,
                            out authorizationReason);
                }
                catch
                {
                    authorized = false;
                    authorizationReason =
                        "xml_socket_peer_authority_failed";
                }
                if (!authorized)
                {
                    LogManager.Log(
                        "[XmlSocket] Rejected unauthorized peer: "
                        + (string.IsNullOrWhiteSpace(
                                authorizationReason)
                            ? "xml_socket_peer_denied"
                            : authorizationReason));
                    PerfTrace.Mark(
                        "socket.client_rejected");
                    try { client.Close(); } catch { }
                    return;
                }
                client.NoDelay = true; // 禁用 Nagle：frame 消息需要低延迟
                LogManager.Log("[XmlSocket] Client connected (NoDelay=true)");
                PerfTrace.Mark("socket.client_connected");

                int gen;
                int oldGeneration = 0;
                Action oldDisconnected = null;
                Action<int> oldGenerationDisconnected = null;
                lock (_clientLock)
                {
                    bool hadOldClient = _client != null || _stream != null;
                    if (hadOldClient)
                    {
                        oldGeneration = _generation;
                        TryClaimDisconnectLocked(oldGeneration, out oldDisconnected,
                            out oldGenerationDisconnected);
                    }
                    // Advance ownership before the old ReadLoop can wake from Close and claim the
                    // same disconnect. No replacement is installed until callbacks finish.
                    CloseClientLocked();
                    _generation++;
                    gen = _generation;
                    _clientReady = false;
                }

                if (oldGeneration > 0)
                {
                    Action<int, int> afterReserved = AfterReplacementGenerationReservedForTests;
                    if (afterReserved != null)
                    {
                        try { afterReserved(oldGeneration, gen); }
                        catch (Exception ex)
                        {
                            LogManager.Log("[XmlSocket] generation reservation test hook error: "
                                + ex.GetType().Name);
                        }
                    }
                }

                FireDisconnected(oldDisconnected, oldGenerationDisconnected, oldGeneration,
                    "replacement");

                NetworkStream localStream = null;
                bool installed = false;
                try { localStream = client.GetStream(); }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] replacement stream failed: "
                        + ex.GetType().Name);
                }
                lock (_clientLock)
                {
                    if (_running && localStream != null && _generation == gen
                        && _client == null && _stream == null)
                    {
                        _client = client;
                        _stream = localStream;
                        installed = true;
                    }
                }
                if (!installed)
                {
                    try { if (localStream != null) localStream.Close(); } catch { }
                    try { client.Close(); } catch { }
                    return;
                }

                TcpClient localClient = client;
                Thread readThread = new Thread(delegate()
                {
                    ReadLoop(localClient, localStream, gen);
                });
                readThread.IsBackground = true;
                readThread.Start();
            }
        }

        private void ReadLoop(TcpClient localClient, NetworkStream localStream, int gen)
        {
            // 字节层缓冲：按 \0 切消息边界，再对每条完整消息整体 UTF-8 解码。
            //
            // 历史 bug：原实现对每个 read chunk 单独 Encoding.UTF8.GetString，
            // 跨 chunk 边界的多字节 UTF-8 字符（中文 3 字节）会被切断 → 替换为 U+FFFD，
            // 累积污染玩家 mydata。详见存档乱码工程 plan (prancy-weaving-treasure.md) 与
            // XmlSocketReadLoopTests.cs 的回归测试。
            //
            // 修复点不变式：
            //   - \0 (0x00) 不会出现在合法 UTF-8 多字节序列中（多字节首字节/续字节都 ≥ 0x80），
            //     所以可在字节层定位边界，无需关心字符。
            //   - 快车道前缀 (F/R/K/P/U/B/N/W/D 等) 全是 ASCII，字节切割后再整体解码不变形。
            MemoryStream byteBuffer = new MemoryStream();
            byte[] readBuf = new byte[8192];

            try
            {
                while (_running)
                {
                    int bytesRead = localStream.Read(readBuf, 0, readBuf.Length);
                    if (bytesRead == 0)
                        break;

                    int start = 0;
                    for (int i = 0; i < bytesRead; i++)
                    {
                        if (readBuf[i] != 0) continue;
                        // 命中消息边界：把 [start, i) 段拼到 byteBuffer，整体解码并分发
                        if (i > start)
                            byteBuffer.Write(readBuf, start, i - start);

                        if (byteBuffer.Length > 0)
                        {
                            string message = Encoding.UTF8.GetString(
                                byteBuffer.GetBuffer(), 0, (int)byteBuffer.Length);
                            byteBuffer.SetLength(0);
                            if (message.Length > 0)
                            {
                                Action<int> beforeTransition = BeforeMessageTransitionForTests;
                                if (beforeTransition != null)
                                {
                                    try { beforeTransition(gen); }
                                    catch (Exception ex)
                                    {
                                        LogManager.Log("[XmlSocket] message transition test hook error: "
                                            + ex.GetType().Name);
                                    }
                                }
                                HandleMessage(message, gen, localClient, localStream);
                            }
                        }
                        start = i + 1;
                    }

                    // chunk 末尾的残余字节（消息未结束）累积到 byteBuffer 等下一次 read 拼接
                    if (start < bytesRead)
                        byteBuffer.Write(readBuf, start, bytesRead - start);
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

            // 回调必须在 _clientLock 外触发，防止订阅者 handler 内调用 Send/Close
            // 重入该锁；_acceptTransitionLock 仍覆盖 claim + publish，保证跨代事件总序。
            lock (_acceptTransitionLock)
            {
                Action dcHandler = null;
                Action<int> dcGenerationHandler = null;
                lock (_clientLock)
                {
                    if (_generation == gen && ReferenceEquals(_client, localClient)
                        && ReferenceEquals(_stream, localStream))
                    {
                        CloseClientLocked();
                        TryClaimDisconnectLocked(gen, out dcHandler,
                            out dcGenerationHandler);
                    }
                }
                FireDisconnected(dcHandler, dcGenerationHandler, gen, "read_loop");
            }

            // 始终关闭自己的本地引用
            try { localStream.Close(); } catch { }
            try { localClient.Close(); } catch { }
        }

        // Phase D Step D2: connectionGen 由 ReadLoop 形参透传, 用于 async/同步响应的
        // gen-bound send (TrySendIfGen). 原连接已被 AcceptLoop 替换后, 响应自动 drop,
        // 不会串到新连接. Prewarm 的 held handshake 依赖此协议保证 socket 断线/重连
        // 时 held callback 不会把 prewarm error 发到下一条连接.
        private void HandleMessage(string message, int connectionGen,
            TcpClient connectionClient, NetworkStream connectionStream)
        {
            // A frame and every event it can claim are ordered against accept, EOF, force-close,
            // and dispose.  Holding the transition barrier through dispatch also prevents an old
            // frame that passed a generation check from mutating business state after replacement.
            lock (_acceptTransitionLock)
            {
                Action readyHandler = null;
                Action<int> readyGenerationHandler = null;
                lock (_clientLock)
                {
                    if (connectionGen != _generation
                        || !ReferenceEquals(_client, connectionClient)
                        || !ReferenceEquals(_stream, connectionStream)) return;
                    // policy request 不代表业务就绪；首条真实业务消息原子 claim 此 generation。
                    if (!_clientReady && message.Length > 0
                        && !FlashPolicyHandler.IsPolicyRequest(message))
                    {
                        _clientReady = true;
                        readyHandler = OnClientReady;
                        readyGenerationHandler = OnClientReadyForGeneration;
                    }
                }
                if (readyHandler != null || readyGenerationHandler != null)
                {
                    PerfTrace.Mark("socket.client_ready");
                    FireReady(readyHandler, readyGenerationHandler, connectionGen);
                }
                HandleCurrentMessage(message, connectionGen);
            }
        }

        private void HandleCurrentMessage(string message, int connectionGen)
        {

            // === 快车道：前缀协议，绕过 JSON 解析 ===
            if (message.Length > 0)
            {
                char prefix = message[0];

                if (prefix == 'F')
                {
                    PerfTrace.Counter("socket.fastlane.F");
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
                        PerfTrace.Counter("socket.frame_ui");
                        LogFrameUiSample(uiState);
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
                    PerfTrace.Counter("socket.fastlane.R");
                    // hn_reset 快车道
                    if (_frameTask == null) return;
                    _frameTask.HandleReset();
                    return;
                }

                if (prefix == 'S')
                {
                    PerfTrace.Counter("socket.fastlane.S");
                    // SFX 快车道：同步分发（单线程，与 ReadLoop 串行）。
                    // Flash 侧已将 S 消息调序到 F 之前发送，确保同批次内音效优先处理。
                    CF7Launcher.Tasks.AudioTask.HandleSfxFastLane(message);
                    return;
                }

                if (prefix == 'B')
                {
                    PerfTrace.Counter("socket.fastlane.B");
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
                    PerfTrace.Counter("socket.fastlane.N");
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
                    PerfTrace.Counter("socket.fastlane.W");
                    // Wave timer 快车道：W{wave}|{total}|{mmss}|{state} 或 W隐藏
                    if (_notchOverlay == null) return;
                    string payload = message.Substring(1);
                    if (payload == "隐藏")
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
                            if (state == "计时")
                            {
                                // ⚔ 波次 3/10 · 剩余 01:23 · 敌人 5
                                text = "⚔ 波次 " + wave + "/" + total + " · 剩余 " + timer;
                                accent = System.Drawing.Color.FromArgb(255, 200, 80);
                            }
                            else
                            {
                                // ⚔ 波次 3/10 · 歼灭模式
                                text = "⚔ 波次 " + wave + "/" + total + " · 歼灭模式";
                                accent = System.Drawing.Color.FromArgb(100, 200, 255);
                            }
                            if (enemies.Length > 0 && enemies != "0")
                                text += " · 残敌 " + enemies;
                            _notchOverlay.SetStatusItem("wave_timer", text, "", accent);
                        }
                    }
                    return;
                }

                if (prefix == 'U')
                {
                    PerfTrace.Counter("socket.fastlane.U");
                    // UI 数据快车道：U{type}|{payload...}
                    // 零解析，整条 payload 转发给 WebView2 层
                    if (_uiDataHandler != null)
                        _uiDataHandler(message.Substring(1));
                    return;
                }

                if (prefix == 'D')
                {
                    PerfTrace.Counter("socket.fastlane.D");
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
            // Flash 策略请求
            if (FlashPolicyHandler.IsPolicyRequest(message))
            {
                Send(FlashPolicyHandler.GetPolicyResponse());
                return;
            }

            // 路由到 MessageRouter
            // Phase D Step D2: 响应走 gen-bound TrySendIfGen, 原连接已被替换时自动 drop.
            // 捕获 ReadLoop 形参 connectionGen 进闭包, 保持 "本消息的响应只发回发起它的 connection" 语义.
            // Authority routes can carry one-time capabilities, transaction identities, and full
            // state projections. Keep those payloads out of transport logs before task validation.
            PerfTrace.Counter("socket.json");
            LogManager.Log(FormatJsonMessageLog(message));

            int respGen = connectionGen;
            string response = _router.ProcessMessage(message, delegate(string asyncResp)
            {
                if (asyncResp != null)
                    TrySendIfGen(asyncResp + "\0", respGen);
            });

            if (response != null)
                TrySendIfGen(response + "\0", respGen);
        }

        private void LogFrameUiSample(string uiState)
        {
            int count = Interlocked.Increment(ref _frameUiLogCount);
            int now = Environment.TickCount;
            int last = _frameUiLastLogTick;
            if (count <= 3 || unchecked(now - last) >= FRAME_UI_LOG_INTERVAL_MS)
            {
                _frameUiLastLogTick = now;
                LogManager.Log("[Frame:UI] sample count=" + count + " " + uiState);
            }
        }

        internal static string FormatJsonMessageLog(string message)
        {
            string redacted;
            if (AuthorityLogFormatter.TryFormatTransportEnvelope(
                    message, out redacted))
                return redacted;

            if (message.Length < 500)
                return "[XmlSocket:JSON] " + message;

            return "[XmlSocket:JSON] (len=" + message.Length + ") "
                + message.Substring(0, 120) + "...";
        }

        /// <summary>
        /// Phase D Step D2: gen-bound send. expectedGen 与当前 _generation 不匹配时 drop
        /// (原 connection 已被 AcceptLoop 替换). 返回 true 仅代表本地写入成功.
        /// </summary>
        public bool TrySendIfGen(string data, int expectedGen)
        {
            lock (_clientLock)
            {
                if (_generation != expectedGen) return false;
                if (_stream == null || _client == null || !_client.Connected) return false;
                try
                {
                    byte[] bytes = Encoding.UTF8.GetBytes(data);
                    _stream.Write(bytes, 0, bytes.Length);
                    _stream.Flush();
                    return true;
                }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] TrySendIfGen error (gen=" + expectedGen + "): " + ex.Message);
                    return false;
                }
            }
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
        /// 关流/关 client 在 _clientLock 内，Fire 回调在该锁外、代际屏障内。
        /// 调用方（GameLaunchFlow.Reset）若已订阅 OnClientDisconnected + 在等待 dcGate，
        /// 强关后 ReadLoop 退出时 handler 会被 Fire，即便当前没有处于 ReadLoop 阻塞中
        /// 也可由本方法直接 Fire 一次（两种路径对订阅者语义一致：至少通知一次）。
        /// </summary>
        public void ForceCloseCurrentClient()
        {
            lock (_acceptTransitionLock)
            {
                Action dcHandler = null;
                Action<int> dcGenerationHandler = null;
                int closedGeneration = 0;
                lock (_clientLock)
                {
                    if (_client == null && _stream == null) return;
                    closedGeneration = _generation;
                    CloseClientLocked();
                    TryClaimDisconnectLocked(closedGeneration, out dcHandler,
                        out dcGenerationHandler);
                }
                LogManager.Log("[XmlSocket] ForceCloseCurrentClient");
                FireDisconnected(dcHandler, dcGenerationHandler, closedGeneration,
                    "force_close");
            }
        }

        /// <summary>
        /// Closes the current client only when it is still the captured connection generation.
        /// A caller recovering from a failed generation-bound send must use this overload so a
        /// replacement client accepted between send failure and cleanup is never disconnected.
        /// </summary>
        public bool ForceCloseCurrentClientIfGen(int expectedGeneration)
        {
            lock (_acceptTransitionLock)
            {
                Action dcHandler = null;
                Action<int> dcGenerationHandler = null;
                lock (_clientLock)
                {
                    if (_generation != expectedGeneration
                        || (_client == null && _stream == null)) return false;
                    CloseClientLocked();
                    TryClaimDisconnectLocked(expectedGeneration, out dcHandler,
                        out dcGenerationHandler);
                }
                LogManager.Log("[XmlSocket] ForceCloseCurrentClientIfGen generation="
                    + expectedGeneration);
                FireDisconnected(dcHandler, dcGenerationHandler, expectedGeneration,
                    "force_close_generation");
                return true;
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

        /// <summary>Must be called under _clientLock. Claims one disconnect per generation.</summary>
        private bool TryClaimDisconnectLocked(int generation, out Action handler,
            out Action<int> generationHandler)
        {
            handler = null;
            generationHandler = null;
            if (generation <= 0 || generation <= _lastDisconnectedGeneration) return false;
            _lastDisconnectedGeneration = generation;
            handler = OnClientDisconnected;
            generationHandler = OnClientDisconnectedForGeneration;
            return true;
        }

        private static void FireDisconnected(Action handler, Action<int> generationHandler,
            int generation, string origin)
        {
            if (handler != null)
            {
                try { handler(); }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] disconnect handler error origin=" + origin
                        + " type=" + ex.GetType().Name);
                }
            }
            if (generationHandler != null)
            {
                try { generationHandler(generation); }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] generation disconnect handler error origin="
                        + origin + " type=" + ex.GetType().Name);
                }
            }
        }

        private static void FireReady(Action handler, Action<int> generationHandler,
            int generation)
        {
            if (handler != null)
            {
                try { handler(); }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] ready handler error type="
                        + ex.GetType().Name);
                }
            }
            if (generationHandler != null)
            {
                try { generationHandler(generation); }
                catch (Exception ex)
                {
                    LogManager.Log("[XmlSocket] generation ready handler error type="
                        + ex.GetType().Name);
                }
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
            lock (_acceptTransitionLock)
            {
                _running = false;
                if (_listener != null)
                {
                    try { _listener.Stop(); } catch { }
                    _listener = null;
                }
                if (_listener6 != null)
                {
                    try { _listener6.Stop(); } catch { }
                    _listener6 = null;
                }
                Action dcHandler = null;
                Action<int> dcGenerationHandler = null;
                int closedGeneration = 0;
                lock (_clientLock)
                {
                    if (_client != null || _stream != null)
                    {
                        closedGeneration = _generation;
                        CloseClientLocked();
                        TryClaimDisconnectLocked(closedGeneration, out dcHandler,
                            out dcGenerationHandler);
                    }
                }
                FireDisconnected(dcHandler, dcGenerationHandler, closedGeneration, "dispose");
                LogManager.Log("[XmlSocket] Stopped");
            }
        }
    }
}
