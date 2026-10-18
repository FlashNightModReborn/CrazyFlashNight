using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.RagTerminal
{
    /// <summary>SSE 事件种类（《协议》5.2）。Unknown = 合法但不认识的事件名，调用方忽略。</summary>
    internal enum DialogueInterjectEventKind
    {
        Unknown = 0,
        Status,
        Mute,
        Line,
        Plan,
        Done,
        Error
    }

    /// <summary>一条已解析的 SSE 事件。</summary>
    internal sealed class DialogueInterjectEvent
    {
        internal DialogueInterjectEventKind Kind;
        internal string EventName;
        internal JObject Data;

        internal string Text(string key)
        {
            JToken token = Data != null ? Data[key] : null;
            return token != null && token.Type == JTokenType.String ? token.Value<string>() : "";
        }

        internal int Int(string key, int fallback)
        {
            JToken token = Data != null ? Data[key] : null;
            if (token == null || token.Type != JTokenType.Integer) return fallback;
            return token.Value<int>();
        }

        internal JToken Raw(string key)
        {
            return Data != null ? Data[key] : null;
        }
    }

    /// <summary>
    /// 文本协议 SSE 解析器：逐行喂入（不含换行），按 <c>event:</c>/<c>data:</c> 派发。
    /// 语义按 WHATWG event-stream 的实用于集：
    /// - 空行结束一条事件；
    /// - 多个 <c>data:</c> 行以 '\n' 拼接；
    /// - ':' 开头为注释，忽略；
    /// - 缺 event 名带 data → 按 "message" 处理（未知事件，调用方忽略）；
    /// - data 不是 JSON 对象 → 计一条畸形并丢弃，不抛异常（不打断在途播放）。
    /// 解析器不判断先后/终态语义，只做搬运；顺序与终态由 <see cref="DialogueInterjectStream"/> 把关。
    /// </summary>
    internal sealed class DialogueInterjectSseParser
    {
        private readonly Action<DialogueInterjectEvent> _sink;
        private string _eventName;
        private readonly StringBuilder _data = new StringBuilder();
        private bool _hasData;

        internal int MalformedLines { get; private set; }
        internal int EventCount { get; private set; }

        internal DialogueInterjectSseParser(Action<DialogueInterjectEvent> sink)
        {
            if (sink == null) throw new ArgumentNullException(nameof(sink));
            _sink = sink;
        }

        /// <summary>喂一行（不含 \r\n）。返回派发出的事件，无则 null。</summary>
        internal DialogueInterjectEvent Feed(string line)
        {
            if (line == null) line = "";
            if (line.Length > 0 && line[line.Length - 1] == '\r') line = line.Substring(0, line.Length - 1);

            if (line.Length == 0)
            {
                return Dispatch();
            }
            if (line[0] == ':') return null;      // 注释/保活

            int colon = line.IndexOf(':');
            string field = colon < 0 ? line : line.Substring(0, colon);
            string value = colon < 0 ? "" : line.Substring(colon + 1);
            if (value.Length > 0 && value[0] == ' ') value = value.Substring(1);

            if (string.Equals(field, "event", StringComparison.Ordinal))
            {
                _eventName = value;
                return null;
            }
            if (string.Equals(field, "data", StringComparison.Ordinal))
            {
                if (_hasData) _data.Append('\n');
                _data.Append(value);
                _hasData = true;
                return null;
            }
            return null;   // id:/retry:/未知字段：不参与本功能
        }

        /// <summary>流末：把未以空行收尾的挂起事件派发掉。</summary>
        internal DialogueInterjectEvent Flush()
        {
            return Dispatch();
        }

        private DialogueInterjectEvent Dispatch()
        {
            if (!_hasData) { _eventName = null; return null; }
            string payload = _data.ToString();
            string name = _eventName ?? "message";
            _eventName = null;
            _data.Length = 0;
            _hasData = false;

            JObject data = null;
            if (payload.Length > 0)
            {
                try
                {
                    data = JObject.Parse(payload);
                }
                catch (Exception)
                {
                    MalformedLines++;
                    return null;
                }
            }
            EventCount++;
            var evt = new DialogueInterjectEvent
            {
                EventName = name,
                Kind = KindOf(name),
                Data = data ?? new JObject()
            };
            _sink(evt);
            return evt;
        }

        internal static DialogueInterjectEventKind KindOf(string name)
        {
            switch (name)
            {
                case "status": return DialogueInterjectEventKind.Status;
                case "mute": return DialogueInterjectEventKind.Mute;
                case "line": return DialogueInterjectEventKind.Line;
                case "plan": return DialogueInterjectEventKind.Plan;
                case "done": return DialogueInterjectEventKind.Done;
                case "error": return DialogueInterjectEventKind.Error;
                default: return DialogueInterjectEventKind.Unknown;
            }
        }
    }

    /// <summary>SSE 传输层：只负责"拿到一个响应流"和 finalize 回执。生产实现是 loopback HTTP。</summary>
    internal interface IDialogueInterjectTransport
    {
        /// <summary>POST 请求体并返回 SSE 响应流（调用方负责 Dispose）。取消必须中止在途请求。</summary>
        Task<Stream> OpenAsync(string requestJson, CancellationToken cancellationToken);
        /// <summary>POST finalize（已播对账，幂等）；返回后端回执 JSON。</summary>
        Task<JObject> PostFinalizeAsync(string requestJson, CancellationToken cancellationToken);
    }

    /// <summary>
    /// 生产传输：<c>POST http://127.0.0.1:7077/api/game/dialogue-interject</c>，
    /// <see cref="HttpCompletionOption.ResponseHeadersRead"/> 拿到流后逐行读，不整包缓冲。
    /// 取消约定：token 取消 → 中止请求并 Dispose 响应流（Dispose 会真正断掉连接，
    /// 只取消读取而不关流在后端看起来仍是活连接）。
    /// </summary>
    internal sealed class HttpDialogueInterjectTransport : IDialogueInterjectTransport, IDisposable
    {
        internal const string DefaultPath = "/api/game/dialogue-interject";

        private readonly HttpClient _http;
        private readonly string _url;
        private readonly bool _ownsHttp;

        internal HttpDialogueInterjectTransport(string baseUrl, string path)
            : this(new HttpClient(), baseUrl, path, true)
        {
        }

        internal HttpDialogueInterjectTransport(HttpClient http, string baseUrl, string path, bool ownsHttp)
        {
            _http = http ?? throw new ArgumentNullException(nameof(http));
            _ownsHttp = ownsHttp;
            string root = baseUrl ?? RagTerminalService.LoopbackOrigin;
            string tail = string.IsNullOrEmpty(path) ? DefaultPath : path;
            _url = root.TrimEnd('/') + tail;
        }

        internal string Url { get { return _url; } }

        /// <summary>finalize 端点 = 插话端点 + /finalize（协议 5.1）。</summary>
        internal string FinalizeUrl { get { return _url + "/finalize"; } }

        public async Task<Stream> OpenAsync(string requestJson, CancellationToken cancellationToken)
        {
            var request = new HttpRequestMessage(HttpMethod.Post, _url)
            {
                Content = new StringContent(requestJson ?? "{}", Encoding.UTF8, "application/json")
            };
            request.Headers.Accept.ParseAdd("text/event-stream");
            HttpResponseMessage response = await _http
                .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
                .ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                int status = (int)response.StatusCode;
                response.Dispose();
                throw new HttpRequestException("dialogue-interject http " + status);
            }
            return await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        }

        public async Task<JObject> PostFinalizeAsync(string requestJson, CancellationToken cancellationToken)
        {
            using (var request = new HttpRequestMessage(HttpMethod.Post, FinalizeUrl))
            {
                request.Content = new StringContent(requestJson ?? "{}", Encoding.UTF8, "application/json");
                using (HttpResponseMessage response = await _http.SendAsync(request,
                    HttpCompletionOption.ResponseContentRead, cancellationToken).ConfigureAwait(false))
                {
                    string body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
                    if (!response.IsSuccessStatusCode)
                        throw new HttpRequestException("dialogue-interject finalize http "
                            + (int)response.StatusCode);
                    return string.IsNullOrEmpty(body) ? new JObject() : JObject.Parse(body);
                }
            }
        }

        public void Dispose()
        {
            if (_ownsHttp) _http.Dispose();
        }
    }

    /// <summary>
    /// 逐句流读取器：把 SSE 流读成事件序列，并守住两条终态纪律：
    /// 1. 收到 <c>done</c>/<c>error</c> 之后不再向调用方交付任何事件（含 line）；
    /// 2. 取消（<see cref="CancellationToken"/> 或 <see cref="Cancel"/>）之后立即停止读取并断流。
    /// 首句时序不由这里保证——只要后端一推 line 就立刻回调，调用方即可上屏（G0-3 通过
    /// 假流断言"首句回调早于 done 回调"）。
    /// </summary>
    internal sealed class DialogueInterjectStream : IDisposable
    {
        private readonly IDialogueInterjectTransport _transport;
        private readonly Action<DialogueInterjectEvent> _sink;
        private readonly Action<Action> _dispatch;
        private readonly object _gate = new object();
        private CancellationTokenSource _cts;
        private Stream _stream;
        private bool _terminal;
        private bool _cancelled;
        private int _malformed;

        internal DialogueInterjectStream(IDialogueInterjectTransport transport,
            Action<DialogueInterjectEvent> sink, Action<Action> dispatch)
        {
            _transport = transport ?? throw new ArgumentNullException(nameof(transport));
            _sink = sink ?? throw new ArgumentNullException(nameof(sink));
            _dispatch = dispatch;
        }

        internal bool SawTerminal { get { lock (_gate) { return _terminal; } } }
        internal bool Cancelled { get { lock (_gate) { return _cancelled; } } }
        internal int MalformedLines { get { lock (_gate) { return _malformed; } } }

        /// <summary>外部取消（关闭对话/新发送/组结束）。可重复调用。
        /// 除取消 token 外会 Dispose 在途响应流——只取消读取而不关流，后端仍视为活连接，
        /// 达不到"真取消在途 HTTP 请求"（《协议》8）。</summary>
        internal void Cancel()
        {
            CancellationTokenSource cts;
            Stream stream;
            lock (_gate)
            {
                _cancelled = true;
                cts = _cts;
                stream = _stream;
            }
            if (stream != null)
            {
                try { stream.Dispose(); } catch { }
            }
            if (cts == null) return;
            try { cts.Cancel(); }
            catch (ObjectDisposedException) { }
        }

        /// <summary>
        /// 跑完一整轮流。返回时流已终止（done/error/取消/流错误）。
        /// 不抛异常：取消与 IO 失败都折算成返回值，失败不打断已播台词。
        /// </summary>
        internal async Task RunAsync(string requestJson, CancellationToken external)
        {
            CancellationTokenSource cts = CancellationTokenSource.CreateLinkedTokenSource(external);
            lock (_gate)
            {
                if (_cts != null) { try { _cts.Dispose(); } catch { } }
                _cts = cts;
            }
            Stream opened = null;
            try
            {
                opened = await _transport.OpenAsync(requestJson, cts.Token).ConfigureAwait(false);
                lock (_gate)
                {
                    if (_cancelled)
                    {
                        try { opened.Dispose(); } catch { }
                        return;
                    }
                    _stream = opened;
                }
                var parser = new DialogueInterjectSseParser(Deliver);
                using (var reader = new StreamReader(opened, Encoding.UTF8, false, 4096, true))
                {
                    while (!cts.IsCancellationRequested)
                    {
                        string line = await reader.ReadLineAsync(cts.Token).ConfigureAwait(false);
                        if (line == null) break;
                        parser.Feed(line);
                        if (IsTerminal())
                        {
                            // 终态后不再读：直接断流，避免后端继续产出被误播。
                            break;
                        }
                    }
                    if (!cts.IsCancellationRequested && !IsTerminal()) parser.Flush();
                }
                lock (_gate) { _malformed = parser.MalformedLines; }
            }
            catch (OperationCanceledException)
            {
                lock (_gate) { _cancelled = true; }
            }
            catch (Exception)
            {
                // 断流/协议错误：已交付的 line 保留，调用方按 D-17 回原对话。
                lock (_gate) { _terminal = true; }
            }
            finally
            {
                lock (_gate)
                {
                    if (ReferenceEquals(_stream, opened)) _stream = null;
                }
                if (opened != null)
                {
                    try { opened.Dispose(); } catch { }
                }
                lock (_gate)
                {
                    if (ReferenceEquals(_cts, cts)) _cts = null;
                }
                try { cts.Dispose(); } catch { }
            }
        }

        private bool IsTerminal()
        {
            lock (_gate) { return _terminal || _cancelled; }
        }

        /// <summary>释放：先取消在途轮（含断流），再释放 token 源。</summary>
        public void Dispose()
        {
            Cancel();
            CancellationTokenSource cts;
            lock (_gate)
            {
                cts = _cts;
                _cts = null;
            }
            if (cts == null) return;
            try { cts.Dispose(); } catch (ObjectDisposedException) { }
        }

        /// <summary>解析器回调：终态/取消失效后一律丢弃，保证"error 之后不再产生台词"。</summary>
        private void Deliver(DialogueInterjectEvent evt)
        {
            Action run = delegate
            {
                lock (_gate)
                {
                    if (_cancelled) return;
                    if (_terminal) return;
                    if (evt.Kind == DialogueInterjectEventKind.Done
                        || evt.Kind == DialogueInterjectEventKind.Error)
                        _terminal = true;
                }
                _sink(evt);
            };
            if (_dispatch == null) run();
            else _dispatch(run);
        }
    }

    /// <summary>一条待播台词（line 事件的行视图）。</summary>
    internal sealed class DialogueInterjectLine
    {
        internal string Kind;        // add | closing
        internal string Text;
        internal string Emotion;
        internal string Speaker;
        internal int Seq;
        internal int SplitIndex = -1;
        internal int SplitCount = 1;

        /// <summary>true = 165 拆分出来的非末段（输入可暂锁，《协议》3.3 / 5.2）。</summary>
        internal bool IsSplitHead
        {
            get { return SplitCount > 1 && SplitIndex >= 0 && SplitIndex < SplitCount - 1; }
        }

        internal static DialogueInterjectLine FromEvent(DialogueInterjectEvent evt)
        {
            var line = new DialogueInterjectLine
            {
                Kind = evt.Text("kind"),
                Text = evt.Text("text"),
                Emotion = evt.Text("emotion"),
                Speaker = evt.Text("speaker"),
                Seq = evt.Int("seq", -1)
            };
            JToken split = evt.Raw("split");
            if (split != null && split.Type == JTokenType.Object)
            {
                JToken index = split["index"];
                JToken count = split["count"];
                if (index != null && index.Type == JTokenType.Integer) line.SplitIndex = index.Value<int>();
                if (count != null && count.Type == JTokenType.Integer && count.Value<int>() > 0)
                    line.SplitCount = count.Value<int>();
            }
            return line;
        }
    }

    /// <summary>
    /// 首句排队（G0-3 的"玩家 $PC 播放期间到达的首句排队，$PC 播完再播"）：
    ///
    /// 状态很薄，只做三件事：
    /// 1. <see cref="BeginPlayerLine"/> 之后到达的 line 全部排队，不上屏；
    /// 2. <see cref="EndPlayerLine"/> 或当前句播完（<see cref="NotifyLineFinished"/>）时按序放出下一条；
    /// 3. <see cref="Cancel"/> 之后丢弃全部未播行，且不再放出（取消后不得再播未到的行）。
    ///
    /// 播放本身（打字机/输入可用切换）不在这里，调用方拿到 <see cref="LineReady"/> 再驱动 widget。
    /// </summary>
    internal sealed class DialogueInterjectPlayback
    {
        private readonly Queue<DialogueInterjectLine> _queue = new Queue<DialogueInterjectLine>();
        private bool _playerPlaying;
        private bool _linePlaying;
        private bool _cancelled;
        private bool _muted;

        /// <summary>放出一条可上屏的行（保证同一时刻只有一条在播）。</summary>
        internal event Action<DialogueInterjectLine> LineReady;

        internal bool Muted { get { return _muted; } }
        internal int PendingCount { get { return _queue.Count; } }
        internal bool Cancelled { get { return _cancelled; } }

        /// <summary>禁言事件（任务模式）：本组后续输入禁用，但不影响已排队台词。</summary>
        internal void MarkMuted()
        {
            if (_cancelled) return;
            _muted = true;
        }

        internal void BeginPlayerLine()
        {
            if (_cancelled) return;
            _playerPlaying = true;
        }

        /// <summary>玩家台词播完：之前排队的首句此刻上屏。</summary>
        internal void EndPlayerLine()
        {
            if (_cancelled) return;
            _playerPlaying = false;
            Drain();
        }

        /// <summary>当前播出的台词结束（打字机走完/被补全）。</summary>
        internal void NotifyLineFinished()
        {
            if (_cancelled) return;
            _linePlaying = false;
            Drain();
        }

        /// <summary>到达一条 line：玩家台词或上一条在播时排队，否则立刻上屏。</summary>
        internal bool Enqueue(DialogueInterjectLine line)
        {
            if (_cancelled || line == null) return false;
            _queue.Enqueue(line);
            Drain();
            return true;
        }

        /// <summary>取消在途轮：丢弃未播行；已上屏的归调用方（已播历史）。</summary>
        internal void Cancel()
        {
            _cancelled = true;
            _queue.Clear();
            _playerPlaying = false;
            _linePlaying = false;
        }

        private void Drain()
        {
            if (_cancelled || _playerPlaying || _linePlaying) return;
            if (_queue.Count == 0) return;
            DialogueInterjectLine next = _queue.Dequeue();
            _linePlaying = true;
            Action<DialogueInterjectLine> handler = LineReady;
            if (handler != null) handler(next);
        }
    }
}
