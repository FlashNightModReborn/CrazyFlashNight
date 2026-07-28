using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;
using SkiaSharp;
using Svg;
using Svg.Model;
using Svg.Skia;

namespace Cf7.PlayerInfoHud.RendererQualification;

internal static class StrictSvgValidator
{
    internal const int MaxBytes = 1_048_576;
    internal const int MaxNodes = 10_000;
    internal const int MaxDepth = 64;
    internal const int MaxDimension = 4096;
    internal const int MaxPathDataCharacters = 262_144;
    internal const int MaxPathCommands = 32_768;
    internal const int MaxPathNumbers = 131_072;
    internal const int MaxReferenceDepth = 32;
    internal const int MaxExpandedRenderNodes = 32_768;
    private const double MaxCoordinateMagnitude = 1_000_000;
    private const int MaxSemanticTraversalSteps = MaxExpandedRenderNodes;
    private const string DocumentRenderNode = "$document";

    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly XNamespace SvgNamespace = "http://www.w3.org/2000/svg";
    private static readonly Regex LocalUrl = new(
        @"^url\(#(?<id>[A-Za-z_][A-Za-z0-9_.:-]*)\)$",
        RegexOptions.CultureInvariant);
    private static readonly Regex Color = new(
        @"^#[0-9A-Fa-f]{6}$",
        RegexOptions.CultureInvariant);
    private static readonly Regex NumberAt = new(
        @"\G[-+]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][-+]?\d+)?",
        RegexOptions.CultureInvariant);
    private static readonly HashSet<string> GradientElements =
        ["linearGradient", "radialGradient"];
    private static readonly HashSet<string> UseReferenceTargets =
        ["g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "use"];
    private static readonly HashSet<string> GradientUnits =
        ["userSpaceOnUse", "objectBoundingBox"];
    private static readonly HashSet<string> SpreadMethods =
        ["pad", "reflect", "repeat"];
    private static readonly HashSet<string> FillRules =
        ["nonzero", "evenodd"];
    private static readonly HashSet<string> StrokeLineCaps =
        ["butt", "round", "square"];
    private static readonly HashSet<string> StrokeLineJoins =
        ["miter", "round", "bevel"];
    private static readonly HashSet<string> PreserveAspectRatioAlignments =
    [
        "xMinYMin", "xMidYMin", "xMaxYMin",
        "xMinYMid", "xMidYMid", "xMaxYMid",
        "xMinYMax", "xMidYMax", "xMaxYMax"
    ];

    private static readonly HashSet<string> CommonAttributes =
    [
        "id", "transform", "fill", "stroke", "stroke-width", "opacity",
        "fill-rule", "clip-rule", "clip-path"
    ];
    private static readonly HashSet<string> RenderableElements =
    [
        "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "use"
    ];

    private static readonly IReadOnlyDictionary<string, HashSet<string>> ElementAttributes =
        new Dictionary<string, HashSet<string>>(StringComparer.Ordinal)
        {
            ["svg"] = ["width", "height", "viewBox", "preserveAspectRatio"],
            ["g"] = [],
            ["defs"] = [],
            ["path"] = ["d", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit"],
            ["rect"] = ["x", "y", "width", "height"],
            ["circle"] = ["cx", "cy", "r"],
            ["ellipse"] = ["cx", "cy", "rx", "ry"],
            ["line"] = ["x1", "y1", "x2", "y2"],
            ["polyline"] = ["points"],
            ["polygon"] = ["points"],
            ["linearGradient"] =
                ["x1", "y1", "x2", "y2", "gradientUnits", "gradientTransform", "spreadMethod", "href"],
            ["radialGradient"] =
                ["cx", "cy", "r", "fx", "fy", "gradientUnits", "gradientTransform", "spreadMethod", "href"],
            ["stop"] = ["offset", "stop-color", "stop-opacity"],
            ["clipPath"] = ["clipPathUnits"],
            ["use"] = ["href", "x", "y", "width", "height"]
        };

    internal static void Validate(ReadOnlyMemory<byte> bytes)
    {
        if (bytes.IsEmpty || bytes.Length > MaxBytes)
        {
            throw new InvalidDataException($"SVG byte length must be 1..{MaxBytes}.");
        }

        var xml = StrictUtf8.GetString(bytes.Span);
        using var stringReader = new StringReader(xml);
        using var reader = XmlReader.Create(stringReader, new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            MaxCharactersInDocument = MaxBytes,
            MaxCharactersFromEntities = 0,
            IgnoreComments = false,
            IgnoreProcessingInstructions = false
        });

        var document = XDocument.Load(reader, LoadOptions.PreserveWhitespace | LoadOptions.SetLineInfo);
        if (document.DocumentType is not null)
        {
            throw new InvalidDataException("DTD is forbidden.");
        }
        if (document.DescendantNodes().Any(node => node is XProcessingInstruction))
        {
            throw new InvalidDataException("Processing instructions are forbidden.");
        }
        if (document.Root is null || document.Root.Name != SvgNamespace + "svg")
        {
            throw new InvalidDataException("Root must be an SVG-namespace svg element.");
        }

        var ids = new Dictionary<string, XElement>(StringComparer.Ordinal);
        var references = new List<ReferenceEdge>();
        var nodeCount = 0;
        foreach (var element in document.Root.DescendantsAndSelf())
        {
            nodeCount++;
            if (nodeCount > MaxNodes)
            {
                throw new InvalidDataException($"SVG node limit exceeded: {MaxNodes}.");
            }
            if (element.Ancestors().Count() > MaxDepth)
            {
                throw new InvalidDataException($"SVG depth limit exceeded: {MaxDepth}.");
            }
            if (element.Name.Namespace != SvgNamespace ||
                !ElementAttributes.TryGetValue(element.Name.LocalName, out var elementAllowed))
            {
                throw new InvalidDataException($"Element is outside the core subset: {element.Name}.");
            }
            if (!ReferenceEquals(element, document.Root) &&
                element.Name == SvgNamespace + "svg")
            {
                throw new InvalidDataException("Nested svg elements are forbidden.");
            }
            if (element.Nodes().OfType<XText>().Any(text => !string.IsNullOrWhiteSpace(text.Value)))
            {
                throw new InvalidDataException($"Text content is forbidden in {element.Name.LocalName}.");
            }
            if (element.Attributes().Count(attribute => !attribute.IsNamespaceDeclaration) > 64)
            {
                throw new InvalidDataException("Attribute count limit exceeded.");
            }

            foreach (var attribute in element.Attributes())
            {
                if (attribute.IsNamespaceDeclaration)
                {
                    continue;
                }
                if (attribute.Name.Namespace != XNamespace.None)
                {
                    throw new InvalidDataException($"Namespaced attribute is forbidden: {attribute.Name}.");
                }

                var name = attribute.Name.LocalName;
                var value = attribute.Value.Trim();
                if (name.StartsWith("on", StringComparison.OrdinalIgnoreCase) ||
                    (!CommonAttributes.Contains(name) && !elementAllowed.Contains(name)))
                {
                    throw new InvalidDataException(
                        $"Attribute is outside the core subset: {element.Name.LocalName}@{name}.");
                }
                if (value.Length > 65_536 ||
                    value.Contains("javascript:", StringComparison.OrdinalIgnoreCase) ||
                    Regex.IsMatch(value, @"(?:^|[^A-Za-z])(NaN|Infinity)(?:$|[^A-Za-z])",
                        RegexOptions.CultureInvariant | RegexOptions.IgnoreCase))
                {
                    throw new InvalidDataException($"Unsafe attribute value: {name}.");
                }
                if (!string.Equals(attribute.Value, value, StringComparison.Ordinal))
                {
                    throw new InvalidDataException($"Leading or trailing whitespace is forbidden: {name}.");
                }

                if (name == "id")
                {
                    if (!IsIdentifier(value) || !ids.TryAdd(value, element))
                    {
                        throw new InvalidDataException($"Invalid or duplicate id: {value}.");
                    }
                    continue;
                }

                ValidateAttributeValue(element, name, value, references);
            }
        }

        var hasRenderableElement = document.Descendants().Any(element =>
            RenderableElements.Contains(element.Name.LocalName) &&
            !element.Ancestors().Any(ancestor =>
                ancestor.Name == SvgNamespace + "defs" ||
                ancestor.Name == SvgNamespace + "clipPath"));
        if (!hasRenderableElement)
        {
            throw new InvalidDataException("SVG has no renderable element outside defs/clipPath.");
        }

        ValidateReferences(document.Root, ids, references);

        ValidateRootGeometry(document.Root);
        ValidateCompositeTransforms(document.Root);
        ValidateSemanticCompositeTransforms(document.Root, ids);
        ValidatePathComplexity(document);
    }

    private static void ValidateAttributeValue(
        XElement element,
        string name,
        string value,
        ICollection<ReferenceEdge> references)
    {
        var elementName = element.Name.LocalName;
        switch (name)
        {
            case "transform":
            case "gradientTransform":
                ValidateTransform(value, name);
                return;
            case "fill":
            case "stroke":
                if (value == "none" || Color.IsMatch(value))
                {
                    return;
                }
                references.Add(new ReferenceEdge(
                    element,
                    ParseLocalUrl(value, $"{elementName}@{name}"),
                    ReferenceKind.Paint));
                return;
            case "clip-path":
                if (value == "none")
                {
                    return;
                }
                references.Add(new ReferenceEdge(
                    element,
                    ParseLocalUrl(value, $"{elementName}@{name}"),
                    ReferenceKind.ClipPath));
                return;
            case "href":
                {
                    if (!value.StartsWith('#') || value.Length == 1 || !IsIdentifier(value[1..]))
                    {
                        throw new InvalidDataException("Only same-document href is allowed.");
                    }
                    var kind = elementName switch
                    {
                        "use" => ReferenceKind.Use,
                        "linearGradient" or "radialGradient" => ReferenceKind.Gradient,
                        _ => throw new InvalidDataException($"href is forbidden on {elementName}.")
                    };
                    references.Add(new ReferenceEdge(element, value[1..], kind));
                    return;
                }
            case "opacity":
            case "stop-opacity":
            case "offset":
                ValidateRange(ParseFinite(value, $"{elementName}@{name}"), 0, 1, $"{elementName}@{name}");
                return;
            case "stop-color":
                if (!Color.IsMatch(value))
                {
                    throw new InvalidDataException($"{elementName}@{name} must be #RRGGBB.");
                }
                return;
            case "gradientUnits":
            case "clipPathUnits":
                ValidateEnum(value, GradientUnits, $"{elementName}@{name}");
                return;
            case "spreadMethod":
                ValidateEnum(value, SpreadMethods, $"{elementName}@{name}");
                return;
            case "fill-rule":
            case "clip-rule":
                ValidateEnum(value, FillRules, $"{elementName}@{name}");
                return;
            case "stroke-linecap":
                ValidateEnum(value, StrokeLineCaps, $"{elementName}@{name}");
                return;
            case "stroke-linejoin":
                ValidateEnum(value, StrokeLineJoins, $"{elementName}@{name}");
                return;
            case "preserveAspectRatio":
                ValidatePreserveAspectRatio(value);
                return;
            case "viewBox":
                _ = ParseNumberList(value, "viewBox", 4, 4);
                return;
            case "points":
                {
                    var minimum = elementName == "polygon" ? 6 : 4;
                    var points = ParseNumberList(value, $"{elementName}@points", minimum, MaxPathNumbers);
                    if ((points.Length & 1) != 0)
                    {
                        throw new InvalidDataException($"{elementName}@points must contain coordinate pairs.");
                    }
                    return;
                }
            case "width":
            case "height":
            case "r":
            case "rx":
            case "ry":
            case "stroke-width":
                {
                    var number = ParseFinite(value, $"{elementName}@{name}");
                    if (number < 0)
                    {
                        throw new InvalidDataException($"{elementName}@{name} must be non-negative.");
                    }
                    return;
                }
            case "stroke-miterlimit":
                {
                    var number = ParseFinite(value, $"{elementName}@{name}");
                    if (number < 1)
                    {
                        throw new InvalidDataException($"{elementName}@{name} must be at least 1.");
                    }
                    return;
                }
            case "x":
            case "y":
            case "cx":
            case "cy":
            case "fx":
            case "fy":
            case "x1":
            case "y1":
            case "x2":
            case "y2":
                _ = ParseFinite(value, $"{elementName}@{name}");
                return;
            case "d":
                return;
            default:
                throw new InvalidDataException($"No value grammar exists for {elementName}@{name}.");
        }
    }

    private static void ValidateRootGeometry(XElement root)
    {
        var width = ParseFinite(root.Attribute("width")?.Value, "width");
        var height = ParseFinite(root.Attribute("height")?.Value, "height");
        if (width <= 0 || height <= 0 || width > MaxDimension || height > MaxDimension)
        {
            throw new InvalidDataException($"SVG dimensions must be within 1..{MaxDimension}.");
        }

        var values = ParseNumberList(root.Attribute("viewBox")?.Value ?? string.Empty, "viewBox", 4, 4);
        if (values[2] <= 0 || values[3] <= 0 || values.Any(value => Math.Abs(value) > 1_000_000))
        {
            throw new InvalidDataException("viewBox is outside the qualification bounds.");
        }
    }

    private static double ParseFinite(string? value, string field)
    {
        var values = ParseNumberList(value ?? string.Empty, field, 1, 1);
        var result = values[0];
        if (Math.Abs(result) > MaxCoordinateMagnitude)
        {
            throw new InvalidDataException($"{field} is outside the qualification bounds.");
        }
        return result;
    }

    private static void ValidatePathComplexity(XDocument document)
    {
        var totalCharacters = 0;
        var totalCommands = 0;
        var totalNumbers = 0;
        foreach (var path in document.Descendants(SvgNamespace + "path"))
        {
            var data = path.Attribute("d")?.Value;
            if (string.IsNullOrWhiteSpace(data))
            {
                throw new InvalidDataException("Every path must have non-empty d data.");
            }

            var characters = data.Length;
            var stats = ValidatePathData(data);
            var commands = stats.Commands;
            var numbers = stats.Numbers;
            if (characters > MaxPathDataCharacters ||
                commands is <= 0 or > MaxPathCommands ||
                numbers > MaxPathNumbers)
            {
                throw new InvalidDataException("Per-path complexity limit exceeded.");
            }

            totalCharacters = checked(totalCharacters + characters);
            totalCommands = checked(totalCommands + commands);
            totalNumbers = checked(totalNumbers + numbers);
            if (totalCharacters > MaxPathDataCharacters ||
                totalCommands > MaxPathCommands ||
                totalNumbers > MaxPathNumbers)
            {
                throw new InvalidDataException("Document path-complexity limit exceeded.");
            }
        }
    }

    private static void ValidateTransform(string value, string field) =>
        _ = ParseTransformMatrix(value, field);

    private static AffineMatrix ParseTransformMatrix(string value, string field)
    {
        const string prefix = "matrix(";
        if (!value.StartsWith(prefix, StringComparison.Ordinal) ||
            value.Length <= prefix.Length ||
            value[^1] != ')' ||
            value.AsSpan(prefix.Length, value.Length - prefix.Length - 1).IndexOfAny('(', ')') >= 0)
        {
            throw new InvalidDataException(
                $"{field} must be exactly one matrix(a b c d e f) transform.");
        }

        var values = ParseNumberList(
            value[prefix.Length..^1],
            $"{field}:matrix",
            6,
            6);
        return new AffineMatrix(
            values[0],
            values[1],
            values[2],
            values[3],
            values[4],
            values[5]);
    }

    private static void ValidateCompositeTransforms(XElement root)
    {
        Visit(root, AffineMatrix.Identity);
        return;

        static void Visit(XElement element, AffineMatrix parent)
        {
            var transform = element.Attribute("transform")?.Value;
            var local = transform is null
                ? AffineMatrix.Identity
                : ParseTransformMatrix(transform, $"{element.Name.LocalName}@transform");
            var composite = AffineMatrix.Multiply(parent, local);
            composite.ValidateBounded($"{element.Name.LocalName}@composite-transform");
            foreach (var child in element.Elements())
            {
                Visit(child, composite);
            }
        }
    }

    private static void ValidateSemanticCompositeTransforms(
        XElement root,
        IReadOnlyDictionary<string, XElement> ids)
    {
        var pending = new Stack<SemanticTraversalItem>();
        pending.Push(new SemanticTraversalItem(root, AffineMatrix.Identity, true));
        var steps = 0;
        while (pending.TryPop(out var item))
        {
            if (++steps > MaxSemanticTraversalSteps)
            {
                throw new InvalidDataException(
                    $"Semantic transform traversal exceeds {MaxSemanticTraversalSteps} steps.");
            }

            var element = item.Element;
            if (!item.ForceDefinitionRoot && IsNaturalDefinitionElement(element))
            {
                continue;
            }

            var transform = element.Attribute("transform")?.Value;
            var local = transform is null
                ? AffineMatrix.Identity
                : ParseTransformMatrix(transform, $"{element.Name.LocalName}@transform");
            var composite = AffineMatrix.Multiply(item.Parent, local);
            composite.ValidateBounded(
                $"{element.Name.LocalName}@semantic-composite-transform");

            var clipPathValue = element.Attribute("clip-path")?.Value;
            if (clipPathValue is not null && clipPathValue != "none")
            {
                var clipPathId = ParseLocalUrl(
                    clipPathValue,
                    $"{element.Name.LocalName}@clip-path");
                pending.Push(new SemanticTraversalItem(
                    ids[clipPathId],
                    composite,
                    true));
            }

            if (element.Name.LocalName == "use")
            {
                var x = element.Attribute("x") is { } xAttribute
                    ? ParseFinite(xAttribute.Value, "use@x")
                    : 0;
                var y = element.Attribute("y") is { } yAttribute
                    ? ParseFinite(yAttribute.Value, "use@y")
                    : 0;
                var placed = AffineMatrix.Multiply(
                    composite,
                    AffineMatrix.Translation(x, y));
                placed.ValidateBounded("use@semantic-placement-transform");

                var href = element.Attribute("href")?.Value;
                if (href is not null)
                {
                    pending.Push(new SemanticTraversalItem(
                        ids[href[1..]],
                        placed,
                        true));
                }
            }

            foreach (var child in element.Elements())
            {
                if (!IsNaturalDefinitionElement(child))
                {
                    pending.Push(new SemanticTraversalItem(
                        child,
                        composite,
                        false));
                }
            }
        }
    }

    private static bool IsNaturalDefinitionElement(XElement element) =>
        element.Name.LocalName is
            "defs" or "clipPath" or "linearGradient" or "radialGradient" or "stop";

    private static void ValidatePreserveAspectRatio(string value)
    {
        var parts = value.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 1 && parts[0] == "none")
        {
            return;
        }
        if (parts.Length is < 1 or > 2 ||
            !PreserveAspectRatioAlignments.Contains(parts[0]) ||
            (parts.Length == 2 && parts[1] is not ("meet" or "slice")))
        {
            throw new InvalidDataException("preserveAspectRatio is outside the controlled enum.");
        }
    }

    private static void ValidateReferences(
        XElement root,
        IReadOnlyDictionary<string, XElement> ids,
        IReadOnlyCollection<ReferenceEdge> references)
    {
        foreach (var reference in references)
        {
            if (!ids.TryGetValue(reference.TargetId, out var target))
            {
                throw new InvalidDataException(
                    $"Unresolved same-document reference: #{reference.TargetId}.");
            }

            var targetName = target.Name.LocalName;
            var expected = reference.Kind switch
            {
                ReferenceKind.Paint => GradientElements.Contains(targetName),
                ReferenceKind.ClipPath => targetName == "clipPath",
                ReferenceKind.Gradient => GradientElements.Contains(targetName),
                ReferenceKind.Use => UseReferenceTargets.Contains(targetName),
                _ => false
            };
            if (!expected)
            {
                throw new InvalidDataException(
                    $"{reference.Source.Name.LocalName} reference #{reference.TargetId} has the wrong target type.");
            }
        }

        var gradientGraph = ids
            .Where(item => GradientElements.Contains(item.Value.Name.LocalName))
            .ToDictionary(
                item => item.Key,
                _ => new List<string>(),
                StringComparer.Ordinal);
        foreach (var reference in references.Where(item => item.Kind == ReferenceKind.Gradient))
        {
            var sourceId = reference.Source.Attribute("id")?.Value;
            if (sourceId is not null)
            {
                gradientGraph[sourceId].Add(reference.TargetId);
            }
        }
        ValidateReferenceDepthAndCycles(gradientGraph, "gradient href");

        var renderGraph = new Dictionary<string, RenderExpansionNode>(StringComparer.Ordinal)
        {
            [DocumentRenderNode] = CollectRenderExpansion(root)
        };
        foreach (var item in ids.Where(item =>
                     UseReferenceTargets.Contains(item.Value.Name.LocalName) ||
                     item.Value.Name.LocalName == "clipPath"))
        {
            renderGraph.Add(item.Key, CollectRenderExpansion(item.Value));
        }
        ValidateRenderExpansion(renderGraph);
    }

    private static RenderExpansionNode CollectRenderExpansion(XElement owner)
    {
        var references = new List<string>();
        var physicalNodes = 0;
        Visit(owner, true);
        return new RenderExpansionNode(physicalNodes, references);

        void Visit(XElement element, bool isOwner)
        {
            var elementName = element.Name.LocalName;
            if (!isOwner &&
                (elementName is "defs" or "clipPath" or "linearGradient" or "radialGradient" or "stop"))
            {
                return;
            }

            physicalNodes++;
            if (elementName == "use")
            {
                var href = element.Attribute("href")?.Value;
                if (href is not null)
                {
                    references.Add(href[1..]);
                }
            }

            var clipPath = element.Attribute("clip-path")?.Value;
            if (clipPath is not null && clipPath != "none")
            {
                references.Add(ParseLocalUrl(clipPath, $"{elementName}@clip-path"));
            }

            foreach (var child in element.Elements())
            {
                Visit(child, false);
            }
        }
    }

    private static void ValidateReferenceDepthAndCycles(
        IReadOnlyDictionary<string, List<string>> graph,
        string label)
    {
        var states = new Dictionary<string, VisitState>(StringComparer.Ordinal);
        var longestDepths = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var node in graph.Keys)
        {
            _ = Visit(node, 0);
        }

        int Visit(string node, int currentDepth)
        {
            if (states.TryGetValue(node, out var state))
            {
                if (state == VisitState.Visiting)
                {
                    throw new InvalidDataException($"{label} cycle is forbidden.");
                }
                var cachedDepth = longestDepths[node];
                if (currentDepth + cachedDepth > MaxReferenceDepth)
                {
                    throw new InvalidDataException(
                        $"{label} depth exceeds {MaxReferenceDepth}.");
                }
                return cachedDepth;
            }
            if (currentDepth > MaxReferenceDepth)
            {
                throw new InvalidDataException(
                    $"{label} depth exceeds {MaxReferenceDepth}.");
            }

            states[node] = VisitState.Visiting;
            var longestDepth = 0;
            foreach (var target in graph[node])
            {
                if (graph.ContainsKey(target))
                {
                    longestDepth = Math.Max(
                        longestDepth,
                        checked(1 + Visit(target, checked(currentDepth + 1))));
                }
            }
            if (currentDepth + longestDepth > MaxReferenceDepth)
            {
                throw new InvalidDataException(
                    $"{label} depth exceeds {MaxReferenceDepth}.");
            }
            states[node] = VisitState.Visited;
            longestDepths[node] = longestDepth;
            return longestDepth;
        }
    }

    private static void ValidateRenderExpansion(
        IReadOnlyDictionary<string, RenderExpansionNode> graph)
    {
        var states = new Dictionary<string, VisitState>(StringComparer.Ordinal);
        var results = new Dictionary<string, RenderExpansionResult>(StringComparer.Ordinal);
        foreach (var node in graph.Keys)
        {
            _ = Visit(node, 0);
        }
        return;

        RenderExpansionResult Visit(string node, int currentDepth)
        {
            if (states.TryGetValue(node, out var state))
            {
                if (state == VisitState.Visiting)
                {
                    throw new InvalidDataException(
                        "use/clip-path render-reference cycle is forbidden.");
                }
                var cachedResult = results[node];
                if (currentDepth + cachedResult.LongestDepth > MaxReferenceDepth)
                {
                    throw new InvalidDataException(
                        $"use/clip-path render-reference depth exceeds {MaxReferenceDepth}.");
                }
                return cachedResult;
            }
            if (currentDepth > MaxReferenceDepth)
            {
                throw new InvalidDataException(
                    $"use/clip-path render-reference depth exceeds {MaxReferenceDepth}.");
            }

            states[node] = VisitState.Visiting;
            var expansion = graph[node].PhysicalNodes;
            var longestDepth = 0;
            foreach (var target in graph[node].Targets)
            {
                if (!graph.ContainsKey(target))
                {
                    throw new InvalidDataException(
                        $"Missing use/clip-path render-reference graph node: #{target}.");
                }
                var targetResult = Visit(target, checked(currentDepth + 1));
                longestDepth = Math.Max(
                    longestDepth,
                    checked(1 + targetResult.LongestDepth));
                if (expansion > MaxExpandedRenderNodes - targetResult.ExpandedNodes)
                {
                    throw new InvalidDataException(
                        $"use/clip-path semantic expansion exceeds {MaxExpandedRenderNodes} nodes.");
                }
                expansion += targetResult.ExpandedNodes;
            }
            if (currentDepth + longestDepth > MaxReferenceDepth)
            {
                throw new InvalidDataException(
                    $"use/clip-path render-reference depth exceeds {MaxReferenceDepth}.");
            }
            if (expansion > MaxExpandedRenderNodes)
            {
                throw new InvalidDataException(
                    $"use/clip-path semantic expansion exceeds {MaxExpandedRenderNodes} nodes.");
            }

            states[node] = VisitState.Visited;
            var result = new RenderExpansionResult(expansion, longestDepth);
            results[node] = result;
            return result;
        }
    }

    private static PathStats ValidatePathData(string data)
    {
        var tokens = new List<PathToken>();
        var index = 0;
        var previousWasNumber = false;
        var commandCount = 0;
        var numberCount = 0;
        while (true)
        {
            var hadWhitespace = SkipWhitespace(data, ref index);
            if (index >= data.Length)
            {
                break;
            }

            var hadComma = false;
            if (data[index] == ',')
            {
                if (tokens.Count == 0 || !previousWasNumber)
                {
                    throw new InvalidDataException("Path comma is not between numeric parameters.");
                }
                hadComma = true;
                index++;
                SkipWhitespace(data, ref index);
                if (index >= data.Length || data[index] == ',')
                {
                    throw new InvalidDataException("Path has an empty parameter after comma.");
                }
            }

            var current = data[index];
            if (IsPathCommand(current))
            {
                if (hadComma)
                {
                    throw new InvalidDataException("Path comma cannot precede a command.");
                }
                if (char.IsAsciiLetterLower(current))
                {
                    throw new InvalidDataException(
                        "Relative path commands are outside the absolute-command subset.");
                }
                tokens.Add(PathToken.ForCommand(current));
                commandCount++;
                index++;
                previousWasNumber = false;
            }
            else
            {
                if (previousWasNumber &&
                    !hadWhitespace &&
                    !hadComma &&
                    current is not ('+' or '-'))
                {
                    throw new InvalidDataException("Adjacent path numbers require a sign or separator.");
                }
                if (!TryReadNumber(data, ref index, out var number, out var raw) ||
                    !double.IsFinite(number) ||
                    Math.Abs(number) > MaxCoordinateMagnitude)
                {
                    throw new InvalidDataException("Path contains invalid, non-finite, or unbounded data.");
                }
                tokens.Add(PathToken.ForNumber(number, raw));
                numberCount++;
                previousWasNumber = true;
            }
            if (commandCount > MaxPathCommands || numberCount > MaxPathNumbers)
            {
                throw new InvalidDataException("Per-path complexity limit exceeded.");
            }
        }

        if (tokens.Count == 0 || !tokens[0].IsCommand || tokens[0].Command != 'M')
        {
            throw new InvalidDataException("Path must begin with moveto.");
        }

        var tokenIndex = 0;
        while (tokenIndex < tokens.Count)
        {
            if (!tokens[tokenIndex].IsCommand)
            {
                throw new InvalidDataException("Path parameters require an explicit command after closepath.");
            }
            var command = tokens[tokenIndex++].Command;
            if (command == 'Z')
            {
                continue;
            }

            var parametersStart = tokenIndex;
            while (tokenIndex < tokens.Count && !tokens[tokenIndex].IsCommand)
            {
                tokenIndex++;
            }
            var parameterCount = tokenIndex - parametersStart;
            var arity = char.ToUpperInvariant(command) switch
            {
                'M' or 'L' or 'T' => 2,
                'H' or 'V' => 1,
                'C' => 6,
                'S' or 'Q' => 4,
                'A' => 7,
                _ => throw new InvalidDataException($"Unsupported path command: {command}.")
            };
            if (parameterCount < arity || parameterCount % arity != 0)
            {
                throw new InvalidDataException($"Path command {command} has invalid arity.");
            }

            if (char.ToUpperInvariant(command) == 'A')
            {
                for (var group = parametersStart; group < tokenIndex; group += arity)
                {
                    if (tokens[group].Number < 0 || tokens[group + 1].Number < 0)
                    {
                        throw new InvalidDataException("Arc radii must be non-negative.");
                    }
                    if (tokens[group + 3].Raw is not ("0" or "1") ||
                        tokens[group + 4].Raw is not ("0" or "1"))
                    {
                        throw new InvalidDataException("Arc flags must be exactly 0 or 1.");
                    }
                }
            }
        }

        return new PathStats(commandCount, numberCount);
    }

    private static double[] ParseNumberList(
        string value,
        string field,
        int minimumCount,
        int maximumCount)
    {
        var numbers = new List<double>(Math.Min(maximumCount, 8));
        var index = 0;
        SkipWhitespace(value, ref index);
        while (index < value.Length)
        {
            if (!TryReadNumber(value, ref index, out var number, out _) ||
                !double.IsFinite(number) ||
                Math.Abs(number) > MaxCoordinateMagnitude)
            {
                throw new InvalidDataException($"{field} must contain bounded finite numbers.");
            }
            numbers.Add(number);
            if (numbers.Count > maximumCount)
            {
                throw new InvalidDataException($"{field} contains too many numbers.");
            }

            var hadWhitespace = SkipWhitespace(value, ref index);
            if (index >= value.Length)
            {
                break;
            }
            if (value[index] == ',')
            {
                index++;
                SkipWhitespace(value, ref index);
                if (index >= value.Length || value[index] == ',')
                {
                    throw new InvalidDataException($"{field} has an empty value after comma.");
                }
            }
            else if (!hadWhitespace)
            {
                throw new InvalidDataException($"{field} numbers require a separator.");
            }
        }

        if (numbers.Count < minimumCount)
        {
            throw new InvalidDataException(
                $"{field} must contain {minimumCount}..{maximumCount} numbers.");
        }
        return numbers.ToArray();
    }

    private static bool TryReadNumber(
        string value,
        ref int index,
        out double number,
        out string raw)
    {
        var match = NumberAt.Match(value, index);
        if (!match.Success || match.Index != index)
        {
            number = default;
            raw = string.Empty;
            return false;
        }
        raw = match.Value;
        index += match.Length;
        return double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out number);
    }

    private static string ParseLocalUrl(string value, string field)
    {
        var match = LocalUrl.Match(value);
        if (!match.Success)
        {
            throw new InvalidDataException($"{field} must be a same-document url(#id).");
        }
        return match.Groups["id"].Value;
    }

    private static void ValidateRange(double value, double minimum, double maximum, string field)
    {
        if (value < minimum || value > maximum)
        {
            throw new InvalidDataException($"{field} must be within {minimum}..{maximum}.");
        }
    }

    private static void ValidateEnum(string value, IReadOnlySet<string> allowed, string field)
    {
        if (!allowed.Contains(value))
        {
            throw new InvalidDataException($"{field} is outside the controlled enum.");
        }
    }

    private static bool SkipWhitespace(string value, ref int index)
    {
        var start = index;
        while (index < value.Length && value[index] is ' ' or '\t' or '\r' or '\n')
        {
            index++;
        }
        return index != start;
    }

    private static bool IsPathCommand(char value) =>
        value is 'A' or 'a' or 'C' or 'c' or 'H' or 'h' or 'L' or 'l' or
            'M' or 'm' or 'Q' or 'q' or 'S' or 's' or 'T' or 't' or
            'V' or 'v' or 'Z' or 'z';

    private static bool IsAsciiLetter(char value) =>
        value is >= 'A' and <= 'Z' or >= 'a' and <= 'z';

    private static bool IsIdentifier(string value) =>
        value.Length > 0 &&
        (IsAsciiLetter(value[0]) || value[0] == '_') &&
        value.All(character =>
            IsAsciiLetter(character) ||
            char.IsAsciiDigit(character) ||
            character is '_' or '-' or '.' or ':');

    private enum VisitState
    {
        Visiting,
        Visited
    }

    private enum ReferenceKind
    {
        Paint,
        ClipPath,
        Gradient,
        Use
    }

    private readonly record struct ReferenceEdge(
        XElement Source,
        string TargetId,
        ReferenceKind Kind);

    private readonly record struct RenderExpansionNode(
        int PhysicalNodes,
        IReadOnlyList<string> Targets);

    private readonly record struct RenderExpansionResult(
        int ExpandedNodes,
        int LongestDepth);

    private readonly record struct SemanticTraversalItem(
        XElement Element,
        AffineMatrix Parent,
        bool ForceDefinitionRoot);

    private readonly record struct AffineMatrix(
        double A,
        double B,
        double C,
        double D,
        double E,
        double F)
    {
        internal static AffineMatrix Identity { get; } = new(1, 0, 0, 1, 0, 0);

        internal static AffineMatrix Translation(double x, double y) =>
            new(1, 0, 0, 1, x, y);

        internal static AffineMatrix Multiply(AffineMatrix parent, AffineMatrix local) =>
            new(
                (parent.A * local.A) + (parent.C * local.B),
                (parent.B * local.A) + (parent.D * local.B),
                (parent.A * local.C) + (parent.C * local.D),
                (parent.B * local.C) + (parent.D * local.D),
                (parent.A * local.E) + (parent.C * local.F) + parent.E,
                (parent.B * local.E) + (parent.D * local.F) + parent.F);

        internal void ValidateBounded(string field)
        {
            if (!double.IsFinite(A) ||
                !double.IsFinite(B) ||
                !double.IsFinite(C) ||
                !double.IsFinite(D) ||
                !double.IsFinite(E) ||
                !double.IsFinite(F) ||
                Math.Abs(A) > MaxCoordinateMagnitude ||
                Math.Abs(B) > MaxCoordinateMagnitude ||
                Math.Abs(C) > MaxCoordinateMagnitude ||
                Math.Abs(D) > MaxCoordinateMagnitude ||
                Math.Abs(E) > MaxCoordinateMagnitude ||
                Math.Abs(F) > MaxCoordinateMagnitude)
            {
                throw new InvalidDataException(
                    $"{field} has a non-finite or out-of-bounds matrix component.");
            }
        }
    }

    private readonly record struct PathStats(int Commands, int Numbers);

    private readonly record struct PathToken(
        char Command,
        double Number,
        string Raw,
        bool IsCommand)
    {
        internal static PathToken ForCommand(char command) => new(command, 0, string.Empty, true);

        internal static PathToken ForNumber(double number, string raw) => new('\0', number, raw, false);
    }
}

internal static class StrictSvgFacade
{
    internal static QualifiedSvg Load(ReadOnlyMemory<byte> immutableBytes)
    {
        StrictSvgValidator.Validate(immutableBytes);
        SvgDocument.DisableDtdProcessing = true;

        var svg = new SKSvg();
        svg.Settings.AlphaType = SKAlphaType.Premul;
        svg.Settings.ColorType = SKColorType.Bgra8888;
        svg.Settings.EnableJavaScript = false;
        svg.Settings.EnableExternalJavaScript = false;
        svg.Settings.EnableBrokenImagePlaceholders = false;
        svg.Settings.EnableSvgFonts = false;
        svg.Settings.EnableTextReferences = false;
        svg.Settings.EnableFilterBackgroundInputs = false;
        svg.Settings.EnableTextSelectionRendering = false;

        try
        {
            var loadOptions = new SvgDocumentLoadOptions
            {
                ProcessingMode = SvgProcessingMode.SecureStatic,
                ExternalResources = SvgExternalResourcePolicy.Disabled,
                PreserveUnknownElements = false,
                PreferSvg2Href = true
            };
            var parameters = new SvgParameters(null, null, null, loadOptions);
            using var stream = new MemoryStream(immutableBytes.ToArray(), writable: false);
            var picture = svg.Load(stream, parameters, new Uri("urn:cf7:player-info-hud:qualification"));
            if (picture is null)
            {
                throw new InvalidDataException("Svg.Skia returned no picture.");
            }
            var bounds = picture.CullRect;
            if (!float.IsFinite(bounds.Left) ||
                !float.IsFinite(bounds.Top) ||
                !float.IsFinite(bounds.Right) ||
                !float.IsFinite(bounds.Bottom) ||
                bounds.Width <= 0 ||
                bounds.Height <= 0)
            {
                throw new InvalidDataException("Svg.Skia returned empty or non-finite picture bounds.");
            }
            return new QualifiedSvg(svg);
        }
        catch
        {
            svg.Dispose();
            throw;
        }
    }
}

internal sealed class QualifiedSvg(SKSvg svg) : IDisposable
{
    private SKSvg? _svg = svg;

    internal SKBitmap Rasterize(int width, int height)
    {
        if (width is <= 0 or > StrictSvgValidator.MaxDimension ||
            height is <= 0 or > StrictSvgValidator.MaxDimension)
        {
            throw new ArgumentOutOfRangeException(nameof(width), "Raster dimensions are outside the contract.");
        }

        var bitmap = new SKBitmap(width, height, SKColorType.Bgra8888, SKAlphaType.Premul);
        if (bitmap.GetPixels() == IntPtr.Zero ||
            bitmap.ColorType != SKColorType.Bgra8888 ||
            bitmap.AlphaType != SKAlphaType.Premul ||
            bitmap.RowBytes < checked(width * 4))
        {
            bitmap.Dispose();
            throw new InvalidDataException("Raster allocation violates the BGRA/Premul stride contract.");
        }
        using var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.Transparent);
        (_svg ?? throw new ObjectDisposedException(nameof(QualifiedSvg))).Draw(canvas);
        canvas.Flush();
        return bitmap;
    }

    public void Dispose()
    {
        Interlocked.Exchange(ref _svg, null)?.Dispose();
    }
}
