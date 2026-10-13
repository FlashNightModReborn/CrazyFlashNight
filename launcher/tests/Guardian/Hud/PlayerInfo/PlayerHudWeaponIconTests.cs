using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudWeaponIconTests
{
    [Fact]
    public void LegacyAndExtendedCombatSnapshotsRemainAtomicAcrossEquipmentReplacement()
    {
        var state = new PlayerHudState(); var data = PlayerHudStateTests.Full();
        Assert.True(state.Receive(PlayerHudStateTests.Encode(data), 1));
        Assert.Equal("", state.Snapshot!.Combat.WeaponItemIconKey);
        data["seq"] = 2;
        var weapon = (JObject)data["groups"]!["combat"]!["weapon"]!;
        weapon["iconKey"] = "专用图"; weapon["itemIconKey"] = "装备图A"; weapon["sourceItem"] = "装备A";
        Assert.True(state.Receive(PlayerHudStateTests.Encode(data), 2));
        var first = state.Snapshot;
        Assert.Equal("专用图", first!.Combat.WeaponIconKey);
        data["seq"] = 3; weapon["itemIconKey"] = "装备图B"; weapon["sourceItem"] = "装备B";
        Assert.True(state.Receive(PlayerHudStateTests.Encode(data), 3));
        Assert.Equal("装备图B", state.Snapshot!.Combat.WeaponItemIconKey);
        Assert.Equal("装备图A", first.Combat.WeaponItemIconKey);
        data["seq"] = 4; weapon["iconKey"] = new string('x', 129);
        var before = state.Snapshot;
        Assert.False(state.Receive(PlayerHudStateTests.Encode(data), 4)); Assert.Same(before, state.Snapshot);
    }

    [Fact]
    public void DedicatedIconWinsAndMissingDedicatedIconUsesCachedItemIcon()
    {
        WithCatalog((directory, cache) =>
        {
            var dedicated = cache.GetWeapon("专用", "装备", 32);
            Assert.Same(cache.Get("专用", 32), dedicated);
            var outline = cache.GetWeapon("missing", "装备", 32);
            Assert.NotNull(outline);
            Assert.Same(outline, cache.GetWeapon("", "图标-装备", 32));
            Assert.NotSame(outline, cache.GetWeapon("", "装备", 64));
            var visible = 0;
            for (var y = 0; y < outline!.Height; y++) for (var x = 0; x < outline.Width; x++)
            {
                var color = outline.GetPixel(x, y); if (color.A < 16) continue;
                visible++; Assert.InRange(Math.Abs(color.R - color.G), 0, 1); Assert.InRange(Math.Abs(color.G - color.B), 0, 1);
            }
            Assert.InRange(visible, 35, 450);
            Assert.Equal(0, outline.GetPixel(0, 0).A);
        });
    }

    [Fact]
    public void ItemIconKeepsItsAuthoredOffCenterCloseupInsteadOfTheFullTexture()
    {
        WithCatalog((directory, cache) =>
        {
            var glyph = cache.GetWeapon("", "装备", 32);
            Assert.NotNull(glyph);
            var left = 0; var right = 0;
            for (var y = 0; y < 32; y++) for (var x = 0; x < 32; x++)
                if (glyph!.GetPixel(x, y).A >= 128)
                {
                    if (x < 14) left++;
                    if (x >= 22) right++;
                }
            Assert.True(left > 35, "The item close-up must keep its left-hand placement and vertical shape.");
            Assert.Equal(0, right);
        });
    }

    [Fact]
    public void MissingOrCorruptItemIconDoesNotSilentlyUseTheFullWorldTexture()
    {
        WithCatalog((directory, cache) =>
        {
            Assert.Null(cache.GetWeapon("", "textureOnly", 32));
            Assert.Null(cache.GetWeapon("", "corruptItem", 32));
        });
    }

    [Theory]
    [InlineData(153, 0, 0)]
    [InlineData(0, 153, 0)]
    [InlineData(153, 153, 153)]
    public void QualityFrameAndOpaqueGradientDoNotBecomeTheBattleSkillShape(int red, int green, int blue)
    {
        using var framed = FramedItem(Color.FromArgb(red, green, blue));
        using var glyph = PlayerHudEquipmentOutline.Create(framed, 32);
        Assert.NotNull(glyph);
        var body = 0; var border = 0;
        for (var y = 0; y < 32; y++) for (var x = 0; x < 32; x++) if (glyph!.GetPixel(x, y).A >= 128)
        {
            if (x < 7 || x >= 25 || y < 5 || y >= 29) border++;
            else body++;
        }
        Assert.True(body > 35, "The upright item should survive the frame/background separation.");
        Assert.Equal(0, border);
    }

    [Fact]
    public void FrameAroundUnrelatedOpaqueArtDoesNotSupplyAFalseSilhouette()
    {
        using var framed = new Bitmap(128, 128);
        using (var g = Graphics.FromImage(framed))
        {
            g.Clear(Color.Red);
            using var art = new System.Drawing.Drawing2D.LinearGradientBrush(new Rectangle(4, 4, 120, 120),
                Color.Navy, Color.Orange, 0f);
            g.FillRectangle(art, 4, 4, 120, 120);
        }
        Assert.Null(PlayerHudEquipmentOutline.Create(framed, 32));
    }

    [Fact]
    public void UnknownOrOpaqueEquipmentSourceFallsBackToGenericWithoutInventingRectangleGeometry()
    {
        WithCatalog((directory, cache) =>
        {
            Assert.Null(cache.GetWeapon("", "unknown", 32));
            Assert.Null(cache.GetWeapon("", "opaque", 32));
            Assert.Null(cache.GetWeapon("", "", 32));
        });
    }

    [Fact]
    public void CorruptDedicatedAssetFallsBackToEquipmentAndCachesTheFailure()
    {
        WithCatalog((directory, cache) =>
        {
            var first = cache.GetWeapon("corrupt", "装备", 32);
            Assert.NotNull(first); Assert.Same(first, cache.GetWeapon("corrupt", "装备", 32));
        });
    }

    [Theory]
    [InlineData(16)]
    [InlineData(24)]
    [InlineData(48)]
    public void SmallSilhouetteRetainsThinPartsAndRejectsSoftShadowFootprint(int pixels)
    {
        using var source = Equipment(); using var glyph = PlayerHudEquipmentOutline.Create(source, pixels);
        Assert.NotNull(glyph); Assert.Equal(pixels, glyph!.Width);
        var bright = 0;
        for (var y = 0; y < pixels; y++) for (var x = 0; x < pixels; x++)
            if (glyph.GetPixel(x, y).A >= 128) bright++;
        Assert.InRange(bright, pixels / 2, pixels * pixels / 2);
        Assert.Equal(0, glyph.GetPixel(1, 1).A);
    }

    private static Bitmap Equipment()
    {
        var bitmap = new Bitmap(128, 128, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bitmap);
        g.Clear(Color.Transparent);
        using var shadow = new SolidBrush(Color.FromArgb(230, 0, 0, 0)); g.FillEllipse(shadow, 1, 1, 126, 126);
        using var body = new SolidBrush(Color.FromArgb(255, 60, 100, 80));
        g.FillRectangle(body, 10, 57, 106, 4); g.FillRectangle(body, 32, 49, 34, 17); g.FillRectangle(body, 60, 62, 6, 16);
        return bitmap;
    }
    [Fact]
    public void DarkOpaqueArtworkSurvivesTheRemovalOfAnAlmostOpaqueOvalMatte()
    {
        using var source = new Bitmap(128, 128, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(source))
        {
            g.Clear(Color.Transparent);
            using var matte = new SolidBrush(Color.FromArgb(245, 0, 0, 0)); g.FillEllipse(matte, 1, 1, 126, 126);
            using var ink = new SolidBrush(Color.FromArgb(255, 2, 2, 2)); g.FillRectangle(ink, 48, 25, 28, 80);
        }
        using var glyph = PlayerHudEquipmentOutline.Create(source, 32);
        Assert.NotNull(glyph); var body = 0; var oval = 0;
        for (var y = 0; y < 32; y++) for (var x = 0; x < 32; x++) if (glyph!.GetPixel(x, y).A >= 128)
        {
            if (x < 11 || x > 21) oval++;
            else body++;
        }
        Assert.True(body > 25); Assert.Equal(0, oval);
    }
    [Theory]
    [InlineData(24)]
    [InlineData(38)]
    [InlineData(64)]
    public void AuthoredKeyboardScytheItemIconDoesNotOutlineItsOvalDropShadow(int pixels)
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root != null && !File.Exists(Path.Combine(root.FullName, "fonts", "fonts.xml"))) root = root.Parent;
        Assert.NotNull(root);
        using var cache = new PlayerHudIconCache(Path.Combine(root!.FullName, "launcher", "web", "icons"));
        var glyph = cache.GetWeapon("", "键盘镰刀", pixels);
        Assert.NotNull(glyph);
        // (24,64) in the authored 128px f1 lies on the old oval, outside the item.
        var x = (int)Math.Round(2.5 + 24 * (pixels - 5) / 128.0);
        var y = (int)Math.Round(2.5 + 64 * (pixels - 5) / 128.0);
        Assert.InRange(glyph!.GetPixel(x, y).A, 0, 20);
        var strokes = 0;
        for (var py = 0; py < pixels; py++) for (var px = 0; px < pixels; px++)
            if (glyph.GetPixel(px, py).A >= 128) strokes++;
        Assert.True(strokes > pixels, "The scythe and key strokes must survive matte removal.");
    }
    private static Bitmap ItemIcon()
    {
        var bitmap = new Bitmap(128, 128, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bitmap); g.Clear(Color.Transparent);
        using var body = new SolidBrush(Color.FromArgb(255, 90, 120, 75));
        g.FillRectangle(body, 14, 15, 28, 95);
        return bitmap;
    }
    private static Bitmap FramedItem(Color frame)
    {
        var bitmap = new Bitmap(128, 128, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bitmap); g.Clear(frame);
        using var background = new System.Drawing.Drawing2D.LinearGradientBrush(new Rectangle(4, 4, 120, 120),
            Color.FromArgb(54, 54, 54), Color.FromArgb(8, 8, 8), 90f);
        g.FillRectangle(background, 4, 4, 120, 120);
        using var body = new SolidBrush(Color.FromArgb(160, 170, 180));
        g.FillRectangle(body, 36, 24, 48, 80);
        using var detail = new SolidBrush(Color.Black); g.FillRectangle(detail, 52, 47, 12, 12);
        return bitmap;
    }
    private static void WithCatalog(Action<string, PlayerHudIconCache> action)
    {
        var temporaryRoot = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var directory = Path.GetFullPath(Path.Combine(temporaryRoot, "cf7-weapon-icon-" + Guid.NewGuid().ToString("N")));
        Assert.True(directory.StartsWith(temporaryRoot, StringComparison.OrdinalIgnoreCase));
        Directory.CreateDirectory(directory);
        try
        {
            using (var equipment = Equipment()) equipment.Save(Path.Combine(directory, "gear.png"), ImageFormat.Png);
            using (var item = ItemIcon()) item.Save(Path.Combine(directory, "item.png"), ImageFormat.Png);
            using (var dedicated = new Bitmap(32, 32))
            {
                using var g = Graphics.FromImage(dedicated); g.Clear(Color.CornflowerBlue);
                dedicated.Save(Path.Combine(directory, "dedicated.png"), ImageFormat.Png);
            }
            File.WriteAllText(Path.Combine(directory, "manifest.json"), new JObject
            {
                ["装备"] = new JObject { ["f1"] = "item.png", ["f2"] = "gear.png" },
                ["textureOnly"] = new JObject { ["f2"] = "gear.png" },
                ["corruptItem"] = new JObject { ["f1"] = "corrupt.png", ["f2"] = "gear.png" },
                ["专用"] = new JObject { ["f1"] = "dedicated.png" },
                ["corrupt"] = new JObject { ["f1"] = "corrupt.png" },
                ["opaque"] = new JObject { ["f1"] = "dedicated.png" }
            }.ToString());
            File.WriteAllText(Path.Combine(directory, "corrupt.png"), "invalid image bytes");
            using var cache = new PlayerHudIconCache(directory); action(directory, cache);
        }
        finally { Directory.Delete(directory, true); }
    }
}
