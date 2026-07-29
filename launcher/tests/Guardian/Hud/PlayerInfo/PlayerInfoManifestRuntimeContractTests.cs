using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoManifestRuntimeContractTests
{
    [Fact]
    public void EmbeddedManifest_PreservesTypedRuntimeLayoutAndRendererIdentity()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);

        Assert.Equal(1024, assetSet.Stage.LogicalWidth);
        Assert.Equal(64, assetSet.Stage.LogicalHeight);
        Assert.Equal(new[] { "mp", "hp" }, assetSet.Stage.CompositeOrder);
        Assert.Equal(
            "Svg.Skia/5.1.1;SkiaSharp/3.119.4;cf7-player-info-static-svg-v1;Bgra8888/premultiplied",
            assetSet.RendererIdentity.CacheIdentity);
        Assert.Equal("logical-pixel", assetSet.Units.SvgUnit);
        Assert.Equal(20, assetSet.Units.SourceTwipsPerSvgUnit);
        Assert.Equal(
            new[] { "assetSet.revision", "exact-manifest-sha256" },
            assetSet.RuntimeCacheIdentityComponents);
        Assert.Equal(new[] { "hp", "mp" }, assetSet.Gauges.Keys.OrderBy(id => id));

        PlayerInfoSvgGauge hp = assetSet.Gauges["hp"];
        Assert.Equal(
            new PlayerInfoSvgMatrix(
                0.847213745117188,
                0,
                0,
                0.847213745117188,
                37.75,
                2.65),
            hp.StageMatrix);
        Assert.Equal(
            new[] { "hp.backplate", "hp.fill", "hp.rim" },
            hp.AssetIds);
        Assert.Equal(128, hp.FrameMap.StepCount);
        Assert.Equal(129, hp.FrameMap.VirtualFrameCount);
        Assert.Equal(1, hp.FrameMap.FullVirtualFrame);
        Assert.Equal(129, hp.FrameMap.EmptyVirtualFrame);
        Assert.Null(hp.FrameMap.SourceFrameOffset);
        Assert.True(hp.FrameMap.Reverse);
        Assert.Equal("floor", hp.FrameMap.Rounding);
        Assert.NotNull(hp.Clip);
        Assert.Equal("radial-sector", hp.Clip.Type);
        Assert.Equal(new PlayerInfoSvgPoint(0, 0), hp.Clip.Center);
        Assert.Equal(128, hp.Clip.Radius);
        Assert.Equal(-90, hp.Clip.StartAngleDegrees);
        Assert.Equal("counterclockwise", hp.Clip.Direction);
        Assert.NotNull(hp.FillTextureRotation);
        Assert.Equal("hp.fill", hp.FillTextureRotation.AssetId);
        Assert.Equal(
            new[] { "hp-fill-gradient-0003" },
            hp.FillTextureRotation.SvgGradientIds);
        Assert.Equal(-1, hp.FillTextureRotation.SourceFrameOffset);
        Assert.Equal(2.8125, hp.FillTextureRotation.DegreesPerSourceFrame);
        Assert.Equal("clockwise", hp.FillTextureRotation.PositiveDirection);

        PlayerInfoSvgGauge mp = assetSet.Gauges["mp"];
        Assert.Equal(
            new PlayerInfoSvgMatrix(
                1.0810546875,
                0,
                0,
                1.0810546875,
                90.1,
                -4.3),
            mp.StageMatrix);
        Assert.Equal(
            new[]
            {
                "mp.backplate",
                "mp.fill",
                "mp.rim",
                "mp.rim-vf70",
                "mp.rim-vf91"
            },
            mp.AssetIds);
        Assert.Equal(100, mp.FrameMap.StepCount);
        Assert.Equal(101, mp.FrameMap.VirtualFrameCount);
        Assert.Equal(-1, mp.FrameMap.SourceFrameOffset);
        Assert.Equal("coverage-only", mp.MaskPaintSemantics);
        Assert.Equal(
            new[] { "mp-left-mask", "mp-right-mask" },
            mp.ClipBindings.Select(binding => binding.Id));
        Assert.Equal(
            new[] { 1, 70, 91 },
            mp.RimVariants.Select(variant => variant.StartVirtualFrame));
        Assert.Equal(
            new[] { 1, 70, 91 },
            mp.PaletteStates.Select(state => state.StartVirtualFrame));
        Assert.Equal(34, mp.TopologyBreak?.LastTwoContourVirtualFrame);
        Assert.Equal(35, mp.TopologyBreak?.FirstOneContourVirtualFrame);
        Assert.Equal(99, mp.TerminalEmpty?.PreviousSourceFrame);
        Assert.Equal(100, mp.TerminalEmpty?.EmptySourceFrame);
        Assert.Equal(101, mp.TerminalEmpty?.EmptyVirtualFrame);
        Assert.Equal(3, mp.MorphIntervals.Count);
        Assert.Equal(
            new[] { 1, 2, 1 },
            mp.MorphIntervals.Select(interval => interval.Correspondence.Count));
        Assert.Equal(
            new PlayerInfoSvgPoint(-607, 5),
            mp.MorphIntervals[0]
                .Correspondence[0]
                .AStartAndAnchorsTwips[0]);

        Assert.Single(assetSet.EffectPolicy.IncludedStatic);
        Assert.Equal(
            "hp-rim-static-bevel-expanded",
            assetSet.EffectPolicy.IncludedStatic[0].SvgGroupId);
        Assert.Equal(
            new[]
            {
                "hp-light-overlay",
                "hp-mp-dynamic-text-and-glow",
                "hp-horizontal-line-glow"
            },
            assetSet.EffectPolicy.ProgrammaticLayers.Select(effect => effect.Id));
        Assert.Equal(
            new[] { "overlay", "source-over", "source-over" },
            assetSet.EffectPolicy.ProgrammaticLayers.Select(effect => effect.BlendMode));
        Assert.Equal(
            new[]
            {
                PlayerInfoProgrammaticEffectDisposition.DeferredB3,
                PlayerInfoProgrammaticEffectDisposition.ImplementedActive,
                PlayerInfoProgrammaticEffectDisposition.ImplementedActive
            },
            assetSet.EffectPolicy.ProgrammaticLayers.Select(
                effect => effect.Disposition));
        Assert.Equal(
            new[]
            {
                "hp-mp-dynamic-text-and-glow",
                "hp-horizontal-line-glow"
            },
            assetSet.EffectPolicy.ImplementedActiveLayers.Select(
                effect => effect.Id));
        Assert.Equal(
            new[] { "hp-light-overlay" },
            assetSet.EffectPolicy.DeferredB3Layers.Select(effect => effect.Id));

        Assert.All(assetSet.Assets, asset =>
        {
            Assert.True(asset.ViewBox.Width > 0);
            Assert.True(asset.ViewBox.Height > 0);
            Assert.Equal(new PlayerInfoSvgPoint(0, 0), asset.Registration);
            Assert.Equal("source-over", asset.BlendMode);
            Assert.Equal(1d, asset.Opacity);
            Assert.True(asset.Cacheable);
        });
    }

    [Fact]
    public void RasterKey_ContainsAuthoredTransformAndExcludesTelemetryDpi()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assetSet,
            new System.Drawing.Rectangle(0, 0, 1024, 576),
            monitorDpiScale: 1.75f);
        PlayerInfoRasterKey key = plan.Layers[0].Key;

        Assert.Equal(assetSet.Revision, key.AssetSetRevision);
        Assert.Equal(assetSet.ExactManifestSha256, key.ExactManifestSha256);
        Assert.False(string.IsNullOrWhiteSpace(key.LayerId));
        Assert.True(key.PixelWidth > 0);
        Assert.True(key.PixelHeight > 0);
        Assert.False(string.IsNullOrWhiteSpace(key.SourceToBitmapIdentity));
        Assert.Equal(
            plan.Layers[0].SourceToBitmap.ToCacheIdentity(),
            key.SourceToBitmapIdentity);
        Assert.Equal(assetSet.RendererIdentity.CacheIdentity, key.RendererIdentity);
        Assert.Equal(assetSet.RasterContractVersion, key.RasterContractVersion);
        Assert.DoesNotContain("1.75", key.ToCacheIdentity(), StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("missing_hp_frame_map", "$.gauges.hp")]
    [InlineData("hp_non_uniform_matrix", "$.gauges.hp.stageMatrix")]
    [InlineData("rotation_unknown_asset", "$.gauges.hp.fillTextureRotation.assetId")]
    [InlineData("duplicate_clip_binding_id", "$.gauges.mp.clipBindings[1].id")]
    [InlineData("morph_range_overlap", "$.gauges.mp.morphIntervals[2].sourceStart")]
    [InlineData("morph_open_contour", "explicitly closed")]
    [InlineData("palette_rim_mismatch", "$.gauges.mp.paletteStates[1].rimAssetId")]
    [InlineData("palette_invalid_color", "canonical #RRGGBB")]
    [InlineData("effect_missing_composite", "$.effectPolicy.programmaticLayers[0]")]
    [InlineData("unknown_dynamic_field", "$.gauges.hp property closure")]
    public void DynamicManifestMutation_FailsClosed(
        string mutation,
        string expectedMessage)
    {
        JsonObject root = ParseEmbeddedManifest();
        ApplyMutation(root, mutation);

        InvalidDataException exception = Assert.Throws<InvalidDataException>(
            () => PlayerInfoSvgAssetCatalog.LoadFromResources(
                CreateResourceClosure(Encoding.UTF8.GetBytes(
                    root.ToJsonString(new JsonSerializerOptions
                    {
                        WriteIndented = false
                    })))));

        Assert.Contains(expectedMessage, exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void DuplicateJsonProperty_FailsClosedBeforeTypedLoading()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        string manifest = Encoding.UTF8.GetString(assetSet.ManifestBytes.Span);
        string duplicate =
            "{\"format\":\"cf7.player-info-hud.asset-manifest\"," + manifest[1..];

        InvalidDataException exception = Assert.Throws<InvalidDataException>(
            () => PlayerInfoSvgAssetCatalog.LoadFromResources(
                CreateResourceClosure(Encoding.UTF8.GetBytes(duplicate))));

        Assert.Contains(
            "duplicate property 'format'",
            exception.Message,
            StringComparison.Ordinal);
    }

    private static JsonObject ParseEmbeddedManifest()
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        return JsonNode.Parse(assetSet.ManifestBytes.Span)?.AsObject()
            ?? throw new InvalidDataException("Embedded PlayerInfo manifest is not an object.");
    }

    private static Dictionary<string, byte[]> CreateResourceClosure(
        byte[] manifestBytes)
    {
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        var resources = assetSet.Assets.ToDictionary(
            asset => asset.ResourceName,
            asset => asset.Bytes.ToArray(),
            StringComparer.Ordinal);
        resources.Add(PlayerInfoSvgAssetCatalog.ManifestResourceName, manifestBytes);
        return resources;
    }

    private static void ApplyMutation(JsonObject root, string mutation)
    {
        JsonObject hp = ObjectAt(root, "gauges", "hp");
        JsonObject mp = ObjectAt(root, "gauges", "mp");
        switch (mutation)
        {
            case "missing_hp_frame_map":
                hp.Remove("frameMap");
                break;
            case "hp_non_uniform_matrix":
                hp["stageMatrix"] = JsonNode.Parse("[1,0,0,2,37.75,5.65]");
                break;
            case "rotation_unknown_asset":
                ObjectAt(hp, "fillTextureRotation")["assetId"] = "mp.fill";
                break;
            case "duplicate_clip_binding_id":
                ArrayAt(mp, "clipBindings")[1]!["id"] = "mp-left-mask";
                break;
            case "morph_range_overlap":
                ArrayAt(mp, "morphIntervals")[2]!["sourceStart"] = 33;
                break;
            case "morph_open_contour":
                ArrayAt(
                    ArrayAt(
                        ArrayAt(mp, "morphIntervals")[0]!.AsObject(),
                        "correspondence")[0]!.AsObject(),
                    "aStartAndAnchorsTwips")[4] = JsonNode.Parse("[-606,5]");
                break;
            case "palette_rim_mismatch":
                ArrayAt(mp, "paletteStates")[1]!["rimAssetId"] = "mp.rim";
                break;
            case "palette_invalid_color":
                ArrayAt(mp, "paletteStates")[0]!["label"] = "#5eeffb";
                break;
            case "effect_missing_composite":
                ArrayAt(
                    ObjectAt(root, "effectPolicy"),
                    "programmaticLayers")[0]!
                    .AsObject()
                    .Remove("compositeBefore");
                break;
            case "unknown_dynamic_field":
                hp["futureMode"] = "silently-ignored";
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(mutation), mutation, null);
        }
    }

    private static JsonObject ObjectAt(JsonObject root, params string[] path)
    {
        JsonNode current = root;
        foreach (string segment in path)
        {
            current = current[segment]
                ?? throw new InvalidDataException(
                    $"Test manifest path is missing: {string.Join(".", path)}.");
        }
        return current.AsObject();
    }

    private static JsonArray ArrayAt(JsonObject root, string propertyName) =>
        root[propertyName]?.AsArray()
        ?? throw new InvalidDataException(
            $"Test manifest array is missing: {propertyName}.");
}
