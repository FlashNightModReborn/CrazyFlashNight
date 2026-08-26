using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using CF7Launcher.Guardian.HitNumbers;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tools.HitNumberVisualHarness
{
    internal sealed class ProductionPerformanceProbeResult
    {
        internal int WarmupFrames;
        internal int MeasuredFrames;
        internal int LedgerFillFrames;
        internal int HitsPerFrame;
        internal int SimulatedHits;
        internal int MaximumActiveSegments;
        internal int MaximumBackingSegments;
        internal double ElapsedMilliseconds;
        internal double AverageMillisecondsPerFrame;
        internal double ReducerLayoutMillisecondsPerFrame;
        internal double PainterMillisecondsPerFrame;
        internal long ManagedAllocatedBytes;
        internal double ManagedAllocatedBytesPerFrame;
        internal int Gen0Collections;
        internal int GdiObjectsBefore;
        internal int GdiObjectsAfter;
        internal int UserObjectsBefore;
        internal int UserObjectsAfter;
        internal int ProcessHandlesBefore;
        internal int ProcessHandlesAfter;
        internal int LedgerRetainedSegments;
        internal long LedgerDroppedSegments;
        internal int LedgerTotalBursts;
        internal int LedgerPageBursts;
        internal double LedgerMaterializeMilliseconds;
        internal long LedgerMaterializeManagedAllocatedBytes;
        internal bool HistoryBounded;
        internal bool LedgerBounded;
        internal bool GuiResourcesStable;
    }

    /// <summary>
    /// 确定性生产管线压力探针：1200 段/秒，贯穿 span parser、寿命 reducer、
    /// 默认平衡布局、短目标锚和 GDI+ Painter。世界态只按自然寿命增长；场景对账
    /// 环继续灌满到发生可观测覆盖，再在暂停态按需物化第一页 JSON。
    /// </summary>
    internal static class ProductionPerformanceProbe
    {
        private const int WarmupFrames = 180;
        private const int MeasuredFrames = 600;
        private const int LedgerFillFrames = 900;
        private const int HitsPerFrame = 20;
        private const int FramesPerSecond = 60;

        internal static ProductionPerformanceProbeResult Run()
        {
            double now = 0.0;
            var runtime = new HitNumberRuntime(() => now);
            using var painter = new HitNumberPainter();
            using var scenePainter = new HitNumberScenePainter();
            using var bitmap = new Bitmap(1600, 900, PixelFormat.Format32bppPArgb);
            using Graphics graphics = Graphics.FromImage(bitmap);
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var viewport = new RectangleF(0, 0, bitmap.Width, bitmap.Height);

            for (int frame = 0; frame < WarmupFrames; frame++)
            {
                DrawFrame(runtime, painter, scenePainter, graphics, viewport,
                    BuildPayload(frame), ref now, out _, out _);
            }

            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            ResourceSnapshot before = CaptureResources();
            long allocatedBefore = GC.GetAllocatedBytesForCurrentThread();
            int gen0Before = GC.CollectionCount(0);
            int maximumActive = runtime.StoredSegmentCountForTests;
            int maximumBacking = runtime.BackingSegmentCountForTests;
            long reducerLayoutTicks = 0;
            long painterTicks = 0;
            var stopwatch = Stopwatch.StartNew();

            for (int frame = 0; frame < MeasuredFrames; frame++)
            {
                DrawFrame(runtime, painter, scenePainter, graphics, viewport,
                    BuildPayload(WarmupFrames + frame), ref now,
                    out long frameReducerLayoutTicks, out long framePainterTicks);
                reducerLayoutTicks += frameReducerLayoutTicks;
                painterTicks += framePainterTicks;
                maximumActive = Math.Max(maximumActive, runtime.StoredSegmentCountForTests);
                maximumBacking = Math.Max(maximumBacking, runtime.BackingSegmentCountForTests);
            }

            stopwatch.Stop();
            long allocated = GC.GetAllocatedBytesForCurrentThread() - allocatedBefore;
            ResourceSnapshot after = CaptureResources();
            int gdiDelta = after.GdiObjects - before.GdiObjects;
            int userDelta = after.UserObjects - before.UserObjects;
            int handleDelta = after.ProcessHandles - before.ProcessHandles;

            int nextFrame = WarmupFrames + MeasuredFrames;
            for (int frame = 0; frame < LedgerFillFrames; frame++)
            {
                runtime.ProcessFrame("0|0|1", BuildPayload(nextFrame + frame));
                maximumActive = Math.Max(maximumActive, runtime.StoredSegmentCountForTests);
                maximumBacking = Math.Max(maximumBacking, runtime.BackingSegmentCountForTests);
                now += 1.0 / FramesPerSecond;
            }

            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            long ledgerAllocatedBefore = GC.GetAllocatedBytesForCurrentThread();
            var ledgerStopwatch = Stopwatch.StartNew();
            JObject ledger = runtime.BuildLedgerPage(0, 24);
            ledgerStopwatch.Stop();
            long ledgerAllocated = GC.GetAllocatedBytesForCurrentThread() - ledgerAllocatedBefore;
            int retained = ledger.Value<int>("retainedSegments");
            long dropped = ledger.Value<long>("droppedSegments");
            int totalBursts = ledger.Value<int>("totalBursts");
            int pageBursts = ((JArray)ledger["bursts"]).Count;

            return new ProductionPerformanceProbeResult
            {
                WarmupFrames = WarmupFrames,
                MeasuredFrames = MeasuredFrames,
                LedgerFillFrames = LedgerFillFrames,
                HitsPerFrame = HitsPerFrame,
                SimulatedHits = (WarmupFrames + MeasuredFrames + LedgerFillFrames) * HitsPerFrame,
                MaximumActiveSegments = maximumActive,
                MaximumBackingSegments = maximumBacking,
                ElapsedMilliseconds = stopwatch.Elapsed.TotalMilliseconds,
                AverageMillisecondsPerFrame = stopwatch.Elapsed.TotalMilliseconds / MeasuredFrames,
                ReducerLayoutMillisecondsPerFrame =
                    reducerLayoutTicks * 1000.0 / Stopwatch.Frequency / MeasuredFrames,
                PainterMillisecondsPerFrame =
                    painterTicks * 1000.0 / Stopwatch.Frequency / MeasuredFrames,
                ManagedAllocatedBytes = allocated,
                ManagedAllocatedBytesPerFrame = allocated / (double)MeasuredFrames,
                Gen0Collections = GC.CollectionCount(0) - gen0Before,
                GdiObjectsBefore = before.GdiObjects,
                GdiObjectsAfter = after.GdiObjects,
                UserObjectsBefore = before.UserObjects,
                UserObjectsAfter = after.UserObjects,
                ProcessHandlesBefore = before.ProcessHandles,
                ProcessHandlesAfter = after.ProcessHandles,
                LedgerRetainedSegments = retained,
                LedgerDroppedSegments = dropped,
                LedgerTotalBursts = totalBursts,
                LedgerPageBursts = pageBursts,
                LedgerMaterializeMilliseconds = ledgerStopwatch.Elapsed.TotalMilliseconds,
                LedgerMaterializeManagedAllocatedBytes = ledgerAllocated,
                HistoryBounded = maximumActive <= 1320 && maximumBacking <= 5500,
                LedgerBounded = retained == HitNumberLedgerStore.Capacity && dropped > 0 &&
                    pageBursts == 24,
                GuiResourcesStable = Math.Abs(gdiDelta) <= 2 &&
                    Math.Abs(userDelta) <= 2 && Math.Abs(handleDelta) <= 2
            };
        }

        private static void DrawFrame(
            HitNumberRuntime runtime,
            HitNumberPainter painter,
            HitNumberScenePainter scenePainter,
            Graphics graphics,
            RectangleF viewport,
            string payload,
            ref double now,
            out long reducerLayoutTicks,
            out long painterTicks)
        {
            long reducerStart = Stopwatch.GetTimestamp();
            HitNumberRuntimeSnapshot snapshot = runtime.ProcessFrame("0|0|1", payload);
            reducerLayoutTicks = Stopwatch.GetTimestamp() - reducerStart;
            long painterStart = Stopwatch.GetTimestamp();
            graphics.Clear(Color.Transparent);
            if (snapshot?.Frame != null)
            {
                scenePainter.DrawWorldRows(
                    graphics,
                    viewport,
                    snapshot.Frame.WorldRows,
                    HitNumberDisplayMode.Balanced);
                painter.Paint(graphics, snapshot.Frame.Items, new HitNumberPaintContext(viewport));
            }
            painterTicks = Stopwatch.GetTimestamp() - painterStart;
            now += 1.0 / FramesPerSecond;
        }

        private static string BuildPayload(int frame)
        {
            var payload = new StringBuilder(HitsPerFrame * 72);
            for (int hit = 0; hit < HitsPerFrame; hit++)
            {
                if (hit > 0) payload.Append(';');
                int sequence = frame * HitsPerFrame + hit;
                int flags = hit % 7 == 1 ? 2 : hit % 13 == 2 ? 8 : 0;
                int colorId = hit % 7;
                int packed = HitNumberPacking.Create(flags, false, 28, colorId);
                payload
                    .Append(80 + sequence % 421).Append('|')
                    .Append("512|400|").Append(packed).Append('|')
                    .Append(flags == 8 ? "火" : string.Empty).Append("||0|0|boss|perf-")
                    .Append(sequence.ToString(CultureInfo.InvariantCulture))
                    .Append("|1");
            }
            return payload.ToString();
        }

        private static ResourceSnapshot CaptureResources()
        {
            using Process process = Process.GetCurrentProcess();
            process.Refresh();
            return new ResourceSnapshot(
                checked((int)GetGuiResources(process.Handle, 0)),
                checked((int)GetGuiResources(process.Handle, 1)),
                process.HandleCount);
        }

        private readonly struct ResourceSnapshot
        {
            internal ResourceSnapshot(int gdiObjects, int userObjects, int processHandles)
            {
                GdiObjects = gdiObjects;
                UserObjects = userObjects;
                ProcessHandles = processHandles;
            }

            internal int GdiObjects { get; }
            internal int UserObjects { get; }
            internal int ProcessHandles { get; }
        }

        [DllImport("user32.dll")]
        private static extern uint GetGuiResources(IntPtr process, uint flags);
    }
}
