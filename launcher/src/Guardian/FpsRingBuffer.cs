using System;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 线程安全的 FPS 环形缓冲。
    ///
    /// 写入：socket 线程（FrameTask.HandleRaw），频率 0.25-1 Hz
    /// 读取：UI 线程（NotchOverlay 定时器），频率 ~60 Hz
    ///
    /// 使用 lock 保护——写入极低频，竞争可忽略。
    /// min/max 在被覆盖值命中极值时触发 O(n) 重算。
    /// </summary>
    public class FpsRingBuffer
    {
        private readonly float[] _data;
        private readonly object _lock = new object();
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

        public FpsRingBuffer(int capacity)
        {
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
            lock (_lock)
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
        /// 场景重置时调用。不清空 buffer（sparkline 仍需历史），
        /// 仅归零场景内样本计数，供决策引擎做 warmup 判断。
        /// </summary>
        public void NotifySceneReset()
        {
            lock (_lock) { _samplesAfterReset = 0; }
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
