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
    private readonly PlayerHudIconCache _icons;
    private readonly PlayerHudArtCache _art = new();
    private readonly PlayerHudTextCache _numbers = new();
    private readonly GraphicsPath _poiseCells = CreatePoiseCells();
    private sealed record Caption(string Text,GraphicsPath Path);
    // Countdown strings change often; retain only the current caption for each lane.
    private readonly Caption?[] _captions = new Caption?[18];
    private readonly Font _body = NativeHudFonts.CreateRoleFont("native.player-info.body", 10, FontStyle.Regular, GraphicsUnit.Pixel);
    private readonly Font _small = NativeHudFonts.CreateRoleFont("native.player-info.body", 9, FontStyle.Regular, GraphicsUnit.Pixel);
    private readonly Font _nameFont = NativeHudFonts.CreateRoleFont("native.player-info.body", 11, FontStyle.Regular, GraphicsUnit.Pixel);
    private readonly Font _hotkeyFont = NativeHudFonts.CreateRoleFont("native.player-info.body", 9, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _poiseLabel = NativeHudFonts.CreateRoleFont("native.hud.body", 8, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _slotMark = NativeHudFonts.CreateRoleFont("native.player-info.body", 12, FontStyle.Regular, GraphicsUnit.Pixel);
    private PlayerHudTarget? _hover, _down;
    private bool _upMatches;
    private int _nameClock;
    private readonly int[] _readyFlash = new int[18];
    private PlayerHudCooldown[]? _lastCooldowns;
    private static readonly float[] ReadyAlpha = [1, 0.828125f, 0.671875f, 0.5f, 0.328125f, 0.171875f, 0, 0];
    private static readonly float[] GridOffsets = [0, 0.25f, 0.5f, 0.75f, 1.05f, 1.3f, 1.55f, 1.8f, 2.1f, 2.35f, 2.6f];
    private long _epoch;
    internal static RectangleF SkillRect(int index) => new(602.25f + index * 35.05f, 536.5f, 26, 26);
    internal static RectangleF DrugRect(int lane) => new(343.8f + lane * 34.9f, 535.35f, 26, 26);
    internal static RectangleF UnequipRect(int index) => new(623.4f + index * 35f, 532.3f, 10, 10);
    internal static readonly RectangleF SwitchRect = new(308.9f, 535.35f, 26, 26);
    // The first authored header stripe doubles as the read-only details entry.
    internal static readonly RectangleF DetailsFace = new(947.3f, 518.05f, 19.65f, 7.7f);
    internal static readonly PointF[] DetailsOutline = [new(947.3f,518.05f),new(957.7f,518.05f),new(966.95f,525.75f),new(956.5f,525.75f)];
    internal static readonly RectangleF DetailsRect = new(945.3f, 515.05f, 23.65f, 13.7f);
    internal static RectangleF HotkeyRect(RectangleF slot) => new(slot.X+1,slot.Bottom-9.5f,slot.Width-2,9);
    internal static RectangleF CooldownTrackRect(RectangleF slot) => new(slot.X+2,slot.Bottom-12,slot.Width-4,2);
    internal static readonly RectangleF WeaponRect = new(560.55f, 534.65f, 26, 26);
    protected override RectangleF LogicalBounds => new(0, 504, 1024, 72);
    public override bool WantsAnimationTick => Visible && Snapshot is { } s &&
        (s.Vitals.Decorations || Array.Exists(_readyFlash, time => time >= 0 && time < 234));

    internal PlayerHudBottomWidget(Control anchor, PlayerHudController controller, string iconsRoot) : base(anchor, controller)
    {
        _icons = new PlayerHudIconCache(iconsRoot);
        Array.Fill(_readyFlash, -1);
        controller.StatusChanged += Repaint;
    }

    protected override void OnStateChanged()
    {
        if (Snapshot?.Epoch != _epoch) { _epoch = Snapshot?.Epoch ?? 0; _nameClock = 0; _lastCooldowns = null; Array.Fill(_readyFlash, -1); Cancel(); }
        if (Snapshot is { } current)
        {
            if (_lastCooldowns != null)
                for (var i = 0; i < 18; i++) if (!_lastCooldowns[i].Ready && current.Cooldowns[i].Ready) _readyFlash[i] = 0;
            _lastCooldowns = current.Cooldowns;
        }
        if (_hover != null && !StillCurrent(_hover)) { Controller.HideTooltip(); _hover = null; }
        if (_down != null && !StillCurrent(_down)) { _down = null; _upMatches = false; }
        base.OnStateChanged();
    }
    private bool StillCurrent(PlayerHudTarget t)
    {
        var s = Snapshot; if (s == null || s.Epoch != t.Epoch || t.ConnectionGeneration != Controller.Generation || t.Paused != s.Vitals.Paused) return false;
        return t.Kind switch { "skill" => t.Revision == s.Loadout.Revision,
            "drug" or "switch" => t.Revision == s.Loadout.DrugRevision && t.Bank == s.Loadout.Bank, _ => true };
    }
    public override void Tick(int deltaMs)
    {
        if (!Visible || Snapshot == null) return;
        var oldFrame = _nameClock * 3 / 100;
        if (Snapshot.Vitals.Decorations) _nameClock = (_nameClock + deltaMs) % 110000;
        var changed = _nameClock * 3 / 100 != oldFrame;
        for (var i = 0; i < 18; i++)
        {
            if (_readyFlash[i] < 0 || _readyFlash[i] >= 234) continue;
            var old = _readyFlash[i] * 3 / 100;
            _readyFlash[i] += deltaMs;
            changed |= _readyFlash[i] * 3 / 100 != old;
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

    protected override void PaintLogical(Graphics g)
    {
        var s = Snapshot!; var v = s.Vitals;
        var muted = Color.FromArgb(204, 204, 204);
        using var text = new SolidBrush(Color.FromArgb(239, 238, 220));
        using var dim = new SolidBrush(muted);
        using var poise = new SolidBrush(PlayerHudResourceStyle.Poise);
        using var background = new SolidBrush(Color.FromArgb(200, 25, 30, 31));
        DrawArt(g, "bottom-panel", 49.7f, 568.45f, 0.8472137451f, 0.8472137451f);
        using (var raisedPanel=new LinearGradientBrush(new RectangleF(90,504,190,32),
            Color.FromArgb(44,47,48),Color.FromArgb(17,20,21),LinearGradientMode.Vertical))
            g.FillPolygon(raisedPanel,[new PointF(90,504),new PointF(271,504),new PointF(280,512),new PointF(280,537),new PointF(90,537)]);
        var ornaments = g.Save();
        g.SetClip(new RectangleF(86,535,194,38),CombineMode.Exclude);
        DrawArt(g, "bottom-ornaments", 49.7f, 568.45f, 0.8472137451f, 0.8472137451f);
        g.Restore(ornaments);
        var poiseState = PlayerHudResourceStyle.PoiseStateLabel(v.PoiseDetail);
        var poiseBar = PlayerHudResourceLayout.PoiseBar;
        if (poiseState.Length > 0)
            g.DrawString(poiseState,_poiseLabel,poise,poiseBar.Right+3,poiseBar.Top,StringFormat.GenericTypographic);
        _numbers.Draw(g, Math.Floor(v.Poise * 100).ToString(CultureInfo.InvariantCulture) + "%", 90+PlayerHudResourceLayout.PoiseOffsetX, poiseBar.Bottom, 11.5f, Scale, 26, PlayerHudResourceStyle.Poise);
        PaintPoise(g, v);
        using (var levelBase = new SolidBrush(Color.FromArgb(21,24,25)))
            g.FillPolygon(levelBase,[new PointF(4,PlayerHudResourceLayout.LevelTop),new PointF(74,PlayerHudResourceLayout.LevelTop),new PointF(86,573),new PointF(4,573)]);
        using (var edge = new Pen(Color.FromArgb(75,79,80),0.6f))
            g.DrawLines(edge,[new PointF(6,554),new PointF(73,554),new PointF(79,560)]);
        DrawSizedArt(g, "level-label", new RectangleF(12, 554, 20.65f, 17.8f));
        _numbers.Draw(g, v.Level.ToString(CultureInfo.InvariantCulture), 41, 572, 18, Scale, 37, muted);
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
        // Authored name mask and 300-frame loop; glyphs retain the original x scale.
        var saved = g.Save();
        g.SetClip(new RectangleF(342.35f, 514.85f, 134, 16), CombineMode.Intersect);
        DrawNameGrid(g);
        g.TranslateTransform(342.35f + NameOffset(_nameClock), 516.15f);
        g.ScaleTransform(1.3433228f, 1);
        g.DrawString(v.Name, _nameFont, dim, PointF.Empty, StringFormat.GenericTypographic);
        g.Restore(saved);

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
            g.FillRectangle(background, 592, 506, 421, 23);
            g.DrawString(Controller.Message, _body, text, 596, 510);
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
        var detail = value.PoiseDetail;
        var inactive = detail?.Phase is "air" or "down" or "rigid" or "unavailable";
        var fraction = detail?.Phase is "air" or "down" ? 0 : (float)Math.Clamp(value.Poise, 0, 1);
        var source=PlayerHudBarArtData.MpBounds;
        var split = detail is { HasStaggerBand: true } && !inactive ? (float)detail.Threshold * source.Width : 0;
        var saved=g.Save();
        g.TranslateTransform(PlayerHudResourceLayout.PoiseOffsetX,PlayerHudResourceLayout.PoiseTop-source.Top);
        using var track = new SolidBrush(Color.FromArgb(24, 28, 28));
        using var fill = new SolidBrush(inactive ? Color.FromArgb(145,147,151) : PlayerHudResourceStyle.Poise);
        using var border = new Pen(inactive ? Color.FromArgb(91,94,98) : Color.FromArgb(139,130,80),0.3f);
        g.FillPath(track,_poiseCells);
        var filled=g.Save();
        g.SetClip(new RectangleF(source.Left,source.Top,source.Width*fraction,source.Height),CombineMode.Intersect);
        g.FillPath(fill,_poiseCells);g.Restore(filled);
        g.DrawPath(border,_poiseCells);
        if (split > 0)
        {
            var risk=g.Save();
            g.SetClip(_poiseCells,CombineMode.Intersect);
            g.SetClip(new RectangleF(source.Left,source.Top,split,source.Height),CombineMode.Intersect);
            using var cut = new SolidBrush(Color.FromArgb(20,24,24));
            for(var x=source.Left+2;x<source.Left+split;x+=6)
                g.FillPolygon(cut,[new PointF(x-1.8f,source.Bottom),new PointF(x,source.Bottom-2.4f),new PointF(x+1.8f,source.Bottom)]);
            g.Restore(risk);
            var boundary=source.Left+split;
            g.FillRectangle(cut,boundary-1.1f,source.Top,2.2f,source.Height);
            using var marker = new SolidBrush(Color.FromArgb(245,241,222));
            g.FillPolygon(marker,[new PointF(boundary-2,source.Top-2),new PointF(boundary+2,source.Top-2),new PointF(boundary,source.Top+0.5f)]);
        }
        g.Restore(saved);
    }

    private static bool HasWeaponSlot(PlayerHudCombat combat) => combat.WeaponVisible && combat.Mode is not ("" or "双枪" or "长枪副武器");
    private void DrawNameGrid(Graphics g)
    {
        var offset = GridOffsets[(_nameClock * 3 / 100) % 11];
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
    private void PaintCombat(Graphics g, PlayerHudCombat combat)
    {
        var mode = Array.IndexOf(new[] { "手枪", "手枪2", "长枪", "兵器", "手雷", "空手", "双枪", "长枪副武器" }, combat.Mode);
        if (mode < 0) return;
        const float x = 506.95f, y = 522.45f;
        DrawArt(g, "mode-" + mode, x, y);
        if (mode < 6)
        {
            DrawArt(g, "weapon-panel", x, y);
            using var emptyMark = new SolidBrush(Color.FromArgb(229, 229, 229));
            g.DrawString("+", _slotMark, emptyMark, x + 62.3f, y + 15.3f);
        }
        using var text = new SolidBrush(Color.FromArgb(204, 204, 204));
        if (mode < 3)
        {
            DrawArt(g, "ammo-round", x - 14.45f, y + 1.95f);
            DrawArt(g, "ammo-magazine", x - 14.3f, y + 25.35f);
            g.DrawString(AmmoValue(combat.Ammo[0]), _nameFont, text, x - 1.45f, y - 1.45f);
            g.DrawString(AmmoValue(combat.Ammo[1]), _nameFont, text, x - 1.6f, y + 22);
        }
        else if (mode >= 6)
        {
            using var centered = new StringFormat(StringFormat.GenericTypographic) { Alignment = StringAlignment.Center };
            for (var row = 0; row < 2; row++)
            {
                DrawArt(g, "ammo-round", x - 23.6f, y - 5.8f + row * 24.5f);
                DrawArt(g, "ammo-magazine", x - 24.1f, y + 6.2f + row * 24.5f);
                g.DrawString(Ammo(combat.Ammo[row * 2], combat.Ammo[row * 2 + 1]), _nameFont, text,
                    new RectangleF(x - 10.1f, y - 3 + row * 24.55f, 81.25f, 15.55f), centered);
            }
        }
        else if (mode == 4) g.DrawString(AmmoValue(combat.Ammo[1]), _nameFont, text, x + 1.2f, y + 17.65f);
        if (mode is >= 3 and <= 5)
        {
            using var tiny = NativeHudFonts.CreateRoleFont("native.player-info.body", 4, FontStyle.Regular, GraphicsUnit.Pixel);
            g.DrawString("+++++++++++++++++", tiny, text, x - 9.25f + (mode == 4 ? 9.2f : -1.5f), y + 5.6f);
        }
    }

    private void DrawBankDots(Graphics g, int bank)
    {
        DrawArt(g, "bank-" + bank, 321.9f, 548.35f);
    }
    private void DrawSlot(Graphics g, RectangleF r, string icon, string key, string badge, PlayerHudCooldown cooldown, string kind, int slot, int bank = -1)
    {
        if (kind != "weapon") DrawArt(g, "slot", r.X + 13, r.Y + 13.1f);
        if (kind is "skill" or "drug")
        {
            using var authoredPlus = new SolidBrush(Color.FromArgb(229, 229, 229));
            g.DrawString("+", _slotMark, authoredPlus, r.X + 8.7f, r.Y + 4.3f);
        }
        var bitmap = _icons.Get(icon, (int)Math.Ceiling(24 * Scale));
        if (bitmap != null) g.DrawImage(bitmap, r.X + 1, r.Y + 1, r.Width - 2, r.Height - 2);
        if (kind != "weapon") DrawArt(g, "slot-detail", r.X + 13, r.Y + 13.1f);
        // All authored foreground belongs below cooldown feedback, including non-bitmap controls.
        if (kind == "switch") DrawBankDots(g, bank);
        else if (kind == "weapon")
        {
            DrawArt(g, "weapon", 573.55f, 547.65f);
        }
        if (kind == "drug" && cooldown.Ready && _hover?.Kind == kind && _hover.Slot == slot)
            DrawArt(g, "drug-hover", r.X + 13, r.Y + 13);
        if (!cooldown.Ready)
        {
            using var shade = new SolidBrush(Color.FromArgb(165, 5, 10, 15));
            g.FillRectangle(shade, r.X + 1, r.Y + 1, r.Width - 2, (float)((r.Height - 2) * (1 - cooldown.Fraction)));
            if (kind is "switch" or "weapon")
            {
                using var track = new SolidBrush(Color.FromArgb(240, 15, 20, 25));
                using var progress = new SolidBrush(Color.FromArgb(241, 201, 112));
                var strip=CooldownTrackRect(r);
                g.FillRectangle(track,strip);
                g.FillRectangle(progress,strip.X,strip.Y,(float)(strip.Width*cooldown.Fraction),strip.Height);
            }
        }
        var cooldownIndex = kind == "weapon" ? 0 : kind == "skill" ? slot : kind == "switch" ? 17 : 13 + slot % 4;
        var flashFrame = _readyFlash[cooldownIndex] < 0 ? 7 : _readyFlash[cooldownIndex] * 3 / 100;
        if (cooldown.Ready && flashFrame < 7 && ReadyAlpha[flashFrame] > 0)
        {
            using var flash = new SolidBrush(Color.FromArgb((int)(255 * ReadyAlpha[flashFrame]), Color.White));
            g.FillRectangle(flash, r.X + 0.5f, r.Y + 0.5f, 25.5f, 25.5f);
        }
        using var foreground = new SolidBrush(Color.FromArgb(248, 243, 222));
        using var shadow = new SolidBrush(Color.FromArgb(235, 15, 18, 19));
        if (badge.Length > 0)
        {
            g.DrawString(badge, _small, shadow, r.X + 4, r.Y + 1);
            g.DrawString(badge, _small, foreground, r.X + 3, r.Y);
        }
        DrawHotkey(g,r,key,cooldown,cooldownIndex);
    }
    private void DrawHotkey(Graphics g, RectangleF slot, string key,PlayerHudCooldown cooldown,int index)
    {
        var label=!cooldown.Ready ? PlayerHudCooldownText.Format(cooldown)
            : key.Equals("Spacebar",StringComparison.OrdinalIgnoreCase) || key.Equals("Space",StringComparison.OrdinalIgnoreCase) || key==" " ? "空格" : key;
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
        using var ink=new SolidBrush(cooldown.Ready?Color.FromArgb(238,239,237):Color.FromArgb(241,201,112));
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
        for (var i = 0; i < 12; i++)
            if (s.Loadout.Skills[i].Equipped && UnequipRect(i).Contains(point)) return Target("skill", i + 1, s.Loadout.Skills[i].Key, s.Loadout.Revision, UnequipRect(i));
        for (var i = 0; i < 12; i++)
            if (s.Loadout.Skills[i].Equipped && SkillRect(i).Contains(point)) return Target("skill", i + 1, s.Loadout.Skills[i].Key, s.Loadout.Revision, SkillRect(i));
        for (var i = 0; i < 4; i++)
            if (s.Loadout.Drugs[i].Count > 0 && DrugRect(i).Contains(point)) return Target("drug", s.Loadout.Drugs[i].Slot, s.Loadout.Drugs[i].Name, s.Loadout.DrugRevision, DrugRect(i));
        if (HasWeaponSlot(s.Combat) && WeaponRect.Contains(point)) return Target("weapon", 0, s.Combat.WeaponName, 0, WeaponRect);
        return null;
    }
    public override bool TryHitTest(Point screenPt) => Hit(screenPt) != null;
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
    public override void SetHostSuppressed(bool suppressed) { if (suppressed) Cancel(); base.SetHostSuppressed(suppressed); }
    public override void Dispose()
    {
        foreach(var caption in _captions)caption?.Path.Dispose();Array.Clear(_captions);
        Cancel(); Controller.StatusChanged -= Repaint; _icons.Dispose(); _art.Dispose(); _numbers.Dispose(); _poiseCells.Dispose(); _body.Dispose(); _small.Dispose(); _nameFont.Dispose(); _hotkeyFont.Dispose(); _poiseLabel.Dispose(); _slotMark.Dispose(); base.Dispose();
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
