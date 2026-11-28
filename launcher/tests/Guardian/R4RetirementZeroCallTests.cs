using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class R4RetirementZeroCallTests
{
    private const BindingFlags Declared = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly;
    private const int NoActivate = 0x08000000;

    [Fact]
    public void CoreAndNativeDeliveryHaveNoFlashFocusRepairEntryPoints()
    {
        const string retired = @"\b(?:RestoreFlashInputFocus\w*|RestoreFlashInnerFocusOnce|HandoffFlashFocus\w*|SuspendFlashKeyboard\w*|ResumeFlashKeyboard|ObserveStrictKeyboard|DeferFlashFocus|DeliverFlashInnerFocus|AttachThreadInput)\b";
        Assert.DoesNotMatch(retired, MemberNames(typeof(WindowManager)));
        Assert.DoesNotMatch(retired, MemberNames(typeof(IFlashFocusWindowApi)));
        Assert.Null(typeof(WindowManager).Assembly.GetType("CF7Launcher.Guardian.PanelFocusRestoreGate"));
        Assert.DoesNotMatch(@"\b(?:ReturnGameKeyboard|TextInputFocusChanged)\b",
            MemberNames(typeof(ModifierNativeSurface)));

        foreach (string file in new[]
        {
            "launcher/src/Program.cs",
            "launcher/src/Guardian/WindowManager.cs",
            "launcher/src/Guardian/WindowManager.CloseFocus.cs",
            "launcher/src/Guardian/GuardianForm.cs",
            "launcher/src/Guardian/PanelHostController.CloseTransaction.cs",
            "launcher/src/Guardian/PanelHostController.TransitionSettlement.cs",
            "launcher/src/Guardian/WebOverlayForm.cs",
            "launcher/src/Guardian/WorldCompositor/WorldCompositorController.cs",
            "launcher/src/Guardian/WorldCompositor/WorldCompositionSurface.cs",
            "launcher/native/world-compositor/InputBridge.cpp",
        })
            Assert.DoesNotMatch(retired, ReadSource(file));

        string windowManager = ReadSource("launcher/src/Guardian/WindowManager.cs")
            + ReadSource("launcher/src/Guardian/WindowManager.CloseFocus.cs");
        Assert.DoesNotMatch(@"\bSetFocus\s*\(", windowManager);
        Assert.DoesNotMatch(@"\bSetFocus\s*\(", ReadSource("launcher/native/world-compositor/InputBridge.cpp"));
        Assert.DoesNotMatch(@"\bworld_pointer\b",
            ReadSource("launcher/src/Program.cs"));
        Assert.DoesNotMatch(@"\b(?:AllKeysReleased|GetAsyncKeyState)\b",
            ReadSource("launcher/src/Guardian/WorldCompositor/WorldCompositorController.cs"));
    }

    [Theory]
    [InlineData(540)]
    [InlineData(482)]
    public void RenderSelectionAndOrdinaryRefreshPreserveHeldGameplayKey(int height)
    {
        using var owner = new Form();
        using var compositor = WorldCompositorTests.RenderController(owner);
        var authority = R1UiAdapterTests.StartGameAuthority();
        compositor.ConfigurePassiveInput(authority);
        Assert.True(authority.ObserveKey((int)Keys.W, true));
        long epoch = authority.CurrentKeyboardEpoch;
        string held = authority.AdmittedHex;

        var selection = new RenderSelection(3, height, "LOW", 2);
        compositor.ApplyRenderSelection(selection, 0, _ => { });
        compositor.BeginCaptureWait(CaptureWaitReason.RenderRefresh, hold: false);
        compositor.ApplyRenderSelection(selection, 0, _ => { });
        Assert.True(compositor.CaptureInputBlocked);
        Assert.False(compositor.KeyboardBlockRequested);
        Assert.True(authority.IsGameKeyboardAdmitted);
        Assert.Equal(epoch, authority.CurrentKeyboardEpoch);
        Assert.Equal(held, authority.AdmittedHex);
        Assert.False(authority.IsSuppressed((int)Keys.W));

        compositor.EndCaptureWait();
        Assert.True(authority.IsGameKeyboardAdmitted);
        Assert.Equal(epoch, authority.CurrentKeyboardEpoch);
    }

    [Fact]
    public void CoreStartupHasNoColdInputHostOrSecondGuardProcess()
    {
        Assert.Null(typeof(WindowManager).Assembly.GetType("CF7Launcher.Guardian.HotkeyGuard"));
        Assert.DoesNotMatch(@"UnifiedCandidateInvocation|UnifiedInputHost|--hotkey-guard",
            ReadSource("launcher/src/Program.cs"));
        Assert.DoesNotMatch(@"\b(?:SetTextInputActive|SetActivationProbe|_textInputActive|_isAppActive)\b",
            MemberNames(typeof(KeyboardHook)));
        Assert.DoesNotMatch(@"\b(?:TryDeferCloseForInputRelease|PollPhysicalClose\w*|DeferredPhysicalClose)\b",
            MemberNames(typeof(PanelHostController)));
    }

    [Fact]
    public void FirstExternalKeyAfterForegroundLossPassesThroughAndRevokesImmediately()
    {
        var authority = R1UiAdapterTests.StartGameAuthority();
        bool foreground = true;
        int shortcuts = 0;
        var posted = new Queue<Action>();
        using var hook = new KeyboardHook
        {
            LiveForegroundProbeForTests = () => foreground,
            ReadAsyncKeyState = _ => 0,
        };
        hook.BindPassiveInput(authority, () => foreground, postShortcut: posted.Enqueue);
        hook.RegisterAction((uint)Keys.W, () => shortcuts++);

        Assert.False(KeyboardHookStateTests.Edge(hook, (uint)Keys.W, down: true));
        Assert.True(authority.IsPhysicallyDown((int)Keys.W));
        Assert.True(authority.IsGameKeyboardAdmitted);
        foreground = false;
        Assert.False(KeyboardHookStateTests.Edge(hook, (uint)Keys.Tab, down: true));
        Assert.False(authority.ForegroundEligible);
        Assert.False(authority.IsGameKeyboardAdmitted);
        Assert.True(authority.IsSuppressed((int)Keys.W));
        Assert.False(authority.IsPhysicallyDown((int)Keys.Tab));
        R1UiAdapterTests.SettleGameCancel(authority);

        Assert.False(KeyboardHookStateTests.Edge(hook, (uint)Keys.W, down: false));
        Assert.False(authority.IsSuppressed((int)Keys.W));
        Assert.False(KeyboardHookStateTests.Edge(hook, (uint)Keys.Escape, down: true));
        Assert.Empty(posted);
        Assert.Equal(0, shortcuts);
    }

    [Fact]
    public void OnlyGuardianIsATaskbarActivatableRootAmongGamePresentationWindows() => R1UiAdapterTests.Sta(() =>
    {
        using var root = new GuardianForm();
        try
        {
            using var modifierTask = new ModifierTask(() => true, _ => true);
            using var modifier = new ModifierNativeSurface(root, "owned", "owned", modifierTask);
            using var hud = new NativeHudOverlay(root, root.FlashHostPanel, presentationEnabled: false);
            using var hitNumbers = new HitNumberOverlay(root, root.FlashHostPanel);
            using var cursor = new DesktopCursorOverlay(root, null);
            using var backdrop = new NativePanelBackdrop(root);
            using var shield = new InputShieldForm(root, root.FlashHostPanel);
            using var composition = new CompositionHelpSurface(root, "owned", "owned");
            using var background = new CompositionHelpSurface(root, "owned", "owned",
                transition: true, presentationPolicy: SceneTransitionPresentationPolicy.ArenaWorker);

            Form[] passive = { modifier, hud, hitNumbers, cursor, backdrop, shield, composition, background };
            Assert.All(passive, form =>
            {
                Assert.False(form.ShowInTaskbar);
                Assert.True(ShowsWithoutActivation(form) || (GetExtendedStyle(form) & NoActivate) != 0,
                    form.GetType().Name);
            });
            Assert.All(new Form[] { modifier, hud, hitNumbers, backdrop, shield }, form =>
            {
                Assert.Same(root, form.Owner);
                Assert.Equal(root.Handle, GetWindow(form.Handle, 4 /* GW_OWNER */));
                Assert.NotEqual(0, GetExtendedStyle(form) & NoActivate);
            });
            Assert.NotEqual(0, GetExtendedStyle(cursor) & NoActivate);
            Assert.NotEqual(0, GetExtendedStyle(background) & NoActivate);
            Assert.True(ShowsWithoutActivation(composition));
            Assert.Null(cursor.Owner);
            Assert.Null(root.Owner);
            Assert.Equal(root.Handle, GetAncestor(root.FlashHostPanel.Handle, 2 /* GA_ROOT */));
            Assert.Same(root, Assert.Single(passive.Append(root).Where(form =>
                form.TopLevel && form.ShowInTaskbar && !ShowsWithoutActivation(form)
                && (GetExtendedStyle(form) & NoActivate) == 0)));
        }
        finally { LogManager.Init(null, null); }
    });

    private static string MemberNames(Type type) =>
        string.Join("\n", type.GetMembers(Declared).Select(member => member.Name));

    private static bool ShowsWithoutActivation(Form form) => (bool)form.GetType()
        .GetProperty("ShowWithoutActivation", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(form);

    private static string ReadSource(string path)
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory != null; directory = directory.Parent)
        {
            string candidate = Path.Combine(directory.FullName, path);
            if (File.Exists(candidate)) return File.ReadAllText(candidate);
        }
        throw new FileNotFoundException(path);
    }

    private static int GetExtendedStyle(Form form) => GetWindowLong(form.Handle, -20 /* GWL_EXSTYLE */);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr window, int index);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr window, uint flags);
}
