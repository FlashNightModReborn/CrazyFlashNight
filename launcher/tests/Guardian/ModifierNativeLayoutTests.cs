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
            string webRoot = Path.Combine(Directory.GetCurrentDirectory(), "launcher", "web");
            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner, webRoot, "owned", task);
            surface.PrepareAsync().GetAwaiter().GetResult();
            surface.ClientSize = new Size(1016, 484);
            using var bitmap = new Bitmap(1016, 484);
            surface.DrawToBitmap(bitmap, new Rectangle(0, 0, 1016, 484));
            Assert.Equal(1016, bitmap.Width);
            Assert.Equal(484, bitmap.Height);
        }

        [Fact]
        public void SurfaceUsesTheNativeDesignSizeAtEveryClientSize()
        {
            var client = new Size(1016, 484);
            float scale = ModifierNativeLayout.ScaleFor(client);
            Assert.InRange(scale, 1.19f, 1.21f);
            PointF offset = ModifierNativeLayout.OffsetFor(client, scale);
            Assert.InRange(offset.X, 1.9f, 2.6f);
            Assert.InRange(offset.Y, 1.5f, 2.6f);
        }

        [Fact]
        public void LogicalAndClientCoordinatesRoundTrip()
        {
            var client = new Size(1016, 484);
            Rectangle source = ModifierNativeLayout.ItemCell(17);
            Point center = new Point(source.X + source.Width / 2, source.Y + source.Height / 2);
            Rectangle clientCell = ModifierNativeLayout.ToClient(source, client);
            Point logical = ModifierNativeLayout.ToLogical(
                new Point(clientCell.X + clientCell.Width / 2, clientCell.Y + clientCell.Height / 2), client);
            Assert.InRange(logical.X, center.X - 1, center.X + 1);
            Assert.InRange(logical.Y, center.Y - 1, center.Y + 1);
        }

        [Fact]
        public void ItemGridResolvesExactlyTheEightByEightSurface()
        {
            Assert.Equal(0, ModifierNativeLayout.ItemIndexAt(new Point(180, 113)));
            Assert.Equal(7, ModifierNativeLayout.ItemIndexAt(new Point(180 + 7 * 28, 113)));
            Assert.Equal(56, ModifierNativeLayout.ItemIndexAt(new Point(180, 113 + 7 * 28)));
            Assert.Equal(63, ModifierNativeLayout.ItemIndexAt(new Point(180 + 7 * 28, 113 + 7 * 28)));
            Assert.Equal(-1, ModifierNativeLayout.ItemIndexAt(new Point(404, 113)));
            Assert.Equal(-1, ModifierNativeLayout.ItemIndexAt(new Point(180, 337)));
        }

        [Fact]
        public void UnitRowsResolveExactlyEightRows()
        {
            Assert.Equal(0, ModifierNativeLayout.UnitIndexAt(new Point(180, 104)));
            Assert.Equal(7, ModifierNativeLayout.UnitIndexAt(new Point(180, 104 + 7 * 28)));
            Assert.Equal(-1, ModifierNativeLayout.UnitIndexAt(new Point(180, 104 + 8 * 28)));
            Assert.Equal(-1, ModifierNativeLayout.UnitIndexAt(new Point(364, 104)));
        }

        [Fact]
        public void EveryVisibleTabHasAnExactHitRegion()
        {
            Assert.Equal("economy", ModifierNativeLayout.TabAt(new Point(80, 145)));
            Assert.Equal("items", ModifierNativeLayout.TabAt(new Point(80, 195)));
            Assert.Equal("level", ModifierNativeLayout.TabAt(new Point(80, 245)));
            Assert.Equal("units", ModifierNativeLayout.TabAt(new Point(80, 295)));
            Assert.Null(ModifierNativeLayout.TabAt(new Point(180, 145)));
        }
    }
}
