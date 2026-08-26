using System;

namespace CF7Launcher.Guardian.HitNumbers
{
    /// <summary>
    /// ReadLoop 到 UI 线程之间的 latest-wins 单槽邮箱。无论生产者在 UI 忙碌期间
    /// 发布多少帧，同一时刻都只允许一个待执行 dispatch；reset generation 同时
    /// 充当旧帧栅栏，避免场景切换前的迟到帧重新出现。
    /// </summary>
    internal sealed class HitNumberFrameMailbox : IDisposable
    {
        private readonly object _gate = new object();
        private HitNumberRuntimeSnapshot _pending;
        private bool _ready;
        private bool _dispatchQueued;
        private bool _disposed;
        private int _acceptedGeneration;

        internal int PendingDispatchCount
        {
            get { lock (_gate) return _dispatchQueued ? 1 : 0; }
        }

        internal int AcceptedGeneration
        {
            get { lock (_gate) return _acceptedGeneration; }
        }

        /// <summary>
        /// 返回 true 表示调用方必须安排一次 UI drain。返回 false 时，本帧已经被
        /// 合并、拒绝，或已有一个 drain 在途。
        /// </summary>
        internal bool Publish(HitNumberRuntimeSnapshot snapshot)
        {
            if (snapshot == null) return false;
            lock (_gate)
            {
                if (_disposed || snapshot.Generation < _acceptedGeneration) return false;
                if (snapshot.Generation > _acceptedGeneration)
                    _acceptedGeneration = snapshot.Generation;
                _pending = snapshot;
                if (!_ready || _dispatchQueued) return false;
                _dispatchQueued = true;
                return true;
            }
        }

        /// <summary>
        /// 标记 UI 已可用。若 ready 前已有快照，返回 true，由 UI 线程立即 drain。
        /// </summary>
        internal bool SetReady()
        {
            lock (_gate)
            {
                if (_disposed) return false;
                _ready = true;
                if (_pending == null || _dispatchQueued) return false;
                _dispatchQueued = true;
                return true;
            }
        }

        internal HitNumberRuntimeSnapshot DrainLatest()
        {
            lock (_gate)
            {
                if (_disposed) return null;
                HitNumberRuntimeSnapshot snapshot = _pending;
                _pending = null;
                _dispatchQueued = false;
                if (snapshot == null || snapshot.Generation < _acceptedGeneration) return null;
                return snapshot;
            }
        }

        /// <summary>
        /// BeginInvoke 未能排入 UI 队列时重新开放调度；保留 latest 快照，让下一帧
        /// 可以再次触发 dispatch，而不是永久卡死在 queued 状态。
        /// </summary>
        internal void DispatchFailed()
        {
            lock (_gate) _dispatchQueued = false;
        }

        public void Dispose()
        {
            lock (_gate)
            {
                _disposed = true;
                _pending = null;
                _dispatchQueued = false;
            }
        }
    }
}
