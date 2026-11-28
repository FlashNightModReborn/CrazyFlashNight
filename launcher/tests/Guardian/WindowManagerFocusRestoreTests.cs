using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
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
        using var editor = new ModifierInputOverlay(modifier);
        using var unrelated = new Form { Owner=root };
        using var otherModifier = new ModifierNativeSurface(otherRoot, "owned", "owned", task);
        var manager = new WindowManager(new RootFocusApi(), IntPtr.Zero);
        manager.ConfigureSessionRoot(root);
        Assert.True(manager.IsPassiveInputWindow(modifier.Handle));
        Assert.True(manager.IsPassiveInputWindow(editor.Handle));
        Assert.False(manager.IsPassiveInputWindow(unrelated.Handle));
        Assert.False(manager.IsPassiveInputWindow(otherModifier.Handle));
        Assert.False(manager.IsPassiveInputWindow(IntPtr.Zero));
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
        Assert.Empty(fixture.Results);
        Assert.Empty(fixture.FocusApi.ForegroundWrites);
    });

    private sealed class PassiveBootstrapFixture : IDisposable
    {
        public Form Guardian { get; } = new();
        public Panel Host { get; } = new();
        public IntPtr External { get; } = new(0x9ab);
        public RootFocusApi FocusApi { get; } = new();
        public SessionInputAuthority Authority { get; } = R1UiAdapterTests.StartGameAuthority();
        public WindowManager Window { get; }
        public List<bool> Results { get; } = new();

        public PassiveBootstrapFixture()
        {
            var source = new Panel();
            Guardian.Controls.Add(Host);
            Host.Controls.Add(source);
            FocusApi.Foreground = External;
            // WinForms can create a hidden control under a parking HWND. Model
            // the production SetParent boundary before staging the passive audit.
            IntPtr host = Host.Handle;
            IntPtr flash = source.Handle;
            if (GetParent(flash) != host) SetParent(flash, host);
            Assert.Equal(host, GetParent(flash));
            Window = new WindowManager(FocusApi, flash);
            using var process = Process.GetCurrentProcess();
            Window.TrackProcess(process);
            Window.ConfigurePassiveInput(Authority, Guardian);
        }

        public void Dispose()
        {
            Window.StopPassiveFocusAudit();
            Guardian.Dispose();
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
