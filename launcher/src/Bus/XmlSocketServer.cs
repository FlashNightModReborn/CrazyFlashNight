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
    /// 协议：\0 分割的 JSON 消息，单客户端。
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

        // 每次新连接递增，用于 ReadLoop 检测自己是否已被替换
        private int _generation;

        public int Port { get; private set; }
        public bool HasClient { get { return _client != null && _client.Connected; } }

        public XmlSocketServer(MessageRouter router)
        {
            _router = router;
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
                    LogManager.Log("[XmlSocket] Client connected");

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
