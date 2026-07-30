using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;
using CF7Launcher.Tests.AgentRuntime.Wings;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class LauncherWingsRuntimeHostTests
    {
        [Fact]
        public void ShowRegistersOnlyOwnedWingsHwndAndStartsPaused()
        {
            RunSta(() =>
            {
                using var setup = new Setup();

                Assert.True(
                    setup.Host.TryShow(out string reason),
                    reason);

                WingsShellForm shell = setup.Host.FormForTest;
                Assert.True(shell.Visible);
                Assert.Same(setup.OwnerForm, shell.Owner);
                Assert.True(setup.Host.ShellSnapshot.Paused);
                Assert.Equal(0, setup.FreshActivationRequests);

                SessionSurfaceSnapshot surface =
                    Assert.Single(
                        setup.Controller.Snapshot.Surfaces,
                        item => item.TargetId
                            == Setup.WingsTargetId);
                Assert.Equal(SurfaceKind.WingsShell, surface.Kind);
                Assert.Equal(
                    AgentTargetSafetyKind.RuntimeOwned,
                    surface.SafetyKind);
                Assert.Equal(
                    SessionSurfaceOwnerRelation.LauncherOwned,
                    surface.OwnerRelation);
                Assert.Equal(
                    Setup.LauncherTargetId,
                    surface.OwnerTargetId);
                Assert.Equal(
                    shell.Handle.ToInt64(),
                    surface.WindowHandle);
                Assert.Equal(
                    setup.OwnerForm.Handle.ToInt64(),
                    surface.OwnerWindowHandle);
                Assert.Equal(
                    new[] {
                        ObservationMode.WindowGraphicsCapture
                    },
                    surface.ObservationModes);
                Assert.Equal(
                    new[] { InputMode.SendInputGuarded },
                    surface.InputModes);
            });
        }

        [Fact]
        public void UnqualifiedRuntimePublishesObserveOnlyWingsSurface()
        {
            RunSta(() =>
            {
                using var setup = new Setup(
                    RuntimeMode.UnqualifiedDev);

                Assert.True(
                    setup.Host.TryShow(out string reason),
                    reason);

                SessionSurfaceSnapshot surface =
                    Assert.Single(
                        setup.Controller.Snapshot.Surfaces,
                        item => item.TargetId
                            == Setup.WingsTargetId);
                Assert.Equal(
                    new[]
                    {
                        ObservationMode
                            .WindowGraphicsCapture
                    },
                    surface.ObservationModes);
                Assert.Empty(surface.InputModes);
            });
        }

        [Fact]
        public void ResumeRequiresExplicitFreshActivationAndHidePauses()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                Assert.True(setup.Host.TryShow(out _));

                Assert.True(
                    setup.Host.TryResume(out string resumeReason),
                    resumeReason);
                Assert.False(setup.Host.ShellSnapshot.Paused);
                Assert.Equal(1, setup.FreshActivationRequests);

                Assert.True(
                    setup.Host.TryHide(out string hideReason),
                    hideReason);
                Assert.True(setup.Host.ShellSnapshot.Paused);
                Assert.False(setup.Host.FormForTest.Visible);
                Assert.Equal(
                    WingsOperationState.Offline,
                    setup.Host.PersonaSnapshot.OperationState);
                Assert.DoesNotContain(
                    setup.Controller.Snapshot.Surfaces,
                    item => item.TargetId
                        == Setup.WingsTargetId);
                Assert.Contains(
                    setup.PauseEffects,
                    effect => effect.HasFlag(
                        WingsShellEffect.StopCapture)
                        && effect.HasFlag(
                            WingsShellEffect.StopInference)
                        && effect.HasFlag(
                            WingsShellEffect.RevokeWriteLease)
                        && effect.HasFlag(
                            WingsShellEffect.CancelPendingActions)
                        && effect.HasFlag(
                            WingsShellEffect.SuspendReadGrant));

                Assert.False(
                    setup.Host.TryResume(out string hiddenReason));
                Assert.Equal("wings_shell_hidden", hiddenReason);
            });
        }

        [Fact]
        public void PauseRevokesStructuredActionCoordinator()
        {
            RunSta(() =>
            {
                var actions =
                    new RecordingStructuredCoordinator();
                using var setup = new Setup(
                    structuredActions: actions);
                Assert.True(setup.Host.TryShow(out _));
                Assert.True(setup.Host.TryResume(out _));

                Assert.True(
                    setup.Host.TryPause(
                        out string pauseReason),
                    pauseReason);

                Assert.Contains(
                    "wings_shell_paused",
                    actions.Revocations);
            });
        }

        [Fact]
        public void OwnSecurityCardReadRetirementDoesNotCancelActionPath()
        {
            RunSta(() =>
            {
                var actions =
                    new RecordingStructuredCoordinator
                    {
                        IsPresentingOwnConsent = true
                    };
                using var setup = new Setup(
                    structuredActions: actions);

                setup.Host.ApplyPlayerAssistAuthorization(
                    setup.View,
                    new WingsPlayerAssistAuthorizationChangedEventArgs(
                        false,
                        null,
                        "security_surface_appeared"));
                Assert.Empty(actions.Revocations);

                setup.Host.ApplyPlayerAssistAuthorization(
                    setup.View,
                    new WingsPlayerAssistAuthorizationChangedEventArgs(
                        false,
                        null,
                        "wings_indicator_closed"));
                Assert.Contains(
                    "wings_indicator_closed",
                    actions.Revocations);
            });
        }

        [Fact]
        public void UserCloseImmediatelyPausesAndUnpublishes()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                Assert.True(setup.Host.TryShow(out _));
                Assert.True(setup.Host.TryResume(out _));

                setup.Host.FormForTest.Close();
                Application.DoEvents();

                Assert.False(setup.Host.FormForTest.Visible);
                Assert.False(setup.Host.FormForTest.IsDisposed);
                Assert.True(setup.Host.ShellSnapshot.Paused);
                Assert.Equal(
                    WingsOperationState.Offline,
                    setup.Host.PersonaSnapshot.OperationState);
                Assert.True(setup.OwnerForm.Visible);
                Assert.False(setup.OwnerForm.IsDisposed);
                Assert.DoesNotContain(
                    setup.Controller.Snapshot.Surfaces,
                    item => item.TargetId
                        == Setup.WingsTargetId);
            });
        }

        [Fact]
        public void GuidanceCanOnlyUseDeterministicOfflineBackend()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                Assert.True(setup.Host.TryShow(out _));
                Assert.True(setup.Host.TryResume(out _));

                WingsGuidanceRequest request =
                    setup.Guidance("任务建议");
                Assert.True(
                    setup.Host.TryGenerateOfflineAndPresent(
                        request,
                        out WingsBackendResult result,
                        out string reason),
                    reason);

                Assert.NotNull(result);
                Assert.Equal(
                    WingsBackendSource.OfflineReference,
                    result.Source);
                Assert.Null(result.ProviderId);
                Assert.Empty(result.DisclosedFieldKeys);
                Assert.Contains(
                    result.Output.Text,
                    setup.Host.FormForTest.TranscriptText,
                    StringComparison.Ordinal);
                Assert.Equal(
                    WingsOperationState.Idle,
                    setup.Host.PersonaSnapshot.OperationState);
            });
        }

        [Fact]
        public void ConsentIsHumanOnlyAndNeverBecomesAgentSurface()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                Assert.True(setup.Host.TryShow(out _));

                TrustedNeutralConsentPrompt prompt =
                    setup.Prompt();
                Assert.True(
                    setup.Host.TryPresentNeutralConsent(
                        prompt,
                        out string reason),
                    reason);
                WingsConsentForm consent =
                    setup.Host.ConsentFormForTest;
                Assert.NotNull(consent);
                Assert.True(consent.Visible);
                Assert.Same(setup.OwnerForm, consent.Owner);

                SessionSnapshot snapshot =
                    setup.Controller.Snapshot;
                Assert.Equal(
                    BlockingModalKind.HumanOnlySecurity,
                    snapshot.BlockingModalKind);
                Assert.All(
                    snapshot.Surfaces,
                    surface => Assert.Equal(
                        AgentTargetSafetyKind.RuntimeOwned,
                        surface.SafetyKind));
                Assert.DoesNotContain(
                    snapshot.Surfaces,
                    surface => surface.WindowHandle
                        == consent.Handle.ToInt64());

                consent.RejectButton.PerformClick();
                Application.DoEvents();
                NeutralConsentDecisionIntent decision =
                    Assert.Single(setup.Decisions);
                Assert.Equal(
                    NeutralConsentDecision.Reject,
                    decision.Decision);
                Assert.Null(setup.Host.ConsentFormForTest);
                Assert.Equal(
                    BlockingModalKind.None,
                    setup.Controller.Snapshot
                        .BlockingModalKind);
            });
        }

        [Fact]
        public void OwnerExitPausesUnpublishesAndNeverCancelsClose()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                Assert.True(setup.Host.TryShow(out _));
                Assert.True(setup.Host.TryResume(out _));
                WingsShellForm shell =
                    setup.Host.FormForTest;
                bool closingObserved = false;
                setup.OwnerForm.FormClosing += (_, args) =>
                {
                    closingObserved = true;
                    Assert.False(args.Cancel);
                };

                setup.OwnerForm.Close();
                Application.DoEvents();

                Assert.True(closingObserved);
                Assert.True(setup.Host.ShellSnapshot.Paused);
                Assert.True(setup.OwnerForm.IsDisposed);
                Assert.True(shell.IsDisposed);
                Assert.Null(setup.Host.FormForTest);
                Assert.DoesNotContain(
                    setup.Controller.Snapshot.Surfaces,
                    item => item.TargetId
                        == Setup.WingsTargetId);
            });
        }

        private static void RunSta(Action action)
        {
            Exception failure = null;
            var thread = new Thread(() =>
            {
                try
                {
                    action();
                }
                catch (Exception exception)
                {
                    failure = exception;
                }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            if (!thread.Join(TimeSpan.FromSeconds(20)))
            {
                throw new TimeoutException(
                    "Launcher Wings runtime test timed out.");
            }
            if (failure != null)
                ExceptionDispatchInfo.Capture(failure).Throw();
        }

        private sealed class Setup : IDisposable
        {
            public const string WingsTargetId =
                "target_wings_runtime_7pK4dB";
            public const string LauncherTargetId =
                "target_launcher_runtime_5Hm9qX";

            public Setup(
                RuntimeMode runtimeMode =
                    RuntimeMode.FormalRuntime,
                ILauncherWingsStructuredActionCoordinator
                    structuredActions = null)
            {
                OwnerForm = new Form
                {
                    Text = "CF7 Launcher owner",
                    ShowInTaskbar = false,
                    StartPosition = FormStartPosition.Manual
                };
                OwnerForm.Show();
                _ = OwnerForm.Handle;

                View = WingsTestFixture.View();
                RegistryOwner =
                    SessionRegistryHostOwner
                        .CaptureCurrentLauncher();
                var registry = new SessionSurfaceRegistry(
                    RegistryOwner,
                    new AcceptingHostValidator());
                Controller = new SessionSurfaceHostController(
                    registry,
                    RegistryOwner,
                    Qualification(runtimeMode),
                    new string('C', 64),
                    new[]
                    {
                        AgentCapabilitiesV1.GetWindow
                    });
                Controller.SynchronizeSurface(
                    LauncherRegistration());

                Host = new LauncherWingsRuntimeHost(
                    OwnerForm,
                    Controller,
                    RegistryOwner,
                    Controller.SessionId,
                    WingsTargetId,
                    LauncherTargetId,
                    View,
                    1,
                    Guidance,
                    effect => PauseEffects.Add(effect),
                    () => FreshActivationRequests++,
                    Prompt,
                    new RecordingDecisionSink(Decisions),
                    utcNow: () => WingsTestFixture.Now,
                    structuredActions:
                        structuredActions);
            }

            private RuntimeQualificationRegistration
                Qualification(RuntimeMode runtimeMode)
            {
                return runtimeMode
                    == RuntimeMode.UnqualifiedDev
                    ? new RuntimeQualificationRegistration
                    {
                        RuntimeMode =
                            RuntimeMode.UnqualifiedDev,
                        UnqualifiedReason =
                            "test_unqualified_runtime",
                        ActualProcessPath =
                            RegistryOwner.LauncherProcess
                                .ExecutablePath
                    }
                    : new RuntimeQualificationRegistration
                    {
                        RuntimeMode = runtimeMode,
                        BuildIdentity =
                            new string('A', 64),
                        PayloadClosure =
                            new string('B', 64),
                        ActualProcessPath =
                            RegistryOwner.LauncherProcess
                                .ExecutablePath
                    };
            }

            public Form OwnerForm { get; }
            public LoreView View { get; }
            public SessionRegistryHostOwner RegistryOwner { get; }
            public SessionSurfaceHostController Controller { get; }
            public LauncherWingsRuntimeHost Host { get; }
            public List<WingsShellEffect> PauseEffects { get; } =
                new();
            public List<NeutralConsentDecisionIntent> Decisions
            {
                get;
            } = new();
            public int FreshActivationRequests { get; private set; }

            public WingsGuidanceRequest Guidance(string text)
            {
                _ = text;
                return WingsGuidanceRequest.ForGuidance(
                    Controller.SessionId,
                    View,
                    WingsGuidanceDomain.Task,
                    "task.overview",
                    WingsTestFixture.VisibleContext(
                        WingsGuidanceDomain.Task));
            }

            public TrustedNeutralConsentPrompt Prompt()
            {
                return new TrustedNeutralConsentPrompt(
                    "cp_runtime_5Hm9qX2cV7nL",
                    Controller.SessionId,
                    View.Progress.SaveBindingId,
                    "Wings",
                    "当前游戏会话",
                    "当前佣兵存档",
                    new[]
                    {
                        new NeutralConsentScopeDisplay(
                            "observation.screen",
                            "查看当前游戏窗口"),
                        new NeutralConsentScopeDisplay(
                            "guidance.read-only",
                            "根据可见状态提供建议")
                    },
                    "只观察当前画面，不执行输入。",
                    WingsTestFixture.Now.AddMinutes(-1),
                    WingsTestFixture.Now.AddMinutes(10),
                    "仅本次会话；不导出。",
                    "可随时在 Launcher 中撤销。",
                    "Launcher Kill Switch 会立即停止。");
            }

            public void Dispose()
            {
                Host.Dispose();
                if (!OwnerForm.IsDisposed)
                {
                    OwnerForm.Close();
                    OwnerForm.Dispose();
                }
                Application.DoEvents();
            }

            private SessionSurfaceHostRegistration
                LauncherRegistration()
            {
                var bounds = new SessionPhysicalRect(
                    OwnerForm.Bounds.X,
                    OwnerForm.Bounds.Y,
                    Math.Max(1, OwnerForm.Bounds.Width),
                    Math.Max(1, OwnerForm.Bounds.Height));
                return new SessionSurfaceHostRegistration
                {
                    TargetId = LauncherTargetId,
                    Kind = SurfaceKind.Launcher,
                    SafetyKind =
                        AgentTargetSafetyKind.RuntimeOwned,
                    OwnerRelation =
                        SessionSurfaceOwnerRelation
                            .LauncherTopLevel,
                    OwnerProcess =
                        RegistryOwner.LauncherProcess,
                    WindowHandle =
                        OwnerForm.Handle.ToInt64(),
                    BoundsPhysical = bounds,
                    ClientRectPhysical = bounds,
                    ContentRectPhysical = bounds,
                    Dpi = OwnerForm.DeviceDpi,
                    ZIndex = 10,
                    Visible = true,
                    ObservationModes = new[]
                    {
                        ObservationMode.WindowGraphicsCapture
                    },
                    InputModes = Array.Empty<InputMode>()
                };
            }
        }

        private sealed class RecordingDecisionSink
            : INeutralConsentDecisionSink
        {
            private readonly List<NeutralConsentDecisionIntent>
                _decisions;

            public RecordingDecisionSink(
                List<NeutralConsentDecisionIntent> decisions)
            {
                _decisions = decisions;
            }

            public void SubmitHumanDecision(
                NeutralConsentDecisionIntent intent)
            {
                _decisions.Add(intent);
            }
        }

        private sealed class RecordingStructuredCoordinator
            : ILauncherWingsStructuredActionCoordinator
        {
            public bool IsAvailable => true;
            public bool IsHairChangeAvailable => true;
            public bool IsPresentingOwnConsent { get; set; }
            public ITrustedActionResultAuthority ResultAuthority
            {
                get;
            } = new RejectingActionResultAuthority();
            public List<string> Revocations { get; } = new();

            public event EventHandler ExecutionStarting;

            public Task<LauncherWingsStructuredActionResult>
                ActivateCurrentGameWindowAsync(
                    CancellationToken cancellationToken)
            {
                return Task.FromResult(
                    LauncherWingsStructuredActionResult
                        .Rejected("consent_required"));
            }

            public Task<LauncherWingsStructuredActionResult>
                ChangeHairAsync(
                    CancellationToken cancellationToken)
            {
                return Task.FromResult(
                    LauncherWingsStructuredActionResult
                        .Rejected("consent_required"));
            }

            public void CompleteResultProjection(
                string actionReceiptId)
            {
            }

            public void Revoke(string reasonCode)
            {
                Revocations.Add(reasonCode);
            }

            public void Dispose()
            {
            }
        }

        private sealed class RejectingActionResultAuthority
            : ITrustedActionResultAuthority
        {
            public bool TryResolve(
                string receiptId,
                out TrustedActionResultFacts facts,
                out string reasonCode)
            {
                facts = null;
                reasonCode = "wings_result_unavailable";
                return false;
            }
        }

        private sealed class AcceptingHostValidator
            : ISessionSurfaceHostValidator
        {
            public bool ValidateSession(
                SessionRegistryHostOwner hostOwner,
                SessionHostRegistration registration,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }

            public bool ValidateAttemptProcess(
                SessionRegistryHostOwner hostOwner,
                SessionProcessIdentity flashProcess,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }

            public bool ValidateSurface(
                SessionRegistryHostOwner hostOwner,
                SessionSurfaceValidationContext context,
                SessionSurfaceHostRegistration registration,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }
        }
    }
}
