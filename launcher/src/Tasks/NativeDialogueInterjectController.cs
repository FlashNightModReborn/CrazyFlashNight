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
    /// <summary>插话输入可用状态（《协议》3.3 的 P1 子集）。</summary>
    internal enum DialogueInterjectInputState
    {
        /// <summary>没有可输入的时点：$PC 播放中 / 无对话会话 / 本组未开始。</summary>
        Hidden = 0,
        /// <summary>等待首句：输入显示但禁用（“……”）。</summary>
        Locked = 1,
        /// <summary>可输入（每句开始显示即可用，D-10）。</summary>
        Ready = 2
    }

    /// <summary>
    /// 日常插话 Host 侧控制器（P1 / G1）：会话 id、请求组装、$PC 插入、首句排队、
    /// 取消与失败回退、finalize。
    ///
    /// 边界：
    /// - 只做 daily；task / plan / mute / closing 留给 P2/P4（事件照常解析，不丢弃）。
    /// - 播放仍然走 <see cref="NativeDialogueBookSession"/>：AI 台词以 WireIndex=-1 的
    ///   本地行插入播放序列，AS2 的 wire 行数与 finish 契约不受影响（G0-2）。
    /// - 所有方法只在 task 的采用队列（UI dispatch）上调用；SSE 回调也经 dispatch 回到队列。
    /// - 不碰 UI 控件：输入框的显示/禁用由 <see cref="InputStateChanged"/> 的订阅方决定。
    /// </summary>
    internal sealed class NativeDialogueInterjectController : IDisposable
    {
        private const int MaxPlayerInput = 150;
        private const int LineHardMax = 165;
        private const int LinePromptMax = 135;
        private const string PcName = "$PC";
        private const string DefaultEmotion = "普通";

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

        // ── 本轮 ──
        private string _turnId;
        private DialogueInterjectStream _stream;
        private readonly Queue<DialogueInterjectLine> _queued = new Queue<DialogueInterjectLine>();
        private bool _playerLinePlaying;
        /// <summary>本组是否允许插话：G1 只认 mode=ordinary（stage 是场景剧情，不在这里插）。</summary>
        private bool _groupAllowsInterject;
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
        /// <summary>后台执行器：生产 Task.Run；测试注入同步执行，避免竞态。</summary>
        internal Func<Func<Task>, Task> TaskRunner = f => Task.Run(f);

        private DialogueInterjectInputState _inputState = DialogueInterjectInputState.Hidden;

        /// <summary>输入可用状态变化（订阅方据此显示/隐藏/禁用输入框）。</summary>
        internal event Action<DialogueInterjectInputState> InputStateChanged;

        /// <summary>诊断/测试观测：最近一次失败码（成功轮为空）。</summary>
        internal string LastFailure { get; private set; }

        /// <summary>诊断/测试观测：最近一次 finalize 回执原文。</summary>
        internal string LastFinalizeReply { get; private set; }

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
            _groupAllowsInterject = string.Equals(session.Mode, "ordinary", StringComparison.Ordinal);
            _dialogueInstanceId = null;      // 首次插入才建（D-04 / 6.1）
            _npcName = null;
            lock (_playedGate) { _played.Clear(); _nextSeq = 0; }
            _queued.Clear();
            _aiLineShown = false;
            _turnActive = false;
            _turnTailIndex = -1;
            _pcRevision = -1;
            session.LinePresented = OnLinePresented;
            SetInputState(_groupAllowsInterject
                ? DialogueInterjectInputState.Ready
                : DialogueInterjectInputState.Hidden);
        }

        private void OnSessionEnded(NativeDialogueBookSession session)
        {
            if (!ReferenceEquals(session, _session)) return;
            CancelTurn("session_end");
            session.LinePresented = null;
            _session = null;
            _groupAllowsInterject = false;
            _dialogueInstanceId = null;
            _npcName = null;
            lock (_playedGate) { _played.Clear(); _nextSeq = 0; }
            SetInputState(DialogueInterjectInputState.Hidden);
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

            if (isPc)
            {
                _playerLinePlaying = true;
                SetInputState(DialogueInterjectInputState.Hidden);
                return;
            }
            if (isLocal)
            {
                // 本地增强行 = 本轮 AI 台词：开始显示即可输入（D-10）
                _aiLineShown = true;
                if (_groupAllowsInterject) SetInputState(DialogueInterjectInputState.Ready);
                return;
            }
            // 原作台词：可输入（stage 场景剧情不开放插话）
            if (_groupAllowsInterject) SetInputState(DialogueInterjectInputState.Ready);
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
                    return;
                }
            }
            SetInputState(DialogueInterjectInputState.Locked);
            FlushPendingFinalize();
        }

        // ════════════════ 玩家发送 ════════════════

        /// <summary>
        /// 玩家发送一句：先补全当前句 → 播 $PC → 并发起请求。
        /// 返回 false＝当前不允许插话（无会话/输入禁用/空串/超长）。
        /// </summary>
        internal bool Submit(string playerInput)
        {
            if (_session == null || !_groupAllowsInterject) return false;
            if (_inputState != DialogueInterjectInputState.Ready) return false;
            string text = (playerInput ?? "").Trim();
            if (text.Length == 0 || text.Length > MaxPlayerInput) return false;
            string npc = _npcName;
            if (string.IsNullOrEmpty(npc)) return false;

            // 上一轮还在途（逐句插话）：取消在途流，已收未播丢弃（P2 再转参考续写）。
            if (_turnActive) CancelTurn("superseded");

            // 协议 3.3：发送时若当前句仍在逐字显示，先补全当前句。
            _widget.CompleteCurrentLineTyping();

            // played 只取本轮发送之前的已播历史（不含本轮 $PC）。
            List<PlayedRow> playedSnapshot;
            lock (_playedGate) { playedSnapshot = new List<PlayedRow>(_played); }
            int wireResume = _session.CurrentWireIndex + 1;
            var remaining = BuildRemaining(wireResume);
            string dialogueInstanceId = _dialogueInstanceId ?? (_dialogueInstanceId = _newId());
            string turnId = _newId();
            string requestJson = BuildRequest(text, npc, dialogueInstanceId, turnId, playedSnapshot, remaining);

            // 播 $PC：插在当前播放点之后并直接呈现（ReplaceFrom 的 present=true），接回当前 wire 的下一行。
            int insertAt = _session.Index + 1;
            if (!_session.ReplaceFrom(insertAt, new[] { BuildPcLine(text) }, wireResume))
            {
                LastFailure = "splice_failed";
                return false;
            }
            _pcRevision = _session.Revision;
            _turnTailIndex = insertAt + 1;    // $PC 之后、wire 尾之前：本轮 AI 行的插入点
            _wireResume = wireResume;
            _turnId = turnId;
            _turnActive = true;
            _aiLineShown = false;
            _queued.Clear();
            LastFailure = null;
            SetInputState(DialogueInterjectInputState.Hidden);

            StartStream(requestJson);
            return true;
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

        private string BuildRequest(string playerInput, string npc, string dialogueInstanceId,
            string turnId, List<PlayedRow> played, JArray remaining)
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
                    ["reference_continuation"] = new JArray()
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

        /// <summary>SSE 事件（已在 dispatch 队列上）：P1 只消费 line / done / error，
        /// status/mute/plan 解析保留但不动作（P2/P4 填）。</summary>
        private void OnEvent(DialogueInterjectEvent evt)
        {
            if (evt == null) return;
            switch (evt.Kind)
            {
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

        private void AcceptLine(DialogueInterjectLine line)
        {
            if (!_turnActive || line == null || string.IsNullOrEmpty(line.Text)) return;
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
            // 非首句：插到本轮段末，等玩家点“下一条”自然走到（P2 再补逐句推进策略）
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

        /// <summary>把一条 line 变成播放序列里的本地行。advance=true 时立刻显示（首句）。</summary>
        private bool PlayLine(DialogueInterjectLine line, bool advance)
        {
            if (_session == null || _turnTailIndex < 0) return false;
            // 玩家已经越过本轮段（走到原文尾部）后到达的行不抢播：留在队列由 P2 处理。
            if (_session.Index >= _turnTailIndex && !advance) return false;
            var local = new NativeDialogueBookSession.Line
            {
                Name = string.IsNullOrEmpty(line.Speaker) ? (_npcName ?? "") : line.Speaker,
                Title = "",
                Text = line.Text,
                PortraitKey = "",
                Expression = string.IsNullOrEmpty(line.Emotion) ? DefaultEmotion : line.Emotion,
                ImageAction = "keep",
                ImagePath = ""
            };
            if (!_session.ReplaceFrom(_turnTailIndex, new[] { local }, _wireResume, advance)) return false;
            _turnTailIndex++;
            if (advance)
            {
                _pcRevision = -1;           // 后续打字完成不再当 $PC
                _aiLineShown = true;
                SetInputState(DialogueInterjectInputState.Ready);
            }
            return true;
        }

        private void CompleteTurn()
        {
            if (!_turnActive) return;
            _turnActive = false;
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
        /// D-17 / F-11：失败不补写、不重试整段；**已经收到的台词照常播放**，
        /// 没有 AI 行上屏时把播放序列还原到原对话当前点。
        /// </summary>
        private void FailTurn(string code)
        {
            LastFailure = code;
            _stream = null;
            _turnActive = false;

            if (_queued.Count == 0)
            {
                _finalizePending = false;
                RestoreOriginalTailIfNoAiLine();
                SetInputState(DialogueInterjectInputState.Ready);
                Finalize("turn_error");
                return;
            }

            // 已收到的行还有得播：按"失败但保留已收台词"处理，收尾推迟到首句上屏。
            _finalizePending = true;
            if (_playerLinePlaying) return;      // $PC 播完再放（OnTypingFinished → PlayLine → Flush）
            DialogueInterjectLine next = _queued.Dequeue();
            if (PlayLine(next, true))
            {
                FlushPendingFinalize();
                return;
            }
            _finalizePending = false;
            _queued.Clear();
            RestoreOriginalTailIfNoAiLine();
            SetInputState(DialogueInterjectInputState.Ready);
            Finalize("turn_error");
        }

        /// <summary>关闭/组结束/新一轮覆盖：真取消在途流（Dispose 流 + token），未到行不播。</summary>
        internal void CancelTurn(string reason)
        {
            DialogueInterjectStream stream = _stream;
            _stream = null;
            if (stream != null)
            {
                try { stream.Cancel(); } catch { }
                try { stream.Dispose(); } catch { }
            }
            bool wasActive = _turnActive || _finalizePending;
            _turnActive = false;
            _finalizePending = false;
            _queued.Clear();
            RestoreOriginalTailIfNoAiLine();
            if (_session != null) SetInputState(DialogueInterjectInputState.Ready);
            if (wasActive) Finalize("turn_cancel:" + reason);
        }

        /// <summary>本轮没有 AI 行上屏时，删除本轮本地行并接回原文（$PC 已播保留在历史里）。</summary>
        private void RestoreOriginalTailIfNoAiLine()
        {
            if (_session == null || _aiLineShown || _turnTailIndex < 0) return;
            // 用当前已到达的原始行号 +1 接回：index 可能已经推进到原文里，不能用提交时的快照。
            _session.ReplaceFrom(_session.Index + 1, new NativeDialogueBookSession.Line[0],
                _session.CurrentWireIndex + 1, present: false);
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
