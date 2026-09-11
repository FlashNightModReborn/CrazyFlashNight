using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public sealed class FocusTracePhysicalHistoryTests : IDisposable
    {
        private static readonly Point Target = new Point(150, 150);
        private static readonly Rectangle TargetRect = new Rectangle(100, 100, 100, 100);
        private readonly List<string> _batches = new List<string>();

        public FocusTracePhysicalHistoryTests() { Restart(); }
        public void Dispose() { FocusTrace.TickCount64Provider = null; FocusTrace.Stop(); }

        private void Restart()
        {
            FocusTrace.TickCount64Provider = null;
            FocusTrace.Stop();
            _batches.Clear();
            FocusTrace.Start(_batches.Add, false);
            FocusTrace.SetTarget(TargetRect);
        }

        private JObject[] Read()
        {
            FocusTrace.Flush();
            return _batches.SelectMany(x => x.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries))
                .Select(x => JObject.Parse(x.Substring("[FocusTrace] ".Length))).ToArray();
        }

        [Fact]
        public void BurstSamePositionClicksCorrelateFifoAndRetainAmbiguity()
        {
            const int t0 = 1000;
            string g1 = FocusTrace.PhysicalEdge(0x0201, Target, 0, t0, 7);
            FocusTrace.PhysicalEdge(0x0202, Target, 0, t0 + 80, 7);
            string g2 = FocusTrace.PhysicalEdge(0x0201, Target, 0, t0 + 300, 7);
            FocusTrace.PhysicalEdge(0x0202, Target, 0, t0 + 380, 7);

            // 消息入队时间晚于两次按下：两个未认领候选同时成立，必须保留不确定性。
            NativeMouseCorrelation first = FocusTrace.CorrelateNativeMouse(Target, 0x0201, t0 + 400, true);
            Assert.Equal(g1, first.MouseId);
            Assert.Equal("position_time_candidate", first.Kind);
            Assert.True(first.Ambiguous);
            Assert.Equal(2, first.CandidateCount);
            Assert.Equal(400.0, first.HookToMessageMs.Value);

            NativeMouseCorrelation second = FocusTrace.CorrelateNativeMouse(Target, 0x0201, t0 + 700, true);
            Assert.Equal(g2, second.MouseId);
            Assert.False(second.Ambiguous);
            Assert.Equal(1, second.CandidateCount);
            Assert.Equal(1, second.ClaimedAtPoint);

            // 全部认领完后再次引用：引用最近已认领手势，绝不编造新 id。
            NativeMouseCorrelation third = FocusTrace.CorrelateNativeMouse(Target, 0x0201, t0 + 900, true);
            Assert.Equal("repeat_reference", third.Kind);
            Assert.Equal(g2, third.MouseId);
        }

        [Fact]
        public void MessageTimeOrderingRejectsPhysicallyImpossibleCandidate()
        {
            const int t0 = 2000;
            string g1 = FocusTrace.PhysicalEdge(0x0201, Target, 0, t0, 7);
            string g2 = FocusTrace.PhysicalEdge(0x0201, Target, 0, t0 + 100, 7);
            // 入队时间落在两次 hook 之间：第二次按下物理上不可能是该消息的来源。
            NativeMouseCorrelation corr = FocusTrace.CorrelateNativeMouse(Target, 0x0201, t0 + 50, true);
            Assert.Equal(g1, corr.MouseId);
            Assert.False(corr.Ambiguous);
            Assert.Equal(1, corr.CandidateCount);
            Assert.Equal(50.0, corr.HookToMessageMs.Value);

            // 若只剩"hook 晚于消息入队"的候选，明确报时序不可能而不是硬凑。
            Restart();
            FocusTrace.PhysicalEdge(0x0201, Target, 0, 5000, 7);
            NativeMouseCorrelation impossible = FocusTrace.CorrelateNativeMouse(Target, 0x0201, 4950, true);
            Assert.Null(impossible.MouseId);
            Assert.Equal("unobserved", impossible.Kind);
            Assert.Equal("timing_after_message", impossible.Reason);
        }

        [Fact]
        public void DelayBeyondTwoSecondsStillCorrelatesAsStaleCandidate()
        {
            // 复现事故形态：hook 后 ~3.2s 消息才入队（旧实现 2000ms 硬截断会丢证据）。
            const int hook = 100000;
            string mouse = FocusTrace.PhysicalEdge(0x0201, Target, 0, hook, 7);
            NativeMouseCorrelation corr = FocusTrace.CorrelateNativeMouse(Target, 0x0201, hook + 3218, true);
            Assert.Equal(mouse, corr.MouseId);
            Assert.Equal("position_time_candidate", corr.Kind);
            Assert.True(corr.Stale);
            Assert.Equal(3218.0, corr.HookToMessageMs.Value);
            Assert.Equal("message_time", corr.DelaySource);
            Assert.True(corr.HookToObservedMs >= 0);
        }

        [Fact]
        public void MessageTimeWrapAroundDoesNotBreakDelayMath()
        {
            const uint hook = 0xFFFFFFF0;
            string mouse = FocusTrace.PhysicalEdge(0x0201, Target, 0, hook, 7);
            NativeMouseCorrelation corr = FocusTrace.CorrelateNativeMouse(Target, 0x0201, 0x20, true);
            Assert.Equal(mouse, corr.MouseId);
            Assert.Equal(48.0, corr.HookToMessageMs.Value);
            Assert.False(corr.Stale);
        }

        [Fact]
        public void RingRetentionIsBoundedAndOverflowIsExplicitlyReported()
        {
            int extra = 5;
            for (int i = 0; i < FocusTrace.PhysicalRingCapacity + extra; i++)
                Assert.Null(FocusTrace.PhysicalEdge(0x0201, new Point(1000 + i, 1000), 0, (uint)(3000 + i), 7));
            NativeMouseCorrelation corr = FocusTrace.CorrelateNativeMouse(new Point(1000, 1000), 0x0201, 4000, true);
            Assert.Equal(FocusTrace.PhysicalRingCapacity, corr.RingDepth);
            Assert.Equal((long)extra, corr.RingDropped);
            // 最早的手势已被挤出：按点找不到候选，但理由必须能区分"溢出"而非凭空否认。
            Assert.Null(corr.MouseId);
            JObject[] rows = Read();
            Assert.Equal(extra, rows.Count(x => (string)x["event"] == "mouse.ring_evict"));
            Assert.Equal(extra, (int)rows.Where(x => (string)x["event"] == "mouse.ring_evict").Last()["data"]["ringDropped"]);
        }

        [Fact]
        public void UnmatchedReasonsDistinguishEmptyMismatchStaleResidueAndConsumed()
        {
            NativeMouseCorrelation empty = FocusTrace.CorrelateNativeMouse(Target, 0x0201, 5000, true);
            Assert.Equal("no_candidate_in_ring", empty.Reason);
            Assert.Null(empty.MouseId);

            Restart();
            FocusTrace.PhysicalEdge(0x0201, new Point(160, 160), 0, 5000, 7);
            Assert.Equal("position_mismatch",
                FocusTrace.CorrelateNativeMouse(Target, 0x0201, 5100, true).Reason);

            Restart();
            FocusTrace.PhysicalEdge(0x0201, Target, 0, 5000, 7);
            Assert.Equal("stale_residue_only",
                FocusTrace.CorrelateNativeMouse(Target, 0x0201, 75000, true).Reason);

            Restart();
            string mouse = FocusTrace.PhysicalEdge(0x0201, Target, 0, 5000, 7);
            FocusTrace.HudDown(Target, new IntPtr(1), "fixture");
            FocusTrace.HudDown(Target, new IntPtr(1), "fixture");
            JObject[] rows = Read();
            JObject[] downs = rows.Where(x => (string)x["event"] == "hud.down").ToArray();
            Assert.Equal(2, downs.Length);
            Assert.Equal(mouse, (string)downs[0]["data"]["mouseId"]);
            Assert.Equal("position_time_candidate", (string)downs[0]["data"]["correlation"]);
            Assert.Equal("unobserved", (string)downs[1]["data"]["correlation"]);
            Assert.Equal("already_consumed", (string)downs[1]["data"]["detail"]["reason"]);
        }

        [Fact]
        public void UpPhasePairsByReleasePointAndReportsMissingUp()
        {
            const int t0 = 6000;
            var release = new Point(500, 500);
            string mouse = FocusTrace.PhysicalEdge(0x0201, Target, 0, t0, 7);
            FocusTrace.PhysicalEdge(0x0202, release, 0, t0 + 90, 7);
            // 原生 up 按其释放点认领，延迟用 up 自己的 hook 时刻计算。
            NativeMouseCorrelation up = FocusTrace.CorrelateNativeMouse(release, 0x0202, t0 + 200, true);
            Assert.Equal(mouse, up.MouseId);
            Assert.Equal(110.0, up.HookToMessageMs.Value);
            // 同手势在按下点查询 up：up 未在此点被观察到。
            Assert.Equal("up_not_observed",
                FocusTrace.CorrelateNativeMouse(Target, 0x0202, t0 + 200, true).Reason);

            Restart();
            FocusTrace.PhysicalEdge(0x0201, Target, 0, t0, 7);
            Assert.Equal("up_not_observed",
                FocusTrace.CorrelateNativeMouse(Target, 0x0202, t0 + 100, true).Reason);
        }

        [Fact]
        public void NativeAndHudClaimsAreIndependentAxes()
        {
            const int t0 = 8000;
            string mouse = FocusTrace.PhysicalEdge(0x0201, Target, 0, t0, 7);
            FocusTrace.HudDown(Target, new IntPtr(1), "fixture");
            // hud 轴已认领不影响原生轴：WndProc 迟到的 down 仍能认领同一候选。
            NativeMouseCorrelation native = FocusTrace.CorrelateNativeMouse(Target, 0x0201, t0 + 100, true);
            Assert.Equal(mouse, native.MouseId);
            Assert.Equal("position_time_candidate", native.Kind);
            Assert.Equal("repeat_reference",
                FocusTrace.CorrelateNativeMouse(Target, 0x0201, t0 + 150, true).Kind);
        }

        [Fact]
        public void OutOfTargetEdgesAreContextOnlyAndUnmatchedUpIsMarked()
        {
            var outside = new Point(900, 900);
            Assert.Null(FocusTrace.PhysicalEdge(0x0201, outside, 0, 9000, 7));
            Assert.Null(FocusTrace.PhysicalEdge(0x0202, outside, 0, 9100, 7));
            JObject[] rows = Read();
            JObject[] edges = rows.Where(x => (string)x["event"] == "mouse.edge").ToArray();
            Assert.Equal(2, edges.Length);
            Assert.Equal("down", (string)edges[0]["data"]["edge"]);
            Assert.False((bool)edges[0]["data"]["inTarget"]);
            Assert.Equal(JTokenType.Integer, edges[0]["data"]["foreground"].Type);
            Assert.Equal("up", (string)edges[1]["data"]["edge"]);
            Assert.DoesNotContain(rows, x => (string)x["event"] == "mouse.down" || (string)x["event"] == "mouse.up");

            // 无 open down 的 up：保留事件但显式标 unmatched，不挂到任何手势上。
            Restart();
            Assert.Null(FocusTrace.PhysicalEdge(0x0202, Target, 0, 9200, 7));
            JObject orphan = Read().Single(x => (string)x["event"] == "mouse.edge" && (string)x["data"]["edge"] == "up");
            Assert.Equal("no_open_down", (string)orphan["data"]["unmatched"]);
            Assert.Equal(JTokenType.Null, orphan["data"]["mouseId"].Type);
        }

        [Fact]
        public void RestartClearsHistoryAndDisabledTraceInventsNothing()
        {
            FocusTrace.PhysicalEdge(0x0201, Target, 0, 10000, 7);
            Restart();
            NativeMouseCorrelation cleared = FocusTrace.CorrelateNativeMouse(Target, 0x0201, 10100, true);
            Assert.Equal("no_candidate_in_ring", cleared.Reason);
            Assert.Equal(0, cleared.RingDepth);
            Assert.Equal(0L, cleared.RingDropped);

            FocusTrace.Stop();
            int batches = _batches.Count;
            Assert.Null(FocusTrace.PhysicalEdge(0x0201, Target, 0, 10200, 7));
            Assert.Equal("disabled", FocusTrace.CorrelateNativeMouse(Target, 0x0201, 10300, true).Reason);
            Assert.Null(FocusTrace.NativeMouseCandidate(Target));
            FocusTrace.Flush();
            Assert.Equal(batches, _batches.Count);
        }

        [Fact]
        public void HookDispatchDelayIsRecordedOnEveryEdge()
        {
            // hookDispatchMs 暴露 LL 钩子回调自身被 UI 线程停滞延迟的证据。
            uint nowish = unchecked((uint)Environment.TickCount);
            FocusTrace.PhysicalEdge(0x0201, Target, 0, nowish - 30u, 7);
            JObject down = Read().Single(x => (string)x["event"] == "mouse.down");
            Assert.True((long)down["data"]["hookDispatchMs"] >= 0);
            Assert.False((bool)down["data"]["hookDispatchAmbiguous"]);
        }

        [Fact]
        public void WrappingTickDeltaCrossesUint32BoundaryAndFlagsImpossible()
        {
            // wrap 穿越：earlier 在 0xFFFFFFFF 前、later 在 0 之后 → 正确的短间隔。
            Assert.Equal(32, FocusTrace.WrappingTickDeltaMs(0x10u, 0xFFFFFFF0u, out bool ambiguous));
            Assert.False(ambiguous);
            // 不可能区间：earlier"晚于"later → 真实差只能解释为 delta+2^32 的歧义。
            Assert.Equal(-16, FocusTrace.WrappingTickDeltaMs(0x10u, 0x20u, out ambiguous));
            Assert.True(ambiguous);
            Assert.Equal(0, FocusTrace.WrappingTickDeltaMs(0x55u, 0x55u, out ambiguous));
            Assert.False(ambiguous);
        }

        [Fact]
        public void HookDispatchAboveUint32UptimeUsesWrappingDomainNot64BitSubtraction()
        {
            // 模拟开机超过 2^32 ms：observed=0x1_0000_0100，hook time=0xFFFFFFF0（wrap 前）。
            // 修复前 observed - time ≈ 4.29e9 ms 的假大值；修复后低 32 位域差 = 0x110 = 272ms。
            FocusTrace.TickCount64Provider = () => 0x100000100L;
            try
            {
                string mouse = FocusTrace.PhysicalEdge(0x0201, Target, 0, 0xFFFFFFF0u, 7);
                NativeMouseCorrelation corr = FocusTrace.CorrelateNativeMouse(Target, 0x0201, 0x20u, true);
                Assert.Equal(mouse, corr.MouseId);
                Assert.Equal(272.0, corr.HookDispatchMs);
                Assert.False(corr.HookDispatchAmbiguous);
                JObject down = Read().Single(x => (string)x["event"] == "mouse.down");
                Assert.Equal(272, (int)down["data"]["hookDispatchMs"]);
                Assert.False((bool)down["data"]["hookDispatchAmbiguous"]);
            }
            finally { FocusTrace.TickCount64Provider = null; }
        }

        [Fact]
        public void ImpossibleHookIntervalIsMarkedAmbiguousNotInvented()
        {
            // hook time"晚于"观察时刻：事件不可能在未来发生——真实差是 delta+2^32 的歧义，
            // 显式标 ambiguous，不把负值当正常延迟、不臆造超大值。
            FocusTrace.TickCount64Provider = () => 0x10L;
            try
            {
                FocusTrace.PhysicalEdge(0x0201, Target, 0, 0x20u, 7);
                JObject down = Read().Single(x => (string)x["event"] == "mouse.down");
                Assert.Equal(-16, (int)down["data"]["hookDispatchMs"]);
                Assert.True((bool)down["data"]["hookDispatchAmbiguous"]);
                NativeMouseCorrelation corr = FocusTrace.CorrelateNativeMouse(Target, 0x0201, 0x30u, true);
                Assert.True(corr.HookDispatchAmbiguous);
                Assert.Equal(-16.0, corr.HookDispatchMs);
            }
            finally { FocusTrace.TickCount64Provider = null; }
        }
    }
}
