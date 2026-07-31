using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.Tests.AgentRuntime.Domain;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class CompositeAgentRuntimeActionPerformerTests
    {
        [Fact]
        public async Task ClickMapsFramePixelThroughContentAndVirtualDesktop()
        {
            using var fixture = new PerformerFixture();
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.Click,
                new
                {
                    x = 10,
                    y = 20,
                    button = "primary",
                    clickCount = 1
                });

            AgentActionPerformance result =
                await fixture.PerformAsync(action);

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(
                new NativeScreenPoint(125, 266),
                fixture.Coordinates.Points.Single());
            NativeInputPacket move =
                fixture.Win32.SentBatches.Single()[0];
            Assert.Equal(1234, move.MouseDx);
            Assert.Equal(5678, move.MouseDy);
            Assert.True((move.MouseFlags & 0x8000) != 0);
            Assert.True((move.MouseFlags & 0x4000) != 0);
        }

        [Theory]
        [InlineData(-1, 0)]
        [InlineData(100, 0)]
        [InlineData(0, 80)]
        public async Task ClickRejectsCoordinatesOutsideCapturedFrame(
            int x,
            int y)
        {
            using var fixture = new PerformerFixture();
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.Click,
                new
                {
                    x,
                    y,
                    button = "primary",
                    clickCount = 1
                });

            AgentActionPerformance result =
                await fixture.PerformAsync(action);

            Assert.Equal(ActionOutcome.Rejected, result.Outcome);
            Assert.Equal(
                "stale_coordinate_space",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public async Task ClickRejectsCoordinateNormalizerFailure()
        {
            using var fixture = new PerformerFixture();
            fixture.Coordinates.Accept = false;

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    fixture.Action(
                        AgentCapabilitiesV1.Click,
                        new
                        {
                            x = 1,
                            y = 1,
                            button = "primary",
                            clickCount = 1
                        }));

            Assert.Equal(ActionOutcome.Rejected, result.Outcome);
            Assert.Equal(
                "stale_coordinate_space",
                result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public async Task AllowedKeyDispatchesBalancedModifierBatch()
        {
            using var fixture = new PerformerFixture();

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    fixture.Action(
                        AgentCapabilitiesV1.PressKey,
                        new
                        {
                            key = "a",
                            modifiers = new[] { "ctrl", "shift" },
                            repeat = 1
                        }));

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(
                new[]
                {
                    "Key:17",
                    "Key:16",
                    "Key:65",
                    "Key:65",
                    "Key:16",
                    "Key:17"
                },
                fixture.Win32.SentBatches.Single()
                    .Select(packet => packet.ControlId));
        }

        [Theory]
        [InlineData("tab", "alt")]
        [InlineData("f4", "alt")]
        [InlineData("delete", "ctrl,alt")]
        [InlineData("printscreen", "")]
        public async Task SystemShortcutsAndKeysOutsideAllowlistAreRejected(
            string key,
            string modifierList)
        {
            using var fixture = new PerformerFixture();
            string[] modifiers = string.IsNullOrEmpty(modifierList)
                ? Array.Empty<string>()
                : modifierList.Split(',');

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    fixture.Action(
                        AgentCapabilitiesV1.PressKey,
                        new
                        {
                            key,
                            modifiers,
                            repeat = 1
                        }));

            Assert.Equal(ActionOutcome.Rejected, result.Outcome);
            Assert.Equal("arguments_invalid", result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public async Task TextSecondBatchPartialInsertionIsUnknownAndPreempts()
        {
            using var fixture = new PerformerFixture();
            fixture.Win32.InsertedCountForCall =
                (call, requested) => call == 2
                    ? 1
                    : requested;
            string text = new string('a', 65);

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    fixture.Action(
                        AgentCapabilitiesV1.TypeText,
                        new { text }));

            Assert.Equal(ActionOutcome.Unknown, result.Outcome);
            Assert.Equal(
                ReconcileKind.VisualAmbiguous,
                result.ReconcileKind);
            Assert.Equal("input_not_inserted", result.ReasonCode);
            Assert.True(
                fixture.Sink.WaitFor("input_not_inserted"));
            Assert.False(
                fixture.Guard.IsLeaseBound(
                    PerformerFixture.SessionId,
                    PerformerFixture.LeaseId));
        }

        [Fact]
        public async Task TypeTextDoesNotSplitPairWhoseHighSurrogateIsCodeUnit64()
        {
            using var fixture = new PerformerFixture();
            string text = new string('a', 63)
                + "😀"
                + "z";

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    fixture.Action(
                        AgentCapabilitiesV1.TypeText,
                        new { text }));

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(
                new[] { 126, 6 },
                fixture.Win32.SentBatches
                    .Select(batch => batch.Length));
            Assert.Equal(
                text,
                TypedCodeUnits(fixture.Win32.SentBatches));
            Assert.True(
                char.IsHighSurrogate(
                    (char)fixture.Win32.SentBatches[1][0]
                        .ScanCode));
            Assert.True(
                char.IsLowSurrogate(
                    (char)fixture.Win32.SentBatches[1][2]
                        .ScanCode));
        }

        [Fact]
        public async Task TypeTextPreservesConsecutiveEmojiAcrossBatches()
        {
            using var fixture = new PerformerFixture();
            string text = string.Concat(
                Enumerable.Repeat("😀", 70));

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    fixture.Action(
                        AgentCapabilitiesV1.TypeText,
                        new { text }));

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(
                new[] { 128, 128, 24 },
                fixture.Win32.SentBatches
                    .Select(batch => batch.Length));
            Assert.Equal(
                text,
                TypedCodeUnits(fixture.Win32.SentBatches));
        }

        [Theory]
        [InlineData("{\"text\":\"\\uD83D\"}")]
        [InlineData("{\"text\":\"\\uDE00\"}")]
        public async Task TypeTextRejectsIsolatedSurrogate(
            string rawArguments)
        {
            using var fixture = new PerformerFixture();
            using JsonDocument document =
                JsonDocument.Parse(rawArguments);
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.TypeText,
                new { text = "valid" });
            action.Arguments = document.RootElement.Clone();

            AgentActionPerformance result =
                await fixture.PerformAsync(action);

            Assert.Equal(ActionOutcome.Rejected, result.Outcome);
            Assert.Equal("arguments_invalid", result.ReasonCode);
            Assert.Empty(fixture.Win32.SentBatches);
        }

        [Fact]
        public async Task TypeTextRejectsUnknownInnerFocusButPressKeyDoesNot()
        {
            using (var fixture = new PerformerFixture())
            {
                fixture.Win32.FocusedHwnd = IntPtr.Zero;
                AgentActionPerformance text =
                    await fixture.PerformAsync(
                        fixture.Action(
                            AgentCapabilitiesV1.TypeText,
                            new { text = "literal" }));

                Assert.Equal(ActionOutcome.Rejected, text.Outcome);
                Assert.Equal("stale_focus", text.ReasonCode);
                Assert.Empty(fixture.Win32.SentBatches);
            }

            using (var fixture = new PerformerFixture())
            {
                fixture.Win32.FocusedHwnd = IntPtr.Zero;
                AgentActionPerformance key =
                    await fixture.PerformAsync(
                        fixture.Action(
                            AgentCapabilitiesV1.PressKey,
                            new
                            {
                                key = "a",
                                modifiers = Array.Empty<string>(),
                                repeat = 1
                            }));

                Assert.Equal(
                    ActionOutcome.InputDispatched,
                    key.Outcome);
                Assert.Single(fixture.Win32.SentBatches);
            }
        }

        private static string TypedCodeUnits(
            IEnumerable<NativeInputPacket[]> batches)
        {
            return new string(
                batches
                    .SelectMany(batch => batch)
                    .Where(
                        (_, packetIndex) =>
                            packetIndex % 2 == 0)
                    .Select(packet => (char)packet.ScanCode)
                    .ToArray());
        }

        [Fact]
        public async Task DragCancellationPreemptsAndReleasesOwnedButton()
        {
            using var fixture = new PerformerFixture();
            using var source = new CancellationTokenSource();
            fixture.Win32.AfterSend =
                call =>
                {
                    if (call == 1)
                        source.Cancel();
                };
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.Drag,
                new
                {
                    startX = 1,
                    startY = 1,
                    endX = 10,
                    endY = 10,
                    durationMs = 100
                });

            await Assert.ThrowsAnyAsync<OperationCanceledException>(
                () => fixture.PerformAsync(
                    action,
                    source.Token));

            Assert.True(fixture.Sink.WaitFor("deadline_exceeded"));
            Assert.True(
                SpinWait.SpinUntil(
                    () => fixture.Win32.SentBatches
                        .Skip(1)
                        .SelectMany(batch => batch)
                        .Any(packet =>
                            packet.ControlId == "MouseLeft"
                            && packet.Transition
                                == NativeControlTransition.Up),
                    TimeSpan.FromSeconds(1)));
        }

        [Fact]
        public async Task StructuredNodeClickRoutesToHostAndFailClosedHostRejects()
        {
            using var fixture = new PerformerFixture();
            var recordingHost = new RecordingStructuredHost(
                AgentActionPerformance.Completed(
                    ActionOutcome.EffectObserved,
                    EvidenceKind.PostObservation,
                    PerformerFixture.TargetId,
                    true));
            fixture.ReplaceStructuredHost(recordingHost);
            ActionEnvelope semanticClick = fixture.Action(
                AgentCapabilitiesV1.Click,
                new
                {
                    x = 1,
                    y = 1,
                    button = "primary",
                    clickCount = 1
                });
            semanticClick.NodeId = "node_AAAAAAAAAAAAAAAAAA";

            AgentActionPerformance routed =
                await fixture.PerformAsync(semanticClick);

            Assert.Equal(ActionOutcome.EffectObserved, routed.Outcome);
            Assert.Equal(1, recordingHost.CallCount);
            Assert.Empty(fixture.Win32.SentBatches);

            AgentActionPerformance panel =
                await fixture.PerformAsync(
                    fixture.Action(
                        AgentCapabilitiesV1.PanelOpen,
                        new { panel = "help" }),
                    fixture.StructuredActionLease());
            Assert.Equal(
                ActionOutcome.EffectObserved,
                panel.Outcome);
            Assert.Equal(2, recordingHost.CallCount);
            Assert.Empty(fixture.Win32.SentBatches);

            fixture.ReplaceStructuredHost(
                new FailClosedAgentStructuredActionHost());
            AgentActionPerformance rejected =
                await fixture.PerformAsync(
                    fixture.Action(
                        AgentCapabilitiesV1.SetValue,
                        new { value = "x" }));
            Assert.Equal(ActionOutcome.Rejected, rejected.Outcome);
            Assert.Equal(
                "unsupported_for_surface",
                rejected.ReasonCode);
        }

        [Fact]
        public async Task HairCommitAndRestoreReturnPairedDomainResults()
        {
            using var fixture = new PerformerFixture();
            HairAppearancePreview preview =
                await fixture.ReadyHairPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.HairConsent.IssueForNeutralUi(
                    preview,
                    "consent-receipt",
                    TimeSpan.FromMinutes(1));
            fixture.HairPreviews.Store(
                fixture.Context,
                PerformerFixture.TargetId,
                preview);
            WriteLease commitLease = fixture.DomainLease(
                AgentMethodsV1.HairCommit,
                preview);
            ActionEnvelope commitAction = fixture.Action(
                AgentMethodsV1.HairCommit,
                new
                {
                    transactionId = preview.TransactionId,
                    previewHash = preview.PreviewHash,
                    consentToken = consent.Token
                });

            AgentActionPerformance committed =
                await fixture.PerformAsync(
                    commitAction,
                    commitLease);

            Assert.Equal(
                ActionOutcome.DomainCommitted,
                committed.Outcome);
            Assert.NotNull(committed.DomainResult);
            Assert.Equal(
                preview.TransactionId,
                committed.DomainResult.TransactionId);
            Assert.Equal(
                preview.PreviewHash,
                committed.DomainResult.PreviewHash);
            Assert.False(
                string.IsNullOrWhiteSpace(
                    committed.DomainResult.RestoreToken));
            Assert.NotNull(
                committed.DomainResult.RestoreExpiresAtUtc);

            WriteLease restoreLease = fixture.DomainLease(
                AgentMethodsV1.HairRestore,
                preview);
            ActionEnvelope restoreAction = fixture.Action(
                AgentMethodsV1.HairRestore,
                new
                {
                    transactionId = preview.TransactionId,
                    restoreToken =
                        committed.DomainResult.RestoreToken
                });
            AgentActionPerformance restored =
                await fixture.PerformAsync(
                    restoreAction,
                    restoreLease);

            Assert.Equal(
                ActionOutcome.DomainCommitted,
                restored.Outcome);
            Assert.Equal(
                preview.TransactionId,
                restored.DomainResult.TransactionId);
            Assert.Equal(
                preview.PreviewHash,
                restored.DomainResult.PreviewHash);
            Assert.Null(restored.DomainResult.RestoreToken);
            Assert.Null(
                restored.DomainResult.RestoreExpiresAtUtc);
        }

        [Fact]
        public async Task HairRejectsPreviewHashAndLeaseOperationMismatch()
        {
            using var fixture = new PerformerFixture();
            HairAppearancePreview preview =
                await fixture.ReadyHairPreviewAsync();
            fixture.HairPreviews.Store(
                fixture.Context,
                PerformerFixture.TargetId,
                preview);
            ActionEnvelope action = fixture.Action(
                AgentMethodsV1.HairCommit,
                new
                {
                    transactionId = preview.TransactionId,
                    previewHash = new string('A', 64),
                    consentToken = "unused"
                });

            AgentActionPerformance previewMismatch =
                await fixture.PerformAsync(
                    action,
                    fixture.DomainLease(
                        AgentMethodsV1.HairCommit,
                        preview));
            Assert.Equal(
                ActionOutcome.Rejected,
                previewMismatch.Outcome);
            Assert.Equal(
                "domain_revision_conflict",
                previewMismatch.ReasonCode);

            action.Arguments = JsonSerializer.SerializeToElement(
                new
                {
                    transactionId = preview.TransactionId,
                    previewHash = preview.PreviewHash,
                    consentToken = "unused"
                });
            AgentActionPerformance operationMismatch =
                await fixture.PerformAsync(
                    action,
                    fixture.DomainLease(
                        AgentMethodsV1.HairRestore,
                        preview));
            Assert.Equal(
                ActionOutcome.Rejected,
                operationMismatch.Outcome);
            Assert.Equal(
                "operation_invalid",
                operationMismatch.ReasonCode);
        }

        [Fact]
        public async Task HairTargetMismatchRejectsBeforeAnyDomainWrite()
        {
            using var fixture = new PerformerFixture();
            HairAppearancePreview preview =
                await fixture.ReadyHairPreviewAsync();
            HairAppearanceConsentToken consent =
                fixture.HairConsent.IssueForNeutralUi(
                    preview,
                    "consent-receipt",
                    TimeSpan.FromMinutes(1));
            fixture.HairPreviews.Store(
                fixture.Context,
                "launcher_target_not_domain",
                preview);
            ActionEnvelope action = fixture.Action(
                AgentMethodsV1.HairCommit,
                new
                {
                    transactionId = preview.TransactionId,
                    previewHash = preview.PreviewHash,
                    consentToken = consent.Token
                });

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    action,
                    fixture.DomainLease(
                        AgentMethodsV1.HairCommit,
                        preview));

            Assert.Equal(ActionOutcome.Rejected, result.Outcome);
            Assert.Equal(
                "domain_revision_conflict",
                result.ReasonCode);
            Assert.Empty(fixture.HairAdapter.CommitCommands);
        }

        private sealed class PerformerFixture : IDisposable
        {
            internal const string SessionId =
                "session_performer_a";
            internal const string TargetId =
                "target_performer_aa";
            internal const string LeaseId =
                "lease_performer_aaa";
            private const string AttemptId =
                "attempt_performer_a";
            private const string PanelId =
                "panel_performer_aa";
            private const string ObservationId =
                "observation_performer_a";
            private const string FrameId =
                "frame_performer_aaaa";

            private IAgentStructuredActionHost _structuredHost;

            internal PerformerFixture()
            {
                Clock = new ManualAgentRuntimeClock();
                Epochs = new InputEpochSnapshot(
                    SessionId,
                    7,
                    AttemptId,
                    3,
                    TargetId,
                    11,
                    13,
                    PanelId,
                    5,
                    17,
                    19);
                Safety = new InputSafetyStateMachine(Clock);
                Safety.SetInitialAuthoritativeState(
                    Epochs,
                    TargetId);
                Win32 = new TestWin32Facade
                {
                    ForegroundHwnd = new IntPtr(100),
                    FocusedHwnd = new IntPtr(100),
                    HitHwnd = new IntPtr(100),
                    InteractiveDesktop = true,
                    RelatedHit = true
                };
                Win32.IntegrityByPid[Win32.CurrentProcessId] =
                    0x2000;
                Win32.IntegrityByPid[222] = 0x2000;
                Targets = new MutableNativeTargets(
                    new NativeInputTargetSnapshot(
                        SessionId,
                        TargetId,
                        new IntPtr(100),
                        222,
                        Epochs,
                        true,
                        false,
                        false));
                Sink = new RecordingPreemptionSink();
                Guard = new NativeInputGuard(
                    Safety,
                    Win32,
                    Sink,
                    false);
                Win32.MonotonicMilliseconds =
                    InputSafetyStateMachine
                        .QuiescenceMilliseconds;
                Guard.BindLease(SessionId, LeaseId);
                NativeInput = new NativeInputExecutor(
                    Safety,
                    Guard,
                    Win32,
                    Targets);
                Observations =
                    new AgentObservationEnvelopeStore();
                Context = new AgentRuntimeDispatchContext(
                    "connection_performer_a",
                    Principal());
                Observations.Store(
                    Context,
                    ObservationDataScopesV1.Pixels,
                    Envelope());
                Coordinates =
                    new RecordingCoordinateNormalizer();
                _structuredHost =
                    new FailClosedAgentStructuredActionHost();

                HairBinding = new HairSaveBinding(
                    SessionId,
                    7,
                    AttemptId,
                    3,
                    "slot_performer",
                    "save_performer");
                HairAdapter =
                    new InMemoryHairdresserDomainAdapter(
                        HairBinding,
                        "光头");
                HairConsent =
                    new HairAppearanceConsentBroker(Clock);
                Hair = new HairAppearanceModifierTransaction(
                    HairAdapter,
                    new InMemoryHairRestorePointStore(),
                    HairConsent,
                    Clock);
                HairPreviews = new AgentHairPreviewStore();
                HairTargets =
                    new RecordingHairTargetAuthority(TargetId);
                RebuildPerformer();
            }

            internal ManualAgentRuntimeClock Clock { get; }
            internal InputEpochSnapshot Epochs { get; }
            internal InputSafetyStateMachine Safety { get; }
            internal TestWin32Facade Win32 { get; }
            internal MutableNativeTargets Targets { get; }
            internal RecordingPreemptionSink Sink { get; }
            internal NativeInputGuard Guard { get; }
            internal NativeInputExecutor NativeInput { get; }
            internal AgentObservationEnvelopeStore Observations
            {
                get;
            }
            internal RecordingCoordinateNormalizer Coordinates
            {
                get;
            }
            internal AgentRuntimeDispatchContext Context { get; }
            internal HairSaveBinding HairBinding { get; }
            internal InMemoryHairdresserDomainAdapter HairAdapter
            {
                get;
            }
            internal HairAppearanceConsentBroker HairConsent
            {
                get;
            }
            internal HairAppearanceModifierTransaction Hair { get; }
            internal AgentHairPreviewStore HairPreviews { get; }
            internal RecordingHairTargetAuthority HairTargets
            {
                get;
            }
            internal CompositeAgentRuntimeActionPerformer Performer
            {
                get;
                private set;
            }

            internal void ReplaceStructuredHost(
                IAgentStructuredActionHost host)
            {
                _structuredHost = host;
                RebuildPerformer();
            }

            internal Task<AgentActionPerformance> PerformAsync(
                ActionEnvelope action,
                CancellationToken cancellationToken = default)
            {
                return PerformAsync(
                    action,
                    GuiLease(action.Operation),
                    cancellationToken);
            }

            internal Task<AgentActionPerformance> PerformAsync(
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken = default)
            {
                return Performer.PerformAsync(
                    Context,
                    action,
                    lease,
                    cancellationToken);
            }

            internal async Task<HairAppearancePreview>
                ReadyHairPreviewAsync()
            {
                HairInspectResult inspect =
                    await Hair.InspectAsync(HairBinding);
                Assert.True(inspect.Success);
                string after = inspect.Snapshot.Catalog
                    .Select(item => item.Identifier)
                    .First(value => !string.Equals(
                        value,
                        inspect.Snapshot.CurrentHair,
                        StringComparison.Ordinal));
                HairPreviewResult result =
                    await Hair.PreviewAsync(
                        new HairPreviewRequest(
                            HairBinding,
                            after,
                            inspect.Snapshot.CurrentHair,
                            inspect.Snapshot.Revision,
                            inspect.Snapshot.Generation,
                            inspect.SnapshotHash));
                Assert.Equal(
                    HairTransactionOutcome.PreviewReady,
                    result.Outcome);
                return result.Preview;
            }

            internal WriteLease DomainLease(
                string operation,
                HairAppearancePreview preview)
            {
                return Lease(
                    "lease_domain_"
                        + (operation == AgentMethodsV1.HairCommit
                            ? "commit"
                            : "restore"),
                    WriteLeaseKind.DomainTransaction,
                    operation,
                    preview.PreviewHash,
                    preview.ExpectedRevision.ToString());
            }

            internal WriteLease StructuredActionLease()
            {
                return Lease(
                    LeaseId,
                    WriteLeaseKind.StructuredAction,
                    AgentCapabilitiesV1.PanelOpen,
                    null,
                    null);
            }

            internal ActionEnvelope Action(
                string operation,
                object arguments)
            {
                return new ActionEnvelope
                {
                    ActionId = "action_performer_aaaa",
                    IdempotencyKey =
                        "idempotency_performer",
                    DeadlineMs = 1_000,
                    SessionId = SessionId,
                    ObservationGrantId =
                        "obsgrant_performer_aa",
                    LeaseId = LeaseId,
                    ObservationId = ObservationId,
                    ExpectedLifecycleGeneration = 7,
                    TargetId = TargetId,
                    ExpectedSurfaceEpoch = 11,
                    ExpectedAttemptId = AttemptId,
                    ExpectedAttemptGeneration = 3,
                    ExpectedPanelInstanceId = PanelId,
                    ExpectedSemanticGeneration = 23,
                    ExpectedDocumentGeneration = 5,
                    ExpectedCoordinateSpaceVersion = 13,
                    ExpectedFocusEpoch = 17,
                    ExpectedModalEpoch = 19,
                    FrameId = FrameId,
                    SemanticSnapshotId =
                        "semantic_performer_a",
                    Operation = operation,
                    Arguments =
                        JsonSerializer.SerializeToElement(
                            arguments),
                    Reason = "focused performer test"
                };
            }

            private void RebuildPerformer()
            {
                Performer =
                    new CompositeAgentRuntimeActionPerformer(
                        NativeInput,
                        Guard,
                        Safety,
                        Observations,
                        _structuredHost,
                        Hair,
                        HairPreviews,
                        HairTargets,
                        Coordinates);
            }

            private WriteLease GuiLease(string capability)
            {
                return Lease(
                    LeaseId,
                    WriteLeaseKind.GuiInput,
                    capability,
                    null,
                    null);
            }

            private WriteLease Lease(
                string leaseId,
                WriteLeaseKind kind,
                string capability,
                string previewHash,
                string revision)
            {
                PrincipalCredential principal = Context?.Principal
                    ?? Principal();
                return new WriteLease(
                    leaseId,
                    principal,
                    new WriteLeaseRequest
                    {
                        SessionId = SessionId,
                        LifecycleGeneration = 7,
                        Kind = kind,
                        Capabilities = new[] { capability },
                        TargetScope = new[] { TargetId },
                        PreviewHash = previewHash,
                        ExpectedRevision = revision,
                        Operation = kind
                                is WriteLeaseKind.DomainTransaction
                                or WriteLeaseKind.StructuredAction
                            ? capability
                            : null
                    },
                    0,
                    60_000,
                    kind is WriteLeaseKind.StructuredAction
                        or WriteLeaseKind.Shutdown
                        ? 1
                        : 20);
            }

            private static PrincipalCredential Principal()
            {
                return new PrincipalCredential(
                    "credential_performer_a",
                    "principal_performer_aa",
                    "client_performer_aaaa",
                    AgentPrincipalKind.DeveloperAgent,
                    AgentSessionMode.DeveloperInteractive,
                    1,
                    0,
                    60_000,
                    DateTimeOffset.UtcNow,
                    new[]
                    {
                        AgentCapabilitiesV1.Click,
                        AgentCapabilitiesV1.PanelOpen,
                        AgentCapabilitiesV1.PressKey,
                        AgentCapabilitiesV1.TypeText,
                        AgentCapabilitiesV1.Scroll,
                        AgentCapabilitiesV1.Drag,
                        AgentCapabilitiesV1.SetValue,
                        AgentMethodsV1.HairCommit,
                        AgentMethodsV1.HairRestore
                    },
                    new[] { TargetId },
                    "test-enrollment",
                    null,
                    null,
                    null,
                    null);
            }

            private static ObservationEnvelope Envelope()
            {
                return new ObservationEnvelope
                {
                    ObservationId = ObservationId,
                    ObservationGrantId =
                        "obsgrant_performer_aa",
                    SessionId = SessionId,
                    LifecycleGeneration = 7,
                    CapturedUtc = DateTimeOffset.UtcNow,
                    CapturedAtMonotonic = 10,
                    AttemptId = AttemptId,
                    AttemptGeneration = 3,
                    PanelInstanceId = PanelId,
                    DocumentGeneration = 5,
                    TargetId = TargetId,
                    SurfaceEpoch = 11,
                    CoordinateSpaceVersion = 13,
                    FocusEpoch = 17,
                    ModalEpoch = 19,
                    SemanticSnapshotId =
                        "semantic_performer_a",
                    SemanticGeneration = 23,
                    Visible = true,
                    Active = true,
                    Frames = new List<FrameEnvelope>
                    {
                        new FrameEnvelope
                        {
                            FrameId = FrameId,
                            ObservationId = ObservationId,
                            TargetId = TargetId,
                            SurfaceEpoch = 11,
                            CoordinateSpaceVersion = 13,
                            Width = 100,
                            Height = 80,
                            ContentRectPhysical =
                                new PhysicalRect
                                {
                                    X = 100,
                                    Y = 200,
                                    Width = 300,
                                    Height = 300
                                },
                            FrameToTargetContentTransform =
                                new AffineTransform
                                {
                                    M11 = 2,
                                    M22 = 3,
                                    Dx = 4,
                                    Dy = 5
                                },
                            OpaqueContentHandle =
                                "content_performer_aa"
                        }
                    }
                };
            }

            public void Dispose()
            {
                Guard.Dispose();
                Sink.Dispose();
            }
        }

        private sealed class RecordingCoordinateNormalizer
            : INativeScreenCoordinateNormalizer
        {
            internal bool Accept { get; set; } = true;
            internal List<NativeScreenPoint> Points { get; } =
                new List<NativeScreenPoint>();

            public bool TryNormalize(
                NativeScreenPoint point,
                out int absoluteX,
                out int absoluteY)
            {
                Points.Add(point);
                absoluteX = 1234;
                absoluteY = 5678;
                return Accept;
            }
        }

        private sealed class RecordingHairTargetAuthority
            : IAgentHairDomainTargetAuthority
        {
            private readonly string _targetId;

            internal RecordingHairTargetAuthority(string targetId)
            {
                _targetId = targetId;
            }

            internal bool Accept { get; set; } = true;

            public bool TryAuthorize(
                string sessionId,
                string targetId,
                out string reasonCode)
            {
                if (Accept
                    && string.Equals(
                        _targetId,
                        targetId,
                        StringComparison.Ordinal))
                {
                    reasonCode = null;
                    return true;
                }
                reasonCode = "unsupported_for_surface";
                return false;
            }
        }

        private sealed class RecordingStructuredHost
            : IAgentStructuredActionHost
        {
            private readonly AgentActionPerformance _result;

            internal RecordingStructuredHost(
                AgentActionPerformance result)
            {
                _result = result;
            }

            internal int CallCount { get; private set; }

            public Task<AgentActionPerformance> PerformAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
            {
                CallCount++;
                return Task.FromResult(_result);
            }
        }

        private sealed class MutableNativeTargets
            : IAuthoritativeNativeInputTarget
        {
            internal MutableNativeTargets(
                NativeInputTargetSnapshot snapshot)
            {
                Snapshot = snapshot;
            }

            internal NativeInputTargetSnapshot Snapshot { get; set; }

            public bool TryResolve(
                string sessionId,
                string targetId,
                out NativeInputTargetSnapshot target,
                out string reasonCode)
            {
                target = Snapshot;
                reasonCode = null;
                return true;
            }

            public bool TryResolveForDispatch(
                string sessionId,
                string targetId,
                out NativeInputTargetSnapshot target,
                out string reasonCode)
            {
                return TryResolve(
                    sessionId,
                    targetId,
                    out target,
                    out reasonCode);
            }

            public bool TryValidateDispatchIdentity(
                NativeInputTargetSnapshot target,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }

            public bool IsRegisteredInputWindow(
                NativeInputTargetSnapshot target,
                IntPtr candidateHwnd)
            {
                return candidateHwnd == target.TargetHwnd;
            }
        }

        private sealed class RecordingPreemptionSink
            : INativeInputPreemptionSink,
            IDisposable
        {
            private readonly AutoResetEvent _signal =
                new AutoResetEvent(false);
            private readonly ConcurrentQueue<string> _reasons =
                new ConcurrentQueue<string>();

            public void RevokeLeaseAndCancelQueuedActions(
                string sessionId,
                string leaseId,
                string reasonCode)
            {
                _reasons.Enqueue(reasonCode);
                _signal.Set();
            }

            internal bool WaitFor(string reasonCode)
            {
                if (_reasons.Contains(reasonCode))
                    return true;
                _signal.WaitOne(TimeSpan.FromSeconds(1));
                return _reasons.Contains(reasonCode);
            }

            public void Dispose()
            {
                _signal.Dispose();
            }
        }

        private sealed class TestWin32Facade
            : INativeInputWin32Facade
        {
            private Func<NativeLowLevelHookEvent, bool> _callback;
            private int _sendCallCount;

            internal TestHookSession HookSession { get; } =
                new TestHookSession();
            internal bool InteractiveDesktop { get; set; }
            internal IntPtr ForegroundHwnd { get; set; }
            internal IntPtr FocusedHwnd { get; set; }
            internal IntPtr HitHwnd { get; set; }
            internal bool RelatedHit { get; set; }
            internal Dictionary<int, int> IntegrityByPid { get; } =
                new Dictionary<int, int>();
            internal Func<int, int, int> InsertedCountForCall
            {
                get;
                set;
            }
            internal Action<int> AfterSend { get; set; }
            internal List<NativeInputPacket[]> SentBatches { get; } =
                new List<NativeInputPacket[]>();

            public int CurrentProcessId => 111;
            public long MonotonicMilliseconds { get; set; }

            public INativeLowLevelHookSession
                InstallLowLevelHooks(
                    ulong runtimeInjectionTag,
                    Func<NativeLowLevelHookEvent, bool> callback)
            {
                _callback = callback;
                return HookSession;
            }

            public bool IsInteractiveDesktopAvailable()
            {
                return InteractiveDesktop;
            }

            public IntPtr GetForegroundWindow()
            {
                return ForegroundHwnd;
            }

            public bool TryGetFocusedWindow(
                IntPtr foregroundTopLevelHwnd,
                out IntPtr focusedHwnd)
            {
                focusedHwnd = FocusedHwnd;
                return focusedHwnd != IntPtr.Zero;
            }

            public IntPtr WindowFromPoint(NativeScreenPoint point)
            {
                return HitHwnd;
            }

            public bool IsSameChildOrOwnedWindow(
                IntPtr targetTopLevelHwnd,
                IntPtr candidateHwnd)
            {
                return RelatedHit;
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
                return IntegrityByPid.TryGetValue(
                    processId,
                    out integrityRid);
            }

            public int SendInput(
                IReadOnlyList<NativeInputPacket> packets,
                ulong runtimeInjectionTag)
            {
                NativeInputPacket[] copy = packets.ToArray();
                SentBatches.Add(copy);
                int call = Interlocked.Increment(
                    ref _sendCallCount);
                int inserted = Math.Clamp(
                    InsertedCountForCall?.Invoke(
                        call,
                        copy.Length)
                        ?? copy.Length,
                    0,
                    copy.Length);
                for (int i = 0; i < inserted; i++)
                {
                    _callback(
                        ToHookEvent(
                            copy[i],
                            runtimeInjectionTag));
                }
                AfterSend?.Invoke(call);
                return inserted;
            }

            private static NativeLowLevelHookEvent ToHookEvent(
                NativeInputPacket packet,
                ulong tag)
            {
                NativeHookDevice device =
                    packet.Kind
                        == NativeInputPacketKind.Keyboard
                            ? NativeHookDevice.Keyboard
                            : NativeHookDevice.Mouse;
                return new NativeLowLevelHookEvent(
                    device,
                    packet.ControlId,
                    packet.Transition,
                    true,
                    tag,
                    device == NativeHookDevice.Mouse
                        ? new NativeScreenPoint(125, 266)
                        : null,
                    NativeMessage(packet));
            }

            private static uint NativeMessage(
                NativeInputPacket packet)
            {
                if (packet.Kind
                    == NativeInputPacketKind.Keyboard)
                {
                    return packet.Transition
                        == NativeControlTransition.Up
                            ? 0x0101u
                            : 0x0100u;
                }
                uint flags = packet.MouseFlags;
                if ((flags & 0x0002) != 0) return 0x0201;
                if ((flags & 0x0004) != 0) return 0x0202;
                if ((flags & 0x0008) != 0) return 0x0204;
                if ((flags & 0x0010) != 0) return 0x0205;
                if ((flags & 0x0020) != 0) return 0x0207;
                if ((flags & 0x0040) != 0) return 0x0208;
                if ((flags & 0x0800) != 0) return 0x020A;
                if ((flags & 0x1000) != 0) return 0x020E;
                return 0x0200;
            }
        }

        private sealed class TestHookSession
            : INativeLowLevelHookSession
        {
            private bool _healthy = true;

            public bool IsHealthy(TimeSpan maximumHeartbeatAge)
            {
                return _healthy;
            }

            public bool TryRefresh(TimeSpan timeout)
            {
                return _healthy;
            }

            public void Dispose()
            {
                _healthy = false;
            }
        }
    }
}
