using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;

namespace CF7Launcher.Guardian.Hud
{
    internal enum NativeHudTopologyDecision
    {
        Unspecified = 0,
        NotRequired,
        SingleSurfaceAccepted,
        SplitRequired,
        FlashRetained,
        Stopped
    }

    /// <summary>
    /// Geometry-only evidence for the single layered-window surface decision.
    /// It performs no rendering and never registers a production widget.
    /// </summary>
    internal sealed class NativeHudTopologyProbeResult
    {
        internal NativeHudTopologyProbeResult(
            Rectangle viewport,
            IList<Rectangle> bounds,
            Rectangle? rawOuterUnion,
            int inflatePixels,
            Rectangle? inflatedOuterUnion,
            Rectangle clippedSurface,
            long viewportPixels,
            long rawInflatedSurfacePixels,
            long submittedSurfacePixels,
            long offViewportPixels,
            long exactRectangleUnionPixels,
            int components,
            long bridgeWastePixels,
            long rawInflatedSurfaceBytes,
            long submittedSurfaceBytes,
            double amplification,
            double clippedViewportRatio,
            double exactVisibleFillRatio,
            bool fullViewportBridge,
            bool nearFullBridge,
            NativeHudTopologyDecision decision,
            long elapsedTicks)
        {
            Viewport = viewport;
            Bounds = new List<Rectangle>(bounds).AsReadOnly();
            RawOuterUnion = rawOuterUnion;
            InflatePixels = inflatePixels;
            InflatedOuterUnion = inflatedOuterUnion;
            ClippedSurface = clippedSurface;
            ViewportPixels = viewportPixels;
            RawInflatedSurfacePixels = rawInflatedSurfacePixels;
            SubmittedSurfacePixels = submittedSurfacePixels;
            OffViewportPixels = offViewportPixels;
            ExactRectangleUnionPixels = exactRectangleUnionPixels;
            Components = components;
            BridgeWastePixels = bridgeWastePixels;
            RawInflatedSurfaceBytes = rawInflatedSurfaceBytes;
            SubmittedSurfaceBytes = submittedSurfaceBytes;
            Amplification = amplification;
            ClippedViewportRatio = clippedViewportRatio;
            ExactVisibleFillRatio = exactVisibleFillRatio;
            FullViewportBridge = fullViewportBridge;
            NearFullBridge = nearFullBridge;
            RequiresDecision = fullViewportBridge || nearFullBridge;
            Decision = decision;
            DecisionValue = ToContractValue(decision);
            ElapsedTicks = elapsedTicks;
            ElapsedMilliseconds = elapsedTicks <= 0
                ? 0.0
                : elapsedTicks * 1000.0 / Stopwatch.Frequency;
        }

        public Rectangle Viewport { get; private set; }
        public IReadOnlyList<Rectangle> Bounds { get; private set; }
        public Rectangle? RawOuterUnion { get; private set; }
        public int InflatePixels { get; private set; }
        public Rectangle? InflatedOuterUnion { get; private set; }
        public Rectangle ClippedSurface { get; private set; }
        public long ViewportPixels { get; private set; }
        public long RawInflatedSurfacePixels { get; private set; }
        public long SubmittedSurfacePixels { get; private set; }
        public long OffViewportPixels { get; private set; }
        public long ExactRectangleUnionPixels { get; private set; }
        public int Components { get; private set; }
        public long BridgeWastePixels { get; private set; }
        public long RawInflatedSurfaceBytes { get; private set; }
        public long SubmittedSurfaceBytes { get; private set; }
        public double Amplification { get; private set; }
        public double ClippedViewportRatio { get; private set; }
        public double ExactVisibleFillRatio { get; private set; }
        public bool FullViewportBridge { get; private set; }
        public bool NearFullBridge { get; private set; }
        public bool RequiresDecision { get; private set; }
        public NativeHudTopologyDecision Decision { get; private set; }
        public string DecisionValue { get; private set; }
        public long ElapsedTicks { get; private set; }
        public double ElapsedMilliseconds { get; private set; }

        private static string ToContractValue(NativeHudTopologyDecision decision)
        {
            switch (decision)
            {
                case NativeHudTopologyDecision.NotRequired: return "not_required";
                case NativeHudTopologyDecision.SingleSurfaceAccepted: return "single_surface_accepted";
                case NativeHudTopologyDecision.SplitRequired: return "split_required";
                case NativeHudTopologyDecision.FlashRetained: return "flash_retained";
                case NativeHudTopologyDecision.Stopped: return "stopped";
                default: return "unspecified";
            }
        }
    }

    internal static class NativeHudTopologyProbe
    {
        public const int DefaultInflatePixels = 6;
        public const double NearFullViewportRatio = 0.90;
        public const double NearFullMaximumExactFillRatio = 0.50;

        public static NativeHudTopologyProbeResult Capture(
            Rectangle viewport,
            IEnumerable<Rectangle> bounds,
            int inflatePixels,
            NativeHudTopologyDecision decision)
        {
            long started = Stopwatch.GetTimestamp();
            ValidateViewport(viewport);
            if (bounds == null) throw new ArgumentNullException("bounds");
            if (inflatePixels < 0) throw new ArgumentOutOfRangeException("inflatePixels");
            if (!Enum.IsDefined(typeof(NativeHudTopologyDecision), decision))
                throw new ArgumentOutOfRangeException("decision");

            List<Rectangle> input = new List<Rectangle>();
            foreach (Rectangle rectangle in bounds)
            {
                ValidateRepresentable(rectangle, "bounds");
                if (IsNonEmpty(rectangle)) input.Add(rectangle);
            }
            Rectangle? rawOuterUnion = ComputeOuterUnion(input);
            Rectangle? inflatedOuterUnion = rawOuterUnion.HasValue
                ? InflateChecked(rawOuterUnion.Value, inflatePixels)
                : (Rectangle?)null;
            Rectangle clippedSurface = inflatedOuterUnion.HasValue
                ? IntersectChecked(viewport, inflatedOuterUnion.Value)
                : Rectangle.Empty;

            List<Rectangle> visibleBounds = new List<Rectangle>();
            for (int i = 0; i < input.Count; i++)
            {
                Rectangle clipped = IntersectChecked(viewport, input[i]);
                if (IsNonEmpty(clipped)) visibleBounds.Add(clipped);
            }

            long viewportPixels = Area(viewport);
            long rawInflatedSurfacePixels = inflatedOuterUnion.HasValue
                ? Area(inflatedOuterUnion.Value)
                : 0;
            long submittedSurfacePixels = Area(clippedSurface);
            long offViewportPixels = Math.Max(
                0,
                rawInflatedSurfacePixels - submittedSurfacePixels);
            long exactRectangleUnionPixels = ComputeExactUnionArea(visibleBounds);
            int components = CountConnectedComponents(visibleBounds);
            long bridgeWastePixels = Math.Max(
                0,
                submittedSurfacePixels - exactRectangleUnionPixels);
            long rawInflatedSurfaceBytes = checked(rawInflatedSurfacePixels * 4L);
            long submittedSurfaceBytes = checked(submittedSurfacePixels * 4L);
            double amplification = exactRectangleUnionPixels == 0
                ? (submittedSurfacePixels == 0 ? 0.0 : Double.PositiveInfinity)
                : (double)submittedSurfacePixels / exactRectangleUnionPixels;
            double clippedViewportRatio = viewportPixels == 0
                ? 0.0
                : (double)submittedSurfacePixels / viewportPixels;
            double exactVisibleFillRatio = submittedSurfacePixels == 0
                ? 0.0
                : (double)exactRectangleUnionPixels / submittedSurfacePixels;

            bool fullViewportBridge =
                clippedSurface == viewport &&
                components >= 2;
            bool nearFullBridge =
                clippedViewportRatio >= NearFullViewportRatio &&
                exactVisibleFillRatio <= NearFullMaximumExactFillRatio &&
                components >= 2;
            bool requiresDecision = fullViewportBridge || nearFullBridge;

            if (requiresDecision &&
                (decision == NativeHudTopologyDecision.Unspecified ||
                 decision == NativeHudTopologyDecision.NotRequired))
            {
                throw new InvalidOperationException(
                    "A full/near-full NativeHud bridge requires an explicit topology decision.");
            }

            NativeHudTopologyDecision effectiveDecision = decision;
            if (!requiresDecision && effectiveDecision == NativeHudTopologyDecision.Unspecified)
                effectiveDecision = NativeHudTopologyDecision.NotRequired;

            long elapsedTicks = Stopwatch.GetTimestamp() - started;
            return new NativeHudTopologyProbeResult(
                viewport,
                input,
                rawOuterUnion,
                inflatePixels,
                inflatedOuterUnion,
                clippedSurface,
                viewportPixels,
                rawInflatedSurfacePixels,
                submittedSurfacePixels,
                offViewportPixels,
                exactRectangleUnionPixels,
                components,
                bridgeWastePixels,
                rawInflatedSurfaceBytes,
                submittedSurfaceBytes,
                amplification,
                clippedViewportRatio,
                exactVisibleFillRatio,
                fullViewportBridge,
                nearFullBridge,
                effectiveDecision,
                elapsedTicks);
        }

        public static NativeHudTopologyProbeResult Capture(
            Rectangle viewport,
            IEnumerable<Rectangle> bounds,
            NativeHudTopologyDecision decision)
        {
            return Capture(viewport, bounds, DefaultInflatePixels, decision);
        }

        public static NativeHudTopologyProbeResult Capture(
            Rectangle viewport,
            IEnumerable<Rectangle> bounds)
        {
            return Capture(
                viewport,
                bounds,
                DefaultInflatePixels,
                NativeHudTopologyDecision.Unspecified);
        }

        private static void ValidateViewport(Rectangle viewport)
        {
            ValidateRepresentable(viewport, "viewport");
            if (!IsNonEmpty(viewport))
                throw new ArgumentOutOfRangeException("viewport");
        }

        private static void ValidateRepresentable(Rectangle rectangle, string parameterName)
        {
            if (rectangle.Width < 0 || rectangle.Height < 0)
                throw new ArgumentOutOfRangeException(
                    parameterName,
                    "Topology rectangles cannot have negative dimensions.");

            long right = (long)rectangle.X + rectangle.Width;
            long bottom = (long)rectangle.Y + rectangle.Height;
            if (right < Int32.MinValue || right > Int32.MaxValue ||
                bottom < Int32.MinValue || bottom > Int32.MaxValue)
            {
                throw new OverflowException(
                    "Topology rectangle edges exceed Int32 coordinates.");
            }
        }

        private static bool IsNonEmpty(Rectangle rectangle)
        {
            return rectangle.Width > 0 && rectangle.Height > 0;
        }

        private static Rectangle? ComputeOuterUnion(IList<Rectangle> rectangles)
        {
            Rectangle? result = null;
            for (int i = 0; i < rectangles.Count; i++)
            {
                result = result.HasValue
                    ? UnionChecked(result.Value, rectangles[i])
                    : rectangles[i];
            }
            return result;
        }

        private static Rectangle UnionChecked(Rectangle left, Rectangle right)
        {
            long unionLeft = Math.Min((long)left.X, right.X);
            long unionTop = Math.Min((long)left.Y, right.Y);
            long unionRight = Math.Max(Right(left), Right(right));
            long unionBottom = Math.Max(Bottom(left), Bottom(right));
            return FromEdgesChecked(
                unionLeft,
                unionTop,
                unionRight,
                unionBottom,
                "Topology union");
        }

        private static Rectangle IntersectChecked(Rectangle left, Rectangle right)
        {
            long intersectionLeft = Math.Max((long)left.X, right.X);
            long intersectionTop = Math.Max((long)left.Y, right.Y);
            long intersectionRight = Math.Min(Right(left), Right(right));
            long intersectionBottom = Math.Min(Bottom(left), Bottom(right));
            if (intersectionRight <= intersectionLeft ||
                intersectionBottom <= intersectionTop)
            {
                return Rectangle.Empty;
            }
            return FromEdgesChecked(
                intersectionLeft,
                intersectionTop,
                intersectionRight,
                intersectionBottom,
                "Topology intersection");
        }

        private static Rectangle InflateChecked(Rectangle rectangle, int pixels)
        {
            long left = (long)rectangle.X - pixels;
            long top = (long)rectangle.Y - pixels;
            long right = Right(rectangle) + pixels;
            long bottom = Bottom(rectangle) + pixels;
            return FromEdgesChecked(
                left,
                top,
                right,
                bottom,
                "Inflated topology bounds");
        }

        private static Rectangle FromEdgesChecked(
            long left,
            long top,
            long right,
            long bottom,
            string operation)
        {
            long width = right - left;
            long height = bottom - top;
            if (left < Int32.MinValue || left > Int32.MaxValue ||
                top < Int32.MinValue || top > Int32.MaxValue ||
                right < Int32.MinValue || right > Int32.MaxValue ||
                bottom < Int32.MinValue || bottom > Int32.MaxValue ||
                width < 0 || width > Int32.MaxValue ||
                height < 0 || height > Int32.MaxValue)
            {
                throw new OverflowException(
                    operation + " cannot be represented by System.Drawing.Rectangle.");
            }
            return new Rectangle((int)left, (int)top, (int)width, (int)height);
        }

        private static long Right(Rectangle rectangle)
        {
            return (long)rectangle.X + rectangle.Width;
        }

        private static long Bottom(Rectangle rectangle)
        {
            return (long)rectangle.Y + rectangle.Height;
        }

        private static long Area(Rectangle rectangle)
        {
            if (!IsNonEmpty(rectangle)) return 0;
            return (long)rectangle.Width * rectangle.Height;
        }

        private static long ComputeExactUnionArea(IList<Rectangle> rectangles)
        {
            if (rectangles.Count == 0) return 0;

            List<int> xCoordinates = new List<int>(rectangles.Count * 2);
            for (int i = 0; i < rectangles.Count; i++)
            {
                xCoordinates.Add(rectangles[i].Left);
                xCoordinates.Add(checked((int)Right(rectangles[i])));
            }
            xCoordinates.Sort();

            long area = 0;
            for (int xIndex = 0; xIndex + 1 < xCoordinates.Count; xIndex++)
            {
                int left = xCoordinates[xIndex];
                int right = xCoordinates[xIndex + 1];
                if (right <= left) continue;

                List<Tuple<int, int>> intervals = new List<Tuple<int, int>>();
                for (int i = 0; i < rectangles.Count; i++)
                {
                    Rectangle rectangle = rectangles[i];
                    int rectangleRight = checked((int)Right(rectangle));
                    int rectangleBottom = checked((int)Bottom(rectangle));
                    if (rectangle.Left < right && rectangleRight > left)
                        intervals.Add(Tuple.Create(rectangle.Top, rectangleBottom));
                }
                if (intervals.Count == 0) continue;

                intervals.Sort(delegate(Tuple<int, int> a, Tuple<int, int> b)
                {
                    int compare = a.Item1.CompareTo(b.Item1);
                    return compare != 0 ? compare : a.Item2.CompareTo(b.Item2);
                });

                long coveredHeight = 0;
                int currentTop = intervals[0].Item1;
                int currentBottom = intervals[0].Item2;
                for (int i = 1; i < intervals.Count; i++)
                {
                    Tuple<int, int> interval = intervals[i];
                    if (interval.Item1 <= currentBottom)
                    {
                        if (interval.Item2 > currentBottom) currentBottom = interval.Item2;
                    }
                    else
                    {
                        coveredHeight = checked(
                            coveredHeight + ((long)currentBottom - currentTop));
                        currentTop = interval.Item1;
                        currentBottom = interval.Item2;
                    }
                }
                coveredHeight = checked(
                    coveredHeight + ((long)currentBottom - currentTop));
                long stripWidth = (long)right - left;
                area = checked(area + checked(stripWidth * coveredHeight));
            }
            return area;
        }

        private static int CountConnectedComponents(IList<Rectangle> rectangles)
        {
            int count = rectangles.Count;
            if (count == 0) return 0;

            int[] parent = new int[count];
            for (int i = 0; i < count; i++) parent[i] = i;

            for (int i = 0; i < count; i++)
            {
                for (int j = i + 1; j < count; j++)
                {
                    if (AreConnected(rectangles[i], rectangles[j]))
                        Union(parent, i, j);
                }
            }

            HashSet<int> roots = new HashSet<int>();
            for (int i = 0; i < count; i++) roots.Add(Find(parent, i));
            return roots.Count;
        }

        private static bool AreConnected(Rectangle a, Rectangle b)
        {
            long aRight = Right(a);
            long bRight = Right(b);
            long aBottom = Bottom(a);
            long bBottom = Bottom(b);
            bool verticalOverlap = a.Top < bBottom && aBottom > b.Top;
            bool horizontalOverlap = a.Left < bRight && aRight > b.Left;
            if (verticalOverlap && horizontalOverlap)
            {
                return true;
            }

            return (verticalOverlap && (aRight == b.Left || bRight == a.Left)) ||
                   (horizontalOverlap && (aBottom == b.Top || bBottom == a.Top));
        }

        private static int Find(int[] parent, int index)
        {
            while (parent[index] != index)
            {
                parent[index] = parent[parent[index]];
                index = parent[index];
            }
            return index;
        }

        private static void Union(int[] parent, int left, int right)
        {
            int leftRoot = Find(parent, left);
            int rightRoot = Find(parent, right);
            if (leftRoot != rightRoot) parent[rightRoot] = leftRoot;
        }
    }
}
