#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Xml;
using System.Xml.Linq;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerInfoSvgAssetCatalog
{
    internal const string ResourcePrefix = "CF7Launcher.Guardian.Hud.PlayerInfo.Assets";
    internal const string ManifestResourceName =
        ResourcePrefix + ".player-info.manifest.json";
    internal const int ExpectedAssetCount = 8;

    private const int MaxEmbeddedResourceBytes = 1_048_576;
    private const string ExpectedFormat = "cf7.player-info-hud.asset-manifest";
    private const string ExpectedAssetSetId = "player-info-hp-mp-b0";
    private const string ExpectedRevisionAlgorithm =
        "sha256(sorted UTF-8 relative path + NUL + exact file bytes + NUL)";
    private const string ExpectedRendererPackage = "Svg.Skia";
    private const string ExpectedRendererVersion = "5.1.1";
    private const string ExpectedSkiaSharpVersion = "3.119.4";
    private const string ExpectedFeatureSet = "cf7-player-info-static-svg-v1";

    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly ExpectedAsset[] ExpectedAssets =
    [
        new("hp.backplate", "hp/backplate.svg", ResourcePrefix + ".hp.backplate.svg"),
        new("hp.fill", "hp/fill.svg", ResourcePrefix + ".hp.fill.svg"),
        new("hp.rim", "hp/rim.svg", ResourcePrefix + ".hp.rim.svg"),
        new("mp.backplate", "mp/backplate.svg", ResourcePrefix + ".mp.backplate.svg"),
        new("mp.fill", "mp/fill.svg", ResourcePrefix + ".mp.fill.svg"),
        new("mp.rim", "mp/rim.svg", ResourcePrefix + ".mp.rim.svg"),
        new("mp.rim-vf70", "mp/rim-vf70.svg", ResourcePrefix + ".mp.rim-vf70.svg"),
        new("mp.rim-vf91", "mp/rim-vf91.svg", ResourcePrefix + ".mp.rim-vf91.svg")
    ];

    internal static PlayerInfoSvgAssetSet LoadEmbedded() =>
        LoadFromAssembly(typeof(PlayerInfoSvgAssetCatalog).Assembly);

    internal static PlayerInfoSvgAssetSet LoadFromAssembly(Assembly assembly)
    {
        ArgumentNullException.ThrowIfNull(assembly);
        ValidateNoRepoOnlyResources(assembly);
        ValidateExactResourceSet(assembly);
        return LoadFromResourceReader(name => ReadResource(assembly, name));
    }

    internal static PlayerInfoSvgAssetSet LoadFromResources(
        IReadOnlyDictionary<string, byte[]> resources)
    {
        ArgumentNullException.ThrowIfNull(resources);
        ValidateNoRepoOnlyResourceNames(resources.Keys);
        ValidateExactResourceNames(resources.Keys);
        return LoadFromResourceReader(name =>
        {
            if (!resources.TryGetValue(name, out var bytes) ||
                bytes is null ||
                bytes.Length is <= 0 or > MaxEmbeddedResourceBytes)
            {
                throw new InvalidDataException(
                    $"PlayerInfo resource has an invalid byte length: {name}.");
            }
            return bytes;
        });
    }

    private static PlayerInfoSvgAssetSet LoadFromResourceReader(
        Func<string, byte[]> readResource)
    {
        var manifestBytes = readResource(ManifestResourceName);
        _ = StrictUtf8.GetString(manifestBytes);
        using var document = JsonDocument.Parse(manifestBytes, new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 64
        });
        EnsureNoDuplicateProperties(document.RootElement, "$");

        var root = RequireObject(document.RootElement, "$");
        RequireExactProperties(
            root,
            "$",
            "format",
            "schemaVersion",
            "assetSet",
            "units",
            "stage",
            "rendererContract",
            "assets",
            "gauges",
            "effectPolicy");
        RequireString(root, "format", "$", ExpectedFormat);
        RequireInt32(root, "schemaVersion", "$", 1);

        var assetSet = RequireObjectProperty(root, "assetSet", "$");
        RequireExactProperties(
            assetSet,
            "$.assetSet",
            "id",
            "revision",
            "revisionAlgorithm",
            "rasterContractVersion",
            "runtimeCacheIdentityComponents");
        var assetSetId = RequireString(assetSet, "id", "$.assetSet", ExpectedAssetSetId);
        var revision = RequireString(assetSet, "revision", "$.assetSet");
        RequireString(
            assetSet,
            "revisionAlgorithm",
            "$.assetSet",
            ExpectedRevisionAlgorithm);
        var rasterContractVersion = RequireInt32(
            assetSet,
            "rasterContractVersion",
            "$.assetSet",
            1);
        var runtimeCacheIdentityComponents = RequireExactStringArray(
            assetSet,
            "runtimeCacheIdentityComponents",
            "$.assetSet",
            "assetSet.revision",
            "exact-manifest-sha256");

        var unitsObject = RequireObjectProperty(root, "units", "$");
        RequireExactProperties(
            unitsObject,
            "$.units",
            "svgUnit",
            "sourceTwipsPerSvgUnit");
        var units = new PlayerInfoSvgUnits(
            RequireString(unitsObject, "svgUnit", "$.units", "logical-pixel"),
            RequireInt32(unitsObject, "sourceTwipsPerSvgUnit", "$.units", 20));

        var stageObject = RequireObjectProperty(root, "stage", "$");
        RequireExactProperties(
            stageObject,
            "$.stage",
            "logicalWidth",
            "logicalHeight",
            "compositeOrder");
        var stage = new PlayerInfoSvgStage(
            RequirePositiveInt32(stageObject, "logicalWidth", "$.stage", 1024),
            RequirePositiveInt32(stageObject, "logicalHeight", "$.stage", 64),
            RequireStringArray(stageObject, "compositeOrder", "$.stage"));
        if (!stage.CompositeOrder.SequenceEqual(
                new[] { "mp", "hp" },
                StringComparer.Ordinal))
        {
            throw new InvalidDataException(
                "$.stage.compositeOrder must equal ['mp','hp'].");
        }

        var renderer = RequireObjectProperty(root, "rendererContract", "$");
        RequireExactProperties(
            renderer,
            "$.rendererContract",
            "package",
            "version",
            "skiaSharpVersion",
            "featureSet",
            "colorType",
            "alphaType",
            "externalResources",
            "scripts",
            "runtimeTextElements");
        var rendererPackage = RequireString(
            renderer,
            "package",
            "$.rendererContract",
            ExpectedRendererPackage);
        var rendererVersion = RequireString(
            renderer,
            "version",
            "$.rendererContract",
            ExpectedRendererVersion);
        var skiaSharpVersion = RequireString(
            renderer,
            "skiaSharpVersion",
            "$.rendererContract",
            ExpectedSkiaSharpVersion);
        var featureSet = RequireString(
            renderer,
            "featureSet",
            "$.rendererContract",
            ExpectedFeatureSet);
        var colorType = RequireString(
            renderer,
            "colorType",
            "$.rendererContract",
            "Bgra8888");
        var alphaType = RequireString(
            renderer,
            "alphaType",
            "$.rendererContract",
            "premultiplied");
        RequireString(renderer, "externalResources", "$.rendererContract", "forbidden");
        RequireString(renderer, "scripts", "$.rendererContract", "forbidden");
        RequireString(renderer, "runtimeTextElements", "$.rendererContract", "forbidden");
        var rendererIdentity = new PlayerInfoRendererIdentity(
            rendererPackage,
            rendererVersion,
            skiaSharpVersion,
            featureSet,
            colorType,
            alphaType);

        if (!root.TryGetProperty("assets", out var assetArray) ||
            assetArray.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("$.assets must be an array.");
        }
        if (assetArray.GetArrayLength() != ExpectedAssets.Length)
        {
            throw new InvalidDataException(
                $"$.assets must contain exactly {ExpectedAssets.Length} entries.");
        }

        var loadedAssets = new PlayerInfoSvgAsset[ExpectedAssets.Length];
        var index = 0;
        foreach (var element in assetArray.EnumerateArray())
        {
            var path = $"$.assets[{index}]";
            var assetObject = RequireObject(element, path);
            RequireExactProperties(
                assetObject,
                path,
                "id",
                "path",
                "sha256",
                "viewBox",
                "sourceGeometryBounds",
                "registration",
                "gaugeLayerOrder",
                "blendMode",
                "opacity",
                "cacheable");
            var expected = ExpectedAssets[index];
            RequireString(assetObject, "id", path, expected.Id);
            RequireString(assetObject, "path", path, expected.RelativePath);
            var manifestHash = RequireLowerSha256(
                RequireString(assetObject, "sha256", path),
                path + ".sha256");
            var viewBox = RequireRectArray(assetObject, "viewBox", path, positiveSize: true);
            var sourceGeometryBounds = RequireEdgeRectArray(
                assetObject,
                "sourceGeometryBounds",
                path);
            var registration = RequirePointArray(assetObject, "registration", path);
            if (registration != new PlayerInfoSvgPoint(0, 0))
            {
                throw new InvalidDataException(
                    $"{path}.registration must equal [0,0] for the B0 raster contract.");
            }
            var gaugeLayerOrder = RequireNonNegativeInt32(
                assetObject,
                "gaugeLayerOrder",
                path);
            var blendMode = RequireString(
                assetObject,
                "blendMode",
                path,
                "source-over");
            var opacity = RequireFiniteDouble(assetObject, "opacity", path);
            if (opacity is < 0 or > 1)
            {
                throw new InvalidDataException($"{path}.opacity must be between 0 and 1.");
            }
            var cacheable = RequireBoolean(assetObject, "cacheable", path, true);

            var bytes = readResource(expected.ResourceName);
            var actualHash = Sha256Lower(bytes);
            if (!string.Equals(manifestHash, actualHash, StringComparison.Ordinal))
            {
                throw new InvalidDataException(
                    $"Embedded PlayerInfo asset hash mismatch: {expected.RelativePath}.");
            }

            loadedAssets[index] = new PlayerInfoSvgAsset(
                expected.Id,
                expected.RelativePath,
                expected.ResourceName,
                actualHash,
                bytes,
                viewBox,
                sourceGeometryBounds,
                registration,
                gaugeLayerOrder,
                blendMode,
                opacity,
                cacheable);
            index++;
        }

        var gauges = LoadGauges(root, stage, loadedAssets);
        var effectPolicy = LoadEffectPolicy(root, loadedAssets);
        var computedRevision = ComputeAssetSetRevision(loadedAssets);
        var expectedRevision = "sha256:" + computedRevision;
        if (!string.Equals(revision, expectedRevision, StringComparison.Ordinal))
        {
            throw new InvalidDataException(
                $"Embedded PlayerInfo asset-set revision mismatch: expected {expectedRevision}, manifest {revision}.");
        }

        return new PlayerInfoSvgAssetSet(
            assetSetId,
            revision,
            Sha256Lower(manifestBytes),
            rasterContractVersion,
            featureSet,
            runtimeCacheIdentityComponents,
            rendererIdentity,
            units,
            stage,
            gauges,
            effectPolicy,
            manifestBytes,
            loadedAssets);
    }

    private static IReadOnlyDictionary<string, PlayerInfoSvgGauge> LoadGauges(
        JsonElement root,
        PlayerInfoSvgStage stage,
        IReadOnlyList<PlayerInfoSvgAsset> assets)
    {
        var gaugesObject = RequireObjectProperty(root, "gauges", "$");
        RequireExactProperties(gaugesObject, "$.gauges", "hp", "mp");
        var knownAssetIds = assets
            .Select(asset => asset.Id)
            .ToHashSet(StringComparer.Ordinal);
        var assignedAssetIds = new HashSet<string>(StringComparer.Ordinal);
        var gauges = new Dictionary<string, PlayerInfoSvgGauge>(StringComparer.Ordinal);

        foreach (var gaugeId in stage.CompositeOrder)
        {
            if (!gauges.TryAdd(
                    gaugeId,
                    gaugeId switch
                    {
                        "hp" => LoadHpGauge(
                            RequireObjectProperty(gaugesObject, gaugeId, "$.gauges"),
                            knownAssetIds,
                            assignedAssetIds,
                            assets),
                        "mp" => LoadMpGauge(
                            RequireObjectProperty(gaugesObject, gaugeId, "$.gauges"),
                            knownAssetIds,
                            assignedAssetIds,
                            assets),
                        _ => throw new InvalidDataException(
                            $"Unsupported PlayerInfo gauge '{gaugeId}'.")
                    }))
            {
                throw new InvalidDataException(
                    $"$.stage.compositeOrder contains duplicate gauge '{gaugeId}'.");
            }
        }

        var unassigned = knownAssetIds
            .Except(assignedAssetIds, StringComparer.Ordinal)
            .OrderBy(id => id, StringComparer.Ordinal)
            .ToArray();
        if (unassigned.Length != 0)
        {
            throw new InvalidDataException(
                "PlayerInfo assets are not assigned to a gauge: " +
                string.Join(",", unassigned) + ".");
        }

        return gauges;
    }

    private static PlayerInfoSvgGauge LoadHpGauge(
        JsonElement gauge,
        IReadOnlySet<string> knownAssetIds,
        ISet<string> assignedAssetIds,
        IReadOnlyList<PlayerInfoSvgAsset> assets)
    {
        const string path = "$.gauges.hp";
        RequireExactProperties(
            gauge,
            path,
            "assetIds",
            "stageMatrix",
            "frameMap",
            "clip",
            "fillTextureRotation");
        var directAssetIds = RequireExactStringArray(
            gauge,
            "assetIds",
            path,
            "hp.backplate",
            "hp.fill",
            "hp.rim");
        var assetIds = RegisterGaugeAssets(
            path,
            directAssetIds,
            [],
            knownAssetIds,
            assignedAssetIds);

        var stageMatrix = RequireMatrixArray(gauge, "stageMatrix", path);
        var expectedMatrix = new PlayerInfoSvgMatrix(
            0.847213745117188,
            0,
            0,
            0.847213745117188,
            37.75,
            5.65);
        if (stageMatrix != expectedMatrix)
        {
            throw new InvalidDataException($"{path}.stageMatrix drifted.");
        }

        var frameMapObject = RequireObjectProperty(gauge, "frameMap", path);
        RequireExactProperties(
            frameMapObject,
            path + ".frameMap",
            "stepCount",
            "virtualFrameCount",
            "fullVirtualFrame",
            "emptyVirtualFrame",
            "reverse",
            "rounding");
        var frameMap = new PlayerInfoFrameMap(
            RequireInt32(frameMapObject, "stepCount", path + ".frameMap", 128),
            RequireInt32(frameMapObject, "virtualFrameCount", path + ".frameMap", 129),
            RequireInt32(frameMapObject, "fullVirtualFrame", path + ".frameMap", 1),
            RequireInt32(frameMapObject, "emptyVirtualFrame", path + ".frameMap", 129),
            SourceFrameOffset: null,
            RequireBoolean(frameMapObject, "reverse", path + ".frameMap", true),
            RequireString(frameMapObject, "rounding", path + ".frameMap", "floor"));
        ValidateFrameMap(frameMap, path + ".frameMap");

        var clipObject = RequireObjectProperty(gauge, "clip", path);
        RequireExactProperties(
            clipObject,
            path + ".clip",
            "type",
            "center",
            "radius",
            "startAngleDegrees",
            "direction");
        var clip = new PlayerInfoRadialClip(
            RequireString(clipObject, "type", path + ".clip", "radial-sector"),
            RequireExactPointArray(clipObject, "center", path + ".clip", 0, 0),
            RequireExactFiniteDouble(clipObject, "radius", path + ".clip", 128),
            RequireExactFiniteDouble(
                clipObject,
                "startAngleDegrees",
                path + ".clip",
                -90),
            RequireString(
                clipObject,
                "direction",
                path + ".clip",
                "counterclockwise"));

        var rotationObject = RequireObjectProperty(
            gauge,
            "fillTextureRotation",
            path);
        RequireExactProperties(
            rotationObject,
            path + ".fillTextureRotation",
            "assetId",
            "svgGradientIds",
            "pivot",
            "sourceFrameOffset",
            "degreesPerSourceFrame",
            "positiveDirection");
        var rotation = new PlayerInfoFillTextureRotation(
            RequireString(
                rotationObject,
                "assetId",
                path + ".fillTextureRotation",
                "hp.fill"),
            RequireExactStringArray(
                rotationObject,
                "svgGradientIds",
                path + ".fillTextureRotation",
                "hp-fill-gradient-0003"),
            RequireExactPointArray(
                rotationObject,
                "pivot",
                path + ".fillTextureRotation",
                0,
                0),
            RequireInt32(
                rotationObject,
                "sourceFrameOffset",
                path + ".fillTextureRotation",
                -1),
            RequireExactFiniteDouble(
                rotationObject,
                "degreesPerSourceFrame",
                path + ".fillTextureRotation",
                2.8125),
            RequireString(
                rotationObject,
                "positiveDirection",
                path + ".fillTextureRotation",
                "clockwise"));
        if (!assetIds.Contains(rotation.AssetId, StringComparer.Ordinal))
        {
            throw new InvalidDataException(
                $"{path}.fillTextureRotation.assetId is not assigned to HP.");
        }
        RequireExactSvgId(
            GetAsset(assets, rotation.AssetId),
            rotation.SvgGradientIds.Single(),
            element =>
                element.Name.LocalName is "linearGradient" or "radialGradient" &&
                element.Attribute("gradientTransform") is not null,
            path + ".fillTextureRotation.svgGradientIds[0]");
        if ((frameMap.StepCount * rotation.DegreesPerSourceFrame) != 360)
        {
            throw new InvalidDataException(
                $"{path}.fillTextureRotation does not complete one turn across the frame map.");
        }

        return new PlayerInfoSvgGauge("hp", stageMatrix, assetIds, frameMap)
        {
            Clip = clip,
            FillTextureRotation = rotation
        };
    }

    private static PlayerInfoSvgGauge LoadMpGauge(
        JsonElement gauge,
        IReadOnlySet<string> knownAssetIds,
        ISet<string> assignedAssetIds,
        IReadOnlyList<PlayerInfoSvgAsset> assets)
    {
        const string path = "$.gauges.mp";
        RequireExactProperties(
            gauge,
            path,
            "assetIds",
            "stageMatrix",
            "frameMap",
            "rimVariants",
            "maskPaintSemantics",
            "clipBindings",
            "topologyBreak",
            "terminalEmpty",
            "morphIntervals",
            "paletteStates");
        var directAssetIds = RequireExactStringArray(
            gauge,
            "assetIds",
            path,
            "mp.backplate",
            "mp.fill");

        var stageMatrix = RequireMatrixArray(gauge, "stageMatrix", path);
        var expectedMatrix = new PlayerInfoSvgMatrix(
            1.0810546875,
            0,
            0,
            1.0810546875,
            90.1,
            -1.3);
        if (stageMatrix != expectedMatrix)
        {
            throw new InvalidDataException($"{path}.stageMatrix drifted.");
        }

        var frameMapObject = RequireObjectProperty(gauge, "frameMap", path);
        RequireExactProperties(
            frameMapObject,
            path + ".frameMap",
            "stepCount",
            "virtualFrameCount",
            "fullVirtualFrame",
            "emptyVirtualFrame",
            "sourceFrameOffset",
            "reverse",
            "rounding");
        var frameMap = new PlayerInfoFrameMap(
            RequireInt32(frameMapObject, "stepCount", path + ".frameMap", 100),
            RequireInt32(frameMapObject, "virtualFrameCount", path + ".frameMap", 101),
            RequireInt32(frameMapObject, "fullVirtualFrame", path + ".frameMap", 1),
            RequireInt32(frameMapObject, "emptyVirtualFrame", path + ".frameMap", 101),
            RequireInt32(frameMapObject, "sourceFrameOffset", path + ".frameMap", -1),
            RequireBoolean(frameMapObject, "reverse", path + ".frameMap", true),
            RequireString(frameMapObject, "rounding", path + ".frameMap", "floor"));
        ValidateFrameMap(frameMap, path + ".frameMap");

        var rimVariants = LoadRimVariants(
            RequireArrayProperty(gauge, "rimVariants", path),
            assets);
        var assetIds = RegisterGaugeAssets(
            path,
            directAssetIds,
            rimVariants.Select(variant => variant.AssetId),
            knownAssetIds,
            assignedAssetIds);

        var maskPaintSemantics = RequireString(
            gauge,
            "maskPaintSemantics",
            path,
            "coverage-only");
        var clipBindings = LoadClipBindings(
            RequireArrayProperty(gauge, "clipBindings", path),
            directAssetIds,
            assets);

        var topologyObject = RequireObjectProperty(gauge, "topologyBreak", path);
        RequireExactProperties(
            topologyObject,
            path + ".topologyBreak",
            "lastTwoContourVirtualFrame",
            "firstOneContourVirtualFrame",
            "policy");
        var topologyBreak = new PlayerInfoTopologyBreak(
            RequireInt32(
                topologyObject,
                "lastTwoContourVirtualFrame",
                path + ".topologyBreak",
                34),
            RequireInt32(
                topologyObject,
                "firstOneContourVirtualFrame",
                path + ".topologyBreak",
                35),
            RequireString(
                topologyObject,
                "policy",
                path + ".topologyBreak",
                "hard-cut-no-cross-topology-interpolation"));
        if (topologyBreak.FirstOneContourVirtualFrame !=
            topologyBreak.LastTwoContourVirtualFrame + 1)
        {
            throw new InvalidDataException(
                $"{path}.topologyBreak must describe adjacent virtual frames.");
        }

        var terminalObject = RequireObjectProperty(gauge, "terminalEmpty", path);
        RequireExactProperties(
            terminalObject,
            path + ".terminalEmpty",
            "previousSourceFrame",
            "emptySourceFrame",
            "emptyVirtualFrame");
        var terminalEmpty = new PlayerInfoTerminalEmpty(
            RequireInt32(
                terminalObject,
                "previousSourceFrame",
                path + ".terminalEmpty",
                99),
            RequireInt32(
                terminalObject,
                "emptySourceFrame",
                path + ".terminalEmpty",
                100),
            RequireInt32(
                terminalObject,
                "emptyVirtualFrame",
                path + ".terminalEmpty",
                101));
        if (terminalEmpty.EmptySourceFrame != terminalEmpty.PreviousSourceFrame + 1 ||
            terminalEmpty.EmptyVirtualFrame != frameMap.EmptyVirtualFrame ||
            terminalEmpty.EmptyVirtualFrame + frameMap.SourceFrameOffset !=
            terminalEmpty.EmptySourceFrame)
        {
            throw new InvalidDataException(
                $"{path}.terminalEmpty is inconsistent with frameMap.");
        }

        var morphIntervals = LoadMorphIntervals(
            RequireArrayProperty(gauge, "morphIntervals", path),
            clipBindings,
            topologyBreak,
            terminalEmpty);
        var paletteStates = LoadPaletteStates(
            RequireArrayProperty(gauge, "paletteStates", path),
            rimVariants,
            assets);

        return new PlayerInfoSvgGauge("mp", stageMatrix, assetIds, frameMap)
        {
            RimVariants = rimVariants,
            MaskPaintSemantics = maskPaintSemantics,
            ClipBindings = clipBindings,
            TopologyBreak = topologyBreak,
            TerminalEmpty = terminalEmpty,
            MorphIntervals = morphIntervals,
            PaletteStates = paletteStates
        };
    }

    private static IReadOnlyList<string> RegisterGaugeAssets(
        string path,
        IEnumerable<string> directAssetIds,
        IEnumerable<string> variantAssetIds,
        IReadOnlySet<string> knownAssetIds,
        ISet<string> assignedAssetIds)
    {
        var result = new List<string>();
        var localIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var assetId in directAssetIds.Concat(variantAssetIds))
        {
            if (!knownAssetIds.Contains(assetId))
            {
                throw new InvalidDataException(
                    $"{path} references unknown asset '{assetId}'.");
            }
            if (!localIds.Add(assetId))
            {
                throw new InvalidDataException(
                    $"{path} contains duplicate asset reference '{assetId}'.");
            }
            if (!assignedAssetIds.Add(assetId))
            {
                throw new InvalidDataException(
                    $"PlayerInfo asset '{assetId}' is assigned to multiple gauges.");
            }
            result.Add(assetId);
        }
        if (result.Count == 0)
        {
            throw new InvalidDataException($"{path}.assetIds must not be empty.");
        }
        return result;
    }

    private static IReadOnlyList<PlayerInfoRimVariant> LoadRimVariants(
        JsonElement variants,
        IReadOnlyList<PlayerInfoSvgAsset> assets)
    {
        const string path = "$.gauges.mp.rimVariants";
        if (variants.GetArrayLength() != 3)
        {
            throw new InvalidDataException($"{path} must contain frames 1/70/91.");
        }
        var expectedStarts = new[] { 1, 70, 91 };
        var expectedIds = new[] { "mp.rim", "mp.rim-vf70", "mp.rim-vf91" };
        var expectedFills = new[] { "#5EEFFB", "#5EEFFB", "#B6B6B6" };
        var result = new List<PlayerInfoRimVariant>(3);
        var seenStarts = new HashSet<int>();
        var seenIds = new HashSet<string>(StringComparer.Ordinal);
        var index = 0;
        foreach (var value in variants.EnumerateArray())
        {
            var itemPath = $"{path}[{index}]";
            var item = RequireObject(value, itemPath);
            RequireExactProperties(item, itemPath, "startVirtualFrame", "assetId");
            var start = RequireInt32(
                item,
                "startVirtualFrame",
                itemPath,
                expectedStarts[index]);
            var assetId = RequireString(
                item,
                "assetId",
                itemPath,
                expectedIds[index]);
            if (!seenStarts.Add(start) || !seenIds.Add(assetId))
            {
                throw new InvalidDataException($"{itemPath} duplicates a rim variant.");
            }
            RequireOnlySvgPathFill(
                GetAsset(assets, assetId),
                expectedFills[index],
                itemPath + ".assetId");
            result.Add(new PlayerInfoRimVariant(start, assetId));
            index++;
        }
        return result;
    }

    private static IReadOnlyList<PlayerInfoClipBinding> LoadClipBindings(
        JsonElement bindings,
        IReadOnlyList<string> directAssetIds,
        IReadOnlyList<PlayerInfoSvgAsset> assets)
    {
        const string path = "$.gauges.mp.clipBindings";
        if (bindings.GetArrayLength() != 2)
        {
            throw new InvalidDataException($"{path} must contain exactly two masks.");
        }
        var expectedIds = new[] { "mp-left-mask", "mp-right-mask" };
        var expectedGroups = new[]
        {
            new[] { "mp-fill-left-background-copy", "mp-fill-left-slot" },
            new[] { "mp-fill-right-decoration", "mp-fill-right-slot" }
        };
        var result = new List<PlayerInfoClipBinding>(2);
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var allGroupIds = new HashSet<string>(StringComparer.Ordinal);
        var index = 0;
        foreach (var value in bindings.EnumerateArray())
        {
            var itemPath = $"{path}[{index}]";
            var item = RequireObject(value, itemPath);
            RequireExactProperties(item, itemPath, "id", "assetId", "svgGroupIds");
            var id = RequireString(item, "id", itemPath, expectedIds[index]);
            var assetId = RequireString(item, "assetId", itemPath, "mp.fill");
            var groupIds = RequireExactStringArray(
                item,
                "svgGroupIds",
                itemPath,
                expectedGroups[index]);
            if (!ids.Add(id))
            {
                throw new InvalidDataException($"{itemPath}.id is duplicated.");
            }
            if (!directAssetIds.Contains(assetId, StringComparer.Ordinal))
            {
                throw new InvalidDataException(
                    $"{itemPath}.assetId is not a direct MP asset.");
            }
            var asset = GetAsset(assets, assetId);
            foreach (var groupId in groupIds)
            {
                if (!allGroupIds.Add(groupId))
                {
                    throw new InvalidDataException(
                        $"{itemPath}.svgGroupIds duplicates '{groupId}'.");
                }
                RequireExactSvgId(
                    asset,
                    groupId,
                    element => element.Name.LocalName == "g",
                    itemPath + ".svgGroupIds");
            }
            result.Add(new PlayerInfoClipBinding(id, assetId, groupIds));
            index++;
        }
        return result;
    }

    private static IReadOnlyList<PlayerInfoMorphInterval> LoadMorphIntervals(
        JsonElement intervals,
        IReadOnlyList<PlayerInfoClipBinding> bindings,
        PlayerInfoTopologyBreak topologyBreak,
        PlayerInfoTerminalEmpty terminalEmpty)
    {
        const string path = "$.gauges.mp.morphIntervals";
        if (intervals.GetArrayLength() != 3)
        {
            throw new InvalidDataException($"{path} must contain the exact three spans.");
        }
        var expected = new[]
        {
            (Mask: "mp-left-mask", Start: 0, End: 99, CorrespondenceCount: 1),
            (Mask: "mp-right-mask", Start: 0, End: 33, CorrespondenceCount: 2),
            (Mask: "mp-right-mask", Start: 34, End: 99, CorrespondenceCount: 1)
        };
        var bindingIds = bindings
            .Select(binding => binding.Id)
            .ToHashSet(StringComparer.Ordinal);
        var result = new List<PlayerInfoMorphInterval>(3);
        var intervalKeys = new HashSet<string>(StringComparer.Ordinal);
        var index = 0;
        foreach (var value in intervals.EnumerateArray())
        {
            var itemPath = $"{path}[{index}]";
            var item = RequireObject(value, itemPath);
            RequireExactProperties(
                item,
                itemPath,
                "mask",
                "sourceStart",
                "sourceEnd",
                "interpolation",
                "correspondence");
            var mask = RequireString(
                item,
                "mask",
                itemPath,
                expected[index].Mask);
            var sourceStart = RequireInt32(
                item,
                "sourceStart",
                itemPath,
                expected[index].Start);
            var sourceEnd = RequireInt32(
                item,
                "sourceEnd",
                itemPath,
                expected[index].End);
            var interpolation = RequireString(
                item,
                "interpolation",
                itemPath,
                "ordered-line-only-A/B-correspondence");
            if (!bindingIds.Contains(mask) ||
                sourceStart < 0 ||
                sourceEnd < sourceStart ||
                sourceEnd > terminalEmpty.PreviousSourceFrame ||
                !intervalKeys.Add($"{mask}\0{sourceStart}\0{sourceEnd}"))
            {
                throw new InvalidDataException($"{itemPath} has an invalid mask/range.");
            }

            var correspondenceArray = RequireArrayProperty(
                item,
                "correspondence",
                itemPath);
            if (correspondenceArray.GetArrayLength() !=
                expected[index].CorrespondenceCount)
            {
                throw new InvalidDataException(
                    $"{itemPath}.correspondence count drifted.");
            }
            var correspondences = new List<PlayerInfoMorphCorrespondence>();
            var correspondenceIndex = 0;
            foreach (var correspondenceValue in correspondenceArray.EnumerateArray())
            {
                var correspondencePath =
                    $"{itemPath}.correspondence[{correspondenceIndex}]";
                var correspondenceObject = RequireObject(
                    correspondenceValue,
                    correspondencePath);
                RequireExactProperties(
                    correspondenceObject,
                    correspondencePath,
                    "aStartAndAnchorsTwips",
                    "bStartAndAnchorsTwips");
                var a = RequireClosedTwipContour(
                    RequireArrayProperty(
                        correspondenceObject,
                        "aStartAndAnchorsTwips",
                        correspondencePath),
                    correspondencePath + ".aStartAndAnchorsTwips");
                var b = RequireClosedTwipContour(
                    RequireArrayProperty(
                        correspondenceObject,
                        "bStartAndAnchorsTwips",
                        correspondencePath),
                    correspondencePath + ".bStartAndAnchorsTwips");
                if (a.Count != b.Count)
                {
                    throw new InvalidDataException(
                        $"{correspondencePath} endpoint cardinality drifted.");
                }
                correspondences.Add(new PlayerInfoMorphCorrespondence(a, b));
                correspondenceIndex++;
            }
            result.Add(new PlayerInfoMorphInterval(
                mask,
                sourceStart,
                sourceEnd,
                interpolation,
                correspondences));
            index++;
        }

        var right = result
            .Where(interval => interval.MaskId == "mp-right-mask")
            .OrderBy(interval => interval.SourceStart)
            .ToArray();
        if (right.Length != 2 ||
            right[0].SourceEnd + 1 != right[1].SourceStart ||
            right[0].SourceEnd + 1 != topologyBreak.LastTwoContourVirtualFrame ||
            right[1].SourceStart + 1 != topologyBreak.FirstOneContourVirtualFrame)
        {
            throw new InvalidDataException(
                $"{path} does not align with topologyBreak.");
        }
        return result;
    }

    private static IReadOnlyList<PlayerInfoPaletteState> LoadPaletteStates(
        JsonElement states,
        IReadOnlyList<PlayerInfoRimVariant> rimVariants,
        IReadOnlyList<PlayerInfoSvgAsset> assets)
    {
        const string path = "$.gauges.mp.paletteStates";
        if (states.GetArrayLength() != 3)
        {
            throw new InvalidDataException($"{path} must contain frames 1/70/91.");
        }
        var result = new List<PlayerInfoPaletteState>(3);
        var starts = new HashSet<int>();
        var index = 0;
        foreach (var value in states.EnumerateArray())
        {
            var itemPath = $"{path}[{index}]";
            var item = RequireObject(value, itemPath);
            RequireExactProperties(
                item,
                itemPath,
                "startVirtualFrame",
                "rimAssetId",
                "label",
                "percent",
                "current",
                "max",
                "decoration",
                "decorativeCurrent",
                "decorativeMax");
            var rimVariant = rimVariants[index];
            var start = RequireInt32(
                item,
                "startVirtualFrame",
                itemPath,
                rimVariant.StartVirtualFrame);
            var rimAssetId = RequireString(
                item,
                "rimAssetId",
                itemPath,
                rimVariant.AssetId);
            if (!starts.Add(start))
            {
                throw new InvalidDataException(
                    $"{itemPath}.startVirtualFrame is duplicated.");
            }
            var state = new PlayerInfoPaletteState(
                start,
                rimAssetId,
                RequireCanonicalColor(item, "label", itemPath),
                RequireCanonicalColor(item, "percent", itemPath),
                RequireCanonicalColor(item, "current", itemPath),
                RequireCanonicalColor(item, "max", itemPath),
                RequireCanonicalColor(item, "decoration", itemPath),
                LoadColorAlpha(
                    RequireObjectProperty(item, "decorativeCurrent", itemPath),
                    itemPath + ".decorativeCurrent"),
                LoadColorAlpha(
                    RequireObjectProperty(item, "decorativeMax", itemPath),
                    itemPath + ".decorativeMax"));
            RequireOnlySvgPathFill(
                GetAsset(assets, rimAssetId),
                state.Decoration,
                itemPath + ".decoration");
            result.Add(state);
            index++;
        }
        return result;
    }

    private static PlayerInfoColorAlpha LoadColorAlpha(
        JsonElement item,
        string path)
    {
        RequireExactProperties(item, path, "color", "alpha");
        var color = RequireCanonicalColor(item, "color", path);
        var alpha = RequireFiniteDouble(item, "alpha", path);
        if (alpha is < 0 or > 1)
        {
            throw new InvalidDataException($"{path}.alpha must be within 0..1.");
        }
        return new PlayerInfoColorAlpha(color, alpha);
    }

    private static PlayerInfoEffectPolicy LoadEffectPolicy(
        JsonElement root,
        IReadOnlyList<PlayerInfoSvgAsset> assets)
    {
        const string path = "$.effectPolicy";
        var policy = RequireObjectProperty(root, "effectPolicy", "$");
        RequireExactProperties(policy, path, "includedStatic", "programmaticLayers");

        var includedArray = RequireArrayProperty(policy, "includedStatic", path);
        if (includedArray.GetArrayLength() != 1)
        {
            throw new InvalidDataException(
                $"{path}.includedStatic must contain the HP bevel.");
        }
        var includedPath = path + ".includedStatic[0]";
        var includedObject = RequireObject(includedArray[0], includedPath);
        RequireExactProperties(
            includedObject,
            includedPath,
            "id",
            "implementation",
            "assetId",
            "svgGroupId");
        var included = new PlayerInfoIncludedStaticEffect(
            RequireString(
                includedObject,
                "id",
                includedPath,
                "hp-border-bevel"),
            RequireString(
                includedObject,
                "implementation",
                includedPath,
                "expanded-vector-gradient"),
            RequireString(
                includedObject,
                "assetId",
                includedPath,
                "hp.rim"),
            RequireString(
                includedObject,
                "svgGroupId",
                includedPath,
                "hp-rim-static-bevel-expanded"));
        RequireExactSvgId(
            GetAsset(assets, included.AssetId),
            included.SvgGroupId,
            element => element.Name.LocalName == "g",
            includedPath + ".svgGroupId");

        var programmaticArray = RequireArrayProperty(
            policy,
            "programmaticLayers",
            path);
        if (programmaticArray.GetArrayLength() != 3)
        {
            throw new InvalidDataException(
                $"{path}.programmaticLayers must contain three entries.");
        }
        var expected = new[]
        {
            (
                Id: "hp-horizontal-line-glow",
                Owner: "native-effect",
                After: "hp.fill",
                Before: "hp.rim",
                Blend: "source-over",
                Disposition: PlayerInfoProgrammaticEffectDisposition.DeferredB3),
            (
                Id: "hp-light-overlay",
                Owner: "native-effect",
                After: "hp.fill",
                Before: "hp.rim",
                Blend: "overlay",
                Disposition: PlayerInfoProgrammaticEffectDisposition.DeferredB3),
            (
                Id: "hp-mp-dynamic-text-and-glow",
                Owner: "native-draw",
                After: "gauge-static-layers",
                Before: (string?)null,
                Blend: "source-over",
                Disposition: PlayerInfoProgrammaticEffectDisposition.ImplementedActive)
        };
        var programmatic = new List<PlayerInfoProgrammaticEffect>(3);
        var effectIds = new HashSet<string>(StringComparer.Ordinal)
        {
            included.Id
        };
        for (var index = 0; index < expected.Length; index++)
        {
            var itemPath = $"{path}.programmaticLayers[{index}]";
            var item = RequireObject(programmaticArray[index], itemPath);
            if (expected[index].Before is null)
            {
                RequireExactProperties(
                    item,
                    itemPath,
                    "id",
                    "rendererOwner",
                    "compositeAfter",
                    "blendMode");
            }
            else
            {
                RequireExactProperties(
                    item,
                    itemPath,
                    "id",
                    "rendererOwner",
                    "compositeAfter",
                    "compositeBefore",
                    "blendMode");
            }
            var effect = new PlayerInfoProgrammaticEffect(
                RequireString(item, "id", itemPath, expected[index].Id),
                RequireString(
                    item,
                    "rendererOwner",
                    itemPath,
                    expected[index].Owner),
                RequireString(
                    item,
                    "compositeAfter",
                    itemPath,
                    expected[index].After),
                expected[index].Before is null
                    ? null
                    : RequireString(
                        item,
                        "compositeBefore",
                        itemPath,
                        expected[index].Before),
                RequireString(
                    item,
                    "blendMode",
                    itemPath,
                    expected[index].Blend),
                expected[index].Disposition);
            if (!effectIds.Add(effect.Id))
            {
                throw new InvalidDataException($"{itemPath}.id is duplicated.");
            }
            programmatic.Add(effect);
        }

        return new PlayerInfoEffectPolicy([included], programmatic);
    }

    private static void ValidateExactResourceSet(Assembly assembly)
    {
        var actual = assembly.GetManifestResourceNames()
            .Where(name => name.StartsWith(ResourcePrefix + ".", StringComparison.Ordinal))
            .ToArray();
        ValidateExactResourceNames(actual);
    }

    private static void ValidateExactResourceNames(IEnumerable<string> resourceNames)
    {
        var expected = ExpectedAssets
            .Select(asset => asset.ResourceName)
            .Append(ManifestResourceName)
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        var actual = resourceNames
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        var missing = expected.Except(actual, StringComparer.Ordinal).ToArray();
        var unexpected = actual.Except(expected, StringComparer.Ordinal).ToArray();
        if (missing.Length != 0 || unexpected.Length != 0)
        {
            throw new InvalidDataException(
                "PlayerInfo resource set mismatch: " +
                $"missing=[{string.Join(",", missing)}] unexpected=[{string.Join(",", unexpected)}].");
        }
    }

    private static void ValidateNoRepoOnlyResources(Assembly assembly)
    {
        ValidateNoRepoOnlyResourceNames(assembly.GetManifestResourceNames());
    }

    internal static void ValidateNoRepoOnlyResourceNames(
        IEnumerable<string> resourceNames)
    {
        var forbidden = resourceNames
            .Where(name =>
                name.Contains("PlayerInfo", StringComparison.OrdinalIgnoreCase) &&
                (name.Contains("provenance", StringComparison.OrdinalIgnoreCase) ||
                  name.Contains("evidence", StringComparison.OrdinalIgnoreCase) ||
                  name.Contains("oracle", StringComparison.OrdinalIgnoreCase) ||
                  name.Contains("fixture", StringComparison.OrdinalIgnoreCase)))
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        if (forbidden.Length != 0)
        {
            throw new InvalidDataException(
                "Repo-only PlayerInfo fixture/provenance/evidence resource is embedded: " +
                string.Join(",", forbidden) + ".");
        }
    }

    private static byte[] ReadResource(Assembly assembly, string resourceName)
    {
        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidDataException(
                $"Embedded PlayerInfo resource is missing: {resourceName}.");
        if (!stream.CanRead || stream.Length is <= 0 or > MaxEmbeddedResourceBytes)
        {
            throw new InvalidDataException(
                $"Embedded PlayerInfo resource has an invalid byte length: {resourceName}.");
        }

        var bytes = new byte[checked((int)stream.Length)];
        stream.ReadExactly(bytes);
        if (stream.ReadByte() != -1)
        {
            throw new InvalidDataException(
                $"Embedded PlayerInfo resource length changed while reading: {resourceName}.");
        }
        return bytes;
    }

    private static string ComputeAssetSetRevision(IEnumerable<PlayerInfoSvgAsset> assets)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var asset in assets.OrderBy(item => item.RelativePath, StringComparer.Ordinal))
        {
            hash.AppendData(StrictUtf8.GetBytes(asset.RelativePath));
            hash.AppendData([0]);
            hash.AppendData(asset.Bytes.Span);
            hash.AppendData([0]);
        }
        return Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant();
    }

    private static string Sha256Lower(ReadOnlySpan<byte> bytes) =>
        Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    private static void ValidateFrameMap(PlayerInfoFrameMap frameMap, string path)
    {
        if (frameMap.StepCount <= 0 ||
            frameMap.VirtualFrameCount != frameMap.StepCount + 1 ||
            frameMap.FullVirtualFrame != 1 ||
            frameMap.EmptyVirtualFrame != frameMap.VirtualFrameCount ||
            frameMap.SourceFrameOffset is not (null or -1) ||
            !frameMap.Reverse ||
            !string.Equals(frameMap.Rounding, "floor", StringComparison.Ordinal))
        {
            throw new InvalidDataException($"{path} is internally inconsistent.");
        }
    }

    private static PlayerInfoSvgAsset GetAsset(
        IReadOnlyList<PlayerInfoSvgAsset> assets,
        string id) =>
        assets.SingleOrDefault(asset =>
            string.Equals(asset.Id, id, StringComparison.Ordinal))
        ?? throw new InvalidDataException(
            $"PlayerInfo manifest references unknown asset '{id}'.");

    private static XDocument ParseSvgDocument(PlayerInfoSvgAsset asset)
    {
        try
        {
            using var stream = new MemoryStream(asset.Bytes.ToArray(), writable: false);
            var settings = new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null,
                MaxCharactersInDocument = MaxEmbeddedResourceBytes
            };
            using var reader = XmlReader.Create(stream, settings);
            return XDocument.Load(reader, LoadOptions.PreserveWhitespace);
        }
        catch (Exception exception) when (
            exception is XmlException or InvalidOperationException)
        {
            throw new InvalidDataException(
                $"PlayerInfo asset '{asset.Id}' is not well-formed SVG XML.",
                exception);
        }
    }

    private static void RequireExactSvgId(
        PlayerInfoSvgAsset asset,
        string id,
        Func<XElement, bool> predicate,
        string path)
    {
        var matches = ParseSvgDocument(asset)
            .Descendants()
            .Where(element =>
                string.Equals(
                    element.Attribute("id")?.Value,
                    id,
                    StringComparison.Ordinal))
            .ToArray();
        if (matches.Length != 1 || !predicate(matches[0]))
        {
            throw new InvalidDataException(
                $"{path} requires exactly one matching SVG element #{id}.");
        }
    }

    private static void RequireOnlySvgPathFill(
        PlayerInfoSvgAsset asset,
        string expectedFill,
        string path)
    {
        var fills = ParseSvgDocument(asset)
            .Descendants()
            .Where(element => element.Name.LocalName == "path")
            .Select(element => element.Attribute("fill")?.Value)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (fills.Length != 1 ||
            !string.Equals(fills[0], expectedFill, StringComparison.Ordinal))
        {
            throw new InvalidDataException(
                $"{path} does not match the authored rim fill.");
        }
    }

    private static IReadOnlyList<PlayerInfoSvgPoint> RequireClosedTwipContour(
        JsonElement value,
        string path)
    {
        if (value.GetArrayLength() < 4)
        {
            throw new InvalidDataException(
                $"{path} must contain a closed contour.");
        }
        var points = new List<PlayerInfoSvgPoint>();
        var index = 0;
        foreach (var pointValue in value.EnumerateArray())
        {
            if (pointValue.ValueKind != JsonValueKind.Array ||
                pointValue.GetArrayLength() != 2)
            {
                throw new InvalidDataException(
                    $"{path}[{index}] must be an integer x/y pair.");
            }
            var coordinates = pointValue.EnumerateArray().ToArray();
            if (!coordinates[0].TryGetInt32(out var x) ||
                !coordinates[1].TryGetInt32(out var y) ||
                Math.Abs((long)x) > 1_000_000 ||
                Math.Abs((long)y) > 1_000_000)
            {
                throw new InvalidDataException(
                    $"{path}[{index}] must contain bounded integer twips.");
            }
            points.Add(new PlayerInfoSvgPoint(x, y));
            index++;
        }
        if (points[0] != points[^1])
        {
            throw new InvalidDataException($"{path} must be explicitly closed.");
        }
        return points;
    }

    private static JsonElement RequireArrayProperty(
        JsonElement parent,
        string propertyName,
        string parentPath)
    {
        if (!parent.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must be an array.");
        }
        return value;
    }

    private static void RequireExactProperties(
        JsonElement item,
        string path,
        params string[] propertyNames)
    {
        var expected = propertyNames.ToHashSet(StringComparer.Ordinal);
        var actual = item.EnumerateObject()
            .Select(property => property.Name)
            .ToArray();
        var unknown = actual
            .Where(name => !expected.Contains(name))
            .ToArray();
        var missing = propertyNames
            .Where(name => !actual.Contains(name, StringComparer.Ordinal))
            .ToArray();
        if (unknown.Length != 0 || missing.Length != 0)
        {
            throw new InvalidDataException(
                $"{path} property closure drifted; " +
                $"unknown=[{string.Join(",", unknown)}] " +
                $"missing=[{string.Join(",", missing)}].");
        }
    }

    private static IReadOnlyList<string> RequireExactStringArray(
        JsonElement parent,
        string propertyName,
        string parentPath,
        params string[] expected)
    {
        var actual = RequireStringArray(parent, propertyName, parentPath);
        if (!actual.SequenceEqual(expected, StringComparer.Ordinal))
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} values/order drifted.");
        }
        if (actual.Distinct(StringComparer.Ordinal).Count() != actual.Count)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} contains duplicates.");
        }
        return actual;
    }

    private static PlayerInfoSvgPoint RequireExactPointArray(
        JsonElement parent,
        string propertyName,
        string parentPath,
        double expectedX,
        double expectedY)
    {
        var point = RequirePointArray(parent, propertyName, parentPath);
        if (point != new PlayerInfoSvgPoint(expectedX, expectedY))
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} drifted.");
        }
        return point;
    }

    private static double RequireExactFiniteDouble(
        JsonElement parent,
        string propertyName,
        string parentPath,
        double expected)
    {
        var actual = RequireFiniteDouble(parent, propertyName, parentPath);
        if (actual != expected)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must equal {expected}.");
        }
        return actual;
    }

    private static string RequireCanonicalColor(
        JsonElement parent,
        string propertyName,
        string parentPath)
    {
        var value = RequireString(parent, propertyName, parentPath);
        if (value.Length != 7 ||
            value[0] != '#' ||
            value.Skip(1).Any(character =>
                character is not (>= '0' and <= '9') and
                    not (>= 'A' and <= 'F')))
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must be canonical #RRGGBB.");
        }
        return value;
    }

    private static JsonElement RequireObject(JsonElement value, string path)
    {
        if (value.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException($"{path} must be an object.");
        }
        return value;
    }

    private static JsonElement RequireObjectProperty(
        JsonElement parent,
        string propertyName,
        string parentPath)
    {
        if (!parent.TryGetProperty(propertyName, out var value))
        {
            throw new InvalidDataException($"{parentPath}.{propertyName} is required.");
        }
        return RequireObject(value, $"{parentPath}.{propertyName}");
    }

    private static string RequireString(
        JsonElement parent,
        string propertyName,
        string parentPath,
        string? expected = null)
    {
        if (!parent.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.String)
        {
            throw new InvalidDataException($"{parentPath}.{propertyName} must be a string.");
        }
        var actual = value.GetString()
            ?? throw new InvalidDataException($"{parentPath}.{propertyName} must not be null.");
        if (expected is not null && !string.Equals(actual, expected, StringComparison.Ordinal))
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must equal '{expected}'.");
        }
        return actual;
    }

    private static int RequireInt32(
        JsonElement parent,
        string propertyName,
        string parentPath,
        int expected)
    {
        if (!parent.TryGetProperty(propertyName, out var value) ||
            !value.TryGetInt32(out var actual))
        {
            throw new InvalidDataException($"{parentPath}.{propertyName} must be an integer.");
        }
        if (actual != expected)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must equal {expected}.");
        }
        return actual;
    }

    private static int RequirePositiveInt32(
        JsonElement parent,
        string propertyName,
        string parentPath,
        int expected)
    {
        var actual = RequireInt32(parent, propertyName, parentPath, expected);
        if (actual <= 0)
        {
            throw new InvalidDataException($"{parentPath}.{propertyName} must be positive.");
        }
        return actual;
    }

    private static int RequireNonNegativeInt32(
        JsonElement parent,
        string propertyName,
        string parentPath)
    {
        if (!parent.TryGetProperty(propertyName, out var value) ||
            !value.TryGetInt32(out var actual) ||
            actual < 0)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must be a non-negative integer.");
        }
        return actual;
    }

    private static double RequireFiniteDouble(
        JsonElement parent,
        string propertyName,
        string parentPath)
    {
        if (!parent.TryGetProperty(propertyName, out var value) ||
            !value.TryGetDouble(out var actual) ||
            !double.IsFinite(actual))
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must be a finite number.");
        }
        return actual;
    }

    private static bool RequireBoolean(
        JsonElement parent,
        string propertyName,
        string parentPath,
        bool expected)
    {
        if (!parent.TryGetProperty(propertyName, out var value) ||
            value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must be a boolean.");
        }
        var actual = value.GetBoolean();
        if (actual != expected)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must equal {expected.ToString().ToLowerInvariant()}.");
        }
        return actual;
    }

    private static IReadOnlyList<string> RequireStringArray(
        JsonElement parent,
        string propertyName,
        string parentPath)
    {
        if (!parent.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must be an array.");
        }
        var values = new List<string>();
        var index = 0;
        foreach (var item in value.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String ||
                string.IsNullOrEmpty(item.GetString()))
            {
                throw new InvalidDataException(
                    $"{parentPath}.{propertyName}[{index}] must be a non-empty string.");
            }
            values.Add(item.GetString()!);
            index++;
        }
        if (values.Count == 0)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must not be empty.");
        }
        return values;
    }

    private static double[] RequireNumberArray(
        JsonElement parent,
        string propertyName,
        string parentPath,
        int expectedLength)
    {
        if (!parent.TryGetProperty(propertyName, out var value) ||
            value.ValueKind != JsonValueKind.Array ||
            value.GetArrayLength() != expectedLength)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must contain exactly {expectedLength} numbers.");
        }
        var values = new double[expectedLength];
        var index = 0;
        foreach (var item in value.EnumerateArray())
        {
            if (!item.TryGetDouble(out var number) || !double.IsFinite(number))
            {
                throw new InvalidDataException(
                    $"{parentPath}.{propertyName}[{index}] must be a finite number.");
            }
            values[index++] = number;
        }
        return values;
    }

    private static PlayerInfoSvgRect RequireRectArray(
        JsonElement parent,
        string propertyName,
        string parentPath,
        bool positiveSize)
    {
        var values = RequireNumberArray(parent, propertyName, parentPath, 4);
        if (positiveSize && (values[2] <= 0 || values[3] <= 0))
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} width and height must be positive.");
        }
        return new PlayerInfoSvgRect(values[0], values[1], values[2], values[3]);
    }

    private static PlayerInfoSvgRect RequireEdgeRectArray(
        JsonElement parent,
        string propertyName,
        string parentPath)
    {
        var values = RequireNumberArray(parent, propertyName, parentPath, 4);
        if (values[2] < values[0] || values[3] < values[1])
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must be [left,top,right,bottom].");
        }
        return PlayerInfoSvgRect.FromEdges(
            values[0],
            values[1],
            values[2],
            values[3]);
    }

    private static PlayerInfoSvgPoint RequirePointArray(
        JsonElement parent,
        string propertyName,
        string parentPath)
    {
        var values = RequireNumberArray(parent, propertyName, parentPath, 2);
        return new PlayerInfoSvgPoint(values[0], values[1]);
    }

    private static PlayerInfoSvgMatrix RequireMatrixArray(
        JsonElement parent,
        string propertyName,
        string parentPath)
    {
        var values = RequireNumberArray(parent, propertyName, parentPath, 6);
        var matrix = new PlayerInfoSvgMatrix(
            values[0],
            values[1],
            values[2],
            values[3],
            values[4],
            values[5]);
        if (!matrix.IsUniformScaleTranslation)
        {
            throw new InvalidDataException(
                $"{parentPath}.{propertyName} must be a positive uniform-scale translation matrix.");
        }
        return matrix;
    }

    private static string RequireLowerSha256(string value, string path)
    {
        if (value.Length != 64 || value.Any(character =>
                character is not (>= '0' and <= '9') and
                    not (>= 'a' and <= 'f')))
        {
            throw new InvalidDataException($"{path} must be a lowercase SHA-256 digest.");
        }
        return value;
    }

    private static void EnsureNoDuplicateProperties(JsonElement element, string path)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in element.EnumerateObject())
            {
                if (!names.Add(property.Name))
                {
                    throw new InvalidDataException(
                        $"{path} contains duplicate property '{property.Name}'.");
                }
                EnsureNoDuplicateProperties(property.Value, $"{path}.{property.Name}");
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            var index = 0;
            foreach (var item in element.EnumerateArray())
            {
                EnsureNoDuplicateProperties(item, $"{path}[{index}]");
                index++;
            }
        }
    }

    private sealed record ExpectedAsset(
        string Id,
        string RelativePath,
        string ResourceName);
}

internal static class PlayerInfoSvgAssetContract
{
    internal static PlayerInfoSvgAssetSet LoadProductionEmbedded(bool minimumRaster) =>
        LoadAndValidate(typeof(PlayerInfoSvgAssetContract).Assembly, minimumRaster);

    internal static PlayerInfoSvgAssetSet LoadAndValidate(
        Assembly assembly,
        bool minimumRaster)
    {
        var assetSet = PlayerInfoSvgAssetCatalog.LoadFromAssembly(assembly);
        foreach (var asset in assetSet.Assets)
        {
            using var svg = StrictSvgFacade.Load(asset.Bytes);
            if (minimumRaster)
            {
                using var bitmap = svg.Rasterize(1, 1);
            }
        }
        return assetSet;
    }
}

internal sealed class PlayerInfoSvgAssetSet(
    string assetSetId,
    string revision,
    string exactManifestSha256,
    int rasterContractVersion,
    string featureSet,
    IReadOnlyList<string> runtimeCacheIdentityComponents,
    PlayerInfoRendererIdentity rendererIdentity,
    PlayerInfoSvgUnits units,
    PlayerInfoSvgStage stage,
    IReadOnlyDictionary<string, PlayerInfoSvgGauge> gauges,
    PlayerInfoEffectPolicy effectPolicy,
    byte[] manifestBytes,
    IReadOnlyList<PlayerInfoSvgAsset> assets)
{
    internal string AssetSetId { get; } = assetSetId;
    internal string Revision { get; } = revision;
    internal string ExactManifestSha256 { get; } = exactManifestSha256;
    internal int RasterContractVersion { get; } = rasterContractVersion;
    internal string FeatureSet { get; } = featureSet;
    internal IReadOnlyList<string> RuntimeCacheIdentityComponents { get; } =
        runtimeCacheIdentityComponents;
    internal PlayerInfoRendererIdentity RendererIdentity { get; } = rendererIdentity;
    internal PlayerInfoSvgUnits Units { get; } = units;
    internal PlayerInfoSvgStage Stage { get; } = stage;
    internal IReadOnlyDictionary<string, PlayerInfoSvgGauge> Gauges { get; } = gauges;
    internal PlayerInfoEffectPolicy EffectPolicy { get; } = effectPolicy;
    internal ReadOnlyMemory<byte> ManifestBytes { get; } = manifestBytes;
    internal IReadOnlyList<PlayerInfoSvgAsset> Assets { get; } = assets;
}

internal sealed class PlayerInfoSvgAsset(
    string id,
    string relativePath,
    string resourceName,
    string sha256,
    byte[] bytes,
    PlayerInfoSvgRect viewBox,
    PlayerInfoSvgRect sourceGeometryBounds,
    PlayerInfoSvgPoint registration,
    int gaugeLayerOrder,
    string blendMode,
    double opacity,
    bool cacheable)
{
    internal string Id { get; } = id;
    internal string RelativePath { get; } = relativePath;
    internal string ResourceName { get; } = resourceName;
    internal string Sha256 { get; } = sha256;
    internal ReadOnlyMemory<byte> Bytes { get; } = bytes;
    internal PlayerInfoSvgRect ViewBox { get; } = viewBox;
    internal PlayerInfoSvgRect SourceGeometryBounds { get; } = sourceGeometryBounds;
    internal PlayerInfoSvgPoint Registration { get; } = registration;
    internal int GaugeLayerOrder { get; } = gaugeLayerOrder;
    internal string BlendMode { get; } = blendMode;
    internal double Opacity { get; } = opacity;
    internal bool Cacheable { get; } = cacheable;
}

internal readonly record struct PlayerInfoSvgPoint(double X, double Y);

internal sealed record PlayerInfoSvgUnits(
    string SvgUnit,
    int SourceTwipsPerSvgUnit);

internal readonly record struct PlayerInfoSvgRect(
    double X,
    double Y,
    double Width,
    double Height)
{
    internal double Left => X;
    internal double Top => Y;
    internal double Right => X + Width;
    internal double Bottom => Y + Height;

    internal static PlayerInfoSvgRect FromEdges(
        double left,
        double top,
        double right,
        double bottom) =>
        new(left, top, right - left, bottom - top);
}

internal readonly record struct PlayerInfoSvgMatrix(
    double A,
    double B,
    double C,
    double D,
    double Tx,
    double Ty)
{
    internal bool IsUniformScaleTranslation =>
        B == 0 &&
        C == 0 &&
        A > 0 &&
        A == D;

    internal PlayerInfoSvgPoint Transform(PlayerInfoSvgPoint point) =>
        new(
            (A * point.X) + (C * point.Y) + Tx,
            (B * point.X) + (D * point.Y) + Ty);

    internal PlayerInfoSvgRect TransformBounds(PlayerInfoSvgRect rect)
    {
        var topLeft = Transform(new PlayerInfoSvgPoint(rect.Left, rect.Top));
        var bottomRight = Transform(new PlayerInfoSvgPoint(rect.Right, rect.Bottom));
        return PlayerInfoSvgRect.FromEdges(
            Math.Min(topLeft.X, bottomRight.X),
            Math.Min(topLeft.Y, bottomRight.Y),
            Math.Max(topLeft.X, bottomRight.X),
            Math.Max(topLeft.Y, bottomRight.Y));
    }
}

internal sealed class PlayerInfoSvgStage(
    int logicalWidth,
    int logicalHeight,
    IReadOnlyList<string> compositeOrder)
{
    internal int LogicalWidth { get; } = logicalWidth;
    internal int LogicalHeight { get; } = logicalHeight;
    internal IReadOnlyList<string> CompositeOrder { get; } = compositeOrder;
}

internal sealed class PlayerInfoSvgGauge(
    string id,
    PlayerInfoSvgMatrix stageMatrix,
    IReadOnlyList<string> assetIds,
    PlayerInfoFrameMap frameMap)
{
    internal string Id { get; } = id;
    internal PlayerInfoSvgMatrix StageMatrix { get; } = stageMatrix;
    internal IReadOnlyList<string> AssetIds { get; } = assetIds;
    internal PlayerInfoFrameMap FrameMap { get; } = frameMap;
    internal PlayerInfoRadialClip? Clip { get; init; }
    internal PlayerInfoFillTextureRotation? FillTextureRotation { get; init; }
    internal IReadOnlyList<PlayerInfoRimVariant> RimVariants { get; init; } = [];
    internal string? MaskPaintSemantics { get; init; }
    internal IReadOnlyList<PlayerInfoClipBinding> ClipBindings { get; init; } = [];
    internal PlayerInfoTopologyBreak? TopologyBreak { get; init; }
    internal PlayerInfoTerminalEmpty? TerminalEmpty { get; init; }
    internal IReadOnlyList<PlayerInfoMorphInterval> MorphIntervals { get; init; } = [];
    internal IReadOnlyList<PlayerInfoPaletteState> PaletteStates { get; init; } = [];
}

internal sealed record PlayerInfoFrameMap(
    int StepCount,
    int VirtualFrameCount,
    int FullVirtualFrame,
    int EmptyVirtualFrame,
    int? SourceFrameOffset,
    bool Reverse,
    string Rounding);

internal sealed record PlayerInfoRadialClip(
    string Type,
    PlayerInfoSvgPoint Center,
    double Radius,
    double StartAngleDegrees,
    string Direction);

internal sealed record PlayerInfoFillTextureRotation(
    string AssetId,
    IReadOnlyList<string> SvgGradientIds,
    PlayerInfoSvgPoint Pivot,
    int SourceFrameOffset,
    double DegreesPerSourceFrame,
    string PositiveDirection);

internal sealed record PlayerInfoRimVariant(
    int StartVirtualFrame,
    string AssetId);

internal sealed record PlayerInfoClipBinding(
    string Id,
    string AssetId,
    IReadOnlyList<string> SvgGroupIds);

internal sealed record PlayerInfoTopologyBreak(
    int LastTwoContourVirtualFrame,
    int FirstOneContourVirtualFrame,
    string Policy);

internal sealed record PlayerInfoTerminalEmpty(
    int PreviousSourceFrame,
    int EmptySourceFrame,
    int EmptyVirtualFrame);

internal sealed record PlayerInfoMorphCorrespondence(
    IReadOnlyList<PlayerInfoSvgPoint> AStartAndAnchorsTwips,
    IReadOnlyList<PlayerInfoSvgPoint> BStartAndAnchorsTwips);

internal sealed record PlayerInfoMorphInterval(
    string MaskId,
    int SourceStart,
    int SourceEnd,
    string Interpolation,
    IReadOnlyList<PlayerInfoMorphCorrespondence> Correspondence);

internal sealed record PlayerInfoColorAlpha(
    string Color,
    double Alpha);

internal sealed record PlayerInfoPaletteState(
    int StartVirtualFrame,
    string RimAssetId,
    string Label,
    string Percent,
    string Current,
    string Max,
    string Decoration,
    PlayerInfoColorAlpha DecorativeCurrent,
    PlayerInfoColorAlpha DecorativeMax);

internal sealed record PlayerInfoIncludedStaticEffect(
    string Id,
    string Implementation,
    string AssetId,
    string SvgGroupId);

internal enum PlayerInfoProgrammaticEffectDisposition
{
    ImplementedActive,
    DeferredB3
}

internal sealed record PlayerInfoProgrammaticEffect(
    string Id,
    string RendererOwner,
    string CompositeAfter,
    string? CompositeBefore,
    string BlendMode,
    PlayerInfoProgrammaticEffectDisposition Disposition);

internal sealed record PlayerInfoEffectPolicy(
    IReadOnlyList<PlayerInfoIncludedStaticEffect> IncludedStatic,
    IReadOnlyList<PlayerInfoProgrammaticEffect> ProgrammaticLayers)
{
    internal IReadOnlyList<PlayerInfoProgrammaticEffect> ImplementedActiveLayers { get; } =
        ProgrammaticLayers
            .Where(effect =>
                effect.Disposition ==
                PlayerInfoProgrammaticEffectDisposition.ImplementedActive)
            .ToArray();

    internal IReadOnlyList<PlayerInfoProgrammaticEffect> DeferredB3Layers { get; } =
        ProgrammaticLayers
            .Where(effect =>
                effect.Disposition ==
                PlayerInfoProgrammaticEffectDisposition.DeferredB3)
            .ToArray();
}

internal sealed class PlayerInfoRendererIdentity(
    string package,
    string version,
    string skiaSharpVersion,
    string featureSet,
    string colorType,
    string alphaType)
{
    internal string Package { get; } = package;
    internal string Version { get; } = version;
    internal string SkiaSharpVersion { get; } = skiaSharpVersion;
    internal string FeatureSet { get; } = featureSet;
    internal string ColorType { get; } = colorType;
    internal string AlphaType { get; } = alphaType;
    internal string CacheIdentity { get; } =
        $"{package}/{version};SkiaSharp/{skiaSharpVersion};{featureSet};{colorType}/{alphaType}";
}
