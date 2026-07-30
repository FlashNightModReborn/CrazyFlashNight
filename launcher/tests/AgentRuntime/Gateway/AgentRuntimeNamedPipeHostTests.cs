using System;
using System.Collections.Concurrent;
using System.IO;
using System.IO.Pipes;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Transport;
using Microsoft.Win32.SafeHandles;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentRuntimeNamedPipeHostTests
    {
        [Fact]
        public async Task AcceptLoopUsesSameOpaquePipeAndUniqueConnectionIds()
        {
            string pipeId = AgentRendezvousStore.GenerateOpaqueId();
            var verifier = new CountingVerifier();
            var runner = new RecordingRunner();
            await using var host = CreateHost(
                pipeId,
                verifier,
                runner);
            Task run = host.RunAsync(CancellationToken.None);
            await using NamedPipeClientStream first =
                CreateClient(host.PipeName);
            await using NamedPipeClientStream second =
                CreateClient(host.PipeName);
            using var timeout = NewTimeout();

            await first.ConnectAsync(timeout.Token);
            await runner.WaitForInvocationsAsync(1, timeout.Token);
            await second.ConnectAsync(timeout.Token);
            await runner.WaitForInvocationsAsync(2, timeout.Token);

            string[] ids = runner.ConnectionIds.ToArray();
            Assert.Equal(2, ids.Length);
            Assert.NotEqual(ids[0], ids[1]);
            Assert.All(
                ids,
                id => Assert.Matches(
                    new Regex(
                        "^connection_[0-9a-f]{32}$",
                        RegexOptions.CultureInvariant),
                    id));
            Assert.Equal(2, verifier.VerificationCount);
            Assert.False(run.IsCompleted);

            await host.DisposeAsync();
            await run.WaitAsync(timeout.Token);
            Assert.Equal(2, runner.CompletionCount);
        }

        [Fact]
        public async Task RejectedPeerNeverReachesRunnerAndLoopContinues()
        {
            string pipeId = AgentRendezvousStore.GenerateOpaqueId();
            var verifier = new CountingVerifier(rejectFirst: true);
            var runner = new RecordingRunner();
            await using var host = CreateHost(
                pipeId,
                verifier,
                runner);
            Task run = host.RunAsync(CancellationToken.None);
            await using NamedPipeClientStream rejected =
                CreateClient(host.PipeName);
            await using NamedPipeClientStream accepted =
                CreateClient(host.PipeName);
            using var timeout = NewTimeout();

            await rejected.ConnectAsync(timeout.Token);
            await verifier.WaitForVerificationsAsync(
                1,
                timeout.Token);
            Assert.Equal(0, runner.InvocationCount);

            await accepted.ConnectAsync(timeout.Token);
            await runner.WaitForInvocationsAsync(1, timeout.Token);

            Assert.Equal(2, verifier.VerificationCount);
            Assert.Equal(1, runner.InvocationCount);
            Assert.False(run.IsCompleted);
        }

        [Fact]
        public async Task RunnerFailureIsIsolatedFromNextConnection()
        {
            string pipeId = AgentRendezvousStore.GenerateOpaqueId();
            var verifier = new CountingVerifier();
            var runner = new RecordingRunner(failFirst: true);
            await using var host = CreateHost(
                pipeId,
                verifier,
                runner);
            Task run = host.RunAsync(CancellationToken.None);
            await using NamedPipeClientStream failed =
                CreateClient(host.PipeName);
            await using NamedPipeClientStream next =
                CreateClient(host.PipeName);
            using var timeout = NewTimeout();

            await failed.ConnectAsync(timeout.Token);
            await runner.WaitForInvocationsAsync(1, timeout.Token);
            await runner.WaitForCompletionsAsync(1, timeout.Token);

            await next.ConnectAsync(timeout.Token);
            await runner.WaitForInvocationsAsync(2, timeout.Token);

            Assert.Equal(2, verifier.VerificationCount);
            Assert.Equal(2, runner.InvocationCount);
            Assert.False(run.IsCompleted);
        }

        [Fact]
        public async Task DisposeStopsPendingAcceptWithoutAClient()
        {
            string pipeId = AgentRendezvousStore.GenerateOpaqueId();
            var verifier = new CountingVerifier();
            var runner = new RecordingRunner();
            await using var host = CreateHost(
                pipeId,
                verifier,
                runner);
            Task run = host.RunAsync(CancellationToken.None);
            using var timeout = NewTimeout();

            await Task.Yield();
            Assert.False(run.IsCompleted);

            await host.DisposeAsync().AsTask().WaitAsync(timeout.Token);
            await run.WaitAsync(timeout.Token);

            Assert.Equal(0, verifier.VerificationCount);
            Assert.Equal(0, runner.InvocationCount);
            Assert.Throws<ObjectDisposedException>(
                (Action)(() =>
                {
                    _ = host.RunAsync(CancellationToken.None);
                }));
        }

        [Fact]
        public async Task DisposeWaitsForActiveRunnerCleanup()
        {
            string pipeId = AgentRendezvousStore.GenerateOpaqueId();
            var verifier = new CountingVerifier();
            var runner = new RecordingRunner(
                holdCompletion: true);
            await using var host = CreateHost(
                pipeId,
                verifier,
                runner);
            Task run = host.RunAsync(CancellationToken.None);
            await using NamedPipeClientStream client =
                CreateClient(host.PipeName);
            using var timeout = NewTimeout();

            await client.ConnectAsync(timeout.Token);
            await runner.WaitForInvocationsAsync(1, timeout.Token);

            Task disposing = host.DisposeAsync().AsTask();
            try
            {
                await runner.WaitForCancellationAsync(timeout.Token);
                Assert.False(disposing.IsCompleted);
            }
            finally
            {
                runner.ReleaseCompletion();
            }
            await disposing.WaitAsync(timeout.Token);
            await run.WaitAsync(timeout.Token);

            Assert.Equal(1, runner.CompletionCount);
            Assert.Equal(1, verifier.VerificationCount);
        }

        private static AgentRuntimeNamedPipeHost CreateHost(
            string pipeId,
            IAgentPipePeerVerifier verifier,
            IAgentRuntimeConnectionRunner runner)
        {
            return new AgentRuntimeNamedPipeHost(
                pipeId,
                new AgentNamedPipeServerFactory(),
                verifier,
                runner);
        }

        private static NamedPipeClientStream CreateClient(
            string pipeName)
        {
            return new NamedPipeClientStream(
                ".",
                pipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous);
        }

        private static CancellationTokenSource NewTimeout()
        {
            return new CancellationTokenSource(
                TimeSpan.FromSeconds(10));
        }

        private sealed class CountingVerifier
            : IAgentPipePeerVerifier
        {
            private readonly bool _rejectFirst;
            private readonly SemaphoreSlim _verificationSignal =
                new SemaphoreSlim(0);
            private int _verificationCount;

            public int VerificationCount
            {
                get { return Volatile.Read(ref _verificationCount); }
            }

            public CountingVerifier(bool rejectFirst = false)
            {
                _rejectFirst = rejectFirst;
            }

            public AgentPipePeerVerificationResult Verify(
                SafePipeHandle pipeHandle)
            {
                int current =
                    Interlocked.Increment(ref _verificationCount);
                _verificationSignal.Release();
                if (_rejectFirst && current == 1)
                {
                    return AgentPipePeerVerificationResult.Reject(
                        "remote_client_rejected");
                }

                return AgentPipePeerVerificationResult.Accept(
                    new AgentProcessSecurityIdentity(
                        checked((uint)Environment.ProcessId),
                        DateTimeOffset.Parse(
                            "2026-07-30T08:00:00Z"),
                        1,
                        AgentElevationType.Limited,
                        "S-1-5-21-1000"));
            }

            public async Task WaitForVerificationsAsync(
                int expected,
                CancellationToken cancellationToken)
            {
                while (VerificationCount < expected)
                {
                    await _verificationSignal.WaitAsync(
                        cancellationToken);
                }
            }
        }

        private sealed class RecordingRunner
            : IAgentRuntimeConnectionRunner
        {
            private readonly bool _failFirst;
            private readonly bool _holdCompletion;
            private readonly SemaphoreSlim _invocationSignal =
                new SemaphoreSlim(0);
            private readonly SemaphoreSlim _completionSignal =
                new SemaphoreSlim(0);
            private readonly TaskCompletionSource<bool>
                _cancellationObserved =
                    new TaskCompletionSource<bool>(
                        TaskCreationOptions.RunContinuationsAsynchronously);
            private readonly TaskCompletionSource<bool>
                _completionRelease =
                    new TaskCompletionSource<bool>(
                        TaskCreationOptions.RunContinuationsAsynchronously);
            private int _invocationCount;
            private int _completionCount;

            public ConcurrentQueue<string> ConnectionIds { get; } =
                new ConcurrentQueue<string>();

            public int InvocationCount
            {
                get { return Volatile.Read(ref _invocationCount); }
            }

            public int CompletionCount
            {
                get { return Volatile.Read(ref _completionCount); }
            }

            public RecordingRunner(
                bool failFirst = false,
                bool holdCompletion = false)
            {
                _failFirst = failFirst;
                _holdCompletion = holdCompletion;
                if (!holdCompletion)
                    _completionRelease.TrySetResult(true);
            }

            public async Task<AgentConnectionTermination>
                RunConnectionAsync(
                    string connectionId,
                    Stream stream,
                    AgentProcessSecurityIdentity peerIdentity,
                    CancellationToken cancellationToken)
            {
                int invocation =
                    Interlocked.Increment(ref _invocationCount);
                ConnectionIds.Enqueue(connectionId);
                _invocationSignal.Release();
                try
                {
                    if (_failFirst && invocation == 1)
                    {
                        throw new InvalidOperationException(
                            "synthetic runner failure");
                    }

                    await Task.Delay(
                        Timeout.InfiniteTimeSpan,
                        cancellationToken);
                    return new AgentConnectionTermination(
                        AgentConnectionTerminationKind.CleanDisconnect,
                        "connection_closed",
                        null);
                }
                catch (OperationCanceledException)
                    when (cancellationToken.IsCancellationRequested)
                {
                    _cancellationObserved.TrySetResult(true);
                    throw;
                }
                finally
                {
                    if (_holdCompletion)
                    {
                        await _completionRelease.Task.ConfigureAwait(
                            false);
                    }
                    Interlocked.Increment(ref _completionCount);
                    _completionSignal.Release();
                }
            }

            public async Task WaitForInvocationsAsync(
                int expected,
                CancellationToken cancellationToken)
            {
                while (InvocationCount < expected)
                {
                    await _invocationSignal.WaitAsync(
                        cancellationToken);
                }
            }

            public async Task WaitForCompletionsAsync(
                int expected,
                CancellationToken cancellationToken)
            {
                while (CompletionCount < expected)
                {
                    await _completionSignal.WaitAsync(
                        cancellationToken);
                }
            }

            public Task WaitForCancellationAsync(
                CancellationToken cancellationToken)
            {
                return _cancellationObserved.Task.WaitAsync(
                    cancellationToken);
            }

            public void ReleaseCompletion()
            {
                _completionRelease.TrySetResult(true);
            }
        }
    }
}
