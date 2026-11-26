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
    internal const float RowHeight = 34f;
    internal const float RowGap = 2f;
    internal const int ComboPulseDurationMs = 150;

    internal const float HpReadoutMaxWidth = 92f;
    internal const double ExactHpCompactThreshold = 1_000_000;

    private sealed class TargetVisualState
    {
        internal FocusLifeState Life;
        internal int LastHits;
        internal int ComboPulseAgeMs = ComboPulseDurationMs;
        internal string? RawName;
        internal string SanitizedName = "";
        internal string? MeasuredName;
        internal float MeasuredScale, NameWidth;
        internal int MeasuredHitDigits = -1;
        internal float HitWidth, HitScale;

        internal TargetVisualState(PlayerHudFocusTarget target)
        {
            var health = new UnitHealth(target.Hp, target.HpMax);
            Life = new FocusLifeState(health);
            Life.Apply(health, target.ShieldRatio, target.PoiseRatio, target.HasPoise,
                target.Rigid, target.Airborne, target.Down, target.Darkened,
                target.HitSeq, staticFeedback: true);
        }

        internal string GetSanitizedName(string raw)
        {
            if (ReferenceEquals(RawName, raw) || string.Equals(RawName, raw, StringComparison.Ordinal))
                return SanitizedName;
            RawName = raw;
            SanitizedName = raw.IndexOf('\r') >= 0 || raw.IndexOf('\n') >= 0
                ? raw.Replace('\r', ' ').Replace('\n', ' ')
                : raw;
            return SanitizedName;
        }

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
    private readonly List<Rectangle> _damageScratch = new(16);
    private readonly PointF[] _chipPoly = new PointF[4];
    private PlayerHudFocusTarget[]? _lastRawTargets;
    private PlayerHudFocusTarget[] _lastOrderedTargets = Array.Empty<PlayerHudFocusTarget>();
    private PlayerHudFocusTarget[] _lastTargets = Array.Empty<PlayerHudFocusTarget>();
    private RectangleF _lastLayout;
    private bool _lastSuppressed;
    private long _epoch;
    private string? _hoverKey;
    private long _hoverId = -1;
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

    // Top two focus targets always get full-width rows (protect & active boss/combat guaranteed readable).
    // Targets 3..8 share a single compact strip beneath row 1.
    private static bool Dense(int count, int allies) => count > 2;
    internal static RectangleF BoundsForBuffCount(int buffCount, int targetCount = 1) => BoundsForBuffCount(buffCount,targetCount,0);
    internal static RectangleF BoundsForBuffCount(int buffCount, int targetCount, int allyCount) =>
        new(6, 0, ColumnWidth, targetCount <= 1 ? 36 : targetCount == 2 ? 72 : 97);

    internal static RectangleF RowBounds(int buffCount, int index, int targetCount) => RowBounds(buffCount,index,targetCount,0);
    internal static RectangleF RowBounds(int buffCount, int index, int targetCount, int allyCount)
    {
        if (index == 0) return new(6, 0, ColumnWidth, 36);
        if (index == 1) return new(6, 38, ColumnWidth, 34);
        float width = (ColumnWidth - 4) / Math.Max(1, targetCount - 2);
        return new(8 + (index - 2) * width, 74, width, 23);
    }

    // Guarantee both a primary protect (critical first) and an active enemy (boss > combat)
    // occupy the two wide rows whenever 3+ targets coexist, without mutating raw wire order.
    internal static PlayerHudFocusTarget[] OrderForDisplay(PlayerHudFocusTarget[] raw)
    {
        if (raw.Length <= 2) return raw;
        int firstIdx = 0;
        for (int i = 0; i < raw.Length; i++)
        {
            if (raw[i].Role == "protect" && Band(raw[i]) == 2)
            {
                firstIdx = i;
                break;
            }
        }
        int secondIdx = firstIdx == 0 ? 1 : 0;
        if (raw[firstIdx].Role == "protect")
        {
            int enemyIdx = -1;
            for (int i = 0; i < raw.Length; i++)
            {
                if (i == firstIdx) continue;
                if (raw[i].Role == "boss") { enemyIdx = i; break; }
                if (raw[i].Role == "combat" && enemyIdx < 0) enemyIdx = i;
            }
            if (enemyIdx >= 0) secondIdx = enemyIdx;
        }
        if (firstIdx == 0 && secondIdx == 1) return raw;
        var ordered = new PlayerHudFocusTarget[raw.Length];
        ordered[0] = raw[firstIdx];
        ordered[1] = raw[secondIdx];
        int dst = 2;
        for (int i = 0; i < raw.Length; i++)
        {
            if (i == firstIdx || i == secondIdx) continue;
            ordered[dst++] = raw[i];
        }
        return ordered;
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

    private static int DigitCount(int n)
    {
        if (n < 10) return 1;
        if (n < 100) return 2;
        if (n < 1000) return 3;
        if (n < 10000) return 4;
        if (n < 100000) return 5;
        return 6;
    }

    private static bool TargetsEqual(PlayerHudFocusTarget[] a, PlayerHudFocusTarget[] b)
    {
        if (ReferenceEquals(a, b)) return true;
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++)
            if (!Equals(a[i], b[i])) return false;
        return true;
    }

    private PlayerHudFocusTarget[] GetOrderedTargets(PlayerHudFocusTarget[] raw)
    {
        if (ReferenceEquals(raw, _lastRawTargets)) return _lastOrderedTargets;
        _lastRawTargets = raw;
        _lastOrderedTargets = OrderForDisplay(raw);
        return _lastOrderedTargets;
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
            _lastRawTargets = null;
            CancelHover();
        }
        var raw = s?.TargetList ?? Array.Empty<PlayerHudFocusTarget>();
        var targets = GetOrderedTargets(raw);
        bool targetsChanged = epochChanged || !TargetsEqual(targets, _lastTargets);
        bool stableRows = !epochChanged && targets.Length == _lastTargets.Length;
        int changedHealth = 0, changedBars = 0, changedHits = 0, wholeRows = 0;
        if (_hoverId >= 0)
        {
            bool hoverFound = false;
            if (s != null)
            {
                for (int i = 0; i < targets.Length; i++)
                    if (targets[i].Id == _hoverId) { hoverFound = true; break; }
            }
            if (!hoverFound) CancelHover();
        }

        if (targets.Length == 0)
        {
            _states.Clear();
            _requestedDolls.Clear();
        }
        else if (targetsChanged)
        {
            _activeIds.Clear();
            const int fullRows = 2;
            for (int i = 0; i < targets.Length; i++)
            {
                var target = targets[i];
                bool compact = i >= fullRows;
                _activeIds.Add(target.Id);
                var health = new UnitHealth(target.Hp, target.HpMax);
                if (!_states.TryGetValue(target.Id, out var st))
                {
                    stableRows = false;
                    st = new TargetVisualState(target);
                    _states.Add(target.Id, st);
                }
                else
                {
                    st.Life.Apply(health, target.ShieldRatio, target.PoiseRatio, target.HasPoise,
                        target.Rigid, target.Airborne, target.Down, target.Darkened,
                        target.HitSeq, PlayerHudMotionSettings.StaticFeedback);
                    if (stableRows)
                    {
                        var old = _lastTargets[i];
                        if (!SameRow(old, target))
                            stableRows = false;
                        else if (Band(old) != Band(target) || (old.Hp > 0) != (target.Hp > 0))
                            wholeRows |= 1 << i;
                        else
                        {
                            if (old.Hits != target.Hits)
                            {
                                // Only trigger a full-row repaint when HIT chip appears/disappears,
                                // changes digit-width (shifting nameLeft), or lives on a compact row.
                                if (compact || (old.Hits > 0) != (target.Hits > 0) || DigitCount(old.Hits) != DigitCount(target.Hits))
                                    wholeRows |= 1 << i;
                                else
                                    changedHits |= 1 << i;
                            }
                            if (old.Hp != target.Hp || old.HpMax != target.HpMax)
                                changedHealth |= 1 << i;
                            else if (old.Shield != target.Shield || old.ShieldMax != target.ShieldMax ||
                                old.Poise != target.Poise || old.Flags != target.Flags || old.HitSeq != target.HitSeq)
                                changedBars |= 1 << i;
                        }
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
        bool local = stableRows && (changedHealth | changedBars | changedHits | wholeRows) != 0 && layout == _lastLayout && !Suppressed && !_lastSuppressed;
        var previous = _lastTargets;
        _lastTargets = targets; _lastLayout = layout; _lastSuppressed = Suppressed;
        if (local) NotifyVisualChange(TrackDamage(targets.Length, changedBars, changedHealth, previous, wholeRows, changedHits));
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
        int changedHits = 0;
        int changedBars = 0;
        var targets = _lastTargets;

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
                    changedHits |= 1 << i;
                    changed = true;
                }
            }
        }

        if (!changed) return;
        NotifyVisualChange(TrackDamage(targets.Length, changedBars, changedHits: changedHits));
    }

    private static RectangleF HitChipBounds(RectangleF row, PlayerHudFocusTarget target, TargetVisualState state)
    {
        var portrait = Portrait(row);
        float by = row.Top + (row.Top == 0 ? 4 : 3);
        bool boss = target.Role == "boss", combat = target.Role == "combat";
        float badgeW = boss ? 32 : combat ? 30 : 44;
        float hitLeft = portrait.Right + 4.8f + badgeW + 4.5f;
        float hitW = state.HitWidth > 0 ? state.HitWidth : 44f;
        return new RectangleF(hitLeft, by, hitW, 12f);
    }

    // A pure trail/fill/shield/poise/hitFlash change only affects pixels inside the dual life track;
    // combo hit count / pulse updates only affect the HIT chip rectangle.
    private EventArgs TrackDamage(int count, int changedBars, int changedHealth = 0, PlayerHudFocusTarget[]? previous = null,
        int wholeRows = 0, int changedHits = 0)
    {
        var viewport = Viewport;
        float scale = viewport.Height / 576f;
        if (scale <= 0) return EventArgs.Empty;
        int all = changedBars | changedHealth | changedHits | wholeRows;
        _damageScratch.Clear();
        int buffs = Snapshot!.BuffCards.Length;
        int trackPad = Math.Max(1, (int)Math.Ceiling(scale * 0.75f + 1.0f));
        for (int i = 0; i < count; i++)
        {
            if ((all & (1 << i)) == 0) continue;
            var row = RowBounds(buffs, i, count, AllyCount);
            if ((wholeRows & (1 << i)) != 0)
            {
                // The critical glow, band shift, or HIT chip show/hide can affect the
                // whole card. The centered GDI stroke also covers the half-pixel sample
                // fringe: the Boss lower edge changes a second pixel at 1080p.
                _damageScratch.Add(ToPixels(row, viewport, scale, Math.Max(1, (int)Math.Ceiling(scale * 0.5f + 0.5f))));
                continue;
            }
            var rowPx = ToPixels(row, viewport, scale, 0);
            if (((changedBars | changedHealth) & (1 << i)) != 0)
            {
                var trackPx = ToPixels(LifeTrack(row), viewport, scale, trackPad);
                _damageScratch.Add(Rectangle.Intersect(trackPx, rowPx));
            }
            if (previous != null && (changedHealth & (1 << i)) != 0)
                _damageScratch.Add(ToPixels(ReadoutDamage(row, previous[i], _lastTargets[i]), viewport, scale, 2));
            if ((changedHits & (1 << i)) != 0 && !Secondary(row) && _states.TryGetValue(_lastTargets[i].Id, out var st))
            {
                var hitPx = ToPixels(HitChipBounds(row, _lastTargets[i], st), viewport, scale, 2);
                _damageScratch.Add(Rectangle.Intersect(hitPx, rowPx));
            }
        }
        return new HudRepaintRegions(_damageScratch.ToArray(), authoritative: previous != null);
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
            return new(row.X + 5.2f, row.Y + pad, first ? 26 : 24, row.Height - 2 * pad);
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
            return new(x, row.Bottom - (first ? 13.8f : 12.6f), row.Right - 6 - x, first ? 10.6f : 9.6f);
        }
        bool stacked = Stacked(row);
        float left = stacked ? p.X : p.Right + 4.5f;
        return new(left, row.Bottom - (stacked ? 4.5f : 7.6f), row.Right - (stacked ? 3 : 5) - left, stacked ? 3.3f : 5.0f);
    }

    private float _digitAdvance, _slashAdvance, _percentReserveWidth;
    private float ReservedHpWidth(PlayerHudFocusTarget target)
    {
        if (_digitAdvance == 0)
        {
            for (char digit = '0'; digit <= '9'; digit++)
                _digitAdvance = Math.Max(_digitAdvance, _numbers.Width(digit.ToString(), 11, HpReadoutMaxWidth));
            _slashAdvance = _numbers.Width("/", 11, HpReadoutMaxWidth);
            _percentReserveWidth = Math.Max(26f, _numbers.Width("100%", 10.2f, 36f));
        }
        int maxDigits = PlayerHudNumberFormat.Full(target.HpMax).Length;
        int digits = Math.Max(maxDigits, PlayerHudNumberFormat.Full(target.Hp).Length) + maxDigits;
        return Math.Min(HpReadoutMaxWidth, digits * _digitAdvance + _slashAdvance);
    }

    private float ReservedWidth(PlayerHudFocusTarget target) => ReservedHpWidth(target) + 4.5f + _percentReserveWidth;

    private static (float Left, float Right) SecondaryTextEdges(RectangleF row, RectangleF portrait) =>
        (portrait.Right + (Stacked(row) ? 2.6f : 4.5f), row.Right - (Stacked(row) ? 3f : 5f));

    private static float NarrowPercentWidth(float left, float right) => Math.Min(26f, right - left);

    private RectangleF ReadoutDamage(RectangleF row, PlayerHudFocusTarget old, PlayerHudFocusTarget target)
    {
        if (Secondary(row))
        {
            var (headerLeft, right) = SecondaryTextEdges(row, Portrait(row));
            bool stacked = Stacked(row);
            // In a cell with an HP pair, the fitted numbers also move the name's
            // ellipsis and can toggle its HIT badge. Both old and new ink live in this header.
            float readoutLeft = row.Width >= 140f ? headerLeft : right - NarrowPercentWidth(headerLeft, right);
            return RectangleF.FromLTRB(readoutLeft - 2, row.Y + (stacked ? 8 : 1),
                row.Right, row.Y + (stacked ? 19 : 16));
        }
        float reserve = ReservedWidth(target);
        float left = reserve == ReservedWidth(old) ? row.Right - 6 - reserve : Portrait(row).Right;
        return RectangleF.FromLTRB(left - 3, row.Top + 1, row.Right - 2, row.Top + 20);
    }

    protected override void PaintLogical(Graphics g)
    {
        var s = Snapshot!;
        var targets = _lastTargets;
        var buffCount = s.BuffCards.Length;
        float scale = Scale;
        float tx, ty, sx, sy;
        using (var transform = g.Transform)
        {
            var e = transform.Elements;
            sx = e[0]; sy = e[3]; tx = e[4]; ty = e[5];
        }
        using var clip = g.Clip;
        var prevSmooth = g.SmoothingMode;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        try
        {
            bool compactStripVisible = false;
            if (targets.Length > 2)
            {
                var strip = new RectangleF(6, 74, ColumnWidth, 23);
                compactStripVisible = clip.IsVisible(RectangleF.Inflate(strip, 1, 1));
                if (compactStripVisible)
                    MetalPlate(g, strip, 2, 5, 2, 2, 0x23282B, 0x111517, 0x090C0D,
                        Color.FromArgb(118, 206, 214, 212), .8f, sx, sy, tx, ty);
            }
            // A slanted divider crosses the cell boundary. Let the strip's device clip
            // rasterize that edge, even when the neighboring cell's content is culled.
            using var divider = compactStripVisible && targets.Length > 3
                ? new Pen(Color.FromArgb(56, 214, 217, 215), .8f) : null;
            for (int i = 0; i < targets.Length; i++)
            {
                var row = RowBounds(buffCount, i, targets.Length, AllyCount);
                if (i > 2 && divider != null)
                    g.DrawLine(divider, row.Left + 1.5f, row.Top + 2.5f, row.Left - 1.5f, row.Bottom - 2.5f);
                if (clip.IsVisible(RectangleF.Inflate(row, 2f, 2f)))
                    PaintRow(g, clip, targets[i], row, scale, sx, sy, tx, ty);
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

    private void MetalPlate(Graphics g, RectangleF r, float tl, float tr, float br, float bl,
        int top, int middle, int bottom, Color rim, float rimWidth, float sx, float sy, float tx, float ty)
    {
        float ox = r.Left * sx + tx, oy = r.Top * sy + ty;
        int left = (int)Math.Floor(ox) - 3, topPx = (int)Math.Floor(oy) - 3;
        float dx = ox - left, dy = oy - topPx;
        int w = (int)Math.Ceiling(r.Width * sx) + 7, h = (int)Math.Ceiling(r.Height * sy) + 7;
        var stampKey = (r, top, middle, bottom, rim.ToArgb(), rimWidth, sx, dx, dy);
        if ((long)w * h * 4 <= 768 * 1024)
        {
            if (!_plates.TryGetValue(stampKey, out var tile))
            {
                if (_plateBytes + (long)w * h * 4 > 2 * 1024 * 1024) ClearPlates();
                tile = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
                using var local = Graphics.FromImage(tile);
                local.SmoothingMode = g.SmoothingMode;
                local.TranslateTransform(dx - r.Left * sx, dy - r.Top * sy);
                local.ScaleTransform(sx, sy);
                DrawPlate(local, r, ChamferedPlaque(r, tl, tr, br, bl), top, middle, bottom, rim, rimWidth);
                _plates.Add(stampKey, tile);
                _plateBytes += (long)w * h * 4;
            }
            var saved = g.Save(); g.ResetTransform();
            try { g.DrawImageUnscaled(tile, left, topPx); } finally { g.Restore(saved); }
            return;
        }
        DrawPlate(g, r, ChamferedPlaque(r, tl, tr, br, bl), top, middle, bottom, rim, rimWidth);
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
        t.Role == "boss" ? 0xc6483e : t.Role == "combat" ? 0xb0bcba : 0x52b6c4);

    private static Color HealthInk(int band) => Rgb(band == 2 ? 0xff8a78 : band == 1 ? 0xf1c970 : 0xeef2f0);

    private static Color PercentInk(PlayerHudFocusTarget t, int band) => Rgb(band == 2 ? 0xff9c88 : band == 1 ? 0xf6cf74 :
        t.Role == "boss" ? 0xf2a094 : t.Role == "combat" ? 0xc2d8dc : 0x86e8f2);

    private void PaintRow(Graphics g, Region clip, PlayerHudFocusTarget target, RectangleF row, float scale,
        float sx, float sy, float tx, float ty)
    {
        bool compact = Secondary(row);
        bool boss = target.Role == "boss", combat = target.Role == "combat";
        int band = Band(target);
        var portrait = Portrait(row);
        var state = _states[target.Id];
        if (!compact)
        {
            bool first = row.Top == 0;
            bool protect = !boss && !combat;
            // Keep outer card rim static per role/band so combo pulses never thrash _plates cache
            // or trigger whole-row repaints; the HIT chip border carries the combo pulse.
            var rim = _hoverId == target.Id ? Color.White :
                band == 2 ? Rgb(0xff6656) :
                band == 1 ? Color.FromArgb(205, 228, 182, 92) :
                boss ? Color.FromArgb(195, 206, 96, 84) :
                protect ? Color.FromArgb(178, 86, 184, 198) :
                Color.FromArgb(184, 192, 204, 202);
            MetalPlate(g, row, first ? 0 : 2.5f, first ? 0 : 4, 6, first ? 4 : 2.5f,
                band == 2 ? 0x341717 : boss ? 0x2a1f21 : protect ? 0x1b2629 : 0x23272a,
                band == 2 ? 0x180b0c : boss ? 0x151012 : protect ? 0x0f1618 : 0x111416,
                band == 2 ? 0x0c0708 : 0x090c0d,
                rim, band == 2 ? 1.25f : boss ? 1.0f : .85f, sx, sy, tx, ty);
        }
        var bladeRect = new RectangleF(row.X + (compact ? 2.5f : 1.3f), row.Y + (row.Top == 0 ? 1.5f : 3f),
            compact ? 2.2f : 2.1f, row.Height - (row.Top == 0 ? 4.5f : 6f));
        if (clip.IsVisible(RectangleF.Inflate(bladeRect, 1f, 1f)))
        {
            using var blade = new SolidBrush(Accent(target, band));
            g.FillRectangle(blade, bladeRect);
        }
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
        if (clip.IsVisible(RectangleF.Inflate(track, 2.5f, 2.5f)))
        {
            var visual = state.Life.Visual with { Critical = band == 2 };
            var style = FillStyle(target.Role);
            UnitLifeBarPainter.Paint(g, track, visual, style, PlayerHudMotionSettings.EventStrength, sx, sy, tx, ty);
        }
        if (!clip.IsVisible(new RectangleF(row.X, row.Top, row.Width, compact ? 18.5f : 20.5f))) return;
        if (compact) PaintSecondaryText(g, clip, target, state, row, portrait, band, scale);
        else PaintPrimaryText(g, clip, target, state, row, portrait, band, scale);
    }

    private void PaintSecondaryText(Graphics g, Region clip, PlayerHudFocusTarget target, TargetVisualState state,
        RectangleF row, RectangleF portrait, int band, float scale)
    {
        bool stacked = Stacked(row);
        bool boss = target.Role == "boss", combat = target.Role == "combat";
        var (left, right) = SecondaryTextEdges(row, portrait);
        string percent = PlayerHudResourceStyle.Percent(target.Hp, target.HpMax);

        if (row.Width >= 220f)
        {
            // Single compact cell (290px): enough room for full role badge + optional HIT + name + % + full HP.
            var badge = new RectangleF(left, row.Y + 1.5f, boss ? 30 : combat ? 28 : 38, 11);
            var fill = Rgb(band == 2 ? 0x4d1715 : band == 1 ? 0x272013 : boss ? 0x421819 : combat ? 0x242a2d : 0x16262a);
            var edge = band == 2 ? Rgb(0xff7a6b) : band == 1 ? Rgb(0xd8a84c) : boss ? Rgb(0xd87062) : combat ? Rgb(0xa4b2b0) : Rgb(0x64b8c4);
            if (clip.IsVisible(RectangleF.Inflate(badge, 2, 2)))
                Chip(g, badge, fill, edge, boss ? "Boss" : combat ? "交战" : band == 2 ? "濒危" : "保护", boss);
            left = badge.Right + 4f;

            string exact = PlayerHudNumberFormat.Full(target.Hp) + "/" + PlayerHudNumberFormat.Full(target.HpMax);
            float hpW = _numbers.DrawRight(g, exact, right, row.Y + 11.8f, 9.6f, scale, 82f, HealthInk(band), compactThreshold: ExactHpCompactThreshold);
            float pctW = _numbers.DrawRight(g, percent, right - hpW - 4f, row.Y + 11.8f, 9.2f, scale, 28f, PercentInk(target, band));
            float nameRight = right - hpW - pctW - 9f;

            if (target.Hits > 0 && nameRight - left >= 58f)
            {
                string hitText = target.Hits.ToString(CultureInfo.InvariantCulture) + " HIT";
                float hitW = Math.Clamp((float)Math.Ceiling(g.MeasureString(hitText, _denseFont, PointF.Empty, _label).Width) + 8f, 32f, 52f);
                var hitRect = new RectangleF(left, row.Y + 1.5f, hitW, 11f);
                if (clip.IsVisible(RectangleF.Inflate(hitRect, 2, 2)))
                    Chip(g, hitRect, Rgb(0x171c1e), Color.FromArgb(142 + (int)(64 * state.ComboPulse), 192, 202, 200), hitText, false);
                left += hitW + 4f;
            }
            if (nameRight > left)
                g.DrawString(state.GetSanitizedName(target.Name), _shortFont, Brushes.White,
                    new RectangleF(left, row.Y + 1f, nameRight - left, 13f), _label);
            return;
        }

        if (row.Width >= 140f)
        {
            // Two compact cells (~145px): mini 1-char role tag + name + compact HP + %.
            var mini = new RectangleF(left, row.Y + 2f, 12f, 10.5f);
            var fill = Rgb(band == 2 ? 0x4d1715 : boss ? 0x421819 : combat ? 0x262c2e : 0x16262a);
            var edge = band == 2 ? Rgb(0xff7a6b) : boss ? Rgb(0xd87062) : combat ? Rgb(0xa4b2b0) : Rgb(0x64b8c4);
            if (clip.IsVisible(RectangleF.Inflate(mini, 1, 1)))
                Chip(g, mini, fill, edge, boss ? "首" : combat ? "战" : "护", false);
            left = mini.Right + 3f;

            float pctW = _numbers.DrawRight(g, percent, right, row.Y + 11.8f, 9.2f, scale, 26f, PercentInk(target, band));
            string compactHp = DenseValue(target.Hp) + "/" + DenseValue(target.HpMax);
            float hpW = _numbers.DrawRight(g, compactHp, right - pctW - 3.5f, row.Y + 11.8f, 8.8f, scale, 52f, HealthInk(band));
            float nameWidth = right - pctW - hpW - 7.5f - left;
            if (nameWidth > 4f)
                g.DrawString(state.GetSanitizedName(target.Name), _shortFont, Brushes.White,
                    new RectangleF(left, row.Y + 1f, nameWidth, 13f), _label);
            return;
        }

        float numberWidth = NarrowPercentWidth(left, right);
        if (!stacked)
        {
            var mini = new RectangleF(left, row.Y + 2.2f, 11.5f, 10f);
            var fill = Rgb(band == 2 ? 0x4d1715 : boss ? 0x421819 : combat ? 0x262c2e : 0x16262a);
            var edge = band == 2 ? Rgb(0xff7a6b) : boss ? Rgb(0xd87062) : combat ? Rgb(0xa4b2b0) : Rgb(0x64b8c4);
            if (clip.IsVisible(RectangleF.Inflate(mini, 1, 1)))
                Chip(g, mini, fill, edge, boss ? "首" : combat ? "战" : "护", false);
            left = mini.Right + 2.5f;
        }
        float narrowNameWidth = (stacked ? right : right - numberWidth - 3) - left - 1;
        var nameBounds = new RectangleF(left, row.Y + (stacked ? 0 : 1), narrowNameWidth, stacked ? 11 : 14);
        if (narrowNameWidth > 0 && clip.IsVisible(RectangleF.Inflate(nameBounds, 2, 2)))
            g.DrawString(state.GetSanitizedName(target.Name), stacked ? _denseFont : _shortFont,
                Brushes.White, nameBounds, _label);
        _numbers.DrawRight(g, percent, right, row.Y + (stacked ? 17.1f : 11.8f),
            stacked ? 8f : 8.4f, scale, Math.Max(1, numberWidth), PercentInk(target, band));
    }

    private void PaintPrimaryText(Graphics g, Region clip, PlayerHudFocusTarget target, TargetVisualState state,
        RectangleF row, RectangleF portrait, int band, float scale)
    {
        float by = row.Top + (row.Top == 0 ? 4 : 3);
        bool boss = target.Role == "boss", combat = target.Role == "combat";
        var badge = new RectangleF(portrait.Right + 4.8f, by, boss ? 32 : combat ? 30 : 44, 12);
        var fill = Rgb(band == 2 ? 0x4d1715 : band == 1 ? 0x272013 : boss ? 0x421819 : combat ? 0x242a2d : 0x16262a);
        var edge = band == 2 ? Rgb(0xff7a6b) : band == 1 ? Rgb(0xd8a84c) : boss ? Rgb(0xd87062) : combat ? Rgb(0xa4b2b0) : Rgb(0x64b8c4);
        if (clip.IsVisible(RectangleF.Inflate(badge, 2, 2)))
            Chip(g, badge, fill, edge, boss ? "Boss" : combat ? "交战" : band == 2 ? "濒危" : "保护目标", boss);
        float right = row.Right - 6;
        float totalReserve = ReservedWidth(target);
        if (clip.IsVisible(new RectangleF(right - totalReserve - 4, by - 4, totalReserve + 8, 20)))
        {
            string exact = PlayerHudNumberFormat.Full(target.Hp) + "/" + PlayerHudNumberFormat.Full(target.HpMax);
            float hpW = _numbers.DrawRight(g, exact, right, by + 10.2f, 11, scale, HpReadoutMaxWidth, HealthInk(band), compactThreshold: double.PositiveInfinity);
            string pct = PlayerHudResourceStyle.Percent(target.Hp, target.HpMax);
            _numbers.DrawRight(g, pct, right - hpW - 4.5f, by + 10.2f, 10.2f, scale, _percentReserveWidth, PercentInk(target, band));
        }
        float nameLeft = badge.Right + 4.5f;
        float nameRight = right - totalReserve - 4;
        string name = state.GetSanitizedName(target.Name);
        if (state.MeasuredName != name || state.MeasuredScale != scale)
        {
            state.NameWidth = g.MeasureString(name, _font, PointF.Empty, _label).Width;
            state.MeasuredName = name;
            state.MeasuredScale = scale;
        }
        if (target.Hits > 0)
        {
            int hitDigits = DigitCount(target.Hits);
            if (state.MeasuredHitDigits != hitDigits || state.HitScale != scale)
            {
                string sample = hitDigits switch
                {
                    1 => "8 HIT",
                    2 => "88 HIT",
                    3 => "888 HIT",
                    4 => "8888 HIT",
                    _ => new string('8', hitDigits) + " HIT"
                };
                state.HitWidth = Math.Max(38, (float)Math.Ceiling(g.MeasureString(sample, _badgeFont, PointF.Empty, _label).Width) + 8);
                state.MeasuredHitDigits = hitDigits;
                state.HitScale = scale;
            }
            float width = state.HitWidth;
            if (nameRight - nameLeft >= width + 24f)
            {
                var hit = new RectangleF(nameLeft, by, width, 12);
                if (clip.IsVisible(RectangleF.Inflate(hit, 2, 2)))
                {
                    string hitText = target.Hits.ToString(CultureInfo.InvariantCulture) + " HIT";
                    Chip(g, hit, Rgb(0x171c1e), Color.FromArgb(138 + (int)(68 * state.ComboPulse), 192, 202, 200), hitText, false);
                }
                nameLeft += width + 5;
            }
        }
        if (nameRight > nameLeft && clip.IsVisible(new RectangleF(nameLeft - 2, by - 4, nameRight - nameLeft + 4, 20)))
        {
            using var ink = new SolidBrush(Rgb(band == 1 ? 0xf6e5bc : 0xf2f5f3));
            g.DrawString(name, _font, ink, new RectangleF(nameLeft, by - 2, nameRight - nameLeft, 16), _label);
        }
    }

    private void Chip(Graphics g, RectangleF r, Color fill, Color edge, string text, bool boss)
    {
        _chipPoly[0] = new(r.Left + 2.4f, r.Top);
        _chipPoly[1] = new(r.Right, r.Top);
        _chipPoly[2] = new(r.Right - 2.4f, r.Bottom);
        _chipPoly[3] = new(r.Left, r.Bottom);
        using var brush = new SolidBrush(fill);
        using var pen = new Pen(edge, .7f);
        g.FillPolygon(brush, _chipPoly);
        g.DrawPolygon(pen, _chipPoly);
        if (boss)
        {
            using var red = new Pen(Rgb(0xb03932), 2.3f);
            g.DrawLine(red, r.Left + 4, r.Top + .8f, r.Left + 1.8f, r.Bottom - .8f);
        }
        g.DrawString(text, _badgeFont, Brushes.White, r, _center);
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
        if (!Visible || !Controller.CanInteract || Snapshot is not { } s || _lastTargets.Length == 0 || Scale <= 0) return null;
        var targets = _lastTargets;
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
        _hoverId = target != null && long.TryParse(target.Key, NumberStyles.None, CultureInfo.InvariantCulture, out long hid) ? hid : -1;
        if (target != null) Controller.ShowTooltip(target);
        Repaint();
    }

    private void CancelHover()
    {
        if (_hoverKey == null) return;
        _hoverKey = null;
        _hoverId = -1;
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
