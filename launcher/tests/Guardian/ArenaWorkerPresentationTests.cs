using System;
using System.Drawing;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class ArenaWorkerPresentationTests
{
    [Fact]
    public void MinimalWorkerWindowKeepsRealNonzeroOutputAtItsRasterBudget() => Sta(() =>
    {
        using var form = new GuardianForm(null, false, "", false, true,
            arenaWorkerMode: true, arenaWorkerMinimalRendering: true);
        Assert.Equal(new Size(320, 180), form.ClientSize);
        _ = form.Handle;
        form.PerformLayout();
        Assert.Equal(new Size(320, 180), form.ClientSize);
        Assert.Equal(form.Size, form.MinimumSize);
        Assert.False(form.TopMost);
        Assert.False(form.ShowInTaskbar);
        Assert.False(form.Visible);
        var schedule = new RenderSchedule(new RenderScheduleSettings(),
            new PerformancePolicy("performance", "fixed", 180), form.ClientSize.Height);
        var initial = schedule.Current;
        Assert.Equal(180, initial.Height);
        Assert.Equal("LOW", initial.Quality);
        Assert.Equal(2, initial.EffectLevel);
        Assert.True(schedule.ConfirmApplied(initial, 0));
        for (int i = 0; i < 100; ++i)
            schedule.Observe(new RenderSample { Frames = 1, DurationMs = 500 }, (i + 1) * 500, true);
        Assert.Equal(initial, schedule.Current);
        Assert.Equal(new Size(320, 180), FlashRenderBudget.Fit(form.ClientSize, 180, initial.Height));
    });

    [Fact]
    public void DisabledHudCannotBeReawakenedByReadyResumeOrWidgetEvents() => Sta(() =>
    {
        using var owner = new Form { ClientSize = new Size(320, 180) };
        using var hud = new NativeHudOverlay(owner, owner, presentationEnabled: false);
        var widget = new AnimatedWidget();
        hud.AddWidget(widget);
        hud.SetReady();
        ((INotchSink)hud).SetReady();
        ((IToastSink)hud).SetReady();
        hud.Suspend();
        hud.Resume();
        owner.ClientSize = new Size(640, 360);
        widget.RequestPresentation();
        hud.SetReady();
        foreach (string name in new[] { "_animTick", "_renderCoalesceTimer" })
        {
            var timer = (System.Windows.Forms.Timer)typeof(NativeHudOverlay)
                .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic).GetValue(hud);
            Assert.False(timer.Enabled);
        }
        Assert.Null(typeof(NativeHudOverlay).GetField("_composedBitmap",
            BindingFlags.Instance | BindingFlags.NonPublic).GetValue(hud));
        Assert.Equal(0, widget.Paints);
        Assert.Equal(0, widget.Ticks);
        Assert.True(widget.Suppressed);
        Assert.False(hud.Visible);
    });

    private sealed class AnimatedWidget : INativeHudWidget, INativeHudResumable
    {
        internal int Paints, Ticks;
        internal bool Suppressed;
        public void SetHostSuppressed(bool suppressed) => Suppressed = suppressed;
        public Rectangle ScreenBounds => new Rectangle(0, 0, 20, 20);
        public bool Visible => true;
        public bool WantsAnimationTick => true;
        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;
        public void RequestPresentation()
        {
            BoundsOrVisibilityChanged?.Invoke(this, EventArgs.Empty);
            RepaintRequested?.Invoke(this, EventArgs.Empty);
            AnimationStateChanged?.Invoke(this, EventArgs.Empty);
        }
        public void Tick(int ms) => Ticks++;
        public void Paint(Graphics graphics, float dpr, Point origin) => Paints++;
        public bool TryHitTest(Point point) => ScreenBounds.Contains(point);
        public void OnMouseEvent(MouseEventArgs args, MouseEventKind kind) { }
    }

    private static void Sta(Action action)
    {
        Exception failure = null;
        var thread = new Thread(() => { try { action(); } catch (Exception error) { failure = error; } });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(30)), "Worker presentation verification did not finish.");
        if (failure != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
