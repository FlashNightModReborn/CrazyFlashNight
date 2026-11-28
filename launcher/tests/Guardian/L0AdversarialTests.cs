using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

// Exercises the capture wait state without showing a window or starting WGC.
public sealed class L0AdversarialTests
{
    [Theory]
    [InlineData(540, CaptureInvalidation.Geometry)]
    [InlineData(482, CaptureInvalidation.Source)]
    [InlineData(540, CaptureInvalidation.Expiry)]
    [InlineData(482, CaptureInvalidation.Expiry)]
    public void L0_RefreshReentryKeepsFirstDeadlineThroughStrictEscalation(int height, CaptureInvalidation invalidation)
    {
        using var owner = new Form();
        using var world = CreateWorld(owner);
        var view = new WorldCompositorController.CaptureView(3, new IntPtr(0x1001), 7, 11, 2,
            new Size(1602, 939), new Size(1600, 938), new Rectangle(160, 74, 1600, 900), 144);
        Field("_presentedView").SetValue(world, view);
        Field("_appliedHeight").SetValue(world, 540);
        world.ApplyRenderSelection(new RenderSelection(3, height, "LOW", 2), 0, _ => { });

        world.BeginBudgetWait(view, admitted: true);
        double firstWait = FirstWait(world);
        Assert.True(double.IsFinite(firstWait));
        Assert.True(world.CaptureInputBlocked);
        Assert.False(world.KeyboardBlockRequested);

        // The geometry/fresh-frame continuation must preserve the existing reason.
        world.BeginCaptureWait(CaptureWaitReason.RenderRefresh, hold: false);
        world.BeginBudgetWait(view, admitted: true);
        Assert.Equal(firstWait, FirstWait(world));
        world.ObserveRefreshDeadline(CaptureWaitReason.RenderRefresh, owesFrame: true,
            firstWait + WorldCompositorController.RefreshEscalationMs - 1);
        Assert.True(world.CaptureInputBlocked);
        Assert.False(world.KeyboardBlockRequested);

        // A source incarnation change can reuse the same HWND and scene.
        var changed = invalidation switch
        {
            CaptureInvalidation.Geometry => view with { RootClient = new Size(1640, 938) },
            CaptureInvalidation.Source => view with { Embed = view.Embed + 1 },
            _ => view
        };
        var reason = WorldCompositorController.ClassifyRefresh(view, changed, admitted: true);
        world.ObserveRefreshDeadline(reason, owesFrame: true, invalidation == CaptureInvalidation.Expiry
            ? firstWait + WorldCompositorController.RefreshEscalationMs
            : firstWait + 1);
        Assert.True(world.CaptureInputBlocked);
        Assert.True(world.KeyboardBlockRequested);
        Assert.Equal(firstWait, FirstWait(world));

        world.BeginBudgetWait(view, admitted: true);
        Assert.True(world.KeyboardBlockRequested);
        Assert.Equal(firstWait, FirstWait(world));
        CheckHardDeadline(world, firstWait + 9_999);
        Assert.IsType<TimeoutException>(Assert.Throws<TargetInvocationException>(
            () => CheckHardDeadline(world, firstWait + 10_001)).InnerException);
    }

    [Fact]
    public void GeometryWaitKeepsPointerBlockedUntilTheNewMappingIsReady()
    {
        using var owner = new Form();
        using var world = CreateWorld(owner);
        var authority = R1UiAdapterTests.StartGameAuthority();
        world.ConfigurePassiveInput(authority);
        Assert.True(authority.ObserveKey((int)Keys.W, true));
        long epoch = authority.CurrentKeyboardEpoch;
        string held = authority.AdmittedHex;

        world.BeginCaptureWait(CaptureWaitReason.GeometryInvalid, hold: false);
        double firstWait = FirstWait(world);
        Assert.True(world.CaptureInputBlocked);
        Assert.True(authority.IsGameKeyboardAdmitted);
        Assert.Equal(held, authority.AdmittedHex);

        world.BeginCaptureWait(CaptureWaitReason.RenderRefresh, hold: false);
        Assert.True(world.CaptureInputBlocked);
        Assert.Equal(firstWait, FirstWait(world));

        world.EndCaptureWait();
        Assert.False(world.CaptureInputBlocked);
        Assert.True(authority.IsGameKeyboardAdmitted);
        Assert.Equal(epoch, authority.CurrentKeyboardEpoch);
        Assert.Equal(held, authority.AdmittedHex);
    }

    public enum CaptureInvalidation { Geometry, Source, Expiry }

    private static FieldInfo Field(string name) =>
        typeof(WorldCompositorController).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic);

    private static double FirstWait(WorldCompositorController world) =>
        (double)Field("_geometryWaitStartedMs").GetValue(world);

    private static void CheckHardDeadline(WorldCompositorController world, double now) =>
        typeof(WorldCompositorController).GetMethod("CheckGeometryRecoveryTimeout",
            BindingFlags.Instance | BindingFlags.NonPublic).Invoke(world, new object[] { now });

    private static WorldCompositorController CreateWorld(Form owner)
    {
        string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
        return new WorldCompositorController(owner, owner, () => new IntPtr(0x1001),
            () => false, _ => { }, root, () => false, _ => { });
    }
}
