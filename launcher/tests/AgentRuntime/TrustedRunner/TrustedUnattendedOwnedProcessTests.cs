using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.TrustedRunner;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.TrustedRunner
{
    public sealed class
        TrustedUnattendedOwnedProcessTests
    {
        [Fact]
        public async Task ForcedRecoveryKillsOnlyExactOwnedProcessTree()
        {
            using Process owned =
                StartLongLivedProcess();
            using Process unrelated =
                StartLongLivedProcess();
            try
            {
                bool forced =
                    await TrustedUnattendedRunner
                        .RecoverExactOwnedGuardianAsync(
                            owned,
                            protocolShutdownObserved:
                                false,
                            recoveryExitTimeout:
                                TimeSpan
                                    .FromMilliseconds(
                                        100));

                Assert.True(forced);
                Assert.True(owned.HasExited);
                Assert.False(unrelated.HasExited);
            }
            finally
            {
                if (!owned.HasExited)
                    owned.Kill(
                        entireProcessTree: true);
                if (!unrelated.HasExited)
                {
                    unrelated.Kill(
                        entireProcessTree: true);
                    await unrelated
                        .WaitForExitAsync();
                }
            }
        }

        [Fact]
        public async Task AlreadyCleanlyExitedProcessNeedsNoRecovery()
        {
            using Process exited =
                StartExitProcess(0);
            await exited.WaitForExitAsync();

            bool forced =
                await TrustedUnattendedRunner
                    .RecoverExactOwnedGuardianAsync(
                        exited,
                        protocolShutdownObserved:
                            true,
                        recoveryExitTimeout:
                            TimeSpan.Zero);

            Assert.False(forced);
            Assert.Equal(0, exited.ExitCode);
            TrustedUnattendedRunner
                .RequireCleanProtocolExit(exited);
        }

        [Fact]
        public async Task ProtocolShutdownRejectsNonzeroOwnedExit()
        {
            using Process crashed =
                StartExitProcess(7);
            await crashed.WaitForExitAsync();

            InvalidDataException error =
                Assert.Throws<InvalidDataException>(
                    () =>
                        TrustedUnattendedRunner
                            .RequireCleanProtocolExit(
                                crashed));

            Assert.Equal(
                "trusted_runner_protocol_shutdown_exit_code_invalid",
                error.Message);
        }

        [Fact]
        public async Task ConnectedProtocolRunsEofThenShutdownAndRequiresCleanExit()
        {
            using Process guardian =
                StartDelayedExitProcess();
            bool adapterReachedEof = false;
            bool shutdownCalled = false;

            int exitCode =
                await TrustedUnattendedRunner
                    .RunConnectedProtocolAsync(
                        guardian,
                        _ =>
                        {
                            adapterReachedEof =
                                true;
                            return Task.FromResult(0);
                        },
                        _ =>
                        {
                            Assert.True(
                                adapterReachedEof);
                            shutdownCalled = true;
                            return Task.CompletedTask;
                        },
                        () => ValueTask.CompletedTask,
                        TimeSpan.FromSeconds(5),
                        TimeSpan.FromSeconds(5),
                        default);

            Assert.Equal(0, exitCode);
            Assert.True(shutdownCalled);
            Assert.True(guardian.HasExited);
            Assert.Equal(0, guardian.ExitCode);
        }

        [Fact]
        public async Task ConnectedProtocolBoundsHungShutdownAndAllowsExactRecovery()
        {
            using Process guardian =
                StartLongLivedProcess();
            using Process unrelated =
                StartLongLivedProcess();
            var never =
                new TaskCompletionSource(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            bool connectionAborted = false;
            bool forcedRecovery = false;
            bool unrelatedWasAlive = false;
            var elapsed = Stopwatch.StartNew();
            try
            {
                TimeoutException error =
                    await Assert.ThrowsAsync<
                        TimeoutException>(
                        () =>
                            TrustedUnattendedRunner
                                .RunConnectedProtocolAsync(
                                    guardian,
                                    _ =>
                                        Task.FromResult(0),
                                    _ => never.Task,
                                    () =>
                                    {
                                        connectionAborted =
                                            true;
                                        return ValueTask
                                            .CompletedTask;
                                    },
                                    TimeSpan
                                        .FromMilliseconds(
                                            50),
                                    TimeSpan
                                        .FromSeconds(1),
                                    default));

                Assert.Equal(
                    "trusted_runner_protocol_shutdown_rpc_timeout",
                    error.Message);
            }
            finally
            {
                forcedRecovery =
                    await TrustedUnattendedRunner
                        .RecoverExactOwnedGuardianAsync(
                            guardian,
                            protocolShutdownObserved:
                                false,
                            recoveryExitTimeout:
                                TimeSpan.Zero);
                unrelatedWasAlive =
                    !unrelated.HasExited;
                if (!unrelated.HasExited)
                {
                    unrelated.Kill(
                        entireProcessTree: true);
                    await unrelated
                        .WaitForExitAsync();
                }
            }

            Assert.True(connectionAborted);
            Assert.True(forcedRecovery);
            Assert.True(guardian.HasExited);
            Assert.True(unrelatedWasAlive);
            Assert.False(
                elapsed.Elapsed
                    > TimeSpan.FromSeconds(3));
        }

        [Fact]
        public async Task ConnectedProtocolBoundsSynchronousShutdownAndHungAbortDelegates()
        {
            using Process guardian =
                StartLongLivedProcess();
            using var releaseShutdown =
                new ManualResetEventSlim(false);
            var shutdownEntered =
                new TaskCompletionSource(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            var abortEntered =
                new TaskCompletionSource(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            var releaseAbort =
                new TaskCompletionSource(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            var elapsed = Stopwatch.StartNew();
            try
            {
                Task<int> run =
                    TrustedUnattendedRunner
                        .RunConnectedProtocolAsync(
                            guardian,
                            _ => Task.FromResult(0),
                            _ =>
                            {
                                shutdownEntered
                                    .TrySetResult();
                                releaseShutdown.Wait();
                                return Task.CompletedTask;
                            },
                            () =>
                            {
                                abortEntered
                                    .TrySetResult();
                                return new ValueTask(
                                    releaseAbort.Task);
                            },
                            TimeSpan
                                .FromMilliseconds(
                                    75),
                            TimeSpan.FromSeconds(1),
                            default);

                await shutdownEntered.Task
                    .WaitAsync(
                        TimeSpan.FromSeconds(1));
                TimeoutException error =
                    await Assert.ThrowsAsync<
                            TimeoutException>(
                            async () =>
                                await run.WaitAsync(
                                    TimeSpan
                                        .FromSeconds(
                                            2)));

                Assert.Equal(
                    "trusted_runner_protocol_shutdown_rpc_timeout",
                    error.Message);
                await abortEntered.Task
                    .WaitAsync(
                        TimeSpan.FromSeconds(1));
                Assert.True(
                    elapsed.Elapsed
                        < TimeSpan.FromSeconds(2));
            }
            finally
            {
                releaseShutdown.Set();
                releaseAbort.TrySetResult();
                await TrustedUnattendedRunner
                    .RecoverExactOwnedGuardianAsync(
                        guardian,
                        protocolShutdownObserved:
                            false,
                        recoveryExitTimeout:
                            TimeSpan.Zero);
            }
        }

        private static Process
            StartLongLivedProcess()
        {
            string command =
                Path.Combine(
                    Environment.SystemDirectory,
                    "ping.exe");
            return Process.Start(
                new ProcessStartInfo
                {
                    FileName = command,
                    Arguments =
                        "127.0.0.1 -n 120",
                    UseShellExecute = false,
                    CreateNoWindow = true
                })
                ?? throw new InvalidOperationException(
                    "test_process_start_failed");
        }

        private static Process StartExitProcess(
            int exitCode)
        {
            string command =
                Path.Combine(
                    Environment.SystemDirectory,
                    "cmd.exe");
            return Process.Start(
                new ProcessStartInfo
                {
                    FileName = command,
                    Arguments =
                        "/d /c exit "
                        + exitCode,
                    UseShellExecute = false,
                    CreateNoWindow = true
                })
                ?? throw new InvalidOperationException(
                    "test_process_start_failed");
        }

        private static Process
            StartDelayedExitProcess()
        {
            string command =
                Path.Combine(
                    Environment.SystemDirectory,
                    "cmd.exe");
            return Process.Start(
                new ProcessStartInfo
                {
                    FileName = command,
                    Arguments =
                        "/d /c ping 127.0.0.1 "
                        + "-n 2 >nul & exit 0",
                    UseShellExecute = false,
                    CreateNoWindow = true
                })
                ?? throw new InvalidOperationException(
                    "test_process_start_failed");
        }
    }
}
