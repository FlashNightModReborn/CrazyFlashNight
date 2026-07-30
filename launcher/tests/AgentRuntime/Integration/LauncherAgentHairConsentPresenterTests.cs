using System;
using System.IO;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;
using CF7Launcher.Tests.AgentRuntime.Security;
using CF7Launcher.Tests.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class LauncherAgentHairConsentPresenterTests
    {
        [Fact]
        public void AllowClosesHumanOnlySurfaceBeforeExactAcknowledgement()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                Task<AgentHairConsentPresentationResult> pending =
                    setup.Presenter.PresentAsync(
                        setup.Request(),
                        CancellationToken.None);

                WingsConsentForm form =
                    setup.Presenter.ActiveFormForTest;
                Assert.NotNull(form);
                Assert.True(form.Visible);
                Assert.Equal(
                    BlockingModalKind.HumanOnlySecurity,
                    setup.Controller.Snapshot
                        .BlockingModalKind);
                Assert.True(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);

                form.AllowButton.PerformClick();

                Assert.Null(
                    setup.Presenter.ActiveFormForTest);
                Assert.False(pending.IsCompleted);
                Assert.Equal(
                    BlockingModalKind.None,
                    setup.Controller.Snapshot
                        .BlockingModalKind);
                Assert.True(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);

                Application.DoEvents();

                AgentHairConsentPresentationResult result =
                    pending.GetAwaiter().GetResult();
                Assert.True(result.Approved);
                Assert.StartsWith(
                    "consentreceipt_",
                    result.ConsentReceipt,
                    StringComparison.Ordinal);
                Assert.Null(result.ReasonCode);
                Assert.False(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);
            });
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void HumanRefusalAcknowledgesOnlyAfterSurfaceIsClosed(
            bool dismiss)
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                Task<AgentHairConsentPresentationResult> pending =
                    setup.Presenter.PresentAsync(
                        setup.Request(),
                        CancellationToken.None);
                WingsConsentForm form =
                    setup.Presenter.ActiveFormForTest;

                if (dismiss)
                    form.Close();
                else
                    form.RejectButton.PerformClick();

                Assert.Null(
                    setup.Presenter.ActiveFormForTest);
                Assert.False(pending.IsCompleted);
                Assert.True(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);

                Application.DoEvents();

                AgentHairConsentPresentationResult result =
                    pending.GetAwaiter().GetResult();
                Assert.False(result.Approved);
                Assert.Null(result.ConsentReceipt);
                Assert.Equal(
                    "consent_required",
                    result.ReasonCode);
                Assert.False(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);
            });
        }

        [Fact]
        public void CancellationAndConcurrentPromptFailClosedWithoutAck()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                using var cancellation =
                    new CancellationTokenSource();
                Task<AgentHairConsentPresentationResult> first =
                    setup.Presenter.PresentAsync(
                        setup.Request(),
                        cancellation.Token);

                AgentHairConsentPresentationResult concurrent =
                    setup.Presenter.PresentAsync(
                            setup.Request(),
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();
                Assert.False(concurrent.Approved);
                Assert.Equal(
                    "human_intervention_required",
                    concurrent.ReasonCode);

                cancellation.Cancel();

                Assert.Null(
                    setup.Presenter.ActiveFormForTest);
                AgentHairConsentPresentationResult cancelled =
                    first.GetAwaiter().GetResult();
                Assert.False(cancelled.Approved);
                Assert.Null(cancelled.ConsentReceipt);
                Assert.Equal(
                    "human_intervention_required",
                    cancelled.ReasonCode);
                Assert.True(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);
            });
        }

        [Fact]
        public void LifecycleReplacementCannotAcknowledgeNewSession()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                Task<AgentHairConsentPresentationResult> pending =
                    setup.Presenter.PresentAsync(
                        setup.Request(),
                        CancellationToken.None);
                WingsConsentForm form =
                    setup.Presenter.ActiveFormForTest;

                setup.Controller.ReplaceLifecycle(
                    setup.Qualification,
                    "replacement_slot");
                form.AllowButton.PerformClick();
                Application.DoEvents();

                AgentHairConsentPresentationResult result =
                    pending.GetAwaiter().GetResult();
                Assert.False(result.Approved);
                Assert.Null(result.ConsentReceipt);
                Assert.Equal(
                    "human_intervention_required",
                    result.ReasonCode);
                Assert.Equal(
                    2UL,
                    setup.Controller.Snapshot
                        .LifecycleGeneration);
            });
        }

        [Fact]
        public void ExpiredAllowNeverProducesReceipt()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                Task<AgentHairConsentPresentationResult> pending =
                    setup.Presenter.PresentAsync(
                        setup.Request(),
                        CancellationToken.None);
                WingsConsentForm form =
                    setup.Presenter.ActiveFormForTest;
                setup.Clock.Advance(TimeSpan.FromSeconds(61));

                form.AllowButton.PerformClick();
                Application.DoEvents();

                AgentHairConsentPresentationResult result =
                    pending.GetAwaiter().GetResult();
                Assert.False(result.Approved);
                Assert.Null(result.ConsentReceipt);
                Assert.Equal(
                    "human_intervention_required",
                    result.ReasonCode);
                Assert.False(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);
            });
        }

        [Fact]
        public void RegistryPublicationFailureNeverShowsOrCompletesAllow()
        {
            RunSta(() =>
            {
                using var setup = new Setup();
                setup.Validator.RejectionReason =
                    "test_registry_rejected";

                AgentHairConsentPresentationResult result =
                    setup.Presenter.PresentAsync(
                            setup.Request(),
                            CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();

                Assert.False(result.Approved);
                Assert.Null(result.ConsentReceipt);
                Assert.Equal(
                    "human_intervention_required",
                    result.ReasonCode);
                Assert.Null(
                    setup.Presenter.ActiveFormForTest);
                Assert.Equal(
                    BlockingModalKind.None,
                    setup.Controller.Snapshot
                        .BlockingModalKind);
                Assert.False(
                    setup.Controller.Snapshot
                        .HumanReauthorizationRequired);
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
                    "Hair consent STA test timed out.");
            }
            if (failure != null)
                ExceptionDispatchInfo.Capture(failure).Throw();
        }

        private static string Id(string prefix)
        {
            return prefix + "_0123456789abcdefghijklmnop";
        }

        private sealed class Setup : IDisposable
        {
            private readonly PrincipalCredential _principal;
            private readonly HairAppearancePreview _preview;

            public Setup()
            {
                Clock = new ManualAgentRuntimeClock();
                OwnerForm = new Form
                {
                    Text = "CF7 consent test owner",
                    ShowInTaskbar = false,
                    StartPosition = FormStartPosition.Manual
                };
                OwnerForm.Show();
                _ = OwnerForm.Handle;

                Launcher = new SessionProcessIdentity(
                    Environment.ProcessId,
                    Clock.UtcNow,
                    Path.GetFullPath(
                        Environment.ProcessPath
                        ?? "Launcher.Tests.exe"));
                var flash = new SessionProcessIdentity(
                    Environment.ProcessId + 10,
                    Clock.UtcNow.AddSeconds(1),
                    Path.GetFullPath("FlashPlayer.exe"));
                RegistryOwner =
                    new SessionRegistryHostOwner(Launcher);
                Validator =
                    new RecordingSessionSurfaceHostValidator();
                Registry = new SessionSurfaceRegistry(
                    RegistryOwner,
                    Validator);
                Qualification =
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode =
                            RuntimeMode.FormalRuntime,
                        BuildIdentity = new string('a', 64),
                        PayloadClosure = new string('b', 64),
                        ActualProcessPath =
                            Launcher.ExecutablePath
                    };
                Controller = new SessionSurfaceHostController(
                    Registry,
                    RegistryOwner,
                    Qualification,
                    new string('c', 64),
                    new[]
                    {
                        AgentCapabilitiesV1
                            .AppearanceHairChange
                    });
                Controller.SetAttempt(
                    Id("attempt"),
                    flash,
                    "developer_slot",
                    3);

                var credentials =
                    new PrincipalCredentialAuthority(
                        Clock,
                        new TestPrincipalEnrollmentVerifier());
                _principal = credentials.IssueDeveloper(
                    new DeveloperEnrollmentEvidence
                    {
                        ClientInstanceId = Id("client"),
                        EnrollmentReceipt =
                            "developer-enrollment",
                        AllowedCapabilities = new[]
                        {
                            AgentCapabilitiesV1
                                .AppearanceHairChange
                        },
                        AllowedTargets = new[] { "*" }
                    });
                var binding = new HairSaveBinding(
                    Controller.SessionId,
                    1,
                    Id("attempt"),
                    1,
                    "developer_slot",
                    new string('d', 64));
                string transactionId = Id("transaction");
                string snapshotHash = new string('e', 64);
                string previewHash =
                    HairAppearanceHashing.ComputePreviewHash(
                        transactionId,
                        binding,
                        "hair.before",
                        "hair.after",
                        7,
                        9,
                        snapshotHash);
                _preview = new HairAppearancePreview(
                    transactionId,
                    binding,
                    "hair.before",
                    "hair.after",
                    7,
                    9,
                    snapshotHash,
                    previewHash,
                    Clock.UtcNow);
                Presenter =
                    new LauncherAgentHairConsentPresenter(
                        OwnerForm,
                        Clock,
                        Controller,
                        RegistryOwner);
            }

            public ManualAgentRuntimeClock Clock { get; }
            public Form OwnerForm { get; }
            public SessionProcessIdentity Launcher { get; }
            public SessionRegistryHostOwner RegistryOwner { get; }
            public RecordingSessionSurfaceHostValidator Validator
            {
                get;
            }
            public SessionSurfaceRegistry Registry { get; }
            public RuntimeQualificationRegistration Qualification
            {
                get;
            }
            public SessionSurfaceHostController Controller { get; }
            public LauncherAgentHairConsentPresenter Presenter
            {
                get;
            }

            public AgentHairConsentPresentationRequest Request()
            {
                return new AgentHairConsentPresentationRequest(
                    Id("connection"),
                    _principal,
                    Id("grant"),
                    Controller.SessionId,
                    1,
                    Id("target"),
                    _preview,
                    new LauncherTrustedHumanInteractionTicket(
                        Id("interaction"),
                        LauncherTrustedHumanInteractionPhase
                            .HairCommitConsent,
                        OwnerForm.Handle.ToInt64()));
            }

            public void Dispose()
            {
                Presenter.Dispose();
                if (!OwnerForm.IsDisposed)
                {
                    OwnerForm.Close();
                    OwnerForm.Dispose();
                }
                Application.DoEvents();
            }
        }
    }
}
