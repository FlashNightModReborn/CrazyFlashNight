#nullable enable

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class B006VisualCaptureFactAttribute : FactAttribute
{
    internal const string OutputDirectoryEnvironment =
        "CF7_PLAYER_INFO_B006_VISUAL_OUTPUT_DIR";

    public B006VisualCaptureFactAttribute()
    {
        if (string.IsNullOrEmpty(
                Environment.GetEnvironmentVariable(
                    OutputDirectoryEnvironment)))
        {
            Skip =
                "B0-06 C# visual capture is opt-in and requires an absolute output directory.";
        }
    }
}

public sealed class PlayerInfoB006VisualCaptureTests
{
    private const string CaptureSchema =
        "cf7.player-info-hud.b0-06-csharp-visual-capture";
    private const int CaptureSchemaVersion = 2;
    private const int ContactSheetColumns = 7;
    private const int ContactSheetGap = 2;

    private static readonly ExpectedCase[] ExpectedCases =
    [
        new("empty", 129, 101),
        new("min_step", 128, 100),
        new("p25", 97, 76),
        new("p50", 65, 51),
        new("p75", 33, 26),
        new("p99", 3, 2),
        new("full", 1, 1),
        new("mp_vf34", 44, 34),
        new("mp_vf35", 45, 35),
        new("mp_vf70", 90, 70),
        new("mp_vf91", 117, 91)
    ];

    private static readonly int[] HpFullToEmptyFrames =
    [
        1, 10, 18, 26, 33, 40, 46, 52, 58, 63, 68, 73, 77, 81,
        85, 88, 91, 94, 97, 100, 102, 104, 106, 108, 110, 112,
        114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124,
        125, 126, 127, 128, 129
    ];

    private static readonly string[] ExpectedRasterLayerOrder =
    [
        "mp.backplate",
        "mp.fill",
        "mp.rim",
        "mp.rim-vf70",
        "mp.rim-vf91",
        "hp.backplate",
        "hp.fill",
        "hp.rim"
    ];

    private static readonly string[] SourceClosurePaths =
    [
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoAnimationModel.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoFrameCompositor.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoLayeredDibSurface.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoPathGlyphAtlas.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoPathGlyphAtlas.Generated.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPipeline.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPlan.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSplitSurface.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoStrictSvg.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgAssetCatalog.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgRasterizer.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoVisualState.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoWidget.cs",
        "launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoB006VisualCaptureTests.cs"
    ];
    private static readonly string[] RendererBinaryRelativeNames =
    [
        "ExCSS.dll",
        "HarfBuzzSharp.dll",
        "ShimSkiaSharp.dll",
        "SkiaSharp.dll",
        "Svg.Animation.dll",
        "Svg.Custom.dll",
        "Svg.Model.dll",
        "Svg.SceneGraph.dll",
        "Svg.Skia.dll",
        "runtimes/win-x64/native/libHarfBuzzSharp.dll",
        "runtimes/win-x64/native/libSkiaSharp.dll"
    ];

    [B006VisualCaptureFact]
    [Trait("Category", "PlayerInfoB006VisualCapture")]
    public async Task CaptureFixtureMatrixAndHpTransition()
    {
        string outputRoot = ResolveEmptyOutputRoot();
        string projectRoot = FindProjectRoot();
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(
                minimumRaster: false);

        Assert.Equal(
            assetSet.ExactManifestSha256,
            Sha256Bytes(assetSet.ManifestBytes.ToArray())
                .ToLowerInvariant());
        Assert.Equal(
            new[] { "mp", "hp" },
            assetSet.Stage.CompositeOrder);
        Assert.Equal(
            ExpectedCases.Select(item => item.CaseId),
            PlayerInfoFixtureInput.AllowedCaseIds);

        var outputs = new List<OutputEvidence>();
        var caseCaptures = new List<CaseCaptureEvidence>();
        var viewportCaptures = new List<ViewportCaptureEvidence>();
        var rasterizer = new PlayerInfoSvgRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);

        ViewportCase baselineViewport = CreateViewportCases()[0];
        PlayerInfoRasterPlan baselinePlan =
            CreateAndValidatePlan(assetSet, baselineViewport);
        await MakeCurrentAsync(pipeline, baselinePlan);

        foreach (ExpectedCase expected in ExpectedCases)
        {
            using RenderedFixture rendered = RenderFixtureDeterministically(
                assetSet,
                pipeline,
                baselinePlan,
                expected.CaseId);
            Assert.Equal(
                expected.HpVirtualFrame,
                rendered.VisualState.Hp.CurrentVirtualFrame);
            Assert.Equal(
                expected.MpVirtualFrame,
                rendered.VisualState.Mp.CurrentVirtualFrame);
            Assert.Equal(
                expected.HpVirtualFrame,
                rendered.PaintResult.HpVirtualFrame);
            Assert.Equal(
                expected.MpVirtualFrame,
                rendered.PaintResult.MpVirtualFrame);

            string mainPath =
                $"cases/{expected.CaseId}.main.png";
            string tightPath =
                $"cases/{expected.CaseId}.tight.png";
            outputs.Add(WriteBitmapOutput(
                outputRoot,
                mainPath,
                "fixture-main-viewport",
                baselineViewport.Id,
                expected.CaseId,
                baselinePlan,
                rendered.MainViewport));
            outputs.Add(WriteBitmapOutput(
                outputRoot,
                tightPath,
                "fixture-alpha-tight-crop",
                baselineViewport.Id,
                expected.CaseId,
                baselinePlan,
                rendered.AlphaTightCrop));
            caseCaptures.Add(new CaseCaptureEvidence(
                expected.CaseId,
                rendered.VisualState,
                rendered.PaintResult,
                mainPath,
                tightPath));
        }

        foreach (ViewportCase viewport in CreateViewportCases())
        {
            PlayerInfoRasterPlan plan =
                CreateAndValidatePlan(assetSet, viewport);
            await MakeCurrentAsync(pipeline, plan);
            var states = new List<ViewportStateEvidence>();
            foreach ((string stateId, string caseId) in new[]
                     {
                         ("full", "full"),
                         ("half", "p50"),
                         ("empty", "empty")
                     })
            {
                using RenderedFixture rendered =
                    RenderFixtureDeterministically(
                        assetSet,
                        pipeline,
                        plan,
                        caseId);
                string relativePath =
                    $"viewports/{viewport.Id}/{stateId}.png";
                outputs.Add(WriteBitmapOutput(
                    outputRoot,
                    relativePath,
                    "viewport-key-state-main-viewport",
                    viewport.Id,
                    caseId,
                    plan,
                    rendered.MainViewport));
                states.Add(new ViewportStateEvidence(
                    stateId,
                    caseId,
                    rendered.VisualState,
                    rendered.PaintResult,
                    relativePath));
            }
            viewportCaptures.Add(new ViewportCaptureEvidence(
                viewport.Id,
                Rect(viewport.HostViewport),
                Plan(viewport, plan),
                states));
        }

        await MakeCurrentAsync(pipeline, baselinePlan);
        TransitionCapture transition = CaptureHpFullToEmptyTransition(
            assetSet,
            pipeline,
            baselineViewport,
            baselinePlan);
        using (transition.ContactSheet)
        {
            outputs.Add(WriteBitmapOutput(
                outputRoot,
                transition.ContactSheetPath,
                "hp-full-to-empty-contact-sheet",
                baselineViewport.Id,
                "full-to-empty",
                baselinePlan,
                transition.ContactSheet));
        }

        Assert.Equal(35, outputs.Count);
        Assert.All(outputs, output =>
        {
            Assert.True(output.PngBytes > 0);
            Assert.True(output.AlphaBounds.Width > 0);
            Assert.True(output.AlphaBounds.Height > 0);
            Assert.Equal(
                "Format32bppPArgb",
                output.SourcePixelFormat);
        });

        var binaries = new List<BinaryEvidence>
        {
            CaptureBinary(
                "core",
                typeof(PlayerInfoWidget).Assembly),
            CaptureBinary(
                "tests",
                typeof(PlayerInfoB006VisualCaptureTests).Assembly)
        };
        string testOutputDirectory = Path.GetDirectoryName(
            typeof(PlayerInfoB006VisualCaptureTests).Assembly.Location) ??
            throw new InvalidOperationException(
                "Visual capture test assembly has no output directory.");
        binaries.AddRange(
            RendererBinaryRelativeNames.Select(relativeName =>
                CaptureBinaryFile(
                    "renderer:" + relativeName,
                    testOutputDirectory,
                    relativeName)));
        SourceFileEvidence[] sourceFiles = SourceClosurePaths
            .Select(relativePath =>
                CaptureSourceFile(projectRoot, relativePath))
            .ToArray();
        OutputEvidence[] orderedOutputs = outputs
            .OrderBy(output => output.RelativePath, StringComparer.Ordinal)
            .ToArray();
        OutputClosureEvidence outputClosure =
            CreateOutputClosure(orderedOutputs);

        var manifest = new CaptureManifest(
            CaptureSchema,
            CaptureSchemaVersion,
            "structural_capture_complete",
            "fixture_only",
            new CanvasContractEvidence(
                assetSet.Stage.LogicalWidth,
                (int)PlayerInfoRasterPlanner.MainStageLogicalHeight,
                "transparent_argb_0",
                null,
                "Main Flash content-viewport PNGs place the imported PlayerInfo sprite at main y=512 and contain no substituted checkerboard, matte, or game-scene background."),
            new DeterminismEvidence(
                true,
                true,
                true,
                "No timestamp, run ID, machine name, absolute output path, or random value is serialized.",
                "Each compositor result and PNG encoding is reproduced in-process before acceptance."),
            new AssetEvidence(
                assetSet.AssetSetId,
                assetSet.Revision,
                assetSet.ExactManifestSha256,
                assetSet.RasterContractVersion,
                assetSet.RendererIdentity.Package,
                assetSet.RendererIdentity.Version,
                assetSet.RendererIdentity.SkiaSharpVersion,
                assetSet.RendererIdentity.FeatureSet,
                assetSet.RendererIdentity.ColorType,
                assetSet.RendererIdentity.AlphaType),
            binaries,
            sourceFiles,
            new LayerOrderEvidence(
                assetSet.Stage.CompositeOrder.ToArray(),
                assetSet.Gauges["mp"].AssetIds.ToArray(),
                assetSet.Gauges["hp"].AssetIds.ToArray(),
                baselinePlan.Layers
                    .Select(layer => layer.Key.LayerId)
                    .ToArray()),
            Plan(baselineViewport, baselinePlan),
            caseCaptures,
            viewportCaptures,
            new TransitionEvidence(
                "hp_full_to_empty",
                PlayerInfoAnimationModel.LogicalFramesPerSecond,
                41,
                transition.Frames.Count,
                transition.ContactSheetPath,
                ContactSheetColumns,
                ContactSheetGap,
                transition.Frames),
            orderedOutputs,
            outputClosure,
            [
                "production typed embedded manifest loaded and exact-manifest SHA independently recomputed",
                "production PlayerInfoRasterPipeline supplied every borrowed atomic batch",
                "production PlayerInfoWidget and its production compositor painted every state",
                "11-case allowlist and key virtual-frame mapping matched the frozen contract",
                "four ADR viewport/content/DPI plans matched child-stage metadata, main viewport, and tight physical bounds",
                "global MP-to-HP and exact eight-layer raster order matched the typed contract",
                "every source bitmap satisfied Format32bppPArgb and byte-level premultiplication",
                "same input produced identical top-down PArgb bytes, paint result, and PNG bytes",
                "HP full-to-empty transition contained exactly 41 changing logical ticks plus initial state"
            ],
            [
                "Flash, FFDec, Web, or cross-renderer pixel parity",
                "visual similarity threshold or aesthetic acceptance",
                "game-scene composite appearance",
                "human visual or UI acceptance",
                "real UiData or pi_* integration",
                "candidate execution, e2e verification, promotion, deployment, or standard entry"
            ]);

        WriteCanonicalManifest(
            Path.Combine(outputRoot, "manifest.json"),
            manifest);
        AssertExactOutputClosure(
            outputRoot,
            orderedOutputs.Select(output => output.RelativePath)
                .Append("manifest.json")
                .ToArray());
    }

    private static PlayerInfoRasterPlan CreateAndValidatePlan(
        PlayerInfoSvgAssetSet assetSet,
        ViewportCase viewport)
    {
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assetSet,
            viewport.ContentViewport,
            viewport.MonitorDpiScale);
        Assert.Equal(viewport.ExpectedPhysicalScale, plan.PhysicalScale, 8);
        Assert.Equal(
            viewport.ExpectedStageBounds,
            plan.StagePhysicalBounds);
        Assert.Equal(
            viewport.ExpectedTightBounds,
            plan.TightPhysicalBounds);
        Assert.Equal(
            ExpectedRasterLayerOrder,
            plan.Layers.Select(layer => layer.Key.LayerId));
        return plan;
    }

    private static async Task MakeCurrentAsync(
        PlayerInfoRasterPipeline pipeline,
        PlayerInfoRasterPlan plan)
    {
        pipeline.Request(plan);
        await pipeline.WaitForIdleAsync()
            .WaitAsync(TimeSpan.FromSeconds(15));
        PlayerInfoRasterPipelineSnapshot snapshot = pipeline.Snapshot;
        Assert.Equal(0, snapshot.FaultCount);
        Assert.Null(snapshot.LastFault);
        Assert.Equal(plan.BatchKey, snapshot.DesiredBatchKey);
        Assert.Equal(plan.BatchKey, snapshot.CurrentBatchKey);
        Assert.Equal(0, snapshot.ActiveWorkers);
    }

    private static RenderedFixture RenderFixtureDeterministically(
        PlayerInfoSvgAssetSet assetSet,
        PlayerInfoRasterPipeline pipeline,
        PlayerInfoRasterPlan plan,
        string caseId)
    {
        var model = new PlayerInfoAnimationModel();
        using var widget = new PlayerInfoWidget(assetSet, model);
        Assert.True(model.ApplyFixture(
            PlayerInfoFixtureInput.FromCaseId(caseId)));
        PlayerInfoVisualStateEvidence visualState =
            VisualState(widget.VisualState);

        using Bitmap firstTight = NewTightBitmap(plan);
        PlayerInfoFramePaintResult firstPaint =
            PaintCurrent(pipeline, widget, plan, firstTight);
        using Bitmap secondTight = NewTightBitmap(plan);
        PlayerInfoFramePaintResult secondPaint =
            PaintCurrent(pipeline, widget, plan, secondTight);
        Assert.Equal(firstPaint, secondPaint);
        Assert.Equal(
            ExtractPArgbBytes(firstTight),
            ExtractPArgbBytes(secondTight));
        Assert.Equal(
            EncodePng(firstTight),
            EncodePng(secondTight));
        ValidatePArgb(firstTight);
        ValidatePArgb(secondTight);

        Bitmap mainViewport = PlaceTightOnMainViewport(firstTight, plan);
        using Bitmap secondMainViewport =
            PlaceTightOnMainViewport(secondTight, plan);
        Assert.Equal(
            ExtractPArgbBytes(mainViewport),
            ExtractPArgbBytes(secondMainViewport));
        Assert.Equal(
            EncodePng(mainViewport),
            EncodePng(secondMainViewport));
        Rectangle alphaBounds = FindAlphaBounds(mainViewport);
        Assert.False(alphaBounds.IsEmpty);
        Bitmap alphaTightCrop = CopyRegion(mainViewport, alphaBounds);
        ValidatePArgb(mainViewport);
        ValidatePArgb(alphaTightCrop);
        Assert.Equal(
            new Rectangle(
                0,
                0,
                alphaTightCrop.Width,
                alphaTightCrop.Height),
            FindAlphaBounds(alphaTightCrop));

        return new RenderedFixture(
            mainViewport,
            alphaTightCrop,
            visualState,
            PaintResult(firstPaint));
    }

    private static TransitionCapture CaptureHpFullToEmptyTransition(
        PlayerInfoSvgAssetSet assetSet,
        PlayerInfoRasterPipeline pipeline,
        ViewportCase viewport,
        PlayerInfoRasterPlan plan)
    {
        var model = new PlayerInfoAnimationModel();
        using var widget = new PlayerInfoWidget(assetSet, model);
        Assert.True(model.ApplyFixture(
            PlayerInfoFixtureInput.FromCaseId("full")));
        Assert.True(model.ApplyFixture(
            PlayerInfoFixtureInput.FromCaseId("empty")));
        Assert.True(model.WantsAnimationTick);

        int tileWidth = plan.TightPhysicalBounds.Width;
        int tileHeight = plan.TightPhysicalBounds.Height;
        int rowCount = (int)Math.Ceiling(
            HpFullToEmptyFrames.Length /
            (double)ContactSheetColumns);
        var contactSheet = new Bitmap(
            checked(
                (tileWidth * ContactSheetColumns) +
                (ContactSheetGap * (ContactSheetColumns - 1))),
            checked(
                (tileHeight * rowCount) +
                (ContactSheetGap * (rowCount - 1))),
            PixelFormat.Format32bppPArgb);
        var frames = new List<TransitionFrameEvidence>(
            HpFullToEmptyFrames.Length);
        try
        {
            for (var index = 0;
                 index < HpFullToEmptyFrames.Length;
                 index++)
            {
                int elapsedMilliseconds = 0;
                if (index > 0)
                {
                    elapsedMilliseconds =
                        OneLogicalFrameDelta(index - 1);
                    Assert.True(model.Tick(elapsedMilliseconds));
                }
                Assert.Equal(
                    HpFullToEmptyFrames[index],
                    widget.VisualState.Hp.CurrentVirtualFrame);

                using Bitmap tight = NewTightBitmap(plan);
                PlayerInfoFramePaintResult paint =
                    PaintCurrent(pipeline, widget, plan, tight);
                ValidatePArgb(tight);
                int column = index % ContactSheetColumns;
                int row = index / ContactSheetColumns;
                var cell = new Rectangle(
                    column * (tileWidth + ContactSheetGap),
                    row * (tileHeight + ContactSheetGap),
                    tileWidth,
                    tileHeight);
                CopyBitmap(
                    tight,
                    new Rectangle(0, 0, tileWidth, tileHeight),
                    contactSheet,
                    cell.Location);
                frames.Add(new TransitionFrameEvidence(
                    index,
                    elapsedMilliseconds,
                    widget.VisualState.Hp.CurrentVirtualFrame,
                    widget.VisualState.Mp.CurrentVirtualFrame,
                    Rect(cell),
                    Rect(FindAlphaBounds(tight)),
                    Sha256Bytes(ExtractPArgbBytes(tight)),
                    VisualState(widget.VisualState),
                    PaintResult(paint)));
            }

            Assert.Equal(42, frames.Count);
            Assert.Equal(
                HpFullToEmptyFrames,
                frames.Select(frame => frame.HpVirtualFrame));
            Assert.False(model.WantsAnimationTick);
            ValidatePArgb(contactSheet);
            return new TransitionCapture(
                contactSheet,
                "transitions/hp-full-to-empty-contact-sheet.png",
                frames);
        }
        catch
        {
            contactSheet.Dispose();
            throw;
        }
    }

    private static PlayerInfoFramePaintResult PaintCurrent(
        PlayerInfoRasterPipeline pipeline,
        PlayerInfoWidget widget,
        PlayerInfoRasterPlan expectedPlan,
        Bitmap destination)
    {
        PlayerInfoFramePaintResult? result = null;
        Assert.True(pipeline.TryUseCurrent((batch, currentPlan) =>
        {
            Assert.Same(expectedPlan, currentPlan);
            Assert.Equal(expectedPlan.BatchKey, batch.BatchKey);
            result = widget.Paint(
                destination,
                batch,
                currentPlan);
        }));
        Assert.True(result.HasValue);
        return result.Value;
    }

    private static Bitmap NewTightBitmap(PlayerInfoRasterPlan plan) =>
        new(
            plan.TightPhysicalBounds.Width,
            plan.TightPhysicalBounds.Height,
            PixelFormat.Format32bppPArgb);

    private static Bitmap PlaceTightOnMainViewport(
        Bitmap tight,
        PlayerInfoRasterPlan plan)
    {
        var mainViewport = new Bitmap(
            plan.FlashViewportPhysical.Width,
            plan.FlashViewportPhysical.Height,
            PixelFormat.Format32bppPArgb);
        try
        {
            CopyBitmap(
                tight,
                new Rectangle(0, 0, tight.Width, tight.Height),
                mainViewport,
                new Point(
                    plan.TightPhysicalBounds.Left -
                    plan.FlashViewportPhysical.Left,
                    plan.TightPhysicalBounds.Top -
                    plan.FlashViewportPhysical.Top));
            return mainViewport;
        }
        catch
        {
            mainViewport.Dispose();
            throw;
        }
    }

    private static Bitmap CopyRegion(
        Bitmap source,
        Rectangle sourceBounds)
    {
        Assert.True(
            new Rectangle(0, 0, source.Width, source.Height)
                .Contains(sourceBounds));
        var destination = new Bitmap(
            sourceBounds.Width,
            sourceBounds.Height,
            PixelFormat.Format32bppPArgb);
        try
        {
            CopyBitmap(
                source,
                sourceBounds,
                destination,
                Point.Empty);
            return destination;
        }
        catch
        {
            destination.Dispose();
            throw;
        }
    }

    private static void CopyBitmap(
        Bitmap source,
        Rectangle sourceBounds,
        Bitmap destination,
        Point destinationOrigin)
    {
        Assert.Equal(
            PixelFormat.Format32bppPArgb,
            source.PixelFormat);
        Assert.Equal(
            PixelFormat.Format32bppPArgb,
            destination.PixelFormat);
        Assert.True(
            new Rectangle(0, 0, source.Width, source.Height)
                .Contains(sourceBounds));
        Assert.True(
            new Rectangle(0, 0, destination.Width, destination.Height)
                .Contains(new Rectangle(
                    destinationOrigin,
                    sourceBounds.Size)));

        BitmapData? sourceData = null;
        BitmapData? destinationData = null;
        try
        {
            sourceData = source.LockBits(
                new Rectangle(0, 0, source.Width, source.Height),
                ImageLockMode.ReadOnly,
                PixelFormat.Format32bppPArgb);
            destinationData = destination.LockBits(
                new Rectangle(
                    0,
                    0,
                    destination.Width,
                    destination.Height),
                ImageLockMode.ReadWrite,
                PixelFormat.Format32bppPArgb);
            int rowBytes = checked(sourceBounds.Width * 4);
            Assert.True(sourceData.Stride >= source.Width * 4);
            Assert.True(
                destinationData.Stride >= destination.Width * 4);
            var row = new byte[rowBytes];
            for (var y = 0; y < sourceBounds.Height; y++)
            {
                IntPtr sourceRow = IntPtr.Add(
                    sourceData.Scan0,
                    checked(
                        ((sourceBounds.Y + y) * sourceData.Stride) +
                        (sourceBounds.X * 4)));
                IntPtr destinationRow = IntPtr.Add(
                    destinationData.Scan0,
                    checked(
                        ((destinationOrigin.Y + y) *
                         destinationData.Stride) +
                        (destinationOrigin.X * 4)));
                Marshal.Copy(sourceRow, row, 0, rowBytes);
                Marshal.Copy(row, 0, destinationRow, rowBytes);
            }
        }
        finally
        {
            if (destinationData is not null)
            {
                destination.UnlockBits(destinationData);
            }
            if (sourceData is not null)
            {
                source.UnlockBits(sourceData);
            }
        }
    }

    private static OutputEvidence WriteBitmapOutput(
        string outputRoot,
        string relativePath,
        string kind,
        string viewportId,
        string stateId,
        PlayerInfoRasterPlan plan,
        Bitmap bitmap)
    {
        ValidatePArgb(bitmap);
        byte[] firstPng = EncodePng(bitmap);
        byte[] secondPng = EncodePng(bitmap);
        Assert.Equal(firstPng, secondPng);

        string outputPath = ResolveOwnedOutputPath(
            outputRoot,
            relativePath);
        Directory.CreateDirectory(
            Path.GetDirectoryName(outputPath)!);
        File.WriteAllBytes(outputPath, firstPng);
        byte[] persisted = File.ReadAllBytes(outputPath);
        Assert.Equal(firstPng, persisted);

        return new OutputEvidence(
            relativePath,
            kind,
            viewportId,
            stateId,
            bitmap.Width,
            bitmap.Height,
            "Format32bppPArgb",
            plan.PhysicalScale,
            plan.MonitorDpiScale,
            Rect(plan.FlashViewportPhysical),
            Rect(plan.StagePhysicalBounds),
            Rect(plan.TightPhysicalBounds),
            Rect(FindAlphaBounds(bitmap)),
            Sha256Bytes(ExtractPArgbBytes(bitmap)),
            firstPng.LongLength,
            Sha256Bytes(firstPng));
    }

    private static byte[] EncodePng(Bitmap bitmap)
    {
        using var stream = new MemoryStream();
        bitmap.Save(stream, ImageFormat.Png);
        return stream.ToArray();
    }

    private static byte[] ExtractPArgbBytes(Bitmap bitmap)
    {
        Assert.Equal(
            PixelFormat.Format32bppPArgb,
            bitmap.PixelFormat);
        BitmapData? locked = null;
        try
        {
            locked = bitmap.LockBits(
                new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                ImageLockMode.ReadOnly,
                PixelFormat.Format32bppPArgb);
            int rowBytes = checked(bitmap.Width * 4);
            Assert.True(locked.Stride >= rowBytes);
            var bytes = new byte[
                checked(rowBytes * bitmap.Height)];
            for (var y = 0; y < bitmap.Height; y++)
            {
                Marshal.Copy(
                    IntPtr.Add(
                        locked.Scan0,
                        checked(y * locked.Stride)),
                    bytes,
                    checked(y * rowBytes),
                    rowBytes);
            }
            return bytes;
        }
        finally
        {
            if (locked is not null)
            {
                bitmap.UnlockBits(locked);
            }
        }
    }

    private static void ValidatePArgb(Bitmap bitmap)
    {
        byte[] bytes = ExtractPArgbBytes(bitmap);
        for (var index = 0; index < bytes.Length; index += 4)
        {
            byte alpha = bytes[index + 3];
            Assert.True(
                bytes[index] <= alpha &&
                bytes[index + 1] <= alpha &&
                bytes[index + 2] <= alpha,
                "Format32bppPArgb pixel violated the premultiplied-alpha contract.");
        }
    }

    private static Rectangle FindAlphaBounds(Bitmap bitmap)
    {
        byte[] bytes = ExtractPArgbBytes(bitmap);
        int left = bitmap.Width;
        int top = bitmap.Height;
        var right = -1;
        var bottom = -1;
        for (var y = 0; y < bitmap.Height; y++)
        {
            for (var x = 0; x < bitmap.Width; x++)
            {
                int alphaIndex =
                    checked(((y * bitmap.Width) + x) * 4 + 3);
                if (bytes[alphaIndex] == 0)
                {
                    continue;
                }
                left = Math.Min(left, x);
                top = Math.Min(top, y);
                right = Math.Max(right, x);
                bottom = Math.Max(bottom, y);
            }
        }
        return right < left || bottom < top
            ? Rectangle.Empty
            : Rectangle.FromLTRB(
                left,
                top,
                checked(right + 1),
                checked(bottom + 1));
    }

    private static string ResolveEmptyOutputRoot()
    {
        string? raw = Environment.GetEnvironmentVariable(
            B006VisualCaptureFactAttribute.OutputDirectoryEnvironment);
        Assert.False(
            string.IsNullOrEmpty(raw),
            $"{B006VisualCaptureFactAttribute.OutputDirectoryEnvironment} is required.");
        Assert.Equal(raw!.Trim(), raw);
        Assert.True(
            Path.IsPathFullyQualified(raw),
            $"{B006VisualCaptureFactAttribute.OutputDirectoryEnvironment} must be an absolute path.");

        string outputRoot = Path.GetFullPath(raw);
        Assert.NotEqual(
            Path.GetPathRoot(outputRoot)?.TrimEnd(
                Path.DirectorySeparatorChar,
                Path.AltDirectorySeparatorChar),
            outputRoot.TrimEnd(
                Path.DirectorySeparatorChar,
                Path.AltDirectorySeparatorChar));
        if (Directory.Exists(outputRoot))
        {
            Assert.Empty(
                Directory.EnumerateFileSystemEntries(
                    outputRoot,
                    "*",
                    SearchOption.TopDirectoryOnly));
        }
        else
        {
            Directory.CreateDirectory(outputRoot);
        }
        return outputRoot;
    }

    private static string ResolveOwnedOutputPath(
        string outputRoot,
        string relativePath)
    {
        Assert.False(Path.IsPathRooted(relativePath));
        Assert.DoesNotContain('\\', relativePath);
        Assert.DoesNotContain("..", relativePath);
        string fullPath = Path.GetFullPath(
            Path.Combine(
                outputRoot,
                relativePath.Replace(
                    '/',
                    Path.DirectorySeparatorChar)));
        string relativeBack = Path.GetRelativePath(
            outputRoot,
            fullPath);
        Assert.False(relativeBack.StartsWith(
            ".." + Path.DirectorySeparatorChar,
            StringComparison.Ordinal));
        return fullPath;
    }

    private static string FindProjectRoot()
    {
        var directory = new DirectoryInfo(
            AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(
                    directory.FullName,
                    "global.json")) &&
                File.Exists(Path.Combine(
                    directory.FullName,
                    "launcher",
                    "CRAZYFLASHER7MercenaryEmpire.csproj")))
            {
                return directory.FullName;
            }
            directory = directory.Parent;
        }
        throw new DirectoryNotFoundException(
            "Unable to locate the repository root from the executing test assembly.");
    }

    private static BinaryEvidence CaptureBinary(
        string id,
        Assembly assembly)
    {
        string path = assembly.Location;
        var file = new FileInfo(path);
        Assert.True(file.Exists);
        return new BinaryEvidence(
            id,
            file.Name,
            file.Length,
            Sha256File(path));
    }

    private static BinaryEvidence CaptureBinaryFile(
        string id,
        string outputDirectory,
        string relativeName)
    {
        Assert.False(Path.IsPathRooted(relativeName));
        Assert.DoesNotContain("..", relativeName);
        string path = Path.Combine(
            outputDirectory,
            relativeName.Replace(
                '/',
                Path.DirectorySeparatorChar));
        var file = new FileInfo(path);
        Assert.True(
            file.Exists,
            $"Missing renderer binary closure file: {relativeName}");
        return new BinaryEvidence(
            id,
            relativeName,
            file.Length,
            Sha256File(path));
    }

    private static SourceFileEvidence CaptureSourceFile(
        string projectRoot,
        string relativePath)
    {
        string path = Path.Combine(
            projectRoot,
            relativePath.Replace(
                '/',
                Path.DirectorySeparatorChar));
        var file = new FileInfo(path);
        Assert.True(file.Exists, $"Missing source closure file: {relativePath}");
        return new SourceFileEvidence(
            relativePath,
            file.Length,
            Sha256File(path));
    }

    private static OutputClosureEvidence CreateOutputClosure(
        IReadOnlyList<OutputEvidence> outputs)
    {
        var canonical = new StringBuilder();
        long totalBytes = 0;
        foreach (OutputEvidence output in outputs)
        {
            totalBytes = checked(totalBytes + output.PngBytes);
            canonical
                .Append(output.RelativePath)
                .Append('\0')
                .Append(output.PngBytes.ToString(
                    CultureInfo.InvariantCulture))
                .Append('\0')
                .Append(output.PngSha256)
                .Append('\n');
        }
        return new OutputClosureEvidence(
            outputs.Count,
            totalBytes,
            Sha256Bytes(
                Encoding.UTF8.GetBytes(
                    canonical.ToString())),
            "sorted relativePath + NUL + decimal byte length + NUL + uppercase SHA-256 + LF");
    }

    private static void WriteCanonicalManifest(
        string path,
        CaptureManifest manifest)
    {
        string first = SerializeCanonical(manifest);
        string second = SerializeCanonical(manifest);
        Assert.Equal(first, second);
        byte[] bytes = new UTF8Encoding(
            encoderShouldEmitUTF8Identifier: false)
            .GetBytes(first);
        Assert.False(
            bytes.AsSpan().StartsWith(
                new byte[] { 0xEF, 0xBB, 0xBF }));
        Assert.DoesNotContain('\r', first);
        File.WriteAllBytes(path, bytes);
        Assert.Equal(bytes, File.ReadAllBytes(path));
        using JsonDocument _ = JsonDocument.Parse(bytes);
    }

    private static string SerializeCanonical(
        CaptureManifest manifest)
    {
        string json = JsonSerializer.Serialize(
            manifest,
            new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                WriteIndented = true
            });
        json = json.Replace(
            "\r\n",
            "\n",
            StringComparison.Ordinal);
        Assert.DoesNotContain('\r', json);
        return json + "\n";
    }

    private static void AssertExactOutputClosure(
        string outputRoot,
        IReadOnlyList<string> expectedRelativePaths)
    {
        string[] actual = Directory.EnumerateFiles(
                outputRoot,
                "*",
                SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(outputRoot, path)
                .Replace('\\', '/'))
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToArray();
        Assert.Equal(
            expectedRelativePaths
                .OrderBy(path => path, StringComparer.Ordinal),
            actual);
    }

    private static PlayerInfoVisualStateEvidence VisualState(
        PlayerInfoVisualState state) =>
        new(
            GaugeState(state.Hp),
            GaugeState(state.Mp),
            state.HasRenderableState,
            state.WantsAnimationTick);

    private static GaugeStateEvidence GaugeState(
        PlayerInfoGaugeVisualState state) =>
        new(
            state.GaugeId,
            state.HasRenderableState,
            state.IsInputValid,
            state.ClampedCurrent,
            state.Maximum,
            state.NormalizedRatio,
            state.CurrentVirtualFrame,
            state.TargetVirtualFrame,
            state.CurrentText,
            state.MaximumText,
            state.PercentText,
            state.CombinedText,
            state.Diagnostic.HasValue
                ? new DiagnosticEvidence(
                    state.Diagnostic.Value.Code,
                    state.Diagnostic.Value.GaugeId,
                    state.Diagnostic.Value.Reason)
                : null);

    private static PaintResultEvidence PaintResult(
        PlayerInfoFramePaintResult result) =>
        new(
            result.HpVirtualFrame,
            result.MpVirtualFrame,
            result.MpLeftContourCount,
            result.MpRightContourCount,
            result.MpRimAssetId,
            result.MpPaletteStart);

    private static PlanEvidence Plan(
        ViewportCase viewport,
        PlayerInfoRasterPlan plan) =>
        new(
            viewport.Id,
            Rect(viewport.ContentViewport),
            viewport.MonitorDpiScale,
            plan.PhysicalScale,
            Rect(plan.StagePhysicalBounds),
            Rect(plan.TightPhysicalBounds),
            plan.BatchKey);

    private static RectEvidence Rect(Rectangle rectangle) =>
        new(
            rectangle.X,
            rectangle.Y,
            rectangle.Width,
            rectangle.Height);

    private static string Sha256File(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static string Sha256Bytes(byte[] bytes) =>
        Convert.ToHexString(SHA256.HashData(bytes));

    private static int OneLogicalFrameDelta(int index) =>
        index % 3 == 0 ? 34 : 33;

    private static ViewportCase[] CreateViewportCases() =>
    [
        new(
            "viewport_1024x576_dpi100",
            new Rectangle(0, 0, 1024, 576),
            new Rectangle(0, 0, 1024, 576),
            1.00f,
            1d,
            new Rectangle(0, 512, 1024, 64),
            new Rectangle(0, 474, 282, 81)),
        new(
            "viewport_1600x900_dpi125",
            new Rectangle(0, 0, 1600, 900),
            new Rectangle(0, 0, 1600, 900),
            1.25f,
            1.5625d,
            new Rectangle(0, 800, 1600, 100),
            new Rectangle(0, 741, 440, 126)),
        new(
            "viewport_1920x1080_dpi150",
            new Rectangle(0, 0, 1920, 1080),
            new Rectangle(0, 0, 1920, 1080),
            1.50f,
            1.875d,
            new Rectangle(0, 960, 1920, 120),
            new Rectangle(0, 890, 528, 150)),
        new(
            "host_1280x960_letterbox_content_1280x720_dpi175",
            new Rectangle(0, 0, 1280, 960),
            new Rectangle(0, 120, 1280, 720),
            1.75f,
            1.25d,
            new Rectangle(0, 760, 1280, 80),
            new Rectangle(0, 713, 352, 101))
    ];

    private sealed class RenderedFixture(
        Bitmap mainViewport,
        Bitmap alphaTightCrop,
        PlayerInfoVisualStateEvidence visualState,
        PaintResultEvidence paintResult) : IDisposable
    {
        internal Bitmap MainViewport { get; } = mainViewport;
        internal Bitmap AlphaTightCrop { get; } = alphaTightCrop;
        internal PlayerInfoVisualStateEvidence VisualState { get; } =
            visualState;
        internal PaintResultEvidence PaintResult { get; } = paintResult;

        public void Dispose()
        {
            MainViewport.Dispose();
            AlphaTightCrop.Dispose();
        }
    }

    private sealed record ExpectedCase(
        string CaseId,
        int HpVirtualFrame,
        int MpVirtualFrame);

    private sealed record ViewportCase(
        string Id,
        Rectangle HostViewport,
        Rectangle ContentViewport,
        float MonitorDpiScale,
        double ExpectedPhysicalScale,
        Rectangle ExpectedStageBounds,
        Rectangle ExpectedTightBounds);

    private sealed record RectEvidence(
        int X,
        int Y,
        int Width,
        int Height);

    private sealed record DiagnosticEvidence(
        string Code,
        string GaugeId,
        string Reason);

    private sealed record GaugeStateEvidence(
        string GaugeId,
        bool HasRenderableState,
        bool IsInputValid,
        double ClampedCurrent,
        double Maximum,
        double NormalizedRatio,
        int CurrentVirtualFrame,
        int TargetVirtualFrame,
        string CurrentText,
        string MaximumText,
        string PercentText,
        string? CombinedText,
        DiagnosticEvidence? Diagnostic);

    private sealed record PlayerInfoVisualStateEvidence(
        GaugeStateEvidence Hp,
        GaugeStateEvidence Mp,
        bool HasRenderableState,
        bool WantsAnimationTick);

    private sealed record PaintResultEvidence(
        int HpVirtualFrame,
        int MpVirtualFrame,
        int MpLeftContourCount,
        int MpRightContourCount,
        string MpRimAssetId,
        string MpPaletteStart);

    private sealed record OutputEvidence(
        string RelativePath,
        string Kind,
        string ViewportId,
        string StateId,
        int Width,
        int Height,
        string SourcePixelFormat,
        double PhysicalScale,
        float MonitorDpiScale,
        RectEvidence FlashViewportPhysical,
        RectEvidence StagePhysicalBounds,
        RectEvidence TightPhysicalBounds,
        RectEvidence AlphaBounds,
        string PixelSha256,
        long PngBytes,
        string PngSha256);

    private sealed record CaseCaptureEvidence(
        string CaseId,
        PlayerInfoVisualStateEvidence VisualState,
        PaintResultEvidence PaintResult,
        string MainViewportPng,
        string TightCropPng);

    private sealed record ViewportStateEvidence(
        string StateId,
        string CaseId,
        PlayerInfoVisualStateEvidence VisualState,
        PaintResultEvidence PaintResult,
        string Png);

    private sealed record PlanEvidence(
        string ViewportId,
        RectEvidence ContentViewport,
        float MonitorDpiScale,
        double PhysicalScale,
        RectEvidence StagePhysicalBounds,
        RectEvidence TightPhysicalBounds,
        string BatchKey);

    private sealed record ViewportCaptureEvidence(
        string ViewportId,
        RectEvidence HostViewport,
        PlanEvidence Plan,
        IReadOnlyList<ViewportStateEvidence> States);

    private sealed record TransitionFrameEvidence(
        int TickIndex,
        int ElapsedMilliseconds,
        int HpVirtualFrame,
        int MpVirtualFrame,
        RectEvidence ContactCell,
        RectEvidence AlphaBounds,
        string PixelSha256,
        PlayerInfoVisualStateEvidence VisualState,
        PaintResultEvidence PaintResult);

    private sealed record TransitionCapture(
        Bitmap ContactSheet,
        string ContactSheetPath,
        IReadOnlyList<TransitionFrameEvidence> Frames);

    private sealed record TransitionEvidence(
        string Id,
        int LogicalFramesPerSecond,
        int TransitionTickCount,
        int FrameCountIncludingInitial,
        string ContactSheetPng,
        int ContactSheetColumns,
        int ContactSheetGapPixels,
        IReadOnlyList<TransitionFrameEvidence> Frames);

    private sealed record BinaryEvidence(
        string Id,
        string FileName,
        long Bytes,
        string Sha256);

    private sealed record SourceFileEvidence(
        string RelativePath,
        long Bytes,
        string Sha256);

    private sealed record AssetEvidence(
        string AssetSetId,
        string Revision,
        string ExactManifestSha256,
        int RasterContractVersion,
        string RendererPackage,
        string RendererVersion,
        string SkiaSharpVersion,
        string FeatureSet,
        string ColorType,
        string AlphaType);

    private sealed record LayerOrderEvidence(
        IReadOnlyList<string> CompositeOrder,
        IReadOnlyList<string> MpAssetIds,
        IReadOnlyList<string> HpAssetIds,
        IReadOnlyList<string> RasterLayerOrder);

    private sealed record DeterminismEvidence(
        bool RunSpecificFieldsOmitted,
        bool SameInputPArgbBytesVerified,
        bool SameBitmapPngBytesVerified,
        string ManifestRule,
        string InProcessVerification);

    private sealed record CanvasContractEvidence(
        int LogicalWidth,
        int LogicalHeight,
        string Background,
        string? CompositeBackgroundId,
        string Detail);

    private sealed record OutputClosureEvidence(
        int FileCount,
        long TotalPngBytes,
        string Sha256,
        string CanonicalFormat);

    private sealed record CaptureManifest(
        string Schema,
        int SchemaVersion,
        string Status,
        string Scope,
        CanvasContractEvidence CanvasContract,
        DeterminismEvidence Determinism,
        AssetEvidence Asset,
        IReadOnlyList<BinaryEvidence> Binaries,
        IReadOnlyList<SourceFileEvidence> SourceFiles,
        LayerOrderEvidence LayerOrder,
        PlanEvidence Baseline,
        IReadOnlyList<CaseCaptureEvidence> Cases,
        IReadOnlyList<ViewportCaptureEvidence> ViewportMatrix,
        TransitionEvidence HpFullToEmpty,
        IReadOnlyList<OutputEvidence> Outputs,
        OutputClosureEvidence OutputClosure,
        IReadOnlyList<string> VerifiedContracts,
        IReadOnlyList<string> UnverifiedClaims);
}
