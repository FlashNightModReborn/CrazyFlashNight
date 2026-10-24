#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Multi-target strip (protect / boss / combat) in the Buff surface with portraits, clock-driven damage trail &amp; heal preview, chamfered/slanted geometry, and Aero numerals.</summary>
internal sealed class PlayerHudFocusTargetWidget : PlayerHudWidgetBase, INativeHudPointerSnapshot
{
    internal const float RowHeight = 30f;
    internal const float RowGap = 3f;
    internal const float BarSlant = 2.0f;
    internal const int LossHoldMs = 90;
    internal const int LossDecayMs = 230;
    internal const int LossTotalMs = LossHoldMs + LossDecayMs;
    internal const int CumulativeLossWindowMs = 260;
    internal const int GainDurationMs = 360;
    internal const int ComboPulseDurationMs = 150;
    internal const int CriticalBreathPeriodMs = 1300;
    internal const double HealPreviewThreshold = 0.055;
    internal const float HpReadoutMaxWidth = 92f;
    internal const double ExactHpCompactThreshold = 1_000_000;

    private static float SmoothStep(float t)
    {
        t = Math.Clamp(t, 0f, 1f);
        return t * t * (3f - 2f * t);
    }

    private sealed class TargetVisualState
    {
        internal double PreviousRatio;
        internal double TrailAnchorRatio;
        internal double TrailRatio;
        internal double HealStartRatio;
        internal int LossAgeMs = LossTotalMs;
        internal int WindowLossAgeMs = CumulativeLossWindowMs;
        internal int GainAgeMs = GainDurationMs;
        internal int LastHits;
        internal int ComboPulseAgeMs = ComboPulseDurationMs;
        internal bool Critical;

        internal float LossAlpha => LossAgeMs >= LossTotalMs
            ? 0f
            : LossAgeMs <= LossHoldMs
                ? 1f
                : Math.Clamp(1f - (LossAgeMs - LossHoldMs) / (float)LossDecayMs, 0f, 1f);

        internal float GainAlpha => GainAgeMs >= GainDurationMs
            ? 0f
            : Math.Clamp(1f - GainAgeMs / (float)GainDurationMs, 0f, 1f);

        internal float ComboPulse => ComboPulseAgeMs >= ComboPulseDurationMs
            ? 0f
            : Math.Clamp(1f - ComboPulseAgeMs / (float)ComboPulseDurationMs, 0f, 1f);

        internal bool HasActiveTransition =>
            (LossAgeMs < LossTotalMs && TrailRatio > PreviousRatio + 0.0005)
            || (GainAgeMs < GainDurationMs && PreviousRatio > HealStartRatio + 0.0005)
            || ComboPulseAgeMs < ComboPulseDurationMs;
    }

    private readonly Font _font = NativeHudFonts.CreateUiFont(12, FontStyle.Regular, GraphicsUnit.Pixel);
    private readonly Font _badgeFont = NativeHudFonts.CreateRoleFont("native.player-info.body", 9.5f, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _initialFont = NativeHudFonts.CreateRoleFont("native.player-info.body", 11f, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly PlayerHudTextCache _numbers = new();
    private readonly Control _anchor;
    private readonly LootIconCatalog? _icons;
    private IDollBakeSink? _dollBake;
    private readonly Dictionary<long, TargetVisualState> _states = new();
    private readonly HashSet<string> _requestedDolls = new(StringComparer.Ordinal);
    private PlayerHudFocusTarget[] _lastTargets = Array.Empty<PlayerHudFocusTarget>();
    private RectangleF _lastLayout;
    private bool _lastSuppressed;
    private long _epoch;
    private string? _hoverKey;
    private int _criticalClockMs;

    protected override bool HasContent => Snapshot is { TargetList.Length: > 0 };
    protected override RectangleF LogicalBounds => BoundsForBuffCount(Snapshot?.BuffCards.Length ?? 0, Math.Max(1, Snapshot?.TargetList.Length ?? 0));
    internal double TrailRatio => Snapshot?.FocusTarget is { } t && _states.TryGetValue(t.Id, out var st) ? st.TrailRatio : 0;
    internal bool IsCritical => Snapshot?.FocusTarget is { } t && _states.TryGetValue(t.Id, out var st) && st.Critical;
    internal double GetTrailRatio(long id) => _states.TryGetValue(id, out var st) ? st.TrailRatio : 0;
    internal bool IsTargetCritical(long id) => _states.TryGetValue(id, out var st) && st.Critical;
    internal float GetHealAlpha(long id) => _states.TryGetValue(id, out var st) ? st.GainAlpha : 0f;
    internal float GetComboPulse(long id) => _states.TryGetValue(id, out var st) ? st.ComboPulse : 0f;

    public override bool WantsAnimationTick =>
        Visible
        && !PlayerHudMotionSettings.StaticFeedback
        && Snapshot is { Vitals.Paused: false }
        && _states.Values.Any(st => st.HasActiveTransition || (st.Critical && !PlayerHudMotionSettings.ReducedMotion));

    // Keep the complete strip in the left column, clear of the widest centered
    // notch and its wave/pause rows. Compact to y=4 when no Buffs are active.
    internal static RectangleF BoundsForBuffCount(int count, int targetCount = 1)
    {
        int rows = Math.Clamp(targetCount, 1, 4);
        float top = (int)Math.Ceiling(Math.Clamp(count, 0, 256) / 32d) * NativeHudTheme.TopBarHeightBase + 4;
        float width = (1024 - RightHudLayout.PreferredNotchMaxWidthBase) / 2f - RightHudLayout.NotchRightGapBase - 6;
        float height = rows * RowHeight + (rows - 1) * RowGap;
        return new(6, top, width, height);
    }

    internal static RectangleF RowBounds(int buffCount, int rowIndex)
    {
        var single = BoundsForBuffCount(buffCount, 1);
        return new(single.X, single.Y + rowIndex * (RowHeight + RowGap), single.Width, RowHeight);
    }

    internal PlayerHudFocusTargetWidget(Control anchor, PlayerHudController controller,
        LootIconCatalog? icons = null, IDollBakeSink? dollBake = null) : base(anchor, controller)
    {
        _anchor = anchor;
        _icons = icons;
        _dollBake = dollBake;
        OnStateChanged();
    }

    internal void SetPortraitBakeSink(IDollBakeSink? dollBake)
    {
        _dollBake = dollBake;
        RequestPendingDollPortraits(Snapshot?.TargetList);
    }

    internal void NotifyPortraitReady(string key)
    {
        if (string.IsNullOrEmpty(key) || _anchor.IsDisposed) return;
        if (_anchor.InvokeRequired)
        {
            try { _anchor.BeginInvoke(new Action(() => NotifyPortraitReady(key))); }
            catch (ObjectDisposedException) { }
            return;
        }
        _icons?.InvalidateDoll(key);
        _requestedDolls.Remove(key);
        if (Snapshot?.TargetList.Any(t => string.Equals(t.PortraitKey, key, StringComparison.Ordinal)) == true)
            Repaint();
    }

    private void RequestPendingDollPortraits(PlayerHudFocusTarget[]? targets)
    {
        if (_dollBake == null || targets == null) return;
        foreach (var target in targets)
        {
            if (target.Doll == null || string.IsNullOrEmpty(target.PortraitKey)) continue;
            if (!_requestedDolls.Add(target.PortraitKey)) continue;
            try { _dollBake.EnsurePortrait(target.Doll, target.PortraitKey); }
            catch { }
        }
    }

    protected override void OnStateChanged()
    {
        var s = Snapshot;
        if (s?.Epoch != _epoch)
        {
            _epoch = s?.Epoch ?? 0;
            _states.Clear();
            _requestedDolls.Clear();
            _criticalClockMs = 0;
            CancelHover();
        }
        var targets = s?.TargetList ?? Array.Empty<PlayerHudFocusTarget>();
        if (_hoverKey != null && (s == null || !targets.Any(t => t.Id.ToString(CultureInfo.InvariantCulture) == _hoverKey)))
            CancelHover();

        if (targets.Length == 0)
        {
            _states.Clear();
            _criticalClockMs = 0;
        }
        else if (!targets.SequenceEqual(_lastTargets))
        {
            var activeIds = new HashSet<long>();
            foreach (var target in targets)
            {
                activeIds.Add(target.Id);
                var ratio = Math.Clamp(target.Hp / target.HpMax, 0, 1);
                if (!_states.TryGetValue(target.Id, out var st))
                {
                    st = new TargetVisualState
                    {
                        PreviousRatio = ratio,
                        TrailAnchorRatio = ratio,
                        TrailRatio = ratio,
                        HealStartRatio = ratio,
                        LossAgeMs = LossTotalMs,
                        WindowLossAgeMs = CumulativeLossWindowMs,
                        GainAgeMs = GainDurationMs,
                        LastHits = target.Hits,
                        ComboPulseAgeMs = target.Hits > 0 && !PlayerHudMotionSettings.StaticFeedback ? 0 : ComboPulseDurationMs,
                        Critical = false
                    };
                    _states[target.Id] = st;
                }
                else
                {
                    if (PlayerHudMotionSettings.StaticFeedback)
                    {
                        st.PreviousRatio = ratio;
                        st.TrailAnchorRatio = ratio;
                        st.TrailRatio = ratio;
                        st.HealStartRatio = ratio;
                        st.LossAgeMs = LossTotalMs;
                        st.WindowLossAgeMs = CumulativeLossWindowMs;
                        st.GainAgeMs = GainDurationMs;
                        st.ComboPulseAgeMs = ComboPulseDurationMs;
                    }
                    else
                    {
                        if (ratio < st.PreviousRatio - 0.0005)
                        {
                            double anchor = st.LossAgeMs < LossTotalMs || st.WindowLossAgeMs < CumulativeLossWindowMs
                                ? Math.Max(st.TrailAnchorRatio, Math.Max(st.TrailRatio, st.PreviousRatio))
                                : Math.Max(st.TrailRatio, st.PreviousRatio);
                            st.TrailAnchorRatio = anchor;
                            st.TrailRatio = anchor;
                            st.PreviousRatio = ratio;
                            st.LossAgeMs = 0;
                            st.WindowLossAgeMs = 0;
                            st.GainAgeMs = GainDurationMs;
                        }
                        else if (ratio > st.PreviousRatio + 0.0005)
                        {
                            var gain = ratio - st.PreviousRatio;
                            if (gain >= HealPreviewThreshold)
                            {
                                st.HealStartRatio = st.PreviousRatio;
                                st.GainAgeMs = 0;
                            }
                            st.PreviousRatio = ratio;
                            if (ratio >= st.TrailRatio)
                            {
                                st.TrailRatio = ratio;
                                st.TrailAnchorRatio = ratio;
                                st.LossAgeMs = LossTotalMs;
                            }
                        }

                        if (target.Hits > st.LastHits && target.Hits > 0)
                            st.ComboPulseAgeMs = 0;
                        else if (target.Hits <= 0)
                            st.ComboPulseAgeMs = ComboPulseDurationMs;
                    }
                    st.LastHits = target.Hits;
                }
                st.Critical = target.Hp > 0 && target.HpMax > 0 && ratio <= (st.Critical ? 0.30 : 0.25);
            }
            var staleIds = _states.Keys.Where(id => !activeIds.Contains(id)).ToArray();
            foreach (var staleId in staleIds) _states.Remove(staleId);
            RequestPendingDollPortraits(targets);
        }

        var layout = LogicalBounds;
        if (targets.SequenceEqual(_lastTargets) && layout == _lastLayout && Suppressed == _lastSuppressed) return;
        _lastTargets = targets; _lastLayout = layout; _lastSuppressed = Suppressed;
        base.OnStateChanged();
    }

    public override void Tick(int deltaMs)
    {
        if (!Visible || Snapshot == null || deltaMs <= 0) return;
        int step = Math.Max(0, deltaMs);
        bool changed = false;

        foreach (var st in _states.Values)
        {
            if (st.WindowLossAgeMs < CumulativeLossWindowMs)
                st.WindowLossAgeMs = (int)Math.Min(CumulativeLossWindowMs, (long)st.WindowLossAgeMs + step);

            if (st.LossAgeMs < LossTotalMs)
            {
                st.LossAgeMs = (int)Math.Min(LossTotalMs, (long)st.LossAgeMs + step);
                if (st.LossAgeMs >= LossTotalMs)
                {
                    st.TrailRatio = st.PreviousRatio;
                    st.TrailAnchorRatio = st.PreviousRatio;
                }
                else if (st.LossAgeMs <= LossHoldMs)
                {
                    st.TrailRatio = st.TrailAnchorRatio;
                }
                else
                {
                    float t = SmoothStep((st.LossAgeMs - LossHoldMs) / (float)LossDecayMs);
                    st.TrailRatio = st.TrailAnchorRatio + (st.PreviousRatio - st.TrailAnchorRatio) * t;
                }
                changed = true;
            }

            if (st.GainAgeMs < GainDurationMs)
            {
                int oldBucket = st.GainAgeMs / 25;
                st.GainAgeMs = (int)Math.Min(GainDurationMs, (long)st.GainAgeMs + step);
                if (st.GainAgeMs >= GainDurationMs) st.HealStartRatio = st.PreviousRatio;
                changed |= st.GainAgeMs / 25 != oldBucket || st.GainAgeMs >= GainDurationMs;
            }

            if (st.ComboPulseAgeMs < ComboPulseDurationMs)
            {
                int oldBucket = st.ComboPulseAgeMs / 25;
                st.ComboPulseAgeMs = (int)Math.Min(ComboPulseDurationMs, (long)st.ComboPulseAgeMs + step);
                changed |= st.ComboPulseAgeMs / 25 != oldBucket || st.ComboPulseAgeMs >= ComboPulseDurationMs;
            }
        }

        if (!PlayerHudMotionSettings.ReducedMotion && _states.Values.Any(st => st.Critical))
        {
            int oldWaveStep = _criticalClockMs / 33;
            _criticalClockMs = (_criticalClockMs + step) % (CriticalBreathPeriodMs * 10);
            if (_criticalClockMs / 33 != oldWaveStep) changed = true;
        }

        if (changed) base.OnStateChanged();
    }

    protected override void PaintLogical(Graphics g)
    {
        var s = Snapshot!;
        var targets = s.TargetList;
        var buffCount = s.BuffCards.Length;
        var prevSmooth = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        try
        {
            for (int i = 0; i < targets.Length; i++)
            {
                PaintRow(g, targets[i], RowBounds(buffCount, i));
            }
        }
        finally
        {
            g.SmoothingMode = prevSmooth;
        }
    }

    private static PointF[] ChamferedPlaque(RectangleF r, float tl = 2.5f, float tr = 3f, float br = 5.5f, float bl = 2.5f) =>
    [
        new(r.Left + tl, r.Top),
        new(r.Right - tr, r.Top),
        new(r.Right, r.Top + tr),
        new(r.Right, r.Bottom - br),
        new(r.Right - br, r.Bottom),
        new(r.Left + bl, r.Bottom),
        new(r.Left, r.Bottom - bl),
        new(r.Left, r.Top + tl)
    ];

    private static PointF[] ShieldBadgePolygon(RectangleF r) =>
    [
        new(r.Left + 2f, r.Top),
        new(r.Right - 3f, r.Top),
        new(r.Right, r.Top + 3f),
        new(r.Right, r.Bottom - 2f),
        new(r.Right - 2f, r.Bottom),
        new(r.Left, r.Bottom),
        new(r.Left, r.Top + 2f)
    ];

    private static PointF[] SlantedBarPolygon(RectangleF track, float slant = BarSlant) =>
    [
        new(track.Left + slant, track.Top),
        new(track.Right, track.Top),
        new(track.Right - slant, track.Bottom),
        new(track.Left, track.Bottom)
    ];

    private void PaintRow(Graphics g, PlayerHudFocusTarget target, RectangleF bounds)
    {
        var role = target.Role;
        var isBoss = role == "boss";
        var isCombat = role == "combat";
        var isEnemy = isBoss || isCombat;
        var isHovered = _hoverKey == target.Id.ToString(CultureInfo.InvariantCulture);
        _states.TryGetValue(target.Id, out var st);
        var critical = st?.Critical ?? false;
        var ratio = Math.Clamp(target.Hp / target.HpMax, 0, 1);
        var trailRatio = st?.TrailRatio ?? ratio;
        var lossAlpha = st?.LossAlpha ?? 0f;
        var gainAlpha = st?.GainAlpha ?? 0f;
        var healStartRatio = st?.HealStartRatio ?? ratio;

        float breathWave = !critical
            ? 0f
            : PlayerHudMotionSettings.ReducedMotion
                ? 0.45f
                : 0.5f + 0.5f * MathF.Sin(_criticalClockMs * MathF.PI * 2f / CriticalBreathPeriodMs);

        var plaque = ChamferedPlaque(bounds);
        // Align chassis background with PlayerInfo resource & shield plaques
        var bgTop = isEnemy
            ? (isBoss ? Color.FromArgb(248, 42, 34, 36) : Color.FromArgb(247, 36, 36, 38))
            : Color.FromArgb(247, 24, 42, 46);
        var bgBottom = isEnemy
            ? (isBoss ? Color.FromArgb(248, 18, 14, 16) : Color.FromArgb(247, 16, 17, 19))
            : Color.FromArgb(247, 10, 20, 23);
        using (var bg = new LinearGradientBrush(bounds, bgTop, bgBottom, LinearGradientMode.Vertical))
            g.FillPolygon(bg, plaque);

        if (critical && target.Hp > 0)
        {
            int pulseAlpha = (int)Math.Clamp(Math.Round(16 + 34 * breathWave), 10, 56);
            var pulseColor = isEnemy
                ? Color.FromArgb(pulseAlpha, 220, 38, 28)
                : Color.FromArgb(pulseAlpha, 242, 168, 52);
            using var pulseBrush = new SolidBrush(pulseColor);
            g.FillPolygon(pulseBrush, plaque);
        }

        Color edgeColor;
        if (isHovered)
        {
            edgeColor = Color.FromArgb(236, 238, 232);
        }
        else if (critical)
        {
            int critEdgeAlpha = (int)Math.Clamp(Math.Round(195 + 55 * breathWave), 180, 255);
            edgeColor = isEnemy
                ? Color.FromArgb(critEdgeAlpha, 244, 112, 92)
                : Color.FromArgb(critEdgeAlpha, 248, 192, 88);
        }
        else
        {
            edgeColor = isBoss
                ? Color.FromArgb(210, 186, 104, 88)
                : isCombat
                    ? Color.FromArgb(165, 108, 112, 114)
                    : Color.FromArgb(185, 64, 168, 184);
        }

        using (var edge = new Pen(edgeColor, isBoss ? 0.95f : 0.8f))
            g.DrawPolygon(edge, plaque);
        using (var topSheen = new Pen(isBoss
            ? Color.FromArgb(68, 255, 208, 184)
            : isEnemy
                ? Color.FromArgb(42, 228, 232, 236)
                : Color.FromArgb(56, 160, 248, 255), 0.7f))
        {
            g.DrawLine(topSheen, bounds.Left + 3f, bounds.Top + 1f, bounds.Right - 3.5f, bounds.Top + 1f);
        }
        using (var bevel = new Pen(Color.FromArgb(160, 10, 12, 14), 0.7f))
            g.DrawLine(bevel, bounds.Left + 3f, bounds.Bottom - 1f, bounds.Right - 6f, bounds.Bottom - 1f);

        var portraitRect = new RectangleF(bounds.X + 3f, bounds.Y + 3f, 22f, 24f);
        PaintPortrait(g, portraitRect, target, isBoss, isCombat, critical);

        var contentLeft = bounds.X + 27.5f;
        var badgeWidth = isBoss || isCombat ? 34f : 48f;
        var badgeRect = new RectangleF(contentLeft, bounds.Y + 3f, badgeWidth, 13.5f);
        var badgePoly = ShieldBadgePolygon(badgeRect);
        var badgeTop = isBoss
            ? Color.FromArgb(245, 104, 28, 28)
            : isCombat
                ? Color.FromArgb(240, 56, 46, 48)
                : critical ? Color.FromArgb(245, 112, 64, 18) : Color.FromArgb(245, 33, 54, 58);
        var badgeBot = isBoss
            ? Color.FromArgb(245, 46, 11, 13)
            : isCombat
                ? Color.FromArgb(240, 25, 21, 23)
                : critical ? Color.FromArgb(245, 48, 24, 8) : Color.FromArgb(245, 9, 23, 26);
        var badgeEdge = isBoss
            ? Color.FromArgb(220, 244, 152, 118)
            : isCombat
                ? Color.FromArgb(190, 196, 162, 156)
                : critical ? Color.FromArgb(220, 246, 186, 88) : Color.FromArgb(200, 0, 230, 236);
        var badgeInk = isBoss
            ? Color.FromArgb(255, 238, 224)
            : isCombat
                ? Color.FromArgb(236, 226, 222)
                : critical ? Color.FromArgb(255, 238, 192) : Color.FromArgb(214, 252, 255);
        using (var bFill = new LinearGradientBrush(badgeRect, badgeTop, badgeBot, LinearGradientMode.Vertical))
            g.FillPolygon(bFill, badgePoly);
        using (var bPen = new Pen(badgeEdge, 0.7f))
            g.DrawPolygon(bPen, badgePoly);
        using (var bText = new SolidBrush(badgeInk))
        using (var bFormat = new StringFormat(StringFormat.GenericTypographic)
            { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap })
        {
            g.DrawString(isBoss ? "Boss" : isCombat ? "交战" : "保护目标", _badgeFont, bText, badgeRect, bFormat);
        }

        // Slanted HP track (translating PlayerInfo MP/Poise slanted cell geometry + HP/Shield palette)
        var track = new RectangleF(contentLeft, bounds.Y + 19.5f, bounds.Right - 6f - contentLeft, 6.5f);
        var trackPoly = SlantedBarPolygon(track);
        using var trackPath = new GraphicsPath();
        trackPath.AddPolygon(trackPoly);

        var trackTop = isEnemy ? Color.FromArgb(244, 28, 14, 15) : Color.FromArgb(244, 14, 30, 34);
        var trackBot = isEnemy ? Color.FromArgb(244, 14, 8, 9) : Color.FromArgb(244, 8, 18, 21);
        using (var trackBg = new LinearGradientBrush(track, trackTop, trackBot, LinearGradientMode.Vertical))
            g.FillPath(trackBg, trackPath);

        float usableWidth = track.Width - BarSlant;
        float eventStrength = PlayerHudMotionSettings.EventStrength;
        var barClip = g.Save();
        try
        {
            g.SetClip(trackPath, CombineMode.Intersect);

            // 1. Damage trail (PlayerInfo DrawHpDamageTrail warm amber-crimson for enemies; ShieldRing ice-cyan for protect)
            double trailEnd = Math.Clamp(trailRatio, ratio, 1);
            if (trailEnd > ratio + 0.001 && eventStrength > 0f)
            {
                float trailAlphaScale = st is { LossAgeMs: < LossTotalMs } ? Math.Max(0.35f, lossAlpha) : 1f;
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
                    fillBrush.InterpolationColors = isEnemy
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
                var sheenColor = critical && !isEnemy
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
            if (target.Hp > target.HpMax)
            {
                var overflowRatio = Math.Clamp((target.Hp - target.HpMax) / target.HpMax, 0, 1);
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
            foreach (float mark in new[] { 0.25f, 0.50f, 0.75f })
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

        // 8. Aero numerals (PlayerHudTextCache + PlayerHudNumberFormat): Percentage% + Compact Current/Max (6-digit exact HP budget)
        var hpInk = critical
            ? Color.FromArgb(255, 218, 138)
            : Color.FromArgb(239, 238, 220);
        var pctInk = critical
            ? Color.FromArgb(255, 198, 96)
            : isEnemy
                ? Color.FromArgb(255, 182, 172)
                : Color.FromArgb(132, 248, 255);
        float readoutRight = bounds.Right - 6f;
        float baseline = bounds.Y + 15.2f;
        float hpWidth = _numbers.DrawRight(g, CompactHealthText(target), readoutRight, baseline, 11.2f, Scale, HpReadoutMaxWidth, hpInk, compactThreshold: ExactHpCompactThreshold);
        float pctRight = readoutRight - hpWidth - 4.5f;
        float pctWidth = _numbers.DrawRight(g, PlayerHudResourceStyle.Percent(target.Hp, target.HpMax), pctRight, baseline, 11.2f, Scale, 34f, pctInk);

        using var format = new StringFormat(StringFormat.GenericTypographic)
            { FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter };
        var nameLeft = badgeRect.Right + 5f;
        if (target.Hits > 0)
        {
            string comboText = target.Hits.ToString(CultureInfo.InvariantCulture) + " HIT";
            float comboMeasured = g.MeasureString(comboText, _badgeFont, 200, format).Width;
            float comboBaseWidth = Math.Clamp(comboMeasured + 9f, 36f, 64f);
            var comboBaseRect = new RectangleF(badgeRect.Right + 3.5f, badgeRect.Y, comboBaseWidth, badgeRect.Height);
            float comboPulse = Math.Clamp((st?.ComboPulse ?? 0f) * eventStrength, 0f, 1f);
            float popX = 1.6f * comboPulse;
            float popY = 0.9f * comboPulse;
            var comboDrawRect = new RectangleF(
                comboBaseRect.X - popX,
                comboBaseRect.Y - popY,
                comboBaseRect.Width + popX * 2f,
                comboBaseRect.Height + popY * 2f);
            var comboPoly = ShieldBadgePolygon(comboDrawRect);

            int boost = (int)Math.Round(42f * comboPulse);
            Color comboTop = target.Hits >= 30
                ? Color.FromArgb(248, Math.Min(255, 156 + boost), Math.Min(255, 44 + boost), Math.Min(255, 24 + boost / 2))
                : target.Hits >= 10
                    ? Color.FromArgb(246, Math.Min(255, 128 + boost), Math.Min(255, 52 + boost), Math.Min(255, 20 + boost / 2))
                    : Color.FromArgb(244, Math.Min(255, 96 + boost), Math.Min(255, 54 + boost), Math.Min(255, 22 + boost / 2));
            Color comboBot = target.Hits >= 30
                ? Color.FromArgb(248, Math.Min(255, 72 + boost / 2), 16, 12)
                : target.Hits >= 10
                    ? Color.FromArgb(246, Math.Min(255, 56 + boost / 2), 20, 10)
                    : Color.FromArgb(244, Math.Min(255, 42 + boost / 2), 22, 10);
            Color comboEdge = target.Hits >= 30
                ? Color.FromArgb(242, 255, Math.Min(255, 206 + boost), Math.Min(255, 108 + boost))
                : target.Hits >= 10
                    ? Color.FromArgb(234, 252, Math.Min(255, 176 + boost), Math.Min(255, 92 + boost))
                    : Color.FromArgb(220, Math.Min(255, 236 + boost), Math.Min(255, 164 + boost), Math.Min(255, 88 + boost));
            Color comboInk = target.Hits >= 30
                ? Color.FromArgb(255, 250, 218)
                : Color.FromArgb(255, 240, 202);

            using (var cFill = new LinearGradientBrush(comboDrawRect, comboTop, comboBot, LinearGradientMode.Vertical))
                g.FillPolygon(cFill, comboPoly);
            using (var cPen = new Pen(comboEdge, comboPulse > 0.05f ? 0.95f : 0.75f))
                g.DrawPolygon(cPen, comboPoly);
            using (var cText = new SolidBrush(comboInk))
            using (var cFormat = new StringFormat(StringFormat.GenericTypographic)
                { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap })
            {
                g.DrawString(comboText, _badgeFont, cText, comboDrawRect, cFormat);
            }
            nameLeft = comboBaseRect.Right + 4.5f;
        }

        using var labelBrush = new SolidBrush(NativeHudTheme.TextPrimary);
        var nameRight = Math.Max(nameLeft + 24f, pctRight - pctWidth - 4f);
        g.DrawString(target.Name.Replace('\r', ' ').Replace('\n', ' '), _font, labelBrush,
            new RectangleF(nameLeft, bounds.Y + 2f, nameRight - nameLeft, 16f), format);
    }

    private void PaintPortrait(Graphics g, RectangleF rect, PlayerHudFocusTarget target, bool isBoss, bool isCombat, bool critical)
    {
        var poly = ChamferedPlaque(rect, 1.5f, 1.5f, 2.5f, 1.5f);
        using (var well = new SolidBrush(Color.FromArgb(246, 12, 15, 17)))
            g.FillPolygon(well, poly);

        Bitmap? bmp = ResolvePortraitBitmap(target);
        if (bmp != null)
        {
            var inner = new RectangleF(rect.X + 1f, rect.Y + 1f, rect.Width - 2f, rect.Height - 2f);
            var saved = g.Save();
            try
            {
                using var clipPath = new GraphicsPath();
                clipPath.AddPolygon(poly);
                g.SetClip(clipPath, CombineMode.Intersect);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(bmp, inner);
            }
            finally
            {
                g.Restore(saved);
            }
        }
        else
        {
            var emblem = InitialGlyph(target.Name);
            var glyphColor = isBoss
                ? Color.FromArgb(240, 255, 166, 152)
                : isCombat
                    ? Color.FromArgb(235, 238, 176, 166)
                    : critical ? Color.FromArgb(240, 252, 212, 132) : Color.FromArgb(240, 136, 242, 255);
            using var glyphBrush = new SolidBrush(glyphColor);
            using var glyphFormat = new StringFormat(StringFormat.GenericTypographic)
                { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap };
            g.DrawString(emblem, _initialFont, glyphBrush, rect, glyphFormat);
        }

        var rimColor = isBoss
            ? Color.FromArgb(205, 212, 96, 82)
            : isCombat
                ? Color.FromArgb(180, 148, 112, 108)
                : critical ? Color.FromArgb(205, 232, 168, 76) : Color.FromArgb(195, 52, 186, 204);
        using var rim = new Pen(rimColor, 0.75f);
        g.DrawPolygon(rim, poly);
    }

    private Bitmap? ResolvePortraitBitmap(PlayerHudFocusTarget target)
    {
        if (_icons == null || string.IsNullOrEmpty(target.PortraitKey)) return null;
        if (_icons.TryGet(target.PortraitKey, out var frames) && frames?.First != null)
            return frames.First;
        if (!target.PortraitKey.StartsWith("敌人-", StringComparison.Ordinal)
            && !target.PortraitKey.StartsWith(DollPortraitKey.Prefix, StringComparison.Ordinal)
            && _icons.TryGet("敌人-" + target.PortraitKey, out frames) && frames?.First != null)
            return frames.First;
        return null;
    }

    private static string InitialGlyph(string name)
    {
        if (!string.IsNullOrEmpty(name))
        {
            for (int i = 0; i < name.Length; i++)
            {
                char c = name[i];
                if (!char.IsWhiteSpace(c) && !char.IsControl(c))
                {
                    if (char.IsHighSurrogate(c) && i + 1 < name.Length && char.IsLowSurrogate(name[i + 1]))
                        return name.Substring(i, 2);
                    return c.ToString();
                }
            }
        }
        return "目标";
    }

    internal static string HealthText(PlayerHudFocusTarget target) =>
        Value(target.Hp) + " / " + Value(target.HpMax);
    internal static string CompactHealthText(PlayerHudFocusTarget target) =>
        Value(target.Hp) + "/" + Value(target.HpMax);
    private static string Value(double value) => Math.Abs(value) >= 1e9
        ? value.ToString("0.##E+0", CultureInfo.InvariantCulture)
        : Math.Floor(value).ToString("0", CultureInfo.InvariantCulture);

    private PlayerHudTarget? Hit(Point screen)
    {
        if (!Visible || !Controller.CanInteract || Snapshot is not { TargetList: { Length: > 0 } targets } s || Scale <= 0) return null;
        var pt = Logical(screen);
        var buffCount = s.BuffCards.Length;
        for (int i = 0; i < targets.Length; i++)
        {
            var rowRect = RowBounds(buffCount, i);
            if (rowRect.Contains(pt))
            {
                return new("focusTarget", i, targets[i].Id.ToString(CultureInfo.InvariantCulture),
                    s.Epoch, 0, s.Loadout.Bank, rowRect, Controller.Generation, s.Vitals.Paused);
            }
        }
        return null;
    }

    public override bool TryHitTest(Point screenPt) => Hit(screenPt) != null;
    public object? CapturePointerTarget(Point screen) => Hit(screen);
    public bool NeedsPointerClick => false;

    public override void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
    {
        if (kind is MouseEventKind.Cancel or MouseEventKind.Leave) { CancelHover(); return; }
        if (kind is not (MouseEventKind.Move or MouseEventKind.Enter)) return;
        var target = Hit(new Point(e.X, e.Y));
        if (target?.Key == _hoverKey) return;
        CancelHover();
        _hoverKey = target?.Key;
        if (target != null) Controller.ShowTooltip(target);
        Repaint();
    }

    private void CancelHover()
    {
        if (_hoverKey == null) return;
        _hoverKey = null;
        Controller.HideTooltip();
        Repaint();
    }

    public override void SetHostSuppressed(bool suppressed)
    {
        if (suppressed) CancelHover();
        base.SetHostSuppressed(suppressed);
    }

    public override void Dispose()
    {
        CancelHover();
        _numbers.Dispose();
        _font.Dispose();
        _badgeFont.Dispose();
        _initialFont.Dispose();
        base.Dispose();
    }
}
