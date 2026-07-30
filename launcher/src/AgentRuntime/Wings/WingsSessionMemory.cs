using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal enum WingsMemoryKey
    {
        GuidanceVerbosity,
        RouteStyle,
        LastActionReasonHash,
        LastConsentReceiptId,
        LastActionReceiptId,
        LastFrameHash
    }

    internal sealed class WingsMemoryEntrySnapshot
    {
        public WingsMemoryEntrySnapshot(
            WingsMemoryKey key,
            string value,
            string sessionId,
            string saveBindingId,
            string loreViewId)
        {
            Key = key;
            Value = value;
            SessionId = sessionId;
            SaveBindingId = saveBindingId;
            LoreViewId = loreViewId;
        }

        public WingsMemoryKey Key { get; }
        public string Value { get; }
        public string SessionId { get; }
        public string SaveBindingId { get; }
        public string LoreViewId { get; }
    }

    /// <summary>
    /// An in-memory, bounded, typed allow-list. It intentionally has no
    /// serializer or cross-session import API.
    /// </summary>
    internal sealed class SessionOnlyWingsMemory : IDisposable
    {
        private sealed class Entry
        {
            public Entry(WingsMemoryKey key, string value)
            {
                Key = key;
                Value = value;
            }

            public WingsMemoryKey Key { get; }
            public string Value { get; }
        }

        private readonly object _sync = new object();
        private readonly int _maximumEntries;
        private readonly int _maximumCharacters;
        private readonly LinkedList<Entry> _entries =
            new LinkedList<Entry>();
        private readonly Dictionary<
            WingsMemoryKey,
            LinkedListNode<Entry>> _byKey =
                new Dictionary<WingsMemoryKey, LinkedListNode<Entry>>();
        private readonly string _sessionId;
        private string _saveBindingId;
        private string _loreViewId;
        private int _characterCount;
        private bool _disposed;

        public SessionOnlyWingsMemory(
            string sessionId,
            LoreView initialView,
            int maximumEntries = 32,
            int maximumCharacters = 4096)
        {
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            if (initialView == null)
                throw new ArgumentNullException(nameof(initialView));
            if (maximumEntries <= 0 || maximumEntries > 128)
                throw new ArgumentOutOfRangeException(
                    nameof(maximumEntries));
            if (maximumCharacters < 64
                || maximumCharacters > 32768)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(maximumCharacters));
            }

            _sessionId = sessionId;
            _saveBindingId =
                initialView.Progress.SaveBindingId;
            _loreViewId = initialView.LoreViewId;
            _maximumEntries = maximumEntries;
            _maximumCharacters = maximumCharacters;
        }

        public int Count
        {
            get
            {
                lock (_sync)
                {
                    ThrowIfDisposed();
                    return _entries.Count;
                }
            }
        }

        public void Remember(
            string sessionId,
            LoreView view,
            WingsMemoryKey key,
            string value)
        {
            ValidateKeyValue(key, value);
            lock (_sync)
            {
                ThrowIfDisposed();
                RequireCurrentBinding(sessionId, view);
                if (value.Length > _maximumCharacters)
                {
                    throw new ArgumentException(
                        "Memory value exceeds the total bound.",
                        nameof(value));
                }

                if (_byKey.TryGetValue(key, out var existing))
                {
                    _characterCount -= existing.Value.Value.Length;
                    _entries.Remove(existing);
                    _byKey.Remove(key);
                }
                var node = _entries.AddLast(
                    new Entry(key, value));
                _byKey.Add(key, node);
                _characterCount += value.Length;
                EvictToBounds();
            }
        }

        public bool TryRecall(
            string sessionId,
            LoreView view,
            WingsMemoryKey key,
            out string value)
        {
            if (!Enum.IsDefined(key))
                throw new ArgumentOutOfRangeException(nameof(key));
            lock (_sync)
            {
                ThrowIfDisposed();
                if (!BindingMatches(sessionId, view))
                {
                    value = null;
                    return false;
                }
                if (_byKey.TryGetValue(key, out var node))
                {
                    value = node.Value.Value;
                    return true;
                }
                value = null;
                return false;
            }
        }

        public void TransitionLoreView(
            string sessionId,
            LoreView nextView)
        {
            if (nextView == null)
                throw new ArgumentNullException(nameof(nextView));
            lock (_sync)
            {
                ThrowIfDisposed();
                if (!string.Equals(
                        sessionId,
                        _sessionId,
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "memory_session_binding_mismatch");
                }
                if (string.Equals(
                        _saveBindingId,
                        nextView.Progress.SaveBindingId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _loreViewId,
                        nextView.LoreViewId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                ClearLocked();
                _saveBindingId =
                    nextView.Progress.SaveBindingId;
                _loreViewId = nextView.LoreViewId;
            }
        }

        public ReadOnlyCollection<WingsMemoryEntrySnapshot> Snapshot(
            string sessionId,
            LoreView view)
        {
            lock (_sync)
            {
                ThrowIfDisposed();
                RequireCurrentBinding(sessionId, view);
                return Array.AsReadOnly(
                    _entries
                        .Select(entry =>
                            new WingsMemoryEntrySnapshot(
                                entry.Key,
                                entry.Value,
                                _sessionId,
                                _saveBindingId,
                                _loreViewId))
                        .ToArray());
            }
        }

        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed)
                    return;
                ClearLocked();
                _disposed = true;
            }
        }

        private static void ValidateKeyValue(
            WingsMemoryKey key,
            string value)
        {
            if (!Enum.IsDefined(key))
                throw new ArgumentOutOfRangeException(nameof(key));
            switch (key)
            {
                case WingsMemoryKey.GuidanceVerbosity:
                    if (value != "brief"
                        && value != "standard"
                        && value != "detailed")
                    {
                        throw new ArgumentException(
                            "Unknown guidance verbosity.",
                            nameof(value));
                    }
                    break;
                case WingsMemoryKey.RouteStyle:
                    if (value != "safe"
                        && value != "balanced"
                        && value != "fast")
                    {
                        throw new ArgumentException(
                            "Unknown route style.",
                            nameof(value));
                    }
                    break;
                case WingsMemoryKey.LastActionReasonHash:
                case WingsMemoryKey.LastFrameHash:
                    WingsProtocolValue.RequireSha256(
                        value,
                        nameof(value));
                    break;
                case WingsMemoryKey.LastConsentReceiptId:
                case WingsMemoryKey.LastActionReceiptId:
                    WingsProtocolValue.RequireOpaqueId(
                        value,
                        nameof(value));
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(key));
            }
        }

        private void EvictToBounds()
        {
            while (_entries.Count > _maximumEntries
                || _characterCount > _maximumCharacters)
            {
                LinkedListNode<Entry> oldest = _entries.First;
                _entries.RemoveFirst();
                _byKey.Remove(oldest.Value.Key);
                _characterCount -= oldest.Value.Value.Length;
            }
        }

        private bool BindingMatches(
            string sessionId,
            LoreView view)
        {
            return view != null
                && string.Equals(
                    sessionId,
                    _sessionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    view.Progress.SaveBindingId,
                    _saveBindingId,
                    StringComparison.Ordinal)
                && string.Equals(
                    view.LoreViewId,
                    _loreViewId,
                    StringComparison.Ordinal);
        }

        private void RequireCurrentBinding(
            string sessionId,
            LoreView view)
        {
            if (!BindingMatches(sessionId, view))
            {
                throw new InvalidOperationException(
                    "memory_lore_view_binding_mismatch");
            }
        }

        private void ClearLocked()
        {
            _entries.Clear();
            _byKey.Clear();
            _characterCount = 0;
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(
                    nameof(SessionOnlyWingsMemory));
        }
    }
}
