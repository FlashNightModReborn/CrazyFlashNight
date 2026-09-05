using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public sealed class FocusTraceTests : IDisposable
    {
        private readonly List<string> _batches = new List<string>();
        public FocusTraceTests() { FocusTrace.Start(_batches.Add, false); }
        public void Dispose() { FocusTrace.Stop(); }
        private JObject[] Read()
        {
            FocusTrace.Flush();
            return _batches.SelectMany(x => x.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries))
                .Select(x => JObject.Parse(x.Substring("[FocusTrace] ".Length))).ToArray();
        }

        [Fact]
        public void DisabledPathDoesNotRecordOrTouchPayload()
        {
            FocusTrace.Stop();
            int count = _batches.Count;
            FocusTrace.Record("disabled", new ThrowingPayload());
            FocusTrace.Flush();
            Assert.Equal(count, _batches.Count);
        }

        private sealed class ThrowingPayload { public int Value => throw new InvalidOperationException(); }

        [Fact]
        public void QueueOverflowIsBoundedAndExplicitlyMarksLostEvidence()
        {
            for (int i = 0; i < FocusTrace.Capacity + 17; i++) FocusTrace.Record("edge");
            JObject[] rows = Read();
            Assert.Equal(FocusTrace.Capacity + 1, rows.Length);
            Assert.Equal("trace.dropped", (string)rows[0]["event"]);
            Assert.Equal(18, (int)rows[0]["count"]);
            Assert.Equal(FocusTrace.Capacity + 18, (int)rows.Last()["seq"]);
        }

        [Fact]
        public void SessionBudgetStopsObservationAndDoesNotResumeAfterDrain()
        {
            for (int i = 0; i < FocusTrace.EventBudget + 4; i++) FocusTrace.Record("edge");
            Assert.False(FocusTrace.Enabled);
            JObject[] rows = Read();
            Assert.Equal("trace.limit", (string)rows.Last()["event"]);
            int count = _batches.Count;
            FocusTrace.Record("later");
            FocusTrace.Flush();
            Assert.Equal(count, _batches.Count);
        }

        [Fact]
        public void BrokenPayloadOrSinkCannotThrowIntoInputHandler()
        {
            FocusTrace.Record("broken", new ThrowingPayload());
            FocusTrace.Start(_ => throw new InvalidOperationException(), false);
            FocusTrace.Record("input");
            FocusTrace.Flush();
            Assert.True(FocusTrace.Enabled);
        }

        [Fact]
        public void MouseMoveAndUnrelatedDesktopClicksAreExcludedAndSnapshotIsNotReceiverProof()
        {
            var point = new Point(150, 150);
            FocusTrace.SetTarget(new Rectangle(100, 100, 100, 100));
            FocusTrace.PhysicalEdge(0x0200, point, 0, 10, 7);
            FocusTrace.PhysicalEdge(0x0201, Point.Empty, 0, 11, 7);
            FocusTrace.PhysicalEdge(0x0202, Point.Empty, 0, 12, 7);
            FocusTrace.PhysicalEdge(0x0201, point, 1, 13, 7);
            string gesture = FocusTrace.HudDown(point, new IntPtr(123), "fixture");
            using (FocusTrace.UseGesture(gesture)) FocusTrace.Record("intent.created", new { intentId = "host.1" });
            FocusTrace.PhysicalEdge(0x0202, Point.Empty, 1, 14, 7);
            string unobserved = FocusTrace.HudDown(point, new IntPtr(123), "fixture");
            JObject[] rows = Read();
            Assert.Single(rows.Where(x => (string)x["event"] == "mouse.down"));
            JObject down = rows.First(x => (string)x["event"] == "mouse.down");
            Assert.True((bool)down["data"]["injected"]);
            Assert.Equal("unknown", (string)down["data"]["windows"]["actualExternalReceiver"]);
            Assert.Equal(gesture, (string)rows.Single(x => (string)x["event"] == "intent.created")["gesture"]);
            Assert.Equal("unobserved", (string)rows.Single(x => (string)x["gesture"] == unobserved)["data"]["correlation"]);
            Assert.Null(FocusTrace.Gesture);
        }
    }
}
