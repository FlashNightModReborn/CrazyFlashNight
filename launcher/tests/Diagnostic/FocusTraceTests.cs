using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Diagnostics;
using System.Reflection;
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
            Assert.Null(down["data"]["windows"]);
            Assert.Equal("ll_screen_cached_target", (string)down["data"]["coordinateSource"]);
            Assert.Equal(gesture, (string)rows.Single(x => (string)x["event"] == "intent.created")["gesture"]);
            Assert.Equal("position_time_candidate", (string)rows.Single(x => (string)x["gesture"] == unobserved)["data"]["correlation"]);
            Assert.Null(FocusTrace.Gesture);
        }

        [Fact]
        public void NativeHitQueriesAreBoundedAndDoNotConsumeHudCorrelation()
        {
            var point = new Point(150, 150);
            FocusTrace.SetTarget(new Rectangle(100, 100, 100, 100));
            string mouse = FocusTrace.PhysicalEdge(0x0201, point, 0, 10, 7);
            using (FocusTrace.ObserveSnapshot())
                Assert.False(FocusTrace.ShouldTraceNativeHitTest(point));
            Assert.True(FocusTrace.ShouldTraceNativeHitTest(new Point(151, 150)));
            for (int i = 0; i < 31; i++) Assert.True(FocusTrace.ShouldTraceNativeHitTest(point));
            Assert.False(FocusTrace.ShouldTraceNativeHitTest(point));
            FocusTrace.HudDown(point, new IntPtr(123), "fixture");
            Assert.Equal(mouse, (string)Read().Single(x => (string)x["event"] == "hud.down")["data"]["mouseId"]);
            FocusTrace.PhysicalEdge(0x0202, point, 0, 11, 7);
            Assert.Equal(mouse, FocusTrace.NativeMouseCandidate(point));
            FocusTrace.PhysicalEdge(0x0201, Point.Empty, 0, 12, 7);
            Assert.Equal(mouse, FocusTrace.NativeMouseCandidate(point));
        }

        [Fact]
        public void HookReturnAndBrokenHudSnapshotAreEvidenceOnly()
        {
            var point = new Point(150, 150);
            FocusTrace.SetTarget(new Rectangle(100, 100, 100, 100));
            int snapshotCalls = 0;
            FocusTrace.HudInputSnapshot = _ => { snapshotCalls++; throw new InvalidOperationException("fixture"); };
            try
            {
                string mouse = FocusTrace.PhysicalEdge(0x0201, point, 0, 10, 7);
                FocusTrace.HookChainResult(mouse, 0x0201, new IntPtr(1), Stopwatch.GetTimestamp());
                FocusTrace.HookChainResult(mouse, 0x0202, IntPtr.Zero, Stopwatch.GetTimestamp());
                JObject[] rows = Read();
                Assert.Equal(0, snapshotCalls);
                Assert.Null(rows.Single(x => (string)x["event"] == "mouse.down")["data"]["hudInput"]);
                JObject[] results = rows.Where(x => (string)x["event"] == "mouse.hook_chain_result").ToArray();
                Assert.True((bool)results[0]["data"]["suppressed"]);
                Assert.False((bool)results[1]["data"]["suppressed"]);
                Assert.DoesNotContain(rows, x => (string)x["event"] == "hud.down");
                FocusTrace.Stop();
                Assert.Null(FocusTrace.CaptureHudInput(point));
            }
            finally { FocusTrace.HudInputSnapshot = null; }
        }

        [Fact]
        public void RollingCaptureKeepsOneSessionBeyondLegacyBudgetAndDeadline()
        {
            FocusTrace.Start(_batches.Add, false, true);
            _batches.Clear();
            string session = FocusTrace.Session;
            typeof(FocusTrace).GetField("_deadline", BindingFlags.Static | BindingFlags.NonPublic).SetValue(null, -1L);
            for (int i = 0; i < FocusTrace.EventBudget + 2; i++)
            {
                FocusTrace.Record("rolling.fixture");
                if (i % 100 == 0) FocusTrace.Flush();
            }
            FocusTrace.CaptureAs2LogBatch("[FocusTraceAS2] session=wrong seq=1 event=observe_ready");
            FocusTrace.CaptureAs2LogBatch("[FocusTraceAS2] session=" + session + " seq=1 event=observe_ready detail=rolling_host_retention");
            JObject[] rows = Read();
            Assert.True(FocusTrace.Enabled);
            Assert.Equal(session, FocusTrace.Session);
            Assert.DoesNotContain(rows, x => (string)x["event"] == "trace.limit");
            Assert.Single(rows, x => (string)x["event"] == "as2.observation");
        }

        [Fact]
        public void SkillConfigurationMustBelongToCurrentSessionAndCannotLeakAcrossRestart()
        {
            FocusTrace.Start(_batches.Add, false, true);
            string keys = " v=1 seq=1 timer=1 event=keys slot=0 a=0 b=0 attempt=0 detail=65,66,67,68,69,70,71,72,73,74,75,76";
            FocusTrace.CaptureAs2LogBatch("[SkillInputAS2] session=other" + keys);
            Assert.False(FocusTrace.IsSkillKey(65));
            FocusTrace.CaptureAs2LogBatch("[SkillInputAS2] session=" + FocusTrace.Session + keys);
            Assert.True(FocusTrace.IsSkillKey(65));
            Assert.False(FocusTrace.IsSkillKey(13));
            FocusTrace.Start(_batches.Add, false, true);
            Assert.False(FocusTrace.IsSkillKey(65));
        }

        [Fact]
        public void FastOnlyProducerHonorsBoundedRecordingLimit()
        {
            for (int i = 0; i < FocusTrace.EventBudget + 5; i++)
                FocusTrace.Input("fixture.fast", new InputData { message = i });
            Assert.False(FocusTrace.Enabled);
            Assert.Single(Read(), row => (string)row["event"] == "trace.limit");
        }
    }
}
