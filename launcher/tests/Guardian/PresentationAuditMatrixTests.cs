using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.HitNumbers;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class PresentationAuditFactAttribute : FactAttribute
{
    public PresentationAuditFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CF7_AUDIT_MATRIX_REPORT")))
            Skip = "Set CF7_AUDIT_MATRIX_REPORT to opt into the owned-window matrix.";
        else if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE")))
            Skip = "An explicit shared-world candidate is required.";
        else if (DisplayPowerObservation.ReadSessionState() != 1)
            Skip = "The session display must already be on.";
    }
}

public sealed class PresentationAuditMatrixTests
{
    [PresentationAuditFact]
    public void MeasureNativePresentationAuditMatrix() => OpaqueHudGpuTests.RunPresentationAuditMatrix();

    [Fact]
    public void AuditReportPreservesPhaseIdentityAndPresentationDiagAbi()
        => OpaqueHudGpuTests.VerifyPresentationAuditReportContract();

    [Fact]
    public void AuditInputsUseProductionBulletRayFxAndHitNumberData()
        => OpaqueHudGpuTests.VerifyPresentationAuditInputs();
}

public sealed partial class OpaqueHudGpuTests
{
    private const int AuditHz = 30, AuditWarmup = 60;
    private const string AuditScenarioList = "S0,S0b,S1,S2,S3,S4,S5,S6,S7,S9,S10";
    private const string AuditSizeList = "1024x576,1920x1080";
    private const string AuditBoundary = "Owned WGC source and D3D composition output. GPU timestamps exclude WGC, DXGI Present and DWM. No gameplay or physical scanout evidence.";
    private static readonly bool[] AuditAbba = { false, true, true, false };
    private static readonly FieldInfo[] AuditDiagFields = typeof(NativeCompositorSession.PresentationDiagStats)
        .GetFields(BindingFlags.Instance | BindingFlags.NonPublic);

    private static void VerifyAuditDiagLayout()
    {
        var type = typeof(NativeCompositorSession.PresentationDiagStats);
        Assert.Equal(232, Marshal.SizeOf(type));
        Assert.Equal(24, Marshal.OffsetOf(type, nameof(NativeCompositorSession.PresentationDiagStats.ActiveBlitSamples)).ToInt32());
        Assert.Equal(216, Marshal.OffsetOf(type, nameof(NativeCompositorSession.PresentationDiagStats.WakeFrozenPresenceOnly)).ToInt32());
        Assert.Equal(224, Marshal.OffsetOf(type, nameof(NativeCompositorSession.PresentationDiagStats.WakeOther)).ToInt32());
    }

    private static JObject AuditDiagJson(NativeCompositorSession.PresentationDiagStats? value)
    {
        if (!value.HasValue) return null;
        object boxed = value.Value;
        return new JObject(AuditDiagFields.Select(field => new JProperty(
            char.ToLowerInvariant(field.Name[0]) + field.Name[1..],
            new JValue(field.GetValue(boxed)))));
    }

    private static double AuditDiagTime(JObject diag, string field) => diag?.Value<double>(field) ?? 0;

    private static JObject ReadAuditDiag(NativeCompositorSession world) =>
        AuditDiagJson(world.ReadPresentationDiag());

    private static int AuditInteger(string name, int fallback, int min, int max)
    {
        string value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(value)) return fallback;
        Assert.True(int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out int result),
            name + " must be an integer.");
        Assert.InRange(result, min, max);
        return result;
    }

    private static string[] AuditList(string name, string defaults)
    {
        var entries = (Environment.GetEnvironmentVariable(name) ?? defaults)
            .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        Assert.NotEmpty(entries);
        Assert.Equal(entries.Length, entries.Distinct(StringComparer.OrdinalIgnoreCase).Count());
        return entries;
    }

    private static string AuditProjectRoot() => Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_HUD_COST_PROJECT")
        ?? Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));

    private static Size AuditSize(string value)
    {
        string[] parts = value.Split('x', 'X');
        if (parts.Length == 2 && int.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out int width)
            && int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out int height)
            && width is >= 320 and <= 4096 && height is >= 180 and <= 4096)
            return new Size(width, height);
        throw new ArgumentException("Expected a supported WIDTHxHEIGHT audit size.", nameof(value));
    }

    private static JObject AuditReport(string variant, string candidate, string buildIdentity, string payloadClosure,
        string coreSha256, string candidateCoreSha256, string nativeSha256, string adapter, uint vendorId, JArray rows) =>
        JObject.FromObject(new
        {
            schema = "cf7-native-presentation-audit.v1", evidenceLevel = "synthetic_owned_window",
            variant, candidate, buildIdentity, payloadClosure, coreSha256, candidateCoreSha256,
            nativeSha256, adapter, vendorId, rows
        });

    private static JObject AuditRow(string scenario, string variant, Size size, string temperature, int repeat,
        string phase, object samples, object counters, object gpuTiming, object presentationDiag, object hitNumberDiag,
        params string[] limitations) => JObject.FromObject(new
        {
            scenario, variant, outputSize = new { width = size.Width, height = size.Height },
            coldOrWarm = temperature, repeat, phase, samples, counters, gpuTiming, presentationDiag, hitNumberDiag,
            limitations = new[] { AuditBoundary }.Concat(limitations).ToArray()
        });

    internal static void RunPresentationAuditMatrix()
    {
        VerifyAuditDiagLayout();
        string destination = Environment.GetEnvironmentVariable("CF7_AUDIT_MATRIX_REPORT");
        Assert.True(Path.IsPathFullyQualified(destination), "Use an absolute, unique report path.");
        Assert.False(File.Exists(destination), "Audit reports are immutable per run.");
        int repeats = AuditInteger("CF7_AUDIT_MATRIX_REPEATS", 3, 1, 5);
        int frames = AuditInteger("CF7_AUDIT_MATRIX_FRAMES", 240, 60, 900);
        var validScenarios = AuditScenarioList.Split(',');
        var scenarios = AuditList("CF7_AUDIT_MATRIX_SCENARIOS", AuditScenarioList)
            .Select(name => Assert.Single(validScenarios, valid => string.Equals(valid, name, StringComparison.OrdinalIgnoreCase)))
            .ToArray();
        var sizes = AuditList("CF7_AUDIT_MATRIX_SIZES", AuditSizeList).Select(AuditSize).ToArray();
        Assert.Equal(sizes.Length, sizes.Distinct().Count());
        string variant = Environment.GetEnvironmentVariable("CF7_AUDIT_MATRIX_VARIANT") ?? "unspecified";
        string candidate = Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"));
        string metadataPath = Path.Combine(candidate, "runtime-build-metadata.v2.json");
        var metadata = JObject.Parse(File.ReadAllText(metadataPath));
        string buildIdentity = metadata.Value<string>("buildIdentityHash");
        string payloadClosure = metadata.Value<string>("payloadClosureHash");
        Assert.False(string.IsNullOrWhiteSpace(buildIdentity));
        Assert.False(string.IsNullOrWhiteSpace(payloadClosure));
        string core = typeof(NativeCompositorSession).Assembly.Location;
        string native = Path.Combine(candidate, "runtime", NativeCompositorSession.ModuleName);
        string candidateCore = Path.Combine(candidate, "runtime", Path.GetFileName(core));
        string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
        string coreSha256 = Hash(core), nativeSha256 = Hash(native), candidateCoreSha256 = Hash(candidateCore);
        string metadataSha256 = Hash(metadataPath);
        string[] manifestCore = File.ReadLines(Path.Combine(candidate, "runtime", "cf7-runtime-manifest.tsv"))
            .Select(line => line.Split('\t')).Single(parts => parts.Length == 4 && parts[0] == "file"
                && parts[1] == "runtime/" + Path.GetFileName(core));
        Assert.Equal(manifestCore[3], candidateCoreSha256, ignoreCase: true);
        string root = AuditProjectRoot();
        RuntimeFontCatalog.Configure(root);

        string adapter = null;
        uint vendorId = 0;
        var rows = new JArray();
        Directory.CreateDirectory(Path.GetDirectoryName(destination));
        string liveLog = destination + ".jsonl";
        foreach (Size size in sizes)
        foreach (string scenario in scenarios)
        for (int repeat = 1; repeat <= repeats; repeat++)
        {
            Assert.Equal(1, DisplayPowerObservation.ReadSessionState());
            Run((world, scene, output, source) =>
            {
                Assert.Equal(size, output.ClientSize);
                Assert.Equal(size, source.ClientSize);
                var stats = world.Read();
                Assert.Equal(((uint)size.Width, (uint)size.Height), (stats.Width, stats.Height));
                adapter ??= stats.Adapter;
                if (vendorId == 0) vendorId = stats.Vendor;
                Assert.Equal(adapter, stats.Adapter);
                Assert.Equal(vendorId, stats.Vendor);
                using var run = new AuditFixture(world, scene, output, (Window)source, root, size,
                    scenario, variant, repeat, frames, rows, liveLog);
                run.Execute();
            }, size, TimeSpan.FromSeconds(120 + 10 * (AuditWarmup + frames) / (double)AuditHz));
        }
        Assert.Equal(1, DisplayPowerObservation.ReadSessionState());
        Assert.Equal(coreSha256, Hash(core));
        Assert.Equal(nativeSha256, Hash(native));
        Assert.Equal(candidateCoreSha256, Hash(candidateCore));
        Assert.Equal(metadataSha256, Hash(metadataPath));
        Directory.CreateDirectory(Path.GetDirectoryName(destination));
        using var stream = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
        using var writer = new StreamWriter(stream);
        writer.Write(AuditReport(variant, candidate, buildIdentity, payloadClosure, coreSha256, candidateCoreSha256,
            nativeSha256, adapter, vendorId, rows).ToString(Formatting.Indented));
    }

    private sealed class AuditFixture : IDisposable
    {
        private readonly NativeCompositorSession world;
        private readonly CompositionSceneHost scene;
        private readonly Form output;
        private readonly Window source;
        private readonly string root, scenario, variant, liveLog;
        private readonly Size size;
        private readonly int repeat, frames;
        private readonly JArray rows;
        private readonly List<HitNumberPaintDiagnostics> numberSamples;
        private BulletVisualCatalog bulletCatalog;
        private CombatFxCatalog fxCatalog;
        private AuditHud hud;
        private HitNumberOverlay numbers;
        private WorldRasterPresentation damage;
        private HitNumberRuntime numberRuntime;
        private HitNumberRuntimeSnapshot lastNumbers;
        private BulletVisualFrame[] bullets;
        private RayVisualDrawFrame[] rays;
        private CombatFxDrawFrame[] effects;
        private int grant, sourceTick;
        private int sourceEpoch;
        private Size sourceViewport;
        private double numberTime;
        private bool handoffMarker;

        internal AuditFixture(NativeCompositorSession world, CompositionSceneHost scene, Form output, Window source,
            string root, Size size, string scenario, string variant, int repeat, int frames, JArray rows, string liveLog)
        {
            this.world = world; this.scene = scene; this.output = output; this.source = source;
            this.root = root; this.size = size; this.scenario = scenario; this.variant = variant;
            this.repeat = repeat; this.frames = frames; this.rows = rows; this.liveLog = liveLog;
            sourceViewport = size;
            numberSamples = new List<HitNumberPaintDiagnostics>(frames);
        }

        internal void Execute()
        {
            Assert.True(world.HudCostSamplingAvailable);
            world.Postprocess(false, 0, false);
            world.NightVision(NightVisionProfile.None, 0, ShakeTestIdentityGrade, false, null);
            world.Atmosphere(0, new float[12]);
            world.Weather(0, 0, 0, 1);
            if (scenario is "S2" or "S6" or "S7" or "S9" or "S10")
                Assert.True(world.WorldShakeAvailable);

            switch (scenario)
            {
                case "S0":
                    MeasureIdle("static");
                    break;
                case "S0b":
                    FrozenPresence();
                    break;
                case "S1":
                    using (hud = new AuditHud(output, world))
                        Measure("hud_only", tick => hud.Tick(tick), validate: (gpu, after, before) =>
                        {
                            Assert.Equal(before.World.Received, after.World.Received);
                            Assert.True(after.Raster.Accepted > before.Raster.Accepted);
                            Assert.True(after.Work.Compositions > before.Work.Compositions);
                            Assert.True(gpu.Completed > 0);
                        });
                    hud = null;
                    break;
                case "S2":
                    ColdShake();
                    for (int round = 1; round <= 3; round++)
                    {
                        ArmShake();
                        Measure("pulse_" + round, PulseTick, validate: ValidateStaticShake);
                        ClearActiveShake();
                    }
                    MeasureIdle("cleared");
                    break;
                case "S3":
                    PrepareBullets();
                    foreach (var mix in new[] { (Bullets: 64, Rays: 64), (Bullets: 512, Rays: 256) })
                    {
                        PrepareSource();
                        bullets = BuildAuditBullets(bulletCatalog, frames + AuditWarmup, mix.Bullets, sourceEpoch, synced: true);
                        rays = BuildAuditRays(mix.Rays);
                        Measure(mix.Bullets == 64 ? "sparse" : "dense", tick => DriveMixed(tick, tagged: true),
                            validate: ValidateMixed,
                            afterWindow: () => JObject.FromObject(new
                            {
                                bulletsPerFrame = mix.Bullets, rayBodies = mix.Rays,
                                bulletSource = VerifyBulletHistory()
                            }));
                        ClearDecorations();
                    }
                    break;
                case "S4":
                    PrepareNumbers();
                    foreach (var mode in new[] { HitNumberDisplayMode.Balanced, HitNumberDisplayMode.Total,
                        HitNumberDisplayMode.Detail, HitNumberDisplayMode.Classic })
                    foreach (bool scattered in new[] { false, true })
                    {
                        SetNumberMode(mode);
                        Measure(mode + (scattered ? "_scattered" : "_near"), tick => TickNumbers(tick, scattered),
                            validate: (_, after, before) =>
                            {
                                Assert.NotEmpty(numberSamples);
                                Assert.Equal(before.World.Received, after.World.Received);
                                Assert.True(after.Raster.Accepted > before.Raster.Accepted);
                            },
                            offlineAlpha: () => AuditAlpha(lastNumbers, size));
                    }
                    break;
                case "S5":
                    PrepareFx();
                    effects = BuildAuditFx(fxCatalog, highDensity: true);
                    float[] lights = BuildAuditSceneLights();
                    world.SceneLightField(lights, 32, .8f);
                    // Each pair retains one immutable dynamic-light snapshot long enough to exercise the cache.
                    Measure("fx_blood_16_dynamic_32_scene_lights", tick =>
                    {
                        if (tick % 2 == 0) world.CombatFxFrame(effects[tick / 2 % effects.Length], 0, 0, 1);
                    }, validate: (_, after, before) =>
                    {
                        Assert.True(after.Work.LightDraws > before.Work.LightDraws);
                        Assert.True(after.Work.FxUploads > before.Work.FxUploads);
                        Assert.Equal(32u, after.Lights.Count);
                        Assert.True(after.Lights.CacheHits > before.Lights.CacheHits);
                    });
                    break;
                case "S6":
                    PrepareMixed(highDensity: false);
                    for (int leg = 0; leg < AuditAbba.Length; leg++)
                    {
                        bool shake = AuditAbba[leg];
                        if (leg == 1) ColdShake();
                        if (shake) ArmShake();
                        using (hud = new AuditHud(output, world))
                            Measure($"abba_{leg + 1}_{(shake ? "on" : "off")}", tick =>
                            {
                                DriveMixed(tick, tagged: false);
                                if (shake) PulseTick(tick);
                            }, validate: (gpu, after, before) =>
                            {
                                ValidateMixed(gpu, after, before);
                                Assert.True(after.Raster.Accepted > before.Raster.Accepted);
                                Assert.Equal(shake, after.Shake.Value.ActivePasses > before.Shake.Value.ActivePasses);
                            });
                        hud = null;
                        if (shake) ClearActiveShake();
                        ClearDecorations();
                    }
                    break;
                case "S7":
                    PrepareMixed(highDensity: true);
                    PrepareNumbers();
                    SetNumberMode(HitNumberDisplayMode.Balanced);
                    ArmShake();
                    using (hud = new AuditHud(output, world))
                        Measure("joint_high_load", tick =>
                        {
                            DriveMixed(tick, tagged: true);
                            PulseTick(tick);
                            TickNumbers(tick, scattered: true);
                        }, validate: (gpu, after, before) =>
                        {
                            ValidateMixed(gpu, after, before);
                            Assert.True(after.Shake.Value.ActivePasses > before.Shake.Value.ActivePasses);
                            Assert.NotEmpty(numberSamples);
                        }, afterWindow: () => JObject.FromObject(new { bulletSource = VerifyBulletHistory() }));
                    hud = null;
                    ClearActiveShake();
                    break;
                case "S9":
                    PauseAndResume();
                    break;
                case "S10":
                    HandoffViewport();
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(scenario), scenario, "Unknown audit scenario.");
            }
        }

        private void FrozenPresence()
        {
            PrepareBullets();
            PrepareFx();
            using var frozenHud = new AuditHud(output, world);
            frozenHud.Tick(0);
            Pump(() => world.ReadHudRaster().VisibleLayers == 1, scene, "frozen production HUD adoption");
            var withHud = Grab(world);
            var frozenBullet = BuildAuditBullets(bulletCatalog, 1, 64, 1)[0];
            var frozenRay = BuildAuditRays(64)[0];
            var frozenFx = BuildAuditFx(fxCatalog, highDensity: false)[0];
            Assert.True(frozenBullet.InstanceCount > 0 && frozenRay.Count > 0 && frozenFx.Count > 0);
            ulong before = world.Read().Presented;
            world.BulletFrame(frozenBullet, 0, 0, 1);
            world.RayFrame(frozenRay, 0, 0, 1);
            world.CombatFxFrame(frozenFx, 0, 0, 1);
            Pump(() => world.Read().Presented > before && world.ReadHudRaster().VisibleLayers == 1,
                scene, "frozen feature and HUD adoption");
            PixelsUntil(world, scene, frame => !SamePixels(frame, withHud.Pixels), "visible frozen decorations");
            Measure("frozen_nonempty", _ => { }, validate: (_, after, start) =>
            {
                Assert.Equal(start.World.Received, after.World.Received);
                Assert.Equal(start.Raster.Accepted, after.Raster.Accepted);
            });
            ClearDecorations();
            PixelsUntil(world, scene, frame => SamePixels(frame, withHud.Pixels), "frozen decorations cleared");
            MeasureIdle("frozen_cleared");
        }

        private void PrepareBullets()
        {
            bulletCatalog = BulletVisualCatalog.Load(root);
            world.BulletStyles(bulletCatalog);
            Pump(() => world.BulletResourcesReady, scene, "production bullet atlas");
        }

        private void PrepareFx()
        {
            fxCatalog = CombatFxCatalog.Load(root);
            world.CombatFxAtlas(fxCatalog);
            Pump(() => world.CombatFxReady, scene, "production combat FX atlas");
        }

        private void PrepareMixed(bool highDensity)
        {
            PrepareBullets();
            PrepareFx();
            PrepareSource();
            effects = BuildAuditFx(fxCatalog, highDensity);
            bullets = highDensity ? BuildAuditBullets(bulletCatalog, frames + AuditWarmup, 512, sourceEpoch, synced: true)
                : BuildHudCostBullets(bulletCatalog, 180);
            rays = highDensity ? BuildAuditRays(256) : null;
            if (highDensity) world.SceneLightField(BuildAuditSceneLights(), 32, .8f);
        }

        private void ClearDecorations()
        {
            world.ClearBulletFrame();
            world.ClearRayFrame();
            world.ClearCombatFxFrame();
        }

        private void PrepareSource()
        {
            sourceEpoch++;
            source.FixturePaint = PaintSource;
        }

        private void PaintSource(Graphics graphics)
        {
            graphics.Clear(Color.Black);
            using var fill = new SolidBrush(Color.FromArgb(30 + (sourceTick & 1), 80, 140));
            graphics.FillRectangle(fill, new Rectangle(Point.Empty, sourceViewport));
            graphics.FillRectangle(Brushes.Lime, sourceViewport.Width / 4, sourceViewport.Height / 4,
                sourceViewport.Width / 8, sourceViewport.Height / 8);
            if (handoffMarker)
                graphics.FillRectangle(Brushes.Red, sourceViewport.Width * 3 / 4, sourceViewport.Height / 4,
                    sourceViewport.Width / 8, sourceViewport.Height / 8);
            if (sourceEpoch == 0) return;
            // Four production V2 tag cells at logical y=560..576, aligned to source pixel centers.
            float scale = Math.Min(sourceViewport.Width / 1024f, sourceViewport.Height / 576f);
            float left = (sourceViewport.Width - 1024 * scale) / 2, top = (sourceViewport.Height - 576 * scale) / 2;
            for (int i = 0; i < 4; i++)
            {
                using var tag = new SolidBrush(AuditTagColor(i, sourceEpoch, sourceTick));
                graphics.FillRectangle(tag, left + i * 16 * scale, top + 560 * scale, 16 * scale, 16 * scale);
            }
        }

        private void DriveMixed(int tick, bool tagged)
        {
            sourceTick = tick;
            world.BulletFrame(bullets[tick % bullets.Length], 0, 0, 1);
            if (rays != null) world.RayFrame(rays[tick % rays.Length], 0, 0, 1);
            if (effects != null) world.CombatFxFrame(effects[tick % effects.Length], 0, 0, 1);
            if (!tagged) sourceEpoch = 0;
            source.Refresh();
            hud?.Tick(tick);
        }

        private NativeCompositorSession.BulletSourceStats VerifyBulletHistory()
        {
            // This API requests asynchronous GPU tag readback. Call it only after sampling is disabled.
            var initial = world.ReadBulletSource();
            Assert.True(initial.HasValue, "V2 bullet source diagnostics are required for the synced rows.");
            var seen = initial.Value;
            Pump(() =>
            {
                seen = world.ReadBulletSource().Value;
                return seen.SampleNumber > initial.Value.SampleNumber;
            }, scene, "V2 source tag and eight retained snapshots");
            Assert.Equal(1u, seen.Status);
            Assert.Equal(1u, seen.TagValid);
            Assert.Equal(8u, seen.HistoryCount);
            Assert.Equal(sourceEpoch, seen.SourceEpoch);
            Assert.InRange(seen.SourceFrame, sourceTick - 7, sourceTick);
            Assert.Equal(seen.SourceFrame, seen.MatchedOrdinaryFrame);
            Assert.Equal(seen.SourceFrame, seen.MatchedChainFrame);
            Assert.Equal((uint)bullets[0].InstanceCount, seen.MatchedItems);
            return seen;
        }

        private void PrepareNumbers()
        {
            damage = new WorldRasterPresentation();
            damage.Faulted += error => throw new InvalidOperationException("Audit damage raster upload failed.", error);
            damage.Adopt(new OpaqueHudRasterScene(world, 0), output.RectangleToScreen(output.ClientRectangle), true);
            numbers = new HitNumberOverlay(output, output);
            numbers.SetSharedPresentation(damage);
            numbers.SetReady();
            numberRuntime = new HitNumberRuntime(() => numberTime);
        }

        private void SetNumberMode(HitNumberDisplayMode mode)
        {
            numbers.UpdateFrame(numberRuntime.Reset());
            Application.DoEvents();
            numberTime = 1;
            var modeChange = numberRuntime.Configure(new HitNumberRuntimeOptions(mode, 24));
            if (modeChange != null) numbers.UpdateFrame(modeChange);
        }

        private void TickNumbers(int tick, bool scattered)
        {
            numberTime += 1.0 / AuditHz;
            lastNumbers = numberRuntime.ProcessFrame("0|0|1", AuditDamagePacket(tick, scattered));
            Assert.NotNull(lastNumbers);
            numbers.UpdateFrame(lastNumbers);
        }

        private void ArmShake()
        {
            grant++;
            world.SetWorldShakeGrant(grant, clearState: true);
        }

        private void PulseTick(int tick)
        {
            if (tick % 15 == 0) SubmitShake(world, grant);
        }

        private void ColdShake()
        {
            Application.DoEvents();
            Thread.Sleep(60);
            ArmShake();
            Assert.Equal(0ul, world.ReadWorldShake().Value.RtBytes);
            Measure("first_shake_stage_create", tick =>
            {
                // Let any in-flight pre-epoch composition finish on tick 0 so the cold
                // stage allocation always runs under the active sampling epoch.
                if (tick == 1) SubmitAndWaitForActiveShake();
            }, sampleFrames: 5, warmup: 0, temperature: "cold",
                validate: ValidateStaticShake);
            Assert.True(world.ReadWorldShake().Value.RtBytes > 0);
            if (rows.Last["presentationDiag"]["presentationDiagAvailable"].Value<bool>())
                Assert.Equal(1ul, rows.Last["presentationDiag"]["shakeStageCreates"].Value<ulong>());
            ClearActiveShake();
        }

        private void ClearActiveShake()
        {
            var active = SubmitAndWaitForActiveShake();
            ClearShakeAndWait(world, scene, active);
            var cleared = world.ReadWorldShake().Value;
            rows.Last["clear"] = JObject.FromObject(new
            {
                tailPasses = cleared.TailPasses - active.TailPasses,
                cleared.CurrentGrant, cleared.ActiveCount, cleared.TailPending, cleared.LastOffsetX, cleared.LastOffsetY
            });
        }

        private NativeCompositorSession.WorldShakeStats SubmitAndWaitForActiveShake()
        {
            ulong passes = world.ReadWorldShake().Value.ActivePasses;
            SubmitShake(world, grant);
            NativeCompositorSession.WorldShakeStats active = default;
            Pump(() =>
            {
                active = world.ReadWorldShake().Value;
                return active.ActivePasses > passes && (active.LastOffsetX != 0 || active.LastOffsetY != 0);
            }, scene, "nonzero audit shake");
            return active;
        }

        private void PauseAndResume()
        {
            var identity = Grab(world);
            ArmShake();
            Measure("before_pause_shake", PulseTick, validate: ValidateStaticShake);
            var active = SubmitAndWaitForActiveShake();
            world.Active(false);
            world.SetWorldShakeGrant(0, clearState: true);
            SubmitShake(world, grant);
            Assert.Equal(active.RejectedGrant + 1, world.ReadWorldShake().Value.RejectedGrant);
            MeasureIdle("paused_grant_cleared");
            world.Active(true);
            Pump(() =>
            {
                var shake = world.ReadWorldShake().Value;
                return shake.LastOffsetX == 0 && shake.LastOffsetY == 0 && shake.TailPending == 0;
            }, scene, "resume with zero shake");
            var resumed = world.ReadWorldShake().Value;
            Assert.Equal(active.TailPasses + 1, resumed.TailPasses);
            ArmShake();
            AssertRestoredShake();
            Assert.True(SamePixels(Grab(world), identity.Pixels));
            MeasureIdle("resumed_idle");
            rows.Last["pauseAndResume"] = JObject.FromObject(new
            {
                tailPasses = resumed.TailPasses - active.TailPasses,
                rejectedStaleGrant = resumed.RejectedGrant - active.RejectedGrant,
                readmittedGrant = grant, identityPixelsMatch = true
            });
        }

        private void HandoffViewport()
        {
            source.FixturePaint = PaintSource;
            source.Refresh();
            int markX = size.Width * 5 / 16, markY = size.Height * 5 / 16;
            int newX = size.Width * 13 / 16;
            PixelsUntil(world, scene, f => Pixel(f, markX, markY, 0, 255, 0), "original audit viewport");
            ArmShake();
            Measure("before_drs_shake", PulseTick, validate: ValidateStaticShake);
            var active = SubmitAndWaitForActiveShake();
            world.HoldViewport();
            var held = world.Read();
            world.SetWorldShakeGrant(0, clearState: true);
            SubmitShake(world, grant);
            Assert.Equal(active.RejectedGrant + 1, world.ReadWorldShake().Value.RejectedGrant);
            sourceViewport = new Size(size.Width * 3 / 4, size.Height * 3 / 4);
            handoffMarker = true;
            double fence = Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency;
            source.Refresh();
            Application.DoEvents();
            Assert.Equal(held.Presented, world.Read().Presented);
            world.Viewport(new Rectangle(Point.Empty, sourceViewport), fence);
            Pump(() =>
            {
                var stats = world.Read();
                var shake = world.ReadWorldShake().Value;
                return stats.Width == sourceViewport.Width && stats.Height == sourceViewport.Height
                    && stats.LastFrameQpcMs >= fence && stats.Presented > held.Presented
                    && shake.LastOffsetX == 0 && shake.LastOffsetY == 0 && shake.TailPending == 0;
            }, scene, "DRS fresh source fence and zero offset");
            var handedOff = world.Read();
            var cleared = world.ReadWorldShake().Value;
            Assert.Equal(active.TailPasses + 1, cleared.TailPasses);
            Assert.Equal(size, output.ClientSize);
            PixelsUntil(world, scene, f => f.Width == size.Width && f.Height == size.Height
                && Pixel(f, markX, markY, 0, 255, 0) && Pixel(f, newX, markY, 0, 0, 255), "unchanged DRS output geometry");
            ArmShake();
            AssertRestoredShake();
            MeasureIdle("drs_re_admitted_idle");
            rows.Last["viewportHandoff"] = JObject.FromObject(new
            {
                captureBefore = new { width = held.Width, height = held.Height },
                captureAfter = new { width = handedOff.Width, height = handedOff.Height },
                fenceQpcMs = fence, frameQpcMs = handedOff.LastFrameQpcMs,
                presentsWhileHeld = 0, readmittedGrant = grant,
                tailPasses = cleared.TailPasses - active.TailPasses,
                rejectedStaleGrant = cleared.RejectedGrant - active.RejectedGrant
            });
        }

        private void AssertRestoredShake()
        {
            var shake = world.ReadWorldShake().Value;
            Assert.Equal((uint)grant, shake.CurrentGrant);
            Assert.Equal((0u, 0u, 0, 0), (shake.ActiveCount, shake.TailPending, shake.LastOffsetX, shake.LastOffsetY));
        }

        private void MeasureIdle(string phase) => Measure(phase, _ => { }, validate: (gpu, after, before) =>
        {
            Assert.Equal(before.World.Presented, after.World.Presented);
            Assert.Equal(before.World.Received, after.World.Received);
            Assert.Equal(before.Work.Compositions, after.Work.Compositions);
            Assert.Equal(before.Shake?.ActivePasses, after.Shake?.ActivePasses);
            Assert.Equal(before.Shake?.TailPasses, after.Shake?.TailPasses);
            Assert.Equal(0ul, gpu.Completed);
        });

        private static void ValidateStaticShake(NativeCompositorSession.HudCostStats gpu, AuditSnapshot after, AuditSnapshot before)
        {
            Assert.Equal(before.World.Received, after.World.Received);
            Assert.True(after.World.Presented > before.World.Presented);
            Assert.True(after.Shake.Value.Accepted > before.Shake.Value.Accepted);
            Assert.True(after.Shake.Value.ActivePasses > before.Shake.Value.ActivePasses);
            Assert.True(gpu.Completed > 0);
        }

        private static void ValidateMixed(NativeCompositorSession.HudCostStats gpu, AuditSnapshot after, AuditSnapshot before)
        {
            Assert.True(after.World.Received > before.World.Received);
            Assert.True(after.World.Presented > before.World.Presented);
            Assert.True(gpu.Completed > 0);
        }

        internal readonly record struct AuditSnapshot(NativeCompositorSession.Stats World, NativeCompositorSession.WorkStats Work,
            NativeCompositorSession.HudRasterStats Raster, NativeCompositorSession.WorldShakeStats? Shake,
            NativeCompositorSession.SceneLightsStats Lights);

        private AuditSnapshot Snapshot() => new(world.Read(), world.ReadWork().Value, world.ReadHudRaster(),
            world.ReadWorldShake(), world.ReadSceneLights());

        private void Measure(string phase, Action<int> tick,
            Action<NativeCompositorSession.HudCostStats, AuditSnapshot, AuditSnapshot> validate,
            int sampleFrames = 0, int warmup = AuditWarmup, string temperature = "warm",
            Func<object> offlineAlpha = null, Func<JObject> afterWindow = null)
        {
            if (sampleFrames == 0) sampleFrames = frames;
            void Step(int frame)
            {
                tick(frame);
                Application.DoEvents();
                scene.Commit();
            }

            DriveAuditClock(warmup, 0, Step);
            numberSamples.Clear();
            if (numbers != null) numbers.PaintDiagnosticsObserver = numberSamples.Add;
            var before = Snapshot();
            var present = new AuditPresentSamples(world, sampleFrames);
            var driver = new List<double>(sampleFrames);
            world.SetHudCostSampling(true);
            double seconds;
            AuditSnapshot after;
            try
            {
                seconds = DriveAuditClock(sampleFrames, warmup, frame =>
                {
                    long start = Stopwatch.GetTimestamp();
                    Step(frame);
                    driver.Add(Stopwatch.GetElapsedTime(start).TotalMilliseconds);
                }, present.Observe);
                after = Snapshot();
            }
            finally
            {
                world.SetHudCostSampling(false);
                if (numbers != null) numbers.PaintDiagnosticsObserver = null;
            }
            var gpu = AwaitAuditGpu(world);
            var diag = ReadAuditDiag(world);
            Assert.Equal(0ul, after.World.CpuReadbacks - before.World.CpuReadbacks);
            Assert.Equal(0, after.World.Error);
            Assert.Equal(before.Shake?.DroppedCapacity, after.Shake?.DroppedCapacity);
            validate(gpu, after, before);

            if (diag != null)
            {
                Assert.Equal(0ul, diag.Value<ulong>("shakeStageAllocFails"));
                if (after.Work.Compositions == before.Work.Compositions)
                    Assert.Equal(0ul, diag.Value<ulong>("wakeFrozenPresenceOnly") + diag.Value<ulong>("wakeOther")
                        + diag.Value<ulong>("wakeHudVersion") + diag.Value<ulong>("wakeShake") + diag.Value<ulong>("wakeFreshSource"));
                if (after.Shake?.ActivePasses > before.Shake?.ActivePasses)
                    Assert.True(diag.Value<ulong>("activeBlitSamples") > 0);
            }
            var details = afterWindow?.Invoke();
            var hitNumberDiag = numberSamples.Count == 0 ? null : SummarizeHitNumbers(numberSamples,
                after.Raster.CopiedBytes - before.Raster.CopiedBytes, after.Raster.UploadedBytes - before.Raster.UploadedBytes,
                offlineAlpha?.Invoke());
            var row = AuditRow(scenario, variant, size, temperature, repeat, phase,
                new { warmupFrames = warmup, requestedFrames = sampleFrames, seconds, inputHz = AuditHz,
                    presentedHz = (after.World.Presented - before.World.Presented) / seconds,
                    compositionsHz = (after.Work.Compositions - before.Work.Compositions) / seconds,
                    presentIntervals = CostDistribution(present.Intervals), presentObservations = present.Observed,
                    missedPresentObservations = present.Missed, driverCpu = CostDistribution(driver) },
                AuditCounters(before, after), AuditGpuTiming(gpu, diag), PresentDiagEnvelope(diag), hitNumberDiag,
                "Present intervals use only adjacent observed native QPC timestamps inside this phase.",
                "GPU diagnostics use the native sampling epoch and its retained percentile window.",
                hud != null ? "HUD animation exercises the production Combo widget and main HUD painter." : "Fixture pacing is 30 Hz.",
                scenario == "S7" ? "S7 raster byte deltas include damage and production HUD." : "Frame count refers to scheduled fixture ticks.");
            if (details != null) row["workload"] = details;
            rows.Add(row);
            string serialized = row.ToString(Formatting.None);
            Console.WriteLine("PRESENTATION_AUDIT " + serialized);
            if (!string.IsNullOrEmpty(liveLog)) File.AppendAllText(liveLog, serialized + Environment.NewLine);
        }

        public void Dispose()
        {
            numbers?.Dispose();
            damage?.Dispose();
            hud?.Dispose();
        }
    }

    private sealed class AuditHud : IDisposable
    {
        private readonly WorldRasterPresentation presentation;
        private readonly NativeHudOverlay overlay;
        private readonly ComboWidget combo;
        private readonly INativeHudWidget[] widgets;
        private readonly Action render;
        private readonly FieldInfo pending = typeof(NativeHudOverlay)
            .GetField("_renderPending", BindingFlags.Instance | BindingFlags.NonPublic);

        internal AuditHud(Form output, NativeCompositorSession world)
        {
            presentation = new WorldRasterPresentation();
            presentation.Adopt(new OpaqueHudRasterScene(world, 4), output.RectangleToScreen(output.ClientRectangle), true);
            presentation.Faulted += error => throw new InvalidOperationException("Audit main HUD upload failed.", error);
            overlay = new NativeHudOverlay(output, output);
            combo = new ComboWidget(output);
            combo.ForceGameReady(true);
            widgets = new INativeHudWidget[] { combo };
            overlay.AddWidget(combo);
            overlay.SetSharedPresentation(presentation);
            overlay.SetReady();
            render = (Action)Delegate.CreateDelegate(typeof(Action), overlay, typeof(NativeHudOverlay)
                .GetMethod("RenderToBitmapAndCommit", BindingFlags.Instance | BindingFlags.NonPublic));
            Application.DoEvents();
            FreezeHudTimers(overlay);
        }

        internal void Tick(int tick)
        {
            if (tick % 30 == 0) combo.OnNotchNotice("combo", "DFA 连击 " + tick / 30, Color.Orange);
            TickHudCostWidgets(widgets);
            // Drain queued BeginInvoke(RequestRenderFromUi/MaybeStartTick) before freezing timers and rendering.
            Application.DoEvents();
            FreezeHudTimers(overlay);
            if ((bool)pending.GetValue(overlay))
            {
                render();
                pending.SetValue(overlay, false);
            }
            Application.DoEvents();
            FreezeHudTimers(overlay);
        }

        public void Dispose()
        {
            overlay.Dispose();
            presentation.Dispose();
        }
    }

    private sealed class AuditPresentSamples
    {
        private readonly NativeCompositorSession world;
        private NativeCompositorSession.BulletSyncStats previous;
        private bool insideWindow;
        internal readonly List<double> Intervals;
        internal ulong Observed { get; private set; }
        internal ulong Missed { get; private set; }

        internal AuditPresentSamples(NativeCompositorSession world, int frames)
        {
            this.world = world;
            previous = world.ReadBulletSync();
            Intervals = new List<double>(frames);
        }

        internal void Observe()
        {
            // The regular sync counter carries the last successful native Present QPC on
            // every path, including an empty bullet layer. It performs no GPU readback.
            var now = world.ReadBulletSync();
            ulong delta = now.PresentedCount - previous.PresentedCount;
            if (delta == 0) return;
            if (delta == 1 && insideWindow)
                Intervals.Add(now.PresentedQpcMs - previous.PresentedQpcMs);
            Missed += delta - 1;
            Observed++;
            insideWindow = true;
            previous = now;
        }
    }

    private static double DriveAuditClock(int count, int initialTick, Action<int> step, Action observe = null)
    {
        var clock = Stopwatch.StartNew();
        const double interval = 1000.0 / AuditHz;
        double next = 0;
        for (int i = 0; i < count; i++)
        {
            double started = clock.Elapsed.TotalMilliseconds;
            step(initialTick + i);
            // Preserve phase cadence when on time. After a missed deadline, avoid a burst
            // of immediate input submissions that would be coalesced by WGC.
            next += interval;
            if (clock.Elapsed.TotalMilliseconds >= next)
                next = Math.Max(next, started + interval);
            do
            {
                observe?.Invoke();
                Application.DoEvents();
                if (clock.Elapsed.TotalMilliseconds >= next) break;
                Thread.Sleep(1);
            } while (true);
        }
        return clock.Elapsed.TotalSeconds;
    }

    private static NativeCompositorSession.HudCostStats AwaitAuditGpu(NativeCompositorSession world)
    {
        var timer = Stopwatch.StartNew();
        NativeCompositorSession.HudCostStats gpu;
        do
        {
            gpu = world.ReadHudCost();
            if (gpu.Completed + gpu.Disjoint + gpu.Errors + gpu.Dropped >= gpu.Started) break;
            Thread.Sleep(5);
        } while (timer.ElapsedMilliseconds < 5000);
        Assert.Equal(0ul, gpu.Disjoint);
        Assert.Equal(0ul, gpu.Dropped);
        Assert.Equal(0ul, gpu.Errors);
        Assert.Equal((ulong)gpu.Started, gpu.Completed);
        return gpu;
    }

    private static object AuditCounters(AuditFixture.AuditSnapshot before, AuditFixture.AuditSnapshot after) => new
    {
        received = after.World.Received - before.World.Received,
        presented = after.World.Presented - before.World.Presented,
        superseded = after.World.Superseded - before.World.Superseded,
        compositions = after.Work.Compositions - before.Work.Compositions,
        cpuReadbacks = after.World.CpuReadbacks - before.World.CpuReadbacks,
        lightDraws = after.Work.LightDraws - before.Work.LightDraws,
        lightCacheHits = after.Work.LightCacheHits - before.Work.LightCacheHits,
        fxUploads = after.Work.FxUploads - before.Work.FxUploads,
        sceneLightCount = after.Lights.Count,
        sceneLightBuilds = after.Lights.Builds - before.Lights.Builds,
        sceneLightCacheHits = after.Lights.CacheHits - before.Lights.CacheHits,
        rasterAccepted = after.Raster.Accepted - before.Raster.Accepted,
        rasterUploads = after.Raster.Uploads - before.Raster.Uploads,
        copiedBytes = after.Raster.CopiedBytes - before.Raster.CopiedBytes,
        uploadedBytes = after.Raster.UploadedBytes - before.Raster.UploadedBytes,
        shakeAccepted = after.Shake?.Accepted - before.Shake?.Accepted,
        shakeActivePasses = after.Shake?.ActivePasses - before.Shake?.ActivePasses,
        shakeTailPasses = after.Shake?.TailPasses - before.Shake?.TailPasses,
        shakeRejectedGrant = after.Shake?.RejectedGrant - before.Shake?.RejectedGrant,
        shake = after.Shake is { } shake ? new { shake.CurrentGrant, shake.ActiveCount, shake.TailPending,
            shake.LastOffsetX, shake.LastOffsetY, shake.RtBytes } : null,
        captureSize = new { width = after.World.Width, height = after.World.Height }
    };

    private static object AuditGpuTiming(NativeCompositorSession.HudCostStats gpu, JObject diag) => new
    {
        gpu.Started, gpu.Completed, gpu.Retained, gpu.Disjoint, gpu.Errors, gpu.Dropped,
        worldIncludingBlit = new { sumMs = gpu.WorldMsTotal, p50Ms = gpu.WorldP50Ms, p95Ms = gpu.WorldP95Ms, p99Ms = gpu.WorldP99Ms },
        worldPreBlit = diag == null ? null : new
        {
            sumMs = AuditDiagTime(diag, "worldPreBlitMsTotal"), p50Ms = AuditDiagTime(diag, "worldPreBlitP50Ms"),
            p95Ms = AuditDiagTime(diag, "worldPreBlitP95Ms"), p99Ms = AuditDiagTime(diag, "worldPreBlitP99Ms")
        },
        shakeBlitActive = diag == null ? null : new
        {
            samples = diag.Value<ulong>("activeBlitSamples"), sumMs = AuditDiagTime(diag, "shakeBlitActiveMsTotal"),
            p50Ms = AuditDiagTime(diag, "shakeBlitActiveP50Ms"), p95Ms = AuditDiagTime(diag, "shakeBlitActiveP95Ms"),
            p99Ms = AuditDiagTime(diag, "shakeBlitActiveP99Ms")
        },
        hud = new { sumMs = gpu.HudMsTotal, p50Ms = gpu.HudP50Ms, p95Ms = gpu.HudP95Ms, p99Ms = gpu.HudP99Ms },
        componentSumMs = gpu.WorldMsTotal + gpu.HudMsTotal,
        copyCpu = new { gpu.CopySamples, gpu.CopyBytes, gpu.AllocationCpuMs, gpu.CopyCpuMs, gpu.PoolAllocations, gpu.PoolReuses }
    };

    private static JObject PresentDiagEnvelope(JObject diag)
    {
        var result = diag ?? new JObject();
        result["presentationDiagAvailable"] = diag != null;
        return result;
    }

    private static Color AuditTagColor(int index, int epoch, int frame)
    {
        int f0 = frame & 255, f1 = (frame >> 8) & 255, f2 = (frame >> 16) & 255;
        int e0 = epoch & 255, e1 = (epoch >> 8) & 255;
        return index switch
        {
            0 => Color.FromArgb(0x13, 0x57, 0x9B),
            1 => Color.FromArgb(f0, f1, f2),
            2 => Color.FromArgb(e0, e1, (f0 + f1 + f2 + e0 + e1 + 167) & 255),
            _ => Color.FromArgb(255 - f0, 255 - f1, 255 - f2)
        };
    }

    private static BulletVisualFrame[] BuildAuditBullets(BulletVisualCatalog catalog, int frames, int count, int epoch,
        bool synced = false)
    {
        var result = new BulletVisualFrame[frames];
        for (int frame = 0; frame < frames; frame++)
        {
            var items = new BulletVisualInstance[count];
            for (int i = 0; i < items.Length; i++)
                items[i] = new BulletVisualInstance(i % catalog.Styles.Count, 70 + (i * 37 + frame * 9) % 850,
                    60 + (i * 17) % 450, i * 13 % 360, 70, 70, 90);
            result[frame] = BulletVisualFrame.Compose(epoch, frame, items, Array.Empty<BulletVisualInstance>(),
                synced ? epoch : -1, synced ? frame : -1);
        }
        return result;
    }

    private static RayVisualDrawFrame[] BuildAuditRays(int count)
    {
        var engine = new RayVisualEngine();
        var values = Enumerable.Repeat(1f, RayVisualCatalog.FieldNames.Length).ToArray();
        values[0] = 0xFF8800; values[1] = 0xFFDD88; values[2] = 4; values[3] = 90; values[4] = 20; values[5] = 0;
        values[6] = 70; values[7] = 100; values[10] = 35; values[11] = 40; values[14] = .7f;
        values[20] = 60; values[24] = 15; values[25] = 50; values[27] = .6f; values[37] = 1;
        values[41] = 0x7A6F66; values[42] = 0xFFB347; values[47] = 4; values[49] = 0x34302A;
        string fields = string.Join(',', values.Select(value => value.ToString(CultureInfo.InvariantCulture)));
        string[] configs = new[] { 11, 0, 9 }.Select((style, i) => $"c,{i + 1},{style},{fields},-").ToArray();
        var spawns = Enumerable.Range(1, count).Select(i =>
        {
            int config = (i - 1) % configs.Length + 1, x = 40 + i * 83 % 720, y = 40 + i * 31 % 480;
            int kind = config == 1 ? 4 : 0;
            return $"s,{i},{config},0,0,{x},{y},{x + 150},{y + 10},{kind},0,1,0,{i + 123},{i},1,150,1,5,2,-,-,0";
        });
        var result = new RayVisualDrawFrame[40];
        for (int tick = 0; tick < result.Length; tick++)
        {
            string packet = $"1|{tick + 1}|{tick}|0;o,0,0";
            if (tick == 0) packet += ";" + string.Join(';', configs.Concat(spawns));
            Assert.True(RayVisualFrame.TryParse(packet, out var parsed));
            Assert.True(engine.Apply(parsed, 1));
            var draw = engine.BuildDraw();
            Assert.Equal(count, draw.Count);
            result[tick] = new RayVisualDrawFrame(draw.Count) { Count = draw.Count };
            Array.Copy(draw.Data, result[tick].Data, draw.Count * RayVisualCatalog.Stride);
        }
        return result;
    }

    private static CombatFxDrawFrame[] BuildAuditFx(CombatFxCatalog catalog, bool highDensity)
    {
        int muzzle = Array.FindIndex(catalog.Styles, style => style.Linkage == "高爆枪火" && style.IsMuzzle);
        int impact = Array.FindIndex(catalog.Styles, style => style.Linkage == "烈焰火花" && style.IsImpact);
        int casing = Array.FindIndex(catalog.Styles, style => style.Linkage == "步枪弹壳" && style.IsCasing);
        int blood = Array.FindIndex(catalog.Styles, style => style.Linkage == "子弹碎片-飞血" && style.IsBlood);
        Assert.True(muzzle >= 0 && impact >= 0 && casing >= 0 && blood >= 0);
        var engine = new CombatFxEngine(catalog);
        var result = new CombatFxDrawFrame[90];
        int lightCount = highDensity ? 16 : 8;
        for (int tick = 0; tick < result.Length; tick++)
        {
            var records = new List<string> { $"1|{tick + 1}|{tick}|0" };
            for (int i = 0; i < (highDensity ? 24 : 8); i++)
            {
                int x = 64 + (i * 109 + tick * 19) % 890, y = 70 + (i * 41 + tick * 11) % 410;
                int seed = tick * 100 + i + 1;
                records.Add($"i,{impact},{x},{y},150,150,0,{seed},0");
                if (i < (highDensity ? 12 : 4)) records.Add($"m,{muzzle},{x},{y},145,145,0,{seed},0");
                if (highDensity && tick % 6 == 0)
                    records.Add($"p,{seed},{blood},{x},{y},{y + 100},100,{seed}");
            }
            if (highDensity && tick % 12 == 0) records.Add($"s,{casing},470,305,100,100,470,32,{tick + 1},0");
            for (int i = 0; i < lightCount; i++)
            {
                int x = 100 + (i * 97 + tick / 2 * 13) % 820, y = 100 + i * 101 % 380;
                records.Add($"l,{i + 1},0,{x},{y},0,0,96,0,0.65,1,0.7,0.3");
            }
            Assert.True(CombatFxFrame.TryParse(string.Join(';', records), catalog, out var parsed));
            Assert.True(engine.Apply(parsed, 1));
            var draw = engine.BuildDraw();
            Assert.True(draw.Count > 0);
            // Resident lights lead the production list. Fix their count across both
            // ABBA legs even when an authored muzzle also emits a transient light.
            Assert.Equal(lightCount, draw.ResidentLightCount);
            result[tick] = new CombatFxDrawFrame(draw.Count)
            {
                Count = draw.Count, CasingCount = draw.CasingCount, ImpactCount = draw.ImpactCount,
                LightCount = lightCount, MaximumLightResponse = draw.MaximumLightResponse
            };
            Array.Copy(draw.Data, result[tick].Data, draw.Count * 16);
            Array.Copy(draw.Lights, result[tick].Lights, lightCount * 16);
        }
        return result;
    }

    private static float[] BuildAuditSceneLights()
    {
        var lights = new float[32 * 16];
        for (int i = 0; i < 32; i++)
        {
            float[] point = { 80 + i % 8 * 120, 80 + i / 8 * 120, 115, .5f, .35f, .65f, 1, 0 };
            Array.Copy(point, 0, lights, i * 16, point.Length);
        }
        return lights;
    }

    private static string AuditDamagePacket(int tick, bool scattered)
    {
        Point[] positions = scattered
            ? new[] { new Point(74, 110), new Point(918, 112), new Point(105, 508), new Point(927, 506),
                new Point(480, 330), new Point(840, 424) }
            : new[] { new Point(427, 280), new Point(485, 257), new Point(516, 348), new Point(575, 316),
                new Point(597, 380), new Point(468, 402) };
        return string.Join(';', positions.Select((point, target) => target == positions.Length - 1
            ? FormattableString.Invariant($"{120 + tick % 70}|{point.X}|{point.Y}|4194304|||0|0|heal{target}||1")
            : FormattableString.Invariant($"{850 + tick % 90}|{point.X}|{point.Y}|28672|||0|0|unit{target}|burst{tick}.{target}|2;")
                + FormattableString.Invariant($"{500 + tick % 70}|{point.X}|{point.Y}|28672|||0|0|unit{target}|burst{tick}.{target}|2")));
    }

    private static object SummarizeHitNumbers(IReadOnlyCollection<HitNumberPaintDiagnostics> samples,
        ulong copiedBytes, ulong uploadedBytes, object offlineAlphaSparsity)
    {
        object Distribution(Func<HitNumberPaintDiagnostics, double> value) => CostDistribution(samples.Select(value).ToArray());
        return new
        {
            count = samples.Count,
            plan = Distribution(value => value.PlanMs), clear = Distribution(value => value.ClearMs),
            scenePaint = Distribution(value => value.ScenePaintMs), numberPaint = Distribution(value => value.NumberPaintMs),
            graphicsFlush = Distribution(value => value.GraphicsFlushMs), gdiFlush = Distribution(value => value.GdiFlushMs),
            presentSubmit = Distribution(value => value.PresentSubmitMs),
            plannedPixels = samples.Sum(value => (long)value.PlannedWidth * value.PlannedHeight),
            maxPlannedPixels = samples.Max(value => (long)value.PlannedWidth * value.PlannedHeight),
            maxDibCapacityPixels = samples.Max(value => (long)value.DibCapacityWidth * value.DibCapacityHeight),
            maxWorldRows = samples.Max(value => value.WorldRowCount), maxItems = samples.Max(value => value.ItemCount),
            copiedBytes, uploadedBytes, offlineAlphaSparsity
        };
    }

    private static AuditAlphaStats AuditAlpha(HitNumberRuntimeSnapshot snapshot, Size size)
    {
        float scale = Math.Min(size.Width / 1024f, size.Height / 576f);
        var region = HitNumberRenderPlanner.Plan(snapshot.Frame, 1024 * scale, 576 * scale);
        Assert.False(region.IsEmpty);
        using var bitmap = new Bitmap(region.PixelBounds.Width, region.PixelBounds.Height, PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        using (var scenePainter = new HitNumberScenePainter())
        using (var numberPainter = new HitNumberPainter())
        {
            graphics.Clear(Color.Transparent);
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            scenePainter.DrawWorldRows(graphics, region.LocalViewport, snapshot.Frame.WorldRows, snapshot.Mode);
            numberPainter.Paint(graphics, snapshot.Frame.Items, new HitNumberPaintContext(region.LocalViewport));
            graphics.Flush(FlushIntention.Sync);
        }
        long nonzero = 0;
        var data = bitmap.LockBits(new Rectangle(Point.Empty, bitmap.Size), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        try
        {
            var line = new byte[checked(bitmap.Width * 4)];
            for (int y = 0; y < bitmap.Height; y++)
            {
                Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), line, 0, line.Length);
                for (int x = 3; x < line.Length; x += 4) if (line[x] != 0) nonzero++;
            }
        }
        finally { bitmap.UnlockBits(data); }
        long planned = (long)bitmap.Width * bitmap.Height;
        Assert.InRange(nonzero, 1, planned - 1);
        return new AuditAlphaStats(nonzero, planned, nonzero / (double)planned, 1 - nonzero / (double)planned);
    }

    private sealed record AuditAlphaStats(long nonzeroAlphaPixels, long plannedPixels,
        double nonzeroAlphaRatio, double transparentHoleRate);

    internal static void VerifyPresentationAuditReportContract()
    {
        VerifyAuditDiagLayout();
        var diag = new NativeCompositorSession.PresentationDiagStats { Size = 232, WakeFrozenPresenceOnly = 121, WorldPreBlitP95Ms = 1.7 };
        var available = PresentDiagEnvelope(AuditDiagJson(diag));
        Assert.True(available.Value<bool>("presentationDiagAvailable"));
        Assert.Equal(121ul, available.Value<ulong>("wakeFrozenPresenceOnly"));
        Assert.Equal(1.7, available.Value<double>("worldPreBlitP95Ms"));
        Assert.Equal(AuditDiagFields.Length + 1, available.Count);

        Assert.Equal(new[] { false, true, true, false }, AuditAbba);
        var size = AuditSize("1920x1080");
        var row = AuditRow("S0b", "test", size, "warm", 1, "frozen_nonempty",
            new { requestedFrames = 240 }, new { presented = 121, compositions = 121 },
            AuditGpuTiming(default, null), PresentDiagEnvelope(null), null);
        var report = AuditReport("test", "candidate", "identity", "closure", "core", "candidateCore",
            "native", "adapter", 0x8086, new JArray(row));
        var parsed = JObject.Parse(report.ToString(Formatting.None));
        Assert.Equal(new[] { "schema", "evidenceLevel", "variant", "candidate", "buildIdentity", "payloadClosure", "coreSha256",
            "candidateCoreSha256", "nativeSha256", "adapter", "vendorId", "rows" }, parsed.Properties().Select(p => p.Name));
        Assert.Equal("cf7-native-presentation-audit.v1", parsed.Value<string>("schema"));
        Assert.Equal("synthetic_owned_window", parsed.Value<string>("evidenceLevel"));
        Assert.Equal(0x8086u, parsed.Value<uint>("vendorId"));
        var parsedRow = Assert.IsType<JObject>(Assert.Single((JArray)parsed["rows"]));
        Assert.Equal(new[] { "scenario", "variant", "outputSize", "coldOrWarm", "repeat", "phase", "samples", "counters",
            "gpuTiming", "presentationDiag", "hitNumberDiag", "limitations" }, parsedRow.Properties().Select(p => p.Name));
        Assert.Equal(1920, parsedRow["outputSize"].Value<int>("width"));
        Assert.Equal(1080, parsedRow["outputSize"].Value<int>("height"));
        Assert.False(parsedRow["presentationDiag"].Value<bool>("presentationDiagAvailable"));
        Assert.Equal(JTokenType.Null, parsedRow["gpuTiming"]["worldPreBlit"].Type);
    }

    internal static void VerifyPresentationAuditInputs()
    {
        foreach (int count in new[] { 64, 256 })
        {
            var rays = BuildAuditRays(count).Last();
            var styles = Enumerable.Range(0, rays.Count).Select(i => (int)rays.Data[i * RayVisualCatalog.Stride + 15]);
            Assert.Equal(new[] { 0, 9, 11 }, styles.Distinct().OrderBy(style => style));
        }
        string root = AuditProjectRoot();
        var bullets = BuildAuditBullets(BulletVisualCatalog.Load(root), 8, 512, 12, synced: true);
        Assert.All(bullets, frame => Assert.Equal((12, frame.Frame, 512, true),
            (frame.ChainEpoch, frame.ChainFrame, frame.InstanceCount, frame.NativeOwned)));
        Assert.Equal(8, bullets.Select(frame => frame.Frame).Distinct().Count());
        var fxCatalog = CombatFxCatalog.Load(root);
        Assert.All(BuildAuditFx(fxCatalog, highDensity: false), frame => Assert.Equal(8, frame.LightCount));
        var dense = BuildAuditFx(fxCatalog, highDensity: true);
        Assert.All(dense, frame => Assert.Equal(16, frame.LightCount));
        Assert.Contains(dense, frame => frame.CasingCount > 0 && frame.ImpactCount > 24 && frame.Count > 64);
        foreach (var mode in new[] { HitNumberDisplayMode.Balanced, HitNumberDisplayMode.Total,
            HitNumberDisplayMode.Detail, HitNumberDisplayMode.Classic })
        {
            AuditAlphaStats Render(bool scattered)
            {
                double now = 1;
                var runtime = new HitNumberRuntime(() => now);
                runtime.Configure(new HitNumberRuntimeOptions(mode, 24));
                HitNumberRuntimeSnapshot snapshot = null;
                for (int i = 0; i < 12; i++)
                {
                    now += 1.0 / AuditHz;
                    snapshot = runtime.ProcessFrame("0|0|1", AuditDamagePacket(i, scattered));
                }
                Assert.Contains(snapshot.Frame.Items, item => item.Kind == CombatNumberKind.HealHp);
                Assert.Contains(snapshot.Frame.Items, item => item.Kind == CombatNumberKind.Damage);
                return AuditAlpha(snapshot, new Size(1024, 576));
            }
            var near = Render(false);
            var scattered = Render(true);
            Assert.True(scattered.plannedPixels > near.plannedPixels, mode.ToString());
            Assert.True(scattered.transparentHoleRate > near.transparentHoleRate, mode.ToString());
        }
    }
}
