using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal enum WingsActionHumanDecisionKind
    {
        Allow,
        Reject,
        Dismiss
    }

    /// <summary>
    /// Structured, Host-owned facts shown by a human-only presenter. It does
    /// not accept Persona prose as an executable field.
    /// </summary>
    internal sealed class TrustedWingsActionConsentCard
    {
        internal TrustedWingsActionConsentCard(
            WingsActionIntentV1 intent)
        {
            if (intent == null)
                throw new ArgumentNullException(nameof(intent));
            IntentId = intent.IntentId;
            ActionId = intent.ActionId;
            SessionId = intent.SessionId;
            Slot = intent.Slot;
            SaveBindingId = intent.SaveBindingId;
            LoreViewId = intent.LoreViewId;
            TargetId = intent.TargetId;
            ObservationId = intent.ObservationId;
            Operation = intent.Operation;
            CanonicalArguments =
                intent.CanonicalArguments.GetRawText();
            ArgumentBoundsHash =
                intent.ArgumentBoundsHash;
            Reason = intent.Reason;
            IssuedMonotonic = intent.IssuedMonotonic;
            ExpiresMonotonic = intent.ExpiresMonotonic;
            BindingHash = intent.BindingHash;
        }

        public string IntentId { get; }
        public string ActionId { get; }
        public string SessionId { get; }
        public string Slot { get; }
        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public string TargetId { get; }
        public string ObservationId { get; }
        public string Operation { get; }
        public string CanonicalArguments { get; }
        public string ArgumentBoundsHash { get; }
        public string Reason { get; }
        public long IssuedMonotonic { get; }
        public long ExpiresMonotonic { get; }
        public string BindingHash { get; }
        public int MaximumActions => 1;
        public bool AllowsPersistence => false;
        public bool AllowsExport => false;
    }

    internal sealed class WingsActionHumanDecision
    {
        private WingsActionHumanDecision(
            WingsActionHumanDecisionKind kind,
            string humanInteractionReceiptId,
            bool surfaceClosedAndUnpublished)
        {
            Kind = kind;
            HumanInteractionReceiptId =
                humanInteractionReceiptId;
            SurfaceClosedAndUnpublished =
                surfaceClosedAndUnpublished;
        }

        public WingsActionHumanDecisionKind Kind { get; }
        public string HumanInteractionReceiptId { get; }

        /// <summary>
        /// A presenter may return Allow only after the human-only HWND is
        /// closed and unpublished. The broker rejects any other shape.
        /// </summary>
        public bool SurfaceClosedAndUnpublished { get; }

        internal static WingsActionHumanDecision AllowAfterClose(
            string humanInteractionReceiptId)
        {
            WingsProtocolValue.RequireOpaqueId(
                humanInteractionReceiptId,
                nameof(humanInteractionReceiptId));
            return new WingsActionHumanDecision(
                WingsActionHumanDecisionKind.Allow,
                humanInteractionReceiptId,
                true);
        }

        internal static WingsActionHumanDecision Reject()
        {
            return new WingsActionHumanDecision(
                WingsActionHumanDecisionKind.Reject,
                null,
                true);
        }

        internal static WingsActionHumanDecision Dismiss()
        {
            return new WingsActionHumanDecision(
                WingsActionHumanDecisionKind.Dismiss,
                null,
                true);
        }
    }

    /// <summary>
    /// The production implementation must own a registered
    /// human_only_security_surface. It returns only after closing and
    /// unpublishing that surface.
    /// </summary>
    internal interface IWingsActionConsentPresenter
    {
        Task<WingsActionHumanDecision> PresentAsync(
            TrustedWingsActionConsentCard card,
            CancellationToken cancellationToken);
    }

    internal sealed class FailClosedWingsActionConsentPresenter
        : IWingsActionConsentPresenter
    {
        public Task<WingsActionHumanDecision> PresentAsync(
            TrustedWingsActionConsentCard card,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(
                WingsActionHumanDecision.Dismiss());
        }
    }

    internal interface IWingsActionBindingAuthority
    {
        bool TryValidate(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            out string reasonCode);
    }

    internal sealed class FailClosedWingsActionBindingAuthority
        : IWingsActionBindingAuthority
    {
        public bool TryValidate(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            reasonCode = "wings_action_binding_unavailable";
            return false;
        }
    }

    internal interface IWingsActionReauthorizationAuthority
    {
        bool TryAcknowledgeAfterHumanSurfaceClosed(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            string humanInteractionReceiptId,
            out string reauthorizationReceiptId,
            out string reasonCode);
    }

    internal sealed class FailClosedWingsActionReauthorizationAuthority
        : IWingsActionReauthorizationAuthority
    {
        public bool TryAcknowledgeAfterHumanSurfaceClosed(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            string humanInteractionReceiptId,
            out string reauthorizationReceiptId,
            out string reasonCode)
        {
            reauthorizationReceiptId = null;
            reasonCode =
                "wings_action_reauthorization_unavailable";
            return false;
        }
    }

    /// <summary>
    /// Per-composition authentication boundary shared only by the human
    /// consent broker and the structured executor. Merely constructing an
    /// authorization-shaped object cannot bypass the human-only flow.
    /// </summary>
    internal sealed class WingsActionConsentTrustDomain
    {
        private readonly byte[] _key =
            RandomNumberGenerator.GetBytes(32);

        internal TrustedWingsActionAuthorization Seal(
            WingsActionIntentV1 intent,
            PrincipalCredential principal,
            string humanInteractionReceiptId,
            string reauthorizationReceiptId,
            long authorizedMonotonic)
        {
            if (intent == null)
                throw new ArgumentNullException(nameof(intent));
            if (principal == null)
                throw new ArgumentNullException(nameof(principal));
            WingsProtocolValue.RequireOpaqueId(
                humanInteractionReceiptId,
                nameof(humanInteractionReceiptId));
            WingsProtocolValue.RequireOpaqueId(
                reauthorizationReceiptId,
                nameof(reauthorizationReceiptId));
            byte[] tag = Sign(
                intent.BindingHash,
                principal.SecurityPrincipalId,
                principal.ClientInstanceId,
                principal.CredentialId,
                principal.Generation,
                principal.IssuerReceipt,
                humanInteractionReceiptId,
                reauthorizationReceiptId,
                authorizedMonotonic);
            return new TrustedWingsActionAuthorization(
                intent,
                principal,
                humanInteractionReceiptId,
                reauthorizationReceiptId,
                authorizedMonotonic,
                tag);
        }

        internal bool Verify(
            TrustedWingsActionAuthorization authorization)
        {
            if (authorization == null)
                return false;
            byte[] expected = Sign(
                authorization.Intent.BindingHash,
                authorization.SecurityPrincipalId,
                authorization.ClientInstanceId,
                authorization.CredentialId,
                authorization.CredentialGeneration,
                authorization.TrustedCredentialIssuerReceipt,
                authorization.HumanInteractionReceiptId,
                authorization.ReauthorizationReceiptId,
                authorization.AuthorizedMonotonic);
            return CryptographicOperations.FixedTimeEquals(
                expected,
                authorization.AuthenticationTag);
        }

        private byte[] Sign(
            string intentBindingHash,
            string securityPrincipalId,
            string clientInstanceId,
            string credentialId,
            long credentialGeneration,
            string trustedCredentialIssuerReceipt,
            string humanInteractionReceiptId,
            string reauthorizationReceiptId,
            long authorizedMonotonic)
        {
            string canonical = CanonicalJsonV1.Canonicalize(
                JsonSerializer.Serialize(
                    new
                    {
                        intentBindingHash,
                        securityPrincipalId,
                        clientInstanceId,
                        credentialId,
                        credentialGeneration,
                        trustedCredentialIssuerReceipt,
                        humanInteractionReceiptId,
                        reauthorizationReceiptId,
                        authorizedMonotonic
                    },
                    AgentProtocolV1.JsonOptions));
            using var hmac = new HMACSHA256(_key);
            return hmac.ComputeHash(
                Encoding.UTF8.GetBytes(canonical));
        }
    }

    /// <summary>
    /// One-shot proof that the exact intent passed human-only consent and
    /// post-close session reauthorization. It is not an ActionReceipt and
    /// cannot be constructed from Persona output.
    /// </summary>
    internal sealed class TrustedWingsActionAuthorization
    {
        private int _consumed;

        internal TrustedWingsActionAuthorization(
            WingsActionIntentV1 intent,
            PrincipalCredential principal,
            string humanInteractionReceiptId,
            string reauthorizationReceiptId,
            long authorizedMonotonic,
            byte[] authenticationTag)
        {
            Intent = intent;
            SecurityPrincipalId =
                principal.SecurityPrincipalId;
            ClientInstanceId =
                principal.ClientInstanceId;
            CredentialId = principal.CredentialId;
            CredentialGeneration = principal.Generation;
            TrustedCredentialIssuerReceipt =
                principal.IssuerReceipt;
            HumanInteractionReceiptId =
                humanInteractionReceiptId;
            ReauthorizationReceiptId =
                reauthorizationReceiptId;
            AuthorizedMonotonic =
                authorizedMonotonic;
            _authenticationTag =
                authenticationTag?.ToArray()
                ?? throw new ArgumentNullException(
                    nameof(authenticationTag));
        }

        private readonly byte[] _authenticationTag;

        public WingsActionIntentV1 Intent { get; }
        public string SecurityPrincipalId { get; }
        public string ClientInstanceId { get; }
        public string CredentialId { get; }
        public long CredentialGeneration { get; }
        public string TrustedCredentialIssuerReceipt { get; }
        public string HumanInteractionReceiptId { get; }
        public string ReauthorizationReceiptId { get; }
        public long AuthorizedMonotonic { get; }
        internal ReadOnlySpan<byte> AuthenticationTag =>
            _authenticationTag;

        internal bool TryConsume(
            PrincipalCredential principal,
            long nowMonotonic,
            out string reasonCode)
        {
            if (principal == null
                || principal.State != CredentialState.Active
                || principal.PrincipalKind
                    != AgentPrincipalKind.WingsPersona
                || principal.SessionMode
                    != AgentSessionMode.PlayerAssist
                || !string.Equals(
                    principal.CredentialId,
                    CredentialId,
                    StringComparison.Ordinal)
                || principal.Generation
                    != CredentialGeneration
                || !string.Equals(
                    principal.SecurityPrincipalId,
                    SecurityPrincipalId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    principal.ClientInstanceId,
                    ClientInstanceId,
                    StringComparison.Ordinal)
                || !PrincipalCredentialAuthority
                    .IsExactIssuerReceipt(
                        principal,
                        TrustedCredentialIssuerReceipt))
            {
                reasonCode = "principal_mismatch";
                return false;
            }
            if (nowMonotonic < AuthorizedMonotonic
                || nowMonotonic
                    >= Intent.ExpiresMonotonic
                || nowMonotonic
                    >= principal.ExpiresMonotonic)
            {
                reasonCode = "consent_expired";
                return false;
            }
            if (Interlocked.CompareExchange(
                    ref _consumed,
                    1,
                    0) != 0)
            {
                reasonCode = "consent_replayed";
                return false;
            }
            reasonCode = null;
            return true;
        }
    }

    internal sealed class WingsActionConsentResult
    {
        private WingsActionConsentResult(
            TrustedWingsActionAuthorization authorization,
            string reasonCode)
        {
            Authorization = authorization;
            ReasonCode = reasonCode;
        }

        public bool Authorized => Authorization != null;
        public TrustedWingsActionAuthorization Authorization
        {
            get;
        }
        public string ReasonCode { get; }

        internal static WingsActionConsentResult Allow(
            TrustedWingsActionAuthorization authorization)
        {
            return new WingsActionConsentResult(
                authorization
                    ?? throw new ArgumentNullException(
                        nameof(authorization)),
                null);
        }

        internal static WingsActionConsentResult Reject(
            string reasonCode)
        {
            return new WingsActionConsentResult(
                null,
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "consent_required"
                    : reasonCode);
        }
    }

    /// <summary>
    /// Human-only, fail-closed consent broker. Every binding is checked before
    /// presentation and again after the surface is closed and the session is
    /// reauthorized.
    /// </summary>
    internal sealed class WingsActionConsentBroker
    {
        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly IWingsActionBindingAuthority
            _bindings;
        private readonly IWingsActionConsentPresenter
            _presenter;
        private readonly IWingsActionReauthorizationAuthority
            _reauthorization;
        private readonly WingsActionConsentTrustDomain
            _trustDomain;
        private readonly HashSet<string> _activeIntentIds =
            new HashSet<string>(StringComparer.Ordinal);
        private readonly Dictionary<string, long>
            _finalizedIntentIds =
                new Dictionary<string, long>(
                    StringComparer.Ordinal);

        internal WingsActionConsentBroker(
            IAgentRuntimeClock clock,
            IWingsActionBindingAuthority bindings,
            WingsActionConsentTrustDomain trustDomain,
            IWingsActionConsentPresenter presenter = null,
            IWingsActionReauthorizationAuthority
                reauthorization = null)
        {
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _bindings = bindings
                ?? throw new ArgumentNullException(
                    nameof(bindings));
            _trustDomain = trustDomain
                ?? throw new ArgumentNullException(
                    nameof(trustDomain));
            _presenter = presenter
                ?? new FailClosedWingsActionConsentPresenter();
            _reauthorization = reauthorization
                ?? new FailClosedWingsActionReauthorizationAuthority();
        }

        public async Task<WingsActionConsentResult>
            RequestAsync(
                PrincipalCredential principal,
                WingsActionIntentV1 intent,
                CancellationToken cancellationToken)
        {
            string principalReason =
                ValidatePrincipal(principal, intent);
            if (principalReason != null)
            {
                return WingsActionConsentResult.Reject(
                    principalReason);
            }
            long now = _clock.MonotonicMilliseconds;
            if (now < intent.IssuedMonotonic
                || now >= intent.ExpiresMonotonic)
            {
                return WingsActionConsentResult.Reject(
                    "consent_expired");
            }
            if (!TryValidateBinding(
                    principal,
                    intent,
                    out string reasonCode))
            {
                return WingsActionConsentResult.Reject(
                    reasonCode
                        ?? "wings_action_binding_invalid");
            }
            lock (_sync)
            {
                PurgeFinalizedLocked(now);
                if (_activeIntentIds.Contains(
                        intent.IntentId)
                    || _finalizedIntentIds.ContainsKey(
                        intent.IntentId))
                {
                    return WingsActionConsentResult
                        .Reject("consent_replayed");
                }
                _activeIntentIds.Add(intent.IntentId);
            }

            try
            {
                WingsActionHumanDecision decision;
                try
                {
                    decision = await _presenter
                        .PresentAsync(
                            new TrustedWingsActionConsentCard(
                                intent),
                            cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                    when (cancellationToken
                        .IsCancellationRequested)
                {
                    return WingsActionConsentResult.Reject(
                        "consent_required");
                }
                catch
                {
                    return WingsActionConsentResult.Reject(
                        "consent_required");
                }
                if (decision == null
                    || decision.Kind
                        != WingsActionHumanDecisionKind.Allow)
                {
                    return WingsActionConsentResult.Reject(
                        "consent_required");
                }
                if (!decision.SurfaceClosedAndUnpublished
                    || string.IsNullOrWhiteSpace(
                        decision
                            .HumanInteractionReceiptId))
                {
                    return WingsActionConsentResult.Reject(
                        "consent_invalid");
                }

                now = _clock.MonotonicMilliseconds;
                if (now < intent.IssuedMonotonic
                    || now >= intent.ExpiresMonotonic
                    || principal.State
                        != CredentialState.Active)
                {
                    return WingsActionConsentResult.Reject(
                        "consent_expired");
                }
                if (!TryReauthorize(
                        principal,
                        intent,
                        decision
                            .HumanInteractionReceiptId,
                        out string reauthorizationReceiptId,
                        out reasonCode)
                    || string.IsNullOrWhiteSpace(
                        reauthorizationReceiptId))
                {
                    return WingsActionConsentResult.Reject(
                        reasonCode
                            ?? "consent_invalid");
                }
                try
                {
                    WingsProtocolValue.RequireOpaqueId(
                        reauthorizationReceiptId,
                        nameof(
                            reauthorizationReceiptId));
                }
                catch (ArgumentException)
                {
                    return WingsActionConsentResult.Reject(
                        "consent_invalid");
                }
                if (!TryValidateBinding(
                        principal,
                        intent,
                        out reasonCode))
                {
                    return WingsActionConsentResult.Reject(
                        reasonCode
                            ?? "wings_action_binding_invalid");
                }

                return WingsActionConsentResult.Allow(
                    _trustDomain.Seal(
                        intent,
                        principal,
                        decision.HumanInteractionReceiptId,
                        reauthorizationReceiptId,
                        now));
            }
            finally
            {
                lock (_sync)
                {
                    _activeIntentIds.Remove(
                        intent.IntentId);
                    _finalizedIntentIds[intent.IntentId] =
                        intent.ExpiresMonotonic;
                }
            }
        }

        private void PurgeFinalizedLocked(long now)
        {
            string[] expired = _finalizedIntentIds
                .Where(pair => pair.Value <= now)
                .Select(pair => pair.Key)
                .ToArray();
            foreach (string intentId in expired)
                _finalizedIntentIds.Remove(intentId);
        }

        private bool TryValidateBinding(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            try
            {
                return _bindings.TryValidate(
                    principal,
                    intent,
                    out reasonCode);
            }
            catch
            {
                reasonCode =
                    "wings_action_binding_unavailable";
                return false;
            }
        }

        private bool TryReauthorize(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            string humanInteractionReceiptId,
            out string reauthorizationReceiptId,
            out string reasonCode)
        {
            try
            {
                return _reauthorization
                    .TryAcknowledgeAfterHumanSurfaceClosed(
                        principal,
                        intent,
                        humanInteractionReceiptId,
                        out reauthorizationReceiptId,
                        out reasonCode);
            }
            catch
            {
                reauthorizationReceiptId = null;
                reasonCode =
                    "wings_action_reauthorization_unavailable";
                return false;
            }
        }

        private static string ValidatePrincipal(
            PrincipalCredential principal,
            WingsActionIntentV1 intent)
        {
            if (principal == null
                || principal.State != CredentialState.Active
                || principal.PrincipalKind
                    != AgentPrincipalKind.WingsPersona
                || principal.SessionMode
                    != AgentSessionMode.PlayerAssist)
            {
                return "principal_mismatch";
            }
            if (intent == null)
                return "wings_action_binding_required";
            if (!string.Equals(
                    principal.SelectedSessionId,
                    intent.SessionId,
                    StringComparison.Ordinal))
            {
                return "session_scope_mismatch";
            }
            if (string.IsNullOrWhiteSpace(
                    principal.IssuerReceipt))
            {
                return "consent_receipt_invalid";
            }
            return null;
        }
    }
}
