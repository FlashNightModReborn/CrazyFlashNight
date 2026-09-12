using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Tooltip;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>dense 检视相位。Idle=无会话或 simple/pinned；pinned 不占用相位（显式生命周期）。</summary>
    internal enum TooltipInspectionPhase
    {
        Idle = 0,
        Scan = 1,
        Pending = 2,
        Inspect = 3
    }

    /// <summary>
    /// 检视控制器的周期泵。生产 = WinForms Timer（UI 线程）；测试 = 手动 Tick。
    /// 只在需要采样的窗口期运行（dense Scan/Pending、simple 悬停持有），Inspect/Idle 停摆。
    /// </summary>
    internal interface ITooltipInspectionPump : IDisposable
    {
        event Action Tick;
        void Start();
        void Stop();
    }

    /// <summary>生产默认泵：System.Windows.Forms.Timer（创建线程的消息泵上 Tick）。</summary>
    internal sealed class WinFormsInspectionPump : ITooltipInspectionPump
    {
        private readonly Timer _timer;
        private readonly Action _tickHandler;

        internal WinFormsInspectionPump(int intervalMs)
        {
            _timer = new Timer();
            _timer.Interval = Math.Max(10, intervalMs);
            _tickHandler = delegate { Action h = Tick; if (h != null) h(); };
            _timer.Tick += delegate(object s, EventArgs e) { _tickHandler(); };
        }

        public void Start() { _timer.Start(); }
        public void Stop() { _timer.Stop(); }
        public void Dispose() { _timer.Dispose(); }
        public event Action Tick;
    }

    /// <summary>
    /// native 视觉投影挂点（native 岗位在 widget 上实现；adapter 探测转发）。
    /// state 与 web data-inspection-state 同值："idle"/"scan"/"pending"/"inspect"。
    /// </summary>
    internal interface ITooltipInspectionProjection
    {
        void SetInspectionState(string state, int remainingMs);
    }

    /// <summary>
    /// native_interaction tooltip 三 profile 交互控制器（独立于 widget/task 的检视状态机）。
    ///
    /// 语义权威 = 迁移前 Web launcher/web/modules/tooltip.js（冻结基线，不按记忆重写）：
    /// - simple-tooltip：复合悬停。owner leave 的 hide 到来时若指针在浮层内（或 140ms 过桥窗
    ///   内进入）则保持展示；离开浮层再经 140ms 宽限才真正 Hide。浮层内滚轮仅实际滚动时消费，
    ///   到边界放行穿透。
    /// - dense-inspect：浮层不命中。show → scan；（desc 可滚时）→ pending（稳定停留
    ///   InspectionDelayMs，默认 1000）→ inspect。快速运动复位计时：相邻样本位移
    ///   ≥MoveTolerancePx 且（速度 ≥SpeedPxPerMs 或位移 ≥3×tolerance）。仅 inspect 态接管
    ///   owner 滚轮且到边界仍消费（不穿透）；scan/pending 一律放行。Esc 在 inspect 退 scan
    ///   （不 hide、不发 cancel）。scan 不因时间自动晋级——需合格运动重新 pending，或同
    ///   requestId 内容刷新按已停留时长补算。内容刷新使 desc 不再可滚时 inspect→scan。
    /// - pinned-inspector：外点（浮层 rect 外且 owner 区外）→ 终结会话（task 发 cancel）。
    ///
    /// owner 命中区：surface.OwnerScreenBounds 存在时严格按它判定（对应 web owner 元素
    /// 命中；native 侧以 ownerRect 或 Flash 客户区兜底填值）。缺失时：
    ///   · 滚轮消费 fail-open（不拦轮——root 约定「不能全桌面拦轮」）；
    ///   · dwell/Esc 判定放行（会话存活≈仍 hover owner，hide 迟到窗口只影响一次 Esc 退出权）。
    /// 会话合法性始终按当前 requestId 校验（root 约定：request/scene + AS2 hide 判会话）。
    ///
    /// 线程：Sync/Tick/TryDeferHide/ExitInspection/TryDismissPinnedAt 在 UI 线程调用；
    /// EscConsumable/TryConsumeWheel 会被输入钩子线程调用——读 volatile 快照 + 锁内校验。
    /// </summary>
    internal sealed class TooltipInspectionController : IDisposable
    {
        internal const int DefaultInspectionDelayMs = 1000;
        internal const double DefaultMoveTolerancePx = 8.0;
        internal const double DefaultSpeedPxPerMs = 0.45;
        internal const int DefaultHoverGraceMs = 140;
        internal const int DefaultPollIntervalMs = 33;

        // 测试可调（生产保持默认）；数值与 web DEFAULT_* 一一对应。
        internal int InspectionDelayMs = DefaultInspectionDelayMs;
        internal double MoveTolerancePx = DefaultMoveTolerancePx;
        internal double SpeedPxPerMs = DefaultSpeedPxPerMs;
        internal int HoverGraceMs = DefaultHoverGraceMs;

        /// <summary>
        /// 不可变会话快照：钩子线程 O(1) 读取（EscConsumable / TryConsumeWheel）。
        /// 每次 UI 线程状态变化后由 UpdateSnapLocked 重建；null = 无活跃 tooltip 会话。
        /// </summary>
        internal sealed class Snapshot
        {
            internal string RequestId;
            internal NativeTooltipProfile Profile;
            internal bool Scrollable;
            internal Rectangle ScreenBounds;
            internal Rectangle? OwnerBounds;
            internal TooltipInspectionPhase Phase;
            internal long PendingRemainingMs;
        }

        private readonly INativeInteractionTooltipSurface _surface;
        private readonly ITooltipInspectionPump _pump;
        private readonly Action _pumpTickHandler;
        private readonly Func<Point> _pointer;
        private readonly Func<long> _now;
        private readonly object _gate = new object();

        private volatile Snapshot _snap;

        // 会话跟踪（_gate 保护，UI 线程写）
        private string _rid;
        private TooltipInspectionPhase _phase;
        private long _dwellStartedAt;
        private long _remainingMs;
        private Point _lastPt;
        private long _lastPtAt;
        private bool _hasLastPt;
        private TooltipInspectionPhase _pushedPhase = TooltipInspectionPhase.Idle;
        private long _pushedRemaining = -1;

        // simple 复合悬停（hide 延迟/持有）
        private string _holdRid;
        private long _holdDeadline;
        private bool _holding;
        private long _holdExitSince = -1;

        /// <summary>相位/剩余时间推送后触发（UI 线程）；native 视觉层可另行订阅。</summary>
        internal event Action ProjectionChanged;

        internal TooltipInspectionController(INativeInteractionTooltipSurface surface)
            : this(surface, null, null, null) { }

        internal TooltipInspectionController(INativeInteractionTooltipSurface surface,
            ITooltipInspectionPump pump, Func<Point> pointerProvider, Func<long> nowMs)
        {
            if (surface == null) throw new ArgumentNullException("surface");
            _surface = surface;
            _pump = pump ?? new WinFormsInspectionPump(DefaultPollIntervalMs);
            _pumpTickHandler = new Action(Tick);
            _pump.Tick += _pumpTickHandler;
            _pointer = pointerProvider ?? DefaultPointer;
            _now = nowMs ?? DefaultNow;
        }

        private static Point DefaultPointer() { return Cursor.Position; }
        private static long DefaultNow() { return Environment.TickCount64; }

        // ── 只读探针（钩子线程安全） ─────────────────────────────────

        /// <summary>当前快照（null = 无会话）。诊断/测试/native 视觉层用。</summary>
        internal Snapshot GetSnapshot() { return _snap; }

        /// <summary>当前相位（无会话 = Idle）。</summary>
        internal TooltipInspectionPhase CurrentPhase
        {
            get { Snapshot s = _snap; return s != null ? s.Phase : TooltipInspectionPhase.Idle; }
        }

        /// <summary>
        /// ESC 消费探针（KeyboardHook 线程，O(1)）：dense 处于 inspect 且指针仍在 owner 上。
        /// 对应 web noteKeyboardInput 的 canRestorePointer 分支；owner 区缺失时放行
        /// （Esc 只退检视，低风险；应用未前台时 KeyboardHook 自身已拦不下来）。
        /// </summary>
        internal bool EscConsumable
        {
            get
            {
                Snapshot s = _snap;
                if (s == null || s.Profile != NativeTooltipProfile.Dense
                    || s.Phase != TooltipInspectionPhase.Inspect) return false;
                if (!s.OwnerBounds.HasValue) return true;
                Point pt;
                try { pt = _pointer(); } catch { return false; }
                return s.OwnerBounds.Value.Contains(pt);
            }
        }

        /// <summary>
        /// 滚轮消费仲裁（输入探针线程）：
        /// - dense：仅 inspect 态 + 指针在 owner 区内 → 滚动并恒消费（含边界，不穿透）；
        ///   scan/pending 一律放行；owner 区缺失时不拦轮（root 约定）。
        /// - simple：指针在浮层 rect 内且可滚 → 仅实际滚动才消费（边界放行）。
        /// - pinned 由 widget.OnMouseWheel 先行处理（框内恒消费），本函数不再承接。
        /// </summary>
        internal bool TryConsumeWheel(int screenX, int screenY, int wheelDelta)
        {
            Snapshot s = _snap;
            if (s == null) return false;
            // 迟到防护：快照身份必须仍是当前实例
            string cur;
            try { cur = _surface.CurrentRequestId; } catch { return false; }
            if (!string.Equals(cur, s.RequestId, StringComparison.Ordinal)) return false;

            Point pt = new Point(screenX, screenY);
            if (s.Profile == NativeTooltipProfile.Dense)
            {
                if (s.Phase != TooltipInspectionPhase.Inspect) return false;
                if (!s.OwnerBounds.HasValue || !s.OwnerBounds.Value.Contains(pt)) return false;
                return ConsumeScroll(wheelDelta, true);
            }
            if (s.Profile == NativeTooltipProfile.Simple)
            {
                if (!s.Scrollable || !s.ScreenBounds.Contains(pt)) return false;
                return ConsumeScroll(wheelDelta, false);
            }
            return false;
        }

        private bool ConsumeScroll(int wheelDelta, bool consumeAtBoundary)
        {
            int notches = wheelDelta / 120;
            if (notches == 0) notches = wheelDelta > 0 ? 1 : -1;
            bool scrolled = false;
            try { scrolled = _surface.ScrollByLines(-notches * 3); }
            catch (Exception ex) { LogManager.Log("[NativeInteraction] inspect scroll throw: " + ex.Message); }
            return consumeAtBoundary || scrolled;
        }

        // ── task 通知面（UI 线程） ─────────────────────────────────

        /// <summary>
        /// 与 surface 当前文档对账：新 requestId → 开新会话（dwell 重新计时）；
        /// 同 requestId → 内容刷新语义（web updateContent → contentChanged）；
        /// 无文档 → 全清。show/hide/reset/suppress/dismiss 后由 task 调用。
        /// </summary>
        internal void Sync()
        {
            bool fire = false;
            lock (_gate)
            {
                NativeTooltipDocument doc = SafeDoc();
                if (doc == null)
                {
                    fire = TeardownLocked();
                }
                else if (string.Equals(doc.RequestId, _rid, StringComparison.Ordinal))
                {
                    fire = ContentChangedLocked(doc);
                }
                else
                {
                    fire = BeginSessionLocked(doc);
                }
            }
            if (fire) FireProjection();
        }

        /// <summary>
        /// simple hide 延迟判定：仅当当前实例是 simple 且 requestId 匹配时接管——
        /// 140ms 过桥窗内指针进入浮层 → 保持；到点仍在外 → 真正 Hide。
        /// 返回 true 时调用方不得再执行 Hide（本控制器稍后按条件代执行）。
        /// dense/pinned/身份不符一律 false（hide 立即生效）。
        /// </summary>
        internal bool TryDeferHide(string requestId)
        {
            bool fire = false;
            lock (_gate)
            {
                NativeTooltipDocument doc = SafeDoc();
                if (doc == null || doc.Profile != NativeTooltipProfile.Simple
                    || !string.Equals(doc.RequestId, requestId, StringComparison.Ordinal))
                    return false;
                _holdRid = requestId;
                _holdDeadline = _now() + HoverGraceMs;
                _holdExitSince = -1;
                // 指针已在浮层内 → 直接 held（web pointerTargetsTooltip 在到点时同样判真）
                _holding = InsideTooltipLocked();
                UpdatePumpLocked();
                fire = UpdateSnapLocked();
            }
            if (fire) FireProjection();
            return true;
        }

        /// <summary>
        /// pinned 外点关闭（web outsideClick）：点在浮层 rect 外且不在 owner 区内 →
        /// Hide 当前实例并返回其 requestId（调用方据先行快照的 sceneId 发 cancel）。
        /// 返回 null = 非 pinned / 点在界内 / 实例已轮换。
        /// </summary>
        internal string TryDismissPinnedAt(int screenX, int screenY)
        {
            Snapshot s = _snap;
            if (s == null || s.Profile != NativeTooltipProfile.Pinned) return null;
            Point pt = new Point(screenX, screenY);
            if (s.ScreenBounds.Contains(pt)) return null;
            if (s.OwnerBounds.HasValue && s.OwnerBounds.Value.Contains(pt)) return null;
            string rid = s.RequestId;
            bool fire = false;
            lock (_gate)
            {
                // 迟到防护：当前实例可能已轮换
                if (!string.Equals(_surface.CurrentRequestId, rid, StringComparison.Ordinal))
                    return null;
                try { _surface.Hide(rid); }
                catch (Exception ex)
                {
                    LogManager.Log("[NativeInteraction] pinned outside-dismiss hide throw: " + ex.Message);
                    return null;
                }
                fire = TeardownLocked();
            }
            if (fire) FireProjection();
            return rid;
        }

        /// <summary>
        /// Esc 退检视（UI 线程）：dense inspect → scan。不 hide、不重置停留计时
        /// （web resetInspectionProjection 语义——此后合格运动重新 pending，
        /// 同 requestId 内容刷新按已停留时长可能立即回 inspect）。
        /// </summary>
        internal bool ExitInspection()
        {
            bool fire = false;
            lock (_gate)
            {
                NativeTooltipDocument doc = SafeDoc();
                if (doc == null || doc.Profile != NativeTooltipProfile.Dense
                    || _phase != TooltipInspectionPhase.Inspect
                    || !string.Equals(doc.RequestId, _rid, StringComparison.Ordinal))
                    return false;
                _phase = TooltipInspectionPhase.Scan;
                UpdatePumpLocked();
                fire = UpdateSnapLocked();
            }
            if (fire) FireProjection();
            return true;
        }

        // ── 泵驱动（UI 线程；测试手动调用） ─────────────────────────

        /// <summary>
        /// 周期采样：指针运动判定 + pending 倒计时晋级 + simple 悬停持有窗口。
        /// 幂等；会话被外部终结时对账清场并自停泵。
        /// </summary>
        internal void Tick()
        {
            bool fire = false;
            lock (_gate)
            {
                NativeTooltipDocument doc = SafeDoc();
                if (doc == null)
                {
                    fire = TeardownLocked();
                }
                else if (!string.Equals(doc.RequestId, _rid, StringComparison.Ordinal))
                {
                    fire = BeginSessionLocked(doc);
                }
                else
                {
                    fire = TickHoldLocked(doc);
                    fire = TickDwellLocked(doc) || fire;
                    fire = UpdateSnapLocked() || fire;
                }
            }
            if (fire) FireProjection();
        }

        public void Dispose()
        {
            _pump.Tick -= _pumpTickHandler;
            lock (_gate) { TeardownLocked(); }
            _pump.Dispose();
        }

        // ── 内部状态机（_gate 内） ─────────────────────────────────

        private NativeTooltipDocument SafeDoc()
        {
            try { return _surface.ActiveDocument; }
            catch (Exception ex) { LogManager.Log("[NativeInteraction] inspect doc read throw: " + ex.Message); return null; }
        }

        private bool SafeScrollable()
        {
            try { return _surface.Scrollable; } catch { return false; }
        }

        private Rectangle SafeScreenBounds()
        {
            try { return _surface.ScreenBounds; } catch { return Rectangle.Empty; }
        }

        private Rectangle? SafeOwnerBounds()
        {
            try { return _surface.OwnerScreenBounds; } catch { return null; }
        }

        private bool PointerOverOwnerLocked()
        {
            Rectangle? bounds = SafeOwnerBounds();
            if (!bounds.HasValue) return true;   // 无 owner 几何：会话存活即 owner 上下文
            Point pt;
            try { pt = _pointer(); } catch { return false; }
            return bounds.Value.Contains(pt);
        }

        private bool InsideTooltipLocked()
        {
            Rectangle b = SafeScreenBounds();
            if (b.Width <= 0 || b.Height <= 0) return false;
            Point pt;
            try { pt = _pointer(); } catch { return false; }
            return b.Contains(pt);
        }

        private bool BeginSessionLocked(NativeTooltipDocument doc)
        {
            _rid = doc.RequestId;
            _holdRid = null; _holding = false; _holdExitSince = -1;
            _dwellStartedAt = _now();
            _lastPtAt = _dwellStartedAt;
            try { _lastPt = _pointer(); _hasLastPt = true; } catch { _hasLastPt = false; }
            if (doc.Profile == NativeTooltipProfile.Dense)
            {
                // web beginInspectionDwell→refreshInspectionDwell：可滚→pending(全程)，否则 scan
                RefreshDwellLocked(doc);
            }
            else
            {
                _phase = TooltipInspectionPhase.Idle;
                _remainingMs = 0;
            }
            UpdatePumpLocked();
            UpdateSnapLocked();
            return true;
        }

        private bool ContentChangedLocked(NativeTooltipDocument doc)
        {
            if (doc.Profile != NativeTooltipProfile.Dense)
            {
                _phase = TooltipInspectionPhase.Idle;
                _remainingMs = 0;
            }
            else if (_phase == TooltipInspectionPhase.Inspect)
            {
                // web：inspecting 且不再可滚 → 回 scan；仍可滚保持 inspect
                if (!SafeScrollable()) _phase = TooltipInspectionPhase.Scan;
            }
            else
            {
                // web onInspectionContentChanged→refreshInspectionDwell：按已停留补算，
                // 停够即直接 inspect（含 Esc→scan 后的刷新回检）
                RefreshDwellLocked(doc);
            }
            UpdatePumpLocked();
            return UpdateSnapLocked();
        }

        /// <summary>web refreshInspectionDwell：非可滚/指针离主 → scan；停够 → inspect；否则 pending(remaining)。</summary>
        private void RefreshDwellLocked(NativeTooltipDocument doc)
        {
            if (!SafeScrollable() || !PointerOverOwnerLocked())
            {
                _phase = TooltipInspectionPhase.Scan;
                _remainingMs = 0;
                return;
            }
            long elapsed = Math.Max(0, _now() - _dwellStartedAt);
            long remaining = InspectionDelayMs - elapsed;
            if (remaining <= 0) { ActivateLocked(); return; }
            _phase = TooltipInspectionPhase.Pending;
            _remainingMs = remaining;
        }

        private void ActivateLocked()
        {
            _phase = TooltipInspectionPhase.Inspect;
            _remainingMs = 0;
        }

        private bool TickDwellLocked(NativeTooltipDocument doc)
        {
            if (doc.Profile != NativeTooltipProfile.Dense) return false;
            if (_phase != TooltipInspectionPhase.Scan && _phase != TooltipInspectionPhase.Pending)
                return false;

            long now = _now();
            Point pt;
            try { pt = _pointer(); } catch { return false; }
            // web 的运动判定只统计落在 owner 上的指针事件——区外采样不进基线，
            // 否则「离开又回入 owner」会被误判成一次巨大位移而复位计时。
            bool overOwner = PointerOverOwnerLocked();
            bool moved = false;
            if (_hasLastPt && overOwner)
            {
                double dx = pt.X - _lastPt.X, dy = pt.Y - _lastPt.Y;
                double dist = Math.Sqrt(dx * dx + dy * dy);
                long dt = Math.Max(1, now - _lastPtAt);
                // web noteInspectionMotion：位移≥tolerance 且（速度≥阈值 或 位移≥3×tolerance）→ 重计时
                if (dist >= MoveTolerancePx
                    && (dist / dt >= SpeedPxPerMs || dist >= MoveTolerancePx * 3))
                {
                    _dwellStartedAt = now;
                    moved = true;
                }
            }
            if (overOwner) { _lastPt = pt; _lastPtAt = now; _hasLastPt = true; }

            if (moved)
            {
                RefreshDwellLocked(doc);
            }
            else if (_phase == TooltipInspectionPhase.Pending)
            {
                long remaining = InspectionDelayMs - Math.Max(0, now - _dwellStartedAt);
                _remainingMs = Math.Max(0, remaining);
                if (remaining <= 0) ActivateLocked();
            }
            UpdatePumpLocked();
            return moved;
        }

        private bool TickHoldLocked(NativeTooltipDocument doc)
        {
            if (_holdRid == null) return false;
            if (!string.Equals(doc.RequestId, _holdRid, StringComparison.Ordinal))
            {
                _holdRid = null; _holding = false; _holdExitSince = -1;
                UpdatePumpLocked();
                return false;
            }
            bool inside = InsideTooltipLocked();
            long now = _now();
            if (!_holding)
            {
                if (inside) { _holding = true; _holdExitSince = -1; return false; }
                if (now >= _holdDeadline) { ApplyHeldHideLocked(); return true; }
                return false;
            }
            if (inside) { _holdExitSince = -1; return false; }
            if (_holdExitSince < 0) { _holdExitSince = now; return false; }
            if (now - _holdExitSince >= HoverGraceMs) { ApplyHeldHideLocked(); return true; }
            return false;
        }

        /// <summary>宽限耗尽：代执行 AS2 发起的 hide（不回包），随后对账清场。</summary>
        private void ApplyHeldHideLocked()
        {
            string rid = _holdRid;
            _holdRid = null; _holding = false; _holdExitSince = -1;
            try { _surface.Hide(rid); }
            catch (Exception ex) { LogManager.Log("[NativeInteraction] held hide throw: " + ex.Message); }
            TeardownLocked();
        }

        private bool TeardownLocked()
        {
            bool had = _rid != null || _holdRid != null || _phase != TooltipInspectionPhase.Idle;
            _rid = null;
            _phase = TooltipInspectionPhase.Idle;
            _remainingMs = 0;
            _hasLastPt = false;
            _holdRid = null; _holding = false; _holdExitSince = -1;
            UpdatePumpLocked();
            _snap = null;
            PushProjectionLocked("idle", 0);
            return had;
        }

        private void UpdatePumpLocked()
        {
            bool want = _holdRid != null
                || _phase == TooltipInspectionPhase.Scan
                || _phase == TooltipInspectionPhase.Pending;
            try
            {
                if (want) _pump.Start(); else _pump.Stop();
            }
            catch (Exception ex) { LogManager.Log("[NativeInteraction] inspect pump throw: " + ex.Message); }
        }

        private bool UpdateSnapLocked()
        {
            NativeTooltipDocument doc = SafeDoc();
            if (doc == null || !string.Equals(doc.RequestId, _rid, StringComparison.Ordinal))
            {
                bool had = _snap != null;
                _snap = null;
                PushProjectionLocked("idle", 0);
                return had;
            }
            _snap = new Snapshot
            {
                RequestId = doc.RequestId,
                Profile = doc.Profile,
                Scrollable = SafeScrollable(),
                ScreenBounds = SafeScreenBounds(),
                OwnerBounds = SafeOwnerBounds(),
                Phase = _phase,
                PendingRemainingMs = _remainingMs
            };
            // 投影推送：相位迁移必推；pending 内剩余时间变化也推（web 每次 setInspectionState
            // 都更新 meter）。Scan/Idle 不逐 tick 推。
            if (_phase != _pushedPhase
                || (_phase == TooltipInspectionPhase.Pending && _remainingMs != _pushedRemaining))
            {
                PushProjectionLocked(StateName(_phase), (int)Math.Max(0, _remainingMs));
            }
            return true;
        }

        private static string StateName(TooltipInspectionPhase phase)
        {
            switch (phase)
            {
                case TooltipInspectionPhase.Scan: return "scan";
                case TooltipInspectionPhase.Pending: return "pending";
                case TooltipInspectionPhase.Inspect: return "inspect";
                default: return "idle";
            }
        }

        private void PushProjectionLocked(string state, int remainingMs)
        {
            _pushedPhase = state == "pending" ? TooltipInspectionPhase.Pending
                : state == "scan" ? TooltipInspectionPhase.Scan
                : state == "inspect" ? TooltipInspectionPhase.Inspect
                : TooltipInspectionPhase.Idle;
            _pushedRemaining = state == "pending" ? remainingMs : -1;
            try { _surface.SetInspectionState(state, remainingMs); }
            catch (Exception ex) { LogManager.Log("[NativeInteraction] inspection projection throw: " + ex.Message); }
        }

        private void FireProjection()
        {
            Action h = ProjectionChanged;
            if (h == null) return;
            try { h(); }
            catch (Exception ex) { LogManager.Log("[NativeInteraction] projection handler throw: " + ex.Message); }
        }
    }
}
