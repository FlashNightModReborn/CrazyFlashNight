using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Gateway
{
    /// <summary>
    /// One-shot delivery boundary for actions whose host-side finalization
    /// must happen only after every CF7A frame in the success response
    /// (JSON and, when present, its binary chunk) has been written.
    /// A failed write takes the abort branch instead. Callback failures never
    /// change bytes already written, but their acknowledgement is returned so
    /// callers can retain the writer reservation and fail closed.
    /// </summary>
    internal sealed class AgentRuntimeResponseCompletion
    {
        private readonly object _sync = new object();
        private readonly Func<bool> _beforeWrite;
        private readonly Action _afterWrite;
        private readonly Action<bool> _afterAbort;
        private readonly Action _afterPostWriteCommitFailure;
        private ResponseCompletionState _state;
        private bool _abortAcknowledged;
        private bool _postWriteCommitFailureReported;

        public AgentRuntimeResponseCompletion(
            Action afterWrite,
            Action afterAbort)
            : this(
                null,
                afterWrite,
                _ => afterAbort(),
                null)
        {
        }

        public AgentRuntimeResponseCompletion(
            Func<bool> beforeWrite,
            Action afterWrite,
            Action<bool> afterAbort,
            Action afterPostWriteCommitFailure = null)
        {
            _beforeWrite = beforeWrite;
            _afterWrite = afterWrite
                ?? throw new ArgumentNullException(nameof(afterWrite));
            _afterAbort = afterAbort
                ?? throw new ArgumentNullException(nameof(afterAbort));
            _afterPostWriteCommitFailure =
                afterPostWriteCommitFailure;
        }

        public bool TryPrepareWrite()
        {
            bool abort = false;
            lock (_sync)
            {
                while (_state == ResponseCompletionState.Aborting)
                    Monitor.Wait(_sync);
                if (_state == ResponseCompletionState.Prepared)
                    return true;
                if (_state != ResponseCompletionState.Pending)
                    return false;
                try
                {
                    if (_beforeWrite != null && !_beforeWrite())
                    {
                        _state = ResponseCompletionState.Aborting;
                        abort = true;
                    }
                    else
                    {
                        _state = ResponseCompletionState.Prepared;
                    }
                }
                catch
                {
                    _state = ResponseCompletionState.Aborting;
                    abort = true;
                }
            }
            if (abort)
            {
                CompleteAbort(false);
                return false;
            }
            return true;
        }

        public bool CommitAfterWrite()
        {
            if (!TryPrepareWrite())
            {
                return false;
            }
            lock (_sync)
            {
                if (_state != ResponseCompletionState.Prepared)
                    return false;
                _state = ResponseCompletionState.Committed;
            }
            try
            {
                _afterWrite();
                return true;
            }
            catch
            {
                return false;
            }
        }

        public void ReportPostWriteCommitFailure()
        {
            Action callback;
            lock (_sync)
            {
                if (_postWriteCommitFailureReported)
                    return;
                _postWriteCommitFailureReported = true;
                callback = _afterPostWriteCommitFailure;
            }
            try
            {
                callback?.Invoke();
            }
            catch
            {
                // The complete response frames are already written. This
                // notification is evidence-only and must never turn them
                // into a transport rollback or skip the final flush.
            }
        }

        public bool Abort()
        {
            bool writeStarted;
            lock (_sync)
            {
                while (_state == ResponseCompletionState.Aborting)
                    Monitor.Wait(_sync);
                if (_state == ResponseCompletionState.Committed)
                {
                    return false;
                }
                if (_state == ResponseCompletionState.Aborted)
                {
                    return _abortAcknowledged;
                }
                writeStarted =
                    _state == ResponseCompletionState.Prepared;
                _state = ResponseCompletionState.Aborting;
            }
            return CompleteAbort(writeStarted);
        }

        private bool CompleteAbort(bool writeStarted)
        {
            bool acknowledged;
            try
            {
                _afterAbort(writeStarted);
                acknowledged = true;
            }
            catch
            {
                acknowledged = false;
            }
            lock (_sync)
            {
                _abortAcknowledged = acknowledged;
                _state = ResponseCompletionState.Aborted;
                Monitor.PulseAll(_sync);
            }
            return acknowledged;
        }

        private enum ResponseCompletionState
        {
            Pending,
            Prepared,
            Committed,
            Aborting,
            Aborted
        }
    }

    internal sealed class AgentRuntimeActionExecutionResult
    {
        public AgentRuntimeActionExecutionResult(
            ActionReceipt receipt,
            AgentRuntimeResponseCompletion responseCompletion,
            AgentRuntimeResponseDeliveryDisposition
                responseDeliveryDisposition =
                    AgentRuntimeResponseDeliveryDisposition
                        .NotApplicable)
        {
            Receipt = receipt
                ?? throw new ArgumentNullException(nameof(receipt));
            ResponseCompletion = responseCompletion;
            ResponseDeliveryDisposition =
                responseDeliveryDisposition;
        }

        public ActionReceipt Receipt { get; }

        public AgentRuntimeResponseCompletion ResponseCompletion
        {
            get;
        }

        public AgentRuntimeResponseDeliveryDisposition
            ResponseDeliveryDisposition
        {
            get;
        }
    }

    internal enum AgentRuntimeResponseDeliveryDisposition
    {
        NotApplicable,
        OwnerPending,
        Committed,
        Unknown
    }

    internal interface IAgentObservationBindingStore
    {
        void Store(
            AgentRuntimeDispatchContext context,
            string dataScope,
            ObservationEnvelope envelope);

        bool TryResolveForAction(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            out string dataScope,
            out string reasonCode);

        bool TryResolveAuditFrame(
            AgentRuntimeDispatchContext context,
            string observationId,
            string targetId,
            string frameId,
            out string resolvedFrameId,
            out string frameHash,
            out string reasonCode);
    }

    internal sealed class AgentActionPerformance
    {
        private AgentActionPerformance(
            ActionOutcome outcome,
            EvidenceKind evidenceKind,
            string reasonCode,
            ReconcileKind reconcileKind,
            string actualTargetId,
            bool focusVerified,
            string afterObservationId,
            HairDomainActionResult domainResult,
            AgentRuntimeResponseCompletion responseCompletion)
        {
            Outcome = outcome;
            EvidenceKind = evidenceKind;
            ReasonCode = reasonCode;
            ReconcileKind = reconcileKind;
            ActualTargetId = actualTargetId;
            FocusVerified = focusVerified;
            AfterObservationId = afterObservationId;
            DomainResult = domainResult;
            ResponseCompletion = responseCompletion;
        }

        public ActionOutcome Outcome { get; }
        public EvidenceKind EvidenceKind { get; }
        public string ReasonCode { get; }
        public ReconcileKind ReconcileKind { get; }
        public string ActualTargetId { get; }
        public bool FocusVerified { get; }
        public string AfterObservationId { get; }
        public HairDomainActionResult DomainResult { get; }
        public AgentRuntimeResponseCompletion ResponseCompletion
        {
            get;
        }

        public static AgentActionPerformance Completed(
            ActionOutcome outcome,
            EvidenceKind evidenceKind,
            string actualTargetId,
            bool focusVerified,
            string afterObservationId = null,
            string reasonCode = "none",
            HairDomainActionResult domainResult = null,
            AgentRuntimeResponseCompletion responseCompletion = null)
        {
            return new AgentActionPerformance(
                outcome,
                evidenceKind,
                reasonCode,
                ReconcileKind.None,
                actualTargetId,
                focusVerified,
                afterObservationId,
                domainResult,
                responseCompletion);
        }

        public static AgentActionPerformance Rejected(
            string reasonCode)
        {
            return new AgentActionPerformance(
                ActionOutcome.Rejected,
                EvidenceKind.None,
                reasonCode,
                ReconcileKind.None,
                null,
                false,
                null,
                null,
                null);
        }

        public static AgentActionPerformance Unknown(
            string reasonCode,
            ReconcileKind reconcileKind)
        {
            return new AgentActionPerformance(
                ActionOutcome.Unknown,
                EvidenceKind.ReconciliationRequired,
                reasonCode,
                reconcileKind,
                null,
                false,
                null,
                null,
                null);
        }
    }

    internal interface IAgentRuntimeActionPerformer
    {
        Task<AgentActionPerformance> PerformAsync(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            WriteLease lease,
            CancellationToken cancellationToken);
    }

    /// <summary>
    /// Couples idempotency, the single-writer lease, one-use observation and
    /// pending-action revocation before any action performer is entered.
    /// Same-key concurrent calls share one terminal task and can never double
    /// dispatch.
    /// </summary>
    internal sealed class AgentRuntimeActionExecutionBroker
    {
        private readonly object _sync = new object();
        private readonly ObservationCaptureBroker _observations;
        private readonly IAgentObservationBindingStore
            _observationBindings;
        private readonly WriteLeaseBroker _leases;
        private readonly ActionIdempotencyLedger _ledger;
        private readonly AgentRuntimeRevocationCoordinator
            _revocations;
        private readonly IAgentRuntimeActionPerformer _performer;
        private readonly IAgentRuntimeAuditSink _audit;
        private readonly Dictionary<string, InFlightAction>
            _inFlightByAction =
                new Dictionary<string, InFlightAction>(
                    StringComparer.Ordinal);
        private readonly Dictionary<string, InFlightAction>
            _inFlightByIdempotency =
                new Dictionary<string, InFlightAction>(
                    StringComparer.Ordinal);

        public AgentRuntimeActionExecutionBroker(
            ObservationCaptureBroker observations,
            IAgentObservationBindingStore observationBindings,
            WriteLeaseBroker leases,
            ActionIdempotencyLedger ledger,
            AgentRuntimeRevocationCoordinator revocations,
            IAgentRuntimeActionPerformer performer,
            IAgentRuntimeAuditSink audit)
        {
            _observations = observations
                ?? throw new ArgumentNullException(
                    nameof(observations));
            _observationBindings = observationBindings
                ?? throw new ArgumentNullException(
                    nameof(observationBindings));
            _leases = leases
                ?? throw new ArgumentNullException(nameof(leases));
            _ledger = ledger
                ?? throw new ArgumentNullException(nameof(ledger));
            _revocations = revocations
                ?? throw new ArgumentNullException(
                    nameof(revocations));
            _performer = performer
                ?? throw new ArgumentNullException(nameof(performer));
            _audit = audit
                ?? throw new ArgumentNullException(nameof(audit));
        }

        public Task<AgentRuntimeActionExecutionResult> ExecuteAsync(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            string requiredCapability,
            CancellationToken cancellationToken)
        {
            if (context == null)
                throw new ArgumentNullException(nameof(context));
            if (action == null)
                throw new ArgumentNullException(nameof(action));
            string canonicalHash =
                CanonicalJsonV1
                    .ComputeActionPayloadSha256(action)
                    .ToLowerInvariant();
            var identity = new ActionLedgerIdentity(
                context.Principal.SecurityPrincipalId,
                action.SessionId,
                action.ActionId,
                action.IdempotencyKey,
                canonicalHash);
            string actionKey = NamespaceKey(
                identity.SecurityPrincipalId,
                identity.SessionId,
                identity.ActionId);
            string idempotencyKey = NamespaceKey(
                identity.SecurityPrincipalId,
                identity.SessionId,
                identity.IdempotencyKey);

            lock (_sync)
            {
                _inFlightByAction.TryGetValue(
                    actionKey,
                    out InFlightAction byAction);
                _inFlightByIdempotency.TryGetValue(
                    idempotencyKey,
                    out InFlightAction byIdempotency);
                InFlightAction existing =
                    byAction ?? byIdempotency;
                if (byAction != null
                    && byIdempotency != null
                    && !ReferenceEquals(
                        byAction,
                        byIdempotency))
                {
                    return AwaitReplayAsync(
                        AuditStandaloneRejected(
                            context,
                            action,
                            canonicalHash,
                            requiredCapability,
                            "idempotency_conflict"));
                }
                if (existing != null)
                {
                    if (!string.Equals(
                            existing.CanonicalHash,
                            canonicalHash,
                            StringComparison.Ordinal))
                    {
                        return AwaitReplayAsync(
                            AuditStandaloneRejected(
                                context,
                                action,
                                canonicalHash,
                                requiredCapability,
                                "idempotency_conflict"));
                    }
                    return AwaitReplayAsync(
                        existing.Task,
                        existing.ResponseDelivery.Task,
                        context,
                        action,
                        cancellationToken);
                }

                ActionBeginResult begin =
                    _ledger.Begin(identity);
                if (begin.Kind == ActionBeginKind.Conflict)
                {
                    return AwaitReplayAsync(
                        AuditStandaloneRejected(
                            context,
                            action,
                            canonicalHash,
                            requiredCapability,
                            "idempotency_conflict"));
                }
                if (begin.Kind
                    == ActionBeginKind.ExistingReceipt)
                {
                    if (begin.Receipt?.ContractReceipt
                        != null)
                    {
                        return Task.FromResult(
                            new AgentRuntimeActionExecutionResult(
                                begin.Receipt.ContractReceipt,
                                null,
                                AgentRuntimeResponseDeliveryDisposition
                                    .Committed));
                    }
                    return Task.FromResult(
                        new AgentRuntimeActionExecutionResult(
                            AuditStandaloneRecord(
                                context,
                                begin.Receipt,
                                action,
                                canonicalHash,
                                requiredCapability),
                            null));
                }

                ActionAuditState auditState;
                try
                {
                    auditState = BeginAudit(
                        context,
                        action,
                        canonicalHash,
                        requiredCapability);
                }
                catch (Exception error)
                {
                    return Task.FromException<
                        AgentRuntimeActionExecutionResult>(error);
                }
                var source =
                    new TaskCompletionSource<ActionReceipt>(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
                var inFlight = new InFlightAction(
                    canonicalHash,
                    source.Task);
                var responseCompletionSlot =
                    new ResponseCompletionSlot();
                _inFlightByAction.Add(
                    actionKey,
                    inFlight);
                _inFlightByIdempotency.Add(
                    idempotencyKey,
                    inFlight);
                _ = ExecuteOwnerAsync(
                    context,
                    action,
                    requiredCapability,
                    identity,
                    source,
                    actionKey,
                    idempotencyKey,
                    auditState,
                    responseCompletionSlot,
                    cancellationToken);
                return AwaitOwnerAsync(
                    source.Task,
                    responseCompletionSlot);
            }
        }

        private async Task ExecuteOwnerAsync(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            string requiredCapability,
            ActionLedgerIdentity identity,
            TaskCompletionSource<ActionReceipt> completion,
            string actionKey,
            string idempotencyKey,
            ActionAuditState auditState,
            ResponseCompletionSlot responseCompletionSlot,
            CancellationToken cancellationToken)
        {
            ActionReceipt receipt = null;
            WriteLease lease = null;
            bool dispatchStarted = false;
            string dataScope = null;
            AgentRuntimeResponseCompletion responseCompletion = null;
            bool responseDeliveryDependent = false;
            ActionReceipt responseDeliveryUnknownReceipt = null;
            bool executionReservationOwned = false;
            bool executionReservationReleaseAuthorized = true;

            bool AbortDependentResponseCompletion()
            {
                if (!responseDeliveryDependent)
                {
                    return executionReservationReleaseAuthorized;
                }
                AgentRuntimeResponseCompletion pendingCompletion =
                    responseCompletion;
                responseCompletion = null;
                responseDeliveryDependent = false;
                bool acknowledged =
                    pendingCompletion?.Abort() ?? false;
                if (!acknowledged)
                {
                    // A host which cannot acknowledge abort may still own
                    // shutdown side effects. Keep the per-session writer
                    // reservation fail-closed and make the continuity loss
                    // visible to every later action lookup.
                    executionReservationReleaseAuthorized = false;
                    _ledger.MarkContinuityLost();
                }
                return acknowledged;
            }

            void RejectBeforeDispatch(string reasonCode)
            {
                Exception rejectionError = null;
                try
                {
                    receipt = CompleteBeforeDispatch(
                        context,
                        action,
                        reasonCode,
                        lease,
                        identity,
                        auditState);
                    responseCompletion =
                        executionReservationOwned
                            ? ExecutionReservationCompletion(
                                lease)
                            : null;
                }
                catch (Exception error)
                {
                    rejectionError = error;
                }
                try
                {
                    // These early returns precede the main response-finally
                    // block. Publish exactly once here, before AwaitOwnerAsync
                    // can observe the result, so a successful consume remains
                    // reserved through the whole rejection response write.
                    PublishOwnerResponseCompletionAndRemoveInFlight(
                        actionKey,
                        idempotencyKey,
                        receipt,
                        responseCompletion,
                        responseCompletionSlot,
                        lease,
                        executionReservationOwned,
                        responseDeliveryDependent: false);
                    ReleaseInactiveLease(lease);
                }
                catch (Exception error)
                {
                    rejectionError = rejectionError == null
                        ? error
                        : new AggregateException(
                            rejectionError,
                            error);
                }
                if (rejectionError == null)
                {
                    completion.TrySetResult(receipt);
                }
                else
                {
                    completion.TrySetException(
                        new InvalidOperationException(
                            "audit_unavailable",
                            rejectionError));
                }
            }

            try
            {
                if (!_leases.TryConsumeAction(
                        action.LeaseId,
                        context.Principal.ClientInstanceId,
                        context.Principal.SecurityPrincipalId,
                        action.SessionId,
                        requiredCapability,
                        action.TargetId,
                        action.Operation,
                        out lease,
                        out string leaseReason))
                {
                    RejectBeforeDispatch(
                        AgentRuntimeGateway.NormalizeReason(
                            leaseReason));
                    return;
                }
                executionReservationOwned = true;
                if (action.ExpectedLifecycleGeneration
                    != lease.LifecycleGeneration)
                {
                    RejectBeforeDispatch("stale_observation");
                    return;
                }
                if (!PlayerArgumentBoundsMatch(
                        action,
                        lease))
                {
                    RejectBeforeDispatch("arguments_invalid");
                    return;
                }

                if (!_observationBindings.TryResolveForAction(
                        context,
                        action,
                        out dataScope,
                        out string bindingReason))
                {
                    RejectBeforeDispatch(
                        AgentRuntimeGateway.NormalizeReason(
                            bindingReason));
                    return;
                }
                if (!_observationBindings.TryResolveAuditFrame(
                        context,
                        action.ObservationId,
                        action.TargetId,
                        action.FrameId,
                        out auditState.BeforeFrameId,
                        out auditState.BeforeFrameHash,
                        out auditState.BeforeFrameReasonCode))
                {
                    RejectBeforeDispatch("capture_unavailable");
                    return;
                }
                if (!_observations.TryUseObservation(
                        new ObservationUseRequest
                        {
                            ObservationId =
                                action.ObservationId,
                            ObservationGrantId =
                                action.ObservationGrantId,
                            ClientInstanceId =
                                context.Principal
                                    .ClientInstanceId,
                            SecurityPrincipalId =
                                context.Principal
                                    .SecurityPrincipalId,
                            SessionId = action.SessionId,
                            TargetId = action.TargetId,
                            FrameId = action.FrameId,
                            DataScope = dataScope
                        },
                        true,
                        out string observationReason))
                {
                    RejectBeforeDispatch(
                        AgentRuntimeGateway.NormalizeReason(
                            observationReason));
                    return;
                }

                AppendAuditRequired(
                    AuditEvent(
                        context,
                        action,
                        auditState,
                        AgentRuntimeAuditEventTypes
                            .ActionBindingValidated,
                        lease));
                if (lease.Kind
                    == WriteLeaseKind.DomainTransaction)
                {
                    AppendAuditRequired(
                        AuditEvent(
                            context,
                            action,
                            auditState,
                            AgentRuntimeAuditEventTypes
                                .DomainProposal,
                            lease,
                            domainPreviewHash:
                                lease.PreviewHash));
                }
                AppendAuditRequired(
                    AuditEvent(
                        context,
                        action,
                        auditState,
                        AgentRuntimeAuditEventTypes
                            .ActionDispatchStarted,
                        lease,
                        dispatchMayHaveStarted: true));
                ActionReconcileKind ledgerReconcile =
                    lease.Kind switch
                    {
                        WriteLeaseKind.DomainTransaction =>
                            ActionReconcileKind
                                .DomainAuthoritative,
                        WriteLeaseKind.Shutdown =>
                            ActionReconcileKind
                                .ManualRequired,
                        _ =>
                            ActionReconcileKind
                                .VisualAmbiguous
                    };
                _ledger.MarkDispatchStarted(
                    identity,
                    ledgerReconcile);
                dispatchStarted = true;
                using AgentRuntimeRevocationCoordinator
                    .ActionCancellationRegistration pending =
                        _revocations.RegisterAction(
                            context.ConnectionId,
                            action.LeaseId,
                            cancellationToken);
                AgentActionPerformance performance =
                    await _performer.PerformAsync(
                        context,
                        action,
                        lease,
                        pending.Token)
                    .ConfigureAwait(false);
                performance ??=
                    AgentActionPerformance.Unknown(
                        "internal_error",
                        ReconcileKind.ManualRequired);
                responseCompletion =
                    performance.ResponseCompletion;
                responseDeliveryDependent =
                    responseCompletion != null;
                await CaptureAfterAsync(
                        context,
                        action,
                        dataScope,
                        auditState,
                        pending.Token)
                    .ConfigureAwait(false);
                if (performance.Outcome
                        == ActionOutcome.EffectObserved
                    && auditState.AfterFrameHash == null)
                {
                    performance =
                        AgentActionPerformance.Unknown(
                            "reconcile_required",
                            ReconcileKind.VisualAmbiguous);
                }
                receipt = ToReceipt(
                    action,
                    performance,
                    lease);
                receipt.AfterObservationId =
                    auditState.AfterObservationId;
            }
            catch (OperationCanceledException)
                when (dispatchStarted)
            {
                receipt = ToReceipt(
                    action,
                    AgentActionPerformance.Unknown(
                        "reconcile_required",
                        lease?.Kind
                            == WriteLeaseKind.DomainTransaction
                            ? ReconcileKind
                                .DomainAuthoritative
                            : ReconcileKind.ManualRequired),
                    lease);
            }
            catch
            {
                receipt = dispatchStarted
                    ? ToReceipt(
                        action,
                        AgentActionPerformance.Unknown(
                            "internal_error",
                            lease?.Kind
                                == WriteLeaseKind
                                    .DomainTransaction
                                ? ReconcileKind
                                    .DomainAuthoritative
                                : ReconcileKind
                                    .ManualRequired),
                        lease)
                    : RejectedReceipt(
                        action,
                        "internal_error",
                    lease);
            }

            try
            {
                receipt = CommitAuditedReceipt(
                    context,
                    action,
                    auditState,
                    receipt,
                    lease,
                    dispatchStarted,
                    responseDeliveryPending:
                        responseDeliveryDependent
                        && receipt != null
                        && receipt.Outcome
                            != ActionOutcome.Rejected
                        && receipt.Outcome
                            != ActionOutcome.Unknown);
                if (receipt.Outcome == ActionOutcome.Unknown)
                {
                    bool abortAcknowledged =
                        AbortDependentResponseCompletion();
                    _ledger.RecordUnknown(
                        identity,
                        ToLedgerReceipt(receipt));
                    if (dispatchStarted
                        && abortAcknowledged)
                    {
                        responseCompletion =
                            ExecutionReservationCompletion(
                                lease);
                    }
                }
                else if (responseDeliveryDependent
                    && receipt.Outcome
                        != ActionOutcome.Rejected)
                {
                    AgentRuntimeResponseCompletion hostCompletion =
                        responseCompletion;
                    IAgentRuntimeActionResponseAuditSink
                        responseAudit =
                            _audit
                                as IAgentRuntimeActionResponseAuditSink
                            ?? throw new InvalidOperationException(
                                "audit_unavailable");
                    AgentRuntimeAuditCommit terminal =
                        auditState.TerminalCommit
                        ?? throw new InvalidOperationException(
                            "audit_unavailable");
                    ActionReceipt terminalReceipt = receipt;
                    responseDeliveryUnknownReceipt =
                        DeliveryUnknownContractReceipt(
                            action,
                            terminalReceipt);
                    responseCompletion =
                        new AgentRuntimeResponseCompletion(
                            delegate
                            {
                                AgentRuntimeActionResponseAuditFact
                                    writtenFact =
                                        ResponseAuditFact(
                                            context,
                                            action,
                                            auditState,
                                            terminal,
                                            AgentRuntimeActionResponseDisposition
                                                .Written,
                                            null);
                                if (!responseAudit
                                        .TryClaimActionResponseWrite(
                                            writtenFact,
                                            out _))
                                {
                                    return false;
                                }
                                return _revocations
                                    .TryClaimShutdownDeliveryWrite(
                                        action.LeaseId);
                            },
                            delegate
                            {
                                bool auditWritten = false;
                                bool leaseCompleted = false;
                                try
                                {
                                    auditWritten =
                                        responseAudit
                                            .TryCompleteActionResponse(
                                                ResponseAuditFact(
                                                    context,
                                                    action,
                                                    auditState,
                                                    terminal,
                                                    AgentRuntimeActionResponseDisposition
                                                        .Written,
                                                    null),
                                                out _,
                                                out _);
                                    leaseCompleted =
                                        _leases
                                            .CompleteShutdownDelivery(
                                                action.LeaseId);
                                    if (!auditWritten
                                        || !leaseCompleted)
                                    {
                                        _ledger.MarkContinuityLost();
                                    }
                                    CompleteKnown(
                                        identity,
                                        terminalReceipt);
                                }
                                finally
                                {
                                    bool hostCommitted =
                                        hostCompletion
                                            ?.CommitAfterWrite()
                                        ?? true;
                                    if (!hostCommitted)
                                    {
                                        _ledger.MarkContinuityLost();
                                    }
                                    ReleaseInactiveLease(lease);
                                    FinishResponseDelivery(
                                        actionKey,
                                        idempotencyKey,
                                        AgentRuntimeResponseDeliveryDisposition
                                            .Committed);
                                }
                            },
                            writeStarted =>
                            {
                                bool auditCompleted = false;
                                bool hostAbortAcknowledged = false;
                                try
                                {
                                    auditCompleted =
                                        responseAudit
                                        .TryCompleteActionResponse(
                                            ResponseAuditFact(
                                                context,
                                                action,
                                                auditState,
                                                terminal,
                                                AgentRuntimeActionResponseDisposition
                                                    .Unknown,
                                                writeStarted
                                                    ? "response_write_failed"
                                                    : "response_write_not_started"),
                                            out _,
                                            out _);
                                    try
                                    {
                                        _ledger.RecordUnknown(
                                            identity,
                                            ToLedgerReceipt(
                                                responseDeliveryUnknownReceipt));
                                    }
                                    finally
                                    {
                                        // SafeExit must acknowledge abort
                                        // while the per-session execution
                                        // reservation still excludes every
                                        // later writer.
                                        hostAbortAcknowledged =
                                            hostCompletion?.Abort()
                                            ?? true;
                                    }
                                }
                                finally
                                {
                                    bool leaseCompleted = false;
                                    if (hostAbortAcknowledged)
                                    {
                                        leaseCompleted =
                                            writeStarted
                                                ? _leases
                                                    .AbortClaimedShutdownDeliveryWrite(
                                                        action.LeaseId)
                                                : _leases
                                                        .AbortPendingShutdownDelivery(
                                                            action.LeaseId)
                                                    || _leases
                                                        .AbortPendingActionExecution(
                                                            action.LeaseId);
                                    }
                                    if ((!auditCompleted
                                            && auditState
                                                .TerminalCommit != null)
                                        || !hostAbortAcknowledged
                                        || !leaseCompleted)
                                    {
                                        _ledger.MarkContinuityLost();
                                    }
                                    if (hostAbortAcknowledged)
                                    {
                                        ReleaseInactiveLease(lease);
                                    }
                                    FinishResponseDelivery(
                                        actionKey,
                                        idempotencyKey,
                                        AgentRuntimeResponseDeliveryDisposition
                                            .Unknown);
                                }
                                if (!hostAbortAcknowledged)
                                {
                                    throw new InvalidOperationException(
                                        "host_abort_unacknowledged");
                                }
                            },
                            _ledger.MarkContinuityLost);
                }
                else if (receipt.Outcome
                    != ActionOutcome.Rejected)
                {
                    CompleteKnown(identity, receipt);
                    if (dispatchStarted)
                    {
                        responseCompletion =
                            ExecutionReservationCompletion(
                                lease);
                    }
                }
                else
                {
                    CompleteKnown(identity, receipt);
                    if (dispatchStarted)
                    {
                        responseCompletion =
                            ExecutionReservationCompletion(
                                lease);
                    }
                }
            }
            catch (Exception error)
            {
                if (dispatchStarted)
                {
                    bool abortAcknowledged =
                        AbortDependentResponseCompletion();
                    try
                    {
                        receipt = ToReceipt(
                            action,
                            AgentActionPerformance.Unknown(
                                "internal_error",
                                lease?.Kind
                                    == WriteLeaseKind
                                        .DomainTransaction
                                    ? ReconcileKind
                                        .DomainAuthoritative
                                    : ReconcileKind
                                        .ManualRequired),
                            lease);
                        receipt.AfterObservationId =
                            auditState.AfterObservationId;
                        receipt = CommitAuditedReceipt(
                            context,
                            action,
                            auditState,
                            receipt,
                            lease,
                            true);
                        _ledger.RecordUnknown(
                            identity,
                            ToLedgerReceipt(receipt));
                        if (abortAcknowledged)
                        {
                            responseCompletion =
                                ExecutionReservationCompletion(
                                    lease);
                        }
                    }
                    catch (Exception fallbackError)
                    {
                        TryRecordUnauditedUnknown(
                            identity,
                            action,
                            lease);
                        completion.TrySetException(
                            new InvalidOperationException(
                                "audit_unavailable",
                                new AggregateException(
                                    error,
                                    fallbackError)));
                        return;
                    }
                }
                else
                {
                    completion.TrySetException(
                        new InvalidOperationException(
                            "audit_unavailable",
                            error));
                    return;
                }
            }
            finally
            {
                bool responsePublished =
                    PublishOwnerResponseCompletionAndRemoveInFlight(
                    actionKey,
                    idempotencyKey,
                    receipt,
                    responseCompletion,
                    responseCompletionSlot,
                    lease,
                    executionReservationOwned
                        && executionReservationReleaseAuthorized,
                    responseDeliveryDependent);
                if (responseDeliveryDependent
                    && !responsePublished
                    && responseDeliveryUnknownReceipt != null)
                {
                    receipt =
                        responseDeliveryUnknownReceipt;
                }
                ReleaseInactiveLease(lease);
            }
            completion.TrySetResult(receipt);
        }

        private ActionAuditState BeginAudit(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            string canonicalHash,
            string consentPurpose)
        {
            var state = new ActionAuditState(
                OpaqueIdGenerator.Create(
                    "auditaction"),
                canonicalHash,
                consentPurpose);
            AppendAuditRequired(
                AuditEvent(
                    context,
                    action,
                    state,
                    AgentRuntimeAuditEventTypes
                        .ActionValidation,
                    null));
            return state;
        }

        private Task<ActionReceipt> AuditStandaloneRejected(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            string canonicalHash,
            string consentPurpose,
            string reasonCode)
        {
            try
            {
                ActionAuditState state = BeginAudit(
                    context,
                    action,
                    canonicalHash,
                    consentPurpose);
                state.AfterFrameReasonCode =
                    "action_not_dispatched";
                ActionReceipt receipt =
                    CommitAuditedReceipt(
                        context,
                        action,
                        state,
                        RejectedReceipt(
                            action,
                            reasonCode,
                            null),
                        null,
                        false);
                return Task.FromResult(receipt);
            }
            catch (Exception error)
            {
                return Task.FromException<ActionReceipt>(
                    new InvalidOperationException(
                        "audit_unavailable",
                        error));
            }
        }

        private ActionReceipt AuditStandaloneRecord(
            AgentRuntimeDispatchContext context,
            ActionReceiptRecord record,
            ActionEnvelope action,
            string canonicalHash,
            string consentPurpose)
        {
            if (record == null)
            {
                return AuditStandaloneRejected(
                        context,
                        action,
                        canonicalHash,
                        consentPurpose,
                        "internal_error")
                    .GetAwaiter()
                    .GetResult();
            }
            ActionAuditState state = BeginAudit(
                context,
                action,
                canonicalHash,
                consentPurpose);
            state.AfterFrameReasonCode =
                "action_not_dispatched";
            AgentActionPerformance performance =
                record.Outcome
                    == ActionReceiptOutcome.Unknown
                    ? AgentActionPerformance.Unknown(
                        record.ReasonCode,
                        ToContractReconcile(
                            record.ReconcileKind))
                    : record.Outcome
                        == ActionReceiptOutcome.Rejected
                            ? AgentActionPerformance.Rejected(
                                record.ReasonCode)
                            : AgentActionPerformance.Unknown(
                                "reconcile_required",
                                ReconcileKind.ManualRequired);
            return CommitAuditedReceipt(
                context,
                action,
                state,
                ToReceipt(action, performance, null),
                null,
                record.Outcome
                    != ActionReceiptOutcome.Rejected);
        }

        private ActionReceipt CompleteBeforeDispatch(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            string reasonCode,
            WriteLease lease,
            ActionLedgerIdentity identity,
            ActionAuditState auditState)
        {
            auditState.AfterFrameReasonCode =
                "action_not_dispatched";
            ActionReceipt receipt =
                CommitAuditedReceipt(
                    context,
                    action,
                    auditState,
                    RejectedReceipt(
                        action,
                        reasonCode,
                        lease),
                    lease,
                    false);
            CompleteKnown(identity, receipt);
            return receipt;
        }

        private async Task CaptureAfterAsync(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            string dataScope,
            ActionAuditState auditState,
            CancellationToken cancellationToken)
        {
            ObservationCaptureOutcome captured;
            try
            {
                captured = await _observations.CaptureAsync(
                        new ObservationCaptureRequest
                        {
                            ObservationGrantId =
                                action.ObservationGrantId,
                            ClientInstanceId =
                                context.Principal
                                    .ClientInstanceId,
                            SecurityPrincipalId =
                                context.Principal
                                    .SecurityPrincipalId,
                            SessionId = action.SessionId,
                            TargetId = action.TargetId,
                            DataScope = dataScope
                        },
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            catch
            {
                auditState.AfterFrameReasonCode =
                    "capture_unavailable";
                return;
            }
            if (!captured.Success)
            {
                auditState.AfterFrameReasonCode =
                    captured.ReasonCode
                        ?? "capture_unavailable";
                return;
            }
            try
            {
                _observationBindings.Store(
                    context,
                    dataScope,
                    captured.Envelope);
                auditState.AfterObservationId =
                    captured.Envelope.ObservationId;
                if (!_observationBindings
                    .TryResolveAuditFrame(
                        context,
                        captured.Envelope.ObservationId,
                        action.TargetId,
                        null,
                        out auditState.AfterFrameId,
                        out auditState.AfterFrameHash,
                        out auditState
                            .AfterFrameReasonCode))
                {
                    auditState.AfterFrameReasonCode ??=
                        "keyframe_hash_unavailable";
                }
            }
            catch
            {
                auditState.AfterFrameReasonCode =
                    "keyframe_hash_unavailable";
            }
        }

        private ActionReceipt CommitAuditedReceipt(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            ActionAuditState auditState,
            ActionReceipt receipt,
            WriteLease lease,
            bool dispatchMayHaveStarted,
            bool responseDeliveryPending = false)
        {
            if (receipt == null)
            {
                receipt = RejectedReceipt(
                    action,
                    "internal_error",
                    lease);
            }
            string outcomeEvent = receipt.Outcome switch
            {
                ActionOutcome.Rejected =>
                    AgentRuntimeAuditEventTypes
                        .ActionRejected,
                ActionOutcome.Unknown =>
                    AgentRuntimeAuditEventTypes
                        .ActionUnknown,
                _ => null
            };
            if (outcomeEvent != null)
            {
                AppendAuditRequired(
                    AuditEvent(
                        context,
                        action,
                        auditState,
                        outcomeEvent,
                        lease,
                        receipt,
                        dispatchMayHaveStarted));
            }
            if (receipt.Outcome == ActionOutcome.Unknown)
            {
                AppendAuditRequired(
                    AuditEvent(
                        context,
                        action,
                        auditState,
                        AgentRuntimeAuditEventTypes
                            .ActionReconcileRequired,
                        lease,
                        receipt,
                        true));
            }
            if (receipt.Outcome
                == ActionOutcome.DomainCommitted)
            {
                AppendAuditRequired(
                    AuditEvent(
                        context,
                        action,
                        auditState,
                        AgentRuntimeAuditEventTypes
                            .DomainCommit,
                        lease,
                        receipt,
                        true,
                        receipt.DomainResult
                            ?.TransactionId,
                        receipt.DomainResult
                            ?.PreviewHash));
            }
            AgentRuntimeAuditCommit terminal =
                AppendAuditRequired(
                    AuditEvent(
                        context,
                        action,
                        auditState,
                        AgentRuntimeAuditEventTypes
                            .ActionTerminal,
                        lease,
                        receipt,
                        dispatchMayHaveStarted,
                        receipt.DomainResult
                            ?.TransactionId,
                        receipt.DomainResult
                            ?.PreviewHash,
                        terminalAction: true,
                        responseDeliveryPending:
                            responseDeliveryPending));
            auditState.TerminalCommit = terminal;
            receipt.AuditSequence =
                checked((ulong)terminal.AuditSequence);
            return receipt;
        }

        private AgentRuntimeAuditEventEnvelope AuditEvent(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            ActionAuditState state,
            string eventType,
            WriteLease lease,
            ActionReceipt receipt = null,
            bool dispatchMayHaveStarted = false,
            string domainTransactionId = null,
            string domainPreviewHash = null,
            bool terminalAction = false,
            bool responseDeliveryPending = false)
        {
            return new AgentRuntimeAuditEventEnvelope
            {
                Principal = context.Principal,
                ConnectionId = context.ConnectionId,
                SessionId = action.SessionId,
                LifecycleGeneration =
                    action.ExpectedLifecycleGeneration,
                ConsentPurpose = state.ConsentPurpose,
                CorrelationId = state.CorrelationId,
                EventType = eventType,
                Action = action,
                ActionPayloadHash =
                    state.CanonicalHash,
                Lease = lease,
                Outcome = receipt?.Outcome,
                EvidenceKind =
                    receipt?.EvidenceKind,
                ReasonCode =
                    receipt?.ReasonCode,
                ReconcileKind =
                    receipt?.ReconcileKind,
                BeforeFrameId =
                    state.BeforeFrameId,
                BeforeFrameHash =
                    state.BeforeFrameHash,
                BeforeFrameReasonCode =
                    state.BeforeFrameReasonCode,
                AfterObservationId =
                    state.AfterObservationId,
                AfterFrameId =
                    state.AfterFrameId,
                AfterFrameHash =
                    state.AfterFrameHash,
                AfterFrameReasonCode =
                    state.AfterFrameReasonCode,
                DomainTransactionId =
                    domainTransactionId,
                DomainPreviewHash =
                    domainPreviewHash,
                RestoreSecretIssued =
                    receipt?.DomainResult
                        ?.RestoreToken != null,
                RestoreExpiresAtUtc =
                    receipt?.DomainResult
                        ?.RestoreExpiresAtUtc,
                DispatchMayHaveStarted =
                    dispatchMayHaveStarted,
                TerminalAction = terminalAction,
                ResponseDeliveryPending =
                    responseDeliveryPending
            };
        }

        private static AgentRuntimeActionResponseAuditFact
            ResponseAuditFact(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                ActionAuditState state,
                AgentRuntimeAuditCommit terminal,
                AgentRuntimeActionResponseDisposition disposition,
                string reasonCode)
        {
            return new AgentRuntimeActionResponseAuditFact
            {
                Principal = context.Principal,
                ConnectionId = context.ConnectionId,
                SessionId = action.SessionId,
                LifecycleGeneration =
                    action.ExpectedLifecycleGeneration,
                ConsentPurpose = state.ConsentPurpose,
                CorrelationId = state.CorrelationId,
                ActionId = action.ActionId,
                ActionPayloadHash = state.CanonicalHash,
                TerminalAuditSequence =
                    terminal.AuditSequence,
                TerminalEntryHash = terminal.EntryHash,
                Disposition = disposition,
                ReasonCode = reasonCode
            };
        }

        private AgentRuntimeAuditCommit AppendAuditRequired(
            AgentRuntimeAuditEventEnvelope auditEvent)
        {
            if (!_audit.TryAppend(
                    auditEvent,
                    out AgentRuntimeAuditCommit commit,
                    out string reasonCode)
                || commit == null)
            {
                throw new InvalidOperationException(
                    reasonCode
                        ?? "audit_unavailable");
            }
            return commit;
        }

        private static bool PlayerArgumentBoundsMatch(
            ActionEnvelope action,
            WriteLease lease)
        {
            if (lease.SessionMode
                != AgentSessionMode.PlayerAssist)
            {
                return true;
            }
            if (string.IsNullOrWhiteSpace(
                    lease.ArgumentBoundsHash))
            {
                return false;
            }
            try
            {
                string actual =
                    CanonicalJsonV1
                        .ComputeArgumentBoundsSha256(
                            action.Operation,
                            action.Arguments);
                return CanonicalJsonV1
                    .FixedTimeEqualsSha256(
                        lease.ArgumentBoundsHash,
                        actual);
            }
            catch
            {
                return false;
            }
        }

        private void TryRecordUnauditedUnknown(
            ActionLedgerIdentity identity,
            ActionEnvelope action,
            WriteLease lease)
        {
            try
            {
                _ledger.RecordUnknown(
                    identity,
                    new ActionReceiptRecord(
                        action.ActionId,
                        true,
                        ActionReceiptOutcome.Unknown,
                        "reconcile_required",
                        lease?.Kind
                            == WriteLeaseKind.DomainTransaction
                            ? ActionReconcileKind
                                .DomainAuthoritative
                            : ActionReconcileKind
                                .ManualRequired,
                        false));
            }
            catch
            {
                _ledger.MarkContinuityLost();
            }
        }

        private void CompleteKnown(
            ActionLedgerIdentity identity,
            ActionReceipt receipt)
        {
            _ledger.Complete(
                identity,
                ToLedgerReceipt(receipt));
        }

        private AgentRuntimeResponseCompletion
            ExecutionReservationCompletion(WriteLease lease)
        {
            void CompleteReservation()
            {
                if (lease == null)
                    return;
                if (!_leases.CompleteActionExecution(
                        lease.LeaseId,
                        retainShutdownDelivery: false))
                {
                    _ledger.MarkContinuityLost();
                    throw new InvalidOperationException(
                        "execution_reservation_completion_failed");
                }
                ReleaseInactiveLease(lease);
            }

            return new AgentRuntimeResponseCompletion(
                null,
                CompleteReservation,
                _ => CompleteReservation(),
                _ledger.MarkContinuityLost);
        }

        private void ReleaseInactiveLease(WriteLease lease)
        {
            if (lease == null
                || lease.State == WriteLeaseState.Active
                || lease.ActionExecutionPending
                || lease.ShutdownDeliveryPending
                || lease.ShutdownDeliveryWriteOwned)
            {
                return;
            }
            _revocations.UntrackLeaseAndCancelQueuedActions(
                lease.SessionId,
                lease.LeaseId,
                lease.RevokeReason
                    ?? "action_limit_consumed");
        }

        private ActionReceipt RejectedReceipt(
            ActionEnvelope action,
            string reasonCode,
            WriteLease lease)
        {
            return ToReceipt(
                action,
                AgentActionPerformance.Rejected(
                    reasonCode),
                lease);
        }

        private ActionReceipt ToReceipt(
            ActionEnvelope action,
            AgentActionPerformance performance,
            WriteLease lease)
        {
            ReasonCodeDefinition reason;
            string reasonCode =
                AgentRuntimeGateway.NormalizeReason(
                    performance.ReasonCode);
            AgentReasonCodesV1.TryGet(
                reasonCode,
                out reason);
            ReconcileKind reconcile =
                performance.ReconcileKind;
            if (!reason.AllowedReconcileKinds.Contains(
                    reconcile))
            {
                reconcile =
                    reason.AllowedReconcileKinds[0];
            }
            return new ActionReceipt
            {
                ActionId = action.ActionId,
                AuditSequence = 0,
                Terminal = true,
                Outcome = performance.Outcome,
                EvidenceKind = performance.EvidenceKind,
                ReasonCode = reasonCode,
                ReconcileKind = reconcile,
                Retryable = reason.Retryable,
                ActualTargetId =
                    performance.ActualTargetId,
                FocusVerified =
                    performance.FocusVerified,
                BeforeObservationId =
                    action.ObservationId,
                AfterObservationId =
                    performance.AfterObservationId,
                LeaseState = ToContractLeaseState(lease),
                DomainResult = performance.DomainResult
            };
        }

        private static ActionReceiptRecord ToLedgerReceipt(
            ActionReceipt receipt)
        {
            return new ActionReceiptRecord(
                receipt.ActionId,
                receipt.Terminal,
                ToLedgerOutcome(receipt.Outcome),
                receipt.ReasonCode,
                ToLedgerReconcile(receipt.ReconcileKind),
                receipt.Retryable)
            {
                ContractReceipt = receipt
            };
        }

        private static ActionReceipt
            DeliveryUnknownContractReceipt(
                ActionEnvelope action,
                ActionReceipt terminalReceipt)
        {
            return new ActionReceipt
            {
                ActionId = action.ActionId,
                AuditSequence =
                    terminalReceipt?.AuditSequence ?? 0,
                Terminal = true,
                Outcome = ActionOutcome.Unknown,
                EvidenceKind =
                    EvidenceKind.ReconciliationRequired,
                ReasonCode = "reconcile_required",
                ReconcileKind =
                    ReconcileKind.ManualRequired,
                Retryable = false,
                ActualTargetId =
                    terminalReceipt?.ActualTargetId,
                FocusVerified = false,
                BeforeObservationId =
                    terminalReceipt
                        ?.BeforeObservationId
                    ?? action.ObservationId,
                AfterObservationId =
                    terminalReceipt?.AfterObservationId,
                LeaseState =
                    terminalReceipt?.LeaseState
                    ?? LeaseState.Revoked
            };
        }

        private static LeaseState ToContractLeaseState(
            WriteLease lease)
        {
            if (lease == null)
                return LeaseState.Revoked;
            return lease.State switch
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
            };
        }

        private static ActionReceiptOutcome ToLedgerOutcome(
            ActionOutcome value)
        {
            return value switch
            {
                ActionOutcome.InputDispatched =>
                    ActionReceiptOutcome.InputDispatched,
                ActionOutcome.EffectObserved =>
                    ActionReceiptOutcome.EffectObserved,
                ActionOutcome.DomainCommitted =>
                    ActionReceiptOutcome.DomainCommitted,
                ActionOutcome.Unknown =>
                    ActionReceiptOutcome.Unknown,
                _ => ActionReceiptOutcome.Rejected
            };
        }

        private static ActionReconcileKind ToLedgerReconcile(
            ReconcileKind value)
        {
            return value switch
            {
                ReconcileKind.DomainAuthoritative =>
                    ActionReconcileKind.DomainAuthoritative,
                ReconcileKind.VisualAmbiguous =>
                    ActionReconcileKind.VisualAmbiguous,
                ReconcileKind.ManualRequired =>
                    ActionReconcileKind.ManualRequired,
                _ => ActionReconcileKind.None
            };
        }

        private static ReconcileKind ToContractReconcile(
            ActionReconcileKind value)
        {
            return value switch
            {
                ActionReconcileKind.DomainAuthoritative =>
                    ReconcileKind.DomainAuthoritative,
                ActionReconcileKind.VisualAmbiguous =>
                    ReconcileKind.VisualAmbiguous,
                ActionReconcileKind.ManualRequired =>
                    ReconcileKind.ManualRequired,
                _ => ReconcileKind.None
            };
        }

        private static string NamespaceKey(
            string principalId,
            string sessionId,
            string value)
        {
            return principalId.Length + ":" + principalId
                + sessionId.Length + ":" + sessionId
                + value.Length + ":" + value;
        }

        private void RemoveInFlight(
            string actionKey,
            string idempotencyKey)
        {
            InFlightAction removed = null;
            lock (_sync)
            {
                _inFlightByAction.TryGetValue(
                    actionKey,
                    out removed);
                _inFlightByAction.Remove(actionKey);
                _inFlightByIdempotency.Remove(
                    idempotencyKey);
            }
            removed?.ResponseDelivery.TrySetResult(
                AgentRuntimeResponseDeliveryDisposition
                    .NotApplicable);
        }

        private void FinishResponseDelivery(
            string actionKey,
            string idempotencyKey,
            AgentRuntimeResponseDeliveryDisposition disposition)
        {
            InFlightAction removed = null;
            lock (_sync)
            {
                _inFlightByAction.TryGetValue(
                    actionKey,
                    out removed);
                _inFlightByAction.Remove(actionKey);
                _inFlightByIdempotency.Remove(
                    idempotencyKey);
            }
            removed?.ResponseDelivery.TrySetResult(
                disposition);
        }

        private bool PublishOwnerResponseCompletionAndRemoveInFlight(
            string actionKey,
            string idempotencyKey,
            ActionReceipt receipt,
            AgentRuntimeResponseCompletion completion,
            ResponseCompletionSlot slot,
            WriteLease lease,
            bool executionReservationOwned,
            bool responseDeliveryDependent)
        {
            bool publish = completion != null
                && receipt != null;
            if (executionReservationOwned
                && lease != null)
            {
                if (!publish)
                {
                    _leases.CompleteActionExecution(
                        lease.LeaseId,
                        retainShutdownDelivery: false);
                }
            }
            if (publish)
            {
                if (responseDeliveryDependent
                    && (lease?.Kind
                            != WriteLeaseKind.Shutdown
                        || !_leases
                            .MarkShutdownDeliveryPending(
                                lease.LeaseId)))
                {
                    completion.Abort();
                    RemoveInFlight(
                        actionKey,
                        idempotencyKey);
                    return false;
                }
                slot.Completion = completion;
                if (!responseDeliveryDependent)
                {
                    RemoveInFlight(
                        actionKey,
                        idempotencyKey);
                }
                return true;
            }
            completion?.Abort();
            RemoveInFlight(
                actionKey,
                idempotencyKey);
            return true;
        }

        private static async Task<AgentRuntimeActionExecutionResult>
            AwaitOwnerAsync(
                Task<ActionReceipt> task,
                ResponseCompletionSlot slot)
        {
            ActionReceipt receipt =
                await task.ConfigureAwait(false);
            return new AgentRuntimeActionExecutionResult(
                receipt,
                slot.Completion,
                slot.Completion == null
                    ? AgentRuntimeResponseDeliveryDisposition
                        .NotApplicable
                    : AgentRuntimeResponseDeliveryDisposition
                        .OwnerPending);
        }

        private static async Task<AgentRuntimeActionExecutionResult>
            AwaitReplayAsync(Task<ActionReceipt> task)
        {
            ActionReceipt receipt =
                await task.ConfigureAwait(false);
            return new AgentRuntimeActionExecutionResult(
                receipt,
                null);
        }

        private async Task<AgentRuntimeActionExecutionResult>
            AwaitReplayAsync(
                Task<ActionReceipt> task,
                Task<AgentRuntimeResponseDeliveryDisposition>
                    responseDelivery,
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                CancellationToken cancellationToken)
        {
            ActionReceipt receipt =
                await task.WaitAsync(cancellationToken)
                    .ConfigureAwait(false);
            AgentRuntimeResponseDeliveryDisposition disposition =
                await responseDelivery
                    .WaitAsync(cancellationToken)
                    .ConfigureAwait(false);
            if (disposition
                == AgentRuntimeResponseDeliveryDisposition.Unknown)
            {
                ActionLookupResult lookup = _ledger.Get(
                    context.Principal.SecurityPrincipalId,
                    action.SessionId,
                    action.ActionId);
                receipt = lookup.Receipt?.ContractReceipt
                    ?? throw new InvalidOperationException(
                        "audit_unavailable");
            }
            return new AgentRuntimeActionExecutionResult(
                receipt,
                null,
                disposition);
        }

        private sealed class ActionAuditState
        {
            public ActionAuditState(
                string correlationId,
                string canonicalHash,
                string consentPurpose)
            {
                CorrelationId = correlationId;
                CanonicalHash = canonicalHash;
                ConsentPurpose = consentPurpose;
                BeforeFrameReasonCode =
                    "keyframe_not_yet_resolved";
                AfterFrameReasonCode =
                    "after_capture_not_yet_attempted";
            }

            public string CorrelationId { get; }
            public string CanonicalHash { get; }
            public string ConsentPurpose { get; }
            public string BeforeFrameId;
            public string BeforeFrameHash;
            public string BeforeFrameReasonCode;
            public string AfterObservationId;
            public string AfterFrameId;
            public string AfterFrameHash;
            public string AfterFrameReasonCode;
            public AgentRuntimeAuditCommit TerminalCommit;
        }

        private sealed class InFlightAction
        {
            public InFlightAction(
                string canonicalHash,
                Task<ActionReceipt> task)
            {
                CanonicalHash = canonicalHash;
                Task = task;
                ResponseDelivery =
                    new TaskCompletionSource<
                        AgentRuntimeResponseDeliveryDisposition>(
                            TaskCreationOptions
                                .RunContinuationsAsynchronously);
            }

            public string CanonicalHash { get; }
            public Task<ActionReceipt> Task { get; }
            public TaskCompletionSource<
                AgentRuntimeResponseDeliveryDisposition>
                    ResponseDelivery { get; }
        }

        private sealed class ResponseCompletionSlot
        {
            public AgentRuntimeResponseCompletion Completion;
        }
    }
}
