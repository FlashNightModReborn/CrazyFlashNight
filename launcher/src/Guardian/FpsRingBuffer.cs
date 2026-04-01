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
    }
}
