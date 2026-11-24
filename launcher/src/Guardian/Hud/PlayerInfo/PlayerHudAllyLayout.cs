using System;
using System.Drawing;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudAllyLayout
{
    internal const int PageSize = 5;
    internal const int ColumnsPerRow = 10;
    internal const float RowHeight = 28f;
    internal const float RowGap = 2f;
    internal const float RowStride = RowHeight + RowGap;
    internal const float MaxSingleWideCardWidth = 142.5f;

    internal static bool Dense(int slots, int focus) => slots > 3 || focus > 2;

    internal static int RowCount(int slots, int focus) =>
        slots <= 0 ? 0 : !Dense(slots, focus) ? 1 : 1 + (slots - 1) / ColumnsPerRow;

    internal static RectangleF Cell(int slot, int occupiedSlots, int focusCount, float top)
    {
        if (!Dense(occupiedSlots, focusCount))
        {
            float w = Math.Min(MaxSingleWideCardWidth, 285f / Math.Max(1, occupiedSlots));
            return new RectangleF(12 + w * slot, top + 3f, w - 2f, 22f);
        }
        int row = slot / ColumnsPerRow;
        int col = slot % ColumnsPerRow;
        return new RectangleF(12 + col * 26.5f, top + 2f + row * RowStride, 23.5f, 24f);
    }

    /// <summary>Per-row snug plate wrapping only occupied cells on that row (row 0 reserves +N toggle width only when overflow exists).</summary>
    internal static RectangleF RowTray(int row, int slots, int focus, float top, bool hasOverflow = false)
    {
        if (slots <= 0)
            return hasOverflow && row == 0 ? new RectangleF(6f, top, 294f, RowHeight) : RectangleF.Empty;
        if (!Dense(slots, focus))
        {
            if (row != 0) return RectangleF.Empty;
            float right = Cell(slots - 1, slots, focus, top).Right + 5f;
            if (hasOverflow) right = Math.Max(right, 300f);
            return new RectangleF(6f, top, right - 6f, RowHeight);
        }
        int rows = RowCount(slots, focus);
        if (row < 0 || row >= rows) return RectangleF.Empty;
        int lastSlotInRow = Math.Min(slots - 1, (row + 1) * ColumnsPerRow - 1);
        float rowRight = Cell(lastSlotInRow, slots, focus, top).Right + 5f;
        if (row == 0 && hasOverflow) rowRight = Math.Max(rowRight, 300f);
        return new RectangleF(6f, top + row * RowStride, rowRight - 6f, RowHeight);
    }

    internal static RectangleF Tray(int slots, int focus, float top, bool hasOverflow = false)
    {
        if (slots <= 0)
            return hasOverflow ? new RectangleF(6f, top, 294f, RowHeight) : RectangleF.Empty;
        int rows = RowCount(slots, focus);
        var first = RowTray(0, slots, focus, top, hasOverflow);
        float height = RowHeight + (rows - 1) * RowStride;
        return new RectangleF(first.X, top, first.Width, height);
    }

    internal static RectangleF Toggle(float top) => new(276f, top + 3.5f, 21f, 21f);
    internal static RectangleF Drawer(RectangleF tray, int count) =>
        new(tray.Right - 136f, tray.Bottom + 2f, 136f, 22f + 14f * Math.Min(count, PageSize));
}
