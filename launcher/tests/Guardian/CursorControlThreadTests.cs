using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class CursorControlThreadTests
    {
        [Fact]
        public void CursorRequestsFromWorker_RunOnUiThreadEvenWhenWebFails()
        {
            Exception failure = null;
            var thread = new Thread(() =>
            {
                try
                {
                    using var owner = new Form { ShowInTaskbar = false };
                    using var anchor = new Panel { Dock = DockStyle.Fill };
                    owner.Controls.Add(anchor);
                    string missing = Path.Combine(Path.GetTempPath(), "cf7-web-missing-" + Guid.NewGuid().ToString("N"));
                    using var overlay = new WebOverlayForm(owner, anchor, missing, missing,
                        false, false, false, 60, false, "", false, false, false, null);
                    object Read(string name) => typeof(WebOverlayForm).GetField(name, BindingFlags.NonPublic | BindingFlags.Instance).GetValue(overlay);
                    Assert.Equal(IntPtr.Zero, (IntPtr)Read("_cursorHook"));
                    Assert.True((bool)Read("_cursorHookInstallPending"));
                    Assert.True(((System.Windows.Forms.Timer)Read("_cursorTimer")).Enabled);
                    var request = JObject.Parse("{\"state\":\"attack\",\"dragging\":true}");
                    string response = Task.Run(() => overlay.HandleCursorControl(request)).GetAwaiter().GetResult();
                    Assert.True(JObject.Parse(response).Value<bool>("success"));
                    // The worker must not mutate UI-owned state or create an unpumped hook.
                    Assert.Equal("normal", (string)Read("_cursorState"));
                    Application.DoEvents();
                    Assert.NotEqual(IntPtr.Zero, (IntPtr)Read("_cursorHook"));
                    Assert.False((bool)Read("_cursorHookInstallPending"));
                    Assert.Equal("attack", (string)Read("_cursorState"));
                    Assert.True((bool)Read("_cursorDragging"));
                    var deadline = DateTime.UtcNow.AddSeconds(3);
                    while (!(bool)Read("_webFailed") && DateTime.UtcNow < deadline)
                    { Application.DoEvents(); Thread.Sleep(5); }
                    Assert.True((bool)Read("_webFailed"));
                    Assert.True(((System.Windows.Forms.Timer)Read("_cursorTimer")).Enabled);
                }
                catch (Exception error) { failure = error; }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            Assert.True(thread.Join(TimeSpan.FromSeconds(15)), "Cursor UI-thread regression timed out.");
            if (failure != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
        }

        [Fact]
        public void DisposedBeforeMessagePump_DoesNotInstallDesktopHook()
        {
            Exception failure = null;
            var thread = new Thread(() =>
            {
                try
                {
                    using var owner = new Form { ShowInTaskbar = false };
                    using var anchor = new Panel();
                    owner.Controls.Add(anchor);
                    string missing = Path.Combine(Path.GetTempPath(), "cf7-web-missing-" + Guid.NewGuid().ToString("N"));
                    using var overlay = new WebOverlayForm(owner, anchor, missing, missing,
                        false, false, false, 60, false, "", false, false, false, null);
                    overlay.Dispose();
                    Application.DoEvents();
                    var hook = typeof(WebOverlayForm).GetField("_cursorHook", BindingFlags.NonPublic | BindingFlags.Instance);
                    Assert.Equal(IntPtr.Zero, (IntPtr)hook.GetValue(overlay));
                }
                catch (Exception error) { failure = error; }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            Assert.True(thread.Join(TimeSpan.FromSeconds(15)), "Disposed cursor hook regression timed out.");
            if (failure != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
        }

        [Fact]
        public void HookConsumerFailuresAreContainedAndDeferredWithoutPhysicalInput()
        {
            Exception failure = null;
            var thread = new Thread(() =>
            {
                try
                {
                    using var owner = new Form { ShowInTaskbar = false };
                    using var anchor = new Panel();
                    owner.Controls.Add(anchor);
                    string missing = Path.Combine(Path.GetTempPath(), "cf7-web-missing-" + Guid.NewGuid().ToString("N"));
                    using var overlay = new WebOverlayForm(owner, anchor, missing, missing,
                        false, false, false, 60, false, "", false, false, false, null);
                    var callback = typeof(WebOverlayForm).GetMethod("CursorHookCallback", BindingFlags.Instance | BindingFlags.NonPublic);
                    var errors = typeof(WebOverlayForm).GetField("_cursorHookErrors", BindingFlags.Instance | BindingFlags.NonPublic);
                    IntPtr sample = Marshal.AllocHGlobal(32);
                    try
                    {
                        for (int offset=0;offset<32;offset+=4) Marshal.WriteInt32(sample,offset,0);
                        overlay.SetInteractionInputProbes((_,_,_) => throw new InvalidOperationException(),
                            (_,_,_) => throw new InvalidOperationException(),
                            (_,_) => throw new InvalidOperationException());
                        // Invoke the observer directly, without SendInput, moving the
                        // desktop cursor or installing an unpumped global hook.
                        callback.Invoke(overlay,new object[] { 0,new IntPtr(0x200),sample });
                        callback.Invoke(overlay,new object[] { 0,new IntPtr(0x201),sample });
                        callback.Invoke(overlay,new object[] { 0,new IntPtr(0x20A),sample });
                        Assert.Equal(3,(int)errors.GetValue(overlay));
                        overlay.SetInteractionInputProbes(null,null,null);
                        overlay.WorldDragInputRouter=(_,_,_,_) => throw new InvalidOperationException();
                        callback.Invoke(overlay,new object[] { 0,new IntPtr(0x202),sample });
                        Assert.Equal(4,(int)errors.GetValue(overlay));
                    }
                    finally { Marshal.FreeHGlobal(sample); }
                }
                catch(Exception error) { failure=error; }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            Assert.True(thread.Join(TimeSpan.FromSeconds(15)));
            if(failure!=null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }
}
