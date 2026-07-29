#nullable enable

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Linq;
using System.Security.Cryptography;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoFrameCompositorTests
{
    [Fact]
    public void CompositionRecipe_FreezesActiveEffectAndSourceDerivedTextGeometry()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);

        PlayerInfoCompositionRecipe.ValidateEffectPolicy(assets.EffectPolicy);
        Assert.Equal(
            new[]
            {
                new PlayerInfoTextLayout(
                    "mp-label",
                    PlayerInfoPathGlyphAtlas.Aero,
                    15.9744f,
                    2.8f,
                    18.55f,
                    PlayerInfoPathTextAlignment.Left,
                    0f,
                    0f,
                    null),
                new PlayerInfoTextLayout(
                    "mp-percent",
                    PlayerInfoPathGlyphAtlas.Aero,
                    11.9808f,
                    -2.15f,
                    30.5f,
                    PlayerInfoPathTextAlignment.Left,
                    0f,
                    0f,
                    null),
                new PlayerInfoTextLayout(
                    "mp-current",
                    PlayerInfoPathGlyphAtlas.Aero,
                    13.0048f,
                    74.55f,
                    17.85f,
                    PlayerInfoPathTextAlignment.Right,
                    0f,
                    0f,
                    null),
                new PlayerInfoTextLayout(
                    "mp-maximum",
                    PlayerInfoPathGlyphAtlas.Aero,
                    13.0048f,
                    80.65f,
                    17.85f,
                    PlayerInfoPathTextAlignment.Left,
                    0f,
                    0f,
                    null),
                new PlayerInfoTextLayout(
                    "mp-decorative-current",
                    PlayerInfoPathGlyphAtlas.Aero,
                    13.0048f,
                    74.55f,
                    18.05f,
                    PlayerInfoPathTextAlignment.Right,
                    0f,
                    0f,
                    null),
                new PlayerInfoTextLayout(
                    "mp-decorative-maximum",
                    PlayerInfoPathGlyphAtlas.Aero,
                    13.0048f,
                    80.65f,
                    18.05f,
                    PlayerInfoPathTextAlignment.Left,
                    0f,
                    0f,
                    null),
                new PlayerInfoTextLayout(
                    "hp-percent",
                    PlayerInfoPathGlyphAtlas.LcdStd,
                    19.968f,
                    13.45f,
                    -4.5f,
                    PlayerInfoPathTextAlignment.Right,
                    1f,
                    1.5f,
                    new SKColor(255, 0, 0, 255)),
                new PlayerInfoTextLayout(
                    "hp-maximum",
                    PlayerInfoPathGlyphAtlas.LcdStd,
                    11.9808f,
                    8.975f,
                    19.95f,
                    PlayerInfoPathTextAlignment.Center,
                    1f,
                    1.5f,
                    new SKColor(255, 0, 0, 255)),
                new PlayerInfoTextLayout(
                    "hp-current",
                    PlayerInfoPathGlyphAtlas.LcdStd,
                    11.9808f,
                    -5.775f,
                    7.7f,
                    PlayerInfoPathTextAlignment.Center,
                    1f,
                    1.5f,
                    new SKColor(255, 0, 0, 255))
            },
            PlayerInfoCompositionRecipe.TextLayouts);

        using var atlas = new PlayerInfoPathGlyphAtlas();
        foreach (PlayerInfoTextLayout layout in
                 PlayerInfoCompositionRecipe.TextLayouts)
        {
            string sample = layout.Id == "mp-label"
                ? "MP"
                : layout.Id.StartsWith(
                    "mp-decorative-",
                    StringComparison.Ordinal)
                    ? "00000"
                    : "99999";
            using SKPath path = atlas.BuildTextPath(
                layout.FontId,
                sample,
                layout.FontPixels,
                layout.AnchorX,
                layout.BaselineY,
                layout.Alignment);
            Assert.False(path.IsEmpty);
            Assert.True(float.IsFinite(path.Bounds.Left));
            Assert.True(float.IsFinite(path.Bounds.Top));
            Assert.InRange(path.Bounds.Width, 1f, 100f);
            Assert.InRange(path.Bounds.Height, 1f, 30f);
            Assert.InRange(
                path.Bounds.Top,
                layout.BaselineY - (layout.FontPixels * 1.5f),
                layout.BaselineY + 1f);
            Assert.InRange(
                path.Bounds.Bottom,
                layout.BaselineY - (layout.FontPixels * 0.5f),
                layout.BaselineY + (layout.FontPixels * 0.5f));
        }

        Assert.Equal(2, assets.EffectPolicy.ImplementedActiveLayers.Count);
        PlayerInfoProgrammaticEffect active =
            assets.EffectPolicy.ImplementedActiveLayers.Single(effect =>
                effect.Id == PlayerInfoCompositionRecipe.DynamicTextEffectId);
        var invalidPolicy = new PlayerInfoEffectPolicy(
            assets.EffectPolicy.IncludedStatic,
            assets.EffectPolicy.ProgrammaticLayers
                .Select(effect =>
                    effect.Id == active.Id
                        ? effect with
                        {
                            Disposition =
                                PlayerInfoProgrammaticEffectDisposition.DeferredB3
                        }
                        : effect)
                .ToArray());
        Assert.Throws<System.IO.InvalidDataException>(() =>
            PlayerInfoCompositionRecipe.ValidateEffectPolicy(invalidPolicy));
    }

    [Fact]
    public void CompositionRecipe_AppliesSourceRedGlowOnlyToHpText()
    {
        PlayerInfoTextLayout[] hpLayouts =
            PlayerInfoCompositionRecipe.TextLayouts
                .Where(layout =>
                    layout.Id.StartsWith("hp-", StringComparison.Ordinal))
                .ToArray();
        Assert.Equal(3, hpLayouts.Length);
        Assert.All(hpLayouts, layout =>
        {
            Assert.Equal(1f, layout.GlowSigmaPixels);
            Assert.Equal(1.5f, layout.GlowStrength);
            Assert.True(layout.GlowColor.HasValue);
            Assert.Equal(
                new SKColor(255, 0, 0, 255),
                layout.GlowColor.Value);
        });

        PlayerInfoTextLayout[] mpLayouts =
            PlayerInfoCompositionRecipe.TextLayouts
                .Where(layout =>
                    layout.Id.StartsWith("mp-", StringComparison.Ordinal))
                .ToArray();
        Assert.Equal(6, mpLayouts.Length);
        Assert.All(mpLayouts, layout =>
        {
            Assert.Equal(0f, layout.GlowSigmaPixels);
            Assert.Equal(0f, layout.GlowStrength);
            Assert.Null(layout.GlowColor);
        });
    }

    [Fact]
    public void FrozenFixtureMatrix_ComposesTightPArgbWithTypedMaskBoundaries()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assets,
            new Rectangle(0, 0, 1024, 576),
            monitorDpiScale: 1f);
        using PlayerInfoRasterBatch batch =
            new PlayerInfoSvgRasterizer().Bake(
                plan,
                System.Threading.CancellationToken.None);
        using var compositor = new PlayerInfoFrameCompositor(assets);

        var hashes = new HashSet<string>(StringComparer.Ordinal);
        foreach (string caseId in PlayerInfoFixtureInput.AllowedCaseIds)
        {
            var model = new PlayerInfoAnimationModel();
            Assert.True(model.ApplyFixture(
                PlayerInfoFixtureInput.FromCaseId(caseId)));
            Assert.True(model.VisualState.HasRenderableState);
            using var bitmap = NewDestination(plan);

            PlayerInfoFramePaintResult result = compositor.Paint(
                bitmap,
                batch,
                plan,
                model.VisualState);

            Assert.Equal(
                model.VisualState.Hp.CurrentVirtualFrame,
                result.HpVirtualFrame);
            Assert.Equal(
                model.VisualState.Mp.CurrentVirtualFrame,
                result.MpVirtualFrame);
            Assert.Equal(
                caseId == "empty" ? 0 : 1,
                result.MpLeftContourCount);
            Assert.Equal(
                ExpectedRightContours(result.MpVirtualFrame),
                result.MpRightContourCount);
            Assert.Equal(
                ExpectedRim(result.MpVirtualFrame),
                result.MpRimAssetId);
            Assert.Equal(
                ExpectedPaletteStart(result.MpVirtualFrame).ToString(),
                result.MpPaletteStart);
            Assert.True(CountNonTransparent(bitmap) > 100);
            int aboveChildStageHeight =
                plan.StagePhysicalBounds.Top -
                plan.TightPhysicalBounds.Top;
            Assert.True(aboveChildStageHeight > 0);
            Assert.True(
                CountNonTransparent(
                    bitmap,
                    new Rectangle(
                        0,
                        0,
                        bitmap.Width,
                        aboveChildStageHeight)) > 100,
                "The composed bitmap must retain the HP ball and text above the child authoring stage.");
            Assert.True(hashes.Add(HashBitmap(bitmap)));
        }

        Assert.Equal(PlayerInfoFixtureInput.AllowedCaseIds.Count, hashes.Count);
    }

    [Fact]
    public void Paint_RejectsIncompleteStateAndWrongDestinationContract()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assets,
            new Rectangle(0, 0, 1024, 576),
            monitorDpiScale: 1f);
        using PlayerInfoRasterBatch batch =
            new PlayerInfoSvgRasterizer().Bake(
                plan,
                System.Threading.CancellationToken.None);
        using var compositor = new PlayerInfoFrameCompositor(assets);
        var incomplete = new PlayerInfoAnimationModel();
        Assert.True(incomplete.ApplyFixture(
            new PlayerInfoFixtureInput(
                "empty",
                new PlayerInfoGaugeInput(0, 100),
                mp: null)));
        using var validDestination = NewDestination(plan);

        Assert.Throws<InvalidOperationException>(() =>
            compositor.Paint(
                validDestination,
                batch,
                plan,
                incomplete.VisualState));

        var complete = new PlayerInfoAnimationModel();
        complete.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("full"));
        using var wrongPixelFormat = new Bitmap(
            plan.TightPhysicalBounds.Width,
            plan.TightPhysicalBounds.Height,
            PixelFormat.Format32bppArgb);
        Assert.Throws<System.IO.InvalidDataException>(() =>
            compositor.Paint(
                wrongPixelFormat,
                batch,
                plan,
                complete.VisualState));
    }

    [Fact]
    public void Paint_IsDeterministicAndDoesNotMutateAtomicBatch()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assets,
            new Rectangle(0, 0, 1920, 1080),
            monitorDpiScale: 1.75f);
        using PlayerInfoRasterBatch batch =
            new PlayerInfoSvgRasterizer().Bake(
                plan,
                System.Threading.CancellationToken.None);
        var model = new PlayerInfoAnimationModel();
        model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("mp_vf35"));
        using var compositor = new PlayerInfoFrameCompositor(assets);
        string[] layerHashesBefore = batch.Layers
            .Select(layer => HashBitmap(layer.Bitmap))
            .ToArray();
        using var first = NewDestination(plan);
        using var second = NewDestination(plan);

        PlayerInfoFramePaintResult firstResult = compositor.Paint(
            first,
            batch,
            plan,
            model.VisualState);
        PlayerInfoFramePaintResult secondResult = compositor.Paint(
            second,
            batch,
            plan,
            model.VisualState);

        Assert.Equal(firstResult, secondResult);
        Assert.Equal(HashBitmap(first), HashBitmap(second));
        Assert.Equal(
            layerHashesBefore,
            batch.Layers.Select(layer => HashBitmap(layer.Bitmap)).ToArray());
    }

    [Fact]
    public void Compositor_DisposeIsIdempotentAndRejectsPaint()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assets,
            new Rectangle(0, 0, 1024, 576),
            monitorDpiScale: 1f);
        using PlayerInfoRasterBatch batch =
            new PlayerInfoSvgRasterizer().Bake(
                plan,
                System.Threading.CancellationToken.None);
        var model = new PlayerInfoAnimationModel();
        model.ApplyFixture(PlayerInfoFixtureInput.FromCaseId("full"));
        var compositor = new PlayerInfoFrameCompositor(assets);
        using var destination = NewDestination(plan);

        compositor.Dispose();
        compositor.Dispose();

        Assert.Throws<ObjectDisposedException>(() =>
            compositor.Paint(destination, batch, plan, model.VisualState));
    }

    private static Bitmap NewDestination(PlayerInfoRasterPlan plan) =>
        new(
            plan.TightPhysicalBounds.Width,
            plan.TightPhysicalBounds.Height,
            PixelFormat.Format32bppPArgb);

    private static int ExpectedRightContours(int virtualFrame) =>
        virtualFrame == 101 ? 0 : virtualFrame < 35 ? 2 : 1;

    private static string ExpectedRim(int virtualFrame) =>
        virtualFrame >= 91
            ? "mp.rim-vf91"
            : virtualFrame >= 70
                ? "mp.rim-vf70"
                : "mp.rim";

    private static int ExpectedPaletteStart(int virtualFrame) =>
        virtualFrame >= 91 ? 91 : virtualFrame >= 70 ? 70 : 1;

    private static int CountNonTransparent(Bitmap bitmap) =>
        CountNonTransparent(
            bitmap,
            new Rectangle(0, 0, bitmap.Width, bitmap.Height));

    private static int CountNonTransparent(
        Bitmap bitmap,
        Rectangle bounds)
    {
        Assert.True(
            new Rectangle(0, 0, bitmap.Width, bitmap.Height)
                .Contains(bounds));
        var count = 0;
        for (var y = bounds.Top; y < bounds.Bottom; y++)
        {
            for (var x = bounds.Left; x < bounds.Right; x++)
            {
                if (bitmap.GetPixel(x, y).A != 0)
                {
                    count++;
                }
            }
        }
        return count;
    }

    private static string HashBitmap(Bitmap bitmap)
    {
        BitmapData? locked = null;
        try
        {
            locked = bitmap.LockBits(
                new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                ImageLockMode.ReadOnly,
                bitmap.PixelFormat);
            int rowBytes = checked(bitmap.Width * 4);
            var bytes = new byte[checked(rowBytes * bitmap.Height)];
            for (var y = 0; y < bitmap.Height; y++)
            {
                System.Runtime.InteropServices.Marshal.Copy(
                    IntPtr.Add(locked.Scan0, checked(y * locked.Stride)),
                    bytes,
                    checked(y * rowBytes),
                    rowBytes);
            }
            return Convert.ToHexString(SHA256.HashData(bytes));
        }
        finally
        {
            if (locked is not null)
            {
                bitmap.UnlockBits(locked);
            }
        }
    }
}
