using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Threading;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public sealed class FocusTraceSessionTests : IDisposable
    {
        private readonly List<string> _rows = new List<string>();
        private void Capture(string batch) { lock (_rows) _rows.AddRange(batch.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries)); }
        private JObject[] Rows() { lock (_rows) return _rows.Select(x => JObject.Parse(x.Replace("[FocusTrace] ", ""))).ToArray(); }
        public void Dispose() { FocusTrace.Stop(); FocusTrace.TickCount64Provider = null; }
        private static FocusTrace.NativeTraceData Entry() => new FocusTrace.NativeTraceData {
            message = 0x0201, point = new Point(10, 10), ObservedTick = Environment.TickCount64
        };
        [Fact] public void SameLabelRestartCannotReuseGeneration()
        {
            FocusTrace.Start(Capture, false, session: "same"); var a = FocusTrace.TryCaptureLease();
            FocusTrace.Start(Capture, false, session: "same"); var b = FocusTrace.TryCaptureLease();
            Assert.NotEqual(a.Generation, b.Generation);
            Assert.False(FocusTrace.TryRecord(a, "old")); Assert.True(FocusTrace.TryRecord(b, "new"));
            FocusTrace.Flush(); Assert.DoesNotContain(Rows(), x => (string)x["event"] == "old");
        }
        [Fact] public void SessionChangedBetweenCaptureAndBeginCannotClaimNewRing()
        {
            FocusTrace.Start(Capture, false, session: "same"); var old = FocusTrace.TryCaptureLease();
            FocusTrace.Start(Capture, false, session: "same"); var current = FocusTrace.TryCaptureLease();
            FocusTrace.SetTarget(new Rectangle(0, 0, 20, 20));
            string mouse = FocusTrace.PhysicalEdge(0x0201, new Point(10, 10), 0, unchecked((uint)Environment.TickCount), 1);
            Assert.False(FocusTrace.TryBeginNative(old, Entry()));
            var fresh = Entry(); Assert.True(FocusTrace.TryBeginNative(current, fresh));
            Assert.Equal(mouse, fresh.mouseId);
        }
        [Fact] public void StopBetweenEntryAndExitProducesPartialTerminal()
        {
            FocusTrace.Start(Capture, false); var lease = FocusTrace.TryCaptureLease(); var entry = Entry();
            Assert.True(FocusTrace.TryBeginNative(lease, entry)); FocusTrace.Stop();
            Assert.False(FocusTrace.TryEndNative(lease, entry, 0, 1, "returned"));
            Assert.Contains(Rows(), x => (string)x["event"] == "trace.native_terminal" && (string)x["data"]["pairState"] == "partial_at_terminal");
        }
        [Fact] public void OldTimerCannotDrainNewSession()
        {
            FocusTrace.Start(Capture, false); var old = FocusTrace.TryCaptureLease(); FocusTrace.Stop();
            int count = 0; FocusTrace.Start(_ => count++, false);
            FocusTrace.Record("new"); FocusTrace.FlushLeaseForTests(old); Assert.Equal(0, count);
            FocusTrace.Flush(); Assert.Equal(1, count);
        }
        [Fact] public void LeaseRetirementAcrossThreadsUsesBarrier()
        {
            FocusTrace.Start(Capture, false, session: "same"); var old = FocusTrace.TryCaptureLease();
            using var captured = new ManualResetEventSlim(); using var release = new ManualResetEventSlim(); bool accepted = true;
            var thread = new Thread(() => { captured.Set(); release.Wait(); accepted = FocusTrace.TryBeginNative(old, Entry()); });
            thread.Start(); Assert.True(captured.Wait(1000)); FocusTrace.Start(Capture, false, session: "same");
            release.Set(); Assert.True(thread.Join(1000)); Assert.False(accepted);
        }
        [Fact] public void DispatchOutcomeIsIndependentOfFinallyAndDoesNotCrossSession()
        {
            FocusTrace.Start(Capture, false); var lease = FocusTrace.TryCaptureLease(); var entry = Entry();
            Assert.True(FocusTrace.TryBeginNative(lease, entry)); Assert.True(FocusTrace.TryEndNative(lease, entry, 0, 1, "threw"));
            FocusTrace.Flush(); var exit = Rows().Single(x => (string)x["data"]?["phase"] == "exit");
            Assert.Equal("threw", (string)exit["data"]["dispatchOutcome"]); Assert.Equal("paired", (string)exit["data"]["pairState"]);
        }
    }
}
