#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudResourceLayout
{
    internal const float ResourceOffsetX = -5;
    // Expose the authored white chassis arc without shifting the adjacent readouts again.
    internal const float HpOffsetX = 12 + ResourceOffsetX - 1.5f;
    internal const float LevelOffsetX = 4;
    internal const float DeckTop = 513.5f;
    internal const float MpOffsetX = 120.2f - 119.56701607f;
    internal const float MpOffsetY = 540.6f - 531.42717092f;
    internal const float LevelTop = 553;
    internal static RectangleF MpBar => PlayerInfoRasterPlanner.LiveMpBar;
    internal static float MpScaleX => MpBar.Width / PlayerHudBarArtData.MpBounds.Width;
    internal static float MpScaleY => MpBar.Height / PlayerHudBarArtData.MpBounds.Height;
    internal static float PoiseTop => 552;
    internal static RectangleF PoiseBar => new(115.34f, PoiseTop, 152, 8);
    internal static float PoisePercentX => 83;
    internal const float PoisePercentWidth = 29;
    internal static readonly RectangleF ShieldPlaque = PlayerInfoRasterPlanner.LiveShieldPlaque;
    internal static readonly RectangleF ShieldStrengthPlaque = new(83.5f, 515.3f, 50, 10.2f);
    internal static readonly RectangleF ShieldCapacityPlaque = new(136.5f, 515.3f, 156, 10.2f);
}

/// <summary>Live-only plaque in the already-owned HP/MP surface; no extra window.</summary>
internal sealed class PlayerHudShieldReadout : IDisposable
{
    private readonly Font _label = NativeHudFonts.CreateRoleFont("native.hud.body",7.8f,FontStyle.Bold,GraphicsUnit.Pixel);
    private readonly PlayerHudTextCache _numbers = new();

    private static Color LerpColor(Color a, Color b, float t)
    {
        if (t <= 0f) return a;
        if (t >= 1f) return b;
        static int Mix(int x, int y, float f) => Math.Clamp((int)Math.Round(x + (y - x) * f), 0, 255);
        return Color.FromArgb(Mix(a.A, b.A, t), Mix(a.R, b.R, t), Mix(a.G, b.G, t), Mix(a.B, b.B, t));
    }

    private static Color ScaleAlpha(Color c, float alpha) =>
        alpha >= 0.999f ? c : Color.FromArgb(Math.Clamp((int)Math.Round(c.A * alpha), 0, 255), c.R, c.G, c.B);

    private readonly record struct PlaqueKey(float Scale,bool Ready,bool Present,double Shield,double Maximum,
        string? StrengthKind,string Strength,string? Recovery,int Percent,int Progress,bool Resistant,
        int Presence,int Empty,int Break,int Resistance,bool Static);
    private PlaqueKey _key;
    private Bitmap? _tile;

    internal void Paint(Bitmap destination,PlayerInfoRasterPlan plan,Rectangle? damage,PlayerHudVitals value,PlayerHudResourceMotion motion)
    {
        float scale=(float)plan.PhysicalScale;
        var r=PlayerHudResourceLayout.ShieldPlaque;
        int left=(int)Math.Floor(r.Left*scale)-2,top=(int)Math.Floor(r.Top*scale)-2;
        var detail=value.ShieldDetail;
        double progress=detail?.Recovery.Progress??0;
        static int Q(double x)=>(int)Math.Round(x*255);
        var key=new PlaqueKey(scale,value.ShieldReady,value.ShieldPresent,Math.Floor(value.Shield),Math.Floor(value.ShieldMax),
            detail?.StrengthKind,PlayerHudResourceStyle.ShieldStrengthReadout(detail),detail?.Recovery.State,
            (int)Math.Round(progress*100,MidpointRounding.AwayFromZero),(int)Math.Round(progress*r.Width*scale),
            detail?.ResistsBypass==true,Q(motion.Shield.Presence),motion.EmptyInitialized?Q(motion.EmptyMix):-1,
            Q(motion.Shield.BreakPulse*PlayerHudMotionSettings.EventStrength),motion.ResistantInitialized?Q(motion.ResistantMix):-1,
            PlayerHudMotionSettings.StaticFeedback);
        if (_tile==null || key!=_key)
        {
            var size=new Size((int)Math.Ceiling(r.Right*scale)+2-left,(int)Math.Ceiling(r.Bottom*scale)+2-top);
            if (_tile?.Size!=size)
            {
                _tile?.Dispose();
                _tile=new Bitmap(size.Width,size.Height,System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            }
            using var local=Graphics.FromImage(_tile);
            local.Clear(Color.Transparent);
            local.SmoothingMode=SmoothingMode.AntiAlias;
            local.TranslateTransform(-left,-top);
            local.ScaleTransform(scale,scale);
            PaintPlaque(local,value,scale,motion);
            _key=key;
        }
        using var graphics=Graphics.FromImage(destination);
        if (damage.HasValue) graphics.SetClip(damage.Value);
        graphics.DrawImageUnscaled(_tile,left+plan.FlashViewportPhysical.Left-plan.TightPhysicalBounds.Left,
            top+plan.FlashViewportPhysical.Top-plan.TightPhysicalBounds.Top);
    }

    private void PaintPlaque(Graphics g, PlayerHudVitals value, float scale, PlayerHudResourceMotion? motion = null)
    {
        if (!value.ShieldReady || !value.ShieldPresent)
        {
            if (!value.ShieldReady)
            {
                using var muted = new SolidBrush(Color.FromArgb(115,128,131));
                g.DrawString("护盾未就绪", _label, muted, 116, 516.3f, StringFormat.GenericTypographic);
            }
            return;
        }
        var display = value;
        var alpha = !value.ShieldReady
            ? 1f
            : value.ShieldPresent
                ? (motion is { Shield.Presence: > 0f } ? motion.Shield.Presence : 1f)
                : (motion?.Shield.Presence ?? 0f);
        if (alpha <= 0f) return;

        var strength=PlayerHudResourceLayout.ShieldStrengthPlaque;
        var r=PlayerHudResourceLayout.ShieldCapacityPlaque;
        var emptyMix = !display.ShieldReady
            ? 1f
            : !PlayerHudMotionSettings.StaticFeedback && motion is { EmptyInitialized: true } && (value.ShieldPresent || motion.Shield.Presence > 0f)
                ? motion.EmptyMix
                : (display.Shield <= 0 ? 1f : 0f);
        var baseColor = LerpColor(PlayerHudResourceStyle.Shield, PlayerHudResourceStyle.ShieldEmpty, emptyMix);
        var breakPulse = (motion?.Shield.BreakPulse ?? 0f) * PlayerHudMotionSettings.EventStrength;
        if (breakPulse > 0f)
        {
            baseColor = LerpColor(baseColor, Color.FromArgb(236, 252, 255), breakPulse * 0.75f);
        }
        var resistantMix = !PlayerHudMotionSettings.StaticFeedback && motion is { ResistantInitialized: true } && value.ShieldReady && (value.ShieldPresent || motion.Shield.Presence > 0f)
            ? motion.ResistantMix
            : (display.ShieldDetail?.ResistsBypass == true ? 1f : 0f);
        var resistantTarget = LerpColor(Color.FromArgb(224,207,255), Color.FromArgb(142,124,163), emptyMix);
        var strengthColor = ScaleAlpha(LerpColor(baseColor, resistantTarget, resistantMix), alpha);
        var color = ScaleAlpha(baseColor, alpha);

        using var background = new SolidBrush(ScaleAlpha(Color.FromArgb(246,13,28,30), alpha));
        var lineAlpha = (int)Math.Clamp(Math.Round((100 + 120 * breakPulse) * alpha), 0, 255);
        using var line = new Pen(Color.FromArgb(lineAlpha, baseColor.R, baseColor.G, baseColor.B), 0.5f + 0.6f * breakPulse);
        PointF[] outline = [new(r.Left,r.Top),new(r.Right-6,r.Top),new(r.Right,r.Top+r.Height/2),new(r.Right-6,r.Bottom),new(r.Left,r.Bottom)];
        g.FillPolygon(background,outline);g.DrawPolygon(line,outline);
        PointF[] badge = [new(strength.Left+2,strength.Top),new(strength.Right-3,strength.Top),new(strength.Right,strength.Top+3),
            new(strength.Right,strength.Bottom-2),new(strength.Right-2,strength.Bottom),new(strength.Left,strength.Bottom),new(strength.Left,strength.Top+2)];
        using var metal = new SolidBrush(ScaleAlpha(LerpColor(Color.FromArgb(25,43,46), Color.FromArgb(53,38,70), resistantMix), alpha));
        var edgeAlpha = (int)Math.Round((100 + 100 * resistantMix + 55 * breakPulse) * alpha);
        using var badgeEdge = new Pen(Color.FromArgb(Math.Clamp(edgeAlpha, 0, 255), strengthColor.R, strengthColor.G, strengthColor.B), 0.6f + 0.5f * breakPulse);
        g.FillPolygon(metal,badge);g.DrawPolygon(badgeEdge,badge);
        var detail=display.ShieldDetail;
        var recovery=detail?.Recovery;
        var clipped=g.Save();
        using(var path=new GraphicsPath()) { path.AddPolygon(outline);g.SetClip(path,CombineMode.Intersect); }
        if(recovery is {State:"waiting"} or {State:"charging"})
        {
            var progress=recovery.State=="charging"?1:recovery.Progress;
            using var fill=new SolidBrush(ScaleAlpha(Color.FromArgb(recovery.State=="charging"?38:76,45,166,167), alpha));
            g.FillRectangle(fill,r.Left+1,r.Top+1,(float)((r.Width-2)*progress),r.Height-2);
            if(recovery.State=="waiting" && progress>0 && progress<1)
                g.DrawLine(line,r.Left+1+(float)((r.Width-2)*progress),r.Top+1,r.Left+1+(float)((r.Width-2)*progress),r.Bottom-1);
        }
        else if(recovery?.State is "health" or "mp" or "conditions")
        {
            using var blocked=new HatchBrush(HatchStyle.ForwardDiagonal,ScaleAlpha(Color.FromArgb(65,116,139,140), alpha),Color.Transparent);
            g.FillRectangle(blocked,r);
        }
        g.Restore(clipped);
        var strengthText=PlayerHudResourceStyle.ShieldStrengthReadout(detail);
        using (var strengthInk = new SolidBrush(strengthColor))
            g.DrawString("强度",_label,strengthInk,86.1f,515.45f,StringFormat.GenericTypographic);
        _numbers.Draw(g,strengthText,106.8f,524f,9.7f,scale,25,strengthColor);
        using var ink = new SolidBrush(color);
        g.DrawString("盾量",_label,ink,140,515.45f,StringFormat.GenericTypographic);
        var capacity=Math.Floor(display.Shield).ToString("0",CultureInfo.InvariantCulture)+"/"+
            Math.Floor(display.ShieldMax).ToString("0",CultureInfo.InvariantCulture);
        _numbers.Draw(g,capacity,162,524.2f,10,scale,73,color);
        var caption = recovery?.State switch
        {
            "manual" => "手动补盾", "full" => "已充满", "charging" => "充能中",
            "waiting" => "等待 " + Math.Round(100 * recovery.Progress, MidpointRounding.AwayFromZero).ToString("0",CultureInfo.InvariantCulture) + "%",
            "health" => "须满血", "mp" => "供能缺蓝", "conditions" => "多层受阻",
            _ => ""
        };
        if (caption.Length != 0)
        {
            using var labelInk = new SolidBrush(Color.FromArgb(172,184,183));
            using var right = new StringFormat(StringFormat.GenericTypographic) { Alignment = StringAlignment.Far, FormatFlags = StringFormatFlags.NoWrap };
            g.DrawString(caption,_label,labelInk,new RectangleF(235,515.45f,50,11),right);
        }
    }

    public void Dispose() { _tile?.Dispose();_numbers.Dispose();_label.Dispose(); }
}
