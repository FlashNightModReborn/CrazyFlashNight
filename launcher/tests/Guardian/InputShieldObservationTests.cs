using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class InputShieldObservationTests
    {
        [Theory]
        [InlineData(0x0201)]
        [InlineData(0x0204)]
        [InlineData(0x0207)]
        [InlineData(0x020B)]
        public void SharedHookObservesEachButtonWithoutReplacingOtherConsumers(int message)
        {
            WithOverlay((overlay, shield) =>
            {
                Enter(shield);
                int native = 0, world = 0;
                overlay.SetInteractionInputProbes((_, _, _) => native++, null);
                overlay.WorldDragInputRouter = (_, _, _, _) => { world++; return true; };
                Assert.Equal(new IntPtr(1), Sample(overlay, message));
                Assert.Equal(1, Read<int>(shield, "_sessionTotalClicks"));
                Assert.Equal(1, native);
                Assert.Equal(1, world);
                Assert.Equal(IntPtr.Zero, Read<IntPtr>(overlay, "_cursorHook"));
            });
        }

        [Fact]
        public void RefreshExitReopenAndDetachKeepExactObservationLifecycle()
        {
            WithOverlay((overlay, shield) =>
            {
                overlay.WorldDragInputRouter = (_, _, _, _) => true;
                Sample(overlay, 0x0201);
                Assert.Equal(0, Read<int>(shield, "_sessionTotalClicks"));
                Enter(shield);
                Sample(overlay, 0x0201);
                var updated = new Rectangle(600, 400, 100, 100);
                shield.EnterTelemetryMode(updated, new IntPtr(12), new Rectangle(0, 0, 1000, 800), new IntPtr(13));
                Assert.Equal(updated, Read<Rectangle>(shield, "_telemetryPanelRect"));
                Assert.Equal(new IntPtr(12), Read<IntPtr>(shield, "_telemetryGuardianHwnd"));
                Assert.Equal(new IntPtr(13), Read<IntPtr>(shield, "_telemetryWebOverlayHwnd"));
                Assert.Equal(1, Read<int>(shield, "_sessionTotalClicks"));
                shield.ExitTelemetryMode();
                shield.ExitTelemetryMode();
                Sample(overlay, 0x0201);
                Assert.Equal(1, Read<int>(shield, "_sessionTotalClicks"));
                Enter(shield);
                foreach (int message in new[] { 0x0200, 0x0202, 0x0205, 0x0208, 0x020C, 0x020A })
                {
                    shield.ObserveTelemetryButtonDown(200, 100, message);
                    Sample(overlay, message);
                }
                Assert.Equal(0, Read<int>(shield, "_sessionTotalClicks"));
                Sample(overlay, 0x0201);
                Assert.Equal(1, Read<int>(shield, "_sessionTotalClicks"));
                overlay.SetInputShield(null);
                Sample(overlay, 0x0201);
                Assert.Equal(1, Read<int>(shield, "_sessionTotalClicks"));
            });
        }

        [Fact]
        public void DisposedShieldCannotReopenOrObserveAndDoesNotBlockOtherConsumers()
        {
            WithOverlay((overlay, shield) =>
            {
                Enter(shield);
                shield.Dispose();
                Enter(shield);
                int native = 0;
                overlay.SetInteractionInputProbes((_, _, _) => native++, null);
                overlay.WorldDragInputRouter = (_, _, _, _) => true;
                Sample(overlay, 0x0201);
                Assert.False(shield.TelemetryActive);
                Assert.Equal(0, Read<int>(shield, "_sessionTotalClicks"));
                Assert.Equal(1, native);
            });
        }

        [Fact]
        public void NativeConsumerFailureDoesNotDropTelemetryOrWorldRouting()
        {
            WithOverlay((overlay, shield) =>
            {
                Enter(shield);
                int world = 0;
                overlay.SetInteractionInputProbes((_, _, _) => throw new InvalidOperationException(), null);
                overlay.WorldDragInputRouter = (_, _, _, _) => { world++; return true; };
                Assert.Equal(new IntPtr(1), Sample(overlay, 0x0201));
                Assert.Equal(1, Read<int>(shield, "_sessionTotalClicks"));
                Assert.Equal(1, Read<int>(overlay, "_cursorHookErrors"));
                Assert.Equal(1, world);
            });
        }

        [Fact]
        public void ShieldNoLongerDeclaresItsOwnGlobalMouseHookInterop()
        {
            foreach (string method in new[] { "SetWindowsHookEx", "UnhookWindowsHookEx", "CallNextHookEx" })
                Assert.Null(typeof(InputShieldForm).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Static));
        }

        private static void Enter(InputShieldForm shield)
            => shield.EnterTelemetryMode(new Rectangle(500, 300, 100, 100), IntPtr.Zero,
                new Rectangle(100, 50, 1000, 800), IntPtr.Zero);

        private static T Read<T>(object target, string field)
            => (T)target.GetType().GetField(field, BindingFlags.NonPublic | BindingFlags.Instance).GetValue(target);

        private static IntPtr Sample(WebOverlayForm overlay, int message)
        {
            IntPtr data = Marshal.AllocHGlobal(32);
            try
            {
                for (int offset = 0; offset < 32; offset += 4) Marshal.WriteInt32(data, offset, 0);
                Marshal.WriteInt32(data, 0, 200);
                Marshal.WriteInt32(data, 4, 100);
                // Directly invoke the managed callback. No OS input, cursor move,
                // message pumping or installed desktop hook is involved.
                return (IntPtr)typeof(WebOverlayForm).GetMethod("CursorHookCallback",
                    BindingFlags.NonPublic | BindingFlags.Instance).Invoke(overlay,
                    new object[] { 0, new IntPtr(message), data });
            }
            finally { Marshal.FreeHGlobal(data); }
        }

        private static void WithOverlay(Action<WebOverlayForm, InputShieldForm> test)
        {
            Exception failure = null;
            var thread = new Thread(() =>
            {
                try
                {
                    using var owner = new Form { ShowInTaskbar = false };
                    using var anchor = new Panel();
                    owner.Controls.Add(anchor);
                    string missing = Path.Combine(Path.GetTempPath(), "cf7-observer-missing-" + Guid.NewGuid().ToString("N"));
                    using var overlay = new WebOverlayForm(owner, anchor, missing, missing,
                        false, false, false, 60, false, "", false, false, false, null);
                    using var shield = new InputShieldForm(owner, anchor);
                    overlay.SetInputShield(shield);
                    test(overlay, shield);
                }
                catch (Exception error) { failure = error; }
            }) { IsBackground = true };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            Assert.True(thread.Join(TimeSpan.FromSeconds(15)), "Shared input observation fixture timed out.");
            if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }
}
