using System;
using System.Drawing;

namespace CF7Launcher.Guardian
{
    internal static class ModifierNativeLayout
    {
        internal const int Width = 843;
        internal const int Height = 456;
        internal const int Inset = 2;

        internal static readonly Rectangle EconomyTab = new Rectangle(1, 157, 177, 38);
        internal static readonly Rectangle ItemsTab = new Rectangle(1, 212, 175, 38);
        internal static readonly Rectangle LevelTab = new Rectangle(1, 268, 176, 38);
        internal static readonly Rectangle UnitsTab = new Rectangle(1, 323, 176, 38);
        internal static readonly Rectangle Close = new Rectangle(620, 31, 21, 22);

        internal static readonly Rectangle Money = new Rectangle(200, 165, 130, 37);
        internal static readonly Rectangle KCoin = new Rectangle(200, 231, 130, 37);
        internal static readonly Rectangle TestSpace = new Rectangle(199, 306, 131, 37);

        internal static readonly Rectangle ItemFirst = new Rectangle(194, 379, 22, 23);
        internal static readonly Rectangle ItemPrevious = new Rectangle(224, 379, 22, 23);
        internal static readonly Rectangle ItemNext = new Rectangle(284, 379, 22, 23);
        internal static readonly Rectangle ItemLast = new Rectangle(314, 379, 22, 23);
        internal static readonly Rectangle ItemQuery = new Rectangle(433, 318, 92, 24);
        internal static readonly Rectangle ItemQuantity = new Rectangle(461, 243, 75, 24);
        internal static readonly Rectangle ItemMinus = new Rectangle(547, 241, 24, 24);
        internal static readonly Rectangle ItemPlus = new Rectangle(592, 241, 24, 24);
        internal static readonly Rectangle ItemProduce = new Rectangle(426, 272, 108, 31);
        internal static readonly Rectangle ItemSearch = new Rectangle(426, 341, 108, 31);
        internal static readonly Rectangle ItemGrid = new Rectangle(179, 145, 224, 224);
        internal const int ItemCellSize = 28;
        internal const int ItemColumns = 8;
        internal const int ItemRows = 8;

        internal static readonly Rectangle KillAll = new Rectangle(199, 158, 94, 30);
        internal static readonly Rectangle FinishWave = new Rectangle(199, 214, 94, 30);
        internal static readonly Rectangle FinishMap = new Rectangle(199, 272, 94, 30);
        internal static readonly Rectangle FinishStage = new Rectangle(199, 328, 94, 30);
        internal static readonly Rectangle TaskId = new Rectangle(372, 163, 75, 24);
        internal static readonly Rectangle GrantTask = new Rectangle(464, 158, 108, 31);
        internal static readonly Rectangle UnlockStages = new Rectangle(464, 215, 108, 31);

        internal static readonly Rectangle UnitFirst = new Rectangle(194, 379, 22, 23);
        internal static readonly Rectangle UnitPrevious = new Rectangle(224, 379, 22, 23);
        internal static readonly Rectangle UnitNext = new Rectangle(284, 379, 22, 23);
        internal static readonly Rectangle UnitLast = new Rectangle(314, 379, 22, 23);
        internal static readonly Rectangle UnitGrid = new Rectangle(183, 139, 171, 225);
        internal static readonly Rectangle UnitFrame = new Rectangle(382, 138, 231, 138);
        internal static readonly Rectangle UnitLevel = new Rectangle(428, 326, 35, 22);
        internal static readonly Rectangle UnitCount = new Rectangle(429, 347, 35, 22);
        internal static readonly Rectangle UnitLevelMinus = new Rectangle(415, 325, 20, 20);
        internal static readonly Rectangle UnitLevelPlus = new Rectangle(480, 327, 20, 20);
        internal static readonly Rectangle UnitCountMinus = new Rectangle(415, 346, 20, 20);
        internal static readonly Rectangle UnitCountPlus = new Rectangle(480, 348, 20, 20);
        internal static readonly Rectangle UnitHostile = new Rectangle(519, 306, 12, 12);
        internal static readonly Rectangle UnitSpawn = new Rectangle(506, 329, 108, 31);
        internal static readonly Rectangle UnitMerc = new Rectangle(506, 375, 108, 31);
        internal static readonly Rectangle UnitPageState = new Rectangle(316, 381, 48, 20);
        internal static readonly Rectangle Reconcile = new Rectangle(704, 403, 42, 18);
        internal const int UnitRowHeight = 28;
        internal const int UnitRowsPerPage = 8;

        internal static float ScaleFor(Size client)
        {
            float availableWidth = Math.Max(1f, client.Width - Inset * 2f);
            float availableHeight = Math.Max(1f, client.Height - Inset * 2f);
            return Math.Min(availableWidth / Width, availableHeight / Height);
        }

        internal static PointF OffsetFor(Size client, float scale)
        {
            return new PointF(
                (client.Width - Width * scale) / 2f,
                (client.Height - Height * scale) / 2f);
        }

        internal static Rectangle ToClient(Rectangle logical, Size client)
        {
            float scale = ScaleFor(client);
            PointF offset = OffsetFor(client, scale);
            return new Rectangle(
                (int)Math.Round(offset.X + logical.X * scale),
                (int)Math.Round(offset.Y + logical.Y * scale),
                Math.Max(1, (int)Math.Round(logical.Width * scale)),
                Math.Max(1, (int)Math.Round(logical.Height * scale)));
        }

        internal static Point ToLogical(Point client, Size size)
        {
            float scale = ScaleFor(size);
            PointF offset = OffsetFor(size, scale);
            return new Point(
                (int)Math.Floor((client.X - offset.X) / scale),
                (int)Math.Floor((client.Y - offset.Y) / scale));
        }

        internal static Rectangle ItemCell(int index)
        {
            int column = index % ItemColumns;
            int row = index / ItemColumns;
            return new Rectangle(
                ItemGrid.Left + column * ItemCellSize,
                ItemGrid.Top + row * ItemCellSize,
                ItemCellSize,
                ItemCellSize);
        }

        internal static int ItemIndexAt(Point logical)
        {
            if (!ItemGrid.Contains(logical)) return -1;
            int column = (logical.X - ItemGrid.Left) / ItemCellSize;
            int row = (logical.Y - ItemGrid.Top) / ItemCellSize;
            if (column < 0 || column >= ItemColumns || row < 0 || row >= ItemRows) return -1;
            return row * ItemColumns + column;
        }

        internal static Rectangle UnitRow(int index)
        {
            return new Rectangle(
                UnitGrid.Left,
                UnitGrid.Top + index * UnitRowHeight,
                UnitGrid.Width,
                UnitRowHeight);
        }

        internal static int UnitIndexAt(Point logical)
        {
            if (!UnitGrid.Contains(logical)) return -1;
            int index = (logical.Y - UnitGrid.Top) / UnitRowHeight;
            return index >= 0 && index < UnitRowsPerPage ? index : -1;
        }

        internal static string TabAt(Point logical)
        {
            if (EconomyTab.Contains(logical)) return "economy";
            if (ItemsTab.Contains(logical)) return "items";
            if (LevelTab.Contains(logical)) return "level";
            if (UnitsTab.Contains(logical)) return "units";
            return null;
        }
    }
}
