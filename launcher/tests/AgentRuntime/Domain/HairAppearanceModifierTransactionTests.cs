using System;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Domain
{
    public sealed class HairAppearanceModifierTransactionTests
    {
        private const string BeforeHair = "光头";
        private const string AfterHair = "发型-男式-平头";
        private const string ThirdHair = "发型-女式-短发";

        [Fact]
        public async Task InspectAndPreview_BindExactSaveRevisionGenerationAndHashes()
        {
            Fixture fixture = new Fixture();

            HairInspectResult first =
                await fixture.Service.InspectAsync(fixture.Binding);
            HairInspectResult second =
                await fixture.Service.InspectAsync(fixture.Binding);

            Assert.True(first.Success);
            Assert.Equal(BeforeHair, first.Snapshot.CurrentHair);
            Assert.Equal(7, first.Snapshot.Revision);
            Assert.Equal(3, first.Snapshot.Generation);
            Assert.Equal("save-001", first.Snapshot.Binding.SaveSignature);
            Assert.Equal(first.SnapshotHash, second.SnapshotHash);
            Assert.Matches("^[0-9a-f]{64}$", first.SnapshotHash);

            HairPreviewResult preview = await fixture.PreviewAsync(first);

            Assert.Equal(
                HairTransactionOutcome.PreviewReady,
                preview.Outcome);
            Assert.Equal(
                HairAppearanceOperation.Name,
                preview.Preview.Operation);
            Assert.Equal(fixture.Binding, preview.Preview.Binding);
            Assert.Equal(BeforeHair, preview.Preview.BeforeHair);
            Assert.Equal(AfterHair, preview.Preview.AfterHair);
            Assert.Equal(first.SnapshotHash, preview.Preview.ExpectedSnapshotHash);
            Assert.Matches(
                "^[0-9a-f]{64}$",
                preview.Preview.PreviewHash);
        }

        [Theory]
        [InlineData("revision")]
        [InlineData("generation")]
        [InlineData("current")]
        [InlineData("hash")]
        [InlineData("catalog")]
        public async Task Preview_RejectsStaleOrOutOfCatalogProposal(
            string mutation)
        {
            Fixture fixture = new Fixture();
            HairInspectResult inspect =
                await fixture.Service.InspectAsync(fixture.Binding);
            var request = new HairPreviewRequest(
                fixture.Binding,
                mutation == "catalog" ? "目录外发型" : AfterHair,
                mutation == "current" ? ThirdHair : BeforeHair,
                mutation == "revision"
                    ? inspect.Snapshot.Revision + 1
                    : inspect.Snapshot.Revision,
                mutation == "generation"
                    ? inspect.Snapshot.Generation + 1
                    : inspect.Snapshot.Generation,
                mutation == "hash"
                    ? new string('a', 64)
                    : inspect.SnapshotHash);

            HairPreviewResult result =
                await fixture.Service.PreviewAsync(request);

            Assert.Equal(HairTransactionOutcome.Rejected, result.Outcome);
            if (mutation == "revision" || mutation == "generation")
            {
                Assert.Equal(
                    HairAppearanceReasonCodes.StaleRevision,
                    result.ReasonCode);
            }
            else if (mutation == "catalog")
            {
                Assert.Equal(
                    HairAppearanceReasonCodes.HairNotFound,
                    result.ReasonCode);
            }
            else
            {
                Assert.Equal(
                    HairAppearanceReasonCodes.StaleState,
                    result.ReasonCode);
            }
            Assert.Empty(fixture.Adapter.CommitCommands);
        }

        [Fact]
        public async Task Inspect_RejectsCrossSaveAuthority()
        {
            Fixture fixture = new Fixture();
            fixture.Adapter.ReplaceBinding(
                new HairSaveBinding(
                    fixture.Binding.SessionId,
                    fixture.Binding.LifecycleGeneration,
                    fixture.Binding.AttemptId,
                    fixture.Binding.AttemptGeneration,
                    "other-slot",
                    "save-999"));

            HairInspectResult result =
                await fixture.Service.InspectAsync(fixture.Binding);

            Assert.False(result.Success);
            Assert.Equal(
                HairAppearanceReasonCodes.CrossSave,
                result.ReasonCode);
        }

        [Fact]
        public async Task Commit_PersistsPreparedPointBeforeCallingCasAdapter()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Adapter.BeforeCommit = command =>
            {
                HairRestorePointRecord prepared =
                    fixture.Store.ReadDirect(preview.TransactionId);
                Assert.NotNull(prepared);
                Assert.Equal(
                    HairRestorePointState.Prepared,
                    prepared.State);
                Assert.Equal(preview.ExpectedRevision, command.ExpectedRevision);
                Assert.Equal(
                    preview.ExpectedGeneration,
                    command.ExpectedGeneration);
                Assert.Equal(
                    preview.ExpectedSnapshotHash,
                    command.ExpectedSnapshotHash);
                Assert.Equal(preview.BeforeHair, command.ExpectedCurrentHair);
                Assert.Equal(preview.AfterHair, command.HairIdentifier);
                Assert.False(command.IsRestore);
            };

            HairTransactionResult result = await fixture.Service.CommitAsync(
                preview,
                consent.Token);

            Assert.Equal(
                HairTransactionOutcome.DomainCommitted,
                result.Outcome);
            Assert.Equal(AfterHair, result.AuthoritativeInspect.Snapshot.CurrentHair);
            Assert.NotNull(result.RestoreToken);
            Assert.True(result.RestoreExpiresAtUtc > fixture.Clock.UtcNow);
            Assert.Single(fixture.Adapter.CommitCommands);

            HairRestorePointRecord stored =
                fixture.Store.ReadDirect(preview.TransactionId);
            Assert.Equal(HairRestorePointState.Committed, stored.State);
            Assert.NotEqual(result.RestoreToken, stored.RestoreTokenHash);
            Assert.Matches("^[0-9a-f]{64}$", stored.RestoreTokenHash);
            Assert.Equal(preview.PreviewHash, stored.PreviewHash);
            Assert.Equal("save-001", stored.Binding.SaveSignature);
        }

        [Fact]
        public async Task AdapterCas_RejectsHumanChangeBetweenValidationAndDispatch()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Adapter.BeforeCommit = _ =>
            {
                fixture.Adapter.BeforeCommit = null;
                fixture.Adapter.HumanChange(ThirdHair);
            };

            HairTransactionResult result = await fixture.Service.CommitAsync(
                preview,
                consent.Token);

            Assert.Equal(HairTransactionOutcome.Rejected, result.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.StaleRevision,
                result.ReasonCode);
            Assert.Equal(ThirdHair, fixture.Adapter.CurrentSnapshot.CurrentHair);
            Assert.Single(fixture.Adapter.CommitCommands);
            Assert.Equal(
                HairRestorePointState.CommitRejected,
                fixture.Store.ReadDirect(preview.TransactionId).State);
        }

        [Fact]
        public async Task MissingDurableRestoreStore_FailsClosedBeforeAdapterWrite()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Store.FailCreate = true;

            HairTransactionResult result = await fixture.Service.CommitAsync(
                preview,
                consent.Token);

            Assert.Equal(HairTransactionOutcome.Rejected, result.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.RestoreStoreUnavailable,
                result.ReasonCode);
            Assert.Empty(fixture.Adapter.CommitCommands);
            Assert.Equal(BeforeHair, fixture.Adapter.CurrentSnapshot.CurrentHair);
        }

        [Fact]
        public async Task ExpiredConsent_FailsBeforeRestoreRecordOrAdapterWrite()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview, TimeSpan.FromSeconds(2));
            fixture.Clock.Advance(TimeSpan.FromSeconds(2));

            HairTransactionResult result = await fixture.Service.CommitAsync(
                preview,
                consent.Token);

            Assert.Equal(HairTransactionOutcome.Rejected, result.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.ConsentExpired,
                result.ReasonCode);
            Assert.Null(fixture.Store.ReadDirect(preview.TransactionId));
            Assert.Empty(fixture.Adapter.CommitCommands);
        }

        [Theory]
        [InlineData(FakeHairCommitBehavior.AppliedThenUnknown)]
        [InlineData(FakeHairCommitBehavior.AppliedThenThrow)]
        [InlineData(FakeHairCommitBehavior.MalformedAppliedAck)]
        public async Task LostOrMalformedAck_IsUnknownAndReconcilesAppliedWithoutReplay(
            FakeHairCommitBehavior behavior)
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Adapter.NextCommitBehavior = behavior;

            HairTransactionResult commit = await fixture.Service.CommitAsync(
                preview,
                consent.Token);
            HairTransactionResult reconciled =
                await fixture.Service.ReconcileAsync(preview.TransactionId);

            Assert.Equal(HairTransactionOutcome.Unknown, commit.Outcome);
            Assert.Equal("domain_authoritative", commit.ReconcileKind);
            Assert.Equal(
                HairTransactionOutcome.DomainCommitted,
                reconciled.Outcome);
            Assert.Equal(AfterHair, reconciled.AuthoritativeInspect.Snapshot.CurrentHair);
            Assert.Single(fixture.Adapter.CommitCommands);
            Assert.Equal(
                HairRestorePointState.Committed,
                fixture.Store.ReadDirect(preview.TransactionId).State);
        }

        [Fact]
        public async Task UnknownCommit_ReleasesEscrowOnlyOnceAfterDurableReconcileForExactPreview()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview =
                await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Adapter.NextCommitBehavior =
                FakeHairCommitBehavior.AppliedThenUnknown;

            HairTransactionResult commit =
                await fixture.Service.CommitAsync(
                    preview,
                    consent.Token);
            HairReconciledRestoreCapability beforeReconcile =
                await fixture.Service
                    .TryConsumeReconciledRestoreCapabilityAsync(
                        preview);
            HairTransactionResult reconciled =
                await fixture.Service.ReconcileAsync(
                    preview.TransactionId);
            HairAppearancePreview clone =
                ClonePreview(preview);
            HairReconciledRestoreCapability cloned =
                await fixture.Service
                    .TryConsumeReconciledRestoreCapabilityAsync(
                        clone);
            HairReconciledRestoreCapability capability =
                await fixture.Service
                    .TryConsumeReconciledRestoreCapabilityAsync(
                        preview);
            HairReconciledRestoreCapability replay =
                await fixture.Service
                    .TryConsumeReconciledRestoreCapabilityAsync(
                        preview);

            Assert.Equal(
                HairTransactionOutcome.Unknown,
                commit.Outcome);
            Assert.Null(commit.RestoreToken);
            Assert.Null(beforeReconcile);
            Assert.Equal(
                HairTransactionOutcome.DomainCommitted,
                reconciled.Outcome);
            Assert.Null(cloned);
            Assert.NotNull(capability);
            Assert.False(
                string.IsNullOrWhiteSpace(
                    capability.RestoreToken));
            Assert.True(
                capability.ExpiresAtUtc
                    > fixture.Clock.UtcNow);
            Assert.Null(replay);
        }

        [Fact]
        public async Task UnknownCommit_EscrowDoesNotSurviveTransactionServiceRestart()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview =
                await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Adapter.NextCommitBehavior =
                FakeHairCommitBehavior.AppliedThenUnknown;

            HairTransactionResult commit =
                await fixture.Service.CommitAsync(
                    preview,
                    consent.Token);
            var restarted =
                new HairAppearanceModifierTransaction(
                    fixture.Adapter,
                    fixture.Store,
                    new HairAppearanceConsentBroker(
                        fixture.Clock),
                    fixture.Clock);
            HairTransactionResult reconciled =
                await restarted.ReconcileAsync(
                    preview.TransactionId);
            HairReconciledRestoreCapability capability =
                await restarted
                    .TryConsumeReconciledRestoreCapabilityAsync(
                        preview);

            Assert.Equal(
                HairTransactionOutcome.Unknown,
                commit.Outcome);
            Assert.Null(commit.RestoreToken);
            Assert.Equal(
                HairTransactionOutcome.DomainCommitted,
                reconciled.Outcome);
            Assert.Null(capability);
        }

        [Fact]
        public async Task Reconcile_ReturnsUnknownUntilCommittedStatePersists()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview =
                await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Adapter.NextCommitBehavior =
                FakeHairCommitBehavior.AppliedThenUnknown;
            HairTransactionResult commit =
                await fixture.Service.CommitAsync(
                    preview,
                    consent.Token);
            fixture.Store.FailUpdateOnCall =
                fixture.Store.UpdateCalls + 1;

            HairTransactionResult first =
                await fixture.Service.ReconcileAsync(
                    preview.TransactionId);

            Assert.Equal(
                HairTransactionOutcome.Unknown,
                commit.Outcome);
            Assert.Equal(
                HairTransactionOutcome.Unknown,
                first.Outcome);
            Assert.Equal(
                "domain_authoritative",
                first.ReconcileKind);
            Assert.Equal(
                HairRestorePointState.CommitUnknown,
                fixture.Store.ReadDirect(
                    preview.TransactionId).State);

            HairTransactionResult second =
                await fixture.Service.ReconcileAsync(
                    preview.TransactionId);

            Assert.Equal(
                HairTransactionOutcome.DomainCommitted,
                second.Outcome);
        }

        [Fact]
        public async Task UnknownWithoutApply_ReconcilesNotAppliedWithoutReplay()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Adapter.NextCommitBehavior =
                FakeHairCommitBehavior.UnknownWithoutApply;

            HairTransactionResult commit = await fixture.Service.CommitAsync(
                preview,
                consent.Token);
            HairTransactionResult reconciled =
                await fixture.Service.ReconcileAsync(preview.TransactionId);

            Assert.Equal(HairTransactionOutcome.Unknown, commit.Outcome);
            Assert.Equal(
                HairTransactionOutcome.NotApplied,
                reconciled.Outcome);
            Assert.Single(fixture.Adapter.CommitCommands);
            Assert.Equal(BeforeHair, fixture.Adapter.CurrentSnapshot.CurrentHair);
            Assert.Equal(
                HairRestorePointState.CommitRejected,
                fixture.Store.ReadDirect(preview.TransactionId).State);
        }

        [Fact]
        public async Task UnknownWithoutApply_CannotReplayConsumedConsent()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Adapter.NextCommitBehavior =
                FakeHairCommitBehavior.UnknownWithoutApply;

            HairTransactionResult first = await fixture.Service.CommitAsync(
                preview,
                consent.Token);
            HairTransactionResult replay = await fixture.Service.CommitAsync(
                preview,
                consent.Token);

            Assert.Equal(HairTransactionOutcome.Unknown, first.Outcome);
            Assert.Equal(HairTransactionOutcome.Rejected, replay.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.ConsentReplayed,
                replay.ReasonCode);
            Assert.Single(fixture.Adapter.CommitCommands);
        }

        [Fact]
        public async Task AckedCommit_WithStoreStateUpdateLoss_ReconcilesAfterRestart()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.IssueConsent(preview);
            fixture.Store.FailUpdate = true;

            HairTransactionResult commit = await fixture.Service.CommitAsync(
                preview,
                consent.Token);

            Assert.Equal(
                HairTransactionOutcome.DomainCommitted,
                commit.Outcome);
            Assert.Equal(
                HairRestorePointState.Prepared,
                fixture.Store.ReadDirect(preview.TransactionId).State);
            fixture.Store.FailUpdate = false;

            var restarted = new HairAppearanceModifierTransaction(
                fixture.Adapter,
                fixture.Store,
                new HairAppearanceConsentBroker(fixture.Clock),
                fixture.Clock);
            HairTransactionResult reconciled =
                await restarted.ReconcileAsync(preview.TransactionId);

            Assert.Equal(
                HairTransactionOutcome.DomainCommitted,
                reconciled.Outcome);
            Assert.Single(fixture.Adapter.CommitCommands);
            Assert.Equal(
                HairRestorePointState.Committed,
                fixture.Store.ReadDirect(preview.TransactionId).State);
        }

        [Fact]
        public async Task Restore_SurvivesServiceRestartAndUsesSameCasAdapterPort()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);

            var restartedConsent =
                new HairAppearanceConsentBroker(fixture.Clock);
            var restarted = new HairAppearanceModifierTransaction(
                fixture.Adapter,
                fixture.Store,
                restartedConsent,
                fixture.Clock);
            HairTransactionResult restored = await restarted.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);

            Assert.Equal(HairTransactionOutcome.Restored, restored.Outcome);
            Assert.Equal(BeforeHair, fixture.Adapter.CurrentSnapshot.CurrentHair);
            Assert.Equal(2, fixture.Adapter.CommitCommands.Count);
            HairDomainCommitCommand restoreCommand =
                fixture.Adapter.CommitCommands[1];
            Assert.True(restoreCommand.IsRestore);
            Assert.Equal(BeforeHair, restoreCommand.HairIdentifier);
            Assert.Equal(AfterHair, restoreCommand.ExpectedCurrentHair);
            Assert.Equal(
                HairRestorePointState.Restored,
                fixture.Store.ReadDirect(preview.TransactionId).State);
        }

        [Fact]
        public async Task Restore_RejectsHumanConcurrentChange()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);
            fixture.Adapter.HumanChange(ThirdHair);

            HairTransactionResult restored = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);

            Assert.Equal(HairTransactionOutcome.Rejected, restored.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.StaleState,
                restored.ReasonCode);
            Assert.Equal(ThirdHair, fixture.Adapter.CurrentSnapshot.CurrentHair);
            Assert.Single(fixture.Adapter.CommitCommands);
        }

        [Fact]
        public async Task Restore_RejectsAwayAndBackHumanChangeByRevision()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);
            fixture.Adapter.HumanChange(ThirdHair);
            fixture.Adapter.HumanChange(AfterHair);

            HairTransactionResult restored = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);

            Assert.Equal(HairTransactionOutcome.Rejected, restored.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.StaleState,
                restored.ReasonCode);
            Assert.Single(fixture.Adapter.CommitCommands);
        }

        [Fact]
        public async Task RestoreStoreTransitionFailure_FailsBeforeRestoreDispatch()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);
            fixture.Store.FailUpdate = true;

            HairTransactionResult restored = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);

            Assert.Equal(HairTransactionOutcome.Rejected, restored.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.RestoreStoreUnavailable,
                restored.ReasonCode);
            Assert.Equal(AfterHair, fixture.Adapter.CurrentSnapshot.CurrentHair);
            Assert.Single(fixture.Adapter.CommitCommands);
        }

        [Fact]
        public async Task RestoreAppliedButTerminalStoreTransitionFails_ReturnsUnknownUntilReconciled()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview =
                await fixture.ReadyPreviewAsync();
            HairTransactionResult committed =
                await fixture.CommitAsync(preview);
            fixture.Store.FailUpdateOnCall =
                fixture.Store.UpdateCalls + 2;

            HairTransactionResult restore =
                await fixture.Service.RestoreAsync(
                    preview.TransactionId,
                    committed.RestoreToken);
            HairTransactionResult reconciled =
                await fixture.Service.ReconcileAsync(
                    preview.TransactionId);

            Assert.Equal(
                HairTransactionOutcome.Unknown,
                restore.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes
                    .RestoreStoreUnavailable,
                restore.ReasonCode);
            Assert.Equal(
                "domain_authoritative",
                restore.ReconcileKind);
            Assert.Equal(
                BeforeHair,
                fixture.Adapter.CurrentSnapshot.CurrentHair);
            Assert.Equal(
                HairTransactionOutcome.Restored,
                reconciled.Outcome);
            Assert.Equal(
                HairRestorePointState.Restored,
                fixture.Store.ReadDirect(
                    preview.TransactionId).State);
            Assert.Equal(
                2,
                fixture.Adapter.CommitCommands.Count);
        }

        [Fact]
        public async Task RestoreUnknownAfterApply_ReconcilesRestoredWithoutReplay()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);
            fixture.Adapter.NextCommitBehavior =
                FakeHairCommitBehavior.AppliedThenUnknown;

            HairTransactionResult restore = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);
            HairTransactionResult reconciled =
                await fixture.Service.ReconcileAsync(preview.TransactionId);

            Assert.Equal(HairTransactionOutcome.Unknown, restore.Outcome);
            Assert.Equal("domain_authoritative", restore.ReconcileKind);
            Assert.Equal(HairTransactionOutcome.Restored, reconciled.Outcome);
            Assert.Equal(BeforeHair, fixture.Adapter.CurrentSnapshot.CurrentHair);
            Assert.Equal(2, fixture.Adapter.CommitCommands.Count);
        }

        [Fact]
        public async Task RestoreUnknownWithoutApply_ReconcilesNotApplied()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);
            fixture.Adapter.NextCommitBehavior =
                FakeHairCommitBehavior.UnknownWithoutApply;

            HairTransactionResult restore = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);
            HairTransactionResult reconciled =
                await fixture.Service.ReconcileAsync(preview.TransactionId);

            Assert.Equal(HairTransactionOutcome.Unknown, restore.Outcome);
            Assert.Equal(
                HairTransactionOutcome.NotApplied,
                reconciled.Outcome);
            Assert.Equal(AfterHair, fixture.Adapter.CurrentSnapshot.CurrentHair);
            Assert.Equal(2, fixture.Adapter.CommitCommands.Count);
            Assert.Equal(
                HairRestorePointState.RestoreRejected,
                fixture.Store.ReadDirect(preview.TransactionId).State);
        }

        [Fact]
        public async Task RestoreToken_IsOneShot()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);

            HairTransactionResult first = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);
            HairTransactionResult replay = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);

            Assert.Equal(HairTransactionOutcome.Restored, first.Outcome);
            Assert.Equal(HairTransactionOutcome.Rejected, replay.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.RestoreTokenReplayed,
                replay.ReasonCode);
            Assert.Equal(2, fixture.Adapter.CommitCommands.Count);
        }

        [Fact]
        public async Task InvalidRestoreToken_DoesNotConsumeValidToken()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);

            HairTransactionResult invalid = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                "not-the-token");
            HairTransactionResult valid = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);

            Assert.Equal(HairTransactionOutcome.Rejected, invalid.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.RestoreTokenInvalid,
                invalid.ReasonCode);
            Assert.Equal(HairTransactionOutcome.Restored, valid.Outcome);
            Assert.Equal(2, fixture.Adapter.CommitCommands.Count);
        }

        [Fact]
        public async Task RestoreToken_ExpiresAtBoundedPersistedTtl()
        {
            Fixture fixture = new Fixture(
                restoreTtl: TimeSpan.FromMinutes(2));
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);
            fixture.Clock.Advance(TimeSpan.FromMinutes(2));

            HairTransactionResult result = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);

            Assert.Equal(HairTransactionOutcome.Rejected, result.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.RestoreExpired,
                result.ReasonCode);
            Assert.Single(fixture.Adapter.CommitCommands);
            Assert.Equal(
                HairRestorePointState.Expired,
                fixture.Store.ReadDirect(preview.TransactionId).State);
        }

        [Fact]
        public async Task Restore_RejectsCrossSaveAfterRestart()
        {
            Fixture fixture = new Fixture();
            HairAppearancePreview preview = await fixture.ReadyPreviewAsync();
            HairTransactionResult committed = await fixture.CommitAsync(preview);
            fixture.Adapter.ReplaceBinding(
                new HairSaveBinding(
                    fixture.Binding.SessionId,
                    fixture.Binding.LifecycleGeneration + 1,
                    "attempt-2",
                    fixture.Binding.AttemptGeneration + 1,
                    "slot-2",
                    "save-002"));

            HairTransactionResult result = await fixture.Service.RestoreAsync(
                preview.TransactionId,
                committed.RestoreToken);

            Assert.Equal(HairTransactionOutcome.Rejected, result.Outcome);
            Assert.Equal(
                HairAppearanceReasonCodes.CrossSave,
                result.ReasonCode);
            Assert.Single(fixture.Adapter.CommitCommands);
        }

        [Fact]
        public async Task FailClosedProductionPlaceholders_NeverDispatchDomainWrite()
        {
            var clock = new ManualAgentRuntimeClock();
            var consent = new HairAppearanceConsentBroker(clock);
            var service = new HairAppearanceModifierTransaction(
                new FailClosedHairdresserDomainAdapter(),
                new FailClosedHairRestorePointStore(),
                consent,
                clock);
            var binding = Binding();

            HairInspectResult inspect = await service.InspectAsync(binding);

            Assert.False(inspect.Success);
            Assert.Equal(
                HairAppearanceReasonCodes.AdapterUnavailable,
                inspect.ReasonCode);
        }

        [Fact]
        public void RestoreTtl_HasHardMaximum()
        {
            Fixture fixture = new Fixture();

            Assert.Throws<ArgumentOutOfRangeException>(() =>
                new HairAppearanceModifierTransaction(
                    fixture.Adapter,
                    fixture.Store,
                    fixture.Consent,
                    fixture.Clock,
                    HairAppearanceModifierTransaction.MaximumRestoreTtl
                        + TimeSpan.FromMilliseconds(1)));
        }

        private static HairSaveBinding Binding()
        {
            return new HairSaveBinding(
                "session-1",
                11,
                "attempt-1",
                5,
                "slot-1",
                "save-001");
        }

        private static HairAppearancePreview ClonePreview(
            HairAppearancePreview preview)
        {
            return new HairAppearancePreview(
                preview.TransactionId,
                preview.Binding,
                preview.BeforeHair,
                preview.AfterHair,
                preview.ExpectedRevision,
                preview.ExpectedGeneration,
                preview.ExpectedSnapshotHash,
                preview.PreviewHash,
                preview.CreatedAtUtc);
        }

        private sealed class Fixture
        {
            public Fixture(TimeSpan? restoreTtl = null)
            {
                Binding = HairAppearanceModifierTransactionTests.Binding();
                Clock = new ManualAgentRuntimeClock();
                Adapter = new InMemoryHairdresserDomainAdapter(
                    Binding,
                    BeforeHair);
                Store = new InMemoryHairRestorePointStore();
                Consent = new HairAppearanceConsentBroker(Clock);
                Service = new HairAppearanceModifierTransaction(
                    Adapter,
                    Store,
                    Consent,
                    Clock,
                    restoreTtl);
            }

            public HairSaveBinding Binding { get; }

            public ManualAgentRuntimeClock Clock { get; }

            public InMemoryHairdresserDomainAdapter Adapter { get; }

            public InMemoryHairRestorePointStore Store { get; }

            public HairAppearanceConsentBroker Consent { get; }

            public HairAppearanceModifierTransaction Service { get; }

            public async Task<HairPreviewResult> PreviewAsync(
                HairInspectResult inspect)
            {
                return await Service.PreviewAsync(
                    new HairPreviewRequest(
                        Binding,
                        AfterHair,
                        inspect.Snapshot.CurrentHair,
                        inspect.Snapshot.Revision,
                        inspect.Snapshot.Generation,
                        inspect.SnapshotHash));
            }

            public async Task<HairAppearancePreview> ReadyPreviewAsync()
            {
                HairInspectResult inspect = await Service.InspectAsync(Binding);
                HairPreviewResult result = await PreviewAsync(inspect);
                Assert.Equal(
                    HairTransactionOutcome.PreviewReady,
                    result.Outcome);
                return result.Preview;
            }

            public HairAppearanceConsentToken IssueConsent(
                HairAppearancePreview preview,
                TimeSpan? ttl = null)
            {
                return Consent.IssueForNeutralUi(
                    preview,
                    "consent-receipt-1",
                    ttl ?? TimeSpan.FromSeconds(60));
            }

            public async Task<HairTransactionResult> CommitAsync(
                HairAppearancePreview preview)
            {
                HairAppearanceConsentToken consent = IssueConsent(preview);
                HairTransactionResult result = await Service.CommitAsync(
                    preview,
                    consent.Token);
                Assert.Equal(
                    HairTransactionOutcome.DomainCommitted,
                    result.Outcome);
                return result;
            }
        }
    }
}
