using System.Collections.Generic;

namespace CF7Launcher.Guardian.Hud.Loot
{
    /// <summary>
    /// 多生产者、单 UI drain 的小型批队列。
    /// Enqueue 仅在从 idle 切换为 scheduled 时返回 true；drain 执行期间到达的条目
    /// 会并入下一批，但不会再各自投递 BeginInvoke。
    /// </summary>
    internal sealed class SingleFlightBatchQueue<T>
    {
        private readonly object _sync = new object();
        private List<T> _pending = new List<T>();
        private bool _scheduled;

        internal bool Enqueue(T item)
        {
            lock (_sync)
            {
                _pending.Add(item);
                if (_scheduled) return false;
                _scheduled = true;
                return true;
            }
        }

        internal List<T> BeginDrain()
        {
            lock (_sync)
            {
                List<T> batch = _pending;
                _pending = new List<T>();
                return batch;
            }
        }

        /// <summary>
        /// 当前批处理完成后调用。true 表示 drain 期间又有数据，调用方只需再投递一次。
        /// </summary>
        internal bool CompleteDrain()
        {
            lock (_sync)
            {
                if (_pending.Count > 0) return true;
                _scheduled = false;
                return false;
            }
        }

        internal void Abort()
        {
            lock (_sync)
            {
                _pending.Clear();
                _scheduled = false;
            }
        }

        internal int PendingCount
        {
            get { lock (_sync) return _pending.Count; }
        }

        internal bool IsScheduled
        {
            get { lock (_sync) return _scheduled; }
        }
    }
}
