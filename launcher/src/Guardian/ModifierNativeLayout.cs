using System;
using System.Drawing;

namespace CF7Launcher.Guardian
{
    internal static class ModifierNativeLayout
    {
        internal const int Width = 843;
        internal const int Height = 400;
        internal const int Inset = 2;

        internal static readonly Rectangle EconomyTab = new Rectangle(0, 132, 169, 34);
        internal static readonly Rectangle ItemsTab = new Rectangle(0, 182, 169, 34);
        internal static readonly Rectangle LevelTab = new Rectangle(0, 232, 169, 34);
        internal static readonly Rectangle UnitsTab = new Rectangle(0, 282, 169, 34);
        internal static readonly Rectangle Close = new Rectangle(618, 4, 34, 34);

        internal static readonly Rectangle Money = new Rectangle(200, 133, 122, 30);
        internal static readonly Rectangle KCoin = new Rectangle(200, 188, 122, 30);
        internal static readonly Rectangle TestSpace = new Rectangle(200, 270, 122, 30);

        internal static readonly Rectangle ItemFirst = new Rectangle(200, 348, 24, 24);
        internal static readonly Rectangle ItemPrevious = new Rectangle(232, 348, 24, 24);
        internal static readonly Rectangle ItemNext = new Rectangle(300, 348, 24, 24);
        internal static readonly Rectangle ItemLast = new Rectangle(332, 348, 24, 24);
        internal static readonly Rectangle ItemQuery = new Rectangle(430, 292, 150, 20);
        internal static readonly Rectangle ItemQuantity = new Rectangle(446, 226, 45, 18);
        internal static readonly Rectangle ItemMinus = new Rectangle(536, 224, 24, 24);
        internal static readonly Rectangle ItemPlus = new Rectangle(576, 224, 24, 24);
        internal static readonly Rectangle ItemProduce = new Rectangle(436, 258, 90, 27);
        internal static readonly Rectangle ItemSearch = new Rectangle(436, 303, 90, 27);
        internal static readonly Rectangle ItemGrid = new Rectangle(180, 113, 224, 224);
        internal const int ItemCellSize = 28;
        internal const int ItemColumns = 8;
        internal const int ItemRows = 8;

        internal static readonly Rectangle KillAll = new Rectangle(195, 130, 100, 28);
        internal static readonly Rectangle FinishWave = new Rectangle(195, 175, 100, 28);
        internal static readonly Rectangle FinishMap = new Rectangle(195, 220, 100, 28);
        internal static readonly Rectangle FinishStage = new Rectangle(195, 270, 100, 28);
        internal static readonly Rectangle TaskId = new Rectangle(370, 131, 75, 18);
        internal static readonly Rectangle GrantTask = new Rectangle(460, 130, 106, 30);
        internal static readonly Rectangle UnlockStages = new Rectangle(460, 175, 106, 30);

        internal static readonly Rectangle UnitFirst = new Rectangle(200, 348, 24, 24);
        internal static readonly Rectangle UnitPrevious = new Rectangle(232, 348, 24, 24);
        internal static readonly Rectangle UnitNext = new Rectangle(300, 348, 24, 24);
        internal static readonly Rectangle UnitLast = new Rectangle(332, 348, 24, 24);
        internal static readonly Rectangle UnitGrid = new Rectangle(180, 104, 184, 224);
        internal static readonly Rectangle UnitFrame = new Rectangle(380, 50, 165, 190);
        internal static readonly Rectangle UnitLevel = new Rectangle(425, 290, 35, 17);
        internal static readonly Rectangle UnitCount = new Rectangle(425, 311, 35, 17);
        internal static readonly Rectangle UnitLevelMinus = new Rectangle(412, 288, 20, 20);
        internal static readonly Rectangle UnitLevelPlus = new Rectangle(476, 288, 20, 20);
        internal static readonly Rectangle UnitCountMinus = new Rectangle(412, 309, 20, 20);
        internal static readonly Rectangle UnitCountPlus = new Rectangle(476, 309, 20, 20);
        internal static readonly Rectangle UnitHostile = new Rectangle(535, 254, 12, 12);
        internal static readonly Rectangle UnitSpawn = new Rectangle(505, 260, 106, 27);
        internal static readonly Rectangle UnitMerc = new Rectangle(505, 305, 106, 27);
        internal static readonly Rectangle UnitPageState = new Rectangle(350, 348, 130, 20);
        internal static readonly Rectangle Reconcile = new Rectangle(704, 374, 42, 18);
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
