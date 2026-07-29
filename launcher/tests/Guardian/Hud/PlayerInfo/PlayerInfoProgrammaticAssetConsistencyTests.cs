#nullable enable

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoProgrammaticAssetConsistencyTests
{
    private const string MpFillAssetId = "mp.fill";
    private const string MpLeftMaskId = "mp-left-mask";
    private const string MpRightMaskId = "mp-right-mask";
    private const string HpFillAssetId = "hp.fill";
    private static readonly XNamespace SvgNamespace =
        "http://www.w3.org/2000/svg";

    [Fact]
    public void MpFlattenedFill_DualStableGroupMasksAreSelfConsistentWithoutCrossLeak()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoSvgGauge mp = assets.Gauges["mp"];
        PlayerInfoSvgAsset mpFill = FindAsset(assets, MpFillAssetId);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assets,
            new Rectangle(0, 0, 1024, 576),
            monitorDpiScale: 1f);
        using PlayerInfoRasterBatch batch =
            new PlayerInfoSvgRasterizer().Bake(
                plan,
                System.Threading.CancellationToken.None);
        PlayerInfoRasterLayer productionFill = batch.Layers.Single(
            layer => layer.Key.LayerId == MpFillAssetId);
        PlayerInfoRasterLayerPlan fillPlan = FindLayerPlan(plan, MpFillAssetId);

        Assert.Equal("coverage-only", mp.MaskPaintSemantics);
        Assert.Equal(
            new[] { MpLeftMaskId, MpRightMaskId },
            mp.ClipBindings.Select(binding => binding.Id));
        Assert.All(
            mp.ClipBindings,
            binding => Assert.Equal(MpFillAssetId, binding.AssetId));

        IReadOnlyDictionary<string, byte[]> fragments =
            BuildStableGroupFragments(mpFill, mp);
        using SKBitmap leftFragment = Rasterize(
            fragments[MpLeftMaskId],
            fillPlan);
        using SKBitmap rightFragment = Rasterize(
            fragments[MpRightMaskId],
            fillPlan);
        Assert.True(CountOpaqueOrTranslucent(leftFragment) > 0);
        Assert.True(CountOpaqueOrTranslucent(rightFragment) > 0);
        AssertByteIdentical(
            leftFragment,
            productionFill.RequireFragment(MpLeftMaskId),
            "batch-owned MP left fragment");
        AssertByteIdentical(
            rightFragment,
            productionFill.RequireFragment(MpRightMaskId),
            "batch-owned MP right fragment");
        long oneFillBitmapBytes = checked(
            (long)fillPlan.PixelWidth * fillPlan.PixelHeight * 4L);
        Assert.Equal(oneFillBitmapBytes * 3L, productionFill.ByteSize);
        Assert.Equal(
            batch.Layers.Sum(layer => layer.ByteSize),
            batch.ByteSize);

        using var compositor = new PlayerInfoFrameCompositor(assets);
        MethodInfo buildProductionMask = RequirePrivateMethod(
            "BuildMpMask",
            typeof(string),
            typeof(int));
        MethodInfo drawProductionMpFill = RequirePrivateMethod(
            "DrawMpFill",
            typeof(SKCanvas),
            typeof(PlayerInfoRasterLayer),
            typeof(PlayerInfoRasterPlan),
            typeof(SKPath),
            typeof(SKPath));

        int[] virtualFrames = [34, 35, 70, 71, 101];
        foreach (int virtualFrame in virtualFrames)
        {
            using ProductionMaskProbe productionLeft = BuildProductionMask(
                compositor,
                buildProductionMask,
                MpLeftMaskId,
                virtualFrame);
            using ProductionMaskProbe productionRight = BuildProductionMask(
                compositor,
                buildProductionMask,
                MpRightMaskId,
                virtualFrame);
            using OracleMask oracleLeft = BuildManifestMask(
                assets,
                mp,
                MpLeftMaskId,
                virtualFrame);
            using OracleMask oracleRight = BuildManifestMask(
                assets,
                mp,
                MpRightMaskId,
                virtualFrame);

            int expectedRightContours =
                virtualFrame == mp.FrameMap.EmptyVirtualFrame
                    ? 0
                    : virtualFrame <=
                        (mp.TopologyBreak?.LastTwoContourVirtualFrame ??
                         throw new InvalidDataException(
                             "MP topology break is missing."))
                        ? 2
                        : 1;
            Assert.Equal(
                virtualFrame == mp.FrameMap.EmptyVirtualFrame ? 0 : 1,
                productionLeft.ContourCount);
            Assert.Equal(expectedRightContours, productionRight.ContourCount);
            Assert.Equal(productionLeft.ContourCount, oracleLeft.ContourCount);
            Assert.Equal(productionRight.ContourCount, oracleRight.ContourCount);

            if (virtualFrame != mp.FrameMap.EmptyVirtualFrame)
            {
                Assert.True(
                    oracleLeft.Path.Bounds.Right < oracleRight.Path.Bounds.Left,
                    $"MP masks overlap at virtual frame {virtualFrame}: " +
                    $"left={oracleLeft.Path.Bounds}, right={oracleRight.Path.Bounds}.");
            }

            using var emptyLeftMask = new SKPath();
            using var emptyRightMask = new SKPath();
            using SKBitmap productionLeftOnly = RenderProductionMpSides(
                plan,
                drawProductionMpFill,
                productionFill,
                productionLeft.Path,
                emptyRightMask);
            using SKBitmap productionRightOnly = RenderProductionMpSides(
                plan,
                drawProductionMpFill,
                productionFill,
                emptyLeftMask,
                productionRight.Path);
            using SKBitmap productionCombined = RenderProductionMpSides(
                plan,
                drawProductionMpFill,
                productionFill,
                productionLeft.Path,
                productionRight.Path);

            using SKBitmap expectedLeftOnly = RenderOracleMpSides(
                plan,
                fillPlan,
                virtualFrame == mp.FrameMap.EmptyVirtualFrame
                    ? []
                    : [(leftFragment, oracleLeft.Path)]);
            using SKBitmap expectedRightOnly = RenderOracleMpSides(
                plan,
                fillPlan,
                virtualFrame == mp.FrameMap.EmptyVirtualFrame
                    ? []
                    : [(rightFragment, oracleRight.Path)]);
            using SKBitmap expectedCombined = RenderOracleMpSides(
                plan,
                fillPlan,
                virtualFrame == mp.FrameMap.EmptyVirtualFrame
                    ? []
                    :
                    [
                        (leftFragment, oracleLeft.Path),
                        (rightFragment, oracleRight.Path)
                    ]);

            AssertByteIdentical(
                expectedLeftOnly,
                productionLeftOnly,
                $"MP left stable-group fragment at vf{virtualFrame}");
            AssertByteIdentical(
                expectedRightOnly,
                productionRightOnly,
                $"MP right stable-group fragment at vf{virtualFrame}");
            AssertByteIdentical(
                expectedCombined,
                productionCombined,
                $"MP independently clipped stable-group composition at vf{virtualFrame}");

            if (virtualFrame == mp.FrameMap.EmptyVirtualFrame)
            {
                Assert.Equal(0, CountOpaqueOrTranslucent(productionCombined));
            }
            else
            {
                Assert.True(CountOpaqueOrTranslucent(productionLeftOnly) > 0);
                Assert.True(CountOpaqueOrTranslucent(productionRightOnly) > 0);
            }
        }

        batch.Dispose();
        Assert.True(productionFill.IsDisposed);
        Assert.Throws<ObjectDisposedException>(
            () => productionFill.RequireFragment(MpLeftMaskId));
    }

    [Fact]
    public void HpGradient_LocalRByMIsSelfConsistentWithManifestOracleAndRejectsGlobalRotation()
    {
        PlayerInfoSvgAssetSet assets =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
        PlayerInfoSvgGauge hp = assets.Gauges["hp"];
        PlayerInfoSvgAsset hpFill = FindAsset(assets, HpFillAssetId);
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assets,
            new Rectangle(0, 0, 1024, 576),
            monitorDpiScale: 1f);
        PlayerInfoRasterLayerPlan fillPlan = FindLayerPlan(plan, HpFillAssetId);
        using var compositor = new PlayerInfoFrameCompositor(assets);
        MethodInfo drawProductionHpFill = RequirePrivateMethod(
            "DrawHpFill",
            typeof(SKCanvas),
            typeof(PlayerInfoRasterPlan),
            typeof(int));

        PlayerInfoFillTextureRotation rotation =
            hp.FillTextureRotation ??
            throw new InvalidDataException("HP rotation contract is missing.");
        Assert.Equal(HpFillAssetId, rotation.AssetId);
        Assert.Equal(new PlayerInfoSvgPoint(0, 0), rotation.Pivot);
        Assert.Equal("clockwise", rotation.PositiveDirection);
        string gradientId = Assert.Single(rotation.SvgGradientIds);
        string canonicalCoveragePath = ReadCoveragePathData(hpFill.Bytes);

        int[] coloredKeyFrames = [1, 2, 33, 65, 97];
        foreach (int virtualFrame in coloredKeyFrames)
        {
            double degrees =
                (virtualFrame + rotation.SourceFrameOffset) *
                rotation.DegreesPerSourceFrame;
            byte[] oracleSvg = BuildLocalGradientRotationSvg(
                hpFill.Bytes,
                gradientId,
                degrees,
                out Matrix6 sourceMatrix,
                out Matrix6 composedMatrix);

            // This is the exact R×M convention used by the tracked Web harness:
            // the coverage path stays byte-for-byte the same and only the named
            // gradient's local transform changes.
            Assert.Equal(canonicalCoveragePath, ReadCoveragePathData(oracleSvg));
            Assert.Equal(
                ComposeClockwiseRotation(sourceMatrix, degrees),
                composedMatrix);

            using SKBitmap production = RenderProductionHp(
                plan,
                compositor,
                drawProductionHpFill,
                virtualFrame);
            using SKBitmap oracle = RenderHpSvgOracle(
                oracleSvg,
                plan,
                fillPlan,
                hp,
                virtualFrame);

            InteriorDelta delta = MeasureOpaqueInteriorDelta(production, oracle);
            // The vf97 fill sector is intrinsically narrow and leaves only 64
            // fully opaque interior pixels after edge antialiasing. Keep the
            // original 100-pixel guard for broader sectors and a non-degenerate
            // 50-pixel floor only for that frozen narrow case.
            int minimumComparedPixels = virtualFrame == 97 ? 50 : 100;
            Assert.True(
                delta.ComparedPixelCount >= minimumComparedPixels,
                $"HP vf{virtualFrame} had only {delta.ComparedPixelCount} " +
                "fully covered oracle pixels; expected at least " +
                $"{minimumComparedPixels}.");
            Assert.True(
                delta.MaxChannelDelta <= 1,
                $"HP vf{virtualFrame} R×M interior delta was " +
                $"{delta.MaxChannelDelta}, expected <= 1.");
        }

        using (SKBitmap terminal = RenderProductionHp(
                   plan,
                   compositor,
                   drawProductionHpFill,
                   hp.FrameMap.EmptyVirtualFrame))
        {
            Assert.Equal(0, CountOpaqueOrTranslucent(terminal));
        }

        const int discriminatingFrame = 33;
        double discriminatingDegrees =
            (discriminatingFrame + rotation.SourceFrameOffset) *
            rotation.DegreesPerSourceFrame;
        byte[] localSvg = BuildLocalGradientRotationSvg(
            hpFill.Bytes,
            gradientId,
            discriminatingDegrees,
            out _,
            out _);
        byte[] globalSvg = BuildIncorrectGlobalRotationSvg(
            hpFill.Bytes,
            discriminatingDegrees);
        Assert.Equal(canonicalCoveragePath, ReadCoveragePathData(globalSvg));

        using SKBitmap localOracle = RenderHpSvgOracle(
            localSvg,
            plan,
            fillPlan,
            hp,
            discriminatingFrame);
        using SKBitmap globalAlternative = RenderHpSvgOracle(
            globalSvg,
            plan,
            fillPlan,
            hp,
            discriminatingFrame);
        Assert.NotEqual(HashBitmap(localOracle), HashBitmap(globalAlternative));
        Assert.True(
            CountAlphaDifferences(localOracle, globalAlternative) >= 8,
            "The HP oracle no longer discriminates gradient-local R×M from " +
            "rotating the complete fill geometry.");
    }

    private static IReadOnlyDictionary<string, byte[]> BuildStableGroupFragments(
        PlayerInfoSvgAsset fill,
        PlayerInfoSvgGauge gauge)
    {
        string text = new UTF8Encoding(false, true).GetString(fill.Bytes.Span);
        XDocument canonical = XDocument.Parse(text, LoadOptions.PreserveWhitespace);
        XElement fillRoot = canonical
            .Descendants(SvgNamespace + "g")
            .Single(element =>
                string.Equals(
                    (string?)element.Attribute("id"),
                    "mp-fill",
                    StringComparison.Ordinal));
        string[] directGroupIds = fillRoot
            .Elements(SvgNamespace + "g")
            .Select(element =>
                (string?)element.Attribute("id") ??
                throw new InvalidDataException(
                    "Canonical MP fill has an unnamed direct group."))
            .ToArray();
        string[] boundGroupIds = gauge.ClipBindings
            .SelectMany(binding => binding.SvgGroupIds)
            .ToArray();
        Assert.Equal(
            directGroupIds.OrderBy(id => id, StringComparer.Ordinal),
            boundGroupIds.OrderBy(id => id, StringComparer.Ordinal));
        Assert.Equal(
            boundGroupIds.Length,
            boundGroupIds.Distinct(StringComparer.Ordinal).Count());

        var result = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (PlayerInfoClipBinding binding in gauge.ClipBindings)
        {
            var fragment = new XDocument(canonical);
            XElement fragmentRoot = fragment
                .Descendants(SvgNamespace + "g")
                .Single(element =>
                    string.Equals(
                        (string?)element.Attribute("id"),
                        "mp-fill",
                        StringComparison.Ordinal));
            var keep = binding.SvgGroupIds.ToHashSet(StringComparer.Ordinal);
            foreach (XElement child in fragmentRoot
                         .Elements(SvgNamespace + "g")
                         .ToArray())
            {
                string id = (string?)child.Attribute("id") ??
                    throw new InvalidDataException(
                        "Canonical MP fill has an unnamed direct group.");
                if (!keep.Contains(id))
                {
                    child.Remove();
                }
            }
            Assert.Equal(
                binding.SvgGroupIds.OrderBy(id => id, StringComparer.Ordinal),
                fragmentRoot
                    .Elements(SvgNamespace + "g")
                    .Select(element => (string)element.Attribute("id")!)
                    .OrderBy(id => id, StringComparer.Ordinal));
            result.Add(
                binding.Id,
                Encoding.UTF8.GetBytes(
                    fragment.ToString(SaveOptions.DisableFormatting)));
        }
        return result;
    }

    private static OracleMask BuildManifestMask(
        PlayerInfoSvgAssetSet assets,
        PlayerInfoSvgGauge gauge,
        string maskId,
        int virtualFrame)
    {
        int sourceOffset = gauge.FrameMap.SourceFrameOffset ??
            throw new InvalidDataException("MP source-frame offset is missing.");
        int sourceFrame = checked(virtualFrame + sourceOffset);
        var path = new SKPath
        {
            FillType = SKPathFillType.Winding
        };
        if (virtualFrame == gauge.FrameMap.EmptyVirtualFrame)
        {
            return new OracleMask(path, 0);
        }

        PlayerInfoMorphInterval interval = gauge.MorphIntervals.Single(candidate =>
            candidate.MaskId == maskId &&
            sourceFrame >= candidate.SourceStart &&
            sourceFrame <= candidate.SourceEnd);
        double u = (sourceFrame - interval.SourceStart) /
            (double)(interval.SourceEnd - interval.SourceStart);
        foreach (PlayerInfoMorphCorrespondence correspondence in
                 interval.Correspondence)
        {
            for (var index = 0;
                 index < correspondence.AStartAndAnchorsTwips.Count;
                 index++)
            {
                PlayerInfoSvgPoint a =
                    correspondence.AStartAndAnchorsTwips[index];
                PlayerInfoSvgPoint b =
                    correspondence.BStartAndAnchorsTwips[index];
                float x = (float)(
                    (a.X + ((b.X - a.X) * u)) /
                    assets.Units.SourceTwipsPerSvgUnit);
                float y = (float)(
                    (a.Y + ((b.Y - a.Y) * u)) /
                    assets.Units.SourceTwipsPerSvgUnit);
                if (index == 0)
                {
                    path.MoveTo(x, y);
                }
                else
                {
                    path.LineTo(x, y);
                }
            }
            path.Close();
        }
        return new OracleMask(path, interval.Correspondence.Count);
    }

    private static ProductionMaskProbe BuildProductionMask(
        PlayerInfoFrameCompositor compositor,
        MethodInfo method,
        string maskId,
        int virtualFrame)
    {
        object result = method.Invoke(
            compositor,
            [maskId, virtualFrame]) ??
            throw new InvalidOperationException(
                "Production MP mask builder returned null.");
        PropertyInfo pathProperty = result.GetType().GetProperty(
            "Path",
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic) ??
            throw new MissingMemberException(result.GetType().FullName, "Path");
        PropertyInfo countProperty = result.GetType().GetProperty(
            "ContourCount",
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic) ??
            throw new MissingMemberException(
                result.GetType().FullName,
                "ContourCount");
        return new ProductionMaskProbe(
            (SKPath)(pathProperty.GetValue(result) ??
                throw new InvalidOperationException(
                    "Production MP mask path was null.")),
            (int)(countProperty.GetValue(result) ??
                throw new InvalidOperationException(
                    "Production MP contour count was null.")));
    }

    private static SKBitmap RenderProductionMpSides(
        PlayerInfoRasterPlan plan,
        MethodInfo drawMethod,
        PlayerInfoRasterLayer fill,
        SKPath leftMask,
        SKPath rightMask)
    {
        SKBitmap target = NewTarget(plan);
        try
        {
            using var canvas = new SKCanvas(target);
            canvas.Clear(SKColors.Transparent);
            drawMethod.Invoke(
                obj: null,
                [canvas, fill, plan, leftMask, rightMask]);
            canvas.Flush();
            return target;
        }
        catch
        {
            target.Dispose();
            throw;
        }
    }

    private static SKBitmap RenderOracleMpSides(
        PlayerInfoRasterPlan plan,
        PlayerInfoRasterLayerPlan fillPlan,
        IReadOnlyList<(SKBitmap Fragment, SKPath Mask)> sides)
    {
        SKBitmap target = NewTarget(plan);
        try
        {
            using var canvas = new SKCanvas(target);
            canvas.Clear(SKColors.Transparent);
            foreach ((SKBitmap fragment, SKPath mask) in sides)
            {
                DrawBitmapThroughLocalMask(
                    canvas,
                    fragment,
                    fillPlan,
                    plan,
                    mask);
            }
            canvas.Flush();
            return target;
        }
        catch
        {
            target.Dispose();
            throw;
        }
    }

    private static void DrawBitmapThroughLocalMask(
        SKCanvas canvas,
        SKBitmap bitmap,
        PlayerInfoRasterLayerPlan layerPlan,
        PlayerInfoRasterPlan plan,
        SKPath localMask)
    {
        SKRect destination = ToLocalRect(
            layerPlan.PhysicalBounds,
            plan.TightPhysicalBounds);
        using SKPath mappedMask = MapPath(
            localMask,
            destination,
            layerPlan.SourceToBitmap);
        canvas.Save();
        try
        {
            canvas.ClipPath(
                mappedMask,
                SKClipOperation.Intersect,
                antialias: true);
            canvas.DrawBitmap(bitmap, destination);
        }
        finally
        {
            canvas.Restore();
        }
    }

    private static SKBitmap RenderProductionHp(
        PlayerInfoRasterPlan plan,
        PlayerInfoFrameCompositor compositor,
        MethodInfo drawMethod,
        int virtualFrame)
    {
        SKBitmap target = NewTarget(plan);
        try
        {
            using var canvas = new SKCanvas(target);
            canvas.Clear(SKColors.Transparent);
            drawMethod.Invoke(
                compositor,
                [canvas, plan, virtualFrame]);
            canvas.Flush();
            return target;
        }
        catch
        {
            target.Dispose();
            throw;
        }
    }

    private static SKBitmap RenderHpSvgOracle(
        byte[] svg,
        PlayerInfoRasterPlan plan,
        PlayerInfoRasterLayerPlan fillPlan,
        PlayerInfoSvgGauge gauge,
        int virtualFrame)
    {
        using SKBitmap fill = Rasterize(svg, fillPlan);
        SKBitmap target = NewTarget(plan);
        try
        {
            using var canvas = new SKCanvas(target);
            canvas.Clear(SKColors.Transparent);
            double fraction =
                (gauge.FrameMap.EmptyVirtualFrame - virtualFrame) /
                (double)gauge.FrameMap.StepCount;
            if (fraction <= 0)
            {
                return target;
            }
            fraction = Math.Clamp(fraction, 0, 1);
            SKRect destination = ToLocalRect(
                fillPlan.PhysicalBounds,
                plan.TightPhysicalBounds);

            canvas.Save();
            try
            {
                if (fraction < 1)
                {
                    using SKPath localSector = BuildHpSector(gauge, fraction);
                    using SKPath mappedSector = MapPath(
                        localSector,
                        destination,
                        fillPlan.SourceToBitmap);
                    canvas.ClipPath(
                        mappedSector,
                        SKClipOperation.Intersect,
                        antialias: true);
                }
                canvas.DrawBitmap(fill, destination);
            }
            finally
            {
                canvas.Restore();
            }
            canvas.Flush();
            return target;
        }
        catch
        {
            target.Dispose();
            throw;
        }
    }

    private static SKPath BuildHpSector(
        PlayerInfoSvgGauge gauge,
        double fraction)
    {
        PlayerInfoRadialClip clip = gauge.Clip ??
            throw new InvalidDataException("HP radial clip is missing.");
        var path = new SKPath
        {
            FillType = SKPathFillType.Winding
        };
        float radius = (float)clip.Radius;
        path.MoveTo((float)clip.Center.X, (float)clip.Center.Y);
        double startRadians = clip.StartAngleDegrees * Math.PI / 180d;
        path.LineTo(
            (float)(clip.Center.X + (clip.Radius * Math.Cos(startRadians))),
            (float)(clip.Center.Y + (clip.Radius * Math.Sin(startRadians))));
        path.ArcTo(
            new SKRect(
                (float)clip.Center.X - radius,
                (float)clip.Center.Y - radius,
                (float)clip.Center.X + radius,
                (float)clip.Center.Y + radius),
            (float)clip.StartAngleDegrees,
            (float)(-360d * fraction),
            forceMoveTo: false);
        path.Close();
        return path;
    }

    private static byte[] BuildLocalGradientRotationSvg(
        ReadOnlyMemory<byte> canonicalBytes,
        string gradientId,
        double clockwiseDegrees,
        out Matrix6 sourceMatrix,
        out Matrix6 composedMatrix)
    {
        XDocument document = ParseSvg(canonicalBytes);
        XElement gradient = document
            .Descendants()
            .Single(element =>
                (element.Name == SvgNamespace + "radialGradient" ||
                 element.Name == SvgNamespace + "linearGradient") &&
                string.Equals(
                    (string?)element.Attribute("id"),
                    gradientId,
                    StringComparison.Ordinal));
        sourceMatrix = ParseMatrix(
            (string?)gradient.Attribute("gradientTransform"));
        composedMatrix =
            ComposeClockwiseRotation(sourceMatrix, clockwiseDegrees);
        gradient.SetAttributeValue(
            "gradientTransform",
            FormatMatrix(composedMatrix));
        return Encoding.UTF8.GetBytes(
            document.ToString(SaveOptions.DisableFormatting));
    }

    private static byte[] BuildIncorrectGlobalRotationSvg(
        ReadOnlyMemory<byte> canonicalBytes,
        double clockwiseDegrees)
    {
        XDocument document = ParseSvg(canonicalBytes);
        XElement fillRoot = document
            .Descendants(SvgNamespace + "g")
            .Single(element =>
                string.Equals(
                    (string?)element.Attribute("id"),
                    "hp-fill",
                    StringComparison.Ordinal));
        double radians = clockwiseDegrees * Math.PI / 180d;
        double cos = Math.Cos(radians);
        double sin = Math.Sin(radians);
        fillRoot.SetAttributeValue(
            "transform",
            FormatMatrix(new Matrix6(cos, sin, -sin, cos, 0, 0)));
        return Encoding.UTF8.GetBytes(
            document.ToString(SaveOptions.DisableFormatting));
    }

    private static Matrix6 ComposeClockwiseRotation(
        Matrix6 source,
        double clockwiseDegrees)
    {
        double radians = clockwiseDegrees * Math.PI / 180d;
        double cos = Math.Cos(radians);
        double sin = Math.Sin(radians);
        return new Matrix6(
            NormalizeNegativeZero((cos * source.A) - (sin * source.B)),
            NormalizeNegativeZero((sin * source.A) + (cos * source.B)),
            NormalizeNegativeZero((cos * source.C) - (sin * source.D)),
            NormalizeNegativeZero((sin * source.C) + (cos * source.D)),
            NormalizeNegativeZero((cos * source.E) - (sin * source.F)),
            NormalizeNegativeZero((sin * source.E) + (cos * source.F)));
    }

    private static double NormalizeNegativeZero(double value) =>
        value == 0d ? 0d : value;

    private static Matrix6 ParseMatrix(string? value)
    {
        const string prefix = "matrix(";
        if (value is null ||
            !value.StartsWith(prefix, StringComparison.Ordinal) ||
            !value.EndsWith(")", StringComparison.Ordinal))
        {
            throw new InvalidDataException("Expected one SVG matrix transform.");
        }
        double[] values = value[prefix.Length..^1]
            .Split(
                (char[]?)null,
                StringSplitOptions.RemoveEmptyEntries)
            .Select(token => double.Parse(
                token,
                NumberStyles.Float,
                CultureInfo.InvariantCulture))
            .ToArray();
        if (values.Length != 6 || values.Any(value => !double.IsFinite(value)))
        {
            throw new InvalidDataException(
                "SVG matrix must contain six finite values.");
        }
        return new Matrix6(
            values[0],
            values[1],
            values[2],
            values[3],
            values[4],
            values[5]);
    }

    private static string FormatMatrix(Matrix6 matrix) =>
        string.Create(
            CultureInfo.InvariantCulture,
            $"matrix({matrix.A:G17} {matrix.B:G17} {matrix.C:G17} " +
            $"{matrix.D:G17} {matrix.E:G17} {matrix.F:G17})");

    private static string ReadCoveragePathData(ReadOnlyMemory<byte> svgBytes)
    {
        XDocument document = ParseSvg(svgBytes);
        return (string?)document
            .Descendants(SvgNamespace + "path")
            .Single(element =>
                string.Equals(
                    (string?)element.Attribute("id"),
                    "hp-fill-path-0004",
                    StringComparison.Ordinal))
            .Attribute("d") ??
            throw new InvalidDataException("HP coverage path has no d attribute.");
    }

    private static XDocument ParseSvg(ReadOnlyMemory<byte> bytes) =>
        XDocument.Parse(
            new UTF8Encoding(false, true).GetString(bytes.Span),
            LoadOptions.PreserveWhitespace);

    private static SKBitmap Rasterize(
        ReadOnlyMemory<byte> bytes,
        PlayerInfoRasterLayerPlan plan)
    {
        using QualifiedSvg qualified = StrictSvgFacade.Load(bytes);
        return qualified.Rasterize(
            plan.PixelWidth,
            plan.PixelHeight,
            plan.SourceViewBox,
            plan.SourceToBitmap);
    }

    private static SKPath MapPath(
        SKPath source,
        SKRect destination,
        PlayerInfoRasterTransform transform)
    {
        var mapped = new SKPath();
        var matrix = new SKMatrix(
            (float)transform.ScaleX,
            0f,
            destination.Left + (float)transform.TranslateX,
            0f,
            (float)transform.ScaleY,
            destination.Top + (float)transform.TranslateY,
            0f,
            0f,
            1f);
        source.Transform(matrix, mapped);
        return mapped;
    }

    private static SKRect ToLocalRect(Rectangle absolute, Rectangle tight) =>
        new(
            absolute.Left - tight.Left,
            absolute.Top - tight.Top,
            absolute.Right - tight.Left,
            absolute.Bottom - tight.Top);

    private static SKBitmap NewTarget(PlayerInfoRasterPlan plan) =>
        new(new SKImageInfo(
            plan.TightPhysicalBounds.Width,
            plan.TightPhysicalBounds.Height,
            SKColorType.Bgra8888,
            SKAlphaType.Premul));

    private static PlayerInfoSvgAsset FindAsset(
        PlayerInfoSvgAssetSet assets,
        string assetId) =>
        assets.Assets.Single(asset => asset.Id == assetId);

    private static PlayerInfoRasterLayerPlan FindLayerPlan(
        PlayerInfoRasterPlan plan,
        string assetId) =>
        plan.Layers.Single(layer => layer.Key.LayerId == assetId);

    private static MethodInfo RequirePrivateMethod(
        string name,
        params Type[] parameterTypes) =>
        typeof(PlayerInfoFrameCompositor).GetMethod(
            name,
            BindingFlags.Instance | BindingFlags.Static | BindingFlags.NonPublic,
            binder: null,
            types: parameterTypes,
            modifiers: null) ??
        throw new MissingMethodException(
            typeof(PlayerInfoFrameCompositor).FullName,
            name);

    private static void AssertByteIdentical(
        SKBitmap expected,
        SKBitmap actual,
        string label)
    {
        byte[] expectedBytes = ReadBitmapBytes(expected);
        byte[] actualBytes = ReadBitmapBytes(actual);
        Assert.True(
            expectedBytes.AsSpan().SequenceEqual(actualBytes),
            $"{label} was not byte-identical: expected " +
            $"{Convert.ToHexString(SHA256.HashData(expectedBytes))}, actual " +
            $"{Convert.ToHexString(SHA256.HashData(actualBytes))}; " +
            $"different bytes={expectedBytes.Zip(actualBytes).Count(pair => pair.First != pair.Second)}, " +
            $"expected alpha pixels={CountOpaqueOrTranslucent(expected)}, " +
            $"actual alpha pixels={CountOpaqueOrTranslucent(actual)}.");
    }

    private static void AssertByteIdentical(
        SKBitmap expected,
        Bitmap actual,
        string label)
    {
        byte[] expectedBytes = ReadBitmapBytes(expected);
        byte[] actualBytes = ReadBitmapBytes(actual);
        Assert.True(
            expectedBytes.AsSpan().SequenceEqual(actualBytes),
            $"{label} was not byte-identical: expected " +
            $"{Convert.ToHexString(SHA256.HashData(expectedBytes))}, actual " +
            $"{Convert.ToHexString(SHA256.HashData(actualBytes))}.");
    }

    private static InteriorDelta MeasureOpaqueInteriorDelta(
        SKBitmap first,
        SKBitmap second)
    {
        byte[] a = ReadBitmapBytes(first);
        byte[] b = ReadBitmapBytes(second);
        Assert.Equal(a.Length, b.Length);
        var compared = 0;
        var max = 0;
        for (var offset = 0; offset < a.Length; offset += 4)
        {
            if (a[offset + 3] != byte.MaxValue ||
                b[offset + 3] != byte.MaxValue)
            {
                continue;
            }
            compared++;
            for (var channel = 0; channel < 4; channel++)
            {
                max = Math.Max(
                    max,
                    Math.Abs(a[offset + channel] - b[offset + channel]));
            }
        }
        return new InteriorDelta(compared, max);
    }

    private static int CountAlphaDifferences(SKBitmap first, SKBitmap second)
    {
        byte[] a = ReadBitmapBytes(first);
        byte[] b = ReadBitmapBytes(second);
        Assert.Equal(a.Length, b.Length);
        var count = 0;
        for (var offset = 3; offset < a.Length; offset += 4)
        {
            if (a[offset] != b[offset])
            {
                count++;
            }
        }
        return count;
    }

    private static int CountOpaqueOrTranslucent(SKBitmap bitmap)
    {
        byte[] bytes = ReadBitmapBytes(bitmap);
        var count = 0;
        for (var offset = 3; offset < bytes.Length; offset += 4)
        {
            if (bytes[offset] != 0)
            {
                count++;
            }
        }
        return count;
    }

    private static string HashBitmap(SKBitmap bitmap) =>
        Convert.ToHexString(SHA256.HashData(ReadBitmapBytes(bitmap)));

    private static byte[] ReadBitmapBytes(SKBitmap bitmap)
    {
        int rowBytes = checked(bitmap.Width * 4);
        var bytes = new byte[checked(rowBytes * bitmap.Height)];
        for (var y = 0; y < bitmap.Height; y++)
        {
            Marshal.Copy(
                IntPtr.Add(bitmap.GetPixels(), checked(y * bitmap.RowBytes)),
                bytes,
                checked(y * rowBytes),
                rowBytes);
        }
        return bytes;
    }

    private static byte[] ReadBitmapBytes(Bitmap bitmap)
    {
        System.Drawing.Imaging.BitmapData? locked = null;
        try
        {
            locked = bitmap.LockBits(
                new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                System.Drawing.Imaging.ImageLockMode.ReadOnly,
                System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            int rowBytes = checked(bitmap.Width * 4);
            var bytes = new byte[checked(rowBytes * bitmap.Height)];
            for (var y = 0; y < bitmap.Height; y++)
            {
                Marshal.Copy(
                    IntPtr.Add(locked.Scan0, checked(y * locked.Stride)),
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

    private sealed class ProductionMaskProbe(
        SKPath path,
        int contourCount) : IDisposable
    {
        internal SKPath Path { get; } = path;
        internal int ContourCount { get; } = contourCount;
        public void Dispose() => Path.Dispose();
    }

    private sealed class OracleMask(
        SKPath path,
        int contourCount) : IDisposable
    {
        internal SKPath Path { get; } = path;
        internal int ContourCount { get; } = contourCount;
        public void Dispose() => Path.Dispose();
    }

    private readonly record struct Matrix6(
        double A,
        double B,
        double C,
        double D,
        double E,
        double F);

    private readonly record struct InteriorDelta(
        int ComparedPixelCount,
        int MaxChannelDelta);
}
