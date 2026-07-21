using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Dev-only Lockbox S0 orchestration state machine.
    ///
    /// This type deliberately has no PanelHost, WebOverlay, socket, timer, or environment
    /// dependencies.  A future runtime adapter must perform those operations and report their
    /// exact outcomes here; merely constructing this coordinator does not enable the S0 route.
    /// </summary>
    public sealed class DevLockboxS0Coordinator
    {
        public const string RequiredEnvironmentValue = "1";
        public const string RequiredSource = "as2-chest-s0";
        public const string RequiredFixture = "insurance-safe-s0-v1";
        // S0 has exactly one business write intent per flow; its complete call-id domain is {1}.
        public const int MaximumFlowCallId = 1;
        public const int MaximumWebDocumentEpoch = int.MaxValue;
        public const int MaximumIdentityPartLength = 256;

        public enum FlowState
        {
            Idle,
            OpenQueued,
            OpenBindUnknown,
            PanelBound,
            RevokePending,
            ResultPending,
            ResultApplied,
            ReconcileRequired,
            KnownTerminal
        }

        public enum RouteOrigin
        {
            TrustedAs2Socket,
            WebMessage,
            Http,
            Other
        }

        public enum BeginRejection
        {
            None,
            InvalidRequest,
            Busy,
            NotDevRepository,
            EnvironmentGateClosed,
            UntrustedOrigin,
            SourceMismatch,
            FixtureMismatch,
            PanelOrchestrationBusy,
            InvalidDocumentEpoch,
            DocumentEpochMismatch,
            InvalidIdentity
        }

        public enum BindQueryConclusion
        {
            Bound,
            Unbound
        }

        public enum KnownOpenFailure
        {
            PostNotDelivered,
            WebBindRejected
        }

        public enum LimitedResult
        {
            Success,
            Cancel,
            Failure
        }

        public enum AuthorityQueryConclusion
        {
            AppliedSuccess,
            AppliedCancel,
            AppliedFailure,
            ConfirmedNoWrite,
            Expired
        }

        public sealed class BeginRequest
        {
            public bool IsDevRepository { get; set; }
            public string EnvironmentGateValue { get; set; }
            public RouteOrigin Origin { get; set; }
            public string Source { get; set; }
            public string Fixture { get; set; }
            public bool IsPanelOrchestrationIdle { get; set; }
            public long WebDocumentEpoch { get; set; }
        }

        /// <summary>
        /// All three values are reserved before a tracked open is enqueued.  Web receives only
        /// FlowHandle and PanelInstanceId; ChestSession remains outside this type and outside Web.
        /// </summary>
        public sealed class AttemptIdentity
        {
            internal AttemptIdentity(string flowHandle, string requestToken,
                string panelInstanceId, long webDocumentEpoch)
            {
                FlowHandle = flowHandle;
                RequestToken = requestToken;
                PanelInstanceId = panelInstanceId;
                WebDocumentEpoch = webDocumentEpoch;
            }

            public string FlowHandle { get; private set; }
            public string RequestToken { get; private set; }
            public string PanelInstanceId { get; private set; }
            public long WebDocumentEpoch { get; private set; }
        }

        private readonly object _sync = new object();
        private readonly Func<string> _flowHandleFactory;
        private readonly Func<string> _requestTokenFactory;
        private readonly Func<string> _panelInstanceIdFactory;
        private readonly HashSet<string> _usedIdentityParts =
            new HashSet<string>(StringComparer.Ordinal);

        private long _webDocumentEpoch;
        private FlowState _state;
        private AttemptIdentity _activeIdentity;
        private bool _openExecutionStarted;
        private bool _domMayExist;
        private bool _documentEpochChanged;
        private int _submittedCallId;
        private int _unknownFlowCallId;
        private int _observedCallWatermark;
        private LimitedResult? _submittedResult;

        public DevLockboxS0Coordinator(long initialWebDocumentEpoch,
            Func<string> flowHandleFactory = null,
            Func<string> requestTokenFactory = null,
            Func<string> panelInstanceIdFactory = null)
        {
            if (!IsValidWebDocumentEpoch(initialWebDocumentEpoch))
                throw new ArgumentOutOfRangeException(nameof(initialWebDocumentEpoch));

            _webDocumentEpoch = initialWebDocumentEpoch;
            _flowHandleFactory = flowHandleFactory ?? (() => "chest.flow." + Guid.NewGuid().ToString("N"));
            _requestTokenFactory = requestTokenFactory ?? (() => "chest.open." + Guid.NewGuid().ToString("N"));
            _panelInstanceIdFactory = panelInstanceIdFactory ?? (() => "panel.lockbox." + Guid.NewGuid().ToString("N"));
            _state = FlowState.Idle;
        }

        public FlowState State
        {
            get { lock (_sync) return _state; }
        }

        public long WebDocumentEpoch
        {
            get { lock (_sync) return _webDocumentEpoch; }
        }

        public AttemptIdentity ActiveIdentity
        {
            get { lock (_sync) return _activeIdentity; }
        }

        public int SubmittedFlowCallId
        {
            get { lock (_sync) return _submittedCallId; }
        }

        public int UnknownFlowCallId
        {
            get { lock (_sync) return _unknownFlowCallId; }
        }

        public int ObservedCallWatermark
        {
            get { lock (_sync) return _observedCallWatermark; }
        }

        public LimitedResult? SubmittedResult
        {
            get { lock (_sync) return _submittedResult; }
        }

        public bool HoldsGlobalPause
        {
            get { lock (_sync) return _state != FlowState.Idle; }
        }

        public bool ShouldRejectOtherPanelOpen
        {
            get { lock (_sync) return _state != FlowState.Idle; }
        }

        public bool ShouldBlockGenericUnpause
        {
            get { lock (_sync) return _state != FlowState.Idle; }
        }

        public bool CanRebuildWebDocument
        {
            get { lock (_sync) return _state == FlowState.Idle; }
        }

        public bool CanIssueCausalResultQuery
        {
            get
            {
                lock (_sync)
                    return _state == FlowState.ReconcileRequired && _unknownFlowCallId > 0;
            }
        }

        public bool DocumentEpochChanged
        {
            get { lock (_sync) return _documentEpochChanged; }
        }

        /// <summary>
        /// Release requires both an AS2-known terminal and proof that no exact DOM instance can
        /// remain.  Queue acceptance, bind/result unknown, and a new empty document never qualify.
        /// </summary>
        public bool CanReleaseGlobalPause
        {
            get { lock (_sync) return _state == FlowState.KnownTerminal && !_domMayExist; }
        }

        public bool TryBegin(BeginRequest request, out AttemptIdentity identity,
            out BeginRejection rejection)
        {
            lock (_sync)
            {
                identity = null;
                rejection = ValidateBeginLocked(request);
                if (rejection != BeginRejection.None) return false;

                string flowHandle;
                string requestToken;
                string panelInstanceId;
                try
                {
                    flowHandle = _flowHandleFactory();
                    requestToken = _requestTokenFactory();
                    panelInstanceId = _panelInstanceIdFactory();
                }
                catch
                {
                    rejection = BeginRejection.InvalidIdentity;
                    return false;
                }

                if (!IsFreshIdentityPartLocked(flowHandle)
                    || !IsFreshIdentityPartLocked(requestToken)
                    || !IsFreshIdentityPartLocked(panelInstanceId)
                    || string.Equals(flowHandle, requestToken, StringComparison.Ordinal)
                    || string.Equals(flowHandle, panelInstanceId, StringComparison.Ordinal)
                    || string.Equals(requestToken, panelInstanceId, StringComparison.Ordinal))
                {
                    rejection = BeginRejection.InvalidIdentity;
                    return false;
                }

                _usedIdentityParts.Add(flowHandle);
                _usedIdentityParts.Add(requestToken);
                _usedIdentityParts.Add(panelInstanceId);
                _activeIdentity = new AttemptIdentity(flowHandle, requestToken,
                    panelInstanceId, request.WebDocumentEpoch);
                _openExecutionStarted = false;
                _domMayExist = false;
                _documentEpochChanged = false;
                _submittedCallId = 0;
                _unknownFlowCallId = 0;
                _observedCallWatermark = 0;
                _submittedResult = null;
                _state = FlowState.OpenQueued;
                identity = _activeIdentity;
                return true;
            }
        }

        /// <summary>Queue-side pre-execution recheck.  A canceled or stale token returns false.</summary>
        public bool CanExecuteQueuedOpen(string requestToken)
        {
            lock (_sync)
                return _state == FlowState.OpenQueued && !_openExecutionStarted
                    && MatchesRequestTokenLocked(requestToken);
        }

        public bool MarkQueuedOpenExecuting(string requestToken)
        {
            lock (_sync)
            {
                if (_state != FlowState.OpenQueued || _openExecutionStarted
                    || !MatchesRequestTokenLocked(requestToken)) return false;
                _openExecutionStarted = true;
                _domMayExist = true;
                return true;
            }
        }

        /// <summary>Cancels only an exact open that has not started executing.</summary>
        public bool CancelQueuedOpenExact(string requestToken)
        {
            lock (_sync)
            {
                if (_state != FlowState.OpenQueued || _openExecutionStarted
                    || !MatchesRequestTokenLocked(requestToken)) return false;
                _state = FlowState.RevokePending;
                _domMayExist = false;
                return true;
            }
        }

        public bool MarkKnownOpenFailure(string flowHandle, string panelInstanceId,
            long webDocumentEpoch, KnownOpenFailure failure)
        {
            lock (_sync)
            {
                if (failure != KnownOpenFailure.PostNotDelivered
                    && failure != KnownOpenFailure.WebBindRejected) return false;
                if ((_state != FlowState.OpenQueued && _state != FlowState.OpenBindUnknown)
                    || !_openExecutionStarted
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;

                _state = FlowState.RevokePending;
                _domMayExist = failure == KnownOpenFailure.WebBindRejected;
                return true;
            }
        }

        public bool MarkBindTimeout(string flowHandle, string panelInstanceId,
            long webDocumentEpoch)
        {
            lock (_sync)
            {
                if (_state != FlowState.OpenQueued || !_openExecutionStarted
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;
                _state = FlowState.OpenBindUnknown;
                _domMayExist = true;
                return true;
            }
        }

        public bool TryAcknowledgeBind(string flowHandle, string panelInstanceId,
            long webDocumentEpoch)
        {
            lock (_sync)
            {
                if (_state != FlowState.OpenQueued || !_openExecutionStarted
                    || _documentEpochChanged
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;
                _state = FlowState.PanelBound;
                _domMayExist = true;
                return true;
            }
        }

        public bool ApplyExactBindQuery(string flowHandle, string panelInstanceId,
            long webDocumentEpoch, BindQueryConclusion conclusion)
        {
            lock (_sync)
            {
                if (conclusion != BindQueryConclusion.Bound
                    && conclusion != BindQueryConclusion.Unbound) return false;
                if (_state != FlowState.OpenBindUnknown || _documentEpochChanged
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;

                if (conclusion == BindQueryConclusion.Bound)
                {
                    _state = FlowState.PanelBound;
                    _domMayExist = true;
                }
                else
                {
                    _state = FlowState.RevokePending;
                    _domMayExist = false;
                }
                return true;
            }
        }

        public bool TrySubmitResult(string flowHandle, string panelInstanceId,
            long webDocumentEpoch, int flowCallId, LimitedResult result)
        {
            lock (_sync)
            {
                if (result != LimitedResult.Success && result != LimitedResult.Cancel
                    && result != LimitedResult.Failure) return false;
                if (_state != FlowState.PanelBound || _documentEpochChanged
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch)
                    || flowCallId != 1 || flowCallId > MaximumFlowCallId
                    || _submittedCallId != 0 || _submittedResult.HasValue)
                    return false;

                _submittedCallId = flowCallId;
                _submittedResult = result;
                _state = FlowState.ResultPending;
                return true;
            }
        }

        public bool TryAcknowledgeResult(string flowHandle, string panelInstanceId,
            long webDocumentEpoch, int flowCallId, LimitedResult appliedResult,
            int observedCallWatermark, bool authorityTerminal)
        {
            lock (_sync)
            {
                if (_state != FlowState.ResultPending
                    || !MatchesSubmittedResultLocked(flowHandle, panelInstanceId,
                        webDocumentEpoch, flowCallId, appliedResult)
                    || observedCallWatermark < flowCallId
                    || (appliedResult != LimitedResult.Success && !authorityTerminal))
                    return false;

                _observedCallWatermark = Math.Max(_observedCallWatermark, observedCallWatermark);
                _state = authorityTerminal ? FlowState.KnownTerminal : FlowState.ResultApplied;
                return true;
            }
        }

        public bool MarkResultTransportUnknown(string flowHandle, string panelInstanceId,
            long webDocumentEpoch, int flowCallId)
        {
            lock (_sync)
            {
                if (_state != FlowState.ResultPending
                    || flowCallId != _submittedCallId
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;
                _unknownFlowCallId = flowCallId;
                _state = FlowState.ReconcileRequired;
                return true;
            }
        }

        /// <summary>
        /// Web may have posted its one allowed result while Host observed nothing.  An exact
        /// result_query is then evidence of delivery uncertainty, not evidence of a particular
        /// result.  Reserve callId=1 and enter causal reconciliation without recording an enum or
        /// replaying a write; only AS2's ordered watermark/no-write reply may settle it.
        /// </summary>
        public bool MarkExternalResultDeliveryUnknown(string flowHandle, string panelInstanceId,
            long webDocumentEpoch, int flowCallId)
        {
            lock (_sync)
            {
                if (_state != FlowState.PanelBound || _documentEpochChanged
                    || flowCallId != 1 || flowCallId > MaximumFlowCallId
                    || _submittedCallId != 0 || _submittedResult.HasValue
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;
                _submittedCallId = flowCallId;
                _unknownFlowCallId = flowCallId;
                _state = FlowState.ReconcileRequired;
                return true;
            }
        }

        public bool ApplyAuthorityQuery(string flowHandle, string panelInstanceId,
            long webDocumentEpoch, int unknownFlowCallId, int observedCallWatermark,
            AuthorityQueryConclusion conclusion, bool authorityTerminal)
        {
            lock (_sync)
            {
                if (_state != FlowState.ReconcileRequired || _unknownFlowCallId <= 0
                    || unknownFlowCallId != _unknownFlowCallId
                    || observedCallWatermark < unknownFlowCallId
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch)
                    || !QueryConclusionMatchesSubmittedResultLocked(conclusion)
                    || (conclusion != AuthorityQueryConclusion.AppliedSuccess
                        && !authorityTerminal))
                    return false;

                _observedCallWatermark = Math.Max(_observedCallWatermark, observedCallWatermark);
                _unknownFlowCallId = 0;
                if (conclusion == AuthorityQueryConclusion.AppliedSuccess && !authorityTerminal)
                    _state = FlowState.ResultApplied;
                else
                    _state = FlowState.KnownTerminal;
                return true;
            }
        }

        public bool MarkSuccessAuthorityTerminal(string flowHandle, string panelInstanceId,
            long webDocumentEpoch, int observedCallWatermark)
        {
            lock (_sync)
            {
                if (_state != FlowState.ResultApplied
                    || _submittedResult != LimitedResult.Success
                    || observedCallWatermark < _submittedCallId
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;
                _observedCallWatermark = Math.Max(_observedCallWatermark, observedCallWatermark);
                _state = FlowState.KnownTerminal;
                return true;
            }
        }

        public bool AcknowledgeKnownRevocation(string flowHandle, string panelInstanceId,
            long webDocumentEpoch)
        {
            lock (_sync)
            {
                if (_state != FlowState.RevokePending
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;
                _state = FlowState.KnownTerminal;
                return true;
            }
        }

        /// <summary>
        /// Marks an AS2-known scene/authority expiration.  It does not claim that a possible DOM
        /// instance was closed; exact close or explicit old-document teardown proof is still needed.
        /// </summary>
        public bool ConfirmAuthorityExpired(string flowHandle, string panelInstanceId,
            long webDocumentEpoch)
        {
            lock (_sync)
            {
                if (_state == FlowState.Idle || _activeIdentity == null
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;
                _state = FlowState.KnownTerminal;
                _unknownFlowCallId = 0;
                return true;
            }
        }

        /// <summary>
        /// Records the trusted PanelHost proof that a tracked open completed without accepting a
        /// Web post.  This is intentionally limited to an already-terminal exact attempt; an
        /// accepted Web post must still complete the exact close handshake instead.
        /// </summary>
        public bool ConfirmTrackedOpenDidNotReachDom(string flowHandle, string panelInstanceId,
            long webDocumentEpoch)
        {
            lock (_sync)
            {
                if (_state != FlowState.KnownTerminal || _activeIdentity == null
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;
                _domMayExist = false;
                return true;
            }
        }

        public bool RecordExactCloseAck(string flowHandle, string panelInstanceId,
            long webDocumentEpoch)
        {
            lock (_sync)
            {
                if (_state == FlowState.Idle || _activeIdentity == null
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch))
                    return false;

                _domMayExist = false;
                if ((_state == FlowState.OpenQueued && _openExecutionStarted)
                    || _state == FlowState.OpenBindUnknown || _state == FlowState.PanelBound)
                    _state = FlowState.RevokePending;
                return true;
            }
        }

        /// <summary>
        /// A monotonically newer top-level document invalidates all later messages from the old
        /// Web document.  It does not overwrite Host/AS2 authority state: navigation is a DOM
        /// lifecycle fact, not by itself a result-query or no-write conclusion.
        /// </summary>
        public bool AdvanceWebDocumentEpoch(long newWebDocumentEpoch)
        {
            lock (_sync)
            {
                if (!IsValidWebDocumentEpoch(newWebDocumentEpoch)
                    || newWebDocumentEpoch <= _webDocumentEpoch) return false;
                _webDocumentEpoch = newWebDocumentEpoch;
                if (_state != FlowState.Idle)
                {
                    _documentEpochChanged = true;
                }
                return true;
            }
        }

        /// <summary>
        /// Explicit proof that the old exact document was torn down.  Merely observing an empty
        /// DOM must not call this method.  Once teardown is proved, pre-result flows revoke their
        /// no-write authority; an in-flight result becomes a causal query instead of a resend.
        /// </summary>
        public bool ConfirmOldDocumentTeardown(string flowHandle, string panelInstanceId,
            long oldWebDocumentEpoch)
        {
            lock (_sync)
            {
                if (_state == FlowState.Idle || !_documentEpochChanged
                    || !MatchesIdentityLocked(flowHandle, panelInstanceId, oldWebDocumentEpoch))
                    return false;
                _domMayExist = false;
                if (_state == FlowState.OpenQueued || _state == FlowState.OpenBindUnknown
                    || _state == FlowState.PanelBound)
                {
                    _state = FlowState.RevokePending;
                }
                else if (_state == FlowState.ResultPending)
                {
                    _unknownFlowCallId = _submittedCallId;
                    _state = FlowState.ReconcileRequired;
                }
                return true;
            }
        }

        public bool TryReleaseGlobalPauseAndReset()
        {
            lock (_sync)
            {
                if (_state != FlowState.KnownTerminal || _domMayExist) return false;
                _activeIdentity = null;
                _openExecutionStarted = false;
                _documentEpochChanged = false;
                _submittedCallId = 0;
                _unknownFlowCallId = 0;
                _observedCallWatermark = 0;
                _submittedResult = null;
                _state = FlowState.Idle;
                return true;
            }
        }

        public static bool TryMapLockboxOutcome(string coreOutcome, bool userCancelled,
            out LimitedResult result)
        {
            result = LimitedResult.Failure;
            if (userCancelled)
            {
                if (!string.IsNullOrEmpty(coreOutcome)) return false;
                result = LimitedResult.Cancel;
                return true;
            }

            if (string.Equals(coreOutcome, "success", StringComparison.Ordinal)
                || string.Equals(coreOutcome, "partial_success", StringComparison.Ordinal))
            {
                result = LimitedResult.Success;
                return true;
            }
            if (string.Equals(coreOutcome, "fail", StringComparison.Ordinal))
            {
                result = LimitedResult.Failure;
                return true;
            }
            return false;
        }

        private BeginRejection ValidateBeginLocked(BeginRequest request)
        {
            if (request == null) return BeginRejection.InvalidRequest;
            if (_state != FlowState.Idle) return BeginRejection.Busy;
            if (!request.IsDevRepository) return BeginRejection.NotDevRepository;
            if (!string.Equals(request.EnvironmentGateValue, RequiredEnvironmentValue,
                StringComparison.Ordinal)) return BeginRejection.EnvironmentGateClosed;
            if (request.Origin != RouteOrigin.TrustedAs2Socket)
                return BeginRejection.UntrustedOrigin;
            if (!string.Equals(request.Source, RequiredSource, StringComparison.Ordinal))
                return BeginRejection.SourceMismatch;
            if (!string.Equals(request.Fixture, RequiredFixture, StringComparison.Ordinal))
                return BeginRejection.FixtureMismatch;
            if (!request.IsPanelOrchestrationIdle)
                return BeginRejection.PanelOrchestrationBusy;
            if (!IsValidWebDocumentEpoch(request.WebDocumentEpoch))
                return BeginRejection.InvalidDocumentEpoch;
            if (request.WebDocumentEpoch != _webDocumentEpoch)
                return BeginRejection.DocumentEpochMismatch;
            return BeginRejection.None;
        }

        private bool IsFreshIdentityPartLocked(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > MaximumIdentityPartLength
                || char.IsWhiteSpace(value[0]) || char.IsWhiteSpace(value[value.Length - 1])
                || _usedIdentityParts.Contains(value)) return false;
            for (int i = 0; i < value.Length; i++)
            {
                if (char.IsControl(value[i])) return false;
            }
            return true;
        }

        private static bool IsValidWebDocumentEpoch(long value)
        {
            return value >= 1 && value <= MaximumWebDocumentEpoch;
        }

        private bool MatchesRequestTokenLocked(string requestToken)
        {
            return _activeIdentity != null && string.Equals(_activeIdentity.RequestToken,
                requestToken, StringComparison.Ordinal);
        }

        private bool MatchesIdentityLocked(string flowHandle, string panelInstanceId,
            long webDocumentEpoch)
        {
            return _activeIdentity != null
                && string.Equals(_activeIdentity.FlowHandle, flowHandle, StringComparison.Ordinal)
                && string.Equals(_activeIdentity.PanelInstanceId, panelInstanceId, StringComparison.Ordinal)
                && _activeIdentity.WebDocumentEpoch == webDocumentEpoch;
        }

        private bool MatchesSubmittedResultLocked(string flowHandle, string panelInstanceId,
            long webDocumentEpoch, int flowCallId, LimitedResult appliedResult)
        {
            return MatchesIdentityLocked(flowHandle, panelInstanceId, webDocumentEpoch)
                && _submittedResult.HasValue && _submittedResult.Value == appliedResult
                && _submittedCallId == flowCallId;
        }

        private bool QueryConclusionMatchesSubmittedResultLocked(AuthorityQueryConclusion conclusion)
        {
            if (conclusion == AuthorityQueryConclusion.ConfirmedNoWrite
                || conclusion == AuthorityQueryConclusion.Expired) return true;
            if (!_submittedResult.HasValue) return false;
            return (conclusion == AuthorityQueryConclusion.AppliedSuccess
                    && _submittedResult.Value == LimitedResult.Success)
                || (conclusion == AuthorityQueryConclusion.AppliedCancel
                    && _submittedResult.Value == LimitedResult.Cancel)
                || (conclusion == AuthorityQueryConclusion.AppliedFailure
                    && _submittedResult.Value == LimitedResult.Failure);
        }

    }
}
