#nullable enable

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class B006QualificationFactAttribute : FactAttribute
{
    public B006QualificationFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    "CF7_PLAYER_INFO_B006_REPORT_PATH")) ||
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    "CF7_PLAYER_INFO_B006_RUN_ID")) ||
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    "CF7_PLAYER_INFO_B006_PROJECT_ROOT")))
        {
            Skip =
                "B0-06 HWND/ULW qualification is executed only by its dedicated runner.";
        }
    }
}

public sealed class PlayerInfoB006RuntimeQualificationTests
{
    private const string ReportPathEnvironment =
        "CF7_PLAYER_INFO_B006_REPORT_PATH";
    private const string RunIdEnvironment =
        "CF7_PLAYER_INFO_B006_RUN_ID";
    private const string SdkVersionEnvironment =
        "CF7_PLAYER_INFO_B006_SDK_VERSION";
    private const string ProjectRootEnvironment =
        "CF7_PLAYER_INFO_B006_PROJECT_ROOT";
    private const string ExpectedPriorityClassEnvironment =
        "CF7_PLAYER_INFO_B006_EXPECTED_PRIORITY_CLASS";
    private const string ExpectedAffinityMaskEnvironment =
        "CF7_PLAYER_INFO_B006_EXPECTED_AFFINITY_MASK";
    private const string ReportSchema =
        "cf7.player-info-hud.b0-06-runtime-qualification";
    private const string MeasurementKind =
        "actual_sta_hwnd_update_layered_window";
    private const int VisualStepCount = 3_000;
    private const int IdleTickCount = 3_000;
    private const int LifecycleWarmupCycleCount = 100;
    private const int LifecycleWarmupMaxGroupCount = 5;
    private const int LifecycleWarmupRequiredConsecutiveConvergedGroups = 2;
    private const int LifecycleCycleCount = 100;
    private const int LifecycleCheckpointInterval = 10;
    private const int ResourceCheckpointInterval = 250;
    private const int LogicalStepMilliseconds = 34;
    private const int CanonicalRasterLayerCount = 8;
    private const int OwnedRasterFragmentCount = 2;
    private const int RasterParseAndRasterCount = 10;
    private const long RasterByteBudget = 16L * 1024 * 1024;
    private const double SurfaceP95LimitMilliseconds = 4.0;
    private const double CommitP95LimitMilliseconds = 33.0;
    private const double NativeHudCommitRegressionLimitPercent = 10.0;
    private static readonly string[] PerformanceOverrideEnvironmentNames =
    [
        "DOTNET_TieredPGO",
        "COMPlus_TieredPGO",
        "DOTNET_TieredCompilation",
        "COMPlus_TieredCompilation",
        "DOTNET_ReadyToRun",
        "COMPlus_ReadyToRun",
        "DOTNET_TC_QuickJit",
        "COMPlus_TC_QuickJit",
        "DOTNET_TC_QuickJitForLoops",
        "COMPlus_TC_QuickJitForLoops",
        "DOTNET_gcServer",
        "COMPlus_gcServer"
    ];
    private static readonly string[] SourceTraceRelativePaths =
    [
        "launcher/src/Program.cs",
        "launcher/src/Guardian/FlashCoordinateMapper.cs",
        "launcher/src/Guardian/LauncherCommandRouter.cs",
        "launcher/src/Guardian/NativeHudOverlay.cs",
        "launcher/src/Guardian/OverlayBase.cs",
        "launcher/src/Guardian/PanelHostController.cs",
        "launcher/src/Guardian/Hud/AudioHudState.cs",
        "launcher/src/Guardian/Hud/ComboWidget.cs",
        "launcher/src/Guardian/Hud/LayeredWindowCommit.cs",
        "launcher/src/Guardian/Hud/MapHudDataCatalog.cs",
        "launcher/src/Guardian/Hud/NotchWidget.cs",
        "launcher/src/Guardian/Hud/RightContextWidget.cs",
        "launcher/src/Guardian/Hud/RightHudLayout.cs",
        "launcher/src/Guardian/Hud/SafeExitPanelWidget.cs",
        "launcher/src/Guardian/Hud/ToastWidget.cs",
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
        "launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoB006RuntimeQualificationTests.cs",
        "tools/player-info-hud/evidence/b0-06/glyph-atlas-provenance.json",
        "tools/player-info-hud/generate-player-info-glyph-atlas.py",
        "tools/player-info-hud/run-b0-06-runtime-qualification.ps1",
        "flashswf/UI/玩家信息界面.swf"
    ];
    private static readonly string[] ResolutionMetadataNames =
    [
        "Launcher.Tests.deps.json",
        "Launcher.Tests.runtimeconfig.json"
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

    [Fact]
    [Trait("Category", "PlayerInfoB006QualificationContract")]
    public void B0_06_NormalSuiteContract_QualificationOptInIsAbsent()
    {
        Assert.True(
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(ReportPathEnvironment)),
            $"{ReportPathEnvironment} must be absent from the normal suite.");
        Assert.True(
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(RunIdEnvironment)),
            $"{RunIdEnvironment} must be absent from the normal suite.");
        Assert.True(
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(ProjectRootEnvironment)),
            $"{ProjectRootEnvironment} must be absent from the normal suite.");
        Assert.True(
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    ExpectedPriorityClassEnvironment)),
            $"{ExpectedPriorityClassEnvironment} must be absent from the normal suite.");
        Assert.True(
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    ExpectedAffinityMaskEnvironment)),
            $"{ExpectedAffinityMaskEnvironment} must be absent from the normal suite.");
    }

    [Fact]
    [Trait("Category", "PlayerInfoB006QualificationContract")]
    public void B0_06_LifecycleWarmup_RequiresFirstConsecutiveConvergedPair()
    {
        Assert.Null(
            FindFirstLifecycleWarmupConvergedPairEndIndex(
                [false, true]));
        Assert.Equal(
            5,
            FindFirstLifecycleWarmupConvergedPairEndIndex(
                [false, true, false, true, true]));
        Assert.Equal(
            3,
            FindFirstLifecycleWarmupConvergedPairEndIndex(
                [false, true, true]));
        Assert.Null(
            FindFirstLifecycleWarmupConvergedPairEndIndex(
                [false, true, false, true, false]));
    }

    [Fact]
    [Trait("Category", "PlayerInfoB006QualificationContract")]
    public void B0_06_PerformanceEnvironment_RejectsEveryFrozenMutation()
    {
        string[] expectedOverrideNames =
        [
            "DOTNET_TieredPGO",
            "COMPlus_TieredPGO",
            "DOTNET_TieredCompilation",
            "COMPlus_TieredCompilation",
            "DOTNET_ReadyToRun",
            "COMPlus_ReadyToRun",
            "DOTNET_TC_QuickJit",
            "COMPlus_TC_QuickJit",
            "DOTNET_TC_QuickJitForLoops",
            "COMPlus_TC_QuickJitForLoops",
            "DOTNET_gcServer",
            "COMPlus_gcServer"
        ];
        Assert.Equal(
            expectedOverrideNames,
            PerformanceOverrideEnvironmentNames);
        Assert.Equal(
            PerformanceOverrideEnvironmentNames.Length,
            PerformanceOverrideEnvironmentNames
                .Distinct(StringComparer.Ordinal)
                .Count());

        Dictionary<string, string?> overrides =
            PerformanceOverrideEnvironmentNames.ToDictionary(
                name => name,
                _ => (string?)null,
                StringComparer.Ordinal);
        const string affinity = "000000000000000F";
        Assert.True(
            IsPerformanceEnvironmentQualified(
                overrides,
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                serverGc: false));

        foreach (string name in PerformanceOverrideEnvironmentNames)
        {
            overrides[name] = "1";
            Assert.False(
                IsPerformanceEnvironmentQualified(
                    overrides,
                    ProcessPriorityClass.Normal.ToString(),
                    affinity,
                    ProcessPriorityClass.Normal.ToString(),
                    affinity,
                    serverGc: false),
                name);
            overrides[name] = null;
        }

        Assert.False(
            IsPerformanceEnvironmentQualified(
                overrides,
                ProcessPriorityClass.High.ToString(),
                affinity,
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                serverGc: false));
        Assert.False(
            IsPerformanceEnvironmentQualified(
                overrides,
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                ProcessPriorityClass.High.ToString(),
                affinity,
                serverGc: false));
        Assert.False(
            IsPerformanceEnvironmentQualified(
                overrides,
                ProcessPriorityClass.Normal.ToString(),
                "0000000000000003",
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                serverGc: false));
        Assert.False(
            IsPerformanceEnvironmentQualified(
                overrides,
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                ProcessPriorityClass.Normal.ToString(),
                expectedAffinityMask: null,
                serverGc: false));
        Assert.False(
            IsPerformanceEnvironmentQualified(
                overrides,
                ProcessPriorityClass.Normal.ToString(),
                "0000000000000000",
                ProcessPriorityClass.Normal.ToString(),
                "0000000000000000",
                serverGc: false));
        Assert.False(
            IsPerformanceEnvironmentQualified(
                overrides,
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                serverGc: true));

        overrides["unexpected"] = null;
        Assert.False(
            IsPerformanceEnvironmentQualified(
                overrides,
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                ProcessPriorityClass.Normal.ToString(),
                affinity,
                serverGc: false));
    }

    [B006QualificationFact]
    [Trait("Category", "PlayerInfoB006Qualification")]
    public void B0_06_ActualStaHwndAndLayeredWindowQualification()
    {
        string? reportPath =
            Environment.GetEnvironmentVariable(ReportPathEnvironment);
        string? runId =
            Environment.GetEnvironmentVariable(RunIdEnvironment);
        string? projectRoot =
            Environment.GetEnvironmentVariable(ProjectRootEnvironment);
        Assert.False(
            string.IsNullOrWhiteSpace(reportPath),
            $"{ReportPathEnvironment} is required.");
        Assert.False(
            string.IsNullOrWhiteSpace(runId),
            $"{RunIdEnvironment} is required.");
        Assert.False(
            string.IsNullOrWhiteSpace(projectRoot),
            $"{ProjectRootEnvironment} is required.");

        reportPath = Path.GetFullPath(reportPath);
        projectRoot = Path.GetFullPath(projectRoot);
        var reportWritten = false;
        try
        {
            QualificationOutcome outcome = RunOnSta(
                () => ExecuteQualification(runId, projectRoot),
                TimeSpan.FromMinutes(12));
            WriteReport(reportPath, outcome.Report);
            reportWritten = true;
            Assert.True(
                outcome.Failures.Count == 0,
                "B0-06 qualification gates failed: " +
                string.Join("; ", outcome.Failures));
        }
        catch (Exception exception) when (!reportWritten)
        {
            WriteReport(
                reportPath,
                new
                {
                    schema = ReportSchema,
                    schemaVersion = 2,
                    runId,
                    status = "failed",
                    measurementKind = MeasurementKind,
                    gates = Array.Empty<object>(),
                    failures = new[]
                    {
                        "qualification_exception: " +
                        exception.GetType().Name + ": " + exception.Message
                    },
                    failure = new
                    {
                        type = exception.GetType().FullName,
                        exception.Message
                    }
                });
            throw;
        }
    }

    private static QualificationOutcome ExecuteQualification(
        string runId,
        string projectRoot)
    {
        var gates = new List<QualificationGate>();
        var failures = new List<string>();
        Dictionary<string, string?> inheritedPerformanceOverrides =
            PerformanceOverrideEnvironmentNames.ToDictionary(
                name => name,
                name => Environment.GetEnvironmentVariable(name),
                StringComparer.Ordinal);
        string processPriorityClass;
        string processorAffinityMask;
        using (Process currentProcess = Process.GetCurrentProcess())
        {
            processPriorityClass = currentProcess.PriorityClass.ToString();
            processorAffinityMask = FormatAffinityMask(
                currentProcess.ProcessorAffinity);
        }
        string? expectedPriorityClass =
            Environment.GetEnvironmentVariable(
                ExpectedPriorityClassEnvironment);
        string? expectedAffinityMask =
            Environment.GetEnvironmentVariable(
                ExpectedAffinityMaskEnvironment);
        bool serverGc = System.Runtime.GCSettings.IsServerGC;
        bool performanceEnvironmentQualified =
            IsPerformanceEnvironmentQualified(
                inheritedPerformanceOverrides,
                processPriorityClass,
                processorAffinityMask,
                expectedPriorityClass,
                expectedAffinityMask,
                serverGc);
        if (!performanceEnvironmentQualified)
        {
            failures.Add(
                "runtime_performance_environment: actual=" +
                JsonSerializer.Serialize(new
                {
                    inheritedPerformanceOverrides,
                    processPriorityClass,
                    processorAffinityMask,
                    serverGc
                }) +
                " expected=" +
                JsonSerializer.Serialize(new
                {
                    inheritedPerformanceOverrides =
                        PerformanceOverrideEnvironmentNames.ToDictionary(
                            name => name,
                            _ => (string?)null,
                            StringComparer.Ordinal),
                    processPriorityClass =
                        ProcessPriorityClass.Normal.ToString(),
                    processorAffinityMask = expectedAffinityMask,
                    serverGc = false
                }));
        }
        string baseCommitAtExecution =
            RunGit(projectRoot, "rev-parse", "HEAD");
        var splitObserver = new RecordingCommitObserver();
        var nativeHudObserver = new RecordingCommitObserver();
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(
                minimumRaster: false);

        using Form owner = CreateHost(out Panel anchor);
        using var nativeHud = new NativeHudOverlay(owner, anchor);
        nativeHud.SetCommitObserver(nativeHudObserver);

        FrozenProductionWidget[] widgets =
            CreateFrozenProductionWidgets(projectRoot, anchor);
        foreach (FrozenProductionWidget widget in widgets)
        {
            nativeHud.AddWidget(widget);
        }
        Assert.Equal(5, widgets.Length);
        Assert.All(widgets, widget => Assert.True(widget.Visible));
        string[] productionWidgetTypes = widgets
            .Select(widget => widget.ProductionType)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        string[] expectedWidgetTypes =
        [
            typeof(ComboWidget).FullName!,
            typeof(NotchWidget).FullName!,
            typeof(RightContextWidget).FullName!,
            typeof(SafeExitPanelWidget).FullName!,
            typeof(ToastWidget).FullName!
        ];
        Array.Sort(expectedWidgetTypes, StringComparer.Ordinal);
        Assert.Equal(expectedWidgetTypes, productionWidgetTypes);

        Rectangle nativeUnionBefore =
            NativeHudOverlay.ComputeBoundsUnion(widgets, padding: 6) ??
            throw new InvalidOperationException(
                "The all-visible NativeHud qualification union is empty.");
        nativeHud.SetReady();
        Assert.True(
            nativeHudObserver.Results.LastOrDefault()?.Succeeded,
            "Initial real NativeHud UpdateLayeredWindow commit failed.");

        using PlayerInfoSplitSurface surface =
            PlayerInfoSplitSurface.CreateFixture(
                owner,
                anchor,
                "full",
                splitObserver);
        surface.SetReady();
        WaitWithoutMessagePump(
            () => surface.Counters.Pipeline.PublishCount > 0,
            TimeSpan.FromSeconds(20),
            "PlayerInfo background raster publish did not finish.");
        PumpUntil(
            () => surface.Counters.CommitSuccessCount > 0,
            TimeSpan.FromSeconds(20),
            "PlayerInfo initial actual ULW commit did not finish.");
        Assert.True(
            splitObserver.Results.LastOrDefault()?.Succeeded,
            "Initial PlayerInfo UpdateLayeredWindow commit failed.");

        RasterOwnershipObservation rasterOwnership =
            ProbeRasterOwnership(
                assetSet,
                new Rectangle(Point.Empty, anchor.ClientSize),
                surface.DeviceDpi / 96f);

        // Acquire the deterministic qualification clock before changing a
        // target. The production wall-clock timer cannot race the samples
        // after this point.
        Assert.False(surface.AdvanceFixtureForQualification(0));
        var lifecycleWarmups =
            new List<SurfaceLifecycleObservation>(
                LifecycleWarmupMaxGroupCount);
        SurfaceLifecycleObservation lifecycleChurn;
        using (Form lifecycleOwner =
            CreateHost(out Panel lifecycleAnchor))
        {
            // Run complete isomorphic groups until two consecutive groups
            // independently stay within their respective starting handle
            // envelopes. This is a fail-closed process first-use convergence
            // gate, not a retry of the measured sample and not a relaxed
            // positive-growth limit.
            for (var group = 1;
                group <= LifecycleWarmupMaxGroupCount;
                group++)
            {
                SurfaceLifecycleObservation warmup =
                    RunSurfaceLifecycleChurn(
                        lifecycleOwner,
                        lifecycleAnchor);
                Assert.Equal(
                    LifecycleWarmupCycleCount,
                    warmup.Rounds.Length);
                Assert.Equal(
                    Enumerable.Range(1, LifecycleWarmupCycleCount),
                    warmup.Rounds.Select(round => round.Cycle));
                lifecycleWarmups.Add(warmup);
                if (FindFirstLifecycleWarmupConvergedPairEndIndex(
                        lifecycleWarmups.Select(
                            IsLifecycleWarmupConverged).ToArray()) is not null)
                {
                    break;
                }
            }
            // The next group is the acceptance sample only after a consecutive
            // converged pair. If the cap is exhausted it remains a
            // diagnostic-after-cap group, and the explicit warmup Gate fails
            // while preserving full data.
            lifecycleChurn = RunSurfaceLifecycleChurn(
                lifecycleOwner,
                lifecycleAnchor);
        }
        Application.DoEvents();
        var driverState = new SurfaceDriverState("full");
        WarmSurface(surface, driverState, 160);

        // PlayerInfo-hidden phase. The same five real production widget paints
        // and same frozen bounds remain enrolled for both halves of the A/B.
        surface.Suspend();
        int hiddenNativeStart = nativeHudObserver.Count;
        for (var step = 0; step < VisualStepCount; step++)
        {
            widgets[0].AdvanceVisualStep();
            // Match the enabled half's one UI dispatch opportunity and
            // scheduler yield without producing any PlayerInfo work.
            Application.DoEvents();
            Thread.Sleep(1);
        }
        LayeredWindowCommitResult[] hiddenNativeResults =
            nativeHudObserver.Slice(hiddenNativeStart);
        Assert.Equal(VisualStepCount, hiddenNativeResults.Length);

        // Resume and warm any one-time ShowWindow/z-order path before the
        // enabled resource/timing baseline.
        surface.Resume();
        PumpUntil(
            () => surface.Counters.Shown,
            TimeSpan.FromSeconds(10),
            "PlayerInfo surface did not resume.");
        Assert.False(
            surface.ResumePending,
            "A shown surface must have established the resumed raster request.");
        WarmSurface(surface, driverState, 160);
        Application.DoEvents();
        ForceManagedCleanup();

        PlayerInfoSplitSurfaceSnapshot activeStart = surface.Snapshot;
        int enabledNativeStart = nativeHudObserver.Count;
        int enabledSplitObserverStart = splitObserver.Count;
        var requestSamples = new List<double>(VisualStepCount);
        var resourceSamples =
            new List<ResourceCheckpoint>(
                (VisualStepCount / ResourceCheckpointInterval) + 2);
        resourceSamples.Add(
            new ResourceCheckpoint(
                0,
                "active_start",
                CaptureProcessMetrics()));

        for (var step = 1; step <= VisualStepCount; step++)
        {
            // NativeHud commit happens synchronously through the real
            // BoundsOrVisibilityChanged -> RecomputeBounds -> GDI+ Paint ->
            // UpdateLayeredWindow path.
            widgets[0].AdvanceVisualStep();

            long previousCommitCount = surface.Counters.CommitCount;
            long requestStart = Stopwatch.GetTimestamp();
            bool changed = DriveOneSurfaceVisualStep(surface, driverState);
            requestSamples.Add(ElapsedMilliseconds(requestStart));
            Assert.True(changed, $"Visual step {step} did not change state.");
            PumpUntil(
                () => surface.Counters.CommitCount > previousCommitCount,
                TimeSpan.FromSeconds(5),
                $"PlayerInfo visual step {step} did not commit.");
            Assert.Equal(
                previousCommitCount + 1,
                surface.Counters.CommitCount);

            if (step % ResourceCheckpointInterval == 0)
            {
                resourceSamples.Add(
                    new ResourceCheckpoint(
                        step,
                        "active",
                        CaptureProcessMetrics()));
            }
        }

        PlayerInfoSplitSurfaceSnapshot activeEnd = surface.Snapshot;
        LayeredWindowCommitResult[] enabledNativeResults =
            nativeHudObserver.Slice(enabledNativeStart);
        LayeredWindowCommitResult[] enabledSplitObserverResults =
            splitObserver.Slice(enabledSplitObserverStart);
        Assert.Equal(VisualStepCount, enabledNativeResults.Length);
        Assert.Equal(VisualStepCount, enabledSplitObserverResults.Length);
        var expectedSplitCommitGeometry = new CommitGeometry(
            activeEnd.TightPhysicalBounds.Left,
            activeEnd.TightPhysicalBounds.Top,
            activeEnd.TightPhysicalBounds.Width,
            activeEnd.TightPhysicalBounds.Height);
        CommitGeometry[] observedSplitCommitGeometries =
            enabledSplitObserverResults
                .Select(result => new CommitGeometry(
                    result.ScreenX,
                    result.ScreenY,
                    result.Width,
                    result.Height))
                .Distinct()
                .ToArray();

        Rectangle nativeUnionAfter =
            NativeHudOverlay.ComputeBoundsUnion(widgets, padding: 6) ??
            throw new InvalidOperationException(
                "The NativeHud union disappeared during the enabled phase.");

        var idleSettleVisualSteps = 0;
        while (surface.AdvanceFixtureForQualification(
                   LogicalStepMilliseconds))
        {
            idleSettleVisualSteps++;
            Assert.True(
                idleSettleVisualSteps <= 128,
                "PlayerInfo did not settle before the idle qualification.");
            long expected = surface.Counters.CommitCount;
            PumpUntil(
                () => surface.Counters.CommitCount > expected,
                TimeSpan.FromSeconds(5),
                "PlayerInfo pre-idle settle step did not commit.");
            Assert.Equal(
                expected + 1,
                surface.Counters.CommitCount);
        }

        PlayerInfoSplitSurfaceSnapshot idleStart = surface.Snapshot;
        for (var tick = 1; tick <= IdleTickCount; tick++)
        {
            Assert.False(
                surface.AdvanceFixtureForQualification(
                    LogicalStepMilliseconds));
            if (tick % 100 == 0)
            {
                Application.DoEvents();
            }
        }
        Application.DoEvents();
        ForceManagedCleanup();
        PlayerInfoSplitSurfaceSnapshot idleEnd = surface.Snapshot;
        resourceSamples.Add(
            new ResourceCheckpoint(
                VisualStepCount + IdleTickCount,
                "idle_end",
                CaptureProcessMetrics()));

        Task shutdown = surface.BeginShutdown();
        surface.WaitForDrainAsync(TimeSpan.FromSeconds(10))
            .GetAwaiter()
            .GetResult();
        shutdown.GetAwaiter().GetResult();
        Application.DoEvents();
        PlayerInfoSplitSurfaceSnapshot shutdownSnapshot =
            surface.Snapshot;

        SurfaceCounters activeDelta =
            SurfaceCounters.Delta(activeStart, activeEnd);
        SurfaceCounters idleDelta =
            SurfaceCounters.Delta(idleStart, idleEnd);
        double[] surfaceSamples = SliceSamples(
            activeStart.SurfaceMilliseconds.Count,
            activeEnd.SurfaceMilliseconds);
        double[] paintSamples = SliceSamples(
            activeStart.PaintMilliseconds.Count,
            activeEnd.PaintMilliseconds);
        double[] splitCommitSamples = SliceSamples(
            activeStart.CommitMilliseconds.Count,
            activeEnd.CommitMilliseconds);
        double[] splitObservedCommitSamples = enabledSplitObserverResults
            .Select(result => RoundSample(result.ElapsedMilliseconds))
            .ToArray();
        double[] splitUlwOnlySamples = enabledSplitObserverResults
            .Select(result => RoundSample(
                result.UpdateLayeredWindowMilliseconds))
            .ToArray();
        double[] hiddenNativeCommitSamples = hiddenNativeResults
            .Select(result => RoundSample(result.ElapsedMilliseconds))
            .ToArray();
        double[] enabledNativeCommitSamples = enabledNativeResults
            .Select(result => RoundSample(result.ElapsedMilliseconds))
            .ToArray();

        TimingSummary requestSummary = Summarize(requestSamples);
        TimingSummary surfaceSummary = Summarize(surfaceSamples);
        TimingSummary paintSummary = Summarize(paintSamples);
        TimingSummary splitCommitSummary = Summarize(splitCommitSamples);
        TimingSummary splitObservedCommitSummary =
            Summarize(splitObservedCommitSamples);
        TimingSummary splitUlwOnlySummary =
            Summarize(splitUlwOnlySamples);
        TimingSummary hiddenNativeSummary =
            Summarize(hiddenNativeCommitSamples);
        TimingSummary enabledNativeSummary =
            Summarize(enabledNativeCommitSamples);

        double? nativeHudRegressionPercent =
            hiddenNativeSummary.P95 <= 0
                ? null
                : ((enabledNativeSummary.P95 /
                    hiddenNativeSummary.P95) - 1d) * 100d;

        ProcessMetrics resourceStart = resourceSamples[0].Metrics;
        ProcessMetrics resourceEnd = resourceSamples[^1].Metrics;
        ProcessMetrics resourceDelta =
            ProcessMetrics.Delta(resourceStart, resourceEnd);
        HandleTrend handleTrend = AnalyzeHandleTrend(resourceSamples);
        bool[] lifecycleWarmupConvergenceSequence =
            lifecycleWarmups.Select(
                IsLifecycleWarmupConverged).ToArray();
        int? lifecycleWarmupConvergedPairEndGroupIndex =
            FindFirstLifecycleWarmupConvergedPairEndIndex(
                lifecycleWarmupConvergenceSequence);
        bool lifecycleWarmupConverged =
            lifecycleWarmups.Count is >=
                LifecycleWarmupRequiredConsecutiveConvergedGroups and <=
                LifecycleWarmupMaxGroupCount &&
            lifecycleWarmupConvergedPairEndGroupIndex ==
                lifecycleWarmups.Count &&
            lifecycleWarmups.All(warmup =>
                warmup.Rounds.Length ==
                    LifecycleWarmupCycleCount &&
                warmup.OwnerOwnedFormsBaseline == 0 &&
                warmup.OwnerOwnedFormHandlesBaseline.Length == 0);

        string[] expectedFragmentIds =
        [
            "mp-left-mask",
            "mp-right-mask"
        ];
        RasterLayerOwnershipObservation[] fragmentOwners =
            rasterOwnership.Layers
                .Where(layer => layer.FragmentIds.Length != 0)
                .ToArray();
        bool exactFragmentOwnership =
            fragmentOwners.Length == 1 &&
            string.Equals(
                fragmentOwners[0].LayerId,
                "mp.fill",
                StringComparison.Ordinal) &&
            fragmentOwners[0].FragmentIds.SequenceEqual(
                expectedFragmentIds,
                StringComparer.Ordinal);

        AddGate(
            gates,
            "surface_lifecycle_warmup_converged",
            "surface_lifecycle_resources",
            lifecycleWarmupConverged,
            new
            {
                groupsRun = lifecycleWarmups.Count,
                totalCycles =
                    lifecycleWarmups.Count *
                    LifecycleWarmupCycleCount,
                convergedGroups =
                    lifecycleWarmupConvergenceSequence,
                requiredConsecutiveConvergedGroups =
                    LifecycleWarmupRequiredConsecutiveConvergedGroups,
                convergedPairEndGroupIndex =
                    lifecycleWarmupConvergedPairEndGroupIndex
            },
            new
            {
                groupsRunMinimum =
                    LifecycleWarmupRequiredConsecutiveConvergedGroups,
                groupsRunMaximum =
                    LifecycleWarmupMaxGroupCount,
                groupCycleCount =
                    LifecycleWarmupCycleCount,
                requiredConsecutiveConvergedGroups =
                    LifecycleWarmupRequiredConsecutiveConvergedGroups,
                convergedPairEndsAtGroupsRun = true
            },
            "strict_first_consecutive_converged_pair",
            "lifecycle_group",
            "At most five complete excluded groups may establish the process first-use envelope; the first pair of consecutive strictly converged groups must be followed by a new measured 100-cycle group.");
        AddGate(
            gates,
            "surface_lifecycle_cycle_count",
            "surface_lifecycle",
            lifecycleChurn.Rounds.Length == LifecycleCycleCount &&
            lifecycleChurn.Rounds.Select(round => round.Cycle)
                .SequenceEqual(
                    Enumerable.Range(1, LifecycleCycleCount)),
            lifecycleChurn.Rounds.Select(round => round.Cycle).ToArray(),
            Enumerable.Range(1, LifecycleCycleCount).ToArray(),
            "exact_sequence",
            "cycle",
            "The real HWND lifecycle qualification must complete all 100 ordered cycles.");
        AddGate(
            gates,
            "surface_lifecycle_real_publish_and_ulw",
            "surface_lifecycle",
            lifecycleChurn.Rounds.All(round =>
                round.HwndCreated &&
                round.PublishCount == 1 &&
                round.ParseCount == RasterParseAndRasterCount &&
                round.RasterCount == RasterParseAndRasterCount &&
                round.RepaintRequestCount == 1 &&
                round.PaintCount == 1 &&
                round.CommitCount == 1 &&
                round.ObserverCommitCount == 1 &&
                round.ObserverSuccessCount == 1 &&
                round.CommitSuccessCount == 1 &&
                round.CommitFailureCount == 0),
            lifecycleChurn.Rounds.Where(round =>
                    !round.HwndCreated ||
                    round.PublishCount != 1 ||
                    round.ParseCount != RasterParseAndRasterCount ||
                    round.RasterCount != RasterParseAndRasterCount ||
                    round.RepaintRequestCount != 1 ||
                    round.PaintCount != 1 ||
                    round.CommitCount != 1 ||
                    round.ObserverCommitCount != 1 ||
                    round.ObserverSuccessCount != 1 ||
                    round.CommitSuccessCount != 1 ||
                    round.CommitFailureCount != 0)
                .Select(round => round.Cycle)
                .ToArray(),
            Array.Empty<int>(),
            "exact_sequence",
            "failed_cycle",
            "Every deterministic fresh HWND must publish one ten-payload batch and complete exactly one repaint, paint, and successful real ULW transaction.");
        AddGate(
            gates,
            "surface_lifecycle_queued_render_suppressed",
            "surface_lifecycle",
            lifecycleChurn.Rounds.All(round =>
                round.QueuedCaseChanged &&
                round.QueuedRepaintDelta == 1 &&
                round.QueuedPaintDelta == 0 &&
                round.QueuedCommitDelta == 0 &&
                round.PaintDeltaAfterShutdownPump == 0 &&
                round.CommitDeltaAfterShutdownPump == 0 &&
                round.ObserverLateCommitDeltaBeforeDispose == 0),
            lifecycleChurn.Rounds.Where(round =>
                    !round.QueuedCaseChanged ||
                    round.QueuedRepaintDelta != 1 ||
                    round.QueuedPaintDelta != 0 ||
                    round.QueuedCommitDelta != 0 ||
                    round.PaintDeltaAfterShutdownPump != 0 ||
                    round.CommitDeltaAfterShutdownPump != 0 ||
                    round.ObserverLateCommitDeltaBeforeDispose != 0)
                .Select(round => new
                {
                    round.Cycle,
                    round.QueuedCaseChanged,
                    round.QueuedRepaintDelta,
                    round.QueuedPaintDelta,
                    round.QueuedCommitDelta,
                    round.PaintDeltaAfterShutdownPump,
                    round.CommitDeltaAfterShutdownPump,
                    round.ObserverLateCommitDeltaBeforeDispose
                })
                .ToArray(),
            Array.Empty<object>(),
            "exact_sequence",
            "failed_cycle",
            "An opposite fixture queues exactly one repaint; shutdown then suppresses its paint and commit while the HWND remains alive.");
        AddGate(
            gates,
            "surface_lifecycle_shutdown_drained",
            "surface_lifecycle",
            lifecycleChurn.Rounds.All(round =>
                round.Shutdown &&
                round.ActiveWorkersAfterShutdown == 0 &&
                round.CacheBytesAfterShutdown == 0 &&
                round.CacheCountAfterShutdown == 0 &&
                round.DesiredBatchKeyAfterShutdown is null &&
                round.CurrentBatchKeyAfterShutdown is null &&
                round.LastFaultAfterShutdown is null &&
                round.DisposedBatchCount == 1 &&
                round.DisposedLayerCount ==
                    CanonicalRasterLayerCount),
            lifecycleChurn.Rounds.Where(round =>
                    !round.Shutdown ||
                    round.ActiveWorkersAfterShutdown != 0 ||
                    round.CacheBytesAfterShutdown != 0 ||
                    round.CacheCountAfterShutdown != 0 ||
                    round.DesiredBatchKeyAfterShutdown is not null ||
                    round.CurrentBatchKeyAfterShutdown is not null ||
                    round.LastFaultAfterShutdown is not null ||
                    round.DisposedBatchCount != 1 ||
                    round.DisposedLayerCount !=
                        CanonicalRasterLayerCount)
                .Select(round => round.Cycle)
                .ToArray(),
            Array.Empty<int>(),
            "exact_sequence",
            "failed_cycle",
            "Every cycle drains its worker and releases the current batch before Form disposal.");
        AddGate(
            gates,
            "surface_lifecycle_window_destroyed",
            "surface_lifecycle",
            lifecycleChurn.Rounds.All(round =>
                round.HwndCreated &&
                round.IsWindowAfterDrain &&
                !round.IsWindowAfterDispose &&
                round.IsDisposedAfterDispose &&
                !round.IsHandleCreatedAfterDispose),
            lifecycleChurn.Rounds.Where(round =>
                    !round.HwndCreated ||
                    !round.IsWindowAfterDrain ||
                    round.IsWindowAfterDispose ||
                    !round.IsDisposedAfterDispose ||
                    round.IsHandleCreatedAfterDispose)
                .Select(round => new
                {
                    round.Cycle,
                    round.Hwnd,
                    round.HwndCreated,
                    round.IsWindowAfterDrain,
                    round.IsWindowAfterDispose,
                    round.IsDisposedAfterDispose,
                    round.IsHandleCreatedAfterDispose
                })
                .ToArray(),
            Array.Empty<object>(),
            "exact_sequence",
            "leaked_hwnd",
            "The HWND remains valid through drain, then Form disposal must destroy it and clear managed handle state.");
        AddGate(
            gates,
            "surface_lifecycle_owner_forms_restored",
            "surface_lifecycle",
            lifecycleChurn.OwnerOwnedFormsBaseline == 0 &&
            lifecycleChurn.OwnerOwnedFormHandlesBaseline.Length == 0 &&
            lifecycleChurn.Rounds.All(round =>
                round.OwnerOwnedFormsAfterCreate == 1 &&
                round.OwnerContainsCandidateAfterCreate &&
                round.OwnerBaselineSetPreservedAfterCreate &&
                round.OwnerOwnedFormsAfterDrain == 1 &&
                round.OwnerContainsCandidateAfterDrain &&
                round.OwnerBaselineSetPreservedAfterDrain &&
                round.OwnerOwnedFormsAfterDispose ==
                    lifecycleChurn.OwnerOwnedFormsBaseline &&
                round.OwnerBaselineSetRestoredAfterDispose),
            lifecycleChurn.Rounds.Where(round =>
                    round.OwnerOwnedFormsAfterCreate != 1 ||
                    !round.OwnerContainsCandidateAfterCreate ||
                    !round.OwnerBaselineSetPreservedAfterCreate ||
                    round.OwnerOwnedFormsAfterDrain != 1 ||
                    !round.OwnerContainsCandidateAfterDrain ||
                    !round.OwnerBaselineSetPreservedAfterDrain ||
                    round.OwnerOwnedFormsAfterDispose !=
                        lifecycleChurn.OwnerOwnedFormsBaseline ||
                    !round.OwnerBaselineSetRestoredAfterDispose)
                .Select(round => new
                {
                    round.Cycle,
                    round.OwnerOwnedFormsAfterCreate,
                    round.OwnerContainsCandidateAfterCreate,
                    round.OwnerBaselineSetPreservedAfterCreate,
                    round.OwnerOwnedFormsAfterDrain,
                    round.OwnerContainsCandidateAfterDrain,
                    round.OwnerBaselineSetPreservedAfterDrain,
                    round.OwnerOwnedFormsAfterDispose,
                    round.OwnerBaselineSetRestoredAfterDispose
                })
                .ToArray(),
            new
            {
                failedCycles = Array.Empty<int>(),
                ownerOwnedFormsBaseline = 0,
                ownerOwnedFormHandlesBaseline =
                    Array.Empty<string>()
            },
            "exact_sequence",
            "owned_form",
            "A dedicated host starts empty, owns the candidate through drain, and recovers its exact reference set after Dispose.");
        AddGate(
            gates,
            "surface_lifecycle_no_late_commit",
            "surface_lifecycle",
            lifecycleChurn.Rounds.All(round =>
                round.ObserverLateCommitDeltaBeforeDispose == 0 &&
                round.ObserverLateCommitDeltaAfterDispose == 0),
            lifecycleChurn.Rounds.Where(round =>
                    round.ObserverLateCommitDeltaBeforeDispose != 0 ||
                    round.ObserverLateCommitDeltaAfterDispose != 0)
                .Select(round => new
                {
                    round.Cycle,
                    round.ObserverLateCommitDeltaBeforeDispose,
                    round.ObserverLateCommitDeltaAfterDispose
                })
                .ToArray(),
            Array.Empty<object>(),
            "exact_sequence",
            "late_commit",
            "Pumping queued UI work after drain and Dispose must not produce another ULW transaction.");
        AddGate(
            gates,
            "surface_lifecycle_gdi_handles_no_net_growth",
            "surface_lifecycle_resources",
            lifecycleChurn.ResourceDelta.GdiObjects <= 0,
            lifecycleChurn.ResourceDelta.GdiObjects,
            0,
            "less_than_or_equal",
            "handle",
            "Symmetric GC/finalizer-drained endpoints cover all 100 real surface lifecycles.");
        AddGate(
            gates,
            "surface_lifecycle_user_handles_no_net_growth",
            "surface_lifecycle_resources",
            lifecycleChurn.ResourceDelta.UserObjects <= 0,
            lifecycleChurn.ResourceDelta.UserObjects,
            0,
            "less_than_or_equal",
            "handle",
            "USER handles must not grow after 100 owned Form/HWND lifecycles.");
        AddGate(
            gates,
            "surface_lifecycle_process_handles_no_net_growth",
            "surface_lifecycle_resources",
            lifecycleChurn.ResourceDelta.ProcessHandles <= 0,
            lifecycleChurn.ResourceDelta.ProcessHandles,
            0,
            "less_than_or_equal",
            "handle",
            "Process handles must not grow after 100 drained and disposed surfaces.");
        AddGate(
            gates,
            "surface_lifecycle_handle_series_not_positive_linear",
            "surface_lifecycle_resources",
            !lifecycleChurn.HandleTrend.AnyPositiveMonotonicGrowth,
            lifecycleChurn.HandleTrend,
            new
            {
                anyPositiveMonotonicGrowth = false
            },
            "equals",
            "checkpoint_series",
            "Every ten cycles plus symmetric endpoints is inspected for monotonic positive handle growth.");

        AddGate(
            gates,
            "raster_batch_canonical_layer_count",
            "raster_ownership",
            rasterOwnership.CanonicalLayerCount ==
                CanonicalRasterLayerCount,
            rasterOwnership.CanonicalLayerCount,
            CanonicalRasterLayerCount,
            "equals",
            "layer",
            "Stable-group fragments are owned payloads and must not inflate the canonical SVG layer count.");
        AddGate(
            gates,
            "raster_batch_owned_fragment_count",
            "raster_ownership",
            rasterOwnership.OwnedFragmentCount ==
                OwnedRasterFragmentCount,
            rasterOwnership.OwnedFragmentCount,
            OwnedRasterFragmentCount,
            "equals",
            "bitmap",
            "The MP fill layer owns exactly the two compositor clip fragments.");
        AddGate(
            gates,
            "raster_batch_exact_fragment_ids",
            "raster_ownership",
            exactFragmentOwnership,
            fragmentOwners.Select(owner => new
            {
                owner.LayerId,
                owner.FragmentIds
            }).ToArray(),
            new[]
            {
                new
                {
                    LayerId = "mp.fill",
                    FragmentIds = expectedFragmentIds
                }
            },
            "exact_sequence",
            "fragment_id",
            "Only mp.fill may own fragments, in the manifest/compositor identity order.");
        AddGate(
            gates,
            "raster_batch_parse_count",
            "raster_ownership",
            rasterOwnership.ParseCount ==
                RasterParseAndRasterCount,
            rasterOwnership.ParseCount,
            RasterParseAndRasterCount,
            "equals",
            "svg_parse",
            "Eight canonical layers plus two MP stable-group fragments are independently parsed.");
        AddGate(
            gates,
            "raster_batch_raster_count",
            "raster_ownership",
            rasterOwnership.RasterCount ==
                RasterParseAndRasterCount,
            rasterOwnership.RasterCount,
            RasterParseAndRasterCount,
            "equals",
            "bitmap_raster",
            "Every parsed canonical layer or owned fragment is rasterized once.");
        AddGate(
            gates,
            "raster_batch_byte_size",
            "raster_ownership",
            rasterOwnership.BatchByteSize ==
                rasterOwnership.IndependentlyComputedByteSize,
            rasterOwnership.BatchByteSize,
            rasterOwnership.IndependentlyComputedByteSize,
            "equals",
            "byte",
            "The independent calculation includes every canonical and fragment PArgb allocation.");
        AddGate(
            gates,
            "raster_batch_byte_budget",
            "raster_ownership",
            rasterOwnership.BatchByteSize <= RasterByteBudget,
            rasterOwnership.BatchByteSize,
            RasterByteBudget,
            "less_than_or_equal",
            "byte",
            "The full owned batch must fit the production 16 MiB current-plus-inactive cache budget.");
        AddGate(
            gates,
            "raster_batch_owned_payload_contract",
            "raster_ownership",
            rasterOwnership.AllPayloadsMatchKeyAndPArgb &&
            rasterOwnership.AllBitmapReferencesDistinct,
            new
            {
                rasterOwnership.AllPayloadsMatchKeyAndPArgb,
                rasterOwnership.AllBitmapReferencesDistinct
            },
            new
            {
                allPayloadsMatchKeyAndPArgb = true,
                allBitmapReferencesDistinct = true
            },
            "equals",
            "ownership",
            "Fragments must be full-size PArgb payloads with identities distinct from every layer and sibling fragment.");
        AddGate(
            gates,
            "raster_batch_owned_dispose",
            "raster_ownership",
            rasterOwnership.BatchDisposed &&
            rasterOwnership.DisposedLayerCount ==
                CanonicalRasterLayerCount &&
            rasterOwnership.BatchLayerAccessThrowsObjectDisposed &&
            rasterOwnership.LayerBitmapAccessThrowsObjectDisposed &&
            rasterOwnership.FragmentAccessThrowsObjectDisposed,
            new
            {
                rasterOwnership.BatchDisposed,
                rasterOwnership.DisposedLayerCount,
                rasterOwnership.BatchLayerAccessThrowsObjectDisposed,
                rasterOwnership.LayerBitmapAccessThrowsObjectDisposed,
                rasterOwnership.FragmentAccessThrowsObjectDisposed
            },
            new
            {
                batchDisposed = true,
                disposedLayerCount = CanonicalRasterLayerCount,
                batchLayerAccessThrowsObjectDisposed = true,
                layerBitmapAccessThrowsObjectDisposed = true,
                fragmentAccessThrowsObjectDisposed = true
            },
            "equals",
            "ownership",
            "Disposing the batch atomically invalidates all canonical layers and owned fragments.");
        AddGate(
            gates,
            "split_pipeline_active_bake_contract",
            "split_pipeline",
            activeEnd.Pipeline.ParseCount ==
                RasterParseAndRasterCount &&
            activeEnd.Pipeline.RasterCount ==
                RasterParseAndRasterCount &&
            activeEnd.Pipeline.PublishCount == 1 &&
            activeEnd.Pipeline.FaultCount == 0 &&
            activeEnd.Pipeline.ActiveWorkers == 0 &&
            activeEnd.Pipeline.MaxConcurrentWorkers == 1,
            activeEnd.Pipeline,
            new
            {
                parseCount = RasterParseAndRasterCount,
                rasterCount = RasterParseAndRasterCount,
                publishCount = 1,
                faultCount = 0,
                activeWorkers = 0,
                maxConcurrentWorkers = 1
            },
            "contains",
            "pipeline_counter",
            "The real split surface publishes one ten-payload bake with a drained single worker.");
        AddGate(
            gates,
            "split_pipeline_active_cache_contract",
            "split_pipeline",
            activeEnd.Pipeline.CacheBytes ==
                rasterOwnership.BatchByteSize &&
            activeEnd.Pipeline.CacheBytes <= RasterByteBudget &&
            activeEnd.Pipeline.CacheCount == 1 &&
            !string.IsNullOrEmpty(
                activeEnd.Pipeline.CurrentBatchKey) &&
            string.Equals(
                activeEnd.Pipeline.CurrentBatchKey,
                activeEnd.Pipeline.DesiredBatchKey,
                StringComparison.Ordinal),
            new
            {
                activeEnd.Pipeline.CacheBytes,
                activeEnd.Pipeline.CacheCount,
                activeEnd.Pipeline.DesiredBatchKey,
                activeEnd.Pipeline.CurrentBatchKey
            },
            new
            {
                cacheBytes = rasterOwnership.BatchByteSize,
                maximumCacheBytes = RasterByteBudget,
                cacheCount = 1,
                desiredEqualsCurrent = true
            },
            "contains",
            "cache",
            "The real surface accounts for its current batch, including both owned MP fragments, under the same byte budget.");
        AddGate(
            gates,
            "split_pipeline_shutdown_drained",
            "split_pipeline",
            shutdownSnapshot.Shutdown &&
            shutdownSnapshot.Pipeline.ActiveWorkers == 0 &&
            shutdownSnapshot.Pipeline.CacheBytes == 0 &&
            shutdownSnapshot.Pipeline.CacheCount == 0 &&
            shutdownSnapshot.Pipeline.DesiredBatchKey is null &&
            shutdownSnapshot.Pipeline.CurrentBatchKey is null &&
            shutdownSnapshot.Pipeline.LastFault is null,
            shutdownSnapshot.Pipeline,
            new
            {
                shutdown = true,
                activeWorkers = 0,
                cacheBytes = 0,
                cacheCount = 0,
                desiredBatchKey = (string?)null,
                currentBatchKey = (string?)null,
                lastFault = (string?)null
            },
            "contains",
            "pipeline_state",
            "Shutdown must drain workers and remove all current/cache ownership before qualification returns.");
        AddGate(
            gates,
            "split_pipeline_shutdown_owned_dispose",
            "split_pipeline",
            shutdownSnapshot.Pipeline.ParseCount ==
                RasterParseAndRasterCount &&
            shutdownSnapshot.Pipeline.RasterCount ==
                RasterParseAndRasterCount &&
            shutdownSnapshot.Pipeline.DisposedBatchCount == 1 &&
            shutdownSnapshot.Pipeline.DisposedLayerCount ==
                CanonicalRasterLayerCount,
            new
            {
                shutdownSnapshot.Pipeline.ParseCount,
                shutdownSnapshot.Pipeline.RasterCount,
                shutdownSnapshot.Pipeline.DisposedBatchCount,
                shutdownSnapshot.Pipeline.DisposedLayerCount
            },
            new
            {
                parseCount = RasterParseAndRasterCount,
                rasterCount = RasterParseAndRasterCount,
                disposedBatchCount = 1,
                disposedLayerCount = CanonicalRasterLayerCount
            },
            "equals",
            "ownership",
            "Pipeline disposal counts canonical layers once; their two fragment payloads remain layer-owned.");

        AddGate(
            gates,
            "native_hud_all_production_widgets_visible",
            "native_hud_contract",
            productionWidgetTypes.SequenceEqual(
                expectedWidgetTypes,
                StringComparer.Ordinal) &&
            widgets.All(widget => widget.Visible),
            productionWidgetTypes,
            expectedWidgetTypes,
            "exact_sequence",
            "type",
            "All five currently registered production widget implementations are painted with frozen animation clocks.");
        AddGate(
            gates,
            "native_hud_union_unchanged",
            "native_hud_ab",
            nativeUnionBefore == nativeUnionAfter,
            Rect(nativeUnionAfter),
            Rect(nativeUnionBefore),
            "equals",
            "physical_pixel",
            "The independent PlayerInfo surface must not enter or widen NativeHud's union.");
        AddGate(
            gates,
            "native_hud_hidden_commit_count",
            "native_hud_ab",
            hiddenNativeResults.Length == VisualStepCount,
            hiddenNativeResults.Length,
            VisualStepCount,
            "equals",
            "commit",
            "PlayerInfo-hidden half uses one actual NativeHud ULW commit per deterministic step.");
        AddGate(
            gates,
            "native_hud_enabled_commit_count",
            "native_hud_ab",
            enabledNativeResults.Length == VisualStepCount,
            enabledNativeResults.Length,
            VisualStepCount,
            "equals",
            "commit",
            "PlayerInfo-enabled half preserves the same NativeHud commit count.");
        AddGate(
            gates,
            "native_hud_all_commits_succeeded",
            "native_hud_ab",
            hiddenNativeResults.Concat(enabledNativeResults)
                .All(result => result.Succeeded),
            hiddenNativeResults.Concat(enabledNativeResults)
                .Count(result => result.Succeeded),
            VisualStepCount * 2,
            "equals",
            "commit",
            "Every NativeHud sample is a successful real UpdateLayeredWindow call.");
        AddGate(
            gates,
            "native_hud_commit_dimensions_match_union",
            "native_hud_ab",
            hiddenNativeResults.Concat(enabledNativeResults).All(
                result =>
                    result.Width == nativeUnionBefore.Width &&
                    result.Height == nativeUnionBefore.Height),
            hiddenNativeResults.Concat(enabledNativeResults)
                .Select(result => new[] { result.Width, result.Height })
                .Distinct(IntArrayComparer.Instance)
                .ToArray(),
            new[] { new[] { nativeUnionBefore.Width, nativeUnionBefore.Height } },
            "exact_set",
            "physical_pixel",
            "No hidden PlayerInfo geometry is bridged into the NativeHud bitmap.");
        bool nativeRegressionPassed =
            nativeHudRegressionPercent is null ||
            nativeHudRegressionPercent.Value <=
                NativeHudCommitRegressionLimitPercent;
        AddGate(
            gates,
            "native_hud_commit_p95_regression",
            "native_hud_ab",
            nativeRegressionPassed,
            nativeHudRegressionPercent,
            NativeHudCommitRegressionLimitPercent,
            nativeHudRegressionPercent is null
                ? "absolute_only_zero_baseline"
                : "less_than_or_equal",
            "percent",
            "The relative gate is omitted only when the hidden-side p95 denominator is zero.");

        AddGate(
            gates,
            "split_visual_step_count",
            "split_active",
            driverState.VisualSteps == VisualStepCount,
            driverState.VisualSteps,
            VisualStepCount,
            "equals",
            "visual_step",
            "Target transitions and easing ticks are both counted only when they change the rendered state.");
        AddGate(
            gates,
            "split_repaint_count",
            "split_active",
            activeDelta.RepaintRequestCount == VisualStepCount,
            activeDelta.RepaintRequestCount,
            VisualStepCount,
            "equals",
            "repaint_request",
            "Each visible state step schedules at most and exactly one repaint in this qualification workload.");
        AddGate(
            gates,
            "split_paint_count",
            "split_active",
            activeDelta.PaintCount == VisualStepCount,
            activeDelta.PaintCount,
            VisualStepCount,
            "equals",
            "paint",
            "Each visible state step produces exactly one compositor paint.");
        AddGate(
            gates,
            "split_commit_count",
            "split_active",
            activeDelta.CommitCount == VisualStepCount,
            activeDelta.CommitCount,
            VisualStepCount,
            "equals",
            "commit",
            "Each visible state step produces exactly one real layered-window commit.");
        AddGate(
            gates,
            "split_commit_success_count",
            "split_active",
            activeDelta.CommitSuccessCount == VisualStepCount &&
            activeDelta.CommitFailureCount == 0 &&
            enabledSplitObserverResults.All(result => result.Succeeded),
            new
            {
                activeDelta.CommitSuccessCount,
                activeDelta.CommitFailureCount,
                observerSuccess = enabledSplitObserverResults.Count(
                    result => result.Succeeded)
            },
            new
            {
                commitSuccessCount = VisualStepCount,
                commitFailureCount = 0,
                observerSuccess = VisualStepCount
            },
            "equals",
            "commit",
            "Snapshot and observer independently agree that every actual commit succeeded.");
        AddGate(
            gates,
            "split_commit_geometry_matches_tight",
            "split_active",
            observedSplitCommitGeometries.Length == 1 &&
            observedSplitCommitGeometries[0] ==
                expectedSplitCommitGeometry,
            observedSplitCommitGeometries,
            new[] { expectedSplitCommitGeometry },
            "equals",
            "physical_pixel_rectangle",
            "Every actual split-surface ULW commit must use the main-viewport-clipped tight bounds, including the HP pixels above the child authoring stage.");
        AddGate(
            gates,
            "split_sample_counts",
            "split_active",
            surfaceSamples.Length == VisualStepCount &&
            paintSamples.Length == VisualStepCount &&
            splitCommitSamples.Length == VisualStepCount &&
            splitObservedCommitSamples.Length == VisualStepCount,
            new
            {
                surface = surfaceSamples.Length,
                paint = paintSamples.Length,
                commit = splitCommitSamples.Length,
                observer = splitObservedCommitSamples.Length
            },
            new
            {
                surface = VisualStepCount,
                paint = VisualStepCount,
                commit = VisualStepCount,
                observer = VisualStepCount
            },
            "equals",
            "sample",
            "No percentile may be computed from a diluted or incomplete sample set.");
        AddGate(
            gates,
            "split_surface_p95",
            "split_active",
            surfaceSummary.P95 <= SurfaceP95LimitMilliseconds,
            surfaceSummary.P95,
            SurfaceP95LimitMilliseconds,
            "less_than_or_equal",
            "ms",
            "Measured on the STA UI thread from render transaction entry through paint, actual commit, z-order, and show.");
        AddGate(
            gates,
            "split_actual_commit_p95",
            "split_active",
            splitObservedCommitSummary.P95 <
                CommitP95LimitMilliseconds,
            splitObservedCommitSummary.P95,
            CommitP95LimitMilliseconds,
            "less_than",
            "ms",
            "LayeredWindowCommitResult measures the actual prepared-memory-DC UpdateLayeredWindow transaction; reusable top-down PArgb DIB/memory-DC setup and cleanup are amortized across frames and remain covered by lifecycle resource gates.");

        AddGate(
            gates,
            "split_idle_repaint_zero",
            "split_idle",
            idleDelta.RepaintRequestCount == 0,
            idleDelta.RepaintRequestCount,
            0,
            "equals",
            "repaint_request",
            "3000 deterministic idle ticks must not request paint.");
        AddGate(
            gates,
            "split_idle_paint_zero",
            "split_idle",
            idleDelta.PaintCount == 0,
            idleDelta.PaintCount,
            0,
            "equals",
            "paint",
            "3000 deterministic idle ticks must not paint.");
        AddGate(
            gates,
            "split_idle_commit_zero",
            "split_idle",
            idleDelta.CommitCount == 0,
            idleDelta.CommitCount,
            0,
            "equals",
            "commit",
            "3000 deterministic idle ticks must not call UpdateLayeredWindow.");

        AddGate(
            gates,
            "gdi_handles_no_net_growth",
            "resource_stability",
            resourceDelta.GdiObjects <= 0,
            resourceDelta.GdiObjects,
            0,
            "less_than_or_equal",
            "handle",
            "Endpoint is captured after all HWND, fonts, bitmaps, and native renderer warmups.");
        AddGate(
            gates,
            "user_handles_no_net_growth",
            "resource_stability",
            resourceDelta.UserObjects <= 0,
            resourceDelta.UserObjects,
            0,
            "less_than_or_equal",
            "handle",
            "USER objects must not grow across active+idle qualification.");
        AddGate(
            gates,
            "process_handles_no_net_growth",
            "resource_stability",
            resourceDelta.ProcessHandles <= 0,
            resourceDelta.ProcessHandles,
            0,
            "less_than_or_equal",
            "handle",
            "Process handles must not grow after all one-time qualification setup.");
        AddGate(
            gates,
            "handle_series_not_positive_linear",
            "resource_stability",
            !handleTrend.AnyPositiveMonotonicGrowth,
            handleTrend,
            new
            {
                anyPositiveMonotonicGrowth = false
            },
            "equals",
            "checkpoint_series",
            "Every 250 active steps plus the idle endpoint is inspected; an always-nondecreasing positive endpoint series fails.");

        foreach (QualificationGate gate in gates.Where(gate => !gate.Passed))
        {
            failures.Add(
                $"{gate.Id}: actual={JsonSerializer.Serialize(gate.Actual)} " +
                $"expected={JsonSerializer.Serialize(gate.Expected)}");
        }

        ProcessMetrics processBefore = resourceSamples[0].Metrics;
        ProcessMetrics processAfter = resourceSamples[^1].Metrics;
        string testAssemblyPath =
            typeof(PlayerInfoB006RuntimeQualificationTests)
                .Assembly.Location;
        string coreAssemblyPath =
            typeof(PlayerInfoSplitSurface).Assembly.Location;
        string testOutputDirectory =
            Path.GetDirectoryName(testAssemblyPath) ??
            throw new InvalidOperationException(
                "Qualification test assembly has no output directory.");
        FileIdentityObservation[] projectAssemblies =
            CaptureFileIdentityClosure(
                [coreAssemblyPath, testAssemblyPath],
                projectRoot);
        FileIdentityObservation[] resolutionMetadata =
            CaptureFileIdentityClosure(
                ResolutionMetadataNames.Select(
                    name => Path.Combine(
                        testOutputDirectory,
                        name)),
                projectRoot);
        FileIdentityObservation[] rendererBinaries =
            CaptureFileIdentityClosure(
                RendererBinaryRelativeNames.Select(
                    name => Path.Combine(
                        testOutputDirectory,
                        name.Replace(
                            '/',
                            Path.DirectorySeparatorChar))),
                projectRoot);
        SourceTraceIdentityObservation[] sourceTraceClosure =
            CaptureSourceTraceClosure(
                SourceTraceRelativePaths,
                projectRoot);
        string assetSourceDirectory = Path.Combine(
            projectRoot,
            "launcher",
            "src",
            "Guardian",
            "Hud",
            "PlayerInfo",
            "Assets");
        FileIdentityObservation manifestSource =
            CaptureFileIdentity(
                Path.Combine(
                    assetSourceDirectory,
                    "player-info.manifest.json"),
                projectRoot);
        AssetSourceIdentityObservation[] assetSources =
            assetSet.Assets
                .OrderBy(
                    asset => asset.RelativePath,
                    StringComparer.Ordinal)
                .Select(asset =>
                    new AssetSourceIdentityObservation(
                        asset.Id,
                        asset.RelativePath,
                        asset.Bytes.Length,
                        asset.Sha256,
                        CaptureFileIdentity(
                            Path.Combine(
                                assetSourceDirectory,
                                asset.RelativePath.Replace(
                                    '/',
                                    Path.DirectorySeparatorChar)),
                            projectRoot)))
                .ToArray();

        object report = new
        {
            schema = ReportSchema,
            schemaVersion = 2,
            runId,
            status = failures.Count == 0 ? "passed" : "failed",
            measurementKind = MeasurementKind,
            generatedAtUtc = DateTime.UtcNow.ToString(
                "O",
                CultureInfo.InvariantCulture),
            qualification = new
            {
                visualSteps = VisualStepCount,
                idleTicks = IdleTickCount,
                lifecycleWarmupCycles =
                    lifecycleWarmups.Count *
                    LifecycleWarmupCycleCount,
                lifecycleWarmupCycleCountPerGroup =
                    LifecycleWarmupCycleCount,
                lifecycleWarmupMaxGroups =
                    LifecycleWarmupMaxGroupCount,
                lifecycleWarmupRequiredConsecutiveConvergedGroups =
                    LifecycleWarmupRequiredConsecutiveConvergedGroups,
                lifecycleCycles = LifecycleCycleCount,
                lifecycleCheckpointInterval =
                    LifecycleCheckpointInterval,
                logicalStepMilliseconds = LogicalStepMilliseconds,
                quantileMethod = "nearest_rank",
                surfaceP95LimitMilliseconds =
                    SurfaceP95LimitMilliseconds,
                commitP95LimitMilliseconds =
                    CommitP95LimitMilliseconds,
                nativeHudCommitRegressionLimitPercent =
                    NativeHudCommitRegressionLimitPercent,
                fixtureOnly = true,
                realUiDataConnected = false,
                oldFlashHudMutationAttempted = false,
                oldFlashHudVisibilityObserved = false,
                nativeHudRegistration = false,
                qualificationClock =
                    "PlayerInfoSplitSurface.AdvanceFixtureForQualification",
                resourceEndpointPreparation =
                    "symmetric Application.DoEvents + full GC/finalizer drain before active_start and idle_end",
                lifecycleResourceEndpointPreparation =
                    "up to five full 100-cycle isomorphic lifecycle groups until two consecutive groups independently satisfy strict checkpoint-envelope convergence, then symmetric Application.DoEvents + full GC/finalizer drain before a new measured lifecycle_start and lifecycle_end"
            },
            sourceIdentity = new
            {
                baseCommitAtExecution,
                commitBindingSemantics =
                    "pre-evidence-commit base only; containing commit is verified externally from the report blob and sourceTraceClosure gitBlobOid values",
                sdkVersion = Environment.GetEnvironmentVariable(
                    SdkVersionEnvironment) ?? string.Empty,
                projectAssemblies,
                rendererResolutionClosure = new
                {
                    resolutionMetadata,
                    rendererBinaries
                },
                sourceTraceClosure,
                exactClosureScope =
                    "project Core/Test assemblies, declared renderer resolution files, embedded PlayerInfo assets, and exact B0 source trace",
                environmentBoundary = new
                {
                    includedInExactBinaryClosure = false,
                    components = new[]
                    {
                        "Windows OS, user32, gdi32, and DWM implementation",
                        "Microsoft.NETCore.App shared framework"
                    },
                    meaning =
                        "observed execution environment; not byte-bound by this report"
                }
            },
            runtime = new
            {
                RuntimeInformation.FrameworkDescription,
                RuntimeInformation.RuntimeIdentifier,
                RuntimeInformation.ProcessArchitecture,
                environmentVersion = Environment.Version.ToString(),
                qualificationSdkVersion =
                    Environment.GetEnvironmentVariable(
                        SdkVersionEnvironment) ?? string.Empty,
                is64BitProcess = Environment.Is64BitProcess,
                serverGc,
                performanceEnvironmentQualified,
                performanceEnvironment = new
                {
                    inheritedOverrides =
                        inheritedPerformanceOverrides,
                    processPriorityClass,
                    processorAffinityMask,
                    expectedProcessPriorityClass =
                        expectedPriorityClass,
                    expectedProcessorAffinityMask =
                        expectedAffinityMask
                }
            },
            machine = new
            {
                os = Environment.OSVersion.VersionString,
                framework = RuntimeInformation.FrameworkDescription,
                processArchitecture =
                    RuntimeInformation.ProcessArchitecture.ToString(),
                processorCount = Environment.ProcessorCount,
                systemDpi = GetDpiForSystem(),
                surfaceDeviceDpi = surface.DeviceDpi,
                stopwatchFrequency = Stopwatch.Frequency,
                staThread = Thread.CurrentThread.GetApartmentState()
                    .ToString()
            },
            assets = new
            {
                assetSet.AssetSetId,
                assetSetRevision = assetSet.Revision,
                assetSet.ExactManifestSha256,
                rendererPackage = assetSet.RendererIdentity.Package,
                rendererVersion = assetSet.RendererIdentity.Version,
                skiaSharpVersion =
                    assetSet.RendererIdentity.SkiaSharpVersion,
                assetCount = assetSet.Assets.Count,
                revisionAlgorithm =
                    "sha256(sorted UTF-8 relative path + NUL + exact file bytes + NUL)",
                manifestSource,
                assetSources
            },
            rasterOwnership = new
            {
                rasterOwnership.CanonicalLayerCount,
                rasterOwnership.OwnedFragmentCount,
                rasterOwnership.ParseCount,
                rasterOwnership.RasterCount,
                rasterOwnership.BatchByteSize,
                rasterOwnership.IndependentlyComputedByteSize,
                byteBudget = RasterByteBudget,
                rasterOwnership.AllPayloadsMatchKeyAndPArgb,
                rasterOwnership.AllBitmapReferencesDistinct,
                rasterOwnership.BatchDisposed,
                rasterOwnership.DisposedLayerCount,
                rasterOwnership.BatchLayerAccessThrowsObjectDisposed,
                rasterOwnership.LayerBitmapAccessThrowsObjectDisposed,
                rasterOwnership.FragmentAccessThrowsObjectDisposed,
                rasterOwnership.Layers
            },
            surfaceLifecycle = new
            {
                warmup = new
                {
                    groupCycleCount =
                        LifecycleWarmupCycleCount,
                    maxGroups =
                        LifecycleWarmupMaxGroupCount,
                    requiredConsecutiveConvergedGroups =
                        LifecycleWarmupRequiredConsecutiveConvergedGroups,
                    groupsRun = lifecycleWarmups.Count,
                    totalCycles =
                        lifecycleWarmups.Count *
                        LifecycleWarmupCycleCount,
                    checkpointInterval =
                        LifecycleCheckpointInterval,
                    converged =
                        lifecycleWarmupConverged,
                    convergedPairEndGroupIndex =
                        lifecycleWarmupConverged
                            ? lifecycleWarmups.Count
                            : (int?)null,
                    acceptanceMeasurementImmediatelyFollowsConvergedPair =
                        lifecycleWarmupConverged,
                    convergenceRule =
                        "first pair of consecutive complete groups where each group's GDI, USER, and process handle checkpoints never exceed that group's start, endpoint deltas are <= 0, and positive-monotonic trends are all false",
                    groups = lifecycleWarmups.Select(
                        (warmup, index) => new
                        {
                            index = index + 1,
                            cycles =
                                LifecycleWarmupCycleCount,
                            roundsCompleted =
                                warmup.Rounds.Length,
                            measurementExcluded = true,
                            warmup.OwnerOwnedFormsBaseline,
                            warmup.OwnerOwnedFormHandlesBaseline,
                            noCheckpointAboveStart =
                                IsLifecycleWarmupWithinStartingEnvelope(
                                    warmup),
                            converged =
                                IsLifecycleWarmupConverged(warmup),
                            resources = new
                            {
                                checkpoints =
                                    warmup.ResourceCheckpoints.Select(
                                        checkpoint => new
                                        {
                                            checkpoint.Step,
                                            checkpoint.Phase,
                                            checkpoint.Metrics
                                        }).ToArray(),
                                before = warmup.ResourceBefore,
                                after = warmup.ResourceAfter,
                                delta = warmup.ResourceDelta,
                                warmup.HandleTrend
                            }
                        }).ToArray(),
                    exclusionReason =
                        "process-level first-use stabilization exercised only by complete isomorphic PlayerInfo lifecycle groups; the independent 100 cycles immediately following the first consecutive converged pair retain the unchanged zero-growth gates"
                },
                acceptanceMeasurementEligible =
                    lifecycleWarmupConverged,
                measurementRole =
                    lifecycleWarmupConverged
                        ? "acceptance_measurement"
                        : "diagnostic_after_warmup_cap",
                cycles = LifecycleCycleCount,
                checkpointInterval =
                    LifecycleCheckpointInterval,
                lifecycleChurn.OwnerOwnedFormsBaseline,
                lifecycleChurn.OwnerOwnedFormHandlesBaseline,
                lifecycleChurn.Rounds,
                resources = new
                {
                    checkpoints =
                        lifecycleChurn.ResourceCheckpoints.Select(
                            checkpoint => new
                            {
                                checkpoint.Step,
                                checkpoint.Phase,
                                checkpoint.Metrics
                            }).ToArray(),
                    before = lifecycleChurn.ResourceBefore,
                    after = lifecycleChurn.ResourceAfter,
                    delta = lifecycleChurn.ResourceDelta,
                    lifecycleChurn.HandleTrend
                }
            },
            viewport = new
            {
                host = Rect(new Rectangle(Point.Empty, anchor.ClientSize)),
                declaredMatrixCase =
                    "viewport_1920x1080_dpi150_max_design_case",
                actualSystemDpi = GetDpiForSystem(),
                actualSurfaceDeviceDpi = surface.DeviceDpi,
                physicalScale =
                    anchor.ClientSize.Height / 576d,
                tightPhysicalBounds = Rect(
                    activeEnd.TightPhysicalBounds),
                tightPixels =
                    (long)activeEnd.TightPhysicalBounds.Width *
                    activeEnd.TightPhysicalBounds.Height,
                tightBytes =
                    (long)activeEnd.TightPhysicalBounds.Width *
                    activeEnd.TightPhysicalBounds.Height * 4L
            },
            nativeHud = new
            {
                productionWidgetTypes,
                frozenAnimationAdapter =
                    "test-only: real production ScreenBounds/CompositeBounds/Paint, WantsAnimationTick=false",
                trigger =
                    "BoundsOrVisibilityChanged -> RecomputeBounds -> Paint -> actual ULW",
                unionBefore = Rect(nativeUnionBefore),
                unionAfter = Rect(nativeUnionAfter),
                playerInfoHidden = new
                {
                    visualSteps = VisualStepCount,
                    commitSamples = hiddenNativeCommitSamples,
                    commitSummary = hiddenNativeSummary,
                    successCount = hiddenNativeResults.Count(
                        result => result.Succeeded),
                    dimensions = DistinctDimensions(hiddenNativeResults)
                },
                playerInfoEnabled = new
                {
                    visualSteps = VisualStepCount,
                    commitSamples = enabledNativeCommitSamples,
                    commitSummary = enabledNativeSummary,
                    successCount = enabledNativeResults.Count(
                        result => result.Succeeded),
                    dimensions = DistinctDimensions(enabledNativeResults)
                },
                commitP95RegressionPercent = nativeHudRegressionPercent
            },
            splitSurface = new
            {
                hwnd = new
                {
                    created = surface.IsHandleCreated,
                    handle = "0x" + surface.Handle.ToInt64()
                        .ToString("X", CultureInfo.InvariantCulture),
                    actualUpdateLayeredWindowMeasured = true
                },
                active = new
                {
                    visualSteps = driverState.VisualSteps,
                    targetTransitions = driverState.TargetTransitions,
                    easingSteps = driverState.EasingSteps,
                    counters = activeDelta,
                    requestSamples = requestSamples
                        .Select(RoundSample)
                        .ToArray(),
                    requestSummary,
                    surfaceSamples,
                    surfaceSummary,
                    paintSamples,
                    paintSummary,
                    commitSamples = splitCommitSamples,
                    commitSummary = splitCommitSummary,
                    observerCommitSamples =
                        splitObservedCommitSamples,
                    observerCommitSummary =
                        splitObservedCommitSummary,
                    observerCommitMeasurementScope =
                        "actual prepared-memory-DC UpdateLayeredWindow transaction; reusable top-down PArgb DIB/memory-DC setup and cleanup are amortized across frames and guarded by lifecycle GDI/USER/process zero-growth checks",
                    observerCommitGeometry =
                        observedSplitCommitGeometries,
                    updateLayeredWindowOnlySamples =
                        splitUlwOnlySamples,
                    updateLayeredWindowOnlySummary =
                        splitUlwOnlySummary
                },
                idle = new
                {
                    ticks = IdleTickCount,
                    settleVisualSteps = idleSettleVisualSteps,
                    logicalStepMilliseconds =
                        LogicalStepMilliseconds,
                    counters = idleDelta
                },
                pipeline = new
                {
                    active = activeEnd.Pipeline,
                    shutdown = new
                    {
                        surfaceShutdown =
                            shutdownSnapshot.Shutdown,
                        counters = shutdownSnapshot.Pipeline
                    }
                }
            },
            resources = new
            {
                checkpoints = resourceSamples.Select(checkpoint => new
                {
                    checkpoint.Step,
                    checkpoint.Phase,
                    checkpoint.Metrics
                }).ToArray(),
                before = processBefore,
                after = processAfter,
                delta = ProcessMetrics.Delta(
                    processBefore,
                    processAfter),
                handleTrend,
                diagnosticOnly = new[]
                {
                    "cpuMilliseconds",
                    "allocatedBytes",
                    "gc0",
                    "gc1",
                    "gc2",
                    "workingSetBytes",
                    "privateBytes"
                }
            },
            gates,
            failures,
            verifier = new
            {
                mustRecomputeFromRawSamples = true,
                summaryAlgorithm =
                    "sort ascending; nearest-rank index=max(0,ceil(p*n)-1)",
                requiredIndependentChecks = new[]
                {
                    "all sample values finite and non-negative",
                    "Core/Test, renderer resolution, and exact source trace file identities",
                    "manifest plus eight SVG source hashes and aggregate asset revision",
                    "sample counts and counter deltas equal 3000",
                    "nearest-rank p50/p95/p99/max summaries",
                    "absent frozen JIT/GC overrides, Normal testhost priority, exact nonzero runner-inherited affinity mask, and server GC disabled",
                    "surface p95 <= 4 ms",
                    "prepared-memory-DC UpdateLayeredWindow transaction p95 < 33 ms; reusable DIB/DC lifecycle is amortized and covered by resource gates",
                    "NativeHud A/B union, count, dimensions, success, and p95 regression",
                    "canonical layer, exact fragment ownership, byte accounting, and owned disposal",
                    "real pipeline parse/raster=10, cache budget, and drained shutdown",
                    "up to five complete 100-cycle isomorphic groups until the first pair of consecutive strict checkpoint-envelope convergences, followed immediately by 100 independently measured real HWND publish/ULW/drain/dispose cycles with IsWindow, owner-root, late-commit, and unchanged zero-growth handle checks",
                    "idle 3000 repaint/paint/commit deltas are zero",
                    "GDI/USER/process handle endpoint and checkpoint trend"
                }
            }
        };
        return new QualificationOutcome(report, failures);
    }

    private static SurfaceLifecycleObservation RunSurfaceLifecycleChurn(
        Form owner,
        Control anchor)
    {
        Application.DoEvents();
        ForceManagedCleanup();
        Form[] ownerBaselineForms = owner.OwnedForms;
        int ownerOwnedFormsBaseline = ownerBaselineForms.Length;
        string[] ownerBaselineHandles = ownerBaselineForms
            .Where(form => form.IsHandleCreated)
            .Select(form => "0x" + form.Handle.ToInt64().ToString(
                "X",
                CultureInfo.InvariantCulture))
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        ProcessMetrics resourceBefore = CaptureProcessMetrics();
        var resourceCheckpoints = new List<ResourceCheckpoint>(
            (LifecycleCycleCount / LifecycleCheckpointInterval) + 1)
        {
            new(
                0,
                "lifecycle_start",
                resourceBefore)
        };
        var rounds =
            new List<SurfaceLifecycleRoundObservation>(
                LifecycleCycleCount);

        for (var cycle = 1; cycle <= LifecycleCycleCount; cycle++)
        {
            var observer = new RecordingCommitObserver();
            PlayerInfoSplitSurface? candidate = null;
            IntPtr hwnd = IntPtr.Zero;
            var hwndCreated = false;
            PlayerInfoSplitSurfaceCounterSnapshot activeCounters =
                default;
            PlayerInfoSplitSurfaceCounterSnapshot shutdownCounters =
                default;
            var observerCommitCountBeforeDispose = 0;
            var observerSuccessCount = 0;
            var ownerOwnedFormsAfterCreate = 0;
            var ownerContainsCandidateAfterCreate = false;
            var ownerBaselineSetPreservedAfterCreate = false;
            var ownerOwnedFormsAfterDrain = 0;
            var ownerContainsCandidateAfterDrain = false;
            var ownerBaselineSetPreservedAfterDrain = false;
            var queuedCaseChanged = false;
            long queuedRepaintDelta = 0;
            long queuedPaintDelta = 0;
            long queuedCommitDelta = 0;
            long paintDeltaAfterShutdownPump = 0;
            long commitDeltaAfterShutdownPump = 0;
            var observerLateCommitDeltaBeforeDispose = 0;
            var isWindowAfterDrain = false;
            try
            {
                string fixtureCase = (cycle & 1) == 0
                    ? "full"
                    : "empty";
                candidate = PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    fixtureCase,
                    observer);
                Form[] ownedAfterCreate = owner.OwnedForms;
                ownerOwnedFormsAfterCreate =
                    ownedAfterCreate.Length;
                ownerContainsCandidateAfterCreate =
                    ownedAfterCreate.Any(
                        form => ReferenceEquals(form, candidate));
                ownerBaselineSetPreservedAfterCreate =
                    ContainsEveryFormByReference(
                        ownedAfterCreate,
                        ownerBaselineForms);
                hwnd = candidate.Handle;
                hwndCreated =
                    hwnd != IntPtr.Zero && IsWindow(hwnd);
                candidate.SetReady();
                Assert.False(
                    candidate.AdvanceFixtureForQualification(0),
                    $"Lifecycle cycle {cycle} did not acquire a settled deterministic clock.");
                WaitWithoutMessagePump(
                    () =>
                        candidate.Counters.Pipeline.PublishCount > 0,
                    TimeSpan.FromSeconds(20),
                    $"Lifecycle cycle {cycle} raster publish did not finish.");
                PumpUntil(
                    () => candidate.Counters.CommitSuccessCount > 0,
                    TimeSpan.FromSeconds(20),
                    $"Lifecycle cycle {cycle} real ULW commit did not finish.");
                activeCounters = candidate.Counters;
                LayeredWindowCommitResult[] commitResults =
                    observer.Results;
                observerCommitCountBeforeDispose =
                    commitResults.Length;
                observerSuccessCount = commitResults.Count(
                    result => result.Succeeded);

                string queuedFixtureCase = string.Equals(
                    fixtureCase,
                    "full",
                    StringComparison.Ordinal)
                    ? "empty"
                    : "full";
                queuedCaseChanged =
                    candidate.SetFixtureCase(queuedFixtureCase);
                PlayerInfoSplitSurfaceCounterSnapshot queuedCounters =
                    candidate.Counters;
                queuedRepaintDelta =
                    queuedCounters.RepaintRequestCount -
                    activeCounters.RepaintRequestCount;
                queuedPaintDelta =
                    queuedCounters.PaintCount -
                    activeCounters.PaintCount;
                queuedCommitDelta =
                    queuedCounters.CommitCount -
                    activeCounters.CommitCount;

                Task shutdown = candidate.BeginShutdown();
                candidate.WaitForDrainAsync(
                        TimeSpan.FromSeconds(10))
                    .GetAwaiter()
                    .GetResult();
                shutdown.GetAwaiter().GetResult();
                shutdownCounters = candidate.Counters;
                Form[] ownedAfterDrain = owner.OwnedForms;
                ownerOwnedFormsAfterDrain =
                    ownedAfterDrain.Length;
                ownerContainsCandidateAfterDrain =
                    ownedAfterDrain.Any(
                        form => ReferenceEquals(form, candidate));
                ownerBaselineSetPreservedAfterDrain =
                    ContainsEveryFormByReference(
                        ownedAfterDrain,
                        ownerBaselineForms);
                isWindowAfterDrain = IsWindow(hwnd);

                // The deliberately queued render now runs against a shutdown
                // but still-live HWND. It must clear its post flag and return
                // without painting or committing.
                for (var pump = 0; pump < 3; pump++)
                {
                    Application.DoEvents();
                    Thread.Sleep(1);
                }
                PlayerInfoSplitSurfaceCounterSnapshot pumpedCounters =
                    candidate.Counters;
                paintDeltaAfterShutdownPump =
                    pumpedCounters.PaintCount -
                    activeCounters.PaintCount;
                commitDeltaAfterShutdownPump =
                    pumpedCounters.CommitCount -
                    activeCounters.CommitCount;
                observerLateCommitDeltaBeforeDispose =
                    observer.Count -
                    observerCommitCountBeforeDispose;
            }
            finally
            {
                candidate?.Dispose();
            }

            // Flush any message posted concurrently with Dispose as a second
            // boundary. The observer must remain unchanged.
            for (var pump = 0; pump < 3; pump++)
            {
                Application.DoEvents();
                Thread.Sleep(1);
            }
            int observerLateCommitDeltaAfterDispose =
                observer.Count - observerCommitCountBeforeDispose;
            Form[] ownedAfterDispose = owner.OwnedForms;
            bool ownerBaselineSetRestoredAfterDispose =
                HaveSameFormsByReference(
                    ownedAfterDispose,
                    ownerBaselineForms);
            rounds.Add(
                new SurfaceLifecycleRoundObservation(
                    cycle,
                    (cycle & 1) == 0 ? "full" : "empty",
                    "0x" + hwnd.ToInt64().ToString(
                        "X",
                        CultureInfo.InvariantCulture),
                    hwndCreated,
                    activeCounters.Pipeline.PublishCount,
                    activeCounters.Pipeline.ParseCount,
                    activeCounters.Pipeline.RasterCount,
                    observerCommitCountBeforeDispose,
                    observerSuccessCount,
                    activeCounters.RepaintRequestCount,
                    activeCounters.PaintCount,
                    activeCounters.CommitCount,
                    activeCounters.CommitSuccessCount,
                    activeCounters.CommitFailureCount,
                    queuedCaseChanged,
                    queuedRepaintDelta,
                    queuedPaintDelta,
                    queuedCommitDelta,
                    shutdownCounters.Shutdown,
                    shutdownCounters.Pipeline.ActiveWorkers,
                    shutdownCounters.Pipeline.CacheBytes,
                    shutdownCounters.Pipeline.CacheCount,
                    shutdownCounters.Pipeline.DesiredBatchKey,
                    shutdownCounters.Pipeline.CurrentBatchKey,
                    shutdownCounters.Pipeline.LastFault,
                    shutdownCounters.Pipeline.DisposedBatchCount,
                    shutdownCounters.Pipeline.DisposedLayerCount,
                    paintDeltaAfterShutdownPump,
                    commitDeltaAfterShutdownPump,
                    observerLateCommitDeltaBeforeDispose,
                    ownerOwnedFormsAfterCreate,
                    ownerContainsCandidateAfterCreate,
                    ownerBaselineSetPreservedAfterCreate,
                    ownerOwnedFormsAfterDrain,
                    ownerContainsCandidateAfterDrain,
                    ownerBaselineSetPreservedAfterDrain,
                    isWindowAfterDrain,
                    IsWindow(hwnd),
                    candidate?.IsDisposed ?? true,
                    candidate?.IsHandleCreated ?? false,
                    ownedAfterDispose.Length,
                    ownerBaselineSetRestoredAfterDispose,
                    observerLateCommitDeltaAfterDispose));

            if (cycle % LifecycleCheckpointInterval == 0 &&
                cycle < LifecycleCycleCount)
            {
                resourceCheckpoints.Add(
                    new ResourceCheckpoint(
                        cycle,
                        "lifecycle",
                        CaptureProcessMetrics()));
            }
        }

        Application.DoEvents();
        ForceManagedCleanup();
        ProcessMetrics resourceAfter = CaptureProcessMetrics();
        resourceCheckpoints.Add(
            new ResourceCheckpoint(
                LifecycleCycleCount,
                "lifecycle_end",
                resourceAfter));
        ProcessMetrics resourceDelta =
            ProcessMetrics.Delta(resourceBefore, resourceAfter);
        HandleTrend handleTrend =
            AnalyzeHandleTrend(resourceCheckpoints);
        return new SurfaceLifecycleObservation(
            ownerOwnedFormsBaseline,
            ownerBaselineHandles,
            rounds.ToArray(),
            resourceCheckpoints.ToArray(),
            resourceBefore,
            resourceAfter,
            resourceDelta,
            handleTrend);
    }

    private static bool ContainsEveryFormByReference(
        IReadOnlyList<Form> superset,
        IReadOnlyList<Form> subset) =>
        subset.All(expected =>
            superset.Any(
                actual => ReferenceEquals(actual, expected)));

    private static bool HaveSameFormsByReference(
        IReadOnlyList<Form> left,
        IReadOnlyList<Form> right) =>
        left.Count == right.Count &&
        ContainsEveryFormByReference(left, right) &&
        ContainsEveryFormByReference(right, left);

    private static RasterOwnershipObservation ProbeRasterOwnership(
        PlayerInfoSvgAssetSet assetSet,
        Rectangle viewport,
        float monitorDpiScale)
    {
        PlayerInfoRasterPlan plan = PlayerInfoRasterPlanner.Create(
            assetSet,
            viewport,
            monitorDpiScale);
        var progress = new PlayerInfoRasterProgress();
        PlayerInfoRasterBatch batch = new PlayerInfoSvgRasterizer().Bake(
            plan,
            CancellationToken.None,
            progress);
        PlayerInfoRasterLayer[] layers = batch.Layers.ToArray();
        var ownedBitmaps = new List<Bitmap>(
            CanonicalRasterLayerCount + OwnedRasterFragmentCount);
        var allReferencesDistinct = true;
        var allPayloadsMatch = true;
        long independentBatchBytes = 0;
        RasterLayerOwnershipObservation[] layerObservations;

        void ObserveReference(Bitmap bitmap)
        {
            if (ownedBitmaps.Any(
                    candidate => ReferenceEquals(candidate, bitmap)))
            {
                allReferencesDistinct = false;
                return;
            }
            ownedBitmaps.Add(bitmap);
        }

        try
        {
            layerObservations = layers.Select(layer =>
            {
                string[] fragmentIds = layer.FragmentIds
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray();
                long independentLayerBytes = checked(
                    (long)layer.Key.PixelWidth *
                    layer.Key.PixelHeight *
                    4L *
                    (1L + fragmentIds.Length));
                independentBatchBytes = checked(
                    independentBatchBytes + independentLayerBytes);

                Bitmap main = layer.Bitmap;
                ObserveReference(main);
                bool mainMatches =
                    main.Width == layer.Key.PixelWidth &&
                    main.Height == layer.Key.PixelHeight &&
                    main.PixelFormat ==
                        PixelFormat.Format32bppPArgb;
                allPayloadsMatch &= mainMatches;

                RasterFragmentOwnershipObservation[] fragments =
                    fragmentIds.Select(fragmentId =>
                    {
                        Bitmap fragment =
                            layer.RequireFragment(fragmentId);
                        ObserveReference(fragment);
                        bool matches =
                            fragment.Width == layer.Key.PixelWidth &&
                            fragment.Height == layer.Key.PixelHeight &&
                            fragment.PixelFormat ==
                                PixelFormat.Format32bppPArgb;
                        allPayloadsMatch &= matches;
                        return new RasterFragmentOwnershipObservation(
                            fragmentId,
                            fragment.Width,
                            fragment.Height,
                            fragment.PixelFormat.ToString(),
                            matches);
                    }).ToArray();

                return new RasterLayerOwnershipObservation(
                    layer.Key.LayerId,
                    layer.Key.PixelWidth,
                    layer.Key.PixelHeight,
                    layer.ByteSize,
                    independentLayerBytes,
                    main.Width,
                    main.Height,
                    main.PixelFormat.ToString(),
                    mainMatches,
                    fragmentIds,
                    fragments);
            }).ToArray();
        }
        finally
        {
            batch.Dispose();
        }

        bool batchLayerAccessThrows =
            ThrowsObjectDisposedException(
                () =>
                {
                    _ = batch.Layers;
                });
        bool layerBitmapAccessThrows = layers.All(
            layer => ThrowsObjectDisposedException(
                () =>
                {
                    _ = layer.Bitmap;
                }));
        PlayerInfoRasterLayer? fragmentOwner = layers.SingleOrDefault(
            layer => string.Equals(
                layer.Key.LayerId,
                "mp.fill",
                StringComparison.Ordinal));
        bool fragmentAccessThrows =
            fragmentOwner is not null &&
            ThrowsObjectDisposedException(
                () =>
                {
                    _ = fragmentOwner.RequireFragment("mp-left-mask");
                });

        return new RasterOwnershipObservation(
            layers.Length,
            layerObservations.Sum(layer => layer.FragmentIds.Length),
            progress.ParseCount,
            progress.RasterCount,
            batch.ByteSize,
            independentBatchBytes,
            allPayloadsMatch,
            allReferencesDistinct,
            batch.IsDisposed,
            layers.Count(layer => layer.IsDisposed),
            batchLayerAccessThrows,
            layerBitmapAccessThrows,
            fragmentAccessThrows,
            layerObservations);
    }

    private static bool ThrowsObjectDisposedException(Action action)
    {
        try
        {
            action();
            return false;
        }
        catch (ObjectDisposedException)
        {
            return true;
        }
    }

    private static FrozenProductionWidget[] CreateFrozenProductionWidgets(
        string projectRoot,
        Control anchor)
    {
        var router = new LauncherCommandRouter(
            socketServer: null!,
            onSendKey: _ => { },
            onToggleFullscreen: () => { },
            onToggleLog: () => { },
            onForceExit: () => { },
            postToWeb: _ => { },
            onPanelStateChanged: _ => { },
            setActivePanel: _ => { });
        MapHudDataCatalog catalog = MapHudDataCatalog.LoadFromFile(
            Path.Combine(
                projectRoot,
                "launcher",
                "data",
                "map_hud_data.json"));
        var rightContext = new RightContextWidget(
            anchor,
            router,
            catalog,
            MapDisplayPreference.Expanded);
        rightContext.ForceGameReady(true);
        rightContext.ForceMapMode("1");
        rightContext.ForceMapHotspot("base_roof");
        rightContext.ForceTaskDone(true);

        var safeExit = new SafeExitPanelWidget(anchor, router);
        safeExit.ForceGameReady(true);
        safeExit.Arm();

        var combo = new ComboWidget(anchor);
        combo.ForceGameReady(true);
        combo.OnLegacyUiData(
            "combo",
            ["", "→↓", "DFA 冲拳|→↓→;Sync 连击|↓→↓"]);

        var toast = new ToastWidget(anchor);
        toast.SetReady();
        for (var line = 1; line <= 8; line++)
        {
            toast.AddMessage(
                $"B0-06 NativeHud visible workload line {line}");
        }

        var fps = new FpsRingBuffer(600);
        for (var index = 0; index < 120; index++)
        {
            fps.Push(60f - ((index % 7) * 0.25f));
        }
        var notch = new NotchWidget(
            anchor,
            fps,
            projectRoot,
            () => { },
            () => { },
            () => { },
            _ => { },
            new AudioHudState());
        notch.ForceGameReadyForTest(true);
        notch.ForceCurrenciesForTest(9_999_999, 88_888);
        notch.BeginExpandForTest();
        notch.Tick(10_000);

        INativeHudWidget[] production =
        [
            rightContext,
            safeExit,
            combo,
            toast,
            notch
        ];
        return production
            .Select(widget => new FrozenProductionWidget(widget))
            .ToArray();
    }

    private static bool DriveOneSurfaceVisualStep(
        PlayerInfoSplitSurface surface,
        SurfaceDriverState state)
    {
        bool changed = surface.AdvanceFixtureForQualification(
            LogicalStepMilliseconds);
        if (changed)
        {
            state.EasingSteps++;
        }
        else
        {
            state.NextTarget =
                string.Equals(
                    state.NextTarget,
                    "empty",
                    StringComparison.Ordinal)
                    ? "full"
                    : "empty";
            changed = surface.SetFixtureCase(state.NextTarget);
            if (changed)
            {
                state.TargetTransitions++;
            }
        }
        if (changed)
        {
            state.VisualSteps++;
        }
        return changed;
    }

    private static void WarmSurface(
        PlayerInfoSplitSurface surface,
        SurfaceDriverState driverState,
        int steps)
    {
        for (var step = 0; step < steps; step++)
        {
            long previous = surface.Counters.CommitCount;
            Assert.True(DriveOneSurfaceVisualStep(surface, driverState));
            PumpUntil(
                () => surface.Counters.CommitCount > previous,
                TimeSpan.FromSeconds(5),
                "PlayerInfo warm visual step did not commit.");
            Assert.Equal(previous + 1, surface.Counters.CommitCount);
        }
        driverState.ResetCounts();
    }

    private static Form CreateHost(out Panel anchor)
    {
        var owner = new Form
        {
            AutoScaleMode = AutoScaleMode.None,
            ClientSize = new Size(1920, 1080),
            FormBorderStyle = FormBorderStyle.None,
            Location = new Point(-20_000, -20_000),
            ShowInTaskbar = false,
            StartPosition = FormStartPosition.Manual
        };
        anchor = new Panel
        {
            Bounds = new Rectangle(0, 0, 1920, 1080)
        };
        owner.Controls.Add(anchor);
        _ = owner.Handle;
        _ = anchor.Handle;
        return owner;
    }

    private static void WaitWithoutMessagePump(
        Func<bool> condition,
        TimeSpan timeout,
        string failureMessage)
    {
        var timer = Stopwatch.StartNew();
        while (!condition() && timer.Elapsed < timeout)
        {
            Thread.Sleep(5);
        }
        Assert.True(condition(), failureMessage);
    }

    private static void PumpUntil(
        Func<bool> condition,
        TimeSpan timeout,
        string failureMessage)
    {
        var timer = Stopwatch.StartNew();
        while (!condition() && timer.Elapsed < timeout)
        {
            Application.DoEvents();
            Thread.Sleep(1);
        }
        Application.DoEvents();
        Assert.True(condition(), failureMessage);
    }

    private static T RunOnSta<T>(
        Func<T> action,
        TimeSpan timeout)
    {
        Exception? failure = null;
        T? result = default;
        var thread = new Thread(() =>
        {
            try
            {
                result = action();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
        })
        {
            IsBackground = true,
            Name = "PlayerInfoB006Qualification.STA"
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(
            thread.Join(timeout),
            "B0-06 STA qualification exceeded its fail-closed timeout of " +
            $"{timeout.TotalMinutes:0.###} minutes.");
        if (failure is not null)
        {
            ExceptionDispatchInfo.Capture(failure).Throw();
        }
        return result!;
    }

    private static double[] SliceSamples(
        int start,
        IReadOnlyList<double> values)
    {
        if (start < 0 || start > values.Count)
        {
            throw new ArgumentOutOfRangeException(nameof(start));
        }
        return values
            .Skip(start)
            .Select(RoundSample)
            .ToArray();
    }

    private static TimingSummary Summarize(
        IEnumerable<double> source)
    {
        double[] values = source
            .Select(value =>
            {
                if (!double.IsFinite(value) || value < 0)
                {
                    throw new InvalidDataException(
                        "Timing samples must be finite and non-negative.");
                }
                return RoundSample(value);
            })
            .OrderBy(value => value)
            .ToArray();
        if (values.Length == 0)
        {
            return new TimingSummary(0, 0, 0, 0, 0);
        }
        return new TimingSummary(
            values.Length,
            Percentile(values, 0.50),
            Percentile(values, 0.95),
            Percentile(values, 0.99),
            values[^1]);
    }

    private static double Percentile(
        IReadOnlyList<double> sorted,
        double percentile)
    {
        if (sorted.Count == 0)
        {
            return 0;
        }
        int index = Math.Max(
            0,
            (int)Math.Ceiling(percentile * sorted.Count) - 1);
        return sorted[index];
    }

    private static double RoundSample(double value) =>
        Math.Round(value, 6, MidpointRounding.AwayFromZero);

    private static double ElapsedMilliseconds(long startTimestamp) =>
        RoundSample(
            (Stopwatch.GetTimestamp() - startTimestamp) *
            1000d /
            Stopwatch.Frequency);

    private static void ForceManagedCleanup()
    {
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        using Process process = Process.GetCurrentProcess();
        process.Refresh();
    }

    private static ProcessMetrics CaptureProcessMetrics()
    {
        using Process process = Process.GetCurrentProcess();
        process.Refresh();
        return new ProcessMetrics(
            process.TotalProcessorTime.TotalMilliseconds,
            GC.GetTotalAllocatedBytes(precise: false),
            GC.CollectionCount(0),
            GC.CollectionCount(1),
            GC.CollectionCount(2),
            process.WorkingSet64,
            process.PrivateMemorySize64,
            process.HandleCount,
            checked((int)GetGuiResources(process.Handle, 0)),
            checked((int)GetGuiResources(process.Handle, 1)));
    }

    private static HandleTrend AnalyzeHandleTrend(
        IReadOnlyList<ResourceCheckpoint> checkpoints)
    {
        bool gdi = IsPositiveMonotonicGrowth(
            checkpoints.Select(checkpoint =>
                checkpoint.Metrics.GdiObjects));
        bool user = IsPositiveMonotonicGrowth(
            checkpoints.Select(checkpoint =>
                checkpoint.Metrics.UserObjects));
        bool process = IsPositiveMonotonicGrowth(
            checkpoints.Select(checkpoint =>
                checkpoint.Metrics.ProcessHandles));
        return new HandleTrend(
            gdi,
            user,
            process,
            gdi || user || process);
    }

    private static bool IsLifecycleWarmupWithinStartingEnvelope(
        SurfaceLifecycleObservation observation)
    {
        if (observation.ResourceCheckpoints.Length !=
            (LifecycleWarmupCycleCount /
                LifecycleCheckpointInterval) + 1)
        {
            return false;
        }
        ProcessMetrics start =
            observation.ResourceCheckpoints[0].Metrics;
        return observation.ResourceCheckpoints.All(checkpoint =>
            checkpoint.Metrics.GdiObjects <= start.GdiObjects &&
            checkpoint.Metrics.UserObjects <= start.UserObjects &&
            checkpoint.Metrics.ProcessHandles <=
                start.ProcessHandles);
    }

    private static bool IsLifecycleWarmupConverged(
        SurfaceLifecycleObservation observation) =>
        IsLifecycleWarmupWithinStartingEnvelope(observation) &&
        observation.ResourceDelta.GdiObjects <= 0 &&
        observation.ResourceDelta.UserObjects <= 0 &&
        observation.ResourceDelta.ProcessHandles <= 0 &&
        !observation.HandleTrend.AnyPositiveMonotonicGrowth;

    private static int? FindFirstLifecycleWarmupConvergedPairEndIndex(
        IReadOnlyList<bool> convergenceSequence)
    {
        var consecutiveConvergedGroups = 0;
        for (var index = 0; index < convergenceSequence.Count; index++)
        {
            consecutiveConvergedGroups = convergenceSequence[index]
                ? consecutiveConvergedGroups + 1
                : 0;
            if (consecutiveConvergedGroups >=
                LifecycleWarmupRequiredConsecutiveConvergedGroups)
            {
                return index + 1;
            }
        }
        return null;
    }

    private static bool IsPerformanceEnvironmentQualified(
        IReadOnlyDictionary<string, string?>
            inheritedPerformanceOverrides,
        string processPriorityClass,
        string processorAffinityMask,
        string? expectedPriorityClass,
        string? expectedAffinityMask,
        bool serverGc)
    {
        bool expectedAffinityIsNonZero =
            ulong.TryParse(
                expectedAffinityMask,
                NumberStyles.AllowHexSpecifier,
                CultureInfo.InvariantCulture,
                out ulong expectedAffinity) &&
            expectedAffinity != 0;
        return
            inheritedPerformanceOverrides.Count ==
                PerformanceOverrideEnvironmentNames.Length &&
            PerformanceOverrideEnvironmentNames.All(name =>
                inheritedPerformanceOverrides.TryGetValue(
                    name,
                    out string? value) &&
                value is null) &&
            string.Equals(
                processPriorityClass,
                ProcessPriorityClass.Normal.ToString(),
                StringComparison.Ordinal) &&
            string.Equals(
                expectedPriorityClass,
                ProcessPriorityClass.Normal.ToString(),
                StringComparison.Ordinal) &&
            expectedAffinityIsNonZero &&
            string.Equals(
                processorAffinityMask,
                expectedAffinityMask,
                StringComparison.Ordinal) &&
            !serverGc;
    }

    private static string FormatAffinityMask(IntPtr affinity) =>
        unchecked((ulong)affinity.ToInt64())
            .ToString("X16", CultureInfo.InvariantCulture);

    private static bool IsPositiveMonotonicGrowth(
        IEnumerable<int> source)
    {
        int[] values = source.ToArray();
        if (values.Length < 2 || values[^1] <= values[0])
        {
            return false;
        }
        for (var index = 1; index < values.Length; index++)
        {
            if (values[index] < values[index - 1])
            {
                return false;
            }
        }
        return true;
    }

    private static object[] DistinctDimensions(
        IEnumerable<LayeredWindowCommitResult> results) =>
        results
            .Select(result => new Dimension(
                result.Width,
                result.Height,
                result.PixelCount,
                result.ByteCount))
            .Distinct()
            .Cast<object>()
            .ToArray();

    private static object Rect(Rectangle rectangle) =>
        new
        {
            rectangle.X,
            rectangle.Y,
            rectangle.Width,
            rectangle.Height,
            pixels = (long)rectangle.Width * rectangle.Height,
            bytes = (long)rectangle.Width * rectangle.Height * 4L
        };

    private static FileIdentityObservation[] CaptureFileIdentityClosure(
        IEnumerable<string> paths,
        string projectRoot)
    {
        FileIdentityObservation[] identities = paths
            .Select(path =>
                CaptureFileIdentity(path, projectRoot))
            .OrderBy(
                identity => identity.Path,
                StringComparer.Ordinal)
            .ToArray();
        if (identities.Length == 0 ||
            identities.Select(identity => identity.Path)
                .Distinct(StringComparer.Ordinal)
                .Count() != identities.Length)
        {
            throw new InvalidOperationException(
                "Qualification file identity closure must be non-empty and unique.");
        }
        return identities;
    }

    private static SourceTraceIdentityObservation[]
        CaptureSourceTraceClosure(
            IEnumerable<string> relativePaths,
            string projectRoot)
    {
        SourceTraceIdentityObservation[] identities = relativePaths
            .Select(relativePath =>
            {
                string normalized = relativePath.Replace(
                    '\\',
                    '/');
                if (Path.IsPathRooted(normalized) ||
                    normalized.Equals(
                        "..",
                        StringComparison.Ordinal) ||
                    normalized.StartsWith(
                        "../",
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        $"Qualification source trace path escapes the project root: {relativePath}");
                }
                string fullPath = Path.Combine(
                    projectRoot,
                    normalized.Replace(
                        '/',
                        Path.DirectorySeparatorChar));
                FileIdentityObservation file =
                    CaptureFileIdentity(fullPath, projectRoot);
                string gitBlobOid = RunGit(
                    projectRoot,
                    "hash-object",
                    "--path=" + normalized,
                    fullPath);
                if (gitBlobOid.Length is not (40 or 64) ||
                    gitBlobOid.Any(character =>
                        !Uri.IsHexDigit(character)))
                {
                    throw new InvalidDataException(
                        $"git hash-object returned an invalid OID for {normalized}.");
                }
                return new SourceTraceIdentityObservation(
                    file.Path,
                    file.Bytes,
                    file.Sha256,
                    gitBlobOid.ToLowerInvariant());
            })
            .OrderBy(
                identity => identity.Path,
                StringComparer.Ordinal)
            .ToArray();
        if (identities.Length == 0 ||
            identities.Select(identity => identity.Path)
                .Distinct(StringComparer.Ordinal)
                .Count() != identities.Length)
        {
            throw new InvalidOperationException(
                "Qualification source trace closure must be non-empty and unique.");
        }
        return identities;
    }

    private static FileIdentityObservation CaptureFileIdentity(
        string path,
        string projectRoot)
    {
        string fullPath = Path.GetFullPath(path);
        var info = new FileInfo(fullPath);
        if (!info.Exists || info.Length <= 0)
        {
            throw new FileNotFoundException(
                "Qualification source identity file is missing.",
                fullPath);
        }
        string relative = Path.GetRelativePath(projectRoot, fullPath)
            .Replace('\\', '/');
        if (Path.IsPathRooted(relative) ||
            relative.Equals("..", StringComparison.Ordinal) ||
            relative.StartsWith("../", StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Qualification identity path escapes the project root: {fullPath}");
        }
        return new FileIdentityObservation(
            relative,
            info.Length,
            Sha256(fullPath));
    }

    private static string Sha256(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static string RunGit(
        string projectRoot,
        params string[] arguments)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "git",
            WorkingDirectory = projectRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        startInfo.ArgumentList.Add("-C");
        startInfo.ArgumentList.Add(projectRoot);
        foreach (string argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        using Process process = Process.Start(startInfo) ??
            throw new InvalidOperationException("Unable to start git.");
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"git {string.Join(" ", arguments)} failed: {stderr}");
        }
        return stdout.Trim();
    }

    private static void AddGate(
        ICollection<QualificationGate> gates,
        string id,
        string phase,
        bool passed,
        object? actual,
        object? expected,
        string comparison,
        string unit,
        string detail) =>
        gates.Add(
            new QualificationGate(
                id,
                phase,
                passed,
                actual,
                expected,
                comparison,
                unit,
                detail));

    private static void WriteReport(string path, object report)
    {
        Directory.CreateDirectory(
            Path.GetDirectoryName(path) ??
            throw new InvalidOperationException(
                "Report path has no parent directory."));
        string json = JsonSerializer.Serialize(
            report,
            new JsonSerializerOptions
            {
                WriteIndented = true,
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });
        json = json
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .TrimEnd('\r', '\n') + "\n";
        File.WriteAllText(path, json, new UTF8Encoding(false));
    }

    private sealed class FrozenProductionWidget :
        INativeHudWidget,
        INativeHudCompositeBoundsProvider,
        IDisposable
    {
        private readonly INativeHudWidget _inner;
        private int _visualEpoch;

        internal FrozenProductionWidget(INativeHudWidget inner)
        {
            _inner = inner ??
                throw new ArgumentNullException(nameof(inner));
        }

        internal string ProductionType =>
            _inner.GetType().FullName ??
            _inner.GetType().Name;

        public Rectangle ScreenBounds => _inner.ScreenBounds;
        public Rectangle CompositeBounds =>
            _inner is INativeHudCompositeBoundsProvider provider
                ? provider.CompositeBounds
                : _inner.ScreenBounds;
        public bool Visible => _inner.Visible;
        public bool WantsAnimationTick => false;

        public event EventHandler? BoundsOrVisibilityChanged;
        public event EventHandler? RepaintRequested
        {
            add { }
            remove { }
        }
        public event EventHandler? AnimationStateChanged
        {
            add { }
            remove { }
        }

        public void Tick(int deltaMs)
        {
        }

        public void Paint(Graphics graphics, float dpr, Point hudOrigin)
        {
            _inner.Paint(graphics, dpr, hudOrigin);
            Rectangle bounds = ScreenBounds;
            if (bounds.Width <= 0 || bounds.Height <= 0)
            {
                return;
            }
            int localX = bounds.Left - hudOrigin.X;
            int localY = bounds.Top - hudOrigin.Y;
            Color marker = (_visualEpoch & 1) == 0
                ? Color.FromArgb(1, 255, 255, 255)
                : Color.FromArgb(1, 0, 0, 0);
            using var brush = new SolidBrush(marker);
            graphics.FillRectangle(brush, localX, localY, 1, 1);
        }

        public bool TryHitTest(Point screenPoint) =>
            _inner.TryHitTest(screenPoint);

        public void OnMouseEvent(
            MouseEventArgs args,
            MouseEventKind kind) =>
            _inner.OnMouseEvent(args, kind);

        internal void AdvanceVisualStep()
        {
            _visualEpoch = checked(_visualEpoch + 1);
            BoundsOrVisibilityChanged?.Invoke(this, EventArgs.Empty);
        }

        public void Dispose()
        {
            if (_inner is IDisposable disposable)
            {
                disposable.Dispose();
            }
            BoundsOrVisibilityChanged = null;
        }
    }

    private sealed class RecordingCommitObserver :
        ILayeredWindowCommitObserver
    {
        private readonly object _gate = new();
        private readonly List<LayeredWindowCommitResult> _results = [];

        internal int Count
        {
            get
            {
                lock (_gate)
                {
                    return _results.Count;
                }
            }
        }

        internal LayeredWindowCommitResult[] Results
        {
            get
            {
                lock (_gate)
                {
                    return _results.ToArray();
                }
            }
        }

        internal LayeredWindowCommitResult[] Slice(int start)
        {
            lock (_gate)
            {
                if (start < 0 || start > _results.Count)
                {
                    throw new ArgumentOutOfRangeException(nameof(start));
                }
                return _results.Skip(start).ToArray();
            }
        }

        public void OnCommit(LayeredWindowCommitResult result)
        {
            lock (_gate)
            {
                _results.Add(result);
            }
        }
    }

    private sealed class SurfaceDriverState(string nextTarget)
    {
        internal string NextTarget { get; set; } = nextTarget;
        internal int VisualSteps { get; set; }
        internal int TargetTransitions { get; set; }
        internal int EasingSteps { get; set; }

        internal void ResetCounts()
        {
            VisualSteps = 0;
            TargetTransitions = 0;
            EasingSteps = 0;
        }
    }

    private sealed record QualificationOutcome(
        object Report,
        IReadOnlyList<string> Failures);

    private sealed record QualificationGate(
        string Id,
        string Phase,
        bool Passed,
        object? Actual,
        object? Expected,
        string Comparison,
        string Unit,
        string Detail);

    private sealed record FileIdentityObservation(
        string Path,
        long Bytes,
        string Sha256);

    private sealed record SourceTraceIdentityObservation(
        string Path,
        long Bytes,
        string Sha256,
        string GitBlobOid);

    private sealed record AssetSourceIdentityObservation(
        string Id,
        string RelativePath,
        int LoadedBytes,
        string LoadedSha256,
        FileIdentityObservation SourceFile);

    private sealed record SurfaceLifecycleObservation(
        int OwnerOwnedFormsBaseline,
        string[] OwnerOwnedFormHandlesBaseline,
        SurfaceLifecycleRoundObservation[] Rounds,
        ResourceCheckpoint[] ResourceCheckpoints,
        ProcessMetrics ResourceBefore,
        ProcessMetrics ResourceAfter,
        ProcessMetrics ResourceDelta,
        HandleTrend HandleTrend);

    private sealed record SurfaceLifecycleRoundObservation(
        int Cycle,
        string FixtureCase,
        string Hwnd,
        bool HwndCreated,
        long PublishCount,
        long ParseCount,
        long RasterCount,
        int ObserverCommitCount,
        int ObserverSuccessCount,
        long RepaintRequestCount,
        long PaintCount,
        long CommitCount,
        long CommitSuccessCount,
        long CommitFailureCount,
        bool QueuedCaseChanged,
        long QueuedRepaintDelta,
        long QueuedPaintDelta,
        long QueuedCommitDelta,
        bool Shutdown,
        int ActiveWorkersAfterShutdown,
        long CacheBytesAfterShutdown,
        int CacheCountAfterShutdown,
        string? DesiredBatchKeyAfterShutdown,
        string? CurrentBatchKeyAfterShutdown,
        string? LastFaultAfterShutdown,
        long DisposedBatchCount,
        long DisposedLayerCount,
        long PaintDeltaAfterShutdownPump,
        long CommitDeltaAfterShutdownPump,
        int ObserverLateCommitDeltaBeforeDispose,
        int OwnerOwnedFormsAfterCreate,
        bool OwnerContainsCandidateAfterCreate,
        bool OwnerBaselineSetPreservedAfterCreate,
        int OwnerOwnedFormsAfterDrain,
        bool OwnerContainsCandidateAfterDrain,
        bool OwnerBaselineSetPreservedAfterDrain,
        bool IsWindowAfterDrain,
        bool IsWindowAfterDispose,
        bool IsDisposedAfterDispose,
        bool IsHandleCreatedAfterDispose,
        int OwnerOwnedFormsAfterDispose,
        bool OwnerBaselineSetRestoredAfterDispose,
        int ObserverLateCommitDeltaAfterDispose);

    private sealed record RasterOwnershipObservation(
        int CanonicalLayerCount,
        int OwnedFragmentCount,
        int ParseCount,
        int RasterCount,
        long BatchByteSize,
        long IndependentlyComputedByteSize,
        bool AllPayloadsMatchKeyAndPArgb,
        bool AllBitmapReferencesDistinct,
        bool BatchDisposed,
        int DisposedLayerCount,
        bool BatchLayerAccessThrowsObjectDisposed,
        bool LayerBitmapAccessThrowsObjectDisposed,
        bool FragmentAccessThrowsObjectDisposed,
        RasterLayerOwnershipObservation[] Layers);

    private sealed record RasterLayerOwnershipObservation(
        string LayerId,
        int PixelWidth,
        int PixelHeight,
        long DeclaredByteSize,
        long IndependentlyComputedByteSize,
        int MainBitmapWidth,
        int MainBitmapHeight,
        string MainPixelFormat,
        bool MainBitmapMatchesKeyAndPArgb,
        string[] FragmentIds,
        RasterFragmentOwnershipObservation[] Fragments);

    private sealed record RasterFragmentOwnershipObservation(
        string FragmentId,
        int Width,
        int Height,
        string PixelFormat,
        bool MatchesKeyAndPArgb);

    private sealed record TimingSummary(
        int Count,
        double P50,
        double P95,
        double P99,
        double Max);

    private sealed record SurfaceCounters(
        long RepaintRequestCount,
        long PaintCount,
        long CommitCount,
        long CommitSuccessCount,
        long CommitFailureCount)
    {
        internal static SurfaceCounters Delta(
            PlayerInfoSplitSurfaceSnapshot before,
            PlayerInfoSplitSurfaceSnapshot after) =>
            new(
                after.RepaintRequestCount - before.RepaintRequestCount,
                after.PaintCount - before.PaintCount,
                after.CommitCount - before.CommitCount,
                after.CommitSuccessCount - before.CommitSuccessCount,
                after.CommitFailureCount - before.CommitFailureCount);
    }

    private sealed record ProcessMetrics(
        double CpuMilliseconds,
        long AllocatedBytes,
        int Gc0,
        int Gc1,
        int Gc2,
        long WorkingSetBytes,
        long PrivateBytes,
        int ProcessHandles,
        int GdiObjects,
        int UserObjects)
    {
        internal static ProcessMetrics Delta(
            ProcessMetrics before,
            ProcessMetrics after) =>
            new(
                after.CpuMilliseconds - before.CpuMilliseconds,
                after.AllocatedBytes - before.AllocatedBytes,
                after.Gc0 - before.Gc0,
                after.Gc1 - before.Gc1,
                after.Gc2 - before.Gc2,
                after.WorkingSetBytes - before.WorkingSetBytes,
                after.PrivateBytes - before.PrivateBytes,
                after.ProcessHandles - before.ProcessHandles,
                after.GdiObjects - before.GdiObjects,
                after.UserObjects - before.UserObjects);
    }

    private sealed record ResourceCheckpoint(
        int Step,
        string Phase,
        ProcessMetrics Metrics);

    private sealed record HandleTrend(
        bool GdiPositiveMonotonicGrowth,
        bool UserPositiveMonotonicGrowth,
        bool ProcessPositiveMonotonicGrowth,
        bool AnyPositiveMonotonicGrowth);

    private sealed record CommitGeometry(
        int ScreenX,
        int ScreenY,
        int Width,
        int Height);

    private sealed record Dimension(
        int Width,
        int Height,
        long Pixels,
        long Bytes);

    private sealed class IntArrayComparer : IEqualityComparer<int[]>
    {
        internal static readonly IntArrayComparer Instance = new();

        public bool Equals(int[]? left, int[]? right) =>
            left is not null &&
            right is not null &&
            left.SequenceEqual(right);

        public int GetHashCode(int[] value)
        {
            var hash = new HashCode();
            foreach (int item in value)
            {
                hash.Add(item);
            }
            return hash.ToHashCode();
        }
    }

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern uint GetGuiResources(
        IntPtr processHandle,
        uint flags);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern uint GetDpiForSystem();

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr hWnd);
}
