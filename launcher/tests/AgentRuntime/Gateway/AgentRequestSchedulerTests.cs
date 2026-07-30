using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentRequestSchedulerTests
    {
        [Fact]
        public async Task RateWindowRejectsRequest121AndRecovers()
        {
            var clock = new ManualAgentRuntimeClock();
            using var scheduler =
                new AgentRequestScheduler(clock);
            for (int index = 0; index < 120; index++)
            {
                AgentScheduledResult<int> accepted =
                    await scheduler.ExecuteAsync(
                        1_000,
                        _ => Task.FromResult(index),
                        CancellationToken.None);
                Assert.True(accepted.Success);
            }

            AgentScheduledResult<int> rejected =
                await scheduler.ExecuteAsync(
                    1_000,
                    _ => Task.FromResult(121),
                    CancellationToken.None);
            Assert.False(rejected.Success);
            Assert.Equal("rate_limited", rejected.ReasonCode);

            clock.Advance(TimeSpan.FromMinutes(1));
            AgentScheduledResult<int> recovered =
                await scheduler.ExecuteAsync(
                    1_000,
                    _ => Task.FromResult(122),
                    CancellationToken.None);
            Assert.True(recovered.Success);
        }

        [Fact]
        public async Task QueueDepthIsHardCappedAt16()
        {
            var clock = new ManualAgentRuntimeClock();
            using var scheduler =
                new AgentRequestScheduler(clock);
            var release = new TaskCompletionSource<bool>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var started = new TaskCompletionSource<bool>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            int running = 0;
            Func<CancellationToken, Task<int>> blocked =
                async cancellationToken =>
                {
                    if (Interlocked.Increment(ref running) == 4)
                        started.TrySetResult(true);
                    await release.Task.WaitAsync(cancellationToken);
                    return 1;
                };

            Task<AgentScheduledResult<int>>[] active =
                Enumerable.Range(0, 4)
                    .Select(_ => scheduler.ExecuteAsync(
                        30_000,
                        blocked,
                        CancellationToken.None))
                    .ToArray();
            await started.Task.WaitAsync(TimeSpan.FromSeconds(2));
            var queued = new List<
                Task<AgentScheduledResult<int>>>();
            for (int index = 0; index < 16; index++)
            {
                queued.Add(scheduler.ExecuteAsync(
                    30_000,
                    _ => Task.FromResult(2),
                    CancellationToken.None));
            }
            Assert.Equal(16, scheduler.QueuedCount);

            AgentScheduledResult<int> overflow =
                await scheduler.ExecuteAsync(
                    30_000,
                    _ => Task.FromResult(3),
                    CancellationToken.None);
            Assert.False(overflow.Success);
            Assert.Equal("queue_full", overflow.ReasonCode);

            release.SetResult(true);
            await Task.WhenAll(active.Concat(queued));
        }

        [Fact]
        public async Task QueueWaitConsumesMonotonicDeadline()
        {
            var clock = new ManualAgentRuntimeClock();
            using var scheduler =
                new AgentRequestScheduler(clock);
            var release = new TaskCompletionSource<bool>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var started = new TaskCompletionSource<bool>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            int running = 0;
            Func<CancellationToken, Task<int>> blocked =
                async cancellationToken =>
                {
                    if (Interlocked.Increment(ref running) == 4)
                        started.TrySetResult(true);
                    await release.Task.WaitAsync(cancellationToken);
                    return 1;
                };
            Task<AgentScheduledResult<int>>[] active =
                Enumerable.Range(0, 4)
                    .Select(_ => scheduler.ExecuteAsync(
                        30_000,
                        blocked,
                        CancellationToken.None))
                    .ToArray();
            await started.Task.WaitAsync(TimeSpan.FromSeconds(2));

            Task<AgentScheduledResult<int>> queued =
                scheduler.ExecuteAsync(
                    500,
                    _ => Task.FromResult(2),
                    CancellationToken.None);
            clock.Advance(TimeSpan.FromSeconds(1));
            release.SetResult(true);

            AgentScheduledResult<int> result = await queued;
            Assert.False(result.Success);
            Assert.Equal(
                "deadline_exceeded",
                result.ReasonCode);
            await Task.WhenAll(active);
        }

        [Fact]
        public async Task PreAdmissionWorkConsumesFrameReceivedDeadline()
        {
            var clock = new ManualAgentRuntimeClock();
            using var scheduler =
                new AgentRequestScheduler(clock);
            int invocationCount = 0;
            long frameReceivedMonotonic =
                clock.MonotonicMilliseconds;
            clock.Advance(TimeSpan.FromMilliseconds(501));

            AgentScheduledResult<int> result =
                await scheduler.ExecuteAsync(
                    500,
                    frameReceivedMonotonic,
                    _ =>
                    {
                        Interlocked.Increment(
                            ref invocationCount);
                        return Task.FromResult(1);
                    },
                    CancellationToken.None);

            Assert.False(result.Success);
            Assert.Equal(
                "deadline_exceeded",
                result.ReasonCode);
            Assert.Equal(
                0,
                Volatile.Read(ref invocationCount));
        }
    }
}
