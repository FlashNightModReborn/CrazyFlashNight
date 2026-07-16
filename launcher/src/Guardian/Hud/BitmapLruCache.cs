using System;
using System.Collections.Generic;
using System.Drawing;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 按解码后像素字节计费的 Bitmap LRU。缓存取得所有权，淘汰与清空时负责 Dispose。
    /// 调用方必须在外部同步；这样可以把“取原图 → 生成染色图 → 绘制”纳入同一临界区，
    /// 避免后台预热淘汰仍在使用的 GDI 对象。
    /// </summary>
    internal sealed class BitmapLruCache : IDisposable
    {
        private sealed class Entry
        {
            internal Bitmap Bitmap;
            internal long Bytes;
            internal LinkedListNode<string> Node;
        }

        private readonly long _maxBytes;
        private readonly Dictionary<string, Entry> _entries;
        private readonly LinkedList<string> _lru = new LinkedList<string>();
        private long _currentBytes;

        internal BitmapLruCache(long maxBytes, StringComparer comparer)
        {
            if (maxBytes <= 0) throw new ArgumentOutOfRangeException(nameof(maxBytes));
            _maxBytes = maxBytes;
            _entries = new Dictionary<string, Entry>(comparer ?? StringComparer.Ordinal);
        }

        internal long MaxBytes { get { return _maxBytes; } }
        internal long CurrentBytes { get { return _currentBytes; } }
        internal int Count { get { return _entries.Count; } }

        internal bool TryGet(string key, out Bitmap bitmap)
        {
            Entry entry;
            if (!_entries.TryGetValue(key, out entry))
            {
                bitmap = null;
                return false;
            }
            _lru.Remove(entry.Node);
            _lru.AddFirst(entry.Node);
            bitmap = entry.Bitmap;
            return true;
        }

        /// <summary>
        /// 成功时缓存取得 bitmap 所有权；单图超过预算时返回 false，所有权仍归调用方。
        /// </summary>
        internal bool TryAdd(string key, Bitmap bitmap)
        {
            if (string.IsNullOrEmpty(key)) throw new ArgumentException("Cache key is required.", nameof(key));
            if (bitmap == null) throw new ArgumentNullException(nameof(bitmap));

            long bytes = EstimateBytes(bitmap);
            if (bytes > _maxBytes) return false;

            Remove(key);
            while (_currentBytes + bytes > _maxBytes && _lru.Last != null)
                Remove(_lru.Last.Value);

            LinkedListNode<string> node = _lru.AddFirst(key);
            _entries[key] = new Entry { Bitmap = bitmap, Bytes = bytes, Node = node };
            _currentBytes += bytes;
            return true;
        }

        internal void Clear()
        {
            foreach (Entry entry in _entries.Values)
                DisposeBitmap(entry.Bitmap);
            _entries.Clear();
            _lru.Clear();
            _currentBytes = 0;
        }

        public void Dispose()
        {
            Clear();
        }

        private void Remove(string key)
        {
            Entry entry;
            if (!_entries.TryGetValue(key, out entry)) return;
            _entries.Remove(key);
            _lru.Remove(entry.Node);
            _currentBytes -= entry.Bytes;
            DisposeBitmap(entry.Bitmap);
        }

        private static long EstimateBytes(Bitmap bitmap)
        {
            return checked((long)bitmap.Width * bitmap.Height * 4L);
        }

        private static void DisposeBitmap(Bitmap bitmap)
        {
            try { bitmap.Dispose(); } catch { }
        }
    }
}
