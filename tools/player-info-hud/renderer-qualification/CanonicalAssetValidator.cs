using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace Cf7.PlayerInfoHud.RendererQualification;

internal static class CanonicalAssetValidator
{
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly Regex LowerSha256 = new(
        "^[0-9a-f]{64}$",
        RegexOptions.CultureInvariant);
    private static readonly (string Id, string Path, int Order)[] ExpectedAssets =
    [
        ("hp.backplate", "hp/backplate.svg", 0),
        ("hp.fill", "hp/fill.svg", 1),
        ("hp.rim", "hp/rim.svg", 2),
        ("mp.backplate", "mp/backplate.svg", 0),
        ("mp.fill", "mp/fill.svg", 1),
        ("mp.rim", "mp/rim.svg", 2),
        ("mp.rim-vf70", "mp/rim-vf70.svg", 2),
        ("mp.rim-vf91", "mp/rim-vf91.svg", 2)
    ];

    internal static CanonicalAssetValidationResult Validate(string manifestPath)
    {
        var fullManifestPath = Path.GetFullPath(manifestPath);
        var assetRoot = Path.GetDirectoryName(fullManifestPath)
            ?? throw new InvalidDataException("Manifest has no parent directory.");
        var manifestBytes = File.ReadAllBytes(fullManifestPath);
        _ = StrictUtf8.GetString(manifestBytes);

        using var document = JsonDocument.Parse(manifestBytes, new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 64
        });
        RejectDuplicateProperties(document.RootElement, "$");
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
        RequireString(root, "format", "cf7.player-info-hud.asset-manifest", "$");
        RequireInteger(root, "schemaVersion", 1, "$");

        var assetSet = RequireObjectProperty(root, "assetSet", "$");
        RequireExactProperties(
            assetSet,
            "$.assetSet",
            "id",
            "revision",
            "revisionAlgorithm",
            "rasterContractVersion",
            "runtimeCacheIdentityComponents");
        RequireString(assetSet, "id", "player-info-hp-mp-b0", "$.assetSet");
        var revision = RequireString(assetSet, "revision", "$.assetSet");
        if (!revision.StartsWith("sha256:", StringComparison.Ordinal) ||
            !LowerSha256.IsMatch(revision["sha256:".Length..]))
        {
            throw new InvalidDataException("$.assetSet.revision must be lowercase sha256.");
        }
        RequireString(
            assetSet,
            "revisionAlgorithm",
            "sha256(sorted UTF-8 relative path + NUL + exact file bytes + NUL)",
            "$.assetSet");
        RequireInteger(assetSet, "rasterContractVersion", 1, "$.assetSet");
        RequireStringArray(
            assetSet,
            "runtimeCacheIdentityComponents",
            ["assetSet.revision", "exact-manifest-sha256"],
            "$.assetSet");

        var units = RequireObjectProperty(root, "units", "$");
        RequireExactProperties(units, "$.units", "svgUnit", "sourceTwipsPerSvgUnit");
        RequireString(units, "svgUnit", "logical-pixel", "$.units");
        RequireInteger(units, "sourceTwipsPerSvgUnit", 20, "$.units");

        var stage = RequireObjectProperty(root, "stage", "$");
        RequireExactProperties(
            stage,
            "$.stage",
            "logicalWidth",
            "logicalHeight",
            "compositeOrder");
        RequireInteger(stage, "logicalWidth", 1024, "$.stage");
        RequireInteger(stage, "logicalHeight", 64, "$.stage");
        RequireStringArray(stage, "compositeOrder", ["mp", "hp"], "$.stage");

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
        RequireString(renderer, "package", "Svg.Skia", "$.rendererContract");
        RequireString(renderer, "version", "5.1.1", "$.rendererContract");
        RequireString(renderer, "skiaSharpVersion", "3.119.4", "$.rendererContract");
        RequireString(
            renderer,
            "featureSet",
            "cf7-player-info-static-svg-v1",
            "$.rendererContract");
        RequireString(renderer, "colorType", "Bgra8888", "$.rendererContract");
        RequireString(renderer, "alphaType", "premultiplied", "$.rendererContract");
        RequireString(renderer, "externalResources", "forbidden", "$.rendererContract");
        RequireString(renderer, "scripts", "forbidden", "$.rendererContract");
        RequireString(renderer, "runtimeTextElements", "forbidden", "$.rendererContract");

        var assetsElement = RequireProperty(root, "assets", "$");
        if (assetsElement.ValueKind != JsonValueKind.Array ||
            assetsElement.GetArrayLength() != ExpectedAssets.Length)
        {
            throw new InvalidDataException("$.assets must be the exact eight-entry closure.");
        }

        var validatedAssets = new List<CanonicalAssetResult>();
        var revisionEntries = new List<(string Path, byte[] Bytes)>();
        using var revisionInput = new MemoryStream();
        var index = 0;
        foreach (var asset in assetsElement.EnumerateArray())
        {
            var context = $"$.assets[{index}]";
            var item = RequireObject(asset, context);
            RequireExactProperties(
                item,
                context,
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
            RequireString(item, "id", expected.Id, context);
            RequireString(item, "path", expected.Path, context);
            RequireInteger(item, "gaugeLayerOrder", expected.Order, context);
            RequireString(item, "blendMode", "source-over", context);
            RequireNumber(item, "opacity", 1, context);
            RequireBoolean(item, "cacheable", true, context);
            RequireNumberArray(item, "registration", [0, 0], context);

            var declaredSha = RequireString(item, "sha256", context);
            if (!LowerSha256.IsMatch(declaredSha))
            {
                throw new InvalidDataException($"{context}.sha256 must be lowercase SHA-256.");
            }
            var assetPath = ResolveAssetPath(assetRoot, expected.Path);
            var bytes = File.ReadAllBytes(assetPath);
            if (StrictUtf8.GetString(bytes).Contains("pending-oracle", StringComparison.Ordinal))
            {
                throw new InvalidDataException($"{context} contains an unresolved oracle token.");
            }
            var actualSha = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
            if (!string.Equals(actualSha, declaredSha, StringComparison.Ordinal))
            {
                throw new InvalidDataException($"{context} byte hash does not match the manifest.");
            }

            StrictSvgValidator.Validate(bytes);
            var svgDocument = XDocument.Parse(
                StrictUtf8.GetString(bytes),
                LoadOptions.PreserveWhitespace);
            var svgRoot = svgDocument.Root
                ?? throw new InvalidDataException($"{context} has no SVG root.");
            var declaredViewBox = RequireNumberArray(item, "viewBox", 4, context);
            var svgViewBox = ParseSvgNumberList(
                svgRoot.Attribute("viewBox")?.Value,
                4,
                $"{context} SVG viewBox");
            RequireSameNumbers(declaredViewBox, svgViewBox, $"{context}.viewBox");
            var geometryBounds = RequireNumberArray(item, "sourceGeometryBounds", 4, context);
            RequireContainedBounds(
                geometryBounds,
                declaredViewBox,
                $"{context}.sourceGeometryBounds");

            var semanticRootId = expected.Id.Replace('.', '-');
            var semanticRootCount = svgDocument
                .Descendants()
                .Count(element =>
                    string.Equals(
                        element.Attribute("id")?.Value,
                        semanticRootId,
                        StringComparison.Ordinal));
            if (semanticRootCount != 1)
            {
                throw new InvalidDataException(
                    $"{context} must contain exactly one #{semanticRootId} group.");
            }

            using var qualified = StrictSvgFacade.Load(bytes);
            var width = checked((int)Math.Round(ParseSvgNumber(svgRoot, "width")) * 2);
            var height = checked((int)Math.Round(ParseSvgNumber(svgRoot, "height")) * 2);
            using var bitmap = qualified.Rasterize(width, height);
            var nonTransparentPixels = CountNonTransparent(bitmap);
            if (nonTransparentPixels == 0)
            {
                throw new InvalidDataException($"{context} rasterized to a transparent bitmap.");
            }

            revisionEntries.Add((expected.Path, bytes));
            validatedAssets.Add(
                new CanonicalAssetResult(
                    expected.Id,
                    expected.Path,
                    bytes.Length,
                    actualSha,
                    nonTransparentPixels));
            index++;
        }

        foreach (var entry in revisionEntries.OrderBy(item => item.Path, StringComparer.Ordinal))
        {
            revisionInput.Write(StrictUtf8.GetBytes(entry.Path));
            revisionInput.WriteByte(0);
            revisionInput.Write(entry.Bytes);
            revisionInput.WriteByte(0);
        }
        var actualRevision = "sha256:" + Convert.ToHexString(
            SHA256.HashData(revisionInput.ToArray())).ToLowerInvariant();
        if (!string.Equals(actualRevision, revision, StringComparison.Ordinal))
        {
            throw new InvalidDataException("$.assetSet.revision does not bind the eight exact assets.");
        }

        var gauges = RequireObjectProperty(root, "gauges", "$");
        RequireExactProperties(gauges, "$.gauges", "hp", "mp");
        ValidateHpGauge(
            RequireObjectProperty(gauges, "hp", "$.gauges"),
            assetRoot);
        ValidateMpGauge(RequireObjectProperty(gauges, "mp", "$.gauges"), assetRoot);
        ValidateEffectPolicy(
            RequireObjectProperty(root, "effectPolicy", "$"),
            assetRoot);

        return new CanonicalAssetValidationResult(
            "canonical_assets_validated",
            Convert.ToHexString(SHA256.HashData(manifestBytes)).ToLowerInvariant(),
            revision,
            validatedAssets.Count,
            validatedAssets.Sum(asset => asset.Bytes),
            validatedAssets);
    }

    private static void ValidateHpGauge(JsonElement hp, string assetRoot)
    {
        const string context = "$.gauges.hp";
        RequireExactProperties(
            hp,
            context,
            "assetIds",
            "stageMatrix",
            "frameMap",
            "clip",
            "fillTextureRotation");
        RequireStringArray(
            hp,
            "assetIds",
            ["hp.backplate", "hp.fill", "hp.rim"],
            context);
        RequireNumberArray(
            hp,
            "stageMatrix",
            [0.847213745117188, 0, 0, 0.847213745117188, 37.75, 5.65],
            context);
        var frameMap = RequireObjectProperty(hp, "frameMap", context);
        RequireExactProperties(
            frameMap,
            $"{context}.frameMap",
            "stepCount",
            "virtualFrameCount",
            "fullVirtualFrame",
            "emptyVirtualFrame",
            "reverse",
            "rounding");
        RequireInteger(frameMap, "stepCount", 128, $"{context}.frameMap");
        RequireInteger(frameMap, "virtualFrameCount", 129, $"{context}.frameMap");
        RequireInteger(frameMap, "fullVirtualFrame", 1, $"{context}.frameMap");
        RequireInteger(frameMap, "emptyVirtualFrame", 129, $"{context}.frameMap");
        RequireBoolean(frameMap, "reverse", true, $"{context}.frameMap");
        RequireString(frameMap, "rounding", "floor", $"{context}.frameMap");

        var clip = RequireObjectProperty(hp, "clip", context);
        RequireExactProperties(
            clip,
            $"{context}.clip",
            "type",
            "center",
            "radius",
            "startAngleDegrees",
            "direction");
        RequireString(clip, "type", "radial-sector", $"{context}.clip");
        RequireNumberArray(clip, "center", [0, 0], $"{context}.clip");
        RequireNumber(clip, "radius", 128, $"{context}.clip");
        RequireNumber(clip, "startAngleDegrees", -90, $"{context}.clip");
        RequireString(
            clip,
            "direction",
            "counterclockwise",
            $"{context}.clip");

        var rotation = RequireObjectProperty(hp, "fillTextureRotation", context);
        RequireExactProperties(
            rotation,
            $"{context}.fillTextureRotation",
            "assetId",
            "svgGradientIds",
            "pivot",
            "sourceFrameOffset",
            "degreesPerSourceFrame",
            "positiveDirection");
        RequireString(rotation, "assetId", "hp.fill", $"{context}.fillTextureRotation");
        RequireStringArray(
            rotation,
            "svgGradientIds",
            ["hp-fill-gradient-0003"],
            $"{context}.fillTextureRotation");
        RequireNumberArray(
            rotation,
            "pivot",
            [0, 0],
            $"{context}.fillTextureRotation");
        RequireInteger(
            rotation,
            "sourceFrameOffset",
            -1,
            $"{context}.fillTextureRotation");
        RequireNumber(
            rotation,
            "degreesPerSourceFrame",
            2.8125,
            $"{context}.fillTextureRotation");
        RequireString(
            rotation,
            "positiveDirection",
            "clockwise",
            $"{context}.fillTextureRotation");
        var hpFill = XDocument.Load(
            ResolveAssetPath(assetRoot, "hp/fill.svg"),
            LoadOptions.PreserveWhitespace);
        var gradientCount = hpFill.Descendants().Count(element =>
            string.Equals(
                element.Attribute("id")?.Value,
                "hp-fill-gradient-0003",
                StringComparison.Ordinal) &&
            element.Name.LocalName is "linearGradient" or "radialGradient" &&
            element.Attribute("gradientTransform") is not null);
        if (gradientCount != 1)
        {
            throw new InvalidDataException(
                $"{context}.fillTextureRotation requires exactly one transformed SVG gradient.");
        }
    }

    private static void ValidateMpGauge(JsonElement mp, string assetRoot)
    {
        const string context = "$.gauges.mp";
        RequireExactProperties(
            mp,
            context,
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
        RequireStringArray(
            mp,
            "assetIds",
            ["mp.backplate", "mp.fill"],
            context);
        RequireNumberArray(
            mp,
            "stageMatrix",
            [1.0810546875, 0, 0, 1.0810546875, 90.1, -1.3],
            context);
        var frameMap = RequireObjectProperty(mp, "frameMap", context);
        RequireExactProperties(
            frameMap,
            $"{context}.frameMap",
            "stepCount",
            "virtualFrameCount",
            "fullVirtualFrame",
            "emptyVirtualFrame",
            "sourceFrameOffset",
            "reverse",
            "rounding");
        RequireInteger(frameMap, "stepCount", 100, $"{context}.frameMap");
        RequireInteger(frameMap, "virtualFrameCount", 101, $"{context}.frameMap");
        RequireInteger(frameMap, "fullVirtualFrame", 1, $"{context}.frameMap");
        RequireInteger(frameMap, "emptyVirtualFrame", 101, $"{context}.frameMap");
        RequireInteger(frameMap, "sourceFrameOffset", -1, $"{context}.frameMap");
        RequireBoolean(frameMap, "reverse", true, $"{context}.frameMap");
        RequireString(frameMap, "rounding", "floor", $"{context}.frameMap");
        ValidateRimVariants(RequireProperty(mp, "rimVariants", context), assetRoot);
        RequireString(mp, "maskPaintSemantics", "coverage-only", context);

        var bindings = RequireProperty(mp, "clipBindings", context);
        if (bindings.ValueKind != JsonValueKind.Array || bindings.GetArrayLength() != 2)
        {
            throw new InvalidDataException($"{context}.clipBindings must contain two masks.");
        }
        var expectedBindings = new[]
        {
            (
                "mp-left-mask",
                new[] {"mp-fill-left-background-copy", "mp-fill-left-slot"}),
            (
                "mp-right-mask",
                new[] {"mp-fill-right-decoration", "mp-fill-right-slot"})
        };
        var bindingIndex = 0;
        foreach (var binding in bindings.EnumerateArray())
        {
            var bindingContext = $"{context}.clipBindings[{bindingIndex}]";
            var item = RequireObject(binding, bindingContext);
            RequireExactProperties(item, bindingContext, "id", "assetId", "svgGroupIds");
            RequireString(item, "id", expectedBindings[bindingIndex].Item1, bindingContext);
            RequireString(item, "assetId", "mp.fill", bindingContext);
            RequireStringArray(
                item,
                "svgGroupIds",
                expectedBindings[bindingIndex].Item2,
                bindingContext);
            bindingIndex++;
        }
        var mpFill = XDocument.Load(
            ResolveAssetPath(assetRoot, "mp/fill.svg"),
            LoadOptions.PreserveWhitespace);
        foreach (var groupId in expectedBindings.SelectMany(binding => binding.Item2))
        {
            var count = mpFill.Descendants().Count(element =>
                string.Equals(element.Attribute("id")?.Value, groupId, StringComparison.Ordinal));
            if (count != 1)
            {
                throw new InvalidDataException(
                    $"{context}.clipBindings requires exactly one SVG group #{groupId}.");
            }
        }

        var topology = RequireObjectProperty(mp, "topologyBreak", context);
        RequireExactProperties(
            topology,
            $"{context}.topologyBreak",
            "lastTwoContourVirtualFrame",
            "firstOneContourVirtualFrame",
            "policy");
        RequireInteger(
            topology,
            "lastTwoContourVirtualFrame",
            34,
            $"{context}.topologyBreak");
        RequireInteger(
            topology,
            "firstOneContourVirtualFrame",
            35,
            $"{context}.topologyBreak");
        RequireString(
            topology,
            "policy",
            "hard-cut-no-cross-topology-interpolation",
            $"{context}.topologyBreak");

        var terminal = RequireObjectProperty(mp, "terminalEmpty", context);
        RequireExactProperties(
            terminal,
            $"{context}.terminalEmpty",
            "previousSourceFrame",
            "emptySourceFrame",
            "emptyVirtualFrame");
        RequireInteger(terminal, "previousSourceFrame", 99, $"{context}.terminalEmpty");
        RequireInteger(terminal, "emptySourceFrame", 100, $"{context}.terminalEmpty");
        RequireInteger(terminal, "emptyVirtualFrame", 101, $"{context}.terminalEmpty");

        ValidateMorphIntervals(RequireProperty(mp, "morphIntervals", context));
        ValidatePaletteStates(RequireProperty(mp, "paletteStates", context));
    }

    private static void ValidateRimVariants(JsonElement variants, string assetRoot)
    {
        const string context = "$.gauges.mp.rimVariants";
        if (variants.ValueKind != JsonValueKind.Array || variants.GetArrayLength() != 3)
        {
            throw new InvalidDataException($"{context} must contain frames 1/70/91.");
        }
        var expected = new[]
        {
            (1, "mp.rim", "mp/rim.svg", "#5EEFFB"),
            (70, "mp.rim-vf70", "mp/rim-vf70.svg", "#5EEFFB"),
            (91, "mp.rim-vf91", "mp/rim-vf91.svg", "#B6B6B6")
        };
        var index = 0;
        foreach (var variant in variants.EnumerateArray())
        {
            var itemContext = $"{context}[{index}]";
            var item = RequireObject(variant, itemContext);
            RequireExactProperties(item, itemContext, "startVirtualFrame", "assetId");
            RequireInteger(item, "startVirtualFrame", expected[index].Item1, itemContext);
            RequireString(item, "assetId", expected[index].Item2, itemContext);

            var svg = XDocument.Load(
                ResolveAssetPath(assetRoot, expected[index].Item3),
                LoadOptions.PreserveWhitespace);
            var fills = svg.Descendants()
                .Where(element => element.Name.LocalName == "path")
                .Select(element => element.Attribute("fill")?.Value)
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            if (fills.Length != 1 ||
                !string.Equals(fills[0], expected[index].Item4, StringComparison.Ordinal))
            {
                throw new InvalidDataException($"{itemContext} does not bind its authored fill.");
            }
            index++;
        }
    }

    private static void ValidateMorphIntervals(JsonElement intervals)
    {
        const string context = "$.gauges.mp.morphIntervals";
        if (intervals.ValueKind != JsonValueKind.Array || intervals.GetArrayLength() != 3)
        {
            throw new InvalidDataException($"{context} must contain the exact three spans.");
        }
        var expected = new[]
        {
            ("mp-left-mask", 0, 99, 1),
            ("mp-right-mask", 0, 33, 2),
            ("mp-right-mask", 34, 99, 1)
        };
        var index = 0;
        foreach (var interval in intervals.EnumerateArray())
        {
            var itemContext = $"{context}[{index}]";
            var item = RequireObject(interval, itemContext);
            RequireExactProperties(
                item,
                itemContext,
                "mask",
                "sourceStart",
                "sourceEnd",
                "interpolation",
                "correspondence");
            RequireString(item, "mask", expected[index].Item1, itemContext);
            RequireInteger(item, "sourceStart", expected[index].Item2, itemContext);
            RequireInteger(item, "sourceEnd", expected[index].Item3, itemContext);
            RequireString(
                item,
                "interpolation",
                "ordered-line-only-A/B-correspondence",
                itemContext);
            var correspondence = RequireProperty(item, "correspondence", itemContext);
            if (correspondence.ValueKind != JsonValueKind.Array ||
                correspondence.GetArrayLength() != expected[index].Item4)
            {
                throw new InvalidDataException($"{itemContext}.correspondence count drifted.");
            }
            var segmentIndex = 0;
            foreach (var segment in correspondence.EnumerateArray())
            {
                var segmentContext = $"{itemContext}.correspondence[{segmentIndex}]";
                var segmentObject = RequireObject(segment, segmentContext);
                RequireExactProperties(
                    segmentObject,
                    segmentContext,
                    "aStartAndAnchorsTwips",
                    "bStartAndAnchorsTwips");
                var a = RequirePointList(
                    RequireProperty(segmentObject, "aStartAndAnchorsTwips", segmentContext),
                    $"{segmentContext}.aStartAndAnchorsTwips");
                var b = RequirePointList(
                    RequireProperty(segmentObject, "bStartAndAnchorsTwips", segmentContext),
                    $"{segmentContext}.bStartAndAnchorsTwips");
                if (a.Count != b.Count)
                {
                    throw new InvalidDataException($"{segmentContext} endpoint cardinality drifted.");
                }
                segmentIndex++;
            }
            index++;
        }
    }

    private static void ValidatePaletteStates(JsonElement states)
    {
        const string context = "$.gauges.mp.paletteStates";
        if (states.ValueKind != JsonValueKind.Array || states.GetArrayLength() != 3)
        {
            throw new InvalidDataException($"{context} must contain frames 1/70/91.");
        }
        var expectedStarts = new[] {1, 70, 91};
        var expectedRims = new[] {"mp.rim", "mp.rim-vf70", "mp.rim-vf91"};
        var index = 0;
        foreach (var state in states.EnumerateArray())
        {
            var itemContext = $"{context}[{index}]";
            var item = RequireObject(state, itemContext);
            RequireExactProperties(
                item,
                itemContext,
                "startVirtualFrame",
                "rimAssetId",
                "label",
                "percent",
                "current",
                "max",
                "decoration",
                "decorativeCurrent",
                "decorativeMax");
            RequireInteger(item, "startVirtualFrame", expectedStarts[index], itemContext);
            RequireString(item, "rimAssetId", expectedRims[index], itemContext);
            foreach (var property in new[] {"label", "percent", "current", "max", "decoration"})
            {
                RequireColor(RequireString(item, property, itemContext), $"{itemContext}.{property}");
            }
            ValidateColorAlpha(
                RequireObjectProperty(item, "decorativeCurrent", itemContext),
                $"{itemContext}.decorativeCurrent");
            ValidateColorAlpha(
                RequireObjectProperty(item, "decorativeMax", itemContext),
                $"{itemContext}.decorativeMax");
            index++;
        }
    }

    private static void ValidateColorAlpha(JsonElement item, string context)
    {
        RequireExactProperties(item, context, "color", "alpha");
        RequireColor(RequireString(item, "color", context), $"{context}.color");
        var alpha = RequireFiniteNumber(RequireProperty(item, "alpha", context), $"{context}.alpha");
        if (alpha is < 0 or > 1)
        {
            throw new InvalidDataException($"{context}.alpha must be within 0..1.");
        }
    }

    private static void ValidateEffectPolicy(JsonElement policy, string assetRoot)
    {
        const string context = "$.effectPolicy";
        RequireExactProperties(
            policy,
            context,
            "includedStatic",
            "programmaticLayers");
        var included = RequireProperty(policy, "includedStatic", context);
        if (included.ValueKind != JsonValueKind.Array || included.GetArrayLength() != 1)
        {
            throw new InvalidDataException($"{context}.includedStatic must contain the HP bevel.");
        }
        var bevel = RequireObject(included[0], $"{context}.includedStatic[0]");
        RequireExactProperties(
            bevel,
            $"{context}.includedStatic[0]",
            "id",
            "implementation",
            "assetId",
            "svgGroupId");
        RequireString(bevel, "id", "hp-border-bevel", $"{context}.includedStatic[0]");
        RequireString(
            bevel,
            "implementation",
            "expanded-vector-gradient",
            $"{context}.includedStatic[0]");
        RequireString(bevel, "assetId", "hp.rim", $"{context}.includedStatic[0]");
        RequireString(
            bevel,
            "svgGroupId",
            "hp-rim-static-bevel-expanded",
            $"{context}.includedStatic[0]");

        var rim = XDocument.Load(
            ResolveAssetPath(assetRoot, "hp/rim.svg"),
            LoadOptions.PreserveWhitespace);
        var bevelGroups = rim.Descendants().Count(element =>
            string.Equals(
                element.Attribute("id")?.Value,
                "hp-rim-static-bevel-expanded",
                StringComparison.Ordinal));
        if (bevelGroups != 1)
        {
            throw new InvalidDataException("HP rim vector bevel group is not exact.");
        }

        var programmatic = RequireProperty(policy, "programmaticLayers", context);
        if (programmatic.ValueKind != JsonValueKind.Array ||
            programmatic.GetArrayLength() != 3)
        {
            throw new InvalidDataException(
                $"{context}.programmaticLayers must contain the three explicit owners.");
        }
        var expected = new[]
        {
            (
                "hp-horizontal-line-glow",
                "native-effect",
                "hp.fill",
                "hp.rim",
                "source-over"),
            (
                "hp-light-overlay",
                "native-effect",
                "hp.fill",
                "hp.rim",
                "overlay"),
            (
                "hp-mp-dynamic-text-and-glow",
                "native-draw",
                "gauge-static-layers",
                (string?)null,
                "source-over")
        };
        var index = 0;
        foreach (var effect in programmatic.EnumerateArray())
        {
            var effectContext = $"{context}.programmaticLayers[{index}]";
            var item = RequireObject(effect, effectContext);
            if (expected[index].Item4 is null)
            {
                RequireExactProperties(
                    item,
                    effectContext,
                    "id",
                    "rendererOwner",
                    "compositeAfter",
                    "blendMode");
            }
            else
            {
                RequireExactProperties(
                    item,
                    effectContext,
                    "id",
                    "rendererOwner",
                    "compositeAfter",
                    "compositeBefore",
                    "blendMode");
                RequireString(
                    item,
                    "compositeBefore",
                    expected[index].Item4!,
                    effectContext);
            }
            RequireString(item, "id", expected[index].Item1, effectContext);
            RequireString(item, "rendererOwner", expected[index].Item2, effectContext);
            RequireString(item, "compositeAfter", expected[index].Item3, effectContext);
            RequireString(item, "blendMode", expected[index].Item5, effectContext);
            index++;
        }
    }

    private static string ResolveAssetPath(string assetRoot, string relativePath)
    {
        if (relativePath.Contains('\\', StringComparison.Ordinal) ||
            relativePath.StartsWith("/", StringComparison.Ordinal) ||
            relativePath.Contains("..", StringComparison.Ordinal))
        {
            throw new InvalidDataException($"Asset path is not canonical: {relativePath}.");
        }
        var fullRoot = Path.GetFullPath(assetRoot) + Path.DirectorySeparatorChar;
        var fullPath = Path.GetFullPath(
            Path.Combine(assetRoot, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        if (!fullPath.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException($"Asset path escaped the manifest root: {relativePath}.");
        }
        return fullPath;
    }

    private static void RejectDuplicateProperties(JsonElement element, string context)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in element.EnumerateObject())
            {
                if (!names.Add(property.Name))
                {
                    throw new InvalidDataException($"{context} contains duplicate property {property.Name}.");
                }
                RejectDuplicateProperties(property.Value, $"{context}.{property.Name}");
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            var index = 0;
            foreach (var item in element.EnumerateArray())
            {
                RejectDuplicateProperties(item, $"{context}[{index++}]");
            }
        }
    }

    private static JsonElement RequireObject(JsonElement element, string context)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException($"{context} must be an object.");
        }
        return element;
    }

    private static JsonElement RequireObjectProperty(
        JsonElement parent,
        string name,
        string context) =>
        RequireObject(RequireProperty(parent, name, context), $"{context}.{name}");

    private static JsonElement RequireProperty(JsonElement parent, string name, string context)
    {
        if (!parent.TryGetProperty(name, out var value))
        {
            throw new InvalidDataException($"{context}.{name} is required.");
        }
        return value;
    }

    private static void RequireExactProperties(
        JsonElement item,
        string context,
        params string[] names)
    {
        var expected = new HashSet<string>(names, StringComparer.Ordinal);
        var actual = item.EnumerateObject().Select(property => property.Name).ToArray();
        var unknown = actual.Where(name => !expected.Contains(name)).ToArray();
        var missing = names.Where(name => !actual.Contains(name, StringComparer.Ordinal)).ToArray();
        if (unknown.Length > 0 || missing.Length > 0)
        {
            throw new InvalidDataException(
                $"{context} property closure drifted; unknown=[{string.Join(",", unknown)}], " +
                $"missing=[{string.Join(",", missing)}].");
        }
    }

    private static string RequireString(JsonElement parent, string name, string context)
    {
        var element = RequireProperty(parent, name, context);
        if (element.ValueKind != JsonValueKind.String)
        {
            throw new InvalidDataException($"{context}.{name} must be a string.");
        }
        return element.GetString()
            ?? throw new InvalidDataException($"{context}.{name} must not be null.");
    }

    private static void RequireString(
        JsonElement parent,
        string name,
        string expected,
        string context)
    {
        var actual = RequireString(parent, name, context);
        if (!string.Equals(actual, expected, StringComparison.Ordinal))
        {
            throw new InvalidDataException($"{context}.{name} drifted.");
        }
    }

    private static void RequireInteger(
        JsonElement parent,
        string name,
        int expected,
        string context)
    {
        var value = RequireProperty(parent, name, context);
        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var actual) ||
            actual != expected)
        {
            throw new InvalidDataException($"{context}.{name} must equal {expected}.");
        }
    }

    private static void RequireNumber(
        JsonElement parent,
        string name,
        double expected,
        string context)
    {
        var actual = RequireFiniteNumber(
            RequireProperty(parent, name, context),
            $"{context}.{name}");
        if (actual != expected)
        {
            throw new InvalidDataException($"{context}.{name} must equal {expected}.");
        }
    }

    private static void RequireBoolean(
        JsonElement parent,
        string name,
        bool expected,
        string context)
    {
        var value = RequireProperty(parent, name, context);
        var actual = value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => throw new InvalidDataException($"{context}.{name} must be boolean.")
        };
        if (actual != expected)
        {
            throw new InvalidDataException($"{context}.{name} drifted.");
        }
    }

    private static IReadOnlyList<double> RequireNumberArray(
        JsonElement parent,
        string name,
        int count,
        string context)
    {
        var element = RequireProperty(parent, name, context);
        if (element.ValueKind != JsonValueKind.Array || element.GetArrayLength() != count)
        {
            throw new InvalidDataException($"{context}.{name} must contain {count} numbers.");
        }
        return element.EnumerateArray()
            .Select((value, index) =>
                RequireFiniteNumber(value, $"{context}.{name}[{index}]"))
            .ToArray();
    }

    private static void RequireNumberArray(
        JsonElement parent,
        string name,
        IReadOnlyList<double> expected,
        string context)
    {
        var actual = RequireNumberArray(parent, name, expected.Count, context);
        RequireSameNumbers(actual, expected, $"{context}.{name}");
    }

    private static void RequireStringArray(
        JsonElement parent,
        string name,
        IReadOnlyList<string> expected,
        string context)
    {
        var element = RequireProperty(parent, name, context);
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() != expected.Count)
        {
            throw new InvalidDataException($"{context}.{name} cardinality drifted.");
        }
        var index = 0;
        foreach (var item in element.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String ||
                !string.Equals(item.GetString(), expected[index], StringComparison.Ordinal))
            {
                throw new InvalidDataException($"{context}.{name}[{index}] drifted.");
            }
            index++;
        }
    }

    private static double RequireFiniteNumber(JsonElement value, string context)
    {
        if (value.ValueKind != JsonValueKind.Number ||
            !value.TryGetDouble(out var number) ||
            !double.IsFinite(number))
        {
            throw new InvalidDataException($"{context} must be finite.");
        }
        return number;
    }

    private static IReadOnlyList<(double X, double Y)> RequirePointList(
        JsonElement list,
        string context)
    {
        if (list.ValueKind != JsonValueKind.Array || list.GetArrayLength() < 4)
        {
            throw new InvalidDataException($"{context} must contain a closed contour.");
        }
        var points = new List<(double X, double Y)>();
        var index = 0;
        foreach (var point in list.EnumerateArray())
        {
            if (point.ValueKind != JsonValueKind.Array || point.GetArrayLength() != 2)
            {
                throw new InvalidDataException($"{context}[{index}] must be an x/y pair.");
            }
            var values = point.EnumerateArray().ToArray();
            var x = RequireFiniteNumber(values[0], $"{context}[{index}][0]");
            var y = RequireFiniteNumber(values[1], $"{context}[{index}][1]");
            if (Math.Abs(x) > 1_000_000 || Math.Abs(y) > 1_000_000)
            {
                throw new InvalidDataException($"{context}[{index}] exceeds the coordinate bound.");
            }
            points.Add((x, y));
            index++;
        }
        if (points[0] != points[^1])
        {
            throw new InvalidDataException($"{context} must be explicitly closed.");
        }
        return points;
    }

    private static IReadOnlyList<double> ParseSvgNumberList(
        string? value,
        int count,
        string context)
    {
        var parts = (value ?? string.Empty).Split(
            (char[]?)null,
            StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != count)
        {
            throw new InvalidDataException($"{context} must contain {count} numbers.");
        }
        return parts.Select(part =>
        {
            if (!double.TryParse(
                    part,
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out var number) ||
                !double.IsFinite(number))
            {
                throw new InvalidDataException($"{context} contains a non-finite value.");
            }
            return number;
        }).ToArray();
    }

    private static double ParseSvgNumber(XElement root, string attribute)
    {
        var values = ParseSvgNumberList(root.Attribute(attribute)?.Value, 1, $"SVG {attribute}");
        return values[0];
    }

    private static void RequireSameNumbers(
        IReadOnlyList<double> actual,
        IReadOnlyList<double> expected,
        string context)
    {
        if (actual.Count != expected.Count ||
            actual.Where((value, index) => value != expected[index]).Any())
        {
            throw new InvalidDataException($"{context} numeric values drifted.");
        }
    }

    private static void RequireContainedBounds(
        IReadOnlyList<double> bounds,
        IReadOnlyList<double> viewBox,
        string context)
    {
        var viewRight = viewBox[0] + viewBox[2];
        var viewBottom = viewBox[1] + viewBox[3];
        if (bounds[0] > bounds[2] ||
            bounds[1] > bounds[3] ||
            bounds[0] < viewBox[0] ||
            bounds[1] < viewBox[1] ||
            bounds[2] > viewRight ||
            bounds[3] > viewBottom)
        {
            throw new InvalidDataException($"{context} is not contained by viewBox.");
        }
    }

    private static void RequireColor(string color, string context)
    {
        if (!Regex.IsMatch(
                color,
                "^#[0-9A-F]{6}$",
                RegexOptions.CultureInvariant))
        {
            throw new InvalidDataException($"{context} must be canonical #RRGGBB.");
        }
    }

    private static int CountNonTransparent(SkiaSharp.SKBitmap bitmap)
    {
        var count = 0;
        for (var y = 0; y < bitmap.Height; y++)
        for (var x = 0; x < bitmap.Width; x++)
        {
            if (bitmap.GetPixel(x, y).Alpha > 0)
            {
                count++;
            }
        }
        return count;
    }
}

internal sealed record CanonicalAssetValidationResult(
    string Status,
    string ManifestSha256,
    string AssetSetRevision,
    int AssetCount,
    long AssetBytes,
    IReadOnlyList<CanonicalAssetResult> Assets);

internal sealed record CanonicalAssetResult(
    string Id,
    string Path,
    int Bytes,
    string Sha256,
    int NonTransparentPixels);
