#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal abstract class PlayerHudWidgetBase : INativeHudWidget, INativeHudResumable, IDisposable
{
    protected readonly Control Anchor;
    protected readonly PlayerHudController Controller;
    private readonly FlashCoordinateMapper _mapper;
    protected bool Suppressed, Disposed;
    private Rectangle _lastBounds;
    private bool _lastVisible, _lastAnimation;
    protected PlayerHudSnapshot? Snapshot => Controller.State.Snapshot;
    protected abstract RectangleF LogicalBounds { get; }
    protected virtual bool HasContent => Snapshot != null;
    protected Rectangle Viewport => RightHudLayout.GetViewportRect(Anchor, _mapper);
    protected float Scale => Viewport.Height / 576f;
    public bool Visible => !Disposed && !Suppressed && HasContent;
    public Rectangle ScreenBounds
    {
        get
        {
            if (!Visible) return Rectangle.Empty;
            var viewport = Viewport; var r = LogicalBounds; var scale = viewport.Height / 576f;
            return Rectangle.FromLTRB((int)Math.Floor(viewport.X + r.Left * scale),
                (int)Math.Floor(viewport.Y + r.Top * scale), (int)Math.Ceiling(viewport.X + r.Right * scale),
                (int)Math.Ceiling(viewport.Y + r.Bottom * scale));
        }
    }
    public event EventHandler? BoundsOrVisibilityChanged;
    public event EventHandler? RepaintRequested;
    public event EventHandler? AnimationStateChanged;
    public virtual bool WantsAnimationTick => false;
    protected PlayerHudWidgetBase(Control anchor, PlayerHudController controller)
    {
        Anchor = anchor; Controller = controller; _mapper = new FlashCoordinateMapper(anchor, 1024, 576);
        controller.State.Changed += OnStateChanged;
    }
    protected virtual void OnStateChanged()
    {
        var bounds = ScreenBounds; var visible = Visible; var animation = WantsAnimationTick;
        if (bounds != _lastBounds || visible != _lastVisible)
        {
            _lastBounds = bounds; _lastVisible = visible;
            BoundsOrVisibilityChanged?.Invoke(this, EventArgs.Empty);
        }
        if (animation != _lastAnimation) { _lastAnimation = animation; AnimationStateChanged?.Invoke(this, EventArgs.Empty); }
        Repaint();
    }
    protected void Repaint() => RepaintRequested?.Invoke(this, EventArgs.Empty);
    public virtual void SetHostSuppressed(bool suppressed)
    {
        if (Suppressed == suppressed) return;
        Suppressed = suppressed; OnStateChanged();
    }
    public void Paint(Graphics g, float dpr, Point hudOrigin)
    {
        if (!Visible || Scale <= 0) return;
        var saved = g.Save();
        try
        {
            var viewport = Viewport;
            g.TranslateTransform(viewport.X - hudOrigin.X, viewport.Y - hudOrigin.Y);
            g.ScaleTransform(Scale, Scale);
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            PaintLogical(g);
        }
        finally { g.Restore(saved); }
    }
    protected abstract void PaintLogical(Graphics g);
    protected PointF Logical(Point screen) => new((screen.X - Viewport.X) / Scale, (screen.Y - Viewport.Y) / Scale);
    public abstract bool TryHitTest(Point screenPt);
    public abstract void OnMouseEvent(MouseEventArgs e, MouseEventKind kind);
    public virtual void Tick(int deltaMs) { }
    public virtual void Dispose() { Disposed = true; Controller.State.Changed -= OnStateChanged; }
}

internal static class PlayerHudResourceStyle
{
    // Source: 新版人物文字信息 / 盾槽条 and 韧性条. Layout/labels separate MP from shields.
    internal static readonly Color Shield = Color.FromArgb(0, 255, 255);
    internal static readonly Color ShieldTrack = Color.FromArgb(24, 66, 70);
    internal static readonly Color ShieldEmpty = Color.FromArgb(94, 149, 149);
    internal static readonly Color Poise = Color.FromArgb(255, 204, 0);
    internal static readonly Color PoiseRisk = Color.FromArgb(204, 143, 0);
    internal static readonly Color ExperienceDark = Color.FromArgb(153,153,153);
    internal static readonly Color ExperienceLight = Color.FromArgb(229,229,229);

    internal static string PoiseCaption(PlayerHudPoise? detail) => detail?.Phase switch
    {
        "buffer" => detail.HasStaggerBand ? "缓冲段" : "无踉跄段",
        "stagger" => "踉跄风险", "break" => "破韧风险", "rigid" => "刚体",
        "air" => "浮空", "down" => "倒地", _ => "分界待就绪"
    };
    internal static string PoiseStateLabel(PlayerHudPoise? detail) => detail?.Phase switch
    {
        "stagger" => "踉跄", "break" => "破韧", "rigid" => "刚体", "air" => "浮空", "down" => "倒地", _ => ""
    };

    internal static string Percent(double current, double maximum)
    {
        var percent = maximum > 0 ? current * 100 / maximum : double.NaN;
        return double.IsFinite(percent) ? Math.Floor(percent).ToString("0", CultureInfo.InvariantCulture) + "%" : "--";
    }

    internal static string ShieldReadout(PlayerHudVitals value) => !value.ShieldReady ? "护盾未就绪"
        : !value.ShieldPresent ? ""
        : "盾 " + Math.Floor(value.Shield).ToString("0", CultureInfo.InvariantCulture) + " · " + Percent(value.Shield, value.ShieldMax);

    internal static string ShieldStrengthReadout(PlayerHudShield? detail) => detail?.StrengthKind switch
    {
        "unlimited" => "∞",
        "finite" => detail.Strength > 0 && detail.Strength < 1
            ? detail.Strength < 0.01 ? "<0.01" : detail.Strength.ToString("0.##",CultureInfo.InvariantCulture) : PlayerHudNumberFormat.Full(detail.Strength),
        _ => "--"
    };

    internal static (double Earned, double Required) LevelExperience(PlayerHudVitals value) =>
        (Math.Max(0, value.Experience - value.ExperienceStart), Math.Max(0, value.ExperienceEnd - value.ExperienceStart));

    internal static string ExperienceReadout(PlayerHudVitals value)
    {
        var (earned, required) = LevelExperience(value);
        return required > 0 ? Math.Floor(earned).ToString("0", CultureInfo.InvariantCulture) + "/" + Math.Floor(required).ToString("0", CultureInfo.InvariantCulture)
            : Math.Floor(value.Experience).ToString("0", CultureInfo.InvariantCulture);
    }
}

internal sealed class PlayerHudBottomWidget : PlayerHudWidgetBase
{
    internal const float NameVisibleWidth = 126.6f;
    internal const int PoisePulseDurationMs = 260;
    internal const int BankSwitchPulseDurationMs = 180;
    internal const int MessageHoldMs = 2100;
    internal const int MessageFadeMs = 400;
    internal const int MessageTotalMs = MessageHoldMs + MessageFadeMs;

    private readonly PlayerHudIconCache _icons;
    private readonly PlayerHudArtCache _art = new();
    private readonly PlayerHudTextCache _numbers = new();
    private readonly GraphicsPath _poiseCells = CreatePoiseCells();
    private sealed record Caption(string Text,GraphicsPath Path);
    // Countdown strings change often; retain only the current caption for each lane (18 base + up to 12 coldSkills).
    private readonly Caption?[] _captions = new Caption?[30];
    private readonly Caption?[] _countdownCaptions = new Caption?[30];
    private readonly Font _body = NativeHudFonts.CreateRoleFont("native.player-info.body", 10, FontStyle.Regular, GraphicsUnit.Pixel);
    private readonly Font _small = NativeHudFonts.CreateRoleFont("native.player-info.body", 9, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _nameFont = NativeHudFonts.CreateRoleFont("native.player-info.body", 11, FontStyle.Regular, GraphicsUnit.Pixel);
    private readonly Font _hotkeyFont = NativeHudFonts.CreateRoleFont("native.player-info.body", 9, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _poiseLabel = NativeHudFonts.CreateRoleFont("native.player-info.body", 10, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _slotMark = NativeHudFonts.CreateRoleFont("native.player-info.body", 12, FontStyle.Regular, GraphicsUnit.Pixel);
    private PlayerHudTarget? _hover, _down;
    private bool _upMatches;
    private int _nameClock;
    private int _resourceHintClock;
    private readonly PlayerHudDenialMotion _denial = new();
    private readonly int[] _readyFlash = new int[30];
    private readonly int[] _observedAmmoCapacity = new int[5];
    private PlayerHudCooldown[]? _lastCooldowns;
    private PlayerHudColdSkill[]? _lastColdSkills;
    private string? _lastPoisePhase;
    private int _poisePulseMs = -1;
    private bool _poisePulseIsRisk;
    private int _lastBank = -1;
    private int _bankSwitchPulseMs = -1;
    private int _messageAgeMs = -1;
    private static readonly float[] ReadyAlpha = [1, 0.828125f, 0.671875f, 0.5f, 0.328125f, 0.171875f, 0, 0];
    private static readonly float[] GridOffsets = [0, 0.25f, 0.5f, 0.75f, 1.05f, 1.3f, 1.55f, 1.8f, 2.1f, 2.35f, 2.6f];
    private long _epoch;
    internal static RectangleF SkillRect(int index) => new(602.25f + index * 35.05f, 536.5f, 26, 26);
    internal static RectangleF ColdSkillRect(int index) => new(602.25f + index * 35.05f, 478.5f, 26, 26);
    internal static RectangleF DrugRect(int lane) => new(343.8f + lane * 34.9f, 535.35f, 26, 26);
    internal static RectangleF UnequipRect(int index) => new(623.4f + index * 35f, 532.3f, 10, 10);
    internal static readonly RectangleF SwitchRect = new(308.9f, 535.35f, 26, 26);
    // The first authored header stripe doubles as the read-only details entry.
    internal static readonly RectangleF DetailsFace = new(947.3f, 518.05f, 19.65f, 7.7f);
    internal static readonly PointF[] DetailsOutline = [new(947.3f,518.05f),new(957.7f,518.05f),new(966.95f,525.75f),new(956.5f,525.75f)];
    internal static readonly RectangleF DetailsRect = new(945.3f, 515.05f, 23.65f, 13.7f);
    internal static RectangleF HotkeyRect(RectangleF slot) => new(slot.X+1,slot.Bottom-9.5f,slot.Width-2,9);
    internal static RectangleF CooldownTextRect(RectangleF slot) => new(slot.X+1f,slot.Y+4.0f,slot.Width-2f,9.5f);
    internal static RectangleF CooldownTrackRect(RectangleF slot) => new(slot.X+2,slot.Bottom-12,slot.Width-4,2);
    internal static readonly RectangleF WeaponRect = new(560.55f, 534.65f, 26, 26);
    protected override RectangleF LogicalBounds => VisibleColdSkills(Snapshot).Length > 0
        ? new(0, 474, 1024, 102)
        : new(0, 504, 1024, 72);

    internal static PlayerHudColdSkill[] VisibleColdSkills(PlayerHudSnapshot? snapshot)
    {
        if (snapshot?.ColdSkills is not { Length: > 0 } coldSkills) return Array.Empty<PlayerHudColdSkill>();
        var equipped = snapshot.Loadout.Skills;
        var count = 0;
        for (var i = 0; i < coldSkills.Length; i++)
        {
            if (!IsEquippedInQuickBar(coldSkills[i].Name, equipped)) count++;
        }
        if (count == coldSkills.Length) return coldSkills;
        if (count == 0) return Array.Empty<PlayerHudColdSkill>();
        var filtered = new PlayerHudColdSkill[count];
        var write = 0;
        for (var i = 0; i < coldSkills.Length; i++)
        {
            if (!IsEquippedInQuickBar(coldSkills[i].Name, equipped)) filtered[write++] = coldSkills[i];
        }
        return filtered;
    }

    private static bool IsEquippedInQuickBar(string name, PlayerHudSkill[] skills)
    {
        for (var i = 0; i < skills.Length; i++)
        {
            if (skills[i].Equipped && string.Equals(skills[i].Key, name, StringComparison.Ordinal)) return true;
        }
        return false;
    }
    public override bool WantsAnimationTick => Visible && Snapshot is { } s &&
        (s.Vitals.Hp > 0
        || Array.Exists(_readyFlash, time => time >= 0 && time < 234)
        || (_poisePulseMs >= 0 && _poisePulseMs < PoisePulseDurationMs)
        || (_bankSwitchPulseMs >= 0 && _bankSwitchPulseMs < BankSwitchPulseDurationMs)
        || (Controller.Message.Length > 0 && !Controller.WritePending && _messageAgeMs >= 0 && _messageAgeMs < MessageTotalMs));

    internal PlayerHudBottomWidget(Control anchor, PlayerHudController controller, string iconsRoot) : base(anchor, controller)
    {
        _icons = new PlayerHudIconCache(iconsRoot);
        Array.Fill(_readyFlash, -1);
        controller.StatusChanged += OnStatusChanged;
    }

    private void OnStatusChanged()
    {
        _messageAgeMs = Controller.Message.Length > 0 && !Controller.WritePending ? 0 : -1;
        base.OnStateChanged();
    }

    protected override void OnStateChanged()
    {
        if (Snapshot?.Epoch != _epoch)
        {
            _epoch = Snapshot?.Epoch ?? 0;
            _nameClock = _resourceHintClock = 0;
            _lastCooldowns = null;
            _lastColdSkills = null;
            _lastPoisePhase = null;
            _poisePulseMs = -1;
            _poisePulseIsRisk = false;
            _lastBank = -1;
            _bankSwitchPulseMs = -1;
            Array.Clear(_observedAmmoCapacity);
            Array.Fill(_readyFlash, -1);
            Cancel();
        }
        _denial.Observe(Snapshot, Visible);
        if (Snapshot is { } current)
        {
            ObserveCombatAmmo(current.Combat);

            if (_lastCooldowns != null)
                for (var i = 0; i < 18; i++) if (!_lastCooldowns[i].Ready && current.Cooldowns[i].Ready) _readyFlash[i] = 0;
            _lastCooldowns = current.Cooldowns;

            var visibleCold = VisibleColdSkills(current);
            if (_lastColdSkills != null)
            {
                for (var i = 0; i < Math.Min(12, visibleCold.Length); i++)
                {
                    var cur = visibleCold[i];
                    for (var j = 0; j < _lastColdSkills.Length; j++)
                    {
                        if (string.Equals(_lastColdSkills[j].Name, cur.Name, StringComparison.Ordinal))
                        {
                            if (!_lastColdSkills[j].Cooldown.Ready && cur.Cooldown.Ready) _readyFlash[18 + i] = 0;
                            break;
                        }
                    }
                }
            }
            _lastColdSkills = visibleCold;

            var poisePhase = current.Vitals.PoiseDetail?.Phase;
            if (_lastPoisePhase != null && poisePhase != null && _lastPoisePhase != poisePhase)
            {
                if (_lastPoisePhase == "buffer" && poisePhase is "stagger" or "break")
                {
                    _poisePulseMs = 0;
                    _poisePulseIsRisk = true;
                }
                else if (_lastPoisePhase is "stagger" or "break" && poisePhase == "buffer")
                {
                    _poisePulseMs = 0;
                    _poisePulseIsRisk = false;
                }
            }
            _lastPoisePhase = poisePhase;

            if (_lastBank >= 0 && current.Loadout.Bank != _lastBank)
                _bankSwitchPulseMs = 0;
            _lastBank = current.Loadout.Bank;
        }
        if (_hover != null && !StillCurrent(_hover)) { Controller.HideTooltip(); _hover = null; }
        if (_down != null && !StillCurrent(_down)) { _down = null; _upMatches = false; }
        base.OnStateChanged();
    }
    private bool StillCurrent(PlayerHudTarget t)
    {
        var s = Snapshot; if (s == null || s.Epoch != t.Epoch || t.ConnectionGeneration != Controller.Generation || t.Paused != s.Vitals.Paused) return false;
        return t.Kind switch { "skill" or "coldSkill" => t.Revision == s.Loadout.Revision,
            "drug" or "switch" => t.Revision == s.Loadout.DrugRevision && t.Bank == s.Loadout.Bank, _ => true };
    }
    public override void Tick(int deltaMs)
    {
        if (!Visible || Snapshot == null) return;
        var stepMs = Math.Max(0, deltaMs);
        var oldFrame = _nameClock * 3 / 100;
        if (Snapshot.Vitals.Hp > 0 && !PlayerHudMotionSettings.ReducedMotion) _nameClock = (_nameClock + stepMs) % 110000;
        if (Snapshot.Vitals.Hp > 0 && !Snapshot.Vitals.Paused && !PlayerHudMotionSettings.ReducedMotion)
            _resourceHintClock = (int)((_resourceHintClock + (long)stepMs) % PlayerHudSlotFeedbackGeometry.BreathPeriodMilliseconds);
        var changed = _nameClock * 3 / 100 != oldFrame;
        changed |= _denial.Advance(stepMs);
        for (var i = 0; i < _readyFlash.Length; i++)
        {
            if (_readyFlash[i] < 0 || _readyFlash[i] >= 234) continue;
            var old = _readyFlash[i] * 3 / 100;
            _readyFlash[i] += stepMs;
            changed |= _readyFlash[i] * 3 / 100 != old;
        }
        if (_poisePulseMs >= 0 && _poisePulseMs < PoisePulseDurationMs)
        {
            var oldPulse = _poisePulseMs * 3 / 100;
            _poisePulseMs += stepMs;
            changed |= _poisePulseMs * 3 / 100 != oldPulse || _poisePulseMs >= PoisePulseDurationMs;
        }
        if (_bankSwitchPulseMs >= 0 && _bankSwitchPulseMs < BankSwitchPulseDurationMs)
        {
            var oldBankPulse = _bankSwitchPulseMs * 3 / 100;
            _bankSwitchPulseMs += stepMs;
            changed |= _bankSwitchPulseMs * 3 / 100 != oldBankPulse || _bankSwitchPulseMs >= BankSwitchPulseDurationMs;
        }
        if (Controller.Message.Length > 0 && !Controller.WritePending && _messageAgeMs >= 0 && _messageAgeMs < MessageTotalMs)
        {
            var oldFadeFrame = _messageAgeMs >= MessageHoldMs ? (_messageAgeMs - MessageHoldMs) / 33 : -1;
            _messageAgeMs += stepMs;
            var newFadeFrame = _messageAgeMs >= MessageHoldMs ? (_messageAgeMs - MessageHoldMs) / 33 : -1;
            changed |= newFadeFrame != oldFadeFrame || _messageAgeMs >= MessageTotalMs;
        }
        if (changed) base.OnStateChanged();
    }
    internal static float NameOffset(int elapsedMs)
    {
        var frame = (float)Math.Floor((elapsedMs % 10000) * 0.03);
        if (frame < 99) return 3.7f;
        if (frame < 199) return 3.7f + (-130f - 3.7f) * (frame - 99) / 100;
        if (frame < 200) return -130;
        return 136f + (3.7f - 136f) * Math.Min(1, (frame - 200) / 99);
    }
    internal static float NameOffset(int elapsedMs, float textWidth) =>
        textWidth <= NameVisibleWidth ? 3.7f : NameOffset(elapsedMs);

    protected override void PaintLogical(Graphics g)
    {
        var s = Snapshot!; var v = s.Vitals;
        var muted = Color.FromArgb(204, 204, 204);
        using var text = new SolidBrush(Color.FromArgb(239, 238, 220));
        using var dim = new SolidBrush(muted);
        using var poise = new SolidBrush(PlayerHudResourceStyle.Poise);
        using var background = new SolidBrush(Color.FromArgb(200, 25, 30, 31));
        DrawArt(g, "bottom-panel", 49.7f, 568.45f, 0.8472137451f, 0.8472137451f);
        var resourcePanel = g.Save();
        g.TranslateTransform(PlayerHudResourceLayout.ResourceOffsetX,0);
        using (var raisedPanel=new LinearGradientBrush(new RectangleF(90,504,190,32),
            Color.FromArgb(44,47,48),Color.FromArgb(17,20,21),LinearGradientMode.Vertical))
            g.FillPolygon(raisedPanel,[new PointF(90,504),new PointF(271,504),new PointF(280,512),new PointF(280,537),new PointF(90,537)]);
        g.Restore(resourcePanel);
        var ornaments = g.Save();
        g.SetClip(new RectangleF(86+PlayerHudResourceLayout.ResourceOffsetX,535,194,38),CombineMode.Exclude);
        DrawArt(g, "bottom-ornaments", 49.7f, 568.45f, 0.8472137451f, 0.8472137451f);
        g.Restore(ornaments);
        var poiseState = PlayerHudResourceStyle.PoiseStateLabel(v.PoiseDetail);
        var poiseBar = PlayerHudResourceLayout.PoiseBar;
        if (poiseState.Length > 0)
            g.DrawString(poiseState,_poiseLabel,poise,poiseBar.Right+4,poiseBar.Top-2,StringFormat.GenericTypographic);
        var poiseFlags=PlayerHudPoisePainter.Flags(v);
        var poiseInk=poiseFlags.Airborne || poiseFlags.Down || v.PoiseDetail?.Phase=="unavailable" ? Color.FromArgb(160,167,171) : PlayerHudResourceStyle.Poise;
        _numbers.Draw(g, Math.Floor(v.Poise * 100).ToString(CultureInfo.InvariantCulture) + "%", PlayerHudResourceLayout.PoisePercentX, poiseBar.Bottom, 11.5f, Scale, PlayerHudResourceLayout.PoisePercentWidth, poiseInk);
        PaintPoise(g, v);
        var levelTransform=g.Save();g.TranslateTransform(PlayerHudResourceLayout.LevelOffsetX,0);
        using (var levelBase = new SolidBrush(Color.FromArgb(21,24,25)))
            g.FillPolygon(levelBase,[new PointF(4,PlayerHudResourceLayout.LevelTop),new PointF(74,PlayerHudResourceLayout.LevelTop),new PointF(86,573),new PointF(4,573)]);
        using (var edge = new Pen(Color.FromArgb(75,79,80),0.6f))
            g.DrawLines(edge,[new PointF(6,554),new PointF(73,554),new PointF(79,560)]);
        DrawSizedArt(g, "level-label", new RectangleF(12, 554, 20.65f, 17.8f));
        _numbers.Draw(g, v.Level.ToString(CultureInfo.InvariantCulture), 41, 572, 18, Scale, 37, muted);
        g.Restore(levelTransform);
        var (earned, required) = PlayerHudResourceStyle.LevelExperience(v);
        var xp = required > 0 ? Math.Clamp(earned / required, 0, 1) : 0;
        var xpColor = PlayerHudResourceStyle.ExperienceLight;
        _numbers.Draw(g, PlayerHudResourceStyle.Percent(earned, required), 90, 572, 14.5f, Scale, 36, xpColor);
        _numbers.Draw(g, PlayerHudResourceStyle.ExperienceReadout(v), 132, 572, 14.5f, Scale, 166, xpColor);
        var xpWidth = 293f;
        g.FillRectangle(background, 5, 573, xpWidth, 3);
        using (var xpBrush = new LinearGradientBrush(new RectangleF(5,573,xpWidth,3),
            PlayerHudResourceStyle.ExperienceDark,PlayerHudResourceStyle.ExperienceLight,LinearGradientMode.Vertical))
            g.FillRectangle(xpBrush, 5, 573, (float)(xpWidth * xp), 3);

        DrawArt(g, "skill-panel", 592.9f, 528.9f);
        DrawSizedArt(g, "skill-label", new RectangleF(598.9f, 511.2f, 2259f / 1024 * 18, 18));
        DrawSizedArt(g, "sp-label", new RectangleF(649.7f, 512.35f, 1679f / 1024 * 15, 15));
        _numbers.Draw(g, Number(v.SkillPoints), 677.15f, 525.2f, 18, Scale, 73.95f);
        PaintDetailsEntry(g);
        DrawArt(g, "drug-panel", 301.4f, 541.8f);
        DrawArt(g, "name-background", 342.35f, 514.65f);
        // Keep the authored mask and 300-frame loop; scroll only when the natural glyph width overflows.
        var saved = g.Save();
        g.SetClip(new RectangleF(342.35f, 514.85f, 134, 16), CombineMode.Intersect);
        var nameWidth = g.MeasureString(v.Name, _nameFont, new SizeF(10000, 1000), StringFormat.GenericTypographic).Width;
        DrawNameGrid(g, !PlayerHudMotionSettings.ReducedMotion && nameWidth > NameVisibleWidth);
        g.TranslateTransform(342.35f + NameOffset(PlayerHudMotionSettings.ReducedMotion ? 0 : _nameClock, nameWidth), 516.15f);
        g.DrawString(v.Name, _nameFont, dim, PointF.Empty, StringFormat.GenericTypographic);
        g.Restore(saved);

        var visibleCold = VisibleColdSkills(s);
        for (var i = 0; i < Math.Min(12, visibleCold.Length); i++)
        {
            var cold = visibleCold[i];
            DrawSlot(g, ColdSkillRect(i), cold.Icon, cold.Key,
                cold.Level > 0 ? cold.Level.ToString(CultureInfo.InvariantCulture) : "",
                cold.Cooldown, "coldSkill", i + 1, -1, cold.Blocked);
        }

        for (var i = 0; i < 12; i++)
        {
            var skill = s.Loadout.Skills[i];
            DrawSlot(g, SkillRect(i), skill.Equipped ? skill.Icon : "", skill.Hotkey,
                skill.Equipped ? skill.Level.ToString(CultureInfo.InvariantCulture) : "", s.Cooldowns[i + 1], "skill", i + 1);
            if (skill.Equipped)
            {
                var center = UnequipRect(i);
                using var shadow = new SolidBrush(Color.FromArgb(220, 0, 0, 0));
                g.FillEllipse(shadow, center);
                var b = PlayerHudArtData.Bounds("unequip");
                var destination = new RectangleF(center.X + 5 + b.X * 0.7f, center.Y + 5 + b.Y * 0.7f, b.Width * 0.7f, b.Height * 0.7f);
                var image = _art.Get("unequip", (int)Math.Ceiling(destination.Width * Scale), (int)Math.Ceiling(destination.Height * Scale));
                var brightness = _hover?.Kind == "skill" && _hover.Slot == i + 1 && _hover.Anchor == center ? 0.5f : -0.36f;
                using var colors = new ImageAttributes();
                colors.SetColorMatrix(new ColorMatrix { Matrix40 = brightness, Matrix41 = brightness, Matrix42 = brightness });
                g.DrawImage(image, new[] { destination.Location, new PointF(destination.Right, destination.Top), new PointF(destination.Left, destination.Bottom) },
                    new RectangleF(0, 0, image.Width, image.Height), GraphicsUnit.Pixel, colors);
            }
        }
        for (var i = 0; i < 4; i++)
        {
            var drug = s.Loadout.Drugs[i];
            DrawSlot(g, DrugRect(i), drug.Count > 0 ? drug.Icon : "", drug.Hotkey,
                drug.Count > 1 ? Number(drug.Count) : "", s.Cooldowns[i + 13], "drug", drug.Slot);
        }
        DrawSlot(g, SwitchRect, "", s.Loadout.SwitchKey, "", s.Cooldowns[17], "switch", 0, s.Loadout.Bank);
        PaintCombat(g, s.Combat);
        if (HasWeaponSlot(s.Combat))
        {
            DrawSlot(g, WeaponRect, "", s.Combat.WeaponKey, "", s.Cooldowns[0], "weapon", 0);
        }
        if (Controller.Message.Length > 0)
        {
            var msgAlpha = 1f;
            if (!Controller.WritePending && _messageAgeMs >= 0)
            {
                if (_messageAgeMs >= MessageTotalMs) msgAlpha = 0f;
                else if (_messageAgeMs > MessageHoldMs) msgAlpha = 1f - (float)(_messageAgeMs - MessageHoldMs) / MessageFadeMs;
            }
            if (msgAlpha > 0.01f)
            {
                using var msgBg = new SolidBrush(Color.FromArgb((int)Math.Round(215 * msgAlpha), 25, 30, 31));
                using var msgBorder = new Pen(Color.FromArgb((int)Math.Round(150 * msgAlpha), 210, 165, 95), 0.8f);
                using var msgText = new SolidBrush(Color.FromArgb((int)Math.Round(255 * msgAlpha), 239, 238, 220));
                g.FillRectangle(msgBg, 592, 506, 421, 23);
                g.DrawRectangle(msgBorder, 592.4f, 506.4f, 420.2f, 22.2f);
                g.DrawString(Controller.Message, _body, msgText, 596, 510);
            }
        }
    }

    private static GraphicsPath CreatePoiseCells()
    {
        var path=new GraphicsPath(FillMode.Winding);
        foreach(var cell in PlayerHudBarArtData.Cells) path.AddPolygon(cell);
        return path;
    }

    private void PaintDetailsEntry(Graphics g)
    {
        var saved=g.Save();g.SmoothingMode=SmoothingMode.AntiAlias;
        if (_hover?.Kind == "resources")
        {
            using var highlight=new SolidBrush(Color.White);
            g.FillPolygon(highlight,DetailsOutline);
        }
        var x=DetailsFace.Left+DetailsFace.Width/2;var y=DetailsFace.Top+DetailsFace.Height/2;
        using var ink=new SolidBrush(Color.FromArgb(15,19,20));
        using var ring=new Pen(ink,0.65f);
        g.DrawEllipse(ring,x-2.95f,y-2.95f,5.9f,5.9f);
        g.FillEllipse(ink,x-0.425f,y-1.8f,0.85f,0.85f);
        g.FillRectangle(ink,x-0.4f,y-0.4f,0.8f,2.1f);
        g.FillRectangle(ink,x-0.8f,y+1.3f,1.6f,0.5f);
        g.Restore(saved);
    }

    private void PaintPoise(Graphics g, PlayerHudVitals value)
    {
        var pulse = _poisePulseMs >= 0 && _poisePulseMs < PoisePulseDurationMs
            ? 1f - (float)_poisePulseMs / PoisePulseDurationMs
            : 0f;
        PlayerHudPoisePainter.Paint(g, value, _poiseCells, pulse, _poisePulseIsRisk);
    }

    private static bool HasWeaponSlot(PlayerHudCombat combat) => combat.WeaponVisible && combat.Mode is not ("" or "双枪" or "长枪副武器");
    private void DrawNameGrid(Graphics g, bool animate = true)
    {
        var offset = animate ? GridOffsets[(_nameClock * 3 / 100) % 11] : 0f;
        var saved = g.Save();
        g.SetClip(new RectangleF(341, 514.8f + offset, 138, 16 - offset), CombineMode.Intersect);
        DrawArt(g, "name-grid", 407.45f, 527.2f + offset, 1.3478241f, 1);
        g.Restore(saved);
        if (offset <= 0) return;
        saved = g.Save();
        g.SetClip(new RectangleF(341, 514.8f, 138, offset), CombineMode.Intersect);
        DrawArt(g, "name-grid", 407.45f, 527.2f + offset - 2.9f, 1.3478241f, 1);
        g.Restore(saved);
    }
    private void DrawSizedArt(Graphics g, string id, RectangleF rectangle)
    {
        var image = _art.Get(id, (int)Math.Ceiling(rectangle.Width * Scale), (int)Math.Ceiling(rectangle.Height * Scale));
        g.DrawImage(image, rectangle);
    }
    private void DrawArt(Graphics g, string id, float x, float y, float scaleX = 1, float scaleY = 1)
    {
        var b = PlayerHudArtData.Bounds(id);
        DrawSizedArt(g, id, new RectangleF(x + b.X * scaleX, y + b.Y * scaleY, b.Width * scaleX, b.Height * scaleY));
    }
    private void DrawAmmo(Graphics g, string raw, Brush ink, RectangleF bounds, bool centered)
    {
        using var format=new StringFormat(StringFormat.GenericTypographic) { Alignment=centered?StringAlignment.Center:StringAlignment.Near,
            FormatFlags=StringFormatFlags.NoWrap, Trimming=StringTrimming.EllipsisCharacter };
        float Measure(string text)=>g.MeasureString(text,_nameFont,new SizeF(10000,1000),StringFormat.GenericTypographic).Width;
        var text=PlayerHudNumberFormat.FitText(raw,Measure,bounds.Width-2);
        var saved=g.Save();g.SetClip(bounds,CombineMode.Intersect);
        g.DrawString(text,_nameFont,ink,bounds,format);g.Restore(saved);
    }

    private void DrawRawText(Graphics g, string text, Brush ink, RectangleF bounds)
    {
        using var format = new StringFormat(StringFormat.GenericTypographic)
        {
            Alignment = StringAlignment.Near,
            FormatFlags = StringFormatFlags.NoWrap,
            Trimming = StringTrimming.None
        };
        var saved = g.Save();
        g.SetClip(bounds, CombineMode.Intersect);
        g.DrawString(text, _nameFont, ink, bounds, format);
        g.Restore(saved);
    }

    private void PaintCombat(Graphics g, PlayerHudCombat combat)
    {
        var mode = Array.IndexOf(new[] { "手枪", "手枪2", "长枪", "兵器", "手雷", "空手", "双枪", "长枪副武器" }, combat.Mode);
        if (mode < 0) return;
        const float x = 506.95f, y = 522.45f;
        var hasWeaponSlot = HasWeaponSlot(combat);

        if (mode is >= 3 and <= 5)
        {
            DrawArt(g, "mode-" + mode, x, y);
        }
        if ((mode is >= 3 and <= 5) || (mode < 3 && hasWeaponSlot))
        {
            DrawArt(g, "weapon-panel", x, y);
            using var emptyMark = new SolidBrush(Color.FromArgb(229, 229, 229));
            g.DrawString("+", _slotMark, emptyMark, x + 62.3f, y + 15.3f);
        }

        using var text = new SolidBrush(Color.FromArgb(204, 204, 204));
        float Measure(string s) => g.MeasureString(s, _nameFont, new SizeF(10000, 1000), StringFormat.GenericTypographic).Width;
        if (mode < 3)
        {
            var cardLeft = PlayerHudAmmoPainter.CardLeft;
            var cardRight = hasWeaponSlot ? PlayerHudAmmoPainter.CardRightCompact : PlayerHudAmmoPainter.CardRightFull;
            var cardWidth = cardRight - cardLeft;
            var contentLeft = cardLeft + PlayerHudAmmoPainter.ContentPadX;
            var contentRight = cardRight - PlayerHudAmmoPainter.ContentPadX;
            var barWidth = contentRight - contentLeft;
            var numberLeft = contentLeft + PlayerHudAmmoPainter.IconWidth + PlayerHudAmmoPainter.IconToNumberGap;
            var availableNumWidth = Math.Max(20f, contentRight - numberLeft);

            var slot = AmmoSlotIndex(combat.Mode, 0);
            var observedCap = slot >= 0 ? _observedAmmoCapacity[slot] : 0;
            var detail = combat.AmmoDetails?[0];
            var ammoColor = AmmoColor(detail, combat.Ammo[0], observedCap);
            var reserveColor = ReserveAmmoColor(combat.Ammo[1]);
            using var ammoInk = new SolidBrush(ammoColor);
            using var reserveInk = new SolidBrush(reserveColor);

            // Row 0: Primary Chamber Card (Icon + Loaded Count + Magazine Capacity Bar)
            var row0Top = PlayerHudAmmoPainter.Row0Top;
            PlayerHudAmmoPainter.PaintTacticalCard(g, new RectangleF(cardLeft, row0Top, cardWidth, PlayerHudAmmoPainter.CardHeight), Scale, ammoColor);
            PlayerHudAmmoPainter.PaintBulletIcon(g, contentLeft, row0Top + PlayerHudAmmoPainter.IconOffsetY, Scale, ammoColor);
            var capAnchor = Math.Max(detail?.Capacity ?? 0, observedCap);
            var primary = PlayerHudAmmoPainter.FormatPrimaryLoaded(AmmoValue(combat.Ammo[0]), Measure, availableNumWidth, capAnchor);
            DrawRawText(g, primary.Text, ammoInk, new RectangleF(numberLeft, row0Top + PlayerHudAmmoPainter.TextOffsetY, availableNumWidth + 2f, 14f));
            PlayerHudAmmoPainter.PaintMagazineBar(g, new RectangleF(contentLeft, row0Top + PlayerHudAmmoPainter.BarOffsetY, barWidth, PlayerHudAmmoPainter.BarHeight), Scale, detail, combat.Ammo[0], observedCap);

            // Row 1: Reserve Magazine Card (Vertically centered Icon + Reserve Count; no 10-slot bar to avoid confusion with magazine capacity bar)
            var row1Top = PlayerHudAmmoPainter.Row1Top;
            PlayerHudAmmoPainter.PaintTacticalCard(g, new RectangleF(cardLeft, row1Top, cardWidth, PlayerHudAmmoPainter.CardHeight), Scale, reserveColor);
            PlayerHudAmmoPainter.PaintMagazineIcon(g, contentLeft, row1Top + PlayerHudAmmoPainter.ReserveRowIconOffsetY, Scale, reserveColor);
            var reserve = PlayerHudAmmoPainter.FormatReserveWithYield(AmmoValue(combat.Ammo[1]), Measure, availableNumWidth);
            DrawRawText(g, reserve, reserveInk, new RectangleF(numberLeft, row1Top + PlayerHudAmmoPainter.ReserveRowTextOffsetY, availableNumWidth + 2f, 14f));
        }
        else if (mode >= 6)
        {
            var cardLeft = PlayerHudAmmoPainter.CardLeft;
            var cardRight = PlayerHudAmmoPainter.CardRightFull;
            var cardWidth = cardRight - cardLeft;
            var contentLeft = cardLeft + PlayerHudAmmoPainter.ContentPadX;
            var contentRight = cardRight - PlayerHudAmmoPainter.ContentPadX;
            var barWidth = contentRight - contentLeft;
            var primaryNumX = contentLeft + PlayerHudAmmoPainter.IconWidth + PlayerHudAmmoPainter.IconToNumberGap;

            for (var row = 0; row < 2; row++)
            {
                var cardTop = PlayerHudAmmoPainter.Row0Top + row * PlayerHudAmmoPainter.RowStep;
                var iconY = cardTop + PlayerHudAmmoPainter.IconOffsetY;
                var textY = cardTop + PlayerHudAmmoPainter.TextOffsetY;
                var loadedText = combat.Ammo[row * 2];
                var magText = combat.Ammo[row * 2 + 1];
                var slot = AmmoSlotIndex(combat.Mode, row);
                var observedCap = slot >= 0 ? _observedAmmoCapacity[slot] : 0;
                var detail = combat.AmmoDetails?[row];
                var ammoColor = AmmoColor(detail, loadedText, observedCap);
                var reserveColor = ReserveAmmoColor(magText);
                using var ammoInk = new SolidBrush(ammoColor);
                using var reserveInk = new SolidBrush(reserveColor);

                PlayerHudAmmoPainter.PaintTacticalCard(g, new RectangleF(cardLeft, cardTop, cardWidth, PlayerHudAmmoPainter.CardHeight), Scale, ammoColor);
                PlayerHudAmmoPainter.PaintBulletIcon(g, contentLeft, iconY, Scale, ammoColor);

                var capAnchor = Math.Max(detail?.Capacity ?? 0, observedCap);
                var primary = PlayerHudAmmoPainter.FormatPrimaryLoaded(AmmoValue(loadedText), Measure, 36f, capAnchor);
                DrawRawText(g, primary.Text, ammoInk, new RectangleF(primaryNumX, textY, primary.ReservedWidth + 2f, 14f));

                var idealReserve = PlayerHudAmmoPainter.FormatReserveWithYield(AmmoValue(magText), Measure, 34f);
                var magIconX = PlayerHudAmmoPainter.ResolveDualMagazineIconX(
                    primaryNumX, contentRight, primary.ReservedWidth, Measure(idealReserve), PlayerHudAmmoPainter.DefaultDualSplitX);
                var dividerX = magIconX - PlayerHudAmmoPainter.DividerToIconGap;
                PlayerHudAmmoPainter.PaintZoneDivider(g, dividerX, iconY + 1.0f, PlayerHudAmmoPainter.IconHeight - 2.0f, Scale);
                PlayerHudAmmoPainter.PaintMagazineIcon(g, magIconX, iconY, Scale, reserveColor);

                var reserveNumX = magIconX + PlayerHudAmmoPainter.IconWidth + PlayerHudAmmoPainter.IconToNumberGap;
                var remainingWidth = Math.Max(14f, contentRight - reserveNumX);
                var reserve = PlayerHudAmmoPainter.FormatReserveWithYield(AmmoValue(magText), Measure, remainingWidth);
                DrawRawText(g, reserve, reserveInk, new RectangleF(reserveNumX, textY, remainingWidth + 2f, 14f));

                PlayerHudAmmoPainter.PaintMagazineBar(g, new RectangleF(contentLeft, cardTop + PlayerHudAmmoPainter.BarOffsetY, barWidth, PlayerHudAmmoPainter.BarHeight), Scale, detail, loadedText, observedCap);
            }
        }
        else if (mode == 4)
        {
            using var grenadeInk = new SolidBrush(AmmoColor(null, combat.Ammo[1], _observedAmmoCapacity[4]));
            DrawAmmo(g,AmmoValue(combat.Ammo[1]),grenadeInk,new RectangleF(x+1.2f,y+17.65f,46,14),false);
        }
        if (mode is >= 3 and <= 5)
        {
            using var tiny = NativeHudFonts.CreateRoleFont("native.player-info.body", 4, FontStyle.Regular, GraphicsUnit.Pixel);
            g.DrawString("+++++++++++++++++", tiny, text, x - 9.25f + (mode == 4 ? 9.2f : -1.5f), y + 5.6f);
        }
    }

    private static int AmmoSlotIndex(string mode, int row) => (mode, row) switch
    {
        ("手枪", 0) or ("双枪", 0) => 0,
        ("手枪2", 0) or ("双枪", 1) => 1,
        ("长枪", 0) or ("长枪副武器", 0) => 2,
        ("长枪副武器", 1) => 3,
        ("手雷", _) => 4,
        _ => -1
    };

    private void ObserveCombatAmmo(PlayerHudCombat combat)
    {
        if (combat.Mode == "手雷")
        {
            if (TryParseAmmoCount(combat.Ammo[1], out var grenades) && grenades > _observedAmmoCapacity[4])
                _observedAmmoCapacity[4] = grenades;
            return;
        }
        var rows = combat.Mode is "双枪" or "长枪副武器" ? 2 : (combat.Mode is "手枪" or "手枪2" or "长枪" ? 1 : 0);
        for (var row = 0; row < rows; row++)
        {
            var slot = AmmoSlotIndex(combat.Mode, row);
            if (slot < 0) continue;
            if (combat.AmmoDetails?[row] is { Capacity: > 0 } detail)
                _observedAmmoCapacity[slot] = Math.Max(_observedAmmoCapacity[slot], detail.Capacity);
            if (TryParseAmmoCount(combat.Ammo[row * 2], out var loaded) && loaded > _observedAmmoCapacity[slot])
                _observedAmmoCapacity[slot] = loaded;
        }
    }

    private static bool TryParseAmmoCount(string raw, out int count) =>
        PlayerHudAmmoPainter.TryParseAmmoCount(raw, out count);

    internal static Color AmmoColor(
        PlayerHudAmmoDetail? detail,
        string loadedText = "",
        int observedCapacity = 0) =>
        PlayerHudAmmoPainter.AmmoColor(detail, loadedText, observedCapacity);

    internal static Color ReserveAmmoColor(string magText) =>
        PlayerHudAmmoPainter.ReserveAmmoColor(magText);

    private void DrawBankDots(Graphics g, int bank)
    {
        DrawArt(g, "bank-" + bank, 321.9f, 548.35f);
    }
    private void DrawSlot(Graphics g, RectangleF r, string icon, string key, string badge, PlayerHudCooldown cooldown, string kind, int slot, int bank = -1, bool blockedOverride = false)
    {
        if (kind != "weapon") DrawArt(g, "slot", r.X + 13, r.Y + 13.1f);
        if (kind is "skill" or "coldSkill" or "drug")
        {
            using var authoredPlus = new SolidBrush(Color.FromArgb(229, 229, 229));
            g.DrawString("+", _slotMark, authoredPlus, r.X + 8.7f, r.Y + 4.3f);
        }
        var pixels = (int)Math.Ceiling(24 * Scale);
        var bitmap = kind == "weapon" && Snapshot is { } snapshot
            ? _icons.GetWeapon(snapshot.Combat.WeaponIconKey, snapshot.Combat.WeaponItemIconKey, pixels)
            : _icons.Get(icon, pixels);
        if (bitmap != null && kind != "weapon") g.DrawImage(bitmap, r.X + 1, r.Y + 1, r.Width - 2, r.Height - 2);
        if (kind != "weapon") DrawArt(g, "slot-detail", r.X + 13, r.Y + 13.1f);
        // All authored foreground belongs below cooldown feedback, including non-bitmap controls.
        if (kind == "switch") DrawBankDots(g, bank);
        else if (kind == "weapon")
        {
            DrawArt(g, "weapon", 573.55f, 547.65f);
            if (bitmap != null)
            {
                // Keep the authored frame/title, replacing only the inner symbol.
                using var backplate = new SolidBrush(Color.FromArgb(24, 28, 30));
                g.FillRectangle(backplate, r.X + 1, r.Y + 1, r.Width - 2, r.Height - 2);
                g.DrawImage(bitmap, r.X + 1, r.Y + 1, r.Width - 2, r.Height - 2);
            }
        }
        if (kind == "drug" && cooldown.Ready && _hover?.Kind == kind && _hover.Slot == slot)
            DrawArt(g, "drug-hover", r.X + 13, r.Y + 13);
        if (!cooldown.Ready)
        {
            var shadeHeight = (float)((r.Height - 2) * (1 - cooldown.Fraction));
            using var shade = new SolidBrush(Color.FromArgb(165, 5, 10, 15));
            g.FillRectangle(shade, r.X + 1, r.Y + 1, r.Width - 2, shadeHeight);
            if (kind is "skill" or "coldSkill" or "drug" && shadeHeight > 1.2f && shadeHeight < r.Height - 3.2f)
            {
                using var horizon = new Pen(Color.FromArgb(170, 241, 201, 112), 0.9f);
                var hy = r.Y + 1 + shadeHeight;
                g.DrawLine(horizon, r.X + 1.5f, hy, r.Right - 1.5f, hy);
            }
        }
        var cooldownIndex = kind == "weapon" ? 0 : kind == "skill" ? slot : kind == "switch" ? 17 : kind == "coldSkill" ? 17 + slot : 13 + slot % 4;
        var flashFrame = _readyFlash[cooldownIndex] < 0 ? 7 : _readyFlash[cooldownIndex] * 3 / 100;
        var resourceHint = kind == "coldSkill"
            ? new PlayerHudResourceHint(blockedOverride ? "blocked" : "ready", blockedOverride ? "mp" : "")
            : PlayerHudResourceHintPainter.Hint(Snapshot, kind, slot);
        if (resourceHint.State != "blocked" && cooldown.Ready && flashFrame < 7 && ReadyAlpha[flashFrame] > 0)
        {
            var alpha = ReadyAlpha[flashFrame];
            using var flash = new SolidBrush(Color.FromArgb((int)(160 * alpha), 220, 248, 255));
            g.FillRectangle(flash, r.X + 1f, r.Y + 1f, r.Width - 2f, r.Height - 2f);
            using var rim = new Pen(Color.FromArgb((int)(235 * alpha), 255, 255, 255), 1.2f);
            g.DrawRectangle(rim, r.X + 1.1f, r.Y + 1.1f, r.Width - 2.2f, r.Height - 2.2f);
        }
        if (kind is "drug" or "switch" && _bankSwitchPulseMs >= 0 && _bankSwitchPulseMs < BankSwitchPulseDurationMs)
        {
            var pulseAlpha = 1f - (float)_bankSwitchPulseMs / BankSwitchPulseDurationMs;
            using var bankHighlight = new Pen(Color.FromArgb((int)(175 * pulseAlpha), 155, 224, 233), 1f);
            g.DrawRectangle(bankHighlight, r.X + 1.2f, r.Y + 1.2f, r.Width - 2.4f, r.Height - 2.4f);
        }
        PlayerHudResourceHintPainter.PaintSlot(g, r, resourceHint, cooldown.Ready && Snapshot?.Vitals.Paused != true,
            _resourceHintClock, kind == "coldSkill" ? 0f : _denial.SlotAlpha(kind, kind == "drug" ? slot % 4 : slot));
        if (!cooldown.Ready && kind is "switch" or "weapon")
        {
            // Only these two slots own a progress strip; it stays above the seal like the countdown text.
            using var track = new SolidBrush(Color.FromArgb(240, 15, 20, 25));
            using var progress = new SolidBrush(Color.FromArgb(241, 201, 112));
            var strip = CooldownTrackRect(r);
            g.FillRectangle(track, strip);
            g.FillRectangle(progress, strip.X, strip.Y, (float)(strip.Width * cooldown.Fraction), strip.Height);
        }
        using var foreground = new SolidBrush(Color.FromArgb(248, 243, 222));
        using var shadow = new SolidBrush(Color.FromArgb(235, 15, 18, 19));
        if (badge.Length > 0)
        {
            if (resourceHint.State == "blocked" && badge.Length > 2)
            {
                // Long item counts use one fixed wider band; skill levels keep the diagonal middle visible.
                using var badgeBacking = new SolidBrush(Color.FromArgb(230, 8, 11, 12));
                g.FillRectangle(badgeBacking, r.X + 2, r.Y, 22, 10);
            }
            g.DrawString(badge, _small, shadow, r.X + 4, r.Y + 1);
            g.DrawString(badge, _small, foreground, r.X + 3, r.Y);
        }
        DrawHotkey(g, r, key, cooldown, cooldownIndex);
        if (!cooldown.Ready)
            DrawCooldownCountdown(g, r, cooldown, cooldownIndex);
    }
    private static string NormalizeKeyLabel(string key) =>
        key.Equals("Spacebar", StringComparison.OrdinalIgnoreCase) || key.Equals("Space", StringComparison.OrdinalIgnoreCase) || key == " "
            ? "空格"
            : key;
    private void DrawCooldownCountdown(Graphics g, RectangleF slot, PlayerHudCooldown cooldown, int index)
    {
        var label = PlayerHudCooldownText.Format(cooldown);
        if (label.Length == 0) return;
        var cached = _countdownCaptions[index];
        if (cached?.Text != label)
        {
            cached?.Path.Dispose(); _countdownCaptions[index] = null;
            var path = new GraphicsPath();
            path.AddString(label, _hotkeyFont.FontFamily, (int)FontStyle.Bold, 9.5f, PointF.Empty, StringFormat.GenericTypographic);
            var bounds = path.GetBounds();
            if (bounds.Width <= 0 || bounds.Height <= 0) { path.Dispose(); return; }
            var scale = Math.Min(1f, Math.Min(22f / bounds.Width, 9.5f / bounds.Height));
            using var fit = new Matrix(scale, 0, 0, scale, -bounds.Left * scale, -bounds.Top * scale);
            path.Transform(fit); cached = new Caption(label, path); _countdownCaptions[index] = cached;
        }
        var r = CooldownTextRect(slot); var glyphs = cached!.Path.GetBounds(); var saved = g.Save();
        g.SetClip(r, CombineMode.Intersect); g.SmoothingMode = SmoothingMode.AntiAlias;
        using var backing = new SolidBrush(Color.FromArgb(192, 6, 9, 10));
        using var ink = new SolidBrush(Color.FromArgb(241, 201, 112));
        var left = r.Left + (r.Width - glyphs.Width) / 2f;
        var top = r.Top + (r.Height - glyphs.Height) / 2f;
        g.FillRectangle(backing, Math.Max(r.Left, left - 1.2f), Math.Max(r.Top, top - 0.8f), Math.Min(r.Width, glyphs.Width + 2.4f), Math.Min(r.Height, glyphs.Height + 1.6f));
        g.TranslateTransform(left, top);
        g.FillPath(ink, cached.Path); g.Restore(saved);
    }
    private void DrawHotkey(Graphics g, RectangleF slot, string key, PlayerHudCooldown cooldown, int index)
    {
        var label = NormalizeKeyLabel(key);
        if(label.Length==0)return;
        var cached=_captions[index];
        if(cached?.Text!=label)
        {
            cached?.Path.Dispose();_captions[index]=null;
            var path=new GraphicsPath();
            path.AddString(label,_hotkeyFont.FontFamily,(int)FontStyle.Bold,9,PointF.Empty,StringFormat.GenericTypographic);
            var bounds=path.GetBounds();
            if(bounds.Width<=0 || bounds.Height<=0) { path.Dispose();return; }
            var scale=Math.Min(1,Math.Min(22/bounds.Width,7.5f/bounds.Height));
            using var fit=new Matrix(scale,0,0,scale,-bounds.Left*scale,-bounds.Top*scale);
            path.Transform(fit);cached=new Caption(label,path);_captions[index]=cached;
        }
        var r=HotkeyRect(slot);var glyphs=cached!.Path.GetBounds();var saved=g.Save();
        g.SetClip(r,CombineMode.Intersect);g.SmoothingMode=SmoothingMode.AntiAlias;
        using var backing=new SolidBrush(Color.FromArgb(218,8,11,12));
        using var ink=new SolidBrush(cooldown.Ready?Color.FromArgb(238,239,237):Color.FromArgb(196,204,208));
        var left=r.Left+(r.Width-glyphs.Width)/2;
        g.FillRectangle(backing,left-1,r.Top,glyphs.Width+2,r.Height);
        g.TranslateTransform(left,r.Top+(r.Height-glyphs.Height)/2);
        g.FillPath(ink,cached.Path);g.Restore(saved);
    }
    private static string Number(double value) => Math.Floor(value).ToString("0", CultureInfo.InvariantCulture);
    private static string Ammo(string a, string b) => (a.Length == 0 ? "—" : a) + " / " + (b.Length == 0 ? "—" : b);
    private static string AmmoValue(string value) => value.Length == 0 ? "—" : value;

    private PlayerHudTarget? Hit(Point screen)
    {
        if (!Visible || !Controller.CanInteract || Scale <= 0 || Snapshot is not { } s) return null;
        var point = Logical(screen);
        PlayerHudTarget Target(string kind, int slot, string key, long revision, RectangleF rect) =>
            new(kind, slot, key, s.Epoch, revision, s.Loadout.Bank, rect, Controller.Generation, s.Vitals.Paused);
        if (DetailsRect.Contains(point)) return Target("resources", 0, "", 0, DetailsRect);
        if (SwitchRect.Contains(point)) return Target("switch", 0, "", s.Loadout.DrugRevision, SwitchRect);
        var visibleCold = VisibleColdSkills(s);
        for (var i = 0; i < Math.Min(12, visibleCold.Length); i++)
        {
            var rect = ColdSkillRect(i);
            if (rect.Contains(point)) return Target("coldSkill", i + 1, visibleCold[i].Name, s.Loadout.Revision, rect);
        }
        for (var i = 0; i < 12; i++)
            if (s.Loadout.Skills[i].Equipped && UnequipRect(i).Contains(point)) return Target("skill", i + 1, s.Loadout.Skills[i].Key, s.Loadout.Revision, UnequipRect(i));
        for (var i = 0; i < 12; i++)
            if (s.Loadout.Skills[i].Equipped && SkillRect(i).Contains(point)) return Target("skill", i + 1, s.Loadout.Skills[i].Key, s.Loadout.Revision, SkillRect(i));
        for (var i = 0; i < 4; i++)
            if (s.Loadout.Drugs[i].Count > 0 && DrugRect(i).Contains(point)) return Target("drug", s.Loadout.Drugs[i].Slot, s.Loadout.Drugs[i].Name, s.Loadout.DrugRevision, DrugRect(i));
        if (HasWeaponSlot(s.Combat) && WeaponRect.Contains(point)) return Target("weapon", 0, s.Combat.WeaponName, 0, WeaponRect);
        if (s.Combat.AmmoDetails is { } details)
        {
            var dual = s.Combat.Mode is "双枪" or "长枪副武器";
            for (var i=0;i<(dual?2:1);i++)
            {
                var right = (dual || !HasWeaponSlot(s.Combat)) ? PlayerHudAmmoPainter.CardRightFull : PlayerHudAmmoPainter.CardRightCompact; var area = dual ? new RectangleF(484f, 516f + i * 25f, right - 484f, 22f) : new RectangleF(484f, 516f, right - 484f, 47f);
                if (details[i] != null && area.Contains(point)) return Target("ammo",i,"",0,area);
            }
        }
        return null;
    }
    public override bool TryHitTest(Point screenPt) => Hit(screenPt) != null;
    internal PlayerHudTarget? CapturePointerTarget(Point screenPt) => Hit(screenPt);
    public override void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
    {
        var hit = Hit(new Point(e.X, e.Y));
        if (kind is MouseEventKind.Cancel or MouseEventKind.Leave) { Cancel(); return; }
        if (kind is MouseEventKind.Move or MouseEventKind.Enter)
        {
            if (hit != _hover)
            {
                _hover = hit; Controller.HideTooltip();
                if (hit != null) Controller.ShowTooltip(hit);
                Repaint();
            }
        }
        if (e.Button != MouseButtons.Left) return;
        if (kind == MouseEventKind.Down) { _down = hit; _upMatches = false; }
        if (kind == MouseEventKind.Up) _upMatches = _down != null && _down == hit;
        if (kind == MouseEventKind.Click)
        {
            if (_upMatches && _down != null && _down == hit &&
                (_down.Kind != "skill" || _down.Anchor == UnequipRect(_down.Slot - 1))) Controller.Act(_down);
            _down = null; _upMatches = false; Repaint();
        }
    }
    private void Cancel() { _down = null; _upMatches = false; _hover = null; Controller.HideTooltip(); Repaint(); }
    public override void SetHostSuppressed(bool suppressed) { if (suppressed) { _denial.Clear(); Cancel(); } base.SetHostSuppressed(suppressed); }
    public override void Dispose()
    {
        foreach(var caption in _captions)caption?.Path.Dispose();Array.Clear(_captions);
        foreach(var caption in _countdownCaptions)caption?.Path.Dispose();Array.Clear(_countdownCaptions);
        Cancel(); Controller.StatusChanged -= OnStatusChanged; _icons.Dispose(); _art.Dispose(); _numbers.Dispose(); _poiseCells.Dispose(); _body.Dispose(); _small.Dispose(); _nameFont.Dispose(); _hotkeyFont.Dispose(); _poiseLabel.Dispose(); _slotMark.Dispose(); base.Dispose();
    }
}

internal sealed class PlayerHudBuffWidget : PlayerHudWidgetBase
{
    protected override bool HasContent => Snapshot?.Buffs.Length>0;
    protected override RectangleF LogicalBounds => new(6,0,6+Math.Min(32,Snapshot?.Buffs.Length??0)*28,
        Math.Max(1,(float)Math.Ceiling((Snapshot?.Buffs.Length??0)/32d))*NativeHudTheme.TopBarHeightBase);
    internal PlayerHudBuffWidget(Control anchor, PlayerHudController controller) : base(anchor, controller) { }
    protected override void PaintLogical(Graphics g)
    {
        var rows = Snapshot!.Buffs;
        // Use the top HUD's device-pixel frame rules, not scaled hairline art.
        var saved=g.Save();g.ScaleTransform(1/Scale,1/Scale);
        Rectangle Pixels(float x,float y,float w,float h)=>Rectangle.FromLTRB(
            (int)Math.Round(x*Scale),(int)Math.Round(y*Scale),(int)Math.Round((x+w)*Scale),(int)Math.Round((y+h)*Scale));
        var bounds=LogicalBounds;
        NativeHudTheme.DrawPanel(g,Pixels(bounds.X,bounds.Y,bounds.Width,bounds.Height),Scale,NativeHudTheme.PanelFill,Color.Empty,false);
        for (var i = 0; i < rows.Length; i++)
        {
            var x=9+(i%32)*28;var y=3+(i/32)*NativeHudTheme.TopBarHeightBase;
            var slot=Pixels(x,y,26,26);
            NativeHudTheme.DrawButton(g,slot,Scale,false,false,false,false);
            // No name/icon/polarity metadata exists yet. Keep a neutral placeholder.
            using var mark=new SolidBrush(NativeHudTheme.TextDisabled);
            var center=Pixels(x+10,y+8,6,6);g.FillRectangle(mark,center);
            if (rows[i].Timed)
            {
                var fraction = rows[i].Total > 0 ? Math.Clamp(rows[i].Remaining / rows[i].Total, 0, 1) : 0;
                // Preserve the existing 26-step timer. Untimed does not imply permanent.
                fraction = Math.Floor(fraction * 25) / 25;
                var track=Pixels(x+3,y+21,20,2);
                using var background=new SolidBrush(NativeHudTheme.FrameMuted);
                using var progress=new SolidBrush(NativeHudTheme.TextSecondary);
                g.FillRectangle(background,track);
                g.FillRectangle(progress,track.X,track.Y,(float)(track.Width*fraction),track.Height);
            }
        }
        g.Restore(saved);
    }
    public override bool TryHitTest(Point screenPt) => false;
    public override void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }
}
