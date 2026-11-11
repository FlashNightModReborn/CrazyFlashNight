using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Xunit;

namespace Launcher.Tests.Guardian
{
    public sealed class ModifierNativeLayoutTests
    {
        [Fact]
        public void NativeSurfacePaintsWithoutAWebView()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            string webRoot = Path.Combine(repository.FullName, "launcher", "web");
            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner, webRoot, "owned", task);
            surface.PrepareAsync().GetAwaiter().GetResult();
            surface.ClientSize = new Size(1016, 550);
            using var bitmap = surface.RenderFrame();
            Assert.Equal(1016, bitmap.Width);
            Assert.Equal(550, bitmap.Height);
            Assert.Equal(0, bitmap.GetPixel(0, 0).A);
            Assert.Equal(204, bitmap.GetPixel(500, 300).A);
        }

        [Fact]
        public void SurfaceUsesTheNativeDesignSizeAtEveryClientSize()
        {
            var client = new Size(1016, 550);
            float scale = ModifierNativeLayout.ScaleFor(client);
            Assert.InRange(scale, 1.19f, 1.21f);
            PointF offset = ModifierNativeLayout.OffsetFor(client, scale);
            Assert.InRange(offset.X, 3.0f, 4.0f);
            Assert.InRange(offset.Y, 1.5f, 2.6f);
        }

        [Fact]
        public void LogicalAndClientCoordinatesRoundTrip()
        {
            var client = new Size(1016, 550);
            Rectangle source = ModifierNativeLayout.ItemCell(17);
            Point center = new Point(source.X + source.Width / 2, source.Y + source.Height / 2);
            Rectangle clientCell = ModifierNativeLayout.ToClient(source, client);
            Point logical = ModifierNativeLayout.ToLogical(
                new Point(clientCell.X + clientCell.Width / 2, clientCell.Y + clientCell.Height / 2), client);
            Assert.InRange(logical.X, center.X - 2, center.X + 2);
            Assert.InRange(logical.Y, center.Y - 2, center.Y + 2);
        }

        [Fact]
        public void ItemGridResolvesExactlyTheEightByEightSurface()
        {
            Assert.Equal(0, ModifierNativeLayout.ItemIndexAt(new Point(179, 145)));
            Assert.Equal(7, ModifierNativeLayout.ItemIndexAt(new Point(179 + 7 * 28, 145)));
            Assert.Equal(56, ModifierNativeLayout.ItemIndexAt(new Point(179, 145 + 7 * 28)));
            Assert.Equal(63, ModifierNativeLayout.ItemIndexAt(new Point(179 + 7 * 28, 145 + 7 * 28)));
            Assert.Equal(-1, ModifierNativeLayout.ItemIndexAt(new Point(403, 145)));
            Assert.Equal(-1, ModifierNativeLayout.ItemIndexAt(new Point(179, 369)));
        }

        [Fact]
        public void UnitRowsResolveExactlyEightRows()
        {
            Assert.Equal(0, ModifierNativeLayout.UnitIndexAt(new Point(183, 139)));
            Assert.Equal(7, ModifierNativeLayout.UnitIndexAt(new Point(183, 139 + 7 * 28)));
            Assert.Equal(-1, ModifierNativeLayout.UnitIndexAt(new Point(183, 139 + 8 * 28)));
            Assert.Equal(-1, ModifierNativeLayout.UnitIndexAt(new Point(354, 139)));
        }

        [Fact]
        public void EveryVisibleTabHasAnExactHitRegion()
        {
            Assert.Equal("economy", ModifierNativeLayout.TabAt(new Point(80, 170)));
            Assert.Equal("items", ModifierNativeLayout.TabAt(new Point(80, 225)));
            Assert.Equal("level", ModifierNativeLayout.TabAt(new Point(80, 280)));
            Assert.Equal("units", ModifierNativeLayout.TabAt(new Point(80, 335)));
            Assert.Null(ModifierNativeLayout.TabAt(new Point(180, 170)));
        }

        [Fact]
        public void PaginationFallbacksMatchTheDrawnArtRects()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            var art = new ModifierArtCatalog(Path.Combine(repository.FullName, "launcher", "web"));
            AssertNav(art, "items", "item_first", ModifierNativeLayout.ItemFirst);
            AssertNav(art, "items", "item_prev", ModifierNativeLayout.ItemPrevious);
            AssertNav(art, "items", "item_next", ModifierNativeLayout.ItemNext);
            AssertNav(art, "items", "item_last", ModifierNativeLayout.ItemLast);
            AssertNav(art, "units", "unit_first", ModifierNativeLayout.UnitFirst);
            AssertNav(art, "units", "unit_prev", ModifierNativeLayout.UnitPrevious);
            AssertNav(art, "units", "unit_next", ModifierNativeLayout.UnitNext);
            AssertNav(art, "units", "unit_last", ModifierNativeLayout.UnitLast);
        }

        [Fact]
        public void PageClampingKeepsTypedPagesInsideTheAvailableRange()
        {
            Assert.Equal(0, ModifierNativeLayout.PageCount(0, 64));
            Assert.Equal(4, ModifierNativeLayout.PageCount(200, 64));
            Assert.Equal(1, ModifierNativeLayout.ClampPage(1, 200, 64));
            Assert.Equal(2, ModifierNativeLayout.ClampPage(2, 200, 64));
            Assert.Equal(4, ModifierNativeLayout.ClampPage(99, 200, 64));
            Assert.Equal(1, ModifierNativeLayout.ClampPage(0, 200, 64));
            Assert.Equal(1, ModifierNativeLayout.ClampPage(-5, 0, 64));
            Assert.Equal(1, ModifierNativeLayout.ClampPage(99, 0, 64));
        }

        [Fact]
        public void PageInputsSitOutsideTheNavigationButtonArt()
        {
            Assert.True(ModifierNativeLayout.ItemPage.Left >= ModifierNativeLayout.ItemLast.Right);
            Assert.True(ModifierNativeLayout.ItemPageLabel.Right <= ModifierNativeLayout.ItemPage.Left);
            Assert.True(ModifierNativeLayout.ItemPage.Right <= ModifierNativeLayout.ItemPageTotal.Left);
            Assert.True(ModifierNativeLayout.UnitPage.Left >= ModifierNativeLayout.UnitLast.Right);
            Assert.True(ModifierNativeLayout.UnitPageLabel.Right <= ModifierNativeLayout.UnitPage.Left);
            Assert.True(ModifierNativeLayout.UnitPage.Right <= ModifierNativeLayout.UnitPageTotal.Left);
            Assert.True(ModifierNativeLayout.ItemPageTotal.Right <= ModifierNativeLayout.Width);
            Assert.True(ModifierNativeLayout.UnitPageTotal.Right <= ModifierNativeLayout.Width);
        }

        private static void AssertNav(ModifierArtCatalog art, string page, string action, Rectangle expected)
        {
            RectangleF asset = art.AssetRect(page, action);
            Assert.False(asset.IsEmpty);
            Assert.InRange(Math.Abs(asset.Left - expected.Left), 0f, 1.5f);
            Assert.InRange(Math.Abs(asset.Top - expected.Top), 0f, 1.5f);
            Assert.InRange(Math.Abs(asset.Width - expected.Width), 0f, 1.5f);
            Assert.InRange(Math.Abs(asset.Height - expected.Height), 0f, 1.5f);
        }

        [Fact]
        public void ArtCatalogSeparatesButtonImagesFromTheirSourceHitRects()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            string webRoot = Path.Combine(repository.FullName, "launcher", "web");
            var art = new ModifierArtCatalog(webRoot);
            RectangleF moneyImage = art.AssetRect("economy", "money");
            RectangleF moneyHit = art.HitRect("economy", "money");
            Assert.False(moneyImage.IsEmpty);
            Assert.False(moneyHit.IsEmpty);
            Assert.NotEqual(moneyImage, moneyHit);
            Assert.True(moneyHit.Contains(moneyHit.X + moneyHit.Width / 2, moneyHit.Y + moneyHit.Height / 2));
            Assert.EndsWith("tab-economy-over.png", art.ButtonImage("economy", "tab:economy", false, false));
            Assert.True(art.ButtonFlipX("units", "unit_prev"));
            Assert.False(art.ButtonFlipX("units", "unit_next"));
            Assert.True(art.AssetRect("economy", "tab:items").Left >= 0);
            Assert.True(art.UnitFrameMask.Bottom <= ModifierNativeLayout.Height);
            for (int i = 0; i < 8; i++) Assert.False(art.UnitRow(i).IsEmpty);
            using var background = new Bitmap(art.Background("economy"));
            Assert.Equal(204, background.GetPixel(400, 200).A);
            using var items = new Bitmap(art.Background("items"));
            Color guide = items.GetPixel(193, 145);
            Assert.False(guide.R > 150 && guide.G > 150 && guide.B < 100);
            using var tab = new Bitmap(art.ButtonImage("economy", "tab:economy", false, false));
            bool opaqueWhite = false;
            for (int y = 0; y < tab.Height && !opaqueWhite; y++)
                for (int x = 0; x < tab.Width; x++)
                    if (tab.GetPixel(x, y).A == 255) { opaqueWhite = true; break; }
            Assert.True(opaqueWhite);
        }
    }
}
