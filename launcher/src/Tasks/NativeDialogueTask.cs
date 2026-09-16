using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Dialogue;

namespace CF7Launcher.Tasks
{
    /// <summary>AS2 持有对话权威；宿主只采用有序快照并回送一次当前行的输入。
    /// wire v2（version:2）：book/append/set/hide/status 由 <see cref="NativeDialogueBookSession"/>
    /// 承载本地换句与 closing 终态重试；mutation 经异步 handler 在采用后回 callId ack。</summary>
    public sealed class NativeDialogueTask
    {
        public const string TaskKey = "native_dialogue";
        /// <summary>wire v2 能力握手负载（OnClientReadyForGeneration 每代下发一次）。</summary>
        internal const string CapsWire =
            "{\"task\":\"dialogue_caps\",\"modes\":[\"snapshot\",\"book\"]}";
        private readonly XmlSocketServer _socket;
        private readonly NativeDialogueWidget _widget;
        private readonly Action<Action> _dispatch;
        private readonly Func<string, bool> _send;
        private readonly Func<bool> _inputAllowed;
        private long _maxSequence;
        private long _transportEpoch;
        private volatile NativeDialogueFrame _current;
        private NativeDialogueBookSession _bookSession;
        private int _advanceKey = 13;
        private int _sentRevision;
        private string _sentVerb;
        private long _sentAt;
        private string _sceneImagePath;

        /// <summary>代际绑定发送（caps 用）：生产 = XmlSocketServer.TrySendIfGen，测试注入。</summary>
        internal Func<string, int, bool> SendForGeneration;
        /// <summary>source book 装配挂点（M3 接线；未注册时 source book 拒 malformed）。
        /// 接口定义在 Guardian.Dialogue（并行任务接缝）。</summary>
        internal CF7Launcher.Guardian.Dialogue.INativeDialogueSourceAssembler SourceAssembler;
        /// <summary>closing 重试调度器注入点：(delayMs, callback) → callback 回到采用队列执行；
        /// null = 生产默认 System.Threading.Timer → _dispatch。</summary>
        internal Action<long, Action> BookRetryScheduler;
        /// <summary>closing 重试时钟注入点（参照 widget TypingClock）。</summary>
        internal Func<long> BookRetryClock;

        // 回调收到的位图由 task 在 widget 克隆后释放。资源解析不拥有剧情推进权。
        internal Action<NativeDialogueFrame, JObject, Action<Bitmap>> LoadPortrait;
        /// <summary>元数据感知立绘加载（优先于 LoadPortrait）：回调第二参 = 外部 SWF
        /// 作者取景的舞台逻辑矩形（可为 null）。与位图同属一次 revision 投递。</summary>
        internal Action<NativeDialogueFrame, JObject, Action<Bitmap, RectangleF?>> LoadPortraitWithRect;
        internal Action<string, Action<Bitmap>> LoadSceneImage;
        /// <summary>下一句立绘预取（warm-only）：(key, expression, 归一化 appearance 或 null)。
        /// null appearance = 静态立绘。只暖缓存，绝不投递 widget、不发事件。</summary>
        internal Action<string, string, JObject> PrefetchPortrait;
        internal Func<JObject, string> ReceivePortraitResult;

        public string HandlePortraitResult(JObject message)
        {
            return ReceivePortraitResult?.Invoke(message) ?? "{\"success\":false}";
        }

        internal NativeDialogueTask(XmlSocketServer socket, NativeDialogueWidget widget,
            Action<Action> dispatch, Func<bool> inputAllowed = null)
            : this(widget, dispatch,
                wire => socket != null && socket.IsClientReady && socket.TrySend(wire), inputAllowed)
        {
            _socket = socket;
            if (socket != null) SendForGeneration = socket.TrySendIfGen;
        }

        internal NativeDialogueTask(NativeDialogueWidget widget, Action<Action> dispatch,
            Func<string, bool> send, Func<bool> inputAllowed = null)
        {
            _widget = widget ?? throw new ArgumentNullException(nameof(widget));
            _dispatch = dispatch ?? throw new ArgumentNullException(nameof(dispatch));
            _send = send ?? throw new ArgumentNullException(nameof(send));
            _inputAllowed = inputAllowed ?? (() => true);
            _widget.InputRequested = OnInput;
        }

        public string Handle(JObject message)
        {
            var payload = message?["payload"] as JObject;
            if (payload == null) return null;
            var copy = (JObject)payload.DeepClone();
            long epoch = Interlocked.Read(ref _transportEpoch);
            // v2 报文经同步入口到达时仍按同一采用点落地（ack 无人接收 = "ack 丢失
            // 但已采用"情形，AS2 可走 status 查询恢复），不静默丢弃成悬挂。
            bool v2 = IsV2Payload(payload);
            try
            {
                _dispatch(() =>
                {
                    if (epoch != Interlocked.Read(ref _transportEpoch)) return;
                    if (v2) AdoptV2(copy); else Adopt(copy);
                });
            }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
            return null;
        }

        /// <summary>wire v2 异步入口（MessageRouter callId 应答能力）：
        /// v1 报文原样走 <see cref="Handle"/> fire-and-forget 路径（逐字节保留）；
        /// version==2 的报文 dispatch 到采用队列完成校验与原子采用后再经 respond 回 ack，
        /// 禁止持 socket 串行锁等待 UI——本方法 dispatch 后立即返回。</summary>
        public void HandleAsync(JObject message, Action<string> respond)
        {
            var payload = message?["payload"] as JObject;
            if (payload == null || !IsV2Payload(payload))
            {
                Handle(message);
                return;
            }
            var copy = (JObject)payload.DeepClone();
            long epoch = Interlocked.Read(ref _transportEpoch);
            try
            {
                _dispatch(() =>
                {
                    // 连接代复查：断线已清会话，迟到采用一律拒绝（回包仍经
                    // TrySendIfGen 代际绑定发送，跨代后自然 drop）。
                    string ack = epoch == Interlocked.Read(ref _transportEpoch)
                        ? AdoptV2(copy)
                        : RejectAck(copy, "wrong_session");
                    if (ack != null && respond != null) respond(ack);
                });
            }
            catch (ObjectDisposedException) { SafeReject(copy, respond); }
            catch (InvalidOperationException) { SafeReject(copy, respond); }
        }

        private static bool IsV2Payload(JObject payload)
        {
            var v = payload["version"];
            return v != null && v.Type == JTokenType.Integer && v.Value<long>() == 2;
        }

        /// <summary>dispatch 失败兜底应答：不让 AS2 的 sendTaskWithCallback 悬挂等超时。</summary>
        private void SafeReject(JObject payload, Action<string> respond)
        {
            if (respond == null) return;
            try { respond(RejectAck(payload, "wrong_session")); }
            catch (Exception ex) { LogManager.Log("[NativeDialogue] v2 reject respond: " + ex.Message); }
        }

        /// <summary>wire v2 能力握手：每代客户端 ready 经代际绑定通道下发一次 caps。</summary>
        internal void PushCapsForGeneration(int generation)
        {
            var send = SendForGeneration;
            if (send == null) return;
            try { send(CapsWire + "\0", generation); }
            catch (Exception ex) { LogManager.Log("[NativeDialogue] caps push: " + ex.Message); }
        }

        internal void Adopt(JObject payload)
        {
            NativeDialogueFrame frame;
            long sequence;
            bool hide;
            if (!TryParse(payload, out frame, out sequence, out hide))
            {
                LogManager.Log("[NativeDialogue] rejected malformed snapshot");
                return;
            }
            if (sequence < _maxSequence) return;
            var previous = _current;
            if (hide)
            {
                ApplyHideTombstone(frame.RequestId, frame.SceneId, sequence);
                return;
            }
            if (sequence == _maxSequence)
            {
                if (previous == null || previous.RequestId != frame.RequestId
                    || previous.SceneId != frame.SceneId || frame.Revision <= previous.Revision) return;
            }
            else
            {
                // 不再先 Reset：ShowFrame 的 newSession 分支已覆盖清场（含跨会话
                // carry/hold-last-frame），先 Reset 会把 bounds 打空、触发覆层
                // hide→show 周期，连续对话整面板闪烁。
                _sceneImagePath = null;
            }
            _maxSequence = sequence;
            TerminateBookSession();
            _current = frame;
            _sentRevision = 0;
            int advanceKey;
            _advanceKey = Int(payload, "advanceKey", 1, 254, out advanceKey) ? advanceKey : 13;
            if (frame.ImageAction == "clear") _sceneImagePath = null;
            else if (frame.ImageAction == "show") _sceneImagePath = frame.ImagePath;
            _widget.ShowFrame(frame);

            var appearance = payload["portrait"]?["appearance"] as JObject;
            if (LoadPortraitWithRect != null)
                LoadPortraitWithRect(frame, appearance,
                    (bitmap, stageRect) => CompleteBitmap(frame, bitmap, stageRect, false));
            else
                LoadPortrait?.Invoke(frame, appearance,
                    bitmap => CompleteBitmap(frame, bitmap, null, false));
            // keep 行同样订阅当前图片，防止前一行的异步加载在换行后被 revision 门丢掉。
            if (!string.IsNullOrEmpty(_sceneImagePath))
                LoadSceneImage?.Invoke(_sceneImagePath, bitmap => CompleteBitmap(frame, bitmap, null, true));
            AdoptPrefetch(payload);
        }

        /// <summary>第 N+1 句立绘/配图预取：软解析，任何子字段畸形即整体丢弃；
        /// 只暖缓存，异常只记一行日志，绝不影响已采用的 frame。</summary>
        private void AdoptPrefetch(JObject payload)
        {
            try
            {
                var prefetch = payload["prefetch"] as JObject;
                if (prefetch == null) return;
                if (prefetch["portrait"] != null && !TryPrefetchPortrait(prefetch["portrait"] as JObject)) return;
                PrefetchImage(prefetch);
            }
            catch (Exception ex) { LogManager.Log("[NativeDialogue] prefetch dropped: " + ex.Message); }
        }

        /// <summary>prefetch.portrait 与 frame 的 portrait 同构软解析。返回 false = 畸形，
        /// 调用方丢弃整个 prefetch；key=="" 是合法的「下一句无立绘」，返回 true 但不暖。</summary>
        private bool TryPrefetchPortrait(JObject portrait)
        {
            string kind, key;
            if (portrait == null
                || !Text(portrait, "kind", 8, out kind) || (kind != "static" && kind != "doll")
                || !Text(portrait, "key", 256, out key)) return false;
            if (key.Length == 0) return true;
            string expression = "普通";
            if (portrait["expression"] != null)
            {
                if (!Text(portrait, "expression", 80, out expression)) return false;
                if (expression.Length == 0) expression = "普通";
            }
            if (kind == "static") { PrefetchPortrait?.Invoke(key, expression, null); return true; }
            var normalized = CF7Launcher.Guardian.Dialogue.DialoguePortraitService
                .NormalizeAppearance(portrait["appearance"] as JObject);
            if (normalized == null) return false;
            PrefetchPortrait?.Invoke(key, expression, normalized);
            return true;
        }

        /// <summary>prefetch 配图：仅显式 "show" 才暖；位图只进缓存，回调拿到即释放。</summary>
        private void PrefetchImage(JObject prefetch)
        {
            if (prefetch["imageAction"]?.Type != JTokenType.String
                || prefetch.Value<string>("imageAction") != "show") return;
            string path;
            if (!Text(prefetch, "imagePath", 512, out path) || path.Length == 0) return;
            LoadSceneImage?.Invoke(path, bmp => { if (bmp != null) bmp.Dispose(); });
        }

        // ════════════════ wire v2：book 会话采用与应答 ════════════════

        /// <summary>hide 墓碑（v1/v2 同形）：sequence 前沿推进；命中当前会话身份或
        /// 越过其前沿时静默全清。v2 会话期间 _current 即会话呈现帧，同一份判定天然覆盖；
        /// 清场时连同 book 会话一并终止（取消 closing 重试）。</summary>
        private void ApplyHideTombstone(string requestId, string sceneId, long sequence)
        {
            // 前沿门与 v1 Adopt 入口同形：低于前沿的 hide 一律忽略，墓碑绝不回退。
            if (sequence < _maxSequence) return;
            var previous = _current;
            // hide 也形成墓碑：排队中较早的 show 不得重新打开同一请求。
            if (sequence == _maxSequence && previous != null
                && previous.SceneId != sceneId) return;
            _maxSequence = sequence;
            if (previous == null || previous.RequestId == requestId
                || sequence > SequenceOf(previous.RequestId))
            {
                _current = null;
                TerminateBookSession();
                _sceneImagePath = null;
                _sentRevision = 0;
                _widget.Reset();
            }
        }

        private void TerminateBookSession()
        {
            var session = _bookSession;
            if (session == null) return;
            _bookSession = null;
            session.Terminate();
        }

        /// <summary>v2 采用点（仅采用队列）：book/append/set/hide/status 分派；
        /// 返回 callId 应答 JSON，hide 无应答返回 null。</summary>
        internal string AdoptV2(JObject p)
        {
            string op, requestId, sceneId;
            if (!Text(p, "op", 8, out op)
                || !Text(p, "requestId", 32, out requestId)
                || !Text(p, "sceneId", 128, out sceneId) || sceneId.Length == 0)
                return RejectAck(p, "malformed");
            switch (op)
            {
                case "book": return AdoptBook(p, requestId, sceneId);
                case "append": return AdoptAppend(p, requestId, sceneId);
                case "set": return AdoptSet(p, requestId, sceneId);
                case "hide": AdoptHideV2(requestId, sceneId); return null;
                case "status": return StatusReply(requestId, sceneId);
                default: return RejectAck(p, "malformed");
            }
        }

        /// <summary>v2 book：sequence > _maxSequence 且 epoch==1 才采用；行集整包校验，
        /// 任一行畸形整包拒。采用 = 原子顶掉旧会话（含 closing）与 v1 帧。</summary>
        private string AdoptBook(JObject p, string requestId, string sceneId)
        {
            long sequence = SequenceOf(requestId);
            if (sequence < 1) return RejectAck(p, "malformed");
            var epochToken = p["epoch"];
            if (epochToken == null || epochToken.Type != JTokenType.Integer)
                return RejectAck(p, "malformed");
            if (sequence <= _maxSequence) return RejectAck(p, "stale_sequence");
            if (epochToken.Value<long>() != 1) return RejectAck(p, "epoch_gap");
            string mode, kind;
            if (!Text(p, "mode", 8, out mode) || (mode != "ordinary" && mode != "stage"))
                return RejectAck(p, "malformed");
            if (!Text(p, "kind", 8, out kind) || (kind != "inline" && kind != "source"))
                return RejectAck(p, "malformed");
            int advanceKey = 13, startIndex = 0;
            if (p["advanceKey"] != null && !Int(p, "advanceKey", 1, 254, out advanceKey))
                return RejectAck(p, "malformed");
            if (p["startIndex"] != null && !Int(p, "startIndex", 0, int.MaxValue, out startIndex))
                return RejectAck(p, "malformed");

            JArray linesArray;
            if (kind == "source")
            {
                string reason;
                if (!TryAssembleSource(p, out linesArray, out reason))
                {
                    LogManager.Log("[NativeDialogue] source book rejected: " + reason);
                    return RejectAck(p, "malformed");
                }
            }
            else
            {
                linesArray = p["lines"] as JArray;
                if (linesArray == null) return RejectAck(p, "malformed");
            }
            if (linesArray.Count > 4096) return RejectAck(p, "oversize");
            if (linesArray.Count < 1
                || startIndex >= linesArray.Count) return RejectAck(p, "malformed");
            var lines = new NativeDialogueBookSession.Line[linesArray.Count];
            for (int i = 0; i < lines.Length; i++)
                if (!NativeDialogueBookSession.TryParseLine(linesArray[i], out lines[i]))
                    return RejectAck(p, "malformed");

            _maxSequence = sequence;
            TerminateBookSession();
            _current = null;
            _sceneImagePath = null;
            _sentRevision = 0;
            var session = new NativeDialogueBookSession(this, requestId, sceneId, mode,
                advanceKey, lines, Interlocked.Read(ref _transportEpoch));
            session.RetryScheduler = BookRetryScheduler ?? ScheduleBookRetry;
            if (BookRetryClock != null) session.RetryClock = BookRetryClock;
            _bookSession = session;
            session.Begin(startIndex);
            return AcceptAck(p, 1, kind == "source" ? (int?)lines.Length : null);
        }

        /// <summary>v2 append：同会话 + baseEpoch==已应用代际 + epoch==baseEpoch+1；
        /// 整包校验（任一行畸形整包拒），合并后行数 ≤4096；closing 中合法采用即复活。</summary>
        private string AdoptAppend(JObject p, string requestId, string sceneId)
        {
            var session = _bookSession;
            int applied = session != null ? session.AppliedEpoch : 0;
            var baseToken = p["baseEpoch"];
            var epochToken = p["epoch"];
            if (baseToken == null || baseToken.Type != JTokenType.Integer
                || epochToken == null || epochToken.Type != JTokenType.Integer)
                return RejectAck(p, "malformed", applied);
            if (session == null || session.RequestId != requestId || session.SceneId != sceneId)
                return RejectAck(p, "wrong_session", applied);
            long baseEpoch = baseToken.Value<long>(), epoch = epochToken.Value<long>();
            if (baseEpoch != session.AppliedEpoch || epoch != baseEpoch + 1)
                return RejectAck(p, "epoch_gap", applied);
            var linesArray = p["lines"] as JArray;
            if (linesArray == null || linesArray.Count < 1)
                return RejectAck(p, "malformed", applied);
            if (session.RowCount + linesArray.Count > 4096)
                return RejectAck(p, "oversize", applied);
            var lines = new NativeDialogueBookSession.Line[linesArray.Count];
            for (int i = 0; i < lines.Length; i++)
                if (!NativeDialogueBookSession.TryParseLine(linesArray[i], out lines[i]))
                    return RejectAck(p, "malformed", applied);
            int restartIndex = 0;
            if (p["restartIndex"] != null
                && !Int(p, "restartIndex", 0, int.MaxValue, out restartIndex))
                return RejectAck(p, "malformed", applied);
            if (restartIndex >= session.RowCount + lines.Length)
                return RejectAck(p, "malformed", applied);
            session.ApplyAppend(lines, restartIndex, (int)epoch);
            return AcceptAck(p, (int)epoch, null);
        }

        /// <summary>v2 set：白名单字段（advanceKey）低频变更；不 bump epoch，
        /// closing 中应用并保持续试原冻结请求。</summary>
        private string AdoptSet(JObject p, string requestId, string sceneId)
        {
            var session = _bookSession;
            int applied = session != null ? session.AppliedEpoch : 0;
            int advanceKey;
            if (!Int(p, "advanceKey", 1, 254, out advanceKey))
                return RejectAck(p, "malformed", applied);
            if (session == null || session.RequestId != requestId || session.SceneId != sceneId)
                return RejectAck(p, "wrong_session", applied);
            session.ApplySet(advanceKey);
            return AcceptAck(p, session.AppliedEpoch, null);
        }

        /// <summary>v2 hide：墓碑语义与 v1 完全相同（同 rid hide 终止 closing）。</summary>
        private void AdoptHideV2(string requestId, string sceneId)
        {
            long sequence = SequenceOf(requestId);
            if (sequence < 1)
            {
                LogManager.Log("[NativeDialogue] v2 hide malformed requestId");
                return;
            }
            ApplyHideTombstone(requestId, sceneId, sequence);
        }

        /// <summary>v2 status 只读查询：与 mutation 同一采用队列串行；
        /// 无匹配会话（含 v1 会话/无会话/异 rid）→ state:"none"。</summary>
        private string StatusReply(string requestId, string sceneId)
        {
            var session = _bookSession;
            var reply = new JObject
            {
                ["requestId"] = requestId, ["sceneId"] = sceneId
            };
            if (session != null && session.RequestId == requestId && session.SceneId == sceneId)
            {
                reply["state"] = session.State == NativeDialogueBookSession.HostState.Closing
                    ? "closing" : "active";
                reply["appliedEpoch"] = session.AppliedEpoch;
                reply["rowCount"] = session.RowCount;
            }
            else
            {
                reply["state"] = "none";
                reply["appliedEpoch"] = 0;
                reply["rowCount"] = 0;
            }
            return reply.ToString(Formatting.None);
        }

        /// <summary>kind:"source" 的结构校验与装配挂点：sourceRef 限定类型/键/分组/内容版本，
        /// snapshot 必须为对象；未注册装配器或装配失败 → 拒绝（ack 一律 malformed）。</summary>
        private bool TryAssembleSource(JObject p, out JArray lines, out string reason)
        {
            lines = null;
            reason = null;
            var sourceRef = p["sourceRef"] as JObject;
            var snapshot = p["snapshot"] as JObject;
            if (sourceRef == null || snapshot == null)
            {
                reason = "missing sourceRef/snapshot";
                return false;
            }
            string type, key, contentVersion;
            int group;
            if (!Text(sourceRef, "type", 32, out type)
                || !Text(sourceRef, "key", 256, out key)
                || !Text(sourceRef, "contentVersion", 64, out contentVersion))
            {
                reason = "bad sourceRef shape";
                return false;
            }
            // group 可选（缺省=0 由装配器处理）；携带时必须是非负整数。
            if (sourceRef["group"] != null
                && !Int(sourceRef, "group", 0, int.MaxValue, out group))
            {
                reason = "bad sourceRef group";
                return false;
            }
            var assembler = SourceAssembler;
            if (assembler == null)
            {
                reason = "no assembler registered";
                return false;
            }
            List<JObject> assembled;
            int rowCount;
            string rejectReason;
            bool ok;
            try
            {
                ok = assembler.TryAssemble(sourceRef, snapshot,
                    out assembled, out rowCount, out rejectReason);
            }
            catch (Exception ex)
            {
                reason = "assembler exception: " + ex.Message;
                return false;
            }
            if (!ok || assembled == null || assembled.Count < 1 || assembled.Count > 4096)
            {
                reason = rejectReason ?? "assembler returned no lines";
                return false;
            }
            lines = new JArray();
            foreach (var row in assembled) lines.Add(row);
            return true;
        }

        /// <summary>book 会话呈现钩子（会话只准在采用队列调用）：组帧已完成，
        /// 这里负责 _current 同步、widget.ShowFrame 与立绘/配图加载——与 v1 采用段同款。</summary>
        internal void PresentBookFrame(NativeDialogueBookSession session,
            NativeDialogueFrame frame, JObject appearance)
        {
            if (!ReferenceEquals(_bookSession, session)) return;
            _current = frame;
            _sentRevision = 0;
            if (frame.ImageAction == "clear") _sceneImagePath = null;
            else if (frame.ImageAction == "show") _sceneImagePath = frame.ImagePath;
            _widget.ShowFrame(frame);
            if (LoadPortraitWithRect != null)
                LoadPortraitWithRect(frame, appearance,
                    (bitmap, stageRect) => CompleteBitmap(frame, bitmap, stageRect, false));
            else
                LoadPortrait?.Invoke(frame, appearance,
                    bitmap => CompleteBitmap(frame, bitmap, null, false));
            if (!string.IsNullOrEmpty(_sceneImagePath))
                LoadSceneImage?.Invoke(_sceneImagePath,
                    bitmap => CompleteBitmap(frame, bitmap, null, true));
        }

        /// <summary>closing 重试的生产调度器：Threading.Timer 一次性延迟后经 _dispatch
        /// 回到采用队列执行；dispatch 失败（UI 已死）安全吞掉，会话 token 复查保证不串会话。</summary>
        private void ScheduleBookRetry(long delayMs, Action callback)
        {
            System.Threading.Timer timer = null;
            timer = new System.Threading.Timer(_ =>
            {
                try { timer?.Dispose(); } catch (ObjectDisposedException) { }
                try { _dispatch(callback); }
                catch (ObjectDisposedException) { }
                catch (InvalidOperationException) { }
            }, null, delayMs, System.Threading.Timeout.Infinite);
        }

        /// <summary>book 会话自驱预取：对 index+1 行暖立绘/配图缓存，只暖不投递。</summary>
        internal void PrefetchBookLine(NativeDialogueBookSession session,
            NativeDialogueBookSession.Line line)
        {
            if (!ReferenceEquals(_bookSession, session)) return;
            try
            {
                if (line.PortraitKey.Length > 0)
                    PrefetchPortrait?.Invoke(line.PortraitKey, line.Expression,
                        line.IsDoll ? line.NormalizedAppearance : null);
                if (line.ImageAction == "show" && line.ImagePath.Length > 0)
                    LoadSceneImage?.Invoke(line.ImagePath,
                        bmp => { if (bmp != null) bmp.Dispose(); });
            }
            catch (Exception ex)
            {
                LogManager.Log("[NativeDialogue] book prefetch dropped: " + ex.Message);
            }
        }

        /// <summary>冻结终态请求的唯一发射点：发射前复查会话对象身份、连接代与
        /// closing 状态。已过 _inputAllowed 的终态请求重试不再经输入门。</summary>
        internal bool TrySendBookFrozen(NativeDialogueBookSession session)
        {
            if (!ReferenceEquals(_bookSession, session)
                || session.State != NativeDialogueBookSession.HostState.Closing
                || session.TransportEpoch != Interlocked.Read(ref _transportEpoch)
                || session.FrozenWire == null) return false;
            try { return _send(session.FrozenWire); }
            catch (Exception ex)
            {
                LogManager.Log("[NativeDialogue] finish transport: " + ex.Message);
                return false;
            }
        }

        /// <summary>mutation ack（callId 回调）：requestedEpoch=报文 epoch 原样回显，
        /// appliedEpoch=采用后/当前已应用代际，reason∈协议枚举或 null。</summary>
        private string AcceptAck(JObject p, int appliedEpoch, int? rowCount)
        {
            return BuildAck(p, true, null, appliedEpoch, rowCount);
        }

        private string RejectAck(JObject p, string reason)
        {
            return RejectAck(p, reason, _bookSession != null ? _bookSession.AppliedEpoch : 0);
        }

        private string RejectAck(JObject p, string reason, int appliedEpoch)
        {
            return BuildAck(p, false, reason, appliedEpoch, null);
        }

        private static string BuildAck(JObject p, bool applied, string reason,
            int appliedEpoch, int? rowCount)
        {
            var ack = new JObject
            {
                ["requestId"] = LenientText(p, "requestId"),
                ["sceneId"] = LenientText(p, "sceneId"),
                ["op"] = LenientText(p, "op"),
                ["requestedEpoch"] = p != null && p["epoch"] != null
                    && p["epoch"].Type == JTokenType.Integer
                    ? p["epoch"] : JValue.CreateNull(),
                ["appliedEpoch"] = appliedEpoch,
                ["status"] = applied ? "applied" : "rejected",
                ["reason"] = reason
            };
            if (rowCount.HasValue) ack["rowCount"] = rowCount.Value;
            return ack.ToString(Formatting.None);
        }

        private static JToken LenientText(JObject p, string key)
        {
            var token = p != null ? p[key] : null;
            return token != null && token.Type == JTokenType.String
                ? token : (JToken)JValue.CreateNull();
        }

        /// <summary>位图 + 作者取景矩形（stageRect）同属一次 revision 的原子投递：
        /// 迟到帧 ReferenceEquals 门先拦，SetPortrait 再按 request/revision 双验，
        /// 过期包连图带元数据整体丢弃，不改动新句取景。</summary>
        private void CompleteBitmap(NativeDialogueFrame frame, Bitmap bitmap,
            RectangleF? stageRect, bool sceneImage)
        {
            if (bitmap == null) return;
            try
            {
                _dispatch(() =>
                {
                    using (bitmap)
                    {
                        if (!ReferenceEquals(_current, frame)) return;
                        if (sceneImage) _widget.SetSceneImage(frame.RequestId, frame.Revision, bitmap);
                        else _widget.SetPortrait(frame.RequestId, frame.Revision, bitmap, stageRect);
                    }
                });
            }
            catch { bitmap.Dispose(); }
        }

        private void OnInput(NativeDialogueFrame frame, string verb)
        {
            var current = _current;
            if (current == null || frame.RequestId != current.RequestId || frame.SceneId != current.SceneId
                || frame.Revision != current.Revision || !_inputAllowed()
                || (verb != "advance" && verb != "close" && verb != "finish")) return;
            var session = _bookSession;
            if (session != null && session.RequestId == current.RequestId
                && session.SceneId == current.SceneId)
            {
                // v2 会话：advance/close 本地消化；终态由 closing 状态机统一发 finish。
                // finish 动词不进 widget 输入路径（widget 只发 advance/close），忽略。
                if (verb == "advance") session.AdvanceLocal();
                else if (verb == "close") session.RequestClose();
                return;
            }
            if (verb == "finish") return;   // finish 仅属 v2 会话；v1 会话不误用
            if (_sentRevision == frame.Revision && _sentVerb == verb
                && Environment.TickCount64 - _sentAt < 750) return;
            var command = new JObject
            {
                ["task"] = "cmd", ["action"] = "nativeDialogueAction",
                ["requestId"] = frame.RequestId, ["sceneId"] = frame.SceneId,
                ["revision"] = frame.Revision, ["verb"] = verb
            };
            bool sent = false;
            try { sent = _send(command.ToString(Formatting.None) + "\0"); }
            catch (Exception ex) { LogManager.Log("[NativeDialogue] input transport: " + ex.Message); }
            if (sent) { _sentRevision = frame.Revision; _sentVerb = verb; _sentAt = Environment.TickCount64; }
        }

        /// <summary>低级钩子只捕获当前行；UI 回调再次验证，迟到按键不能推进下一行。</summary>
        internal Action CaptureKeyboardAction(uint virtualKey)
        {
            var frame = _current;
            if (frame == null || !_widget.Visible || !_inputAllowed()) return null;
            bool close = virtualKey == 27;
            int advanceKey = _bookSession != null ? _bookSession.AdvanceKey : _advanceKey;
            if (!close && virtualKey != 13 && virtualKey != advanceKey) return null;
            return () =>
            {
                try
                {
                    _dispatch(() =>
                    {
                        if (!ReferenceEquals(frame, _current) || !_widget.Visible || !_inputAllowed()) return;
                        if (close) _widget.TryClose(); else _widget.TryAdvance();
                    });
                }
                catch (ObjectDisposedException) { }
                catch (InvalidOperationException) { }
            };
        }

        public void HandleTransportDisconnected()
        {
            long epoch = Interlocked.Increment(ref _transportEpoch);
            try { _dispatch(() =>
            {
                if (epoch != Interlocked.Read(ref _transportEpoch)) return;
                _current = null;
                TerminateBookSession();
                _maxSequence = 0;
                _sentRevision = 0;
                _sceneImagePath = null;
                _widget.Reset();
            }); }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
        }

        internal static bool TryParse(JObject p, out NativeDialogueFrame frame, out long sequence, out bool hide)
        {
            frame = null; sequence = 0; hide = false;
            int version, revision, index, count;
            string request, scene, op;
            if (p == null || !Int(p, "version", 1, 1, out version)
                || !Text(p, "requestId", 32, out request) || (sequence = SequenceOf(request)) < 1
                || !Text(p, "sceneId", 128, out scene) || scene.Length == 0
                || !Text(p, "op", 4, out op) || (op != "hide" && op != "show")) return false;
            hide = op == "hide";
            frame = new NativeDialogueFrame { RequestId = request, SceneId = scene };
            if (hide) return true;
            string name, title, text, key, expression, kind, imageAction, imagePath;
            var portrait = p["portrait"] as JObject;
            if (!Int(p, "revision", 1, int.MaxValue, out revision)
                || !Int(p, "lineCount", 1, 4096, out count)
                || !Int(p, "lineIndex", 0, count - 1, out index)
                || !Text(p, "name", 256, out name) || !Text(p, "title", 256, out title)
                || !Text(p, "text", 32768, out text) || portrait == null
                || !Text(portrait, "key", 256, out key) || !Text(portrait, "expression", 80, out expression)
                || !Text(portrait, "kind", 8, out kind) || (kind != "static" && kind != "doll")
                || !Text(p, "imageAction", 5, out imageAction)
                || (imageAction != "keep" && imageAction != "show" && imageAction != "clear")) return false;
            imagePath = "";
            if (imageAction == "show" && (!Text(p, "imagePath", 512, out imagePath) || imagePath.Length == 0)) return false;
            if (kind == "doll" && !(portrait["appearance"] is JObject)) return false;
            frame.Revision = revision; frame.LineIndex = index; frame.LineCount = count;
            frame.Name = name; frame.Title = title; frame.Text = text;
            frame.PortraitKey = key; frame.Expression = expression; frame.IsDoll = kind == "doll";
            var normalizedAppearance = frame.IsDoll
                ? CF7Launcher.Guardian.Dialogue.DialoguePortraitService.NormalizeAppearance(
                    (JObject)portrait["appearance"]) : null;
            if (frame.IsDoll && normalizedAppearance == null) return false;
            frame.AppearanceIdentity = normalizedAppearance?.ToString(Formatting.None) ?? "";
            frame.ImageAction = imageAction; frame.ImagePath = imagePath;
            return true;
        }

        internal static long SequenceOf(string request)
        {
            long value;
            if (request == null || !request.StartsWith("nd:", StringComparison.Ordinal)
                || !long.TryParse(request.Substring(3), NumberStyles.None, CultureInfo.InvariantCulture, out value)
                || value < 1 || request != "nd:" + value.ToString(CultureInfo.InvariantCulture)) return 0;
            return value;
        }

        internal static bool Text(JObject p, string key, int max, out string value)
        {
            value = null;
            if (p[key]?.Type != JTokenType.String) return false;
            value = p[key].Value<string>();
            return value.Length <= max && value.IndexOf('\0') < 0;
        }

        internal static bool Int(JObject p, string key, int min, int max, out int value)
        {
            value = 0;
            if (p[key]?.Type != JTokenType.Integer) return false;
            long number;
            if (!long.TryParse(p[key].ToString(), out number) || number < min || number > max) return false;
            value = (int)number; return true;
        }
    }
}
