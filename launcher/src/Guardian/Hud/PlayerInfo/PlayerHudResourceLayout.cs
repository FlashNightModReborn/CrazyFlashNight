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

    internal void Paint(Graphics g, PlayerHudVitals value, float scale)
    {
        if (value.ShieldReady && !value.ShieldPresent) return;
        var strength=PlayerHudResourceLayout.ShieldStrengthPlaque;
        var r=PlayerHudResourceLayout.ShieldCapacityPlaque;
        var color = !value.ShieldReady || value.Shield <= 0 ? PlayerHudResourceStyle.ShieldEmpty : PlayerHudResourceStyle.Shield;
        var resistant = value.ShieldDetail?.ResistsBypass == true;
        var strengthColor = resistant
            ? value.ShieldReady && value.Shield > 0 ? Color.FromArgb(224,207,255) : Color.FromArgb(142,124,163)
            : color;
        using var background = new SolidBrush(Color.FromArgb(246,13,28,30));
        using var line = new Pen(Color.FromArgb(100,color),0.5f);
        PointF[] outline = [new(r.Left,r.Top),new(r.Right-6,r.Top),new(r.Right,r.Top+r.Height/2),new(r.Right-6,r.Bottom),new(r.Left,r.Bottom)];
        g.FillPolygon(background,outline);g.DrawPolygon(line,outline);
        PointF[] badge = [new(strength.Left+2,strength.Top),new(strength.Right-3,strength.Top),new(strength.Right,strength.Top+3),
            new(strength.Right,strength.Bottom-2),new(strength.Right-2,strength.Bottom),new(strength.Left,strength.Bottom),new(strength.Left,strength.Top+2)];
        using var metal = new LinearGradientBrush(strength,
            resistant ? Color.FromArgb(249,66,45,91) : Color.FromArgb(249,33,54,58),
            resistant ? Color.FromArgb(249,27,21,38) : Color.FromArgb(249,9,23,26),LinearGradientMode.Vertical);
        using var badgeEdge = new Pen(Color.FromArgb(resistant ? 200 : 100, strengthColor),0.6f);
        g.FillPolygon(metal,badge);g.DrawPolygon(badgeEdge,badge);
        var detail=value.ShieldDetail;
        var recovery=detail?.Recovery;
        var clipped=g.Save();
        using(var path=new GraphicsPath()) { path.AddPolygon(outline);g.SetClip(path,CombineMode.Intersect); }
        if(recovery is {State:"waiting"} or {State:"charging"})
        {
            var progress=recovery.State=="charging"?1:recovery.Progress;
            using var fill=new SolidBrush(Color.FromArgb(recovery.State=="charging"?38:76,45,166,167));
            g.FillRectangle(fill,r.Left+1,r.Top+1,(float)((r.Width-2)*progress),r.Height-2);
            if(recovery.State=="waiting" && progress>0 && progress<1)
                g.DrawLine(line,r.Left+1+(float)((r.Width-2)*progress),r.Top+1,r.Left+1+(float)((r.Width-2)*progress),r.Bottom-1);
        }
        else if(recovery?.State is "health" or "mp" or "conditions")
        {
            using var blocked=new HatchBrush(HatchStyle.ForwardDiagonal,Color.FromArgb(65,116,139,140),Color.Transparent);
            g.FillRectangle(blocked,r);
        }
        g.Restore(clipped);
        var strengthText=PlayerHudResourceStyle.ShieldStrengthReadout(detail);
        _numbers.Draw(g,strengthText,strength.Left+4,strength.Bottom-2,11f,scale,40,strengthColor);
        using var ink = new SolidBrush(color);
        if (!value.ShieldReady) {g.DrawString("护盾未就绪",_label,ink,r.Left+5,r.Top+1);return;}
        _numbers.Draw(g,PlayerHudResourceStyle.Percent(value.Shield,value.ShieldMax),r.Left+4,r.Bottom-2,11.5f,scale,29,color);
        var capacity=Math.Floor(value.Shield).ToString("0",CultureInfo.InvariantCulture)+"/"+
            Math.Floor(value.ShieldMax).ToString("0",CultureInfo.InvariantCulture);
        _numbers.Draw(g,capacity,r.Left+37,r.Bottom-2,11.5f,scale,91,color);
    }

    public void Dispose() { _numbers.Dispose();_label.Dispose(); }
}
