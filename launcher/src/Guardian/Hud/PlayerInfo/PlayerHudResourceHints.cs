#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed record PlayerHudResourceHint(string State, string Reason)
{
    internal static readonly PlayerHudResourceHint Unknown = new("unknown", "");
}
internal sealed record PlayerHudResourceNotice(long Serial, string Kind, int Slot, string Reason);
internal sealed record PlayerHudResourceHints(PlayerHudResourceHint[] Skills, PlayerHudResourceHint[] Drugs,
    PlayerHudResourceHint Weapon, bool SwitchBlocked, PlayerHudResourceNotice? Feedback);

/// <summary>Consumes authoritative denial events once. It never infers a failure from a low MP value.</summary>
internal sealed class PlayerHudDenialMotion
{
    private long _epoch, _serial;
    private int _elapsed = 650;
    private PlayerHudResourceNotice? _notice;
    internal bool Active => _notice != null && _elapsed < 650;
    internal float Alpha
    {
        get
        {
            if (!Active) return 0;
            // Two soft pulses, an immediate leading edge, then a clean stop.
            var phase = _elapsed / 325f;
            return Math.Clamp((float)(0.35 + 0.65 * Math.Sin(Math.PI * (phase % 1))), 0, 1)
                * Math.Min(1, (650 - _elapsed) / 90f);
        }
    }
    internal float MpAlpha => _notice?.Reason == "mp" ? Alpha : 0;
    internal float SlotAlpha(string kind, int slot) => _notice?.Kind == kind && _notice.Slot == slot ? Alpha : 0;
    internal bool Observe(PlayerHudSnapshot? snapshot, bool visible = true)
    {
        var wasActive = Active;
        if (snapshot == null) { _epoch = _serial = 0; Clear(); return wasActive; }
        var notice = snapshot.Resources?.Feedback;
        if (_epoch != snapshot.Epoch)
        {
            _epoch = snapshot.Epoch; _serial = notice?.Serial ?? 0; Clear();
            return wasActive; // A reconnect/full baseline cannot replay an old sound or pulse.
        }
        if (notice != null && notice.Serial > _serial)
        {
            _serial = notice.Serial;
            if (visible && !snapshot.Vitals.Paused && snapshot.Vitals.Hp > 0)
            { _notice = notice; _elapsed = 0; return true; }
        }
        if (!visible || snapshot.Vitals.Paused || snapshot.Vitals.Hp <= 0 || snapshot.Resources == null) Clear();
        return wasActive != Active;
    }
    internal bool Advance(int elapsedMs)
    {
        if (!Active || elapsedMs <= 0) return false;
        _elapsed = (int)Math.Min(650L, _elapsed + (long)elapsedMs);
        return true;
    }
    internal void Clear() { _notice = null; _elapsed = 650; }
}

internal static class PlayerHudResourceHintPainter
{
    internal static PlayerHudResourceHint Hint(PlayerHudSnapshot? snapshot, string kind, int slot)
    {
        var resources = snapshot?.Resources;
        if (resources == null) return PlayerHudResourceHint.Unknown;
        return kind switch
        {
            "skill" when slot is >= 1 and <= 12 => resources.Skills[slot - 1],
            "drug" when slot is >= 0 and <= 7 => resources.Drugs[slot % 4],
            "weapon" => resources.Weapon,
            "switch" when resources.SwitchBlocked => new("blocked", "empty"),
            _ => PlayerHudResourceHint.Unknown
        };
    }

    internal static void PaintSlot(Graphics g, RectangleF r, PlayerHudResourceHint hint, bool ready,
        int clockMs, float denialAlpha)
    {
        if (hint.State == "blocked")
        {
            using var shade = new SolidBrush(Color.FromArgb(168, 7, 10, 13));
            g.FillRectangle(shade, r.X + 1, r.Y + 1, r.Width - 2, r.Height - 2);
            using var backing = new Pen(Color.FromArgb(7, 10, 12), PlayerHudSlotFeedbackGeometry.SealLineWidth + 0.4f);
            using var lowerEdge = new Pen(Color.FromArgb(59, 59, 57), 0.8f);
            using var seal = new Pen(Color.FromArgb(218, 218, 210), PlayerHudSlotFeedbackGeometry.SealLineWidth);
            using var upperEdge = new Pen(Color.FromArgb(247, 247, 239), 0.4f);
            // Switch, weapon and skill slots share exactly the same three source-bound lines.
            // Fixed level/key bands are clipped once; live captions are composed above this layer.
            DrawSegments(g, r, PlayerHudSlotFeedbackGeometry.VisibleSeal, backing);
            // The XFL's parent BevelFilter is disabled. These narrow directional edges are a
            // native material adaptation of the slot's grey/black plate, not a restored filter.
            DrawSegments(g, r, PlayerHudSlotFeedbackGeometry.VisibleSeal, lowerEdge, -0.35f, 0.35f);
            DrawSegments(g, r, PlayerHudSlotFeedbackGeometry.VisibleSeal, seal);
            DrawSegments(g, r, PlayerHudSlotFeedbackGeometry.VisibleSeal, upperEdge, 0.3f, -0.3f);
        }
        if (hint.State == "last") PaintReserveCorners(g, r, PlayerHudSlotFeedbackGeometry.LightPhase(clockMs, ready));
        // The existing whole-frame press-denial pulse remains separate from the slow corner lights.
        var alpha = denialAlpha * 245;
        if (alpha <= 0) return;
        using var border = new Pen(Color.FromArgb((int)alpha, 235, 88, 70), 1.4f);
        using var edge = new GraphicsPath();
        edge.AddPolygon([new PointF(r.Left + 3, r.Top + 0.8f), new PointF(r.Right - 3, r.Top + 0.8f),
            new PointF(r.Right - 0.8f, r.Top + 3), new PointF(r.Right - 0.8f, r.Bottom - 3),
            new PointF(r.Right - 3, r.Bottom - 0.8f), new PointF(r.Left + 3, r.Bottom - 0.8f),
            new PointF(r.Left + 0.8f, r.Bottom - 3), new PointF(r.Left + 0.8f, r.Top + 3)]);
        g.DrawPath(border, edge);
    }

    private static void PaintReserveCorners(Graphics g, RectangleF r, float phase)
    {
        var strength = 0.3f + 0.7f * phase;
        using var outer = new Pen(Color.FromArgb((int)(22 * strength), 255, 56, 33), 5);
        using var middle = new Pen(Color.FromArgb((int)(55 * strength), 255, 52, 32), 3);
        using var inner = new Pen(Color.FromArgb((int)(130 * strength), 255, 70, 41), 1.6f);
        using var core = new Pen(Color.FromArgb((int)(255 * strength),
            (int)(236 + 19 * phase), (int)(83 + 158 * phase), (int)(57 + 158 * phase)), PlayerHudSlotFeedbackGeometry.FrameLineWidth);
        DrawSegments(g, r, PlayerHudSlotFeedbackGeometry.Corners, outer);
        DrawSegments(g, r, PlayerHudSlotFeedbackGeometry.Corners, middle);
        DrawSegments(g, r, PlayerHudSlotFeedbackGeometry.Corners, inner);
        DrawSegments(g, r, PlayerHudSlotFeedbackGeometry.Corners, core);
    }

    private static void DrawSegments(Graphics g, RectangleF r, ReadOnlySpan<PlayerHudSlotFeedbackGeometry.Segment> segments, Pen pen,
        float offsetX = 0, float offsetY = 0)
    {
        pen.StartCap = pen.EndCap = LineCap.Round;
        foreach (var line in segments)
            g.DrawLine(pen, r.X + line.Start.X + offsetX, r.Y + line.Start.Y + offsetY,
                r.X + line.End.X + offsetX, r.Y + line.End.Y + offsetY);
    }

    internal static void PaintMp(Graphics g, float alpha)
    {
        if (alpha <= 0) return;
        var bar = PlayerHudResourceLayout.MpBar;
        var left = 88 + PlayerHudResourceLayout.ResourceOffsetX;
        // Track and label stay visible even when the actual gauge is completely empty.
        using var wash = new SolidBrush(Color.FromArgb((int)(42 * alpha), 245, 104, 75));
        g.FillRectangle(wash, left, bar.Top - 16, bar.Right - left, bar.Height + 16);
        using var pen = new Pen(Color.FromArgb((int)(240 * alpha), 255, 115, 87), 1.4f);
        g.DrawLines(pen, [new PointF(left, bar.Top - 14), new PointF(left, bar.Bottom + 0.5f),
            new PointF(bar.Right - 4, bar.Bottom + 0.5f), new PointF(bar.Right, bar.Bottom - 3)]);
        using var label = new Pen(Color.FromArgb((int)(255 * alpha), 255, 203, 153), 1.2f);
        g.DrawLine(label, left + 2, bar.Top - 0.5f, left + 24, bar.Top - 0.5f);
    }
}
