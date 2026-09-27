#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>
/// The authored slot's three L corners, in slot-local coordinates. The 26-unit
/// image is inside this frame. These 1/20-unit points come from slot-detail's
/// transforms plus DrawArt's (13, 13.1) anchor; the source-binding test guards them.
/// </summary>
internal static class PlayerHudSlotFeedbackGeometry
{
    internal const float FrameLineWidth = 0.6f;
    internal const float SealLineWidth = 1;
    internal const int BreathPeriodMilliseconds = 1500;
    internal readonly record struct Segment(PointF Start, PointF End);

    internal static readonly PointF TopLeft = new(-3, -2.75f);
    internal static readonly PointF TopPort = new(3.85f, -2.75f);
    internal static readonly PointF LeftPort = new(-3, 4.1f);
    internal static readonly PointF BottomRight = new(29.4f, 29.05f);
    internal static readonly PointF RightPort = new(29.4f, 22.2f);
    internal static readonly PointF BottomPort = new(22.55f, 29.05f);
    // Fixed text bands, independent of which digits happen to be on screen.
    internal static readonly RectangleF BadgeReserve = new(2, 0, 11, 10);
    internal static readonly RectangleF CaptionReserve = new(1, 16.5f, 24, 9);
    // Authored frame + 2.5-unit glow radius + one logical unit for antialias coverage.
    internal static readonly RectangleF MaximumPaintBounds = new(-6.5f, -6.25f, 39.4f, 38.8f);

    private static readonly Segment[] CornerLines =
    [
        new(LeftPort, TopLeft), new(TopLeft, TopPort),
        new(new(3.85f, 29.05f), new(-3, 29.05f)), new(new(-3, 29.05f), new(-3, 22.2f)),
        new(RightPort, BottomRight), new(BottomRight, BottomPort)
    ];
    private static readonly Segment[] SealLines = [new(TopPort, RightPort), new(TopLeft, BottomRight), new(LeftPort, BottomPort)];
    private static readonly Segment[] ClippedSealLines = ClipSeal();
    internal static ReadOnlySpan<Segment> Corners => CornerLines;
    internal static ReadOnlySpan<Segment> Seal => SealLines;
    internal static ReadOnlySpan<Segment> VisibleSeal => ClippedSealLines;

    internal static float LightPhase(int clockMs, bool ready)
    {
        if (!ready) return 0.55f;
        var phase = ((clockMs % BreathPeriodMilliseconds) + BreathPeriodMilliseconds) % BreathPeriodMilliseconds;
        return (float)(0.5 - 0.5 * Math.Cos(phase * Math.PI * 2 / BreathPeriodMilliseconds));
    }

    private static Segment[] ClipSeal()
    {
        var result = new List<Segment>();
        foreach (var line in SealLines)
        {
            var intervals = new List<(float Start, float End)> { (0, 1) };
            foreach (var reserve in new[] { BadgeReserve, CaptionReserve })
            {
                if (!Intersection(line, reserve, out var enter, out var leave)) continue;
                var next = new List<(float Start, float End)>();
                foreach (var interval in intervals)
                {
                    if (leave <= interval.Start || enter >= interval.End) { next.Add(interval); continue; }
                    if (enter > interval.Start) next.Add((interval.Start, enter));
                    if (leave < interval.End) next.Add((leave, interval.End));
                }
                intervals = next;
            }
            foreach (var interval in intervals)
                if (interval.End - interval.Start > 0.00001f)
                    result.Add(new(At(line, interval.Start), At(line, interval.End)));
        }
        return result.ToArray();
    }
    private static PointF At(Segment line, float t) => t <= 0 ? line.Start : t >= 1 ? line.End : new(
        line.Start.X + (line.End.X - line.Start.X) * t, line.Start.Y + (line.End.Y - line.Start.Y) * t);
    private static bool Intersection(Segment line, RectangleF r, out float enter, out float leave)
    {
        enter = 0; leave = 1;
        return ClipAxis(line.Start.X, line.End.X - line.Start.X, r.Left, r.Right, ref enter, ref leave)
            && ClipAxis(line.Start.Y, line.End.Y - line.Start.Y, r.Top, r.Bottom, ref enter, ref leave)
            && leave - enter > 0.00001f;
    }
    private static bool ClipAxis(float start, float delta, float low, float high, ref float enter, ref float leave)
    {
        if (Math.Abs(delta) < 0.00001f) return start >= low && start <= high;
        var a = (low - start) / delta; var b = (high - start) / delta;
        enter = Math.Max(enter, Math.Min(a, b)); leave = Math.Min(leave, Math.Max(a, b));
        return enter < leave;
    }
}
