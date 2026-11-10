using System;
using System.Diagnostics;

namespace CF7Launcher.Guardian
{
    internal sealed class PerfTelemetrySnapshot
    {
        internal int? ConnectionGeneration;
        internal long? HostFrameOrdinal;
        internal int? SourceScene;
        internal long? SourceSampleSequence;
        internal long? SampleFrame;
        internal long? StalenessFrames;
        internal double? SampleAgeMs;
        internal long? AcceptedSampleFrame;
        internal long? AcceptedStalenessFrames;
        internal double? AcceptedSampleAgeMs;
        internal double? FrameIngressAgeMs;
        internal double? TransportAgeMs;
        internal long? InboundCount;
        internal double? SourceFps;
        internal double? AcceptedFps;
        internal string SampleRejectReason;
        internal bool? Paused;
        internal bool? Foreground;
        internal bool? SurfaceGate;
        internal bool? Connected;
    }

    /// <summary>
    /// 线程安全的 FPS 环形缓冲。
    ///
    /// 写入：socket 线程（FrameTask.HandleRaw），约 500ms 一个样本
    /// 读取：UI 渲染循环与 1Hz 会话采样；source/accepted 身份在同一短锁内快照
    ///
    /// 使用 lock 保护——写入极低频，竞争可忽略。
    /// min/max 在被覆盖值命中极值时触发 O(n) 重算。
    /// </summary>
    public class FpsRingBuffer
    {
        private readonly float[] _data;
        private readonly object _lock = new object();
        private readonly Func<double> _nowMs;
        private PerformanceDisplayState _performance=PerformanceDisplayState.Initial;
        public PerformanceDisplayState Performance
        {
            get { lock (_lock) return _performance.Status!="disconnected" && _performance.Status!="unavailable" && _hasData
                && _nowMs()-_lastSampleMs>=FreshSampleLimitMs ? _performance with {Status="stale"} : _performance; }
        }
        internal void SetPerformance(PerformanceDisplayState state) { lock (_lock) _performance=state; }
        private double _lastSampleMs = double.NegativeInfinity;
        public const double FreshSampleLimitMs = 2000;
        private int _head;
        private int _count;
        private float _sum;
        private float _min;
        private float _max;
        private bool _hasData;
        private float _gameHour; // 当前游戏内时间 (0.0-23.999...)
        private int _perfLevel;  // 当前性能等级 (0-3)
        private int _samplesAfterReset; // 场景重置后的有效样本计数
        private int _sceneEpoch;       // AS2 场景计数器（检测变化触发 warmup）
        private int _telemetryGeneration;
        private long _hostFrameOrdinal;
        private bool _hasFrameIngress;
        private double _frameIngressMs;
        private bool _hasSourceSample;
        private bool _hasSourceIdentity;
        private int _sourceScene;
        private int? _retiredResetScene;
        private long _sourceSequence;
        private long _sampleFrame;
        private double _sampleReceivedMs;
        private double _sourceFps;
        private bool _hasAcceptedSample;
        private long _acceptedSampleFrame;
        private double _acceptedSampleReceivedMs;
        private double _acceptedFps;
        private string _sampleRejectReason;
        private bool? _paused;
        private bool? _foreground;
        private bool? _surfaceGate;

        public FpsRingBuffer(int capacity) : this(capacity,
            () => Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency) { }

        internal FpsRingBuffer(int capacity, Func<double> nowMs)
        {
            _nowMs = nowMs ?? throw new ArgumentNullException(nameof(nowMs));
            if (capacity <= 0) capacity = 600;
            _data = new float[capacity];
            _head = 0;
            _count = 0;
            _sum = 0f;
            _min = 0f;
            _max = 0f;
            _hasData = false;
            _gameHour = 7f; // 默认白天
            _samplesAfterReset = 0;
            _sceneEpoch = -1; // -1 = 未收到首个 epoch，首次总是触发
        }

        public void Push(float fps)
        {
            lock (_lock) PushLocked(fps);
        }

        private void PushLocked(float fps)
        {
            bool wasEmpty = !_hasData;
            float evicted = _data[_head];
            bool needRescan = !wasEmpty && _count == _data.Length
                && (evicted <= _min || evicted >= _max);

            if (_count == _data.Length)
                _sum -= evicted;

            _data[_head] = fps;
            _head = (_head + 1) % _data.Length;
            if (_count < _data.Length) _count++;
            _sum += fps;
            _hasData = true;
            _lastSampleMs = _nowMs();
            _samplesAfterReset++;

            if (wasEmpty)
            {
                _min = fps;
                _max = fps;
            }
            else if (needRescan)
            {
                float lo = float.MaxValue;
                float hi = float.MinValue;
                for (int i = 0; i < _count; i++)
                {
                    float v = _data[i];
                    if (v < lo) lo = v;
                    if (v > hi) hi = v;
                }
                _min = lo;
                _max = hi;
            }
            else
            {
                if (fps < _min) _min = fps;
                if (fps > _max) _max = fps;
            }
        }

        internal void PushAcceptedSample(RenderSample sample, int generation,
            long hostFrameOrdinal, double receivedMs, bool? foreground, bool? surfaceReady)
        {
            lock (_lock)
            {
                if (generation != _telemetryGeneration) return;
                Issue205Probe.Current?.Hit(Issue205Counter.FpsAccepted);
                PushLocked((float)sample.Fps);
                _perfLevel = sample.Tier;
                _hasAcceptedSample = true;
                _acceptedSampleFrame = hostFrameOrdinal;
                _acceptedSampleReceivedMs = receivedMs;
                _acceptedFps = sample.Fps;
                _paused = sample.Paused;
                _foreground = foreground;
                _surfaceGate = surfaceReady;
                _sampleRejectReason = null;
            }
        }

        internal void NotifyConnectionReady(int generation)
        {
            lock (_lock)
            {
                if (generation == _telemetryGeneration) return;
                _telemetryGeneration = generation;
                ResetConnectionTelemetryLocked();
            }
        }

        internal void NotifyConnectionDisconnected(int generation)
        {
            lock (_lock)
            {
                if (generation != _telemetryGeneration) return;
                ResetSampleTelemetryLocked();
            }
        }

        internal long ObserveFrameIngress(int generation, out double nowMs)
        {
            lock (_lock)
            {
                nowMs = _nowMs();
                if (generation < _telemetryGeneration) return -1;
                if (generation != _telemetryGeneration)
                {
                    _telemetryGeneration = generation;
                    ResetConnectionTelemetryLocked();
                }
                _hostFrameOrdinal++;
                _hasFrameIngress = true;
                _frameIngressMs = nowMs;
                return _hostFrameOrdinal;
            }
        }

        internal void NoteSourceReject(string reason, int generation)
        {
            lock (_lock)
            {
                if (generation == _telemetryGeneration)
                    _sampleRejectReason = reason;
            }
        }

        internal bool TryRecordSourceSample(RenderSample sample, int generation,
            long hostFrameOrdinal, double receivedMs, bool? foreground,
            string policyRejectReason, out string rejectReason)
        {
            lock (_lock)
            {
                if (generation != _telemetryGeneration)
                {
                    rejectReason = "stale_connection";
                    return false;
                }
                if (_hasSourceIdentity && (sample.Scene < _sourceScene
                    || (_retiredResetScene.HasValue && sample.Scene == _retiredResetScene.Value)))
                {
                    rejectReason = "stale_scene";
                    return false;
                }
                if (_hasSourceIdentity && sample.Scene == _sourceScene)
                {
                    if (sample.Sequence == _sourceSequence)
                    {
                        rejectReason = "duplicate";
                        _sampleRejectReason = rejectReason;
                        return false;
                    }
                    if (sample.Sequence < _sourceSequence)
                    {
                        rejectReason = "regressed";
                        _sampleRejectReason = rejectReason;
                        return false;
                    }
                }
                if (!_hasSourceSample || sample.Scene != _sourceScene)
                    _hasAcceptedSample = false;
                _hasSourceSample = true;
                _hasSourceIdentity = true;
                _retiredResetScene = null;
                _sourceScene = sample.Scene;
                _sourceSequence = sample.Sequence;
                _sampleFrame = hostFrameOrdinal;
                _sampleReceivedMs = receivedMs;
                _sourceFps = sample.Fps;
                _paused = sample.Paused;
                _foreground = foreground;
                _surfaceGate = null;
                _sampleRejectReason = policyRejectReason;
                rejectReason = policyRejectReason;
                return true;
            }
        }

        private void ResetConnectionTelemetryLocked()
        {
            _hostFrameOrdinal = 0;
            _hasFrameIngress = false;
            _frameIngressMs = 0;
            ResetSampleTelemetryLocked();
        }

        private void ResetSampleFactsLocked()
        {
            _hasSourceSample = false;
            _hasAcceptedSample = false;
            _sampleFrame = 0;
            _acceptedSampleFrame = 0;
            _sampleRejectReason = null;
            _paused = null;
            _foreground = null;
            _surfaceGate = null;
        }

        private void ResetSampleTelemetryLocked()
        {
            ResetSampleFactsLocked();
            _hasSourceIdentity = false;
            _sourceScene = 0;
            _retiredResetScene = null;
            _sourceSequence = 0;
        }

        internal PerfTelemetrySnapshot CapturePerfTelemetry(
            CF7Launcher.Bus.PerfTransportSnapshot transport)
        {
            lock (_lock)
            {
                double now = _nowMs();
                bool hasGeneration = _telemetryGeneration > 0;
                bool transportMatches = transport.Available
                    && transport.Generation == _telemetryGeneration;
                long? sampleFrame = _hasSourceSample && _sampleFrame > 0
                    ? _sampleFrame : (long?)null;
                long? acceptedFrame = _hasAcceptedSample && _acceptedSampleFrame > 0
                    ? _acceptedSampleFrame : (long?)null;
                return new PerfTelemetrySnapshot
                {
                    ConnectionGeneration = hasGeneration ? _telemetryGeneration : (int?)null,
                    HostFrameOrdinal = hasGeneration ? _hostFrameOrdinal : (long?)null,
                    SourceScene = _hasSourceSample ? _sourceScene : (int?)null,
                    SourceSampleSequence = _hasSourceSample ? _sourceSequence : (long?)null,
                    SampleFrame = sampleFrame,
                    StalenessFrames = sampleFrame.HasValue
                        ? _hostFrameOrdinal - sampleFrame.Value : (long?)null,
                    SampleAgeMs = _hasSourceSample
                        ? Math.Max(0, now - _sampleReceivedMs) : (double?)null,
                    AcceptedSampleFrame = acceptedFrame,
                    AcceptedStalenessFrames = acceptedFrame.HasValue
                        ? _hostFrameOrdinal - acceptedFrame.Value : (long?)null,
                    AcceptedSampleAgeMs = _hasAcceptedSample
                        ? Math.Max(0, now - _acceptedSampleReceivedMs) : (double?)null,
                    FrameIngressAgeMs = _hasFrameIngress
                        ? Math.Max(0, now - _frameIngressMs) : (double?)null,
                    TransportAgeMs = transportMatches ? transport.TransportAgeMs : null,
                    InboundCount = transportMatches ? transport.InboundCount : (long?)null,
                    SourceFps = _hasSourceSample ? _sourceFps : (double?)null,
                    AcceptedFps = _hasAcceptedSample ? _acceptedFps : (double?)null,
                    SampleRejectReason = _sampleRejectReason,
                    Paused = _paused,
                    Foreground = _foreground,
                    SurfaceGate = _surfaceGate,
                    Connected = transportMatches ? transport.Connected : (bool?)null
                };
            }
        }

        /// <summary>
        /// 按逻辑顺序读取：index 0 = 最旧，index Count-1 = 最新。
        /// </summary>
        public float GetAt(int index)
        {
            lock (_lock)
            {
                if (index < 0 || index >= _count) return 0f;
                int pos = (_head - _count + index + _data.Length) % _data.Length;
                return _data[pos];
            }
        }

        public bool HasData { get { lock (_lock) { return _hasData; } } }
        public double SampleAgeMs
        {
            get
            {
                lock (_lock)
                {
                    double age = _hasData ? _nowMs() - _lastSampleMs : double.PositiveInfinity;
                    return age >= 0 ? age : double.PositiveInfinity;
                }
            }
        }
        public bool HasFreshSample => SampleAgeMs < FreshSampleLimitMs;
        public int Count { get { lock (_lock) { return _count; } } }
        public int Capacity { get { return _data.Length; } }

        public float Average
        {
            get { lock (_lock) { return _count > 0 ? _sum / _count : 0f; } }
        }

        public float Min { get { lock (_lock) { return _min; } } }
        public float Max { get { lock (_lock) { return _max; } } }
        public float GameHour { get { lock (_lock) { return _gameHour; } } }

        public void SetGameHour(float hour)
        {
            lock (_lock) { _gameHour = hour; }
        }

        public int PerfLevel { get { lock (_lock) { return _perfLevel; } } }
        public void SetPerfLevel(int level)
        {
            lock (_lock) { _perfLevel = level; }
        }

        /// <summary>
        /// 设置场景计数器。返回 true 表示 epoch 发生了变化（= 场景切换）。
        /// 首次调用（_sceneEpoch == -1）不视为变化（初始化）。
        /// </summary>
        public bool SetSceneEpoch(int epoch)
        {
            lock (_lock)
            {
                if (_sceneEpoch == -1)
                {
                    _sceneEpoch = epoch;
                    return false; // 首次初始化，不触发
                }
                if (epoch != _sceneEpoch)
                {
                    _sceneEpoch = epoch;
                    return true; // epoch 变化 = 场景切换
                }
                return false;
            }
        }

        public float Latest
        {
            get
            {
                lock (_lock)
                {
                    if (!_hasData) return 0f;
                    return _data[(_head - 1 + _data.Length) % _data.Length];
                }
            }
        }

        // ------------------------------------------------------------------
        // 场景重置支持
        // ------------------------------------------------------------------

        /// <summary>
        /// 场景重置时调用。保留 sparkline 历史与旧场拒收屏障，
        /// 清空当前 source/accepted 新鲜度并归零场景内有效样本计数。
        /// </summary>
        public void NotifySceneReset()
        {
            lock (_lock)
            {
                _samplesAfterReset = 0;
                _lastSampleMs = double.NegativeInfinity;
                if (_hasSourceIdentity)
                    _retiredResetScene = _sourceScene;
                ResetSampleFactsLocked();
            }
        }

        public int SamplesAfterReset
        {
            get { lock (_lock) { return _samplesAfterReset; } }
        }

        // ------------------------------------------------------------------
        // 统计方法（供 PerfDecisionEngine 使用，0.25-1 Hz 调用频率）
        // ------------------------------------------------------------------

        /// <summary>
        /// 最近 window 个样本的平均值。O(window)。
        /// </summary>
        public float WindowAverage(int window)
        {
            lock (_lock)
            {
                int w = window < _count ? window : _count;
                if (w <= 0) return 0f;
                float sum = 0f;
                for (int i = 0; i < w; i++)
                {
                    int pos = (_head - 1 - i + _data.Length) % _data.Length;
                    sum += _data[pos];
                }
                return sum / w;
            }
        }

        /// <summary>
        /// 最近 window 个样本的第 p 百分位 (0-100)。
        /// O(window log window)，window 通常为 5-30，开销可忽略。
        /// </summary>
        public float Percentile(int p, int window)
        {
            lock (_lock)
            {
                int w = window < _count ? window : _count;
                if (w <= 0) return 0f;
                float[] slice = new float[w];
                for (int i = 0; i < w; i++)
                {
                    int pos = (_head - 1 - i + _data.Length) % _data.Length;
                    slice[i] = _data[pos];
                }
                Array.Sort(slice);
                int idx = (int)(w * p / 100f);
                if (idx >= w) idx = w - 1;
                if (idx < 0) idx = 0;
                return slice[idx];
            }
        }

        /// <summary>
        /// 最近 window 个样本的线性回归斜率 (FPS/sample)。
        /// 正 = 帧率改善，负 = 恶化。O(window)。
        /// x=0 为最旧，x=w-1 为最新。
        /// </summary>
        public float Trend(int window)
        {
            lock (_lock)
            {
                int w = window < _count ? window : _count;
                if (w < 2) return 0f;
                // 线性回归: slope = (n*Sxy - Sx*Sy) / (n*Sxx - Sx*Sx)
                float sx = 0f, sy = 0f, sxy = 0f, sxx = 0f;
                for (int i = 0; i < w; i++)
                {
                    // i=0 → 最旧, i=w-1 → 最新
                    int pos = (_head - w + i + _data.Length) % _data.Length;
                    float x = i;
                    float y = _data[pos];
                    sx += x;
                    sy += y;
                    sxy += x * y;
                    sxx += x * x;
                }
                float denom = w * sxx - sx * sx;
                return denom == 0f ? 0f : (w * sxy - sx * sy) / denom;
            }
        }

        /// <summary>
        /// 最近 window 个样本的方差。O(window)。
        /// </summary>
        public float Variance(int window)
        {
            lock (_lock)
            {
                int w = window < _count ? window : _count;
                if (w < 2) return 0f;
                float mean = 0f;
                for (int i = 0; i < w; i++)
                {
                    int pos = (_head - 1 - i + _data.Length) % _data.Length;
                    mean += _data[pos];
                }
                mean /= w;
                float sumSq = 0f;
                for (int i = 0; i < w; i++)
                {
                    int pos = (_head - 1 - i + _data.Length) % _data.Length;
                    float diff = _data[pos] - mean;
                    sumSq += diff * diff;
                }
                return sumSq / (w - 1);
            }
        }
    }
}
