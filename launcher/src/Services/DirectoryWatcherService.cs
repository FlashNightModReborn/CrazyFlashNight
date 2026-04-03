// CF7:ME DirectoryWatcherService — generic file-change watcher with debounce
// C# 5 syntax
// Reusable for any hot-reload scenario: music, mods, skins, config, etc.

using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using CF7Launcher.Guardian;

namespace CF7Launcher.Services
{
    internal enum FileChangeType
    {
        Created,
        Deleted
    }

    internal struct FileChangeInfo
    {
        public FileChangeType ChangeType;
        public string FullPath;
        public string RelativePath;
    }

    /// <summary>
    /// Monitors a directory for file changes, debounces rapid bursts (e.g. bulk copy),
    /// and fires a batched callback. Caller decides how to marshal (BeginInvoke, etc.).
    ///
    /// Usage:
    ///   var watcher = new DirectoryWatcherService(
    ///       soundsDir, new[]{ ".mp3", ".wav", ".ogg", ".flac" },
    ///       true, 500, OnBatch);
    ///   watcher.Start();
    ///
    /// onBatch(null) means the internal buffer overflowed — caller should do a full rescan.
    /// </summary>
    internal class DirectoryWatcherService : IDisposable
    {
        private readonly string _basePath;
        private readonly HashSet<string> _extensions;   // lowercase, with dot
        private readonly bool _recursive;
        private readonly int _debounceMs;
        private readonly Action<List<FileChangeInfo>> _onBatch;

        private FileSystemWatcher _watcher;
        private Timer _debounceTimer;
        private readonly object _pendingLock = new object();
        private Dictionary<string, FileChangeType> _pending;
        private bool _disposed;

        /// <param name="path">Absolute path to watch.</param>
        /// <param name="extensions">Allowed extensions, e.g. { ".mp3", ".wav" }. Case-insensitive.</param>
        /// <param name="recursive">Watch subdirectories.</param>
        /// <param name="debounceMs">Merge window in milliseconds (500 recommended).</param>
        /// <param name="onBatch">Callback with batched changes. null = buffer overflow, do full rescan.</param>
        public DirectoryWatcherService(string path, string[] extensions, bool recursive,
                                        int debounceMs, Action<List<FileChangeInfo>> onBatch)
        {
            _basePath = path;
            _extensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < extensions.Length; i++)
            {
                string ext = extensions[i];
                if (!ext.StartsWith(".")) ext = "." + ext;
                _extensions.Add(ext);
            }
            _recursive = recursive;
            _debounceMs = debounceMs;
            _onBatch = onBatch;
            _pending = new Dictionary<string, FileChangeType>(StringComparer.OrdinalIgnoreCase);
        }

        public void Start()
        {
            if (_watcher != null) return;

            _watcher = new FileSystemWatcher();
            _watcher.Path = _basePath;
            _watcher.Filter = "*.*";  // manual extension check (FSW only supports single pattern)
            _watcher.IncludeSubdirectories = _recursive;
            _watcher.InternalBufferSize = 32768; // 32 KB
            _watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite;

            _watcher.Created += OnCreated;
            _watcher.Deleted += OnDeleted;
            _watcher.Renamed += OnRenamed;
            _watcher.Error += OnError;

            _watcher.EnableRaisingEvents = true;
            LogManager.Log("[DirectoryWatcher] Started: " + _basePath);
        }

        public void Stop()
        {
            if (_watcher == null) return;
            _watcher.EnableRaisingEvents = false;
            _watcher.Dispose();
            _watcher = null;

            if (_debounceTimer != null)
            {
                _debounceTimer.Dispose();
                _debounceTimer = null;
            }
            LogManager.Log("[DirectoryWatcher] Stopped: " + _basePath);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            Stop();
        }

        // ── FSW event handlers (ThreadPool thread) ──

        private void OnCreated(object sender, FileSystemEventArgs e)
        {
            if (!IsAllowedExtension(e.FullPath)) return;
            Enqueue(e.FullPath, FileChangeType.Created);
        }

        private void OnDeleted(object sender, FileSystemEventArgs e)
        {
            if (!IsAllowedExtension(e.FullPath)) return;
            Enqueue(e.FullPath, FileChangeType.Deleted);
        }

        private void OnRenamed(object sender, RenamedEventArgs e)
        {
            // Treat rename as delete(old) + create(new)
            bool oldOk = IsAllowedExtension(e.OldFullPath);
            bool newOk = IsAllowedExtension(e.FullPath);

            if (oldOk) Enqueue(e.OldFullPath, FileChangeType.Deleted);
            if (newOk) Enqueue(e.FullPath, FileChangeType.Created);
        }

        private void OnError(object sender, ErrorEventArgs e)
        {
            LogManager.Log("[DirectoryWatcher] Buffer overflow or error: " + e.GetException().Message);
            // Signal caller to do full rescan
            try { _onBatch(null); }
            catch (Exception ex) { LogManager.Log("[DirectoryWatcher] onBatch(null) error: " + ex.Message); }
        }

        // ── Debounce logic ──

        private void Enqueue(string fullPath, FileChangeType changeType)
        {
            lock (_pendingLock)
            {
                _pending[fullPath] = changeType;

                // Reset or create debounce timer
                if (_debounceTimer == null)
                {
                    _debounceTimer = new Timer(FlushPending, null, _debounceMs, Timeout.Infinite);
                }
                else
                {
                    _debounceTimer.Change(_debounceMs, Timeout.Infinite);
                }
            }
        }

        private void FlushPending(object state)
        {
            Dictionary<string, FileChangeType> snapshot;
            lock (_pendingLock)
            {
                if (_pending.Count == 0) return;
                snapshot = _pending;
                _pending = new Dictionary<string, FileChangeType>(StringComparer.OrdinalIgnoreCase);
            }

            var batch = new List<FileChangeInfo>(snapshot.Count);
            foreach (var kv in snapshot)
            {
                string rel = kv.Key;
                if (rel.StartsWith(_basePath, StringComparison.OrdinalIgnoreCase))
                {
                    rel = rel.Substring(_basePath.Length);
                    if (rel.Length > 0 && (rel[0] == '\\' || rel[0] == '/'))
                        rel = rel.Substring(1);
                }
                // Normalize to forward slashes
                rel = rel.Replace('\\', '/');

                batch.Add(new FileChangeInfo
                {
                    ChangeType = kv.Value,
                    FullPath = kv.Key,
                    RelativePath = rel
                });
            }

            try
            {
                _onBatch(batch);
            }
            catch (Exception ex)
            {
                LogManager.Log("[DirectoryWatcher] onBatch error: " + ex.Message);
            }
        }

        private bool IsAllowedExtension(string path)
        {
            string ext = Path.GetExtension(path);
            return ext != null && _extensions.Contains(ext);
        }
    }
}
