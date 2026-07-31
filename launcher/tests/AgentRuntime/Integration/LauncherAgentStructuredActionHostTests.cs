using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class LauncherAgentStructuredActionHostTests
    {
        [Fact]
        public async Task ActivateUsesExactCallbackOnUiAndReportsBrokerDispatch()
        {
            using var fixture = new Fixture();
            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.ActivateWindow);

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(
                EvidenceKind.BrokerDispatch,
                result.EvidenceKind);
            Assert.Equal(Fixture.TargetId, result.ActualTargetId);
            Assert.True(result.FocusVerified);
            Assert.Equal("none", result.ReasonCode);
            Assert.Equal(1, fixture.Ui.CallCount);
            Assert.Equal(1, fixture.ActivateCallCount);
            Assert.True(fixture.AllCallbacksRanOnUi);
            Assert.NotNull(fixture.LastActivationBinding);
            Assert.Equal(
                1001,
                fixture.LastActivationBinding.WindowHandle);
            Assert.Equal(
                Fixture.LifecycleGeneration,
                fixture.LastActivationBinding
                    .LifecycleGeneration);
            Assert.Equal(
                Fixture.AttemptGeneration,
                fixture.LastActivationBinding
                    .AttemptGeneration);
        }

        [Fact]
        public async Task ActivateCallbackFalseRejectsWithoutEffectClaim()
        {
            using var fixture = new Fixture();
            fixture.ActivateAccepted = false;

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.ActivateWindow);

            AssertRejected(result, "foreground_mismatch");
            Assert.Equal(EvidenceKind.None, result.EvidenceKind);
            Assert.Equal(1, fixture.ActivateCallCount);
        }

        [Fact]
        public async Task ActivateRequiresConfiguredExactTargetCallback()
        {
            using var fixture = new Fixture(
                includeActivator: false);

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.ActivateWindow);

            AssertRejected(
                result,
                "unsupported_for_surface");
            Assert.Equal(1, fixture.Ui.CallCount);
            Assert.Equal(0, fixture.ActivateCallCount);
        }

        [Fact]
        public async Task ActivateNeverDiscoversUnregisteredTarget()
        {
            using var fixture = new Fixture();
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.ActivateWindow,
                Fixture.OtherTargetId);
            WriteLease lease = fixture.Lease(
                AgentCapabilitiesV1.ActivateWindow,
                Fixture.OtherTargetId);

            AgentActionPerformance result =
                await fixture.Host.PerformAsync(
                    fixture.Context,
                    action,
                    lease,
                    CancellationToken.None);

            AssertRejected(result, "target_not_found");
            Assert.Equal(0, fixture.ActivateCallCount);
        }

        [Fact]
        public async Task
            ShutdownPreparesButDoesNotFinalizeBeforeResponseCommit()
        {
            using var fixture = new Fixture();

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.SessionShutdown);

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(
                EvidenceKind.BrokerDispatch,
                result.EvidenceKind);
            Assert.Equal(
                "shutdown_requested",
                result.ReasonCode);
            Assert.False(result.FocusVerified);
            Assert.Equal(1, fixture.PrepareSafeExitCallCount);
            Assert.Equal(0, fixture.CompleteSafeExitCallCount);
            Assert.Equal(0, fixture.AbortSafeExitCallCount);
            Assert.NotNull(result.ResponseCompletion);
            Assert.True(fixture.AllCallbacksRanOnUi);
            Assert.NotEqual(
                EvidenceKind.ProcessExit,
                result.EvidenceKind);

            result.ResponseCompletion.CommitAfterWrite();
            result.ResponseCompletion.CommitAfterWrite();
            result.ResponseCompletion.Abort();

            Assert.Equal(1, fixture.CompleteSafeExitCallCount);
            Assert.Equal(0, fixture.AbortSafeExitCallCount);
            Assert.Equal(
                "action_structured_AAAAA",
                fixture.LastCompletedActionId);
        }

        [Fact]
        public async Task ShutdownAbortIsExactOnceAndNeverFinalizes()
        {
            using var fixture = new Fixture();

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.SessionShutdown);

            Assert.NotNull(result.ResponseCompletion);
            Assert.Equal(1, fixture.PrepareSafeExitCallCount);
            result.ResponseCompletion.Abort();
            result.ResponseCompletion.Abort();
            result.ResponseCompletion.CommitAfterWrite();

            Assert.Equal(0, fixture.CompleteSafeExitCallCount);
            Assert.Equal(1, fixture.AbortSafeExitCallCount);
            Assert.Equal(
                "action_structured_AAAAA",
                fixture.LastAbortedActionId);
        }

        [Fact]
        public async Task
            ShutdownAbortReportsUiAcknowledgementFailure()
        {
            using var fixture = new Fixture();
            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.SessionShutdown);
            fixture.Ui.HostAvailable = false;

            Assert.False(
                result.ResponseCompletion.Abort());
            Assert.False(
                result.ResponseCompletion.Abort());
            Assert.Equal(
                0,
                fixture.AbortSafeExitCallCount);
        }

        [Fact]
        public async Task
            ShutdownCommitReportsUiAcknowledgementFailure()
        {
            using var fixture = new Fixture();
            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.SessionShutdown);
            fixture.Ui.HostAvailable = false;

            Assert.False(
                result.ResponseCompletion
                    .CommitAfterWrite());
            Assert.Equal(
                0,
                fixture.CompleteSafeExitCallCount);
        }

        [Fact]
        public async Task ShutdownFenceFalseRequiresHumanIntervention()
        {
            using var fixture = new Fixture
            {
                PrepareSafeExitAccepted = false
            };

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.SessionShutdown);

            AssertRejected(
                result,
                "human_intervention_required");
            Assert.Null(result.ResponseCompletion);
            Assert.Equal(1, fixture.PrepareSafeExitCallCount);
            Assert.Equal(0, fixture.CompleteSafeExitCallCount);
            Assert.Equal(0, fixture.AbortSafeExitCallCount);
        }

        [Fact]
        public async Task ShutdownWithWrongLeaseKindNeverPrepares()
        {
            using var fixture = new Fixture();
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.SessionShutdown);
            WriteLease lease = fixture.Lease(
                AgentCapabilitiesV1.SessionShutdown,
                Fixture.TargetId,
                WriteLeaseKind.GuiInput);

            AgentActionPerformance result =
                await fixture.Host.PerformAsync(
                    fixture.Context,
                    action,
                    lease,
                    CancellationToken.None);

            AssertRejected(result, "capability_denied");
            Assert.Equal(0, fixture.PrepareSafeExitCallCount);
            Assert.Equal(0, fixture.CompleteSafeExitCallCount);
            Assert.Equal(0, fixture.AbortSafeExitCallCount);
        }

        [Theory]
        [InlineData(AgentCapabilitiesV1.LifecycleReveal)]
        [InlineData(AgentCapabilitiesV1.LifecycleCancel)]
        public async Task LifecycleCallbacksRunOnUiWithDispatchOnlyEvidence(
            string operation)
        {
            using var fixture = new Fixture();

            AgentActionPerformance result =
                await fixture.PerformAsync(operation);

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(
                EvidenceKind.BrokerDispatch,
                result.EvidenceKind);
            Assert.Equal("none", result.ReasonCode);
            Assert.Equal(
                operation
                    == AgentCapabilitiesV1.LifecycleReveal
                        ? 1
                        : 0,
                fixture.RevealCallCount);
            Assert.Equal(
                operation
                    == AgentCapabilitiesV1.LifecycleCancel
                        ? 1
                        : 0,
                fixture.CancelCallCount);
            Assert.True(fixture.AllCallbacksRanOnUi);
        }

        [Fact]
        public async Task PanelOpenPassesOnlyPanelNameToRouterAllowListCallback()
        {
            using var fixture = new Fixture();
            fixture.Snapshot = fixture.CreateSnapshot(
                inputModes: Array.Empty<InputMode>());
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.PanelOpen);
            action.Arguments = JsonSerializer.SerializeToElement(
                new
                {
                    panel = "help"
                });

            AgentActionPerformance result =
                await fixture.PerformAsync(action);

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(
                EvidenceKind.BrokerDispatch,
                result.EvidenceKind);
            Assert.Equal("help", fixture.LastPanelName);
            Assert.Equal(1, fixture.PanelOpenCallCount);
            Assert.True(fixture.AllCallbacksRanOnUi);
        }

        [Fact]
        public async Task PanelOpenWithGuiLeaseKindNeverReachesRouter()
        {
            using var fixture = new Fixture();
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.PanelOpen);
            WriteLease guiLease = fixture.Lease(
                AgentCapabilitiesV1.PanelOpen,
                Fixture.TargetId,
                WriteLeaseKind.GuiInput);

            AgentActionPerformance result =
                await fixture.Host.PerformAsync(
                    fixture.Context,
                    action,
                    guiLease,
                    CancellationToken.None);

            AssertRejected(result, "capability_denied");
            Assert.Equal(0, fixture.PanelOpenCallCount);
        }

        [Fact]
        public async Task PanelRouterRejectionFailsClosed()
        {
            using var fixture = new Fixture();
            fixture.PanelAccepted = false;
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.PanelOpen);
            action.Arguments = JsonSerializer.SerializeToElement(
                new
                {
                    panel = "not_allowlisted"
                });

            AgentActionPerformance result =
                await fixture.PerformAsync(action);

            AssertRejected(
                result,
                "unsupported_for_surface");
            Assert.Equal(
                "not_allowlisted",
                fixture.LastPanelName);
            Assert.Equal(1, fixture.PanelOpenCallCount);
        }

        [Theory]
        [InlineData(AgentCapabilitiesV1.SetValue)]
        [InlineData(
            AgentCapabilitiesV1.PerformSecondaryAction)]
        public async Task SemanticOperationsRemainUnsupported(
            string operation)
        {
            using var fixture = new Fixture();

            AgentActionPerformance result =
                await fixture.PerformAsync(operation);

            AssertRejected(
                result,
                "unsupported_for_surface");
            Assert.Equal(0, fixture.Ui.CallCount);
            Assert.Equal(0, fixture.TotalHostCallbackCount);
        }

        [Fact]
        public async Task UnknownOperationIsRejectedWithoutHostCallback()
        {
            using var fixture = new Fixture();

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.Click);

            AssertRejected(result, "operation_invalid");
            Assert.Equal(0, fixture.Ui.CallCount);
            Assert.Equal(0, fixture.TotalHostCallbackCount);
        }

        [Theory]
        [InlineData("lifecycle", "stale_lifecycle")]
        [InlineData("attempt", "stale_attempt")]
        [InlineData("surface", "stale_surface")]
        [InlineData(
            "coordinate",
            "stale_coordinate_space")]
        [InlineData("focus", "stale_focus")]
        [InlineData("modal", "stale_modal")]
        [InlineData(
            "panel",
            "stale_panel_instance")]
        [InlineData("document", "stale_document")]
        [InlineData(
            "semantic",
            "stale_semantic_node")]
        public async Task GenerationMismatchRejectsBeforeCallback(
            string generation,
            string expectedReason)
        {
            using var fixture = new Fixture();
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.ActivateWindow);
            switch (generation)
            {
                case "lifecycle":
                    action.ExpectedLifecycleGeneration++;
                    break;
                case "attempt":
                    action.ExpectedAttemptGeneration++;
                    break;
                case "surface":
                    action.ExpectedSurfaceEpoch++;
                    break;
                case "coordinate":
                    action.ExpectedCoordinateSpaceVersion++;
                    break;
                case "focus":
                    action.ExpectedFocusEpoch++;
                    break;
                case "modal":
                    action.ExpectedModalEpoch++;
                    break;
                case "panel":
                    action.ExpectedPanelInstanceId =
                        "panel_other_AAAAAAAAAAA";
                    break;
                case "document":
                    action.ExpectedDocumentGeneration++;
                    break;
                case "semantic":
                    action.ExpectedSemanticGeneration++;
                    break;
            }

            AgentActionPerformance result =
                await fixture.PerformAsync(action);

            AssertRejected(result, expectedReason);
            Assert.Equal(1, fixture.Ui.CallCount);
            Assert.Equal(0, fixture.ActivateCallCount);
        }

        [Fact]
        public async Task LeaseTargetScopeIsRevalidatedOnUi()
        {
            using var fixture = new Fixture();
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.ActivateWindow);
            WriteLease lease = fixture.Lease(
                AgentCapabilitiesV1.ActivateWindow,
                Fixture.OtherTargetId);

            AgentActionPerformance result =
                await fixture.Host.PerformAsync(
                    fixture.Context,
                    action,
                    lease,
                    CancellationToken.None);

            AssertRejected(
                result,
                "observation_scope_mismatch");
            Assert.Equal(1, fixture.Ui.CallCount);
            Assert.Equal(0, fixture.ActivateCallCount);
        }

        [Fact]
        public async Task QueuedUiWorkRevalidatesLatestRegistrySnapshot()
        {
            using var fixture = new Fixture();
            fixture.Ui.PauseBeforeCallback = true;
            Task<AgentActionPerformance> pending =
                fixture.PerformAsync(
                    AgentCapabilitiesV1.ActivateWindow);
            await fixture.Ui.Entered.Task;
            fixture.Snapshot = fixture.CreateSnapshot(
                surfaceEpoch: Fixture.SurfaceEpoch + 1);
            fixture.Ui.Release();

            AgentActionPerformance result = await pending;

            AssertRejected(result, "stale_surface");
            Assert.Equal(0, fixture.ActivateCallCount);
        }

        [Fact]
        public async Task SameHwndWithReusedOwnerIncarnationCannotSucceed()
        {
            using var fixture = new Fixture();
            fixture.AfterActivate = delegate
            {
                fixture.Snapshot = fixture.CreateSnapshot(
                    ownerProcess:
                        fixture.ProcessIdentity(
                            startTimeUtc:
                                new DateTimeOffset(
                                    2026,
                                    7,
                                    30,
                                    0,
                                    0,
                                    1,
                                    TimeSpan.Zero)));
            };

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.ActivateWindow);

            Assert.Equal(ActionOutcome.Unknown, result.Outcome);
            Assert.Equal(
                EvidenceKind.ReconciliationRequired,
                result.EvidenceKind);
            Assert.Equal(
                ReconcileKind.VisualAmbiguous,
                result.ReconcileKind);
            Assert.Equal("reconcile_required", result.ReasonCode);
            Assert.Equal(1, fixture.ActivateCallCount);
        }

        [Fact]
        public async Task OtherTargetPanelChangeDoesNotStaleAction()
        {
            using var fixture = new Fixture();
            fixture.Snapshot = fixture.CreateSnapshot(
                activePanelTargetId: Fixture.OtherTargetId,
                panelInstanceId:
                    Fixture.PanelInstanceId);
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.ActivateWindow);
            action.ExpectedPanelInstanceId = null;
            fixture.Snapshot = fixture.CreateSnapshot(
                activePanelTargetId: Fixture.OtherTargetId,
                panelInstanceId:
                    "panel_structured_other_AA");

            AgentActionPerformance result =
                await fixture.PerformAsync(action);

            Assert.Equal(
                ActionOutcome.InputDispatched,
                result.Outcome);
            Assert.Equal(1, fixture.ActivateCallCount);
        }

        [Fact]
        public async Task PreCancelledActionFailsWithoutUiOrHostCallback()
        {
            using var fixture = new Fixture();
            using var cancellation =
                new CancellationTokenSource();
            cancellation.Cancel();

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.ActivateWindow,
                    cancellation.Token);

            AssertRejected(result, "lease_revoked");
            Assert.Equal(0, fixture.Ui.CallCount);
            Assert.Equal(0, fixture.TotalHostCallbackCount);
        }

        [Fact]
        public async Task HostClosingMarshalFailsWithoutCallback()
        {
            using var fixture = new Fixture();
            fixture.Ui.HostAvailable = false;

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.SessionShutdown);

            AssertRejected(result, "lease_revoked");
            Assert.Equal(1, fixture.Ui.CallCount);
            Assert.Equal(0, fixture.PrepareSafeExitCallCount);
        }

        [Fact]
        public async Task DisposedHostFailsClosed()
        {
            using var fixture = new Fixture();
            fixture.Host.Dispose();

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.LifecycleReveal);

            AssertRejected(result, "lease_revoked");
            Assert.Equal(0, fixture.Ui.CallCount);
            Assert.Equal(0, fixture.RevealCallCount);
        }

        [Fact]
        public async Task CallbackExceptionDoesNotBecomeDispatchSuccess()
        {
            using var fixture = new Fixture();
            fixture.ThrowFromPrepareSafeExit = true;

            AgentActionPerformance result =
                await fixture.PerformAsync(
                    AgentCapabilitiesV1.SessionShutdown);

            AssertRejected(result, "internal_error");
            Assert.Equal(EvidenceKind.None, result.EvidenceKind);
        }

        [Fact]
        public async Task InvalidPanelArgumentsNeverReachRouterCallback()
        {
            using var fixture = new Fixture();
            ActionEnvelope action = fixture.Action(
                AgentCapabilitiesV1.PanelOpen);
            action.Arguments = JsonSerializer.SerializeToElement(
                new
                {
                    wrong = "help"
                });

            AgentActionPerformance result =
                await fixture.PerformAsync(action);

            AssertRejected(result, "arguments_invalid");
            Assert.Equal(1, fixture.Ui.CallCount);
            Assert.Equal(0, fixture.PanelOpenCallCount);
        }

        private static void AssertRejected(
            AgentActionPerformance result,
            string reasonCode)
        {
            Assert.Equal(ActionOutcome.Rejected, result.Outcome);
            Assert.Equal(EvidenceKind.None, result.EvidenceKind);
            Assert.Equal(reasonCode, result.ReasonCode);
            Assert.Null(result.ActualTargetId);
            Assert.False(result.FocusVerified);
        }

        private sealed class Fixture : IDisposable
        {
            internal const string SessionId =
                "session_structured_AAAAA";
            internal const string TargetId =
                "target_structured_AAAAAA";
            internal const string OtherTargetId =
                "target_structured_other_A";
            internal const string AttemptId =
                "attempt_structured_AAAAA";
            internal const string PanelInstanceId =
                "panel_structured_AAAAAAA";
            internal const ulong LifecycleGeneration = 7;
            internal const ulong AttemptGeneration = 3;
            internal const ulong SurfaceEpoch = 11;
            internal const ulong CoordinateSpaceVersion = 13;
            internal const ulong FocusEpoch = 17;
            internal const ulong ModalEpoch = 19;
            internal const ulong DocumentGeneration = 5;
            internal const ulong SemanticGeneration = 23;

            private readonly PrincipalCredential _principal;

            internal Fixture(bool includeActivator = true)
            {
                Ui = new RecordingUiMarshal();
                _principal = Principal();
                Context = new AgentRuntimeDispatchContext(
                    "connection_structured_AA",
                    _principal);
                Snapshot = CreateSnapshot();
                var activators =
                    new Dictionary<
                        string,
                        Func<
                            LauncherAgentExactTargetBinding,
                            bool>>(StringComparer.Ordinal);
                if (includeActivator)
                {
                    activators.Add(
                        TargetId,
                        Activate);
                }
                Host = new LauncherAgentStructuredActionHost(
                    () => Snapshot,
                    Ui.InvokeAsync,
                    activators,
                    PrepareSafeExit,
                    CompleteSafeExit,
                    AbortSafeExit,
                    Reveal,
                    Cancel,
                    TryOpenPanel);
            }

            internal RecordingUiMarshal Ui { get; }
            internal AgentRuntimeDispatchContext Context { get; }
            internal LauncherAgentStructuredActionHost Host
            {
                get;
            }
            internal SessionSurfaceRegistrySnapshot Snapshot
            {
                get;
                set;
            }
            internal bool ActivateAccepted { get; set; } = true;
            internal bool PanelAccepted { get; set; } = true;
            internal bool PrepareSafeExitAccepted { get; set; } =
                true;
            internal bool ThrowFromPrepareSafeExit { get; set; }
            internal Action AfterActivate { get; set; }
            internal int ActivateCallCount { get; private set; }
            internal int PrepareSafeExitCallCount
            {
                get;
                private set;
            }
            internal int CompleteSafeExitCallCount
            {
                get;
                private set;
            }
            internal int AbortSafeExitCallCount
            {
                get;
                private set;
            }
            internal int RevealCallCount { get; private set; }
            internal int CancelCallCount { get; private set; }
            internal int PanelOpenCallCount { get; private set; }
            internal string LastPanelName { get; private set; }
            internal string LastCompletedActionId
            {
                get;
                private set;
            }
            internal string LastAbortedActionId
            {
                get;
                private set;
            }
            internal LauncherAgentExactTargetBinding
                LastActivationBinding { get; private set; }
            internal bool AllCallbacksRanOnUi { get; private set; } =
                true;

            internal int TotalHostCallbackCount =>
                ActivateCallCount
                + PrepareSafeExitCallCount
                + CompleteSafeExitCallCount
                + AbortSafeExitCallCount
                + RevealCallCount
                + CancelCallCount
                + PanelOpenCallCount;

            internal Task<AgentActionPerformance> PerformAsync(
                string operation,
                CancellationToken cancellationToken = default)
            {
                return PerformAsync(
                    Action(operation),
                    cancellationToken);
            }

            internal Task<AgentActionPerformance> PerformAsync(
                ActionEnvelope action,
                CancellationToken cancellationToken = default)
            {
                return Host.PerformAsync(
                    Context,
                    action,
                    Lease(
                        action.Operation,
                        action.TargetId),
                    cancellationToken);
            }

            internal ActionEnvelope Action(
                string operation,
                string targetId = TargetId)
            {
                object arguments = operation switch
                {
                    AgentCapabilitiesV1.PanelOpen =>
                        new
                        {
                            panel = "help"
                        },
                    AgentCapabilitiesV1.SetValue =>
                        new
                        {
                            value = "value"
                        },
                    AgentCapabilitiesV1
                        .PerformSecondaryAction =>
                        new
                        {
                            action = "expand"
                        },
                    _ => new { }
                };
                return new ActionEnvelope
                {
                    ActionId =
                        "action_structured_AAAAA",
                    IdempotencyKey =
                        "idempotency_structured_A",
                    DeadlineMs = 1_000,
                    SessionId = SessionId,
                    ObservationGrantId =
                        "obsgrant_structured_AAA",
                    LeaseId = "lease_structured_AAAAAA",
                    ObservationId =
                        "observation_structured_A",
                    ExpectedLifecycleGeneration =
                        LifecycleGeneration,
                    TargetId = targetId,
                    ExpectedSurfaceEpoch = SurfaceEpoch,
                    ExpectedAttemptId = AttemptId,
                    ExpectedAttemptGeneration =
                        AttemptGeneration,
                    ExpectedPanelInstanceId =
                        PanelInstanceId,
                    ExpectedSemanticGeneration =
                        SemanticGeneration,
                    ExpectedDocumentGeneration =
                        DocumentGeneration,
                    ExpectedCoordinateSpaceVersion =
                        CoordinateSpaceVersion,
                    ExpectedFocusEpoch = FocusEpoch,
                    ExpectedModalEpoch = ModalEpoch,
                    SemanticSnapshotId =
                        "semantic_structured_AAA",
                    NodeId = operation
                            == AgentCapabilitiesV1.SetValue
                        || operation
                            == AgentCapabilitiesV1
                                .PerformSecondaryAction
                            ? "node_structured_AAAAAAA"
                            : null,
                    Operation = operation,
                    Arguments =
                        JsonSerializer.SerializeToElement(
                            arguments),
                    Reason = "structured host focused test"
                };
            }

            internal WriteLease Lease(
                string capability,
                string targetId)
            {
                return new WriteLease(
                    "lease_structured_AAAAAA",
                    _principal,
                    new WriteLeaseRequest
                    {
                        SessionId = SessionId,
                        LifecycleGeneration =
                            LifecycleGeneration,
                        Kind = capability switch
                        {
                            AgentCapabilitiesV1
                                .SessionShutdown =>
                                WriteLeaseKind.Shutdown,
                            AgentCapabilitiesV1.PanelOpen =>
                                WriteLeaseKind
                                    .StructuredAction,
                            _ => WriteLeaseKind.GuiInput
                        },
                        Capabilities =
                            new[] { capability },
                        TargetScope = new[] { targetId }
                    },
                    0,
                    60_000,
                    capability
                            is AgentCapabilitiesV1.SessionShutdown
                            or AgentCapabilitiesV1.PanelOpen
                        ? 1
                        : 20);
            }

            internal WriteLease Lease(
                string capability,
                string targetId,
                WriteLeaseKind kind)
            {
                return new WriteLease(
                    "lease_structured_AAAAAA",
                    _principal,
                    new WriteLeaseRequest
                    {
                        SessionId = SessionId,
                        LifecycleGeneration =
                            LifecycleGeneration,
                        Kind = kind,
                        Capabilities =
                            new[] { capability },
                        TargetScope = new[] { targetId }
                    },
                    0,
                    60_000,
                    kind is WriteLeaseKind.Shutdown
                        or WriteLeaseKind.StructuredAction
                        ? 1
                        : 20);
            }

            internal SessionSurfaceRegistrySnapshot
                CreateSnapshot(
                    ulong lifecycleGeneration =
                        LifecycleGeneration,
                    ulong surfaceEpoch = SurfaceEpoch,
                    string activePanelTargetId =
                        TargetId,
                    string panelInstanceId =
                        PanelInstanceId,
                    SessionProcessIdentity ownerProcess = null,
                    IReadOnlyCollection<InputMode> inputModes = null)
            {
                SessionProcessIdentity process =
                    ownerProcess ?? ProcessIdentity();
                var surface = new SessionSurfaceSnapshot(
                    TargetId,
                    SurfaceKind.Launcher,
                    AgentTargetSafetyKind.RuntimeOwned,
                    SessionSurfaceOwnerRelation
                        .RuntimeOverlay,
                    process,
                    1001,
                    null,
                    0,
                    surfaceEpoch,
                    CoordinateSpaceVersion,
                    FocusEpoch,
                    ModalEpoch,
                    SemanticGeneration,
                    DocumentGeneration,
                    Rect(),
                    Rect(),
                    Rect(),
                    96,
                    1,
                    visible: true,
                    minimized: false,
                    active: true,
                    observationModes: new[]
                    {
                        ObservationMode
                            .WindowGraphicsCapture
                    },
                    inputModes: inputModes ?? new[]
                    {
                        InputMode.SendInputGuarded
                    });
                var surfaces =
                    new List<SessionSurfaceSnapshot>
                    {
                        surface
                    };
                if (!string.Equals(
                        activePanelTargetId,
                        TargetId,
                        StringComparison.Ordinal))
                {
                    surfaces.Add(
                        new SessionSurfaceSnapshot(
                            OtherTargetId,
                            SurfaceKind.WebOverlay,
                            AgentTargetSafetyKind.RuntimeOwned,
                            SessionSurfaceOwnerRelation
                                .RuntimeOverlay,
                            process,
                            1002,
                            null,
                            0,
                            SurfaceEpoch,
                            CoordinateSpaceVersion,
                            FocusEpoch,
                            ModalEpoch,
                            SemanticGeneration,
                            DocumentGeneration,
                            Rect(),
                            Rect(),
                            Rect(),
                            96,
                            2,
                            visible: true,
                            minimized: false,
                            active: false,
                            observationModes: new[]
                            {
                                ObservationMode
                                    .WindowGraphicsCapture
                            },
                            inputModes:
                                Array.Empty<InputMode>()));
                }
                var session = new SessionSnapshot(
                    new SessionHostRegistration
                    {
                        SessionId = SessionId,
                        LifecycleGeneration =
                            lifecycleGeneration,
                        SessionMode =
                            SessionMode
                                .DeveloperInteractive,
                        Slot = "developer_slot",
                        AttemptId = AttemptId,
                        AttemptGeneration =
                            AttemptGeneration,
                        LauncherProcess = process,
                        CoreSha256 = new string('C', 64),
                        RuntimeQualification =
                            new RuntimeQualificationRegistration
                            {
                                RuntimeMode =
                                    RuntimeMode.FormalRuntime,
                                BuildIdentity =
                                    new string('A', 64),
                                PayloadClosure =
                                    new string('B', 64),
                                ActualProcessPath =
                                    process.ExecutablePath
                            },
                        Capabilities =
                            SupportedCapabilities()
                    },
                    surfaces,
                    "help",
                    panelInstanceId,
                    activePanelTargetId,
                    FocusEpoch,
                    ModalEpoch,
                    BlockingModalKind.None,
                    humanReauthorizationRequired: false,
                    TargetId,
                    desktopAvailable: true);
                return new SessionSurfaceRegistrySnapshot(
                    1,
                    new[] { session });
            }

            public void Dispose()
            {
                Host.Dispose();
            }

            private bool Activate(
                LauncherAgentExactTargetBinding binding)
            {
                RecordUiCallback();
                ActivateCallCount++;
                LastActivationBinding = binding;
                AfterActivate?.Invoke();
                return ActivateAccepted;
            }

            private bool PrepareSafeExit(string actionId)
            {
                RecordUiCallback();
                PrepareSafeExitCallCount++;
                if (ThrowFromPrepareSafeExit)
                    throw new InvalidOperationException(
                        "synthetic_safe_exit_failure");
                return PrepareSafeExitAccepted;
            }

            private void CompleteSafeExit(string actionId)
            {
                CompleteSafeExitCallCount++;
                LastCompletedActionId = actionId;
            }

            private void AbortSafeExit(string actionId)
            {
                AbortSafeExitCallCount++;
                LastAbortedActionId = actionId;
            }

            private void Reveal()
            {
                RecordUiCallback();
                RevealCallCount++;
            }

            private void Cancel()
            {
                RecordUiCallback();
                CancelCallCount++;
            }

            private bool TryOpenPanel(string panelName)
            {
                RecordUiCallback();
                PanelOpenCallCount++;
                LastPanelName = panelName;
                return PanelAccepted;
            }

            private void RecordUiCallback()
            {
                if (!Ui.InUiCallback)
                    AllCallbacksRanOnUi = false;
            }

            private static PrincipalCredential Principal()
            {
                return new PrincipalCredential(
                    "credential_structured_AA",
                    "principal_structured_AAA",
                    "client_structured_AAAAAA",
                    AgentPrincipalKind.DeveloperAgent,
                    AgentSessionMode
                        .DeveloperInteractive,
                    1,
                    0,
                    60_000,
                    DateTimeOffset.UtcNow,
                    SupportedCapabilities(),
                    new[] { "*" },
                    "test-enrollment",
                    null,
                    null,
                    null,
                    null);
            }

            private static string[] SupportedCapabilities()
            {
                return new[]
                {
                    AgentCapabilitiesV1.ActivateWindow,
                    AgentCapabilitiesV1.SessionShutdown,
                    AgentCapabilitiesV1.LifecycleReveal,
                    AgentCapabilitiesV1.LifecycleCancel,
                    AgentCapabilitiesV1.PanelOpen,
                    AgentCapabilitiesV1.SetValue,
                    AgentCapabilitiesV1
                        .PerformSecondaryAction,
                    AgentCapabilitiesV1.Click
                };
            }

            internal SessionProcessIdentity
                ProcessIdentity(
                    DateTimeOffset? startTimeUtc = null)
            {
                return new SessionProcessIdentity(
                    101,
                    startTimeUtc
                        ?? new DateTimeOffset(
                            2026,
                            7,
                            30,
                            0,
                            0,
                            0,
                            TimeSpan.Zero),
                    Path.GetFullPath(
                        Path.Combine(
                            Path.GetTempPath(),
                            "cf7-structured-host-tests",
                            "Launcher.Core.exe")));
            }

            private static SessionPhysicalRect Rect()
            {
                return new SessionPhysicalRect(
                    0,
                    0,
                    800,
                    600);
            }
        }

        private sealed class RecordingUiMarshal
        {
            private readonly TaskCompletionSource<bool> _release =
                new(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);

            internal int CallCount { get; private set; }
            internal bool HostAvailable { get; set; } = true;
            internal bool PauseBeforeCallback { get; set; }
            internal bool InUiCallback { get; private set; }
            internal TaskCompletionSource<bool> Entered { get; } =
                new(
                    TaskCreationOptions
                        .RunContinuationsAsynchronously);

            internal async Task<bool> InvokeAsync(
                Action callback,
                CancellationToken cancellationToken)
            {
                CallCount++;
                Entered.TrySetResult(true);
                if (!HostAvailable)
                    return false;
                if (PauseBeforeCallback)
                    await _release.Task.ConfigureAwait(false);
                if (cancellationToken.IsCancellationRequested)
                    return false;
                InUiCallback = true;
                try
                {
                    callback();
                }
                finally
                {
                    InUiCallback = false;
                }
                return true;
            }

            internal void Release()
            {
                _release.TrySetResult(true);
            }
        }
    }
}
