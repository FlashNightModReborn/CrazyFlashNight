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

    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly XNamespace SvgNamespace = "http://www.w3.org/2000/svg";
    private static readonly Regex LocalUrl = new(
        @"^url\(\s*#(?<id>[A-Za-z_][A-Za-z0-9_.:-]*)\s*\)$",
        RegexOptions.CultureInvariant);
    private static readonly Regex PathCommand = new(
        @"[AaCcHhLlMmQqSsTtVvZz]",
        RegexOptions.CultureInvariant);
    private static readonly Regex PathNumber = new(
        @"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?",
        RegexOptions.CultureInvariant);

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
        if (document.Nodes().Any(node => node is XProcessingInstruction))
        {
            throw new InvalidDataException("Processing instructions are forbidden.");
        }
        if (document.Root is null || document.Root.Name != SvgNamespace + "svg")
        {
            throw new InvalidDataException("Root must be an SVG-namespace svg element.");
        }

        var ids = new HashSet<string>(StringComparer.Ordinal);
        var references = new List<string>();
        var nodeCount = 0;
        foreach (var element in document.Descendants())
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

                if (name == "id" && (!ids.Add(value) || !IsIdentifier(value)))
                {
                    throw new InvalidDataException($"Invalid or duplicate id: {value}.");
                }
                if (name == "href")
                {
                    if (!value.StartsWith('#') || value.Length == 1 || !IsIdentifier(value[1..]))
                    {
                        throw new InvalidDataException("Only same-document href is allowed.");
                    }
                    references.Add(value[1..]);
                }
                if (value.Contains("url(", StringComparison.OrdinalIgnoreCase))
                {
                    var match = LocalUrl.Match(value);
                    if (!match.Success)
                    {
                        throw new InvalidDataException("Only same-document url(#id) is allowed.");
                    }
                    references.Add(match.Groups["id"].Value);
                }
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

        foreach (var reference in references)
        {
            if (!ids.Contains(reference))
            {
                throw new InvalidDataException($"Unresolved same-document reference: #{reference}.");
            }
        }

        ValidateRootGeometry(document.Root);
        ValidatePathComplexity(document);
    }

    private static void ValidateRootGeometry(XElement root)
    {
        var width = ParseFinite(root.Attribute("width")?.Value, "width");
        var height = ParseFinite(root.Attribute("height")?.Value, "height");
        if (width <= 0 || height <= 0 || width > MaxDimension || height > MaxDimension)
        {
            throw new InvalidDataException($"SVG dimensions must be within 1..{MaxDimension}.");
        }

        var parts = (root.Attribute("viewBox")?.Value ?? string.Empty)
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 4)
        {
            throw new InvalidDataException("viewBox must contain four finite numbers.");
        }
        var values = parts.Select(value => ParseFinite(value, "viewBox")).ToArray();
        if (values[2] <= 0 || values[3] <= 0 || values.Any(value => Math.Abs(value) > 1_000_000))
        {
            throw new InvalidDataException("viewBox is outside the qualification bounds.");
        }
    }

    private static double ParseFinite(string? value, string field)
    {
        if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var result) ||
            !double.IsFinite(result))
        {
            throw new InvalidDataException($"{field} must be finite.");
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
            var commands = PathCommand.Matches(data).Count;
            var numbers = PathNumber.Matches(data).Count;
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

    private static bool IsIdentifier(string value) =>
        value.Length > 0 &&
        (char.IsLetter(value[0]) || value[0] == '_') &&
        value.All(character => char.IsLetterOrDigit(character) || character is '_' or '-' or '.' or ':');
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
