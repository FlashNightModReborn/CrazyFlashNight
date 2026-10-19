using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.RagTerminal;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>插话输入可用状态（《协议》3.3）。</summary>
    internal enum DialogueInterjectInputState
    {
        /// <summary>没有可输入的时点：$PC 播放中 / 无对话会话 / 本组未开始 / closing。</summary>
        Hidden = 0,
        /// <summary>输入显示但禁用：等待首句“……”、拆分前置段“（暂时不适合插话）”。</summary>
        Locked = 1,
        /// <summary>可输入（每句开始显示即可用，D-10）。</summary>
        Ready = 2,
        /// <summary>草案/检索准备中：显示但禁用“（正在准备…）”（《协议》3.3 / F-03）。</summary>
        Preparing = 3
    }

    /// <summary>
    /// 日常插话 Host 侧控制器（P2 / G2）：组类型门控、会话 id、请求组装、$PC 插入、
    /// 首句排队、逐句接排、中途插入的参考续写、取消/失败回退、closing 收尾与 finalize。
    ///
    /// 播放语义（《协议》3.4 / §13.2）：
    /// - 成功轮不接回原作剩余：$PC 与 AI 行都以 resumeOriginalIndex=null 插入，AI 播完即组末，
    ///   点“下一条”走 advance_past_end（finalIndex 仍是 AS2 原始末行）。
    /// - 失败轮才接回：零条 AI 行时在原当前点接回；已播部分 AI 行时接在那些行之后（_wireResume）。
    ///
    /// 边界：
    /// - stage 与 task_pre/task_post 一律不开放（P4 再开任务）；plan/mute 事件照常解析不动作。
    /// - 播放仍走 <see cref="NativeDialogueBookSession"/>：AI 台词是 WireIndex=-1 的本地行，
    ///   AS2 的 wire 行数与 finish 契约不受影响（G0-2）。
    /// - 所有方法只在 task 的采用队列（UI dispatch）上调用；SSE 回调也经 dispatch 回到队列。
    /// - 不碰 UI 控件：输入框的显示/禁用由 <see cref="InputStateChanged"/> 的订阅方决定。
    /// </summary>
    internal sealed class NativeDialogueInterjectController : IDisposable
    {
        private const int MaxPlayerInput = 150;
        private const int LineHardMax = 165;
        private const int LinePromptMax = 135;
        /// <summary>
        /// 单轮"无事件"超时（秒）。依据：任务子 Agent 最坏约 120 秒不产事件，
        /// 检索/最终对话另计；180 秒既能让长工具轮跑完，又不至于让输入无限停在 Locked。
        /// </summary>
        private const int NoEventTimeoutSeconds = 180;
        /// <summary>
        /// 单轮总时长上限（秒）。无事件超时会被持续到达的 status/line 刷新，
        /// 必须另设总上限兜住"有输出但永不结束"；按 120 秒子 Agent 再加检索/多段/重试的一倍余量取 300。
        /// </summary>
        private const int TurnTotalTimeoutSeconds = 300;
        private const string PcName = "$PC";
        private const string DefaultEmotion = "普通";
        private const string KindDaily = "daily";
        private const string KindStage = "stage";

        private sealed class PlayedRow
        {
            internal int Seq;
            internal string Role;
            internal string Name;
            internal string Text;
            internal string Emotion;

            internal JObject ToJson()
            {
                var row = new JObject
                {
                    ["seq"] = Seq,
                    ["role"] = Role,
                    ["name"] = Name ?? "",
                    ["text"] = Text ?? ""
                };
                if (!string.IsNullOrEmpty(Emotion)) row["emotion"] = Emotion;
                return row;
            }
        }

        private readonly NativeDialogueTask _task;
        private readonly NativeDialogueWidget _widget;
        private readonly Action<Action> _dispatch;
        private readonly Func<Task<bool>> _ensureReady;
        private readonly Func<IDialogueInterjectTransport> _transportFactory;
        private readonly Func<string> _newId;
        private readonly Func<DateTime> _clock;

        // ── 组（一次对话组播放）──
        private NativeDialogueBookSession _session;
        private string _dialogueInstanceId;
        private string _npcName;
        private readonly List<PlayedRow> _played = new List<PlayedRow>();
        private readonly object _playedGate = new object();
        private int _nextSeq;
        private bool _groupAllowsInterject;
        private bool _closing;

        // ── 本轮 ──
        private string _turnId;
        private DialogueInterjectStream _stream;
        private readonly Queue<DialogueInterjectLine> _queued = new Queue<DialogueInterjectLine>();
        private readonly Dictionary<NativeDialogueBookSession.Line, DialogueInterjectLine> _insertedLines =
            new Dictionary<NativeDialogueBookSession.Line, DialogueInterjectLine>();
        private bool _playerLinePlaying;
        private bool _aiLineShown;
        private bool _turnActive;
        private int _turnTailIndex = -1;
        private int _wireResume;
        private int _pcRevision = -1;
        private bool _finalizing;
        /// <summary>done 先到、但本轮首句还没上屏（$PC 还在播）：收尾推迟到首句上屏后。</summary>
        private bool _finalizePending;
        /// <summary>finalize 在途时又来一次收尾：这一轮结束后补发一次（transcript 只增不减）。</summary>
        private bool _finalizeAgain;
        /// <summary>失败轮还欠一次"在已播 AI 行之后接回原作"（等 $PC 播完/首句上屏再补）。</summary>
        private bool _resumeAfterFailure;
        /// <summary>本轮收到 status(drafting/searching)：输入显示“（正在准备…）”，line/done/error 清掉。</summary>
        private bool _preparing;
        /// <summary>本轮开始时刻（总时长上限基准）。</summary>
        private DateTime _turnStartedAt;
        /// <summary>最近一次 SSE 事件时刻（无事件超时基准）。</summary>
        private DateTime _lastActivityAt;
        /// <summary>当前在途的单轮看门狗；收尾/取消/新 turn 必须换掉或清空。</summary>
        private IDisposable _watchdog;
        /// <summary>后台执行器：生产 Task.Run；测试注入同步执行，避免竞态。</summary>
        internal Func<Func<Task>, Task> TaskRunner = f => Task.Run(f);
        /// <summary>
        /// 单轮看门狗调度器（delay, callback）→ 可取消句柄。生产用线程池 Timer；
        /// 单测注入假调度器并配合注入时钟手动推进，不 sleep。
        /// </summary>
        internal Func<TimeSpan, Action, IDisposable> WatchdogScheduler = DefaultWatchdogSchedule;

        private static IDisposable DefaultWatchdogSchedule(TimeSpan delay, Action callback)
        {
            if (delay < TimeSpan.Zero) delay = TimeSpan.Zero;
            return new Timer(delegate { callback(); }, null, delay, Timeout.InfiniteTimeSpan);
        }

        private DialogueInterjectInputState _inputState = DialogueInterjectInputState.Hidden;

        /// <summary>输入可用状态变化（订阅方据此显示/隐藏/禁用输入框）。</summary>
        internal event Action<DialogueInterjectInputState> InputStateChanged;

        /// <summary>诊断/测试观测：最近一次失败码（成功轮为空）。</summary>
        internal string LastFailure { get; private set; }

        /// <summary>诊断/测试观测：最近一次 finalize 回执原文。</summary>
        internal string LastFinalizeReply { get; private set; }

        /// <summary>诊断/测试观测：最近一次请求的 reference_continuation 条数。</summary>
        internal int LastReferenceCount { get; private set; }

        internal NativeDialogueInterjectController(
            NativeDialogueTask task,
            NativeDialogueWidget widget,
            Action<Action> dispatch,
            Func<Task<bool>> ensureReady,
            Func<IDialogueInterjectTransport> transportFactory,
            Func<string> newId = null,
            Func<DateTime> clock = null)
        {
            _task = task ?? throw new ArgumentNullException(nameof(task));
            _widget = widget ?? throw new ArgumentNullException(nameof(widget));
            _dispatch = dispatch ?? throw new ArgumentNullException(nameof(dispatch));
            _ensureReady = ensureReady;
            _transportFactory = transportFactory ?? throw new ArgumentNullException(nameof(transportFactory));
            _newId = newId ?? (() => Guid.NewGuid().ToString("D"));
            _clock = clock ?? (() => DateTime.Now);
        }

        internal DialogueInterjectInputState InputState { get { return _inputState; } }
        internal bool IsTurnActive { get { return _turnActive; } }
        internal int PendingLineCount { get { return _queued.Count; } }
        internal string DialogueInstanceId { get { return _dialogueInstanceId; } }
        internal string CurrentTurnId { get { return _turnId; } }
        internal int PlayedCount { get { return _played.Count; } }
        internal NativeDialogueBookSession SessionForTest { get { return _session; } }
        internal bool ClosingForTest { get { return _closing; } }

        /// <summary>挂接 task/widget 钩子；只允许一次。</summary>
        internal void Attach()
        {
            _task.BookSessionStarted = OnSessionStarted;
            _task.BookSessionEnded = OnSessionEnded;
            _widget.TypingFinished = OnTypingFinished;
        }

        // ════════════════ 组生命周期 ════════════════

        private void OnSessionStarted(NativeDialogueBookSession session)
        {
            _session = session;
            _closing = false;
            _groupAllowsInterject = IsDailyGroup(session);
            _dialogueInstanceId = null;      // 首次插入才建（D-04 / 6.1）
            _npcName = null;
            lock (_playedGate) { _played.Clear(); _nextSeq = 0; }
            _queued.Clear();
            _insertedLines.Clear();
            _aiLineShown = false;
            _turnActive = false;
            _turnTailIndex = -1;
            _pcRevision = -1;
            _finalizePending = false;
            _resumeAfterFailure = false;
            _preparing = false;
            DisarmWatchdog();
            session.LinePresented = OnLinePresented;
            session.Closing = OnSessionClosing;
            // 组刚开始还没有任何台词上屏：不能是 Ready（等 Begin 呈现第一句再开）。
            SetInputState(DialogueInterjectInputState.Hidden);
        }

        private void OnSessionEnded(NativeDialogueBookSession session)
        {
            if (!ReferenceEquals(session, _session)) return;
            CancelTurn("session_end");
            session.LinePresented = null;
            session.Closing = null;
            _session = null;
            _groupAllowsInterject = false;
            _closing = false;
            _dialogueInstanceId = null;
            _npcName = null;
            _preparing = false;
            DisarmWatchdog();
            _queued.Clear();
            _insertedLines.Clear();
            lock (_playedGate) { _played.Clear(); _nextSeq = 0; }
            SetInputState(DialogueInterjectInputState.Hidden);
        }

        /// <summary>
        /// closing（advance_past_end / close）立即收尾：隐藏输入、真取消在途流、按已播 finalize。
        /// 本组后续不再接受插话；已收到未插入的台词不再进本组。
        /// </summary>
        private void OnSessionClosing(string reason)
        {
            if (_session == null || _closing) return;
            _closing = true;
            StopStream();
            DisarmWatchdog();
            _turnActive = false;
            _preparing = false;
            _finalizePending = false;
            _resumeAfterFailure = false;
            _queued.Clear();
            _insertedLines.Clear();
            _turnTailIndex = -1;
            _playerLinePlaying = false;
            SetInputState(DialogueInterjectInputState.Hidden);
            // 关闭/组末这一次是权威收尾（transcript 全量前缀，幂等）。
            Finalize("closing:" + (reason ?? ""));
        }

        private static bool IsDailyGroup(NativeDialogueBookSession session)
        {
            if (session == null) return false;
            if (!string.Equals(session.Mode, "ordinary", StringComparison.Ordinal)) return false;
            return string.Equals(session.DialogueKind, KindDaily, StringComparison.Ordinal);
        }

        private void OnLinePresented(NativeDialogueBookSession.Line line)
        {
            if (_session == null || line == null) return;
            string name = line.Name ?? "";
            bool isPc = string.Equals(name, PcName, StringComparison.Ordinal);
            bool isLocal = line.WireIndex < 0;

            if (!isPc && name.Length > 0) _npcName = name;

            string role = isPc ? "player"
                : (isLocal ? "ai" : (string.Equals(name, _npcName, StringComparison.Ordinal) ? "npc" : "other_npc"));
            lock (_playedGate)
            {
                _played.Add(new PlayedRow
                {
                    Seq = _nextSeq++,
                    Role = role,
                    Name = name,
                    Text = line.Text ?? "",
                    Emotion = string.IsNullOrEmpty(line.Expression) ? DefaultEmotion : line.Expression
                });
            }
            // 已走到的行不再是“未播”，从参考续写候选里摘掉。
            _insertedLines.Remove(line);

            if (isPc)
            {
                _playerLinePlaying = true;
                SetInputState(DialogueInterjectInputState.Hidden);
                return;
            }
            if (!_groupAllowsInterject) return;
            if (isLocal)
            {
                _aiLineShown = true;
                // 拆分前置段：输入暂锁；末段/自然单条：开始显示即可输入（§3.3）。
                SetInputState(line.SplitIntermediate
                    ? DialogueInterjectInputState.Locked
                    : DialogueInterjectInputState.Ready);
                return;
            }
            // 原作台词：可输入（stage / 任务组已在 IsDailyGroup 拦掉）
            SetInputState(DialogueInterjectInputState.Ready);
        }

        /// <summary>打字完成（widget 每帧一次）：$PC 播完 → 放出排队的首句或进入等待。</summary>
        private void OnTypingFinished(NativeDialogueFrame frame)
        {
            if (_session == null || frame == null) return;
            if (!string.Equals(frame.RequestId, _session.RequestId, StringComparison.Ordinal)) return;
            if (!_playerLinePlaying) return;
            if (_pcRevision < 0 || frame.Revision != _pcRevision) return;

            _playerLinePlaying = false;
            if (_queued.Count > 0)
            {
                DialogueInterjectLine next = _queued.Dequeue();
                if (PlayLine(next, true))
                {
                    // 首句已上屏：其余已收台词按顺序接在它后面，玩家点“下一条”逐句看。
                    DrainQueueToTail();
                    FlushPendingFinalize();
                    FlushResumeAfterFailure();
                    return;
                }
            }
            // 没有排队的台词可放：按"等待"落回 Locked；草案/检索准备中显示“（正在准备…）”。
            SetInputState(_preparing
                ? DialogueInterjectInputState.Preparing
                : DialogueInterjectInputState.Locked);
            FlushPendingFinalize();
            FlushResumeAfterFailure();
        }

        // ════════════════ 玩家发送 ════════════════

        /// <summary>
        /// 玩家发送一句：先补全当前句 → 收集未播（参考续写）→ 真取消在途流 → 播新 $PC → 发请求。
        /// 返回 false＝当前不允许插话（无会话 / closing / 空串 / 超长 / 非日常组）。
        /// </summary>
        internal bool Submit(string playerInput)
        {
            if (_session == null || !_groupAllowsInterject || _closing) return false;
            if (_session.State != NativeDialogueBookSession.HostState.Active) return false;
            if (_inputState != DialogueInterjectInputState.Ready) return false;
            string text = (playerInput ?? "").Trim();
            if (text.Length == 0 || text.Length > MaxPlayerInput) return false;
            string npc = _npcName;
            if (string.IsNullOrEmpty(npc)) return false;

            // 协议 3.3：发送时若当前句仍在逐字显示，先补全当前句。
            _widget.CompleteCurrentLineTyping();

            // 协议 4.6 / D-09：上一轮未播的新增/结束语转成本轮参考续写（含已插入未走到的行）。
            List<DialogueInterjectLine> unplayed = CollectUnplayedTurnLines();

            // 一轮在途时再次发送：真取消在途流（Dispose 流 + token），已收内容已在上面的 unplayed 里。
            StopStream();
            _turnActive = false;
            _finalizePending = false;
            _resumeAfterFailure = false;

            // played 只取本轮发送之前的已播历史（不含本轮 $PC）。
            List<PlayedRow> playedSnapshot;
            lock (_playedGate) { playedSnapshot = new List<PlayedRow>(_played); }
            int wireResume = _session.CurrentWireIndex + 1;
            var remaining = BuildRemaining(wireResume);
            string dialogueInstanceId = _dialogueInstanceId ?? (_dialogueInstanceId = _newId());
            string turnId = _newId();
            string requestJson = BuildRequest(text, npc, dialogueInstanceId, turnId,
                playedSnapshot, remaining, unplayed);

            // 播 $PC：成功轮不接回原作剩余（resume=null），原作只剩参考价值。
            int insertAt = _session.Index + 1;
            if (!_session.ReplaceFrom(insertAt, new[] { BuildPcLine(text) }, null))
            {
                LastFailure = "splice_failed";
                return false;
            }
            _pcRevision = _session.Revision;
            _turnTailIndex = insertAt + 1;    // $PC 之后：本轮 AI 行的插入点
            _wireResume = wireResume;
            _turnId = turnId;
            _turnActive = true;
            _aiLineShown = false;
            _preparing = false;
            _queued.Clear();
            _insertedLines.Clear();
            LastFailure = null;
            LastReferenceCount = unplayed.Count;
            SetInputState(DialogueInterjectInputState.Hidden);

            // 看门狗只在本轮活动期间有效：新 turn 从此刻重新计时，收尾/取消时 disarm。
            _turnStartedAt = _lastActivityAt = _clock();
            ArmWatchdog(_turnStartedAt);
            StartStream(requestJson);
            return true;
        }

        /// <summary>
        /// 收集"本轮已收到但没播"的台词：排队中的 + 已插进播放序列但当前还没走到的。
        /// 只用于本轮（新一轮开始时清空映射表）。
        /// </summary>
        private List<DialogueInterjectLine> CollectUnplayedTurnLines()
        {
            var unplayed = new List<DialogueInterjectLine>();
            while (_queued.Count > 0) unplayed.Add(_queued.Dequeue());
            if (_session == null) return unplayed;
            for (int i = _session.Index + 1; i < _session.PlaybackCount; i++)
            {
                NativeDialogueBookSession.Line line = _session.GetPlaybackLine(i);
                if (line == null) continue;
                DialogueInterjectLine source;
                if (_insertedLines.TryGetValue(line, out source)) unplayed.Add(source);
            }
            return unplayed;
        }

        private JArray BuildRemaining(int fromWire)
        {
            var remaining = new JArray();
            int index = 1;
            for (int wire = Math.Max(0, fromWire); wire < _session.RowCount; wire++)
            {
                NativeDialogueBookSession.Line row = _session.GetWireRow(wire);
                if (row == null) continue;
                remaining.Add(new JObject
                {
                    ["index"] = index++,
                    ["name"] = row.Name ?? "",
                    ["text"] = row.Text ?? "",
                    ["emotion"] = string.IsNullOrEmpty(row.Expression) ? DefaultEmotion : row.Expression
                });
            }
            return remaining;
        }

        /// <summary>上一轮未播的 add/closing → reference_continuation（协议 5.1）。</summary>
        private JArray BuildReference(List<DialogueInterjectLine> unplayed)
        {
            var reference = new JArray();
            if (unplayed == null) return reference;
            for (int i = 0; i < unplayed.Count; i++)
            {
                DialogueInterjectLine line = unplayed[i];
                if (line == null || string.IsNullOrEmpty(line.Text)) continue;
                reference.Add(new JObject
                {
                    ["kind"] = string.Equals(line.Kind, "closing", StringComparison.Ordinal) ? "closing" : "add",
                    ["name"] = string.IsNullOrEmpty(line.Speaker) ? (_npcName ?? "") : line.Speaker,
                    ["text"] = line.Text,
                    ["emotion"] = string.IsNullOrEmpty(line.Emotion) ? DefaultEmotion : line.Emotion
                });
            }
            return reference;
        }

        private string BuildRequest(string playerInput, string npc, string dialogueInstanceId,
            string turnId, List<PlayedRow> played, JArray remaining, List<DialogueInterjectLine> unplayed)
        {
            var playedArray = new JArray();
            foreach (PlayedRow row in played) playedArray.Add(row.ToJson());
            var request = new JObject
            {
                ["mode"] = "daily",
                ["dialogue_instance_id"] = dialogueInstanceId,
                ["turn_id"] = turnId,
                ["npc"] = npc,
                ["player_input"] = playerInput,
                ["session_title"] = "日常插话 · " + npc + " · "
                    + _clock().ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
                ["dialogue"] = new JObject
                {
                    ["kind"] = "daily",
                    ["group_id"] = _session.RequestId,
                    ["played"] = playedArray,
                    ["remaining"] = remaining,
                    ["reference_continuation"] = BuildReference(unplayed)
                },
                ["task_context"] = JValue.CreateNull(),
                ["limits"] = new JObject
                {
                    ["line_hard_max"] = LineHardMax,
                    ["line_prompt_max"] = LinePromptMax
                }
            };
            return request.ToString(Formatting.None);
        }

        /// <summary>$PC 行：优先沿用本组原作里的 $PC 外观（风险 7 的保守处理），没有就无立绘。</summary>
        private NativeDialogueBookSession.Line BuildPcLine(string text)
        {
            NativeDialogueBookSession.Line template = null;
            for (int wire = 0; wire < _session.RowCount; wire++)
            {
                NativeDialogueBookSession.Line row = _session.GetWireRow(wire);
                if (row != null && string.Equals(row.Name, PcName, StringComparison.Ordinal)) template = row;
            }
            return new NativeDialogueBookSession.Line
            {
                Name = PcName,
                Title = template != null ? template.Title : "",
                Text = text,
                PortraitKey = template != null ? template.PortraitKey : "",
                Expression = template != null ? template.Expression : DefaultEmotion,
                IsDoll = template != null && template.IsDoll,
                Appearance = template != null ? template.Appearance : null,
                NormalizedAppearance = template != null ? template.NormalizedAppearance : null,
                AppearanceIdentity = template != null ? template.AppearanceIdentity : "",
                ImageAction = "keep",
                ImagePath = ""
            };
        }

        // ════════════════ 流与播放 ════════════════

        private void StartStream(string requestJson)
        {
            IDialogueInterjectTransport transport = _transportFactory();
            if (transport == null)
            {
                FailTurn("no_transport");
                return;
            }
            var stream = new DialogueInterjectStream(transport, OnEvent, _dispatch);
            _stream = stream;
            TaskRunner(async () =>
            {
                try
                {
                    if (_ensureReady != null)
                    {
                        bool ready = await _ensureReady().ConfigureAwait(false);
                        if (!ready)
                        {
                            Post(() => { if (ReferenceEquals(_stream, stream)) FailTurn("terminal_unavailable"); });
                            return;
                        }
                    }
                    await stream.RunAsync(requestJson, CancellationToken.None).ConfigureAwait(false);
                    Post(() =>
                    {
                        if (!ReferenceEquals(_stream, stream)) return;
                        // 流结束但没收到 done/error（断流）：按部分有效处理。
                        if (!stream.SawTerminal) FailTurn("stream_closed");
                    });
                }
                catch (Exception ex)
                {
                    LogManager.Log("[DialogueInterject] stream: " + ex.Message);
                    Post(() => { if (ReferenceEquals(_stream, stream)) FailTurn("stream_failed"); });
                }
            });
        }

        private void Post(Action action)
        {
            try { _dispatch(action); }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
        }

        // ════════════════ 单轮看门狗 ════════════════

        /// <summary>每收到一个 SSE 事件刷新无事件窗口；只在本轮活动期间计时。</summary>
        private void NoteWatchdogActivity()
        {
            if (!_turnActive || _closing) return;
            _lastActivityAt = _clock();
            ArmWatchdog(_lastActivityAt);
        }

        /// <summary>按 min(无事件窗口, 总时长上限) 重排一次性定时器；早触发由 OnWatchdogFired 自行续排。</summary>
        private void ArmWatchdog(DateTime now)
        {
            DisarmWatchdog();
            if (!_turnActive || _closing) return;
            DateTime noEventDeadline = _lastActivityAt.AddSeconds(NoEventTimeoutSeconds);
            DateTime totalDeadline = _turnStartedAt.AddSeconds(TurnTotalTimeoutSeconds);
            DateTime deadline = noEventDeadline < totalDeadline ? noEventDeadline : totalDeadline;
            TimeSpan delay = deadline - now;
            if (delay < TimeSpan.Zero) delay = TimeSpan.Zero;
            _watchdog = WatchdogScheduler(delay, delegate { Post(OnWatchdogFired); });
        }

        private void DisarmWatchdog()
        {
            IDisposable timer = _watchdog;
            _watchdog = null;
            if (timer == null) return;
            try { timer.Dispose(); } catch { }
        }

        /// <summary>
        /// 看门狗到期（已回到 dispatch 队列）：本轮已结束就只清定时器；
        /// 没到真超时（假时钟/提前触发）按剩余时间续排；真超时则停流 + 按失败回退并解锁输入。
        /// </summary>
        private void OnWatchdogFired()
        {
            if (_session == null || _closing || !_turnActive)
            {
                DisarmWatchdog();
                return;
            }
            DateTime now = _clock();
            bool noEventExpired = now >= _lastActivityAt.AddSeconds(NoEventTimeoutSeconds);
            bool totalExpired = now >= _turnStartedAt.AddSeconds(TurnTotalTimeoutSeconds);
            if (!noEventExpired && !totalExpired)
            {
                ArmWatchdog(now);
                return;
            }
            StopStream();
            FailTurn("stream_timeout");
        }

        /// <summary>SSE 事件（已在 dispatch 队列上）：消费 status / line / done / error；
        /// mute/plan 解析保留但不动作（P4 填）。internal 也作为单测的中途事件驱动点。</summary>
        internal void OnEvent(DialogueInterjectEvent evt)
        {
            if (evt == null) return;
            NoteWatchdogActivity();
            switch (evt.Kind)
            {
                case DialogueInterjectEventKind.Status:
                    ApplyStatus(evt);
                    break;
                case DialogueInterjectEventKind.Line:
                    AcceptLine(DialogueInterjectLine.FromEvent(evt));
                    break;
                case DialogueInterjectEventKind.Done:
                    CompleteTurn();
                    break;
                case DialogueInterjectEventKind.Error:
                    FailTurn(evt.Text("code").Length > 0 ? evt.Text("code") : "error");
                    break;
                default:
                    break;
            }
        }

        /// <summary>
        /// status（协议 5.2，可选）：drafting/searching 表示草案/检索准备中 →
        /// 输入显示但禁用“（正在准备…）”。line/done/error 由各自路径清掉该标记并回到既有状态；
        /// 其余 stage（connecting/thinking/waiting）不改输入态，避免自造状态。
        /// 后端不提供这两个 stage 时输入保持 Locked“……”即可。
        /// </summary>
        private void ApplyStatus(DialogueInterjectEvent evt)
        {
            if (!_turnActive || _closing || !_groupAllowsInterject) return;
            string stage = evt.Text("stage");
            if (!string.Equals(stage, "drafting", StringComparison.Ordinal)
                && !string.Equals(stage, "searching", StringComparison.Ordinal)) return;
            _preparing = true;
            if (_playerLinePlaying) return;   // $PC 播放期间保持 Hidden，播完再显示“正在准备…”
            SetInputState(DialogueInterjectInputState.Preparing);
        }

        private void AcceptLine(DialogueInterjectLine line)
        {
            if (!_turnActive || _closing || line == null || string.IsNullOrEmpty(line.Text)) return;
            _preparing = false;             // 已经出词：草案/检索阶段结束
            if (_playerLinePlaying)
            {
                _queued.Enqueue(line);      // $PC 播放期间到达：排队，播完再播
                return;
            }
            if (!_aiLineShown)
            {
                // 首句：立即上屏（不等 done/后续行）
                if (!PlayLine(line, true)) _queued.Enqueue(line);
                return;
            }
            // 非首句：接在本轮段末；玩家点“下一条”逐句走到（包括结束语——它只是最后一条）。
            if (!PlayLine(line, false)) _queued.Enqueue(line);
        }

        /// <summary>把排队中的已收台词顺序插到本轮段末（不换当前显示）。</summary>
        private void DrainQueueToTail()
        {
            while (_queued.Count > 0)
            {
                DialogueInterjectLine line = _queued.Dequeue();
                if (!PlayLine(line, false))
                {
                    _queued.Enqueue(line);
                    return;
                }
            }
        }

        /// <summary>
        /// 把一条 line 变成播放序列里的本地行（resume=null：成功轮不接回原作剩余）。
        /// advance=true 时立刻显示（首句）。
        /// </summary>
        private bool PlayLine(DialogueInterjectLine line, bool advance)
        {
            if (_session == null || _turnTailIndex < 0) return false;
            if (!advance && _session.Index >= _turnTailIndex) return false;
            var local = new NativeDialogueBookSession.Line
            {
                Name = string.IsNullOrEmpty(line.Speaker) ? (_npcName ?? "") : line.Speaker,
                Title = "",
                Text = line.Text,
                PortraitKey = "",
                Expression = string.IsNullOrEmpty(line.Emotion) ? DefaultEmotion : line.Emotion,
                ImageAction = "keep",
                ImagePath = "",
                SplitIntermediate = line.IsSplitHead
            };
            if (!_session.ReplaceFrom(_turnTailIndex, new[] { local }, null, advance)) return false;
            _turnTailIndex++;
            _insertedLines[local] = line;
            if (advance)
            {
                _pcRevision = -1;           // 后续打字完成不再当 $PC
                _aiLineShown = true;
                SetInputState(line.IsSplitHead
                    ? DialogueInterjectInputState.Locked
                    : DialogueInterjectInputState.Ready);
            }
            return true;
        }

        private void CompleteTurn()
        {
            if (!_turnActive) return;
            _turnActive = false;
            _preparing = false;
            DisarmWatchdog();
            if (!_aiLineShown && _queued.Count == 0)
            {
                // done 但零条可播（后端违反自身约定）：按失败处理，回原对话。
                FailTurn("done_without_line");
                return;
            }
            if (_playerLinePlaying)
            {
                // $PC 还在播：先不动输入态，等首句上屏再收尾（transcript 要含已播的 AI 行）。
                _finalizePending = true;
                return;
            }
            if (!_aiLineShown) _finalizePending = true;
            SetInputState(DialogueInterjectInputState.Ready);
            FlushPendingFinalize();
        }

        private void FlushPendingFinalize()
        {
            if (!_finalizePending) return;
            if (_playerLinePlaying) return;
            _finalizePending = false;
            Finalize("turn_done");
        }

        // ════════════════ 失败 / 取消 / 收尾 ════════════════

        /// <summary>
        /// D-17 / F-11：失败不补写、不重试整段；已经收到的台词照常播放。
        /// 零条 AI 行 → 在原生当前点接回；已播若干 AI 行 → 接在那些行之后（_wireResume）。
        /// </summary>
        private void FailTurn(string code)
        {
            LastFailure = code;
            _stream = null;
            _turnActive = false;
            _preparing = false;
            DisarmWatchdog();

            if (_queued.Count == 0)
            {
                _finalizePending = false;
                _resumeAfterFailure = false;
                // 已播过 AI 行时 RestoreOriginalTail 会直接返回（_aiLineShown），
                // 必须改走 ResumeAfterPlayedTurnLines 把原作剩余接在那些行之后（P2 缺陷修复）。
                if (_aiLineShown) ResumeAfterPlayedTurnLines();
                else RestoreOriginalTail();
                SetInputState(DialogueInterjectInputState.Ready);
                Finalize("turn_error");
                return;
            }

            // 已收到的行还有得播：按"失败但保留已收台词"处理，收尾与接回都推迟到首句上屏。
            _finalizePending = true;
            _resumeAfterFailure = true;
            if (_playerLinePlaying) return;      // $PC 播完再放（OnTypingFinished → PlayLine → Flush）
            DialogueInterjectLine next = _queued.Dequeue();
            if (PlayLine(next, true))
            {
                DrainQueueToTail();
                FlushPendingFinalize();
                FlushResumeAfterFailure();
                return;
            }
            _finalizePending = false;
            _resumeAfterFailure = false;
            _queued.Clear();
            // 落不了新行（splice 失败等）：与零条失败同一口径，已在播的 AI 行之后接回原作。
            if (_aiLineShown) ResumeAfterPlayedTurnLines();
            else RestoreOriginalTail();
            SetInputState(DialogueInterjectInputState.Ready);
            Finalize("turn_error");
        }

        /// <summary>关闭/组结束/新一轮覆盖：真取消在途流（Dispose 流 + token），未到行不播。</summary>
        internal void CancelTurn(string reason)
        {
            bool wasActive = _turnActive || _finalizePending;
            StopStream();
            DisarmWatchdog();
            _turnActive = false;
            _preparing = false;
            _finalizePending = false;
            _resumeAfterFailure = false;
            _queued.Clear();
            RestoreOriginalTail();
            if (_session != null && !_closing) SetInputState(DialogueInterjectInputState.Ready);
            if (wasActive) Finalize("turn_cancel:" + reason);
        }

        /// <summary>真取消：Dispose 在途响应流再取消 token（只取消读取不算断流）。</summary>
        private void StopStream()
        {
            DialogueInterjectStream stream = _stream;
            _stream = null;
            if (stream == null) return;
            try { stream.Cancel(); } catch { }
            try { stream.Dispose(); } catch { }
        }

        /// <summary>本轮没有 AI 行上屏时，删除本轮本地行并接回原文（$PC 已播保留在历史里）。</summary>
        private void RestoreOriginalTail()
        {
            if (_session == null || _aiLineShown || _closing) return;
            if (_session.State != NativeDialogueBookSession.HostState.Active) return;
            // 用当前已到达的原始行号 +1 接回：index 可能已经推进到原文里，不能用提交时的快照。
            _session.ReplaceFrom(_session.Index + 1, new NativeDialogueBookSession.Line[0],
                _session.CurrentWireIndex + 1, present: false);
            _turnTailIndex = -1;
        }

        /// <summary>失败轮欠的"接回原作"：等 $PC 播完/首句上屏后补一次。</summary>
        private void FlushResumeAfterFailure()
        {
            if (!_resumeAfterFailure || _playerLinePlaying) return;
            _resumeAfterFailure = false;
            ResumeAfterPlayedTurnLines();
        }

        /// <summary>
        /// 失败但已播过 AI 行：把原作剩余接在这些行之后（不换当前显示，玩家点“下一条”回到原文）。
        /// </summary>
        private void ResumeAfterPlayedTurnLines()
        {
            if (_session == null || !_aiLineShown || _closing) return;
            if (_session.State != NativeDialogueBookSession.HostState.Active) return;
            if (_turnTailIndex < 0) return;
            _session.ReplaceFrom(_turnTailIndex, new NativeDialogueBookSession.Line[0],
                _wireResume, present: false);
            _turnTailIndex = -1;
        }

        /// <summary>finalize：按已播 transcript 对账；不阻塞 UI，失败只记日志。</summary>
        private void Finalize(string reason)
        {
            List<PlayedRow> playedSnapshot;
            lock (_playedGate)
            {
                if (_played.Count == 0) return;
                playedSnapshot = new List<PlayedRow>(_played);
            }
            if (_dialogueInstanceId == null) return;
            if (_finalizing) { _finalizeAgain = true; return; }
            IDialogueInterjectTransport transport;
            try { transport = _transportFactory(); }
            catch (Exception ex) { LogManager.Log("[DialogueInterject] finalize transport: " + ex.Message); return; }
            if (transport == null) return;

            var transcript = new JArray();
            foreach (PlayedRow row in playedSnapshot) transcript.Add(row.ToJson());
            var payload = new JObject
            {
                ["dialogue_instance_id"] = _dialogueInstanceId,
                ["turn_id"] = _turnId,
                ["transcript"] = transcript
            };
            string json = payload.ToString(Formatting.None);
            string instanceId = _dialogueInstanceId;
            _finalizing = true;
            TaskRunner(async () =>
            {
                try
                {
                    JObject reply = await transport.PostFinalizeAsync(json, CancellationToken.None)
                        .ConfigureAwait(false);
                    Post(() =>
                    {
                        if (_dialogueInstanceId == instanceId)
                            LastFinalizeReply = reply != null ? reply.ToString(Formatting.None) : "";
                        LogManager.Log("[DialogueInterject] finalize " + reason + " -> "
                            + (reply != null ? reply.ToString(Formatting.None) : "null"));
                    });
                }
                catch (Exception ex)
                {
                    LogManager.Log("[DialogueInterject] finalize failed: " + ex.Message);
                }
                finally
                {
                    Post(() =>
                    {
                        _finalizing = false;
                        if (!_finalizeAgain) return;
                        _finalizeAgain = false;
                        Finalize("resync");
                    });
                }
            });
        }

        private void SetInputState(DialogueInterjectInputState state)
        {
            if (_inputState == state) return;
            _inputState = state;
            Action<DialogueInterjectInputState> handler = InputStateChanged;
            if (handler == null) return;
            try { handler(state); }
            catch (Exception ex) { LogManager.Log("[DialogueInterject] InputStateChanged throw: " + ex.Message); }
        }

        public void Dispose()
        {
            CancelTurn("dispose");
            if (_task != null)
            {
                if (object.Equals(_task.BookSessionStarted, (Action<NativeDialogueBookSession>)OnSessionStarted))
                    _task.BookSessionStarted = null;
                if (object.Equals(_task.BookSessionEnded, (Action<NativeDialogueBookSession>)OnSessionEnded))
                    _task.BookSessionEnded = null;
            }
            if (_widget != null
                && object.Equals(_widget.TypingFinished, (Action<NativeDialogueFrame>)OnTypingFinished))
                _widget.TypingFinished = null;
        }
    }
}
