#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

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

        var manifestBytes = ReadResource(assembly, ManifestResourceName);
        _ = StrictUtf8.GetString(manifestBytes);
        using var document = JsonDocument.Parse(manifestBytes, new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 64
        });
        EnsureNoDuplicateProperties(document.RootElement, "$");

        var root = RequireObject(document.RootElement, "$");
        RequireString(root, "format", "$", ExpectedFormat);
        RequireInt32(root, "schemaVersion", "$", 1);

        var assetSet = RequireObjectProperty(root, "assetSet", "$");
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

        var stageObject = RequireObjectProperty(root, "stage", "$");
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

            var bytes = ReadResource(assembly, expected.ResourceName);
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
            rendererIdentity,
            stage,
            gauges,
            manifestBytes,
            loadedAssets);
    }

    private static IReadOnlyDictionary<string, PlayerInfoSvgGauge> LoadGauges(
        JsonElement root,
        PlayerInfoSvgStage stage,
        IReadOnlyList<PlayerInfoSvgAsset> assets)
    {
        var gaugesObject = RequireObjectProperty(root, "gauges", "$");
        var knownAssetIds = assets
            .Select(asset => asset.Id)
            .ToHashSet(StringComparer.Ordinal);
        var assignedAssetIds = new HashSet<string>(StringComparer.Ordinal);
        var gauges = new Dictionary<string, PlayerInfoSvgGauge>(StringComparer.Ordinal);

        foreach (var gaugeId in stage.CompositeOrder)
        {
            if (!gauges.TryAdd(
                    gaugeId,
                    LoadGauge(
                        RequireObjectProperty(gaugesObject, gaugeId, "$.gauges"),
                        "$.gauges." + gaugeId,
                        gaugeId,
                        knownAssetIds,
                        assignedAssetIds)))
            {
                throw new InvalidDataException(
                    $"$.stage.compositeOrder contains duplicate gauge '{gaugeId}'.");
            }
        }

        var unexpectedGauges = gaugesObject.EnumerateObject()
            .Select(property => property.Name)
            .Except(gauges.Keys, StringComparer.Ordinal)
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        if (unexpectedGauges.Length != 0)
        {
            throw new InvalidDataException(
                "$.gauges contains entries outside stage.compositeOrder: " +
                string.Join(",", unexpectedGauges) + ".");
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

    private static PlayerInfoSvgGauge LoadGauge(
        JsonElement gaugeObject,
        string path,
        string gaugeId,
        IReadOnlySet<string> knownAssetIds,
        ISet<string> assignedAssetIds)
    {
        var assetIds = RequireStringArray(gaugeObject, "assetIds", path).ToList();
        if (gaugeObject.TryGetProperty("rimVariants", out var variants))
        {
            if (variants.ValueKind != JsonValueKind.Array)
            {
                throw new InvalidDataException($"{path}.rimVariants must be an array.");
            }
            var variantIndex = 0;
            foreach (var variant in variants.EnumerateArray())
            {
                var variantPath = $"{path}.rimVariants[{variantIndex}]";
                assetIds.Add(RequireString(
                    RequireObject(variant, variantPath),
                    "assetId",
                    variantPath));
                variantIndex++;
            }
        }

        var distinctAssetIds = new List<string>();
        var localIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var assetId in assetIds)
        {
            if (!knownAssetIds.Contains(assetId))
            {
                throw new InvalidDataException(
                    $"{path} references unknown asset '{assetId}'.");
            }
            if (!localIds.Add(assetId))
            {
                continue;
            }
            if (!assignedAssetIds.Add(assetId))
            {
                throw new InvalidDataException(
                    $"PlayerInfo asset '{assetId}' is assigned to multiple gauges.");
            }
            distinctAssetIds.Add(assetId);
        }
        if (distinctAssetIds.Count == 0)
        {
            throw new InvalidDataException($"{path}.assetIds must not be empty.");
        }

        return new PlayerInfoSvgGauge(
            gaugeId,
            RequireMatrixArray(gaugeObject, "stageMatrix", path),
            distinctAssetIds);
    }

    private static void ValidateExactResourceSet(Assembly assembly)
    {
        var expected = ExpectedAssets
            .Select(asset => asset.ResourceName)
            .Append(ManifestResourceName)
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        var actual = assembly.GetManifestResourceNames()
            .Where(name => name.StartsWith(ResourcePrefix + ".", StringComparison.Ordinal))
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        var missing = expected.Except(actual, StringComparer.Ordinal).ToArray();
        var unexpected = actual.Except(expected, StringComparer.Ordinal).ToArray();
        if (missing.Length != 0 || unexpected.Length != 0)
        {
            throw new InvalidDataException(
                "Embedded PlayerInfo resource set mismatch: " +
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
    PlayerInfoRendererIdentity rendererIdentity,
    PlayerInfoSvgStage stage,
    IReadOnlyDictionary<string, PlayerInfoSvgGauge> gauges,
    byte[] manifestBytes,
    IReadOnlyList<PlayerInfoSvgAsset> assets)
{
    internal string AssetSetId { get; } = assetSetId;
    internal string Revision { get; } = revision;
    internal string ExactManifestSha256 { get; } = exactManifestSha256;
    internal int RasterContractVersion { get; } = rasterContractVersion;
    internal string FeatureSet { get; } = featureSet;
    internal PlayerInfoRendererIdentity RendererIdentity { get; } = rendererIdentity;
    internal PlayerInfoSvgStage Stage { get; } = stage;
    internal IReadOnlyDictionary<string, PlayerInfoSvgGauge> Gauges { get; } = gauges;
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
    IReadOnlyList<string> assetIds)
{
    internal string Id { get; } = id;
    internal PlayerInfoSvgMatrix StageMatrix { get; } = stageMatrix;
    internal IReadOnlyList<string> AssetIds { get; } = assetIds;
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
