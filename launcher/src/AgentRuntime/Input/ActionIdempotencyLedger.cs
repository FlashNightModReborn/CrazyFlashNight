using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Input
{
    public enum ActionReceiptOutcome
    {
        Rejected,
        InputDispatched,
        EffectObserved,
        DomainCommitted,
        Unknown
    }

    public enum ActionReconcileKind
    {
        None,
        DomainAuthoritative,
        VisualAmbiguous,
        ManualRequired
    }

    public sealed record ActionReceiptRecord(
        string ActionId,
        bool Terminal,
        ActionReceiptOutcome Outcome,
        string ReasonCode,
        ActionReconcileKind ReconcileKind,
        bool Retryable)
    {
        /// <summary>
        /// The complete public receipt is retained when one exists so
        /// action.get can reproduce the original terminal response across
        /// reconnects. Prepared/unknown continuity records intentionally do
        /// not fabricate fields that were never durably observed.
        /// </summary>
        public ActionReceipt ContractReceipt { get; init; }
    }

    public sealed record ActionLedgerIdentity(
        string SecurityPrincipalId,
        string SessionId,
        string ActionId,
        string IdempotencyKey,
        string CanonicalPayloadHash);

    public enum ActionBeginKind
    {
        DispatchNew,
        ExistingPrepared,
        ExistingReceipt,
        Conflict
    }

    public sealed class ActionBeginResult
    {
        internal ActionBeginResult(
            ActionBeginKind kind,
            ActionReceiptRecord receipt)
        {
            Kind = kind;
            Receipt = receipt;
        }

        public ActionBeginKind Kind { get; }
        public ActionReceiptRecord Receipt { get; }
    }

    public enum ActionLookupKind
    {
        TerminalReceipt,
        ProvenNotDispatched,
        Unknown,
        NotFoundProven
    }

    public sealed class ActionLookupResult
    {
        internal ActionLookupResult(
            ActionLookupKind kind,
            ActionReceiptRecord receipt)
        {
            Kind = kind;
            Receipt = receipt;
        }

        public ActionLookupKind Kind { get; }
        public ActionReceiptRecord Receipt { get; }
    }

    internal enum ActionLedgerEntryState
    {
        Prepared,
        DispatchStarted,
        Terminal
    }

    internal sealed class ActionLedgerEntry
    {
        public ActionLedgerIdentity Identity { get; init; }
        public ActionLedgerEntryState State { get; set; }
        public ActionReceiptRecord Receipt { get; set; }
    }

    /// <summary>
    /// In-memory lifecycle ledger. Missing-action proofs are only returned
    /// while continuity is known; truncation/crash switches all ambiguous
    /// lookups to unknown until an authoritative reconcile completes.
    /// </summary>
    public sealed class ActionIdempotencyLedger
    {
        private readonly object _sync = new object();
        private readonly Dictionary<string, ActionLedgerEntry> _byAction =
            new Dictionary<string, ActionLedgerEntry>(StringComparer.Ordinal);
        private readonly Dictionary<string, ActionLedgerEntry> _byIdempotency =
            new Dictionary<string, ActionLedgerEntry>(StringComparer.Ordinal);
        private bool _continuityProven = true;

        public ActionBeginResult Begin(ActionLedgerIdentity identity)
        {
            Validate(identity);
            lock (_sync)
            {
                string actionKey = ActionKey(identity);
                string idempotencyKey = IdempotencyKey(identity);
                _byAction.TryGetValue(actionKey, out var byAction);
                _byIdempotency.TryGetValue(
                    idempotencyKey,
                    out var byIdempotency);

                if (byAction != null
                    && byIdempotency != null
                    && !ReferenceEquals(byAction, byIdempotency))
                {
                    return Conflict(identity.ActionId);
                }

                ActionLedgerEntry existing = byAction ?? byIdempotency;
                if (existing != null)
                {
                    if (!string.Equals(
                            existing.Identity.CanonicalPayloadHash,
                            identity.CanonicalPayloadHash,
                            StringComparison.Ordinal))
                    {
                        return Conflict(identity.ActionId);
                    }

                    if (byAction == null)
                    {
                        _byAction.Add(actionKey, existing);
                    }
                    if (byIdempotency == null)
                    {
                        _byIdempotency.Add(idempotencyKey, existing);
                    }

                    if (existing.State == ActionLedgerEntryState.Prepared)
                    {
                        return new ActionBeginResult(
                            ActionBeginKind.ExistingPrepared,
                            null);
                    }
                    return new ActionBeginResult(
                        ActionBeginKind.ExistingReceipt,
                        existing.State == ActionLedgerEntryState.Terminal
                            ? existing.Receipt
                            : existing.Receipt
                                ?? UnknownReceipt(
                                    identity.ActionId,
                                    ActionReconcileKind
                                        .ManualRequired));
                }

                if (!_continuityProven)
                {
                    return new ActionBeginResult(
                        ActionBeginKind.ExistingReceipt,
                        UnknownReceipt(
                            identity.ActionId,
                            ActionReconcileKind.ManualRequired));
                }

                ActionLedgerEntry entry = new ActionLedgerEntry
                {
                    Identity = identity,
                    State = ActionLedgerEntryState.Prepared
                };
                _byAction.Add(actionKey, entry);
                _byIdempotency.Add(idempotencyKey, entry);
                return new ActionBeginResult(
                    ActionBeginKind.DispatchNew,
                    null);
            }
        }

        public void MarkDispatchStarted(
            ActionLedgerIdentity identity,
            ActionReconcileKind reconcileKind)
        {
            Validate(identity);
            if (reconcileKind == ActionReconcileKind.None)
            {
                throw new ArgumentException(
                    "A dispatch must declare its failure reconcile path.",
                    nameof(reconcileKind));
            }
            lock (_sync)
            {
                ActionLedgerEntry entry = ResolveExactLocked(identity);
                if (entry.State != ActionLedgerEntryState.Prepared)
                {
                    throw new InvalidOperationException(
                        "action_not_prepared");
                }
                entry.State = ActionLedgerEntryState.DispatchStarted;
                entry.Receipt = UnknownReceipt(
                    identity.ActionId,
                    reconcileKind);
            }
        }

        public void Complete(
            ActionLedgerIdentity identity,
            ActionReceiptRecord receipt)
        {
            Validate(identity);
            if (receipt == null)
            {
                throw new ArgumentNullException(nameof(receipt));
            }
            if (!receipt.Terminal
                || !string.Equals(
                    identity.ActionId,
                    receipt.ActionId,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "terminal_receipt_required");
            }
            ValidateTerminalReceiptShape(receipt);

            lock (_sync)
            {
                ActionLedgerEntry entry = ResolveExactLocked(identity);
                if (entry.State == ActionLedgerEntryState.Terminal)
                {
                    if (!Equals(entry.Receipt, receipt))
                    {
                        throw new InvalidOperationException(
                            "terminal_receipt_conflict");
                    }
                    return;
                }
                if (entry.State == ActionLedgerEntryState.Prepared
                    && receipt.Outcome
                        != ActionReceiptOutcome.Rejected)
                {
                    throw new InvalidOperationException(
                        "dispatch_start_required");
                }
                entry.Receipt = receipt;
                entry.State = ActionLedgerEntryState.Terminal;
            }
        }

        public void RecordUnknown(
            ActionLedgerIdentity identity,
            ActionReceiptRecord receipt)
        {
            Validate(identity);
            if (receipt == null
                || !receipt.Terminal
                || receipt.Outcome
                    != ActionReceiptOutcome.Unknown
                || receipt.ReconcileKind
                    == ActionReconcileKind.None
                || !string.Equals(
                    receipt.ActionId,
                    identity.ActionId,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "unknown_receipt_required");
            }

            lock (_sync)
            {
                ActionLedgerEntry entry = ResolveExactLocked(
                    identity);
                if (entry.State
                    != ActionLedgerEntryState.DispatchStarted)
                {
                    throw new InvalidOperationException(
                        "dispatch_start_required");
                }
                entry.Receipt = receipt;
            }
        }

        public ActionLookupResult Get(
            string securityPrincipalId,
            string sessionId,
            string actionId)
        {
            RequireValue(securityPrincipalId, nameof(securityPrincipalId));
            RequireValue(sessionId, nameof(sessionId));
            RequireValue(actionId, nameof(actionId));

            lock (_sync)
            {
                string key = NamespaceKey(
                    securityPrincipalId,
                    sessionId,
                    actionId);
                if (!_byAction.TryGetValue(key, out var entry))
                {
                    return _continuityProven
                        ? new ActionLookupResult(
                            ActionLookupKind.NotFoundProven,
                            null)
                        : new ActionLookupResult(
                            ActionLookupKind.Unknown,
                            UnknownReceipt(
                                actionId,
                                ActionReconcileKind.ManualRequired));
                }
                if (entry.State == ActionLedgerEntryState.Prepared)
                {
                    return new ActionLookupResult(
                        ActionLookupKind.ProvenNotDispatched,
                        null);
                }
                if (entry.State == ActionLedgerEntryState.DispatchStarted)
                {
                    return new ActionLookupResult(
                        ActionLookupKind.Unknown,
                        entry.Receipt);
                }
                return new ActionLookupResult(
                    ActionLookupKind.TerminalReceipt,
                    entry.Receipt);
            }
        }

        public void MarkContinuityLost()
        {
            lock (_sync)
            {
                _continuityProven = false;
                foreach (ActionLedgerEntry entry in _byAction.Values)
                {
                    if (entry.State == ActionLedgerEntryState.Prepared)
                    {
                        entry.State = ActionLedgerEntryState.DispatchStarted;
                        entry.Receipt = UnknownReceipt(
                            entry.Identity.ActionId,
                            ActionReconcileKind.ManualRequired);
                    }
                }
            }
        }

        public void ReconcileUnknown(
            ActionLedgerIdentity identity,
            ActionReceiptRecord authoritativeReceipt)
        {
            Validate(identity);
            if (authoritativeReceipt == null
                || !authoritativeReceipt.Terminal
                || authoritativeReceipt.Outcome
                    == ActionReceiptOutcome.Unknown)
            {
                throw new InvalidOperationException(
                    "authoritative_terminal_reconcile_required");
            }

            lock (_sync)
            {
                ActionLedgerEntry entry = ResolveExactLocked(identity);
                if (entry.State != ActionLedgerEntryState.DispatchStarted)
                {
                    throw new InvalidOperationException(
                        "action_is_not_unknown");
                }
                if (!string.Equals(
                        identity.ActionId,
                        authoritativeReceipt.ActionId,
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "receipt_action_mismatch");
                }
                entry.Receipt = authoritativeReceipt;
                entry.State = ActionLedgerEntryState.Terminal;
            }
        }

        public static string HashCanonicalPayload(string canonicalPayload)
        {
            if (canonicalPayload == null)
            {
                throw new ArgumentNullException(nameof(canonicalPayload));
            }
            return Convert.ToHexString(
                    SHA256.HashData(
                        Encoding.UTF8.GetBytes(canonicalPayload)))
                .ToLowerInvariant();
        }

        private ActionLedgerEntry ResolveExactLocked(
            ActionLedgerIdentity identity)
        {
            if (!_byAction.TryGetValue(
                    ActionKey(identity),
                    out var entry)
                || !string.Equals(
                    entry.Identity.IdempotencyKey,
                    identity.IdempotencyKey,
                    StringComparison.Ordinal)
                || !string.Equals(
                    entry.Identity.CanonicalPayloadHash,
                    identity.CanonicalPayloadHash,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "action_identity_mismatch");
            }
            return entry;
        }

        private static ActionBeginResult Conflict(string actionId)
        {
            return new ActionBeginResult(
                ActionBeginKind.Conflict,
                new ActionReceiptRecord(
                    actionId,
                    true,
                    ActionReceiptOutcome.Rejected,
                    "idempotency_conflict",
                    ActionReconcileKind.None,
                    false));
        }

        private static ActionReceiptRecord UnknownReceipt(
            string actionId,
            ActionReconcileKind reconcileKind)
        {
            return new ActionReceiptRecord(
                actionId,
                true,
                ActionReceiptOutcome.Unknown,
                "reconcile_required",
                reconcileKind,
                false);
        }

        private static void ValidateTerminalReceiptShape(
            ActionReceiptRecord receipt)
        {
            if (receipt.Outcome == ActionReceiptOutcome.Unknown)
            {
                throw new InvalidOperationException(
                    "unknown_requires_reconcile_state");
            }
            if (receipt.Outcome == ActionReceiptOutcome.Rejected
                && string.IsNullOrWhiteSpace(receipt.ReasonCode))
            {
                throw new InvalidOperationException(
                    "rejected_reason_required");
            }
            if (receipt.ReconcileKind != ActionReconcileKind.None)
            {
                throw new InvalidOperationException(
                    "terminal_reconcile_kind_must_be_none");
            }
        }

        private static void Validate(ActionLedgerIdentity identity)
        {
            if (identity == null)
            {
                throw new ArgumentNullException(nameof(identity));
            }
            RequireValue(
                identity.SecurityPrincipalId,
                nameof(identity.SecurityPrincipalId));
            RequireValue(identity.SessionId, nameof(identity.SessionId));
            RequireValue(identity.ActionId, nameof(identity.ActionId));
            RequireValue(
                identity.IdempotencyKey,
                nameof(identity.IdempotencyKey));
            RequireValue(
                identity.CanonicalPayloadHash,
                nameof(identity.CanonicalPayloadHash));
        }

        private static string ActionKey(ActionLedgerIdentity identity)
        {
            return NamespaceKey(
                identity.SecurityPrincipalId,
                identity.SessionId,
                identity.ActionId);
        }

        private static string IdempotencyKey(
            ActionLedgerIdentity identity)
        {
            return NamespaceKey(
                identity.SecurityPrincipalId,
                identity.SessionId,
                identity.IdempotencyKey);
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

        private static void RequireValue(
            string value,
            string parameterName)
        {
            PrincipalCredentialAuthority.RequireValue(
                value,
                parameterName);
        }
    }
}
