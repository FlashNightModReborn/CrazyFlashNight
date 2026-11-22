#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Guardian.Hud.UnitLife;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Multi-target strip (protect / boss / combat) in the Buff surface with portraits, clock-driven damage trail &amp; heal preview, chamfered/slanted geometry, and Aero numerals.</summary>
internal sealed partial class PlayerHudFocusTargetWidget : PlayerHudWidgetBase, INativeHudPointerSnapshot
{
    private const float ColumnWidth = 294f;
    internal const float RowHeight = 30f;
    internal const float RowGap = 2f;
    internal const int ComboPulseDurationMs = 150;

    internal const float HpReadoutMaxWidth = 92f;
    internal const double ExactHpCompactThreshold = 1_000_000;

    private sealed class TargetVisualState(UnitHealth health)
    {
        internal FocusLifeState Life = new(health);
        internal int LastHits;
        internal int ComboPulseAgeMs = ComboPulseDurationMs;
        internal string? MeasuredName;
        internal float MeasuredScale, NameWidth;
        internal int MeasuredHits = -1;
        internal float HitWidth, HitScale;

        internal float ComboPulse => ComboPulseAgeMs >= ComboPulseDurationMs
            ? 0f
            : Math.Clamp(1f - ComboPulseAgeMs / (float)ComboPulseDurationMs, 0f, 1f);

        internal bool HasActiveTransition => Life.HasActiveTransition || ComboPulseAgeMs < ComboPulseDurationMs;
    }

    private readonly Font _font = NativeHudFonts.CreateUiFont(11, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _badgeFont = NativeHudFonts.CreateRoleFont("native.player-info.body", 9.5f, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _initialFont = NativeHudFonts.CreateRoleFont("native.player-info.body", 11f, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly PlayerHudTextCache _numbers = new();
    private readonly PlayerHudPortraitCache _portraits = new();
    // Only three fixed logical plaques enter this table (wide primary, wide secondary, compact strip).
    private readonly Dictionary<(RectangleF, int, int, int),LinearGradientBrush> _plateFills = new();
    private readonly Control _anchor;
    private readonly LootIconCatalog? _icons;
    private IDollBakeSink? _dollBake;
    private readonly Dictionary<long, TargetVisualState> _states = new();
    private readonly HashSet<long> _activeIds = new();
    private readonly HashSet<string> _requestedDolls = new(StringComparer.Ordinal);
    private PlayerHudFocusTarget[] _lastTargets = Array.Empty<PlayerHudFocusTarget>();
    private RectangleF _lastLayout;
    private bool _lastSuppressed;
    private long _epoch;
    private string? _hoverKey;
    private readonly Font _denseFont = NativeHudFonts.CreateUiFont(8, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _shortFont = NativeHudFonts.CreateUiFont(9, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly StringFormat _label = new(StringFormat.GenericTypographic) { FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter };
    private readonly StringFormat _center = new(StringFormat.GenericTypographic) { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap };
    private int AllyCount => Snapshot?.Allies?.Rows.Length ?? 0;

    protected override PlayerHudGroups ConsumedGroups =>
        PlayerHudGroups.Focus | PlayerHudGroups.Allies | PlayerHudGroups.Vitals;
    protected override bool HasContent => Snapshot is { TargetList.Length: > 0 };
    protected override RectangleF LogicalBounds => BoundsForBuffCount(0, Snapshot?.TargetList.Length ?? 0, AllyCount);
    internal double TrailRatio => Snapshot?.FocusTarget is { } t && _states.TryGetValue(t.Id, out var st) ? st.Life.TrailRatio : 0;
    internal bool IsCritical => Snapshot?.FocusTarget is { } t && Band(t) == 2;
    internal double GetTrailRatio(long id) => _states.TryGetValue(id, out var st) ? st.Life.TrailRatio : 0;
    internal bool IsTargetCritical(long id) => Snapshot?.TargetList.FirstOrDefault(t => t.Id == id) is { } t && Band(t) == 2;
    internal float GetHealAlpha(long id) => _states.TryGetValue(id, out var st) ? st.Life.GainAlpha : 0f;
    internal float GetComboPulse(long id) => _states.TryGetValue(id, out var st) ? st.ComboPulse : 0f;

    public override bool WantsAnimationTick
    {
        get
        {
            if (!Visible || PlayerHudMotionSettings.StaticFeedback || Snapshot is not { Vitals.Paused: false })
                return false;
            foreach (var state in _states.Values)
                if (state.HasActiveTransition)
                    return true;
            return false;
        }
    }

    // The first focus is always wide. Further targets share one strip when the squad or focus list is dense.
    private static bool Dense(int count, int allies) => count > 2 || allies > 3;
    internal static RectangleF BoundsForBuffCount(int buffCount, int targetCount = 1) => BoundsForBuffCount(buffCount,targetCount,0);
    internal static RectangleF BoundsForBuffCount(int buffCount, int targetCount, int allyCount) =>
        new(6, 0, ColumnWidth, targetCount <= 1 ? 32 : Dense(targetCount, allyCount) ? 57 : 64);

    internal static RectangleF RowBounds(int buffCount, int index, int targetCount) => RowBounds(buffCount,index,targetCount,0);
    internal static RectangleF RowBounds(int buffCount, int index, int targetCount, int allyCount)
    {
        if (index == 0) return new(6, 0, ColumnWidth, 32);
        if (!Dense(targetCount, allyCount)) return new(6, 34, ColumnWidth, 30);
        float width = (ColumnWidth - 4) / (targetCount - 1);
        return new(8 + (index - 1) * width, 34, width, 23);
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
        if (ContainsPortrait(Snapshot?.TargetList, key)) Repaint();
    }

    private static bool ContainsPortrait(PlayerHudFocusTarget[]? targets, string key)
    {
        if (targets == null) return false;
        foreach (var target in targets)
            if (target.PortraitKey == key) return true;
        return false;
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
        bool epochChanged = (s?.Epoch ?? 0) != _epoch;
        if (epochChanged)
        {
            _epoch = s?.Epoch ?? 0;
            _states.Clear();
            _requestedDolls.Clear();
            CancelHover();
        }
        var targets = s?.TargetList ?? Array.Empty<PlayerHudFocusTarget>();
        bool targetsChanged = epochChanged || !targets.SequenceEqual(_lastTargets);
        bool stableRows = !epochChanged && targets.Length == _lastTargets.Length;
        int changedHealth = 0, wholeRows = 0;
        if (_hoverKey != null && (s == null || !targets.Any(t => t.Id.ToString(CultureInfo.InvariantCulture) == _hoverKey)))
            CancelHover();

        if (targets.Length == 0)
        {
            _states.Clear();
            _requestedDolls.Clear();
        }
        else if (targetsChanged)
        {
            _activeIds.Clear();
            int fullRows = Dense(targets.Length, AllyCount) ? 1 : 2;
            for (int i = 0; i < targets.Length; i++)
            {
                var target = targets[i];
                bool compact = i >= fullRows;
                _activeIds.Add(target.Id);
                var health = new UnitHealth(target.Hp, target.HpMax);
                if (!_states.TryGetValue(target.Id, out var st))
                {
                    stableRows = false;
                    st = new TargetVisualState(health);
                    _states.Add(target.Id, st);
                }
                else
                {
                    st.Life.Apply(health, PlayerHudMotionSettings.StaticFeedback);
                    if (stableRows)
                    {
                        var old = _lastTargets[i];
                        if (!SameRow(old, target))
                            stableRows = false;
                        else if (old.Hits != target.Hits || Band(old) != Band(target) ||
                            (old.Hp > 0) != (target.Hp > 0))
                            wholeRows |= 1 << i;
                        else if (old.Hp != target.Hp || old.HpMax != target.HpMax)
                            changedHealth |= 1 << i;
                    }
                }

                if (PlayerHudMotionSettings.StaticFeedback || compact || target.Hits <= 0)
                    st.ComboPulseAgeMs = ComboPulseDurationMs;
                else if (target.Hits > st.LastHits)
                    st.ComboPulseAgeMs = 0;
                st.LastHits = target.Hits;
            }
            foreach (var old in _lastTargets)
            {
                if (!_activeIds.Contains(old.Id)) _states.Remove(old.Id);
                if (old.Doll != null && _requestedDolls.Contains(old.PortraitKey) && !ContainsPortrait(targets, old.PortraitKey))
                    _requestedDolls.Remove(old.PortraitKey);
            }
            RequestPendingDollPortraits(targets);
        }

        var layout = LogicalBounds;
        // TL 状态列实际底边上报分区仲裁，BL fallback 消息据此让位（ADR D5）。
        HudZoneLayout.ReportTopLeftBottom(TopLeftBottomFor(0, targets.Length, Suppressed || s == null, AllyCount));
        if (!targetsChanged && layout == _lastLayout && Suppressed == _lastSuppressed) return;
        bool local = stableRows && (changedHealth | wholeRows) != 0 && layout == _lastLayout && !Suppressed && !_lastSuppressed;
        var previous = _lastTargets;
        _lastTargets = targets; _lastLayout = layout; _lastSuppressed = Suppressed;
        if (local) NotifyVisualChange(TrackDamage(targets.Length, changedHealth | wholeRows, previous, wholeRows));
        else NotifyVisualChange(targetsChanged ? HudRepaintRegions.AuthoritativeWidget : EventArgs.Empty);
    }

    private static bool SameRow(PlayerHudFocusTarget old, PlayerHudFocusTarget next) =>
        old.Id == next.Id && old.Role == next.Role && old.Name == next.Name && old.Icon == next.Icon &&
        old.PortraitKey == next.PortraitKey && old.Compact == next.Compact &&
        (ReferenceEquals(old.Doll, next.Doll) || (old.Doll != null && next.Doll != null &&
            old.Doll.Count == next.Doll.Count && old.Doll.All(pair =>
                next.Doll.TryGetValue(pair.Key, out var value) && value == pair.Value)));

    internal static float TopLeftBottomFor(int buffCount, int targetCount, bool hidden) =>
        TopLeftBottomFor(buffCount,targetCount,hidden,0);
    internal static float TopLeftBottomFor(int buffCount, int targetCount, bool hidden, int allyCount) =>
        hidden || targetCount == 0 ? 0f : BoundsForBuffCount(buffCount, targetCount, allyCount).Bottom;

    // Screen warnings follow the art contract. The shared life core keeps its own trail and heal policy.
    internal static int Band(PlayerHudFocusTarget target) =>
        target.Role != "protect" || target.HpMax <= 0 ? 0 :
        target.Hp < target.HpMax * .30 ? 2 : target.Hp <= target.HpMax * .60 ? 1 : 0;

    public override void Tick(int deltaMs)
    {
        if (!Visible || Snapshot is not { Vitals.Paused: false } || PlayerHudMotionSettings.StaticFeedback || deltaMs <= 0) return;
        int step = deltaMs;
        bool changed = false;
        int wholeRows = 0;
        int changedBars = 0;
        var targets = Snapshot.TargetList;

        for (int i = 0; i < targets.Length; i++)
        {
            if (!_states.TryGetValue(targets[i].Id, out var st)) continue;
            if (st.Life.Tick(step))
            {
                changed = true;
                changedBars |= 1 << i;
            }

            if (st.ComboPulseAgeMs < ComboPulseDurationMs)
            {
                int oldBucket = st.ComboPulseAgeMs / 25;
                st.ComboPulseAgeMs = (int)Math.Min(ComboPulseDurationMs, (long)st.ComboPulseAgeMs + step);
                if (st.ComboPulseAgeMs / 25 != oldBucket || st.ComboPulseAgeMs >= ComboPulseDurationMs)
                {
                    wholeRows |= 1 << i;
                    changed = true;
                }
            }
        }

        if (!changed) return;
        NotifyVisualChange(TrackDamage(targets.Length, changedBars | wholeRows, wholeRows: wholeRows));
    }

    // A pure trail/fill animation only changes pixels inside the life track.
    // The changing geometry is painted inside trackPath; its outer rim is static.
    private EventArgs TrackDamage(int count, int changed, PlayerHudFocusTarget[]? previous = null, int wholeRows = 0)
    {
        var viewport = Viewport;
        float scale = viewport.Height / 576f;
        if (scale <= 0) return EventArgs.Empty;
        var regions = new List<Rectangle>(previous == null ? count : count * 2);
        int buffs = Snapshot!.BuffCards.Length;
        for (int i = 0; i < count; i++)
        {
            if ((changed & (1 << i)) == 0) continue;
            var row = RowBounds(buffs, i, count, AllyCount);
            if ((wholeRows & (1 << i)) != 0)
            {
                // The critical glow, combo pulse, name layout and portrait can affect the
                // whole card. The centered GDI stroke also covers the half-pixel sample
                // fringe: the Boss lower edge changes a second pixel at 1080p.
                regions.Add(ToPixels(row, viewport, scale, Math.Max(1, (int)Math.Ceiling(scale * 0.5f + 0.5f))));
                continue;
            }
            regions.Add(ToPixels(LifeTrack(row), viewport, scale, 0));
            if (previous != null)
                regions.Add(ToPixels(ReadoutDamage(row, previous[i], _lastTargets[i], scale), viewport, scale, 2));
        }
        return new HudRepaintRegions(regions.ToArray(), authoritative: previous != null);
    }

    private static Rectangle ToPixels(RectangleF r, Rectangle viewport, float scale, int padding) =>
        Rectangle.FromLTRB(viewport.Left + (int)Math.Floor(r.Left * scale) - padding,
            viewport.Top + (int)Math.Floor(r.Top * scale) - padding,
            viewport.Left + (int)Math.Ceiling(r.Right * scale) + padding,
            viewport.Top + (int)Math.Ceiling(r.Bottom * scale) + padding);

    private static bool Secondary(RectangleF row) => row.Height == 23f;
    private static bool Stacked(RectangleF row) => row.Width <= (ColumnWidth - 4) / 4;

    private static RectangleF Portrait(RectangleF row)
    {
        if (!Secondary(row))
        {
            bool first = row.Top == 0;
            float pad = first ? 3.5f : 3f;
            return new(row.X + 5.2f, row.Y + pad, first ? 24 : 22, row.Height - 2 * pad);
        }
        bool stacked = Stacked(row);
        return new(row.X + (stacked ? 5.8f : 6.5f), row.Y + 3,
            stacked ? (row.Width < 50 ? 11 : 14) : 17, stacked ? 14.3f : row.Height - 6);
    }

    private static RectangleF LifeTrack(RectangleF row)
    {
        var p = Portrait(row);
        if (!Secondary(row))
        {
            bool first = row.Top == 0;
            float x = p.Right + 4.8f;
            return new(x,row.Bottom - (first ? 10.2f : 9.2f),row.Right - 6 - x,first ? 6.8f : 6.4f);
        }
        bool stacked = Stacked(row);
        float left = stacked ? p.X : p.Right + 4.5f;
        return new(left,row.Bottom - (stacked ? 4 : 7),row.Right - (stacked ? 3 : 5) - left,stacked ? 2.8f : 4.2f);
    }

    private float _digitAdvance, _slashAdvance;
    private float ReservedWidth(PlayerHudFocusTarget target)
    {
        if (_digitAdvance == 0)
        {
            for (char digit = '0'; digit <= '9'; digit++)
                _digitAdvance = Math.Max(_digitAdvance, _numbers.Width(digit.ToString(), 11, HpReadoutMaxWidth));
            _slashAdvance = _numbers.Width("/", 11, HpReadoutMaxWidth);
        }
        int maxDigits = PlayerHudNumberFormat.Full(target.HpMax).Length;
        int digits = Math.Max(maxDigits, PlayerHudNumberFormat.Full(target.Hp).Length) + maxDigits;
        return Math.Min(HpReadoutMaxWidth, digits * _digitAdvance + _slashAdvance);
    }

    private RectangleF ReadoutDamage(RectangleF row, PlayerHudFocusTarget old, PlayerHudFocusTarget target, float scale)
    {
        if (Secondary(row))
        {
            var p = Portrait(row);
            bool stacked = Stacked(row);
            float tx = p.Right + (stacked ? 2.6f : 4.5f);
            return RectangleF.FromLTRB(Math.Max(tx, row.Right - (stacked ? 3 : 5) - 26) - 2,
                row.Y + (stacked ? 8 : 1),row.Right,row.Y + (stacked ? 19 : 15));
        }
        float reserve = ReservedWidth(target);
        float left = reserve == ReservedWidth(old) ? row.Right - 6 - reserve : Portrait(row).Right;
        return RectangleF.FromLTRB(left - 2, row.Top + 1, row.Right - 2, row.Top + 19);
    }

    protected override void PaintLogical(Graphics g)
    {
        var s = Snapshot!;
        var targets = s.TargetList;
        var buffCount = s.BuffCards.Length;
        float scale = Scale;
        using var clip = g.Clip;
        var prevSmooth = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        try
        {
            if (targets.Length > 1 && Dense(targets.Length, AllyCount))
            {
                var strip = new RectangleF(6, 34, ColumnWidth, 23);
                if (clip.IsVisible(RectangleF.Inflate(strip, 1, 1)))
                    MetalPlate(g, strip, ChamferedPlaque(strip, 2, 5, 2, 2), 0x23282B, 0x111517, 0x090C0D,
                        Color.FromArgb(102, 214, 217, 215), .8f);
            }
            for (int i = 0; i < targets.Length; i++)
            {
                var row = RowBounds(buffCount, i, targets.Length, AllyCount);
                if (clip.IsVisible(RectangleF.Inflate(row, 2f, 2f)))
                    PaintRow(g, clip, targets[i], row, scale, i);
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

    private static Color Rgb(int value) => Color.FromArgb(unchecked((int)0xff000000) | value);

    private void MetalPlate(Graphics g, RectangleF r, PointF[] points, int top, int middle, int bottom, Color rim, float rimWidth)
    {
        using var transform=g.Transform;
        var origin=new[]{new PointF(r.Left,r.Top)};
        transform.TransformPoints(origin);
        float scale=transform.Elements[0];
        int left=(int)Math.Floor(origin[0].X)-3,topPx=(int)Math.Floor(origin[0].Y)-3;
        float dx=origin[0].X-left,dy=origin[0].Y-topPx;
        int w=(int)Math.Ceiling(r.Width*scale)+7,h=(int)Math.Ceiling(r.Height*scale)+7;
        var stampKey=(r,top,middle,bottom,rim.ToArgb(),rimWidth,scale,dx,dy);
        if ((long)w*h*4<=768*1024)
        {
            if (!_plates.TryGetValue(stampKey,out var tile))
            {
                if (_plateBytes+(long)w*h*4>2*1024*1024) ClearPlates();
                tile=new Bitmap(w,h,System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
                using var local=Graphics.FromImage(tile);
                local.SmoothingMode=g.SmoothingMode;
                local.TranslateTransform(dx-r.Left*scale,dy-r.Top*scale);
                local.ScaleTransform(scale,scale);
                DrawPlate(local,r,points,top,middle,bottom,rim,rimWidth);
                _plates.Add(stampKey,tile);
                _plateBytes+=(long)w*h*4;
            }
            var saved=g.Save();g.ResetTransform();
            try {g.DrawImageUnscaled(tile,left,topPx);} finally {g.Restore(saved);}
            return;
        }
        DrawPlate(g,r,points,top,middle,bottom,rim,rimWidth);
    }

    private readonly Dictionary<(RectangleF,int,int,int,int,float,float,float,float),Bitmap> _plates=new();
    private long _plateBytes;
    private void ClearPlates()
    {
        foreach(var tile in _plates.Values) tile.Dispose();
        _plates.Clear(); _plateBytes=0;
    }

    private void DrawPlate(Graphics g, RectangleF r, PointF[] points, int top, int middle, int bottom, Color rim, float rimWidth)
    {
        var key = (r,top,middle,bottom);
        if (!_plateFills.TryGetValue(key, out var gradient))
        {
            gradient = new LinearGradientBrush(r, Rgb(top), Rgb(bottom), LinearGradientMode.Vertical);
            gradient.InterpolationColors = new ColorBlend(3) { Colors = [Rgb(top),Rgb(middle),Rgb(bottom)], Positions = [0f,.62f,1f] };
            _plateFills.Add(key,gradient);
        }
        using var edge = new Pen(rim, rimWidth);
        g.FillPolygon(gradient, points);
        g.DrawPolygon(edge, points);
        using var sheen = new Pen(Color.FromArgb(51,228,232,236), .75f);
        g.DrawLine(sheen,r.Left + 3,r.Top + .9f,r.Right - 4.5f,r.Top + .9f);
    }

    private static Color Accent(PlayerHudFocusTarget t, int band) => Rgb(band == 2 ? 0xff6656 : band == 1 ? 0xe0b052 :
        t.Role == "boss" ? 0xa83832 : t.Role == "combat" ? 0x8e9694 : 0x649aa2);

    private static Color HealthInk(int band) => Rgb(band == 2 ? 0xff8a78 : band == 1 ? 0xf1c970 : 0xe8eeec);

    private void PaintRow(Graphics g, Region clip, PlayerHudFocusTarget target, RectangleF row, float scale, int index)
    {
        bool compact = Secondary(row);
        bool boss = target.Role == "boss", combat = target.Role == "combat";
        int band = Band(target);
        var portrait = Portrait(row);
        var state = _states[target.Id];
        if (!compact)
        {
            bool first = row.Top == 0;
            var shape = ChamferedPlaque(row, first ? 0 : 2.5f, first ? 0 : 4, 6, first ? 4 : 2.5f);
            var rim = _hoverKey == target.Id.ToString(CultureInfo.InvariantCulture) ? Color.White :
                band == 2 ? Rgb(0xff6656) : band == 1 ? Color.FromArgb(189,224,180,92) : Color.FromArgb(133,182,190,188);
            bool protect = !boss && !combat;
            MetalPlate(g,row,shape,band == 2 ? 0x341717 : protect ? 0x1f2629 : 0x23272a,
                band == 2 ? 0x180b0c : protect ? 0x101517 : 0x111416,band == 2 ? 0x0c0708 : 0x090c0d,rim,band == 2 ? 1.25f : .85f);
        }
        else if (index > 1)
        {
            using var divider = new Pen(Color.FromArgb(56,214,217,215),.8f);
            g.DrawLine(divider,row.Left + 1.5f,row.Top + 2.5f,row.Left - 1.5f,row.Bottom - 2.5f);
        }
        using (var blade = new SolidBrush(Accent(target,band)))
            g.FillRectangle(blade,row.X + (compact ? 2.5f : 1.3f),row.Y + (row.Top == 0 ? 1.5f : 3f),
                compact ? 2.2f : 2.1f,row.Height - (row.Top == 0 ? 4.5f : 6f));
        if (clip.IsVisible(RectangleF.Inflate(portrait,2,2)))
        {
            PaintPortrait(g,portrait,target,boss,combat,band == 2);
            if (band == 2)
            {
                var tag = new RectangleF(portrait.Right - 7.5f,portrait.Top,9,9);
                using var red = new SolidBrush(Rgb(0xb72b22));
                g.FillRectangle(red,tag);
                g.DrawString("!",_denseFont,Brushes.White,tag,_center);
            }
        }
        var track = LifeTrack(row);
        if (clip.IsVisible(RectangleF.Inflate(track,2,2)))
        {
            var visual = state.Life.Visual with { Critical = band == 2 };
            var style = FillStyle(target.Role);
            if (_gpuFill != null && !_gpuFill.Rectangles[index].IsEmpty)
            {
                var saved = g.Save();
                try
                {
                    using var transform = g.Transform;
                    g.ResetTransform();
                    g.ExcludeClip(_gpuFill.Rectangles[index]);
                    g.Transform = transform;
                    UnitLifeBarPainter.Paint(g,track,visual,style,PlayerHudMotionSettings.EventStrength,focusV38:true);
                }
                finally { g.Restore(saved); }
            }
            else UnitLifeBarPainter.Paint(g,track,visual,style,PlayerHudMotionSettings.EventStrength,focusV38:true);
        }
        if (!clip.IsVisible(new RectangleF(row.X,row.Top,row.Width,compact && Stacked(row) ? 18.5f : 17.5f))) return;
        if (compact) PaintSecondaryText(g,clip,target,row,portrait,band,scale);
        else PaintPrimaryText(g,clip,target,state,row,portrait,band,scale);
    }

    private void PaintSecondaryText(Graphics g, Region clip, PlayerHudFocusTarget target, RectangleF row, RectangleF portrait, int band, float scale)
    {
        bool stacked = Stacked(row);
        float left = portrait.Right + (stacked ? 2.6f : 4.5f);
        float right = row.Right - (stacked ? 3 : 5);
        float numberWidth = Math.Min(26,right - left);
        float nameWidth = (stacked ? right : right - numberWidth - 3) - left - 1;
        var nameBounds=new RectangleF(left,row.Y + (stacked ? 0 : 1),nameWidth,stacked ? 11 : 14);
        if (nameWidth > 0 && clip.IsVisible(RectangleF.Inflate(nameBounds,2,2)))
            g.DrawString(target.Name.Replace('\r',' ').Replace('\n',' '),stacked ? _denseFont : _shortFont,
                Brushes.White,nameBounds,_label);
        string percent = target.HpMax > 0 ? Math.Round(target.Hp / target.HpMax * 100,MidpointRounding.AwayFromZero).ToString("0",CultureInfo.InvariantCulture) + "%" : "--";
        _numbers.DrawRight(g,percent,right,row.Y + (stacked ? 17.1f : 11.8f),
            stacked ? 8f : row.Width >= 145 ? 9.6f : 8.4f,scale,Math.Max(1,numberWidth),HealthInk(band));
    }

    private void PaintPrimaryText(Graphics g, Region clip, PlayerHudFocusTarget target, TargetVisualState state,
        RectangleF row, RectangleF portrait, int band, float scale)
    {
        float by = row.Top + (row.Top == 0 ? 4 : 3);
        bool boss = target.Role == "boss", combat = target.Role == "combat";
        var badge = new RectangleF(portrait.Right + 4.8f,by,boss ? 32 : combat ? 30 : 44,12);
        var fill = Rgb(band == 2 ? 0x4d1715 : band == 1 ? 0x272013 : boss ? 0x1e2224 : combat ? 0x222628 : 0x172225);
        var edge = band == 2 ? Rgb(0xff7a6b) : band == 1 ? Rgb(0xd8a84c) : boss ? Color.FromArgb(148,176,184,182) : combat ? Rgb(0x8a9290) : Rgb(0x769aa0);
        if (clip.IsVisible(RectangleF.Inflate(badge,2,2)))
            Chip(g,badge,fill,edge,boss ? "Boss" : combat ? "交战" : band == 2 ? "濒危" : "保护目标",boss);
        float right = row.Right - 6;
        if (clip.IsVisible(new RectangleF(right-HpReadoutMaxWidth-3,by-4,HpReadoutMaxWidth+6,20)))
        {
            string exact = PlayerHudNumberFormat.Full(target.Hp) + "/" + PlayerHudNumberFormat.Full(target.HpMax);
            _numbers.DrawRight(g,exact,right,by + 10.2f,11,scale,HpReadoutMaxWidth,HealthInk(band),compactThreshold:double.PositiveInfinity);
        }
        float nameLeft = badge.Right + 4.5f;
        float nameRight = right - ReservedWidth(target) - 4;
        string name = target.Name.Replace('\r',' ').Replace('\n',' ');
        if (state.MeasuredName != name || state.MeasuredScale != scale)
        {
            state.NameWidth = g.MeasureString(name,_font,PointF.Empty,_label).Width;
            state.MeasuredName = name;
            state.MeasuredScale = scale;
        }
        if (target.Hits > 0)
        {
            string hitText = target.Hits.ToString(CultureInfo.InvariantCulture) + " HIT";
            if (state.MeasuredHits != target.Hits || state.HitScale != scale)
            {
                state.HitWidth = Math.Max(38,(float)Math.Ceiling(g.MeasureString(hitText,_badgeFont,PointF.Empty,_label).Width) + 8);
                state.MeasuredHits = target.Hits;
                state.HitScale = scale;
            }
            float width = state.HitWidth;
            if (width + 5 + state.NameWidth <= nameRight - nameLeft)
            {
                var hit = new RectangleF(nameLeft,by,width,12);
                if (clip.IsVisible(RectangleF.Inflate(hit,2,2)))
                    Chip(g,hit,Rgb(0x171c1e),Color.FromArgb(122 + (int)(64 * state.ComboPulse),186,194,192),hitText,false);
                nameLeft += width + 5;
            }
        }
        if (nameRight > nameLeft && clip.IsVisible(new RectangleF(nameLeft-2,by-4,nameRight-nameLeft+4,20)))
        {
            using var ink = new SolidBrush(Rgb(band == 1 ? 0xf6e5bc : 0xf2f5f3));
            g.DrawString(name,_font,ink,new RectangleF(nameLeft,by - 2,nameRight - nameLeft,16),_label);
        }
    }

    private void Chip(Graphics g, RectangleF r, Color fill, Color edge, string text, bool boss)
    {
        PointF[] poly = [new(r.Left + 2.4f,r.Top),new(r.Right,r.Top),new(r.Right - 2.4f,r.Bottom),new(r.Left,r.Bottom)];
        using var brush = new SolidBrush(fill);
        using var pen = new Pen(edge,.7f);
        g.FillPolygon(brush,poly);
        g.DrawPolygon(pen,poly);
        if (boss)
        {
            using var red = new Pen(Rgb(0xb03932),2.3f);
            g.DrawLine(red,r.Left + 4,r.Top + .8f,r.Left + 1.8f,r.Bottom - .8f);
        }
        g.DrawString(text,_badgeFont,Brushes.White,r,_center);
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
                _portraits.Draw(g, bmp, inner, Scale);
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
        Math.Floor(target.Hp).ToString("0", CultureInfo.InvariantCulture) + " / " + Math.Floor(target.HpMax).ToString("0", CultureInfo.InvariantCulture);
    internal static string CompactHealthText(PlayerHudFocusTarget target) =>
        Value(target.Hp) + "/" + Value(target.HpMax);
    internal static string DensePercent(double hp, double maximum) =>
        hp > 0 && hp < maximum / 100d ? "<1%" : PlayerHudResourceStyle.Percent(hp, maximum);

    internal static string DenseValue(double value)
    {
        double magnitude = Math.Abs(value);
        if (magnitude < 10_000) return Math.Floor(value).ToString("0", CultureInfo.InvariantCulture);
        double unit = PlayerHudNumberFormat.Unit(magnitude);
        double scaled = magnitude / unit;
        if (scaled >= 10_000)
        {
            int exponent = (int)Math.Floor(Math.Log10(magnitude));
            double leading = Math.Truncate(value / Math.Pow(10, exponent - 1)) / 10d;
            return leading.ToString("0.#", CultureInfo.InvariantCulture) + "E" + exponent.ToString(CultureInfo.InvariantCulture);
        }
        double factor = scaled < 1000 ? 10d : 1d;
        return (Math.Truncate(value / unit * factor) / factor).ToString("0.#", CultureInfo.InvariantCulture) + PlayerHudNumberFormat.UnitSuffix(unit);
    }

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
            var rowRect = RowBounds(buffCount, i, targets.Length, AllyCount);
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
        _portraits.Dispose();
        foreach (var fill in _plateFills.Values) fill.Dispose();
        _plateFills.Clear();
        _font.Dispose();
        _badgeFont.Dispose();
        _initialFont.Dispose();
        ClearPlates();
        _shortFont.Dispose();
        _denseFont.Dispose();
        _label.Dispose();
        _center.Dispose();
        base.Dispose();
    }
}
