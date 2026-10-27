#nullable enable
using System;
using System.Drawing;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Buffs and target bars share the column reserved beside the widest notch.</summary>
internal static class PlayerHudBuffLayout
{
    internal const float Left = 6;
    internal const float SlotLeft = 9;
    internal const float SlotTop = 3;
    internal const float SlotSize = 26;
    internal const float SlotPitch = 28;
    internal const int MaxVisibleRows = 8;
    internal const float PagerHeight = 20;
    internal const float SafeRight = (1024 - RightHudLayout.PreferredNotchMaxWidthBase) / 2f
        - RightHudLayout.NotchRightGapBase;
    internal const float ColumnWidth = SafeRight - Left;
    internal static readonly int Columns = Math.Max(1, (int)Math.Floor((SafeRight - SlotLeft - SlotSize) / SlotPitch) + 1);
    internal static readonly int PageSize = Columns * MaxVisibleRows;

    internal static int PageCount(int count) => Math.Max(1, (Math.Clamp(count, 0, 256) + PageSize - 1) / PageSize);
    internal static int VisibleRows(int count) => Math.Min(MaxVisibleRows, (Math.Clamp(count, 0, 256) + Columns - 1) / Columns);
    internal static float ContentHeight(int count) => VisibleRows(count) * NativeHudTheme.TopBarHeightBase
        + (PageCount(count) > 1 ? PagerHeight : 0);
    internal static RectangleF SlotRect(int index) => new(SlotLeft + (index % Columns) * SlotPitch,
        SlotTop + (index / Columns) * NativeHudTheme.TopBarHeightBase, SlotSize, SlotSize);
    internal static RectangleF Bounds(int count) => count <= 0 ? RectangleF.Empty
        : new(Left, 0, 6 + Math.Min(Columns, count) * SlotPitch, ContentHeight(count));
    internal static RectangleF PreviousPageRect(int count) => new(SlotLeft,
        VisibleRows(count) * NativeHudTheme.TopBarHeightBase + 1, SlotSize, PagerHeight - 2);
    internal static RectangleF NextPageRect(int count) => new(Bounds(count).Right - SlotSize - 3,
        VisibleRows(count) * NativeHudTheme.TopBarHeightBase + 1, SlotSize, PagerHeight - 2);
}
