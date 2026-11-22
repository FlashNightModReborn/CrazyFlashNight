using System;
using System.Drawing;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudAllyLayout
{
    internal const int PageSize = 5;
    internal static bool Dense(int slots, int focus) => slots > 3 || focus > 2;

    internal static RectangleF Cell(int slot, int occupiedSlots, int focusCount, float top)
    {
        if (!Dense(occupiedSlots, focusCount))
        {
            float w = 285f / Math.Max(1,occupiedSlots);
            return new RectangleF(12 + w*slot, top+3, w-2, 22);
        }
        return new RectangleF(12 + (slot%10)*26.5f, top+3.2f+(slot/10)*28, 23.5f, 24.5f);
    }

    internal static RectangleF Tray(int slots, int focus, float top) =>
        new(6,top,slots is > 0 and <= 10 ? Cell(slots-1,slots,focus,top).Right-6+5 : 294,Dense(slots,focus) ? 31 + Math.Max(0,(slots-1)/10)*28 : 28);
    internal static RectangleF Toggle(float top) => new(276,top+4,21,21);
    internal static RectangleF Drawer(RectangleF tray, int count) =>
        new(tray.Right-136,tray.Bottom+2,136,22+14*Math.Min(count,PageSize));
}
