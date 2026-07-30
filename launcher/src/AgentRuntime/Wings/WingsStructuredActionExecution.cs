using System;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal sealed class WingsStructuredActionExecutionResult
    {
        private WingsStructuredActionExecutionResult(
            WingsBrokeredActionReceipt brokeredReceipt,
            string reasonCode)
        {
            BrokeredReceipt = brokeredReceipt;
            ReasonCode = reasonCode;
        }

        public bool HasTerminalReceipt =>
            BrokeredReceipt != null;
        public WingsBrokeredActionReceipt BrokeredReceipt
        {
            get;
        }
        public string ReasonCode { get; }

        internal static WingsStructuredActionExecutionResult
            Completed(
                WingsBrokeredActionReceipt receipt)
        {
            return new WingsStructuredActionExecutionResult(
                receipt
                    ?? throw new ArgumentNullException(
                        nameof(receipt)),
                null);
        }

        internal static WingsStructuredActionExecutionResult
            Rejected(string reasonCode)
        {
            return new WingsStructuredActionExecutionResult(
                null,
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "internal_error"
                    : reasonCode);
        }
    }

    /// <summary>
    /// Opaque execution provenance. A raw ActionReceipt is insufficient
    /// because the v1 receipt does not repeat principal/save/lore/lease
    /// bindings. This wrapper is authenticated by a composition-owned trust
    /// domain before Persona projection.
    /// </summary>
    internal sealed class WingsBrokeredActionReceipt
    {
        private readonly ActionReceipt _receipt;
        private readonly byte[] _authenticationTag;

        internal WingsBrokeredActionReceipt(
            string securityPrincipalId,
            string clientInstanceId,
            string credentialId,
            long credentialGeneration,
            string trustedCredentialIssuerReceipt,
            string intentBindingHash,
            string intentId,
            string sessionId,
            string saveBindingId,
            string loreViewId,
            string targetId,
            string observationGrantId,
            string observationId,
            string leaseId,
            ActionReceipt receipt,
            byte[] authenticationTag)
        {
            SecurityPrincipalId = securityPrincipalId;
            ClientInstanceId = clientInstanceId;
            CredentialId = credentialId;
            CredentialGeneration = credentialGeneration;
            TrustedCredentialIssuerReceipt =
                trustedCredentialIssuerReceipt;
            IntentBindingHash = intentBindingHash;
            IntentId = intentId;
            SessionId = sessionId;
            SaveBindingId = saveBindingId;
            LoreViewId = loreViewId;
            TargetId = targetId;
            ObservationGrantId =
                observationGrantId;
            ObservationId = observationId;
            LeaseId = leaseId;
            _receipt = CloneReceipt(receipt);
            _authenticationTag =
                authenticationTag?.ToArray()
                ?? throw new ArgumentNullException(
                    nameof(authenticationTag));
        }

        public string SecurityPrincipalId { get; }
        public string ClientInstanceId { get; }
        public string CredentialId { get; }
        public long CredentialGeneration { get; }
        public string TrustedCredentialIssuerReceipt { get; }
        public string IntentBindingHash { get; }
        public string IntentId { get; }
        public string SessionId { get; }
        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public string TargetId { get; }
        public string ObservationGrantId { get; }
        public string ObservationId { get; }
        public string LeaseId { get; }

        internal ActionReceipt ReceiptSnapshot()
        {
            return CloneReceipt(_receipt);
        }

        internal ReadOnlySpan<byte> AuthenticationTag =>
            _authenticationTag;

        private static ActionReceipt CloneReceipt(
            ActionReceipt receipt)
        {
            if (receipt == null)
                throw new ArgumentNullException(nameof(receipt));
            byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(
                receipt,
                AgentProtocolV1.JsonOptions);
            return JsonSerializer.Deserialize<ActionReceipt>(
                    bytes,
                    AgentProtocolV1.JsonOptions)
                ?? throw new InvalidOperationException(
                    "wings_receipt_clone_failed");
        }
    }

    /// <summary>
    /// Per-composition authentication boundary shared only by the trusted
    /// executor and receipt projector. Receipts sealed by another instance
    /// cannot be projected.
    /// </summary>
    internal sealed class WingsActionReceiptTrustDomain
    {
        private readonly byte[] _key =
            RandomNumberGenerator.GetBytes(32);

        internal WingsBrokeredActionReceipt Seal(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            string leaseId,
            ActionReceipt receipt)
        {
            if (principal == null)
                throw new ArgumentNullException(
                    nameof(principal));
            if (intent == null)
                throw new ArgumentNullException(
                    nameof(intent));
            WingsProtocolValue.RequireOpaqueId(
                leaseId,
                nameof(leaseId));
            ActionReceipt frozen =
                CloneReceipt(receipt);
            byte[] tag = Sign(
                principal.SecurityPrincipalId,
                principal.ClientInstanceId,
                principal.CredentialId,
                principal.Generation,
                principal.IssuerReceipt,
                intent.BindingHash,
                intent.IntentId,
                intent.SessionId,
                intent.SaveBindingId,
                intent.LoreViewId,
                intent.TargetId,
                intent.ObservationGrantId,
                intent.ObservationId,
                leaseId,
                frozen);
            return new WingsBrokeredActionReceipt(
                principal.SecurityPrincipalId,
                principal.ClientInstanceId,
                principal.CredentialId,
                principal.Generation,
                principal.IssuerReceipt,
                intent.BindingHash,
                intent.IntentId,
                intent.SessionId,
                intent.SaveBindingId,
                intent.LoreViewId,
                intent.TargetId,
                intent.ObservationGrantId,
                intent.ObservationId,
                leaseId,
                frozen,
                tag);
        }

        internal bool Verify(
            WingsBrokeredActionReceipt evidence)
        {
            if (evidence == null)
                return false;
            ActionReceipt receipt =
                evidence.ReceiptSnapshot();
            byte[] expected = Sign(
                evidence.SecurityPrincipalId,
                evidence.ClientInstanceId,
                evidence.CredentialId,
                evidence.CredentialGeneration,
                evidence.TrustedCredentialIssuerReceipt,
                evidence.IntentBindingHash,
                evidence.IntentId,
                evidence.SessionId,
                evidence.SaveBindingId,
                evidence.LoreViewId,
                evidence.TargetId,
                evidence.ObservationGrantId,
                evidence.ObservationId,
                evidence.LeaseId,
                receipt);
            return CryptographicOperations.FixedTimeEquals(
                expected,
                evidence.AuthenticationTag);
        }

        private byte[] Sign(
            string securityPrincipalId,
            string clientInstanceId,
            string credentialId,
            long credentialGeneration,
            string trustedCredentialIssuerReceipt,
            string intentBindingHash,
            string intentId,
            string sessionId,
            string saveBindingId,
            string loreViewId,
            string targetId,
            string observationGrantId,
            string observationId,
            string leaseId,
            ActionReceipt receipt)
        {
            string json = JsonSerializer.Serialize(
                new
                {
                    securityPrincipalId,
                    clientInstanceId,
                    credentialId,
                    credentialGeneration,
                    trustedCredentialIssuerReceipt,
                    intentBindingHash,
                    intentId,
                    sessionId,
                    saveBindingId,
                    loreViewId,
                    targetId,
                    observationGrantId,
                    observationId,
                    leaseId,
                    receipt
                },
                AgentProtocolV1.JsonOptions);
            string canonical =
                CanonicalJsonV1.Canonicalize(json);
            using var hmac = new HMACSHA256(_key);
            return hmac.ComputeHash(
                Encoding.UTF8.GetBytes(canonical));
        }

        private static ActionReceipt CloneReceipt(
            ActionReceipt receipt)
        {
            if (receipt == null)
                throw new ArgumentNullException(nameof(receipt));
            return JsonSerializer.Deserialize<ActionReceipt>(
                    JsonSerializer.SerializeToUtf8Bytes(
                        receipt,
                        AgentProtocolV1.JsonOptions),
                    AgentProtocolV1.JsonOptions)
                ?? throw new InvalidOperationException(
                    "wings_receipt_clone_failed");
        }
    }

    /// <summary>
    /// The only structured Wings execution path. It acquires an exact
    /// one-action lease and invokes the direct registered method through the
    /// validated virtual connection, so the shared dispatcher, observation
    /// consumption, action broker, idempotency ledger, audit and reconcile
    /// behavior remain authoritative.
    ///
    /// PlayerAssist lease.acquire carries the immutable intent's canonical
    /// operation/arguments hash. Only the dedicated virtual-connection path
    /// can add the non-wire Host attestation; the shared lease descriptor and
    /// action broker preserve and revalidate that exact binding. Production
    /// composition still stays fail-closed until a Launcher-owned chooser,
    /// write-capable attached principal and trusted observations are wired.
    /// </summary>
    internal sealed class WingsStructuredActionExecutor
    {
        private readonly IAgentRuntimeClock _clock;
        private readonly IWingsActionBindingAuthority
            _bindings;
        private readonly WingsVirtualAuthenticatedConnection
            _connection;
        private readonly WingsActionReceiptTrustDomain
            _trustDomain;
        private readonly WingsActionConsentTrustDomain
            _consentTrustDomain;

        internal WingsStructuredActionExecutor(
            IAgentRuntimeClock clock,
            IWingsActionBindingAuthority bindings,
            WingsVirtualAuthenticatedConnection connection,
            WingsActionConsentTrustDomain consentTrustDomain,
            WingsActionReceiptTrustDomain trustDomain)
        {
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _bindings = bindings
                ?? throw new ArgumentNullException(
                    nameof(bindings));
            _connection = connection
                ?? throw new ArgumentNullException(
                    nameof(connection));
            _consentTrustDomain = consentTrustDomain
                ?? throw new ArgumentNullException(
                    nameof(consentTrustDomain));
            _trustDomain = trustDomain
                ?? throw new ArgumentNullException(
                    nameof(trustDomain));
        }

        public async Task<
            WingsStructuredActionExecutionResult> ExecuteAsync(
                TrustedWingsActionAuthorization authorization,
                CancellationToken cancellationToken)
        {
            if (authorization == null)
            {
                return WingsStructuredActionExecutionResult
                    .Rejected("consent_required");
            }
            if (!_consentTrustDomain.Verify(
                    authorization))
            {
                return WingsStructuredActionExecutionResult
                    .Rejected("consent_invalid");
            }
            PrincipalCredential principal =
                _connection.Principal;
            WingsActionIntentV1 intent =
                authorization.Intent;
            if (!principal.AllowsCapability(
                    AgentCapabilitiesV1.LeaseAcquire)
                || !principal.AllowsCapability(
                    AgentCapabilitiesV1.LeaseRelease)
                || !AgentMethodsV1.TryGet(
                    intent.Operation,
                    out AgentMethodDefinition method)
                || !principal.AllowsCapability(
                    method.RequiredCapability)
                || !principal.AllowsTarget(
                    intent.TargetId))
            {
                return WingsStructuredActionExecutionResult
                    .Rejected("capability_denied");
            }
            if (!TryValidateBinding(
                    principal,
                    intent,
                    out string reasonCode))
            {
                return WingsStructuredActionExecutionResult
                    .Rejected(
                        reasonCode
                            ?? "wings_action_binding_invalid");
            }
            long now = _clock.MonotonicMilliseconds;
            if (!authorization.TryConsume(
                    principal,
                    now,
                    out reasonCode))
            {
                return WingsStructuredActionExecutionResult
                    .Rejected(reasonCode);
            }

            int remainingMs = checked((int)Math.Clamp(
                intent.ExpiresMonotonic - now,
                1,
                intent.LeaseKind
                    == WingsActionLeaseKind.GuiInput
                        ? 30_000
                        : 60_000));
            var leaseRequest =
                new LeaseAcquireParametersV1
                {
                    SessionId = intent.SessionId,
                    Kind = intent.LeaseKind
                        == WingsActionLeaseKind.GuiInput
                            ? "gui_input"
                            : "domain_transaction",
                    Capabilities = new()
                    {
                        method.RequiredCapability
                    },
                    TargetScope = new()
                    {
                        intent.TargetId
                    },
                    RequestedTtlMs = remainingMs,
                    RequestedActionLimit = 1,
                    ConsentReceipt =
                        authorization
                            .TrustedCredentialIssuerReceipt,
                    ArgumentBoundsHash =
                        intent.ArgumentBoundsHash,
                    PreviewHash =
                        intent.HairBinding?.PreviewHash,
                    ExpectedRevision =
                        intent.HairBinding
                            ?.ExpectedRevision,
                    Operation =
                        intent.LeaseKind
                            == WingsActionLeaseKind
                                .DomainTransaction
                            ? intent.Operation
                            : null
                };
            AgentRuntimeDispatchResult leaseResult =
                await _connection.DispatchLeaseAcquireAsync(
                    intent,
                    leaseRequest,
                    cancellationToken)
                .ConfigureAwait(false);
            if (!leaseResult.Success)
            {
                return WingsStructuredActionExecutionResult
                    .Rejected(
                        leaseResult.ReasonCode
                            ?? "lease_required");
            }

            LeaseDescriptor lease;
            try
            {
                lease =
                    leaseResult.Result
                        .Deserialize<LeaseDescriptor>(
                            AgentProtocolV1.JsonOptions);
            }
            catch (JsonException)
            {
                lease = null;
            }
            if (!LeaseMatches(
                    principal,
                    intent,
                    method.RequiredCapability,
                    lease,
                    _clock.MonotonicMilliseconds))
            {
                if (lease?.LeaseId != null)
                {
                    await TryReleaseAsync(
                        lease.LeaseId)
                        .ConfigureAwait(false);
                }
                return WingsStructuredActionExecutionResult
                    .Rejected("lease_scope_mismatch");
            }

            if (!TryValidateBinding(
                    principal,
                    intent,
                    out reasonCode))
            {
                await TryReleaseAsync(lease.LeaseId)
                    .ConfigureAwait(false);
                return WingsStructuredActionExecutionResult
                    .Rejected(
                        reasonCode
                            ?? "wings_action_binding_invalid");
            }

            now = _clock.MonotonicMilliseconds;
            if (now < intent.IssuedMonotonic
                || now >= intent.ExpiresMonotonic)
            {
                await TryReleaseAsync(lease.LeaseId)
                    .ConfigureAwait(false);
                return WingsStructuredActionExecutionResult
                    .Rejected("consent_expired");
            }
            int actionDeadlineMs = checked(
                (int)Math.Clamp(
                    intent.ExpiresMonotonic - now,
                    1,
                    AgentProtocolV1
                        .MaximumActionDeadlineMs));
            ActionEnvelope action =
                WingsActionIntentV1.HostFactory
                    .ToActionEnvelope(
                        intent,
                        lease.LeaseId,
                        actionDeadlineMs);
            AgentRuntimeDispatchResult actionResult =
                await _connection.DispatchAsync(
                    intent.Operation,
                    JsonSerializer.SerializeToElement(
                        action,
                        AgentProtocolV1.JsonOptions),
                    cancellationToken)
                .ConfigureAwait(false);
            if (!actionResult.Success)
            {
                await TryReleaseAsync(lease.LeaseId)
                    .ConfigureAwait(false);
                return WingsStructuredActionExecutionResult
                    .Rejected(
                        actionResult.ReasonCode
                            ?? "internal_error");
            }

            ActionReceipt receipt;
            try
            {
                receipt =
                    actionResult.Result
                        .Deserialize<ActionReceipt>(
                            AgentProtocolV1.JsonOptions);
            }
            catch (JsonException)
            {
                receipt = null;
            }
            if (!WingsTerminalActionReceiptValidator
                .TryValidate(
                    intent,
                    receipt,
                    out string receiptReason))
            {
                await TryReleaseAsync(lease.LeaseId)
                    .ConfigureAwait(false);
                return WingsStructuredActionExecutionResult
                    .Rejected(
                        receiptReason);
            }
            return WingsStructuredActionExecutionResult
                .Completed(
                    _trustDomain.Seal(
                        principal,
                        intent,
                        lease.LeaseId,
                        receipt));
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

        private async Task TryReleaseAsync(
            string leaseId)
        {
            if (string.IsNullOrWhiteSpace(leaseId))
                return;
            try
            {
                await _connection.DispatchAsync(
                    AgentCapabilitiesV1.LeaseRelease,
                    JsonSerializer.SerializeToElement(
                        new LeaseReleaseParametersV1
                        {
                            LeaseId = leaseId
                        },
                        AgentProtocolV1.JsonOptions),
                    CancellationToken.None)
                    .ConfigureAwait(false);
            }
            catch
            {
            }
        }

        private static bool LeaseMatches(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            string requiredCapability,
            LeaseDescriptor lease,
            long nowMonotonic)
        {
            if (lease == null
                || nowMonotonic < 0
                || AgentContractValidator
                    .Validate(lease).Count != 0
                || lease.State != LeaseState.Active
                || lease.SessionMode
                    != SessionMode.PlayerAssist
                || lease.Scope?.Session == null
                || !string.Equals(
                    lease.OwnerClientId,
                    principal.ClientInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    lease.SecurityPrincipalId,
                    principal.SecurityPrincipalId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    lease.Scope.Session.SessionId,
                    intent.SessionId,
                    StringComparison.Ordinal)
                || lease.Scope.Session
                    .LifecycleGeneration
                    != intent.LifecycleGeneration
                || !string.Equals(
                    lease.Scope.Session.AttemptId,
                    intent.AttemptId,
                    StringComparison.Ordinal)
                || lease.Scope.Session.AttemptGeneration
                    != intent.AttemptGeneration
                || lease.Scope.Session.CrossAttempt
                || lease.Scope.MaximumActions != 1
                || lease.Scope.TargetScope == null
                || lease.Scope.TargetScope.Count != 1
                || !string.Equals(
                    lease.Scope.TargetScope[0],
                    intent.TargetId,
                    StringComparison.Ordinal)
                || lease.Scope.OperationScope == null
                || lease.Scope.OperationScope.Count != 1
                || !string.Equals(
                    lease.Scope.OperationScope[0],
                    requiredCapability,
                    StringComparison.Ordinal)
                || !string.Equals(
                    lease.Scope.ArgumentBoundsHash,
                    intent.ArgumentBoundsHash,
                    StringComparison.OrdinalIgnoreCase)
                || lease.Capabilities == null
                || lease.Capabilities.Count != 1
                || !string.Equals(
                    lease.Capabilities[0],
                    requiredCapability,
                    StringComparison.Ordinal)
                || !PrincipalCredentialAuthority
                    .IsExactIssuerReceipt(
                        principal,
                        lease.ConsentReceipt)
                || lease.IssuedMonotonic
                    > checked((ulong)nowMonotonic)
                || lease.ExpiresMonotonic
                    <= checked((ulong)nowMonotonic)
                || lease.ExpiresMonotonic
                    > checked(
                        (ulong)intent.ExpiresMonotonic))
            {
                return false;
            }
            return intent.LeaseKind
                == WingsActionLeaseKind.GuiInput
                    ? lease.Purpose
                        == LeasePurpose.GuiInput
                    : lease.Purpose
                        == LeasePurpose.DomainTransaction;
        }
    }

    internal sealed class TrustedWingsActionProjection
    {
        internal TrustedWingsActionProjection(
            string intentId,
            string actionId,
            ActionOutcome outcome,
            EvidenceKind evidenceKind,
            string reasonCode,
            ReconcileKind reconcileKind,
            bool retryable,
            string targetId,
            string beforeObservationId,
            string afterObservationId,
            HairDomainActionResult domainResult)
        {
            IntentId = intentId;
            ActionId = actionId;
            Outcome = outcome;
            EvidenceKind = evidenceKind;
            ReasonCode = reasonCode;
            ReconcileKind = reconcileKind;
            Retryable = retryable;
            TargetId = targetId;
            BeforeObservationId =
                beforeObservationId;
            AfterObservationId =
                afterObservationId;
            DomainResult = domainResult;
        }

        public string IntentId { get; }
        public string ActionId { get; }
        public ActionOutcome Outcome { get; }
        public string OutcomeCode => Outcome switch
        {
            ActionOutcome.Rejected => "rejected",
            ActionOutcome.InputDispatched =>
                "input_dispatched",
            ActionOutcome.EffectObserved =>
                "effect_observed",
            ActionOutcome.DomainCommitted =>
                "domain_committed",
            ActionOutcome.Unknown => "unknown",
            _ => throw new InvalidOperationException(
                "wings_action_outcome_unregistered")
        };
        public EvidenceKind EvidenceKind { get; }
        public string ReasonCode { get; }
        public ReconcileKind ReconcileKind { get; }
        public bool Retryable { get; }
        public string TargetId { get; }
        public string BeforeObservationId { get; }
        public string AfterObservationId { get; }
        public HairDomainActionResult DomainResult { get; }
    }

    internal static class WingsTerminalActionReceiptValidator
    {
        internal static bool TryValidate(
            WingsActionIntentV1 intent,
            ActionReceipt receipt,
            out string reasonCode)
        {
            if (intent == null
                || receipt == null
                || !receipt.Terminal
                || AgentContractValidator
                    .Validate(receipt).Count != 0)
            {
                reasonCode =
                    "wings_terminal_receipt_required";
                return false;
            }
            if (!string.Equals(
                    receipt.ActionId,
                    intent.ActionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    receipt.BeforeObservationId,
                    intent.ObservationId,
                    StringComparison.Ordinal)
                || (receipt.ActualTargetId != null
                    && !string.Equals(
                        receipt.ActualTargetId,
                        intent.TargetId,
                        StringComparison.Ordinal))
                || (receipt.Outcome
                        is ActionOutcome.InputDispatched
                            or ActionOutcome.EffectObserved
                            or ActionOutcome.DomainCommitted
                    && !string.Equals(
                        receipt.ActualTargetId,
                        intent.TargetId,
                        StringComparison.Ordinal)))
            {
                reasonCode =
                    "wings_receipt_binding_mismatch";
                return false;
            }
            if (receipt.Outcome
                == ActionOutcome.DomainCommitted)
            {
                WingsHairActionBinding hair =
                    intent.HairBinding;
                if (hair == null
                    || receipt.DomainResult == null
                    || !string.Equals(
                        receipt.DomainResult
                            .TransactionId,
                        hair.TransactionId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        receipt.DomainResult
                            .PreviewHash,
                        hair.PreviewHash,
                        StringComparison.OrdinalIgnoreCase))
                {
                    reasonCode =
                        "wings_receipt_domain_mismatch";
                    return false;
                }
            }
            reasonCode = null;
            return true;
        }
    }

    /// <summary>
    /// Persona-facing projector. It accepts only an authenticated terminal
    /// broker receipt and exact-reconciles every identity/binding before
    /// exposing one of the five frozen outcomes.
    /// </summary>
    internal sealed class TrustedWingsActionReceiptAuthority
    {
        private readonly WingsActionReceiptTrustDomain
            _trustDomain;
        private readonly IWingsActionBindingAuthority
            _bindings;

        internal TrustedWingsActionReceiptAuthority(
            WingsActionReceiptTrustDomain trustDomain,
            IWingsActionBindingAuthority bindings)
        {
            _trustDomain = trustDomain
                ?? throw new ArgumentNullException(
                    nameof(trustDomain));
            _bindings = bindings
                ?? throw new ArgumentNullException(
                    nameof(bindings));
        }

        public bool TryProject(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            WingsBrokeredActionReceipt evidence,
            out TrustedWingsActionProjection projection,
            out string reasonCode)
        {
            projection = null;
            if (principal == null
                || intent == null
                || evidence == null
                || !_trustDomain.Verify(evidence))
            {
                reasonCode =
                    "wings_receipt_untrusted";
                return false;
            }
            bool bindingValid;
            try
            {
                bindingValid = _bindings.TryValidate(
                    principal,
                    intent,
                    out _);
            }
            catch
            {
                bindingValid = false;
            }
            if (!bindingValid)
            {
                reasonCode =
                    "wings_receipt_binding_mismatch";
                return false;
            }
            if (principal.PrincipalKind
                    != AgentPrincipalKind.WingsPersona
                || principal.SessionMode
                    != AgentSessionMode.PlayerAssist
                || principal.State
                    != CredentialState.Active
                || !string.Equals(
                    principal.SelectedSessionId,
                    intent.SessionId,
                    StringComparison.Ordinal)
                || !principal.AllowsTarget(
                    intent.TargetId)
                || !string.Equals(
                    evidence.SecurityPrincipalId,
                    principal.SecurityPrincipalId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.ClientInstanceId,
                    principal.ClientInstanceId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.CredentialId,
                    principal.CredentialId,
                    StringComparison.Ordinal)
                || evidence.CredentialGeneration
                    != principal.Generation
                || !PrincipalCredentialAuthority
                    .IsExactIssuerReceipt(
                        principal,
                        evidence
                            .TrustedCredentialIssuerReceipt)
                || !string.Equals(
                    evidence.IntentBindingHash,
                    intent.BindingHash,
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.IntentId,
                    intent.IntentId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.SessionId,
                    intent.SessionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.SaveBindingId,
                    intent.SaveBindingId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.LoreViewId,
                    intent.LoreViewId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.TargetId,
                    intent.TargetId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.ObservationGrantId,
                    intent.ObservationGrantId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.ObservationId,
                    intent.ObservationId,
                    StringComparison.Ordinal))
            {
                reasonCode =
                    "wings_receipt_binding_mismatch";
                return false;
            }

            ActionReceipt receipt =
                evidence.ReceiptSnapshot();
            if (!WingsTerminalActionReceiptValidator
                .TryValidate(
                    intent,
                    receipt,
                    out reasonCode))
            {
                return false;
            }

            projection =
                new TrustedWingsActionProjection(
                    intent.IntentId,
                    receipt.ActionId,
                    receipt.Outcome,
                    receipt.EvidenceKind,
                    receipt.ReasonCode,
                    receipt.ReconcileKind,
                    receipt.Retryable,
                    intent.TargetId,
                    receipt.BeforeObservationId,
                    receipt.AfterObservationId,
                    receipt.DomainResult);
            reasonCode = null;
            return true;
        }
    }
}
