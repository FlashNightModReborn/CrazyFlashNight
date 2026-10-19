using System;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Dialogue;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// wire v2 对白会话宿主（每 requestId 一个实例，inline/source 同一宿主）。
    ///
    /// 持有：不可变行集、当前 index、本地 revision（每 requestId 单调 ++ 每次 ShowFrame，
    /// 与 index 方向无关，禁止按 index 派生）、mode/advanceKey/appliedEpoch、
    /// rowCount（规范化行数）、closing 状态机与终态请求重试。
    ///
    /// closing 状态机：active → closing →（同 rid hide / 更高 sequence 帧 / 断线）closed；
    /// closing 收到合法更新代 append → 复活回 active；closing 收到 set → 应用设置
    /// 并继续重试原冻结请求；任何其他新 op（含被拒绝的）都不终止 closing。
    ///
    /// 线程模型：全部方法只准在 task 的采用队列（UI dispatch）上调用；重试回调
    /// 也经同一队列返回，_retryToken 使在途回调失效即为取消。
    /// </summary>
    internal sealed class NativeDialogueBookSession
    {
        internal enum HostState { Active, Closing, Closed }

        /// <summary>book/append 单行（与 v1 portrait/imageAction 同构同校验后的冻结形态）。</summary>
        internal sealed class Line
        {
            internal string Name, Title, Text;
            internal string PortraitKey, Expression;
            internal bool IsDoll;
            /// <summary>AS2 原始行号（0 基）；-1 = Host 本地增强行（插话新增/改写拆分）。
            /// 只有 >=0 的行会推进 <see cref="CurrentWireIndex"/>；finish/close 的分支
            /// 全部按原始行号取值，增强行不改变 AS2 的 rowCount 口径。</summary>
            internal int WireIndex = -1;
            /// <summary>加载路径用原始 appearance（LoadPortraitWithRect 内部自行归一化）。</summary>
            internal JObject Appearance;
            /// <summary>doll 行预取用的已归一化外观；static 行为 null。</summary>
            internal JObject NormalizedAppearance;
            internal string AppearanceIdentity;
            internal string ImageAction, ImagePath;
            /// <summary>插话侧标记：这条本地行是被 165 上限拆出来的非末段（输入暂锁，§3.3）。
            /// 只影响 Host 输入状态，不参与 wire 校验。</summary>
            internal bool SplitIntermediate;
        }

        private readonly NativeDialogueTask _task;
        internal readonly string RequestId;
        internal readonly string SceneId;
        internal readonly string Mode;
        /// <summary>组类型：daily（缺省）/ task_pre / task_post / stage（协议 5.1 / §13.2）。
        /// 只由 book 报文决定；append 不改变组类型。</summary>
        internal readonly string DialogueKind;
        /// <summary>任务 id（task_pre/task_post 组才有，来自 book 可选字段 dialogueTaskId，协议 4.1）。
        /// 只由 book 报文决定；append 不改变；daily/stage 恒 null。</summary>
        internal readonly string DialogueTaskId;
        /// <summary>book 报文里的玩家快照（source 组）；插话本地 $PC 行据此还原名称/头衔/立绘。</summary>
        internal readonly string PlayerName;
        internal readonly string HeroTitle;
        internal readonly JObject HeroPortrait;
        /// <summary>会话创建时的连接代；跨代后在途重试发射前复查不通过。</summary>
        internal readonly long TransportEpoch;

        private Line[] _lines;
        /// <summary>AS2 原始行（book + 合法 append），按 wire 顺序；与 <see cref="_lines"/>
        /// （播放序列，含本地增强行）分开维护。WireRowCount 只读它。</summary>
        private readonly List<Line> _wireRows = new List<Line>();
        /// <summary>当前播放点对应的原始行号上界（进过 Present 的最大 WireIndex）。
        /// close 的 finalIndex 取它；增强行不推进。</summary>
        private int _currentWire;
        private int _index;
        private int _revision;                  // 本地单调：每次 ShowFrame ++
        private int _appliedEpoch = 1;          // 已应用行集代际（book=1，append 连续 ++）
        private int _advanceKey;
        private HostState _state = HostState.Active;
        private string _frozenWire;             // 冻结终态请求（含 \0），重试逐字节相同
        private long _retryToken;               // 每次 ArmRetry/取消 ++，在途回调比对失效
        private long _retryArmedAt = -1;        // 最近一次 ArmRetry 的时钟戳（诊断/测试观测）

        /// <summary>重试节拍（ms），协议要求 0.5–1s；测试可注入更小值或直接注入调度器。</summary>
        internal long RetryIntervalMs = 750;
        /// <summary>可注入时钟（参照 widget TypingClock 模式）。</summary>
        internal Func<long> RetryClock = () => Environment.TickCount64;
        /// <summary>(delayMs, callback) 延迟调度；callback 必须回到 task 采用队列执行。</summary>
        internal Action<long, Action> RetryScheduler;

        internal NativeDialogueBookSession(NativeDialogueTask task, string requestId,
            string sceneId, string mode, int advanceKey, Line[] lines, long transportEpoch,
            string dialogueKind = null, string dialogueTaskId = null,
            JObject playerSnapshot = null)
        {
            _task = task ?? throw new ArgumentNullException(nameof(task));
            RequestId = requestId;
            SceneId = sceneId;
            Mode = mode;
            DialogueKind = NormalizeDialogueKind(dialogueKind);
            // 日常/stage 即使报文带了 id 也忽略（协议 4.1：只有任务组使用任务 id）。
            DialogueTaskId = (DialogueKind == "task_pre" || DialogueKind == "task_post")
                ? NormalizeDialogueTaskId(dialogueTaskId) : null;
            PlayerName = playerSnapshot != null
                ? (playerSnapshot.Value<string>("playerName") ?? "") : "";
            HeroTitle = playerSnapshot != null
                ? (playerSnapshot.Value<string>("heroTitle") ?? "") : "";
            JObject hero = playerSnapshot != null ? playerSnapshot["heroPortrait"] as JObject : null;
            HeroPortrait = hero != null ? (JObject)hero.DeepClone() : null;
            _advanceKey = advanceKey;
            _lines = lines ?? throw new ArgumentNullException(nameof(lines));
            for (int i = 0; i < _lines.Length; i++)
            {
                _lines[i].WireIndex = i;
                _wireRows.Add(_lines[i]);
            }
            TransportEpoch = transportEpoch;
        }

        internal int AppliedEpoch { get { return _appliedEpoch; } }
        internal int AdvanceKey { get { return _advanceKey; } }
        /// <summary>AS2 口径行数（wire 原始行）。本地增强行不计入：ack/status 与
        /// advance_past_end 的 finalIndex 基准都必须是它。</summary>
        internal int RowCount { get { return _wireRows.Count; } }
        /// <summary>本地播放序列长度（AS2 原始行 + 本地增强行）。</summary>
        internal int PlaybackCount { get { return _lines.Length; } }
        internal int Index { get { return _index; } }
        /// <summary>本地单调修订号（每次 Present ++）；宿主用它把打字完成对回具体某一句。</summary>
        internal int Revision { get { return _revision; } }
        /// <summary>close 用的原始行号：当前播放点已到达的最大 wire 行号，钳在原始范围内。</summary>
        internal int CurrentWireIndex
        {
            get
            {
                int last = _wireRows.Count - 1;
                if (last < 0) return 0;
                return Math.Max(0, Math.Min(_currentWire, last));
            }
        }
        internal HostState State { get { return _state; } }
        /// <summary>冻结的终态请求串（含 \0）；非 closing 为 null。重试逐字节重发。</summary>
        internal string FrozenWire { get { return _frozenWire; } }
        /// <summary>最近一次 ArmRetry 的注入时钟戳；未布防为 -1（测试观测时钟注入）。</summary>
        internal long RetryArmedAt { get { return _retryArmedAt; } }

        /// <summary>会话起步：呈现 startIndex 行并自驱预取下一句。</summary>
        internal void Begin(int startIndex)
        {
            _index = startIndex;
            _currentWire = ClampWire(startIndex);
            Present();
        }

        /// <summary>widget advance 输入（仅打字完成后才会到达）：非末行换句；
        /// 越末行 → 进 closing 并发送冻结 finish（reason=advance_past_end）。</summary>
        internal void AdvanceLocal()
        {
            if (_state != HostState.Active) return;
            if (_index + 1 < _lines.Length) { _index++; Present(); return; }
            EnterClosing("advance_past_end");
        }

        /// <summary>
        /// 本地增强：从 startIndex 起替换后续播放序列（原地插入/改写/跳过）。
        /// - startIndex 是**播放序列**下标（0..PlaybackCount），替换点之前保持不动；
        /// - replacement 每条都是播放行；携带 WireIndex >= 0 表示"这条占用了某条原始行"，
        ///   -1 表示纯本地新增（不推进原始行号）；
        /// - resumeOriginalIndex = 增强行播完后接回的原始行号（0..WireRowCount）；
        ///   null = 不接回原文，增强序列播完即组末。
        /// 不改变 AppliedEpoch：本地增强不是 AS2 代际，append 的 baseEpoch 仍按 wire 代际。
        /// present=false 只改播放序列、不换当前显示（把后续台词插到队尾时用）。
        /// 返回 false = 状态/下标非法，播放序列保持不变。
        /// </summary>
        internal bool ReplaceFrom(int startIndex, Line[] replacement, int? resumeOriginalIndex,
            bool present = true)
        {
            if (_state != HostState.Active) return false;
            if (startIndex < 0 || startIndex > _lines.Length) return false;
            if (replacement == null) replacement = new Line[0];
            int resume = resumeOriginalIndex ?? _wireRows.Count;
            if (resume < 0 || resume > _wireRows.Count) return false;
            for (int i = 0; i < replacement.Length; i++)
            {
                if (replacement[i] == null) return false;
                if (replacement[i].WireIndex >= _wireRows.Count) return false;
            }

            var merged = new List<Line>(_lines.Length - startIndex
                + replacement.Length + (_wireRows.Count - resume));
            for (int i = 0; i < startIndex; i++) merged.Add(_lines[i]);
            for (int i = 0; i < replacement.Length; i++) merged.Add(replacement[i]);
            for (int i = resume; i < _wireRows.Count; i++) merged.Add(_wireRows[i]);
            if (merged.Count < 1) return false;

            _lines = merged.ToArray();
            if (!present)
            {
                _index = Math.Min(_index, _lines.Length - 1);
                _retryToken++;
                _frozenWire = null;
                return true;
            }
            _index = Math.Min(startIndex, _lines.Length - 1);
            _retryToken++;                  // 播放序列变了：在途重试回调失效
            _frozenWire = null;
            Present();
            return true;
        }

        /// <summary>widget close / 终态意图输入：active → closing（reason=close）；
        /// closing 中再次到达不重建请求，保持续试原冻结请求。</summary>
        internal void RequestClose()
        {
            if (_state != HostState.Active) return;
            EnterClosing("close");
        }

        /// <summary>set 采用点：只更新白名单字段，不 bump epoch、不终止 closing。</summary>
        internal void ApplySet(int advanceKey)
        {
            _advanceKey = advanceKey;
        }

        /// <summary>连续代际追加的原子采用：合并行集、推进 appliedEpoch、按 restartIndex
        /// 重播；closing 中到达即复活（取消在途重试、回 active）。</summary>
        internal void ApplyAppend(Line[] extra, int restartIndex, int epoch)
        {
            var merged = new Line[_lines.Length + extra.Length];
            Array.Copy(_lines, merged, _lines.Length);
            Array.Copy(extra, 0, merged, _lines.Length, extra.Length);
            _lines = merged;
            // wire 口径：append 的每一行都是 AS2 原始行，行号续在既有 wire 行之后。
            for (int i = 0; i < extra.Length; i++)
            {
                extra[i].WireIndex = _wireRows.Count;
                _wireRows.Add(extra[i]);
            }
            _appliedEpoch = epoch;
            _retryToken++;                  // 取消在途重试回调
            _frozenWire = null;
            _state = HostState.Active;
            _index = restartIndex;
            Present();
        }

        /// <summary>终止会话（hide/更高 sequence/断线）：在途重试回调全部失效。</summary>
        internal void Terminate()
        {
            _state = HostState.Closed;
            _retryToken++;
            _frozenWire = null;
        }

        /// <summary>呈现当前行：组 NativeDialogueFrame（Revision=本地单调计数），
        /// 交给 task 驱动 widget 与立绘/配图加载，再自驱预取 index+1。</summary>
        private void Present()
        {
            _revision++;
            var line = _lines[_index];
            // 原始行号只在真正走到 AS2 原始行时推进；本地增强行沿用当前值
            // （close 取"当前值"，advance_past_end 恒取 WireRowCount-1）。
            if (line.WireIndex >= 0) _currentWire = line.WireIndex;
            var frame = new NativeDialogueFrame
            {
                RequestId = RequestId,
                SceneId = SceneId,
                Revision = _revision,
                LineIndex = _index,
                LineCount = _lines.Length,
                Name = line.Name,
                Title = line.Title,
                Text = line.Text,
                PortraitKey = line.PortraitKey,
                Expression = line.Expression,
                IsDoll = line.IsDoll,
                AppearanceIdentity = line.AppearanceIdentity,
                ImageAction = line.ImageAction,
                ImagePath = line.ImagePath
            };
            _task.PresentBookFrame(this, frame, line.Appearance);
            if (LinePresented != null)
            {
                try { LinePresented(line); }
                catch (Exception ex) { LogManager.Log("[NativeDialogue] LinePresented throw: " + ex.Message); }
            }
            PrefetchAt(_index + 1);
        }

        /// <summary>本组每呈现一行（含本地增强行）回调一次；插话侧据此记已播历史。
        /// 在采用队列（UI dispatch）上同步触发，回调里禁止再触发换句。</summary>
        internal Action<Line> LinePresented;

        /// <summary>进入 closing（advance_past_end / close）时回调一次，参数是 reason。
        /// 插话侧据此立即取消在途流并 finalize（§13.2 决定 5）。</summary>
        internal Action<string> Closing;

        /// <summary>播放序列行读取（越界返回 null）：中途插入时收集"已插入未播"的本地行。</summary>
        internal Line GetPlaybackLine(int playbackIndex)
        {
            if (playbackIndex < 0 || playbackIndex >= _lines.Length) return null;
            return _lines[playbackIndex];
        }

        /// <summary>组类型归一：daily / task_pre / task_post / stage；未知值回落 daily。</summary>
        internal static string NormalizeDialogueKind(string raw)
        {
            if (string.Equals(raw, "task_pre", StringComparison.Ordinal)
                || string.Equals(raw, "task_post", StringComparison.Ordinal)
                || string.Equals(raw, "stage", StringComparison.Ordinal))
                return raw;
            return "daily";
        }

        /// <summary>任务 id 归一（防御性）：去首尾空白后 1..32 才保留，否则 null。
        /// 日常/stage 组即使传入也按 null 处理（协议 4.1：只有任务组带 id）。</summary>
        internal static string NormalizeDialogueTaskId(string raw)
        {
            string trimmed = (raw ?? "").Trim();
            if (trimmed.Length < 1 || trimmed.Length > 32) return null;
            return trimmed;
        }

        /// <summary>原始行读取（越界返回 null）：请求 remaining / 失败回退定位用。</summary>
        internal Line GetWireRow(int wireIndex)
        {
            if (wireIndex < 0 || wireIndex >= _wireRows.Count) return null;
            return _wireRows[wireIndex];
        }

        private void PrefetchAt(int index)
        {
            if (index >= _lines.Length) return;
            _task.PrefetchBookLine(this, _lines[index]);
        }

        /// <summary>把任意下标钳进原始行范围（startIndex/当前值都可能越界）。</summary>
        private int ClampWire(int wireIndex)
        {
            int last = _wireRows.Count - 1;
            if (last < 0) return 0;
            return Math.Max(0, Math.Min(wireIndex, last));
        }

        private void EnterClosing(string reason)
        {
            _state = HostState.Closing;
            Action<string> closing = Closing;
            if (closing != null)
            {
                try { closing(reason); }
                catch (Exception ex) { LogManager.Log("[NativeDialogue] Closing throw: " + ex.Message); }
            }
            // AS2 校验口径（NativeDialogueService.handleV2Action）：
            //   advance_past_end 要求 finalIndex == AS2 rowCount-1（原始行数，非增强行数）；
            //   close 要求 finalIndex ∈ [0, rowCount-1]。
            // 冻结语义：epoch/finalIndex/reason 在入 closing 当下定死，
            // 之后任何重试都逐字节重发同一份请求，绝不从变化后的状态重拼。
            int finalIndex = string.Equals(reason, "advance_past_end", StringComparison.Ordinal)
                ? _wireRows.Count - 1
                : CurrentWireIndex;
            var command = new JObject
            {
                ["task"] = "cmd", ["action"] = "nativeDialogueAction",
                ["requestId"] = RequestId, ["sceneId"] = SceneId,
                ["verb"] = "finish", ["epoch"] = _appliedEpoch,
                ["finalIndex"] = finalIndex, ["reason"] = reason
            };
            _frozenWire = command.ToString(Formatting.None) + "\0";
            _task.TrySendBookFrozen(this);
            ArmRetry();
        }

        private void ArmRetry()
        {
            var scheduler = RetryScheduler;
            if (scheduler == null) return;
            long token = ++_retryToken;
            _retryArmedAt = RetryClock();
            scheduler(RetryIntervalMs, () => RetryTick(token));
        }

        /// <summary>重试节拍：token/状态复查（会话与连接代复查在 TrySendBookFrozen 内），
        /// 不设次数上限，频率与资源由固定节拍保证有界。</summary>
        private void RetryTick(long token)
        {
            if (token != _retryToken || _state != HostState.Closing) return;
            _task.TrySendBookFrozen(this);
            ArmRetry();
        }

        /// <summary>lines[] 单行解析：与 v1 portrait/imageAction 同构同校验，
        /// 任一字段畸形即失败（book/append 任一行失败 = 整包拒绝）。</summary>
        internal static bool TryParseLine(JToken token, out Line line)
        {
            line = null;
            var p = token as JObject;
            if (p == null) return false;
            string name, title, text, key, expression, kind, imageAction, imagePath;
            var portrait = p["portrait"] as JObject;
            if (!NativeDialogueTask.Text(p, "name", 256, out name)
                || !NativeDialogueTask.Text(p, "title", 256, out title)
                || !NativeDialogueTask.Text(p, "text", 32768, out text)
                || portrait == null
                || !NativeDialogueTask.Text(portrait, "key", 256, out key)
                || !NativeDialogueTask.Text(portrait, "expression", 80, out expression)
                || !NativeDialogueTask.Text(portrait, "kind", 8, out kind)
                || (kind != "static" && kind != "doll")
                || !NativeDialogueTask.Text(p, "imageAction", 5, out imageAction)
                || (imageAction != "keep" && imageAction != "show" && imageAction != "clear"))
                return false;
            imagePath = "";
            if (imageAction == "show"
                && (!NativeDialogueTask.Text(p, "imagePath", 512, out imagePath)
                    || imagePath.Length == 0)) return false;
            var appearance = portrait["appearance"] as JObject;
            if (kind == "doll" && appearance == null) return false;
            var normalized = kind == "doll"
                ? CF7Launcher.Guardian.Dialogue.DialoguePortraitService
                    .NormalizeAppearance(appearance) : null;
            if (kind == "doll" && normalized == null) return false;
            line = new Line
            {
                Name = name, Title = title, Text = text,
                PortraitKey = key, Expression = expression,
                IsDoll = kind == "doll",
                Appearance = appearance,
                NormalizedAppearance = normalized,
                AppearanceIdentity = normalized != null
                    ? normalized.ToString(Formatting.None) : "",
                ImageAction = imageAction, ImagePath = imagePath
            };
            return true;
        }
    }
}
