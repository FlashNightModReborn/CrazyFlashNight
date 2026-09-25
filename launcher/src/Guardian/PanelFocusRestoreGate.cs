using System;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Web panel focus requests can outlive the message-loop turn that scheduled them.  This
    /// state-only gate keeps those callbacks bound to the panel generation that created them and
    /// suppresses the activation echo caused by SetForegroundWindow.  It deliberately contains
    /// no HWND/WebView2 code so the race policy can be covered by ordinary unit tests.
    /// </summary>
    internal sealed class PanelFocusRestoreGate
    {
        internal const long DebounceMilliseconds = 200;

        private readonly object _sync = new object();
        private int _generation;
        private int _queuedGeneration;
        private int _lastAttemptGeneration;
        private long _lastAttemptTick = long.MinValue;

        internal int BeginPanel()
        {
            lock (_sync)
            {
                _generation = _generation == int.MaxValue ? 1 : _generation + 1;
                _queuedGeneration = 0;
                return _generation;
            }
        }

        internal void EndPanel()
        {
            lock (_sync)
            {
                _queuedGeneration = 0;
            }
        }

        internal bool TryQueue(bool takeForeground, bool panelMode, bool disposed,
            long nowTick, out int generation)
        {
            lock (_sync)
            {
                generation = _generation;
                if (!takeForeground || !panelMode || disposed || generation <= 0)
                    return false;
                if (_queuedGeneration == generation
                    || IsDebouncedLocked(generation, nowTick))
                    return false;
                _queuedGeneration = generation;
                return true;
            }
        }

        internal bool TryBeginExecution(int scheduledGeneration, bool takeForeground,
            bool panelMode, bool disposed, bool foregroundEligible, long nowTick)
        {
            lock (_sync)
            {
                if (!takeForeground || !panelMode || disposed || !foregroundEligible
                    || scheduledGeneration <= 0 || scheduledGeneration != _generation
                    || scheduledGeneration != _queuedGeneration
                    || IsDebouncedLocked(scheduledGeneration, nowTick))
                    return false;
                return true;
            }
        }

        internal bool TryCommitExecution(int scheduledGeneration, bool takeForeground,
            bool panelMode, bool disposed, long nowTick)
        {
            lock (_sync)
            {
                if (!takeForeground || !panelMode || disposed)
                    return false;
                if (scheduledGeneration <= 0
                    || scheduledGeneration != _generation
                    || scheduledGeneration != _queuedGeneration
                    || IsDebouncedLocked(scheduledGeneration, nowTick))
                    return false;

                _lastAttemptGeneration = scheduledGeneration;
                _lastAttemptTick = nowTick;
                return true;
            }
        }

        internal bool IsCurrentExecution(int scheduledGeneration, bool takeForeground,
            bool panelMode, bool disposed)
        {
            lock (_sync)
            {
                return takeForeground && panelMode && !disposed
                    && scheduledGeneration > 0
                    && scheduledGeneration == _generation
                    && scheduledGeneration == _queuedGeneration;
            }
        }

        internal void Complete(int scheduledGeneration)
        {
            lock (_sync)
            {
                if (_queuedGeneration == scheduledGeneration)
                    _queuedGeneration = 0;
            }
        }

        private bool IsDebouncedLocked(int generation, long nowTick)
        {
            if (_lastAttemptGeneration != generation || _lastAttemptTick == long.MinValue)
                return false;
            long elapsed = nowTick - _lastAttemptTick;
            return elapsed >= 0 && elapsed < DebounceMilliseconds;
        }
    }

    /// <summary>前台看门狗一次前台采样的会话归属分类。</summary>
    internal enum SessionForegroundOwnership
    {
        /// <summary>GetForegroundWindow()==NULL：前台真空，没有任何窗口持有前台。</summary>
        Null,
        /// <summary>前台窗口属于本会话（Guardian / Flash 进程窗口，含 overlay/宿主交接途经的窗口）。</summary>
        Session,
        /// <summary>前台窗口属于真实外部进程：用户确实去了别的程序。</summary>
        External
    }

    /// <summary>
    /// A0.2 — NULL 前台看门狗的决策策略：真空连续确认、恢复资格与输出节流。
    ///
    /// 连续观察到 GetForegroundWindow()==NULL 只证明"没人持有前台"，不证明用户
    /// 允许游戏夺回——真空持续时间本身不构成意图，计时器不能自行创造恢复资格。
    /// 资格只有两个来源：
    ///   • 仍有效的用户返回：本进程最近一次合法激活（WM_ACTIVATEAPP(true)，
    ///     用户切回/点击回来）之后，尚未观察到真实外部前台持有；
    ///   • 会话内交接仍有效：本会话窗口持有真实前台——面板/宿主交接途经自己
    ///     的窗口时资格同样保持。
    /// 失效：任一次采样看到真实外部窗口持有前台（用户确实去了别处）、
    ///   本进程失活（WM_ACTIVATEAPP(false)）、或进入任一抑制段（锁屏/最小化/
    ///   面板模式）——穿越边界后资格不存活，直到下一次合法激活或会话前台重建。
    ///   历史激活不是无限期许可：失活与抑制都代表"当前这次用户返回"已结束。
    /// NULL 采样中性：既不授予也不撤销——真空是"无人持有"，不是意图证据。
    ///
    /// 与 PanelFocusRestoreGate 同为纯状态机：无 HWND/Win32 依赖；
    /// 仅 GuardianForm 的 UI 线程调用（OnSessionActivated 来自 WndProc，
    /// OnForegroundTick/OnSuppressedTick 来自看门狗 timer）。
    /// </summary>
    internal sealed class ForegroundVacuumWatchdogPolicy
    {
        /// <summary>真空须连续命中的 tick 数（400ms tick × 2 ≈ 800ms）。</summary>
        internal const int VacuumConfirmStreak = 2;
        /// <summary>Observe / Restore 两类输出共用的节流窗（毫秒）。</summary>
        internal const int EmitThrottleMilliseconds = 2000;

        internal enum Decision
        {
            /// <summary>本 tick 无输出：前台非真空、真空仍在确认中、或仍在节流窗内。</summary>
            Skip,
            /// <summary>持续真空但无恢复资格：仅观察日志，零恢复调用。</summary>
            Observe,
            /// <summary>持续真空且资格仍有效：执行恢复。</summary>
            Restore
        }

        internal enum ClaimSource
        {
            None,
            /// <summary>WM_ACTIVATEAPP(true)：用户返回 / 本进程合法激活成立。</summary>
            SessionActivation,
            /// <summary>采样到本会话窗口持有真实前台（含会话内交接途经）。</summary>
            SessionForeground
        }

        private bool _claimLive;
        private ClaimSource _lastClaimSource = ClaimSource.None;
        private int _vacuumStreak;
        private int _lastEmitTick = int.MinValue;

        /// <summary>当前是否具备恢复资格（OnForegroundTick 执行前复核的就是该值）。</summary>
        internal bool IsRestoreEligible { get { return _claimLive; } }

        /// <summary>最近一次资格授予的来源（诊断/日志归属用）。</summary>
        internal ClaimSource LastClaimSource { get { return _lastClaimSource; } }

        /// <summary>WM_ACTIVATEAPP(true)：本进程合法激活成立 → 资格基线重建。</summary>
        internal void OnSessionActivated()
        {
            _claimLive = true;
            _lastClaimSource = ClaimSource.SessionActivation;
        }

        /// <summary>WM_ACTIVATEAPP(false)：本进程失活 → 当前这次用户返回已结束，撤销资格。</summary>
        internal void OnSessionDeactivated()
        {
            _claimLive = false;
            _lastClaimSource = ClaimSource.None;
        }

        /// <summary>
        /// 执行前复核：策略决策与真正 SetForegroundWindow 之间前台可能已变
        /// （外部窗口先拿到前台）。调用方在执行恢复前必须以最新采样调用本方法；
        /// 样本按既有规则更新资格（Session 授予 / External 撤销 / NULL 中性），
        /// 返回复核后的当前资格。
        /// </summary>
        internal bool RecheckEligibility(SessionForegroundOwnership foreground)
        {
            if (foreground == SessionForegroundOwnership.Session)
            {
                _claimLive = true;
                _lastClaimSource = ClaimSource.SessionForeground;
            }
            else if (foreground == SessionForegroundOwnership.External)
            {
                _claimLive = false;
                _lastClaimSource = ClaimSource.None;
            }
            return _claimLive;
        }

        /// <summary>
        /// 被守卫抑制的 tick（锁屏 / 非 Ready / 最小化 / 面板模式 / 无 WindowManager）：
        /// 真空计数清零并撤销资格——抑制段内不采样前台，期间资格存续无法复核，
        /// 穿越抑制边界后必须由新的合法激活或会话前台样本重建。
        /// </summary>
        internal void OnSuppressedTick()
        {
            _vacuumStreak = 0;
            _claimLive = false;
            _lastClaimSource = ClaimSource.None;
        }

        /// <summary>
        /// 每个未抑制 tick 的唯一入口：先喂前台归属更新资格，再做真空确认与节流，
        /// 资格判定落在确认与节流通过之后——即"执行前复核"以最新状态为准。
        /// </summary>
        internal Decision OnForegroundTick(
            SessionForegroundOwnership foreground,
            int nowTick)
        {
            if (foreground == SessionForegroundOwnership.Session)
            {
                _claimLive = true;
                _lastClaimSource = ClaimSource.SessionForeground;
            }
            else if (foreground == SessionForegroundOwnership.External)
            {
                _claimLive = false;
                _lastClaimSource = ClaimSource.None;
            }
            // Null：中性证据，资格原样保留

            if (foreground != SessionForegroundOwnership.Null)
            {
                _vacuumStreak = 0;
                return Decision.Skip;
            }

            // 焦点真空须【连续】命中：正常前台交接过程中 GetForegroundWindow()
            // 会瞬时返回 NULL，单帧采样会与用户主动切换竞态——≥2 次连续命中才
            // 视作"持续真空"进入资格判定。
            if (_vacuumStreak < int.MaxValue) _vacuumStreak++;
            if (_vacuumStreak < VacuumConfirmStreak) return Decision.Skip;

            // 节流：Observe 与 Restore 共用同一输出窗——持续真空无论有无资格，
            // 都不会每 400ms 刷一条 [FgWatchdog] 日志。
            int elapsed = unchecked(nowTick - _lastEmitTick);
            if (_lastEmitTick != int.MinValue
                && elapsed >= 0 && elapsed < EmitThrottleMilliseconds)
                return Decision.Skip;

            _lastEmitTick = nowTick;
            return _claimLive ? Decision.Restore : Decision.Observe;
        }
    }
}
