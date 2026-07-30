using System;
using System.IO;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Transport;
using CF7Launcher.AgentRuntime.Wings;
using CF7Launcher.Tests.AgentRuntime.Security;
using CF7Launcher.Tests.AgentRuntime.Wings;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class LauncherWingsPlayerAssistAuthorityTests
    {
        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void HumanAllowBindsReadGrantToUnobservableNeutralIndicator(
            bool hideIndicator)
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.Controller.SetActivePanel(
                    "inventory",
                    Id("panel"),
                    Setup.WebTargetId);
                string receipt = null;
                setup.Authority.AuthorizationChanged +=
                    (_, change) =>
                    {
                        if (change.Authorized)
                            receipt = change.ReceiptId;
                    };

                TrustedNeutralConsentPrompt prompt =
                    setup.Authority.CreatePrompt();
                Assert.True(
                    setup.Port.TryPresent(
                        prompt,
                        out string reason),
                    reason);
                WingsConsentForm form =
                    setup.Port.ActiveFormForTest;
                Assert.NotNull(form);
                Assert.True(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);

                form.AllowButton.PerformClick();
                Assert.Null(setup.Port.ActiveFormForTest);
                Assert.Null(receipt);
                Application.DoEvents();

                Assert.NotNull(receipt);
                Assert.False(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);
                Assert.True(
                    setup.Authority.TryResolve(
                        receipt,
                        out TrustedNeutralPermissionFacts facts,
                        out string factsReason),
                    factsReason);
                Assert.Equal(
                    AgentSessionMode.PlayerAssist,
                    setup.IssuedCredential.SessionMode);
                Assert.Equal(
                    AgentPrincipalKind.WingsPersona,
                    setup.IssuedCredential.PrincipalKind);
                Assert.Equal(
                    receipt,
                    setup.IssuedCredential.IssuerReceipt);
                Assert.Equal(
                    receipt,
                    setup.Authority.GrantForTest
                        .ConsentReceipt);
                Assert.DoesNotContain(
                    AgentCapabilitiesV1.Click,
                    setup.IssuedCredential
                        .AllowedCapabilities);
                InvalidOperationException writeDenied =
                    Assert.Throws<InvalidOperationException>(
                        () => setup.WriteLeases.Acquire(
                            new WriteLeaseRequest
                            {
                                CredentialId =
                                    setup.IssuedCredential
                                        .CredentialId,
                                ClientInstanceId =
                                    setup.IssuedCredential
                                        .ClientInstanceId,
                                SessionId =
                                    setup.Controller.SessionId,
                                LifecycleGeneration =
                                    setup.Controller.Snapshot
                                        .LifecycleGeneration,
                                Kind =
                                    WriteLeaseKind.GuiInput,
                                Capabilities = new[]
                                {
                                    AgentCapabilitiesV1.Click
                                },
                                TargetScope =
                                    new[] { Setup.WebTargetId },
                                RequestedLifetime =
                                    TimeSpan.FromSeconds(10),
                                RequestedActionLimit = 1,
                                ConsentReceipt = receipt,
                                ArgumentBoundsHash =
                                    new string('A', 64)
                            }));
                Assert.Equal(
                    "capability_scope_denied",
                    writeDenied.Message);
                Assert.Equal(
                    new[]
                    {
                        "lore_public",
                        "window_metadata"
                    },
                    facts.GrantedScopes);
                Form indicator =
                    setup.Authority.IndicatorFormForTest;
                Assert.NotNull(indicator);
                Assert.True(indicator.Visible);
                Assert.NotSame(
                    setup.Port.ActiveFormForTest,
                    indicator);
                Assert.DoesNotContain(
                    setup.Controller.Snapshot.Surfaces,
                    surface => surface.WindowHandle
                        == indicator.Handle.ToInt64());

                WingsVisibleGuidanceContext context =
                    setup.Authority.VisibleContext(
                        WingsGuidanceDomain.Ui);
                Assert.Equal(
                    "inventory",
                    context.Fields[
                        "ui.visible-panel-id"]);

                if (hideIndicator)
                    indicator.Hide();
                else
                    indicator.Close();
                Application.DoEvents();
                Assert.False(
                    setup.Authority.TryResolve(
                        receipt,
                        out _,
                        out _));
                Assert.Equal(
                    CredentialState.Revoked,
                    setup.IssuedCredential.State);
            });
        }

        [Fact]
        public void UnattendedSessionCannotPromptOrShowWings()
        {
            RunSta(() =>
            {
                using var setup = new Setup(
                    SessionMode.UnattendedTest);

                InvalidOperationException promptError =
                    Assert.Throws<InvalidOperationException>(
                        () => setup.Authority.CreatePrompt());
                Assert.Equal(
                    "wings_observation_target_unavailable",
                    promptError.Message);
                Assert.Null(setup.Authority.GrantForTest);

                using LauncherWingsRuntimeHost host =
                    setup.CreateRuntimeHost(_ => null);
                Assert.False(
                    host.TryShow(out string showReason));
                Assert.Equal("wings_unavailable", showReason);
                Assert.Null(host.FormForTest);
            });
        }

        [Fact]
        public void RuntimeHostOwnsVirtualConnectionAcrossAllRevocationEdges()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                var resources =
                    new RecordingConnectionResources();
                using LauncherWingsRuntimeHost host =
                    setup.CreateRuntimeHost(
                        principal =>
                            new WingsVirtualAuthenticatedConnection(
                                principal,
                                resources,
                                new RejectingDispatcher(),
                                setup.Clock));
                setup.Authority.AuthorizationChanged +=
                    (_, change) =>
                        host.ApplyPlayerAssistAuthorization(
                            WingsTestFixture.View(),
                            change);
                Assert.True(host.TryShow(out string showReason),
                    showReason);
                Assert.True(
                    host.TryResume(out string resumeReason),
                    resumeReason);

                Allow(setup);
                string firstConnection =
                    host.VirtualConnectionIdForTest;
                Assert.NotNull(firstConnection);
                Assert.Equal(1, resources.RegisterCount);
                Assert.DoesNotContain(
                    AgentCapabilitiesV1.Click,
                    setup.IssuedCredential
                        .AllowedCapabilities);

                Assert.True(
                    host.TryHide(out string hideReason),
                    hideReason);
                Assert.Null(
                    host.VirtualConnectionIdForTest);
                Assert.Equal(1, resources.RevokeCount);

                Assert.True(host.TryShow(out showReason),
                    showReason);
                Assert.True(
                    host.TryResume(out resumeReason),
                    resumeReason);
                Allow(setup);
                Assert.NotNull(
                    host.VirtualConnectionIdForTest);
                setup.Authority.IndicatorFormForTest.Hide();
                Application.DoEvents();
                Assert.Null(
                    host.VirtualConnectionIdForTest);
                Assert.Equal(2, resources.RevokeCount);

                Allow(setup);
                Assert.NotNull(
                    host.VirtualConnectionIdForTest);
                setup.Controller.ReplaceLifecycle(
                    setup.Qualification,
                    "replacement_slot");
                Application.DoEvents();
                Assert.Null(
                    host.VirtualConnectionIdForTest);
                Assert.Equal(3, resources.RevokeCount);
            });
        }

        [Fact]
        public void LifecycleDriftAfterPromptCannotIssuePlayerCredential()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                bool authorized = false;
                setup.Authority.AuthorizationChanged +=
                    (_, change) =>
                        authorized |= change.Authorized;
                TrustedNeutralConsentPrompt prompt =
                    setup.Authority.CreatePrompt();
                Assert.True(
                    setup.Port.TryPresent(
                        prompt,
                        out _));

                setup.Controller.ReplaceLifecycle(
                    setup.Qualification,
                    "replacement_slot");
                setup.Port.ActiveFormForTest
                    .AllowButton.PerformClick();
                Application.DoEvents();

                Assert.False(authorized);
                Assert.Null(setup.IssuedCredential);
                Assert.Equal(
                    2UL,
                    setup.Controller.Snapshot
                        .LifecycleGeneration);
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
                    "Wings player-assist STA test timed out.");
            }
            if (failure != null)
                ExceptionDispatchInfo.Capture(failure).Throw();
        }

        private static string Id(string prefix)
        {
            return prefix + "_0123456789abcdefghijklmnop";
        }

        private static void Allow(Setup setup)
        {
            TrustedNeutralConsentPrompt prompt =
                setup.Authority.CreatePrompt();
            Assert.True(
                setup.Port.TryPresent(
                    prompt,
                    out string reasonCode),
                reasonCode);
            setup.Port.ActiveFormForTest
                .AllowButton.PerformClick();
            Application.DoEvents();
            Assert.NotNull(setup.IssuedCredential);
        }

        private sealed class Setup : IDisposable
        {
            public const string WebTargetId =
                "web_0123456789abcdefghijklmnop";
            private const string LauncherTargetId =
                "launcher_0123456789abcdefghijklmnop";
            private readonly string _tempRoot;

            public Setup(
                SessionMode sessionMode =
                    SessionMode.DeveloperInteractive)
            {
                Clock = new ManualAgentRuntimeClock();
                OwnerForm = new Form
                {
                    ShowInTaskbar = false
                };
                OwnerForm.Show();
                _ = OwnerForm.Handle;
                RegistryOwner =
                    SessionRegistryHostOwner
                        .CaptureCurrentLauncher();
                var registry = new SessionSurfaceRegistry(
                    RegistryOwner,
                    new AcceptingHostValidator());
                Qualification =
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode =
                            RuntimeMode.FormalRuntime,
                        BuildIdentity = new string('a', 64),
                        PayloadClosure = new string('b', 64),
                        ActualProcessPath =
                            RegistryOwner.LauncherProcess
                                .ExecutablePath
                    };
                Controller = new SessionSurfaceHostController(
                    registry,
                    RegistryOwner,
                    Qualification,
                    new string('c', 64),
                    new[]
                    {
                        AgentCapabilitiesV1.GetWindow
                    },
                    initialSlot:
                        sessionMode
                                == SessionMode.UnattendedTest
                            ? "cf7_agent_test"
                            : "launcher_idle",
                    sessionMode: sessionMode);
                var flash = new SessionProcessIdentity(
                    Environment.ProcessId + 100,
                    Clock.UtcNow.AddSeconds(1),
                    Path.GetFullPath("FlashPlayer.exe"));
                Controller.SetAttempt(
                    Id("attempt"),
                    flash,
                    sessionMode
                            == SessionMode.UnattendedTest
                        ? "cf7_agent_test"
                        : "developer_slot",
                    1);
                RegisterSurface(
                    LauncherTargetId,
                    SurfaceKind.Launcher,
                    SessionSurfaceOwnerRelation
                        .LauncherTopLevel,
                    null,
                    OwnerForm.Handle.ToInt64());
                RegisterSurface(
                    WebTargetId,
                    SurfaceKind.WebOverlay,
                    SessionSurfaceOwnerRelation
                        .LauncherOwned,
                    LauncherTargetId,
                    OwnerForm.Handle.ToInt64() + 1);

                _tempRoot = Path.Combine(
                    Path.GetTempPath(),
                    "cf7-wings-player-assist-tests",
                    Guid.NewGuid().ToString("N"));
                var verifier =
                    new HostPrincipalEnrollmentVerifier(
                        new PersistentDeveloperEnrollmentStore(
                            Directory.GetCurrentDirectory(),
                            Clock,
                            _tempRoot));
                Credentials =
                    new PrincipalCredentialAuthority(
                        Clock,
                        verifier);
                var grants = new ObservationGrantBroker(
                    Clock,
                    Credentials,
                    registry);
                WriteLeases = new WriteLeaseBroker(
                    Clock,
                    Credentials,
                    registry);
                Authority =
                    new LauncherWingsPlayerAssistAuthority(
                        OwnerForm,
                        Clock,
                        Controller,
                        RegistryOwner,
                        verifier,
                        Credentials,
                        grants,
                        WebTargetId,
                        WingsTestFixture.View());
                Authority.AuthorizationChanged +=
                    (_, change) =>
                    {
                        if (change.Authorized)
                            IssuedCredential =
                                Authority.CredentialForTest;
                    };
                Port = new WingsConsentPresentationPort(
                    OwnerForm,
                    new LauncherHumanOnlySurfacePublisher(
                        Controller,
                        RegistryOwner),
                    Authority,
                    () => Clock.UtcNow);
            }

            public ManualAgentRuntimeClock Clock { get; }
            public Form OwnerForm { get; }
            public SessionRegistryHostOwner RegistryOwner { get; }
            public RuntimeQualificationRegistration Qualification
            {
                get;
            }
            public SessionSurfaceHostController Controller { get; }
            public PrincipalCredentialAuthority Credentials { get; }
            public WriteLeaseBroker WriteLeases { get; }
            public LauncherWingsPlayerAssistAuthority Authority
            {
                get;
            }
            public WingsConsentPresentationPort Port { get; }
            public PrincipalCredential IssuedCredential { get; private set; }

            public LauncherWingsRuntimeHost CreateRuntimeHost(
                Func<
                    PrincipalCredential,
                    WingsVirtualAuthenticatedConnection>
                        connectionFactory)
            {
                LoreView view = WingsTestFixture.View();
                return new LauncherWingsRuntimeHost(
                    OwnerForm,
                    Controller,
                    RegistryOwner,
                    Controller.SessionId,
                    Id("wings"),
                    LauncherTargetId,
                    view,
                    1,
                    _ => WingsGuidanceRequest.ForGuidance(
                        Controller.SessionId,
                        view,
                        WingsGuidanceDomain.Task,
                        "task.overview",
                        WingsTestFixture.VisibleContext(
                            WingsGuidanceDomain.Task)),
                    effect =>
                    {
                        if (effect.HasFlag(
                                WingsShellEffect
                                    .SuspendReadGrant))
                        {
                            Authority.Suspend(
                                "wings_shell_paused");
                        }
                    },
                    () => { },
                    Authority.CreatePrompt,
                    Authority,
                    consentFactsAuthority: Authority,
                    utcNow: () => Clock.UtcNow,
                    ownedConsentAuthority: Authority,
                    virtualConnectionFactory:
                        connectionFactory);
            }

            public void Dispose()
            {
                Port.Dispose();
                Authority.Dispose();
                if (!OwnerForm.IsDisposed)
                {
                    OwnerForm.Close();
                    OwnerForm.Dispose();
                }
                Application.DoEvents();
            }

            private void RegisterSurface(
                string targetId,
                SurfaceKind kind,
                SessionSurfaceOwnerRelation relation,
                string ownerTargetId,
                long handle)
            {
                var bounds =
                    new SessionPhysicalRect(0, 0, 100, 100);
                Controller.SynchronizeSurface(
                    new SessionSurfaceHostRegistration
                    {
                        TargetId = targetId,
                        Kind = kind,
                        SafetyKind =
                            AgentTargetSafetyKind.RuntimeOwned,
                        OwnerRelation = relation,
                        OwnerProcess =
                            RegistryOwner.LauncherProcess,
                        WindowHandle = handle,
                        OwnerTargetId = ownerTargetId,
                        OwnerWindowHandle =
                            ownerTargetId == null
                                ? 0
                                : OwnerForm.Handle.ToInt64(),
                        BoundsPhysical = bounds,
                        ClientRectPhysical = bounds,
                        ContentRectPhysical = bounds,
                        Dpi = 96,
                        ZIndex =
                            kind == SurfaceKind.Launcher
                                ? 10
                                : 20,
                        Visible = true,
                        ObservationModes = new[]
                        {
                            ObservationMode
                                .WindowGraphicsCapture
                        },
                        InputModes =
                            Array.Empty<InputMode>()
                    });
            }
        }

        private sealed class RecordingConnectionResources
            : IAgentConnectionResourceAuthority
        {
            private bool _authorized;

            public int RegisterCount { get; private set; }
            public int RevokeCount { get; private set; }

            public void RegisterConnection(
                string connectionId,
                PrincipalCredential principal,
                Action<string> terminateConnection)
            {
                RegisterCount++;
                _authorized = true;
            }

            public bool IsDispatchAuthorized(
                string connectionId,
                PrincipalCredential principal)
            {
                return _authorized
                    && principal.State
                        == CredentialState.Active;
            }

            public Task RevokeAsync(
                string connectionId,
                AgentConnectionTermination termination)
            {
                RevokeCount++;
                _authorized = false;
                return Task.CompletedTask;
            }
        }

        private sealed class RejectingDispatcher
            : IAgentRuntimeMethodDispatcher
        {
            public Task<AgentRuntimeDispatchResult>
                DispatchAsync(
                    AgentRuntimeDispatchContext context,
                    AgentJsonRpcRequest request,
                    CancellationToken cancellationToken)
            {
                return Task.FromResult(
                    AgentRuntimeDispatchResult.Rejected(
                        "unsupported_for_surface"));
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
