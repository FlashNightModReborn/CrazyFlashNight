using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.AgentRuntime.TrustedRunner;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.TrustedRunner
{
    public sealed class
        TrustedOwnedRuntimeShutdownProtocolTests
    {
        private const string SessionId =
            "session_trusted_shutdown_AAA";
        private const string TargetId =
            "target_trusted_shutdown_AAAA";
        private const string LifecycleRef =
            "lifecycle_trusted_shutdown_A";
        private const string GrantId =
            "grant_trusted_shutdown_AAAAA";
        private const string ObservationId =
            "observation_trusted_shutdown_A";
        private const string FrameId =
            "frame_trusted_shutdown_AAAAA";
        private const string LeaseId =
            "lease_trusted_shutdown_AAAAA";
        private const string ClientId =
            "client_trusted_shutdown_AAAA";
        private const string PrincipalId =
            "principal_trusted_shutdown_A";

        [Fact]
        public async Task ShutdownUsesSupportedBoundActionAndTerminalReceipt()
        {
            string pipeName =
                "cf7-trusted-shutdown-test-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait = server
                .WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;

            var methods = new List<string>();
            Task serve = ServeAsync(
                server,
                methods);
            var credential =
                new TrustedUnattendedCredential(
                    "isolated_candidate",
                    "proof_trusted_shutdown_AAAA",
                    new[]
                    {
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        AgentCapabilitiesV1
                            .ObservationCapture,
                        AgentCapabilitiesV1
                            .LeaseAcquire,
                        AgentCapabilitiesV1
                            .SessionShutdown
                    },
                    new[] { TargetId },
                    SessionId,
                    "attempt_trusted_shutdown_AA",
                    7,
                    "receipt_trusted_shutdown_AA");
            await using TrustedUnattendedAgentClient client =
                TrustedUnattendedAgentClient
                    .CreateAuthenticatedForTest(
                        pipe,
                        credential,
                        LifecycleRef,
                        credential.AllowedCapabilities,
                        ClientId,
                        PrincipalId);

            ActionReceipt receipt =
                await client.ShutdownOwnedRuntimeAsync(
                    CancellationToken.None);
            await serve;

            Assert.Equal(
                new[]
                {
                    AgentMethodsV1
                        .ObservationGrantIssue,
                    AgentMethodsV1
                        .ObservationCapture,
                    AgentCapabilitiesV1
                        .LeaseAcquire,
                    AgentCapabilitiesV1
                        .SessionShutdown
                },
                methods);
            Assert.True(receipt.Terminal);
            Assert.Equal(
                ActionOutcome.InputDispatched,
                receipt.Outcome);
            Assert.Equal(
                EvidenceKind.BrokerDispatch,
                receipt.EvidenceKind);
            Assert.Equal(
                "shutdown_requested",
                receipt.ReasonCode);
            Assert.Equal(
                LeaseState.Consumed,
                receipt.LeaseState);
        }

        [Fact]
        public async Task ShutdownRetriesCaptureUnavailableAndReusesBindings()
        {
            (
                ActionReceipt receipt,
                Exception failure,
                IReadOnlyList<string> methods) =
                    await RunShutdownScenarioAsync(
                        "capture_retry_success",
                        CancellationToken.None);

            Assert.Null(failure);
            Assert.NotNull(receipt);
            Assert.Equal(
                new[]
                {
                    AgentMethodsV1
                        .ObservationGrantIssue,
                    AgentMethodsV1
                        .ObservationCapture,
                    AgentMethodsV1
                        .ObservationCapture,
                    AgentCapabilitiesV1
                        .LeaseAcquire,
                    AgentCapabilitiesV1
                        .SessionShutdown
                },
                methods);
        }

        [Fact]
        public async Task ShutdownRetriesLeaseInputNotQuiescentAndReusesBindings()
        {
            (
                ActionReceipt receipt,
                Exception failure,
                IReadOnlyList<string> methods) =
                    await RunShutdownScenarioAsync(
                        "lease_retry_success",
                        CancellationToken.None);

            Assert.Null(failure);
            Assert.NotNull(receipt);
            Assert.Equal(
                new[]
                {
                    AgentMethodsV1
                        .ObservationGrantIssue,
                    AgentMethodsV1
                        .ObservationCapture,
                    AgentCapabilitiesV1
                        .LeaseAcquire,
                    AgentCapabilitiesV1
                        .LeaseAcquire,
                    AgentCapabilitiesV1
                        .SessionShutdown
                },
                methods);
        }

        [Theory]
        [InlineData(
            "capture_nonretryable",
            "trusted_runner_shutdown_capture_failed",
            2)]
        [InlineData(
            "capture_wrong_retryable_reason",
            "trusted_runner_shutdown_capture_failed",
            2)]
        [InlineData(
            "lease_nonretryable",
            "trusted_runner_shutdown_call_failed:",
            3)]
        [InlineData(
            "lease_wrong_retryable_reason",
            "trusted_runner_shutdown_call_failed:",
            3)]
        public async Task ShutdownDoesNotRetryUnexpectedRpcErrors(
            string fault,
            string expectedMessage,
            int expectedMethodCount)
        {
            (
                ActionReceipt receipt,
                Exception failure,
                IReadOnlyList<string> methods) =
                    await RunShutdownScenarioAsync(
                        fault,
                        CancellationToken.None);

            Assert.Null(receipt);
            InvalidOperationException rejected =
                Assert.IsAssignableFrom<
                    InvalidOperationException>(
                        failure);
            Assert.StartsWith(
                expectedMessage,
                rejected.Message,
                StringComparison.Ordinal);
            Assert.Equal(
                expectedMethodCount,
                methods.Count);
        }

        [Theory]
        [InlineData(
            "capture_retry_exhausted",
            "trusted_runner_shutdown_capture_failed",
            5)]
        [InlineData(
            "lease_retry_exhausted",
            "trusted_runner_shutdown_call_failed:",
            6)]
        public async Task ShutdownFailsAfterStrictTransientRetriesAreExhausted(
            string fault,
            string expectedMessage,
            int expectedMethodCount)
        {
            (
                ActionReceipt receipt,
                Exception failure,
                IReadOnlyList<string> methods) =
                    await RunShutdownScenarioAsync(
                        fault,
                        CancellationToken.None);

            Assert.Null(receipt);
            InvalidOperationException rejected =
                Assert.IsAssignableFrom<
                    InvalidOperationException>(
                        failure);
            Assert.StartsWith(
                expectedMessage,
                rejected.Message,
                StringComparison.Ordinal);
            Assert.Equal(
                expectedMethodCount,
                methods.Count);
        }

        [Fact]
        public async Task ShutdownRetryDelayObservesCancellation()
        {
            var retryableErrorWritten =
                new TaskCompletionSource<bool>(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            using var cancellation =
                new CancellationTokenSource();
            Task<(
                ActionReceipt Receipt,
                Exception Failure,
                IReadOnlyList<string> Methods)> scenario =
                    RunShutdownScenarioAsync(
                        "capture_retry_cancel",
                        cancellation.Token,
                        retryableErrorWritten);

            await retryableErrorWritten.Task
                .WaitAsync(
                    TimeSpan.FromSeconds(5));
            cancellation.Cancel();
            (
                ActionReceipt receipt,
                Exception failure,
                IReadOnlyList<string> methods) =
                    await scenario;

            Assert.Null(receipt);
            Assert.IsAssignableFrom<
                OperationCanceledException>(
                    failure);
            Assert.Equal(
                new[]
                {
                    AgentMethodsV1
                        .ObservationGrantIssue,
                    AgentMethodsV1
                        .ObservationCapture
                },
                methods);
        }

        [Fact]
        public void CompletionEvidenceRecordsExactRuntimeAndReceiptWithoutSecrets()
        {
            string line =
                TrustedUnattendedRunner
                    .FormatCompletionEvidence(
                        "isolated_candidate",
                        Path.GetFullPath(
                            @"C:\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe"),
                        new string('A', 64),
                        new string('B', 64),
                        new string('C', 64),
                        4321,
                        new ActionReceipt
                        {
                            ActionId =
                                "action_trusted_shutdown_AAA",
                            AuditSequence = 9,
                            Terminal = true,
                            Outcome =
                                ActionOutcome.InputDispatched,
                            EvidenceKind =
                                EvidenceKind.BrokerDispatch,
                            ReasonCode =
                                "shutdown_requested",
                            ReconcileKind =
                                ReconcileKind.None,
                            Retryable = false,
                            ActualTargetId = TargetId,
                            FocusVerified = false,
                            BeforeObservationId =
                                ObservationId,
                            LeaseState = LeaseState.Consumed
                        });

            Assert.StartsWith(
                "cf7-trusted-runner-evidence: ",
                line,
                StringComparison.Ordinal);
            using JsonDocument evidence =
                JsonDocument.Parse(
                    line.Substring(
                        "cf7-trusted-runner-evidence: "
                            .Length));
            JsonElement root = evidence.RootElement;
            Assert.Equal(
                "cf7.agent_runtime.trusted_unattended_completion.v1",
                root.GetProperty("schema").GetString());
            Assert.Equal(
                "isolated_candidate",
                root.GetProperty("runtimeMode")
                    .GetString());
            Assert.Equal(
                4321,
                root.GetProperty("guardianProcessId")
                    .GetInt32());
            Assert.Equal(
                "shutdown_requested",
                root.GetProperty("terminalReceipt")
                    .GetProperty("reasonCode")
                    .GetString());
            Assert.DoesNotContain(
                "credential",
                line,
                StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain(
                "ticket",
                line,
                StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain(
                "nonce",
                line,
                StringComparison.OrdinalIgnoreCase);
        }

        [Theory]
        [InlineData("grant_receipt")]
        [InlineData("grant_foreign_target")]
        [InlineData("observation_source_layer")]
        [InlineData("lease_receipt")]
        [InlineData("receipt_evidence")]
        [InlineData("receipt_focus")]
        [InlineData("receipt_reconcile")]
        [InlineData("receipt_retryable")]
        public async Task ShutdownRejectsTamperedExactBindings(
            string fault)
        {
            string pipeName =
                "cf7-trusted-shutdown-negative-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait = server.WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;

            var methods = new List<string>();
            Task serve = ServeAsync(
                server,
                methods,
                fault);
            var credential =
                new TrustedUnattendedCredential(
                    "isolated_candidate",
                    "proof_trusted_shutdown_AAAA",
                    new[]
                    {
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        AgentCapabilitiesV1
                            .ObservationCapture,
                        AgentCapabilitiesV1
                            .LeaseAcquire,
                        AgentCapabilitiesV1
                            .SessionShutdown
                    },
                    new[] { TargetId },
                    SessionId,
                    "attempt_trusted_shutdown_AA",
                    7,
                    "receipt_trusted_shutdown_AA");
            await using TrustedUnattendedAgentClient client =
                TrustedUnattendedAgentClient
                    .CreateAuthenticatedForTest(
                        pipe,
                        credential,
                        LifecycleRef,
                        credential.AllowedCapabilities,
                        ClientId,
                        PrincipalId);

            Exception rejected =
                await Record.ExceptionAsync(
                    () => client.ShutdownOwnedRuntimeAsync(
                        CancellationToken.None));
            if (fault == "observation_source_layer")
            {
                Assert.IsType<InvalidOperationException>(
                    rejected);
                Assert.Equal(
                    "trusted_runner_shutdown_capture_failed",
                    rejected.Message);
            }
            else
            {
                Assert.IsType<InvalidDataException>(
                    rejected);
            }
            await serve;
        }

        private static async Task ServeAsync(
            NamedPipeServerStream stream,
            ICollection<string> methods,
            string fault = null,
            TaskCompletionSource<bool>
                retryableErrorWritten = null)
        {
            var codec = new AgentFrameCodec(
                AgentRendezvousStore.ProtocolMajor);
            int requestCount = fault switch
            {
                "grant_receipt" => 1,
                "grant_foreign_target" => 1,
                "observation_source_layer" => 2,
                "lease_receipt" => 3,
                "capture_retry_success" => 5,
                "capture_retry_exhausted" => 5,
                "capture_retry_cancel" => 2,
                "capture_nonretryable" => 2,
                "capture_wrong_retryable_reason" => 2,
                "lease_retry_success" => 5,
                "lease_retry_exhausted" => 6,
                "lease_nonretryable" => 3,
                "lease_wrong_retryable_reason" => 3,
                _ => 4
            };
            for (int ordinal = 0;
                ordinal < requestCount;
                ordinal++)
            {
                AgentFrame requestFrame =
                    await codec.ReadAsync(
                        stream,
                        CancellationToken.None);
                using JsonDocument request =
                    JsonDocument.Parse(
                        requestFrame.Payload);
                string id = request.RootElement
                    .GetProperty("id")
                    .GetString();
                string method = request.RootElement
                    .GetProperty("method")
                    .GetString();
                methods.Add(method);
                string errorReason =
                    RetryErrorReason(
                        fault,
                        method,
                        ordinal);
                object response;
                if (errorReason != null)
                {
                    _ = method switch
                    {
                        AgentMethodsV1
                            .ObservationCapture =>
                            Observation(
                                request.RootElement,
                                null),
                        AgentCapabilitiesV1
                            .LeaseAcquire =>
                            Lease(
                                request.RootElement,
                                null),
                        _ => throw new InvalidOperationException(
                            method)
                    };
                    response = new
                    {
                        jsonrpc = "2.0",
                        id,
                        error = RpcError(
                            errorReason,
                            ordinal + 1)
                    };
                }
                else
                {
                    object result = method switch
                    {
                        AgentMethodsV1
                            .ObservationGrantIssue =>
                            Grant(request.RootElement, fault),
                        AgentMethodsV1
                            .ObservationCapture =>
                            Observation(
                                request.RootElement,
                                fault),
                        AgentCapabilitiesV1
                            .LeaseAcquire =>
                            Lease(request.RootElement, fault),
                        AgentCapabilitiesV1
                            .SessionShutdown =>
                            Receipt(request.RootElement, fault),
                        _ => throw new InvalidOperationException(
                            method)
                    };
                    response = new
                    {
                        jsonrpc = "2.0",
                        id,
                        result
                    };
                }
                byte[] payload =
                    JsonSerializer.SerializeToUtf8Bytes(
                        response,
                        AgentProtocolV1.JsonOptions);
                await codec.WriteAsync(
                    stream,
                    new AgentFrame(
                        AgentRendezvousStore.ProtocolMajor,
                        AgentFrameKind.JsonRpc,
                        AgentFrameCodec.SupportedFlags,
                        payload),
                    CancellationToken.None);
                if (errorReason != null
                    && retryableErrorWritten != null)
                {
                    retryableErrorWritten
                        .TrySetResult(true);
                }
            }
        }

        private static string RetryErrorReason(
            string fault,
            string method,
            int ordinal)
        {
            if (string.Equals(
                    method,
                    AgentMethodsV1.ObservationCapture,
                    StringComparison.Ordinal))
            {
                return fault switch
                {
                    "capture_retry_success"
                        when ordinal == 1 =>
                            "capture_unavailable",
                    "capture_retry_exhausted" =>
                        "capture_unavailable",
                    "capture_retry_cancel" =>
                        "capture_unavailable",
                    "capture_nonretryable" =>
                        "unsupported_for_surface",
                    "capture_wrong_retryable_reason" =>
                        "input_not_quiescent",
                    _ => null
                };
            }
            if (string.Equals(
                    method,
                    AgentCapabilitiesV1.LeaseAcquire,
                    StringComparison.Ordinal))
            {
                return fault switch
                {
                    "lease_retry_success"
                        when ordinal == 2 =>
                            "input_not_quiescent",
                    "lease_retry_exhausted" =>
                        "input_not_quiescent",
                    "lease_nonretryable" =>
                        "unsupported_for_surface",
                    "lease_wrong_retryable_reason" =>
                        "capture_unavailable",
                    _ => null
                };
            }
            return null;
        }

        private static object RpcError(
            string reasonCode,
            int serverSequence)
        {
            bool retryable =
                reasonCode == "capture_unavailable"
                || reasonCode == "input_not_quiescent";
            return new
            {
                code = -32000,
                message = reasonCode,
                data = new
                {
                    reasonCode,
                    retryable,
                    reconcileKind = "none",
                    serverSequence
                }
            };
        }

        private static async Task<(
            ActionReceipt Receipt,
            Exception Failure,
            IReadOnlyList<string> Methods)>
            RunShutdownScenarioAsync(
                string fault,
                CancellationToken cancellationToken,
                TaskCompletionSource<bool>
                    retryableErrorWritten = null)
        {
            string pipeName =
                "cf7-trusted-shutdown-retry-"
                + Guid.NewGuid().ToString("N");
            await using var server =
                new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
            await using var pipe =
                new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous);
            Task wait =
                server.WaitForConnectionAsync();
            await pipe.ConnectAsync(5_000);
            await wait;

            var methods = new List<string>();
            Task serve =
                ServeAsync(
                    server,
                    methods,
                    fault,
                    retryableErrorWritten);
            var credential =
                new TrustedUnattendedCredential(
                    "isolated_candidate",
                    "proof_trusted_shutdown_AAAA",
                    new[]
                    {
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        AgentCapabilitiesV1
                            .ObservationCapture,
                        AgentCapabilitiesV1
                            .LeaseAcquire,
                        AgentCapabilitiesV1
                            .SessionShutdown
                    },
                    new[] { TargetId },
                    SessionId,
                    "attempt_trusted_shutdown_AA",
                    7,
                    "receipt_trusted_shutdown_AA");
            await using TrustedUnattendedAgentClient client =
                TrustedUnattendedAgentClient
                    .CreateAuthenticatedForTest(
                        pipe,
                        credential,
                        LifecycleRef,
                        credential.AllowedCapabilities,
                        ClientId,
                        PrincipalId);

            ActionReceipt receipt = null;
            Exception failure =
                await Record.ExceptionAsync(
                    async () =>
                    {
                        receipt =
                            await client
                                .ShutdownOwnedRuntimeAsync(
                                    cancellationToken);
                    });
            await serve;
            return (receipt, failure, methods);
        }

        private static object Grant(
            JsonElement request,
            string fault)
        {
            JsonElement grant =
                request.GetProperty("params");
            Assert.Equal(
                new[] { AgentSurfaceKindsV1.Launcher },
                grant.GetProperty("targetKinds")
                    .EnumerateArray()
                    .Select(value => value.GetString())
                    .ToArray());
            Assert.False(
                grant.TryGetProperty(
                    "targetIds",
                    out _));
            return new
            {
                observationGrantId = GrantId,
                ownerClientId = ClientId,
                securityPrincipalId = PrincipalId,
                sessionScope = new
                {
                    sessionId = SessionId,
                    lifecycleGeneration = 3,
                    attemptId =
                        "attempt_trusted_shutdown_AA",
                    attemptGeneration = 7,
                    crossAttempt = false
                },
                targetScope = new[]
                {
                    fault == "grant_foreign_target"
                        ? "target_trusted_foreign_AAAA"
                        : TargetId
                },
                dataScope = new[] { "pixels" },
                issuedMonotonic = 100UL,
                expiresMonotonic = 60_000UL,
                consentReceipt =
                    fault == "grant_receipt"
                        ? "receipt_trusted_tampered_AA"
                        : "receipt_trusted_shutdown_AA",
                allowEphemeralKeyframes = false,
                allowPersistence = false,
                allowExport = false,
                state = "active"
            };
        }

        private static object Observation(
            JsonElement request,
            string fault)
        {
            JsonElement capture =
                request.GetProperty("params");
            Assert.Equal(
                GrantId,
                capture.GetProperty(
                        "observationGrantId")
                    .GetString());
            Assert.Equal(
                SessionId,
                capture.GetProperty("sessionId")
                    .GetString());
            Assert.Equal(
                TargetId,
                capture.GetProperty("targetId")
                    .GetString());
            Assert.Equal(
                "pixels",
                capture.GetProperty("dataScope")
                    .GetString());
            Assert.False(
                capture
                    .GetProperty(
                        "allowValidatedFlashKeyframeFallback")
                    .GetBoolean());
            return new
            {
                observationId = ObservationId,
                observationGrantId = GrantId,
                sessionId = SessionId,
                lifecycleGeneration = 3,
                capturedUtc =
                    "2026-07-30T08:00:05Z",
                capturedAtMonotonic = 200UL,
                attemptId =
                    "attempt_trusted_shutdown_AA",
                attemptGeneration = 7,
                panelInstanceId =
                    "panel_trusted_shutdown_AAAA",
                targetId = TargetId,
                surfaceEpoch = 11,
                coordinateSpaceVersion = 12,
                focusEpoch = 13,
                modalEpoch = 14,
                visible = true,
                minimized = false,
                active = true,
                blockingModalKind = "none",
                frames = new[]
                {
                    new
                    {
                        frameId = FrameId,
                        observationId = ObservationId,
                        targetId = TargetId,
                        surfaceEpoch = 11,
                        sourceLayer =
                            fault
                                == "observation_source_layer"
                                ? "flash"
                                : "launcher",
                        zIndex = 1,
                        capturedAtMonotonic = 200UL,
                        coordinateSpaceId =
                            "coords_trusted_shutdown_AAA",
                        coordinateSpaceVersion = 12,
                        captureRectPhysical = new
                        {
                            x = 0,
                            y = 0,
                            width = 1280,
                            height = 720
                        },
                        clientRectPhysical = new
                        {
                            x = 0,
                            y = 0,
                            width = 1280,
                            height = 720
                        },
                        contentRectPhysical = new
                        {
                            x = 0,
                            y = 0,
                            width = 1280,
                            height = 720
                        },
                        frameToTargetContentTransform =
                            new
                            {
                                m11 = 1,
                                m12 = 0,
                                m21 = 0,
                                m22 = 1,
                                dx = 0,
                                dy = 0
                            },
                        width = 1280,
                        height = 720,
                        dpi = 96,
                        pixelFormat =
                            "bgra8_premultiplied",
                        contentHash =
                            new string('A', 64),
                        opaqueContentHandle =
                            "content_trusted_shutdown_A"
                    }
                }
            };
        }

        private static object Lease(
            JsonElement request,
            string fault)
        {
            JsonElement lease =
                request.GetProperty("params");
            Assert.Equal(
                SessionId,
                lease.GetProperty("sessionId")
                    .GetString());
            Assert.Equal(
                "shutdown",
                lease.GetProperty("kind")
                    .GetString());
            Assert.Equal(
                new[]
                {
                    AgentCapabilitiesV1
                        .SessionShutdown
                },
                lease.GetProperty("capabilities")
                    .EnumerateArray()
                    .Select(value =>
                        value.GetString())
                    .ToArray());
            Assert.Equal(
                new[] { TargetId },
                lease.GetProperty("targetScope")
                    .EnumerateArray()
                    .Select(value =>
                        value.GetString())
                    .ToArray());
            Assert.InRange(
                lease.GetProperty("requestedTtlMs")
                    .GetInt32(),
                1,
                30_000);
            Assert.Equal(
                1,
                lease.GetProperty(
                        "requestedActionLimit")
                    .GetInt32());
            Assert.False(
                lease.TryGetProperty(
                    "operation",
                    out _));
            return new
            {
                leaseId = LeaseId,
                ownerClientId = ClientId,
                securityPrincipalId = PrincipalId,
                sessionMode = "unattended_test",
                purpose = "shutdown",
                scope = new
                {
                    session = new
                    {
                        sessionId = SessionId,
                        lifecycleGeneration = 3,
                        attemptId =
                            "attempt_trusted_shutdown_AA",
                        attemptGeneration = 7,
                        crossAttempt = false
                    },
                    targetScope =
                        new[] { TargetId },
                    operationScope =
                        new[]
                        {
                            AgentCapabilitiesV1
                                .SessionShutdown
                        },
                    maximumActions = 1
                },
                capabilities = new[]
                {
                    AgentCapabilitiesV1
                        .SessionShutdown
                },
                issuedMonotonic = 200UL,
                expiresMonotonic = 30_000UL,
                consentReceipt =
                    fault == "lease_receipt"
                        ? "receipt_trusted_tampered_AA"
                        : "receipt_trusted_shutdown_AA",
                humanOverridePolicy =
                    "always_preempt",
                state = "active"
            };
        }

        private static object Receipt(
            JsonElement request,
            string fault)
        {
            JsonElement action =
                request.GetProperty("params");
            Assert.Equal(
                SessionId,
                action.GetProperty("sessionId")
                    .GetString());
            Assert.Equal(
                GrantId,
                action.GetProperty(
                        "observationGrantId")
                    .GetString());
            Assert.Equal(
                LeaseId,
                action.GetProperty("leaseId")
                    .GetString());
            Assert.Equal(
                ObservationId,
                action.GetProperty("observationId")
                    .GetString());
            Assert.Equal(
                FrameId,
                action.GetProperty("frameId")
                    .GetString());
            Assert.Equal(
                TargetId,
                action.GetProperty("targetId")
                    .GetString());
            Assert.Empty(
                action.GetProperty("arguments")
                    .EnumerateObject());
            return new
            {
                actionId =
                    action.GetProperty("actionId")
                        .GetString(),
                auditSequence = 1,
                terminal = true,
                outcome = "input_dispatched",
                evidenceKind =
                    fault == "receipt_evidence"
                        ? "none"
                        : "broker_dispatch",
                reasonCode =
                    "shutdown_requested",
                reconcileKind =
                    fault == "receipt_reconcile"
                        ? "manual_required"
                        : "none",
                retryable =
                    fault == "receipt_retryable",
                actualTargetId = TargetId,
                focusVerified =
                    fault == "receipt_focus",
                beforeObservationId =
                    ObservationId,
                leaseState = "consumed"
            };
        }
    }
}
