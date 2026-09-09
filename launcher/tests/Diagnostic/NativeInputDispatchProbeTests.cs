using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public sealed class NativeInputDispatchProbeTests
    {
        private sealed class ProbeForm : Form
        {
            internal NativeInputDispatchProbe Probe;
            protected override void WndProc(ref Message m)
            {
                if (m.Msg == NativeInputDispatchProbe.HeartbeatMessage)
                { Probe?.Acknowledge(m.WParam.ToInt64()); return; }
                base.WndProc(ref m);
            }
        }

        [Fact]
        public void ActualThreadHookObservesPostedRemovalAndSingleInflightHeartbeat()
        {
            Exception failure = null;
            var thread = new Thread(() => {
                var batches = new List<string>();
                try
                {
                    FocusTrace.Start(batches.Add, false);
                    using (var form = new ProbeForm())
                    using (var probe = new NativeInputDispatchProbe(form.Handle))
                    {
                        form.Probe = probe;
                        // 故意短暂停泵，让后台记录 pending；不运行游戏或注入真实输入。
                        Thread.Sleep(650);
                        FocusTrace.Flush();
                        var before = Read(batches);
                        Assert.Single(before, x => (string)x["event"] == "input.heartbeat_post");
                        Assert.DoesNotContain(before, x => (string)x["event"] == "input.heartbeat_ack");
                        Application.DoEvents();
                        FocusTrace.Flush();
                        var after = Read(batches);
                        Assert.Contains(after, x => (string)x["event"] == "input.getmessage"
                            && (int)x["data"]["message"] == NativeInputDispatchProbe.HeartbeatMessage
                            && (int)x["data"]["flags"] == 1);
                        Assert.Contains(after, x => (string)x["event"] == "input.heartbeat_ack");
                        var entries = after.Where(x => (string)x["event"] == "input.getmessage").ToArray();
                        Assert.Equal(entries.Count(x => (string)x["data"]["phase"] == "enter"),
                            entries.Count(x => (string)x["data"]["phase"] == "after_next_hook"));
                    }
                    FocusTrace.Flush();
                    Assert.Contains(Read(batches), x => (string)x["event"] == "input.coverage"
                        && (string)x["data"]["phase"] == "unhook" && (bool)x["data"]["ok"]);
                }
                catch (Exception ex) { failure = ex; }
                finally { FocusTrace.Stop(); }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            Assert.True(thread.Join(10000));
            if (failure != null) throw failure;
        }
        private static JObject[] Read(List<string> batches) => batches
            .SelectMany(x => x.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries))
            .Select(x => JObject.Parse(x.Substring(13))).ToArray();
    }
}
