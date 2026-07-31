using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.Tests.AgentRuntime.Observation;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentRuntimeActionExecutionBrokerTests
    {
        private const string ClientId =
            "client_AAAAAAAAAAAAAAAAA";
        private const string SessionId =
            "session_AAAAAAAAAAAAAAA";
        private const string TargetId =
            "target_AAAAAAAAAAAAAAAAA";
        private const string AttemptId =
            "attempt_AAAAAAAAAAAAAAA";
        private const string PanelId =
            "panel_AAAAAAAAAAAAAAAAA";

        [Fact]
        public async Task ConcurrentSameIdentitySharesOneDispatch()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync();
            var performer = new BlockingPerformer();
            fixture.SetPerformer(performer);
            ActionEnvelope action = fixture.Action();

            Task<ActionReceipt> first = fixture.ExecuteAsync(action);
            await performer.Entered.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            Task<ActionReceipt> duplicate =
                fixture.ExecuteAsync(Clone(action));

            Assert.Equal(1, performer.CallCount);
            performer.Complete(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));

            ActionReceipt receipt = await first.WaitAsync(
                TimeSpan.FromSeconds(5));
            Assert.Same(
                receipt,
                await duplicate.WaitAsync(
                    TimeSpan.FromSeconds(5)));
            Assert.Equal(
                ActionOutcome.InputDispatched,
                receipt.Outcome);
            Assert.Equal(1, fixture.Lease.ActionsConsumed);
            Assert.Equal(
                ActionLookupKind.TerminalReceipt,
                fixture.Ledger.Get(
                    fixture.Principal.SecurityPrincipalId,
                    SessionId,
                    action.ActionId).Kind);
        }

        [Fact]
        public async Task SameKeyDifferentPayloadIsRejectedWithoutSecondDispatch()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync();
            var performer = new BlockingPerformer();
            fixture.SetPerformer(performer);
            ActionEnvelope action = fixture.Action();

            Task<ActionReceipt> first = fixture.ExecuteAsync(action);
            await performer.Entered.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            ActionEnvelope conflict = Clone(action);
            conflict.Arguments = JsonSerializer.SerializeToElement(
                new { x = 999, y = 18, button = "left" });

            ActionReceipt rejected =
                await fixture.ExecuteAsync(conflict);
            Assert.Equal(ActionOutcome.Rejected, rejected.Outcome);
            Assert.Equal(
                "idempotency_conflict",
                rejected.ReasonCode);
            Assert.Equal(1, performer.CallCount);

            performer.Complete(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            _ = await first.WaitAsync(TimeSpan.FromSeconds(5));
        }

        [Fact]
        public async Task UnknownReceiptIsDurableAndNeverBlindlyReplayed()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    requestedActionLimit: 2);
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Unknown(
                    "reconcile_required",
                    ReconcileKind.ManualRequired));
            fixture.SetPerformer(performer);
            ActionEnvelope action = fixture.Action();

            ActionReceipt first =
                await fixture.ExecuteAsync(action);
            ActionLookupResult lookup = fixture.Ledger.Get(
                fixture.Principal.SecurityPrincipalId,
                SessionId,
                action.ActionId);
            ActionReceipt retry =
                await fixture.ExecuteAsync(Clone(action));

            Assert.Equal(ActionOutcome.Unknown, first.Outcome);
            Assert.Equal(
                ReconcileKind.ManualRequired,
                first.ReconcileKind);
            Assert.Equal(ActionLookupKind.Unknown, lookup.Kind);
            Assert.Same(first, lookup.Receipt.ContractReceipt);
            Assert.Same(first, retry);
            Assert.Equal(ActionOutcome.Unknown, retry.Outcome);
            Assert.Equal(first.ActionId, retry.ActionId);
            Assert.Equal(first.ReasonCode, retry.ReasonCode);
            Assert.Equal(first.ReconcileKind, retry.ReconcileKind);
            Assert.Equal(1, performer.CallCount);
            Assert.Equal(1, fixture.Lease.ActionsConsumed);
        }

        [Fact]
        public async Task
            ResponseCompletionCommitsLedgerOnlyAfterDeliveryCommit()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    shutdown: true);
            int hostCommitCount = 0;
            int hostAbortCount = 0;
            var hostCompletion =
                new AgentRuntimeResponseCompletion(
                    () => Interlocked.Increment(
                        ref hostCommitCount),
                    () => Interlocked.Increment(
                        ref hostAbortCount));
            fixture.SetPerformer(
                new ImmediatePerformer(
                    AgentActionPerformance.Completed(
                        ActionOutcome.InputDispatched,
                        EvidenceKind.BrokerDispatch,
                        TargetId,
                        false,
                        reasonCode: "shutdown_requested",
                        responseCompletion:
                            hostCompletion)));
            ActionEnvelope action = fixture.Action();

            AgentRuntimeActionExecutionResult execution =
                await fixture.ExecuteWithDeliveryAsync(action);
            ActionReceipt receipt = execution.Receipt;
            ActionLookupResult beforeCommit =
                fixture.Lookup(action);
            AgentRuntimeResponseCompletion deliveryCompletion =
                execution.ResponseCompletion;

            Assert.NotNull(deliveryCompletion);
            Assert.Equal(
                ActionOutcome.InputDispatched,
                receipt.Outcome);
            Assert.Equal(
                ActionLookupKind.Unknown,
                beforeCommit.Kind);
            Assert.Equal(
                ActionReconcileKind.ManualRequired,
                beforeCommit.Receipt.ReconcileKind);
            Assert.Equal(0, hostCommitCount);
            Assert.Equal(0, hostAbortCount);
            Assert.True(
                deliveryCompletion.TryPrepareWrite());
            deliveryCompletion.CommitAfterWrite();
            deliveryCompletion.CommitAfterWrite();
            deliveryCompletion.Abort();

            ActionLookupResult afterCommit =
                fixture.Lookup(action);
            Assert.Equal(
                ActionLookupKind.TerminalReceipt,
                afterCommit.Kind);
            Assert.Same(
                receipt,
                afterCommit.Receipt.ContractReceipt);
            Assert.Equal(1, hostCommitCount);
            Assert.Equal(0, hostAbortCount);
            Assert.Single(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionResponseWritten);
        }

        [Fact]
        public async Task
            ResponseCompletionAbortLeavesActionGetLedgerUnknownManual()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    shutdown: true);
            int hostCommitCount = 0;
            int hostAbortCount = 0;
            var hostCompletion =
                new AgentRuntimeResponseCompletion(
                    () => Interlocked.Increment(
                        ref hostCommitCount),
                    () => Interlocked.Increment(
                        ref hostAbortCount));
            fixture.SetPerformer(
                new ImmediatePerformer(
                    AgentActionPerformance.Completed(
                        ActionOutcome.InputDispatched,
                        EvidenceKind.BrokerDispatch,
                        TargetId,
                        false,
                        reasonCode: "shutdown_requested",
                        responseCompletion:
                            hostCompletion)));
            ActionEnvelope action = fixture.Action();

            AgentRuntimeActionExecutionResult execution =
                await fixture.ExecuteWithDeliveryAsync(action);
            AgentRuntimeResponseCompletion deliveryCompletion =
                execution.ResponseCompletion;
            Assert.NotNull(deliveryCompletion);
            Assert.True(
                deliveryCompletion.TryPrepareWrite());
            deliveryCompletion.Abort();
            deliveryCompletion.Abort();
            deliveryCompletion.CommitAfterWrite();

            ActionLookupResult actionGetLedger =
                fixture.Lookup(action);
            Assert.Equal(
                ActionLookupKind.Unknown,
                actionGetLedger.Kind);
            Assert.Equal(
                ActionReceiptOutcome.Unknown,
                actionGetLedger.Receipt.Outcome);
            Assert.Equal(
                ActionReconcileKind.ManualRequired,
                actionGetLedger.Receipt.ReconcileKind);
            Assert.Equal(
                "reconcile_required",
                actionGetLedger.Receipt.ReasonCode);
            Assert.NotNull(
                actionGetLedger.Receipt.ContractReceipt);
            Assert.Empty(
                AgentContractValidator.Validate(
                    actionGetLedger.Receipt
                        .ContractReceipt));
            Assert.Equal(0, hostCommitCount);
            Assert.Equal(1, hostAbortCount);
            Assert.Single(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionResponseUnknown);
        }

        [Fact]
        public async Task
            ConcurrentShutdownReplayAfterDeliveryAbortReturnsExactUnknownReceipt()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    shutdown: true);
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    false,
                    reasonCode: "shutdown_requested",
                    responseCompletion:
                        new AgentRuntimeResponseCompletion(
                            () => { },
                            () => { })));
            fixture.SetPerformer(performer);
            ActionEnvelope action = fixture.Action();

            AgentRuntimeActionExecutionResult owner =
                await fixture.ExecuteWithDeliveryAsync(action);
            Task<AgentRuntimeActionExecutionResult> duplicate =
                fixture.ExecuteWithDeliveryAsync(
                    Clone(action));

            Assert.True(
                owner.ResponseCompletion.TryPrepareWrite());
            Assert.True(owner.ResponseCompletion.Abort());

            ActionReceipt durableUnknown =
                fixture.Lookup(action)
                    .Receipt.ContractReceipt;
            AgentRuntimeActionExecutionResult replay =
                await duplicate.WaitAsync(
                    TimeSpan.FromSeconds(5));

            Assert.NotNull(durableUnknown);
            Assert.Same(durableUnknown, replay.Receipt);
            Assert.True(replay.Receipt.Terminal);
            Assert.Equal(
                action.ActionId,
                replay.Receipt.ActionId);
            Assert.Equal(
                ActionOutcome.Unknown,
                replay.Receipt.Outcome);
            Assert.Equal(
                EvidenceKind.ReconciliationRequired,
                replay.Receipt.EvidenceKind);
            Assert.Equal(
                "reconcile_required",
                replay.Receipt.ReasonCode);
            Assert.Equal(
                ReconcileKind.ManualRequired,
                replay.Receipt.ReconcileKind);
            Assert.False(replay.Receipt.Retryable);
            Assert.Equal(
                TargetId,
                replay.Receipt.ActualTargetId);
            Assert.Equal(
                action.ObservationId,
                replay.Receipt.BeforeObservationId);
            Assert.Equal(
                LeaseState.Consumed,
                replay.Receipt.LeaseState);
            Assert.Null(replay.ResponseCompletion);
            Assert.Equal(1, performer.CallCount);
            Assert.Single(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionResponseUnknown);
            Assert.Single(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionValidation);
        }

        [Fact]
        public async Task
            ShutdownAbortAcknowledgementHoldsWriterReservation()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    shutdown: true);
            using var abortEntered =
                new ManualResetEventSlim(false);
            using var releaseAbort =
                new ManualResetEventSlim(false);
            var hostCompletion =
                new AgentRuntimeResponseCompletion(
                    () => { },
                    () =>
                    {
                        abortEntered.Set();
                        releaseAbort.Wait(
                            TimeSpan.FromSeconds(5));
                    });
            fixture.SetPerformer(
                new ImmediatePerformer(
                    AgentActionPerformance.Completed(
                        ActionOutcome.InputDispatched,
                        EvidenceKind.BrokerDispatch,
                        TargetId,
                        false,
                        reasonCode: "shutdown_requested",
                        responseCompletion:
                            hostCompletion)));

            AgentRuntimeActionExecutionResult execution =
                await fixture.ExecuteWithDeliveryAsync(
                    fixture.Action());
            Assert.True(
                execution.ResponseCompletion
                    .TryPrepareWrite());
            Task<bool> abort = Task.Run(
                execution.ResponseCompletion.Abort);
            Assert.True(
                abortEntered.Wait(
                    TimeSpan.FromSeconds(5)));

            InvalidOperationException blocked =
                Assert.Throws<InvalidOperationException>(
                    fixture.AcquireReplacementShutdownLease);
            Assert.Equal(
                "write_lease_already_held",
                blocked.Message);

            releaseAbort.Set();
            Assert.True(
                await abort.WaitAsync(
                    TimeSpan.FromSeconds(5)));
            WriteLease replacement =
                fixture.AcquireReplacementShutdownLease();
            Assert.Equal(
                WriteLeaseState.Active,
                replacement.State);
            Assert.True(
                fixture.Leases.Revoke(
                    replacement.LeaseId,
                    "test_cleanup"));
        }

        [Fact]
        public async Task
            FailedShutdownAbortAcknowledgementRetainsReservation()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    shutdown: true);
            var hostCompletion =
                new AgentRuntimeResponseCompletion(
                    () => { },
                    () => throw new InvalidOperationException(
                        "ui_dispatch_unavailable"));
            fixture.SetPerformer(
                new ImmediatePerformer(
                    AgentActionPerformance.Completed(
                        ActionOutcome.InputDispatched,
                        EvidenceKind.BrokerDispatch,
                        TargetId,
                        false,
                        reasonCode: "shutdown_requested",
                        responseCompletion:
                            hostCompletion)));

            AgentRuntimeActionExecutionResult execution =
                await fixture.ExecuteWithDeliveryAsync(
                    fixture.Action());
            Assert.True(
                execution.ResponseCompletion
                    .TryPrepareWrite());
            Assert.False(
                execution.ResponseCompletion.Abort());

            InvalidOperationException blocked =
                Assert.Throws<InvalidOperationException>(
                    fixture.AcquireReplacementShutdownLease);
            Assert.Equal(
                "write_lease_already_held",
                blocked.Message);
        }

        [Fact]
        public async Task
            UnknownOutcomeWithFailedHostAbortRetainsReservation()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    shutdown: true);
            int hostAbortCount = 0;
            var hostCompletion =
                new AgentRuntimeResponseCompletion(
                    () => { },
                    () =>
                    {
                        Interlocked.Increment(
                            ref hostAbortCount);
                        throw new InvalidOperationException(
                            "ui_dispatch_unavailable");
                    });
            fixture.SetPerformer(
                new ImmediatePerformer(
                    AgentActionPerformance.Completed(
                        ActionOutcome.Unknown,
                        EvidenceKind.ReconciliationRequired,
                        TargetId,
                        false,
                        reasonCode: "reconcile_required",
                        responseCompletion:
                            hostCompletion)));

            AgentRuntimeActionExecutionResult execution =
                await fixture.ExecuteWithDeliveryAsync(
                    fixture.Action());
            execution.ResponseCompletion
                ?.CommitAfterWrite();

            Assert.Equal(
                ActionOutcome.Unknown,
                execution.Receipt.Outcome);
            Assert.Null(execution.ResponseCompletion);
            Assert.Equal(1, hostAbortCount);
            Assert.True(
                fixture.Lease.ActionExecutionPending);
            InvalidOperationException blocked =
                Assert.Throws<InvalidOperationException>(
                    fixture.AcquireReplacementLease);
            Assert.Equal(
                "write_lease_already_held",
                blocked.Message);
            Assert.Equal(
                ActionLookupKind.Unknown,
                fixture.Ledger.Get(
                    fixture.Principal
                        .SecurityPrincipalId,
                    SessionId,
                    "action_missing_AAAAAAAAA").Kind);
        }

        [Fact]
        public async Task
            TerminalAuditFailureWithFailedHostAbortRetainsReservation()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    shutdown: true);
            int hostAbortCount = 0;
            var hostCompletion =
                new AgentRuntimeResponseCompletion(
                    () => { },
                    () =>
                    {
                        Interlocked.Increment(
                            ref hostAbortCount);
                        throw new InvalidOperationException(
                            "ui_dispatch_unavailable");
                    });
            fixture.SetAuditSink(
                new FailFirstTerminalAuditSink(
                    fixture.Audit));
            fixture.SetPerformer(
                new ImmediatePerformer(
                    AgentActionPerformance.Completed(
                        ActionOutcome.InputDispatched,
                        EvidenceKind.BrokerDispatch,
                        TargetId,
                        false,
                        reasonCode: "shutdown_requested",
                        responseCompletion:
                            hostCompletion)));

            AgentRuntimeActionExecutionResult execution =
                await fixture.ExecuteWithDeliveryAsync(
                    fixture.Action());
            execution.ResponseCompletion
                ?.CommitAfterWrite();

            Assert.Equal(
                ActionOutcome.Unknown,
                execution.Receipt.Outcome);
            Assert.Null(execution.ResponseCompletion);
            Assert.Equal(1, hostAbortCount);
            Assert.True(
                fixture.Lease.ActionExecutionPending);
            InvalidOperationException blocked =
                Assert.Throws<InvalidOperationException>(
                    fixture.AcquireReplacementLease);
            Assert.Equal(
                "write_lease_already_held",
                blocked.Message);
            Assert.Equal(
                ActionLookupKind.Unknown,
                fixture.Ledger.Get(
                    fixture.Principal
                        .SecurityPrincipalId,
                    SessionId,
                    "action_missing_BBBBBBBBB").Kind);
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task
            ConsumedPredispatchRejectionHoldsReservationUntilResponseCompletion(
                bool commitResponse)
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    requestedActionLimit: 1);
            ActionEnvelope action = fixture.Action();
            action.ExpectedLifecycleGeneration++;

            AgentRuntimeActionExecutionResult execution =
                await fixture.ExecuteWithDeliveryAsync(action)
                    .WaitAsync(TimeSpan.FromSeconds(5));

            Assert.Equal(
                ActionOutcome.Rejected,
                execution.Receipt.Outcome);
            Assert.Equal(
                "stale_observation",
                execution.Receipt.ReasonCode);
            Assert.NotNull(execution.ResponseCompletion);
            Assert.True(
                fixture.Lease.ActionExecutionPending);
            InvalidOperationException blocked =
                Assert.Throws<InvalidOperationException>(
                    fixture.AcquireReplacementLease);
            Assert.Equal(
                "write_lease_already_held",
                blocked.Message);

            Assert.True(
                commitResponse
                    ? execution.ResponseCompletion
                        .CommitAfterWrite()
                    : execution.ResponseCompletion.Abort());
            Assert.False(
                fixture.Lease.ActionExecutionPending);

            AgentRuntimeActionExecutionResult replay =
                await fixture.ExecuteWithDeliveryAsync(
                        Clone(action))
                    .WaitAsync(TimeSpan.FromSeconds(5));
            Assert.Same(
                execution.Receipt,
                replay.Receipt);
            Assert.Null(replay.ResponseCompletion);

            WriteLease replacement =
                fixture.AcquireReplacementLease();
            Assert.True(
                fixture.Leases.Revoke(
                    replacement.LeaseId,
                    "test_cleanup"));
        }

        [Fact]
        public async Task
            RejectedSecondActionCannotReleaseFirstExecutionReservation()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    requestedActionLimit: 2);
            var performer = new BlockingPerformer();
            fixture.SetPerformer(performer);
            ActionEnvelope firstAction = fixture.Action();

            Task<AgentRuntimeActionExecutionResult> first =
                fixture.ExecuteWithDeliveryAsync(firstAction);
            await performer.Entered.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            ActionEnvelope secondAction =
                Clone(firstAction);
            secondAction.ActionId =
                "action_BBBBBBBBBBBBBBBBB";
            secondAction.IdempotencyKey =
                "idempotency_BBBBBBBBBB";

            AgentRuntimeActionExecutionResult second =
                await fixture.ExecuteWithDeliveryAsync(
                        secondAction)
                    .WaitAsync(TimeSpan.FromSeconds(5));

            Assert.Equal(
                ActionOutcome.Rejected,
                second.Receipt.Outcome);
            Assert.Equal(
                "lease_busy",
                second.Receipt.ReasonCode);
            Assert.Null(second.ResponseCompletion);
            Assert.Equal(1, performer.CallCount);
            Assert.True(
                fixture.Lease.ActionExecutionPending);
            Assert.True(
                fixture.Leases.Release(
                    fixture.Lease.LeaseId,
                    fixture.Principal.ClientInstanceId,
                    fixture.Principal.SecurityPrincipalId));
            InvalidOperationException blockedWhileDispatching =
                Assert.Throws<InvalidOperationException>(
                    fixture.AcquireReplacementLease);
            Assert.Equal(
                "write_lease_already_held",
                blockedWhileDispatching.Message);

            performer.Complete(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            AgentRuntimeActionExecutionResult firstExecution =
                await first.WaitAsync(
                    TimeSpan.FromSeconds(5));
            Assert.NotNull(
                firstExecution.ResponseCompletion);
            InvalidOperationException blockedBeforeResponse =
                Assert.Throws<InvalidOperationException>(
                    fixture.AcquireReplacementLease);
            Assert.Equal(
                "write_lease_already_held",
                blockedBeforeResponse.Message);

            Assert.True(
                firstExecution.ResponseCompletion
                    .CommitAfterWrite());
            WriteLease replacement =
                fixture.AcquireReplacementLease();
            Assert.True(
                fixture.Leases.Revoke(
                    replacement.LeaseId,
                    "test_cleanup"));
        }

        [Fact]
        public async Task RevokingTrackedLeaseCancelsPendingActionAsUnknown()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync();
            var performer = new CancellationPerformer();
            fixture.SetPerformer(performer);
            ActionEnvelope action = fixture.Action();

            Task<ActionReceipt> pending =
                fixture.ExecuteAsync(action);
            await performer.Entered.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            fixture.Revocations
                .RevokeLeaseAndCancelQueuedActions(
                    SessionId,
                    fixture.Lease.LeaseId,
                    "human_input");

            ActionReceipt receipt = await pending.WaitAsync(
                TimeSpan.FromSeconds(5));
            Assert.Equal(WriteLeaseState.Revoked,
                fixture.Lease.State);
            Assert.Equal("human_input", fixture.Lease.RevokeReason);
            Assert.Equal(ActionOutcome.Unknown, receipt.Outcome);
            Assert.NotEqual(ReconcileKind.None,
                receipt.ReconcileKind);
        }

        [Fact]
        public async Task
            StructuredActionQueuedHumanBeforeClaimRejectsWithoutPerformer()
        {
            using var deliveryEntered =
                new ManualResetEventSlim(false);
            using var releaseDelivery =
                new ManualResetEventSlim(false);
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    structuredAction: true,
                    externalInputDeliveryEntered:
                        deliveryEntered,
                    releaseExternalInputDelivery:
                        releaseDelivery);
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    false));
            fixture.SetPerformer(performer);

            try
            {
                fixture.ObserveExternalInput();
                Assert.True(
                    deliveryEntered.Wait(
                        TimeSpan.FromSeconds(5)));

                ActionReceipt receipt =
                    await fixture.ExecuteAsync(
                        fixture.Action())
                        .WaitAsync(TimeSpan.FromSeconds(5));

                Assert.Equal(
                    ActionOutcome.Rejected,
                    receipt.Outcome);
                Assert.Equal(
                    "external_input_preempted",
                    receipt.ReasonCode);
                Assert.Equal(
                    "human_input",
                    fixture.Lease.RevokeReason);
                Assert.Equal(0, performer.CallCount);
                Assert.Contains(
                    fixture.AuditEntries(),
                    entry => entry.EventType
                        == AgentRuntimeAuditEventTypes
                            .ActionBindingValidated);
                Assert.DoesNotContain(
                    fixture.AuditEntries(),
                    entry => entry.EventType
                        == AgentRuntimeAuditEventTypes
                            .ActionDispatchStarted);
            }
            finally
            {
                releaseDelivery.Set();
            }
        }

        [Fact]
        public async Task
            StructuredActionQueuedInjectedInputKeepsExternalClassification()
        {
            using var deliveryEntered =
                new ManualResetEventSlim(false);
            using var releaseDelivery =
                new ManualResetEventSlim(false);
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    structuredAction: true,
                    externalInputDeliveryEntered:
                        deliveryEntered,
                    releaseExternalInputDelivery:
                        releaseDelivery);
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    false));
            fixture.SetPerformer(performer);

            try
            {
                fixture.ObserveInjectedExternalInput();
                Assert.True(
                    deliveryEntered.Wait(
                        TimeSpan.FromSeconds(5)));

                ActionReceipt receipt =
                    await fixture.ExecuteAsync(
                        fixture.Action())
                        .WaitAsync(TimeSpan.FromSeconds(5));

                Assert.Equal(
                    ActionOutcome.Rejected,
                    receipt.Outcome);
                Assert.Equal(
                    "external_input_preempted",
                    receipt.ReasonCode);
                Assert.Equal(
                    "external_input",
                    fixture.Lease.RevokeReason);
                Assert.Equal(0, performer.CallCount);
                Assert.Contains(
                    fixture.AuditEntries(),
                    entry => entry.EventType
                        == AgentRuntimeAuditEventTypes
                            .ActionBindingValidated);
                Assert.DoesNotContain(
                    fixture.AuditEntries(),
                    entry => entry.EventType
                        == AgentRuntimeAuditEventTypes
                            .ActionDispatchStarted);
            }
            finally
            {
                releaseDelivery.Set();
            }
        }

        [Fact]
        public async Task
            StructuredActionHookLossBeforeClaimRejectsWithoutPerformer()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    structuredAction: true);
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    false));
            fixture.SetPerformer(performer);
            fixture.FailHookAfterNextHealthyCheck();

            ActionReceipt receipt =
                await fixture.ExecuteAsync(
                    fixture.Action())
                    .WaitAsync(TimeSpan.FromSeconds(5));

            Assert.Equal(
                ActionOutcome.Rejected,
                receipt.Outcome);
            Assert.Equal(
                "input_guard_unhealthy",
                receipt.ReasonCode);
            Assert.Equal(
                "input_guard_unhealthy",
                fixture.Lease.RevokeReason);
            Assert.Equal(0, performer.CallCount);
            Assert.Contains(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionBindingValidated);
            Assert.DoesNotContain(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionDispatchStarted);
        }

        [Fact]
        public async Task
            StructuredActionClaimBeforeHumanInputKeepsDispatchOwnership()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    structuredAction: true);
            var performer =
                new CancellationObservingBlockingPerformer();
            fixture.SetPerformer(performer);
            Task<ActionReceipt> pending =
                fixture.ExecuteAsync(fixture.Action());
            await performer.Entered.Task.WaitAsync(
                TimeSpan.FromSeconds(5));
            using var externalInputDelivered =
                new ManualResetEventSlim(false);

            fixture.ObserveExternalInput(
                externalInputDelivered);

            Assert.True(
                externalInputDelivered.Wait(
                    TimeSpan.FromSeconds(5)));
            Assert.False(
                performer.CancellationRequested);
            Assert.Equal(
                WriteLeaseState.Consumed,
                fixture.Lease.State);

            performer.Complete(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    false));
            ActionReceipt receipt = await pending.WaitAsync(
                TimeSpan.FromSeconds(5));

            Assert.Equal(
                ActionOutcome.InputDispatched,
                receipt.Outcome);
            Assert.Equal(1, performer.CallCount);
            Assert.Contains(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionDispatchStarted);
        }

        [Fact]
        public async Task
            ClaimedStructuredActionSurvivesSynchronousPanelInvalidation()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    structuredAction: true);
            var performer = new CallbackPerformer(
                delegate
                {
                    fixture.Revocations.HandleSessionInvalidation(
                        new SessionScopeInvalidation(
                            SessionInvalidationLevel.Panel,
                            "panel_opened",
                            SessionId,
                            fixture.Observation
                                .LifecycleGeneration,
                            SessionInvalidationFlags.Observations
                            | SessionInvalidationFlags
                                .PendingActions
                            | SessionInvalidationFlags
                                .PendingDomainOperations
                            | SessionInvalidationFlags
                                .ExactInstanceLeases,
                            new[] { TargetId },
                            affectsAllTargets: false,
                            requiresHumanReauthorization:
                                false));
                },
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    false));
            fixture.SetPerformer(performer);

            ActionReceipt receipt =
                await fixture.ExecuteAsync(
                    fixture.Action())
                    .WaitAsync(TimeSpan.FromSeconds(5));

            Assert.False(
                performer.CancellationRequestedAfterCallback);
            Assert.Equal(
                ActionOutcome.InputDispatched,
                receipt.Outcome);
            Assert.Equal(
                EvidenceKind.BrokerDispatch,
                receipt.EvidenceKind);
            Assert.Equal("none", receipt.ReasonCode);
            Assert.Equal(1, performer.CallCount);
        }

        [Theory]
        [InlineData((int)SessionInvalidationFlags.WriteLeases)]
        [InlineData((int)SessionInvalidationFlags.PendingCoordinateActions)]
        [InlineData((int)SessionInvalidationFlags.PendingInput)]
        [InlineData((int)SessionInvalidationFlags.QueuedActions)]
        [InlineData((int)SessionInvalidationFlags.RuntimeHeldInput)]
        [InlineData((int)SessionInvalidationFlags.AttemptScopedAuthorities)]
        public async Task
            ClaimedStructuredActionRejectsStrongerPanelInvalidation(
                int extraFlagValue)
        {
            var extraFlag =
                (SessionInvalidationFlags)extraFlagValue;
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    structuredAction: true);
            var performer = new CancellationPerformer();
            fixture.SetPerformer(performer);
            Task<ActionReceipt> pending =
                fixture.ExecuteAsync(fixture.Action());
            await performer.Entered.Task.WaitAsync(
                TimeSpan.FromSeconds(5));

            fixture.Revocations.HandleSessionInvalidation(
                new SessionScopeInvalidation(
                    SessionInvalidationLevel.Panel,
                    "panel_opened",
                    SessionId,
                    fixture.Observation
                        .LifecycleGeneration,
                    SessionInvalidationFlags.Observations
                    | SessionInvalidationFlags
                        .PendingActions
                    | SessionInvalidationFlags
                        .PendingDomainOperations
                    | SessionInvalidationFlags
                        .ExactInstanceLeases
                    | extraFlag,
                    new[] { TargetId },
                    affectsAllTargets: false,
                    requiresHumanReauthorization: false));

            Assert.True(
                await performer.Cancelled.Task.WaitAsync(
                    TimeSpan.FromSeconds(5)));
            ActionReceipt receipt = await pending.WaitAsync(
                TimeSpan.FromSeconds(5));
            Assert.Equal(
                ActionOutcome.Unknown,
                receipt.Outcome);
            Assert.Equal(
                "reconcile_required",
                receipt.ReasonCode);
        }

        [Theory]
        [InlineData("credential")]
        [InlineData("lifecycle")]
        [InlineData("connection")]
        public async Task
            ClaimedStructuredActionStillHonorsSecurityRevocation(
                string revocationKind)
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    structuredAction: true);
            var performer = new CancellationPerformer();
            fixture.SetPerformer(performer);
            Task<ActionReceipt> pending =
                fixture.ExecuteAsync(fixture.Action());
            await performer.Entered.Task.WaitAsync(
                TimeSpan.FromSeconds(5));

            switch (revocationKind)
            {
                case "credential":
                    fixture.Revocations.RevokeCredential(
                        fixture.Principal.CredentialId,
                        "credential_revoked");
                    break;
                case "lifecycle":
                    fixture.Revocations
                        .HandleSessionInvalidation(
                            new SessionScopeInvalidation(
                                SessionInvalidationLevel
                                    .Lifecycle,
                                "stale_lifecycle",
                                SessionId,
                                fixture.Observation
                                    .LifecycleGeneration + 1,
                                SessionInvalidationFlags
                                    .WriteLeases
                                | SessionInvalidationFlags
                                    .PendingActions,
                                new[] { TargetId },
                                affectsAllTargets: true,
                                requiresHumanReauthorization:
                                    false));
                    break;
                case "connection":
                    fixture.Revocations.RevokeConnection(
                        fixture.Context.ConnectionId,
                        "connection_closed");
                    break;
                default:
                    throw new InvalidOperationException(
                        "unknown_revocation_kind");
            }

            Assert.True(
                await performer.Cancelled.Task.WaitAsync(
                    TimeSpan.FromSeconds(5)));
            Assert.Equal(
                WriteLeaseState.Revoked,
                fixture.Lease.State);
            try
            {
                _ = await pending.WaitAsync(
                    TimeSpan.FromSeconds(5));
            }
            catch (InvalidOperationException)
                when (revocationKind == "credential"
                    || revocationKind == "connection")
            {
                // Revoking the exact credential or connection may also
                // close the audit scope while the cancellation receipt is
                // being sealed.
            }
        }

        [Fact]
        public async Task
            StructuredActionConnectionRevokeBeforeRegistrationIsRejected()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    structuredAction: true);
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    false));
            var audit = new CallbackAuditSink(
                AgentRuntimeAuditEventTypes
                    .ActionBindingValidated,
                () => fixture.Revocations
                    .RevokeConnection(
                        fixture.Context.ConnectionId,
                        "connection_closed"));
            fixture.SetAuditSink(audit);
            fixture.SetPerformer(performer);

            ActionReceipt receipt =
                await fixture.ExecuteAsync(
                    fixture.Action())
                    .WaitAsync(TimeSpan.FromSeconds(5));

            Assert.Equal(
                ActionOutcome.Rejected,
                receipt.Outcome);
            Assert.Equal(
                "lease_revoked",
                receipt.ReasonCode);
            Assert.Equal(0, performer.CallCount);
            Assert.Equal(
                WriteLeaseState.Revoked,
                fixture.Lease.State);
            Assert.Equal(
                "connection_closed",
                fixture.Lease.RevokeReason);
            Assert.True(
                audit.Contains(
                    AgentRuntimeAuditEventTypes
                        .ActionBindingValidated));
            Assert.False(
                audit.Contains(
                    AgentRuntimeAuditEventTypes
                        .ActionDispatchStarted));
        }

        [Fact]
        public async Task
            StructuredActionPredispatchCancellationNeverLeaksConsumedReason()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    structuredAction: true);
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    false));
            fixture.SetPerformer(performer);
            using var cancellation =
                new CancellationTokenSource();
            cancellation.Cancel();

            ActionReceipt receipt =
                await fixture.ExecuteAsync(
                    fixture.Action(),
                    cancellation.Token)
                    .WaitAsync(TimeSpan.FromSeconds(5));

            Assert.Equal(
                ActionOutcome.Rejected,
                receipt.Outcome);
            Assert.Equal(
                "lease_revoked",
                receipt.ReasonCode);
            Assert.Equal(
                "lease_revoked",
                fixture.Lease.RevokeReason);
            Assert.Equal(0, performer.CallCount);
            Assert.DoesNotContain(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionDispatchStarted);
        }

        [Fact]
        public async Task
            GuiPredispatchCallerCancellationKeepsMultiActionLeaseActive()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    requestedActionLimit: 2);
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            fixture.SetPerformer(performer);
            using var cancellation =
                new CancellationTokenSource();
            cancellation.Cancel();

            ActionReceipt receipt =
                await fixture.ExecuteAsync(
                    fixture.Action(),
                    cancellation.Token)
                    .WaitAsync(TimeSpan.FromSeconds(5));

            Assert.Equal(
                ActionOutcome.Rejected,
                receipt.Outcome);
            Assert.Equal(
                "internal_error",
                receipt.ReasonCode);
            Assert.Equal(
                WriteLeaseState.Active,
                fixture.Lease.State);
            Assert.Null(fixture.Lease.RevokeReason);
            Assert.Equal(1, fixture.Lease.ActionsConsumed);
            Assert.False(
                fixture.Lease.ActionExecutionPending);
            Assert.Equal(0, performer.CallCount);
            Assert.DoesNotContain(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionDispatchStarted);
        }

        [Fact]
        public async Task ReleaseReturnsExactLeaseAndPreventsUse()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync();

            Assert.True(fixture.Leases.Release(
                fixture.Lease.LeaseId,
                fixture.Principal.ClientInstanceId,
                fixture.Principal.SecurityPrincipalId,
                out WriteLease released,
                out string releaseReason));
            Assert.Null(releaseReason);
            Assert.Same(fixture.Lease, released);
            Assert.Equal(WriteLeaseState.Released, released.State);

            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            fixture.SetPerformer(performer);
            ActionReceipt receipt =
                await fixture.ExecuteAsync(fixture.Action());
            Assert.Equal(ActionOutcome.Rejected, receipt.Outcome);
            Assert.Equal(0, performer.CallCount);
        }

        [Fact]
        public async Task ForgedCredentialFailsClosedBeforeDispatch()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync();
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            fixture.SetPerformer(performer);
            AgentRuntimeDispatchContext wrongOwner =
                new AgentRuntimeDispatchContext(
                    fixture.Context.ConnectionId,
                    new PrincipalCredential(
                        fixture.Principal.CredentialId,
                        fixture.Principal.SecurityPrincipalId,
                        "client_BBBBBBBBBBBBBBBBB",
                        fixture.Principal.PrincipalKind,
                        fixture.Principal.SessionMode,
                        fixture.Principal.Generation,
                        fixture.Principal.IssuedMonotonic,
                        fixture.Principal.ExpiresMonotonic,
                        fixture.Principal.IssuedUtc,
                        fixture.Principal.AllowedCapabilities,
                        fixture.Principal.AllowedTargets,
                        fixture.Principal.IssuerReceipt,
                        fixture.Principal.SelectedSessionId,
                        fixture.Principal.BuildIdentity,
                        fixture.Principal.AttemptId,
                        fixture.Principal.Slot));

            InvalidOperationException error =
                await Assert.ThrowsAsync<InvalidOperationException>(
                    () => fixture.Broker.ExecuteAsync(
                        wrongOwner,
                        fixture.Action(),
                        AgentCapabilitiesV1.Click,
                        CancellationToken.None));

            Assert.Equal(
                "credential_owner_mismatch",
                error.Message);
            Assert.Equal(0, performer.CallCount);
        }

        [Fact]
        public async Task TerminalReceiptSequenceComesFromScopedAuditAndCarriesOnlyFrameHashes()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync();
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            fixture.SetPerformer(performer);

            ActionReceipt receipt =
                await fixture.ExecuteAsync(fixture.Action());
            AuditEntry terminal = Assert.Single(
                fixture.AuditEntries(),
                entry =>
                    string.Equals(
                        entry.EventType,
                        AgentRuntimeAuditEventTypes.ActionTerminal,
                        StringComparison.Ordinal));
            using JsonDocument payload =
                JsonDocument.Parse(terminal.CanonicalPayload);
            JsonElement root = payload.RootElement;

            Assert.NotEqual(0UL, receipt.AuditSequence);
            Assert.Equal(
                receipt.AuditSequence,
                root.GetProperty("auditSequence").GetUInt64());
            Assert.Equal(
                fixture.Observation.Frames[0].ContentHash,
                root.GetProperty("beforeKeyframe")
                    .GetProperty("frameHash")
                    .GetString());
            Assert.False(
                string.IsNullOrWhiteSpace(
                    root.GetProperty("afterKeyframe")
                        .GetProperty("frameHash")
                        .GetString()));
            Assert.DoesNotContain(
                "opaqueContentHandle",
                terminal.CanonicalPayload,
                StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain(
                "\"pixels\"",
                terminal.CanonicalPayload,
                StringComparison.OrdinalIgnoreCase);
            Assert.Contains(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionDispatchStarted);
        }

        [Fact]
        public async Task RejectedAndUnknownOutcomesHaveExplicitTerminalFacts()
        {
            using ActionFixture rejectedFixture =
                await ActionFixture.CreateAsync();
            Assert.True(rejectedFixture.Leases.Release(
                rejectedFixture.Lease.LeaseId,
                rejectedFixture.Principal.ClientInstanceId,
                rejectedFixture.Principal.SecurityPrincipalId,
                out _,
                out _));
            var rejectedPerformer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            rejectedFixture.SetPerformer(rejectedPerformer);

            ActionReceipt rejected =
                await rejectedFixture.ExecuteAsync(
                    rejectedFixture.Action());

            Assert.Equal(ActionOutcome.Rejected, rejected.Outcome);
            Assert.Equal(0, rejectedPerformer.CallCount);
            Assert.Contains(
                rejectedFixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes.ActionRejected);
            Assert.Contains(
                rejectedFixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes.ActionTerminal);

            using ActionFixture unknownFixture =
                await ActionFixture.CreateAsync();
            unknownFixture.SetPerformer(
                new ImmediatePerformer(
                    AgentActionPerformance.Unknown(
                        "reconcile_required",
                        ReconcileKind.ManualRequired)));

            ActionReceipt unknown =
                await unknownFixture.ExecuteAsync(
                    unknownFixture.Action());

            Assert.Equal(ActionOutcome.Unknown, unknown.Outcome);
            Assert.Contains(
                unknownFixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes.ActionUnknown);
            Assert.Contains(
                unknownFixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes
                        .ActionReconcileRequired);
            Assert.Contains(
                unknownFixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes.ActionTerminal);
        }

        [Fact]
        public async Task AuditUnavailableBeforeValidationDispatchesNothing()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync();
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            fixture.SetAuditSink(new UnavailableAuditSink());
            fixture.SetPerformer(performer);
            ActionEnvelope action = fixture.Action();

            InvalidOperationException error =
                await Assert.ThrowsAsync<InvalidOperationException>(
                    () => fixture.ExecuteAsync(action));

            Assert.Equal("audit_unavailable", error.Message);
            Assert.Equal(0, performer.CallCount);
            Assert.Equal(0, fixture.Lease.ActionsConsumed);
            Assert.Equal(
                ActionLookupKind.ProvenNotDispatched,
                fixture.Ledger.Get(
                    fixture.Principal.SecurityPrincipalId,
                    SessionId,
                    action.ActionId).Kind);
        }

        [Fact]
        public async Task AuditFailureAfterDispatchFallsBackToAuditedUnknown()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync();
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            fixture.SetAuditSink(
                new FailFirstTerminalAuditSink(
                    fixture.Audit));
            fixture.SetPerformer(performer);

            ActionReceipt receipt =
                await fixture.ExecuteAsync(fixture.Action());

            Assert.Equal(ActionOutcome.Unknown, receipt.Outcome);
            Assert.NotEqual(ReconcileKind.None,
                receipt.ReconcileKind);
            Assert.NotEqual(0UL, receipt.AuditSequence);
            Assert.Equal(1, performer.CallCount);
            Assert.Contains(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes.ActionUnknown);
            Assert.Contains(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes.ActionTerminal);
        }

        [Fact]
        public async Task PlayerAssistArgumentBoundsMismatchRejectsBeforePerformer()
        {
            using ActionFixture fixture =
                await ActionFixture.CreateAsync(
                    requestedActionLimit: 1,
                    playerAssist: true);
            var performer = new ImmediatePerformer(
                AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    TargetId,
                    true));
            fixture.SetPerformer(performer);
            ActionEnvelope action = fixture.Action();
            action.Arguments =
                JsonSerializer.SerializeToElement(
                    new
                    {
                        x = 999,
                        y = 18,
                        button = "left"
                    });

            ActionReceipt receipt =
                await fixture.ExecuteAsync(action);

            Assert.Equal(ActionOutcome.Rejected, receipt.Outcome);
            Assert.Equal("arguments_invalid", receipt.ReasonCode);
            Assert.Equal(0, performer.CallCount);
            Assert.Contains(
                fixture.AuditEntries(),
                entry => entry.EventType
                    == AgentRuntimeAuditEventTypes.ActionRejected);
        }

        private static ActionEnvelope Clone(ActionEnvelope action)
        {
            return JsonSerializer.Deserialize<ActionEnvelope>(
                JsonSerializer.Serialize(
                    action,
                    AgentProtocolV1.JsonOptions),
                AgentProtocolV1.JsonOptions);
        }

        private sealed class ActionFixture : IDisposable
        {
            private readonly ManualObservationClock _clock;
            private readonly PrincipalCredentialAuthority
                _credentialAuthority;
            private readonly MutableObservationAuthority _targets;
            private readonly ObservationGrantBroker _grants;
            private readonly PixelContentHandleStore _content;
            private readonly ObservationCaptureBroker _captures;
            private readonly AgentObservationEnvelopeStore
                _observationStore;
            private readonly NativeInputGuard _nativeGuard;
            private readonly ActionGuardWin32Facade _guardWin32;
            private IAgentRuntimeAuditSink _auditSink;

            private ActionFixture(
                ManualObservationClock clock,
                PrincipalCredentialAuthority credentialAuthority,
                MutableObservationAuthority targets,
                PrincipalCredential principal,
                ObservationGrantBroker grants,
                PixelContentHandleStore content,
                ObservationCaptureBroker captures,
                AgentObservationEnvelopeStore observationStore,
                WriteLeaseBroker leases,
                WriteLease lease,
                ActionIdempotencyLedger ledger,
                AgentRuntimeRevocationCoordinator revocations,
                NativeInputGuard nativeGuard,
                ActionGuardWin32Facade guardWin32,
                ScopedAgentRuntimeAuditLedgerManager audit,
                AgentRuntimeDispatchContext context,
                ObservationEnvelope observation)
            {
                _clock = clock;
                _credentialAuthority = credentialAuthority;
                _targets = targets;
                Principal = principal;
                _grants = grants;
                _content = content;
                _captures = captures;
                _observationStore = observationStore;
                Leases = leases;
                Lease = lease;
                Ledger = ledger;
                Revocations = revocations;
                _nativeGuard = nativeGuard;
                _guardWin32 = guardWin32;
                Audit = audit;
                _auditSink = audit;
                Context = context;
                Observation = observation;
            }

            public PrincipalCredential Principal { get; }
            public WriteLeaseBroker Leases { get; }
            public WriteLease Lease { get; }
            public ActionIdempotencyLedger Ledger { get; }
            public ScopedAgentRuntimeAuditLedgerManager Audit
            {
                get;
            }
            public AgentRuntimeRevocationCoordinator Revocations
            {
                get;
            }
            public AgentRuntimeDispatchContext Context { get; }
            public ObservationEnvelope Observation { get; }
            public AgentRuntimeActionExecutionBroker Broker
            {
                get;
                private set;
            }

            public static async Task<ActionFixture> CreateAsync(
                int requestedActionLimit = 8,
                bool playerAssist = false,
                bool shutdown = false,
                bool structuredAction = false,
                ManualResetEventSlim
                    externalInputDeliveryEntered = null,
                ManualResetEventSlim
                    releaseExternalInputDelivery = null)
            {
                if (shutdown && structuredAction)
                {
                    throw new ArgumentException(
                        "Only one one-shot action kind may be selected.");
                }
                var clock = new ManualObservationClock();
                var targets = new MutableObservationAuthority();
                bool launcherAction =
                    shutdown || structuredAction;
                string actionCapability =
                    shutdown
                        ? AgentCapabilitiesV1.SessionShutdown
                        : structuredAction
                            ? AgentCapabilitiesV1.PanelOpen
                            : AgentCapabilitiesV1.Click;
                targets.TargetSurfaceKind = launcherAction
                    ? SurfaceKind.Launcher
                    : SurfaceKind.Flash;
                targets.AddTarget(TargetId);
                targets.Plan = CapturePlan(launcherAction);
                var credentialAuthority =
                    new PrincipalCredentialAuthority(
                        clock,
                        new ObservationEnrollmentVerifier());
                PrincipalCredential principal =
                    playerAssist
                    ? credentialAuthority.IssuePlayerAssist(
                        new PlayerAssistCredentialEvidence
                        {
                            ClientInstanceId = ClientId,
                            ConsentReceipt =
                                "player-consent-receipt",
                            SelectedSessionId = SessionId,
                            AllowedCapabilities = new[]
                            {
                                "observe:pixels",
                                actionCapability
                            },
                            AllowedTargets =
                                new[] { TargetId }
                        })
                    : credentialAuthority.IssueDeveloper(
                        new DeveloperEnrollmentEvidence
                        {
                            ClientInstanceId = ClientId,
                            EnrollmentReceipt =
                                "developer-enrollment",
                            AllowedCapabilities = new[]
                            {
                                "observe:pixels",
                                actionCapability
                            },
                            AllowedTargets =
                                new[] { TargetId }
                        });
                var grants = new ObservationGrantBroker(
                    clock,
                    credentialAuthority,
                    targets);
                ObservationGrant grant = grants.Issue(
                    new ObservationGrantRequest
                    {
                        CredentialId = principal.CredentialId,
                        ClientInstanceId = ClientId,
                        SessionId = SessionId,
                        Targets = new[]
                        {
                            new ObservationTargetScope
                            {
                                TargetId = TargetId
                            }
                        },
                        DataScopes = new[]
                        {
                            ObservationDataScopesV1.Pixels
                        },
                        RequestedLifetime =
                            TimeSpan.FromMinutes(2),
                        ConsentReceipt =
                            playerAssist
                                ? principal.IssuerReceipt
                                : null
                    });
                var content = new PixelContentHandleStore(
                    clock,
                    grants,
                    new RecordingPixelAuditSink());
                var captures = new ObservationCaptureBroker(
                    clock,
                    grants,
                    targets,
                    new RecordingFrameSourceFactory(),
                    new RecordingFlashFallback(),
                    content);
                ObservationCaptureOutcome captured =
                    await captures.CaptureAsync(
                        new ObservationCaptureRequest
                        {
                            ObservationGrantId =
                                grant.ObservationGrantId,
                            ClientInstanceId = ClientId,
                            SecurityPrincipalId =
                                principal.SecurityPrincipalId,
                            SessionId = SessionId,
                            TargetId = TargetId,
                            DataScope =
                                ObservationDataScopesV1.Pixels
                        });
                if (!captured.Success)
                {
                    throw new InvalidOperationException(
                        captured.ReasonCode);
                }
                var context =
                    new AgentRuntimeDispatchContext(
                        "connection_AAAAAAAAAAAAA",
                        principal);
                var observationStore =
                    new AgentObservationEnvelopeStore();
                observationStore.Store(
                    context,
                    ObservationDataScopesV1.Pixels,
                    captured.Envelope);
                var leases = new WriteLeaseBroker(
                    clock,
                    credentialAuthority,
                    targets);
                var revocations =
                    new AgentRuntimeRevocationCoordinator(
                        credentialAuthority,
                        grants,
                        leases);
                revocations.RegisterConnection(
                    context.ConnectionId,
                    principal);
                var guardWin32 =
                    new ActionGuardWin32Facade(clock);
                var nativeGuard = new NativeInputGuard(
                    new InputSafetyStateMachine(clock),
                    guardWin32,
                    revocations,
                    false);
                if (externalInputDeliveryEntered != null)
                {
                    if (releaseExternalInputDelivery == null)
                    {
                        throw new ArgumentNullException(
                            nameof(
                                releaseExternalInputDelivery));
                    }
                    nativeGuard.ExternalInputObserved +=
                        _ =>
                        {
                            externalInputDeliveryEntered.Set();
                            releaseExternalInputDelivery.Wait(
                                TimeSpan.FromSeconds(10));
                        };
                }
                revocations.BindNativeGuard(nativeGuard);
                clock.Advance(
                    TimeSpan.FromMilliseconds(
                        InputSafetyStateMachine
                            .QuiescenceMilliseconds));
                if (!revocations.TryCaptureSessionFence(
                        context.ConnectionId,
                        principal,
                        SessionId,
                        captured.Envelope
                            .LifecycleGeneration,
                        out AgentRuntimeRevocationCoordinator
                            .SessionFenceTicket fenceTicket,
                        out string fenceReason))
                {
                    throw new InvalidOperationException(
                        fenceReason);
                }
                WriteLease lease = leases.Acquire(
                    new WriteLeaseRequest
                    {
                        CredentialId = principal.CredentialId,
                        ClientInstanceId = ClientId,
                        SessionId = SessionId,
                        LifecycleGeneration =
                            captured.Envelope
                                .LifecycleGeneration,
                        Kind = shutdown
                            ? WriteLeaseKind.Shutdown
                            : structuredAction
                                ? WriteLeaseKind
                                    .StructuredAction
                                : WriteLeaseKind.GuiInput,
                        Capabilities =
                            new[] { actionCapability },
                        TargetScope = new[] { TargetId },
                        RequestedLifetime =
                            TimeSpan.FromMinutes(1),
                        RequestedActionLimit =
                            launcherAction
                                ? 1
                                : requestedActionLimit,
                        ConsentReceipt =
                            playerAssist
                                ? principal.IssuerReceipt
                                : null,
                        ArgumentBoundsHash =
                            playerAssist
                                ? CanonicalJsonV1
                                    .ComputeArgumentBoundsSha256(
                                        AgentCapabilitiesV1.Click,
                                        ClickArguments())
                                : null
                    });
                var ledger = new ActionIdempotencyLedger();
                var audit =
                    new ScopedAgentRuntimeAuditLedgerManager(
                        clock,
                        credentialAuthority,
                        new TestAuditScopeAuthority());
                if (!revocations.TryTrackLease(
                        fenceTicket,
                        lease,
                        out string trackReason))
                {
                    leases.Revoke(
                        lease.LeaseId,
                        trackReason);
                    throw new InvalidOperationException(
                        trackReason);
                }
                return new ActionFixture(
                    clock,
                    credentialAuthority,
                    targets,
                    principal,
                    grants,
                    content,
                    captures,
                    observationStore,
                    leases,
                    lease,
                    ledger,
                    revocations,
                    nativeGuard,
                    guardWin32,
                    audit,
                    context,
                    captured.Envelope);
            }

            public void SetPerformer(
                IAgentRuntimeActionPerformer performer)
            {
                Broker = new AgentRuntimeActionExecutionBroker(
                    _captures,
                    _observationStore,
                    Leases,
                    Ledger,
                    Revocations,
                    performer,
                    _auditSink);
            }

            public void SetAuditSink(
                IAgentRuntimeAuditSink auditSink)
            {
                _auditSink = auditSink
                    ?? throw new ArgumentNullException(
                        nameof(auditSink));
            }

            public IReadOnlyList<AuditEntry> AuditEntries()
            {
                return Audit.SnapshotExact(
                        new AgentAuditScopeKey(
                            Principal.SecurityPrincipalId,
                            SessionId,
                            Lease.Kind switch
                            {
                                WriteLeaseKind.Shutdown =>
                                    AgentCapabilitiesV1
                                        .SessionShutdown,
                                WriteLeaseKind
                                    .StructuredAction =>
                                        AgentCapabilitiesV1
                                            .PanelOpen,
                                _ => AgentCapabilitiesV1.Click
                            }))
                    .SelectMany(snapshot =>
                        snapshot.Segments)
                    .SelectMany(segment =>
                        segment.Entries)
                    .ToArray();
            }

            public ActionLookupResult Lookup(
                ActionEnvelope action)
            {
                return Ledger.Get(
                    Principal.SecurityPrincipalId,
                    SessionId,
                    action.ActionId);
            }

            public async Task<ActionReceipt> ExecuteAsync(
                ActionEnvelope action,
                CancellationToken cancellationToken = default)
            {
                if (Broker == null)
                SetPerformer(
                    new ImmediatePerformer(
                        AgentActionPerformance.Completed(
                            ActionOutcome.InputDispatched,
                            EvidenceKind.BrokerDispatch,
                            TargetId,
                            true)));
                AgentRuntimeActionExecutionResult result =
                    await ExecuteWithDeliveryAsync(
                        action,
                        cancellationToken);
                result.ResponseCompletion?.CommitAfterWrite();
                return result.Receipt;
            }

            public Task<AgentRuntimeActionExecutionResult>
                ExecuteWithDeliveryAsync(
                    ActionEnvelope action,
                    CancellationToken cancellationToken = default)
            {
                if (Broker == null)
                    SetPerformer(
                        new ImmediatePerformer(
                            AgentActionPerformance.Completed(
                                ActionOutcome.InputDispatched,
                                EvidenceKind.BrokerDispatch,
                                TargetId,
                                true)));
                return Broker.ExecuteAsync(
                    Context,
                    action,
                    Lease.Kind switch
                    {
                        WriteLeaseKind.Shutdown =>
                            AgentCapabilitiesV1
                                .SessionShutdown,
                        WriteLeaseKind.StructuredAction =>
                            AgentCapabilitiesV1.PanelOpen,
                        _ => AgentCapabilitiesV1.Click
                    },
                    cancellationToken);
            }

            public ActionEnvelope Action()
            {
                FrameEnvelope frame = Observation.Frames[0];
                return new ActionEnvelope
                {
                    ActionId =
                        "action_AAAAAAAAAAAAAAAAA",
                    IdempotencyKey =
                        "idempotency_AAAAAAAAAAAA",
                    DeadlineMs = 1_000,
                    SessionId = SessionId,
                    ObservationGrantId =
                        Observation.ObservationGrantId,
                    LeaseId = Lease.LeaseId,
                    ObservationId =
                        Observation.ObservationId,
                    ExpectedLifecycleGeneration =
                        Observation.LifecycleGeneration,
                    TargetId = TargetId,
                    ExpectedSurfaceEpoch =
                        Observation.SurfaceEpoch,
                    ExpectedAttemptId =
                        Observation.AttemptId,
                    ExpectedAttemptGeneration =
                        Observation.AttemptGeneration,
                    ExpectedPanelInstanceId =
                        Observation.PanelInstanceId,
                    ExpectedSemanticGeneration =
                        Observation.SemanticGeneration,
                    ExpectedDocumentGeneration =
                        Observation.DocumentGeneration,
                    ExpectedCoordinateSpaceVersion =
                        Observation
                            .CoordinateSpaceVersion,
                    ExpectedFocusEpoch =
                        Observation.FocusEpoch,
                    ExpectedModalEpoch =
                        Observation.ModalEpoch,
                    FrameId = frame.FrameId,
                    SemanticSnapshotId =
                        Observation.SemanticSnapshotId,
                    Operation = Lease.Kind switch
                    {
                        WriteLeaseKind.Shutdown =>
                            AgentCapabilitiesV1
                                .SessionShutdown,
                        WriteLeaseKind.StructuredAction =>
                            AgentCapabilitiesV1.PanelOpen,
                        _ => AgentCapabilitiesV1.Click
                    },
                    Arguments =
                        Lease.Kind == WriteLeaseKind.GuiInput
                            ? ClickArguments()
                            : EmptyArguments(),
                    Reason = "focused test"
                };
            }

            public void FailHookAfterNextHealthyCheck()
            {
                _guardWin32.HookSession
                    .FailAfterHealthyChecks(1);
            }

            public void ObserveExternalInput(
                ManualResetEventSlim delivered = null)
            {
                if (delivered != null)
                {
                    _nativeGuard.ExternalInputObserved +=
                        _ => delivered.Set();
                }
                _nativeGuard.ObserveExternallyHeldControls(
                    new[] { "key:A" });
            }

            public void ObserveInjectedExternalInput()
            {
                _guardWin32.EmitInjectedExternalInput();
            }

            public WriteLease AcquireReplacementShutdownLease()
            {
                return AcquireReplacementLease();
            }

            public WriteLease AcquireReplacementLease()
            {
                return Leases.Acquire(
                    new WriteLeaseRequest
                    {
                        CredentialId =
                            Principal.CredentialId,
                        ClientInstanceId =
                            Principal.ClientInstanceId,
                        SessionId = SessionId,
                        LifecycleGeneration =
                            Observation
                                .LifecycleGeneration,
                        Kind = Lease.Kind,
                        Capabilities =
                            Lease.Capabilities,
                        TargetScope =
                            Lease.TargetScope,
                        RequestedLifetime =
                            TimeSpan.FromSeconds(30),
                        RequestedActionLimit = 1,
                        ConsentReceipt =
                            Lease.ConsentReceipt,
                        ArgumentBoundsHash =
                            Lease.ArgumentBoundsHash,
                        PreviewHash =
                            Lease.PreviewHash,
                        ExpectedRevision =
                            Lease.ExpectedRevision,
                        Operation = Lease.Operation
                    });
            }

            public void Dispose()
            {
                Revocations.Dispose();
                _nativeGuard.Dispose();
                _captures.Dispose();
                _content.Dispose();
                Audit.Dispose();
            }

            private sealed class ActionGuardWin32Facade
                : INativeInputWin32Facade
            {
                private readonly ManualObservationClock _clock;
                private Func<NativeLowLevelHookEvent, bool>
                    _hookCallback;
                private ulong _runtimeInjectionTag;

                public ActionGuardWin32Facade(
                    ManualObservationClock clock)
                {
                    _clock = clock;
                }

                public int CurrentProcessId => 111;
                public long MonotonicMilliseconds =>
                    _clock.MonotonicMilliseconds;
                public ActionHookSession HookSession { get; } =
                    new ActionHookSession();

                public INativeLowLevelHookSession
                    InstallLowLevelHooks(
                        ulong runtimeInjectionTag,
                        Func<NativeLowLevelHookEvent, bool>
                            callback)
                {
                    _runtimeInjectionTag =
                        runtimeInjectionTag;
                    _hookCallback = callback;
                    return HookSession;
                }

                public void EmitInjectedExternalInput()
                {
                    Func<NativeLowLevelHookEvent, bool> callback =
                        _hookCallback
                        ?? throw new InvalidOperationException(
                            "hook_not_installed");
                    callback(
                        new NativeLowLevelHookEvent(
                            NativeHookDevice.Keyboard,
                            "Key:17",
                            NativeControlTransition.Down,
                            isInjected: true,
                            extraInfo:
                                _runtimeInjectionTag ^ 1UL,
                            screenPoint: null,
                            nativeMessage: 0x0100));
                }

                public bool IsInteractiveDesktopAvailable()
                {
                    return true;
                }

                public IntPtr GetForegroundWindow()
                {
                    return new IntPtr(9001);
                }

                public bool TryGetFocusedWindow(
                    IntPtr foregroundTopLevelHwnd,
                    out IntPtr focusedHwnd)
                {
                    focusedHwnd = foregroundTopLevelHwnd;
                    return true;
                }

                public IntPtr WindowFromPoint(
                    NativeScreenPoint point)
                {
                    return new IntPtr(9001);
                }

                public bool IsSameChildOrOwnedWindow(
                    IntPtr targetTopLevelHwnd,
                    IntPtr candidateHwnd)
                {
                    return targetTopLevelHwnd
                        == candidateHwnd;
                }

                public IReadOnlyCollection<string>
                    GetAsyncHeldModifiersAndButtons()
                {
                    return Array.Empty<string>();
                }

                public bool TryGetProcessIntegrityLevel(
                    int processId,
                    out int integrityRid)
                {
                    integrityRid = 0x2000;
                    return true;
                }

                public int SendInput(
                    IReadOnlyList<NativeInputPacket> packets,
                    ulong runtimeInjectionTag)
                {
                    return packets?.Count ?? 0;
                }
            }

            private sealed class ActionHookSession
                : INativeLowLevelHookSession
            {
                private readonly object _sync = new object();
                private bool _healthy = true;
                private int _healthyChecksBeforeFailure = -1;

                public void FailAfterHealthyChecks(int count)
                {
                    if (count < 0)
                    {
                        throw new ArgumentOutOfRangeException(
                            nameof(count));
                    }
                    lock (_sync)
                    {
                        _healthy = true;
                        _healthyChecksBeforeFailure = count;
                    }
                }

                public bool IsHealthy(
                    TimeSpan maximumHeartbeatAge)
                {
                    lock (_sync)
                    {
                        if (!_healthy)
                            return false;
                        if (_healthyChecksBeforeFailure < 0)
                            return true;
                        if (_healthyChecksBeforeFailure == 0)
                        {
                            _healthy = false;
                            _healthyChecksBeforeFailure = -1;
                            return false;
                        }
                        _healthyChecksBeforeFailure--;
                        return true;
                    }
                }

                public bool TryRefresh(TimeSpan timeout)
                {
                    return true;
                }

                public void Dispose()
                {
                }
            }

            private static ObservationCapturePlan CapturePlan(
                bool launcherAction = false)
            {
                var surface = new ObservationSurfacePlan(
                    TargetId,
                    launcherAction
                        ? SurfaceKind.Launcher
                        : SurfaceKind.Flash,
                    101,
                    202,
                    new DateTimeOffset(
                        2026,
                        7,
                        30,
                        8,
                        0,
                        0,
                        TimeSpan.Zero),
                    Path.GetFullPath(
                        Path.Combine(
                            Path.GetTempPath(),
                            "cf7-agent-action-tests",
                            "owner.exe")),
                    0,
                    3,
                    5,
                    7,
                    11,
                    13,
                    17,
                    Rect(0, 0, 400, 300),
                    Rect(0, 0, 400, 300),
                    Rect(0, 0, 400, 300),
                    96,
                    1,
                    visible: true,
                    minimized: false,
                    active: true,
                    observationModes: new[]
                    {
                        ObservationMode
                            .WindowGraphicsCapture
                    });
                return new ObservationCapturePlan(
                    SessionId,
                    2,
                    AttemptId,
                    3,
                    PanelId,
                    7,
                    11,
                    BlockingModalKind.None,
                    surface,
                    new[] { surface });
            }

            private static JsonElement ClickArguments()
            {
                return JsonSerializer.SerializeToElement(
                    new
                    {
                        x = 12,
                        y = 18,
                        button = "left"
                    });
            }

            private static JsonElement EmptyArguments()
            {
                return JsonSerializer.SerializeToElement(
                    new { });
            }

            private static PhysicalRect Rect(
                int x,
                int y,
                int width,
                int height)
            {
                return new PhysicalRect
                {
                    X = x,
                    Y = y,
                    Width = width,
                    Height = height
                };
            }
        }

        private sealed class TestAuditScopeAuthority
            : IAgentAuditScopeAuthority
        {
            public bool TryAuthorize(
                PrincipalCredential principal,
                string sessionId,
                ulong lifecycleGeneration,
                string consentPurpose,
                out string reasonCode)
            {
                if (principal == null
                    || !string.Equals(
                        sessionId,
                        SessionId,
                        StringComparison.Ordinal)
                    || lifecycleGeneration != 2
                        && lifecycleGeneration != 3
                    || !principal.AllowsCapability(
                        consentPurpose))
                {
                    reasonCode = "audit_scope_denied";
                    return false;
                }
                reasonCode = null;
                return true;
            }
        }

        private sealed class UnavailableAuditSink
            : IAgentRuntimeAuditSink
        {
            public bool TryAppend(
                AgentRuntimeAuditEventEnvelope auditEvent,
                out AgentRuntimeAuditCommit commit,
                out string reasonCode)
            {
                commit = null;
                reasonCode = "audit_unavailable";
                return false;
            }
        }

        private sealed class CallbackAuditSink
            : IAgentRuntimeAuditSink
        {
            private readonly object _sync = new object();
            private readonly string _triggerEventType;
            private readonly HashSet<string> _eventTypes =
                new HashSet<string>(StringComparer.Ordinal);
            private Action _callback;
            private long _sequence;

            public CallbackAuditSink(
                string triggerEventType,
                Action callback)
            {
                _triggerEventType = triggerEventType;
                _callback = callback
                    ?? throw new ArgumentNullException(
                        nameof(callback));
            }

            public bool TryAppend(
                AgentRuntimeAuditEventEnvelope auditEvent,
                out AgentRuntimeAuditCommit commit,
                out string reasonCode)
            {
                long sequence =
                    Interlocked.Increment(ref _sequence);
                commit = new AgentRuntimeAuditCommit(
                    "audit_scope_test",
                    sequence,
                    "audit_segment_test",
                    sequence,
                    auditEvent.EventType,
                    new string('A', 64),
                    new string('B', 64));
                reasonCode = null;
                Action callback = null;
                lock (_sync)
                {
                    _eventTypes.Add(
                        auditEvent.EventType);
                    if (string.Equals(
                            auditEvent.EventType,
                            _triggerEventType,
                            StringComparison.Ordinal))
                    {
                        callback =
                            Interlocked.Exchange(
                                ref _callback,
                                null);
                    }
                }
                callback?.Invoke();
                return true;
            }

            public bool Contains(string eventType)
            {
                lock (_sync)
                    return _eventTypes.Contains(eventType);
            }
        }

        private sealed class FailFirstTerminalAuditSink
            : IAgentRuntimeAuditSink
        {
            private readonly IAgentRuntimeAuditSink _inner;
            private int _failed;

            public FailFirstTerminalAuditSink(
                IAgentRuntimeAuditSink inner)
            {
                _inner = inner;
            }

            public bool TryAppend(
                AgentRuntimeAuditEventEnvelope auditEvent,
                out AgentRuntimeAuditCommit commit,
                out string reasonCode)
            {
                if (auditEvent.EventType
                        == AgentRuntimeAuditEventTypes
                            .ActionTerminal
                    && Interlocked.CompareExchange(
                        ref _failed,
                        1,
                        0) == 0)
                {
                    commit = null;
                    reasonCode = "audit_unavailable";
                    return false;
                }
                return _inner.TryAppend(
                    auditEvent,
                    out commit,
                    out reasonCode);
            }
        }

        private sealed class ImmediatePerformer
            : IAgentRuntimeActionPerformer
        {
            private readonly AgentActionPerformance _performance;

            public ImmediatePerformer(
                AgentActionPerformance performance)
            {
                _performance = performance;
            }

            public int CallCount { get; private set; }

            public Task<AgentActionPerformance> PerformAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
            {
                CallCount++;
                return Task.FromResult(_performance);
            }
        }

        private sealed class CallbackPerformer
            : IAgentRuntimeActionPerformer
        {
            private readonly Action _callback;
            private readonly AgentActionPerformance _performance;

            public CallbackPerformer(
                Action callback,
                AgentActionPerformance performance)
            {
                _callback = callback;
                _performance = performance;
            }

            public int CallCount { get; private set; }
            public bool CancellationRequestedAfterCallback
            {
                get;
                private set;
            }

            public Task<AgentActionPerformance> PerformAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
            {
                CallCount++;
                _callback();
                CancellationRequestedAfterCallback =
                    cancellationToken.IsCancellationRequested;
                return Task.FromResult(_performance);
            }
        }

        private sealed class BlockingPerformer
            : IAgentRuntimeActionPerformer
        {
            private readonly
                TaskCompletionSource<AgentActionPerformance>
                _completion = new(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);

            public int CallCount { get; private set; }
            public TaskCompletionSource<bool> Entered { get; } =
                new(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);

            public Task<AgentActionPerformance> PerformAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
            {
                CallCount++;
                Entered.TrySetResult(true);
                return _completion.Task;
            }

            public void Complete(
                AgentActionPerformance performance)
            {
                _completion.TrySetResult(performance);
            }
        }

        private sealed class
            CancellationObservingBlockingPerformer
            : IAgentRuntimeActionPerformer
        {
            private readonly
                TaskCompletionSource<AgentActionPerformance>
                _completion = new(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            private CancellationToken _cancellationToken;

            public int CallCount { get; private set; }
            public bool CancellationRequested =>
                _cancellationToken.IsCancellationRequested;
            public TaskCompletionSource<bool> Entered { get; } =
                new(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);

            public Task<AgentActionPerformance> PerformAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
            {
                CallCount++;
                _cancellationToken = cancellationToken;
                Entered.TrySetResult(true);
                return _completion.Task;
            }

            public void Complete(
                AgentActionPerformance performance)
            {
                _completion.TrySetResult(performance);
            }
        }

        private sealed class CancellationPerformer
            : IAgentRuntimeActionPerformer
        {
            public TaskCompletionSource<bool> Entered { get; } =
                new(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);
            public TaskCompletionSource<bool> Cancelled { get; } =
                new(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);

            public async Task<AgentActionPerformance> PerformAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
            {
                var cancellationObserved =
                    new TaskCompletionSource<bool>(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
                // Keep exactly one callback on this token. Awaiting
                // Task.Delay(token) would install a second callback; its
                // LIFO completion can resume this method and dispose
                // registration before the callback below has run, losing
                // the test's cancellation signal.
                using CancellationTokenRegistration registration =
                    cancellationToken.Register(
                        delegate
                        {
                            Cancelled.TrySetResult(true);
                            cancellationObserved
                                .TrySetResult(true);
                        });
                // Signal only after the cancellation observer is installed.
                // Otherwise a full-suite continuation may revoke between
                // Entered and Register, making this synchronization point
                // report readiness before the performer is actually ready.
                Entered.TrySetResult(true);
                await cancellationObserved.Task
                    .ConfigureAwait(false);
                cancellationToken
                    .ThrowIfCancellationRequested();
                throw new InvalidOperationException(
                    "unreachable");
            }
        }
    }
}
