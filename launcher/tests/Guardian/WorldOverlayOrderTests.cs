using System;
using System.Drawing;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class WorldOverlayOrderTests
    {
        [Fact]
        public void RealWindows_CoveredHudRecoversWithHiddenDamageNumberAnchor()
        {
            RunSta(() =>
            {
                using var f = new Fixture();
                f.CoverHud();
                IntPtr foreground = GetForegroundWindow();
                Rectangle worldBounds = f.World.Bounds, hudBounds = f.Hud.Bounds;
                Assert.Equal(f.World.Handle, WindowFromPoint(f.HudPoint));
                Assert.True(f.Order.RestoreNow("forced_field_order"));
                Assert.True(f.Hud.Handle == WindowFromPoint(f.HudPoint), f.Describe());
                Assert.Equal(f.Bottom.Handle, WindowFromPoint(f.BottomPoint));
                Assert.False(IsWindowVisible(f.Damage.Handle));
                Assert.Equal(foreground, GetForegroundWindow());
                Assert.Equal(worldBounds, f.World.Bounds);
                Assert.Equal(hudBounds, f.Hud.Bounds);
                // Route to the OS-selected HWND; sent messages are not physical-input evidence.
                SendMessage(WindowFromPoint(f.HudPoint), 0x201, (IntPtr)1, (IntPtr)0x000A000A);
                Assert.Equal(1, f.Hud.DownCount);
                Assert.Equal(0, f.World.DownCount);
                Assert.True(f.Order.RestoreNow("already_correct"));
            });
        }

        [Theory]
        [InlineData("owner")]
        [InlineData("hud")]
        [InlineData("world")]
        public void RealWindows_LifecycleRestoresAfterSynchronousOrderingHasSettled(string trigger)
        {
            RunSta(() =>
            {
                using var f = new Fixture();
                f.CoverHud();
                if (trigger == "owner") f.Owner.RaiseActivated();
                else if (trigger == "hud") f.Hud.PresentBelow(f.Damage.Handle);
                else { f.World.Hide(); f.World.Show(); }
                // A later synchronous callback may reorder again before the queued repair.
                f.CoverHud();
                Application.DoEvents();
                Assert.Equal(f.Hud.Handle, WindowFromPoint(f.HudPoint));
                Assert.Equal(f.Bottom.Handle, WindowFromPoint(f.BottomPoint));
            });
        }

        [Fact]
        public void RealWindows_ExternalForegroundDoesNotReorderOrActivateAnything()
        {
            RunSta(() =>
            {
                using var f = new Fixture();
                using var external = new QuietForm();
                f.Foreground = external.Handle;
                f.CoverHud();
                IntPtr foreground = GetForegroundWindow(), next = GetWindow(f.World.Handle, 2);
                f.Owner.RaiseActivated();
                Application.DoEvents();
                Assert.False(f.Order.RestoreNow("foreign_foreground"));
                Assert.Equal(next, GetWindow(f.World.Handle, 2));
                Assert.Equal(f.World.Handle, WindowFromPoint(f.HudPoint));
                Assert.Equal(foreground, GetForegroundWindow());
                f.Foreground = f.Owner.Handle;
                f.Owner.RaiseActivated();
                Application.DoEvents();
                Assert.Equal(f.Hud.Handle, WindowFromPoint(f.HudPoint));
            });
        }

        [Fact]
        public void RealWindows_PanelGateAndHiddenWorldRemainSuppressed()
        {
            RunSta(() =>
            {
                using var f = new Fixture();
                f.CoverHud();
                f.CanPresent = false;
                f.Hud.PresentBelow(f.Damage.Handle);
                f.CoverHud();
                Application.DoEvents();
                Assert.Equal(f.World.Handle, WindowFromPoint(f.HudPoint));
                Assert.False(f.Order.RestoreNow("panel_open"));
                f.CanPresent = true;
                f.World.Hide();
                f.Owner.RaiseActivated();
                Application.DoEvents();
                Assert.False(IsWindowVisible(f.World.Handle));
                Assert.False(f.Order.RestoreNow("world_hidden"));
                f.World.Show();
                Application.DoEvents();
                Assert.Equal(f.Hud.Handle, WindowFromPoint(f.HudPoint));
            });
        }

        [Fact]
        public void RealWindows_HiddenHudIsNeverAnAnchorAndDisposedQueueCannotMutate()
        {
            RunSta(() =>
            {
                using var f = new Fixture();
                f.Bottom.Dismiss();
                f.CoverHud();
                Assert.True(f.Order.RestoreNow("hidden_bottom"));
                Assert.False(IsWindowVisible(f.Bottom.Handle));
                Assert.Equal(f.Hud.Handle, WindowFromPoint(f.HudPoint));
                f.CoverHud();
                f.Owner.RaiseActivated();
                f.Order.Dispose();
                Application.DoEvents();
                Assert.Equal(f.World.Handle, WindowFromPoint(f.HudPoint));
                f.Hud.PresentBelow(f.Damage.Handle);
                f.CoverHud();
                Application.DoEvents();
                Assert.Equal(f.World.Handle, WindowFromPoint(f.HudPoint));
            });
        }

        [Fact]
        public void RealWindows_ForegroundGateAcceptsEmbeddedChildButNotOwnedOrForeignPopup()
        {
            RunSta(() =>
            {
                using var owner = new QuietForm();
                using var child = new Control { Parent = owner };
                using var popup = new QuietForm { Owner = owner };
                using var foreign = new QuietForm();
                Assert.True(WorldOverlayOrder.IsOwnerForeground(owner.Handle, owner.Handle));
                Assert.True(WorldOverlayOrder.IsOwnerForeground(owner.Handle, child.Handle));
                Assert.False(WorldOverlayOrder.IsOwnerForeground(owner.Handle, popup.Handle));
                Assert.False(WorldOverlayOrder.IsOwnerForeground(owner.Handle, foreign.Handle));
                Assert.False(WorldOverlayOrder.IsOwnerForeground(owner.Handle, IntPtr.Zero));
            });
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void RealWindows_HiddenOrMinimizedOwnerDoesNotResurrectTheWorld(bool minimized)
        {
            RunSta(() =>
            {
                using var f = new Fixture();
                f.CoverHud();
                if (minimized) f.Owner.WindowState = FormWindowState.Minimized;
                else f.Owner.Hide();
                Application.DoEvents();
                bool visible = IsWindowVisible(f.World.Handle);
                IntPtr next = GetWindow(f.World.Handle, 2), foreground = GetForegroundWindow();
                Assert.False(f.Order.RestoreNow("owner_suppressed"));
                Assert.Equal(visible, IsWindowVisible(f.World.Handle));
                Assert.Equal(next, GetWindow(f.World.Handle, 2));
                Assert.Equal(foreground, GetForegroundWindow());
            });
        }

        private sealed class Fixture : IDisposable
        {
            internal readonly QuietForm Owner, World;
            internal readonly TestOverlay Damage, Hud, Bottom;
            internal readonly WorldOverlayOrder Order;
            internal readonly Point HudPoint = new Point(70, 70), BottomPoint = new Point(70, 150);
            internal bool CanPresent = true;
            internal IntPtr Foreground;

            internal Fixture()
            {
                Owner = new QuietForm { Bounds = new Rectangle(40, 40, 220, 200) };
                Owner.Show();
                SetWindowPos(Owner.Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0213);
                World = new QuietForm { Owner = Owner, Bounds = Owner.Bounds };
                Damage = new TestOverlay(Owner, new Rectangle(50, 50, 100, 40));
                Hud = new TestOverlay(Owner, new Rectangle(50, 50, 100, 40));
                Bottom = new TestOverlay(Owner, new Rectangle(50, 130, 100, 40));
                Damage.PresentBelow(IntPtr.Zero); Damage.Dismiss();
                Hud.PresentBelow(Damage.Handle); Bottom.PresentBelow(Hud.Handle);
                // Keep the fixture above other desktop apps without activating it.
                // OverlayBase creates native handles before Show(), so explicitly
                // place every fixture surface in the same topmost group as its owner.
                SetWindowPos(Bottom.Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0213);
                SetWindowPos(Hud.Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0213);
                SetWindowPos(Damage.Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0213);
                World.Show();
                Foreground = Owner.Handle;
                // Only the foreground fact is injected. Z-order, visibility, alpha,
                // hit-testing and SetWindowPos operate on real Windows HWNDs.
                Order = new WorldOverlayOrder(Owner, World, new[] { Damage, Hud, Bottom },
                    () => CanPresent, () => Foreground);
                Application.DoEvents();
            }

            internal void CoverHud()
            {
                Assert.True(SetWindowPos(World.Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0213));
                Assert.Equal(World.Handle, WindowFromPoint(HudPoint));
            }
            internal string Describe()
            {
                string result = "hit=" + WindowFromPoint(HudPoint);
                foreach (var form in new Form[] { Owner, World, Damage, Hud, Bottom })
                    result += $"\n{form.GetType().Name} hwnd={form.Handle} owner={form.Owner?.Handle} next={GetWindow(form.Handle, 2)} visible={IsWindowVisible(form.Handle)} bounds={form.Bounds}";
                return result;
            }
            public void Dispose()
            {
                Order.Dispose(); Bottom.Dispose(); Hud.Dispose(); Damage.Dispose(); World.Dispose(); Owner.Dispose();
            }
        }

        private sealed class QuietForm : Form
        {
            internal int DownCount;
            internal QuietForm() { ShowInTaskbar = false; FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.Manual; }
            protected override bool ShowWithoutActivation => true;
            internal void RaiseActivated() => OnActivated(EventArgs.Empty);
            protected override void OnMouseDown(MouseEventArgs e) { DownCount++; base.OnMouseDown(e); }
            protected override void WndProc(ref Message m)
            {
                if (m.Msg == 0x21) { m.Result = (IntPtr)3; return; }
                base.WndProc(ref m);
            }
        }
        private sealed class TestOverlay : OverlayBase
        {
            private readonly Rectangle _bounds;
            internal int DownCount;
            internal TestOverlay(Form owner, Rectangle bounds) : base(owner, owner, 1024, 576) { _bounds = bounds; }
            protected override bool IsClickThrough => false;
            internal void PresentBelow(IntPtr after)
            {
                using var bitmap = new Bitmap(_bounds.Width, _bounds.Height, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
                using (var graphics = Graphics.FromImage(bitmap)) graphics.Clear(Color.White);
                CommitBitmap(bitmap, _bounds.X, _bounds.Y, 255);
                ShowOverlayBelow(after);
            }
            internal void Dismiss() => DismissOverlay();
            protected override void OnPositionChanged() { }
            protected override void OnMouseDown(MouseEventArgs e) { DownCount++; base.OnMouseDown(e); }
            protected override void WndProc(ref Message m)
            {
                if (m.Msg == 0x84) { m.Result = (IntPtr)1; return; }
                if (m.Msg == 0x21) { m.Result = (IntPtr)3; return; }
                base.WndProc(ref m);
            }
        }

        private static void RunSta(Action action)
        {
            Exception error = null;
            var thread = new Thread(() => { try { action(); } catch (Exception ex) { error = ex; } }) { IsBackground = true };
            thread.SetApartmentState(ApartmentState.STA); thread.Start();
            Assert.True(thread.Join(15000), "Window test did not finish");
            if (error != null) ExceptionDispatchInfo.Capture(error).Throw();
        }

        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hwnd, int message, IntPtr wparam, IntPtr lparam);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    }
}
