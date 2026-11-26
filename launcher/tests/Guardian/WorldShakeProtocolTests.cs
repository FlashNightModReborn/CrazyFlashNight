using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using CF7Launcher.Bus;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class WorldShakeProtocolTests
    {
        private const string Header = "1|1|1|0";
        private const string Light = "l,1,0,0,0,0,0,100,0,1,1,1,1";
        private static readonly CombatFxCatalog EmptyCatalog = CombatFxCatalog.ForResidentLights(new WorldLightSettings());

        [Fact]
        public void StatsMatchFrozenNativeAbi() => Assert.Equal(88, Marshal.SizeOf<NativeCompositorSession.WorldShakeStats>());

        [Fact]
        public void PresentationDiagStatsMatchesNativeAbi() => Assert.Equal(232, Marshal.SizeOf<NativeCompositorSession.PresentationDiagStats>());

        [Theory]
        [InlineData(0, true)]
        [InlineData(1, true)]
        [InlineData(8, true)]
        [InlineData(9, false)]
        public void EmptyAtlasAcceptsOnlyBoundedShakeBatches(int count, bool valid)
        {
            Assert.Empty(EmptyCatalog.Styles);
            string payload = Header + string.Concat(Enumerable.Repeat(";h,1000000000,7,-1000000,1000000", count));
            Assert.Equal(valid, CombatFxFrame.TryParse(payload, EmptyCatalog, out var frame));
            if (!valid) { Assert.Null(frame); return; }
            Assert.Equal(count, frame.Shakes.Length);
            Assert.All(frame.Shakes, h => Assert.Equal((1_000_000_000, 7, -1_000_000f, 1_000_000f),
                (h.Grant, h.Profile, h.X, h.Y)));
        }

        [Fact]
        public void FullLegacyCategoriesAndEightShakesFitIn265Records()
        {
            var root = new DirectoryInfo(AppContext.BaseDirectory);
            while (root != null && !File.Exists(Path.Combine(root.FullName, CombatFxCatalog.RelativePath))) root = root.Parent;
            Assert.NotNull(root);
            var catalog = CombatFxCatalog.Load(root.FullName);
            int casing = catalog.Styles.First(style => style.IsCasing).Index;
            int muzzle = catalog.Styles.First(style => style.IsMuzzle).Index;
            int impact = catalog.Styles.First(style => style.IsImpact).Index;
            int blood = catalog.Styles.First(style => style.IsBlood).Index;
            string payload = string.Join(';', new[] { Header }
                .Concat(Enumerable.Repeat($"s,{casing},10,20,100,100,0,1,1,0", 16))
                .Concat(Enumerable.Repeat($"m,{muzzle},10,20,100,100,0,1,0", 16))
                .Concat(Enumerable.Repeat($"i,{impact},10,20,100,100,0,1,0", 32))
                .Concat(Enumerable.Range(1, 64).Select(id => $"a,{id},1"))
                .Concat(Enumerable.Range(1, 64).Select(id => $"l,{id},0,0,0,0,0,100,0,1,1,1,1"))
                .Concat(Enumerable.Range(1, 64).Select(id => $"p,{id},{blood},10,20,0,100,1"))
                .Concat(Enumerable.Repeat("h,1,7,0,0", 8)));
            Assert.Equal(265, payload.Count(ch => ch == ';') + 1);
            Assert.True(CombatFxFrame.TryParse(payload, catalog, out var frame));
            Assert.Equal(64, frame.Spawns.Length);
            Assert.Equal(64, frame.Acks.Length);
            Assert.Equal(64, frame.EquipmentLights.Length);
            Assert.Equal(64, frame.BloodEvents.Length);
            Assert.Equal(8, frame.Shakes.Length);
            Assert.False(CombatFxFrame.TryParse(payload + ";h,1,7,0,0", catalog, out frame));
            Assert.Null(frame);
        }

        [Fact]
        public void PayloadCharacterLimitRemains32768()
        {
            string payload = Header + ";h,1,7,0,0";
            payload = payload.PadRight(32768);
            Assert.True(CombatFxFrame.TryParse(payload, EmptyCatalog, out _));
            Assert.False(CombatFxFrame.TryParse(payload + " ", EmptyCatalog, out var frame));
            Assert.Null(frame);
        }

        [Theory]
        [InlineData("h,1,0,0,0")]
        [InlineData("h,1,8,0,0")]
        [InlineData("h,0,1,0,0")]
        [InlineData("h,-1,1,0,0")]
        [InlineData("h,1000000001,1,0,0")]
        [InlineData("h,1.0,1,0,0")]
        [InlineData("h,1,7,NaN,0")]
        [InlineData("h,1,7,0,Infinity")]
        [InlineData("h,1,7,1e999,0")]
        [InlineData("h,1,7,1000000.01,0")]
        [InlineData("h,1,7,0,-1000001")]
        [InlineData("h,1,7,0")]
        [InlineData("h,1,7,0,0,0")]
        public void MalformedShakeRejectsWholeFrame(string record)
        {
            string payload = Header + ";" + Light + ";h,1,7,0,0;" + record;
            Assert.False(CombatFxFrame.TryParse(payload, EmptyCatalog, out var frame));
            Assert.Null(frame);
        }

        [Fact]
        public void BlurRotatesGrantAndOnlyMatchingImpulsesAreForwarded()
        {
            var fixture = new GateFixture(ownerFocused: false);
            Assert.Equal(0, fixture.Gate.ActiveGrant);
            fixture.Gate.SetOwnerFocused(true);
            fixture.Gate.AdmitIfReady();
            int old = fixture.Gate.ActiveGrant;
            Assert.True(old > 0);
            fixture.Gate.SetOwnerFocused(false);
            Assert.Equal(0, fixture.Gate.ActiveGrant);
            Assert.Equal(("native", 0), fixture.Caps[^2]);
            Assert.Equal(("caps", 0), fixture.Caps[^1]);
            fixture.Gate.SetOwnerFocused(true);
            fixture.Gate.AdmitIfReady();
            int current = fixture.Gate.ActiveGrant;
            Assert.True(current > old);
            Assert.Equal(("native", current), fixture.Caps[^2]);
            Assert.Equal(("caps", current), fixture.Caps[^1]);

            fixture.Gate.Observe(new[] { Impulse(old), Impulse(current), Impulse(old) }, 12, 34, 1.5f);
            var submission = Assert.Single(fixture.Submissions);
            Assert.Equal((current, 12f, 34f, 1.5f), (submission.Grant, submission.X, submission.Y, submission.Scale));
            Assert.Equal(current, Assert.Single(submission.Impulses).Grant);
            Assert.Equal(2ul, fixture.Gate.StaleGrantDropped);
            Assert.Equal(current, fixture.Gate.ActiveGrant);
        }

        [Theory]
        [InlineData("scene")]
        [InlineData("capture stop")]
        [InlineData("disconnect")]
        [InlineData("legacy damage")]
        [InlineData("toggle")]
        [InlineData("allocation fault")]
        [InlineData("modal")]
        public void EveryBarrierClearsAndRequiresAFreshGrant(string barrier)
        {
            var fixture = new GateFixture();
            var gate = fixture.Gate;
            Action<bool> allow = barrier switch {
                "scene" => gate.SetSceneReady,
                "capture stop" => ready => {
                    if (ready) { gate.SetNativeReady(true); gate.SetSceneReady(true); }
                    else gate.ResetCapture();
                },
                "disconnect" => ready => {
                    gate.SetConnectionReady(ready);
                    if (ready) gate.SetSceneReady(true);
                },
                "legacy damage" => gate.SetSharedDamageReady,
                "toggle" => gate.SetFeatureEnabled,
                "allocation fault" => gate.SetNativeReady,
                "modal" => ready => gate.SetModalBlocked(!ready),
                _ => throw new ArgumentException(nameof(barrier))
            };
            int old = gate.ActiveGrant;
            allow(false);
            Assert.Equal(0, gate.ActiveGrant);
            Assert.Contains(("native", 0), fixture.Caps);
            if (barrier != "disconnect") Assert.Equal(("caps", 0), fixture.Caps[^1]);
            gate.AdmitIfReady();
            Assert.Equal(0, gate.ActiveGrant);
            allow(true);
            gate.AdmitIfReady();
            Assert.True(gate.ActiveGrant > old);
            gate.Observe(new[] { Impulse(old), Impulse(gate.ActiveGrant) }, 0, 0, 1);
            Assert.Equal(gate.ActiveGrant, Assert.Single(Assert.Single(fixture.Submissions).Impulses).Grant);
        }

        [Theory]
        [InlineData(true, false)]
        [InlineData(true, true)]
        [InlineData(false, false)]
        [InlineData(false, true)]
        public void AnyEnabledWorldAnchoredConsumerLosingReadinessRevokesTheGrant(bool damageFailsFirst, bool fallback)
        {
            var fixture = new GateFixture();
            var gate = fixture.Gate;
            gate.SetUnitLifeWorldAnchorState(enabled: true, available: true, fallback: false);
            int old = gate.ActiveGrant;

            if (damageFailsFirst)
                gate.SetDamageWorldAnchorState(available: fallback, fallback: fallback);
            else
                gate.SetUnitLifeWorldAnchorState(enabled: true, available: fallback, fallback: fallback);

            Assert.Equal(0, gate.ActiveGrant);
            Assert.Equal(("native", 0), fixture.Caps[^2]);
            Assert.Equal(("caps", 0), fixture.Caps[^1]);
            gate.AdmitIfReady();
            Assert.Equal(0, gate.ActiveGrant);

            if (damageFailsFirst)
            {
                gate.SetUnitLifeWorldAnchorState(enabled: true, available: false, fallback: false);
                gate.SetDamageWorldAnchorState(available: true, fallback: false);
            }
            else
            {
                gate.SetDamageWorldAnchorState(available: false, fallback: false);
                gate.SetUnitLifeWorldAnchorState(enabled: true, available: true, fallback: false);
            }
            gate.AdmitIfReady();
            Assert.Equal(0, gate.ActiveGrant);

            gate.SetDamageWorldAnchorState(available: true, fallback: false);
            gate.SetUnitLifeWorldAnchorState(enabled: true, available: true, fallback: false);
            gate.AdmitIfReady();
            Assert.True(gate.ActiveGrant > old);
            gate.Observe(new[] { Impulse(old), Impulse(gate.ActiveGrant) }, 0, 0, 1);
            Assert.Equal(gate.ActiveGrant, Assert.Single(Assert.Single(fixture.Submissions).Impulses).Grant);
        }

        [Fact]
        public void UnitLifeStartsBlockingOnlyWhenEnabledAndUnready()
        {
            var fixture = new GateFixture();
            var gate = fixture.Gate;
            int old = gate.ActiveGrant;
            Assert.True(old > 0);

            gate.SetUnitLifeWorldAnchorState(enabled: false, available: false, fallback: true);
            Assert.Equal(old, gate.ActiveGrant);
            gate.SetUnitLifeWorldAnchorState(enabled: true, available: false, fallback: false);
            Assert.Equal(0, gate.ActiveGrant);
            gate.AdmitIfReady();
            Assert.Equal(0, gate.ActiveGrant);

            gate.SetUnitLifeWorldAnchorState(enabled: false, available: false, fallback: true);
            gate.AdmitIfReady();
            Assert.True(gate.ActiveGrant > old);
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void FailedCapsSendRetriesSameNativeGrantAtBoundedIntervals(bool republishOtherCaps)
        {
            var fixture = new GateFixture(ownerFocused: false) { CanSend = false };
            fixture.Gate.SetOwnerFocused(true);
            fixture.Gate.AdmitIfReady();
            Assert.Equal(0, fixture.Gate.ActiveGrant);
            Assert.Equal(new[] { ("native", 1), ("caps", 1) }, fixture.Caps);
            fixture.Gate.Observe(new[] { Impulse(1) }, 0, 0, 1);
            Assert.Empty(fixture.Submissions);
            fixture.Now = 499;
            fixture.Gate.AdmitIfReady();
            Assert.False(fixture.Gate.PublishCurrentCaps());
            Assert.Equal(2, fixture.Caps.Count);
            fixture.CanSend = true;
            fixture.Now = 500;
            if (republishOtherCaps) Assert.True(fixture.Gate.PublishCurrentCaps());
            else fixture.Gate.AdmitIfReady();
            Assert.Equal(new[] { ("native", 1), ("caps", 1), ("caps", 1) }, fixture.Caps);
            Assert.Equal(1, fixture.Gate.ActiveGrant);

            fixture.CanSend = false;
            fixture.Gate.SetSourcePaused(true);
            int writes = fixture.Caps.Count;
            fixture.Now = 999;
            fixture.Gate.RetryRevocation();
            Assert.Equal(writes, fixture.Caps.Count);
            fixture.CanSend = true;
            fixture.Now = 1000;
            fixture.Gate.RetryRevocation();
            Assert.Equal(writes + 1, fixture.Caps.Count);
            Assert.Equal(("caps", 0), fixture.Caps[^1]);
        }

        [Fact]
        public void ExhaustionNeverWrapsAcrossReconnectionsOrNewGates()
        {
            var sequence = new WorldShakeGrantSequence(WorldShakeGrantSequence.Maximum - 1);
            var fixture = new GateFixture(sequence: sequence);
            Assert.Equal(WorldShakeGrantSequence.Maximum, fixture.Gate.ActiveGrant);
            fixture.Gate.SetConnectionReady(false);
            fixture.Gate.SetConnectionReady(true);
            fixture.Gate.SetSceneReady(true);
            fixture.Gate.AdmitIfReady();
            Assert.Equal(0, fixture.Gate.ActiveGrant);
            Assert.Equal(0, new GateFixture(sequence: sequence).Gate.ActiveGrant);
        }

        [Fact]
        public void PauseEdgesUseExactSegmentsAndTheCurrentGenerationBeforeFirstF6()
        {
            var fixture = new GateFixture();
            var task = new FrameTask(null, null);
            var edges = new List<bool>();
            int clears = 0;
            task.WorldShakePauseObserved = paused => { edges.Add(paused); fixture.Gate.SetSourcePaused(paused); };
            task.WorldShakeCleared = () => clears++;
            task.ObserveShakePauseUi("p:1", 0);
            task.ObserveShakePauseUi("other:p:1|p:1a| p:1|p:0 |p:1|||p:0", 5);
            task.ObserveShakePauseUi("p:1", 4);
            task.ResetCombatFxForGeneration(4);
            Assert.Equal(new[] { true, false }, edges);
            Assert.Equal(0, clears);
            Assert.Equal(0, fixture.Gate.ActiveGrant);
            fixture.Gate.AdmitIfReady();
            Assert.Equal(2, fixture.Gate.ActiveGrant);
            task.HandleReset();
            task.ResetCombatFxForGeneration(5);
            task.ObserveShakePauseUi("p:1", 5);
            Assert.Equal(2, clears);
            Assert.Equal(new[] { true, false }, edges);
            task.ObserveShakePauseUi("p:1", 6);
            Assert.Equal(new[] { true, false, true }, edges);
        }

        [Fact]
        public void PausedF6RevokesAndUnpausedF6CannotResumeWithoutAnEdge()
        {
            var fixture = new GateFixture();
            var task = new FrameTask(null, null);
            task.ConfigureCombatFx(EmptyCatalog);
            task.WorldShakePauseObserved = fixture.Gate.SetSourcePaused;
            task.WorldShakeObserved = (h, x, y, scale) => fixture.Gate.Observe(h, x, y, scale);
            int old = fixture.Gate.ActiveGrant;
            task.HandleRaw("12|34|1.5", "", "", "", connectionGeneration: 5, combatFxPayload: $"1|1|1|1;h,{old},7,0,0");
            Assert.Equal(0, fixture.Gate.ActiveGrant);
            Assert.Equal(0ul, fixture.Gate.StaleGrantDropped);
            task.HandleRaw("12|34|1.5", "", "", "", connectionGeneration: 5, combatFxPayload: $"1|2|2|0;h,{old},7,0,0");
            fixture.Gate.AdmitIfReady();
            Assert.Equal(0, fixture.Gate.ActiveGrant);
            Assert.Empty(fixture.Submissions);
            task.ObserveShakePauseUi("p:0", 5);
            fixture.Gate.AdmitIfReady();
            Assert.True(fixture.Gate.ActiveGrant > old);
        }

        [Theory]
        [InlineData(false, "p:1")]
        [InlineData(false, "p:1|p:0")]
        [InlineData(true, "p:1")]
        [InlineData(true, "p:1|p:0")]
        public async Task XmlSocketServerObservesPauseBeforeHandleRawAndKeepsOtherRecords(bool useU, string edges)
        {
            var fixture = new GateFixture();
            var task = new FrameTask(null, null);
            task.ConfigureCombatFx(EmptyCatalog);
            var grantsAtHandleRaw = new List<int>();
            var lightCounts = new List<int>();
            int rejected = 0;
            task.VisualFrameStarted = () => grantsAtHandleRaw.Add(fixture.Gate.ActiveGrant);
            task.CombatFxObserved = (draw, _, _, _) => lightCounts.Add(draw.LightCount);
            task.CombatFxRejected = () => rejected++;
            task.WorldShakePauseObserved = fixture.Gate.SetSourcePaused;
            task.WorldShakeObserved = (h, x, y, scale) => fixture.Gate.Observe(h, x, y, scale);
            var workDone = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var router = new MessageRouter();
            router.RegisterSync("shake_test_barrier", _ => { workDone.TrySetResult(); return null; });
            using var server = new XmlSocketServer(router, AllowLoopbackXmlSocketPeerAuthority.Instance);
            server.SetFrameHandler(task);
            var probe = new TcpListener(IPAddress.Loopback, 0);
            probe.Start();
            int port = ((IPEndPoint)probe.LocalEndpoint).Port;
            probe.Stop();
            Assert.True(server.Start(port));
            using var client = new TcpClient(AddressFamily.InterNetwork);
            await client.ConnectAsync(IPAddress.Loopback, port);
            int old = fixture.Gate.ActiveGrant;

            async Task Send(string packet)
            {
                workDone = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                await client.GetStream().WriteAsync(Encoding.UTF8.GetBytes(packet + "\0{\"task\":\"shake_test_barrier\"}\0"));
                await workDone.Task.WaitAsync(TimeSpan.FromSeconds(5));
            }

            const string frameStart = "F12|34|1.5\u0001";
            string combat = "\u0006" + Header + $";h,{old},7,0,0;" + Light;
            await Send(useU ? "U" + edges + "\0" + frameStart + combat : frameStart + "\u0003" + edges + combat);
            Assert.Equal(0, Assert.Single(grantsAtHandleRaw));
            Assert.Equal(1, Assert.Single(lightCounts));
            Assert.Equal(0, rejected);
            Assert.Empty(fixture.Submissions);
            Assert.Equal(1ul, fixture.Gate.StaleGrantDropped);

            // A ready tick can follow the resume edge. A replay stays deduplicated,
            // and a new packet carrying only an h record still clears the omitted
            // resident light snapshot while forwarding the shake to native.
            if (edges == "p:1") await Send("Up:0");
            fixture.Gate.AdmitIfReady();
            int current = fixture.Gate.ActiveGrant;
            Assert.True(current > old);
            await Send(frameStart + "\u0006" + Header + $";h,{current},7,0,0\0"
                + frameStart + $"\u00061|2|2|0;h,{current},7,0,0");
            Assert.Equal(new[] { 1, 0 }, lightCounts);
            Assert.Equal(0, rejected);
            var submission = Assert.Single(fixture.Submissions);
            Assert.Equal((current, 12f, 34f, 1.5f), (submission.Grant, submission.X, submission.Y, submission.Scale));
        }

        [Fact]
        public void CatalogLoadsRepositoryConfigAndPacksNativeProfiles()
        {
            var root = new DirectoryInfo(AppContext.BaseDirectory);
            while (root != null && !File.Exists(Path.Combine(root.FullName, WorldShakeCatalog.RelativePath))) root = root.Parent;
            Assert.NotNull(root);
            string path = Path.Combine(root.FullName, WorldShakeCatalog.RelativePath);
            var catalog = WorldShakeCatalog.LoadStrict(path);
            Assert.Equal(64, catalog.Sha256.Length);
            Assert.Equal(7, catalog.Profiles.Length);
            Assert.Equal(14f, catalog.MaxTotalOffsetStagePx);
            Assert.Equal(31, catalog.TailTicks);
            Assert.Equal(new[] { 0, 1, 2, 5, 3, 6, 7, 4 }, catalog.Priorities);
            Assert.Equal(new[] { 7 }, catalog.ScreenWideProfileIds);
            Assert.Equal(2, catalog.BulletBindings["普通爆炸"]);
            Assert.Equal(2, catalog.BulletBindings["火焰集束手雷爆炸"]);
            Assert.Equal(2, catalog.BulletBindings["火焰集束爆炸声"]);
            Assert.Equal(5, catalog.BulletBindings["核弹爆炸"]);
            Assert.Equal(7, catalog.EffectBindings["小地震"]);
            Assert.False(catalog.BulletBindings.ContainsKey("量子爆弹"));
            float[] packed = catalog.PackNativeProfiles();
            Assert.Equal(35, packed.Length);
            Assert.Equal(1f, packed[0]);
            Assert.Equal(3.5f, packed[1]);
            Assert.Equal(8f, packed[2]);
            Assert.Equal(22f, packed[3]);
            Assert.Equal(900f, packed[4]);
        }

        [Fact]
        public void CustomProfileCatalogExtendsFrameBoundsAndFallsBackOnCorruption()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "cf7_shake_cat_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path.Combine(tempDir, "data", "combat_visuals"));
            try
            {
                string file = Path.Combine(tempDir, WorldShakeCatalog.RelativePath.Replace('/', Path.DirectorySeparatorChar));
                File.WriteAllText(file, """
                {
                  "schema": "cf7-screen-shake.v1",
                  "ticksPerSecond": 30,
                  "maxTotalOffsetStagePx": 10,
                  "profiles": [
                    { "id": 1, "name": "p1", "priority": 1, "amplitude": 2, "ticks": 6, "frequency": 20, "radius": 800 },
                    { "id": 2, "name": "p2", "priority": 2, "amplitude": 3, "ticks": 8, "frequency": 18, "radius": 900 },
                    { "id": 3, "name": "p3", "priority": 3, "amplitude": 4, "ticks": 10, "frequency": 16, "radius": 1000 },
                    { "id": 4, "name": "p4", "priority": 4, "amplitude": 5, "ticks": 12, "frequency": 15, "radius": 1100 },
                    { "id": 5, "name": "p5", "priority": 5, "amplitude": 6, "ticks": 14, "frequency": 14, "radius": 1200 },
                    { "id": 6, "name": "p6", "priority": 6, "amplitude": 7, "ticks": 16, "frequency": 13, "radius": 1300 },
                    { "id": 7, "name": "p7", "priority": 7, "amplitude": 8, "ticks": 18, "frequency": 12, "radius": 0 },
                    { "id": 8, "name": "mega", "priority": 9, "amplitude": 11, "ticks": 36, "frequency": 11, "radius": 0 }
                  ],
                  "bindings": {
                    "bullets": { "测试新爆": "mega" },
                    "effects": { "测试新震": "mega" },
                    "exemptBullets": ["豁免弹"]
                  }
                }
                """, Encoding.UTF8);
                var custom = WorldShakeCatalog.LoadStrict(file);
                Assert.Equal(8, custom.MaxProfileId);
                Assert.Equal(37, custom.TailTicks);
                Assert.Equal(new[] { 7, 8 }, custom.ScreenWideProfileIds);
                Assert.Equal(8, custom.BulletBindings["测试新爆"]);
                Assert.Equal(8, custom.EffectBindings["测试新震"]);
                Assert.True(CombatFxFrame.TryParse(Header + ";h,1,8,0,0", EmptyCatalog, out var frame, custom.MaxProfileId));
                Assert.Equal(8, Assert.Single(frame.Shakes).Profile);
                Assert.False(CombatFxFrame.TryParse(Header + ";h,1,9,0,0", EmptyCatalog, out _, custom.MaxProfileId));

                // Overlapping exemptBullets and unknown target must fail strict load and fall back via Load.
                File.WriteAllText(file, """
                {
                  "schema": "cf7-screen-shake.v1",
                  "ticksPerSecond": 30,
                  "maxTotalOffsetStagePx": 10,
                  "profiles": [
                    { "id": 1, "name": "p1", "priority": 1, "amplitude": 2, "ticks": 6, "frequency": 20, "radius": 800 }
                  ],
                  "bindings": {
                    "bullets": { "冲突弹": "p1" },
                    "effects": {},
                    "exemptBullets": ["冲突弹"]
                  }
                }
                """, Encoding.UTF8);
                Assert.Throws<InvalidDataException>(() => WorldShakeCatalog.LoadStrict(file));
                string warning = null;
                var fallback = WorldShakeCatalog.Load(tempDir, msg => warning = msg);
                Assert.NotNull(warning);
                Assert.Same(WorldShakeCatalog.Default, fallback);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        private static CombatFxShakeImpulse Impulse(int grant) => new(grant, 7, 0, 0);

        private sealed class GateFixture
        {
            internal readonly WorldShakeGrantGate Gate;
            internal readonly List<(string Operation, int Grant)> Caps = new();
            internal readonly List<(int Grant, CombatFxShakeImpulse[] Impulses, float X, float Y, float Scale)> Submissions = new();
            internal bool CanSend = true;
            internal double Now;

            internal GateFixture(bool ownerFocused = true, WorldShakeGrantSequence sequence = null)
            {
                Gate = new WorldShakeGrantGate(sequence ?? new WorldShakeGrantSequence(),
                    grant => Caps.Add(("native", grant)),
                    grant => { Caps.Add(("caps", grant)); return CanSend; },
                    (grant, impulses, x, y, scale) => Submissions.Add((grant, impulses.ToArray(), x, y, scale)),
                    () => Now, ownerFocused);
                Gate.SetConnectionReady(true);
                Gate.SetNativeReady(true);
                Gate.SetSharedDamageReady(true);
                Gate.SetSceneReady(true);
                Gate.AdmitIfReady();
            }
        }
    }
}
