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
    /// HTTP API 服务器，提供 Guardian Launcher 的 REST 接口。
    /// 使用 HttpListener (localhost 不需要 ACL)。
    ///
    /// 端点：
    ///   POST /testConnection  — 健康检查
    ///   GET  /getSocketPort   — 返回 XMLSocket 端口号
    ///   POST /logBatch        — 批量日志上报
    ///   POST /console         — 远程控制台命令（转发到 AS2）
    ///   GET  /status          — 连接状态 + task 清单（TaskRegistry 驱动）
    ///   POST /task            — 统一 task 提交（仅 httpCallable task: toast, gomoku_eval）
    ///   POST /shutdown        — 优雅关闭 launcher（CLI 调用）
    ///   GET  /crossdomain.xml — Flash 跨域策略
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
        private MessageRouter _router;
        private Action _shutdownAction;

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

        /// <summary>
        /// 注入 MessageRouter（用于 /task 端点）。在 TaskRegistry.RegisterAll 之后调用。
        /// </summary>
        public void SetRouter(MessageRouter router)
        {
            _router = router;
        }

        /// <summary>
        /// 注入关闭回调（供 /shutdown 端点使用）。
        /// </summary>
        public void SetShutdownAction(Action action)
        {
            _shutdownAction = action;
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
                else if (path == "/status" && method == "GET")
                    HandleStatus(ctx);
                else if (path == "/task" && method == "POST")
                    HandleTask(ctx);
                else if (path == "/shutdown" && method == "POST")
                    HandleShutdown(ctx);
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
            string msg = "{\"task\":\"console\",\"command\":\"" + EscapeJsonString(safeCommand) + "\"}";

            // 先入队再发送——防止 AS2 极速回复时 ResolveConsoleResult 找不到 entry
            ConsoleEntry entry = new ConsoleEntry();
            entry.Done = new ManualResetEvent(false);
            entry.Result = null;

            entry.TimeoutTimer = new Timer(delegate
            {
                entry.Result = "{\"success\":false,\"error\":\"Console command timed out\"}";
                entry.Done.Set();
            }, null, 5000, Timeout.Infinite);

            lock (_consoleLock)
            {
                _pendingConsole.Enqueue(entry);
            }

            // 入队完成后再推送到 AS2
            _socketServer.PushToClient(msg);

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

        private void HandleShutdown(HttpListenerContext ctx)
        {
            ctx.Response.ContentType = "application/json";
            WriteResponse(ctx, "{\"ok\":true,\"message\":\"shutting down\"}");
            LogManager.Log("[HTTP] Shutdown requested via /shutdown");
            if (_shutdownAction != null)
            {
                // 延迟让 HTTP 响应发出去，再执行关闭
                ThreadPool.QueueUserWorkItem(delegate
                {
                    Thread.Sleep(200);
                    _shutdownAction();
                });
            }
        }

        private void HandleStatus(HttpListenerContext ctx)
        {
            ctx.Response.ContentType = "application/json";
            string json = TaskRegistry.ToStatusJson(
                _socketServer.HasClient, Port, _socketPort);
            WriteResponse(ctx, json);
        }

        /// <summary>
        /// POST /task — 统一 task 提交端点（仅 httpCallable task）。
        /// Body: {"task":"gomoku_eval","payload":{...},"timeout":10000}
        /// toast: fire-and-forget，立即返回 {"ok":true}
        /// gomoku_eval: 异步等待，阻塞直到回调或超时
        ///
        /// 不复用 /console 的 FIFO 队列；每个请求独立持有 ManualResetEvent，
        /// 通过 MessageRouter 的 asyncRespond 回调接收响应。
        /// </summary>
        private void HandleTask(HttpListenerContext ctx)
        {
            ctx.Response.ContentType = "application/json";

            if (_router == null)
            {
                ctx.Response.StatusCode = 503;
                WriteResponse(ctx, "{\"ok\":false,\"error\":\"router not initialized\"}");
                return;
            }

            string body = ReadBody(ctx);
            if (string.IsNullOrEmpty(body))
            {
                ctx.Response.StatusCode = 400;
                WriteResponse(ctx, "{\"ok\":false,\"error\":\"empty body\"}");
                return;
            }

            // 提取 task 名称做 httpCallable 检查
            string taskName = null;
            try
            {
                var jobj = Newtonsoft.Json.Linq.JObject.Parse(body);
                taskName = jobj.Value<string>("task");
            }
            catch
            {
                ctx.Response.StatusCode = 400;
                WriteResponse(ctx, "{\"ok\":false,\"error\":\"invalid JSON\"}");
                return;
            }

            if (string.IsNullOrEmpty(taskName))
            {
                ctx.Response.StatusCode = 400;
                WriteResponse(ctx, "{\"ok\":false,\"error\":\"missing task field\"}");
                return;
            }

            // 只允许 httpCallable task（toast, gomoku_eval, audio）
            if (taskName != "toast" && taskName != "gomoku_eval" && taskName != "audio")
            {
                ctx.Response.StatusCode = 400;
                WriteResponse(ctx,
                    "{\"ok\":false,\"error\":\"task '" + taskName + "' is not httpCallable\"}");
                return;
            }

            // 每个请求独立的异步等待机制
            // expired 标志防止 late callback 在 ManualResetEvent 释放后调 Set()
            ManualResetEvent done = new ManualResetEvent(false);
            string asyncResult = null;
            bool expired = false;

            string syncResult = _router.ProcessMessage(body, delegate(string asyncResp)
            {
                if (expired) return; // late callback：超时后到达，静默丢弃
                asyncResult = asyncResp;
                try { done.Set(); } catch { } // 防御性：event 可能已被 Close
            });

            // sync task（如 toast）：ProcessMessage 直接返回
            if (syncResult != null)
            {
                expired = true;
                done.Close();
                WriteResponse(ctx, syncResult);
                return;
            }

            // fire-and-forget task（返回 null，立即响应）
            if (taskName == "toast" || taskName == "audio")
            {
                expired = true;
                done.Close();
                WriteResponse(ctx, "{\"ok\":true}");
                return;
            }

            // async task（如 gomoku_eval）：等待回调或超时
            // TODO: 读取请求体中的 timeout 字段，当前固定 15s
            bool completed = done.WaitOne(15000);
            expired = true; // 标记过期，阻止 late callback
            done.Close();

            if (completed && asyncResult != null)
            {
                WriteResponse(ctx, asyncResult);
            }
            else
            {
                ctx.Response.StatusCode = 504;
                WriteResponse(ctx, "{\"ok\":false,\"error\":\"timeout\"}");
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
                    // application/x-www-form-urlencoded: + 代表空格，%XX 代表其他字符
                    string raw = pair.Substring(prefix.Length).Replace('+', ' ');
                    return Uri.UnescapeDataString(raw);
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
