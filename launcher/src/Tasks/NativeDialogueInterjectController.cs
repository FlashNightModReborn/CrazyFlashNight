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
        Preparing = 3,
        /// <summary>任务模式禁言：显示但禁用“（NPC名）暂时不打算让你插话”（《协议》4.7 / F-09）。
        /// 整组锁，组结束/关闭后重置。</summary>
        Muted = 4,
        /// <summary>聊天终端未启动：禁言样式 + “请先启动聊天终端”；按钮为“启动”，
        /// 点击只拉起终端、不发送输入，就绪后解锁。</summary>
        Offline = 5,
        /// <summary>终端已就绪但模型 API 未配置：禁言样式 + “请配置模型API”；
        /// 按钮为“配置”，点击打开配置小窗，保存后解锁。</summary>
        NeedsConfig = 6
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
        private const string KindTaskPre = "task_pre";
        private const string KindTaskPost = "task_post";
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

        /// <summary>已插入播放序列的本地行：add（TaskIndex=0）或对原第 N 条的改写（TaskIndex=n）。</summary>
        private sealed class InsertedRef
        {
            internal DialogueInterjectLine Line;
            internal int WireIndex = -1;
            internal int TaskIndex;
        }

        /// <summary>plan 里的一条改写意图（n 为当轮 remaining 的 1..N）。</summary>
        private sealed class TaskEdit
        {
            internal string Kind;                      // nochange | edit | remove
            internal readonly List<DialogueInterjectLine> Lines = new List<DialogueInterjectLine>();
        }

        /// <summary>SSE plan（协议 5.2）：end/mute/edits；非法部分宽容忽略。</summary>
        private sealed class TaskPlan
        {
            internal bool HasEnd;
            internal int End;
            internal bool Mute;
            internal readonly Dictionary<int, TaskEdit> Edits = new Dictionary<int, TaskEdit>();
        }

        /// <summary>参考续写条目：add/closing 带行；edit/remove 带下一轮 remaining 的 1..N 下标。</summary>
        private sealed class ReferenceItem
        {
            internal string Kind;
            internal int Index;
            internal DialogueInterjectLine Line;
        }

        private readonly NativeDialogueTask _task;
        private readonly NativeDialogueWidget _widget;
        private readonly Action<Action> _dispatch;
        private readonly Func<Task<bool>> _ensureReady;
        private readonly Func<string, Task> _ensureBound;
        private readonly Func<IDialogueInterjectTransport> _transportFactory;
        private readonly Func<bool> _terminalReady;
        private readonly Func<Task<bool>> _llmConfigured;
        private bool _terminalStarting;
        private bool _terminalStartFailed;
        /// <summary>终端已就绪但模型 API 未配置：输入禁用，等配置小窗保存。</summary>
        private bool _needsConfig;
        private bool _configProbeInFlight;
        // 每个终端就绪周期只自动拉一次配置小窗：小窗会从 localStorage 读回旧配置，
        // 已有配置时屏外关闭并解锁；玩家取消后不再反复弹。
        private bool _autoConfigSyncTried;
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

        // ── 任务组（P4）──
        /// <summary>ordinary + task_pre/task_post；stage 与日常都不是任务模式。</summary>
        private bool _taskMode;
        /// <summary>组开始时取一次的 task_context；null = 不可插话（fail-closed）。</summary>
        private JObject _taskContext;
        /// <summary>mute 是任务模式唯一的整组锁；组结束/关闭后重置。</summary>
        private bool _muted;
        /// <summary>本轮 plan 无 end：原始剩余已放弃，下一轮 remaining 为空、不再接回原文。</summary>
        private bool _abandonedOriginalTail;
        /// <summary>已收到但还没应用（$PC 播放中 / add 还在排队）的 plan。</summary>
        private TaskPlan _pendingPlan;
        /// <summary>本轮 plan 已应用（失败时不再接回原文）。</summary>
        private bool _planApplied;
        /// <summary>已应用、但播放进度还没越过的 remove 的原始行号（下一轮转参考续写）。</summary>
        private readonly List<int> _appliedRemoves = new List<int>();

        // ── 物品往来（P6）──
        /// <summary>Host→AS2 物品命令桥；null = 未接线（物品动作按不可用处理）。</summary>
        private readonly NpcItemExchangeTask _itemExchange;
        /// <summary>后端待处理索取；跨轮保留，closed/error/断线/组结束清空。</summary>
        private JObject _pendingItemClaim;
        private DialogueInterjectItemClaimView _itemClaimView;
        private int _itemClaimGeneration;
        private bool _itemDecisionBusy;
        /// <summary>已执行过的发放 action_id：SSE 重发不得二次发放。</summary>
        private readonly HashSet<string> _executedGrants = new HashSet<string>(StringComparer.Ordinal);
        /// <summary>本组玩家可索取物品名快照（只用于后端索取池）。</summary>
        private List<string> _playerItemNames;
        private int _playerNamesGeneration;
        /// <summary>本轮已点过任务选项：不再重复弹「我接了/我不接」。</summary>
        private bool _taskActionSent;
        /// <summary>已真实扣除、但本轮可能没送达后端的 item_take_accept：失败时用同 action_id 重试一次。</summary>
        private JObject _unackedItemAction;
        private string _itemActionRetriedId;

        // ── 本轮 ──
        private string _turnId;
        private DialogueInterjectStream _stream;
        private readonly Queue<DialogueInterjectLine> _queued = new Queue<DialogueInterjectLine>();
        private readonly Dictionary<NativeDialogueBookSession.Line, InsertedRef> _insertedLines =
            new Dictionary<NativeDialogueBookSession.Line, InsertedRef>();
        private bool _playerLinePlaying;
        /// <summary>当前上屏行是玩家台词（含打字完成、仍停在玩家行等“下一条”）。此期间输入框整条隐藏。</summary>
        private bool _playerLineOnScreen;
        private bool _aiLineShown;
        /// <summary>最近一条已插入的 AI 行是过渡话：越过它但本轮未结束时仍显示 ui_hint 占位。</summary>
        private bool _lastAiLineInterim;
        /// <summary>选项态：草案确认轮的最后一条 add 上，输入条换成「我接了/我不接」两行选项 + 单行输入。</summary>
        private bool _askAccept;
        /// <summary>本轮 done 已到：不会再有新台词，用于「没有结束语时最后一条 add」的判定。</summary>
        private bool _turnLinesDone;
        /// <summary>当前上屏行的 SSE kind（add/closing，原作/占位为 null）。
        /// 必须在 _insertedLines 摘除当前行前记下，否则补判时查不到。</summary>
        private string _presentedLineKind;
        /// <summary>本轮收到过过渡话（line.interim=true）。daily 组派活时后端不推 plan
        /// （orchestrator 只在 mode=="task" 推），过渡话是日常组唯一的草案信号。</summary>
        private bool _sawInterim;
        /// <summary>本轮收到过 status(stage=drafting)：任务草案工具轮的唯一阶段，
        /// daily 组派活时最早、最可靠的信号。</summary>
        private bool _sawDrafting;
        /// <summary>当前上屏行本身是不是过渡话：过渡话不能当「最后一条 add」弹选项。</summary>
        private bool _presentedLineInterim;
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
        /// <summary>本轮最近一次阶段状态文案；空＝尚无状态，占位显示默认「思索中」。</summary>
        private string _turnStatusText;
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

        /// <summary>选项态切换（订阅方据此在「三行选项」与普通输入条之间换布局）。</summary>
        internal event Action<bool> AskAcceptChanged;

        /// <summary>待处理索取视图变化（null＝清空）：订阅方据此显示两按钮＋原输入框。</summary>
        internal event Action<DialogueInterjectItemClaimView> ItemClaimChanged;

        /// <summary>当前是否应显示「我接了/我不接」选项行（草案确认轮的最后一条 add）。</summary>
        internal bool AskAccept { get { return _askAccept; } }

        /// <summary>从插话处启动终端后模型配置缺失：请宿主自动弹出配置小窗。</summary>
        internal event Action ConfigRequired;

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
            Func<DateTime> clock = null,
            Func<bool> terminalReady = null,
            Func<Task<bool>> llmConfigured = null,
            Func<string, Task> ensureBound = null,
            NpcItemExchangeTask itemExchange = null)
        {
            _task = task ?? throw new ArgumentNullException(nameof(task));
            _widget = widget ?? throw new ArgumentNullException(nameof(widget));
            _dispatch = dispatch ?? throw new ArgumentNullException(nameof(dispatch));
            _ensureReady = ensureReady;
            _ensureBound = ensureBound;
            _transportFactory = transportFactory ?? throw new ArgumentNullException(nameof(transportFactory));
            _newId = newId ?? (() => Guid.NewGuid().ToString("D"));
            _clock = clock ?? (() => DateTime.Now);
            _terminalReady = terminalReady;
            _llmConfigured = llmConfigured;
            _itemExchange = itemExchange;
        }

        internal DialogueInterjectInputState InputState { get { return _inputState; } }
        internal bool IsTurnActive { get { return _turnActive; } }
        internal int PendingLineCount { get { return _queued.Count; } }
        internal string DialogueInstanceId { get { return _dialogueInstanceId; } }
        internal string CurrentTurnId { get { return _turnId; } }
        internal int PlayedCount { get { return _played.Count; } }
        internal NativeDialogueBookSession SessionForTest { get { return _session; } }
        internal bool ClosingForTest { get { return _closing; } }
        internal JObject PendingItemClaimForTest { get { return _pendingItemClaim; } }
        internal DialogueInterjectItemClaimView ItemClaimViewForTest { get { return _itemClaimView; } }
        internal IList<string> PlayerItemNamesForTest
        {
            get { return _playerItemNames != null ? (IList<string>)_playerItemNames : new string[0]; }
        }

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
            _taskMode = session.Mode == "ordinary"
                && (string.Equals(session.DialogueKind, KindTaskPre, StringComparison.Ordinal)
                    || string.Equals(session.DialogueKind, KindTaskPost, StringComparison.Ordinal));
            _taskContext = null;
            _muted = false;
            _needsConfig = false;
            _configProbeInFlight = false;
            _pendingPlan = null;
            _planApplied = false;
            _abandonedOriginalTail = false;
            _appliedRemoves.Clear();
            // 跨组不得沿用上一组的索取按钮：先显式清视图，再重置本地状态。
            ClearItemClaim();
            _itemDecisionBusy = false;
            _playerItemNames = null;
            _playerNamesGeneration++;
            _taskActionSent = false;
            _unackedItemAction = null;
            _itemActionRetriedId = null;
            _executedGrants.Clear();
            if (_taskMode)
            {
                // 任务组门控（协议 4.1）：provider 拿到 task_context 才开放，否则 fail-closed。
                _taskContext = BuildTaskContext(session);
                _groupAllowsInterject = _taskContext != null;
            }
            _dialogueInstanceId = null;      // 首次插入才建（D-04 / 6.1）
            _npcName = null;
            lock (_playedGate) { _played.Clear(); _nextSeq = 0; }
            _queued.Clear();
            _insertedLines.Clear();
            _aiLineShown = false;
            _lastAiLineInterim = false;
            SetAskAccept(false);
            _turnLinesDone = false;
            _presentedLineKind = null;
            _presentedLineInterim = false;
            _sawInterim = false;
            _sawDrafting = false;
            _turnActive = false;
            _turnTailIndex = -1;
            _pcRevision = -1;
            _finalizePending = false;
            _resumeAfterFailure = false;
            _preparing = false;
            _turnStatusText = null;
            _playerLineOnScreen = false;
            DisarmWatchdog();
            session.LinePresented = OnLinePresented;
            session.Closing = OnSessionClosing;
            session.EndHoldLineProvider = BuildEndHoldLine;
            // 组刚开始还没有任何台词上屏：不能是 Ready（等 Begin 呈现第一句再开）。
            SetInputState(DialogueInterjectInputState.Hidden);
            // 终端已经在线时也核对一次配置（不自动弹窗；输入条会显示“请配置模型API”）。
            if (_terminalReady != null && _terminalReady()) ProbeLlmConfig(false);
            // 组开始刷新玩家持有名快照：后端索取池只按名字建池，不查背包实例。
            RefreshPlayerItemNames();
        }

        private void OnSessionEnded(NativeDialogueBookSession session)
        {
            if (!ReferenceEquals(session, _session)) return;
            CancelTurn("session_end");
            session.LinePresented = null;
            session.Closing = null;
            session.EndHoldLineProvider = null;
            _session = null;
            _groupAllowsInterject = false;
            _closing = false;
            _dialogueInstanceId = null;
            _npcName = null;
            _preparing = false;
            _turnStatusText = null;
            _taskMode = false;
            _taskContext = null;
            _muted = false;
            _needsConfig = false;
            _configProbeInFlight = false;
            _pendingPlan = null;
            _planApplied = false;
            _abandonedOriginalTail = false;
            _appliedRemoves.Clear();
            _playerLineOnScreen = false;
            _lastAiLineInterim = false;
            SetAskAccept(false);
            ClearItemClaim();
            _playerItemNames = null;
            _playerNamesGeneration++;
            _taskActionSent = false;
            _unackedItemAction = null;
            _itemActionRetriedId = null;
            _executedGrants.Clear();
            _turnLinesDone = false;
            _presentedLineKind = null;
            _presentedLineInterim = false;
            _sawInterim = false;
            _sawDrafting = false;
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
            _turnStatusText = null;
            _muted = false;
            _needsConfig = false;
            _pendingPlan = null;
            _finalizePending = false;
            _resumeAfterFailure = false;
            _queued.Clear();
            _insertedLines.Clear();
            _turnTailIndex = -1;
            _playerLinePlaying = false;
            _playerLineOnScreen = false;
            _lastAiLineInterim = false;
            SetAskAccept(false);
            ClearItemClaim();
            _unackedItemAction = null;
            _itemActionRetriedId = null;
            _turnLinesDone = false;
            _presentedLineKind = null;
            _presentedLineInterim = false;
            _sawInterim = false;
            _sawDrafting = false;
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

        /// <summary>
        /// 组开始取一次任务上下文（协议 4.2）：provider 未注册、抛错或返回 null 都按
        /// 不可插话处理（fail-closed，输入保持 Hidden，不显示也不报错）。
        /// </summary>
        private JObject BuildTaskContext(NativeDialogueBookSession session)
        {
            string taskId = session.DialogueTaskId;
            if (string.IsNullOrEmpty(taskId)) return null;
            Func<string, string, JObject> provider = _task != null ? _task.TaskContextProvider : null;
            if (provider == null) return null;
            try
            {
                return provider(taskId, session.DialogueKind);
            }
            catch (Exception ex)
            {
                LogManager.Log("[DialogueInterject] task_context build failed: " + ex.Message);
                return null;
            }
        }

        private void OnLinePresented(NativeDialogueBookSession.Line line)
        {
            if (_session == null || line == null) return;
            if (line.IsPlaceholder)
            {
                // 等待模型返回：不记入转录、不推进说话人；输入保持“准备中/等待”。
                _playerLineOnScreen = false;
                SetInputState(IdleState());
                return;
            }
            string name = line.Name ?? "";
            bool isPc = line.IsPlayer || string.Equals(name, PcName, StringComparison.Ordinal);
            bool isLocal = line.WireIndex < 0;
            // 任务改写行占用原始行号（WireIndex>=0），但它是 Host 生成的内容：
            // 角色仍按原说话人记（协议 6.2），输入状态与拆分暂锁按“生成行”处理。
            InsertedRef inserted;
            _insertedLines.TryGetValue(line, out inserted);
            // 下面 Remove 之后查不到当前行了：kind 先记到字段，供选项态补判使用。
            _presentedLineKind = inserted != null && inserted.Line != null
                ? inserted.Line.Kind : null;
            _presentedLineInterim = inserted != null && inserted.Line != null
                && inserted.Line.Interim;
            bool isEdit = inserted != null && inserted.TaskIndex > 0;
            bool isGenerated = isLocal || isEdit;

            // 主 NPC 取本组第一个说话人；第三方插话不得改写下一次请求的 npc。
            if (!isPc && name.Length > 0 && string.IsNullOrEmpty(_npcName)) _npcName = name;

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
                _playerLineOnScreen = true;
                SetInputState(DialogueInterjectInputState.Hidden);
                return;
            }
            _playerLineOnScreen = false;
            // 选项态：本条上屏后重算。当前行马上会被摘出 _insertedLines，kind 已在上面存好。
            RefreshAskAccept(line, _presentedLineKind);
            if (isLocal) _aiLineShown = true;
            if (isEdit) _aiLineShown = true;
            if (!_groupAllowsInterject) return;
            if (_muted)
            {
                // 禁言是任务模式唯一整组锁：add/plan/原文照常播放，输入禁用。
                SetInputState(DialogueInterjectInputState.Muted);
                return;
            }
            if (isGenerated)
            {
                // 拆分前置段：输入暂锁；末段/自然单条：开始显示即可输入（§3.3）。
                SetInputState(line.SplitIntermediate
                    ? DialogueInterjectInputState.Locked
                    : ReadyOrMuted());
                return;
            }
            // 原作台词：可输入（stage / 任务组已在 IsGroupAllowsInterject 拦掉）
            SetInputState(ReadyOrMuted());
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
                if (PlayLine(next, AdvanceFirstLineNow()))
                {
                    // 首句已上屏：其余已收台词按顺序接在它后面，玩家点“下一条”逐句看。
                    DrainQueueToTail();
                    // add 全部落完：迟到的 plan 在这里一次性应用（§4.5）。
                    TryApplyPendingPlan();
                    FlushPendingFinalize();
                    FlushResumeAfterFailure();
                    return;
                }
            }
            // 没有排队的台词可放：换句时机已就绪，迟到的 plan 现在应用。
            TryApplyPendingPlan();
            // plan 应用完成：按"成功"解锁输入（协议 4.5 / F-08），不等下一句上屏。
            // 不看组类型——日常组里派活同样会走草案 plan。
            if (_planApplied) SetInputState(ReadyOrMuted());
            else SetInputState(IdleState());
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

            // played 只取本轮发送之前的已播历史（不含本轮 $PC）；下一轮 remaining 从当前播放点之后起算。
            List<PlayedRow> playedSnapshot;
            lock (_playedGate) { playedSnapshot = new List<PlayedRow>(_played); }
            int wireResume = _session.CurrentWireIndex + 1;

            // 协议 4.3 / 4.6：上一轮未播的新增/结束语/改写/移除转成本轮参考续写
            // （含已插入未走到的行；下标按下一轮 remaining 的 1..N 计算）。
            List<ReferenceItem> unplayed = CollectUnplayedTurnLines(wireResume);

            // 一轮在途时再次发送：真取消在途流（Dispose 流 + token），已收内容已在上面的 unplayed 里。
            StopStream();
            _turnActive = false;
            _finalizePending = false;
            _resumeAfterFailure = false;
            // 已收未应用的 plan 不应用（意图已转参考）；本轮 plan 状态重新计数。
            _pendingPlan = null;
            _planApplied = false;
            // 选项态只属于上一轮的最后一条 add：发送即收掉，新的回复按新轮重新判定。
            SetAskAccept(false);
            _taskActionSent = false;
            _unackedItemAction = null;
            _turnLinesDone = false;
            _presentedLineKind = null;
            _presentedLineInterim = false;
            _sawInterim = false;
            _sawDrafting = false;
            _appliedRemoves.RemoveAll(wire => wire < wireResume);

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
            _lastAiLineInterim = false;
            SetAskAccept(false);
            _turnLinesDone = false;
            _presentedLineKind = null;
            _presentedLineInterim = false;
            _sawInterim = false;
            _sawDrafting = false;
            _preparing = false;
            _turnStatusText = null;
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
        /// 收集"本轮已收到但没播"的参考续写：
        /// - 排队中的 add/closing；
        /// - 已插进播放序列但当前还没走到的 add（TaskIndex=0）或改写（TaskIndex=n）；
        /// - 已应用但播放进度还没越过的 remove；
        /// - 已收未应用的 plan 里的 edit/remove（按下一轮 remaining 的 1..N 折算）。
        /// 无 end 的整组替换模式（_abandonedOriginalTail）下原编号已不存在：edit/remove 记录后丢弃。
        /// </summary>
        private List<ReferenceItem> CollectUnplayedTurnLines(int nextWireStart)
        {
            var unplayed = new List<ReferenceItem>();
            while (_queued.Count > 0)
            {
                DialogueInterjectLine queued = _queued.Dequeue();
                unplayed.Add(new ReferenceItem { Kind = RefKindOf(queued), Line = queued });
            }
            if (_session == null) return unplayed;

            int dropped = 0;
            for (int i = _session.Index + 1; i < _session.PlaybackCount; i++)
            {
                NativeDialogueBookSession.Line line = _session.GetPlaybackLine(i);
                if (line == null) continue;
                InsertedRef inserted;
                if (!_insertedLines.TryGetValue(line, out inserted) || inserted.Line == null) continue;
                if (inserted.TaskIndex > 0)
                {
                    if (_abandonedOriginalTail) { dropped++; continue; }
                    int index = inserted.WireIndex - nextWireStart + 1;
                    if (index < 1) { dropped++; continue; }
                    unplayed.Add(new ReferenceItem
                    {
                        Kind = "edit", Index = index, Line = inserted.Line
                    });
                    continue;
                }
                unplayed.Add(new ReferenceItem { Kind = RefKindOf(inserted.Line), Line = inserted.Line });
            }

            for (int i = 0; i < _appliedRemoves.Count; i++)
            {
                int wire = _appliedRemoves[i];
                if (_abandonedOriginalTail) { dropped++; continue; }
                int index = wire - nextWireStart + 1;
                if (index < 1) continue;      // 已越过：remove 已经生效，不再参考
                unplayed.Add(new ReferenceItem { Kind = "remove", Index = index });
            }

            if (_pendingPlan != null) AppendPendingPlanReferences(unplayed, nextWireStart);

            if (dropped > 0)
                LogManager.Log("[DialogueInterject] dropped " + dropped
                    + " reference items (index no longer in remaining)");
            return unplayed;
        }

        /// <summary>已收未应用的 plan：不应用，edit/remove 按下一轮 remaining 编号转参考。</summary>
        private void AppendPendingPlanReferences(List<ReferenceItem> unplayed, int nextWireStart)
        {
            foreach (KeyValuePair<int, TaskEdit> pair in _pendingPlan.Edits)
            {
                int wire = _wireResume + pair.Key - 1;
                int index = wire - nextWireStart + 1;
                if (index < 1) continue;
                TaskEdit edit = pair.Value;
                if (string.Equals(edit.Kind, "remove", StringComparison.Ordinal))
                {
                    unplayed.Add(new ReferenceItem { Kind = "remove", Index = index });
                    continue;
                }
                if (!string.Equals(edit.Kind, "edit", StringComparison.Ordinal)) continue;
                for (int i = 0; i < edit.Lines.Count; i++)
                    unplayed.Add(new ReferenceItem { Kind = "edit", Index = index, Line = edit.Lines[i] });
            }
        }

        private static string RefKindOf(DialogueInterjectLine line)
        {
            return line != null && string.Equals(line.Kind, "closing", StringComparison.Ordinal)
                ? "closing" : "add";
        }

        private JArray BuildRemaining(int fromWire)
        {
            var remaining = new JArray();
            // 无 end 的整组替换：原始剩余视为已放弃，下一轮 remaining 为空（协议 4.5）。
            if (_abandonedOriginalTail) return remaining;
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

        /// <summary>参考续写 → 协议 5.1 的 reference_continuation（add/closing/edit/remove）。</summary>
        private JArray BuildReference(List<ReferenceItem> unplayed)
        {
            var reference = new JArray();
            if (unplayed == null) return reference;
            for (int i = 0; i < unplayed.Count; i++)
            {
                ReferenceItem item = unplayed[i];
                if (item == null) continue;
                if (string.Equals(item.Kind, "remove", StringComparison.Ordinal))
                {
                    reference.Add(new JObject { ["kind"] = "remove", ["index"] = item.Index });
                    continue;
                }
                DialogueInterjectLine line = item.Line;
                if (line == null || string.IsNullOrEmpty(line.Text)) continue;
                var entry = new JObject
                {
                    ["kind"] = item.Kind,
                    ["name"] = string.IsNullOrEmpty(line.Speaker) ? (_npcName ?? "") : line.Speaker,
                    ["text"] = line.Text,
                    ["emotion"] = string.IsNullOrEmpty(line.Emotion) ? DefaultEmotion : line.Emotion
                };
                if (string.Equals(item.Kind, "edit", StringComparison.Ordinal))
                    entry["index"] = item.Index;
                reference.Add(entry);
            }
            return reference;
        }

        private string BuildRequest(string playerInput, string npc, string dialogueInstanceId,
            string turnId, List<PlayedRow> played, JArray remaining, List<ReferenceItem> unplayed,
            JObject action = null)
        {
            var playedArray = new JArray();
            foreach (PlayedRow row in played) playedArray.Add(row.ToJson());
            string kind = _session.DialogueKind;
            string time = _clock().ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
            string sessionTitle = _taskMode
                ? "任务插话 · " + TaskTitle() + " · "
                    + (string.Equals(kind, KindTaskPre, StringComparison.Ordinal) ? "任务前" : "任务后")
                    + " · " + time
                : "日常插话 · " + npc + " · " + time;
            var request = new JObject
            {
                ["mode"] = _taskMode ? "task" : "daily",
                ["dialogue_instance_id"] = dialogueInstanceId,
                ["turn_id"] = turnId,
                ["npc"] = npc,
                ["player_input"] = playerInput,
                ["session_title"] = sessionTitle,
                ["dialogue"] = new JObject
                {
                    ["kind"] = kind,
                    ["group_id"] = _session.RequestId,
                    ["played"] = playedArray,
                    ["remaining"] = remaining,
                    ["reference_continuation"] = BuildReference(unplayed)
                },
                ["task_context"] = _taskMode && _taskContext != null
                    ? (JToken)_taskContext.DeepClone() : (JToken)JValue.CreateNull(),
                ["limits"] = new JObject
                {
                    ["line_hard_max"] = LineHardMax,
                    ["line_prompt_max"] = LinePromptMax
                }
            };
            if (action != null) request["action"] = action;
            if (!_taskMode && _playerItemNames != null)
            {
                var names = new JArray();
                for (int i = 0; i < _playerItemNames.Count; i++) names.Add(_playerItemNames[i]);
                request["player_item_names"] = names;
            }
            return request.ToString(Formatting.None);
        }

        /// <summary>任务名（session_title 用）：取本组在 task_context 里的那一段标题。</summary>
        private string TaskTitle()
        {
            if (_taskContext != null && _session != null)
            {
                JObject segment = (string.Equals(_session.DialogueKind, KindTaskPre, StringComparison.Ordinal)
                    ? _taskContext["upcoming"] : _taskContext["completed"]) as JObject;
                string title = segment != null ? (segment.Value<string>("title") ?? "").Trim() : "";
                if (title.Length > 0) return title;
            }
            return _npcName ?? "";
        }

        /// <summary>$PC 行：优先复用本组原作的玩家行；没有时用 book 快照还原
        /// 玩家名/头衔/纸娃娃立绘。两者都缺才退回无立绘，绝不把 "$PC" 原样上屏。</summary>
        private NativeDialogueBookSession.Line BuildPcLine(string text)
        {
            string playerName = _session.PlayerName ?? "";
            NativeDialogueBookSession.Line template = null;
            for (int wire = 0; wire < _session.RowCount; wire++)
            {
                NativeDialogueBookSession.Line row = _session.GetWireRow(wire);
                if (row == null) continue;
                if (row.IsPlayer
                    || (playerName.Length > 0 && string.Equals(row.Name, playerName, StringComparison.Ordinal))
                    || string.Equals(row.Name, PcName, StringComparison.Ordinal))
                    template = row;
            }
            if (template != null)
            {
                return new NativeDialogueBookSession.Line
                {
                    Name = string.Equals(template.Name, PcName, StringComparison.Ordinal)
                        && playerName.Length > 0 ? playerName : template.Name,
                    Title = string.Equals(template.Title, "$PC_TITLE", StringComparison.Ordinal)
                        ? (_session.HeroTitle ?? "") : template.Title,
                    Text = text,
                    PortraitKey = template.PortraitKey,
                    Expression = template.Expression,
                    IsDoll = template.IsDoll,
                    Appearance = template.Appearance,
                    NormalizedAppearance = template.NormalizedAppearance,
                    AppearanceIdentity = template.AppearanceIdentity,
                    ImageAction = "keep",
                    ImagePath = "",
                    IsPlayer = true
                };
            }

            var line = new NativeDialogueBookSession.Line
            {
                Name = playerName.Length > 0 ? playerName : PcName,
                Title = _session.HeroTitle ?? "",
                Text = text,
                PortraitKey = playerName,
                Expression = DefaultEmotion,
                ImageAction = "keep",
                ImagePath = "",
                IsPlayer = true
            };
            JObject hero = _session.HeroPortrait;
            if (hero != null)
            {
                string kind = hero.Value<string>("kind") ?? "";
                string expression = hero.Value<string>("expression");
                if (!string.IsNullOrEmpty(expression)) line.Expression = expression;
                string key = hero.Value<string>("key");
                if (!string.IsNullOrEmpty(key)) line.PortraitKey = key;
                if (string.Equals(kind, "doll", StringComparison.Ordinal))
                {
                    JObject appearance = hero["appearance"] as JObject;
                    JObject normalized = appearance != null
                        ? CF7Launcher.Guardian.Dialogue.DialoguePortraitService
                            .NormalizeAppearance(appearance)
                        : null;
                    if (normalized != null)
                    {
                        line.IsDoll = true;
                        line.Appearance = appearance;
                        line.NormalizedAppearance = normalized;
                        line.AppearanceIdentity = normalized.ToString(Formatting.None);
                    }
                }
            }
            return line;
        }

        /// <summary>本组 NPC 模板行：优先当前原始行及之前的最近一句，否则向后找第一句；
        /// 插话新增行与占位行据此继承立绘/外观，避免 AI 行落到无立绘空槽。</summary>
        private NativeDialogueBookSession.Line FindNpcTemplate()
        {
            if (_session == null) return null;
            int wire = Math.Min(_session.CurrentWireIndex, _session.RowCount - 1);
            for (int i = wire; i >= 0; i--)
            {
                NativeDialogueBookSession.Line row = _session.GetWireRow(i);
                if (row != null && !row.IsPlayer) return row;
            }
            for (int i = Math.Max(0, wire + 1); i < _session.RowCount; i++)
            {
                NativeDialogueBookSession.Line row = _session.GetWireRow(i);
                if (row != null && !row.IsPlayer) return row;
            }
            return null;
        }

        /// <summary>玩家在末行继续点“下一条”且本轮仍在等模型：返回「思索中……」占位。
        /// 过渡话之后、最终确认对话尚未到达时同样占位（显示最新 ui_hint）；
        /// 占位只追加到播放序列尾部，下一句到达时从同一位置原位替换；不进转录。</summary>
        private NativeDialogueBookSession.Line BuildEndHoldLine()
        {
            if (_session == null || _closing) return null;
            if (!_turnActive && !_finalizePending && !_preparing) return null;
            // 已有普通 AI 行可播时按原语义直接收组；只有过渡话之后才继续等最终确认。
            if (_aiLineShown && !_lastAiLineInterim) return null;
            NativeDialogueBookSession.Line template = FindNpcTemplate();
            return new NativeDialogueBookSession.Line
            {
                Name = template != null ? template.Name : (_npcName ?? ""),
                Title = template != null ? template.Title : "",
                Text = string.IsNullOrEmpty(_turnStatusText) ? "思索中……" : _turnStatusText,
                PortraitKey = template != null ? template.PortraitKey : "",
                Expression = template != null && !string.IsNullOrEmpty(template.Expression)
                    ? template.Expression : DefaultEmotion,
                IsDoll = template != null && template.IsDoll,
                Appearance = template != null ? template.Appearance : null,
                NormalizedAppearance = template != null ? template.NormalizedAppearance : null,
                AppearanceIdentity = template != null ? template.AppearanceIdentity : null,
                ImageAction = "keep",
                ImagePath = "",
                IsPlaceholder = true
            };
        }

        /// <summary>AI 首行到达时是否立即切到它：玩家已点在占位条上 → 是；
        /// 玩家还停在 $PC → 只原位放入下一行，等玩家自己点过去。</summary>
        private bool AdvanceFirstLineNow()
        {
            if (_session == null || _turnTailIndex < 0) return true;
            return _session.Index >= _turnTailIndex;
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
            string playerName = _session != null ? _session.PlayerName : "";
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
                    // 终端就绪后再补一次存档绑定：后端提示词据此拿到玩家名/场景/进度，
                    // 本组 session 也才会带上当前 slot_key 并出现在终端会话列表。
                    if (_ensureBound != null)
                    {
                        try { await _ensureBound(playerName).ConfigureAwait(false); }
                        catch (Exception ex)
                        {
                            LogManager.Log("[DialogueInterject] bind context failed (ignored): " + ex.Message);
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

        /// <summary>SSE 事件（已在 dispatch 队列上）：消费 status / mute / line / plan / done / error。
        /// internal 也作为单测的中途事件驱动点。</summary>
        internal void OnEvent(DialogueInterjectEvent evt)
        {
            if (evt == null) return;
            NoteWatchdogActivity();
            switch (evt.Kind)
            {
                case DialogueInterjectEventKind.Status:
                    ApplyStatus(evt);
                    break;
                case DialogueInterjectEventKind.Mute:
                    ApplyMute(evt);
                    break;
                case DialogueInterjectEventKind.Line:
                    AcceptLine(DialogueInterjectLine.FromEvent(evt));
                    break;
                case DialogueInterjectEventKind.Plan:
                    AcceptPlan(evt);
                    break;
                case DialogueInterjectEventKind.Action:
                    AcceptItemGrantAction(evt);
                    break;
                case DialogueInterjectEventKind.ItemClaim:
                    AcceptItemClaim(evt);
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
        /// status（协议 5.2，可选）：已知 stage 一律刷新等待占位文案（[思考中]/[查资料中]…）；
        /// drafting/searching 另外表示草案/检索准备中 → 输入显示但禁用“（正在准备…）”。
        /// line/done/error 由各自路径清掉该标记并回到既有状态；其余 stage 不改输入态。
        /// </summary>
        private void ApplyStatus(DialogueInterjectEvent evt)
        {
            if (!_turnActive || _closing) return;
            string stage = evt.Text("stage");
            string hint = (evt.Text("ui_hint") ?? "").Trim();
            // drafting 只在任务草案工具轮发（route_task_draft/update/confirm/cancel），
            // 是 daily 组「刚派过活」的确定信号——比过渡话更早，且不受其生成超时影响。
            if (string.Equals(stage, "drafting", StringComparison.Ordinal)) _sawDrafting = true;
            string label = hint.Length > 0 ? hint : StatusLabel(stage);
            if (label.Length > 0)
            {
                _turnStatusText = label;
                // 占位可能已经上屏：原位换文案；还没上屏时由 BuildEndHoldLine 取同一份。
                if (_session != null) _session.UpdatePlaceholderText(label);
            }
            if (!_groupAllowsInterject) return;
            if (_muted) return;               // 禁言优先于“正在准备…”，不覆盖整组锁
            if (!string.Equals(stage, "drafting", StringComparison.Ordinal)
                && !string.Equals(stage, "searching", StringComparison.Ordinal)) return;
            _preparing = true;
            if (_playerLinePlaying) return;   // $PC 播放期间保持 Hidden，播完再显示“正在准备…”
            SetInputState(DialogueInterjectInputState.Preparing);
        }

        /// <summary>status.stage → 占位文案；与终端阶段用词保持一致。</summary>
        private static string StatusLabel(string stage)
        {
            switch (stage)
            {
                case "connecting": return "连接中";
                case "thinking": return "思考中";
                case "searching": return "查资料中";
                case "drafting": return "拟定委托中";
                // 确认/取消草案（route_task_confirm / route_task_cancel）：已经在派发，不再拟稿。
                case "publishing": return "派发委托中";
                case "waiting": return "等待中";
                default: return "";
            }
        }

        // ════════════════ 任务模式：mute / plan ════════════════

        /// <summary>mute 事件（协议 4.7 / F-09）：本组输入禁用；add/plan 照常播放。</summary>
        private void ApplyMute(DialogueInterjectEvent evt)
        {
            if (!_taskMode || _closing || _session == null) return;
            bool mute = evt.Data != null && evt.Data.Value<bool?>("mute").GetValueOrDefault(false);
            if (!mute) return;
            SetMuted();
        }

        private void SetMuted()
        {
            if (_muted) return;
            _muted = true;
            if (_playerLinePlaying || !_groupAllowsInterject) return;   // $PC 播放期间保持 Hidden
            SetInputState(DialogueInterjectInputState.Muted);
        }

        private DialogueInterjectInputState ReadyOrMuted()
        {
            if (_muted) return DialogueInterjectInputState.Muted;
            if (TerminalOffline()) return DialogueInterjectInputState.Offline;
            if (_needsConfig) return DialogueInterjectInputState.NeedsConfig;
            return DialogueInterjectInputState.Ready;
        }

        private bool TerminalOffline()
        {
            return _terminalStarting || (_terminalReady != null && !_terminalReady());
        }

        /// <summary>没有可放台词时的落点：禁言 &gt; 终端未启动 &gt; 模型未配置 &gt; 准备中 &gt; 等待。</summary>
        private DialogueInterjectInputState IdleState()
        {
            if (_muted) return DialogueInterjectInputState.Muted;
            if (TerminalOffline()) return DialogueInterjectInputState.Offline;
            if (_needsConfig) return DialogueInterjectInputState.NeedsConfig;
            return _preparing
                ? DialogueInterjectInputState.Preparing
                : DialogueInterjectInputState.Locked;
        }

        /// <summary>收起条文案：禁言/终端未启动/模型未配置由这里给出。</summary>
        internal string PlaceholderFor(DialogueInterjectInputState state)
        {
            if (state == DialogueInterjectInputState.Offline)
                return _terminalStartFailed
                    ? "聊天终端启动失败，点击重试" : "请先启动聊天终端";
            if (state == DialogueInterjectInputState.NeedsConfig) return "请配置模型API";
            if (state != DialogueInterjectInputState.Muted) return null;
            string npc = string.IsNullOrEmpty(_npcName) ? "" : _npcName;
            return "（" + npc + "）暂时不打算让你插话";
        }

        /// <summary>玩家点击收起条“启动”：拉起终端并核对模型配置，不发送任何输入。</summary>
        internal void RequestTerminalStart()
        {
            if (_terminalStarting || _ensureReady == null) return;
            if (_session == null || _closing) return;
            _terminalStarting = true;
            _terminalStartFailed = false;
            if (_inputState == DialogueInterjectInputState.Offline)
            {
                // 已在 Offline 时强制刷新一次提示文案（启动中视同可重试）。
                _inputState = DialogueInterjectInputState.Hidden;
                SetInputState(DialogueInterjectInputState.Offline);
            }
            TaskRunner(async () =>
            {
                bool ok = false;
                bool configured = true;
                try { ok = await _ensureReady().ConfigureAwait(false); }
                catch (Exception ex) { LogManager.Log("[DialogueInterject] terminal start: " + ex.Message); }
                if (ok && _llmConfigured != null)
                {
                    try { configured = await _llmConfigured().ConfigureAwait(false); }
                    catch (Exception ex)
                    {
                        // 探测失败按已配置处理：不因配置端点异常把输入永久锁死。
                        LogManager.Log("[DialogueInterject] llm config probe: " + ex.Message);
                    }
                }
                Post(() =>
                {
                    _terminalStarting = false;
                    _terminalStartFailed = !ok;
                    if (_session == null || _closing) return;
                    if (!ok)
                    {
                        _inputState = DialogueInterjectInputState.Hidden;
                        SetInputState(DialogueInterjectInputState.Offline);
                        return;
                    }
                    _needsConfig = !configured;
                    if (_needsConfig)
                    {
                        // 手动启动路径已经直接弹了小窗，不再让后续探测重复自动拉。
                        _autoConfigSyncTried = true;
                        if (_groupAllowsInterject && !_playerLinePlaying)
                            SetInputState(ReadyOrMuted());
                        RaiseConfigRequired();
                        return;
                    }
                    SetInputState(ReadyOrMuted());
                });
            });
        }

        /// <summary>终端就绪态变化或面板展开：把停在 Offline 的输入条按当前真实状态重算。</summary>
        internal void RefreshTerminalState()
        {
            if (_session == null || _closing || _terminalStarting) return;
            if (!_groupAllowsInterject || _playerLinePlaying) return;
            if (_terminalReady == null) return;
            if (!_terminalReady())
            {
                _autoConfigSyncTried = false;
                if (_inputState == DialogueInterjectInputState.Offline) return;
                SetInputState(DialogueInterjectInputState.Offline);
                return;
            }
            if (_inputState == DialogueInterjectInputState.NeedsConfig)
            {
                // 展开/就绪变化时重探：终端页或配置小窗可能刚把 localStorage 配置同步到后端。
                ProbeLlmConfig(false);
                return;
            }
            if (_inputState != DialogueInterjectInputState.Offline) return;
            _autoConfigSyncTried = false;
            SetInputState(ReadyOrMuted());
            ProbeLlmConfig(false);
        }

        /// <summary>终端已在线时的配置核对（不弹窗）：缺配置则输入条显示“请配置模型API”。</summary>
        private void ProbeLlmConfig(bool openDialogOnMissing)
        {
            if (_llmConfigured == null || _configProbeInFlight) return;
            _configProbeInFlight = true;
            TaskRunner(async () =>
            {
                bool configured = true;
                try { configured = await _llmConfigured().ConfigureAwait(false); }
                catch (Exception ex)
                {
                    LogManager.Log("[DialogueInterject] llm config probe: " + ex.Message);
                }
                Post(() =>
                {
                    _configProbeInFlight = false;
                    if (_session == null || _closing) return;
                    _needsConfig = !configured;
                    if (TerminalOffline()) return;
                    if (!_needsConfig)
                    {
                        if (_inputState == DialogueInterjectInputState.NeedsConfig)
                            SetInputState(ReadyOrMuted());
                        return;
                    }
                    // 后端内存配置在 exe 重启后会清空；首次缺配置时自动拉一次小窗，
                    // 由小窗把 localStorage 里的旧配置同步回来（已有配置＝屏外关闭并解锁）。
                    bool autoSync = !_autoConfigSyncTried;
                    if (autoSync) _autoConfigSyncTried = true;
                    if (_groupAllowsInterject && !_playerLinePlaying
                        && _inputState != DialogueInterjectInputState.Muted)
                        SetInputState(DialogueInterjectInputState.NeedsConfig);
                    if (openDialogOnMissing || autoSync) RaiseConfigRequired();
                });
            });
        }

        /// <summary>配置小窗保存成功：立即解锁本组输入（若正在播放玩家台词则不抢先显示）。</summary>
        internal void NotifyLlmConfigSaved()
        {
            _needsConfig = false;
            if (_session == null || _closing) return;
            if (TerminalOffline() || _playerLinePlaying) return;
            SetInputState(ReadyOrMuted());
        }

        private void RaiseConfigRequired()
        {
            Action handler = ConfigRequired;
            if (handler == null) return;
            try { handler(); }
            catch (Exception ex) { LogManager.Log("[DialogueInterject] config dialog: " + ex.Message); }
        }

        /// <summary>plan 事件（协议 5.2）：先存；add 全部落完时一次性应用（§4.5）。</summary>
        private void AcceptPlan(DialogueInterjectEvent evt)
        {
            // 不再按组类型拦 plan：日常对话里也能派活（route_task_draft 在日常工具表里），
            // 草案那一轮可能仍是 daily 组。plan 只在草案期间由后端主动推送，收到即应用。
            if (!_turnActive || _closing || _session == null) return;
            if (_planApplied) return;
            TaskPlan plan = ParsePlan(evt);
            if (plan == null) return;
            LogManager.Log("[DialogueInterject] plan received taskMode=" + _taskMode
                + " kind=" + (_session != null ? _session.DialogueKind : "-")
                + " hasEnd=" + plan.HasEnd + " edits=" + plan.Edits.Count);
            if (plan.Mute) SetMuted();
            _pendingPlan = plan;
            TryApplyPendingPlan();
        }

        /// <summary>
        /// plan 解析（宽容）：end 只认整数；edits[] 只认 n ≥ 1 的 nochange/edit/remove；
        /// 同一 n 多条 edit 合并为一条拆成多条；非法条目忽略，不整段打回。
        /// </summary>
        private static TaskPlan ParsePlan(DialogueInterjectEvent evt)
        {
            JObject data = evt.Data;
            if (data == null) return null;
            var plan = new TaskPlan();
            JToken end = data["end"];
            if (end != null && end.Type == JTokenType.Integer)
            {
                plan.HasEnd = true;
                plan.End = end.Value<int>();
            }
            plan.Mute = data.Value<bool?>("mute").GetValueOrDefault(false);

            var edits = data["edits"] as JArray;
            if (edits == null) return plan;
            for (int i = 0; i < edits.Count; i++)
            {
                var entry = edits[i] as JObject;
                if (entry == null) continue;
                JToken nToken = entry["n"];
                if (nToken == null || nToken.Type != JTokenType.Integer) continue;
                int n = nToken.Value<int>();
                if (n < 1) continue;
                string kind = (entry.Value<string>("kind") ?? "").Trim();
                if (string.Equals(kind, "nochange", StringComparison.Ordinal))
                {
                    if (!plan.Edits.ContainsKey(n)) plan.Edits[n] = new TaskEdit { Kind = "nochange" };
                    continue;
                }
                if (string.Equals(kind, "remove", StringComparison.Ordinal))
                {
                    plan.Edits[n] = new TaskEdit { Kind = "remove" };
                    continue;
                }
                if (!string.Equals(kind, "edit", StringComparison.Ordinal)) continue;
                TaskEdit edit;
                if (!plan.Edits.TryGetValue(n, out edit)
                    || !string.Equals(edit.Kind, "edit", StringComparison.Ordinal))
                {
                    edit = new TaskEdit { Kind = "edit" };
                    plan.Edits[n] = edit;
                }
                var lines = entry["lines"] as JArray;
                if (lines == null) continue;
                for (int j = 0; j < lines.Count; j++)
                {
                    var lineObject = lines[j] as JObject;
                    if (lineObject == null) continue;
                    string text = (lineObject.Value<string>("text") ?? "").Trim();
                    if (text.Length == 0) continue;
                    var line = new DialogueInterjectLine
                    {
                        Kind = "edit",
                        Text = text,
                        Emotion = lineObject.Value<string>("emotion") ?? "",
                        Speaker = lineObject.Value<string>("speaker") ?? ""
                    };
                    var split = lineObject["split"] as JObject;
                    if (split != null)
                    {
                        JToken index = split["index"];
                        JToken count = split["count"];
                        if (index != null && index.Type == JTokenType.Integer)
                            line.SplitIndex = index.Value<int>();
                        if (count != null && count.Type == JTokenType.Integer
                            && count.Value<int>() > 0)
                            line.SplitCount = count.Value<int>();
                    }
                    edit.Lines.Add(line);
                }
            }
            return plan;
        }

        /// <summary>
        /// plan 应用时机：add 已全部进播放序列（$PC 播完、队列空）；否则先存，
        /// 等 OnTypingFinished / done 再应用。应用起点 = 新增段之后的第一条原始剩余。
        /// </summary>
        private bool TryApplyPendingPlan()
        {
            if (_pendingPlan == null || _planApplied) return false;
            // 不按组类型拦：日常对话里派活（route_task_draft）同样会推 plan。
            if (_session == null || _closing) return false;
            if (_playerLinePlaying || _queued.Count > 0) return false;
            if (_turnTailIndex < 0) return false;
            if (_session.State != NativeDialogueBookSession.HostState.Active) return false;
            TaskPlan plan = _pendingPlan;
            _pendingPlan = null;
            ApplyPlan(plan);
            return true;
        }

        /// <summary>
        /// 按 end/edits 构建后续（协议 4.5）：
        /// - end 存在：1..end-1 有 edit 用 edit、remove 跳过、其余原文；从 end 起接回原文；
        ///   end 指向被 remove 的条目时跳到下一条未移除原文；end 之后的编辑/移除忽略。
        /// - end 缺省：只用本轮 edit 构成剩余，不接回原文（原始剩余视为已放弃）。
        /// </summary>
        private void ApplyPlan(TaskPlan plan)
        {
            _planApplied = true;
            if (_abandonedOriginalTail)
            {
                // 上一轮已放弃原始剩余：本轮 n 没有对应原文可改，只保留已经播/排好的 add。
                _turnTailIndex = -1;
                RefreshAskAcceptCurrent();
                return;
            }
            int wireStart = _wireResume;
            int count = Math.Max(0, _session.RowCount - wireStart);
            int editLimit = count;
            int resumeN = 0;                        // 1-based；0 = 不接回原文
            bool hasEnd = plan.HasEnd && plan.End >= 1 && plan.End <= count;
            if (hasEnd)
            {
                editLimit = plan.End - 1;
                resumeN = plan.End;
            }

            var replacement = new List<NativeDialogueBookSession.Line>();
            var refs = new List<InsertedRef>();      // 与 replacement 一一对应；原文行 = null
            for (int n = 1; n <= editLimit; n++)
            {
                int wire = wireStart + n - 1;
                TaskEdit edit;
                if (plan.Edits.TryGetValue(n, out edit))
                {
                    if (string.Equals(edit.Kind, "remove", StringComparison.Ordinal))
                    {
                        AddAppliedRemove(wire);
                        continue;
                    }
                    if (string.Equals(edit.Kind, "edit", StringComparison.Ordinal)
                        && edit.Lines.Count > 0)
                    {
                        for (int i = 0; i < edit.Lines.Count; i++)
                        {
                            NativeDialogueBookSession.Line local = BuildEditedLine(edit.Lines[i], wire);
                            if (local == null) continue;
                            replacement.Add(local);
                            refs.Add(new InsertedRef
                            {
                                Line = edit.Lines[i], WireIndex = wire, TaskIndex = n
                            });
                        }
                        continue;
                    }
                    // nochange / edit 空行：按原文处理
                }
                if (resumeN == 0) continue;         // end 缺省：未改写的原文不再播放
                NativeDialogueBookSession.Line origin = _session.GetWireRow(wire);
                if (origin == null) continue;
                replacement.Add(origin);
                refs.Add(null);                     // 原文行不需要参考续写映射
            }

            int resumeWire = _session.RowCount;
            if (resumeN > 0)
            {
                // end 指向被 remove 的条目：跳到下一条未移除原文（协议 5.4）。
                while (resumeN <= count)
                {
                    TaskEdit edit;
                    if (plan.Edits.TryGetValue(resumeN, out edit)
                        && string.Equals(edit.Kind, "remove", StringComparison.Ordinal))
                    {
                        AddAppliedRemove(wireStart + resumeN - 1);
                        resumeN++;
                        continue;
                    }
                    break;
                }
                resumeWire = resumeN > count
                    ? _session.RowCount : wireStart + resumeN - 1;
            }

            // 玩家已经点在占位条上：plan 的首行直接原位替换上屏；还停在 $PC 则不换当前显示。
            bool atTail = _session.Index >= _turnTailIndex;
            if (!_session.ReplaceFrom(_turnTailIndex, replacement.ToArray(), resumeWire,
                present: atTail))
            {
                LogManager.Log("[DialogueInterject] plan apply failed (splice rejected)");
                return;
            }
            for (int i = 0; i < refs.Count; i++)
            {
                if (refs[i] == null) continue;      // 原文行：没有参考续写映射
                _insertedLines[replacement[i]] = refs[i];
            }
            _turnTailIndex = -1;                    // plan 之后不再接受新增行插入
            if (!hasEnd) _abandonedOriginalTail = true;
            // plan 应用后 _planApplied 才为真：当前已上屏的 add 可能正是“最后一条”。
            RefreshAskAcceptCurrent();
        }

        private void AddAppliedRemove(int wire)
        {
            if (!_appliedRemoves.Contains(wire)) _appliedRemoves.Add(wire);
        }

        /// <summary>改写行：保留原说话人/称谓/立绘/配图动作，只换正文与情绪（协议 5.5）。</summary>
        private NativeDialogueBookSession.Line BuildEditedLine(DialogueInterjectLine source, int wire)
        {
            if (_session == null) return null;
            NativeDialogueBookSession.Line origin = _session.GetWireRow(wire);
            if (origin == null) return null;
            return new NativeDialogueBookSession.Line
            {
                Name = origin.Name,
                Title = origin.Title,
                Text = source.Text,
                PortraitKey = origin.PortraitKey,
                Expression = string.IsNullOrEmpty(source.Emotion)
                    ? origin.Expression : source.Emotion,
                IsDoll = origin.IsDoll,
                Appearance = origin.Appearance,
                NormalizedAppearance = origin.NormalizedAppearance,
                AppearanceIdentity = origin.AppearanceIdentity,
                ImageAction = origin.ImageAction,
                ImagePath = origin.ImagePath,
                WireIndex = wire,
                SplitIntermediate = source.IsSplitHead,
                IsPlayer = origin.IsPlayer
            };
        }

        private void AcceptLine(DialogueInterjectLine line)
        {
            if (!_turnActive || _closing || line == null || string.IsNullOrEmpty(line.Text)) return;
            _preparing = false;             // 已经出词：草案/检索阶段结束
            if (_planApplied)
            {
                // plan 是任务模式的最后一块；之后还来 line 属协议违例，忽略不排队。
                LogManager.Log("[DialogueInterject] late line after plan ignored: " + line.Text);
                return;
            }
            if (_playerLinePlaying)
            {
                _queued.Enqueue(line);      // $PC 播放期间到达：排队，播完再播
                return;
            }
            if (!_aiLineShown)
            {
                // 首句：立即上屏（不等 done/后续行）
                if (!PlayLine(line, AdvanceFirstLineNow())) _queued.Enqueue(line);
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
            NativeDialogueBookSession.Line current = _session.GetPlaybackLine(_session.Index);
            if (!advance && current != null && current.IsPlaceholder)
            {
                // 玩家停在等待占位：下一句（最终确认对话）原位替换，不再追加到占位之后。
                NativeDialogueBookSession.Line replacement = BuildLocalLine(line);
                if (replacement == null) return false;
                int index = _session.Index;
                // 同上：ReplaceFrom(present:true) 会同步上屏，登记必须先行。
                _insertedLines[replacement] = new InsertedRef
                {
                    Line = line, WireIndex = -1, TaskIndex = 0
                };
                if (!_session.ReplaceFrom(index, new[] { replacement }, null, true))
                {
                    _insertedLines.Remove(replacement);
                    return false;
                }
                _turnTailIndex = index + 1;
                _aiLineShown = true;
                if (line.Interim) _sawInterim = true;
                _lastAiLineInterim = line.Interim;
                _pcRevision = -1;
                // closing 迟到但玩家正停在最后一条 add：补判选项态。
                RefreshAskAcceptCurrent();
                SetInputState(line.IsSplitHead
                    ? DialogueInterjectInputState.Locked
                    : ReadyOrMuted());
                return true;
            }
            if (!advance && _session.Index >= _turnTailIndex) return false;
            NativeDialogueBookSession.Line local = BuildLocalLine(line);
            if (local == null) return false;
            // 先登记再 ReplaceFrom：advance 时 ReplaceFrom 内部会同步 Present →
            // OnLinePresented，那时必须已经能在字典里查到这一行的 kind。
            _insertedLines[local] = new InsertedRef { Line = line, WireIndex = -1, TaskIndex = 0 };
            if (!_session.ReplaceFrom(_turnTailIndex, new[] { local }, null, advance))
            {
                _insertedLines.Remove(local);
                return false;
            }
            _turnTailIndex++;
            _aiLineShown = true;            // 已插入（未必已上屏）：本轮已有可播内容
            if (line.Interim) _sawInterim = true;   // 本轮派过活：过渡话是 daily 组唯一的草案信号
            _lastAiLineInterim = line.Interim;
            if (advance) _pcRevision = -1;  // 后续打字完成不再当 $PC
            // closing 迟到但玩家正停在最后一条 add：补判选项态。
            RefreshAskAcceptCurrent();
            SetInputState(line.IsSplitHead
                ? DialogueInterjectInputState.Locked
                : ReadyOrMuted());
            return true;
        }

        /// <summary>把一条 AI 台词转成本地播放行（继承本组 NPC 的立绘/称谓）。</summary>
        private NativeDialogueBookSession.Line BuildLocalLine(DialogueInterjectLine line)
        {
            if (line == null) return null;
            NativeDialogueBookSession.Line template = FindNpcTemplate();
            string speaker = string.IsNullOrEmpty(line.Speaker)
                ? (!string.IsNullOrEmpty(_npcName) ? _npcName
                    : (template != null ? template.Name : ""))
                : line.Speaker;
            // AI 正文只属于当前 NPC；其他说话人不套主 NPC 的立绘。
            bool useTemplate = template != null
                && (string.IsNullOrEmpty(line.Speaker)
                    || string.Equals(speaker, template.Name, StringComparison.Ordinal)
                    || string.Equals(speaker, _npcName, StringComparison.Ordinal));
            return new NativeDialogueBookSession.Line
            {
                Name = speaker,
                Title = useTemplate ? template.Title : "",
                Text = line.Text,
                PortraitKey = useTemplate ? template.PortraitKey : "",
                Expression = !string.IsNullOrEmpty(line.Emotion) ? line.Emotion
                    : (useTemplate && !string.IsNullOrEmpty(template.Expression)
                        ? template.Expression : DefaultEmotion),
                IsDoll = useTemplate && template.IsDoll,
                Appearance = useTemplate ? template.Appearance : null,
                NormalizedAppearance = useTemplate ? template.NormalizedAppearance : null,
                AppearanceIdentity = useTemplate ? template.AppearanceIdentity : null,
                ImageAction = "keep",
                ImagePath = "",
                SplitIntermediate = line.IsSplitHead
            };
        }

        private void CompleteTurn()
        {
            if (!_turnActive) return;
            // done = 后端已处理本轮动作请求；不再需要“已扣未送达”的重试。
            _unackedItemAction = null;
            // 本轮不会再有新台词：没有结束语时，靠这个信号判定“最后一条 add”。
            _turnLinesDone = true;
            // 任务模式：没有 add 但有完整 plan 也算成功（协议 4.5 / F-08）。
            if (_taskMode && !_aiLineShown && _queued.Count == 0)
            {
                _turnActive = false;
                _preparing = false;
                DisarmWatchdog();
                if (_playerLinePlaying)
                {
                    // $PC 还在播：plan 等首句/换句时机再应用（不改当前句）。
                    _finalizePending = true;
                    return;
                }
                TryApplyPendingPlan();
                if (_planApplied || _pendingPlan != null)
                {
                    SetInputState(ReadyOrMuted());
                    Finalize("turn_done");
                    return;
                }
                FailTurnCore("done_without_line");
                return;
            }
            _turnActive = false;
            _preparing = false;
            DisarmWatchdog();
            if (!_aiLineShown && _queued.Count == 0)
            {
                // done 但零条可播（后端违反自身约定）：按失败处理，回原对话。
                FailTurnCore("done_without_line");
                return;
            }
            if (_playerLinePlaying)
            {
                // $PC 还在播：先不动输入态，等首句上屏再收尾（transcript 要含已播的 AI 行）。
                _finalizePending = true;
                return;
            }
            if (!_aiLineShown) _finalizePending = true;
            // done 已到且玩家停在最后一条 add：没有结束语也显示选项。
            RefreshAskAcceptCurrent();
            SetInputState(ReadyOrMuted());
            FlushPendingFinalize();
        }

        private void FlushPendingFinalize()
        {
            if (!_finalizePending) return;
            if (_playerLinePlaying) return;
            _finalizePending = false;
            Finalize("turn_done");
        }

        // ════════════════ 选项直连与物品往来（P6） ════════════════

        /// <summary>
        /// 输入条选项点击入口：有待处理索取时走物品决定，否则按任务确认/拒绝直连。
        /// 终端与普通打字不经过这里。
        /// </summary>
        internal void SubmitChoice(bool accept)
        {
            if (_pendingItemClaim != null)
            {
                SubmitItemDecision(accept);
                return;
            }
            if (!_askAccept || _taskActionSent) return;
            SubmitTaskDecision(accept);
        }

        /// <summary>任务确认/拒绝：省掉路由轮，确认文案生成那一次 LLM 保留。</summary>
        private void SubmitTaskDecision(bool accept)
        {
            if (_taskActionSent) return;
            _taskActionSent = true;
            SetAskAccept(false);
            var action = new JObject
            {
                ["kind"] = accept ? "task_accept" : "task_decline",
                ["action_id"] = _newId()
            };
            if (!SubmitAction(action))
            {
                _taskActionSent = false;
                LogManager.Log("[DialogueInterject] task action not started: "
                    + action.Value<string>("kind"));
            }
        }

        /// <summary>
        /// 物品索取决定：点“赠送”先让 AS2 真实扣除（装备取背包最低强化度），
        /// 成功后才发 item_take_accept；点“不赠送”直接发 decline，不扣任何物品。
        /// </summary>
        private void SubmitItemDecision(bool accept)
        {
            JObject claim = _pendingItemClaim;
            if (claim == null || _itemDecisionBusy) return;
            string claimId = claim.Value<string>("claim_id") ?? "";
            string itemName = claim.Value<string>("item_name") ?? "";
            int quantity = claim.Value<int?>("quantity") ?? 1;
            if (claimId.Length == 0 || itemName.Length == 0) return;

            if (!accept)
            {
                var decline = new JObject
                {
                    ["kind"] = "item_take_decline",
                    ["action_id"] = _newId(),
                    ["claim_id"] = claimId,
                    ["item_name"] = itemName,
                    ["quantity"] = Math.Max(1, quantity)
                };
                ClearItemClaim();
                if (!SubmitAction(decline))
                    LogManager.Log("[DialogueInterject] item decline not started");
                return;
            }

            DialogueInterjectItemClaimView view = _itemClaimView;
            if (view == null || !view.Enough) return;
            if (_itemExchange == null)
            {
                LogManager.Log("[DialogueInterject] item take unavailable (no AS2 bridge)");
                return;
            }

            _itemDecisionBusy = true;
            DialogueInterjectItemClaimView busy = CopyClaimView(view);
            busy.Busy = true;
            RaiseItemClaim(busy);
            string takeOperationId = "take:" + _newId();
            TaskRunner(async () =>
            {
                JObject result = null;
                try
                {
                    var args = new JObject
                    {
                        ["name"] = itemName,
                        ["quantity"] = Math.Max(1, quantity),
                        ["operationId"] = takeOperationId
                    };
                    result = await _itemExchange.RequestAsync("npcItemTake", args,
                        CancellationToken.None).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[DialogueInterject] item take failed: " + ex.Message);
                }
                bool ok = result != null && result.Value<bool?>("success") == true;
                if (!ok)
                {
                    string error = result != null
                        ? (result.Value<string>("error") ?? "take_failed") : "take_unavailable";
                    LogManager.Log("[DialogueInterject] item take rejected: " + error);
                    Post(() =>
                    {
                        _itemDecisionBusy = false;
                        // 扣除失败：不记账、不发动作；保留选项并按最新持有刷新（可能置灰）。
                        RefreshItemClaimHoldings();
                    });
                    return;
                }

                int actual = result.Value<int?>("actual") ?? Math.Max(1, quantity);
                if (actual < 1) actual = Math.Max(1, quantity);
                bool equipment = result.Value<bool?>("equipment") == true;
                var action = new JObject
                {
                    ["kind"] = "item_take_accept",
                    ["action_id"] = _newId(),
                    ["claim_id"] = claimId,
                    ["item_name"] = itemName,
                    ["quantity"] = actual
                };
                if (equipment)
                    action["item_level"] = result.Value<int?>("itemLevel") ?? 0;
                Post(() =>
                {
                    _itemDecisionBusy = false;
                    ClearItemClaim();
                    // 物品已真实扣除：请求若没送达，后端未记账；失败时用同 action_id 重试一次。
                    _unackedItemAction = (JObject)action.DeepClone();
                    if (!SubmitAction(action))
                        LogManager.Log("[DialogueInterject] item accept not started; "
                            + "item already deducted, action can be retried");
                    RefreshPlayerItemNames();
                });
            });
        }

        /// <summary>
        /// 选项直连轮：不发 $PC，直接以 action 请求开启一轮；后端预执行动作后只生成最终台词。
        /// 返回 false 表示当前不允许（无会话/组不允许/已关闭/无 NPC）。
        /// </summary>
        private bool SubmitAction(JObject action)
        {
            if (action == null) return false;
            if (_session == null || !_groupAllowsInterject || _closing) return false;
            if (_session.State != NativeDialogueBookSession.HostState.Active) return false;
            string npc = _npcName;
            if (string.IsNullOrEmpty(npc)) return false;

            List<PlayedRow> playedSnapshot;
            lock (_playedGate) { playedSnapshot = new List<PlayedRow>(_played); }
            int wireResume = _session.CurrentWireIndex + 1;
            List<ReferenceItem> unplayed = CollectUnplayedTurnLines(wireResume);

            StopStream();
            _turnActive = false;
            _finalizePending = false;
            _resumeAfterFailure = false;
            _pendingPlan = null;
            _planApplied = false;
            SetAskAccept(false);
            _turnLinesDone = false;
            _presentedLineKind = null;
            _presentedLineInterim = false;
            _sawInterim = false;
            _sawDrafting = false;
            _appliedRemoves.RemoveAll(wire => wire < wireResume);

            var remaining = BuildRemaining(wireResume);
            string dialogueInstanceId = _dialogueInstanceId ?? (_dialogueInstanceId = _newId());
            string turnId = _newId();
            string requestJson = BuildRequest("", npc, dialogueInstanceId, turnId,
                playedSnapshot, remaining, unplayed, action);

            // 没有 $PC：AI 行直接接在当前行之后，玩家点“下一条”逐句看。
            _turnTailIndex = _session.Index + 1;
            _wireResume = wireResume;
            _turnId = turnId;
            _turnActive = true;
            _aiLineShown = false;
            _lastAiLineInterim = false;
            _preparing = false;
            _turnStatusText = null;
            _queued.Clear();
            _insertedLines.Clear();
            LastFailure = null;
            LastReferenceCount = unplayed.Count;
            SetInputState(DialogueInterjectInputState.Hidden);
            _turnStartedAt = _lastActivityAt = _clock();
            ArmWatchdog(_turnStartedAt);
            StartStream(requestJson);
            return true;
        }

        /// <summary>SSE action：item_grant 必须真实发放并回执，不得只播台词。</summary>
        private void AcceptItemGrantAction(DialogueInterjectEvent evt)
        {
            if (!string.Equals(evt.Text("kind"), "item_grant", StringComparison.Ordinal)) return;
            string actionId = evt.Text("action_id");
            if (actionId.Length == 0) return;
            lock (_executedGrants)
            {
                if (_executedGrants.Contains(actionId)) return;
                _executedGrants.Add(actionId);
            }
            string itemName = evt.Text("item_name");
            int quantity = evt.Int("quantity", 0);
            if (itemName.Length == 0 || quantity < 1)
            {
                PostActionResult(actionId, new JObject
                {
                    ["action_id"] = actionId, ["success"] = false,
                    ["error"] = "malformed_action"
                });
                return;
            }
            ExecuteItemGrant(actionId, evt.Text("npc"), itemName, quantity);
        }

        private void ExecuteItemGrant(string actionId, string npc, string itemName, int quantity)
        {
            if (_itemExchange == null)
            {
                PostActionResult(actionId, new JObject
                {
                    ["action_id"] = actionId, ["success"] = false, ["error"] = "host_unavailable"
                });
                return;
            }
            TaskRunner(async () =>
            {
                JObject result = null;
                try
                {
                    var args = new JObject
                    {
                        ["npc"] = npc,
                        ["name"] = itemName,
                        ["quantity"] = quantity,
                        ["operationId"] = actionId
                    };
                    result = await _itemExchange.RequestAsync("npcItemGrant", args,
                        CancellationToken.None).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[DialogueInterject] item grant failed: " + ex.Message);
                }

                bool ok = result != null && result.Value<bool?>("success") == true;
                var ack = new JObject { ["action_id"] = actionId };
                if (ok)
                {
                    ack["success"] = true;
                    ack["actual_quantity"] = result.Value<int?>("actual") ?? quantity;
                    int overflow = result.Value<int?>("overflowMoney") ?? 0;
                    if (overflow > 0) ack["overflow_money"] = overflow;
                }
                else
                {
                    ack["success"] = false;
                    ack["error"] = result != null
                        ? (result.Value<string>("error") ?? "grant_failed") : "as2_unavailable";
                }
                PostActionResult(actionId, ack);
                if (ok) Post(RefreshPlayerItemNames);
            });
        }

        /// <summary>回执丢失重试：同 action_id 最多 3 次；仍失败只记日志供人工对账。</summary>
        private void PostActionResult(string actionId, JObject ack)
        {
            string json = ack.ToString(Formatting.None);
            TaskRunner(async () =>
            {
                for (int attempt = 0; attempt < 3; attempt++)
                {
                    try
                    {
                        IDialogueInterjectTransport transport = _transportFactory();
                        if (transport != null)
                        {
                            var disposable = transport as IDisposable;
                            try
                            {
                                await transport.PostActionResultAsync(json, CancellationToken.None)
                                    .ConfigureAwait(false);
                            }
                            finally
                            {
                                if (disposable != null) disposable.Dispose();
                            }
                            LogManager.Log("[DialogueInterject] action-result " + actionId
                                + " success=" + (ack.Value<bool?>("success") == true));
                            return;
                        }
                    }
                    catch (Exception ex)
                    {
                        LogManager.Log("[DialogueInterject] action-result retry "
                            + (attempt + 1) + " failed: " + ex.Message);
                    }
                    if (attempt < 2)
                        await Task.Delay(400 * (attempt + 1)).ConfigureAwait(false);
                }
                LogManager.Log("[DialogueInterject] action-result lost, reconcile manually: " + json);
            });
        }

        /// <summary>SSE item_claim：pending 显示两按钮，closed 清空。</summary>
        private void AcceptItemClaim(DialogueInterjectEvent evt)
        {
            string state = evt.Text("state");
            if (string.Equals(state, "closed", StringComparison.Ordinal))
            {
                ClearItemClaim();
                return;
            }
            if (!string.Equals(state, "pending", StringComparison.Ordinal)) return;
            string claimId = evt.Text("claim_id");
            string itemName = evt.Text("item_name");
            if (claimId.Length == 0 || itemName.Length == 0) return;
            _pendingItemClaim = new JObject
            {
                ["claim_id"] = claimId,
                ["npc"] = evt.Text("npc"),
                ["item_name"] = itemName,
                ["quantity"] = Math.Max(1, evt.Int("quantity", 1))
            };
            _itemDecisionBusy = false;
            SetAskAccept(false);      // 物品索取优先于任务选项
            RefreshItemClaimHoldings();
        }

        /// <summary>实时查询背包（装备只算背包、给最低强化度）并生成按钮文案。</summary>
        private void RefreshItemClaimHoldings()
        {
            JObject claim = _pendingItemClaim;
            if (claim == null) return;
            int generation = ++_itemClaimGeneration;
            string itemName = claim.Value<string>("item_name") ?? "";
            if (_itemExchange == null)
            {
                RaiseItemClaim(BuildClaimView(claim, 0, false, 0));
                return;
            }
            TaskRunner(async () =>
            {
                JObject result = null;
                try
                {
                    result = await _itemExchange.RequestAsync("npcItemCount",
                        new JObject { ["name"] = itemName },
                        CancellationToken.None).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[DialogueInterject] item count failed: " + ex.Message);
                }
                int count = 0;
                int minLevel = 0;
                bool equipment = false;
                if (result != null && result.Value<bool?>("success") != false)
                {
                    count = result.Value<int?>("count") ?? 0;
                    equipment = result.Value<bool?>("equipment") == true;
                    minLevel = result.Value<int?>("minLevel") ?? 0;
                }
                Post(() =>
                {
                    if (generation != _itemClaimGeneration || _pendingItemClaim == null) return;
                    RaiseItemClaim(BuildClaimView(claim, count, equipment, minLevel));
                });
            });
        }

        private static DialogueInterjectItemClaimView BuildClaimView(JObject claim,
            int count, bool equipment, int minLevel)
        {
            int quantity = claim.Value<int?>("quantity") ?? 1;
            if (equipment) quantity = 1;      // 装备数量固定 1
            return new DialogueInterjectItemClaimView
            {
                ClaimId = claim.Value<string>("claim_id") ?? "",
                Npc = claim.Value<string>("npc") ?? "",
                ItemName = claim.Value<string>("item_name") ?? "",
                Quantity = Math.Max(1, quantity),
                Count = Math.Max(0, count),
                MinLevel = Math.Max(0, minLevel),
                Equipment = equipment
            };
        }

        private static DialogueInterjectItemClaimView CopyClaimView(
            DialogueInterjectItemClaimView source)
        {
            return new DialogueInterjectItemClaimView
            {
                ClaimId = source.ClaimId,
                Npc = source.Npc,
                ItemName = source.ItemName,
                Quantity = source.Quantity,
                Count = source.Count,
                MinLevel = source.MinLevel,
                Equipment = source.Equipment,
                Busy = source.Busy
            };
        }

        private void RaiseItemClaim(DialogueInterjectItemClaimView view)
        {
            _itemClaimView = view;
            Action<DialogueInterjectItemClaimView> handler = ItemClaimChanged;
            if (handler == null) return;
            try { handler(view); }
            catch (Exception ex)
            {
                LogManager.Log("[DialogueInterject] ItemClaimChanged throw: " + ex.Message);
            }
        }

        private void ClearItemClaim()
        {
            _itemClaimGeneration++;
            _itemDecisionBusy = false;
            if (_pendingItemClaim == null && _itemClaimView == null) return;
            _pendingItemClaim = null;
            RaiseItemClaim(null);
        }

        /// <summary>刷新玩家持有名快照：只给后端索取池用，不代表数量、不进台词。</summary>
        private void RefreshPlayerItemNames()
        {
            if (_itemExchange == null || _taskMode || _session == null) return;
            int generation = ++_playerNamesGeneration;
            TaskRunner(async () =>
            {
                var names = new List<string>();
                try
                {
                    JObject result = await _itemExchange.RequestAsync("npcItemSummary",
                        new JObject(), CancellationToken.None).ConfigureAwait(false);
                    if (result != null && result.Value<bool?>("success") == true)
                    {
                        CollectItemNames(result["items"] as JArray, names);
                        CollectItemNames(result["equipment"] as JArray, names);
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[DialogueInterject] item snapshot failed: " + ex.Message);
                }
                Post(() =>
                {
                    if (generation != _playerNamesGeneration) return;
                    _playerItemNames = names;
                });
            });
        }

        private static void CollectItemNames(JArray rows, List<string> names)
        {
            if (rows == null) return;
            for (int i = 0; i < rows.Count; i++)
            {
                var row = rows[i] as JObject;
                if (row == null) continue;
                string name = (row.Value<string>("name") ?? "").Trim();
                if (name.Length == 0 || names.Contains(name)) continue;
                names.Add(name);
            }
        }

        // ════════════════ 失败 / 取消 / 收尾 ════════════════

        /// <summary>
        /// D-17 / F-11：失败不补写、不重试整段；已经收到的台词照常播放。
        /// 零条 AI 行 → 在原生当前点接回；已播若干 AI 行 → 接在那些行之后（_wireResume）。
        /// </summary>
        /// <summary>SSE error / 看门狗 / 传输失败的统一入口：turn 已结束后的迟到 error 只记日志。</summary>
        private void FailTurn(string code)
        {
            if (!_turnActive)
            {
                LogManager.Log("[DialogueInterject] late error ignored: " + code
                    + " (turn already finished)");
                return;
            }
            FailTurnCore(code);
        }

        private void FailTurnCore(string code)
        {
            // 已真实扣除、但本轮可能没送达后端：同 action_id 重试一次，绝不重复扣除。
            JObject retry = _unackedItemAction;
            if (retry != null)
            {
                _unackedItemAction = null;
                string retryId = retry.Value<string>("action_id") ?? "";
                if (retryId.Length > 0 && retryId != _itemActionRetriedId && SubmitAction(retry))
                {
                    _itemActionRetriedId = retryId;
                    LogManager.Log("[DialogueInterject] item accept retried after stream failure: "
                        + retryId);
                    return;
                }
                LogManager.Log("[DialogueInterject] item accept retry failed; reconcile manually: "
                    + retryId);
            }
            // error 等同组内失败：待处理索取不再可靠，清掉选项。
            ClearItemClaim();
            LastFailure = code;
            _stream = null;
            _turnActive = false;
            _preparing = false;
            // 失败不应用尚未应用的 plan（D-17 / §4.9：没有完整 plan 就回原对话当前点）。
            _pendingPlan = null;
            DisarmWatchdog();

            if (_queued.Count == 0)
            {
                _finalizePending = false;
                _resumeAfterFailure = false;
                RestoreOrResumeAfterFailure();
                SetInputState(ReadyOrMuted());
                Finalize("turn_error");
                return;
            }

            // 已收到的行还有得播：按"失败但保留已收台词"处理，收尾与接回都推迟到首句上屏。
            _finalizePending = true;
            _resumeAfterFailure = true;
            if (_playerLinePlaying) return;      // $PC 播完再放（OnTypingFinished → PlayLine → Flush）
            DialogueInterjectLine next = _queued.Dequeue();
            if (PlayLine(next, AdvanceFirstLineNow()))
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
            RestoreOrResumeAfterFailure();
            SetInputState(ReadyOrMuted());
            Finalize("turn_error");
        }

        /// <summary>
        /// 失败回退（D-17 / §4.9）：有已播 AI 行 → 接在那些行之后；没有 → 回当前原文点。
        /// 例外：已应用完整 plan（计划本身即后续）或无 end 的整组替换已放弃原文 → 不接回。
        /// </summary>
        private void RestoreOrResumeAfterFailure()
        {
            if (_planApplied || _abandonedOriginalTail)
            {
                _turnTailIndex = -1;
                return;
            }
            if (_aiLineShown) ResumeAfterPlayedTurnLines();
            else RestoreOriginalTail();
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
            _pendingPlan = null;
            _queued.Clear();
            if (!_planApplied && !_abandonedOriginalTail) RestoreOriginalTail();
            if (_session != null && !_closing) SetInputState(ReadyOrMuted());
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
            if (_abandonedOriginalTail) return;   // 无 end 的整组替换：原始剩余已放弃
            if (_session.State != NativeDialogueBookSession.HostState.Active) return;
            // 用当前已到达的原始行号 +1 接回：index 可能已经推进到原文里，不能用提交时的快照。
            // 玩家已点在「思索中……」占位上时，从占位行本身替换并重呈现，避免留下等待文案。
            NativeDialogueBookSession.Line current = _session.GetPlaybackLine(_session.Index);
            bool onPlaceholder = current != null && current.IsPlaceholder;
            int start = onPlaceholder ? _session.Index : _session.Index + 1;
            _session.ReplaceFrom(start, new NativeDialogueBookSession.Line[0],
                _session.CurrentWireIndex + 1, present: onPlaceholder);
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
            if (_abandonedOriginalTail) return;   // 无 end 的整组替换：原始剩余已放弃
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
            // 玩家台词上屏期间（含打字完成、仍停在玩家行等“下一条”）整条输入框隐藏，
            // 不论展开与否；只有下一句非玩家台词上屏后才恢复。
            if (_playerLineOnScreen && state != DialogueInterjectInputState.Hidden)
                state = DialogueInterjectInputState.Hidden;
            if (_inputState == state) return;
            _inputState = state;
            Action<DialogueInterjectInputState> handler = InputStateChanged;
            if (handler == null) return;
            try { handler(state); }
            catch (Exception ex) { LogManager.Log("[DialogueInterject] InputStateChanged throw: " + ex.Message); }
        }

        /// <summary>
        /// 选项态判定（每个上屏/插入/收流时机重算）：只在任务草案确认轮的最后一条 add 上成立。
        /// 结束语先行可判（下一条是 closing）；结束语为空时靠 done 已到 + 后面没有行。
        /// currentKind 由调用方给出——已上屏的行会被摘出 _insertedLines，不能再查字典。
        /// </summary>
        private void RefreshAskAccept(
            NativeDialogueBookSession.Line current, string currentKind)
        {
            bool want = false;
            string nextKind = null;
            // 派活轮判定三选一：task 组有 plan；daily 组看 status(drafting) 或过渡话。
            bool draftTurn = _planApplied || _sawDrafting || _sawInterim;
            bool eligible = draftTurn && !_closing && !_playerLineOnScreen
                && _pendingItemClaim == null && !_taskActionSent
                && _session != null
                && _session.State == NativeDialogueBookSession.HostState.Active;
            if (eligible && current != null && !current.IsPlayer && !_presentedLineInterim
                && string.Equals(currentKind, "add", StringComparison.Ordinal))
            {
                NativeDialogueBookSession.Line next = _session.GetPlaybackLine(_session.Index + 1);
                InsertedRef nextRef = null;
                if (next != null) _insertedLines.TryGetValue(next, out nextRef);
                if (nextRef != null && nextRef.Line != null) nextKind = nextRef.Line.Kind;
                bool nextClosing = string.Equals(nextKind, "closing", StringComparison.Ordinal);
                // 没有结束语时只能靠收流信号：done 已到且后面确实没有行了。
                want = nextClosing || (next == null && _turnLinesDone);
                LogManager.Log("[DialogueInterject] askAccept-probe want=" + want
                    + " next=" + (nextKind ?? (next == null ? "none" : "original"))
                    + " done=" + _turnLinesDone + " plan=" + _planApplied
                    + " drafting=" + _sawDrafting + " interim=" + _sawInterim);
            }
            SetAskAccept(want);
        }

        /// <summary>按当前播放行重算选项态（closing 迟到插入 / done 到达时补判）。</summary>
        private void RefreshAskAcceptCurrent()
        {
            NativeDialogueBookSession.Line current =
                _session != null ? _session.GetPlaybackLine(_session.Index) : null;
            RefreshAskAccept(current, _presentedLineKind);
        }

        private void SetAskAccept(bool value)
        {
            if (_askAccept == value) return;
            _askAccept = value;
            Action<bool> handler = AskAcceptChanged;
            if (handler == null) return;
            try { handler(value); }
            catch (Exception ex) { LogManager.Log("[DialogueInterject] AskAcceptChanged throw: " + ex.Message); }
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
