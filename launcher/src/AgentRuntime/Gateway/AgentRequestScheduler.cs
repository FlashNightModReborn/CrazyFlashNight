using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Gateway
{
    internal sealed class AgentScheduledResult<T>
    {
        private AgentScheduledResult(
            bool success,
            T value,
            string reasonCode)
        {
            Success = success;
            Value = value;
            ReasonCode = reasonCode;
        }

        public bool Success { get; }
        public T Value { get; }
        public string ReasonCode { get; }

        public static AgentScheduledResult<T> Completed(T value)
        {
            return new AgentScheduledResult<T>(true, value, null);
        }

        public static AgentScheduledResult<T> Rejected(
            string reasonCode)
        {
            return new AgentScheduledResult<T>(
                false,
                default,
                reasonCode);
        }
    }

    /// <summary>
    /// Per-connection hard limits. The caller supplies the monotonic instant
    /// at which the complete request frame was received so parsing, admission,
    /// queueing and execution all consume one server-capped budget.
    /// </summary>
    internal sealed class AgentRequestScheduler : IDisposable
    {
        private const long RateWindowMilliseconds = 60_000;
        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly SemaphoreSlim _concurrency =
            new SemaphoreSlim(
                AgentProtocolV1
                    .MaximumConcurrentRequestsPerClient,
                AgentProtocolV1
                    .MaximumConcurrentRequestsPerClient);
        private readonly Queue<long> _requestTimes =
            new Queue<long>();
        private int _queued;
        private bool _disposed;

        public AgentRequestScheduler(IAgentRuntimeClock clock)
        {
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
        }

        internal int QueuedCount
        {
            get
            {
                lock (_sync) { return _queued; }
            }
        }

        public Task<AgentScheduledResult<T>> ExecuteAsync<T>(
            int requestedDeadlineMs,
            Func<CancellationToken, Task<T>> operation,
            CancellationToken cancellationToken)
        {
            return ExecuteAsync(
                requestedDeadlineMs,
                _clock.MonotonicMilliseconds,
                operation,
                cancellationToken);
        }

        internal async Task<AgentScheduledResult<T>> ExecuteAsync<T>(
            int requestedDeadlineMs,
            long receivedMonotonic,
            Func<CancellationToken, Task<T>> operation,
            CancellationToken cancellationToken)
        {
            if (operation == null)
                throw new ArgumentNullException(nameof(operation));
            if (requestedDeadlineMs <= 0)
            {
                return AgentScheduledResult<T>.Rejected(
                    "arguments_invalid");
            }

            int deadlineMs = Math.Min(
                requestedDeadlineMs,
                AgentProtocolV1.MaximumActionDeadlineMs);
            lock (_sync)
            {
                ThrowIfDisposed();
                PurgeRateWindowLocked(
                    _clock.MonotonicMilliseconds);
                if (_requestTimes.Count
                    >= AgentProtocolV1.MaximumRequestsPerMinute)
                {
                    return AgentScheduledResult<T>.Rejected(
                        "rate_limited");
                }
                _requestTimes.Enqueue(receivedMonotonic);
            }
            long deadlineMonotonic = checked(
                receivedMonotonic + deadlineMs);

            bool acquired = _concurrency.Wait(0);
            bool countedAsQueued = false;
            if (!acquired)
            {
                lock (_sync)
                {
                    ThrowIfDisposed();
                    if (_queued
                        >= AgentProtocolV1.MaximumClientQueueDepth)
                    {
                        return AgentScheduledResult<T>.Rejected(
                            "queue_full");
                    }
                    _queued++;
                    countedAsQueued = true;
                }
                try
                {
                    long waitRemaining = deadlineMonotonic
                        - _clock.MonotonicMilliseconds;
                    if (waitRemaining <= 0)
                    {
                        return AgentScheduledResult<T>.Rejected(
                            "deadline_exceeded");
                    }
                    acquired = await _concurrency.WaitAsync(
                        TimeSpan.FromMilliseconds(waitRemaining),
                        cancellationToken).ConfigureAwait(false);
                    if (!acquired)
                    {
                        return AgentScheduledResult<T>.Rejected(
                            "deadline_exceeded");
                    }
                }
                catch (OperationCanceledException)
                {
                    return AgentScheduledResult<T>.Rejected(
                        cancellationToken.IsCancellationRequested
                            ? "connection_cancelled"
                            : "deadline_exceeded");
                }
                finally
                {
                    lock (_sync)
                    {
                        if (countedAsQueued)
                            _queued--;
                    }
                }
            }

            try
            {
                long remaining = deadlineMonotonic
                    - _clock.MonotonicMilliseconds;
                if (remaining <= 0)
                {
                    return AgentScheduledResult<T>.Rejected(
                        "deadline_exceeded");
                }
                using var deadlineSource =
                    new CancellationTokenSource(
                        TimeSpan.FromMilliseconds(remaining));
                using var linked =
                    CancellationTokenSource
                        .CreateLinkedTokenSource(
                            cancellationToken,
                            deadlineSource.Token);
                try
                {
                    T result = await operation(linked.Token)
                        .ConfigureAwait(false);
                    if (_clock.MonotonicMilliseconds
                        > deadlineMonotonic)
                    {
                        return AgentScheduledResult<T>.Rejected(
                            "deadline_exceeded");
                    }
                    return AgentScheduledResult<T>
                        .Completed(result);
                }
                catch (OperationCanceledException)
                {
                    return AgentScheduledResult<T>.Rejected(
                        cancellationToken.IsCancellationRequested
                            ? "connection_cancelled"
                            : "deadline_exceeded");
                }
                catch
                {
                    return AgentScheduledResult<T>.Rejected(
                        "internal_error");
                }
            }
            finally
            {
                if (acquired)
                    _concurrency.Release();
            }
        }

        public void Dispose()
        {
            lock (_sync)
            {
                _disposed = true;
            }
            // An accepted operation can still be unwinding its finally block
            // after connection cancellation. Disposing SemaphoreSlim here
            // would turn that normal Release into ObjectDisposedException and
            // obscure the real termination reason. The semaphore owns no OS
            // handle; leave it for GC after the connection drains.
        }

        private void PurgeRateWindowLocked(long now)
        {
            while (_requestTimes.Count > 0
                && now - _requestTimes.Peek()
                    >= RateWindowMilliseconds)
            {
                _requestTimes.Dequeue();
            }
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(
                    nameof(AgentRequestScheduler));
        }
    }
}
