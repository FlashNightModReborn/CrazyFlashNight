using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.TrustedRunner
{
    internal sealed class TrustedUnattendedAgentClient
        : IAsyncDisposable
    {
        private const string PipePrefix =
            "CF7FlashNight.AgentRuntime.v1.";
        private static readonly UTF8Encoding StrictUtf8 =
            new UTF8Encoding(false, true);
        private readonly Stream _pipe;
        private readonly AgentFrameCodec _codec =
            new AgentFrameCodec(
                AgentRendezvousStore.ProtocolMajor);
        private readonly HashSet<string>
            _grantedCapabilities;
        private string _lifecycleRef;
        private TrustedUnattendedCredential
            _credential;
        private string _clientInstanceId;
        private string _securityPrincipalId;
        private bool _disposed;

        private TrustedUnattendedAgentClient(
            Stream pipe,
            IEnumerable<string> grantedCapabilities,
            string clientInstanceId = null,
            string securityPrincipalId = null)
        {
            _pipe = pipe;
            _grantedCapabilities =
                new HashSet<string>(
                    grantedCapabilities,
                    StringComparer.Ordinal);
            _clientInstanceId = clientInstanceId;
            _securityPrincipalId = securityPrincipalId;
        }

        public IReadOnlySet<string> GrantedCapabilities =>
            _grantedCapabilities;

        internal static TrustedUnattendedAgentClient
            CreateAuthenticatedForTest(
                Stream stream,
                TrustedUnattendedCredential credential,
                string lifecycleRef,
                IEnumerable<string> grantedCapabilities,
                string clientInstanceId = null,
                string securityPrincipalId = null)
        {
            var client =
                new TrustedUnattendedAgentClient(
                    stream,
                    grantedCapabilities,
                    clientInstanceId,
                    securityPrincipalId);
            client._credential = credential;
            client._lifecycleRef = lifecycleRef;
            return client;
        }

        public static async Task<
            TrustedUnattendedAgentClient> ConnectAsync(
                string projectRoot,
                Process guardian,
                string clientInstanceId,
                TrustedUnattendedCredential credential,
                TrustedUnattendedAdapter adapter,
                CancellationToken cancellationToken)
        {
            if (guardian == null)
                throw new ArgumentNullException(
                    nameof(guardian));
            if (credential == null)
                throw new ArgumentNullException(
                    nameof(credential));

            AgentRendezvousDocument rendezvous =
                await ReadOwnedRendezvousAsync(
                    projectRoot,
                    guardian,
                    credential.RuntimeMode,
                    cancellationToken)
                    .ConfigureAwait(false);
            var pipe = new NamedPipeClientStream(
                ".",
                PipePrefix + rendezvous.PipeId,
                PipeDirection.InOut,
                PipeOptions.Asynchronous);
            try
            {
                await pipe.ConnectAsync(
                    30_000,
                    cancellationToken)
                    .ConfigureAwait(false);
                var client =
                    new TrustedUnattendedAgentClient(
                        pipe,
                        Array.Empty<string>(),
                        clientInstanceId);
                try
                {
                    IReadOnlyCollection<string>
                        granted =
                            await client.AuthenticateAsync(
                                rendezvous,
                                clientInstanceId,
                                credential,
                                adapter,
                                cancellationToken)
                                .ConfigureAwait(false);
                    client._grantedCapabilities
                        .UnionWith(granted);
                    client._credential =
                        credential;
                    credential.ClearCredentialProof();
                    return client;
                }
                catch
                {
                    await client.DisposeAsync()
                        .ConfigureAwait(false);
                    throw;
                }
            }
            catch
            {
                pipe.Dispose();
                throw;
            }
        }

        public async Task<TrustedAgentCallResult>
            CallAsync(
                JsonElement request,
                CancellationToken cancellationToken)
        {
            ThrowIfDisposed();
            IReadOnlyList<ContractViolation>
                violations =
                    AgentJsonRpcValidator
                        .ValidateRequest(request);
            if (violations.Count != 0)
            {
                throw new InvalidDataException(
                    "trusted_runner_request_invalid:"
                        + violations[0].Code);
            }
            string method =
                request.GetProperty("method")
                    .GetString();
            if (string.Equals(
                    method,
                    AgentMethodsV1.RuntimeHello,
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "trusted_runner_hello_reserved");
            }
            AgentMethodsV1.TryGet(
                method,
                out AgentMethodDefinition definition);
            if (definition == null
                || !_grantedCapabilities.Contains(
                    definition.RequiredCapability))
            {
                throw new InvalidDataException(
                    "trusted_runner_capability_not_granted");
            }

            byte[] payload =
                StrictUtf8.GetBytes(
                    request.GetRawText());
            try
            {
                await _codec.WriteAsync(
                    _pipe,
                    new AgentFrame(
                        AgentRendezvousStore.ProtocolMajor,
                        AgentFrameKind.JsonRpc,
                        AgentFrameCodec.SupportedFlags,
                        payload),
                    cancellationToken)
                    .ConfigureAwait(false);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(
                    payload);
            }

            AgentFrame responseFrame =
                await _codec.ReadAsync(
                    _pipe,
                    cancellationToken)
                    .ConfigureAwait(false);
            if (responseFrame == null
                || responseFrame.Kind
                    != AgentFrameKind.JsonRpc)
            {
                throw new InvalidDataException(
                    "trusted_runner_response_missing");
            }
            JsonDocument response =
                JsonDocument.Parse(
                    responseFrame.Payload);
            try
            {
                IReadOnlyList<ContractViolation>
                    responseViolations =
                        AgentJsonRpcValidator
                            .ValidateResponse(
                                response.RootElement);
                if (responseViolations.Count != 0
                    || !string.Equals(
                        response.RootElement
                            .GetProperty("id")
                            .GetString(),
                        request.GetProperty("id")
                            .GetString(),
                        StringComparison.Ordinal))
                {
                    throw new InvalidDataException(
                        "trusted_runner_response_invalid");
                }

                DecodedBinaryChunk binary = null;
                if (string.Equals(
                        method,
                        AgentMethodsV1.ContentRead,
                        StringComparison.Ordinal)
                    && response.RootElement
                        .TryGetProperty("result", out _))
                {
                    AgentFrame binaryFrame =
                        await _codec.ReadAsync(
                            _pipe,
                            cancellationToken)
                            .ConfigureAwait(false);
                    if (binaryFrame == null
                        || binaryFrame.Kind
                            != AgentFrameKind.BinaryChunk)
                    {
                        throw new InvalidDataException(
                            "trusted_runner_binary_missing");
                    }
                    binary = BinaryChunkCodecV1.Decode(
                        binaryFrame.Payload.Span);
                }
                return new TrustedAgentCallResult(
                    response.RootElement.Clone(),
                    binary);
            }
            finally
            {
                response.Dispose();
            }
        }

        public async Task<ActionReceipt>
            ShutdownOwnedRuntimeAsync(
            CancellationToken cancellationToken)
        {
            ThrowIfDisposed();
            if (_credential == null
                || string.IsNullOrWhiteSpace(
                    _lifecycleRef))
            {
                throw new InvalidOperationException(
                    "trusted_runner_shutdown_binding_missing");
            }

            JsonElement grantResult =
                await CallForResultAsync(
                    AgentMethodsV1
                        .ObservationGrantIssue,
                    new
                    {
                        lifecycleRef =
                            _lifecycleRef,
                        targetKinds = new[]
                        {
                            AgentSurfaceKindsV1.Launcher
                        },
                        dataScopes = new[]
                        {
                            ObservationDataScopesV1
                                .Pixels
                        },
                        requestedTtlMs = 60_000,
                        allowEphemeralKeyframes =
                            false,
                        allowPersistence = false,
                        allowExport = false,
                        consentReceipt =
                            _credential.IssuerReceipt
                    },
                    cancellationToken)
                    .ConfigureAwait(false);
            ObservationGrantDescriptor grant =
                HasRequiredProperties(
                    grantResult,
                    "observationGrantId",
                    "ownerClientId",
                    "securityPrincipalId",
                    "sessionScope",
                    "targetScope",
                    "dataScope",
                    "issuedMonotonic",
                    "expiresMonotonic",
                    "consentReceipt",
                    "allowEphemeralKeyframes",
                    "allowPersistence",
                    "allowExport",
                    "state")
                ?
                grantResult.Deserialize<
                    ObservationGrantDescriptor>(
                        AgentProtocolV1.JsonOptions)
                : null;
            IReadOnlyList<ContractViolation>
                grantViolations =
                    AgentContractValidator.Validate(grant);
            if (grant == null
                || grantViolations.Count != 0
                || !string.Equals(
                    grant.OwnerClientId,
                    _clientInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    grant.SecurityPrincipalId,
                    _securityPrincipalId,
                    StringComparison.Ordinal)
                || grant.State
                    != Contracts.ObservationGrantState.Active
                || grant.AllowEphemeralKeyframes
                || grant.AllowPersistence
                || grant.AllowExport
                || grant.DataScope == null
                || grant.DataScope.Count != 1
                || !string.Equals(
                    grant.DataScope[0],
                    ObservationDataScopesV1.Pixels,
                    StringComparison.Ordinal)
                || grant.TargetScope == null
                || grant.TargetScope.Count != 1
                || !_credential.AllowedTargets.Contains(
                    grant.TargetScope[0],
                    StringComparer.Ordinal)
                || !FixedTimeEqualsProtocolValue(
                    _credential.IssuerReceipt,
                    grant.ConsentReceipt)
                || grant.SessionScope == null
                || !string.Equals(
                    grant.SessionScope.SessionId,
                    _credential.SessionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    grant.SessionScope.AttemptId,
                    _credential.AttemptId,
                    StringComparison.Ordinal)
                || grant.SessionScope.AttemptGeneration
                    != _credential.AttemptGeneration
                || grant.SessionScope.CrossAttempt)
            {
                throw new InvalidDataException(
                    "trusted_runner_shutdown_grant_invalid");
            }

            string targetId = null;
            ObservationEnvelope observation = null;
            Exception lastCapture = null;
            foreach (string candidate
                in grant.TargetScope)
            {
                try
                {
                    JsonElement observationResult =
                        await CallForResultAsync(
                            AgentMethodsV1
                                .ObservationCapture,
                            new
                            {
                                observationGrantId =
                                    grant
                                        .ObservationGrantId,
                                sessionId =
                                    _credential
                                        .SessionId,
                                targetId = candidate,
                                dataScope =
                                    ObservationDataScopesV1
                                        .Pixels,
                                allowValidatedFlashKeyframeFallback =
                                    false
                            },
                            cancellationToken)
                            .ConfigureAwait(false);
                    if (!HasRequiredProperties(
                            observationResult,
                            "observationId",
                            "observationGrantId",
                            "sessionId",
                            "lifecycleGeneration",
                            "capturedUtc",
                            "capturedAtMonotonic",
                            "attemptId",
                            "attemptGeneration",
                            "targetId",
                            "surfaceEpoch",
                            "coordinateSpaceVersion",
                            "focusEpoch",
                            "modalEpoch",
                            "visible",
                            "minimized",
                            "active",
                            "blockingModalKind",
                            "frames"))
                    {
                        throw new InvalidDataException(
                            "trusted_runner_shutdown_observation_invalid");
                    }
                    ObservationEnvelope candidateObservation =
                        observationResult.Deserialize<
                            ObservationEnvelope>(
                                AgentProtocolV1
                                    .JsonOptions);
                    IReadOnlyList<ContractViolation>
                        observationViolations =
                            AgentContractValidator.Validate(
                                candidateObservation);
                    if (candidateObservation != null
                        && observationViolations.Count == 0
                        && string.Equals(
                            candidateObservation
                                .ObservationGrantId,
                            grant.ObservationGrantId,
                            StringComparison.Ordinal)
                        && candidateObservation
                                .LifecycleGeneration
                            == grant.SessionScope
                                .LifecycleGeneration
                        && string.Equals(
                            candidateObservation.AttemptId,
                            _credential.AttemptId,
                            StringComparison.Ordinal)
                        && candidateObservation
                                .AttemptGeneration
                            == _credential
                                .AttemptGeneration
                        && candidateObservation.Frames != null
                        && candidateObservation.Frames.Any(
                            frame =>
                                string.Equals(
                                    frame.TargetId,
                                    candidate,
                                    StringComparison
                                        .Ordinal)
                                && !string
                                    .IsNullOrWhiteSpace(
                                        frame.FrameId)
                                && !string
                                    .IsNullOrWhiteSpace(
                                        frame.ContentHash)
                                && frame.SourceLayer
                                    == SourceLayer.Launcher))
                    {
                        targetId = candidate;
                        observation =
                            candidateObservation;
                        break;
                    }
                }
                catch (Exception exception)
                    when (exception
                        is InvalidOperationException
                        || exception
                            is InvalidDataException)
                {
                    lastCapture = exception;
                }
            }
            if (observation == null
                || targetId == null)
            {
                throw new InvalidOperationException(
                    "trusted_runner_shutdown_capture_failed",
                    lastCapture);
            }
            if (!string.Equals(
                    observation.SessionId,
                    _credential.SessionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    observation.TargetId,
                    targetId,
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "trusted_runner_shutdown_observation_invalid");
            }

            JsonElement leaseResult =
                await CallForResultAsync(
                    AgentCapabilitiesV1
                        .LeaseAcquire,
                    new
                    {
                        sessionId =
                            _credential.SessionId,
                        kind = "shutdown",
                        capabilities = new[]
                        {
                            AgentCapabilitiesV1
                                .SessionShutdown
                        },
                        targetScope =
                            new[] { targetId },
                        requestedTtlMs = 30_000,
                        requestedActionLimit = 1,
                        consentReceipt =
                            _credential.IssuerReceipt
                    },
                    cancellationToken)
                    .ConfigureAwait(false);
            LeaseDescriptor lease =
                HasRequiredProperties(
                    leaseResult,
                    "leaseId",
                    "ownerClientId",
                    "securityPrincipalId",
                    "sessionMode",
                    "purpose",
                    "scope",
                    "capabilities",
                    "issuedMonotonic",
                    "expiresMonotonic",
                    "consentReceipt",
                    "humanOverridePolicy",
                    "state")
                ?
                leaseResult.Deserialize<LeaseDescriptor>(
                    AgentProtocolV1.JsonOptions)
                : null;
            IReadOnlyList<ContractViolation>
                leaseViolations =
                    AgentContractValidator.Validate(lease);
            if (lease == null
                || leaseViolations.Count != 0
                || !string.Equals(
                    lease.OwnerClientId,
                    _clientInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    lease.SecurityPrincipalId,
                    _securityPrincipalId,
                    StringComparison.Ordinal)
                || lease.State != LeaseState.Active
                || lease.SessionMode
                    != SessionMode.UnattendedTest
                || lease.Purpose
                    != LeasePurpose.Shutdown
                || lease.RenewAfter.HasValue
                || !FixedTimeEqualsProtocolValue(
                    _credential.IssuerReceipt,
                    lease.ConsentReceipt)
                || lease.Capabilities == null
                || lease.Capabilities.Count != 1
                || !string.Equals(
                    lease.Capabilities[0],
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    StringComparison.Ordinal)
                || lease.Scope == null
                || lease.Scope.Session == null
                || !string.Equals(
                    lease.Scope.Session.SessionId,
                    _credential.SessionId,
                    StringComparison.Ordinal)
                || lease.Scope.Session
                    .LifecycleGeneration
                    != observation
                        .LifecycleGeneration
                || !string.Equals(
                    lease.Scope.Session.AttemptId,
                    _credential.AttemptId,
                    StringComparison.Ordinal)
                || lease.Scope.Session
                    .AttemptGeneration
                    != _credential.AttemptGeneration
                || lease.Scope.Session.CrossAttempt
                || lease.Scope.MaximumActions != 1
                || lease.Scope.TargetScope == null
                || lease.Scope.TargetScope.Count != 1
                || !string.Equals(
                    lease.Scope.TargetScope[0],
                    targetId,
                    StringComparison.Ordinal)
                || lease.Scope.OperationScope == null
                || lease.Scope.OperationScope.Count != 1
                || !string.Equals(
                    lease.Scope.OperationScope[0],
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "trusted_runner_shutdown_lease_invalid");
            }

            var action = new ActionEnvelope
            {
                ActionId =
                    AgentRendezvousStore
                        .GenerateOpaqueId(),
                IdempotencyKey =
                    AgentRendezvousStore
                        .GenerateOpaqueId(),
                DeadlineMs = 10_000,
                SessionId =
                    _credential.SessionId,
                ObservationGrantId =
                    grant.ObservationGrantId,
                LeaseId = lease.LeaseId,
                ObservationId =
                    observation.ObservationId,
                ExpectedLifecycleGeneration =
                    observation
                        .LifecycleGeneration,
                TargetId = targetId,
                ExpectedSurfaceEpoch =
                    observation.SurfaceEpoch,
                ExpectedAttemptId =
                    _credential.AttemptId,
                ExpectedAttemptGeneration =
                    _credential.AttemptGeneration,
                ExpectedPanelInstanceId =
                    observation.PanelInstanceId,
                ExpectedSemanticGeneration =
                    observation.SemanticGeneration,
                ExpectedDocumentGeneration =
                    observation.DocumentGeneration,
                ExpectedCoordinateSpaceVersion =
                    observation
                        .CoordinateSpaceVersion,
                ExpectedFocusEpoch =
                    observation.FocusEpoch,
                ExpectedModalEpoch =
                    observation.ModalEpoch,
                FrameId =
                    observation.Frames
                        .First(
                            frame =>
                                string.Equals(
                                    frame.TargetId,
                                    targetId,
                                    StringComparison
                                        .Ordinal)
                                && !string
                                    .IsNullOrWhiteSpace(
                                        frame.FrameId))
                        .FrameId,
                Operation =
                    AgentCapabilitiesV1
                        .SessionShutdown,
                Arguments =
                    JsonSerializer
                        .SerializeToElement(
                            new { },
                            AgentProtocolV1
                                .JsonOptions),
                Reason =
                    "trusted runner owned runtime shutdown"
            };
            JsonElement receiptResult =
                await CallForResultAsync(
                    AgentCapabilitiesV1
                        .SessionShutdown,
                    action,
                    cancellationToken)
                    .ConfigureAwait(false);
            ActionReceipt receipt =
                HasRequiredProperties(
                    receiptResult,
                    "actionId",
                    "auditSequence",
                    "terminal",
                    "outcome",
                    "evidenceKind",
                    "reasonCode",
                    "reconcileKind",
                    "retryable",
                    "actualTargetId",
                    "focusVerified",
                    "beforeObservationId",
                    "leaseState")
                ?
                receiptResult.Deserialize<ActionReceipt>(
                    AgentProtocolV1.JsonOptions)
                : null;
            IReadOnlyList<ContractViolation>
                receiptViolations =
                    AgentContractValidator.Validate(receipt);
            if (receipt == null
                || receiptViolations.Count != 0
                || !receipt.Terminal
                || !string.Equals(
                    receipt.ActionId,
                    action.ActionId,
                    StringComparison.Ordinal)
                || receipt.Outcome
                    != ActionOutcome.InputDispatched
                || receipt.EvidenceKind
                    != EvidenceKind.BrokerDispatch
                || !string.Equals(
                    receipt.ReasonCode,
                    "shutdown_requested",
                    StringComparison.Ordinal)
                || receipt.ReconcileKind
                    != ReconcileKind.None
                || receipt.Retryable
                || !string.Equals(
                    receipt.ActualTargetId,
                    targetId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    receipt.BeforeObservationId,
                    observation.ObservationId,
                    StringComparison.Ordinal)
                || receipt.FocusVerified
                || receipt.LeaseState
                    != LeaseState.Consumed)
            {
                throw new InvalidDataException(
                    "trusted_runner_shutdown_receipt_invalid");
            }
            return receipt;
        }

        private async Task<JsonElement>
            CallForResultAsync(
                string method,
                object parameters,
                CancellationToken cancellationToken)
        {
            JsonElement request =
                JsonSerializer.SerializeToElement(
                    new AgentJsonRpcRequest
                    {
                        Id =
                            AgentRendezvousStore
                                .GenerateOpaqueId(),
                        Method = method,
                        Params =
                            JsonSerializer
                                .SerializeToElement(
                                    parameters,
                                    AgentProtocolV1
                                        .JsonOptions)
                    },
                    AgentProtocolV1.JsonOptions);
            TrustedAgentCallResult call =
                await CallAsync(
                    request,
                    cancellationToken)
                    .ConfigureAwait(false);
            if (!call.Response.TryGetProperty(
                    "result",
                    out JsonElement result))
            {
                string reason =
                    call.Response
                        .TryGetProperty(
                            "error",
                            out JsonElement error)
                        ? error.GetRawText()
                        : "response_missing_result";
                throw new InvalidOperationException(
                    "trusted_runner_shutdown_call_failed:"
                        + reason);
            }
            return result.Clone();
        }

        private async Task<IReadOnlyCollection<string>>
            AuthenticateAsync(
                AgentRendezvousDocument rendezvous,
                string clientInstanceId,
                TrustedUnattendedCredential credential,
                TrustedUnattendedAdapter adapter,
                CancellationToken cancellationToken)
        {
            string id =
                AgentRendezvousStore
                    .GenerateOpaqueId();
            var hello = new HelloMessage
            {
                ClientInstanceId = clientInstanceId,
                // JSONL/MCP describe only the runner's stdio adapter.
                // Host admission remains the one-shot trusted unattended
                // principal class; developer JSONL/MCP enrollment must never
                // consume this Host-issued proof.
                ClientKind = ClientKind.TestHarness,
                RequestedCapabilities =
                    credential.AllowedCapabilities
                        .Where(
                            capability =>
                                AgentCapabilitiesV1.All
                                    .Contains(
                                        capability))
                        .Distinct(
                            StringComparer.Ordinal)
                        .ToList(),
                Nonce =
                    AgentRendezvousStore
                        .GenerateOpaqueId(),
                ConnectionToken =
                    rendezvous.ConnectionTicket,
                CredentialProof =
                    credential.CredentialProof
            };
            if (hello.RequestedCapabilities.Count == 0)
            {
                throw new InvalidDataException(
                    "trusted_runner_capability_scope_empty");
            }
            JsonElement request =
                JsonSerializer.SerializeToElement(
                    new AgentJsonRpcRequest
                    {
                        Id = id,
                        Method =
                            AgentMethodsV1.RuntimeHello,
                        Params =
                            JsonSerializer
                                .SerializeToElement(
                                    hello,
                                    AgentProtocolV1
                                        .JsonOptions)
                    },
                    AgentProtocolV1.JsonOptions);
            IReadOnlyList<ContractViolation>
                violations =
                    AgentJsonRpcValidator
                        .ValidateRequest(request);
            if (violations.Count != 0)
            {
                throw new InvalidDataException(
                    "trusted_runner_hello_invalid");
            }
            byte[] payload =
                JsonSerializer.SerializeToUtf8Bytes(
                    request,
                    AgentProtocolV1.JsonOptions);
            try
            {
                await _codec.WriteAsync(
                    _pipe,
                    new AgentFrame(
                        AgentRendezvousStore.ProtocolMajor,
                        AgentFrameKind.JsonRpc,
                        AgentFrameCodec.SupportedFlags,
                        payload),
                    cancellationToken)
                    .ConfigureAwait(false);
            }
            finally
            {
                hello.CredentialProof = null;
                CryptographicOperations.ZeroMemory(
                    payload);
            }

            AgentFrame frame =
                await _codec.ReadAsync(
                    _pipe,
                    cancellationToken)
                    .ConfigureAwait(false);
            if (frame == null
                || frame.Kind != AgentFrameKind.JsonRpc)
            {
                throw new InvalidDataException(
                    "trusted_runner_welcome_missing");
            }
            using JsonDocument response =
                JsonDocument.Parse(frame.Payload);
            IReadOnlyList<ContractViolation>
                responseErrors =
                    AgentJsonRpcValidator
                        .ValidateResponse(
                            response.RootElement);
            if (responseErrors.Count != 0
                || !response.RootElement
                    .TryGetProperty(
                        "result",
                        out JsonElement result)
                || !string.Equals(
                    response.RootElement
                        .GetProperty("id")
                        .GetString(),
                    id,
                    StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    "trusted_runner_authentication_failed");
            }
            WelcomeMessage welcome =
                result.Deserialize<WelcomeMessage>(
                    AgentProtocolV1.JsonOptions)
                ?? throw new InvalidDataException(
                    "trusted_runner_welcome_invalid");
            if (!string.Equals(
                    welcome.ProtocolVersion,
                    AgentProtocolV1.Version,
                    StringComparison.Ordinal)
                || welcome.GrantedCapabilities == null
                || welcome.GrantedCapabilities
                    .Distinct(StringComparer.Ordinal)
                    .Count()
                    != welcome.GrantedCapabilities.Count
                || welcome.GrantedCapabilities.Any(
                    capability =>
                        !hello.RequestedCapabilities
                            .Contains(
                                capability,
                                StringComparer.Ordinal)))
            {
                throw new InvalidDataException(
                    "trusted_runner_welcome_invalid");
            }
            _lifecycleRef =
                welcome.MinimalSessionRef
                    ?.LifecycleRef;
            _securityPrincipalId =
                welcome.SecurityPrincipalId;
            return welcome.GrantedCapabilities;
        }

        private static bool HasRequiredProperties(
            JsonElement value,
            params string[] names)
        {
            if (value.ValueKind != JsonValueKind.Object)
                return false;
            foreach (string name in names)
            {
                if (!value.TryGetProperty(name, out _))
                    return false;
            }
            return true;
        }

        private static bool FixedTimeEqualsProtocolValue(
            string expected,
            string actual)
        {
            if (string.IsNullOrWhiteSpace(expected)
                || string.IsNullOrWhiteSpace(actual)
                || expected.Length != actual.Length
                || expected.Length > 256)
            {
                return false;
            }
            return CryptographicOperations.FixedTimeEquals(
                StrictUtf8.GetBytes(expected),
                StrictUtf8.GetBytes(actual));
        }

        private static async Task<AgentRendezvousDocument>
            ReadOwnedRendezvousAsync(
                string projectRoot,
                Process guardian,
                string expectedRuntimeMode,
                CancellationToken cancellationToken)
        {
            string path =
                AgentRendezvousPath.Resolve(
                    projectRoot);
            DateTimeOffset deadline =
                DateTimeOffset.UtcNow
                    .AddSeconds(30);
            Exception last = null;
            while (DateTimeOffset.UtcNow < deadline)
            {
                cancellationToken
                    .ThrowIfCancellationRequested();
                if (guardian.HasExited)
                {
                    throw new InvalidOperationException(
                        "trusted_runner_guardian_exited");
                }
                try
                {
                    TrustedUnattendedRuntimeBundle
                        .RejectReparseChain(
                            path,
                            Path.GetDirectoryName(path));
                    FileInfo info = new FileInfo(path);
                    if ((info.Attributes
                            & (FileAttributes.Directory
                                | FileAttributes
                                    .ReparsePoint)) != 0
                        || info.Length <= 0
                        || info.Length > 64 * 1024)
                    {
                        throw new InvalidDataException(
                            "trusted_runner_rendezvous_file_invalid");
                    }
                    byte[] bytes;
                    using (var stream = new FileStream(
                        path,
                        FileMode.Open,
                        FileAccess.Read,
                        FileShare.Read,
                        4096,
                        FileOptions.SequentialScan))
                    {
                        bytes = new byte[
                            checked((int)stream.Length)];
                        stream.ReadExactly(bytes);
                    }
                    AgentRendezvousDocument document;
                    try
                    {
                        document =
                            AgentRendezvousStore
                                .ParseDocument(bytes);
                    }
                    finally
                    {
                        CryptographicOperations
                            .ZeroMemory(bytes);
                    }
                    if (document.LauncherProcessId
                            != guardian.Id
                        || document
                            .LauncherStartTimeUtc
                            .UtcDateTime.Ticks
                            != guardian.StartTime
                                .ToUniversalTime()
                                .Ticks
                        || document.TicketExpiresUtc
                            <= DateTimeOffset.UtcNow
                        || !string.Equals(
                            document
                                .RuntimeQualificationState,
                            expectedRuntimeMode,
                            StringComparison.Ordinal))
                    {
                        throw new InvalidDataException(
                            "trusted_runner_rendezvous_binding_invalid");
                    }
                    return document;
                }
                catch (Exception exception)
                    when (exception is IOException
                        || exception
                            is UnauthorizedAccessException
                        || exception
                            is InvalidDataException)
                {
                    last = exception;
                }
                await Task.Delay(
                    50,
                    cancellationToken)
                    .ConfigureAwait(false);
            }
            throw new TimeoutException(
                "trusted_runner_rendezvous_timeout",
                last);
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(
                    nameof(
                        TrustedUnattendedAgentClient));
        }

        public ValueTask DisposeAsync()
        {
            if (!_disposed)
            {
                _disposed = true;
                _pipe.Dispose();
            }
            return ValueTask.CompletedTask;
        }
    }

    internal sealed class TrustedAgentCallResult
    {
        public TrustedAgentCallResult(
            JsonElement response,
            DecodedBinaryChunk binary)
        {
            Response = response;
            Binary = binary;
        }

        public JsonElement Response { get; }
        public DecodedBinaryChunk Binary { get; }
    }
}
