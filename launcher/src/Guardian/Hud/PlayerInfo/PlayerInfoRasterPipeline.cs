#nullable enable

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal enum PlayerInfoRasterRequestResult
{
    CurrentHit,
    CacheHit,
    Queued
}

internal readonly record struct PlayerInfoRasterPipelineSnapshot(
    long Generation,
    long RequestCount,
    long PublishCount,
    long CacheHitCount,
    long CurrentLayerHitCount,
    long CacheLayerHitCount,
    long ParseCount,
    long RasterCount,
    int ActiveWorkers,
    int MaxConcurrentWorkers,
    long PendingReplacementCount,
    long StaleDiscardCount,
    long FaultCount,
    long CancelCount,
    long DisposedBatchCount,
    long DisposedLayerCount,
    long CacheBytes,
    int CacheCount,
    string? DesiredBatchKey,
    string? CurrentBatchKey,
    string? LastFault);

internal sealed class PlayerInfoRasterBatchPublishedEventArgs(
    string batchKey,
    long generation,
    bool fromCache) : EventArgs
{
    internal string BatchKey { get; } = batchKey;
    internal long Generation { get; } = generation;
    internal bool FromCache { get; } = fromCache;
}

internal sealed class PlayerInfoRasterPipeline : IDisposable
{
    internal const long DefaultMaxCacheBytes = 16L * 1024 * 1024;

    private sealed record PendingWork(
        PlayerInfoRasterPlan Plan,
        long Generation);

    private sealed record PublishedNotification(
        EventHandler<PlayerInfoRasterBatchPublishedEventArgs> Handlers,
        PlayerInfoRasterBatchPublishedEventArgs Args);

    private readonly object _gate = new();
    private readonly IPlayerInfoRasterizer _rasterizer;
    private readonly long _maxCacheBytes;
    private readonly InactiveBatchCache _cache;
    private readonly Queue<PublishedNotification> _publishedNotifications = new();

    private PlayerInfoRasterBatch? _current;
    private PlayerInfoRasterPlan? _currentPlan;
    private PendingWork? _pending;
    private CancellationTokenSource? _activeCancellation;
    private TaskCompletionSource<bool> _idle =
        CompletedTaskCompletionSource();
    private bool _workerScheduled;
    private bool _notificationDispatching;
    private bool _disposed;
    private int _borrowDepth;
    private int _activeNotificationCallbacks;
    private int _notificationCallbackThreadId;
    private long _generation;
    private string? _desiredBatchKey;

    private long _requestCount;
    private long _publishCount;
    private long _cacheHitCount;
    private long _currentLayerHitCount;
    private long _cacheLayerHitCount;
    private long _parseCount;
    private long _rasterCount;
    private int _activeWorkers;
    private int _maxConcurrentWorkers;
    private long _pendingReplacementCount;
    private long _staleDiscardCount;
    private long _faultCount;
    private long _cancelCount;
    private long _disposedBatchCount;
    private long _disposedLayerCount;
    private string? _lastFault;

    internal PlayerInfoRasterPipeline(
        IPlayerInfoRasterizer rasterizer,
        long maxCacheBytes = DefaultMaxCacheBytes)
    {
        _rasterizer = rasterizer ??
            throw new ArgumentNullException(nameof(rasterizer));
        if (maxCacheBytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxCacheBytes));
        }
        _maxCacheBytes = maxCacheBytes;
        _cache = new InactiveBatchCache(DisposeOwnedBatchLocked);
    }

    internal event EventHandler<PlayerInfoRasterBatchPublishedEventArgs>? BatchPublished;

    internal long MaxCacheBytes => _maxCacheBytes;

    internal PlayerInfoRasterRequestResult Request(PlayerInfoRasterPlan plan)
    {
        ArgumentNullException.ThrowIfNull(plan);
        PlayerInfoRasterRequestResult result;
        var drainNotifications = false;
        lock (_gate)
        {
            ThrowIfDisposed();
            ThrowIfBorrowedMutation();
            _requestCount++;
            _generation = checked(_generation + 1);
            _desiredBatchKey = plan.BatchKey;

            if (_pending is not null || _activeWorkers != 0)
            {
                _pendingReplacementCount++;
            }

            if (_current is not null &&
                string.Equals(
                    _current.BatchKey,
                    plan.BatchKey,
                    StringComparison.Ordinal))
            {
                _currentPlan = plan;
                _currentLayerHitCount = checked(
                    _currentLayerHitCount + plan.Layers.Count);
                _pending = null;
                _activeCancellation?.Cancel();
                CompleteIdleIfPossibleLocked();
                result = PlayerInfoRasterRequestResult.CurrentHit;
            }
            else if (_cache.TryTake(plan.BatchKey, out var cached))
            {
                _cacheHitCount++;
                _cacheLayerHitCount = checked(
                    _cacheLayerHitCount + cached.Layers.Count);
                _pending = null;
                _activeCancellation?.Cancel();
                drainNotifications = PublishLocked(
                    cached,
                    plan,
                    _generation,
                    fromCache: true);
                CompleteIdleIfPossibleLocked();
                result = PlayerInfoRasterRequestResult.CacheHit;
            }
            else
            {
                _pending = new PendingWork(plan, _generation);
                _activeCancellation?.Cancel();
                EnsureWorkerLocked();
                result = PlayerInfoRasterRequestResult.Queued;
            }
        }
        if (drainNotifications)
        {
            DrainPublishedNotifications();
        }
        return result;
    }

    /// <summary>
    /// 借用 current batch 与本次请求的绝对 placement plan。
    /// callback 始终在所有权锁内执行，Bitmap 不得逃逸。
    /// callback 内允许只读 Snapshot；Request/Dispose 会 fail-closed，避免
    /// Monitor 同线程重入销毁正在借用的 Bitmap。
    /// </summary>
    internal bool TryUseCurrent(
        Action<PlayerInfoRasterBatch, PlayerInfoRasterPlan> callback)
    {
        ArgumentNullException.ThrowIfNull(callback);
        lock (_gate)
        {
            ThrowIfDisposed();
            if (_current is null || _currentPlan is null)
            {
                return false;
            }
            _borrowDepth++;
            try
            {
                callback(_current, _currentPlan);
                return true;
            }
            finally
            {
                _borrowDepth--;
            }
        }
    }

    internal PlayerInfoRasterPipelineSnapshot Snapshot
    {
        get
        {
            lock (_gate)
            {
                return SnapshotLocked();
            }
        }
    }

    internal Task WaitForIdleAsync(CancellationToken cancellationToken = default)
    {
        Task task;
        lock (_gate)
        {
            task = _idle.Task;
        }
        return cancellationToken.CanBeCanceled
            ? task.WaitAsync(cancellationToken)
            : task;
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                WaitForNotificationCallbacksLocked();
                return;
            }
            ThrowIfBorrowedMutation();
            _disposed = true;
            _generation = checked(_generation + 1);
            _desiredBatchKey = null;
            _pending = null;
            _activeCancellation?.Cancel();
            var current = _current;
            _current = null;
            _currentPlan = null;
            _cache.Clear();
            if (current is not null)
            {
                DisposeOwnedBatchLocked(current);
            }
            BatchPublished = null;
            _publishedNotifications.Clear();
            if (_activeNotificationCallbacks == 0)
            {
                _notificationDispatching = false;
            }
            CompleteIdleIfPossibleLocked();
            WaitForNotificationCallbacksLocked();
        }
    }

    private void EnsureWorkerLocked()
    {
        if (_workerScheduled)
        {
            return;
        }
        _workerScheduled = true;
        if (_idle.Task.IsCompleted)
        {
            _idle = new TaskCompletionSource<bool>(
                TaskCreationOptions.RunContinuationsAsynchronously);
        }
        _ = Task.Run(WorkerLoop);
    }

    private void WorkerLoop()
    {
        try
        {
            WorkerLoopCore();
        }
        catch (Exception ex)
        {
            lock (_gate)
            {
                _faultCount++;
                _lastFault =
                    "PipelineWorkerException: " +
                    ex.GetType().Name +
                    ": " +
                    ex.Message;
                _activeCancellation?.Cancel();
                _activeCancellation?.Dispose();
                _activeCancellation = null;
                _activeWorkers = 0;
                _workerScheduled = false;
                if (!_disposed && _pending is not null)
                {
                    EnsureWorkerLocked();
                }
                else
                {
                    CompleteIdleIfPossibleLocked();
                }
            }
        }
    }

    private void WorkerLoopCore()
    {
        PendingWork work;
        CancellationTokenSource cancellation;
        lock (_gate)
        {
            if (_disposed || _pending is null)
            {
                FinishWorkerLocked();
                return;
            }
            work = _pending;
            _pending = null;
            cancellation = new CancellationTokenSource();
            _activeCancellation = cancellation;
            _activeWorkers++;
            _maxConcurrentWorkers = Math.Max(
                _maxConcurrentWorkers,
                _activeWorkers);
        }

        PlayerInfoRasterBatch? batch = null;
        var drainNotifications = false;
        try
        {
            Exception? fault = null;
            var cancelled = false;
            var progress = new PlayerInfoRasterProgress();
            try
            {
                batch = _rasterizer.Bake(
                    work.Plan,
                    cancellation.Token,
                    progress);
            }
            catch (OperationCanceledException)
            {
                cancelled = true;
            }
            catch (Exception ex)
            {
                fault = ex;
            }

            lock (_gate)
            {
                _activeWorkers--;
                if (ReferenceEquals(_activeCancellation, cancellation))
                {
                    _activeCancellation = null;
                }
                cancellation.Dispose();
                _parseCount = checked(_parseCount + progress.ParseCount);
                _rasterCount = checked(_rasterCount + progress.RasterCount);

                if (cancelled)
                {
                    _cancelCount++;
                }
                else if (fault is not null)
                {
                    _faultCount++;
                    _lastFault =
                        fault.GetType().Name + ": " + fault.Message;
                }
                else if (batch is null)
                {
                    _faultCount++;
                    _lastFault =
                        "InvalidOperationException: rasterizer returned null.";
                }
                else
                {
                    if (_disposed ||
                        work.Generation != _generation ||
                        !string.Equals(
                            work.Plan.BatchKey,
                            _desiredBatchKey,
                            StringComparison.Ordinal))
                    {
                        _staleDiscardCount++;
                    }
                    else if (!string.Equals(
                                 batch.BatchKey,
                                 work.Plan.BatchKey,
                                 StringComparison.Ordinal))
                    {
                        _faultCount++;
                        _lastFault =
                            "InvalidDataException: rasterizer returned a mismatched batch key.";
                    }
                    else if (batch.ByteSize > _maxCacheBytes)
                    {
                        _faultCount++;
                        _lastFault =
                            "InvalidDataException: raster batch exceeds the cache budget.";
                    }
                    else
                    {
                        var ready = batch;
                        batch = null;
                        drainNotifications = PublishLocked(
                            ready,
                            work.Plan,
                            work.Generation,
                            fromCache: false);
                    }
                }
                FinishWorkerLocked();
            }
        }
        finally
        {
            if (batch is not null)
            {
                lock (_gate)
                {
                    DisposeOwnedBatchLocked(batch);
                }
            }
            if (drainNotifications)
            {
                DrainPublishedNotifications();
            }
        }
    }

    private bool PublishLocked(
        PlayerInfoRasterBatch batch,
        PlayerInfoRasterPlan plan,
        long generation,
        bool fromCache)
    {
        var previous = _current;
        _current = batch;
        _currentPlan = plan;

        var inactiveBudget = _maxCacheBytes - batch.ByteSize;
        if (previous is not null)
        {
            if (!_cache.TryStore(previous, inactiveBudget))
            {
                DisposeOwnedBatchLocked(previous);
            }
        }
        _cache.TrimTo(inactiveBudget);

        _publishCount++;
        var handlers = BatchPublished;
        if (handlers is null)
        {
            return false;
        }
        _publishedNotifications.Enqueue(new PublishedNotification(
            handlers,
            new PlayerInfoRasterBatchPublishedEventArgs(
                batch.BatchKey,
                generation,
                fromCache)));
        if (_notificationDispatching)
        {
            return false;
        }
        _notificationDispatching = true;
        return true;
    }

    private void DrainPublishedNotifications()
    {
        // Publish order and the single-drainer handoff are frozen under _gate.
        // External observers run without that lock; later publishers only enqueue,
        // so a slow observer cannot stall ownership state or reorder notifications.
        while (true)
        {
            PublishedNotification notification;
            lock (_gate)
            {
                if (_disposed || _publishedNotifications.Count == 0)
                {
                    if (_disposed)
                    {
                        _publishedNotifications.Clear();
                    }
                    _notificationDispatching = false;
                    return;
                }
                notification = _publishedNotifications.Dequeue();
            }
            foreach (EventHandler<PlayerInfoRasterBatchPublishedEventArgs> handler
                     in notification.Handlers.GetInvocationList())
            {
                lock (_gate)
                {
                    if (_disposed)
                    {
                        break;
                    }
                    _activeNotificationCallbacks++;
                    _notificationCallbackThreadId =
                        Environment.CurrentManagedThreadId;
                }
                try
                {
                    handler(this, notification.Args);
                }
                catch
                {
                    // Observers are diagnostic/repaint notification only and must
                    // not corrupt cache ownership or the single-worker state machine.
                }
                finally
                {
                    lock (_gate)
                    {
                        _activeNotificationCallbacks--;
                        if (_activeNotificationCallbacks == 0)
                        {
                            _notificationCallbackThreadId = 0;
                            Monitor.PulseAll(_gate);
                        }
                    }
                }
            }
        }
    }

    private void FinishWorkerLocked()
    {
        _workerScheduled = false;
        if (!_disposed && _pending is not null)
        {
            EnsureWorkerLocked();
        }
        else
        {
            CompleteIdleIfPossibleLocked();
        }
    }

    private PlayerInfoRasterPipelineSnapshot SnapshotLocked()
    {
        var currentBytes = _current?.ByteSize ?? 0;
        var currentCount = _current is null ? 0 : 1;
        return new PlayerInfoRasterPipelineSnapshot(
            _generation,
            _requestCount,
            _publishCount,
            _cacheHitCount,
            _currentLayerHitCount,
            _cacheLayerHitCount,
            _parseCount,
            _rasterCount,
            _activeWorkers,
            _maxConcurrentWorkers,
            _pendingReplacementCount,
            _staleDiscardCount,
            _faultCount,
            _cancelCount,
            _disposedBatchCount,
            _disposedLayerCount,
            checked(currentBytes + _cache.CurrentBytes),
            checked(currentCount + _cache.Count),
            _desiredBatchKey,
            _current?.BatchKey,
            _lastFault);
    }

    private void DisposeOwnedBatchLocked(PlayerInfoRasterBatch batch)
    {
        var disposedLayers = batch.DisposeOwnedLayers();
        if (disposedLayers == 0)
        {
            return;
        }
        _disposedBatchCount = checked(_disposedBatchCount + 1);
        _disposedLayerCount = checked(
            _disposedLayerCount + disposedLayers);
    }

    private void CompleteIdleIfPossibleLocked()
    {
        if (!_workerScheduled && _activeWorkers == 0 && _pending is null)
        {
            _idle.TrySetResult(true);
        }
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    private void ThrowIfBorrowedMutation()
    {
        if (_borrowDepth != 0)
        {
            throw new InvalidOperationException(
                "PlayerInfo raster ownership cannot mutate inside TryUseCurrent.");
        }
    }

    private void WaitForNotificationCallbacksLocked()
    {
        int currentThreadId = Environment.CurrentManagedThreadId;
        while (_activeNotificationCallbacks != 0 &&
               _notificationCallbackThreadId != currentThreadId)
        {
            Monitor.Wait(_gate);
        }
    }

    private static TaskCompletionSource<bool> CompletedTaskCompletionSource()
    {
        var completed = new TaskCompletionSource<bool>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        completed.SetResult(true);
        return completed;
    }

    private sealed class InactiveBatchCache
    {
        private sealed class Entry(
            PlayerInfoRasterBatch batch,
            LinkedListNode<string> node)
        {
            internal PlayerInfoRasterBatch Batch { get; } = batch;
            internal LinkedListNode<string> Node { get; } = node;
        }

        private readonly Dictionary<string, Entry> _entries =
            new(StringComparer.Ordinal);
        private readonly LinkedList<string> _lru = new();
        private readonly Action<PlayerInfoRasterBatch> _dispose;

        internal InactiveBatchCache(
            Action<PlayerInfoRasterBatch> dispose)
        {
            _dispose = dispose ??
                throw new ArgumentNullException(nameof(dispose));
        }

        internal long CurrentBytes { get; private set; }
        internal int Count => _entries.Count;

        internal bool TryTake(
            string batchKey,
            out PlayerInfoRasterBatch batch)
        {
            if (!_entries.Remove(batchKey, out var entry))
            {
                batch = null!;
                return false;
            }
            _lru.Remove(entry.Node);
            CurrentBytes -= entry.Batch.ByteSize;
            batch = entry.Batch;
            return true;
        }

        /// <summary>
        /// 成功后 cache 接管所有权；失败仍由 caller 持有。
        /// </summary>
        internal bool TryStore(
            PlayerInfoRasterBatch batch,
            long maxInactiveBytes)
        {
            if (maxInactiveBytes < 0 ||
                batch.ByteSize > maxInactiveBytes)
            {
                return false;
            }
            if (_entries.TryGetValue(batch.BatchKey, out var duplicate))
            {
                RemoveAndDispose(duplicate);
            }
            TrimTo(maxInactiveBytes - batch.ByteSize);
            var node = _lru.AddFirst(batch.BatchKey);
            _entries.Add(batch.BatchKey, new Entry(batch, node));
            CurrentBytes = checked(CurrentBytes + batch.ByteSize);
            return true;
        }

        internal void TrimTo(long maxBytes)
        {
            maxBytes = Math.Max(0, maxBytes);
            while (CurrentBytes > maxBytes && _lru.Last is not null)
            {
                RemoveAndDispose(_entries[_lru.Last.Value]);
            }
        }

        internal void Clear()
        {
            foreach (var entry in _entries.Values)
            {
                _dispose(entry.Batch);
            }
            _entries.Clear();
            _lru.Clear();
            CurrentBytes = 0;
        }

        private void RemoveAndDispose(Entry entry)
        {
            _entries.Remove(entry.Batch.BatchKey);
            _lru.Remove(entry.Node);
            CurrentBytes -= entry.Batch.ByteSize;
            _dispose(entry.Batch);
        }
    }
}
