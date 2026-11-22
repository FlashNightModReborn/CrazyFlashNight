#nullable enable
using System;
using System.Drawing;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudBuffLayout
{
    internal const float SlotLeft = 86.5f, SlotTop = 484.5f, SlotSize = 26, SlotPitch = 28.5f;
    internal const int Columns = 14, PageSize = Columns * 4;
    internal const float SafeRight = (1024 - RightHudLayout.PreferredNotchMaxWidthBase) / 2f - RightHudLayout.NotchRightGapBase;
    internal const float ColumnWidth = 294;
    internal static readonly RectangleF Drawer = new(602, 339, 417, 140);
    internal static int PageCount(int count) => Math.Max(1, (count + PageSize - 1) / PageSize);

    internal static int RailCount(int count, bool hasCold)
    {
        float right = hasCold ? 581 : 1018;
        int Capacity(float edge) => (int)Math.Floor((edge - SlotLeft + SlotPitch - SlotSize) / SlotPitch);
        return count <= Capacity(right) ? count : Capacity(right - 41);
    }

    internal static RectangleF SlotRect(int index) => new(SlotLeft + index * SlotPitch, SlotTop, SlotSize, SlotSize);
    internal static RectangleF DrawerSlot(int index) => new(Drawer.Left + 10.5f + index % Columns * 28.4f,
        Drawer.Top + 22 + index / Columns * 29, SlotSize, SlotSize);
    internal static RectangleF Toggle(bool hasCold) => new((hasCold ? 581 : 1018) - 37.5f, SlotTop, 37.5f, SlotSize);
    internal static RectangleF PreviousPageRect(int count) => new(Drawer.Right - 63, Drawer.Top + 3, 14, 14);
    internal static RectangleF NextPageRect(int count) => new(Drawer.Right - 19, Drawer.Top + 3, 14, 14);
    internal static RectangleF Bed(int shown) => RectangleF.FromLTRB(SlotLeft - 2.5f, SlotTop - 2,
        SlotRect(shown - 1).Right + 2.5f, 512f - .6f);
    internal static RectangleF Bounds(int count, bool hasCold = false, bool open = false)
    {
        if (count == 0) return RectangleF.Empty;
        if (hasCold && !open) return new RectangleF(84f,482.5f,497f,29.5f);
        int shown = RailCount(count, hasCold);
        var bounds = Bed(shown);
        if (count > shown)
        {
            bounds = RectangleF.Union(bounds, Toggle(hasCold));
            if (open) bounds = RectangleF.Union(bounds, Drawer);
        }
        bounds = RectangleF.FromLTRB(bounds.Left, bounds.Top, bounds.Right, 512f);
        return bounds;
    }
}
