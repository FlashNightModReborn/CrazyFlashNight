using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class WindowManagerFocusRestoreTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ExactOwnedSourceActivatesOnlySessionRoot(bool returnPassiveRoot) => R1UiAdapterTests.Sta(() =>
    {
        using var owner = new Form();
        using var source = new SceneTransitionBackingForm(SceneTransitionPresentationPolicy.Interactive)
        {
            Owner = owner,
            ShowInTaskbar = false,
        };
        var api = new RootFocusApi { Foreground = source.Handle };
        var manager = new WindowManager(api, IntPtr.Zero);
        manager.ConfigurePassiveInput(new SessionInputAuthority(), owner);
        try
        {
            bool activated = returnPassiveRoot
                ? manager.ReturnPassiveRoot(source.Handle)
                : manager.ActivateSessionRootBeforeHide(source.Handle);
            Assert.True(activated);
            Assert.Equal(owner.Handle, api.Foreground);
            Assert.Equal(owner.Handle, Assert.Single(api.ForegroundWrites));
        }
        finally { manager.StopPassiveFocusAudit(); }
    });

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void StaleSourceCannotStealExternalOrNullForeground(bool nullForeground) => R1UiAdapterTests.Sta(() =>
    {
        using var owner = new Form();
        using var source = new Form { Owner = owner };
        using var external = new Form();
        var api = new RootFocusApi { Foreground = nullForeground ? IntPtr.Zero : external.Handle };
        var manager = new WindowManager(api, IntPtr.Zero);
        manager.ConfigurePassiveInput(new SessionInputAuthority(), owner);
        try
        {
            Assert.False(manager.ActivateSessionRootBeforeHide(source.Handle));
            Assert.False(manager.ReturnPassiveRoot(source.Handle));
            Assert.False(manager.ActivateSessionRootBeforeHide(IntPtr.Zero));
            if (!nullForeground) Assert.False(manager.ActivateSessionRootBeforeHide(external.Handle));
            Assert.Empty(api.ForegroundWrites);
        }
        finally { manager.StopPassiveFocusAudit(); }
    });

    [Fact]
    public void RootActivationRequiresAReadbackAndDoesNotRepeatWhenAlreadyAtRoot() => R1UiAdapterTests.Sta(() =>
    {
        using var owner = new Form();
        using var source = new SceneTransitionBackingForm(SceneTransitionPresentationPolicy.Interactive)
        {
            Owner = owner,
            ShowInTaskbar = false,
        };
        var api = new RootFocusApi { Foreground = source.Handle, ApplyForegroundWrite = false };
        var manager = new WindowManager(api, IntPtr.Zero);
        manager.ConfigurePassiveInput(new SessionInputAuthority(), owner);
        try
        {
            Assert.False(manager.ActivateSessionRootBeforeHide(source.Handle));
            Assert.Equal(source.Handle, api.Foreground);
            Assert.Equal(owner.Handle, Assert.Single(api.ForegroundWrites));
            api.Foreground = owner.Handle;
            Assert.True(manager.ActivateSessionRootBeforeHide(owner.Handle));
            Assert.Equal(owner.Handle, Assert.Single(api.ForegroundWrites));
        }
        finally { manager.StopPassiveFocusAudit(); }
    });

    [Fact]
    public void PassiveAdmissionRecognizesOwnedModifierAndNestedEditorOnlyInTheExactSession() => R1UiAdapterTests.Sta(() =>
    {
        using var root = new Form();
        using var otherRoot = new Form();
        using var task = new CF7Launcher.Tasks.ModifierTask(() => true, _ => true);
        using var modifier = new ModifierNativeSurface(root, "owned", "owned", task);
        using var unrelated = new Form { Owner=root };
        using var otherModifier = new ModifierNativeSurface(otherRoot, "owned", "owned", task);
        var manager = new WindowManager(new RootFocusApi(), IntPtr.Zero);
        manager.ConfigureSessionRoot(root);
        Rectangle bounds = new(-32000, -32000, 1016, 550);
        var authority = R1UiAdapterTests.StartGameAuthority();
        modifier.BindInputAuthority(authority, authority);
        Assert.True(modifier.ResumePanel(bounds));
        Assert.False(manager.IsPassiveInputWindow(modifier.Handle));
        Assert.True(modifier.TryPost("{\"type\":\"panel_cmd\",\"panel\":\"modifier\",\"cmd\":\"open\",\"initData\":{\"panelInstanceId\":\"current\",\"token\":\"current-token\"}}"));
        Assert.True(otherModifier.ResumePanel(bounds));
        Assert.True(otherModifier.TryPost("{\"type\":\"panel_cmd\",\"panel\":\"modifier\",\"cmd\":\"open\",\"initData\":{\"panelInstanceId\":\"other\",\"token\":\"other-token\"}}"));
        typeof(ModifierNativeSurface).GetMethod("SetTab", BindingFlags.Instance | BindingFlags.NonPublic)
            .Invoke(modifier, new object[] { "items" });
        var editor = (ModifierInputOverlay)typeof(ModifierNativeSurface).GetField("_inputOverlay",
            BindingFlags.Instance | BindingFlags.NonPublic).GetValue(modifier);
        Assert.True(manager.IsPassiveInputWindow(modifier.Handle));
        Assert.True(manager.IsPassiveInputWindow(editor.Handle));
        Assert.False(manager.IsPassiveInputWindow(unrelated.Handle));
        Assert.False(manager.IsPassiveInputWindow(otherModifier.Handle));
        Assert.False(manager.IsPassiveInputWindow(IntPtr.Zero));
        IntPtr modifierHandle = modifier.Handle, editorHandle = editor.Handle;
        modifier.SuspendPanel();
        Assert.False(manager.IsPassiveInputWindow(modifierHandle));
        Assert.False(manager.IsPassiveInputWindow(editorHandle));
    });

    [Fact]
    public void PassiveAuditMaintainsDisabledChildAndFailsClosedAfterSourceLoss() => R1UiAdapterTests.Sta(() =>
    {
        const int styleIndex = -16;
        const int disabled = 0x08000000;
        using var owner = new Form();
        using var source = new Panel();
        owner.Controls.Add(source);
        var manager = new WindowManager(new RootFocusApi(), source.Handle);
        using var process = Process.GetCurrentProcess();
        manager.TrackProcess(process);
        var authority = R1UiAdapterTests.StartGameAuthority();
        Assert.Equal(0, GetWindowLong(source.Handle, styleIndex) & disabled);

        manager.ConfigurePassiveInput(authority, owner);
        try
        {
            Assert.NotEqual(0, GetWindowLong(source.Handle, styleIndex) & disabled);
            Assert.True(manager.AuditPassiveFocus(out bool flashFocused));
            Assert.False(flashFocused);
            EnableWindow(source.Handle, true);
            Assert.Equal(0, GetWindowLong(source.Handle, styleIndex) & disabled);
            Assert.False(manager.AuditPassiveFocus(out flashFocused));
            Assert.False(flashFocused);
            Assert.Equal(0, GetWindowLong(source.Handle, styleIndex) & disabled);
            Assert.False(manager.RefreshPassiveFocusAdmission());
            Assert.NotEqual(0, GetWindowLong(source.Handle, styleIndex) & disabled);
            Assert.True(manager.AuditPassiveFocus(out _));

            manager.ResetEmbedState();
            Assert.False(manager.AuditPassiveFocus(out _));
            Assert.False(authority.IsGameKeyboardAdmitted);
        }
        finally { manager.StopPassiveFocusAudit(); }
    });

    [Fact]
    public void BackgroundRawFlashFocusBlocksBootstrapUntilTheSameGuardianIsSafe() => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, true, false);
        long epoch = fixture.Authority.CurrentKeyboardEpoch;
        Assert.True(fixture.Authority.ForegroundEligible);
        Assert.True(fixture.Window.ReadPassiveFocus(out bool rawFocus));
        Assert.True(rawFocus);
        Assert.Equal(epoch, fixture.Authority.CurrentKeyboardEpoch);
        Assert.True(fixture.Authority.ForegroundEligible);

        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add);
        Assert.Empty(fixture.Results);
        Assert.False(fixture.Authority.ForegroundEligible);
        Assert.False(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.False(fixture.Window.RefreshPassiveFocusAdmission());

        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, false, false);
        Assert.True(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.True(Assert.Single(fixture.Results));
        Assert.False(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.Empty(fixture.FocusApi.ForegroundWrites);
    });

    [Fact]
    public void AHealthyReadCanCompleteAnInitiallyUnknownBackgroundBootstrap() => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        fixture.Window.PassiveBootstrapFocusForTests = () => (false, false, false);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add);
        Assert.Empty(fixture.Results);

        fixture.Window.PassiveBootstrapFocusForTests = () => (true, false, true);
        Assert.False(fixture.Window.RefreshPassiveFocusAdmission());
        Assert.Empty(fixture.Results);

        fixture.Window.PassiveBootstrapFocusForTests = () => (true, false, false);
        Assert.True(fixture.Window.RefreshPassiveFocusAdmission());
        Assert.True(Assert.Single(fixture.Results));
        Assert.Equal(fixture.External, fixture.FocusApi.Foreground);
        Assert.Empty(fixture.FocusApi.ForegroundWrites);
    });

    [Fact]
    public void AnExternalRaceOrResetCannotCompleteTheQueuedGuardianRecovery() => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, true, false);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add);
        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        fixture.Window.PassiveBootstrapFocusForTests = () =>
        {
            fixture.FocusApi.Foreground = fixture.External;
            return (true, false, false);
        };
        Assert.False(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.Empty(fixture.Results);
        fixture.Window.ResetEmbedState();
        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        Assert.False(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.True(SpinWait.SpinUntil(() =>
        {
            Application.DoEvents();
            return fixture.Results.Count > 0;
        }, TimeSpan.FromSeconds(2)));
        Assert.False(Assert.Single(fixture.Results));
        Assert.Empty(fixture.FocusApi.ForegroundWrites);
    });

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void PendingEmbedCanUseTheRecreatedHostOrRootOfTheSameSession(bool recreateRoot) => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, true, false);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add);
        IntPtr original = recreateRoot ? fixture.Guardian.Handle : fixture.Host.Handle;
        IntPtr source = fixture.Source.Handle;
        // Keep the exact source alive while Windows replaces the managed host/root HWND.
        IntPtr oldHost = fixture.Host.Handle;
        SetParent(source, IntPtr.Zero);
        Assert.NotEqual(oldHost, GetParent(source));
        Assert.True(IsWindow(source));
        if (recreateRoot) fixture.Guardian.RecreateNativeHandle();
        else fixture.Host.RecreateNativeHandle();
        IntPtr recreated = recreateRoot ? fixture.Guardian.Handle : fixture.Host.Handle;
        Assert.NotEqual(original, recreated);

        fixture.FocusApi.Foreground = original;
        fixture.Window.RunEmbedWatchdogForTests();
        Assert.Equal(fixture.Host.Handle, GetParent(source));
        Assert.Empty(fixture.Results);
        Assert.False(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.Empty(fixture.FocusApi.ForegroundWrites);

        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, false, false);
        Assert.True(fixture.Window.RecoverPassiveBootstrapForTests());
        fixture.Window.RunEmbedWatchdogForTests();
        Assert.True(Assert.Single(fixture.Results));
        Assert.Equal(source, fixture.Window.FlashHwnd);
        Assert.Empty(fixture.FocusApi.ForegroundWrites);
    });

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void PendingEmbedWithLostSourceOrHostCompletesFailureOnceWhileExternal(bool destroySource) => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, true, false);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add);
        for (int sample = 0; sample < 32; sample++) fixture.Window.RunEmbedWatchdogForTests();
        Assert.Empty(fixture.Results);

        if (destroySource) fixture.Source.Dispose();
        else
        {
            // Isolate host loss from destruction of its old Win32 children.
            SetParent(fixture.Source.Handle, IntPtr.Zero);
            fixture.Host.Dispose();
        }
        fixture.Window.RunEmbedWatchdogForTests();
        fixture.Window.RunEmbedWatchdogForTests();
        Assert.False(Assert.Single(fixture.Results));
        Assert.Equal(fixture.External, fixture.FocusApi.Foreground);
        Assert.Empty(fixture.FocusApi.ForegroundWrites);
    });

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void UnsafeOrUnknownFocusOnlyExpiresAfterContinuousExactGuardianForeground(bool rawFocus) => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        fixture.Window.PassiveBootstrapFocusForTests = () => (rawFocus, rawFocus, false);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add);
        long grace = WindowManager.PassiveBootstrapForegroundGraceMs;
        fixture.Window.RunEmbedWatchdogForTests(0);
        fixture.Window.RunEmbedWatchdogForTests(grace * 20);
        Assert.Empty(fixture.Results);

        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        long firstReturn = grace * 21;
        fixture.Window.RunEmbedWatchdogForTests(firstReturn);
        fixture.Window.RunEmbedWatchdogForTests(firstReturn + grace - 1);
        Assert.Empty(fixture.Results);

        // A short genuine WinEvent excursion between watchdog samples resets the period.
        fixture.FocusApi.Foreground = fixture.External;
        fixture.Window.ObserveBootstrapForegroundForTests(fixture.External);
        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        fixture.Window.ObserveBootstrapForegroundForTests(fixture.Guardian.Handle);
        long secondReturn = firstReturn + grace;
        fixture.Window.RunEmbedWatchdogForTests(secondReturn);
        fixture.Window.RunEmbedWatchdogForTests(secondReturn + grace - 1);
        Assert.Empty(fixture.Results);
        fixture.Window.RunEmbedWatchdogForTests(secondReturn + grace);
        fixture.Window.RunEmbedWatchdogForTests(secondReturn + grace * 2);
        Assert.False(Assert.Single(fixture.Results));
        Assert.Empty(fixture.FocusApi.ForegroundWrites);
    });

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void RecreatingAnOwnedHandleDoesNotExtendTheExistingForegroundGrace(bool recreateRoot) => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        fixture.Window.PassiveBootstrapFocusForTests = () => (false, false, false);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add);
        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        const long firstReturn = 100;
        fixture.Window.RunEmbedWatchdogForTests(firstReturn);
        IntPtr oldHandle = recreateRoot ? fixture.Guardian.Handle : fixture.Host.Handle;
        IntPtr source = fixture.Source.Handle;
        SetParent(source, IntPtr.Zero);
        if (recreateRoot) fixture.Guardian.RecreateNativeHandle();
        else fixture.Host.RecreateNativeHandle();
        Assert.NotEqual(oldHandle, recreateRoot ? fixture.Guardian.Handle : fixture.Host.Handle);
        fixture.FocusApi.Foreground = fixture.Guardian.Handle;

        long deadline = firstReturn + WindowManager.PassiveBootstrapForegroundGraceMs;
        fixture.Window.RunEmbedWatchdogForTests(deadline - 1);
        Assert.Equal(fixture.Host.Handle, GetParent(source));
        Assert.Empty(fixture.Results);
        fixture.Window.RunEmbedWatchdogForTests(deadline);
        Assert.False(Assert.Single(fixture.Results));
    });

    [Theory]
    [InlineData(true, true, false)]
    [InlineData(true, false, true)]
    [InlineData(false, false, false)]
    public void PublicationRejectsAFreshUnsafeCommitSample(bool known, bool focused, bool enabled) => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, true, false);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add);
        fixture.FocusApi.Foreground = fixture.Guardian.Handle;

        int reads = 0;
        fixture.Window.PassiveBootstrapFocusForTests = () => ++reads < 3
            ? (true, false, false) : (known, focused, enabled);
        Assert.False(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.Equal(3, reads);
        Assert.Empty(fixture.Results);

        fixture.Window.PassiveBootstrapFocusForTests = () => (true, false, false);
        Assert.True(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.True(Assert.Single(fixture.Results));
    });

    [Fact]
    public void CancellingTheLaunchCannotPublishLateFocusRecovery() => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        using var cancellation = new CancellationTokenSource();
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, true, false);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add, cancellation.Token);

        cancellation.Cancel();
        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, false, false);
        Assert.False(fixture.Window.RecoverPassiveBootstrapForTests());
        fixture.Window.RunEmbedWatchdogForTests();
        Assert.False(Assert.Single(fixture.Results));
        Assert.Empty(fixture.FocusApi.ForegroundWrites);
    });

    [Theory]
    [InlineData("raw")]
    [InlineData("enabled")]
    [InlineData("unknown")]
    [InlineData("root")]
    [InlineData("retrack")]
    [InlineData("cancel")]
    public void HostCommitRejectsAPreparedTicketAfterTheWindowBoundaryChanges(string change) => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        using var cancellation = new CancellationTokenSource();
        var outcomes = new List<WindowManager.EmbedResult>();
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, true, false);
        fixture.Window.StageBootstrapOfferForTests(fixture.Host, cancellation.Token, outcomes.Add);
        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, false, false);
        Assert.True(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.Equal(WindowManager.EmbedResult.Prepared, Assert.Single(outcomes));

        if (change == "root")
        {
            IntPtr source = fixture.Source.Handle;
            SetParent(source, IntPtr.Zero);
            fixture.Guardian.RecreateNativeHandle();
            SetParent(source, fixture.Host.Handle);
            Assert.True(IsWindow(source));
        }
        else if (change == "retrack") fixture.Window.RetrackBootstrapSourceForTests();
        else if (change == "cancel") cancellation.Cancel();
        else fixture.Window.PassiveBootstrapFocusForTests = () => (change != "unknown", change == "raw", change == "enabled");

        Assert.False(fixture.Window.TryAcceptPassiveBootstrap(cancellation.Token,
            () => throw new InvalidOperationException("expired offer reached Host")));
        Assert.Single(outcomes);
    });

    [Fact]
    public void DuplicateStageKeepsThePendingTicketAndSameHwndRetrackRequiresFreshPublication() => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        using var first = new CancellationTokenSource();
        using var duplicate = new CancellationTokenSource();
        using var next = new CancellationTokenSource();
        var outcomes = new List<WindowManager.EmbedResult>();
        var discarded = new List<WindowManager.EmbedResult>();
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, true, false);
        fixture.Window.StageBootstrapOfferForTests(fixture.Host, first.Token, outcomes.Add);
        fixture.Window.StageBootstrapOfferForTests(fixture.Host, first.Token, discarded.Add);
        fixture.Window.StageBootstrapOfferForTests(fixture.Host, duplicate.Token, discarded.Add);
        Assert.Equal(WindowManager.EmbedResult.Superseded, Assert.Single(discarded));
        Assert.Empty(outcomes);

        fixture.FocusApi.Foreground = fixture.Guardian.Handle;
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, false, false);
        Assert.True(fixture.Window.RecoverPassiveBootstrapForTests());
        Assert.Equal(WindowManager.EmbedResult.Prepared, Assert.Single(outcomes));
        Assert.True(fixture.Window.TryAcceptPassiveBootstrap(first.Token, static () => { }));
        IntPtr source = fixture.Source.Handle;
        long firstEpoch = fixture.Window.EmbedEpoch;
        fixture.Window.RetrackBootstrapSourceForTests();
        Assert.Equal(source, fixture.Window.FlashHwnd);
        Assert.True(fixture.Window.EmbedEpoch > firstEpoch);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add, next.Token);
        Assert.True(Assert.Single(fixture.Results));
    });

    [Fact]
    public void PendingBootstrapClosePostsToOnlyTheExactDisabledChildWithoutActivation() => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        using var ticket = new CancellationTokenSource();
        using var replaced = new CancellationTokenSource();
        uint pid = (uint)Environment.ProcessId;
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, true, false);
        fixture.Window.StageBootstrapOfferForTests(fixture.Host, ticket.Token, _ => { });

        Assert.False(fixture.Window.TryGetUnpublishedBootstrapCloseTarget(replaced.Token, pid, out _));
        Assert.False(fixture.Window.TryGetUnpublishedBootstrapCloseTarget(ticket.Token, pid + 1, out _));
        Assert.True(fixture.Window.TryGetUnpublishedBootstrapCloseTarget(ticket.Token, pid, out var target));
        Assert.Equal(fixture.Source.Handle, target.Window);
        Assert.Equal(fixture.Host.Handle, target.Host);
        Assert.False(fixture.Window.FlashIsEnabled);

        ticket.Cancel();
        fixture.Window.CancelPassiveBootstrapPublication(ticket.Token, "test_close");
        Assert.False(fixture.Window.TryGetUnpublishedBootstrapCloseTarget(ticket.Token, pid, out _));
        Assert.False(ProcessManager.TryPostUnpublishedBootstrapClose(target, pid + 1));
        Assert.False(ProcessManager.TryPostUnpublishedBootstrapClose(target with { Host = fixture.Guardian.Handle }, pid));
        Application.DoEvents();
        Assert.Equal(0, fixture.Source.CloseMessages);

        Assert.True(ProcessManager.TryPostUnpublishedBootstrapClose(target, pid));
        Application.DoEvents();
        Assert.Equal(1, fixture.Source.CloseMessages);
        Assert.False(fixture.Window.FlashIsEnabled);
        Assert.Equal(fixture.External, fixture.FocusApi.Foreground);
        Assert.Empty(fixture.FocusApi.ForegroundWrites);
    });

    [Fact]
    public void PublishedBootstrapCannotBeCapturedForUnpublishedClose() => R1UiAdapterTests.Sta(() =>
    {
        using var fixture = new PassiveBootstrapFixture();
        using var ticket = new CancellationTokenSource();
        fixture.Window.PassiveBootstrapFocusForTests = () => (true, false, false);
        fixture.Window.StagePassiveBootstrapForTests(fixture.Host, fixture.Results.Add, ticket.Token);
        Assert.True(Assert.Single(fixture.Results));
        Assert.False(fixture.Window.TryGetUnpublishedBootstrapCloseTarget(ticket.Token, (uint)Environment.ProcessId, out _));
        Assert.Equal(0, fixture.Source.CloseMessages);
    });

    [Fact]
    public void WatchdogDropsTrackingWhenTheWindowStillExistsButTheProcessIsNotBound() => R1UiAdapterTests.Sta(() =>
    {
        using var source = new Panel();
        IntPtr handle = source.Handle;
        var manager = new WindowManager(new RootFocusApi(), handle);
        Assert.True(IsWindow(handle));
        manager.RunEmbedWatchdogForTests();
        Assert.Equal(IntPtr.Zero, manager.FlashHwnd);
        Assert.True(IsWindow(handle));
    });

    private sealed class PassiveBootstrapFixture : IDisposable
    {
        public RecreatingForm Guardian { get; } = new();
        public RecreatingPanel Host { get; } = new();
        public CloseRecordingPanel Source { get; } = new();
        public IntPtr External { get; } = new(0x9ab);
        public RootFocusApi FocusApi { get; } = new();
        public SessionInputAuthority Authority { get; } = R1UiAdapterTests.StartGameAuthority();
        public WindowManager Window { get; }
        public List<bool> Results { get; } = new();

        public PassiveBootstrapFixture()
        {
            Guardian.Controls.Add(Host);
            FocusApi.Foreground = External;
            // WinForms can create a hidden control under a parking HWND. Model
            // the production SetParent boundary before staging the passive audit.
            IntPtr host = Host.Handle;
            IntPtr flash = Source.Handle;
            if (GetParent(flash) != host) SetParent(flash, host);
            Assert.Equal(host, GetParent(flash));
            Window = new WindowManager(FocusApi, flash);
            using var process = Process.GetCurrentProcess();
            Window.TrackProcess(process);
            Window.ConfigurePassiveInput(Authority, Guardian);
        }

        public void Dispose()
        {
            Window.StopWatchdog();
            Window.StopPassiveFocusAudit();
            Source.Dispose();
            Guardian.Dispose();
        }
    }

    private sealed class RecreatingForm : Form
    {
        public void RecreateNativeHandle() => RecreateHandle();
    }

    private sealed class RecreatingPanel : Panel
    {
        public void RecreateNativeHandle() => RecreateHandle();
    }

    private sealed class CloseRecordingPanel : Panel
    {
        public int CloseMessages { get; private set; }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x0010)
            {
                CloseMessages++;
                return;
            }
            base.WndProc(ref message);
        }
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr window, int index);

    [DllImport("user32.dll")]
    private static extern bool EnableWindow(IntPtr window, bool enabled);

    [DllImport("user32.dll")]
    private static extern IntPtr GetParent(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr SetParent(IntPtr window, IntPtr parent);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr window);
}

internal sealed class RootFocusApi : IFlashFocusWindowApi
{
    internal IntPtr Foreground { get; set; }
    internal bool ApplyForegroundWrite { get; set; } = true;
    internal Action BeforeForegroundWrite { get; set; }
    internal List<IntPtr> ForegroundWrites { get; } = new();

    public IntPtr GetForegroundWindow() => Foreground;
    public bool SetForegroundWindow(IntPtr window)
    {
        BeforeForegroundWrite?.Invoke();
        ForegroundWrites.Add(window);
        if (ApplyForegroundWrite) Foreground = window;
        return true;
    }

    public bool IsWindow(IntPtr window) => window != IntPtr.Zero;
}
