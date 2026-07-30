using System;
using CF7Launcher.AgentRuntime.Input;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Input
{
    public sealed class ActionIdempotencyLedgerTests
    {
        [Fact]
        public void SameIdempotencyAndPayload_NeverDispatchesTwice()
        {
            var ledger = new ActionIdempotencyLedger();
            ActionLedgerIdentity first = Identity(
                "action-a",
                "idem-a",
                "{\"operation\":\"click\",\"x\":1}");
            Assert.Equal(
                ActionBeginKind.DispatchNew,
                ledger.Begin(first).Kind);
            ledger.MarkDispatchStarted(
                first,
                ActionReconcileKind.VisualAmbiguous);
            var receipt = new ActionReceiptRecord(
                "action-a",
                true,
                ActionReceiptOutcome.InputDispatched,
                null,
                ActionReconcileKind.None,
                false);
            ledger.Complete(first, receipt);

            ActionLedgerIdentity retry = Identity(
                "action-b",
                "idem-a",
                "{\"operation\":\"click\",\"x\":1}");
            ActionBeginResult duplicate = ledger.Begin(retry);

            Assert.Equal(
                ActionBeginKind.ExistingReceipt,
                duplicate.Kind);
            Assert.Same(receipt, duplicate.Receipt);
            Assert.Equal("action-a", duplicate.Receipt.ActionId);
        }

        [Fact]
        public void SameKeyDifferentCanonicalPayload_IsTerminalConflict()
        {
            var ledger = new ActionIdempotencyLedger();
            Assert.Equal(
                ActionBeginKind.DispatchNew,
                ledger.Begin(Identity(
                    "action-a",
                    "idem-a",
                    "{\"x\":1}")).Kind);

            ActionBeginResult conflict = ledger.Begin(
                Identity(
                    "action-b",
                    "idem-a",
                    "{\"x\":2}"));

            Assert.Equal(ActionBeginKind.Conflict, conflict.Kind);
            Assert.Equal(
                ActionReceiptOutcome.Rejected,
                conflict.Receipt.Outcome);
            Assert.Equal(
                "idempotency_conflict",
                conflict.Receipt.ReasonCode);
        }

        [Fact]
        public void MissingIsProvenOnlyWhileLifecycleContinuityIsIntact()
        {
            var ledger = new ActionIdempotencyLedger();
            Assert.Equal(
                ActionLookupKind.NotFoundProven,
                ledger.Get(
                    "principal-a",
                    "session-a",
                    "never-seen").Kind);

            ledger.MarkContinuityLost();

            Assert.Equal(
                ActionLookupKind.Unknown,
                ledger.Get(
                    "principal-a",
                    "session-a",
                    "never-seen").Kind);
            Assert.Equal(
                ActionBeginKind.ExistingReceipt,
                ledger.Begin(Identity(
                    "new-after-truncation",
                    "new-idem",
                    "{}")).Kind);
        }

        [Fact]
        public void DispatchWindowStaysUnknownUntilAuthoritativeReconcile()
        {
            var ledger = new ActionIdempotencyLedger();
            ActionLedgerIdentity identity = Identity(
                "action-a",
                "idem-a",
                "{\"operation\":\"hair.change\"}");
            ledger.Begin(identity);
            ledger.MarkDispatchStarted(
                identity,
                ActionReconcileKind.DomainAuthoritative);

            ActionLookupResult unknown = ledger.Get(
                "principal-a",
                "session-a",
                "action-a");
            Assert.Equal(ActionLookupKind.Unknown, unknown.Kind);
            Assert.False(unknown.Receipt.Retryable);

            var reconciled = new ActionReceiptRecord(
                "action-a",
                true,
                ActionReceiptOutcome.DomainCommitted,
                null,
                ActionReconcileKind.None,
                false);
            ledger.ReconcileUnknown(identity, reconciled);

            Assert.Equal(
                ActionReceiptOutcome.DomainCommitted,
                ledger.Get(
                    "principal-a",
                    "session-a",
                    "action-a").Receipt.Outcome);
        }

        [Fact]
        public void PrincipalNamespaceDoesNotLeakOtherPrincipalKeys()
        {
            var ledger = new ActionIdempotencyLedger();
            ActionLedgerIdentity first = Identity(
                "action-a",
                "idem-a",
                "{}");
            ledger.Begin(first);

            ActionLedgerIdentity other = first with
            {
                SecurityPrincipalId = "principal-b"
            };

            Assert.Equal(
                ActionBeginKind.DispatchNew,
                ledger.Begin(other).Kind);
        }

        [Fact]
        public void SuccessfulReceipt_CannotAppearBeforeDispatchStarts()
        {
            var ledger = new ActionIdempotencyLedger();
            ActionLedgerIdentity identity = Identity(
                "action-a",
                "idem-a",
                "{}");
            ledger.Begin(identity);

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => ledger.Complete(
                        identity,
                        new ActionReceiptRecord(
                            "action-a",
                            true,
                            ActionReceiptOutcome.EffectObserved,
                            null,
                            ActionReconcileKind.None,
                            false)));

            Assert.Equal("dispatch_start_required", error.Message);
            Assert.Equal(
                ActionLookupKind.ProvenNotDispatched,
                ledger.Get(
                    "principal-a",
                    "session-a",
                    "action-a").Kind);
        }

        [Fact]
        public void PreDispatchRejection_RequiresReasonAndIsTerminal()
        {
            var ledger = new ActionIdempotencyLedger();
            ActionLedgerIdentity identity = Identity(
                "action-a",
                "idem-a",
                "{}");
            ledger.Begin(identity);

            Assert.Throws<InvalidOperationException>(
                () => ledger.Complete(
                    identity,
                    new ActionReceiptRecord(
                        "action-a",
                        true,
                        ActionReceiptOutcome.Rejected,
                        null,
                        ActionReconcileKind.None,
                        false)));

            ledger.Complete(
                identity,
                new ActionReceiptRecord(
                    "action-a",
                    true,
                    ActionReceiptOutcome.Rejected,
                    "stale_observation",
                    ActionReconcileKind.None,
                    false));
            Assert.Equal(
                ActionLookupKind.TerminalReceipt,
                ledger.Get(
                    "principal-a",
                    "session-a",
                    "action-a").Kind);
        }

        private static ActionLedgerIdentity Identity(
            string actionId,
            string idempotencyKey,
            string payload)
        {
            return new ActionLedgerIdentity(
                "principal-a",
                "session-a",
                actionId,
                idempotencyKey,
                ActionIdempotencyLedger.HashCanonicalPayload(payload));
        }
    }
}
