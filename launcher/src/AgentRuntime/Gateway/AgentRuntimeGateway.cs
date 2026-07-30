using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Gateway
{
    internal interface IAgentConnectionTicketAuthority
    {
        bool TryConsumeAndRotate(
            string presentedTicket,
            out string reasonCode);
    }

    internal sealed class AgentRendezvousTicketAuthority
        : IAgentConnectionTicketAuthority
    {
        private readonly AgentRendezvousStore _store;
        private readonly string _lifecycleId;

        public AgentRendezvousTicketAuthority(
            AgentRendezvousStore store,
            string lifecycleId)
        {
            _store = store
                ?? throw new ArgumentNullException(nameof(store));
            if (string.IsNullOrWhiteSpace(lifecycleId))
                throw new ArgumentException(
                    "A lifecycle ID is required.",
                    nameof(lifecycleId));
            _lifecycleId = lifecycleId;
        }

        public bool TryConsumeAndRotate(
            string presentedTicket,
            out string reasonCode)
        {
            return _store.TryConsumeAndRotate(
                presentedTicket,
                _lifecycleId,
                out _,
                out reasonCode);
        }
    }

    internal interface IMinimalSessionReferenceProvider
    {
        MinimalSessionReference GetMinimalReference();

        bool TryResolveLifecycleReference(
            string lifecycleRef,
            out string sessionId,
            out ulong lifecycleGeneration);
    }

    internal interface IAgentConnectionAuthenticationAuthority
    {
        AgentConnectionAuthenticationResult Authenticate(
            HelloMessage hello,
            AgentProcessSecurityIdentity peerIdentity);
    }

    internal sealed class AgentConnectionAuthenticationAuthority
        : IAgentConnectionAuthenticationAuthority
    {
        private readonly AgentConnectionAuthenticator _authenticator;

        public AgentConnectionAuthenticationAuthority(
            AgentConnectionAuthenticator authenticator)
        {
            _authenticator = authenticator
                ?? throw new ArgumentNullException(
                    nameof(authenticator));
        }

        public AgentConnectionAuthenticationResult Authenticate(
            HelloMessage hello,
            AgentProcessSecurityIdentity peerIdentity)
        {
            return _authenticator.Authenticate(
                hello,
                peerIdentity);
        }
    }

    internal interface IAgentConnectionResourceAuthority
    {
        void RegisterConnection(
            string connectionId,
            PrincipalCredential principal,
            Action<string> terminateConnection);

        bool IsDispatchAuthorized(
            string connectionId,
            PrincipalCredential principal);

        Task RevokeAsync(
            string connectionId,
            AgentConnectionTermination termination);
    }

    internal sealed class AgentConnectionResourceAuthority
        : IAgentConnectionResourceAuthority
    {
        private readonly AgentRuntimeRevocationCoordinator _coordinator;
        private readonly IUnattendedCredentialBindingAuthority
            _unattendedBindings;
        private readonly IAgentRuntimeConnectionAuditSink
            _connectionAudit;

        public AgentConnectionResourceAuthority(
            AgentRuntimeRevocationCoordinator coordinator,
            IUnattendedCredentialBindingAuthority
                unattendedBindings,
            IAgentRuntimeConnectionAuditSink
                connectionAudit = null)
        {
            _coordinator = coordinator
                ?? throw new ArgumentNullException(
                    nameof(coordinator));
            _unattendedBindings = unattendedBindings
                ?? throw new ArgumentNullException(
                    nameof(unattendedBindings));
            _connectionAudit = connectionAudit;
        }

        public void RegisterConnection(
            string connectionId,
            PrincipalCredential principal,
            Action<string> terminateConnection)
        {
            _coordinator.RegisterConnection(
                connectionId,
                principal,
                terminateConnection);
            if (principal.PrincipalKind
                    == AgentPrincipalKind.UnattendedTestRunner
                && !_unattendedBindings
                    .IsPrincipalAuthorized(principal))
            {
                _coordinator.RevokeConnection(
                    connectionId,
                    "unattended_binding_changed");
                throw new InvalidOperationException(
                    "unattended_binding_changed");
            }
            if (_connectionAudit != null
                && !_connectionAudit
                    .TryRegisterAuthenticatedConnection(
                        connectionId,
                        principal,
                        out string auditReason))
            {
                _coordinator.RevokeConnection(
                    connectionId,
                    auditReason ?? "audit_unavailable");
                throw new InvalidOperationException(
                    auditReason ?? "audit_unavailable");
            }
        }

        public bool IsDispatchAuthorized(
            string connectionId,
            PrincipalCredential principal)
        {
            if (!_coordinator.IsDispatchAuthorized(
                    connectionId,
                    principal))
            {
                return false;
            }
            if (principal.PrincipalKind
                    != AgentPrincipalKind.UnattendedTestRunner
                || _unattendedBindings
                    .IsPrincipalAuthorized(principal))
            {
                return true;
            }
            _coordinator.RevokeConnection(
                connectionId,
                "unattended_binding_changed");
            return false;
        }

        public async Task RevokeAsync(
            string connectionId,
            AgentConnectionTermination termination)
        {
            await _coordinator.RevokeAsync(
                    connectionId,
                    termination)
                .ConfigureAwait(false);
            _connectionAudit?.RecordConnectionTermination(
                connectionId,
                termination?.ReasonCode
                    ?? "connection_closed");
        }
    }

    internal sealed class AgentRuntimeDispatchContext
    {
        internal AgentRuntimeDispatchContext(
            string connectionId,
            PrincipalCredential principal)
            : this(connectionId, principal, null)
        {
        }

        internal AgentRuntimeDispatchContext(
            string connectionId,
            PrincipalCredential principal,
            string hostAttestedArgumentBoundsHash)
        {
            ConnectionId = connectionId;
            Principal = principal;
            HostAttestedArgumentBoundsHash =
                hostAttestedArgumentBoundsHash;
        }

        public string ConnectionId { get; }
        public PrincipalCredential Principal { get; }
        internal string HostAttestedArgumentBoundsHash
        {
            get;
        }
    }

    internal sealed class AgentRuntimeBinaryChunk
    {
        public AgentRuntimeBinaryChunk(
            BinaryChunkMetadata metadata,
            byte[] content)
        {
            Metadata = metadata
                ?? throw new ArgumentNullException(nameof(metadata));
            Content = content
                ?? throw new ArgumentNullException(nameof(content));
        }

        public BinaryChunkMetadata Metadata { get; }
        public byte[] Content { get; }
    }

    internal sealed class AgentRuntimeDispatchResult
    {
        private AgentRuntimeDispatchResult(
            JsonElement result,
            AgentRuntimeBinaryChunk binaryChunk,
            string reasonCode,
            ReconcileKind reconcileKind,
            AgentRuntimeResponseCompletion responseCompletion)
        {
            Result = result;
            BinaryChunk = binaryChunk;
            ReasonCode = reasonCode;
            ReconcileKind = reconcileKind;
            ResponseCompletion = responseCompletion;
        }

        public bool Success
        {
            get { return ReasonCode == null; }
        }

        public JsonElement Result { get; }
        public AgentRuntimeBinaryChunk BinaryChunk { get; }
        public string ReasonCode { get; }
        public ReconcileKind ReconcileKind { get; }
        public AgentRuntimeResponseCompletion ResponseCompletion
        {
            get;
        }

        public static AgentRuntimeDispatchResult Completed<T>(
            T result,
            AgentRuntimeBinaryChunk binaryChunk = null,
            AgentRuntimeResponseCompletion responseCompletion = null)
        {
            return new AgentRuntimeDispatchResult(
                JsonSerializer.SerializeToElement(
                    result,
                    AgentProtocolV1.JsonOptions),
                binaryChunk,
                null,
                ReconcileKind.None,
                responseCompletion);
        }

        public static AgentRuntimeDispatchResult Rejected(
            string reasonCode,
            ReconcileKind reconcileKind = ReconcileKind.None)
        {
            if (string.IsNullOrWhiteSpace(reasonCode))
                throw new ArgumentException(
                    "A reason code is required.",
                    nameof(reasonCode));
            return new AgentRuntimeDispatchResult(
                default,
                null,
                reasonCode,
                reconcileKind,
                null);
        }
    }

    internal interface IAgentRuntimeMethodDispatcher
    {
        Task<AgentRuntimeDispatchResult> DispatchAsync(
            AgentRuntimeDispatchContext context,
            AgentJsonRpcRequest request,
            CancellationToken cancellationToken);
    }

    /// <summary>
    /// Authenticated CF7A/JSON-RPC connection boundary. It consumes the
    /// rendezvous ticket before credential verification, admits only one
    /// runtime.hello as the first JSON frame, applies per-client scheduling,
    /// serializes response writes, and couples content.read JSON and binary
    /// frames under the same writer lock.
    /// </summary>
    internal sealed class AgentRuntimeGateway
    {
        private const byte ProtocolMajor = 1;
        private readonly AgentFrameCodec _codec =
            new AgentFrameCodec(ProtocolMajor);
        private readonly IAgentConnectionTicketAuthority _tickets;
        private readonly IAgentConnectionAuthenticationAuthority
            _authenticator;
        private readonly IAgentConnectionResourceAuthority _revocations;
        private readonly IAgentRuntimeClock _clock;
        private readonly IMinimalSessionReferenceProvider _sessions;
        private readonly IAgentRuntimeMethodDispatcher _dispatcher;
        private readonly string _serverInstanceId;
        private long _serverSequence;

        internal Action BeforeDispatchAuthorizationForTests;
        internal Action AfterRequestFrameReceivedForTests;

        public AgentRuntimeGateway(
            IAgentConnectionTicketAuthority tickets,
            IAgentConnectionAuthenticationAuthority authenticator,
            IAgentConnectionResourceAuthority revocations,
            IAgentRuntimeClock clock,
            IMinimalSessionReferenceProvider sessions,
            IAgentRuntimeMethodDispatcher dispatcher,
            string serverInstanceId)
        {
            _tickets = tickets
                ?? throw new ArgumentNullException(nameof(tickets));
            _authenticator = authenticator
                ?? throw new ArgumentNullException(
                    nameof(authenticator));
            _revocations = revocations
                ?? throw new ArgumentNullException(
                    nameof(revocations));
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _sessions = sessions
                ?? throw new ArgumentNullException(nameof(sessions));
            _dispatcher = dispatcher
                ?? throw new ArgumentNullException(nameof(dispatcher));
            if (string.IsNullOrWhiteSpace(serverInstanceId))
                throw new ArgumentException(
                    "A server instance ID is required.",
                    nameof(serverInstanceId));
            _serverInstanceId = serverInstanceId;
        }

        public async Task<AgentConnectionTermination> RunConnectionAsync(
            string connectionId,
            Stream stream,
            CancellationToken cancellationToken)
        {
            return await RunConnectionAsync(
                connectionId,
                stream,
                null,
                cancellationToken).ConfigureAwait(false);
        }

        internal async Task<AgentConnectionTermination>
            RunConnectionAsync(
                string connectionId,
                Stream stream,
                AgentProcessSecurityIdentity peerIdentity,
                CancellationToken cancellationToken)
        {
            if (string.IsNullOrWhiteSpace(connectionId))
                throw new ArgumentException(
                    "A connection ID is required.",
                    nameof(connectionId));
            if (stream == null)
                throw new ArgumentNullException(nameof(stream));

            using var connectionCancellation =
                CancellationTokenSource.CreateLinkedTokenSource(
                    cancellationToken);
            using var writer = new SemaphoreSlim(1, 1);
            using var scheduler = new AgentRequestScheduler(_clock);
            var requests = new ConcurrentDictionary<long, Task>();
            PrincipalCredential principal = null;
            AgentConnectionTermination termination = null;
            long requestOrdinal = 0;
            string forcedTerminationReason = null;

            void TerminateConnection(string reasonCode)
            {
                Interlocked.CompareExchange(
                    ref forcedTerminationReason,
                    string.IsNullOrWhiteSpace(reasonCode)
                        ? "credential_revoked"
                        : reasonCode,
                    null);
                try
                {
                    connectionCancellation.Cancel();
                }
                catch
                {
                }
                try
                {
                    stream.Dispose();
                }
                catch
                {
                }
            }

            try
            {
                AgentFrame helloFrame = await _codec.ReadAsync(
                    stream,
                    connectionCancellation.Token)
                    .ConfigureAwait(false);
                if (helloFrame == null)
                {
                    termination = Termination(
                        AgentConnectionTerminationKind.CleanDisconnect,
                        "connection_closed");
                    return termination;
                }
                if (helloFrame.Kind != AgentFrameKind.JsonRpc)
                {
                    termination = Termination(
                        AgentConnectionTerminationKind.ProtocolViolation,
                        "malformed_frame");
                    return termination;
                }

                if (!TryParseRequest(
                        helloFrame,
                        out AgentJsonRpcRequest helloRequest,
                        out string helloId,
                        out string validationReason))
                {
                    if (helloId != null)
                    {
                        await WriteErrorAsync(
                            stream,
                            writer,
                            helloId,
                            validationReason,
                            ReconcileKind.None,
                            connectionCancellation.Token)
                            .ConfigureAwait(false);
                    }
                    termination = Termination(
                        AgentConnectionTerminationKind.ProtocolViolation,
                        validationReason);
                    return termination;
                }
                if (!string.Equals(
                        helloRequest.Method,
                        AgentMethodsV1.RuntimeHello,
                        StringComparison.Ordinal))
                {
                    await WriteErrorAsync(
                        stream,
                        writer,
                        helloRequest.Id,
                        "authentication_failed",
                        ReconcileKind.None,
                        connectionCancellation.Token)
                        .ConfigureAwait(false);
                    termination = Termination(
                        AgentConnectionTerminationKind.ProtocolViolation,
                        "authentication_failed");
                    return termination;
                }

                HelloMessage hello =
                    helloRequest.Params.Deserialize<HelloMessage>(
                        AgentProtocolV1.JsonOptions);
                string ticketReason = null;
                if (hello == null
                    || !_tickets.TryConsumeAndRotate(
                        hello.ConnectionToken,
                        out ticketReason))
                {
                    string reason = NormalizeTicketReason(
                        ticketReason);
                    await WriteErrorAsync(
                        stream,
                        writer,
                        helloRequest.Id,
                        reason,
                        ReconcileKind.None,
                        connectionCancellation.Token)
                        .ConfigureAwait(false);
                    termination = Termination(
                        AgentConnectionTerminationKind.ProtocolViolation,
                        reason);
                    return termination;
                }

                AgentConnectionAuthenticationResult authentication =
                    _authenticator.Authenticate(
                        hello,
                        peerIdentity);
                if (!authentication.Success)
                {
                    string reason = NormalizeReason(
                        authentication.ReasonCode);
                    await WriteErrorAsync(
                        stream,
                        writer,
                        helloRequest.Id,
                        reason,
                        ReconcileKind.None,
                        connectionCancellation.Token)
                        .ConfigureAwait(false);
                    termination = Termination(
                        AgentConnectionTerminationKind.ProtocolViolation,
                        reason);
                    return termination;
                }

                principal = authentication.Principal;
                _revocations.RegisterConnection(
                    connectionId,
                    principal,
                    TerminateConnection);
                var welcome = new WelcomeMessage
                {
                    ServerInstanceId = _serverInstanceId,
                    SecurityPrincipalId =
                        principal.SecurityPrincipalId,
                    MinimalSessionRef =
                        _sessions.GetMinimalReference(),
                    GrantedCapabilities =
                        authentication
                            .GrantedCapabilities
                            .ToList(),
                    Limits = new WelcomeLimits(),
                    ServerSequence = NextServerSequence()
                };
                await WriteSuccessAsync(
                    stream,
                    writer,
                    helloRequest.Id,
                    JsonSerializer.SerializeToElement(
                        welcome,
                        AgentProtocolV1.JsonOptions),
                    null,
                    null,
                    connectionCancellation.Token)
                    .ConfigureAwait(false);

                var dispatchContext =
                    new AgentRuntimeDispatchContext(
                        connectionId,
                        principal);
                while (true)
                {
                    AgentFrame frame = await _codec.ReadAsync(
                        stream,
                        connectionCancellation.Token)
                        .ConfigureAwait(false);
                    if (frame == null)
                    {
                        termination = Termination(
                            AgentConnectionTerminationKind.CleanDisconnect,
                            "connection_closed");
                        break;
                    }
                    long requestReceivedMonotonic =
                        _clock.MonotonicMilliseconds;
                    AfterRequestFrameReceivedForTests?.Invoke();
                    if (frame.Kind != AgentFrameKind.JsonRpc)
                    {
                        termination = Termination(
                            AgentConnectionTerminationKind.ProtocolViolation,
                            "malformed_frame");
                        break;
                    }

                    if (!TryParseRequest(
                            frame,
                            out AgentJsonRpcRequest request,
                            out string requestId,
                            out validationReason))
                    {
                        if (requestId == null)
                        {
                            termination = Termination(
                                AgentConnectionTerminationKind.ProtocolViolation,
                                validationReason);
                            break;
                        }
                        Task invalidTask = WriteErrorAsync(
                            stream,
                            writer,
                            requestId,
                            validationReason,
                            ReconcileKind.None,
                            connectionCancellation.Token);
                        Track(
                            requests,
                            Interlocked.Increment(
                                ref requestOrdinal),
                            invalidTask);
                        continue;
                    }
                    if (string.Equals(
                            request.Method,
                            AgentMethodsV1.RuntimeHello,
                            StringComparison.Ordinal))
                    {
                        await WriteErrorAsync(
                            stream,
                            writer,
                            request.Id,
                            "operation_invalid",
                            ReconcileKind.None,
                            connectionCancellation.Token)
                            .ConfigureAwait(false);
                        termination = Termination(
                            AgentConnectionTerminationKind.ProtocolViolation,
                            "operation_invalid");
                        break;
                    }

                    if (!_revocations.IsDispatchAuthorized(
                            connectionId,
                            principal))
                    {
                        termination = Termination(
                            AgentConnectionTerminationKind.Cancelled,
                            Volatile.Read(
                                ref forcedTerminationReason)
                                ?? "credential_revoked");
                        break;
                    }

                    AgentMethodsV1.TryGet(
                        request.Method,
                        out AgentMethodDefinition method);
                    if (method == null
                        || !principal.AllowsCapability(
                            method.RequiredCapability))
                    {
                        Task deniedTask = WriteErrorAsync(
                            stream,
                            writer,
                            request.Id,
                            "capability_denied",
                            ReconcileKind.None,
                            connectionCancellation.Token);
                        Track(
                            requests,
                            Interlocked.Increment(
                                ref requestOrdinal),
                            deniedTask);
                        continue;
                    }

                    long ordinal = Interlocked.Increment(
                        ref requestOrdinal);
                    Task dispatch = DispatchScheduledAsync(
                        stream,
                        writer,
                        scheduler,
                        dispatchContext,
                        request,
                        requestReceivedMonotonic,
                        connectionCancellation.Token);
                    Track(requests, ordinal, dispatch);
                }
            }
            catch (AgentFrameProtocolException exception)
            {
                termination = new AgentConnectionTermination(
                    AgentConnectionTerminationKind.ProtocolViolation,
                    "malformed_frame",
                    exception.Error);
            }
            catch (OperationCanceledException)
                when (connectionCancellation
                    .IsCancellationRequested)
            {
                termination = Termination(
                    AgentConnectionTerminationKind.Cancelled,
                    Volatile.Read(
                        ref forcedTerminationReason)
                        ?? "connection_cancelled");
            }
            catch
            {
                string forced = Volatile.Read(
                    ref forcedTerminationReason);
                termination = forced == null
                    ? Termination(
                        AgentConnectionTerminationKind
                            .TransportFailure,
                        "connection_transport_failed")
                    : Termination(
                        AgentConnectionTerminationKind
                            .Cancelled,
                        forced);
            }
            finally
            {
                connectionCancellation.Cancel();
                Task[] pending = requests.Values.ToArray();
                if (pending.Length != 0)
                {
                    try
                    {
                        await Task.WhenAll(pending)
                            .ConfigureAwait(false);
                    }
                    catch
                    {
                        // A broken pipe cannot bypass mandatory revocation.
                    }
                }
                if (principal != null)
                {
                    await _revocations.RevokeAsync(
                        connectionId,
                        termination
                            ?? Termination(
                                AgentConnectionTerminationKind
                                    .TransportFailure,
                                "connection_transport_failed"))
                        .ConfigureAwait(false);
                }
            }

            return termination
                ?? Termination(
                    AgentConnectionTerminationKind.TransportFailure,
                    "connection_transport_failed");
        }

        private async Task DispatchScheduledAsync(
            Stream stream,
            SemaphoreSlim writer,
            AgentRequestScheduler scheduler,
            AgentRuntimeDispatchContext context,
            AgentJsonRpcRequest request,
            long receivedMonotonic,
            CancellationToken cancellationToken)
        {
            int deadlineMs = ReadDeadline(request.Params);
            long deadlineMonotonic = checked(
                receivedMonotonic + deadlineMs);
            AgentRuntimeDispatchResult dispatched = null;
            AgentScheduledResult<AgentRuntimeDispatchResult> scheduled =
                await scheduler.ExecuteAsync(
                    deadlineMs,
                    receivedMonotonic,
                    token =>
                    {
                        Action beforeAuthorization =
                            BeforeDispatchAuthorizationForTests;
                        beforeAuthorization?.Invoke();
                        if (token.IsCancellationRequested
                            || !_revocations
                                .IsDispatchAuthorized(
                                    context.ConnectionId,
                                    context.Principal))
                        {
                            return Task.FromResult(
                                AgentRuntimeDispatchResult
                                    .Rejected(
                                        "credential_revoked"));
                        }
                        return DispatchAndRememberAsync(
                            context,
                            request,
                            token,
                            result => dispatched = result);
                    },
                    cancellationToken)
                    .ConfigureAwait(false);
            if (cancellationToken.IsCancellationRequested)
            {
                (scheduled.Value ?? dispatched)
                    ?.ResponseCompletion?.Abort();
                return;
            }
            if (!scheduled.Success)
            {
                dispatched?.ResponseCompletion?.Abort();
                string reason = NormalizeReason(
                    scheduled.ReasonCode);
                if (string.Equals(
                        scheduled.ReasonCode,
                        "connection_cancelled",
                        StringComparison.Ordinal))
                {
                    return;
                }
                using CancellationTokenSource responseCancellation =
                    CreateResponseWriteCancellation(
                        deadlineMonotonic,
                        cancellationToken);
                await WriteErrorAsync(
                        stream,
                        writer,
                        request.Id,
                        reason,
                        ReconcileKind.None,
                        responseCancellation.Token)
                    .ConfigureAwait(false);
                return;
            }

            AgentRuntimeDispatchResult result =
                scheduled.Value
                ?? AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            if (cancellationToken.IsCancellationRequested)
            {
                result.ResponseCompletion?.Abort();
                return;
            }
            if (!result.Success)
            {
                result.ResponseCompletion?.Abort();
                using CancellationTokenSource responseCancellation =
                    CreateResponseWriteCancellation(
                        deadlineMonotonic,
                        cancellationToken);
                await WriteErrorAsync(
                        stream,
                        writer,
                        request.Id,
                        NormalizeReason(result.ReasonCode),
                        result.ReconcileKind,
                        responseCancellation.Token)
                    .ConfigureAwait(false);
                return;
            }
            using CancellationTokenSource successResponseCancellation =
                CreateResponseWriteCancellation(
                    deadlineMonotonic,
                    cancellationToken);
            try
            {
                await WriteSuccessAsync(
                    stream,
                    writer,
                    request.Id,
                    result.Result,
                    result.BinaryChunk,
                    result.ResponseCompletion,
                    successResponseCancellation.Token)
                    .ConfigureAwait(false);
            }
            catch
            {
                result.ResponseCompletion?.Abort();
                throw;
            }
        }

        private async Task<AgentRuntimeDispatchResult>
            DispatchAndRememberAsync(
                AgentRuntimeDispatchContext context,
                AgentJsonRpcRequest request,
                CancellationToken cancellationToken,
                Action<AgentRuntimeDispatchResult> remember)
        {
            AgentRuntimeDispatchResult result =
                await _dispatcher.DispatchAsync(
                    context,
                    request,
                    cancellationToken).ConfigureAwait(false);
            remember?.Invoke(result);
            return result;
        }

        private async Task WriteSuccessAsync(
            Stream stream,
            SemaphoreSlim writer,
            string id,
            JsonElement result,
            AgentRuntimeBinaryChunk binaryChunk,
            AgentRuntimeResponseCompletion responseCompletion,
            CancellationToken cancellationToken)
        {
            byte[] binaryPayload = null;
            if (binaryChunk != null)
            {
                binaryPayload = BinaryChunkCodecV1.Encode(
                    binaryChunk.Metadata,
                    binaryChunk.Content);
            }
            var response = new AgentJsonRpcSuccessResponse
            {
                Id = id,
                Result = result
            };
            byte[] json = JsonSerializer.SerializeToUtf8Bytes(
                response,
                AgentProtocolV1.JsonOptions);

            await writer.WaitAsync(cancellationToken)
                .ConfigureAwait(false);
            try
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (responseCompletion != null
                    && !responseCompletion.TryPrepareWrite())
                {
                    throw new InvalidOperationException(
                        "response_delivery_not_authorized");
                }
                await _codec.WriteAsync(
                        stream,
                        new AgentFrame(
                        ProtocolMajor,
                        AgentFrameKind.JsonRpc,
                        0,
                        json),
                    cancellationToken)
                    .ConfigureAwait(false);
                if (binaryPayload != null)
                {
                    await _codec.WriteAsync(
                        stream,
                        new AgentFrame(
                            ProtocolMajor,
                            AgentFrameKind.BinaryChunk,
                            0,
                            binaryPayload),
                        cancellationToken)
                        .ConfigureAwait(false);
                }
                // A complete framed write is the last truthful point at
                // which the server can still choose between delivery and
                // abort. Flush may fail after the peer has already read it.
                if (responseCompletion != null
                    && !responseCompletion.CommitAfterWrite())
                {
                    responseCompletion
                        .ReportPostWriteCommitFailure();
                }
                await stream.FlushAsync(cancellationToken)
                    .ConfigureAwait(false);
            }
            finally
            {
                writer.Release();
            }
        }

        private CancellationTokenSource
            CreateResponseWriteCancellation(
                long deadlineMonotonic,
                CancellationToken cancellationToken)
        {
            CancellationTokenSource linked =
                CancellationTokenSource
                    .CreateLinkedTokenSource(
                        cancellationToken);
            long remaining = deadlineMonotonic
                - _clock.MonotonicMilliseconds;
            if (remaining <= 0)
            {
                linked.Cancel();
            }
            else
            {
                linked.CancelAfter(
                    TimeSpan.FromMilliseconds(remaining));
            }
            return linked;
        }

        private async Task WriteErrorAsync(
            Stream stream,
            SemaphoreSlim writer,
            string id,
            string reasonCode,
            ReconcileKind reconcileKind,
            CancellationToken cancellationToken)
        {
            string normalized = NormalizeReason(reasonCode);
            AgentReasonCodesV1.TryGet(
                normalized,
                out ReasonCodeDefinition definition);
            if (!definition.AllowedReconcileKinds.Contains(
                    reconcileKind))
            {
                reconcileKind =
                    definition.AllowedReconcileKinds[0];
            }
            var response = new AgentJsonRpcErrorResponse
            {
                Id = id,
                Error = new AgentJsonRpcError
                {
                    Code = JsonRpcErrorCode(normalized),
                    Message = normalized,
                    Data = new AgentJsonRpcErrorData
                    {
                        ReasonCode = normalized,
                        Retryable = definition.Retryable,
                        ReconcileKind = reconcileKind,
                        ServerSequence = NextServerSequence()
                    }
                }
            };
            byte[] json = JsonSerializer.SerializeToUtf8Bytes(
                response,
                AgentProtocolV1.JsonOptions);

            await writer.WaitAsync(cancellationToken)
                .ConfigureAwait(false);
            try
            {
                await _codec.WriteAsync(
                    stream,
                    new AgentFrame(
                        ProtocolMajor,
                        AgentFrameKind.JsonRpc,
                        0,
                        json),
                    cancellationToken)
                    .ConfigureAwait(false);
                await stream.FlushAsync(cancellationToken)
                    .ConfigureAwait(false);
            }
            finally
            {
                writer.Release();
            }
        }

        private static bool TryParseRequest(
            AgentFrame frame,
            out AgentJsonRpcRequest request,
            out string requestId,
            out string reasonCode)
        {
            request = null;
            requestId = null;
            reasonCode = "arguments_invalid";
            try
            {
                using JsonDocument document = JsonDocument.Parse(
                    frame.Payload);
                JsonElement root = document.RootElement;
                if (root.ValueKind == JsonValueKind.Object
                    && root.TryGetProperty(
                        "id",
                        out JsonElement id)
                    && id.ValueKind == JsonValueKind.String)
                {
                    string candidate = id.GetString();
                    if (!string.IsNullOrEmpty(candidate)
                        && candidate.Length <= 128
                        && !candidate.Any(char.IsControl))
                    {
                        requestId = candidate;
                    }
                }

                IReadOnlyList<ContractViolation> violations =
                    AgentJsonRpcValidator.ValidateRequest(root);
                if (violations.Count != 0)
                {
                    ContractViolation first = violations[0];
                    reasonCode = string.Equals(
                            first.Code,
                            "protocol_version_mismatch",
                            StringComparison.Ordinal)
                        ? "protocol_version_mismatch"
                        : string.Equals(
                                first.Code,
                                "rpc_method_not_found",
                                StringComparison.Ordinal)
                            ? "operation_invalid"
                            : "arguments_invalid";
                    return false;
                }
                request = JsonSerializer.Deserialize<
                    AgentJsonRpcRequest>(
                    root.GetRawText(),
                    AgentProtocolV1.JsonOptions);
                if (request == null)
                    return false;
                request.Params = request.Params.Clone();
                requestId = request.Id;
                reasonCode = null;
                return true;
            }
            catch (JsonException)
            {
                reasonCode = "malformed_json";
                return false;
            }
        }

        private static int ReadDeadline(JsonElement parameters)
        {
            if (parameters.ValueKind == JsonValueKind.Object
                && parameters.TryGetProperty(
                    "deadlineMs",
                    out JsonElement deadline)
                && deadline.ValueKind == JsonValueKind.Number
                && deadline.TryGetInt32(out int value)
                && value > 0)
            {
                return Math.Min(
                    value,
                    AgentProtocolV1.MaximumActionDeadlineMs);
            }
            return AgentProtocolV1.MaximumActionDeadlineMs;
        }

        private static void Track(
            ConcurrentDictionary<long, Task> requests,
            long ordinal,
            Task task)
        {
            requests[ordinal] = task;
            _ = task.ContinueWith(
                _ => requests.TryRemove(ordinal, out _),
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }

        private ulong NextServerSequence()
        {
            long value = Interlocked.Increment(
                ref _serverSequence);
            if (value <= 0
                || value
                    > CanonicalJsonV1.MaximumSafeInteger)
            {
                throw new InvalidOperationException(
                    "server_sequence_exhausted");
            }
            return checked((ulong)value);
        }

        private static string NormalizeTicketReason(
            string reasonCode)
        {
            return reasonCode switch
            {
                "ticket_expired" =>
                    "connection_ticket_expired",
                "ticket_mismatch" =>
                    "connection_ticket_replayed",
                _ => "authentication_failed"
            };
        }

        internal static string NormalizeReason(
            string reasonCode)
        {
            if (AgentReasonCodesV1.TryGet(
                    reasonCode,
                    out _))
            {
                return reasonCode;
            }
            return reasonCode switch
            {
                "observation_grant_not_found" =>
                    "observation_grant_required",
                "observation_grant_inactive" =>
                    "observation_grant_revoked",
                "observation_grant_owner_mismatch" =>
                    "observation_scope_mismatch",
                "session_scope_mismatch" =>
                    "session_mismatch",
                "target_scope_denied" =>
                    "observation_scope_mismatch",
                "data_scope_denied" =>
                    "observation_scope_mismatch",
                "data_scope_invalid" =>
                    "arguments_invalid",
                "target_not_authoritative" =>
                    "target_not_found",
                "write_lease_already_held" =>
                    "lease_busy",
                "action_limit_consumed" =>
                    "lease_action_limit",
                "lease_not_found" =>
                    "lease_required",
                "lease_inactive" or
                "client_released" or
                "connection_closed" or
                "runtime_shutdown" =>
                    "lease_revoked",
                "capability_scope_denied" =>
                    "capability_denied",
                "credential_expired" =>
                    "credential_revoked",
                "lease_not_renewable" or
                "renewal_limit_reached" =>
                    "operation_invalid",
                "client_revoked" =>
                    "observation_grant_revoked",
                "human_input" =>
                    "external_input_preempted",
                "connection_cancelled" =>
                    "internal_error",
                _ => "internal_error"
            };
        }

        private static int JsonRpcErrorCode(
            string reasonCode)
        {
            return reasonCode switch
            {
                "malformed_json" => -32700,
                "arguments_invalid" => -32602,
                "operation_invalid" => -32601,
                _ => -32000
            };
        }

        private static AgentConnectionTermination Termination(
            AgentConnectionTerminationKind kind,
            string reasonCode)
        {
            return new AgentConnectionTermination(
                kind,
                reasonCode,
                null);
        }
    }
}
