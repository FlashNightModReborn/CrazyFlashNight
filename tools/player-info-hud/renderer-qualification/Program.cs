using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Cf7.PlayerInfoHud.RendererQualification;
using SkiaSharp;
using Svg;
using Svg.Model;
using Svg.Skia;

var reportPath = GetOption(args, "--report");
var assetManifestPath = GetOption(args, "--asset-manifest");
var fixtureRoot = Path.Combine(AppContext.BaseDirectory, "fixtures");
var syntheticBytes = Encoding.UTF8.GetBytes(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"20\" viewBox=\"0 0 100 20\">\n" +
    "  <defs>\n" +
    "    <linearGradient id=\"reflect\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" x2=\"25\" y2=\"0\" spreadMethod=\"reflect\">\n" +
    "      <stop offset=\"0\" stop-color=\"#ff0000\"/>\n" +
    "      <stop offset=\"1\" stop-color=\"#0000ff\"/>\n" +
    "    </linearGradient>\n" +
    "    <clipPath id=\"bounds\"><path d=\"M0 0H100V20H0Z\"/></clipPath>\n" +
    "    <path id=\"marker\" d=\"M0 0H4V4H0Z\"/>\n" +
    "  </defs>\n" +
    "  <g clip-path=\"url(#bounds)\" opacity=\"0.5\">\n" +
    "    <path d=\"M0 0H100V20H0Z\" fill=\"url(#reflect)\"/>\n" +
    "  </g>\n" +
    "  <use href=\"#marker\" transform=\"matrix(1 0 0 1 90 8)\" fill=\"#ffffff\"/>\n" +
    "</svg>\n");
var controlledValueGrammarBytes = Encoding.UTF8.GetBytes(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"32\" viewBox=\"0 0 64 32\" preserveAspectRatio=\"none\">\n" +
    "  <defs>\n" +
    "    <linearGradient id=\"base\" gradientUnits=\"objectBoundingBox\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\" spreadMethod=\"repeat\">\n" +
    "      <stop offset=\"0\" stop-color=\"#AABBCC\" stop-opacity=\"0.5\"/>\n" +
    "      <stop offset=\"1\" stop-color=\"#112233\" stop-opacity=\"1\"/>\n" +
    "    </linearGradient>\n" +
    "    <linearGradient id=\"derived\" href=\"#base\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" x2=\"64\" y2=\"0\" gradientTransform=\"matrix(1 0 0 1 1 2)\" spreadMethod=\"pad\"/>\n" +
    "    <radialGradient id=\"radial\" gradientUnits=\"userSpaceOnUse\" cx=\"16\" cy=\"16\" r=\"8\" fx=\"16\" fy=\"16\" spreadMethod=\"reflect\">\n" +
    "      <stop offset=\"0.25\" stop-color=\"#FFFFFF\"/><stop offset=\"0.75\" stop-color=\"#000000\"/>\n" +
    "    </radialGradient>\n" +
    "    <clipPath id=\"clip\" clipPathUnits=\"objectBoundingBox\"><rect x=\"0\" y=\"0\" width=\"1\" height=\"1\"/></clipPath>\n" +
    "    <path id=\"marker\" d=\"M0 0 L1 0 H2 V1 C2 1 3 2 4 3 S5 4 6 5 Q7 6 8 7 T10 9 A1 1 0 0 1 12 11 Z\"/>\n" +
    "  </defs>\n" +
    "  <g transform=\"matrix(1 0 0 1 1 0)\"><g transform=\"matrix(1 0 0 1 0 0)\"><g transform=\"matrix(1 0 0 1 0 0)\">\n" +
    "    <path d=\"M0 0H32V16H0Z\" fill=\"url(#derived)\" stroke=\"#AABBCC\" stroke-width=\"0.5\" opacity=\"0.5\" fill-rule=\"nonzero\" clip-rule=\"evenodd\" clip-path=\"url(#clip)\" stroke-linecap=\"square\" stroke-linejoin=\"bevel\" stroke-miterlimit=\"4\"/>\n" +
    "  </g></g></g>\n" +
    "  <use href=\"#marker\" x=\"1\" y=\"1\" width=\"8\" height=\"8\" transform=\"matrix(1 0 0 1 0 0)\" fill=\"#FFFFFF\"/>\n" +
    "  <circle cx=\"4\" cy=\"4\" r=\"1\" fill=\"none\"/><ellipse cx=\"8\" cy=\"4\" rx=\"2\" ry=\"1\" fill=\"none\"/>\n" +
    "  <line x1=\"0\" y1=\"31\" x2=\"8\" y2=\"31\" stroke=\"#000000\"/><polyline points=\"10,31 12,29\" fill=\"none\"/><polygon points=\"14,31 16,29 18,31\" fill=\"none\"/>\n" +
    "</svg>\n");
var hpMpBytes = File.ReadAllBytes(Path.Combine(fixtureRoot, "hp-mp-feature-derived.svg"));
var tests = new List<TestResult>();
var metrics = new SortedDictionary<string, object?>();
var unsafeDefaults = new SortedDictionary<string, object?>();
CanonicalAssetValidationResult? canonicalAssets = null;

Run("unsafe_defaults_are_documented", () =>
{
    unsafeDefaults["disableDtdProcessing"] = SvgDocument.DisableDtdProcessing;
    unsafeDefaults["externalResourcePolicy"] = new SvgDocumentLoadOptions().ExternalResources.ToString();
    using var defaults = new SKSvg();
    unsafeDefaults["alphaType"] = defaults.Settings.AlphaType.ToString();
    unsafeDefaults["enableJavaScript"] = defaults.Settings.EnableJavaScript;
    unsafeDefaults["enableExternalJavaScript"] = defaults.Settings.EnableExternalJavaScript;
    unsafeDefaults["enableBrokenImagePlaceholders"] = defaults.Settings.EnableBrokenImagePlaceholders;

    Require(!SvgDocument.DisableDtdProcessing, "Candidate default unexpectedly disables DTD processing.");
    Require(new SvgDocumentLoadOptions().ExternalResources == SvgExternalResourcePolicy.Enabled,
        "Candidate default external-resource policy changed.");
    Require(defaults.Settings.AlphaType == SKAlphaType.Unpremul, "Candidate default alpha type changed.");
    Require(!defaults.Settings.EnableJavaScript, "JavaScript master switch must default off.");
    Require(defaults.Settings.EnableExternalJavaScript, "External-JS sub-switch risk is no longer reproducible.");
    Require(defaults.Settings.EnableBrokenImagePlaceholders, "Broken-image placeholder risk changed.");
});

Run("strict_validator_accepts_qualification_corpus", () =>
{
    StrictSvgValidator.Validate(syntheticBytes);
    StrictSvgValidator.Validate(hpMpBytes);
});

Run("strict_validator_accepts_controlled_value_grammar", () =>
{
    using var svg = StrictSvgFacade.Load(controlledValueGrammarBytes);
    using var bitmap = svg.Rasterize(64, 32);
    var renderedPixels = CountNonTransparent(bitmap);
    Require(renderedPixels > 0, "Controlled value-grammar document rasterized empty.");
    StrictSvgValidator.Validate(
        Encoding.UTF8.GetBytes(UseReferenceChain(StrictSvgValidator.MaxReferenceDepth)));
    StrictSvgValidator.Validate(
        Encoding.UTF8.GetBytes(GradientReferenceChain(StrictSvgValidator.MaxReferenceDepth)));
    StrictSvgValidator.Validate(Encoding.UTF8.GetBytes(AcyclicUseExpansion(13)));
    metrics["controlledValueGrammarDocuments"] = 1;
    metrics["controlledValueGrammarPixels"] = renderedPixels;
    metrics["referenceDepthAcceptedBoundary"] = StrictSvgValidator.MaxReferenceDepth;
    metrics["semanticExpansionAcceptedLevels"] = 13;
});

Run("strict_validator_fail_closed_matrix", () =>
{
    var cases = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["malformed"] = "<svg><path></svg>",
        ["dtd"] = "<!DOCTYPE svg [<!ENTITY x 'boom'>]><svg xmlns='http://www.w3.org/2000/svg' width='1' height='1' viewBox='0 0 1 1'><path id='&x;' d='M0 0'/></svg>",
        ["script"] = Wrap("<script>throw 1</script>"),
        ["event"] = Wrap("<path d='M0 0' onclick='x()'/>"),
        ["root_event"] = "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16' onload='x()'><path d='M0 0'/></svg>",
        ["root_unknown_attribute"] = "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16' mystery='1'><path d='M0 0'/></svg>",
        ["nested_processing_instruction"] = Wrap("<g><?cf7 unsafe?><path d='M0 0'/></g>"),
        ["image_http"] = Wrap("<image href='http://127.0.0.1:9/x.png' width='1' height='1'/>"),
        ["image_data"] = Wrap("<image href='data:image/png;base64,AA==' width='1' height='1'/>"),
        ["text"] = Wrap("<text x='0' y='1'>HP</text>"),
        ["animation"] = Wrap("<animate attributeName='opacity' from='0' to='1'/>"),
        ["foreign_object"] = Wrap("<foreignObject width='1' height='1'/>"),
        ["style"] = Wrap("<style>path{fill:red}</style>"),
        ["cross_file_href"] = Wrap("<use href='other.svg#x'/>"),
        ["unknown_attribute"] = Wrap("<path d='M0 0' mystery='1'/>"),
        ["unknown_element"] = Wrap("<metadata/>"),
        ["oversized"] = "<svg xmlns='http://www.w3.org/2000/svg' width='4097' height='1' viewBox='0 0 4097 1'><path d='M0 0H1V1Z'/></svg>",
        ["nested_svg"] = Wrap("<svg width='1' height='1' viewBox='0 0 1 1'><path d='M0 0H1V1Z'/></svg>"),
        ["deep"] = DeepSvg(70),
        ["path_complexity"] = TooComplexPath()
    };
    var valueGrammarCases = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["transform_unknown"] = Wrap("<g transform='skewX(1)'><path d='M0 0H1V1Z'/></g>"),
        ["transform_matrix_arity"] = Wrap("<g transform='matrix(1 0 0 1 0)'><path d='M0 0H1V1Z'/></g>"),
        ["transform_translate_arity"] = Wrap("<g transform='translate(1 2 3)'><path d='M0 0H1V1Z'/></g>"),
        ["transform_scale_empty"] = Wrap("<g transform='scale()'><path d='M0 0H1V1Z'/></g>"),
        ["transform_rotate_arity"] = Wrap("<g transform='rotate(1 2)'><path d='M0 0H1V1Z'/></g>"),
        ["transform_nonfinite"] = Wrap("<g transform='matrix(1 0 0 1 1e309 0)'><path d='M0 0H1V1Z'/></g>"),
        ["transform_trailing_junk"] = Wrap("<g transform='translate(1)junk'><path d='M0 0H1V1Z'/></g>"),
        ["transform_missing_separator"] = Wrap("<g transform='translate(1)scale(1)'><path d='M0 0H1V1Z'/></g>"),
        ["composite_matrix_out_of_bounds"] = Wrap("<g transform='matrix(1001 0 0 1001 0 0)'><g transform='matrix(1000 0 0 1000 0 0)'><path d='M0 0H1V1Z'/></g></g>"),
        ["semantic_use_composite_matrix_out_of_bounds"] = Wrap(
            "<defs>" +
            "<g id='semantic-a' transform='matrix(10 0 0 10 0 0)'><path d='M0 0H1V1Z' clip-path='url(#semantic-clip)'/></g>" +
            "<clipPath id='semantic-clip' transform='matrix(10 0 0 10 0 0)'><use href='#semantic-b' x='1' y='0'/></clipPath>" +
            "<g id='semantic-b' transform='matrix(1000 0 0 1000 1000 0)'><path d='M0 0H1V1Z'/></g>" +
            "</defs><use href='#semantic-a' transform='matrix(10 0 0 10 0 0)'/>"),
        ["path_not_moveto"] = Wrap("<path d='L0 0L1 1'/>"),
        ["relative_path"] = Wrap("<path d='m0 0L1 1'/>"),
        ["path_unknown_command"] = Wrap("<path d='M0 0X1 1'/>"),
        ["path_wrong_arity"] = Wrap("<path d='M0 0L1'/>"),
        ["path_nonfinite"] = Wrap("<path d='M0 0L1e309 1'/>"),
        ["path_unbounded"] = Wrap("<path d='M0 0L1000001 1'/>"),
        ["path_arc_bad_flag"] = Wrap("<path d='M0 0A1 1 0 2 0 2 2'/>"),
        ["path_arc_negative_radius"] = Wrap("<path d='M0 0A-1 1 0 0 0 2 2'/>"),
        ["path_trailing_comma"] = Wrap("<path d='M0 0L1 1,'/>"),
        ["path_comma_before_command"] = Wrap("<path d='M0 0,L1 1'/>"),
        ["path_decimal_without_separator"] = Wrap("<path d='M0 0L1.0.5 1'/>"),
        ["path_garbage_suffix"] = Wrap("<path d='M0 0L1 1 garbage'/>"),
        ["fill_named_color"] = Wrap("<path d='M0 0H1V1Z' fill='red'/>"),
        ["fill_short_hex"] = Wrap("<path d='M0 0H1V1Z' fill='#fff'/>"),
        ["fill_external_url"] = Wrap("<path d='M0 0H1V1Z' fill='url(http://example.invalid/g)'/>"),
        ["stroke_function_color"] = Wrap("<path d='M0 0H1V1Z' stroke='rgb(0,0,0)'/>"),
        ["stop_color_named"] = Wrap("<defs><linearGradient id='g'><stop offset='0' stop-color='red'/></linearGradient></defs><path d='M0 0H1V1Z' fill='url(#g)'/>"),
        ["opacity_above_one"] = Wrap("<path d='M0 0H1V1Z' opacity='1.01'/>"),
        ["opacity_below_zero"] = Wrap("<path d='M0 0H1V1Z' opacity='-0.01'/>"),
        ["stop_opacity_above_one"] = Wrap("<defs><linearGradient id='g'><stop offset='0' stop-color='#000000' stop-opacity='2'/></linearGradient></defs><path d='M0 0H1V1Z' fill='url(#g)'/>"),
        ["offset_above_one"] = Wrap("<defs><linearGradient id='g'><stop offset='1.1' stop-color='#000000'/></linearGradient></defs><path d='M0 0H1V1Z' fill='url(#g)'/>"),
        ["offset_percent"] = Wrap("<defs><linearGradient id='g'><stop offset='50%' stop-color='#000000'/></linearGradient></defs><path d='M0 0H1V1Z' fill='url(#g)'/>"),
        ["gradient_units_enum"] = Wrap("<defs><linearGradient id='g' gradientUnits='viewport'/></defs><path d='M0 0H1V1Z' fill='url(#g)'/>"),
        ["spread_method_enum"] = Wrap("<defs><linearGradient id='g' spreadMethod='mirror'/></defs><path d='M0 0H1V1Z' fill='url(#g)'/>"),
        ["fill_rule_enum"] = Wrap("<path d='M0 0H1V1Z' fill-rule='alternate'/>"),
        ["linecap_enum"] = Wrap("<path d='M0 0H1V1Z' stroke-linecap='flat'/>"),
        ["linejoin_enum"] = Wrap("<path d='M0 0H1V1Z' stroke-linejoin='arcs'/>"),
        ["preserve_aspect_ratio_enum"] = "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16' preserveAspectRatio='xMiddleYMid meet'><path d='M0 0H1V1Z'/></svg>",
        ["coordinate_nonfinite"] = Wrap("<rect x='1e309' y='0' width='1' height='1'/>"),
        ["dimension_negative"] = Wrap("<rect x='0' y='0' width='-1' height='1'/>"),
        ["stroke_width_negative"] = Wrap("<path d='M0 0H1V1Z' stroke-width='-1'/>"),
        ["miterlimit_below_one"] = Wrap("<path d='M0 0H1V1Z' stroke-miterlimit='0.5'/>"),
        ["points_odd"] = Wrap("<polyline points='0 0 1'/>"),
        ["points_trailing_junk"] = Wrap("<polygon points='0 0 1 0 1 1 junk'/>"),
        ["duplicate_id"] = Wrap("<path id='same' d='M0 0H1V1Z'/><path id='same' d='M1 1H2V2Z'/>"),
        ["unresolved_local_url"] = Wrap("<path d='M0 0H1V1Z' fill='url(#missing)'/>"),
        ["paint_wrong_target_type"] = Wrap("<defs><path id='p' d='M0 0H1V1Z'/></defs><path d='M0 0H1V1Z' fill='url(#p)'/>"),
        ["clip_wrong_target_type"] = Wrap("<defs><linearGradient id='g'/></defs><path d='M0 0H1V1Z' clip-path='url(#g)'/>"),
        ["gradient_href_wrong_target_type"] = Wrap("<defs><path id='p' d='M0 0H1V1Z'/><linearGradient id='g' href='#p'/></defs><path d='M0 0H1V1Z' fill='url(#g)'/>"),
        ["use_wrong_target_type"] = Wrap("<defs><linearGradient id='g'/></defs><use href='#g'/>"),
        ["gradient_href_cycle"] = Wrap("<defs><linearGradient id='a' href='#b'/><linearGradient id='b' href='#a'/></defs><path d='M0 0H1V1Z' fill='url(#a)'/>"),
        ["use_direct_cycle"] = Wrap("<defs><use id='a' href='#b'/><use id='b' href='#a'/></defs><use href='#a'/>"),
        ["use_group_cycle"] = Wrap("<defs><g id='a'><use href='#b'/></g><g id='b'><use href='#a'/></g></defs><use href='#a'/>"),
        ["clip_self_cycle"] = Wrap("<defs><clipPath id='clip' clip-path='url(#clip)'><path d='M0 0H1V1Z'/></clipPath></defs><path d='M0 0H1V1Z' clip-path='url(#clip)'/>"),
        ["clip_use_mixed_cycle"] = Wrap("<defs><clipPath id='clip'><use href='#group'/></clipPath><g id='group' clip-path='url(#clip)'><path d='M0 0H1V1Z'/></g></defs><use href='#group'/>"),
        ["use_reference_depth_33"] = UseReferenceChain(33),
        ["gradient_href_depth_33"] = GradientReferenceChain(33),
        ["acyclic_use_expansion_over_32768"] = AcyclicUseExpansion(15)
    };
    var expectedMessages = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["oversized"] = "SVG dimensions",
        ["nested_svg"] = "Nested svg",
        ["composite_matrix_out_of_bounds"] = "composite-transform",
        ["semantic_use_composite_matrix_out_of_bounds"] = "semantic-composite-transform",
        ["relative_path"] = "Relative path",
        ["clip_self_cycle"] = "use/clip-path render-reference cycle",
        ["clip_use_mixed_cycle"] = "use/clip-path render-reference cycle",
        ["use_reference_depth_33"] = "use/clip-path render-reference depth",
        ["gradient_href_depth_33"] = "gradient href depth",
        ["acyclic_use_expansion_over_32768"] = "semantic expansion"
    };

    foreach (var item in cases)
    {
        ExpectRejected(
            item.Key,
            Encoding.UTF8.GetBytes(item.Value),
            expectedMessages.GetValueOrDefault(item.Key));
    }
    foreach (var item in valueGrammarCases)
    {
        ExpectRejected(
            item.Key,
            Encoding.UTF8.GetBytes(item.Value),
            expectedMessages.GetValueOrDefault(item.Key));
    }
    metrics["valueGrammarFailClosedCases"] = valueGrammarCases.Count;
    metrics["failClosedCases"] = cases.Count + valueGrammarCases.Count;
});

Run("synthetic_reflect_use_clip_and_premul", () =>
{
    using var svg = StrictSvgFacade.Load(syntheticBytes);
    using var bitmap = svg.Rasterize(100, 20);
    var samples = new[] { 1, 24, 49, 74, 99 }.Select(x => bitmap.GetPixel(x, 2)).ToArray();
    Require(samples[0].Red > samples[0].Blue, "Reflect sample 0 should be red-dominant.");
    Require(samples[1].Blue > samples[1].Red, "Reflect sample 1 should be blue-dominant.");
    Require(samples[2].Red > samples[2].Blue, "Reflect sample 2 should be red-dominant.");
    Require(samples[3].Blue > samples[3].Red, "Reflect sample 3 should be blue-dominant.");
    Require(samples[4].Red > samples[4].Blue, "Reflect sample 4 should be red-dominant.");
    Require(samples.All(sample => Math.Abs(sample.Alpha - 128) <= 1), "Opacity must resolve to alpha 128.");
    Require(bitmap.GetPixel(91, 9).Alpha == 255, "Same-document use marker did not render.");

    var raw = ReadRawBgra(bitmap, 49, 2);
    Require(raw.A is >= 127 and <= 129 && raw.R <= raw.A && raw.G <= raw.A && raw.B <= raw.A,
        "Raw BGRA output is not premultiplied.");
    metrics["rawPremulBgra"] = new[] { (int)raw.B, raw.G, raw.R, raw.A };
});

Run("hp_mp_feature_derived_corpus", () =>
{
    var sourceText = Encoding.UTF8.GetString(hpMpBytes);
    Require(sourceText.Contains("主角hp显示界面.xml :: 红色底色", StringComparison.Ordinal) &&
        sourceText.Contains("#FF0000", StringComparison.Ordinal) &&
        sourceText.Contains("#330000", StringComparison.Ordinal),
        "HP fixture lost its exact XFL feature anchors.");
    Require(sourceText.Contains("主角mp显示界面.xml :: 左侧MP槽", StringComparison.Ordinal) &&
        sourceText.Contains("#66FFFF", StringComparison.Ordinal) &&
        sourceText.Contains("#0033CC", StringComparison.Ordinal),
        "MP fixture lost its exact XFL feature anchors.");
    using var svg = StrictSvgFacade.Load(hpMpBytes);
    using var bitmap = svg.Rasterize(160, 48);
    var hp = bitmap.GetPixel(20, 15);
    var mp = bitmap.GetPixel(112, 34);
    Require(hp.Alpha > 150 && hp.Red > hp.Blue, "HP-derived fill did not render as expected.");
    Require(mp.Alpha > 150 && mp.Blue > mp.Red, "MP-derived fill did not render as expected.");
    Require(bitmap.GetPixel(0, 0).Alpha == 0, "Corpus background must remain transparent.");
});

if (!string.IsNullOrWhiteSpace(assetManifestPath))
{
    Run("canonical_asset_manifest_and_eight_svg", () =>
    {
        canonicalAssets = CanonicalAssetValidator.Validate(assetManifestPath);
    });
}

Run("strict_facade_rejects_empty_picture", () =>
{
    const string empty = "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'/>";
    try
    {
        using var ignored = StrictSvgFacade.Load(Encoding.UTF8.GetBytes(empty));
        throw new InvalidOperationException("Facade accepted an empty picture.");
    }
    catch (InvalidDataException)
    {
    }
});

Run("resource_disabled_alone_is_not_fail_closed", () =>
{
    const string external = "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'><image href='http://127.0.0.1:9/x.png' width='16' height='16'/></svg>";
    using var bitmap = RenderUnchecked(Encoding.UTF8.GetBytes(external), 16, 16);
    var pixels = CountNonTransparent(bitmap);
    Require(pixels == 0, "External-resource-disabled renderer probe should be empty.");
    metrics["rendererOnlyExternalPixels"] = pixels;
});

Run("independent_parse_raster_parallel_8x25", () =>
{
    Parallel.For(0, 200, new ParallelOptions { MaxDegreeOfParallelism = 8 }, _ =>
    {
        using var svg = StrictSvgFacade.Load(syntheticBytes);
        using var bitmap = svg.Rasterize(100, 20);
        Require(bitmap.GetPixel(49, 2).Alpha is >= 127 and <= 129,
            "Independent parallel raster alpha drifted.");
    });
    metrics["independentParallelIterations"] = 200;
});

Run("shared_readonly_raster_parallel_8x25", () =>
{
    using var svg = StrictSvgFacade.Load(syntheticBytes);
    Parallel.For(0, 200, new ParallelOptions { MaxDegreeOfParallelism = 8 }, _ =>
    {
        using var bitmap = svg.Rasterize(100, 20);
        Require(bitmap.GetPixel(49, 2).Alpha is >= 127 and <= 129,
            "Shared read-only raster alpha drifted.");
    });
    metrics["sharedReadonlyParallelIterations"] = 200;
});

Run("parse_raster_dispose_2x500", () =>
{
    for (var i = 0; i < 20; i++)
    {
        using var warm = StrictSvgFacade.Load(syntheticBytes);
        using var bitmap = warm.Rasterize(100, 20);
    }
    GC.Collect();
    GC.WaitForPendingFinalizers();
    GC.Collect();

    var process = Process.GetCurrentProcess();
    process.Refresh();
    var handlesBefore = process.HandleCount;
    var privateBefore = process.PrivateMemorySize64;
    for (var batch = 0; batch < 2; batch++)
    {
        for (var i = 0; i < 500; i++)
        {
            using var svg = StrictSvgFacade.Load(syntheticBytes);
            using var bitmap = svg.Rasterize(100, 20);
        }
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
    }
    process.Refresh();
    var handleDelta = process.HandleCount - handlesBefore;
    metrics["disposeIterations"] = 1000;
    metrics["disposeHandleDelta"] = handleDelta;
    metrics["disposePrivateBytesDelta"] = process.PrivateMemorySize64 - privateBefore;
    Require(handleDelta <= 2, $"Handle delta exceeded the qualification bound: {handleDelta}.");
});

var failed = tests.Count(test => test.Status == "failed");
var report = new
{
    schema = "cf7-player-info-renderer-qualification-v1",
    qualificationStatus = failed == 0
        ? "isolated_qualification_passed"
        : "isolated_qualification_failed",
    isolatedQualificationPassed = failed == 0,
    rendererQualified = false,
    expectedSdk = "10.0.300",
    targetFramework = "net10.0-windows",
    runtimeIdentifier = "win-x64",
    packagePins = new[]
    {
        new { id = "SkiaSharp", version = "3.119.4" },
        new { id = "Svg.Skia", version = "5.1.1" }
    },
    fixtures = new[]
    {
        Fixture("synthetic-core:inline", syntheticBytes),
        Fixture("hp-mp-feature-derived.svg", hpMpBytes)
    },
    sourceFeatureAnchors = new[]
    {
        new
        {
            fixture = "hp",
            source = "flashswf/UI/玩家信息界面/LIBRARY/sprite/主角hp显示界面.xml",
            layer = "红色底色",
            feature = "RadialGradient spreadMethod=reflect",
            colors = new[] { "#FF0000", "#330000" }
        },
        new
        {
            fixture = "mp",
            source = "flashswf/UI/玩家信息界面/LIBRARY/sprite/主角mp显示界面.xml",
            layer = "左侧MP槽",
            feature = "RadialGradient spreadMethod=reflect",
            colors = new[] { "#66FFFF", "#0033CC" }
        }
    },
    dependencyAudit = new
    {
        addedNodeCount = 11,
        lockedGraph = "renderer-qualification/packages.lock.json",
        vulnerableFindings = 0,
        deprecatedFindings = 0,
        javaScriptPackagePresent = false,
        packages = new[]
        {
            AuditPackage("Svg.Skia", "5.1.1", "MIT", false,
                "3FC4C8EAECD7A690AD0818F472D0FDFD3D00BC3063ECED4D4D773628658D7B09"),
            AuditPackage("ExCSS", "4.3.1", "MIT", false,
                "9CD9F9F9811AA8A4942E1B43B0898D1329DD53F3079DAED5A593541319A8F34A"),
            AuditPackage("HarfBuzzSharp", "8.3.1.3", "MIT", true,
                "FFE644863A4EB3C078B4C3F0DEF0F2B90A861991C9116BF2DD668A31A0F09AB5"),
            AuditPackage("HarfBuzzSharp.NativeAssets.Linux", "8.3.1.3", "MIT", true,
                "7DE58E9DAFFC9DCBE6AEAEC2C670DCCEFD5F69C576A68655E51F8EC82B687295"),
            AuditPackage("HarfBuzzSharp.NativeAssets.macOS", "8.3.1.3", "MIT", true,
                "E962AC27F8C5F691E7696710BDA7B3739015E9F96EDD7B0EC50B3B8B8046609B"),
            AuditPackage("HarfBuzzSharp.NativeAssets.Win32", "8.3.1.3", "MIT", true,
                "58D51098B595152C01293F71ED47614B3F53D8503BC226EFC23B8F7B0FF7C943"),
            AuditPackage("ShimSkiaSharp", "5.1.1", "MIT", false,
                "76EB2FAA7BA87E6CF17002CC14002C24AD9AD3C1F858D8F05F05A4DFAF316AED"),
            AuditPackage("Svg.Animation", "5.1.1", "MIT", false,
                "99771F4A1B198760FDAFBF5F783F01B6FDB2EE40438ECA9C6BED2C074FDB4E87"),
            AuditPackage("Svg.Custom", "5.1.1", "MS-PL", false,
                "D30C4DA0024711733B687DCDEA1AB1948886DAC1AE30A88B5AE4B213CD330606"),
            AuditPackage("Svg.Model", "5.1.1", "MIT", false,
                "267389628459C6744A45D82251B7F0BF3E0F1C36ADD93CA780233B3BF8CDD986"),
            AuditPackage("Svg.SceneGraph", "5.1.1", "MIT", false,
                "51A838202F81C01830E436B0A33A65E3F926F5CC2E2FCBCB0D3B1526DC3DD3DF")
        },
        producerShapedWinX64Payload = new
        {
            filter = "top-level files excluding .xml and .pdb",
            addedFiles = 9,
            addedBytes = 5_289_528,
            nonTargetNativeFiles = 0,
            excludedHarfBuzzPdbBytes = 20_918_272,
            files = new[]
            {
                PayloadFile("ExCSS.dll", 347_136,
                    "6B166E638181EBA3150F0D10379D1CC8362AF6DFD518E9E9E194AA9A746293C2"),
                PayloadFile("HarfBuzzSharp.dll", 122_400,
                    "55E72AC23263F8E12484F3435E02EC22FAC9EFF6E6D169BB0A8C246BE6B99D29"),
                PayloadFile("libHarfBuzzSharp.dll", 1_816_088,
                    "145ADE963EBA427027D5E1381DB5D51A0EF9E98E9FEF9EFBFA6074CA20DA246F"),
                PayloadFile("ShimSkiaSharp.dll", 218_624,
                    "0AC0BE60DAFE273F4CA021BFDA16D111FFBA990F39E97AC9EDC3BCF488E39603"),
                PayloadFile("Svg.Animation.dll", 124_416,
                    "97E1674100225717AA2B5313EE6C3735CF87EF9056862DF178EE2B91ECCCF8C9"),
                PayloadFile("Svg.Custom.dll", 1_020_416,
                    "89242EB48A25E40DD4C06AD839E11ADDCCC5C07412E319953752F7C963291704"),
                PayloadFile("Svg.Model.dll", 160_768,
                    "DF2B9EB253873321155E8B3173797D591A92D405F29AE725224E447289DC51CF"),
                PayloadFile("Svg.SceneGraph.dll", 1_186_816,
                    "C7142D663BD11B898038F68EAC40CB1182065F5CD1A3EC4BC2C18CBF0D3B6ECA"),
                PayloadFile("Svg.Skia.dll", 292_864,
                    "7BC7FB1621133B3CA78EDAB82E26B520205107B0AEDFB07B4A73EEB0050FC611")
            }
        }
    },
    unsafeDefaults,
    canonicalAssets,
    metrics,
    summary = new { total = tests.Count, passed = tests.Count - failed, failed },
    tests
};
var json = JsonSerializer.Serialize(report, new JsonSerializerOptions
{
    Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    WriteIndented = true
}).Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
Console.WriteLine(json);
if (!string.IsNullOrWhiteSpace(reportPath))
{
    var fullPath = Path.GetFullPath(reportPath);
    Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
    File.WriteAllText(fullPath, json + "\n", new UTF8Encoding(false));
}
return failed == 0 ? 0 : 1;

void Run(string name, Action action)
{
    try
    {
        action();
        tests.Add(new TestResult(name, "passed", null));
    }
    catch (Exception ex)
    {
        tests.Add(new TestResult(name, "failed", $"{ex.GetType().Name}: {ex.Message}"));
    }
}

static object Fixture(string name, byte[] bytes) => new
{
    name,
    bytes = bytes.Length,
    sha256 = Convert.ToHexString(SHA256.HashData(bytes))
};

static object AuditPackage(
    string id,
    string version,
    string license,
    bool requiresLicenseAcceptance,
    string nupkgSha256) => new
{
    id,
    version,
    license,
    requiresLicenseAcceptance,
    nupkgSha256
};

static object PayloadFile(string path, int bytes, string sha256) => new
{
    path,
    bytes,
    sha256
};

static void ExpectRejected(string name, byte[] bytes, string? expectedMessage = null)
{
    try
    {
        StrictSvgValidator.Validate(bytes);
    }
    catch (Exception ex) when (ex is InvalidDataException or System.Xml.XmlException or DecoderFallbackException)
    {
        if (expectedMessage is not null &&
            !ex.Message.Contains(expectedMessage, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Fail-closed case {name} rejected for the wrong reason: {ex.Message}");
        }
        return;
    }
    throw new InvalidOperationException($"Fail-closed case was accepted: {name}.");
}

static string Wrap(string body) =>
    $"<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'>{body}</svg>";

static string DeepSvg(int depth) =>
    "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'>" +
    string.Concat(Enumerable.Repeat("<g>", depth)) + "<path d='M0 0'/>" +
    string.Concat(Enumerable.Repeat("</g>", depth)) + "</svg>";

static string TooComplexPath() =>
    Wrap($"<path d='M0 0{string.Concat(Enumerable.Repeat("L0 0", StrictSvgValidator.MaxPathCommands))}'/>");

static string UseReferenceChain(int referenceDepth)
{
    Require(referenceDepth > 0, "Use-reference depth must be positive.");
    var definitions = new StringBuilder("<defs>");
    for (var index = 0; index < referenceDepth; index++)
    {
        var body = index + 1 < referenceDepth
            ? $"<use href='#use{index + 1}'/>"
            : "<path d='M0 0H1V1Z'/>";
        definitions.Append($"<g id='use{index}'>{body}</g>");
    }
    definitions.Append("</defs>");
    return Wrap(definitions + "<use href='#use0'/>");
}

static string GradientReferenceChain(int hrefDepth)
{
    Require(hrefDepth > 0, "Gradient-reference depth must be positive.");
    var definitions = new StringBuilder("<defs>");
    for (var index = 0; index <= hrefDepth; index++)
    {
        var href = index < hrefDepth ? $" href='#gradient{index + 1}'" : string.Empty;
        definitions.Append(
            $"<linearGradient id='gradient{index}'{href}><stop offset='0' stop-color='#000000'/></linearGradient>");
    }
    definitions.Append("</defs>");
    return Wrap(definitions + "<path d='M0 0H1V1Z' fill='url(#gradient0)'/>");
}

static string AcyclicUseExpansion(int levels)
{
    Require(levels > 1, "Acyclic use-expansion levels must exceed one.");
    var definitions = new StringBuilder(
        "<defs><g id='expansion0'><path d='M0 0H1V1Z'/></g>");
    for (var index = 1; index < levels; index++)
    {
        definitions.Append(
            $"<g id='expansion{index}'><use href='#expansion{index - 1}'/><use href='#expansion{index - 1}'/></g>");
    }
    definitions.Append("</defs>");
    return Wrap(definitions + $"<use href='#expansion{levels - 1}'/>");
}

static SKBitmap RenderUnchecked(byte[] bytes, int width, int height)
{
    var options = new SvgDocumentLoadOptions
    {
        ProcessingMode = SvgProcessingMode.SecureStatic,
        ExternalResources = SvgExternalResourcePolicy.Disabled,
        PreserveUnknownElements = false
    };
    var parameters = new SvgParameters(null, null, null, options);
    using var svg = new SKSvg();
    svg.Settings.EnableJavaScript = false;
    svg.Settings.EnableExternalJavaScript = false;
    svg.Settings.EnableBrokenImagePlaceholders = false;
    using var stream = new MemoryStream(bytes, writable: false);
    Require(svg.Load(stream, parameters, new Uri("urn:cf7:unchecked-probe")) is not null,
        "Unchecked renderer returned no picture.");
    var bitmap = new SKBitmap(width, height, SKColorType.Bgra8888, SKAlphaType.Premul);
    using var canvas = new SKCanvas(bitmap);
    canvas.Clear(SKColors.Transparent);
    svg.Draw(canvas);
    canvas.Flush();
    return bitmap;
}

static (byte B, byte G, byte R, byte A) ReadRawBgra(SKBitmap bitmap, int x, int y)
{
    var bytes = new byte[checked(bitmap.RowBytes * bitmap.Height)];
    Marshal.Copy(bitmap.GetPixels(), bytes, 0, bytes.Length);
    var offset = checked((y * bitmap.RowBytes) + (x * 4));
    return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]);
}

static int CountNonTransparent(SKBitmap bitmap)
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

static string? GetOption(string[] arguments, string option)
{
    var index = Array.IndexOf(arguments, option);
    return index >= 0 && index + 1 < arguments.Length ? arguments[index + 1] : null;
}

static void Require(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

internal sealed record TestResult(string Name, string Status, string? Error);
