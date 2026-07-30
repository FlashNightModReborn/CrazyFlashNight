using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Wings
{
    public sealed class WingsShellHostTests
    {
        [Fact]
        public void ProductionShellIsOwnedAndSupportsTextAndNotifications()
        {
            RunSta(() =>
            {
                using var setup = new ShellSetup();
                Assert.True(
                    setup.Host.TryShowShell(out string reason),
                    reason);
                WingsShellForm form = setup.Host.FormForTest;
                Assert.True(form.Visible);
                Assert.Same(setup.Owner, form.Owner);
                Assert.False(form.ShowInTaskbar);
                Assert.True(form.IsHandleCreated);

                WingsBackendResult guidance =
                    new DeterministicOfflineWingsBackend(
                        utcNow: () => WingsTestFixture.Now)
                        .Generate(
                            WingsGuidanceRequest.ForGuidance(
                                WingsTestFixture.SessionId,
                                setup.View,
                                WingsGuidanceDomain.Task,
                                "task.overview",
                                WingsTestFixture.VisibleContext(
                                    WingsGuidanceDomain.Task)));
                Assert.True(
                    setup.Host.TryAppendCheckedDialogue(
                        guidance.Output,
                        out reason),
                    reason);
                Assert.Contains(
                    "当前存档已经公开",
                    form.TranscriptText,
                    StringComparison.Ordinal);

                Assert.True(
                    setup.Host.TryNotify(
                        new WingsShellNotification(
                            WingsNotificationKind.Permission,
                            "等待 Launcher 中性授权确认。"),
                        out reason),
                    reason);
                Assert.Equal(
                    "等待 Launcher 中性授权确认。",
                    form.NotificationText);

                form.InputForTest.Text = "请给我任务建议";
                form.SendButton.PerformClick();
                Assert.Equal(
                    new[] { "请给我任务建议" },
                    setup.Actions.Dialogues);
                Assert.Equal(
                    0,
                    setup.Actions.WindowActivationRequests);
                Assert.Contains(
                    "你：请给我任务建议",
                    form.TranscriptText,
                    StringComparison.Ordinal);

                form.ConsentButton.PerformClick();
                Assert.Equal(
                    1,
                    setup.Actions.ConsentPresentationRequests);
                Assert.Null(setup.Port.ActiveFormForTest);
            });
        }

        [Fact]
        public void FixedActivationChoiceIsAdvertisedOnlyWhenRealPathIsAvailable()
        {
            RunSta(() =>
            {
                using var setup = new ShellSetup();
                Assert.True(setup.Host.TryShowShell(out _));
                WingsShellForm form = setup.Host.FormForTest;
                Assert.False(form.ActivateGameButton.Visible);

                setup.Actions
                    .StructuredWindowActivationAvailable = true;
                setup.Host.RefreshProjectedState();
                Assert.True(form.ActivateGameButton.Visible);
                Assert.True(form.ActivateGameButton.Enabled);

                form.ActivateGameButton.PerformClick();
                Assert.Equal(
                    1,
                    setup.Actions.WindowActivationRequests);

                Assert.True(setup.Host.TryPause(out _));
                Assert.False(form.ActivateGameButton.Enabled);
            });
        }

        [Fact]
        public void HidePauseAndResumeUseHostLifecycleCallbacksOnly()
        {
            RunSta(() =>
            {
                using var setup = new ShellSetup();
                Assert.True(setup.Host.TryShowShell(out _));
                WingsShellForm form = setup.Host.FormForTest;

                form.HideButton.PerformClick();
                Assert.False(form.Visible);
                Assert.Equal(
                    WingsPersonaPresentation.Hidden,
                    setup.Host.ShellSnapshot.Presentation);
                Assert.True(
                    setup.Host.ShellSnapshot
                        .NeutralObservationIndicatorVisible);
                Assert.True(setup.Owner.Visible);

                Assert.True(setup.Host.TryShowShell(out _));
                form.PauseButton.PerformClick();
                Assert.True(setup.Host.ShellSnapshot.Paused);
                Assert.False(
                    setup.Host.ShellSnapshot.CaptureRunning);
                Assert.False(
                    setup.Host.ShellSnapshot.InferenceRunning);
                Assert.Equal(
                    WingsShellEffect.StopCapture
                    | WingsShellEffect.StopInference
                    | WingsShellEffect.RevokeWriteLease
                    | WingsShellEffect.CancelPendingActions
                    | WingsShellEffect.SuspendReadGrant,
                    Assert.Single(
                        setup.Actions.PauseEffects));
                Assert.Equal("恢复", form.PauseButton.Text);

                form.PauseButton.PerformClick();
                Assert.False(setup.Host.ShellSnapshot.Paused);
                Assert.Equal(1, setup.Actions.FreshActivationRequests);
                Assert.False(
                    setup.Host.ShellSnapshot.ReadGrantActive);
            });
        }

        [Fact]
        public void ClosingShellDoesNotCloseOrCancelOwnerExit()
        {
            RunSta(() =>
            {
                using var setup = new ShellSetup();
                Assert.True(setup.Host.TryShowShell(out _));
                WingsShellForm shell = setup.Host.FormForTest;

                shell.Close();
                Application.DoEvents();
                Assert.False(shell.IsDisposed);
                Assert.False(shell.Visible);
                Assert.True(setup.Owner.Visible);
                Assert.False(setup.Owner.IsDisposed);

                Assert.True(setup.Host.TryShowShell(out _));
                bool ownerCloseObserved = false;
                setup.Owner.FormClosing += (_, args) =>
                {
                    ownerCloseObserved = true;
                    Assert.False(args.Cancel);
                };
                setup.Owner.Close();
                Application.DoEvents();
                Assert.True(ownerCloseObserved);
                Assert.True(setup.Owner.IsDisposed);
                Assert.True(shell.IsDisposed);
                Assert.False(
                    setup.Host.TryShowShell(out string reason));
                Assert.Equal(
                    "wings_shell_owner_unavailable",
                    reason);
            });
        }

        [Fact]
        public void ConsentHwndIsPublishedHumanOnlyBeforeVisibility()
        {
            RunSta(() =>
            {
                using var setup = new ShellSetup();
                TrustedNeutralConsentPrompt prompt =
                    Prompt(setup.View);
                Assert.True(
                    setup.Host.TryPresentConsent(
                        prompt,
                        out string reason),
                    reason);
                WingsConsentForm form =
                    setup.Port.ActiveFormForTest;
                Assert.NotNull(form);
                Assert.True(form.Visible);
                Assert.Same(setup.Owner, form.Owner);
                Assert.False(
                    setup.Publisher.WasVisibleAtPublish);

                WingsHumanOnlySurfaceDescriptor descriptor =
                    setup.Publisher.LastDescriptor;
                Assert.Equal(
                    AgentTargetSafetyKind
                        .HumanOnlySecuritySurface,
                    descriptor.SafetyKind);
                Assert.False(descriptor.IsObservationTarget);
                Assert.Empty(descriptor.ObservationModes);
                Assert.Empty(descriptor.InputModes);
                Assert.Equal(
                    form.Handle.ToInt64(),
                    descriptor.WindowHandle);
                Assert.Equal(
                    setup.Owner.Handle.ToInt64(),
                    descriptor.OwnerWindowHandle);

                SessionSurfaceHostRegistration registration =
                    descriptor.ToSessionRegistration(
                        CurrentProcessIdentity());
                Assert.Equal(
                    AgentTargetSafetyKind
                        .HumanOnlySecuritySurface,
                    registration.SafetyKind);
                Assert.Equal(
                    SessionSurfaceOwnerRelation
                        .HumanOnlySecurityReported,
                    registration.OwnerRelation);
                Assert.Empty(registration.ObservationModes);
                Assert.Empty(registration.InputModes);

                form.AllowButton.PerformClick();
                NeutralConsentDecisionIntent intent =
                    Assert.Single(setup.Decisions.Intents);
                Assert.Equal(prompt.PromptId, intent.PromptId);
                Assert.Equal(
                    NeutralConsentDecision.Allow,
                    intent.Decision);
                Assert.Equal(0, intent.PenaltyDelta);
                Assert.True(setup.Publisher.LastLease.Disposed);
                Assert.Null(setup.Port.ActiveFormForTest);
            });
        }

        [Fact]
        public void ConsentPublisherRejectionAndExpiryNeverShowSurface()
        {
            RunSta(() =>
            {
                using var setup = new ShellSetup();
                setup.Publisher.Accept = false;
                Assert.False(
                    setup.Host.TryPresentConsent(
                        Prompt(setup.View),
                        out string rejected));
                Assert.Equal("registry_rejected", rejected);
                Assert.Null(setup.Port.ActiveFormForTest);
                Assert.Empty(setup.Decisions.Intents);

                setup.Publisher.Accept = true;
                TrustedNeutralConsentPrompt expired = Prompt(
                    setup.View,
                    expiresAt: WingsTestFixture.Now);
                Assert.False(
                    setup.Host.TryPresentConsent(
                        expired,
                        out string stale));
                Assert.Equal(
                    "consent_prompt_not_current",
                    stale);
                Assert.Null(setup.Port.ActiveFormForTest);
            });
        }

        [Fact]
        public void ConsentSinkFailureClosesOneShotWithoutMintingAuthority()
        {
            RunSta(() =>
            {
                using var setup = new ShellSetup();
                setup.Decisions.Throw = true;
                Assert.True(
                    setup.Host.TryPresentConsent(
                        Prompt(setup.View),
                        out _));
                WingsConsentForm form =
                    setup.Port.ActiveFormForTest;
                form.AllowButton.PerformClick();

                Assert.Single(setup.Decisions.Intents);
                Assert.Equal(
                    "consent_broker_submission_failed",
                    setup.Port.LastSubmissionFailureReason);
                Assert.Null(setup.Port.ActiveFormForTest);
                Assert.True(setup.Publisher.LastLease.Disposed);
            });
        }

        [Fact]
        public void UncheckedDialogueAndPauseSinkFailureFailClosed()
        {
            RunSta(() =>
            {
                using var setup = new ShellSetup();
                LoreView rebound = WingsTestFixture.ReboundView(
                    setup.View,
                    "sv_4Cx8mN1qT6vK9rL2pD7hF");
                var badDraft = new WingsDraftOutput(
                    setup.View.Progress.SaveBindingId,
                    setup.View.LoreViewId,
                    WingsOutputPurpose.Guidance,
                    "没有 provenance 的内容。",
                    new[]
                    {
                        WingsTestFixture.Claim(
                            setup.View,
                            "guidance.task.visible-state-only")
                    });
                WingsCheckedOutput rejected =
                    new WingsOutputChecker().Check(
                        badDraft,
                        new WingsOutputCheckContext(
                            WingsTestFixture.SessionId,
                            rebound,
                            WingsGuidanceDomain.Task,
                            "task.overview",
                            WingsTestFixture.Now));
                Assert.False(rejected.Accepted);
                Assert.False(
                    setup.Host.TryAppendCheckedDialogue(
                        rejected,
                        out string dialogueReason));
                Assert.Equal(
                    "unchecked_dialogue_rejected",
                    dialogueReason);

                setup.Actions.ThrowOnPause = true;
                Assert.False(
                    setup.Host.TryPause(out string pauseReason));
                Assert.Equal(
                    "pause_effect_sink_failed",
                    pauseReason);
                Assert.True(setup.Host.ShellSnapshot.Paused);
                Assert.Contains(
                    "安全方向保持暂停",
                    setup.Host.FormForTest.NotificationText,
                    StringComparison.Ordinal);
            });
        }

        private static TrustedNeutralConsentPrompt Prompt(
            LoreView view,
            DateTimeOffset? expiresAt = null)
        {
            return new TrustedNeutralConsentPrompt(
                "cp_5Hm9qX2cV7nL1rT8kP4dB",
                WingsTestFixture.SessionId,
                view.Progress.SaveBindingId,
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
                expiresAt ?? WingsTestFixture.Now.AddMinutes(10),
                "仅本次会话；不导出。",
                "可随时在 Launcher 中撤销。",
                "Launcher Kill Switch 会立即停止。");
        }

        private static SessionProcessIdentity CurrentProcessIdentity()
        {
            return new SessionProcessIdentity(
                Environment.ProcessId,
                WingsTestFixture.Now,
                Path.GetFullPath(
                    Environment.ProcessPath
                    ?? "Launcher.Tests.exe"));
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
                throw new TimeoutException(
                    "Wings WinForms smoke thread timed out.");
            if (failure != null)
            {
                ExceptionDispatchInfo.Capture(failure).Throw();
            }
        }

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        private sealed class ShellSetup : IDisposable
        {
            public ShellSetup()
            {
                Owner = new Form
                {
                    Text = "CF7 owner",
                    ShowInTaskbar = false,
                    StartPosition = FormStartPosition.Manual
                };
                Owner.Show();
                _ = Owner.Handle;
                View = WingsTestFixture.View();
                Publisher = new RecordingPublisher();
                Decisions = new RecordingDecisionSink();
                Port = new WingsConsentPresentationPort(
                    Owner,
                    Publisher,
                    Decisions,
                    () => WingsTestFixture.Now);
                Actions = new RecordingShellActions();
                Host = new WingsShellHost(
                    Owner,
                    new WingsPersonaStateMachine(
                        View.Progress.StoryPhaseId,
                        1,
                        true,
                        WingsOperationState.Idle),
                    new WingsShellStateMachine(
                        WingsTestFixture.SessionId,
                        readGrantActive: true,
                        writeLeaseActive: true,
                        pendingActionsExist: true),
                    Actions,
                    Port);
            }

            public Form Owner { get; }
            public LoreView View { get; }
            public RecordingPublisher Publisher { get; }
            public RecordingDecisionSink Decisions { get; }
            public WingsConsentPresentationPort Port { get; }
            public RecordingShellActions Actions { get; }
            public WingsShellHost Host { get; }

            public void Dispose()
            {
                Host.Dispose();
                if (!Owner.IsDisposed)
                {
                    Owner.Close();
                    Owner.Dispose();
                }
                Application.DoEvents();
            }
        }

        private sealed class RecordingShellActions
            : IWingsShellHostActions
        {
            public bool StructuredWindowActivationAvailable
            {
                get;
                set;
            }
            public bool StructuredHairChangeAvailable
            {
                get;
                set;
            }
            public List<string> Dialogues { get; } = new();
            public List<WingsShellEffect> PauseEffects { get; } =
                new();
            public int FreshActivationRequests { get; private set; }
            public int ConsentPresentationRequests { get; private set; }
            public int WindowActivationRequests { get; private set; }
            public int HairChangeRequests { get; private set; }
            public bool ThrowOnPause { get; set; }

            public void SubmitDialogue(string text)
            {
                Dialogues.Add(text);
            }

            public void ApplyPauseEffects(
                WingsShellEffect requiredEffects)
            {
                PauseEffects.Add(requiredEffects);
                if (ThrowOnPause)
                    throw new InvalidOperationException("host failed");
            }

            public void RequestFreshActivation()
            {
                FreshActivationRequests++;
            }

            public void RequestNeutralConsentPresentation()
            {
                ConsentPresentationRequests++;
            }

            public void RequestActivateCurrentGameWindow()
            {
                WindowActivationRequests++;
            }

            public void RequestChangeHair()
            {
                HairChangeRequests++;
            }
        }

        private sealed class RecordingDecisionSink
            : INeutralConsentDecisionSink
        {
            public List<NeutralConsentDecisionIntent> Intents { get; } =
                new();
            public bool Throw { get; set; }

            public void SubmitHumanDecision(
                NeutralConsentDecisionIntent intent)
            {
                Intents.Add(intent);
                if (Throw)
                    throw new InvalidOperationException(
                        "broker rejected");
            }
        }

        private sealed class RecordingPublisher
            : IWingsHumanOnlySurfacePublisher
        {
            public bool Accept { get; set; } = true;
            public WingsHumanOnlySurfaceDescriptor LastDescriptor
            {
                get;
                private set;
            }
            public RecordingLease LastLease { get; private set; }
            public bool WasVisibleAtPublish { get; private set; }

            public bool TryPublish(
                WingsHumanOnlySurfaceDescriptor descriptor,
                out IWingsHumanOnlySurfaceLease lease,
                out string reasonCode)
            {
                LastDescriptor = descriptor;
                WasVisibleAtPublish = IsWindowVisible(
                    new IntPtr(descriptor.WindowHandle));
                if (!Accept)
                {
                    lease = null;
                    reasonCode = "registry_rejected";
                    return false;
                }
                LastLease = new RecordingLease(
                    descriptor);
                lease = LastLease;
                reasonCode = null;
                return true;
            }
        }

        private sealed class RecordingLease
            : IWingsHumanOnlySurfaceLease
        {
            internal RecordingLease(
                WingsHumanOnlySurfaceDescriptor descriptor)
            {
                TargetId = descriptor.TargetId;
                WindowHandle = descriptor.WindowHandle;
                OwnerWindowHandle =
                    descriptor.OwnerWindowHandle;
            }

            public bool Disposed { get; private set; }
            public string TargetId { get; }
            public long WindowHandle { get; }
            public long OwnerWindowHandle { get; }
            public ulong SurfaceEpoch => 1;

            public void Dispose()
            {
                Disposed = true;
            }
        }
    }
}
