#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudResourceLayout
{
    internal const float MpOffsetY = -6;
    internal const float LevelTop = 553;
    internal static RectangleF MpBar => new(PlayerHudBarArtData.MpBounds.X,
        PlayerHudBarArtData.MpBounds.Y + MpOffsetY, PlayerHudBarArtData.MpBounds.Width, PlayerHudBarArtData.MpBounds.Height);
    internal static float PoiseTop => LevelTop - MpBar.Height;
    // Continue the authored left edge through both rows, including their gap.
    internal static float CellSlope => (PlayerHudBarArtData.Cells[0][3].X - PlayerHudBarArtData.Cells[0][0].X) / MpBar.Height;
    internal static float PoiseOffsetX => CellSlope * (PoiseTop - MpBar.Top);
    internal static RectangleF PoiseBar => new(MpBar.X+PoiseOffsetX,PoiseTop,MpBar.Width,MpBar.Height);
    internal static readonly RectangleF ShieldPlaque = new(91,493,187,13);
}

/// <summary>Live-only plaque in the already-owned HP/MP surface; no extra window.</summary>
internal sealed class PlayerHudShieldReadout : IDisposable
{
    private readonly Font _label = NativeHudFonts.CreateRoleFont("native.hud.body",9,FontStyle.Regular,GraphicsUnit.Pixel);
    private readonly PlayerHudTextCache _numbers = new();

    internal void Paint(Graphics g, PlayerHudVitals value, float scale)
    {
        if (value.ShieldReady && !value.ShieldPresent) return;
        var r=PlayerHudResourceLayout.ShieldPlaque;
        var color = !value.ShieldReady || value.Shield <= 0 ? PlayerHudResourceStyle.ShieldEmpty : PlayerHudResourceStyle.Shield;
        using var background = new SolidBrush(Color.FromArgb(246,13,28,30));
        using var line = new Pen(Color.FromArgb(100,color),0.5f);
        PointF[] outline = [new(r.Left,r.Top),new(r.Right-6,r.Top),new(r.Right,r.Top+r.Height/2),new(r.Right-6,r.Bottom),new(r.Left,r.Bottom)];
        g.FillPolygon(background,outline);g.DrawPolygon(line,outline);
        using var ink = new SolidBrush(color);
        g.DrawString(value.ShieldReady ? "护盾" : "护盾未就绪",_label,ink,r.Left+5,r.Top+1);
        if (!value.ShieldReady) return;
        _numbers.Draw(g,PlayerHudResourceStyle.Percent(value.Shield,value.ShieldMax),r.Left+35,r.Bottom-2,11.5f,scale,39,color);
        var capacity=Math.Floor(value.Shield).ToString("0",CultureInfo.InvariantCulture)+"/"+
            Math.Floor(value.ShieldMax).ToString("0",CultureInfo.InvariantCulture);
        _numbers.Draw(g,capacity,r.Left+80,r.Bottom-2,11.5f,scale,99,color);
    }

    public void Dispose() { _numbers.Dispose();_label.Dispose(); }
}
