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

        var renderer = RequireObjectProperty(root, "rendererContract", "$");
        RequireString(renderer, "package", "$.rendererContract", ExpectedRendererPackage);
        RequireString(renderer, "version", "$.rendererContract", ExpectedRendererVersion);
        RequireString(
            renderer,
            "skiaSharpVersion",
            "$.rendererContract",
            ExpectedSkiaSharpVersion);
        var featureSet = RequireString(
            renderer,
            "featureSet",
            "$.rendererContract",
            ExpectedFeatureSet);
        RequireString(renderer, "colorType", "$.rendererContract", "Bgra8888");
        RequireString(renderer, "alphaType", "$.rendererContract", "premultiplied");
        RequireString(renderer, "externalResources", "$.rendererContract", "forbidden");
        RequireString(renderer, "scripts", "$.rendererContract", "forbidden");
        RequireString(renderer, "runtimeTextElements", "$.rendererContract", "forbidden");

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
                bytes);
            index++;
        }

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
            manifestBytes,
            loadedAssets);
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
    byte[] manifestBytes,
    IReadOnlyList<PlayerInfoSvgAsset> assets)
{
    internal string AssetSetId { get; } = assetSetId;
    internal string Revision { get; } = revision;
    internal string ExactManifestSha256 { get; } = exactManifestSha256;
    internal int RasterContractVersion { get; } = rasterContractVersion;
    internal string FeatureSet { get; } = featureSet;
    internal ReadOnlyMemory<byte> ManifestBytes { get; } = manifestBytes;
    internal IReadOnlyList<PlayerInfoSvgAsset> Assets { get; } = assets;
}

internal sealed class PlayerInfoSvgAsset(
    string id,
    string relativePath,
    string resourceName,
    string sha256,
    byte[] bytes)
{
    internal string Id { get; } = id;
    internal string RelativePath { get; } = relativePath;
    internal string ResourceName { get; } = resourceName;
    internal string Sha256 { get; } = sha256;
    internal ReadOnlyMemory<byte> Bytes { get; } = bytes;
}
