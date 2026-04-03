using System;
using CF7Launcher.Bus;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 性能决策引擎：统计阈值 + 迟滞确认，替代 AS2 端的 Kalman+PID。
    ///
    /// 数学基础：PID 已被证明退化为阈值生成器（Proposition 1, 97.4% 积分饱和率），
    /// 迟滞量化器是实际控制权威（69 候选 vs 25 实际切换）。
    /// 本引擎直接实现等价的阈值+迟滞逻辑。
    ///
    /// 数据流：
    ///   AS2 PerformanceScheduler.evaluate()
    ///     → FrameBroadcaster.setFpsPayload("fps|hour|level")
    ///     → FrameTask.HandleRaw() → FpsRingBuffer.Push()
    ///     → PerfDecisionEngine.Evaluate()（本类，内联在 HandleRaw 中）
    ///     → XmlSocketServer.PushToClient("P{tier}|{softU100}")
    ///     → AS2 applyFromLauncher()
    /// </summary>
    public class PerfDecisionEngine
    {
        // --- 依赖 ---
        private readonly FpsRingBuffer _buffer;
        private readonly XmlSocketServer _socket;
        private WindowManager _windowManager; // 延迟注入，可为 null（bus-only 模式）

        // --- 配置常量 ---
        private const float TARGET_FPS = 26f;
        private const float DOWNGRADE_THRESHOLD = 18f;
        private const float PANIC_FPS = 5f;
        private const int DOWNGRADE_CONFIRM = 2;
        private const int UPGRADE_CONFIRM = 3;
        private const int DOWNGRADE_CONFIRM_JITTER = 3;  // 高抖动时更保守
        private const int UPGRADE_CONFIRM_JITTER = 4;
        private const float JITTER_VARIANCE_THRESHOLD = 25f; // 方差阈值
        private const int DECISION_WINDOW = 5;
        private const int TREND_WINDOW = 10;
        private const int WARMUP_SAMPLES = 5;
        private const float SOFTU_SEND_THRESHOLD = 0.15f;
        private const int KEEPALIVE_MS = 3000;

        // --- 状态 ---
        private int _currentTier;
        private int _confirmCount;
        private int _pendingDirection; // +1=降级, -1=升级, 0=无
        private float _lastSentSoftU;
        private int _lastSendTicks;
        private int _focusCooldownMs;
        private int _lastEvalTicks; // 上次 Evaluate 时间，用于计算 elapsed
        private const int STALE_GAP_MS = 15000; // 15秒无样本视为断线过，触发 warmup

        // --- 模式 ---
        /// <summary>
        /// true = 主控模式（发送 P 指令到 AS2）；
        /// false = 影子模式（仅日志对比，不发送）。
        /// </summary>
        public bool IsActive { get; set; }

        public PerfDecisionEngine(FpsRingBuffer buffer, XmlSocketServer socket)
        {
            _buffer = buffer;
            _socket = socket;
            _currentTier = 0;
            _confirmCount = 0;
            _pendingDirection = 0;
            _lastSentSoftU = 0f;
            _lastSendTicks = Environment.TickCount;
            _lastEvalTicks = Environment.TickCount;
            _focusCooldownMs = 0;
            IsActive = false;
        }

        public void SetWindowManager(WindowManager wm)
        {
            _windowManager = wm;
        }

        /// <summary>
        /// 每次 FPS 采样到达时由 FrameTask.HandleRaw 调用。
        /// 返回决策 (tier, softU) 或 null（无变更）。
        /// </summary>
        public PerfDecision? Evaluate()
        {
            int now = Environment.TickCount;
            int elapsedMs = now - _lastEvalTicks;
            _lastEvalTicks = now;

            // 0a. 断线间隙检测：如果距上次样本 > 15秒，可能断线期间切了场景，
            // 强制触发 warmup（等价于 NotifySceneReset）
            if (elapsedMs > STALE_GAP_MS)
            {
                _buffer.NotifySceneReset();
                OnSceneReset();
            }

            // 0b. 从 AS2 上报值同步当前 tier（单一真实来源）
            _currentTier = _buffer.PerfLevel;

            // 1. Warmup 保护：场景切换后积累期不决策
            int samplesAfterReset = _buffer.SamplesAfterReset;
            if (samplesAfterReset < WARMUP_SAMPLES)
                return null;
            bool trendAvailable = (samplesAfterReset >= TREND_WINDOW);

            // 2. 失焦门控（必须先于 panic）
            if (_windowManager != null && !_windowManager.IsFlashForeground())
            {
                _focusCooldownMs = 3000;
                return null;
            }
            if (_focusCooldownMs > 0)
            {
                _focusCooldownMs -= elapsedMs;
                return null;
            }

            // 3. 紧急降级
            float latest = _buffer.Latest;
            if (latest < PANIC_FPS && _currentTier < 1)
            {
                _confirmCount = 0;
                _pendingDirection = 0;
                return MakeDecision(1, 1.0f, now);
            }

            // 4. 统计计算
            float mean5 = _buffer.WindowAverage(DECISION_WINDOW);
            float trend10 = trendAvailable ? _buffer.Trend(TREND_WINDOW) : 0f;

            // 5. softU: [18,26] → [1,0] 线性映射
            float softU = (TARGET_FPS - mean5) / 8f;
            if (softU < 0f) softU = 0f;
            if (softU > 1f) softU = 1f;

            // 6. 迟滞确认（方差自适应阈值）
            float var10 = trendAvailable ? _buffer.Variance(TREND_WINDOW) : 0f;
            bool jittery = (var10 > JITTER_VARIANCE_THRESHOLD);
            int downThresh = jittery ? DOWNGRADE_CONFIRM_JITTER : DOWNGRADE_CONFIRM;
            int upThresh = jittery ? UPGRADE_CONFIRM_JITTER : UPGRADE_CONFIRM;

            int newTier = _currentTier;
            if (mean5 < DOWNGRADE_THRESHOLD)
            {
                // 降级方向
                AccumulateConfirmation(1);
                if (_confirmCount >= downThresh)
                {
                    newTier = 1;
                    _confirmCount = 0;
                    _pendingDirection = 0;
                }
            }
            else if (mean5 > TARGET_FPS && trend10 >= 0f)
            {
                // 升级方向
                AccumulateConfirmation(-1);
                if (_confirmCount >= upThresh)
                {
                    newTier = 0;
                    _confirmCount = 0;
                    _pendingDirection = 0;
                }
            }
            else
            {
                // 与当前一致，清零
                _confirmCount = 0;
                _pendingDirection = 0;
            }

            // 7. 发送判定
            bool tierChanged = (newTier != _currentTier);
            float softUDelta = softU - _lastSentSoftU;
            if (softUDelta < 0) softUDelta = -softUDelta;
            bool softUChanged = (softUDelta > SOFTU_SEND_THRESHOLD);
            bool keepalive = (now - _lastSendTicks >= KEEPALIVE_MS);

            if (tierChanged || softUChanged || keepalive)
            {
                return MakeDecision(newTier, softU, now);
            }
            return null;
        }

        private void AccumulateConfirmation(int direction)
        {
            if (_confirmCount > 0 && direction == _pendingDirection)
            {
                _confirmCount++;
            }
            else
            {
                _pendingDirection = direction;
                _confirmCount = 1;
            }
        }

        private PerfDecision MakeDecision(int tier, float softU, int now)
        {
            _lastSentSoftU = softU;
            _lastSendTicks = now;
            return new PerfDecision { Tier = tier, SoftU = softU };
        }

        /// <summary>发送 P 指令到 AS2 并记录日志。</summary>
        public void SendCommand(PerfDecision decision)
        {
            int softU100 = (int)(decision.SoftU * 100f + 0.5f);
            if (softU100 > 100) softU100 = 100;
            if (softU100 < 0) softU100 = 0;
            string cmd = "P" + decision.Tier + "|" + softU100;
            _socket.PushToClient(cmd);

            float mean5 = _buffer.WindowAverage(DECISION_WINDOW);
            float trend10 = _buffer.Trend(TREND_WINDOW);
            LogManager.Log(string.Format(
                "[PerfActive] fps={0:F1} mean5={1:F1} trend10={2:F2} softU={3:F2} warmup={4} | sent={5}",
                _buffer.Latest, mean5, trend10, decision.SoftU,
                _buffer.SamplesAfterReset, cmd));
        }

        /// <summary>影子模式：记录 C# 决策与 AS2 实际档位的对比日志。</summary>
        public void LogShadowComparison(PerfDecision decision)
        {
            int as2Level = _buffer.PerfLevel;
            float mean5 = _buffer.WindowAverage(DECISION_WINDOW);
            float trend10 = _buffer.Trend(TREND_WINDOW);
            string agree = (decision.Tier == as2Level) ? "AGREE" : "DISAGREE";
            LogManager.Log(string.Format(
                "[PerfShadow] fps={0:F1} mean5={1:F1} trend10={2:F2} softU={3:F2} warmup={4} | AS2=L{5} CS=L{6} {7}",
                _buffer.Latest, mean5, trend10, decision.SoftU,
                _buffer.SamplesAfterReset, as2Level, decision.Tier, agree));
        }

        /// <summary>场景重置回调。</summary>
        public void OnSceneReset()
        {
            _confirmCount = 0;
            _pendingDirection = 0;
            _focusCooldownMs = 0;
        }
    }

    public struct PerfDecision
    {
        public int Tier;
        public float SoftU;
    }
}
