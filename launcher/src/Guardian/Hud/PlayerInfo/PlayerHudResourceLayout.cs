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
    internal const float MpOffsetY = -6;
    internal const float LevelTop = 553;
    internal static RectangleF MpBar => new(PlayerHudBarArtData.MpBounds.X + ResourceOffsetX,
        PlayerHudBarArtData.MpBounds.Y + MpOffsetY, PlayerHudBarArtData.MpBounds.Width, PlayerHudBarArtData.MpBounds.Height);
    internal static float PoiseTop => LevelTop - MpBar.Height;
    // Continue the authored left edge through both rows, including their gap.
    internal static float CellSlope => (PlayerHudBarArtData.Cells[0][3].X - PlayerHudBarArtData.Cells[0][0].X) / MpBar.Height;
    internal static float PoiseOffsetX => CellSlope * (PoiseTop - MpBar.Top);
    internal static RectangleF PoiseBar => new(MpBar.X+PoiseOffsetX,PoiseTop,MpBar.Width,MpBar.Height);
    internal static float PoisePercentX => 88 + ResourceOffsetX + PoiseOffsetX;
    internal const float PoisePercentWidth = 29;
    internal static readonly RectangleF ShieldPlaque = new(91 + ResourceOffsetX,493,187,13);
    internal static readonly RectangleF ShieldStrengthPlaque = new(91 + ResourceOffsetX,493,48,13);
    internal static readonly RectangleF ShieldCapacityPlaque = new(143 + ResourceOffsetX,493,135,13);
}

/// <summary>Live-only plaque in the already-owned HP/MP surface; no extra window.</summary>
internal sealed class PlayerHudShieldReadout : IDisposable
{
    private readonly Font _label = NativeHudFonts.CreateRoleFont("native.hud.body",9,FontStyle.Regular,GraphicsUnit.Pixel);
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

    internal void Paint(Graphics g, PlayerHudVitals value, float scale, PlayerHudResourceMotion? motion = null)
    {
        var display = motion?.ResolveShieldDisplay(value) ?? value;
        if (display.ShieldReady && !display.ShieldPresent) return;
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
            : motion is { EmptyInitialized: true } && (value.ShieldPresent || motion.Shield.Presence > 0f)
                ? motion.EmptyMix
                : (display.Shield <= 0 ? 1f : 0f);
        var baseColor = LerpColor(PlayerHudResourceStyle.Shield, PlayerHudResourceStyle.ShieldEmpty, emptyMix);
        var breakPulse = motion?.Shield.BreakPulse ?? 0f;
        if (breakPulse > 0f)
        {
            baseColor = LerpColor(baseColor, Color.FromArgb(236, 252, 255), breakPulse * 0.75f);
        }
        var resistantMix = motion is { ResistantInitialized: true } && value.ShieldReady && (value.ShieldPresent || motion.Shield.Presence > 0f)
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
        var topMetal = ScaleAlpha(LerpColor(Color.FromArgb(249,33,54,58), Color.FromArgb(249,66,45,91), resistantMix), alpha);
        var bottomMetal = ScaleAlpha(LerpColor(Color.FromArgb(249,9,23,26), Color.FromArgb(249,27,21,38), resistantMix), alpha);
        using var metal = new LinearGradientBrush(strength, topMetal, bottomMetal, LinearGradientMode.Vertical);
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
        _numbers.Draw(g,strengthText,strength.Left+4,strength.Bottom-2,11f,scale,40,strengthColor);
        using var ink = new SolidBrush(color);
        if (!display.ShieldReady) {g.DrawString("护盾未就绪",_label,ink,r.Left+5,r.Top+1);return;}
        _numbers.Draw(g,PlayerHudResourceStyle.Percent(display.Shield,display.ShieldMax),r.Left+4,r.Bottom-2,11.5f,scale,29,color);
        var capacity=Math.Floor(display.Shield).ToString("0",CultureInfo.InvariantCulture)+"/"+
            Math.Floor(display.ShieldMax).ToString("0",CultureInfo.InvariantCulture);
        _numbers.Draw(g,capacity,r.Left+37,r.Bottom-2,11.5f,scale,91,color);
    }

    public void Dispose() { _numbers.Dispose();_label.Dispose(); }
}
