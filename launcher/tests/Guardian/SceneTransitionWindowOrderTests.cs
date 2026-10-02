using System;
using System.Drawing;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class SceneTransitionWindowOrderTests
    {
        [Fact]
        public void CorrectStack_DoesNotSendWindowPositionMessagesAcrossRepeatedTicks()
        {
            RunSta(() =>
            {
                using var owner = new ObservedForm(); owner.Show();
                using var world = new ObservedForm { Owner = owner }; world.Show();
                using var curtain = new ObservedForm { Owner = owner }; curtain.Show(); Raise(curtain);
                Assert.True(IsAbove(curtain.Handle, world.Handle));
                owner.Changes = world.Changes = curtain.Changes = 0;

                for (int i = 0; i < 40; i++) Assert.False(SceneTransitionWindowOrder.RaiseIfCovered(curtain, owner));

                Assert.Equal(0, curtain.Changes);
                Assert.Equal(0, owner.Changes);
                Assert.Equal(0, world.Changes);
            });
        }

        [Fact]
        public void NewlyPresentedSibling_IsRepairedWithoutMovingOwnerOrChangingFocusAndBounds()
        {
            RunSta(() =>
            {
                using var owner = new ObservedForm(); owner.Show();
                using var curtain = new ObservedForm { Owner = owner }; curtain.Show();
                using var hud = new ObservedForm { Owner = owner }; hud.Show(); Raise(hud);
                Assert.True(IsAbove(hud.Handle, curtain.Handle));
                IntPtr foreground = GetForegroundWindow();
                Rectangle bounds = curtain.Bounds, ownerBounds = owner.Bounds;
                owner.Changes = curtain.Changes = 0;

                Assert.True(SceneTransitionWindowOrder.RaiseIfCovered(curtain, owner));
                Assert.True(IsAbove(curtain.Handle, hud.Handle));
                Assert.Equal(1, curtain.Changes);
                Assert.Equal(0, owner.Changes);
                Assert.Equal(foreground, GetForegroundWindow());
                Assert.Equal(bounds, curtain.Bounds);
                Assert.Equal(ownerBounds, owner.Bounds);
                for (int i = 0; i < 40; i++) Assert.False(SceneTransitionWindowOrder.RaiseIfCovered(curtain, owner));
                Assert.Equal(1, curtain.Changes);
            });
        }

        [Fact]
        public void BackingAndCurtain_RepairTogetherAndNeverRaiseAgainstEachOther()
        {
            RunSta(() =>
            {
                using var owner = new ObservedForm(); owner.Show();
                using var hud = new ObservedForm { Owner = owner }; hud.Show();
                using var backing = new ObservedForm { Owner = owner }; backing.Show();
                using var curtain = new ObservedForm { Owner = owner }; curtain.Show();
                Raise(hud);
                Assert.True(SceneTransitionWindowOrder.RaiseIfCovered(backing, owner, curtain.Handle));
                Assert.True(SceneTransitionWindowOrder.RaiseIfCovered(curtain, owner));
                Assert.True(IsAbove(curtain.Handle, backing.Handle));
                Assert.True(IsAbove(backing.Handle, hud.Handle));
                owner.Changes = backing.Changes = curtain.Changes = 0;

                for (int i = 0; i < 40; i++)
                {
                    Assert.False(SceneTransitionWindowOrder.RaiseIfCovered(backing, owner, curtain.Handle));
                    Assert.False(SceneTransitionWindowOrder.RaiseIfCovered(curtain, owner));
                }
                Assert.Equal(0, owner.Changes + backing.Changes + curtain.Changes);
                // A failed renderer must allow its opaque backing to cover it.
                Assert.True(SceneTransitionWindowOrder.RaiseIfCovered(backing, owner));
                Assert.True(IsAbove(backing.Handle, curtain.Handle));
            });
        }

        [Fact]
        public void HiddenForeignAndTopmostWindows_DoNotTriggerUnproductiveRepairs()
        {
            RunSta(() =>
            {
                using var owner = new ObservedForm(); owner.Show();
                using var curtain = new ObservedForm { Owner = owner }; curtain.Show();
                using var hidden = new ObservedForm { Owner = owner }; hidden.Show(); Raise(hidden); hidden.Hide();
                using var foreign = new ObservedForm(); foreign.Show(); Raise(foreign);
                using var cursor = new ObservedForm { Owner = owner, TopMost = true }; cursor.Show();
                curtain.Changes = owner.Changes = 0;
                for (int i = 0; i < 40; i++) Assert.False(SceneTransitionWindowOrder.RaiseIfCovered(curtain, owner));
                Assert.Equal(0, curtain.Changes + owner.Changes);
                Assert.True(cursor.TopMost);
            });
        }

        [Fact]
        public void HiddenOrUnownedTarget_IsNotShownOrReordered()
        {
            RunSta(() =>
            {
                using var owner = new ObservedForm(); owner.Show();
                using var curtain = new ObservedForm { Owner = owner }; curtain.Show(); curtain.Hide();
                using var hud = new ObservedForm { Owner = owner }; hud.Show(); Raise(hud);
                curtain.Changes = 0;
                Assert.False(SceneTransitionWindowOrder.RaiseIfCovered(curtain, owner));
                Assert.False(curtain.Visible);
                Assert.Equal(0, curtain.Changes);
                curtain.Show(); curtain.Owner = null; Raise(hud); curtain.Changes = 0;
                Assert.False(SceneTransitionWindowOrder.RaiseIfCovered(curtain, owner));
                Assert.Equal(0, curtain.Changes);
            });
        }

        private static void Raise(Form window) => Assert.True(SetWindowPos(window.Handle, IntPtr.Zero, 0, 0, 0, 0, 0x0213));
        private static bool IsAbove(IntPtr upper, IntPtr lower)
        {
            for (int i = 0; lower != IntPtr.Zero && i < 512; i++, lower = GetWindow(lower, 3))
                if (lower == upper) return true;
            return false;
        }
        private sealed class ObservedForm : Form
        {
            internal int Changes;
            internal ObservedForm()
            {
                Bounds = new Rectangle(50, 50, 160, 100); ShowInTaskbar = false;
                StartPosition = FormStartPosition.Manual; FormBorderStyle = FormBorderStyle.None;
            }
            protected override bool ShowWithoutActivation => true;
            protected override void WndProc(ref Message m)
            {
                if (m.Msg == 0x0046) Changes++; // WM_WINDOWPOSCHANGING, even for a no-op native request.
                base.WndProc(ref m);
            }
        }
        private static void RunSta(Action action)
        {
            Exception error = null;
            var thread = new Thread(() => { try { action(); } catch (Exception ex) { error = ex; } }) { IsBackground = true };
            thread.SetApartmentState(ApartmentState.STA); thread.Start();
            Assert.True(thread.Join(15000), "Transition window order test did not finish");
            if (error != null) ExceptionDispatchInfo.Capture(error).Throw();
        }
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after,
            int x, int y, int width, int height, uint flags);
    }
}
