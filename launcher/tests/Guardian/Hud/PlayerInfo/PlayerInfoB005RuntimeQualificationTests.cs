#nullable enable

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using SkiaSharp;
using Svg.Skia;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class B005QualificationFactAttribute : FactAttribute
{
    public B005QualificationFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    "CF7_PLAYER_INFO_B005_REPORT_PATH")) ||
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    "CF7_PLAYER_INFO_B005_RUN_ID")) ||
            string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable(
                    "CF7_PLAYER_INFO_B005_PROJECT_ROOT")))
        {
            Skip =
                "B0-05 native qualification is executed only by its dedicated runner.";
        }
    }
}

public sealed class PlayerInfoB005RuntimeQualificationTests
{
    private const string ReportPathEnvironment =
        "CF7_PLAYER_INFO_B005_REPORT_PATH";
    private const string RunIdEnvironment =
        "CF7_PLAYER_INFO_B005_RUN_ID";
    private const string SdkVersionEnvironment =
        "CF7_PLAYER_INFO_B005_SDK_VERSION";
    private const string ProjectRootEnvironment =
        "CF7_PLAYER_INFO_B005_PROJECT_ROOT";
    private const string ExpectedPriorityClassEnvironment =
        "CF7_PLAYER_INFO_B005_EXPECTED_PRIORITY_CLASS";
    private const string ExpectedAffinityMaskEnvironment =
        "CF7_PLAYER_INFO_B005_EXPECTED_AFFINITY_MASK";
    private const string ReportSchema =
        "cf7.player-info-hud.b0-05-runtime-qualification";
    private const string MeasurementKind = "synthetic_fixed_bounds";
    private const string GeometryConclusion =
        "geometry_requires_decision";
    private const string RecordedTopologyDecision = "split_required";
    private const double UiRequestP95LimitMs = 4.0;
    private const double WarmedFreshBakeP95LimitMs = 100.0;
    private const double WarmLookupP95LimitMs = 1.0;
    private const int WarmedFreshExcludedWarmupRounds = 16;
    private const int WarmedFreshSamplesPerViewport = 20;
    private const int PendingCoalescingRequestCount = 100;
    private const int SteadyRequestCount = 3000;
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
    private static readonly ExecutionBinaryContract[] ExpectedExecutionBinaries =
    [
        new(
            "core",
            "managed",
            "launcher/tests/bin/Release/CRAZYFLASHER7MercenaryEmpire.Core.dll"),
        new(
            "excss",
            "managed",
            "launcher/tests/bin/Release/ExCSS.dll"),
        new(
            "harfbuzz_sharp",
            "managed",
            "launcher/tests/bin/Release/HarfBuzzSharp.dll"),
        new(
            "harfbuzz_sharp_native_win_x64",
            "native",
            "launcher/tests/bin/Release/runtimes/win-x64/native/libHarfBuzzSharp.dll"),
        new(
            "shim_skia_sharp",
            "managed",
            "launcher/tests/bin/Release/ShimSkiaSharp.dll"),
        new(
            "skia_sharp",
            "managed",
            "launcher/tests/bin/Release/SkiaSharp.dll"),
        new(
            "skia_sharp_native_win_x64",
            "native",
            "launcher/tests/bin/Release/runtimes/win-x64/native/libSkiaSharp.dll"),
        new(
            "svg_animation",
            "managed",
            "launcher/tests/bin/Release/Svg.Animation.dll"),
        new(
            "svg_custom",
            "managed",
            "launcher/tests/bin/Release/Svg.Custom.dll"),
        new(
            "svg_model",
            "managed",
            "launcher/tests/bin/Release/Svg.Model.dll"),
        new(
            "svg_scene_graph",
            "managed",
            "launcher/tests/bin/Release/Svg.SceneGraph.dll"),
        new(
            "svg_skia",
            "managed",
            "launcher/tests/bin/Release/Svg.Skia.dll")
    ];
    private static readonly string[] ExpectedRendererOutputClosurePaths =
    [
        "launcher/tests/bin/Release/ExCSS.dll",
        "launcher/tests/bin/Release/HarfBuzzSharp.dll",
        "launcher/tests/bin/Release/ShimSkiaSharp.dll",
        "launcher/tests/bin/Release/SkiaSharp.dll",
        "launcher/tests/bin/Release/Svg.Animation.dll",
        "launcher/tests/bin/Release/Svg.Custom.dll",
        "launcher/tests/bin/Release/Svg.Model.dll",
        "launcher/tests/bin/Release/Svg.SceneGraph.dll",
        "launcher/tests/bin/Release/Svg.Skia.dll",
        "launcher/tests/bin/Release/runtimes/win-arm64/native/libHarfBuzzSharp.dll",
        "launcher/tests/bin/Release/runtimes/win-arm64/native/libSkiaSharp.dll",
        "launcher/tests/bin/Release/runtimes/win-x64/native/libHarfBuzzSharp.dll",
        "launcher/tests/bin/Release/runtimes/win-x64/native/libSkiaSharp.dll",
        "launcher/tests/bin/Release/runtimes/win-x86/native/libHarfBuzzSharp.dll",
        "launcher/tests/bin/Release/runtimes/win-x86/native/libSkiaSharp.dll"
    ];

    [Fact]
    [Trait("Category", "PlayerInfoB005QualificationContract")]
    public void B0_05_NormalSuiteContract_QualificationOptInIsAbsent()
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

    [B005QualificationFact]
    [Trait("Category", "PlayerInfoB005Qualification")]
    public async Task B0_05_SyntheticFixedBoundsRuntimeQualification()
    {
        string? reportPath = Environment.GetEnvironmentVariable(
            ReportPathEnvironment);
        string? runId = Environment.GetEnvironmentVariable(
            RunIdEnvironment);
        string? projectRoot = Environment.GetEnvironmentVariable(
            ProjectRootEnvironment);
        Assert.False(
            string.IsNullOrWhiteSpace(reportPath),
            $"{ReportPathEnvironment} is required by the dedicated runner.");
        Assert.False(
            string.IsNullOrWhiteSpace(runId),
            $"{RunIdEnvironment} is required by the dedicated runner.");
        Assert.False(
            string.IsNullOrWhiteSpace(projectRoot),
            $"{ProjectRootEnvironment} is required by the dedicated runner.");

        reportPath = Path.GetFullPath(reportPath);
        projectRoot = Path.GetFullPath(projectRoot);
        var reportWritten = false;
        try
        {
            QualificationOutcome outcome =
                await ExecuteQualificationAsync(runId, projectRoot);
            WriteReportWithoutBom(reportPath, outcome.Report);
            reportWritten = true;

            Assert.True(
                outcome.Failures.Count == 0,
                "B0-05 qualification gates failed: " +
                string.Join("; ", outcome.Failures));
        }
        catch (Exception exception) when (!reportWritten)
        {
            WriteReportWithoutBom(
                reportPath,
                new
                {
                    schema = ReportSchema,
                    runId,
                    status = "failed",
                    measurementKind = MeasurementKind,
                    decision = GeometryConclusion,
                    recordedDecision = RecordedTopologyDecision,
                    gates = new[]
                    {
                        new QualificationGate(
                            "qualification_exception",
                            "runner",
                            false,
                            exception.GetType().FullName,
                            "no exception",
                            "equals",
                            "exception",
                            exception.Message)
                    },
                    failures = new[]
                    {
                        "qualification_exception: " +
                        exception.GetType().Name + ": " + exception.Message
                    },
                    failure = new
                    {
                        type = exception.GetType().FullName,
                        exception.Message
                    },
                    unverified = UnverifiedClaims
                });
            throw;
        }
    }

    private static async Task<QualificationOutcome> ExecuteQualificationAsync(
        string runId,
        string projectRoot)
    {
        var gates = new List<QualificationGate>();
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
        bool performanceEnvironmentPassed =
            inheritedPerformanceOverrides.Values.All(
                value => value is null) &&
            string.Equals(
                processPriorityClass,
                ProcessPriorityClass.Normal.ToString(),
                StringComparison.Ordinal) &&
            string.Equals(
                expectedPriorityClass,
                ProcessPriorityClass.Normal.ToString(),
                StringComparison.Ordinal) &&
            !string.IsNullOrEmpty(expectedAffinityMask) &&
            string.Equals(
                processorAffinityMask,
                expectedAffinityMask,
                StringComparison.Ordinal) &&
            !serverGc;
        AddExactGate(
            gates,
            "runtime_performance_environment",
            "runtime",
            performanceEnvironmentPassed,
            new
            {
                inheritedPerformanceOverrides,
                processPriorityClass,
                processorAffinityMask,
                serverGc
            },
            new
            {
                inheritedPerformanceOverrides =
                    PerformanceOverrideEnvironmentNames.ToDictionary(
                        name => name,
                        _ => (string?)null,
                        StringComparer.Ordinal),
                processPriorityClass = expectedPriorityClass,
                processorAffinityMask = expectedAffinityMask,
                serverGc = false
            },
            "environment_and_process_state",
            "Formal B0-05 timing requires absent frozen JIT/GC overrides, Normal priority, and the runner-inherited affinity mask.");
        PlayerInfoSvgAssetSet assetSet =
            PlayerInfoSvgAssetContract.LoadProductionEmbedded(
                minimumRaster: false);
        ViewportCase[] viewportCases = CreateViewportCases();
        PlayerInfoRasterPlan[] plans = viewportCases
            .Select(viewportCase => PlayerInfoRasterPlanner.Create(
                assetSet,
                viewportCase.ContentViewport,
                viewportCase.MonitorDpiScale))
            .ToArray();

        ValidateViewportContracts(viewportCases, plans, assetSet, gates);

        var productionRasterizer = new PlayerInfoSvgRasterizer();
        // Exercise the exact background path used by the acceptance samples.
        // Fixed round-robin rounds let tiered JIT/native paths settle without
        // adaptively warming to the threshold. Every excluded timing remains
        // in the report for independent review.
        List<TimedSample> warmedFreshExcludedWarmupSamples =
            await MeasureFreshBakesAsync(
                productionRasterizer,
                viewportCases,
                plans,
                WarmedFreshExcludedWarmupRounds,
                "excluded_warmup");
        TimingSummary warmedFreshExcludedWarmupOverall = Summarize(
            warmedFreshExcludedWarmupSamples.Select(
                sample => sample.Milliseconds));
        ViewportTiming[] warmedFreshExcludedWarmupByViewport = viewportCases
            .Select(viewportCase => new ViewportTiming(
                viewportCase.Id,
                Summarize(warmedFreshExcludedWarmupSamples
                    .Where(sample => sample.Scenario == viewportCase.Id)
                    .Select(sample => sample.Milliseconds))))
            .ToArray();
        ForceManagedCleanup();
        ProcessMetrics processBefore = CaptureProcessMetrics();

        List<TimedSample> warmedFreshBakeSamples =
            await MeasureFreshBakesAsync(
                productionRasterizer,
                viewportCases,
                plans,
                WarmedFreshSamplesPerViewport,
                "warmed_fresh");
        TimingSummary warmedFreshBakeOverall = Summarize(
            warmedFreshBakeSamples.Select(sample => sample.Milliseconds));
        ViewportTiming[] warmedFreshBakeByViewport = viewportCases
            .Select(viewportCase => new ViewportTiming(
                viewportCase.Id,
                Summarize(warmedFreshBakeSamples
                    .Where(sample => sample.Scenario == viewportCase.Id)
                    .Select(sample => sample.Milliseconds))))
            .ToArray();

        List<TimedSample> copySamples =
            MeasurePArgbCopies(viewportCases, plans);
        TimingSummary copyTiming = Summarize(
            copySamples.Select(sample => sample.Milliseconds));

        var pipeline = new PlayerInfoRasterPipeline(
            new PlayerInfoSvgRasterizer());
        var uiRequestSamples = new List<TimedSample>(
            plans.Length * 2 + PendingCoalescingRequestCount +
            SteadyRequestCount);
        var coldQueueRequestSamples = new List<TimedSample>(plans.Length);
        var pipelineColdSamples = new List<TimedSample>(plans.Length);
        var warmLookupSamples = new List<TimedSample>(plans.Length);
        var pendingCoalescingSamples =
            new List<TimedSample>(PendingCoalescingRequestCount);
        var steadySamples = new List<TimedSample>(SteadyRequestCount);
        var layerActivity = assetSet.Assets.ToDictionary(
            asset => asset.Id,
            asset => new MutableLayerActivity(asset.Id),
            StringComparer.Ordinal);
        long peakCacheBytes = 0;
        PlayerInfoRasterPipelineSnapshot afterCold = default;
        PlayerInfoRasterPipelineSnapshot afterWarm = default;
        PlayerInfoRasterPipelineSnapshot afterPendingCoalescing = default;
        PlayerInfoRasterPipelineSnapshot beforeSteady = default;
        PlayerInfoRasterPipelineSnapshot afterSteady = default;
        PlayerInfoRasterPipelineSnapshot afterDispose = default;
        var coldQueuedCount = 0;
        var warmCacheHitCount = 0;
        var steadyCurrentHitCount = 0;
        PlayerInfoRasterPlan? finalPendingPlan = null;

        try
        {
            for (var index = 0; index < plans.Length; index++)
            {
                long coldStarted = Stopwatch.GetTimestamp();
                RequestMeasurement request = MeasureRequest(
                    pipeline,
                    plans[index],
                    "cold_queue",
                    viewportCases[index].Id,
                    layerActivity);
                uiRequestSamples.Add(request.Sample);
                coldQueueRequestSamples.Add(request.Sample);
                if (request.Result == PlayerInfoRasterRequestResult.Queued)
                {
                    coldQueuedCount++;
                }
                await WaitForIdleAsync(pipeline);
                pipelineColdSamples.Add(new TimedSample(
                    "pipeline_cold_publish",
                    viewportCases[index].Id,
                    ElapsedMilliseconds(coldStarted)));
                ObservePeakCache(pipeline, ref peakCacheBytes);
            }
            afterCold = pipeline.Snapshot;

            // The four complete batches fit in the 16 MiB budget. Walking the
            // same four keys now must exercise whole-batch inactive-cache swaps.
            for (var index = 0; index < plans.Length; index++)
            {
                RequestMeasurement request = MeasureRequest(
                    pipeline,
                    plans[index],
                    "warm_cache_lookup",
                    viewportCases[index].Id,
                    layerActivity);
                uiRequestSamples.Add(request.Sample);
                warmLookupSamples.Add(request.Sample);
                if (request.Result == PlayerInfoRasterRequestResult.CacheHit)
                {
                    warmCacheHitCount++;
                }
                else
                {
                    await WaitForIdleAsync(pipeline);
                }
                ObservePeakCache(pipeline, ref peakCacheBytes);
            }
            afterWarm = pipeline.Snapshot;

            PlayerInfoRasterPlan[] pendingPlans = Enumerable
                .Range(0, PendingCoalescingRequestCount)
                .Select(index =>
                {
                    int height = 721 + index;
                    int width = checked((int)Math.Round(
                        height * (1024d / 576d),
                        MidpointRounding.AwayFromZero));
                    float dpi = new[] { 1.00f, 1.25f, 1.50f, 1.75f }[
                        index % 4];
                    return PlayerInfoRasterPlanner.Create(
                        assetSet,
                        new Rectangle(0, 0, width, height),
                        dpi);
                })
                .ToArray();

            for (var index = 0; index < pendingPlans.Length; index++)
            {
                RequestMeasurement request = MeasureRequest(
                    pipeline,
                    pendingPlans[index],
                    "pending_coalescing",
                    $"pending_{index + 1:000}",
                    layerActivity);
                uiRequestSamples.Add(request.Sample);
                pendingCoalescingSamples.Add(request.Sample);
            }
            await WaitForIdleAsync(pipeline);
            ObservePeakCache(pipeline, ref peakCacheBytes);
            afterPendingCoalescing = pipeline.Snapshot;
            finalPendingPlan = pendingPlans[^1];

            PlayerInfoRasterPlan steadyPlan = pendingPlans[^1];
            beforeSteady = pipeline.Snapshot;
            for (var tick = 0; tick < SteadyRequestCount; tick++)
            {
                RequestMeasurement request = MeasureRequest(
                    pipeline,
                    steadyPlan,
                    "steady_current_hit",
                    $"tick_{tick + 1:0000}",
                    layerActivity);
                uiRequestSamples.Add(request.Sample);
                steadySamples.Add(request.Sample);
                if (request.Result == PlayerInfoRasterRequestResult.CurrentHit)
                {
                    steadyCurrentHitCount++;
                }
            }
            afterSteady = pipeline.Snapshot;
            ObservePeakCache(pipeline, ref peakCacheBytes);
        }
        finally
        {
            pipeline.Dispose();
            afterDispose = pipeline.Snapshot;
        }

        ForceManagedCleanup();
        ProcessMetrics processAfter = CaptureProcessMetrics();

        TimingSummary uiRequest = Summarize(
            uiRequestSamples.Select(sample => sample.Milliseconds));
        TimingSummary coldQueueRequest = Summarize(
            coldQueueRequestSamples.Select(sample => sample.Milliseconds));
        TimingSummary pipelineCold = Summarize(
            pipelineColdSamples.Select(sample => sample.Milliseconds));
        TimingSummary warmLookup = Summarize(
            warmLookupSamples.Select(sample => sample.Milliseconds));
        TimingSummary pendingCoalescing = Summarize(
            pendingCoalescingSamples.Select(sample => sample.Milliseconds));
        TimingSummary steady = Summarize(
            steadySamples.Select(sample => sample.Milliseconds));

        long steadyParseDelta =
            afterSteady.ParseCount - beforeSteady.ParseCount;
        long steadyRasterDelta =
            afterSteady.RasterCount - beforeSteady.RasterCount;
        long steadyPublishDelta =
            afterSteady.PublishCount - beforeSteady.PublishCount;

        AddExactGate(
            gates,
            "cold_queue_result",
            "pipeline_request",
            coldQueuedCount == plans.Length,
            coldQueuedCount,
            plans.Length,
            "request",
            "Every first-size request must queue a fresh bake.");
        AddExactGate(
            gates,
            "warm_inactive_cache_result",
            "pipeline_request",
            warmCacheHitCount == plans.Length,
            warmCacheHitCount,
            plans.Length,
            "request",
            "Every warmed viewport must swap an inactive whole-batch cache entry.");
        AddExactGate(
            gates,
            "steady_current_hit_result",
            "pipeline_request",
            steadyCurrentHitCount == SteadyRequestCount,
            steadyCurrentHitCount,
            SteadyRequestCount,
            "request",
            "All steady requests must use the current batch.");

        AddUpperBoundGate(
            gates,
            "ui_request_cold_queue_p95",
            "ui_request_cold_queue",
            coldQueueRequest.P95,
            UiRequestP95LimitMs,
            "ms");
        AddUpperBoundGate(
            gates,
            "ui_request_warm_cache_p95",
            "ui_request_warm_cache",
            warmLookup.P95,
            UiRequestP95LimitMs,
            "ms");
        AddUpperBoundGate(
            gates,
            "ui_request_pending_coalescing_p95",
            "ui_request_pending_coalescing",
            pendingCoalescing.P95,
            UiRequestP95LimitMs,
            "ms");
        AddUpperBoundGate(
            gates,
            "ui_request_steady_current_hit_p95",
            "ui_request_steady",
            steady.P95,
            UiRequestP95LimitMs,
            "ms");
        foreach (ViewportTiming viewportTiming in
                 warmedFreshBakeByViewport)
        {
            AddUpperBoundGate(
                gates,
                "warmed_fresh_bake_p95_" + viewportTiming.ViewportId,
                "warmed_fresh_bake",
                viewportTiming.Summary.P95,
                WarmedFreshBakeP95LimitMs,
                "ms",
                $"Per-viewport nearest-rank p95 from " +
                $"{viewportTiming.Summary.Count} fresh bakes; max is diagnostic.");
        }
        AddUpperBoundGate(
            gates,
            "warm_cache_lookup_p95",
            "warm_cache_lookup",
            warmLookup.P95,
            WarmLookupP95LimitMs,
            "ms");
        AddUpperBoundGate(
            gates,
            "cache_budget",
            "cache",
            Math.Max(peakCacheBytes, afterSteady.CacheBytes),
            pipeline.MaxCacheBytes,
            "bytes");
        AddExactGate(
            gates,
            "steady_3000_zero_parse_raster_publish",
            "steady",
            steadyParseDelta == 0 &&
            steadyRasterDelta == 0 &&
            steadyPublishDelta == 0,
            new
            {
                parseDelta = steadyParseDelta,
                rasterDelta = steadyRasterDelta,
                publishDelta = steadyPublishDelta
            },
            new
            {
                parseDelta = 0,
                rasterDelta = 0,
                publishDelta = 0
            },
            "layer_or_batch_count",
            "Steady current-key requests must not parse, rasterize, or publish.");
        AddExactGate(
            gates,
            "single_worker",
            "pipeline_lifecycle",
            afterSteady.MaxConcurrentWorkers == 1,
            afterSteady.MaxConcurrentWorkers,
            1,
            "worker",
            "The raster pipeline must serialize all bake work.");
        AddExactGate(
            gates,
            "fault_free",
            "pipeline_lifecycle",
            afterSteady.FaultCount == 0,
            new
            {
                afterSteady.FaultCount,
                afterSteady.LastFault
            },
            new
            {
                faultCount = 0,
                lastFault = (string?)null
            },
            "fault",
            "No raster pipeline fault is permitted.");
        AddExactGate(
            gates,
            "pending_coalescing_latest_wins",
            "pending_coalescing",
            finalPendingPlan is not null &&
            string.Equals(
                afterPendingCoalescing.CurrentBatchKey,
                finalPendingPlan.BatchKey,
                StringComparison.Ordinal),
            afterPendingCoalescing.CurrentBatchKey,
            finalPendingPlan?.BatchKey,
            "batch_key",
            "The 100 rapidly replaced pending requests must publish the latest key.");

        bool lifecycleDisposed =
            afterDispose.DisposedBatchCount > 0 &&
            afterDispose.DisposedLayerCount ==
                afterDispose.DisposedBatchCount *
                PlayerInfoSvgAssetCatalog.ExpectedAssetCount &&
            afterDispose.CacheBytes == 0 &&
            afterDispose.CacheCount == 0 &&
            afterDispose.ActiveWorkers == 0 &&
            afterDispose.DesiredBatchKey is null &&
            afterDispose.CurrentBatchKey is null;
        AddExactGate(
            gates,
            "pipeline_dispose_returns_to_zero",
            "pipeline_lifecycle",
            lifecycleDisposed,
            new
            {
                afterDispose.DisposedBatchCount,
                afterDispose.DisposedLayerCount,
                afterDispose.CacheBytes,
                afterDispose.CacheCount,
                afterDispose.ActiveWorkers,
                afterDispose.DesiredBatchKey,
                afterDispose.CurrentBatchKey
            },
            new
            {
                disposedBatchCountGreaterThan = 0,
                disposedLayerMultiplier =
                    PlayerInfoSvgAssetCatalog.ExpectedAssetCount,
                cacheBytes = 0,
                cacheCount = 0,
                activeWorkers = 0,
                desiredBatchKey = (string?)null,
                currentBatchKey = (string?)null
            },
            "lifecycle_state",
            "Dispose must release every pipeline-owned atomic batch and clear all live state.");

        foreach (MutableLayerActivity activity in layerActivity.Values)
        {
            // Every pipeline-owned batch is contractually an atomic 8-layer
            // batch. This per-layer value is inferred from the real aggregate
            // disposal counters; it is not a separate per-ID dispose callback.
            activity.InferredBatchDisposalCount =
                afterDispose.DisposedBatchCount;
        }

        NativeHudTopologyProbeResult fullTopology;
        NativeHudTopologyProbeResult tightTopology;
        Rectangle topologyViewport = new(0, 0, 1024, 576);
        Rectangle rightTop = RightHudLayout.TopToolsRectFromViewport(
            topologyViewport,
            RightHudLayout.ScaleForViewport(topologyViewport));
        Rectangle fullPlayerInfo = new(0, 512, 1024, 64);
        Rectangle rawLayerEnvelope = plans[0].Layers
            .Select(layer => layer.PhysicalBounds)
            .Aggregate(Rectangle.Union);
        Rectangle tightPlayerInfo = Rectangle.Intersect(
            rawLayerEnvelope,
            plans[0].FlashViewportPhysical);
        fullTopology = NativeHudTopologyProbe.Capture(
            topologyViewport,
            new[] { rightTop, fullPlayerInfo },
            NativeHudTopologyProbe.DefaultInflatePixels,
            NativeHudTopologyDecision.SplitRequired);
        tightTopology = NativeHudTopologyProbe.Capture(
            topologyViewport,
            new[] { rightTop, tightPlayerInfo },
            NativeHudTopologyProbe.DefaultInflatePixels,
            NativeHudTopologyDecision.SplitRequired);

        bool fullTopologyGeometry =
            rightTop == new Rectangle(724, 0, 252, 32) &&
            fullPlayerInfo == new Rectangle(0, 512, 1024, 64) &&
            fullTopology.RawOuterUnion ==
                new Rectangle(0, 0, 1024, 576) &&
            fullTopology.InflatedOuterUnion ==
                new Rectangle(-6, -6, 1036, 588) &&
            fullTopology.ClippedSurface ==
                new Rectangle(0, 0, 1024, 576) &&
            fullTopology.Components == 2 &&
            fullTopology.FullViewportBridge &&
            fullTopology.NearFullBridge &&
            fullTopology.RequiresDecision;
        bool tightTopologyGeometry =
            rawLayerEnvelope == new Rectangle(-3, 474, 285, 81) &&
            tightPlayerInfo == new Rectangle(0, 474, 282, 81) &&
            tightTopology.RawOuterUnion ==
                new Rectangle(0, 0, 976, 555) &&
            tightTopology.InflatedOuterUnion ==
                new Rectangle(-6, -6, 988, 567) &&
            tightTopology.ClippedSurface ==
                new Rectangle(0, 0, 982, 561) &&
            tightTopology.Components == 2 &&
            !tightTopology.FullViewportBridge &&
            tightTopology.NearFullBridge &&
            tightTopology.RequiresDecision;
        AddExactGate(
            gates,
            "topology_full_stage_exact_geometry",
            "topology",
            fullTopologyGeometry,
            new
            {
                rightTop = Rect(rightTop),
                playerInfo = Rect(fullPlayerInfo),
                probe = Topology(fullTopology)
            },
            "frozen B0-01A full-stage geometry; near/full bridge; requires decision",
            "geometry",
            "The inference comes from geometry, not from the caller-recorded decision.");
        AddExactGate(
            gates,
            "topology_viewport_clipped_canonical_exact_geometry",
            "topology",
            tightTopologyGeometry,
            new
            {
                rawLayerEnvelope = Rect(rawLayerEnvelope),
                viewportClippedEnvelope = Rect(tightPlayerInfo),
                probe = Topology(tightTopology)
            },
            "B0-04 manifest layer envelope clipped to the main Flash viewport; near bridge; requires decision",
            "geometry",
            "282x81 preserves the main-RSL sprite above its 1024x64 authoring stage; this remains a geometry result, not a visual-parity claim.");

        SourceClosure sourceClosure = CaptureSourceClosure(projectRoot);
        TestAssemblyIdentity testAssembly =
            CaptureTestAssemblyIdentity(projectRoot);
        ExecutionBinaryEvidence executionEvidence =
            CaptureExecutionBinaryEvidence(projectRoot);
        IReadOnlyList<ExecutionBinaryIdentity> executionBinaries =
            executionEvidence.ResolvedTargetBinaries;
        AddExactGate(
            gates,
            "source_closure_bound",
            "evidence_identity",
            sourceClosure.Files.Count == ExpectedClosurePaths.Length &&
            sourceClosure.AggregateSha256.Length == 64,
            new
            {
                fileCount = sourceClosure.Files.Count,
                sourceClosure.AggregateSha256,
                sourceClosure.RepositoryDirty,
                sourceClosure.ClosureDirty
            },
            new
            {
                fileCount = ExpectedClosurePaths.Length,
                aggregateSha256Length = 64
            },
            "closure",
            "Worktree bytes plus HEAD/index/status are frozen; dirty state is explicit.");
        AddExactGate(
            gates,
            "test_assembly_bound",
            "evidence_identity",
            testAssembly.Size > 0 &&
            testAssembly.Sha256.Length == 64,
            new
            {
                testAssembly.RelativePath,
                testAssembly.Size,
                testAssembly.Sha256
            },
            "non-empty Launcher.Tests.dll with SHA-256",
            "assembly",
            "The executing test assembly is bound independently of source bytes.");
        string[] actualExecutionBinaryNames = executionBinaries
            .Select(binary => binary.Name)
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        string[] expectedExecutionBinaryNames = ExpectedExecutionBinaries
            .Select(binary => binary.Name)
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        AddExactGate(
            gates,
            "execution_binaries_bound",
            "evidence_identity",
            executionBinaries.Count == ExpectedExecutionBinaries.Length &&
            actualExecutionBinaryNames.SequenceEqual(
                expectedExecutionBinaryNames,
                StringComparer.Ordinal) &&
            executionEvidence.RendererTargetClosurePaths.SequenceEqual(
                ExpectedExecutionBinaries
                    .Where(binary => !string.Equals(
                        binary.Name,
                        "core",
                        StringComparison.Ordinal))
                    .Select(binary => binary.RelativePath)
                    .OrderBy(path => path, StringComparer.Ordinal),
                StringComparer.Ordinal) &&
            executionEvidence.RendererOutputClosurePaths.SequenceEqual(
                ExpectedRendererOutputClosurePaths,
                StringComparer.Ordinal) &&
            executionEvidence.UnexpectedLoadedRendererPaths.Count == 0 &&
            new[]
            {
                "core",
                "skia_sharp",
                "skia_sharp_native_win_x64",
                "svg_skia"
            }.All(requiredName =>
                executionBinaries.Any(binary =>
                    string.Equals(
                        binary.Name,
                        requiredName,
                        StringComparison.Ordinal) &&
                    binary.Loaded)) &&
            executionBinaries.All(binary =>
                binary.Size > 0 &&
                binary.Sha256.Length == 64 &&
                ExpectedExecutionBinaries.Any(expected =>
                    string.Equals(
                        expected.Name,
                        binary.Name,
                        StringComparison.Ordinal) &&
                    string.Equals(
                        expected.Kind,
                        binary.Kind,
                        StringComparison.Ordinal) &&
                    string.Equals(
                        expected.RelativePath,
                        binary.RelativePath,
                        StringComparison.OrdinalIgnoreCase))),
            new
            {
                resolvedTargetBinaries = executionBinaries,
                executionEvidence.LoadedExecutionBinaries,
                executionEvidence.RendererTargetClosurePaths,
                executionEvidence.RendererOutputClosurePaths,
                executionEvidence.UnexpectedLoadedRendererPaths
            },
            new
            {
                binaries = ExpectedExecutionBinaries,
                requiredLoaded =
                    new[]
                    {
                        "core",
                        "skia_sharp",
                        "skia_sharp_native_win_x64",
                        "svg_skia"
                    },
                rendererTargetFileCount =
                    ExpectedExecutionBinaries.Length - 1,
                rendererOutputFileCount =
                    ExpectedRendererOutputClosurePaths.Length,
                unexpectedLoadedRendererPathCount = 0,
                each = "non-empty exact target file with SHA-256"
            },
            "binary_closure",
            "The Core plus exact win-x64 11-file renderer target closure is bound; actual loaded files are enumerated separately, so unresolved dependencies are not called executed.");

        QualificationGate[] frozenGates = gates.ToArray();
        string[] failures = frozenGates
            .Where(gate => !gate.Passed)
            .Select(gate => $"{gate.Id}: {gate.Detail}")
            .ToArray();

        object report = new
        {
            schema = ReportSchema,
            runId,
            status = failures.Length == 0 ? "passed" : "failed",
            measurementKind = MeasurementKind,
            decision = GeometryConclusion,
            recordedDecision = RecordedTopologyDecision,
            generatedAtUtc = DateTimeOffset.UtcNow,
            scope = new
            {
                productionWidgetRegistered = false,
                actualLayeredWindowCommitInvoked = false,
                fixtureBoundsSource =
                    "B0-01A main-stage ty=512 and B0-04 typed manifest",
                conclusion = "B0-05 structural raster/cache/topology preflight only"
            },
            machine = new
            {
                Environment.MachineName,
                osVersion = Environment.OSVersion.VersionString,
                RuntimeInformation.OSDescription,
                RuntimeInformation.OSArchitecture,
                logicalProcessorCount = Environment.ProcessorCount
            },
            runtime = new
            {
                RuntimeInformation.FrameworkDescription,
                RuntimeInformation.RuntimeIdentifier,
                RuntimeInformation.ProcessArchitecture,
                environmentVersion = Environment.Version.ToString(),
                qualificationSdkVersion =
                    Environment.GetEnvironmentVariable(SdkVersionEnvironment),
                is64BitProcess = Environment.Is64BitProcess,
                serverGc,
                performanceEnvironment = new
                {
                    inheritedOverrides = inheritedPerformanceOverrides,
                    processPriorityClass,
                    processorAffinityMask,
                    expectedProcessPriorityClass = expectedPriorityClass,
                    expectedProcessorAffinityMask = expectedAffinityMask
                }
            },
            sourceClosure,
            testAssembly,
            executionBinaries,
            loadedExecutionBinaries =
                executionEvidence.LoadedExecutionBinaries,
            rendererTargetClosurePaths =
                executionEvidence.RendererTargetClosurePaths,
            rendererOutputClosurePaths =
                executionEvidence.RendererOutputClosurePaths,
            unexpectedLoadedRendererPaths =
                executionEvidence.UnexpectedLoadedRendererPaths,
            dpiAwareness = new
            {
                effective = GetEffectiveDpiAwareness(),
                processBootstrapInvokedByQualification = false,
                viewportCoordinates = "physical_pixels",
                monitorDpiScaleRole = "diagnostic_only",
                appliedToRasterScale = false
            },
            asset = new
            {
                assetSetId = assetSet.AssetSetId,
                assetSetRevision = assetSet.Revision,
                exactManifestSha256 = assetSet.ExactManifestSha256,
                assetSet.RasterContractVersion,
                assetCount = assetSet.Assets.Count,
                manifestBytes = assetSet.ManifestBytes.Length,
                assets = assetSet.Assets.Select(asset => new
                {
                    asset.Id,
                    asset.RelativePath,
                    asset.Sha256,
                    byteCount = asset.Bytes.Length,
                    viewBox = SvgRect(asset.ViewBox),
                    registration = new
                    {
                        asset.Registration.X,
                        asset.Registration.Y
                    },
                    asset.Cacheable
                }).ToArray()
            },
            renderer = new
            {
                assetSet.RendererIdentity.Package,
                assetSet.RendererIdentity.Version,
                assetSet.RendererIdentity.SkiaSharpVersion,
                assetSet.RendererIdentity.FeatureSet,
                assetSet.RendererIdentity.ColorType,
                assetSet.RendererIdentity.AlphaType,
                assetSet.RendererIdentity.CacheIdentity
            },
            visualMatrix = viewportCases.Zip(plans).Select(pair => new
            {
                id = pair.First.Id,
                hostViewport = Rect(pair.First.HostViewport),
                contentViewport = Rect(pair.First.ContentViewport),
                pair.First.MonitorDpiScale,
                pair.Second.PhysicalScale,
                stagePhysicalBounds = Rect(pair.Second.StagePhysicalBounds),
                tightPhysicalBounds = Rect(pair.Second.TightPhysicalBounds),
                letterbox = new
                {
                    present =
                        pair.First.HostViewport != pair.First.ContentViewport,
                    topPixels =
                        pair.First.ContentViewport.Top -
                        pair.First.HostViewport.Top,
                    bottomPixels =
                        pair.First.HostViewport.Bottom -
                        pair.First.ContentViewport.Bottom
                },
                batchKey = pair.Second.BatchKey,
                layers = pair.Second.Layers.Select(layer => new
                {
                    layerId = layer.Key.LayerId,
                    layer.PixelWidth,
                    layer.PixelHeight,
                    physicalBounds = Rect(layer.PhysicalBounds),
                    key = new
                    {
                        layer.Key.AssetSetRevision,
                        layer.Key.ExactManifestSha256,
                        layer.Key.LayerId,
                        layer.Key.PixelWidth,
                        layer.Key.PixelHeight,
                        layer.Key.SourceToBitmapIdentity,
                        layer.Key.RendererIdentity,
                        layer.Key.RasterContractVersion
                    }
                }).ToArray()
            }).ToArray(),
            timings = new
            {
                quantileMethod = "nearest_rank",
                uiRequest = new
                {
                    combinedSummaryDiagnosticOnly = uiRequest,
                    thresholdP95Ms = UiRequestP95LimitMs,
                    sampleCount = uiRequestSamples.Count,
                    coldQueue = new
                    {
                        summary = coldQueueRequest,
                        samples = coldQueueRequestSamples
                    },
                    warmInactiveCache = new
                    {
                        summary = warmLookup,
                        samples = warmLookupSamples
                    },
                    pendingCoalescing = new
                    {
                        summary = pendingCoalescing,
                        samples = pendingCoalescingSamples
                    },
                    steadyCurrentHit = new
                    {
                        summary = steady,
                        sampleCount = steadySamples.Count,
                        canonicalSamplesPath =
                            "timings.steadyCurrentHit3000.samples"
                    }
                },
                warmedFreshBake = new
                {
                    execution =
                        "16 fixed excluded round-robin background warmup rounds, then 20 independent round-robin acceptance rounds; every operation performs a fresh SVG parse+raster+PArgb batch",
                    sampleSemantics =
                        "warmed process; fresh asset work; not process-cold",
                    excludedWarmup = new
                    {
                        execution =
                            "same Task.Run background path as acceptance; fixed count; no adaptive threshold stop",
                        rounds = WarmedFreshExcludedWarmupRounds,
                        samplesPerViewport =
                            WarmedFreshExcludedWarmupRounds,
                        sampleCount =
                            warmedFreshExcludedWarmupSamples.Count,
                        overallSummaryDiagnosticOnly =
                            warmedFreshExcludedWarmupOverall,
                        byViewport =
                            warmedFreshExcludedWarmupByViewport,
                        samples =
                            warmedFreshExcludedWarmupSamples
                    },
                    overallSummaryDiagnosticOnly = warmedFreshBakeOverall,
                    byViewport = warmedFreshBakeByViewport,
                    thresholdP95Ms = WarmedFreshBakeP95LimitMs,
                    samplesPerViewport = WarmedFreshSamplesPerViewport,
                    samples = warmedFreshBakeSamples
                },
                pipelineColdPublish = new
                {
                    execution = "Request through background pipeline to publish",
                    summary = pipelineCold,
                    samples = pipelineColdSamples
                },
                pArgbCopy = new
                {
                    execution =
                        "one representative synthetic Bgra8888/Premul copy per logical layer at exact layer dimensions; mp.fill fragments excluded",
                    summary = copyTiming,
                    samples = copySamples
                },
                warmCacheLookup = new
                {
                    execution = "whole inactive-batch cache swap",
                    summary = warmLookup,
                    thresholdP95Ms = WarmLookupP95LimitMs,
                    samples = warmLookupSamples
                },
                pendingCoalescing100 = new
                {
                    meaning =
                        "100 rapidly replaced viewport/DPI requests; latest pending work wins, not 100 completed bakes",
                    summary = pendingCoalescing,
                    samples = pendingCoalescingSamples
                },
                steadyCurrentHit3000 = new
                {
                    summary = steady,
                    sampleCount = steadySamples.Count,
                    samples = steadySamples
                }
            },
            raster = new
            {
                assetCount = assetSet.Assets.Count,
                logicalLayerCount = plans[0].Layers.Count,
                ownedPArgbPayloadsPerBatch =
                    plans[0].Layers.Sum(OwnedPArgbPayloadCount),
                outputContract = "System.Drawing.Format32bppPArgb",
                parseRasterCounterUnit =
                    "completed StrictSvg parse / Skia raster operation for an intended payload slot; PArgb copy completion is not separately counted; mp.fill fragment XDocument parse is outside parseCount",
                pipelineCounters = new
                {
                    afterCold = Snapshot(afterCold),
                    afterWarm = Snapshot(afterWarm),
                    afterPendingCoalescing =
                        Snapshot(afterPendingCoalescing),
                    beforeSteady = Snapshot(beforeSteady),
                    afterSteady = Snapshot(afterSteady),
                    afterDispose = Snapshot(afterDispose)
                },
                layerActivity = layerActivity.Values
                    .OrderBy(activity => activity.LayerId, StringComparer.Ordinal)
                    .Select(activity => new
                    {
                        activity.LayerId,
                        activity.DesiredGenerationCount,
                        activity.CurrentHitCount,
                        activity.InactiveCacheHitCount,
                        activity.InferredBatchDisposalCount
                    })
                    .ToArray(),
                steady3000 = new
                {
                    requestCount = SteadyRequestCount,
                    parseDelta = steadyParseDelta,
                    rasterDelta = steadyRasterDelta,
                    publishDelta = steadyPublishDelta
                }
            },
            cache = new
            {
                budgetBytes = pipeline.MaxCacheBytes,
                peakBytes = peakCacheBytes,
                finalLiveBytesBeforeDispose = afterSteady.CacheBytes,
                finalLiveBatchCountBeforeDispose = afterSteady.CacheCount,
                bytesAfterDispose = afterDispose.CacheBytes,
                batchesAfterDispose = afterDispose.CacheCount,
                inactiveBatchHitCount = afterSteady.CacheHitCount,
                inactiveLayerHitCount = afterSteady.CacheLayerHitCount,
                currentLayerHitCount = afterSteady.CurrentLayerHitCount
            },
            lifecycle = new
            {
                generation = afterDispose.Generation,
                afterSteady.PendingReplacementCount,
                afterSteady.CancelCount,
                afterSteady.StaleDiscardCount,
                afterSteady.FaultCount,
                afterSteady.LastFault,
                afterDispose.DisposedBatchCount,
                afterDispose.DisposedLayerCount,
                ownership = "atomic private eight-layer batch"
            },
            processDiagnostics = new
            {
                before = processBefore,
                after = processAfter,
                delta = ProcessMetrics.Delta(processBefore, processAfter),
                gdiEndpointInterpretation =
                    "endpoint delta only; diagnostic, not a repeated-draw trend gate",
                handleAndMemoryInterpretation =
                    "diagnostic only; lifecycle zero-state is the hard ownership gate"
            },
            topology = new
            {
                geometryConclusion = GeometryConclusion,
                recordedDecision = RecordedTopologyDecision,
                measurementKind = MeasurementKind,
                inflatePixels = NativeHudTopologyProbe.DefaultInflatePixels,
                viewport = Rect(topologyViewport),
                productionRightTopFixedBounds = Rect(rightTop),
                rawCanonicalLayerEnvelope = Rect(rawLayerEnvelope),
                viewportClippedCanonicalEnvelope = Rect(tightPlayerInfo),
                fullStage = Topology(fullTopology),
                viewportClippedCanonicalEnvelopeProbe =
                    Topology(tightTopology),
                actualUpdateLayeredWindowMeasured = false
            },
            gates = frozenGates,
            failures,
            verified = new[]
            {
                "production embedded asset and renderer identity loaded",
                "four physical content viewports planned without DPI double multiplication",
                "static layers parsed, rasterized and copied to PArgb",
                "single-worker latest-wins cache pipeline exercised",
                "3000 current-key requests caused zero parse/raster/publish",
                "fixed-bounds full/main-viewport-clipped geometry requires an explicit topology decision",
                "recorded B0-05 topology decision is split_required"
            },
            unverified = UnverifiedClaims
        };

        return new QualificationOutcome(report, failures);
    }

    private static readonly string[] UnverifiedClaims =
    [
        "production full PlayerInfoWidget behavior",
        "actual NativeHud full-union paint, real draw, or UpdateLayeredWindow commit",
        "production 3000-tick hidden/enabled A/B",
        "GDI, USER, process-handle, and native-memory trend under repeated real draw/commit",
        "Flash oracle or cross-renderer visual parity",
        "game-scene composite aesthetics",
        "real-window mouse hit passthrough",
        "runtime PlayerInfo state integration",
        "candidate execution, e2e verification, promotion or standard entry",
        "human visual/UI acceptance"
    ];

    private static readonly string[] ExpectedClosurePaths =
    [
        "global.json",
        "launcher/CRAZYFLASHER7MercenaryEmpire.csproj",
        "launcher/Directory.Packages.props",
        "launcher/packages.lock.json",
        "launcher/resolve-dotnet.ps1",
        "launcher/src/Guardian/NativeHudOverlay.cs",
        "launcher/src/Guardian/OverlayBase.cs",
        "launcher/src/Guardian/Hud/LayeredWindowCommit.cs",
        "launcher/src/Guardian/Hud/NativeHudTheme.cs",
        "launcher/src/Guardian/Hud/NativeHudTopologyProbe.cs",
        "launcher/src/Guardian/Hud/RightHudLayout.cs",
        "launcher/src/Guardian/Hud/WidgetScaler.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoStrictSvg.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgAssetCatalog.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPlan.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgRasterizer.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPipeline.cs",
        "launcher/src/Guardian/Hud/PlayerInfo/Assets/player-info.manifest.json",
        "launcher/src/Guardian/Hud/PlayerInfo/Assets/hp/backplate.svg",
        "launcher/src/Guardian/Hud/PlayerInfo/Assets/hp/fill.svg",
        "launcher/src/Guardian/Hud/PlayerInfo/Assets/hp/rim.svg",
        "launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/backplate.svg",
        "launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/fill.svg",
        "launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/rim.svg",
        "launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/rim-vf70.svg",
        "launcher/src/Guardian/Hud/PlayerInfo/Assets/mp/rim-vf91.svg",
        "launcher/tests/Launcher.Tests.csproj",
        "launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoB005RuntimeQualificationTests.cs",
        "launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoManifestRuntimeContractTests.cs",
        "launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoPArgbBridgeTests.cs",
        "launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoRasterPipelineTests.cs",
        "launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoRasterPlannerTests.cs",
        "launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoSvgProductionTests.cs",
        "launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoSvgRasterizerTests.cs",
        "launcher/tests/Guardian/LayeredWindowCommitTests.cs",
        "launcher/tests/Guardian/NativeHudTopologyProbeTests.cs",
        "tools/player-info-hud/run-b0-05-runtime-qualification.ps1"
    ];

    private static ViewportCase[] CreateViewportCases() =>
    [
        new(
            "viewport_1024x576_dpi100",
            new Rectangle(0, 0, 1024, 576),
            new Rectangle(0, 0, 1024, 576),
            1.00f),
        new(
            "viewport_1600x900_dpi125",
            new Rectangle(0, 0, 1600, 900),
            new Rectangle(0, 0, 1600, 900),
            1.25f),
        new(
            "viewport_1920x1080_dpi150",
            new Rectangle(0, 0, 1920, 1080),
            new Rectangle(0, 0, 1920, 1080),
            1.50f),
        new(
            "host_1280x960_letterbox_content_1280x720_dpi175",
            new Rectangle(0, 0, 1280, 960),
            new Rectangle(0, 120, 1280, 720),
            1.75f)
    ];

    private static void ValidateViewportContracts(
        IReadOnlyList<ViewportCase> viewportCases,
        IReadOnlyList<PlayerInfoRasterPlan> plans,
        PlayerInfoSvgAssetSet assetSet,
        ICollection<QualificationGate> gates)
    {
        for (var index = 0; index < plans.Count; index++)
        {
            PlayerInfoRasterPlan plan = plans[index];
            double expectedScale =
                viewportCases[index].ContentViewport.Height / 576d;
            AddExactGate(
                gates,
                "physical_scale_" + viewportCases[index].Id,
                "viewport_contract",
                Math.Abs(plan.PhysicalScale - expectedScale) <= 0.0000001,
                plan.PhysicalScale,
                expectedScale,
                "physical_scale",
                "Content viewport height must map once to the 576px logical stage.");
            PlayerInfoRasterPlan dpiNeutral = PlayerInfoRasterPlanner.Create(
                assetSet,
                viewportCases[index].ContentViewport,
                1f);
            AddExactGate(
                gates,
                "dpi_telemetry_only_" + viewportCases[index].Id,
                "viewport_contract",
                dpiNeutral.BatchKey == plan.BatchKey &&
                dpiNeutral.StagePhysicalBounds == plan.StagePhysicalBounds,
                new
                {
                    plan.BatchKey,
                    stage = Rect(plan.StagePhysicalBounds)
                },
                new
                {
                    dpiNeutral.BatchKey,
                    stage = Rect(dpiNeutral.StagePhysicalBounds)
                },
                "key_and_geometry",
                "PMv2 content coordinates are already physical; monitor DPI is diagnostic only.");
        }
    }

    private static async Task<List<TimedSample>>
        MeasureFreshBakesAsync(
        PlayerInfoSvgRasterizer rasterizer,
        IReadOnlyList<ViewportCase> viewportCases,
        IReadOnlyList<PlayerInfoRasterPlan> plans,
        int rounds,
        string phasePrefix)
    {
        if (rounds <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(rounds),
                "Fresh-bake rounds must be positive.");
        }
        if (string.IsNullOrEmpty(phasePrefix))
        {
            throw new ArgumentException(
                "Fresh-bake phase prefix is required.",
                nameof(phasePrefix));
        }
        var samples = new List<TimedSample>(
            viewportCases.Count * rounds);
        // Round-robin the viewports so a short machine-load or thermal phase
        // cannot be assigned wholesale to one resolution's percentile.
        for (var sampleIndex = 0;
             sampleIndex < rounds;
             sampleIndex++)
        {
            for (var viewportIndex = 0;
                 viewportIndex < viewportCases.Count;
                 viewportIndex++)
            {
                long started = Stopwatch.GetTimestamp();
                await Task.Run(() =>
                {
                    using PlayerInfoRasterBatch batch = rasterizer.Bake(
                        plans[viewportIndex],
                        CancellationToken.None);
                });
                samples.Add(new TimedSample(
                    $"{phasePrefix}_{sampleIndex + 1:00}",
                    viewportCases[viewportIndex].Id,
                    ElapsedMilliseconds(started)));
            }
        }
        return samples;
    }

    private static List<TimedSample> MeasurePArgbCopies(
        IReadOnlyList<ViewportCase> viewportCases,
        IReadOnlyList<PlayerInfoRasterPlan> plans)
    {
        var samples = new List<TimedSample>(
            plans.Sum(plan => plan.Layers.Count));
        for (var viewportIndex = 0;
             viewportIndex < viewportCases.Count;
             viewportIndex++)
        {
            foreach (PlayerInfoRasterLayerPlan layer in
                     plans[viewportIndex].Layers)
            {
                using var source = new SKBitmap(new SKImageInfo(
                    layer.PixelWidth,
                    layer.PixelHeight,
                    SKColorType.Bgra8888,
                    SKAlphaType.Premul));
                source.Erase(new SKColor(33, 121, 207, 127));
                long started = Stopwatch.GetTimestamp();
                using Bitmap copied = PlayerInfoPArgbBridge.Copy(source);
                samples.Add(new TimedSample(
                    layer.Key.LayerId,
                    viewportCases[viewportIndex].Id,
                    ElapsedMilliseconds(started)));
            }
        }
        return samples;
    }

    private static RequestMeasurement MeasureRequest(
        PlayerInfoRasterPipeline pipeline,
        PlayerInfoRasterPlan plan,
        string phase,
        string scenario,
        IReadOnlyDictionary<string, MutableLayerActivity> layerActivity)
    {
        long started = Stopwatch.GetTimestamp();
        PlayerInfoRasterRequestResult result = pipeline.Request(plan);
        double elapsed = ElapsedMilliseconds(started);

        foreach (PlayerInfoRasterLayerPlan layer in plan.Layers)
        {
            MutableLayerActivity activity =
                layerActivity[layer.Key.LayerId];
            activity.DesiredGenerationCount++;
            if (result == PlayerInfoRasterRequestResult.CurrentHit)
            {
                activity.CurrentHitCount++;
            }
            else if (result == PlayerInfoRasterRequestResult.CacheHit)
            {
                activity.InactiveCacheHitCount++;
            }
        }

        return new RequestMeasurement(
            result,
            new TimedSample(
                phase,
                scenario,
                elapsed,
                result.ToString()));
    }

    private static async Task WaitForIdleAsync(
        PlayerInfoRasterPipeline pipeline)
    {
        using var timeout = new CancellationTokenSource(
            TimeSpan.FromSeconds(60));
        await pipeline.WaitForIdleAsync(timeout.Token);
    }

    private static int OwnedPArgbPayloadCount(
        PlayerInfoRasterLayerPlan layer)
    {
        ArgumentNullException.ThrowIfNull(layer);
        return string.Equals(
            layer.Key.LayerId,
            "mp.fill",
            StringComparison.Ordinal)
            ? checked(1 + layer.Gauge.ClipBindings.Count)
            : 1;
    }

    private static void ObservePeakCache(
        PlayerInfoRasterPipeline pipeline,
        ref long peakCacheBytes)
    {
        peakCacheBytes = Math.Max(
            peakCacheBytes,
            pipeline.Snapshot.CacheBytes);
    }

    private static TimingSummary Summarize(IEnumerable<double> values)
    {
        double[] ordered = values.OrderBy(value => value).ToArray();
        if (ordered.Length == 0)
        {
            return new TimingSummary(0, 0, 0, 0, 0, 0);
        }
        return new TimingSummary(
            ordered.Length,
            RoundMilliseconds(ordered.Average()),
            RoundMilliseconds(NearestRank(ordered, 0.50)),
            RoundMilliseconds(NearestRank(ordered, 0.95)),
            RoundMilliseconds(NearestRank(ordered, 0.99)),
            RoundMilliseconds(ordered[^1]));
    }

    private static double NearestRank(double[] ordered, double quantile)
    {
        int rank = Math.Max(
            1,
            checked((int)Math.Ceiling(quantile * ordered.Length)));
        return ordered[rank - 1];
    }

    private static string FormatAffinityMask(IntPtr affinity) =>
        unchecked((ulong)affinity.ToInt64())
            .ToString("X16", CultureInfo.InvariantCulture);

    private static void AddUpperBoundGate(
        ICollection<QualificationGate> gates,
        string id,
        string phase,
        double actual,
        double limit,
        string unit,
        string? detail = null)
    {
        gates.Add(new QualificationGate(
            id,
            phase,
            actual <= limit,
            actual,
            limit,
            "less_than_or_equal",
            unit,
            detail ??
            $"Expected <= {limit.ToString("0.######", CultureInfo.InvariantCulture)} " +
            $"{unit}; actual " +
            actual.ToString("0.######", CultureInfo.InvariantCulture) +
            $" {unit}."));
    }

    private static void AddExactGate(
        ICollection<QualificationGate> gates,
        string id,
        string phase,
        bool passed,
        object? actual,
        object? expected,
        string unit,
        string detail)
    {
        gates.Add(new QualificationGate(
            id,
            phase,
            passed,
            actual,
            expected,
            "equals",
            unit,
            detail));
    }

    private static object Snapshot(
        PlayerInfoRasterPipelineSnapshot snapshot) =>
        new
        {
            snapshot.Generation,
            snapshot.RequestCount,
            snapshot.PublishCount,
            snapshot.CacheHitCount,
            snapshot.CurrentLayerHitCount,
            snapshot.CacheLayerHitCount,
            snapshot.ParseCount,
            snapshot.RasterCount,
            snapshot.ActiveWorkers,
            snapshot.MaxConcurrentWorkers,
            snapshot.PendingReplacementCount,
            snapshot.StaleDiscardCount,
            snapshot.FaultCount,
            snapshot.CancelCount,
            snapshot.DisposedBatchCount,
            snapshot.DisposedLayerCount,
            snapshot.CacheBytes,
            snapshot.CacheCount,
            snapshot.DesiredBatchKey,
            snapshot.CurrentBatchKey,
            snapshot.LastFault
        };

    private static object Topology(NativeHudTopologyProbeResult result) =>
        new
        {
            viewport = Rect(result.Viewport),
            bounds = result.Bounds.Select(Rect).ToArray(),
            rawOuterUnion = result.RawOuterUnion.HasValue
                ? Rect(result.RawOuterUnion.Value)
                : null,
            result.InflatePixels,
            inflatedOuterUnion = result.InflatedOuterUnion.HasValue
                ? Rect(result.InflatedOuterUnion.Value)
                : null,
            clippedSurface = Rect(result.ClippedSurface),
            result.ViewportPixels,
            result.RawInflatedSurfacePixels,
            result.SubmittedSurfacePixels,
            result.OffViewportPixels,
            result.ExactRectangleUnionPixels,
            result.Components,
            result.BridgeWastePixels,
            result.RawInflatedSurfaceBytes,
            result.SubmittedSurfaceBytes,
            result.Amplification,
            result.ClippedViewportRatio,
            result.ExactVisibleFillRatio,
            result.FullViewportBridge,
            result.NearFullBridge,
            result.RequiresDecision,
            recordedDecision = result.DecisionValue,
            result.ElapsedTicks,
            result.ElapsedMilliseconds
        };

    private static object Rect(Rectangle rectangle) =>
        new
        {
            rectangle.X,
            rectangle.Y,
            rectangle.Width,
            rectangle.Height,
            rectangle.Left,
            rectangle.Top,
            rectangle.Right,
            rectangle.Bottom
        };

    private static object SvgRect(PlayerInfoSvgRect rectangle) =>
        new
        {
            rectangle.X,
            rectangle.Y,
            rectangle.Width,
            rectangle.Height,
            rectangle.Left,
            rectangle.Top,
            rectangle.Right,
            rectangle.Bottom
        };

    private static string RectText(Rectangle rectangle) =>
        $"{rectangle.X},{rectangle.Y},{rectangle.Width},{rectangle.Height}";

    private static SourceClosure CaptureSourceClosure(string projectRoot)
    {
        string headCommit = RunGitRequired(
            projectRoot,
            "rev-parse",
            "HEAD").StandardOutput;
        GitCommandResult repositoryStatus = RunGitRequired(
            projectRoot,
            "status",
            "--porcelain=v1",
            "--untracked-files=all");
        var files = new List<SourceClosureFile>(
            ExpectedClosurePaths.Length);

        foreach (string relativePath in ExpectedClosurePaths
                     .OrderBy(path => path, StringComparer.Ordinal))
        {
            string absolutePath = Path.GetFullPath(
                Path.Combine(
                    projectRoot,
                    relativePath.Replace('/', Path.DirectorySeparatorChar)));
            string relativeCheck = Path.GetRelativePath(
                    projectRoot,
                    absolutePath)
                .Replace('\\', '/');
            if (!string.Equals(
                    relativePath,
                    relativeCheck,
                    StringComparison.Ordinal) ||
                !File.Exists(absolutePath))
            {
                throw new InvalidOperationException(
                    $"Source closure file is missing/outside root: {relativePath}");
            }

            GitCommandResult status = RunGitRequired(
                projectRoot,
                "status",
                "--porcelain=v1",
                "--untracked-files=all",
                "--",
                relativePath);
            GitCommandResult trackedProbe = RunGit(
                projectRoot,
                "ls-files",
                "--error-unmatch",
                "--",
                relativePath);
            GitCommandResult indexProbe = RunGitRequired(
                projectRoot,
                "ls-files",
                "--stage",
                "--",
                relativePath);
            GitCommandResult headProbe = RunGit(
                projectRoot,
                "rev-parse",
                "--verify",
                $"HEAD:{relativePath}");

            string? indexBlob = ParseIndexBlob(indexProbe.StandardOutput);
            string? headBlob = headProbe.ExitCode == 0 &&
                               !string.IsNullOrEmpty(headProbe.StandardOutput)
                ? headProbe.StandardOutput
                : null;
            var info = new FileInfo(absolutePath);
            files.Add(new SourceClosureFile(
                relativePath,
                info.Length,
                Sha256File(absolutePath),
                trackedProbe.ExitCode == 0,
                headBlob,
                indexBlob,
                status.StandardOutput));
        }

        string canonical = string.Join(
            "\n",
            files.Select(CanonicalClosureLine)) + "\n";
        return new SourceClosure(
            headCommit,
            !string.IsNullOrEmpty(repositoryStatus.StandardOutput),
            files.Any(file => !string.IsNullOrEmpty(file.WorktreeStatus)),
            files.AsReadOnly(),
            Sha256Bytes(Encoding.UTF8.GetBytes(canonical)),
            "path<TAB>size<TAB>worktreeSha256<TAB>tracked01<TAB>" +
            "headBlobOrDash<TAB>indexBlobOrDash<TAB>base64(worktreeStatus); " +
            "ordinal path order; LF terminated",
            "dirty worktree is accepted only because exact closure worktree " +
            "bytes, HEAD/index blobs, status, and executing test DLL are bound",
            new[]
            {
                "qualification report (self-referential generated evidence)",
                "docs/** and README documentation (same-commit ledger; not executable test closure)"
            });
    }

    private static TestAssemblyIdentity CaptureTestAssemblyIdentity(
        string projectRoot)
    {
        string assemblyPath = Path.GetFullPath(
            typeof(PlayerInfoB005RuntimeQualificationTests)
                .Assembly.Location);
        string relativePath = Path.GetRelativePath(
                projectRoot,
                assemblyPath)
            .Replace('\\', '/');
        if (relativePath.StartsWith("../", StringComparison.Ordinal) ||
            Path.IsPathRooted(relativePath))
        {
            throw new InvalidOperationException(
                "Executing Launcher.Tests.dll is outside the project root.");
        }
        var info = new FileInfo(assemblyPath);
        return new TestAssemblyIdentity(
            relativePath,
            info.Length,
            Sha256File(assemblyPath));
    }

    private static ExecutionBinaryEvidence CaptureExecutionBinaryEvidence(
        string projectRoot)
    {
        string targetRoot = Path.GetFullPath(
            Path.Combine(projectRoot, "launcher", "tests", "bin", "Release"));
        string[] rendererOutputClosurePaths =
            EnumerateRendererOutputClosurePaths(projectRoot, targetRoot);
        string targetRootRelative = Path.GetRelativePath(
                projectRoot,
                targetRoot)
            .Replace('\\', '/');
        string winX64Prefix =
            targetRootRelative + "/runtimes/win-x64/";
        string[] rendererTargetClosurePaths = rendererOutputClosurePaths
            .Where(path =>
            {
                string remainder = path[
                    (targetRootRelative.Length + 1)..];
                return !remainder.Contains('/') ||
                       path.StartsWith(
                           winX64Prefix,
                           StringComparison.Ordinal);
            })
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToArray();

        string[] managedLocations = AppDomain.CurrentDomain
            .GetAssemblies()
            .Where(assembly =>
                !assembly.IsDynamic &&
                !string.IsNullOrWhiteSpace(assembly.Location) &&
                (string.Equals(
                    assembly.GetName().Name,
                    "CRAZYFLASHER7MercenaryEmpire.Core",
                    StringComparison.OrdinalIgnoreCase) ||
                 IsRendererFamilyBinaryFileName(
                     Path.GetFileName(assembly.Location))))
            .Select(assembly => Path.GetFullPath(assembly.Location))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        using Process currentProcess = Process.GetCurrentProcess();
        string[] nativeLocations = currentProcess.Modules
            .Cast<ProcessModule>()
            .Where(module =>
                !string.IsNullOrWhiteSpace(module.FileName) &&
                IsRendererFamilyNativeFileName(
                    Path.GetFileName(module.FileName)))
            .Select(module => Path.GetFullPath(module.FileName))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        LoadedExecutionBinaryIdentity[] loadedExecutionBinaries =
            managedLocations
                .Select(path => CaptureLoadedExecutionBinary(
                    projectRoot,
                    "managed",
                    path))
                .Concat(nativeLocations.Select(path =>
                    CaptureLoadedExecutionBinary(
                        projectRoot,
                        "native",
                        path)))
                .OrderBy(binary => binary.Kind, StringComparer.Ordinal)
                .ThenBy(binary => binary.RelativePath, StringComparer.Ordinal)
                .ToArray();
        HashSet<string> loadedPaths = loadedExecutionBinaries
            .Where(binary => binary.InsideProjectRoot)
            .Select(binary => binary.RelativePath)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var resolvedTargetBinaries = new List<ExecutionBinaryIdentity>(
            ExpectedExecutionBinaries.Length);
        foreach (ExecutionBinaryContract contract in ExpectedExecutionBinaries)
        {
            string path = Path.Combine(
                projectRoot,
                contract.RelativePath.Replace(
                    '/',
                    Path.DirectorySeparatorChar));
            resolvedTargetBinaries.Add(CaptureExecutionBinary(
                projectRoot,
                contract.Name,
                contract.Kind,
                path,
                loadedPaths.Contains(contract.RelativePath)));
        }

        HashSet<string> expectedPaths = ExpectedExecutionBinaries
            .Select(binary => binary.RelativePath)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        string[] unexpectedLoadedRendererPaths = loadedExecutionBinaries
            .Where(binary =>
                !string.Equals(
                    binary.FileName,
                    "CRAZYFLASHER7MercenaryEmpire.Core.dll",
                    StringComparison.OrdinalIgnoreCase) &&
                (!binary.InsideProjectRoot ||
                 !expectedPaths.Contains(binary.RelativePath)))
            .Select(binary => binary.RelativePath)
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToArray();

        return new ExecutionBinaryEvidence(
            resolvedTargetBinaries
                .OrderBy(binary => binary.Name, StringComparer.Ordinal)
                .ToArray(),
            loadedExecutionBinaries,
            rendererTargetClosurePaths,
            rendererOutputClosurePaths,
            unexpectedLoadedRendererPaths);
    }

    private static string[] EnumerateRendererOutputClosurePaths(
        string projectRoot,
        string targetRoot)
    {
        var files = new List<string>();
        var pending = new Stack<string>();
        pending.Push(targetRoot);
        while (pending.Count != 0)
        {
            string directory = pending.Pop();
            foreach (string file in Directory.EnumerateFiles(
                         directory,
                         "*",
                         SearchOption.TopDirectoryOnly))
            {
                if (IsRendererFamilyBinaryFileName(Path.GetFileName(file)))
                {
                    files.Add(Path.GetRelativePath(projectRoot, file)
                        .Replace('\\', '/'));
                }
            }
            foreach (string child in Directory.EnumerateDirectories(
                         directory,
                         "*",
                         SearchOption.TopDirectoryOnly))
            {
                if ((File.GetAttributes(child) &
                     FileAttributes.ReparsePoint) != 0)
                {
                    throw new InvalidDataException(
                        "Renderer output closure refuses reparse directory: " +
                        child);
                }
                pending.Push(child);
            }
        }
        return files
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToArray();
    }

    private static ExecutionBinaryIdentity CaptureExecutionBinary(
        string projectRoot,
        string name,
        string kind,
        string path,
        bool loaded)
    {
        string absolutePath = Path.GetFullPath(path);
        string relativePath = Path.GetRelativePath(projectRoot, absolutePath)
            .Replace('\\', '/');
        if (relativePath.StartsWith("../", StringComparison.Ordinal) ||
            Path.IsPathRooted(relativePath))
        {
            throw new InvalidOperationException(
                $"Executing binary '{name}' is outside the project root.");
        }
        var info = new FileInfo(absolutePath);
        if (!info.Exists)
        {
            throw new FileNotFoundException(
                $"Executing binary '{name}' is missing.",
                absolutePath);
        }
        return new ExecutionBinaryIdentity(
            name,
            kind,
            relativePath,
            info.Length,
            Sha256File(absolutePath),
            loaded);
    }

    private static LoadedExecutionBinaryIdentity CaptureLoadedExecutionBinary(
        string projectRoot,
        string kind,
        string path)
    {
        string absolutePath = Path.GetFullPath(path);
        string relativePath = Path.GetRelativePath(projectRoot, absolutePath)
            .Replace('\\', '/');
        bool insideProjectRoot =
            !relativePath.StartsWith("../", StringComparison.Ordinal) &&
            !Path.IsPathRooted(relativePath);
        var info = new FileInfo(absolutePath);
        return new LoadedExecutionBinaryIdentity(
            Path.GetFileName(absolutePath),
            kind,
            relativePath,
            insideProjectRoot,
            info.Length,
            Sha256File(absolutePath));
    }

    private static bool IsRendererFamilyBinaryFileName(string fileName)
    {
        if (!fileName.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return fileName.StartsWith("Svg", StringComparison.OrdinalIgnoreCase) ||
               fileName.StartsWith(
                   "Skia",
                   StringComparison.OrdinalIgnoreCase) ||
               fileName.StartsWith(
                   "libSkia",
                   StringComparison.OrdinalIgnoreCase) ||
               fileName.StartsWith(
                   "HarfBuzz",
                   StringComparison.OrdinalIgnoreCase) ||
               fileName.StartsWith(
                   "libHarfBuzz",
                   StringComparison.OrdinalIgnoreCase) ||
               fileName.StartsWith(
                   "ExCSS",
                   StringComparison.OrdinalIgnoreCase) ||
               fileName.StartsWith(
                   "ShimSkia",
                   StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsRendererFamilyNativeFileName(string fileName) =>
        fileName.StartsWith(
            "libSkia",
            StringComparison.OrdinalIgnoreCase) ||
        fileName.StartsWith(
            "libHarfBuzz",
            StringComparison.OrdinalIgnoreCase);

    private static string CanonicalClosureLine(SourceClosureFile file)
    {
        string statusBase64 = Convert.ToBase64String(
            Encoding.UTF8.GetBytes(file.WorktreeStatus));
        return string.Join(
            "\t",
            file.Path,
            file.Size.ToString(CultureInfo.InvariantCulture),
            file.WorktreeSha256,
            file.Tracked ? "1" : "0",
            file.HeadBlob ?? "-",
            file.IndexBlob ?? "-",
            statusBase64);
    }

    private static string? ParseIndexBlob(string stageOutput)
    {
        if (string.IsNullOrEmpty(stageOutput))
        {
            return null;
        }
        string[] parts = stageOutput.Split(
            [' ', '\t'],
            StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || parts[1].Length != 40)
        {
            throw new InvalidOperationException(
                "Unexpected git ls-files --stage output: " + stageOutput);
        }
        return parts[1];
    }

    private static GitCommandResult RunGitRequired(
        string projectRoot,
        params string[] arguments)
    {
        GitCommandResult result = RunGit(projectRoot, arguments);
        if (result.ExitCode != 0)
        {
            throw new InvalidOperationException(
                "git " + string.Join(" ", arguments) +
                $" failed ({result.ExitCode}): {result.StandardError}");
        }
        return result;
    }

    private static GitCommandResult RunGit(
        string projectRoot,
        params string[] arguments)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "git",
            WorkingDirectory = projectRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        startInfo.ArgumentList.Add("-C");
        startInfo.ArgumentList.Add(projectRoot);
        foreach (string argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException("Unable to start git.");
        }
        Task<string> standardOutput = process.StandardOutput.ReadToEndAsync();
        Task<string> standardError = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(TimeSpan.FromSeconds(30)))
        {
            process.Kill(entireProcessTree: true);
            throw new TimeoutException("git source-closure probe timed out.");
        }
        process.WaitForExit();
        return new GitCommandResult(
            process.ExitCode,
            TrimLineEndings(standardOutput.GetAwaiter().GetResult()),
            TrimLineEndings(standardError.GetAwaiter().GetResult()));
    }

    private static string TrimLineEndings(string value) =>
        value.TrimEnd('\r', '\n');

    private static string Sha256File(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static string Sha256Bytes(byte[] bytes) =>
        Convert.ToHexString(SHA256.HashData(bytes));

    private static string GetEffectiveDpiAwareness()
    {
        try
        {
            return DpiAwarenessBootstrap.GetEffectiveAwareness().ToString();
        }
        catch (Exception exception)
        {
            return "unavailable:" + exception.GetType().Name;
        }
    }

    private static ProcessMetrics CaptureProcessMetrics()
    {
        using Process process = Process.GetCurrentProcess();
        process.Refresh();
        long gdiObjects = -1;
        long userObjects = -1;
        try
        {
            gdiObjects = GetGuiResources(process.Handle, 0);
            userObjects = GetGuiResources(process.Handle, 1);
        }
        catch (Exception)
        {
            // Diagnostic-only on B0-05; the report preserves -1 as unavailable.
        }

        return new ProcessMetrics(
            process.TotalProcessorTime.TotalMilliseconds,
            GC.GetTotalAllocatedBytes(precise: true),
            GC.CollectionCount(0),
            GC.CollectionCount(1),
            GC.CollectionCount(2),
            GC.GetTotalMemory(forceFullCollection: false),
            GC.GetGCMemoryInfo().HeapSizeBytes,
            process.WorkingSet64,
            process.PrivateMemorySize64,
            process.HandleCount,
            gdiObjects,
            userObjects);
    }

    private static void ForceManagedCleanup()
    {
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
    }

    private static void WriteReportWithoutBom(
        string path,
        object report)
    {
        string? directory = Path.GetDirectoryName(path);
        if (string.IsNullOrEmpty(directory))
        {
            throw new InvalidOperationException(
                "B0-05 report path has no parent directory.");
        }
        Directory.CreateDirectory(directory);
        string json = JsonSerializer.Serialize(
            report,
            new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                WriteIndented = true
            });
        // The repository stores JSON as LF. Emit that canonical byte form
        // directly so the report's reviewed size/hash survive git checkout.
        json = json.Replace("\r\n", "\n", StringComparison.Ordinal);
        if (json.IndexOf('\r') >= 0)
        {
            throw new InvalidOperationException(
                "B0-05 report serialization produced a non-canonical CR byte.");
        }
        File.WriteAllText(path, json + "\n",
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    private static double ElapsedMilliseconds(long started) =>
        Stopwatch.GetElapsedTime(started).TotalMilliseconds;

    private static double RoundMilliseconds(double value) =>
        Math.Round(value, 6, MidpointRounding.AwayFromZero);

    [DllImport("user32.dll")]
    private static extern uint GetGuiResources(
        IntPtr processHandle,
        uint flags);

    private sealed record ViewportCase(
        string Id,
        Rectangle HostViewport,
        Rectangle ContentViewport,
        float MonitorDpiScale);

    private sealed record TimedSample(
        string Phase,
        string Scenario,
        double Milliseconds,
        string? Result = null);

    private sealed record TimingSummary(
        int Count,
        double Mean,
        double P50,
        double P95,
        double P99,
        double Max);

    private sealed record ViewportTiming(
        string ViewportId,
        TimingSummary Summary);

    private sealed record RequestMeasurement(
        PlayerInfoRasterRequestResult Result,
        TimedSample Sample);

    private sealed record QualificationGate(
        string Id,
        string Phase,
        bool Passed,
        object? Actual,
        object? Expected,
        string Comparison,
        string Unit,
        string Detail);

    private sealed record QualificationOutcome(
        object Report,
        IReadOnlyList<string> Failures);

    private sealed record SourceClosure(
        string HeadCommit,
        bool RepositoryDirty,
        bool ClosureDirty,
        IReadOnlyList<SourceClosureFile> Files,
        string AggregateSha256,
        string CanonicalFormat,
        string DirtyStateExplanation,
        IReadOnlyList<string> ExcludedFromClosure);

    private sealed record SourceClosureFile(
        string Path,
        long Size,
        string WorktreeSha256,
        bool Tracked,
        string? HeadBlob,
        string? IndexBlob,
        string WorktreeStatus);

    private sealed record TestAssemblyIdentity(
        string RelativePath,
        long Size,
        string Sha256);

    private sealed record ExecutionBinaryIdentity(
        string Name,
        string Kind,
        string RelativePath,
        long Size,
        string Sha256,
        bool Loaded);

    private sealed record LoadedExecutionBinaryIdentity(
        string FileName,
        string Kind,
        string RelativePath,
        bool InsideProjectRoot,
        long Size,
        string Sha256);

    private sealed record ExecutionBinaryEvidence(
        IReadOnlyList<ExecutionBinaryIdentity> ResolvedTargetBinaries,
        IReadOnlyList<LoadedExecutionBinaryIdentity> LoadedExecutionBinaries,
        IReadOnlyList<string> RendererTargetClosurePaths,
        IReadOnlyList<string> RendererOutputClosurePaths,
        IReadOnlyList<string> UnexpectedLoadedRendererPaths);

    private sealed record ExecutionBinaryContract(
        string Name,
        string Kind,
        string RelativePath);

    private sealed record GitCommandResult(
        int ExitCode,
        string StandardOutput,
        string StandardError);

    private sealed class MutableLayerActivity(string layerId)
    {
        internal string LayerId { get; } = layerId;
        internal long DesiredGenerationCount { get; set; }
        internal long CurrentHitCount { get; set; }
        internal long InactiveCacheHitCount { get; set; }
        internal long InferredBatchDisposalCount { get; set; }
    }

    private sealed record ProcessMetrics(
        double ProcessCpuMilliseconds,
        long TotalAllocatedBytes,
        int Gen0Collections,
        int Gen1Collections,
        int Gen2Collections,
        long ManagedMemoryBytes,
        long ManagedHeapSizeBytes,
        long WorkingSetBytes,
        long PrivateMemoryBytes,
        int ProcessHandleCount,
        long GdiObjectCount,
        long UserObjectCount)
    {
        internal static ProcessMetrics Delta(
            ProcessMetrics before,
            ProcessMetrics after) =>
            new(
                after.ProcessCpuMilliseconds -
                before.ProcessCpuMilliseconds,
                after.TotalAllocatedBytes - before.TotalAllocatedBytes,
                after.Gen0Collections - before.Gen0Collections,
                after.Gen1Collections - before.Gen1Collections,
                after.Gen2Collections - before.Gen2Collections,
                after.ManagedMemoryBytes - before.ManagedMemoryBytes,
                after.ManagedHeapSizeBytes - before.ManagedHeapSizeBytes,
                after.WorkingSetBytes - before.WorkingSetBytes,
                after.PrivateMemoryBytes - before.PrivateMemoryBytes,
                after.ProcessHandleCount - before.ProcessHandleCount,
                after.GdiObjectCount < 0 || before.GdiObjectCount < 0
                    ? -1
                    : after.GdiObjectCount - before.GdiObjectCount,
                after.UserObjectCount < 0 || before.UserObjectCount < 0
                    ? -1
                    : after.UserObjectCount - before.UserObjectCount);
    }
}
