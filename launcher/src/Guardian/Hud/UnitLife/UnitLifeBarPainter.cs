#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace CF7Launcher.Guardian.Hud.UnitLife;

internal enum UnitLifeBarStyle { Friendly, Hostile, Boss }

internal enum UnitInfoBarTheme
{
    /// <summary>D2: Muted tactical AS2 olive-green dual-track harmonized with V3.8 gunmetal HUD.</summary>
    MutedAs2Tactical,
    /// <summary>Classic world head bar palette (#99CC00 / #00FFFF / #FFCC00 / #F47A00) for future #38 option.</summary>
    As2ClassicWorld
}

/// <summary>
/// Stateless dual-track unit info bar painter with bounded per-thread pre-baked PArgb strip cache,
/// pre-baked tactical dividers, cached slant clip paths, and zero-churn GDI+ pen/brush/alpha reuse.
/// Draws directly into the caller's surface and existing clip; owns no HWND or timers.
/// </summary>
internal static class UnitLifeBarPainter
{
    private const float FocusSlantLogical = 2f;
    private const long MaxCacheBytes = 2 * 1024 * 1024;
    private const int MaxGdiResourceEntries = 128;
    private const int AlphaBuckets = 32;

    private readonly record struct AtlasKey(
        int UpperW,
        int LowerW,
        int UpperH,
        int LowerH,
        int UpperSlantTenths,
        int LowerSlantTenths,
        bool Compact,
        UnitInfoBarTheme Theme);

    private readonly record struct PenKey(int Argb, int QuarterWidth);

    private sealed class BarStripAtlas : IDisposable
    {
        internal int StripW, UpperW, LowerW, UpperH, ShieldH, LowerH;
        internal long Bytes;
        internal Bitmap UpperEmpty = null!;
        internal Bitmap UpperResidual = null!;
        internal Bitmap UpperHp = null!;
        internal Bitmap UpperHpDark = null!;
        internal Bitmap UpperHpCritical = null!;
        internal Bitmap UpperHpCriticalDark = null!;
        internal Bitmap UpperShield = null!;
        internal Bitmap LowerEmpty = null!;
        internal Bitmap LowerInactive = null!;
        internal Bitmap LowerRigid = null!;
        internal Bitmap LowerPoise = null!;
        internal Bitmap LowerRigidPoise = null!;
        internal PointF[]? UpperPoly;
        internal PointF[]? LowerPoly;
        internal GraphicsPath? UpperClipPath;
        internal GraphicsPath? LowerClipPath;

        public void Dispose()
        {
            UpperEmpty?.Dispose();
            UpperResidual?.Dispose();
            UpperHp?.Dispose();
            UpperHpDark?.Dispose();
            UpperHpCritical?.Dispose();
            UpperHpCriticalDark?.Dispose();
            UpperShield?.Dispose();
            LowerEmpty?.Dispose();
            LowerInactive?.Dispose();
            LowerRigid?.Dispose();
            LowerPoise?.Dispose();
            LowerRigidPoise?.Dispose();
            UpperClipPath?.Dispose();
            LowerClipPath?.Dispose();
        }
    }

    private sealed class ThreadCache
    {
        internal readonly Dictionary<AtlasKey, BarStripAtlas> Atlases = new();
        internal readonly Dictionary<int, SolidBrush> Brushes = new();
        internal readonly Dictionary<PenKey, Pen> Pens = new();
        internal readonly ImageAttributes?[] AlphaAttrs = new ImageAttributes?[AlphaBuckets + 1];
        internal long AtlasBytes;

        internal void ClearAtlases()
        {
            foreach (var atlas in Atlases.Values) atlas.Dispose();
            Atlases.Clear();
            AtlasBytes = 0;
        }

        internal SolidBrush GetBrush(Color color)
        {
            int key = color.ToArgb();
            if (Brushes.TryGetValue(key, out var brush)) return brush;
            if (Brushes.Count >= MaxGdiResourceEntries)
            {
                foreach (var old in Brushes.Values) old.Dispose();
                Brushes.Clear();
            }
            brush = new SolidBrush(color);
            Brushes.Add(key, brush);
            return brush;
        }

        internal Pen GetPen(Color color, float width)
        {
            int qw = Math.Max(1, (int)Math.Round(width * 4f));
            var key = new PenKey(color.ToArgb(), qw);
            if (Pens.TryGetValue(key, out var pen)) return pen;
            if (Pens.Count >= MaxGdiResourceEntries)
            {
                foreach (var old in Pens.Values) old.Dispose();
                Pens.Clear();
            }
            pen = new Pen(color, qw * 0.25f);
            Pens.Add(key, pen);
            return pen;
        }

        internal ImageAttributes? GetAlphaAttr(float alpha)
        {
            if (alpha >= 0.995f) return null;
            int bucket = Math.Clamp((int)Math.Round(alpha * AlphaBuckets), 0, AlphaBuckets);
            if (bucket >= AlphaBuckets) return null;
            var attr = AlphaAttrs[bucket];
            if (attr == null)
            {
                attr = new ImageAttributes();
                attr.SetColorMatrix(new ColorMatrix { Matrix33 = bucket / (float)AlphaBuckets });
                AlphaAttrs[bucket] = attr;
            }
            return attr;
        }
    }

    [ThreadStatic]
    private static ThreadCache? _threadCache;

    private static ThreadCache CurrentCache => _threadCache ??= new ThreadCache();

    internal static void ClearCache()
    {
        _threadCache?.ClearAtlases();
    }

    internal static void Paint(Graphics g, RectangleF track, UnitLifeBarVisual visual,
        UnitLifeBarStyle style, float eventStrength,
        UnitInfoBarTheme theme = UnitInfoBarTheme.MutedAs2Tactical, bool slanted = true)
    {
        if (track.Width <= 2f || track.Height <= 1.5f || visual.Alpha <= 0.005f) return;

        float sx, sy, tx, ty;
        using (var transform = g.Transform)
        {
            var e = transform.Elements;
            sx = Math.Abs(e[0]);
            sy = Math.Abs(e[3]);
            tx = e[4];
            ty = e[5];
        }
        Paint(g, track, visual, style, eventStrength, sx, sy, tx, ty, theme, slanted);
    }

    /// <summary>Transform-free fast path when caller already extracted scale and device offset.</summary>
    internal static void Paint(Graphics g, RectangleF track, UnitLifeBarVisual visual,
        UnitLifeBarStyle style, float eventStrength,
        float scaleX, float scaleY, float offsetX, float offsetY,
        UnitInfoBarTheme theme = UnitInfoBarTheme.MutedAs2Tactical, bool slanted = true)
    {
        if (track.Width <= 2f || track.Height <= 1.5f || visual.Alpha <= 0.005f) return;
        if (scaleX <= 0.01f || scaleY <= 0.01f) return;

        float scale = (scaleX + scaleY) * 0.5f;
        int x0 = (int)Math.Round(track.Left * scaleX + offsetX);
        int y0 = (int)Math.Round(track.Top * scaleY + offsetY);
        int x1 = (int)Math.Round(track.Right * scaleX + offsetX);
        int y1 = (int)Math.Round(track.Bottom * scaleY + offsetY);
        int pxW = x1 - x0;
        int pxH = y1 - y0;
        if (pxW < 4 || pxH < 3) return;

        bool compact = track.Height < 6.5f;
        int gapPx = compact ? Math.Max(1, (int)Math.Round(0.6f * scaleY))
            : Math.Max(1, (int)Math.Round(1.4f * scaleY));
        int availH = Math.Max(2, pxH - gapPx);
        int upperH = Math.Max(1, (int)Math.Round(availH * (compact ? 0.62f : 0.64f)));
        int lowerH = Math.Max(1, availH - upperH);
        int lowerY = y0 + upperH + gapPx;

        float slantPx = slanted ? (compact ? 1.2f : FocusSlantLogical) * scaleX : 0f;
        if (slantPx * 2f >= pxW - 2f) slantPx = 0f;
        float upperSlantPx = slantPx * (upperH / (float)pxH);
        float lowerSlantPx = slantPx * (lowerH / (float)pxH);
        float lowerShiftX = slantPx * ((upperH + gapPx) / (float)pxH);

        int upperLeft = x0 + (int)Math.Round(slantPx - upperSlantPx);
        int upperW = Math.Max(2, pxW - (int)Math.Round(slantPx - upperSlantPx));
        int lowerLeft = x0;
        int lowerW = Math.Max(2, pxW - (int)Math.Round(lowerShiftX));
        bool useSlant = slantPx > 0.01f;

        int upSlantTenths = useSlant ? Math.Max(1, (int)Math.Round(upperSlantPx * 10f)) : 0;
        int loSlantTenths = useSlant ? Math.Max(1, (int)Math.Round(lowerSlantPx * 10f)) : 0;

        bool classicFlat = !useSlant && theme == UnitInfoBarTheme.As2ClassicWorld;
        var cache = CurrentCache;
        var atlas = GetOrBake(cache, new AtlasKey(upperW, lowerW, upperH, lowerH, upSlantTenths, loSlantTenths, compact, theme));

        double hpRatio = visual.Health.Ratio;
        double trailEnd = Math.Clamp(visual.TrailRatio, hpRatio, 1);
        double shieldRatio = Math.Clamp(visual.ShieldRatio, 0, 1);
        double poiseRatio = visual.Airborne || visual.Down ? 0 : Math.Clamp(visual.PoiseRatio, 0, 1);
        bool critical = visual.Critical && style == UnitLifeBarStyle.Friendly;
        bool darkened = visual.Darkened;
        float hitFlash = eventStrength > 0f ? Math.Clamp(visual.HitFlash * eventStrength, 0f, 1f) : 0f;
        float masterAlpha = Math.Clamp(visual.Alpha, 0f, 1f);
        ImageAttributes? alphaAttr = cache.GetAlphaAttr(masterAlpha);

        var saved = g.Save();
        try
        {
            g.ResetTransform();
            g.SmoothingMode = useSlant ? SmoothingMode.AntiAlias : SmoothingMode.None;
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;

            // ==================== 1. UPPER TRACK ====================
            int ux = useSlant ? 0 : upperLeft;
            int uy = useSlant ? 0 : y0;
            GraphicsState? upClip = null;
            if (useSlant)
            {
                g.TranslateTransform(upperLeft, y0);
                upClip = g.Save();
                g.SetClip(atlas.UpperClipPath!, CombineMode.Intersect);
            }

            try
            {
                float usableW = Math.Max(1f, upperW - upperSlantPx);
                int hpSpan = hpRatio > 0 ? Math.Max(1, (int)Math.Round(usableW * hpRatio + upperSlantPx * 0.5f)) : 0;
                hpSpan = Math.Min(upperW, hpSpan);
                int trailSpan = trailEnd > hpRatio + 0.001 && eventStrength > 0f
                    ? Math.Min(upperW, Math.Max(hpSpan, (int)Math.Round(usableW * trailEnd + upperSlantPx * 0.5f)))
                    : hpSpan;

                // 1a. Empty trough [trailSpan .. upperW]
                if (trailSpan < upperW)
                {
                    if (classicFlat && compact && alphaAttr == null)
                        g.FillRectangle(cache.GetBrush(Color.FromArgb(192, 13, 15, 17)), ux + trailSpan, uy, upperW - trailSpan, upperH);
                    else
                        BlitSlice(g, atlas.UpperEmpty, ux + trailSpan, uy, trailSpan, upperW - trailSpan, upperH, alphaAttr);
                }

                // 1b. Damage residual trail [hpSpan .. trailSpan]
                if (trailSpan > hpSpan)
                {
                    float trailFade = visual.LossActive ? Math.Max(0.35f, visual.LossAlpha) : 1f;
                    float effTrailAlpha = Math.Clamp(masterAlpha * eventStrength * trailFade, 0f, 1f);
                    if (classicFlat)
                    {
                        int ta = QuantizeAlpha(215f * effTrailAlpha);
                        if (effTrailAlpha < 0.995f)
                            BlitSlice(g, atlas.UpperEmpty, ux + hpSpan, uy, hpSpan, trailSpan - hpSpan, upperH, alphaAttr);
                        if (ta > 0)
                            g.FillRectangle(cache.GetBrush(Color.FromArgb(ta, 188, 34, 28)), ux + hpSpan, uy, trailSpan - hpSpan, upperH);
                    }
                    else if (effTrailAlpha < 0.995f)
                    {
                        // Avoid slow per-pixel GDI+ ColorMatrix blit on fading damage trails
                        BlitSlice(g, atlas.UpperEmpty, ux + hpSpan, uy, hpSpan, trailSpan - hpSpan, upperH, alphaAttr);
                        int ta = QuantizeAlpha(225f * effTrailAlpha);
                        if (ta > 0)
                            g.FillRectangle(cache.GetBrush(Color.FromArgb(ta, 224, 102, 66)), ux + hpSpan, uy, trailSpan - hpSpan, upperH);
                    }
                    else
                    {
                        BlitSlice(g, atlas.UpperResidual, ux + hpSpan, uy, hpSpan, trailSpan - hpSpan, upperH, alphaAttr);
                    }
                }

                // 1c. Main authoritative HP fill [0 .. hpSpan]
                if (hpSpan > 0)
                {
                    if (classicFlat && !darkened && !critical)
                    {
                        int ha = QuantizeAlpha(255f * masterAlpha);
                        if (ha > 0)
                            g.FillRectangle(cache.GetBrush(Color.FromArgb(ha, 0x99, 0xCC, 0x00)), ux, uy, hpSpan, upperH);
                    }
                    else
                    {
                        Bitmap hpStrip = critical
                            ? (darkened ? atlas.UpperHpCriticalDark : atlas.UpperHpCritical)
                            : (darkened ? atlas.UpperHpDark : atlas.UpperHp);
                        BlitSlice(g, hpStrip, ux, uy, 0, hpSpan, upperH, alphaAttr);
                    }

                    // Gentle hit flash lift (quantized alpha buckets to keep brush cache tiny)
                    if (hitFlash > 0.01f)
                    {
                        int fa = QuantizeAlpha(34f * hitFlash * masterAlpha);
                        if (fa > 0)
                            g.FillRectangle(cache.GetBrush(Color.FromArgb(fa, 255, 252, 232)), ux, uy, hpSpan, upperH);
                        int glintA = QuantizeAlpha(92f * hitFlash * masterAlpha);
                        if (glintA > 0)
                        {
                            int glintH = Math.Max(1, (int)Math.Round(0.8f * scaleY));
                            g.FillRectangle(cache.GetBrush(Color.FromArgb(glintA, 255, 253, 240)), ux, uy, hpSpan, Math.Min(glintH, upperH));
                        }
                    }

                    // Heal preview segment (emerald-mint)
                    if (visual.GainAlpha > 0f && eventStrength > 0f && hpRatio > visual.HealStartRatio + 0.001)
                    {
                        int healA = (int)Math.Clamp(Math.Round(195f * visual.GainAlpha * eventStrength * masterAlpha), 0, 255);
                        if (healA > 0)
                        {
                            int hStart = Math.Clamp((int)Math.Round(usableW * Math.Clamp(visual.HealStartRatio, 0, hpRatio)), 0, hpSpan);
                            if (hpSpan > hStart)
                            {
                                var hRect = new Rectangle(ux + hStart, uy, hpSpan - hStart, upperH);
                                using var hb = new LinearGradientBrush(hRect,
                                    Color.FromArgb(healA, 150, 255, 200),
                                    Color.FromArgb(healA, 52, 205, 130),
                                    LinearGradientMode.Vertical);
                                g.FillRectangle(hb, hRect);
                            }
                        }
                    }

                    // Leading edge blade (non-compact tactical focus bars only)
                    if (!compact && theme != UnitInfoBarTheme.As2ClassicWorld && hpSpan < upperW)
                    {
                        int ba = QuantizeAlpha((darkened ? 90f : 210f) * masterAlpha);
                        var blade = cache.GetPen(Color.FromArgb(ba, 255, 248, 235), Math.Max(1f, 0.9f * scale));
                        float bx = ux + usableW * (float)hpRatio;
                        g.DrawLine(blade, bx, uy + upperH, bx + upperSlantPx, uy);
                    }
                }

                // 1d. Overflow (>100%): coral-gold striped segment
                if (visual.Health.OverflowRatio > 0)
                {
                    int overSpan = Math.Min(upperW, Math.Max(2, (int)Math.Round(usableW * visual.Health.OverflowRatio)));
                    int oa = (int)Math.Clamp(Math.Round(235f * masterAlpha), 0, 255);
                    var oRect = new Rectangle(ux, uy, overSpan, upperH);
                    using var overBrush = new LinearGradientBrush(oRect,
                        Color.FromArgb(oa, 255, 191, 145),
                        Color.FromArgb(oa, 231, 122, 91),
                        LinearGradientMode.Vertical);
                    g.FillRectangle(overBrush, oRect);
                    if (!compact && useSlant)
                    {
                        int sa = QuantizeAlpha(185f * masterAlpha);
                        var stripePen = cache.GetPen(Color.FromArgb(sa, 255, 244, 218), Math.Max(0.8f, 0.75f * scale));
                        float step = Math.Max(4f, 4.5f * scale);
                        for (float sx = ux - upperH; sx < ux + overSpan + upperH; sx += step)
                            g.DrawLine(stripePen, sx, uy + upperH, sx + upperH, uy);
                    }
                }

                // 1e. Shield cap (luminous ice-cyan energy barrier hugging upper ~37-42% of HP track + dark separator)
                if (shieldRatio > 0.001)
                {
                    int shSpan = Math.Min(upperW, Math.Max(2, (int)Math.Round(usableW * shieldRatio + upperSlantPx)));
                    int shH = atlas.ShieldH;
                    int shadowH = compact ? 1 : Math.Max(1, (int)Math.Round(0.85f * scaleY));
                    if (shH < upperH)
                    {
                        int sha = QuantizeAlpha(195f * masterAlpha);
                        g.FillRectangle(cache.GetBrush(Color.FromArgb(sha, 6, 22, 28)), ux, uy + shH, shSpan, Math.Min(shadowH, upperH - shH));
                    }
                    if (classicFlat)
                    {
                        int sfa = QuantizeAlpha(255f * masterAlpha);
                        if (sfa > 0)
                            g.FillRectangle(cache.GetBrush(Color.FromArgb(sfa, 0, 245, 250)), ux, uy, shSpan, shH);
                    }
                    else
                    {
                        BlitSlice(g, atlas.UpperShield, ux, uy, 0, shSpan, shH, alphaAttr);
                    }
                    if (!compact && theme != UnitInfoBarTheme.As2ClassicWorld && shSpan < upperW)
                    {
                        int ta = QuantizeAlpha(240f * masterAlpha);
                        var tip = cache.GetPen(Color.FromArgb(ta, 235, 255, 255), Math.Max(1f, 1.0f * scale));
                        float tx = ux + upperSlantPx + usableW * (float)shieldRatio;
                        g.DrawLine(tip, tx - upperSlantPx * (shH / (float)upperH), uy + shH, tx, uy);
                    }
                }
            }
            finally
            {
                if (upClip != null) g.Restore(upClip);
            }

            // Upper outer rim
            Color upRim = shieldRatio > 0.001
                ? Color.FromArgb(QuantizeAlpha(190f * masterAlpha), 68, 198, 214)
                : hitFlash > 0.15f
                    ? Color.FromArgb(QuantizeAlpha(175f * masterAlpha), 220, 228, 214)
                    : Color.FromArgb(QuantizeAlpha(205f * masterAlpha), 14, 18, 20);
            var upRimPen = cache.GetPen(upRim, Math.Max(1f, (compact ? 0.65f : 0.75f) * scale));
            if (useSlant) g.DrawPolygon(upRimPen, atlas.UpperPoly!);
            else g.DrawRectangle(upRimPen, upperLeft, y0, Math.Max(1, upperW - 1), Math.Max(1, upperH - 1));

            // ==================== 2. LOWER TRACK (POISE + RIGID) ====================
            int lx = useSlant ? 0 : lowerLeft;
            int ly = useSlant ? 0 : lowerY;
            GraphicsState? loClip = null;
            if (useSlant)
            {
                g.TranslateTransform(lowerLeft - upperLeft, lowerY - y0);
                loClip = g.Save();
                g.SetClip(atlas.LowerClipPath!, CombineMode.Intersect);
            }

            try
            {
                float loUsableW = Math.Max(1f, lowerW - lowerSlantPx);
                int poiseSpan = visual.HasPoise && poiseRatio > 0.001
                    ? Math.Min(lowerW, Math.Max(1, (int)Math.Round(loUsableW * poiseRatio + lowerSlantPx * 0.5f)))
                    : 0;

                Bitmap emptyStrip = visual.Rigid
                    ? atlas.LowerRigid
                    : (visual.Airborne || visual.Down ? atlas.LowerInactive : atlas.LowerEmpty);
                Bitmap poiseStrip = visual.Rigid ? atlas.LowerRigidPoise : atlas.LowerPoise;

                if (poiseSpan > 0)
                    BlitSlice(g, poiseStrip, lx, ly, 0, poiseSpan, lowerH, alphaAttr);
                if (poiseSpan < lowerW)
                    BlitSlice(g, emptyStrip, lx + poiseSpan, ly, poiseSpan, lowerW - poiseSpan, lowerH, alphaAttr);
            }
            finally
            {
                if (loClip != null) g.Restore(loClip);
            }

            Color loRim = visual.Rigid
                ? Color.FromArgb(QuantizeAlpha(232f * masterAlpha), 255, 158, 56)
                : Color.FromArgb(QuantizeAlpha(178f * masterAlpha), 18, 22, 25);
            var loRimPen = cache.GetPen(loRim, Math.Max(1f, (visual.Rigid ? 0.85f : 0.65f) * scale));
            if (useSlant) g.DrawPolygon(loRimPen, atlas.LowerPoly!);
            else g.DrawRectangle(loRimPen, lowerLeft, lowerY, Math.Max(1, lowerW - 1), Math.Max(1, lowerH - 1));
        }
        finally
        {
            g.Restore(saved);
        }
    }

    private static int QuantizeAlpha(float raw)
    {
        int a = (int)Math.Clamp(Math.Round(raw), 0, 255);
        if (a <= 0) return 0;
        if (a >= 252) return 255;
        return (a + 2) & ~3; // 4-step alpha bucket (<= 2/255 imperceptible, bounds pen/brush cache tightly)
    }

    private static void BlitSlice(Graphics g, Bitmap strip, int dstX, int dstY, int srcX, int width, int height, ImageAttributes? attr)
    {
        if (width <= 0 || height <= 0) return;
        int safeSrcX = Math.Clamp(srcX, 0, Math.Max(0, strip.Width - 1));
        int safeW = Math.Min(width, strip.Width - safeSrcX);
        if (safeW <= 0) return;
        var dst = new Rectangle(dstX, dstY, safeW, height);
        if (attr == null)
            g.DrawImage(strip, dst, safeSrcX, 0, safeW, height, GraphicsUnit.Pixel);
        else
            g.DrawImage(strip, dst, safeSrcX, 0, safeW, height, GraphicsUnit.Pixel, attr);
    }

    private static PointF[] SlantPoly(int width, int height, float slant) =>
    [
        new(slant, 0f),
        new(width, 0f),
        new(width - slant, height),
        new(0f, height)
    ];

    private static BarStripAtlas GetOrBake(ThreadCache cache, AtlasKey key)
    {
        if (cache.Atlases.TryGetValue(key, out var existing)) return existing;
        var created = BakeAtlas(key);
        if (cache.AtlasBytes + created.Bytes > MaxCacheBytes)
            cache.ClearAtlases();
        cache.Atlases.Add(key, created);
        cache.AtlasBytes += created.Bytes;
        return created;
    }

    private static BarStripAtlas BakeAtlas(AtlasKey key)
    {
        int uw = key.UpperW, lw = key.LowerW, uh = key.UpperH, lh = key.LowerH;
        int w = Math.Max(uw, lw);
        bool classic = key.Theme == UnitInfoBarTheme.As2ClassicWorld;
        bool compact = key.Compact;
        bool bakeDividers = !compact && !classic;
        float upSlant = key.UpperSlantTenths * 0.1f;
        float loSlant = key.LowerSlantTenths * 0.1f;
        int sh = Math.Max(1, Math.Min(uh, (int)Math.Round(uh * (compact ? 0.42f : 0.37f))));

        PointF[]? upperPoly = null, lowerPoly = null;
        GraphicsPath? upperPath = null, lowerPath = null;
        if (key.UpperSlantTenths > 0)
        {
            upperPoly = SlantPoly(uw, uh, upSlant);
            upperPath = new GraphicsPath();
            upperPath.AddPolygon(upperPoly);
            lowerPoly = SlantPoly(lw, lh, loSlant);
            lowerPath = new GraphicsPath();
            lowerPath.AddPolygon(lowerPoly);
        }

        var atlas = new BarStripAtlas
        {
            StripW = w,
            UpperW = uw,
            LowerW = lw,
            UpperH = uh,
            ShieldH = sh,
            LowerH = lh,
            Bytes = (long)w * (6L * uh + sh + 5L * lh) * 4L,
            UpperEmpty = BakeUpperEmpty(w, uw, uh, compact, classic, bakeDividers, upSlant),
            UpperResidual = BakeUpperResidual(w, uw, uh, classic, bakeDividers, upSlant),
            UpperHp = BakeUpperHp(w, uw, uh, compact, classic ? (0x99CC00, 0x99CC00, 0x99CC00) : (0xA4D448, 0x79AE24, 0x4B7012), darkened: false, bakeDividers, upSlant),
            UpperHpDark = BakeUpperHp(w, uw, uh, compact, classic ? (0x4E8100, 0x4E8100, 0x4E8100) : (0x5C7728, 0x446214, 0x2A3F0A), darkened: true, bakeDividers, upSlant),
            UpperHpCritical = BakeUpperHp(w, uw, uh, compact, (0xF27A6A, 0xD9382E, 0x821412), darkened: false, bakeDividers, upSlant),
            UpperHpCriticalDark = BakeUpperHp(w, uw, uh, compact, (0x88443B, 0x791F1A, 0x490B0A), darkened: true, bakeDividers, upSlant),
            UpperShield = BakeUpperShield(w, sh, classic),
            LowerEmpty = BakeLowerStrip(w, lh, compact, classic, rigid: false, poise: false, inactive: false),
            LowerInactive = BakeLowerStrip(w, lh, compact, classic, rigid: false, poise: false, inactive: true),
            LowerRigid = BakeLowerStrip(w, lh, compact, classic, rigid: true, poise: false, inactive: false),
            LowerPoise = BakeLowerStrip(w, lh, compact, classic, rigid: false, poise: true, inactive: false),
            LowerRigidPoise = BakeLowerStrip(w, lh, compact, classic, rigid: true, poise: true, inactive: false),
            UpperPoly = upperPoly,
            LowerPoly = lowerPoly,
            UpperClipPath = upperPath,
            LowerClipPath = lowerPath
        };
        return atlas;
    }

    private static Color Rgb(int v, int a = 255) => Color.FromArgb(a, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);

    private static void DrawBakedUpperDividers(Graphics g, int upperW, int h, float upperSlant)
    {
        float usableW = Math.Max(1f, upperW - upperSlant);
        float scale = Math.Max(1f, h / 6.5f);
        using var tickDark = new Pen(Color.FromArgb(140, 8, 10, 12), Math.Max(1f, 0.8f * scale));
        using var tickLight = new Pen(Color.FromArgb(34, 255, 255, 255), Math.Max(0.75f, 0.45f * scale));
        for (float mark = 0.25f; mark < 1f; mark += 0.25f)
        {
            float mx = usableW * mark;
            g.DrawLine(tickDark, mx, h, mx + upperSlant, 0);
            g.DrawLine(tickLight, mx + 0.8f * scale, h, mx + upperSlant + 0.8f * scale, 0);
        }
    }

    private static Bitmap BakeUpperEmpty(int w, int uw, int h, bool compact, bool classic, bool bakeDividers, float upSlant)
    {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new Rectangle(0, 0, w, h);
        using (var bg = new LinearGradientBrush(rect,
            classic ? Color.FromArgb(185, 16, 19, 21) : Color.FromArgb(245, 18, 21, 24),
            classic ? Color.FromArgb(200, 10, 12, 14) : Color.FromArgb(245, 10, 12, 14),
            LinearGradientMode.Vertical))
        {
            g.FillRectangle(bg, rect);
        }
        if (!compact)
        {
            using var rib = new Pen(Color.FromArgb(classic ? 34 : 22, 255, 255, 255), Math.Max(1f, h * 0.10f));
            float pitch = Math.Max(8f, h * 1.35f);
            for (float rx = -h; rx < w + h; rx += pitch)
                g.DrawLine(rib, rx, h, rx + h * 0.65f, 0);
        }
        if (bakeDividers) DrawBakedUpperDividers(g, uw, h, upSlant);
        return bmp;
    }

    private static Bitmap BakeUpperResidual(int w, int uw, int h, bool classic, bool bakeDividers, float upSlant)
    {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new Rectangle(0, 0, w, h);
        using var grad = new LinearGradientBrush(rect,
            classic ? Color.FromArgb(215, 210, 42, 34) : Color.FromArgb(225, 245, 148, 92),
            classic ? Color.FromArgb(215, 140, 22, 18) : Color.FromArgb(225, 196, 54, 42),
            LinearGradientMode.Vertical);
        g.FillRectangle(grad, rect);
        if (bakeDividers) DrawBakedUpperDividers(g, uw, h, upSlant);
        return bmp;
    }

    private static Bitmap BakeUpperHp(int w, int uw, int h, bool compact, (int Hi, int Mid, int Lo) pal, bool darkened, bool bakeDividers, float upSlant)
    {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new Rectangle(0, 0, w, h);
        using (var grad = new LinearGradientBrush(rect, Rgb(pal.Hi), Rgb(pal.Lo), LinearGradientMode.Vertical))
        {
            grad.InterpolationColors = new ColorBlend(3)
            {
                Colors = [Rgb(pal.Hi), Rgb(pal.Mid), Rgb(pal.Lo)],
                Positions = [0f, 0.44f, 1f]
            };
            g.FillRectangle(grad, rect);
        }
        if (darkened && !compact)
        {
            using var hatch = new Pen(Color.FromArgb(68, 0, 0, 0), Math.Max(1f, h * 0.12f));
            float step = Math.Max(5f, h * 0.72f);
            for (float x = -h; x < w + h; x += step)
                g.DrawLine(hatch, x, h, x + h, 0);
        }
        else if (!darkened && !compact)
        {
            using var sheen = new SolidBrush(Color.FromArgb(88, 255, 255, 255));
            g.FillRectangle(sheen, 0, 0, w, Math.Max(1, h / 6));
        }
        if (bakeDividers) DrawBakedUpperDividers(g, uw, h, upSlant);
        return bmp;
    }

    private static Bitmap BakeUpperShield(int w, int h, bool classic)
    {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(bmp);
        var rect = new Rectangle(0, 0, w, h);
        using var grad = new LinearGradientBrush(rect,
            classic ? Color.FromArgb(255, 0, 255, 255) : Color.FromArgb(252, 174, 255, 255),
            classic ? Color.FromArgb(255, 0, 224, 232) : Color.FromArgb(252, 16, 206, 222),
            LinearGradientMode.Vertical);
        g.FillRectangle(grad, rect);
        return bmp;
    }

    private static Bitmap BakeLowerStrip(int w, int h, bool compact, bool classic, bool rigid, bool poise, bool inactive)
    {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new Rectangle(0, 0, w, h);

        if (rigid)
        {
            using var bg = new LinearGradientBrush(rect,
                classic ? Color.FromArgb(255, 244, 122, 0) : Color.FromArgb(252, 232, 114, 24),
                classic ? Color.FromArgb(255, 196, 86, 0) : Color.FromArgb(252, 152, 54, 8),
                LinearGradientMode.Vertical);
            g.FillRectangle(bg, rect);
        }
        else
        {
            using var bg = new SolidBrush(classic ? Color.FromArgb(190, 28, 32, 36) : Color.FromArgb(238, 20, 24, 27));
            g.FillRectangle(bg, rect);
            if (inactive && !compact)
            {
                using var hatch = new HatchBrush(HatchStyle.ForwardDiagonal,
                    Color.FromArgb(165, 58, 70, 76), Color.FromArgb(28, 18, 22, 26));
                g.FillRectangle(hatch, rect);
            }
        }

        if (poise)
        {
            int inset = rigid && !compact && h >= 5 ? 1 : 0;
            var pRect = new Rectangle(0, inset, w, Math.Max(1, h - inset * 2));
            Color pTop = rigid
                ? Color.FromArgb(252, 255, 230, 108)
                : (classic ? Color.FromArgb(255, 255, 212, 32) : Color.FromArgb(248, 242, 202, 74));
            Color pBot = rigid
                ? Color.FromArgb(252, 228, 152, 22)
                : (classic ? Color.FromArgb(255, 212, 148, 0) : Color.FromArgb(248, 186, 134, 24));
            using var pb = new LinearGradientBrush(pRect, pTop, pBot, LinearGradientMode.Vertical);
            g.FillRectangle(pb, pRect);
        }

        // Segmented tactical cell dividers (20 cells on wide focus bars; 10 cells on narrow/world bars)
        if (!compact || w >= 64)
        {
            int cells = w >= 180 ? 20 : 10;
            float cellW = w / (float)cells;
            float penScale = Math.Max(1f, h / 5f);
            using var cutDark = new Pen(Color.FromArgb(rigid ? 165 : 195, 10, 12, 14), Math.Max(1f, 0.85f * penScale));
            using var cutHi = new Pen(Color.FromArgb(rigid ? 72 : 42, 255, 240, 210), Math.Max(0.75f, 0.45f * penScale));
            using var majorPen = new Pen(Color.FromArgb(228, 6, 8, 10), Math.Max(1.25f, 1.2f * penScale));
            for (int i = 1; i < cells; i++)
            {
                float cx = i * cellW;
                if (cells == 20 && i % 5 == 0)
                {
                    g.DrawLine(majorPen, cx, 0, cx, h);
                }
                else
                {
                    g.DrawLine(cutDark, cx, 0, cx, h);
                    g.DrawLine(cutHi, cx + 0.8f * penScale, 0, cx + 0.8f * penScale, h);
                }
            }
        }
        return bmp;
    }
}
