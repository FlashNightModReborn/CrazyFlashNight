using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;

namespace CF7Launcher.AgentRuntime.TrustedRunner
{
    internal static class TrustedUnattendedRunner
    {
        private static readonly TimeSpan CredentialPoll =
            TimeSpan.FromMilliseconds(50);
        private static readonly TimeSpan GracefulExitTimeout =
            TimeSpan.FromSeconds(10);
        private static readonly TimeSpan ShutdownProtocolTimeout =
            TimeSpan.FromSeconds(30);
        private static readonly TimeSpan RecoveryExitTimeout =
            TimeSpan.FromSeconds(5);
        private static readonly TimeSpan AbortAttemptTimeout =
            TimeSpan.FromMilliseconds(250);
        private static readonly TimeSpan KillObservationTimeout =
            TimeSpan.FromSeconds(5);
        private const int MaximumCompletionEvidenceBytes =
            16 * 1024;

        public static bool IsInvocation(string[] args)
        {
            return TrustedUnattendedRunnerOptions
                .IsRunnerInvocation(args);
        }

        public static int Run(string[] args)
        {
            try
            {
                return RunAsync(
                        args,
                        Console.OpenStandardInput(),
                        Console.OpenStandardOutput(),
                        CancellationToken.None)
                    .GetAwaiter()
                    .GetResult();
            }
            catch (Exception exception)
            {
                WriteMinimalDiagnostic(exception);
                return 2;
            }
        }

        internal static async Task<int> RunAsync(
            string[] args,
            Stream input,
            Stream output,
            CancellationToken cancellationToken)
        {
            TrustedUnattendedRunnerOptions options =
                TrustedUnattendedRunnerOptions.Parse(
                    args);
            TrustedUnattendedRuntimeBundle bundle =
                TrustedUnattendedRuntimeBundle
                    .VerifySelectedProcess();
            using TrustedUnattendedBootstrapLease lease =
                TrustedUnattendedBootstrapLease.Create(
                    bundle,
                    options.Slot);
            using Process guardian =
                lease.StartOwnedGuardian();
            bool protocolShutdownObserved = false;
            bool forcedRecovery = false;
            int adapterExitCode = 2;
            ActionReceipt shutdownReceipt = null;
            try
            {
                TrustedUnattendedCredential credential =
                    lease.WaitForCredential(
                        guardian,
                        CredentialPoll,
                        lease.CredentialAcquisitionPolicyMaximum,
                        cancellationToken);
                await using (
                    TrustedUnattendedAgentClient client =
                        await TrustedUnattendedAgentClient
                            .ConnectAsync(
                                bundle.ProjectRoot,
                                guardian,
                                lease.ClientInstanceId,
                                credential,
                                options.Adapter,
                                cancellationToken)
                            .ConfigureAwait(false))
                {
                    adapterExitCode =
                        await RunConnectedProtocolAsync(
                            guardian,
                            token =>
                                TrustedUnattendedStdioAdapter
                                    .RunAsync(
                                        options.Adapter,
                                        client,
                                        input,
                                        output,
                                        token),
                            async token =>
                            {
                                shutdownReceipt =
                                    await client
                                        .ShutdownOwnedRuntimeAsync(
                                            token)
                                        .ConfigureAwait(false);
                            },
                            () => client.DisposeAsync(),
                            ShutdownProtocolTimeout,
                            GracefulExitTimeout,
                            cancellationToken)
                            .ConfigureAwait(false);
                    protocolShutdownObserved = true;
                }
            }
            catch
            {
                forcedRecovery = !guardian.HasExited;
                throw;
            }
            finally
            {
                forcedRecovery |=
                    await RecoverExactOwnedGuardianAsync(
                        guardian,
                        protocolShutdownObserved,
                        RecoveryExitTimeout)
                        .ConfigureAwait(false);
            }
            if (!forcedRecovery
                && protocolShutdownObserved
                && adapterExitCode == 0
                && shutdownReceipt != null)
            {
                Console.Error.WriteLine(
                    FormatCompletionEvidence(
                        bundle.RuntimeMode,
                        bundle.CorePath,
                        bundle.CoreSha256,
                        bundle.BuildIdentity,
                        bundle.PayloadClosure,
                        guardian.Id,
                        shutdownReceipt));
            }
            return forcedRecovery
                ? 3
                : adapterExitCode;
        }

        internal static string FormatCompletionEvidence(
            string runtimeMode,
            string processPath,
            string coreSha256,
            string buildIdentity,
            string payloadClosure,
            int guardianProcessId,
            ActionReceipt terminalReceipt)
        {
            if (string.IsNullOrWhiteSpace(runtimeMode)
                || string.IsNullOrWhiteSpace(processPath)
                || string.IsNullOrWhiteSpace(coreSha256)
                || string.IsNullOrWhiteSpace(buildIdentity)
                || string.IsNullOrWhiteSpace(payloadClosure)
                || guardianProcessId <= 0
                || terminalReceipt == null)
            {
                throw new InvalidDataException(
                    "trusted_runner_completion_evidence_invalid");
            }
            string json = JsonSerializer.Serialize(
                new
                {
                    schema =
                        "cf7.agent_runtime.trusted_unattended_completion.v1",
                    runtimeMode,
                    processPath = Path.GetFullPath(processPath),
                    coreSha256,
                    buildIdentity,
                    payloadClosure,
                    guardianProcessId,
                    terminalReceipt
                },
                AgentProtocolV1.JsonOptions);
            string line =
                "cf7-trusted-runner-evidence: " + json;
            if (Encoding.UTF8.GetByteCount(line)
                > MaximumCompletionEvidenceBytes)
            {
                throw new InvalidDataException(
                    "trusted_runner_completion_evidence_oversize");
            }
            return line;
        }

        internal static async Task<int>
            RunConnectedProtocolAsync(
                Process guardian,
                Func<CancellationToken, Task<int>>
                    runAdapter,
                Func<CancellationToken, Task>
                    shutdown,
                Func<ValueTask> abortConnection,
                TimeSpan shutdownTimeout,
                TimeSpan gracefulExitTimeout,
                CancellationToken cancellationToken)
        {
            if (guardian == null)
                throw new ArgumentNullException(
                    nameof(guardian));
            if (runAdapter == null)
                throw new ArgumentNullException(
                    nameof(runAdapter));
            if (shutdown == null)
                throw new ArgumentNullException(
                    nameof(shutdown));
            if (abortConnection == null)
                throw new ArgumentNullException(
                    nameof(abortConnection));
            if (shutdownTimeout <= TimeSpan.Zero)
                throw new ArgumentOutOfRangeException(
                    nameof(shutdownTimeout));
            if (gracefulExitTimeout <= TimeSpan.Zero)
                throw new ArgumentOutOfRangeException(
                    nameof(gracefulExitTimeout));

            int adapterExitCode =
                await runAdapter(
                    cancellationToken)
                    .ConfigureAwait(false);
            await RunShutdownWithDeadlineAsync(
                    shutdown,
                    abortConnection,
                    shutdownTimeout,
                    cancellationToken)
                .ConfigureAwait(false);
            bool exited =
                await WaitForExitAsync(
                    guardian,
                    gracefulExitTimeout,
                    cancellationToken)
                    .ConfigureAwait(false);
            if (!exited)
            {
                throw new TimeoutException(
                    "trusted_runner_protocol_shutdown_exit_timeout");
            }
            RequireCleanProtocolExit(
                guardian);
            return adapterExitCode;
        }

        private static async Task
            RunShutdownWithDeadlineAsync(
                Func<CancellationToken, Task> shutdown,
                Func<ValueTask> abortConnection,
                TimeSpan timeout,
                CancellationToken cancellationToken)
        {
            using var shutdownSource =
                CancellationTokenSource
                    .CreateLinkedTokenSource(
                        cancellationToken);
            Task shutdownTask =
                Task.Run(
                    () => shutdown(
                        shutdownSource.Token),
                    CancellationToken.None);
            try
            {
                await shutdownTask
                    .WaitAsync(
                        timeout,
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (TimeoutException)
            {
                shutdownSource.Cancel();
                await TryAbortConnectionWithinBoundAsync(
                        abortConnection)
                    .ConfigureAwait(false);
                ObserveDetached(shutdownTask);
                throw new TimeoutException(
                    "trusted_runner_protocol_shutdown_rpc_timeout");
            }
            catch (OperationCanceledException)
                when (cancellationToken
                    .IsCancellationRequested)
            {
                shutdownSource.Cancel();
                await TryAbortConnectionWithinBoundAsync(
                        abortConnection)
                    .ConfigureAwait(false);
                ObserveDetached(shutdownTask);
                throw;
            }
        }

        private static async Task
            TryAbortConnectionWithinBoundAsync(
                Func<ValueTask> abortConnection)
        {
            Task abortTask =
                Task.Run(
                    async () =>
                    {
                        try
                        {
                            await abortConnection()
                                .ConfigureAwait(false);
                        }
                        catch
                        {
                        }
                    },
                    CancellationToken.None);
            Task completed =
                await Task.WhenAny(
                        abortTask,
                        Task.Delay(
                            AbortAttemptTimeout))
                    .ConfigureAwait(false);
            if (completed == abortTask)
            {
                await abortTask
                    .ConfigureAwait(false);
                return;
            }
            ObserveDetached(abortTask);
        }

        private static void ObserveDetached(Task task)
        {
            _ = task.ContinueWith(
                completed =>
                {
                    _ = completed.Exception;
                },
                CancellationToken.None,
                TaskContinuationOptions
                    .OnlyOnFaulted
                    | TaskContinuationOptions
                        .ExecuteSynchronously,
                TaskScheduler.Default);
        }

        internal static async Task<bool>
            RecoverExactOwnedGuardianAsync(
                Process guardian,
                bool protocolShutdownObserved,
                TimeSpan recoveryExitTimeout)
        {
            if (guardian == null)
                throw new ArgumentNullException(
                    nameof(guardian));
            if (recoveryExitTimeout < TimeSpan.Zero)
                throw new ArgumentOutOfRangeException(
                    nameof(recoveryExitTimeout));
            if (guardian.HasExited)
                return false;

            bool forcedRecovery = false;
            if (!protocolShutdownObserved)
            {
                try
                {
                    guardian.CloseMainWindow();
                }
                catch
                {
                }
                try
                {
                    await WaitForExitAsync(
                        guardian,
                        recoveryExitTimeout,
                        CancellationToken.None)
                        .ConfigureAwait(false);
                }
                catch
                {
                }
            }
            if (!guardian.HasExited)
            {
                forcedRecovery = true;
                try
                {
                    guardian.Kill(
                        entireProcessTree: true);
                    await WaitForExitAsync(
                            guardian,
                            KillObservationTimeout,
                            CancellationToken.None)
                        .ConfigureAwait(false);
                }
                catch
                {
                }
                if (!guardian.HasExited)
                {
                    throw new TimeoutException(
                        "trusted_runner_exact_owned_guardian_kill_timeout");
                }
            }
            return forcedRecovery;
        }

        internal static void RequireCleanProtocolExit(
            Process guardian)
        {
            if (guardian == null)
                throw new ArgumentNullException(
                    nameof(guardian));
            if (!guardian.HasExited)
            {
                throw new InvalidOperationException(
                    "trusted_runner_protocol_shutdown_exit_pending");
            }
            if (guardian.ExitCode != 0)
            {
                throw new InvalidDataException(
                    "trusted_runner_protocol_shutdown_exit_code_invalid");
            }
        }

        private static async Task<bool> WaitForExitAsync(
            Process process,
            TimeSpan timeout,
            CancellationToken cancellationToken)
        {
            if (process.HasExited)
                return true;
            using var timeoutSource =
                CancellationTokenSource
                    .CreateLinkedTokenSource(
                        cancellationToken);
            timeoutSource.CancelAfter(timeout);
            try
            {
                await process.WaitForExitAsync(
                    timeoutSource.Token)
                    .ConfigureAwait(false);
                return true;
            }
            catch (OperationCanceledException)
                when (!cancellationToken
                    .IsCancellationRequested)
            {
                return process.HasExited;
            }
        }

        private static void WriteMinimalDiagnostic(
            Exception exception)
        {
            string reason = exception switch
            {
                InvalidDataException data =>
                    data.Message,
                TimeoutException timeout =>
                    timeout.Message,
                InvalidOperationException operation
                    when operation.Message.StartsWith(
                        "trusted_runner_",
                        StringComparison.Ordinal) =>
                    operation.Message,
                _ => "trusted_runner_failed"
            };
            try
            {
                Console.Error.WriteLine(
                    "cf7-trusted-runner: "
                        + reason);
            }
            catch
            {
            }
        }
    }
}
