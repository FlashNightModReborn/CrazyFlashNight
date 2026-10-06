using System;
using System.IO;
using System.Reflection;
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
                    Assert.NotEqual(IntPtr.Zero, (IntPtr)Read("_cursorHook"));
                    Assert.True(((System.Windows.Forms.Timer)Read("_cursorTimer")).Enabled);
                    var request = JObject.Parse("{\"state\":\"attack\",\"dragging\":true}");
                    string response = Task.Run(() => overlay.HandleCursorControl(request)).GetAwaiter().GetResult();
                    Assert.True(JObject.Parse(response).Value<bool>("success"));
                    // The worker must not mutate UI-owned state or create an unpumped hook.
                    Assert.Equal("normal", (string)Read("_cursorState"));
                    Application.DoEvents();
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
    }
}
