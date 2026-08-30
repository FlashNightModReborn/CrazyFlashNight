using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian.HitNumbers;

namespace CF7Launcher.Tools.HitNumberVisualHarness
{
    internal static class Program
    {
        private static int Main(string[] args)
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            try
            {
                Options options = Options.Parse(args);
                string projectRoot = options.ProjectRoot ?? FindProjectRoot(Environment.CurrentDirectory);
                string outputRoot = options.OutputRoot ?? Path.Combine(
                    projectRoot,
                    "tmp",
                    "hit-number-visual",
                    "review-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"));
                projectRoot = Path.GetFullPath(projectRoot);
                outputRoot = Path.GetFullPath(outputRoot);
                EnsureFreshOutput(outputRoot);

                RuntimeFontCatalog.Configure(projectRoot);
                IReadOnlyList<VisualScenario> scenarios = ScenarioCatalog.BuildReviewScenarios();
                List<ProductionRenderResult> captures;
                string contactSheet;
                var videos = new List<VideoRenderResult>();
                ProductionPerformanceProbeResult performance;

                using (var renderer = new ProductionRenderer(outputRoot))
                {
                    Console.WriteLine("[hit-number-visual] render production acceptance set");
                    captures = renderer.RenderAcceptanceSet(scenarios);
                    contactSheet = renderer.RenderContactSheet(captures);
                    if (!options.NoVideo)
                    {
                        Console.WriteLine("[hit-number-visual] render production videos");
                        videos.AddRange(renderer.RenderAcceptanceVideos());
                    }
                }
                Console.WriteLine("[hit-number-visual] run sustained production performance probe");
                performance = ProductionPerformanceProbe.Run();

                object manifest = BuildManifest(
                    projectRoot,
                    outputRoot,
                    scenarios,
                    captures,
                    contactSheet,
                    videos,
                    performance,
                    options.NoVideo);
                string manifestPath = Path.Combine(outputRoot, "manifest.json");
                File.WriteAllText(
                    manifestPath,
                    JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }),
                    new UTF8Encoding(false));

                Console.WriteLine("[hit-number-visual] output=" + outputRoot);
                Console.WriteLine("[hit-number-visual] productionCaptures=" + captures.Count);
                for (int i = 0; i < videos.Count; i++)
                {
                    Console.WriteLine(
                        "[hit-number-visual] video " + videos[i].Id + "=" +
                        (videos[i].Encoded ? "encoded" : "failed") +
                        (string.IsNullOrEmpty(videos[i].Error) ? "" : " error=" + videos[i].Error));
                }
                Console.WriteLine(
                    "[hit-number-visual] perf avgMs=" +
                    performance.AverageMillisecondsPerFrame.ToString("0.000") +
                    " reducer/layout=" + performance.ReducerLayoutMillisecondsPerFrame.ToString("0.000") +
                    " painter=" + performance.PainterMillisecondsPerFrame.ToString("0.000") +
                    " allocated/frame=" + performance.ManagedAllocatedBytesPerFrame.ToString("0") +
                    " maxActive=" + performance.MaximumActiveSegments +
                    " maxBacking=" + performance.MaximumBackingSegments +
                    " gdi=" + performance.GdiObjectsBefore + "->" + performance.GdiObjectsAfter);
                Console.WriteLine(
                    "[hit-number-visual] ledger retained=" +
                    performance.LedgerRetainedSegments +
                    " dropped=" + performance.LedgerDroppedSegments +
                    " bursts=" + performance.LedgerTotalBursts +
                    " page=" + performance.LedgerPageBursts +
                    " materializeMs=" +
                    performance.LedgerMaterializeMilliseconds.ToString("0.000") +
                    " allocated=" + performance.LedgerMaterializeManagedAllocatedBytes);
                bool videosPassed = videos.All(video => video.Encoded);
                return videosPassed &&
                    performance.HistoryBounded &&
                    performance.LedgerBounded &&
                    performance.GuiResourcesStable
                    ? 0
                    : 2;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(
                    "[hit-number-visual] FAILED " + ex.GetType().Name + ": " + ex.Message);
                Console.Error.WriteLine(ex.StackTrace);
                return 1;
            }
        }

        private static object BuildManifest(
            string projectRoot,
            string outputRoot,
            IReadOnlyList<VisualScenario> scenarios,
            IReadOnlyList<ProductionRenderResult> captures,
            string contactSheet,
            IReadOnlyList<VideoRenderResult> videos,
            ProductionPerformanceProbeResult performance,
            bool videoSkipped)
        {
            var artifacts = Directory.EnumerateFiles(outputRoot, "*", SearchOption.TopDirectoryOnly)
                .Where(path => !string.Equals(Path.GetFileName(path), "manifest.json", StringComparison.OrdinalIgnoreCase))
                .OrderBy(path => Path.GetFileName(path), StringComparer.Ordinal)
                .Select(path => new
                {
                    path = Path.GetFileName(path),
                    bytes = new FileInfo(path).Length,
                    sha256 = Sha256(path)
                }).ToArray();

            return new
            {
                schemaVersion = 11,
                generatedAtUtc = DateTime.UtcNow.ToString("O"),
                source = new
                {
                    projectRoot,
                    painter = "launcher/src/Guardian/HitNumbers/HitNumberPainter.cs",
                    scenePainter = "launcher/src/Guardian/HitNumbers/HitNumberScenePainter.cs",
                    layout = "launcher/src/Guardian/HitNumbers/HitNumberLayoutEngine.cs",
                    renderer = "production tight-region composite; no harness-owned hit-number layout or battle ledger painter",
                    deterministicPlacement = "target-local-centered-stack-balanced-no-arrow-v3"
                },
                scope = new
                {
                    definition = "one damage segment equals one bullet damage event",
                    linkedShotHandling = "virtual bullet segments retain one BurstId and reserve stable geometry with ExpectedBurstHitCount",
                    causalPlacement = "each Burst is a target-attached fixed row; nearby targets never steer its direction",
                    colorProjection = "all modes share one 11-color source table; balanced and total may transiently blend the main number while semantic labels retain their source/fixed colors",
                    losslessRule = "world modes may compress or cap presentation; a separate fixed-capacity scene ledger retains exact segments and materializes only from paused Web settings",
                    onlyAllowedCull = "target outside stage plus 100px margin",
                    input = "deterministic synthetic combat stream and background",
                    evidenceBoundary = "production painter/layout evidence; not Flash/WGC runtime E2E, promotion, or standard-entry verification"
                },
                scenarios = scenarios.Select(s => new
                {
                    id = s.Id,
                    title = s.Title,
                    intent = s.Intent,
                    snapshotSeconds = s.SnapshotSeconds,
                    inputSegments = s.Segments.Count
                }).ToArray(),
                productionAcceptance = new
                {
                    contactSheet,
                    captures = captures.Select(p => new
                    {
                        id = p.Id,
                        scenarioId = p.ScenarioId,
                        title = p.Title,
                        mode = p.Mode,
                        worldRowLimit = p.WorldRowLimit,
                        width = p.Width,
                        height = p.Height,
                        image = p.RelativePath,
                        inputActive = p.InputActive,
                        offscreenCulled = p.OffscreenCulled,
                        worldRows = p.WorldRows,
                        worldRowsOmitted = p.WorldRowsOmitted,
                        worldSegmentsOmitted = p.WorldSegmentsOmitted,
                        surfaceEdgeAlphaPixels = p.SurfaceEdgeAlphaPixels,
                        committedPixelRegion = new
                        {
                            x = p.PixelRegion.X,
                            y = p.PixelRegion.Y,
                            width = p.PixelRegion.Width,
                            height = p.PixelRegion.Height
                        }
                    }).ToArray()
                },
                videoGenerationSkipped = videoSkipped,
                videos = videos.Select(video => new
                {
                    id = video.Id,
                    title = video.Title,
                    renderer = "production HitNumberLayoutEngine + HitNumberScenePainter + HitNumberPainter",
                    encoded = video.Encoded,
                    file = video.RelativeVideoPath,
                    storyboard = video.RelativeStoryboardPath,
                    frames = video.Frames,
                    framesPerSecond = video.FramesPerSecond,
                    error = video.Error
                }).ToArray(),
                sustainedPerformance = new
                {
                    rate = "1200 segments/s (20/frame at 60 fps)",
                    performance.WarmupFrames,
                    performance.MeasuredFrames,
                    performance.LedgerFillFrames,
                    performance.HitsPerFrame,
                    performance.SimulatedHits,
                    performance.MaximumActiveSegments,
                    performance.MaximumBackingSegments,
                    elapsedMilliseconds = performance.ElapsedMilliseconds,
                    averageMillisecondsPerFrame = performance.AverageMillisecondsPerFrame,
                    reducerLayoutMillisecondsPerFrame = performance.ReducerLayoutMillisecondsPerFrame,
                    painterMillisecondsPerFrame = performance.PainterMillisecondsPerFrame,
                    performance.ManagedAllocatedBytes,
                    managedAllocatedBytesPerFrame = performance.ManagedAllocatedBytesPerFrame,
                    performance.Gen0Collections,
                    performance.GdiObjectsBefore,
                    performance.GdiObjectsAfter,
                    performance.UserObjectsBefore,
                    performance.UserObjectsAfter,
                    performance.ProcessHandlesBefore,
                    performance.ProcessHandlesAfter,
                    performance.HistoryBounded,
                    performance.GuiResourcesStable,
                    settingsLedger = new
                    {
                        capacity = HitNumberLedgerStore.Capacity,
                        performance.LedgerRetainedSegments,
                        performance.LedgerDroppedSegments,
                        performance.LedgerTotalBursts,
                        performance.LedgerPageBursts,
                        materializeMilliseconds = performance.LedgerMaterializeMilliseconds,
                        performance.LedgerMaterializeManagedAllocatedBytes,
                        performance.LedgerBounded
                    },
                    evidenceBoundary = "synthetic in-process production pipeline; timing is machine-local and not a real layered-window game E2E"
                },
                artifacts
            };
        }

        private static string Sha256(string path)
        {
            using FileStream stream = File.OpenRead(path);
            return Convert.ToHexString(SHA256.HashData(stream));
        }

        private static void EnsureFreshOutput(string outputRoot)
        {
            if (Directory.Exists(outputRoot) && Directory.EnumerateFileSystemEntries(outputRoot).Any())
                throw new InvalidOperationException("output directory must be absent or empty: " + outputRoot);
            Directory.CreateDirectory(outputRoot);
        }

        private static string FindProjectRoot(string start)
        {
            DirectoryInfo current = new DirectoryInfo(Path.GetFullPath(start));
            while (current != null)
            {
                if (File.Exists(Path.Combine(current.FullName, "global.json")) &&
                    File.Exists(Path.Combine(current.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                    return current.FullName;
                current = current.Parent;
            }
            throw new DirectoryNotFoundException("could not locate repository root from " + start);
        }

        private sealed class Options
        {
            internal string ProjectRoot;
            internal string OutputRoot;
            internal bool NoVideo;

            internal static Options Parse(string[] args)
            {
                var options = new Options();
                for (int i = 0; i < args.Length; i++)
                {
                    switch (args[i])
                    {
                        case "--project-root":
                            options.ProjectRoot = RequireValue(args, ref i, "--project-root");
                            break;
                        case "--output":
                            options.OutputRoot = RequireValue(args, ref i, "--output");
                            break;
                        case "--no-video":
                            options.NoVideo = true;
                            break;
                        default:
                            throw new ArgumentException("unknown argument: " + args[i]);
                    }
                }
                return options;
            }

            private static string RequireValue(string[] args, ref int index, string name)
            {
                if (index + 1 >= args.Length || string.IsNullOrWhiteSpace(args[index + 1]))
                    throw new ArgumentException(name + " requires a value");
                index++;
                return args[index];
            }
        }
    }
}
