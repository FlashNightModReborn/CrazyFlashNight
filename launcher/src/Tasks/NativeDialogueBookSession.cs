using System;
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
            /// <summary>加载路径用原始 appearance（LoadPortraitWithRect 内部自行归一化）。</summary>
            internal JObject Appearance;
            /// <summary>doll 行预取用的已归一化外观；static 行为 null。</summary>
            internal JObject NormalizedAppearance;
            internal string AppearanceIdentity;
            internal string ImageAction, ImagePath;
        }

        private readonly NativeDialogueTask _task;
        internal readonly string RequestId;
        internal readonly string SceneId;
        internal readonly string Mode;
        /// <summary>会话创建时的连接代；跨代后在途重试发射前复查不通过。</summary>
        internal readonly long TransportEpoch;

        private Line[] _lines;
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
            string sceneId, string mode, int advanceKey, Line[] lines, long transportEpoch)
        {
            _task = task ?? throw new ArgumentNullException(nameof(task));
            RequestId = requestId;
            SceneId = sceneId;
            Mode = mode;
            _advanceKey = advanceKey;
            _lines = lines ?? throw new ArgumentNullException(nameof(lines));
            TransportEpoch = transportEpoch;
        }

        internal int AppliedEpoch { get { return _appliedEpoch; } }
        internal int AdvanceKey { get { return _advanceKey; } }
        internal int RowCount { get { return _lines.Length; } }
        internal int Index { get { return _index; } }
        internal HostState State { get { return _state; } }
        /// <summary>冻结的终态请求串（含 \0）；非 closing 为 null。重试逐字节重发。</summary>
        internal string FrozenWire { get { return _frozenWire; } }
        /// <summary>最近一次 ArmRetry 的注入时钟戳；未布防为 -1（测试观测时钟注入）。</summary>
        internal long RetryArmedAt { get { return _retryArmedAt; } }

        /// <summary>会话起步：呈现 startIndex 行并自驱预取下一句。</summary>
        internal void Begin(int startIndex)
        {
            _index = startIndex;
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
            PrefetchAt(_index + 1);
        }

        private void PrefetchAt(int index)
        {
            if (index >= _lines.Length) return;
            _task.PrefetchBookLine(this, _lines[index]);
        }

        private void EnterClosing(string reason)
        {
            _state = HostState.Closing;
            // 冻结语义：epoch/finalIndex/reason 在入 closing 当下定死，
            // 之后任何重试都逐字节重发同一份请求，绝不从变化后的状态重拼。
            var command = new JObject
            {
                ["task"] = "cmd", ["action"] = "nativeDialogueAction",
                ["requestId"] = RequestId, ["sceneId"] = SceneId,
                ["verb"] = "finish", ["epoch"] = _appliedEpoch,
                ["finalIndex"] = _lines.Length - 1, ["reason"] = reason
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
