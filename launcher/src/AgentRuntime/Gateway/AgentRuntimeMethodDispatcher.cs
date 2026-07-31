using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Gateway
{
    internal interface IAgentRuntimeHostMethodService
    {
        Task<AgentRuntimeDispatchResult> DispatchAsync(
            AgentRuntimeDispatchContext context,
            AgentJsonRpcRequest request,
            CancellationToken cancellationToken);
    }

    internal sealed class FailClosedAgentRuntimeHostMethodService
        : IAgentRuntimeHostMethodService
    {
        public Task<AgentRuntimeDispatchResult> DispatchAsync(
            AgentRuntimeDispatchContext context,
            AgentJsonRpcRequest request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(
                AgentRuntimeDispatchResult.Rejected(
                    "unsupported_for_surface"));
        }
    }

    internal interface IAgentWriteLeaseLifecycle
    {
        bool TryActivate(
            WriteLease lease,
            out string reasonCode);

        void Release(WriteLease lease);
    }

    internal sealed class FailClosedAgentWriteLeaseLifecycle
        : IAgentWriteLeaseLifecycle
    {
        public bool TryActivate(
            WriteLease lease,
            out string reasonCode)
        {
            if (lease.Kind
                != WriteLeaseKind.GuiInput)
            {
                reasonCode = null;
                return true;
            }
            reasonCode = "input_guard_unhealthy";
            return false;
        }

        public void Release(WriteLease lease)
        {
        }
    }

    internal interface IAgentHairPreviewStore
    {
        void Store(
            AgentRuntimeDispatchContext context,
            string targetId,
            HairAppearancePreview preview);

        bool TryResolve(
            AgentRuntimeDispatchContext context,
            string transactionId,
            string previewHash,
            out string targetId,
            out HairAppearancePreview preview,
            out string reasonCode);
    }

    internal sealed class AgentHairPreviewStore
        : IAgentHairPreviewStore
    {
        private const int MaximumPreviews = 256;
        private readonly object _sync = new object();
        private readonly Dictionary<string, Entry> _entries =
            new Dictionary<string, Entry>(
                StringComparer.Ordinal);
        private readonly Queue<string> _order =
            new Queue<string>();

        public void Store(
            AgentRuntimeDispatchContext context,
            string targetId,
            HairAppearancePreview preview)
        {
            lock (_sync)
            {
                if (_entries.ContainsKey(
                        preview.TransactionId))
                {
                    throw new InvalidOperationException(
                        "hair_preview_already_registered");
                }
                _entries.Add(
                    preview.TransactionId,
                    new Entry(
                        context.ConnectionId,
                        context.Principal.ClientInstanceId,
                        context.Principal
                            .SecurityPrincipalId,
                        targetId,
                        preview));
                _order.Enqueue(preview.TransactionId);
                while (_entries.Count > MaximumPreviews)
                    _entries.Remove(_order.Dequeue());
            }
        }

        public bool TryResolve(
            AgentRuntimeDispatchContext context,
            string transactionId,
            string previewHash,
            out string targetId,
            out HairAppearancePreview preview,
            out string reasonCode)
        {
            lock (_sync)
            {
                targetId = null;
                preview = null;
                if (!_entries.TryGetValue(
                        transactionId ?? string.Empty,
                        out Entry entry))
                {
                    reasonCode = "domain_token_required";
                    return false;
                }
                if (!string.Equals(
                        entry.ConnectionId,
                        context.ConnectionId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        entry.ClientInstanceId,
                        context.Principal.ClientInstanceId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        entry.SecurityPrincipalId,
                        context.Principal
                            .SecurityPrincipalId,
                        StringComparison.Ordinal))
                {
                    reasonCode = "principal_mismatch";
                    return false;
                }
                if (previewHash != null
                    && !string.Equals(
                        entry.Preview.PreviewHash,
                        previewHash,
                        StringComparison.OrdinalIgnoreCase))
                {
                    reasonCode =
                        "domain_revision_conflict";
                    return false;
                }
                targetId = entry.TargetId;
                preview = entry.Preview;
                reasonCode = null;
                return true;
            }
        }

        private sealed record Entry(
            string ConnectionId,
            string ClientInstanceId,
            string SecurityPrincipalId,
            string TargetId,
            HairAppearancePreview Preview);
    }

    internal sealed class RegistryMinimalSessionReferenceProvider
        : IMinimalSessionReferenceProvider
    {
        private readonly SessionSurfaceRegistry _registry;
        private readonly string _lifecycleSalt;

        public RegistryMinimalSessionReferenceProvider(
            SessionSurfaceRegistry registry,
            string lifecycleSalt)
        {
            _registry = registry
                ?? throw new ArgumentNullException(nameof(registry));
            if (string.IsNullOrWhiteSpace(lifecycleSalt))
                throw new ArgumentException(
                    "A lifecycle salt is required.",
                    nameof(lifecycleSalt));
            _lifecycleSalt = lifecycleSalt;
        }

        public MinimalSessionReference GetMinimalReference()
        {
            SessionSurfaceRegistrySnapshot snapshot =
                _registry.GetSnapshot();
            SessionSnapshot session =
                snapshot.Sessions.Count == 1
                    ? snapshot.Sessions[0]
                    : null;
            return new MinimalSessionReference
            {
                ProjectRunning = session != null,
                QualificationState =
                    session != null
                    && session.RuntimeQualification.RuntimeMode
                        != RuntimeMode.UnqualifiedDev
                        ? RuntimeQualificationState.Verified
                        : RuntimeQualificationState.Unqualified,
                LifecycleRef = session == null
                    ? null
                    : CreateLifecycleReference(
                        session.SessionId,
                        session.LifecycleGeneration)
            };
        }

        public bool TryResolveLifecycleReference(
            string lifecycleRef,
            out string sessionId,
            out ulong lifecycleGeneration)
        {
            sessionId = null;
            lifecycleGeneration = 0;
            if (string.IsNullOrWhiteSpace(lifecycleRef))
                return false;

            SessionSurfaceRegistrySnapshot snapshot =
                _registry.GetSnapshot();
            SessionSnapshot session =
                snapshot.Sessions.Count == 1
                    ? snapshot.Sessions[0]
                    : null;
            if (session == null
                || !string.Equals(
                    lifecycleRef,
                    CreateLifecycleReference(
                        session.SessionId,
                        session.LifecycleGeneration),
                    StringComparison.Ordinal))
            {
                return false;
            }

            sessionId = session.SessionId;
            lifecycleGeneration =
                session.LifecycleGeneration;
            return true;
        }

        private string CreateLifecycleReference(
            string sessionId,
            ulong generation)
        {
            string source = _lifecycleSalt.Length
                + ":" + _lifecycleSalt
                + sessionId.Length
                + ":" + sessionId
                + ":" + generation;
            byte[] hash =
                System.Security.Cryptography.SHA256
                    .HashData(
                        System.Text.Encoding.UTF8
                            .GetBytes(source));
            return Convert.ToBase64String(hash)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }
    }

    /// <summary>
    /// Production method router. The wire layer has already applied exact
    /// parameter validation; this layer still rebinds every operation to the
    /// authenticated principal and Launcher-owned session/grant/lease truth.
    /// </summary>
    internal sealed class AgentRuntimeMethodDispatcher
        : IAgentRuntimeMethodDispatcher
    {
        private const int GuaranteedBinaryDataBytes =
            AgentProtocolV1.MaximumBinaryChunkBytes
            - AgentProtocolV1.BinaryChunkMetadataLengthBytes
            - AgentProtocolV1.MaximumBinaryChunkMetadataBytes;

        private readonly SessionSurfaceRegistry _sessions;
        private readonly IMinimalSessionReferenceProvider
            _minimalSessions;
        private readonly ObservationGrantBroker _grants;
        private readonly ObservationCaptureBroker _captures;
        private readonly PixelContentHandleStore _content;
        private readonly AgentObservationEnvelopeStore
            _observationStore;
        private readonly WriteLeaseBroker _leases;
        private readonly IAgentWriteLeaseLifecycle
            _leaseLifecycle;
        private readonly AgentRuntimeRevocationCoordinator
            _revocations;
        private readonly ActionIdempotencyLedger _ledger;
        private readonly AgentRuntimeActionExecutionBroker
            _actions;
        private readonly HairAppearanceModifierTransaction
            _hair;
        private readonly IAgentHairPreviewStore _hairPreviews;
        private readonly IAgentHairDomainTargetAuthority
            _hairTargets;
        private readonly IAgentHairConsentIssuanceService
            _hairConsent;
        private readonly IAgentRuntimeHostMethodService
            _hostMethods;
        private readonly ScopedAgentRuntimeAuditLedgerManager
            _trustedAudit;

        public AgentRuntimeMethodDispatcher(
            SessionSurfaceRegistry sessions,
            IMinimalSessionReferenceProvider minimalSessions,
            ObservationGrantBroker grants,
            ObservationCaptureBroker captures,
            PixelContentHandleStore content,
            AgentObservationEnvelopeStore observationStore,
            WriteLeaseBroker leases,
            IAgentWriteLeaseLifecycle leaseLifecycle,
            AgentRuntimeRevocationCoordinator revocations,
            ActionIdempotencyLedger ledger,
            AgentRuntimeActionExecutionBroker actions,
            HairAppearanceModifierTransaction hair,
            IAgentHairPreviewStore hairPreviews,
            IAgentHairDomainTargetAuthority hairTargets,
            IAgentHairConsentIssuanceService hairConsent,
            IAgentRuntimeHostMethodService hostMethods,
            ScopedAgentRuntimeAuditLedgerManager
                trustedAudit = null)
        {
            _sessions = sessions
                ?? throw new ArgumentNullException(nameof(sessions));
            _minimalSessions = minimalSessions
                ?? throw new ArgumentNullException(
                    nameof(minimalSessions));
            _grants = grants
                ?? throw new ArgumentNullException(nameof(grants));
            _captures = captures
                ?? throw new ArgumentNullException(nameof(captures));
            _content = content
                ?? throw new ArgumentNullException(nameof(content));
            _observationStore = observationStore
                ?? throw new ArgumentNullException(
                    nameof(observationStore));
            _leases = leases
                ?? throw new ArgumentNullException(nameof(leases));
            _leaseLifecycle = leaseLifecycle
                ?? throw new ArgumentNullException(
                    nameof(leaseLifecycle));
            _revocations = revocations
                ?? throw new ArgumentNullException(
                    nameof(revocations));
            _ledger = ledger
                ?? throw new ArgumentNullException(nameof(ledger));
            _actions = actions
                ?? throw new ArgumentNullException(nameof(actions));
            _hair = hair
                ?? throw new ArgumentNullException(nameof(hair));
            _hairPreviews = hairPreviews
                ?? throw new ArgumentNullException(
                    nameof(hairPreviews));
            _hairTargets = hairTargets
                ?? throw new ArgumentNullException(
                    nameof(hairTargets));
            _hairConsent = hairConsent
                ?? throw new ArgumentNullException(
                    nameof(hairConsent));
            _hostMethods = hostMethods
                ?? throw new ArgumentNullException(
                    nameof(hostMethods));
            _trustedAudit = trustedAudit;
        }

        public async Task<AgentRuntimeDispatchResult> DispatchAsync(
            AgentRuntimeDispatchContext context,
            AgentJsonRpcRequest request,
            CancellationToken cancellationToken)
        {
            try
            {
                switch (request.Method)
                {
                    case AgentCapabilitiesV1.SessionStatus:
                    case AgentCapabilitiesV1.SessionDiscover:
                        return AgentRuntimeDispatchResult
                            .Completed(
                                _minimalSessions
                                    .GetMinimalReference());
                    case AgentCapabilitiesV1.ListWindows:
                        return ListWindows(
                            context,
                            Read<WindowListParametersV1>(
                                request));
                    case AgentCapabilitiesV1.GetWindow:
                        return GetWindow(
                            context,
                            Read<WindowTargetParametersV1>(
                                request));
                    case AgentCapabilitiesV1.GetWindowState:
                        return await GetWindowStateAsync(
                            context,
                            Read<WindowTargetParametersV1>(
                                request),
                            cancellationToken)
                            .ConfigureAwait(false);
                    case AgentCapabilitiesV1.ListApps:
                        return AgentRuntimeDispatchResult
                            .Completed(
                                AgentAppCatalogV1.CreateList(
                                    _sessions
                                        .GetSnapshot()
                                        .Sessions
                                        .Count > 0));
                    case AgentCapabilitiesV1.LaunchApp:
                    case AgentCapabilitiesV1.TraceExport:
                        return await _hostMethods.DispatchAsync(
                            context,
                            request,
                            cancellationToken)
                            .ConfigureAwait(false);
                    case AgentCapabilitiesV1.SessionAttach:
                    case AgentCapabilitiesV1.SessionDetach:
                        return BindSession(
                            context,
                            request.Method,
                            Read<SessionBindingParametersV1>(
                                request));
                    case AgentCapabilitiesV1.LeaseAcquire:
                        return AcquireLease(
                            context,
                            Read<LeaseAcquireParametersV1>(
                                request));
                    case AgentCapabilitiesV1.LeaseRenew:
                        return RenewLease(
                            context,
                            Read<LeaseRenewParametersV1>(
                                request));
                    case AgentCapabilitiesV1.LeaseRelease:
                        return ReleaseLease(
                            context,
                            Read<LeaseReleaseParametersV1>(
                                request));
                    case AgentMethodsV1.ObservationGrantIssue:
                        return IssueGrant(
                            context,
                            Read<
                                ObservationGrantIssueParametersV1>(
                                request));
                    case AgentMethodsV1.ObservationGrantRevoke:
                        return RevokeGrant(
                            context,
                            Read<
                                ObservationGrantRevokeParametersV1>(
                                request));
                    case AgentMethodsV1.ObservationCapture:
                        return await CaptureAsync(
                            context,
                            Read<
                                ObservationCaptureParametersV1>(
                                request),
                            AgentMethodsV1.ObservationCapture,
                            cancellationToken)
                            .ConfigureAwait(false);
                    case AgentMethodsV1.ObservationGet:
                        return GetObservation(
                            context,
                            Read<
                                ObservationReferenceParametersV1>(
                                request));
                    case AgentMethodsV1.ObservationAck:
                        return AcknowledgeObservation(
                            context,
                            Read<
                                ObservationReferenceParametersV1>(
                                request));
                    case AgentMethodsV1.ContentRead:
                        return ReadContent(
                            context,
                            Read<ContentReadRequest>(
                                request));
                    case AgentMethodsV1.ActionGet:
                        return GetAction(
                            context,
                            Read<ActionGetParametersV1>(
                                request));
                    case AgentMethodsV1.HairInspect:
                        return await InspectHairAsync(
                            context,
                            Read<HairInspectParametersV1>(
                                request),
                            cancellationToken)
                            .ConfigureAwait(false);
                    case AgentMethodsV1.HairPreview:
                        return await PreviewHairAsync(
                            context,
                            Read<HairPreviewParametersV1>(
                                request),
                            cancellationToken)
                            .ConfigureAwait(false);
                    case AgentMethodsV1.HairConsent:
                        return await RequestHairConsentAsync(
                            context,
                            Read<HairConsentParametersV1>(
                                request),
                            cancellationToken)
                            .ConfigureAwait(false);
                    case AgentMethodsV1.HairReconcile:
                        return await ReconcileHairAsync(
                            context,
                            Read<HairReconcileParametersV1>(
                                request),
                            cancellationToken)
                            .ConfigureAwait(false);
                    default:
                        if (IsActionMethod(request.Method))
                        {
                            ActionEnvelope action =
                                Read<ActionEnvelope>(request);
                            AgentMethodsV1.TryGet(
                                request.Method,
                                out AgentMethodDefinition method);
                            AgentRuntimeActionExecutionResult execution =
                                await _actions.ExecuteAsync(
                                    context,
                                    action,
                                    method.RequiredCapability,
                                    cancellationToken)
                                .ConfigureAwait(false);
                            ActionReceipt receipt =
                                execution.Receipt;
                            AgentRuntimeResponseCompletion
                                responseCompletion =
                                    execution
                                        .ResponseCompletion;
                            if (string.Equals(
                                    receipt.ReasonCode,
                                    "shutdown_requested",
                                    StringComparison.Ordinal)
                                && responseCompletion == null)
                            {
                                if (execution
                                        .ResponseDeliveryDisposition
                                    == AgentRuntimeResponseDeliveryDisposition
                                        .Committed)
                                {
                                    return AgentRuntimeDispatchResult
                                        .Completed(receipt);
                                }
                                return AgentRuntimeDispatchResult
                                    .Rejected(
                                        "reconcile_required",
                                        ReconcileKind
                                            .ManualRequired);
                            }
                            try
                            {
                                return AgentRuntimeDispatchResult
                                    .Completed(
                                        receipt,
                                        responseCompletion:
                                            responseCompletion);
                            }
                            catch
                            {
                                responseCompletion?.Abort();
                                throw;
                            }
                        }
                        return AgentRuntimeDispatchResult
                            .Rejected("operation_invalid");
                }
            }
            catch (OperationCanceledException)
                when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (InvalidOperationException exception)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        exception.Message));
            }
            catch (JsonException)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "arguments_invalid");
            }
            catch
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
        }

        private AgentRuntimeDispatchResult ListWindows(
            AgentRuntimeDispatchContext context,
            WindowListParametersV1 parameters)
        {
            if (!AuthorizeSessionMetadata(
                    context,
                    parameters,
                    out ObservationGrant grant,
                    out SessionSnapshot session,
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    reasonCode);
            }
            SurfaceDescriptor[] surfaces = session.Surfaces
                .Where(surface =>
                    grant.TargetScope.Contains(
                        surface.TargetId,
                        StringComparer.Ordinal))
                .Select(surface => surface.ToContract())
                .ToArray();
            return AgentRuntimeDispatchResult.Completed(
                new
                {
                    sessionId = session.SessionId,
                    lifecycleGeneration =
                        session.LifecycleGeneration,
                    surfaces
                });
        }

        private AgentRuntimeDispatchResult GetWindow(
            AgentRuntimeDispatchContext context,
            WindowTargetParametersV1 parameters)
        {
            if (!AuthorizeTarget(
                    context,
                    parameters,
                    ObservationDataScopesV1.WindowMetadata,
                    out SessionSnapshot session,
                    out SessionSurfaceSnapshot surface,
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    reasonCode);
            }
            return AgentRuntimeDispatchResult.Completed(
                new
                {
                    sessionId = session.SessionId,
                    lifecycleGeneration =
                        session.LifecycleGeneration,
                    surface = surface.ToContract()
                });
        }

        private async Task<AgentRuntimeDispatchResult>
            GetWindowStateAsync(
                AgentRuntimeDispatchContext context,
                WindowTargetParametersV1 parameters,
                CancellationToken cancellationToken)
        {
            if (string.Equals(
                    parameters.DataScope,
                    ObservationDataScopesV1.WindowMetadata,
                    StringComparison.Ordinal))
            {
                if (!AuthorizeTarget(
                        context,
                        parameters,
                        ObservationDataScopesV1.WindowMetadata,
                        out SessionSnapshot session,
                        out SessionSurfaceSnapshot surface,
                        out string reasonCode))
                {
                    return AgentRuntimeDispatchResult.Rejected(
                        reasonCode);
                }
                return AgentRuntimeDispatchResult.Completed(
                    new
                    {
                        sessionId = session.SessionId,
                        lifecycleGeneration =
                            session.LifecycleGeneration,
                        targetId = surface.TargetId,
                        visible = surface.Visible,
                        minimized = surface.Minimized,
                        active = surface.Active,
                        blockingModalKind =
                            session.BlockingModalKind,
                        humanReauthorizationRequired =
                            session
                                .HumanReauthorizationRequired,
                        desktopAvailable =
                            session.DesktopAvailable,
                        surfaceEpoch =
                            surface.SurfaceEpoch,
                        coordinateSpaceVersion =
                            surface
                                .CoordinateSpaceVersion,
                        focusEpoch = session.FocusEpoch,
                        modalEpoch = session.ModalEpoch,
                        semanticGeneration =
                            surface.SemanticGeneration,
                        documentGeneration =
                            surface.DocumentGeneration,
                        panelInstanceId =
                            session
                                .PanelInstanceIdForTarget(
                                    surface.TargetId)
                    });
            }
            if (!string.Equals(
                    parameters.DataScope,
                    ObservationDataScopesV1.Pixels,
                    StringComparison.Ordinal))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "unsupported_for_surface");
            }
            return await CaptureAsync(
                context,
                new ObservationCaptureParametersV1
                {
                    ObservationGrantId =
                        parameters.ObservationGrantId,
                    SessionId = parameters.SessionId,
                    TargetId = parameters.TargetId,
                    DataScope = parameters.DataScope,
                    AllowValidatedFlashKeyframeFallback =
                        false
                },
                AgentCapabilitiesV1.GetWindowState,
                cancellationToken).ConfigureAwait(false);
        }

        private AgentRuntimeDispatchResult BindSession(
            AgentRuntimeDispatchContext context,
            string method,
            SessionBindingParametersV1 parameters)
        {
            SessionSnapshot session = _sessions.GetSnapshot()
                .FindSession(parameters.SessionId);
            if (session == null)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "session_not_found");
            }
            if (session.LifecycleGeneration
                != parameters.LifecycleGeneration)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "stale_lifecycle");
            }
            bool attaching = string.Equals(
                method,
                AgentCapabilitiesV1.SessionAttach,
                StringComparison.Ordinal);
            bool bound = attaching
                ? _revocations.TryAttachSession(
                    context.ConnectionId,
                    context.Principal,
                    session.SessionId,
                    session.LifecycleGeneration,
                    out string reasonCode)
                : _revocations.TryDetachSession(
                    context.ConnectionId,
                    context.Principal,
                    session.SessionId,
                    session.LifecycleGeneration,
                    out reasonCode);
            if (!bound)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            if (attaching
                && _trustedAudit != null
                && !_trustedAudit
                    .TryRebindConnectionLifecycle(
                        context.ConnectionId,
                        context.Principal,
                        session.SessionId,
                        session.LifecycleGeneration,
                        out reasonCode))
            {
                _revocations.TryDetachSession(
                    context.ConnectionId,
                    context.Principal,
                    session.SessionId,
                    session.LifecycleGeneration,
                    out _);
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            return AgentRuntimeDispatchResult.Completed(
                new
                {
                    sessionId = session.SessionId,
                    lifecycleGeneration =
                        session.LifecycleGeneration,
                    attached = attaching
                });
        }

        private AgentRuntimeDispatchResult IssueGrant(
            AgentRuntimeDispatchContext context,
            ObservationGrantIssueParametersV1 parameters)
        {
            if (!_minimalSessions
                    .TryResolveLifecycleReference(
                        parameters.LifecycleRef,
                        out string sessionId,
                        out ulong lifecycleGeneration))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "stale_lifecycle");
            }
            SessionSnapshot resolvedSession = _sessions
                .GetSnapshot()
                .FindSession(sessionId);
            if (resolvedSession == null
                || resolvedSession.LifecycleGeneration
                    != lifecycleGeneration)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "stale_lifecycle");
            }
            if (!_revocations.TryCaptureSessionFence(
                    context.ConnectionId,
                    context.Principal,
                    sessionId,
                    lifecycleGeneration,
                    out AgentRuntimeRevocationCoordinator
                        .SessionFenceTicket fenceTicket,
                    out string fenceReason))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        fenceReason
                            ?? "credential_revoked"));
            }

            string[] targetIds;
            HashSet<SurfaceKind> requestedKinds = null;
            if (parameters.TargetKinds != null)
            {
                requestedKinds = new HashSet<SurfaceKind>();
                foreach (string value in parameters.TargetKinds)
                {
                    if (!AgentSurfaceKindsV1.TryParse(
                            value,
                            out SurfaceKind kind))
                    {
                        return AgentRuntimeDispatchResult.Rejected(
                            "arguments_invalid");
                    }
                    requestedKinds.Add(kind);
                }
                targetIds = resolvedSession.Surfaces
                    .Where(surface =>
                        requestedKinds.Contains(surface.Kind)
                        && surface.SafetyKind
                            == AgentTargetSafetyKind.RuntimeOwned
                        && context.Principal.AllowsTarget(
                            surface.TargetId))
                    .Select(surface => surface.TargetId)
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .Take(
                        AgentProtocolV1
                            .MaximumTargetScopeItems
                        + 1)
                    .ToArray();
                if (targetIds.Length == 0
                    || targetIds.Length
                        > AgentProtocolV1
                            .MaximumTargetScopeItems)
                {
                    return AgentRuntimeDispatchResult.Rejected(
                        "observation_scope_mismatch");
                }
            }
            else
            {
                targetIds = parameters.TargetIds?.ToArray()
                    ?? Array.Empty<string>();
            }

            ObservationGrant grant = _grants.Issue(
                new ObservationGrantRequest
                {
                    CredentialId =
                        context.Principal.CredentialId,
                    ClientInstanceId =
                        context.Principal.ClientInstanceId,
                    SessionId = sessionId,
                    Targets = targetIds
                        .Select(target =>
                            new ObservationTargetScope
                            {
                                TargetId = target
                            })
                        .ToArray(),
                    DataScopes = parameters.DataScopes,
                    RequestedLifetime =
                        TimeSpan.FromMilliseconds(
                            parameters.RequestedTtlMs),
                    ConsentReceipt =
                        parameters.ConsentReceipt,
                    AllowEphemeralKeyframes =
                        parameters
                            .AllowEphemeralKeyframes,
                    AllowPersistence =
                        parameters.AllowPersistence,
                    AllowExport =
                        parameters.AllowExport
                });
            if (!_revocations.TryTrackGrant(
                    fenceTicket,
                    grant,
                    out fenceReason))
            {
                _grants.Revoke(
                    grant.ObservationGrantId,
                    fenceReason
                        ?? "credential_revoked");
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        fenceReason
                            ?? "credential_revoked"));
            }
            SessionSnapshot session = _sessions.GetSnapshot()
                .FindSession(sessionId);
            if (session == null
                || session.LifecycleGeneration
                    != lifecycleGeneration)
            {
                _revocations.RevokeGrantAndForget(
                    context.ConnectionId,
                    grant.ObservationGrantId,
                    "stale_lifecycle");
                return AgentRuntimeDispatchResult.Rejected(
                    "stale_lifecycle");
            }
            bool targetsStillExact = targetIds.All(
                targetId =>
                {
                    SessionSurfaceSnapshot surface =
                        session.Surfaces.FirstOrDefault(
                            candidate =>
                                string.Equals(
                                    candidate.TargetId,
                                    targetId,
                                    StringComparison.Ordinal));
                    return surface != null
                        && surface.SafetyKind
                            == AgentTargetSafetyKind.RuntimeOwned
                        && context.Principal.AllowsTarget(
                            targetId)
                        && (requestedKinds == null
                            || requestedKinds.Contains(
                                surface.Kind));
            });
            if (!targetsStillExact)
            {
                _revocations.RevokeGrantAndForget(
                    context.ConnectionId,
                    grant.ObservationGrantId,
                    "stale_observation");
                return AgentRuntimeDispatchResult.Rejected(
                    "stale_observation");
            }
            if (!_revocations.IsSessionFenceCurrent(
                    fenceTicket,
                    out fenceReason))
            {
                _revocations.RevokeGrantAndForget(
                    context.ConnectionId,
                    grant.ObservationGrantId,
                    fenceReason
                        ?? "credential_revoked");
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        fenceReason
                            ?? "credential_revoked"));
            }
            if (grant.State
                    != CF7Launcher.AgentRuntime.Security
                        .ObservationGrantState.Active)
            {
                _revocations.RevokeGrantAndForget(
                    context.ConnectionId,
                    grant.ObservationGrantId,
                    "stale_observation");
                return AgentRuntimeDispatchResult.Rejected(
                    "stale_observation");
            }
            if (!TryAppendTrustedAudit(
                    context,
                    session.SessionId,
                    session.LifecycleGeneration,
                    AgentCapabilitiesV1
                        .ObservationGrantManage,
                    AgentRuntimeAuditEventTypes
                        .ObservationGrantIssued,
                    observationGrantId:
                        grant.ObservationGrantId,
                    targetScope:
                        grant.TargetScope,
                    dataScope:
                        grant.DataScope,
                    allowExport:
                        grant.AllowExport,
                    allowPersistence:
                        grant.AllowPersistence,
                    state:
                        grant.State.ToString(),
                    consentReceipt:
                        grant.ConsentReceipt))
            {
                _revocations.RevokeGrantAndForget(
                    context.ConnectionId,
                    grant.ObservationGrantId,
                    "audit_unavailable");
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            return AgentRuntimeDispatchResult.Completed(
                ToContract(grant, session));
        }

        private AgentRuntimeDispatchResult RevokeGrant(
            AgentRuntimeDispatchContext context,
            ObservationGrantRevokeParametersV1 parameters)
        {
            SessionSnapshot session = _sessions
                .GetSnapshot()
                .Sessions
                .SingleOrDefault();
            if (!_grants.RevokeOwned(
                    parameters.ObservationGrantId,
                    context.Principal.ClientInstanceId,
                    context.Principal.SecurityPrincipalId,
                    "client_revoked",
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            if (session == null
                || !TryAppendTrustedAudit(
                    context,
                    session.SessionId,
                    session.LifecycleGeneration,
                    AgentCapabilitiesV1
                        .ObservationGrantManage,
                    AgentRuntimeAuditEventTypes
                        .ObservationGrantRevoked,
                    observationGrantId:
                        parameters.ObservationGrantId,
                    state: "Revoked",
                    reasonCode: "client_revoked"))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            return AgentRuntimeDispatchResult.Completed(
                new
                {
                    observationGrantId =
                        parameters.ObservationGrantId,
                    revoked = true
                });
        }

        private async Task<AgentRuntimeDispatchResult> CaptureAsync(
            AgentRuntimeDispatchContext context,
            ObservationCaptureParametersV1 parameters,
            string auditConsentPurpose,
            CancellationToken cancellationToken)
        {
            ObservationCaptureOutcome capture =
                await _captures.CaptureAsync(
                    new ObservationCaptureRequest
                    {
                        ObservationGrantId =
                            parameters
                                .ObservationGrantId,
                        ClientInstanceId =
                            context.Principal
                                .ClientInstanceId,
                        SecurityPrincipalId =
                            context.Principal
                                .SecurityPrincipalId,
                        SessionId = parameters.SessionId,
                        TargetId = parameters.TargetId,
                        DataScope = parameters.DataScope,
                        AllowValidatedFlashKeyframeFallback =
                            parameters
                                .AllowValidatedFlashKeyframeFallback
                    },
                    cancellationToken)
                .ConfigureAwait(false);
            if (!capture.Success)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        capture.ReasonCode));
            }
            _observationStore.Store(
                context,
                parameters.DataScope,
                capture.Envelope);
            if (!TryAppendTrustedAudit(
                    context,
                    capture.Envelope.SessionId,
                    capture.Envelope
                        .LifecycleGeneration,
                    auditConsentPurpose,
                    AgentRuntimeAuditEventTypes
                        .ObservationCaptured,
                    observationGrantId:
                        capture.Envelope
                            .ObservationGrantId,
                    correlationId:
                        capture.Envelope.ObservationId,
                    targetScope:
                        new[]
                        {
                            capture.Envelope.TargetId
                        },
                    dataScope:
                        new[] { parameters.DataScope },
                    state: "Captured"))
            {
                _observationStore.TryAcknowledge(
                    context,
                    parameters.ObservationGrantId,
                    parameters.SessionId,
                    capture.Envelope.ObservationId,
                    out _,
                    out _,
                    out _);
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            return AgentRuntimeDispatchResult.Completed(
                capture.Envelope);
        }

        private AgentRuntimeDispatchResult GetObservation(
            AgentRuntimeDispatchContext context,
            ObservationReferenceParametersV1 parameters)
        {
            if (!_observationStore.TryGet(
                    context,
                    parameters.ObservationGrantId,
                    parameters.SessionId,
                    parameters.ObservationId,
                    out ObservationEnvelope envelope,
                    out string dataScope,
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            if (!_captures.TryUseObservation(
                    new ObservationUseRequest
                    {
                        ObservationId =
                            envelope.ObservationId,
                        ObservationGrantId =
                            envelope.ObservationGrantId,
                        ClientInstanceId =
                            context.Principal
                                .ClientInstanceId,
                        SecurityPrincipalId =
                            context.Principal
                                .SecurityPrincipalId,
                        SessionId = envelope.SessionId,
                        TargetId = envelope.TargetId,
                        DataScope = dataScope
                    },
                    false,
                    out reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            return AgentRuntimeDispatchResult.Completed(envelope);
        }

        private AgentRuntimeDispatchResult AcknowledgeObservation(
            AgentRuntimeDispatchContext context,
            ObservationReferenceParametersV1 parameters)
        {
            if (!_observationStore.TryAcknowledge(
                    context,
                    parameters.ObservationGrantId,
                    parameters.SessionId,
                    parameters.ObservationId,
                    out ObservationEnvelope envelope,
                    out string dataScope,
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            if (!_captures.TryAcknowledgeObservation(
                    new ObservationUseRequest
                    {
                        ObservationId =
                            envelope.ObservationId,
                        ObservationGrantId =
                            envelope.ObservationGrantId,
                        ClientInstanceId =
                            context.Principal
                                .ClientInstanceId,
                        SecurityPrincipalId =
                            context.Principal
                                .SecurityPrincipalId,
                        SessionId = envelope.SessionId,
                        TargetId = envelope.TargetId,
                        DataScope = dataScope
                    },
                    out reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            return AgentRuntimeDispatchResult.Completed(
                new
                {
                    observationId =
                        parameters.ObservationId,
                    acknowledged = true
                });
        }

        private AgentRuntimeDispatchResult ReadContent(
            AgentRuntimeDispatchContext context,
            ContentReadRequest parameters)
        {
            if (!_observationStore.TryResolveContent(
                    context,
                    parameters.Handle,
                    out PixelContentReadRequest binding,
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            binding = new PixelContentReadRequest
            {
                Handle = binding.Handle,
                ClientInstanceId =
                    binding.ClientInstanceId,
                SecurityPrincipalId =
                    binding.SecurityPrincipalId,
                SessionId = binding.SessionId,
                ObservationGrantId =
                    binding.ObservationGrantId,
                ObservationId =
                    binding.ObservationId,
                Offset = parameters.Offset,
                MaximumBytes = Math.Min(
                    parameters.Count,
                    GuaranteedBinaryDataBytes)
            };
            PixelContentReadOutcome read =
                _content.Read(binding);
            if (!read.Success)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        read.ReasonCode));
            }
            var metadata = new BinaryChunkMetadata
            {
                Handle = parameters.Handle,
                Offset = read.Offset,
                TotalLength = read.TotalBytes,
                Final = read.Final,
                ContentHash = read.ContentHash
            };
            return AgentRuntimeDispatchResult.Completed(
                new
                {
                    handle = parameters.Handle,
                    offset = read.Offset,
                    totalLength = read.TotalBytes,
                    returnedBytes = read.Content.Length,
                    final = read.Final,
                    contentHash = read.ContentHash
                },
                new AgentRuntimeBinaryChunk(
                    metadata,
                    read.Content));
        }

        private AgentRuntimeDispatchResult AcquireLease(
            AgentRuntimeDispatchContext context,
            LeaseAcquireParametersV1 parameters)
        {
            if (context.Principal.SessionMode
                    == AgentSessionMode.PlayerAssist
                && (string.Equals(
                        parameters.Kind,
                        "shutdown",
                        StringComparison.Ordinal)
                    || string.Equals(
                        parameters.Kind,
                        "structured_action",
                        StringComparison.Ordinal)))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "consent_required");
            }
            if (context.Principal.SessionMode
                    == AgentSessionMode.PlayerAssist
                && (!CanonicalJsonV1.FixedTimeEqualsSha256(
                        context
                            .HostAttestedArgumentBoundsHash,
                        parameters.ArgumentBoundsHash)))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "argument_bounds_invalid");
            }
            SessionSnapshot session = _sessions.GetSnapshot()
                .FindSession(parameters.SessionId);
            if (session == null
                || session.LifecycleGeneration == 0)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "session_not_found");
            }
            if (parameters.Capabilities.Any(
                    capability =>
                        !session.Capabilities.Contains(
                            capability,
                            StringComparer.Ordinal)))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "capability_denied");
            }
            if (!_revocations.TryCaptureSessionFence(
                    context.ConnectionId,
                    context.Principal,
                    session.SessionId,
                    session.LifecycleGeneration,
                    out AgentRuntimeRevocationCoordinator
                        .SessionFenceTicket fenceTicket,
                    out string fenceReason))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        fenceReason
                            ?? "credential_revoked"));
            }
            WriteLeaseKind leaseKind =
                parameters.Kind switch
                {
                    "gui_input" =>
                        WriteLeaseKind.GuiInput,
                    "domain_transaction" =>
                        WriteLeaseKind
                            .DomainTransaction,
                    "structured_action" =>
                        WriteLeaseKind
                            .StructuredAction,
                    "shutdown" =>
                        WriteLeaseKind.Shutdown,
                    _ => throw new InvalidOperationException(
                        "arguments_invalid")
                };
            WriteLease lease = _leases.Acquire(
                new WriteLeaseRequest
                {
                    CredentialId =
                        context.Principal.CredentialId,
                    ClientInstanceId =
                        context.Principal.ClientInstanceId,
                    SessionId = parameters.SessionId,
                    LifecycleGeneration =
                        session.LifecycleGeneration,
                    Kind = leaseKind,
                    Capabilities = parameters.Capabilities,
                    TargetScope = parameters.TargetScope,
                    RequestedLifetime =
                        TimeSpan.FromMilliseconds(
                            parameters.RequestedTtlMs),
                    RequestedActionLimit =
                        parameters.RequestedActionLimit,
                    ConsentReceipt =
                        parameters.ConsentReceipt,
                    ArgumentBoundsHash =
                        parameters.ArgumentBoundsHash,
                    PreviewHash = parameters.PreviewHash,
                    ExpectedRevision =
                        parameters.ExpectedRevision,
                    Operation = leaseKind switch
                    {
                        WriteLeaseKind.Shutdown =>
                            AgentCapabilitiesV1
                                .SessionShutdown,
                        WriteLeaseKind.StructuredAction =>
                            AgentCapabilitiesV1.PanelOpen,
                        _ => parameters.Operation
                    }
                });
            if (!_leaseLifecycle.TryActivate(
                    lease,
                    out string reasonCode))
            {
                _leases.Revoke(
                    lease.LeaseId,
                    reasonCode
                        ?? "input_guard_unhealthy");
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            if (!_revocations.TryTrackLease(
                    fenceTicket,
                    lease,
                    out fenceReason))
            {
                return RejectNewLease(
                    lease,
                    fenceReason
                        ?? "credential_revoked");
            }
            SessionSnapshot currentSession =
                _sessions.GetSnapshot()
                    .FindSession(parameters.SessionId);
            if (currentSession == null
                || currentSession.LifecycleGeneration
                    != lease.LifecycleGeneration)
            {
                return RejectNewLease(
                    lease,
                    "stale_lifecycle");
            }
            if (lease.Capabilities.Any(
                    capability =>
                        !currentSession.Capabilities.Contains(
                            capability,
                            StringComparer.Ordinal)))
            {
                return RejectNewLease(
                    lease,
                    "capability_denied");
            }
            bool targetsStillExact = lease.TargetScope.All(
                targetId =>
                {
                    SessionSurfaceSnapshot surface =
                        currentSession.Surfaces.FirstOrDefault(
                            candidate => string.Equals(
                                candidate.TargetId,
                                targetId,
                                StringComparison.Ordinal));
                    return surface != null
                        && surface.SafetyKind
                            == AgentTargetSafetyKind.RuntimeOwned
                        && context.Principal.AllowsTarget(
                            targetId)
                        && (!(lease.Kind
                                is WriteLeaseKind.Shutdown
                                or WriteLeaseKind.StructuredAction)
                            || surface.Kind
                                == SurfaceKind.Launcher);
                });
            if (!targetsStillExact)
            {
                return RejectNewLease(
                    lease,
                    "stale_observation");
            }
            if (!_revocations.IsSessionFenceCurrent(
                    fenceTicket,
                    out fenceReason))
            {
                return RejectNewLease(
                    lease,
                    fenceReason
                        ?? "credential_revoked");
            }
            if (lease.State != WriteLeaseState.Active)
            {
                return RejectNewLease(
                    lease,
                    lease.RevokeReason
                        ?? "lease_revoked");
            }
            string auditPurpose =
                LeaseConsentPurpose(lease);
            if (!TryAppendTrustedAudit(
                    context,
                    lease.SessionId,
                    lease.LifecycleGeneration,
                    auditPurpose,
                    AgentRuntimeAuditEventTypes
                        .WriteLeaseAcquired,
                    leaseId: lease.LeaseId,
                    capability:
                        lease.Capabilities.Count == 1
                            ? lease.Capabilities[0]
                            : null,
                    targetScope:
                        lease.TargetScope,
                    state:
                        lease.State.ToString(),
                    consentReceipt:
                        lease.ConsentReceipt))
            {
                return RejectNewLease(
                    lease,
                    "audit_unavailable");
            }
            return AgentRuntimeDispatchResult.Completed(
                ToContract(lease));
        }

        private AgentRuntimeDispatchResult RejectNewLease(
            WriteLease lease,
            string reasonCode)
        {
            string reason = string.IsNullOrWhiteSpace(
                    reasonCode)
                ? "credential_revoked"
                : reasonCode;
            _revocations.RevokeLeaseAndCancelQueuedActions(
                lease.SessionId,
                lease.LeaseId,
                reason);
            _leaseLifecycle.Release(lease);
            return AgentRuntimeDispatchResult.Rejected(
                AgentRuntimeGateway.NormalizeReason(reason));
        }

        private AgentRuntimeDispatchResult RenewLease(
            AgentRuntimeDispatchContext context,
            LeaseRenewParametersV1 parameters)
        {
            if (!_leases.TryRenewDeveloper(
                    parameters.LeaseId,
                    context.Principal.ClientInstanceId,
                    context.Principal.SecurityPrincipalId,
                    TimeSpan.FromMilliseconds(
                        parameters.RequestedTtlMs),
                    out WriteLease lease,
                    out string reasonCode))
            {
                CleanupInactiveLease(
                    context,
                    lease);
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            SessionSnapshot session = _sessions
                .GetSnapshot()
                .FindSession(lease.SessionId);
            if (session == null
                || !TryAppendTrustedAudit(
                    context,
                    lease.SessionId,
                    lease.LifecycleGeneration,
                    LeaseConsentPurpose(lease),
                    AgentRuntimeAuditEventTypes
                        .WriteLeaseRenewed,
                    leaseId: lease.LeaseId,
                    state: lease.State.ToString(),
                    consentReceipt:
                        lease.ConsentReceipt))
            {
                _revocations
                    .RevokeLeaseAndCancelQueuedActions(
                        lease.SessionId,
                        lease.LeaseId,
                        "audit_unavailable");
                _leaseLifecycle.Release(lease);
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            return AgentRuntimeDispatchResult.Completed(
                ToContract(lease));
        }

        private AgentRuntimeDispatchResult ReleaseLease(
            AgentRuntimeDispatchContext context,
            LeaseReleaseParametersV1 parameters)
        {
            if (!_leases.Release(
                    parameters.LeaseId,
                    context.Principal.ClientInstanceId,
                    context.Principal.SecurityPrincipalId,
                    out WriteLease lease,
                    out string reasonCode))
            {
                CleanupInactiveLease(
                    context,
                    lease);
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode ?? "lease_owner_mismatch"));
            }
            _revocations.UntrackLeaseAndCancelQueuedActions(
                lease.SessionId,
                lease.LeaseId,
                "client_released");
            _leaseLifecycle.Release(lease);
            if (!TryAppendTrustedAudit(
                    context,
                    lease.SessionId,
                    lease.LifecycleGeneration,
                    LeaseConsentPurpose(lease),
                    AgentRuntimeAuditEventTypes
                        .WriteLeaseReleased,
                    leaseId: lease.LeaseId,
                    state: lease.State.ToString(),
                    reasonCode: "client_released",
                    consentReceipt:
                        lease.ConsentReceipt))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "internal_error");
            }
            return AgentRuntimeDispatchResult.Completed(
                new
                {
                    leaseId = parameters.LeaseId,
                    released = true
                });
        }

        private void CleanupInactiveLease(
            AgentRuntimeDispatchContext context,
            WriteLease lease)
        {
            if (context?.Principal == null
                || lease == null
                || lease.State == WriteLeaseState.Active
                || lease.ActionExecutionPending
                || lease.ShutdownDeliveryPending
                || lease.ShutdownDeliveryWriteOwned
                || lease.ShutdownDeliveryCommitted
                || !string.Equals(
                    lease.OwnerClientId,
                    context.Principal.ClientInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    lease.SecurityPrincipalId,
                    context.Principal.SecurityPrincipalId,
                    StringComparison.Ordinal))
            {
                return;
            }
            string reason =
                lease.RevokeReason ?? "lease_inactive";
            _revocations.UntrackLeaseAndCancelQueuedActions(
                lease.SessionId,
                lease.LeaseId,
                reason);
            _leaseLifecycle.Release(lease);
        }

        private AgentRuntimeDispatchResult GetAction(
            AgentRuntimeDispatchContext context,
            ActionGetParametersV1 parameters)
        {
            ActionLookupResult lookup = _ledger.Get(
                context.Principal.SecurityPrincipalId,
                parameters.SessionId,
                parameters.ActionId);
            if (lookup.Kind
                == ActionLookupKind.NotFoundProven)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "action_not_found");
            }
            if (lookup.Kind
                == ActionLookupKind.ProvenNotDispatched)
            {
                return AgentRuntimeDispatchResult.Completed(
                    new
                    {
                        actionId = parameters.ActionId,
                        status = "not_dispatched"
                    });
            }
            if (lookup.Receipt?.ContractReceipt != null)
            {
                return AgentRuntimeDispatchResult.Completed(
                    lookup.Receipt.ContractReceipt);
            }
            // A receipt without a committed scoped-audit terminal fact cannot
            // acquire a synthetic sequence during lookup. The caller must
            // reconcile through an authoritative path.
            return AgentRuntimeDispatchResult.Rejected(
                "reconcile_required");
        }

        private async Task<AgentRuntimeDispatchResult>
            InspectHairAsync(
                AgentRuntimeDispatchContext context,
                HairInspectParametersV1 parameters,
                CancellationToken cancellationToken)
        {
            HairSaveBinding binding = ToBinding(
                parameters.Binding);
            if (!AuthorizeHair(
                    context,
                    parameters.ObservationGrantId,
                    parameters.TargetId,
                    binding.SessionId,
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    reasonCode);
            }
            HairInspectResult inspect =
                await _hair.InspectAsync(
                    binding,
                    cancellationToken)
                .ConfigureAwait(false);
            return inspect.Success
                ? AgentRuntimeDispatchResult.Completed(inspect)
                : AgentRuntimeDispatchResult.Rejected(
                    NormalizeHairReason(
                        inspect.ReasonCode));
        }

        private async Task<AgentRuntimeDispatchResult>
            PreviewHairAsync(
                AgentRuntimeDispatchContext context,
                HairPreviewParametersV1 parameters,
                CancellationToken cancellationToken)
        {
            HairSaveBinding binding = ToBinding(
                parameters.Binding);
            if (!AuthorizeHair(
                    context,
                    parameters.ObservationGrantId,
                    parameters.TargetId,
                    binding.SessionId,
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    reasonCode);
            }
            HairPreviewResult preview =
                await _hair.PreviewAsync(
                    new HairPreviewRequest(
                        binding,
                        parameters.HairIdentifier,
                        parameters.ExpectedCurrentHair,
                        parameters.ExpectedRevision,
                        parameters.ExpectedGeneration,
                        parameters.ExpectedSnapshotHash),
                    cancellationToken)
                .ConfigureAwait(false);
            if (preview.Outcome
                != HairTransactionOutcome.PreviewReady)
            {
                return AgentRuntimeDispatchResult.Rejected(
                    NormalizeHairReason(
                        preview.ReasonCode));
            }
            _hairPreviews.Store(
                context,
                parameters.TargetId,
                preview.Preview);
            return AgentRuntimeDispatchResult.Completed(
                preview.Preview);
        }

        private async Task<AgentRuntimeDispatchResult>
            RequestHairConsentAsync(
                AgentRuntimeDispatchContext context,
                HairConsentParametersV1 parameters,
                CancellationToken cancellationToken)
        {
            if (!_hairPreviews.TryResolve(
                    context,
                    parameters.TransactionId,
                    parameters.PreviewHash,
                    out string previewTargetId,
                    out HairAppearancePreview preview,
                    out string reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            if (!string.Equals(
                    parameters.SessionId,
                    preview.Binding.SessionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    parameters.TargetId,
                    previewTargetId,
                    StringComparison.Ordinal)
                || preview.Binding.LifecycleGeneration <= 0
                || parameters.LifecycleGeneration
                    != checked((ulong)preview.Binding
                        .LifecycleGeneration))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    "stale_lifecycle");
            }
            if (!AuthorizeHair(
                    context,
                    parameters.ObservationGrantId,
                    parameters.TargetId,
                    parameters.SessionId,
                    out reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    reasonCode);
            }

            AgentHairConsentIssuanceResult result =
                await _hairConsent.RequestAsync(
                    new AgentHairConsentPresentationRequest(
                        context.ConnectionId,
                        context.Principal,
                        parameters.ObservationGrantId,
                        parameters.SessionId,
                        parameters.LifecycleGeneration,
                        parameters.TargetId,
                        preview,
                        LauncherTrustedHumanInteractionContext
                            .Current),
                    cancellationToken).ConfigureAwait(false);
            return result.Success
                ? AgentRuntimeDispatchResult.Completed(
                    result.Descriptor)
                : AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        result.ReasonCode));
        }

        private async Task<AgentRuntimeDispatchResult>
            ReconcileHairAsync(
                AgentRuntimeDispatchContext context,
                HairReconcileParametersV1 parameters,
                CancellationToken cancellationToken)
        {
            if (!_hairPreviews.TryResolve(
                    context,
                    parameters.TransactionId,
                    null,
                    out string previewTargetId,
                    out HairAppearancePreview preview,
                    out string reasonCode)
                || !string.Equals(
                    parameters.TargetId,
                    previewTargetId,
                    StringComparison.Ordinal)
                || !AuthorizeHair(
                    context,
                    parameters.ObservationGrantId,
                    parameters.TargetId,
                    preview.Binding.SessionId,
                    out reasonCode))
            {
                return AgentRuntimeDispatchResult.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode));
            }
            HairTransactionResult result =
                await _hair.ReconcileAsync(
                    parameters.TransactionId,
                    cancellationToken)
                .ConfigureAwait(false);
            if (result.Outcome
                == HairTransactionOutcome.DomainCommitted)
            {
                HairReconciledRestoreCapability capability =
                    await _hair
                        .TryConsumeReconciledRestoreCapabilityAsync(
                            preview,
                            cancellationToken)
                        .ConfigureAwait(false);
                if (capability != null)
                {
                    result = HairTransactionResult.Create(
                        result.Outcome,
                        result.ReasonCode,
                        result.ReconcileKind,
                        result.TransactionId,
                        result.PreviewHash,
                        result.AuthoritativeInspect,
                        capability.RestoreToken,
                        capability.ExpiresAtUtc);
                }
            }
            return AgentRuntimeDispatchResult.Completed(
                result);
        }

        private bool AuthorizeHair(
            AgentRuntimeDispatchContext context,
            string grantId,
            string targetId,
            string sessionId,
            out string reasonCode)
        {
            SessionSnapshot session = _sessions.GetSnapshot()
                .FindSession(sessionId);
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }
            if (session.RuntimeQualification.RuntimeMode
                == RuntimeMode.UnqualifiedDev)
            {
                reasonCode = "runtime_unqualified";
                return false;
            }
            if (!session.Capabilities.Contains(
                    AgentCapabilitiesV1.AppearanceHairChange,
                    StringComparer.Ordinal))
            {
                reasonCode = "capability_denied";
                return false;
            }
            if (!_hairTargets.TryAuthorize(
                    sessionId,
                    targetId,
                    out reasonCode))
            {
                reasonCode =
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode);
                return false;
            }
            if (!_grants.TryAuthorize(
                    grantId,
                    context.Principal.ClientInstanceId,
                    context.Principal.SecurityPrincipalId,
                    sessionId,
                    targetId,
                    ObservationDataScopesV1.PlayerState,
                    out _,
                    out reasonCode))
            {
                reasonCode =
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode);
                return false;
            }
            return true;
        }

        private bool AuthorizeSessionMetadata(
            AgentRuntimeDispatchContext context,
            WindowListParametersV1 parameters,
            out ObservationGrant grant,
            out SessionSnapshot session,
            out string reasonCode)
        {
            grant = null;
            session = null;
            reasonCode = null;
            if (!string.Equals(
                    parameters.DataScope,
                    ObservationDataScopesV1.WindowMetadata,
                    StringComparison.Ordinal)
                || !_grants.TryAuthorizeSession(
                    parameters.ObservationGrantId,
                    context.Principal.ClientInstanceId,
                    context.Principal.SecurityPrincipalId,
                    parameters.SessionId,
                    parameters.DataScope,
                    out grant,
                    out reasonCode))
            {
                reasonCode =
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode
                            ?? "observation_scope_mismatch");
                return false;
            }
            session = _sessions.GetSnapshot()
                .FindSession(parameters.SessionId);
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }
            return true;
        }

        private bool AuthorizeTarget(
            AgentRuntimeDispatchContext context,
            WindowTargetParametersV1 parameters,
            string requiredDataScope,
            out SessionSnapshot session,
            out SessionSurfaceSnapshot surface,
            out string reasonCode)
        {
            session = null;
            surface = null;
            reasonCode = null;
            if (!string.Equals(
                    parameters.DataScope,
                    requiredDataScope,
                    StringComparison.Ordinal)
                || !_grants.TryAuthorize(
                    parameters.ObservationGrantId,
                    context.Principal.ClientInstanceId,
                    context.Principal.SecurityPrincipalId,
                    parameters.SessionId,
                    parameters.TargetId,
                    requiredDataScope,
                    out _,
                    out reasonCode))
            {
                reasonCode =
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode
                            ?? "observation_scope_mismatch");
                return false;
            }
            session = _sessions.GetSnapshot()
                .FindSession(parameters.SessionId);
            surface = session?.Surfaces
                .FirstOrDefault(candidate =>
                    string.Equals(
                        candidate.TargetId,
                        parameters.TargetId,
                        StringComparison.Ordinal));
            if (surface == null)
            {
                reasonCode = session == null
                    ? "session_not_found"
                    : "target_not_found";
                return false;
            }
            return true;
        }

        private bool TryAppendTrustedAudit(
            AgentRuntimeDispatchContext context,
            string sessionId,
            ulong lifecycleGeneration,
            string consentPurpose,
            string eventType,
            string correlationId = null,
            string observationGrantId = null,
            string leaseId = null,
            string capability = null,
            IReadOnlyCollection<string>
                targetScope = null,
            IReadOnlyCollection<string>
                dataScope = null,
            bool? allowExport = null,
            bool? allowPersistence = null,
            string state = null,
            string reasonCode = null,
            string consentReceipt = null)
        {
            if (_trustedAudit == null)
                return true;
            return _trustedAudit.TryAppendTrustedFact(
                new AgentRuntimeTrustedAuditFact
                {
                    Principal = context.Principal,
                    ConnectionId =
                        context.ConnectionId,
                    SessionId = sessionId,
                    LifecycleGeneration =
                        lifecycleGeneration,
                    ConsentPurpose = consentPurpose,
                    EventType = eventType,
                    CorrelationId = correlationId,
                    ObservationGrantId =
                        observationGrantId,
                    LeaseId = leaseId,
                    Capability = capability,
                    TargetScope = targetScope,
                    DataScope = dataScope,
                    AllowExport = allowExport,
                    AllowPersistence =
                        allowPersistence,
                    State = state,
                    ReasonCode = reasonCode,
                    ConsentReceipt =
                        consentReceipt
                },
                out _,
                out _);
        }

        private static string LeaseConsentPurpose(
            WriteLease lease)
        {
            if (lease.Kind
                    == WriteLeaseKind.DomainTransaction
                && (string.Equals(
                        lease.Operation,
                        AgentMethodsV1.HairCommit,
                        StringComparison.Ordinal)
                    || string.Equals(
                        lease.Operation,
                        AgentMethodsV1.HairRestore,
                        StringComparison.Ordinal)))
            {
                return AgentCapabilitiesV1
                    .AppearanceHairChange;
            }
            if (lease.Capabilities.Count == 1)
                return lease.Capabilities[0];
            if (!string.IsNullOrWhiteSpace(
                    lease.Operation))
            {
                return lease.Operation;
            }
            return AgentCapabilitiesV1.LeaseAcquire;
        }

        private static ObservationGrantDescriptor ToContract(
            ObservationGrant grant,
            SessionSnapshot session)
        {
            return new ObservationGrantDescriptor
            {
                ObservationGrantId =
                    grant.ObservationGrantId,
                OwnerClientId = grant.OwnerClientId,
                SecurityPrincipalId =
                    grant.SecurityPrincipalId,
                SessionScope = new SessionScopeDescriptor
                {
                    SessionId = grant.SessionId,
                    LifecycleGeneration =
                        session.LifecycleGeneration,
                    AttemptId = session.AttemptId,
                    AttemptGeneration =
                        session.AttemptGeneration,
                    CrossAttempt = false
                },
                TargetScope = grant.TargetScope.ToList(),
                DataScope = grant.DataScope.ToList(),
                IssuedMonotonic = ToProtocolTime(
                    grant.IssuedMonotonic),
                ExpiresMonotonic = ToProtocolTime(
                    grant.ExpiresMonotonic),
                ConsentReceipt = grant.ConsentReceipt,
                AllowEphemeralKeyframes =
                    grant.AllowEphemeralKeyframes,
                AllowPersistence =
                    grant.AllowPersistence,
                AllowExport = grant.AllowExport,
                State = grant.State switch
                {
                    Security.ObservationGrantState
                        .Active =>
                        Contracts.ObservationGrantState
                            .Active,
                    Security.ObservationGrantState
                        .Expired =>
                        Contracts.ObservationGrantState
                            .Expired,
                    _ =>
                        Contracts.ObservationGrantState
                            .Revoked
                },
                RevokeReason = grant.RevokeReason
            };
        }

        private LeaseDescriptor ToContract(
            WriteLease lease)
        {
            SessionSnapshot session = _sessions.GetSnapshot()
                .FindSession(lease.SessionId);
            if (session == null
                || session.LifecycleGeneration == 0)
            {
                throw new InvalidOperationException(
                    "session_not_found");
            }
            return new LeaseDescriptor
            {
                LeaseId = lease.LeaseId,
                OwnerClientId = lease.OwnerClientId,
                SecurityPrincipalId =
                    lease.SecurityPrincipalId,
                SessionMode = lease.SessionMode switch
                {
                    AgentSessionMode
                        .DeveloperInteractive =>
                        SessionMode.DeveloperInteractive,
                    AgentSessionMode.UnattendedTest =>
                        SessionMode.UnattendedTest,
                    _ => SessionMode.PlayerAssist
                },
                Purpose = lease.Kind switch
                {
                    WriteLeaseKind.GuiInput =>
                        LeasePurpose.GuiInput,
                    WriteLeaseKind.DomainTransaction =>
                        LeasePurpose.DomainTransaction,
                    WriteLeaseKind.StructuredAction =>
                        LeasePurpose.StructuredAction,
                    WriteLeaseKind.Shutdown =>
                        LeasePurpose.Shutdown,
                    _ => throw new ArgumentOutOfRangeException()
                },
                Scope = new LeaseScopeDescriptor
                {
                    Session = new SessionScopeDescriptor
                    {
                        SessionId = lease.SessionId,
                        LifecycleGeneration =
                            lease.LifecycleGeneration,
                        AttemptId = session.AttemptId,
                        AttemptGeneration =
                            session.AttemptGeneration,
                        CrossAttempt = false
                    },
                    TargetScope =
                        lease.TargetScope.ToList(),
                    OperationScope =
                        lease.Capabilities.ToList(),
                    MaximumActions = lease.ActionLimit,
                    ArgumentBoundsHash =
                        lease.ArgumentBoundsHash
                },
                Capabilities =
                    lease.Capabilities.ToList(),
                IssuedMonotonic = ToProtocolTime(
                    lease.IssuedMonotonic),
                ExpiresMonotonic = ToProtocolTime(
                    lease.ExpiresMonotonic),
                RenewAfter = lease.Kind
                        is WriteLeaseKind.Shutdown
                        or WriteLeaseKind.StructuredAction
                    ? null
                    : ToProtocolTime(
                        lease.RenewAfterMonotonic),
                ConsentReceipt =
                    lease.ConsentReceipt,
                State = lease.State switch
                {
                    WriteLeaseState.Active =>
                        LeaseState.Active,
                    WriteLeaseState.Released =>
                        LeaseState.Released,
                    WriteLeaseState.Expired =>
                        LeaseState.Expired,
                    WriteLeaseState.Consumed =>
                        LeaseState.Consumed,
                    _ => LeaseState.Revoked
                },
                RevokeReason = lease.RevokeReason
            };
        }

        private static HairSaveBinding ToBinding(
            HairSaveBindingParametersV1 binding)
        {
            return new HairSaveBinding(
                binding.SessionId,
                checked((long)binding.LifecycleGeneration),
                binding.AttemptId,
                checked((long)binding.AttemptGeneration),
                binding.SlotId,
                binding.SaveSignature);
        }

        internal static string NormalizeHairReason(
            string reasonCode)
        {
            return reasonCode switch
            {
                HairAppearanceReasonCodes.ConsentRequired =>
                    "consent_required",
                HairAppearanceReasonCodes.ConsentExpired =>
                    "consent_expired",
                HairAppearanceReasonCodes.ConsentMismatch =>
                    "consent_invalid",
                HairAppearanceReasonCodes.ConsentReplayed =>
                    "domain_token_replayed",
                HairAppearanceReasonCodes.StaleRevision =>
                    "domain_revision_conflict",
                HairAppearanceReasonCodes.StaleState =>
                    "domain_revision_conflict",
                HairAppearanceReasonCodes.RestoreExpired =>
                    "domain_token_expired",
                HairAppearanceReasonCodes.RestoreTokenInvalid =>
                    "consent_invalid",
                HairAppearanceReasonCodes.RestoreTokenReplayed =>
                    "domain_token_replayed",
                HairAppearanceReasonCodes.UnknownWriteOutcome =>
                    "domain_commit_unknown",
                HairAppearanceReasonCodes.ReconcileRequired =>
                    "reconcile_required",
                HairAppearanceReasonCodes.CrossSave =>
                    "session_mismatch",
                HairAppearanceReasonCodes.AdapterUnavailable =>
                    "unsupported_for_surface",
                HairAppearanceReasonCodes.InvalidPayload =>
                    "arguments_invalid",
                _ => "operation_invalid"
            };
        }

        private static bool IsActionMethod(string method)
        {
            return AgentCapabilitiesV1.GuiCapabilitySet
                    .Contains(method, StringComparer.Ordinal)
                && method != AgentCapabilitiesV1.ListWindows
                && method != AgentCapabilitiesV1.GetWindow
                && method != AgentCapabilitiesV1.ListApps
                && method != AgentCapabilitiesV1.LaunchApp
                && method != AgentCapabilitiesV1.GetWindowState
                || method == AgentCapabilitiesV1.SessionShutdown
                || method == AgentCapabilitiesV1.LifecycleReveal
                || method == AgentCapabilitiesV1.LifecycleCancel
                || method == AgentCapabilitiesV1.PanelOpen
                || method == AgentMethodsV1.HairCommit
                || method == AgentMethodsV1.HairRestore;
        }

        private static T Read<T>(
            AgentJsonRpcRequest request)
        {
            return request.Params.Deserialize<T>(
                AgentProtocolV1.JsonOptions)
                ?? throw new JsonException(
                    "Validated parameters could not be materialized.");
        }

        private static ulong ToProtocolTime(long value)
        {
            return checked((ulong)Math.Max(1, value));
        }
    }
}
