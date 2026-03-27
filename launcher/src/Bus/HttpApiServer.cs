using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using CF7Launcher.Guardian;

namespace CF7Launcher.Bus
{
    /// <summary>
    /// HTTP API 服务器，复刻 Local Server 的 HTTP 端点。
    /// 使用 HttpListener (localhost 不需要 ACL)。
    /// </summary>
    public class HttpApiServer : IDisposable
    {
        private HttpListener _listener;
        private Thread _thread;
        private volatile bool _running;
        private readonly int _socketPort;
        private readonly string _projectRoot;

        // Console 命令的 FIFO 队列
        private readonly Queue<ConsoleEntry> _pendingConsole;
        private readonly object _consoleLock = new object();
        private readonly XmlSocketServer _socketServer;

        private class ConsoleEntry
        {
            public ManualResetEvent Done;
            public string Result;
            public Timer TimeoutTimer;
        }

        public int Port { get; private set; }

        public HttpApiServer(int socketPort, string projectRoot, XmlSocketServer socketServer)
        {
            _socketPort = socketPort;
            _projectRoot = projectRoot;
            _socketServer = socketServer;
            _pendingConsole = new Queue<ConsoleEntry>();
        }

        public bool Start(int port)
        {
            try
            {
                _listener = new HttpListener();
                _listener.Prefixes.Add("http://localhost:" + port + "/");
                _listener.Start();
                Port = port;
                _running = true;

                _thread = new Thread(ListenLoop);
                _thread.IsBackground = true;
                _thread.Start();

                LogManager.Log("[HTTP] Listening on port " + port);
                return true;
            }
            catch (Exception ex)
            {
                LogManager.Log("[HTTP] Failed to start on port " + port + ": " + ex.Message);
                return false;
            }
        }

        private void ListenLoop()
        {
            while (_running)
            {
                try
                {
                    HttpListenerContext ctx = _listener.GetContext();
                    ThreadPool.QueueUserWorkItem(delegate { HandleRequest(ctx); });
                }
                catch (HttpListenerException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    LogManager.Log("[HTTP] Listen error: " + ex.Message);
                }
            }
        }

        private void HandleRequest(HttpListenerContext ctx)
        {
            string path = ctx.Request.Url.AbsolutePath;
            string method = ctx.Request.HttpMethod;

            try
            {
                // CORS headers
                ctx.Response.Headers.Add("Access-Control-Allow-Origin", "*");
                ctx.Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
                ctx.Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type");

                if (method == "OPTIONS")
                {
                    ctx.Response.StatusCode = 200;
                    ctx.Response.Close();
                    return;
                }

                if (path == "/testConnection" && method == "POST")
                    HandleTestConnection(ctx);
                else if (path == "/getSocketPort" && method == "GET")
                    HandleGetSocketPort(ctx);
                else if (path == "/logBatch" && method == "POST")
                    HandleLogBatch(ctx);
                else if (path == "/console" && method == "POST")
                    HandleConsole(ctx);
                else if (path == "/crossdomain.xml")
                    HandleCrossDomain(ctx);
                else
                {
                    ctx.Response.StatusCode = 404;
                    WriteResponse(ctx, "Not Found");
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[HTTP] Request error: " + ex.Message);
                try
                {
                    ctx.Response.StatusCode = 500;
                    WriteResponse(ctx, "Internal Server Error");
                }
                catch { }
            }
        }

        private void HandleTestConnection(HttpListenerContext ctx)
        {
            ctx.Response.ContentType = "application/x-www-form-urlencoded";
            WriteResponse(ctx, "status=success");
        }

        private void HandleGetSocketPort(HttpListenerContext ctx)
        {
            if (_socketPort <= 0)
            {
                ctx.Response.StatusCode = 503;
                ctx.Response.ContentType = "application/x-www-form-urlencoded";
                WriteResponse(ctx, "error=socket_server_unavailable");
                return;
            }
            ctx.Response.ContentType = "application/x-www-form-urlencoded";
            WriteResponse(ctx, "socketPort=" + _socketPort);
        }

        private void HandleLogBatch(HttpListenerContext ctx)
        {
            string body = ReadBody(ctx);
            // LogManager 走 BeginInvoke 异步写 TextBox，不阻塞 HTTP 线程
            string decoded = Uri.UnescapeDataString(body);
            LogManager.Log("[LogBatch] " + decoded);
            WriteResponse(ctx, "OK");
        }

        private void HandleConsole(HttpListenerContext ctx)
        {
            string body = ReadBody(ctx);
            string command = "";

            // 兼容 JSON 和 form-encoded 两种格式
            // JSON: {"command": "..."}
            // Form: command=...  或  command=...&other=...
            // Query string: /console?command=...
            string queryCommand = ctx.Request.QueryString["command"];
            if (queryCommand != null)
            {
                command = queryCommand;
            }
            else
            {
                string trimmed = body.Trim();
                if (trimmed.StartsWith("{"))
                {
                    // JSON 格式
                    try
                    {
                        Newtonsoft.Json.Linq.JObject obj = Newtonsoft.Json.Linq.JObject.Parse(trimmed);
                        command = obj.Value<string>("command") ?? "";
                    }
                    catch
                    {
                        command = trimmed;
                    }
                }
                else
                {
                    // form-encoded 格式: command=xxx&...
                    command = ParseFormValue(trimmed, "command") ?? trimmed;
                }
            }

            // 编码非 ASCII 为 %uXXXX
            string safeCommand = EscapeForAS2(command);

            // 推送到 AS2
            string msg = "{\"task\":\"console\",\"command\":\"" + EscapeJsonString(safeCommand) + "\"}";
            _socketServer.PushToClient(msg);

            // FIFO 等待结果
            ConsoleEntry entry = new ConsoleEntry();
            entry.Done = new ManualResetEvent(false);
            entry.Result = null;

            // 5 秒超时
            entry.TimeoutTimer = new Timer(delegate
            {
                entry.Result = "{\"success\":false,\"error\":\"Console command timed out\"}";
                entry.Done.Set();
            }, null, 5000, Timeout.Infinite);

            lock (_consoleLock)
            {
                _pendingConsole.Enqueue(entry);
            }

            // 等待 AS2 返回或超时
            entry.Done.WaitOne(6000);
            entry.TimeoutTimer.Dispose();

            ctx.Response.ContentType = "application/json";
            WriteResponse(ctx, entry.Result ?? "{\"success\":false,\"error\":\"No response\"}");
        }

        /// <summary>
        /// 由 MessageRouter 的 OnConsoleResult 事件调用。
        /// 出队最老的 pending console 请求，透传完整 JSON。
        /// </summary>
        public void ResolveConsoleResult(string fullJson)
        {
            lock (_consoleLock)
            {
                if (_pendingConsole.Count > 0)
                {
                    ConsoleEntry entry = _pendingConsole.Dequeue();
                    entry.Result = fullJson;
                    entry.Done.Set();
                }
            }
        }

        private void HandleCrossDomain(HttpListenerContext ctx)
        {
            ctx.Response.ContentType = "text/xml";
            WriteResponse(ctx,
                "<cross-domain-policy><allow-access-from domain=\"*\" /></cross-domain-policy>");
        }

        /// <summary>
        /// 非 ASCII → %uXXXX (AS2 unescape 兼容)
        /// </summary>
        public static string EscapeForAS2(string str)
        {
            if (str == null) return "";
            StringBuilder sb = new StringBuilder();
            foreach (char c in str)
            {
                if (c > 0x7F)
                    sb.Append("%u" + ((int)c).ToString("X4"));
                else
                    sb.Append(c);
            }
            return sb.ToString();
        }

        /// <summary>
        /// 从 form-encoded body 中提取指定 key 的值（兼容旧 curl -d "command=xxx" 调用）。
        /// </summary>
        private static string ParseFormValue(string body, string key)
        {
            if (string.IsNullOrEmpty(body)) return null;
            string prefix = key + "=";
            string[] pairs = body.Split('&');
            foreach (string pair in pairs)
            {
                if (pair.StartsWith(prefix))
                {
                    return Uri.UnescapeDataString(pair.Substring(prefix.Length));
                }
            }
            return null;
        }

        private static string EscapeJsonString(string s)
        {
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        private static string ReadBody(HttpListenerContext ctx)
        {
            using (StreamReader reader = new StreamReader(ctx.Request.InputStream, Encoding.UTF8))
            {
                return reader.ReadToEnd();
            }
        }

        private static void WriteResponse(HttpListenerContext ctx, string body)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(body);
            ctx.Response.ContentLength64 = bytes.Length;
            ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
            ctx.Response.Close();
        }

        public void Dispose()
        {
            _running = false;
            if (_listener != null)
            {
                try { _listener.Stop(); } catch { }
                try { _listener.Close(); } catch { }
                _listener = null;
            }
            LogManager.Log("[HTTP] Stopped");
        }
    }
}
