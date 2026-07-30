using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Gateway
{
    /// <summary>
    /// Immutable facts which the trusted Launcher consent surface must show.
    /// No field in this request is accepted from a client without first being
    /// rebound to authenticated principal, preview, grant, and session truth.
    /// </summary>
    internal sealed class AgentHairConsentPresentationRequest
    {
        internal AgentHairConsentPresentationRequest(
            string connectionId,
            PrincipalCredential principal,
            string observationGrantId,
            string sessionId,
            ulong lifecycleGeneration,
            string targetId,
            HairAppearancePreview preview,
            LauncherTrustedHumanInteractionTicket interaction = null)
        {
            ConnectionId = Required(connectionId, nameof(connectionId));
            Principal = principal
                ?? throw new ArgumentNullException(nameof(principal));
            ObservationGrantId = Required(
                observationGrantId,
                nameof(observationGrantId));
            SessionId = Required(sessionId, nameof(sessionId));
            if (lifecycleGeneration == 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(lifecycleGeneration));
            }
            LifecycleGeneration = lifecycleGeneration;
            TargetId = Required(targetId, nameof(targetId));
            Preview = preview
                ?? throw new ArgumentNullException(nameof(preview));
            Interaction = interaction;
        }

        public string ConnectionId { get; }
        internal PrincipalCredential Principal { get; }
        public string ClientInstanceId
        {
            get { return Principal.ClientInstanceId; }
        }
        public string SecurityPrincipalId
        {
            get { return Principal.SecurityPrincipalId; }
        }
        public AgentPrincipalKind PrincipalKind
        {
            get { return Principal.PrincipalKind; }
        }
        public string ObservationGrantId { get; }
        public string SessionId { get; }
        public ulong LifecycleGeneration { get; }
        public string TargetId { get; }
        public HairAppearancePreview Preview { get; }
        internal LauncherTrustedHumanInteractionTicket
            Interaction { get; }

        private static string Required(string value, string name)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException(
                    "A non-empty value is required.",
                    name);
            return value;
        }
    }

    internal sealed class AgentHairConsentPresentationResult
    {
        private AgentHairConsentPresentationResult(
            bool approved,
            string consentReceipt,
            string reasonCode)
        {
            Approved = approved;
            ConsentReceipt = consentReceipt;
            ReasonCode = reasonCode;
        }

        public bool Approved { get; }
        public string ConsentReceipt { get; }
        public string ReasonCode { get; }

        /// <summary>
        /// May only be returned after a human explicitly approved the exact
        /// immutable request on a neutral Launcher-owned security surface.
        /// </summary>
        public static AgentHairConsentPresentationResult Allow(
            string consentReceipt)
        {
            if (string.IsNullOrWhiteSpace(consentReceipt))
            {
                throw new ArgumentException(
                    "A trusted consent receipt is required.",
                    nameof(consentReceipt));
            }
            return new AgentHairConsentPresentationResult(
                true,
                consentReceipt,
                null);
        }

        public static AgentHairConsentPresentationResult Reject()
        {
            return new AgentHairConsentPresentationResult(
                false,
                null,
                "consent_required");
        }

        public static AgentHairConsentPresentationResult Unavailable()
        {
            return new AgentHairConsentPresentationResult(
                false,
                null,
                "human_intervention_required");
        }
    }

    /// <summary>
    /// Host boundary for the real neutral consent UI. Implementations must
    /// marshal to the Launcher UI thread, publish the consent HWND as
    /// human-only before showing it, and complete only from a human decision.
    /// Before completing an Allow, the host must close/unpublish that surface
    /// and acknowledge the same trusted human reauthorization on the session;
    /// the issuer's post-presentation authority check otherwise fails closed.
    /// Persona/model output and wire arguments are never approval evidence.
    /// </summary>
    internal interface IAgentHairConsentPresenter
    {
        Task<AgentHairConsentPresentationResult> PresentAsync(
            AgentHairConsentPresentationRequest request,
            CancellationToken cancellationToken);
    }

    internal sealed class FailClosedAgentHairConsentPresenter
        : IAgentHairConsentPresenter
    {
        public Task<AgentHairConsentPresentationResult> PresentAsync(
            AgentHairConsentPresentationRequest request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(
                AgentHairConsentPresentationResult.Unavailable());
        }
    }

    internal sealed class AgentHairConsentIssuanceResult
    {
        private AgentHairConsentIssuanceResult(
            HairConsentDescriptorV1 descriptor,
            string reasonCode)
        {
            Descriptor = descriptor;
            ReasonCode = reasonCode;
        }

        public bool Success
        {
            get { return Descriptor != null; }
        }

        public HairConsentDescriptorV1 Descriptor { get; }
        public string ReasonCode { get; }

        public static AgentHairConsentIssuanceResult Issued(
            HairConsentDescriptorV1 descriptor)
        {
            return new AgentHairConsentIssuanceResult(
                descriptor
                    ?? throw new ArgumentNullException(
                        nameof(descriptor)),
                null);
        }

        public static AgentHairConsentIssuanceResult Rejected(
            string reasonCode)
        {
            if (string.IsNullOrWhiteSpace(reasonCode))
                throw new ArgumentException(
                    "A reason code is required.",
                    nameof(reasonCode));
            return new AgentHairConsentIssuanceResult(
                null,
                reasonCode);
        }
    }

    internal interface IAgentHairConsentIssuanceService
    {
        Task<AgentHairConsentIssuanceResult> RequestAsync(
            AgentHairConsentPresentationRequest request,
            CancellationToken cancellationToken);
    }

    /// <summary>
    /// The only bridge from a trusted human approval to the one-shot domain
    /// token issuer. Rejection, dismissal, cancellation, and absent UI never
    /// mint a token.
    /// </summary>
    internal sealed class AgentHairConsentIssuanceService
        : IAgentHairConsentIssuanceService
    {
        private readonly HairAppearanceConsentBroker _broker;
        private readonly IAgentHairConsentPresenter _presenter;
        private readonly SessionSurfaceRegistry _sessions;
        private readonly ObservationGrantBroker _grants;
        private readonly IAgentHairDomainTargetAuthority
            _hairTargets;

        public AgentHairConsentIssuanceService(
            HairAppearanceModifierTransaction transaction,
            IAgentHairConsentPresenter presenter,
            SessionSurfaceRegistry sessions,
            ObservationGrantBroker grants,
            IAgentHairDomainTargetAuthority hairTargets)
        {
            if (transaction == null)
                throw new ArgumentNullException(nameof(transaction));
            _broker = transaction.ConsentBroker;
            _presenter = presenter
                ?? throw new ArgumentNullException(nameof(presenter));
            _sessions = sessions
                ?? throw new ArgumentNullException(nameof(sessions));
            _grants = grants
                ?? throw new ArgumentNullException(nameof(grants));
            _hairTargets = hairTargets
                ?? throw new ArgumentNullException(
                    nameof(hairTargets));
        }

        public async Task<AgentHairConsentIssuanceResult> RequestAsync(
            AgentHairConsentPresentationRequest request,
            CancellationToken cancellationToken)
        {
            if (request == null)
                throw new ArgumentNullException(nameof(request));
            cancellationToken.ThrowIfCancellationRequested();
            if (!StillAuthorized(
                    request,
                    out string reasonCode))
            {
                return AgentHairConsentIssuanceResult.Rejected(
                    reasonCode);
            }

            AgentHairConsentPresentationResult decision =
                await _presenter.PresentAsync(
                    request,
                    cancellationToken).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            if (decision == null)
            {
                return AgentHairConsentIssuanceResult.Rejected(
                    "human_intervention_required");
            }
            if (!decision.Approved)
            {
                return AgentHairConsentIssuanceResult.Rejected(
                    decision.ReasonCode
                        == "consent_required"
                        ? "consent_required"
                        : "human_intervention_required");
            }
            if (!StillAuthorized(
                    request,
                    out reasonCode))
            {
                return AgentHairConsentIssuanceResult.Rejected(
                    reasonCode);
            }

            HairAppearanceConsentToken token =
                _broker.IssueForNeutralUi(
                    request.Preview,
                    decision.ConsentReceipt,
                    HairAppearanceConsentBroker.MaximumConsentTtl);
            return AgentHairConsentIssuanceResult.Issued(
                new HairConsentDescriptorV1
                {
                    ConsentToken = token.Token,
                    ConsentReceipt =
                        token.ConsentReceiptId,
                    TransactionId =
                        token.TransactionId,
                    PreviewHash = token.PreviewHash,
                    ExpiresInMs = checked((int)
                        HairAppearanceConsentBroker
                            .MaximumConsentTtl
                            .TotalMilliseconds)
                });
        }

        private bool StillAuthorized(
            AgentHairConsentPresentationRequest request,
            out string reasonCode)
        {
            reasonCode = null;
            if (!HairAppearanceValidation
                    .PreviewHashIsAuthentic(
                        request.Preview))
            {
                reasonCode = "arguments_invalid";
                return false;
            }
            if (request.Principal.State
                != CredentialState.Active)
            {
                reasonCode = "credential_revoked";
                return false;
            }
            if (!string.Equals(
                    request.SessionId,
                    request.Preview.Binding.SessionId,
                    StringComparison.Ordinal)
                || request.Preview.Binding
                        .LifecycleGeneration <= 0
                || request.LifecycleGeneration
                    != checked((ulong)request.Preview.Binding
                        .LifecycleGeneration))
            {
                reasonCode = "stale_lifecycle";
                return false;
            }
            SessionSnapshot session = _sessions.GetSnapshot()
                .FindSession(request.SessionId);
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }
            if (session.LifecycleGeneration
                != request.LifecycleGeneration)
            {
                reasonCode = "stale_lifecycle";
                return false;
            }
            if (!_hairTargets.TryAuthorize(
                    request.SessionId,
                    request.TargetId,
                    out reasonCode))
            {
                reasonCode =
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode);
                return false;
            }
            if (!_grants.TryAuthorize(
                    request.ObservationGrantId,
                    request.ClientInstanceId,
                    request.SecurityPrincipalId,
                    request.SessionId,
                    request.TargetId,
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
    }
}
