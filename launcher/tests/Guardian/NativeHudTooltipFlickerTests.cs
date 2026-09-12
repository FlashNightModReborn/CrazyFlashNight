using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NativeHudTooltipFlickerTests
    {
        [Fact]
        public void TooltipShowMoveHide_WindowGeometryNeverPrecedesNewPaint()
        {
            using var owner = new Form();
            using var anchor = new Panel { Size = new Size(1024, 576) };
            owner.Controls.Add(anchor);
            using var hud = new TestHud(owner, anchor);
            var commits = new List<LayeredWindowCommitResult>();
            hud.SetCommitObserver(new CommitObserver(commits));
            var duringPaint = new List<Rectangle>();
            Action observePaint = () => duringPaint.Add(WindowRectOf(hud));
            var permanent = new Widget(new Rectangle(100, 100, 80, 40), observePaint);
            var tooltip = new Widget(new Rectangle(300, 300, 120, 60), observePaint) { Visible = false };
            hud.AddWidget(permanent);
            hud.AddWidget(tooltip);
            hud.SetReady();
            Assert.True(commits[commits.Count - 1].Succeeded);

            void CheckChange(Action change, Rectangle expected)
            {
                var previousRect = WindowRectOf(hud);
                duringPaint.Clear();
                commits.Clear();
                change();
                Assert.NotEmpty(duringPaint);
                // 绘制新帧期间，真实 HWND 必须仍保留旧几何；提前 SetWindowPos 会失败。
                Assert.All(duringPaint, observed => Assert.Equal(previousRect, observed));
                var commit = Assert.Single(commits);
                Assert.True(commit.Succeeded, commit.ErrorMessage);
                Assert.Equal(expected, new Rectangle(commit.ScreenX, commit.ScreenY, commit.Width, commit.Height));
                Assert.True(GetWindowRect(hud.Handle, out var rect));
                Assert.Equal(expected, Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom));
            }

            CheckChange(() => { tooltip.Visible = true; tooltip.Changed(); }, new Rectangle(94, 94, 332, 272));
            CheckChange(() => { tooltip.Bounds = new Rectangle(40, 60, 120, 60); tooltip.Changed(); }, new Rectangle(34, 54, 152, 92));
            CheckChange(() => { tooltip.Visible = false; tooltip.Changed(); }, new Rectangle(94, 94, 92, 52));
        }

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr handle, out RECT rect);
        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left, Top, Right, Bottom; }
        private static Rectangle WindowRectOf(Control control)
        {
            Assert.True(GetWindowRect(control.Handle, out var rect));
            return Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
        }
        private sealed class TestHud : NativeHudOverlay
        {
            public TestHud(Form owner, Control anchor) : base(owner, anchor) { _ownerVisible = false; }
            protected override bool IsOwnerSessionForeground() => false;
        }
        private sealed class CommitObserver : ILayeredWindowCommitObserver
        {
            private readonly List<LayeredWindowCommitResult> _results;
            public CommitObserver(List<LayeredWindowCommitResult> results) { _results = results; }
            public void OnCommit(LayeredWindowCommitResult result) => _results.Add(result);
        }
        private sealed class Widget : INativeHudWidget
        {
            private readonly Action _paint;
            public Rectangle Bounds;
            public bool Visible { get; set; } = true;
            public Widget(Rectangle bounds, Action paint) { Bounds = bounds; _paint = paint; }
            public Rectangle ScreenBounds => Bounds;
            public bool WantsAnimationTick => false;
            public void Paint(Graphics g, float dpr, Point origin) { _paint(); g.FillRectangle(Brushes.Red, Bounds.X - origin.X, Bounds.Y - origin.Y, Bounds.Width, Bounds.Height); }
            public bool TryHitTest(Point point) => false;
            public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }
            public void Tick(int deltaMs) { }
            public event EventHandler BoundsOrVisibilityChanged;
            public event EventHandler RepaintRequested { add { } remove { } }
            public event EventHandler AnimationStateChanged { add { } remove { } }
            public void Changed() => BoundsOrVisibilityChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
