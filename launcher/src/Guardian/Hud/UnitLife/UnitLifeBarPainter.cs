using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace CF7Launcher.Guardian.Hud.UnitLife;

internal enum UnitLifeBarStyle { Friendly, Hostile, Boss }

// Draws into the caller's surface and existing clip; owns no timers, controls or bitmaps.
internal static class UnitLifeBarPainter
{
    private static ColorBlend FocusGradient(UnitLifeBarStyle style, bool critical)
    {
        var (high, mid, low) = style switch
        {
            UnitLifeBarStyle.Boss => (0xE85548, 0xC61E19, 0x740E10),
            UnitLifeBarStyle.Hostile => (0xEEF1F0, 0xB4BBB9, 0x646B69),
            _ when critical => (0xFF8E7A, 0xEF3E32, 0x8E1412),
            _ => (0x9CC4CA, 0x5A9099, 0x315B63)
        };
        return new ColorBlend(3) {
            Colors = [Color.FromArgb(high | -16777216), Color.FromArgb(mid | -16777216), Color.FromArgb(low | -16777216)],
            Positions = [0f, critical ? .45f : .42f, 1f]
        };
    }

    private const float BarSlant = 2f;

    private static PointF[] SlantedBarPolygon(RectangleF track, float slant = BarSlant) =>
    [
        new(track.Left + slant, track.Top),
        new(track.Right, track.Top),
        new(track.Right - slant, track.Bottom),
        new(track.Left, track.Bottom)
    ];

    internal static void Paint(Graphics g, RectangleF track, UnitLifeBarVisual visual,
        UnitLifeBarStyle style, float eventStrength) => Paint(g,track,visual,style,eventStrength,false);

    internal static void Paint(Graphics g, RectangleF track, UnitLifeBarVisual visual,
        UnitLifeBarStyle style, float eventStrength, bool focusV38)
    {
        if (track.Width <= BarSlant || track.Height <= 0) return;
        bool isBoss = style == UnitLifeBarStyle.Boss;
        bool isEnemy = style != UnitLifeBarStyle.Friendly;
        double ratio = visual.Health.Ratio;
        double trailRatio = visual.TrailRatio;
        double healStartRatio = visual.HealStartRatio;
        float lossAlpha = visual.LossAlpha;
        float gainAlpha = visual.GainAlpha;
        bool critical = visual.Critical;
        var trackPoly = SlantedBarPolygon(track);
        using var trackPath = new GraphicsPath();
        trackPath.AddPolygon(trackPoly);

        var trackTop = isEnemy ? Color.FromArgb(244, 28, 14, 15) : Color.FromArgb(244, 14, 30, 34);
        var trackBot = isEnemy ? Color.FromArgb(244, 14, 8, 9) : Color.FromArgb(244, 8, 18, 21);
        using (var trackBg = new LinearGradientBrush(track, trackTop, trackBot, LinearGradientMode.Vertical))
            g.FillPath(trackBg, trackPath);

        float usableWidth = track.Width - BarSlant;
        var barClip = g.Save();
        try
        {
            g.SetClip(trackPath, CombineMode.Intersect);

            // 1. Damage trail (PlayerInfo DrawHpDamageTrail warm amber-crimson for enemies; ShieldRing ice-cyan for protect)
            double trailEnd = Math.Clamp(trailRatio, ratio, 1);
            if (trailEnd > ratio + 0.001 && eventStrength > 0f)
            {
                float trailAlphaScale = visual.LossActive ? Math.Max(0.35f, lossAlpha) : 1f;
                int trailAlpha = (int)Math.Clamp(Math.Round(195 * eventStrength * trailAlphaScale), 0, 255);
                if (trailAlpha > 0)
                {
                    float startX = track.X + (float)(usableWidth * ratio);
                    float endX = track.X + (float)(usableWidth * trailEnd) + BarSlant;
                    var trailRect = new RectangleF(startX - 1f, track.Y, Math.Max(2f, endX - startX + 2f), track.Height);
                    var trailTop = isEnemy
                        ? Color.FromArgb(trailAlpha, 255, 196, 128)
                        : Color.FromArgb(trailAlpha, 151, 194, 211);
                    var trailBot = isEnemy
                        ? Color.FromArgb(trailAlpha, 214, 72, 48)
                        : Color.FromArgb(trailAlpha, 84, 142, 168);
                    using var trailPolyPath = new GraphicsPath();
                    trailPolyPath.AddPolygon(new PointF[]
                    {
                        new(track.X + BarSlant + (float)(usableWidth * ratio), track.Top),
                        new(track.X + BarSlant + (float)(usableWidth * trailEnd), track.Top),
                        new(track.X + (float)(usableWidth * trailEnd), track.Bottom),
                        new(track.X + (float)(usableWidth * ratio), track.Bottom)
                    });
                    using var trailBrush = new LinearGradientBrush(trailRect, trailTop, trailBot, LinearGradientMode.Vertical);
                    g.FillPath(trailBrush, trailPolyPath);
                }
            }

            // 2. Main authoritative fill (Boss & Combat share Player HP orb deep crimson; Protect uses Player Shield #00FFFF cyan)
            if (ratio > 0)
            {
                float fillSpan = Math.Max(1.2f, (float)(usableWidth * ratio));
                using var fillPath = new GraphicsPath();
                fillPath.AddPolygon(new PointF[]
                {
                    new(track.X + BarSlant, track.Top),
                    new(track.X + BarSlant + fillSpan, track.Top),
                    new(track.X + fillSpan, track.Bottom),
                    new(track.X, track.Bottom)
                });
                using (var fillBrush = new LinearGradientBrush(track, Color.White, Color.Black, LinearGradientMode.Vertical))
                {
                    fillBrush.InterpolationColors = focusV38 ? FocusGradient(style, critical) : isEnemy
                        ? new ColorBlend(3)
                        {
                            Colors =
                            [
                                Color.FromArgb(255, 102, 86),
                                Color.FromArgb(218, 28, 22),
                                Color.FromArgb(124, 12, 14)
                            ],
                            Positions = [0f, 0.42f, 1f]
                        }
                        : new ColorBlend(3)
                        {
                            Colors =
                            [
                                Color.FromArgb(168, 255, 255),
                                Color.FromArgb(0, 236, 240),
                                Color.FromArgb(0, 142, 158)
                            ],
                            Positions = [0f, 0.42f, 1f]
                        };
                    g.FillPath(fillBrush, fillPath);
                }

                // 3. Heal preview segment (PlayerInfo DrawHpHealPreview emerald-mint #96FFC8 -> #34CD82)
                if (gainAlpha > 0f && eventStrength > 0f && ratio > healStartRatio + 0.001)
                {
                    int healA = (int)Math.Clamp(Math.Round(195 * gainAlpha * eventStrength), 0, 255);
                    if (healA > 0)
                    {
                        float hStart = (float)(usableWidth * Math.Clamp(healStartRatio, 0, ratio));
                        using var healPath = new GraphicsPath();
                        healPath.AddPolygon(new PointF[]
                        {
                            new(track.X + BarSlant + hStart, track.Top),
                            new(track.X + BarSlant + fillSpan, track.Top),
                            new(track.X + fillSpan, track.Bottom),
                            new(track.X + hStart, track.Bottom)
                        });
                        using var healBrush = new LinearGradientBrush(
                            track,
                            Color.FromArgb(healA, 150, 255, 200),
                            Color.FromArgb(healA, 52, 205, 130),
                            LinearGradientMode.Vertical);
                        g.FillPath(healBrush, healPath);
                    }
                }

                // 4. Subtle dark diagonal mesh inside filled region (translating PlayerHudHpMotion.DrawGrid)
                var meshClip = g.Save();
                try
                {
                    g.SetClip(fillPath, CombineMode.Intersect);
                    using var gridPen = new Pen(Color.FromArgb(30, 0, 0, 0), 0.65f);
                    for (float gx = track.Left - track.Height; gx < track.Left + BarSlant + fillSpan + track.Height; gx += 5.2f)
                    {
                        g.DrawLine(gridPen, gx, track.Bottom, gx + BarSlant * 1.6f, track.Top);
                    }
                }
                finally
                {
                    g.Restore(meshClip);
                }

                // 5. Top specular sheen + slanted leading blade
                var sheenColor = critical && !isEnemy && !focusV38
                    ? Color.FromArgb(225, 255, 198, 92)
                    : isEnemy
                        ? Color.FromArgb(105, 255, 224, 218)
                        : Color.FromArgb(135, 206, 255, 255);
                using (var sheen = new SolidBrush(sheenColor))
                    g.FillRectangle(sheen, track.X + BarSlant, track.Y, fillSpan, 1.15f);

                using (var bladePen = new Pen(isEnemy
                    ? Color.FromArgb(242, 255, 220, 208)
                    : Color.FromArgb(242, 220, 255, 255), 1.25f))
                {
                    g.DrawLine(bladePen,
                        track.X + fillSpan, track.Bottom,
                        track.X + BarSlant + fillSpan, track.Top);
                }
            }

            // 6. Overflow (>100%): PlayerInfo HpOverflow coral-gold (#FFBF91 -> #E77A5B) + MpOverflow diagonal stripes
            if (visual.Health.OverflowRatio > 0)
            {
                var overflowRatio = visual.Health.OverflowRatio;
                var overflowSpan = Math.Max(2f, (float)(usableWidth * overflowRatio));
                using var overPath = new GraphicsPath();
                overPath.AddPolygon(new PointF[]
                {
                    new(track.X + BarSlant, track.Top + 0.8f),
                    new(track.X + BarSlant + overflowSpan, track.Top + 0.8f),
                    new(track.X + overflowSpan, track.Bottom - 0.8f),
                    new(track.X, track.Bottom - 0.8f)
                });
                using (var overBrush = new LinearGradientBrush(
                    track,
                    Color.FromArgb(235, 255, 191, 145),
                    Color.FromArgb(235, 231, 122, 91),
                    LinearGradientMode.Vertical))
                {
                    g.FillPath(overBrush, overPath);
                }
                var overClip = g.Save();
                try
                {
                    g.SetClip(overPath, CombineMode.Intersect);
                    using var stripePen = new Pen(Color.FromArgb(195, 255, 244, 218), 0.85f);
                    for (float sx = track.Left - track.Height; sx < track.Left + BarSlant + overflowSpan + track.Height; sx += 4.5f)
                        g.DrawLine(stripePen, sx, track.Bottom, sx + track.Height, track.Top);
                }
                finally
                {
                    g.Restore(overClip);
                }
                using var overBlade = new Pen(Color.FromArgb(250, 255, 248, 220), 1.3f);
                g.DrawLine(overBlade,
                    track.X + overflowSpan, track.Bottom,
                    track.X + BarSlant + overflowSpan, track.Top);
            }

            // 7. 25% / 50% / 75% slanted tick dividers
            using var tickDark = new Pen(Color.FromArgb(155, 8, 10, 12), 0.9f);
            using var tickLight = new Pen(Color.FromArgb(42, 255, 255, 255), 0.55f);
            for (float mark = 0.25f; mark < 1f; mark += 0.25f)
            {
                float mx = track.X + usableWidth * mark;
                g.DrawLine(tickDark, mx, track.Bottom, mx + BarSlant, track.Top);
                g.DrawLine(tickLight, mx + 0.8f, track.Bottom, mx + BarSlant + 0.8f, track.Top);
            }
        }
        finally
        {
            g.Restore(barClip);
        }

        using (var trackRim = new Pen(isBoss
            ? Color.FromArgb(175, 92, 42, 40)
            : isEnemy
                ? Color.FromArgb(165, 22, 16, 18)
                : Color.FromArgb(175, 18, 62, 70), 0.65f))
        {
            g.DrawPolygon(trackRim, trackPoly);
        }
    }
}
