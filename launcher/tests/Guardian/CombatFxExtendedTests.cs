using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.ArenaWorker;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class CombatFxExtendedTests
    {
        private static readonly Lazy<CombatFxCatalog> Loaded = new(() => CombatFxCatalog.Load(ProjectRoot()));
        private static CombatFxCatalog Catalog => Loaded.Value;
        private static int Style(string linkage)
        {
            int index = Array.FindIndex(Catalog.Styles, style => style.Linkage == linkage);
            Assert.True(index >= 0, "Missing paired effect style: " + linkage);
            return index;
        }
        private static string ProjectRoot()
        {
            var path = new DirectoryInfo(AppContext.BaseDirectory);
            while (path != null && !File.Exists(Path.Combine(path.FullName, CombatFxCatalog.RelativePath))) path = path.Parent;
            return path?.FullName ?? throw new InvalidOperationException("Missing combat effect fixture catalog");
        }
        private static string Birth(int id, int x = 100, int y = 40, int z = 1000000) => $"p,{id},{Style("子弹碎片-飞血")},{x},{y},{z},100,123";
        private static string Hit() => $"i,{Style("火花")},350,220,100,100,0,123,0";
        private static string Muzzle() => $"m,{Style("突击步枪枪火")},300,200,100,100,0,123,0";
        private static string Shell() => $"s,{Style("步枪弹壳")},100,200,100,100,300,64,123,0";
        private static CombatFxFrame Frame(int sequence, int tick, string events = "", int epoch = 1, bool paused = false)
        {
            Assert.True(CombatFxFrame.TryParse($"{epoch}|{sequence}|{tick}|{(paused ? 1 : 0)}" + (events.Length == 0 ? "" : ";" + events), Catalog, out var frame));
            return frame;
        }

        [Fact]
        public void CatalogAppendsTheSevenReviewedStylesAndBindsEachSourceLibrary()
        {
            string[] names = { "冰汽", "烈焰火花", "能量火花", "空手攻击火花", "铁枪能量弹枪火", "飙血", "子弹碎片-飞血" };
            string[] keys = { "mist", "mist", "mist", "stock", "fs", "stock", "stock" };
            Assert.Equal(42, Catalog.Styles.Length);
            Assert.Equal(names, Catalog.Styles.Skip(35).Select(style => style.Linkage).ToArray());
            using var document = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(ProjectRoot(), CombatFxCatalog.RelativePath)));
            JsonElement data = document.RootElement;
            var libraries = data.GetProperty("sourceLibraries").EnumerateArray().ToArray();
            Assert.Equal(new[] { "fs", "mist", "stock" }, libraries.Select(library => library.GetProperty("key").GetString()).OrderBy(key => key).ToArray());
            string[] sources = data.GetProperty("sources").EnumerateArray().Select(source => source.GetProperty("path").GetString()).ToArray();
            foreach (JsonElement library in libraries) Assert.Contains(library.GetProperty("swf").GetString(), sources);
            for (int offset = 0; offset < names.Length; offset++)
            {
                JsonElement entry = data.GetProperty("styles")[35 + offset];
                Assert.Equal(35 + offset, entry.GetProperty("index").GetInt32());
                Assert.Equal(keys[offset], entry.GetProperty("sourceKey").GetString());
                Assert.False(string.IsNullOrEmpty(entry.GetProperty("sourceSymbol").GetString()));
            }
        }

        [Fact]
        public void NewLifetimesAndBehaviorMetadataPreserveTheReviewedSourceSlices()
        {
            Assert.Equal(7, Assert.Single(Catalog.Styles[Style("冰汽")].Variants).Length);
            Assert.Equal(9, Assert.Single(Catalog.Styles[Style("烈焰火花")].Variants).Length);
            Assert.Equal(9, Assert.Single(Catalog.Styles[Style("能量火花")].Variants).Length);
            var unarmed = Catalog.Styles[Style("空手攻击火花")];
            Assert.Equal(3, Assert.Single(unarmed.Variants).Length);
            Assert.True(unarmed.RandomRotation); Assert.True(unarmed.SkipOriginYZero);
            Assert.Equal(new[] { 1f, 0f, 0f, 1f }, unarmed.NestedTransform.Take(4).ToArray());
            var muzzle = Catalog.Styles[Style("铁枪能量弹枪火")];
            Assert.True(muzzle.IsMuzzle); Assert.NotNull(muzzle.Light);
            Assert.Equal(new[] { 5, 3, 4 }, muzzle.Variants.Select(variant => variant.Length).ToArray());
            var impact = Catalog.Styles[Style("飙血")];
            Assert.True(impact.IsImpact); Assert.True(impact.WorldLit);
            Assert.Equal(129, impact.Frames.Length);
            Assert.Equal(new[] { 12, 10, 8, 24, 18, 39, 18 }, impact.Variants.Select(variant => variant.Length).ToArray());
            Assert.Equal(new[] { "blood1.mp3", "blood2.wav", "blood3.mp3", "blood4.mp3", "blood5.wav", "blood6.wav", "blood7.wav" }, impact.VariantSounds);
            Assert.True(impact.SoundAtBirth);
        }

        [Theory]
        [InlineData("火花", "13,12,11,10,9")]
        [InlineData("击中金属", "8,7,6,5")]
        [InlineData("拼刀火花", "530,531,532,533,534,535")]
        [InlineData("战术巴雷特击中特效", "454")]
        [InlineData("屎花", "4,3,2,1")]
        public void TimelineSoundsBindAllTwentyReviewedSwfEventsToFullSfxFilenames(string linkage, string sourceIds)
        {
            var style = Catalog.Styles[Style(linkage)];
            string[] expected = sourceIds.Split(',').Select(id => $"cfnfx-stock-{id}.wav").ToArray();
            Assert.True(style.SoundAtBirth); Assert.Equal(style.Variants.Length, style.VariantSounds.Length);
            Assert.Equal(expected, style.VariantSounds);
            foreach (string id in expected) Assert.True(File.Exists(Path.Combine(ProjectRoot(), "sounds", "export", "特效", id)), id);
        }

        [Theory]
        [InlineData("火花")]
        [InlineData("击中金属")]
        [InlineData("拼刀火花")]
        [InlineData("战术巴雷特击中特效")]
        [InlineData("屎花")]
        [InlineData("飙血")]
        public void BirthSoundUsesTheSameSeedVariantForDrawingAndNeverEchoesAudio(string linkage)
        {
            var style = Catalog.Styles[Style(linkage)];
            Assert.True(style.SoundAtBirth);
            foreach (int seed in Enumerable.Range(1, style.Variants.Length * 2).Append(int.MaxValue))
            {
                var engine = new CombatFxEngine(Catalog);
                var frame = Frame(1, 1, $"i,{style.Index},350,220,100,100,0,{seed},0");
                Assert.True(engine.Apply(frame, 1));
                int variant = (int)((uint)seed % (uint)style.Variants.Length);
                AssertFrameImage(engine.BuildDraw(), style.Frames[style.Variants[variant][0]]);
                Assert.Null(engine.TakeEvents()); Assert.Null(engine.TakeEvents());
                Assert.False(engine.Apply(frame, 1)); Assert.Null(engine.TakeEvents());
                engine.Apply(Frame(2, 2), 1);
                if (style.Variants[variant].Length > 1)
                    AssertFrameImage(engine.BuildDraw(), style.Frames[style.Variants[variant][1]]);
                Assert.Null(engine.TakeEvents());
            }
        }

        [Theory]
        [InlineData("火花")]
        [InlineData("击中金属")]
        [InlineData("拼刀火花")]
        [InlineData("战术巴雷特击中特效")]
        [InlineData("屎花")]
        [InlineData("飙血")]
        public void SaturatedBirthSoundSpritesCannotQueueFeedbackOrReplayTheDroppedVisual(string linkage)
        {
            var style = Catalog.Styles[Style(linkage)];
            Assert.True(style.SoundAtBirth);
            var engine = new CombatFxEngine(Catalog);
            string hit = $"i,{style.Index},350,220,100,100,0,123,0";
            int sequence = 0;
            for (int batch = 0; batch < CombatFxEngine.ImpactLimit / 32; batch++)
            {
                engine.Apply(Frame(++sequence, 1, string.Join(";", Enumerable.Repeat(hit, 32))), 1);
                Assert.Null(engine.TakeEvents());
            }
            Assert.Equal(CombatFxEngine.ImpactLimit, engine.BuildDraw().Count);
            var overflow = Frame(++sequence, 1, hit);
            Assert.True(engine.Apply(overflow, 1)); Assert.False(engine.Apply(overflow, 1));
            Assert.Equal(1, engine.Dropped); Assert.Equal(1, engine.ImpactDropped);
            Assert.Equal(CombatFxEngine.ImpactLimit, engine.BuildDraw().Count); Assert.Null(engine.TakeEvents());
            int endTick = style.Variants.Max(variant => variant.Length) + 1;
            for (int tick = 2; tick <= endTick; tick++)
            {
                engine.Apply(Frame(++sequence, tick), 1);
                Assert.Null(engine.TakeEvents());
            }
            Assert.Equal(0, engine.BuildDraw().Count); Assert.False(engine.HasDecorationState);
            engine.Apply(Frame(++sequence, endTick + 1, hit), 1);
            AssertFrameImage(engine.BuildDraw(), style.Frames[style.Variants[123 % style.Variants.Length][0]]);
            Assert.Equal(1, engine.Dropped); Assert.Null(engine.TakeEvents());
        }

        [Fact]
        public void LegacyFeedbackSoundStillEmitsOnceWhenTheStyleDoesNotOwnABirthCue()
        {
            var catalog = CombatFxCatalog.Load(ProjectRoot());
            var style = catalog.Styles[Style("火花")];
            style.SoundAtBirth = false;
            var engine = new CombatFxEngine(catalog);
            var frame = Frame(1, 1, Hit());
            Assert.True(engine.Apply(frame, 1));
            var events = engine.TakeEvents(); Assert.NotNull(events);
            Assert.Contains(Assert.Single(events.Sounds), style.VariantSounds);
            Assert.Null(engine.TakeEvents()); Assert.False(engine.Apply(frame, 1)); Assert.Null(engine.TakeEvents());
            engine.Apply(Frame(2, 2), 1); Assert.Null(engine.TakeEvents());
        }

        [Fact]
        public void DerivedSoundAssetsLoadWithTheirDeclaredHashesAndRejectAChangedByte()
        {
            using var document = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(ProjectRoot(), CombatFxCatalog.RelativePath)));
            JsonElement data = document.RootElement;
            var assets = data.GetProperty("soundAssets").EnumerateArray().ToArray();
            Assert.Equal(20, assets.Length);
            Assert.Equal(20, assets.Select(asset => asset.GetProperty("sourceSoundId").GetInt32()).Distinct().Count());
            string[] referenced = Catalog.Styles.Where(style => style.SoundAtBirth).SelectMany(style => style.VariantSounds).ToArray();
            Assert.Equal(27, referenced.Length); Assert.Equal(6, Catalog.Styles.Count(style => style.SoundAtBirth));
            foreach (JsonElement asset in assets)
            {
                string id = asset.GetProperty("id").GetString();
                Assert.Equal("stock", asset.GetProperty("sourceKey").GetString());
                Assert.Equal($"cfnfx-stock-{asset.GetProperty("sourceSoundId").GetInt32()}.wav", id);
                Assert.Contains(id, referenced);
                string relative = asset.GetProperty("path").GetString();
                Assert.Equal("sounds/export/特效/" + id, relative);
                byte[] bytes = File.ReadAllBytes(Path.Combine(ProjectRoot(), relative));
                Assert.Equal(asset.GetProperty("bytes").GetInt64(), bytes.LongLength);
                Assert.Equal(asset.GetProperty("sha256").GetString().ToUpperInvariant(), Convert.ToHexString(SHA256.HashData(bytes)));
                Assert.Equal("RIFF", System.Text.Encoding.ASCII.GetString(bytes, 0, 4));
                Assert.Equal("WAVE", System.Text.Encoding.ASCII.GetString(bytes, 8, 4));
            }
            foreach (string id in referenced) Assert.True(File.Exists(Path.Combine(ProjectRoot(), "sounds", "export", "特效", id)), id);
            string fixture = CopySoundCatalogFixture(data);
            try
            {
                Assert.Equal(Catalog.Sha256, CombatFxCatalog.Load(fixture).Sha256);
                string target = Path.Combine(fixture, assets[0].GetProperty("path").GetString());
                byte[] changed = File.ReadAllBytes(target); changed[^1] ^= 1;
                File.WriteAllBytes(target, changed);
                var rejected = Assert.Throws<InvalidDataException>(() => CombatFxCatalog.Load(fixture));
                Assert.Contains("sound integrity mismatch", rejected.Message);
            }
            finally { Directory.Delete(fixture, recursive: true); }
        }

        private static void AssertFrameImage(CombatFxDrawFrame draw, CombatFxImage image)
        {
            Assert.Equal(1, draw.Count);
            Assert.Equal(new[] { image.U0, image.V0, image.U1, image.V1 }, draw.Data.Skip(12).Take(4).ToArray());
            Assert.Equal(image.Width, draw.Data[10]); Assert.Equal(image.Height, draw.Data[11]);
        }

        private static string CopySoundCatalogFixture(JsonElement data)
        {
            string root = Path.Combine(ProjectRoot(), "tmp", "combat-fx-sound-catalog-" + Guid.NewGuid().ToString("N"));
            var files = new HashSet<string>(StringComparer.Ordinal) { CombatFxCatalog.RelativePath, CombatFxCatalog.AtlasPath, CombatFxCatalog.LightsPath };
            foreach (JsonElement library in data.GetProperty("sourceLibraries").EnumerateArray()) files.Add(library.GetProperty("swf").GetString());
            foreach (JsonElement asset in data.GetProperty("soundAssets").EnumerateArray()) files.Add(asset.GetProperty("path").GetString());
            foreach (string id in Catalog.Styles.Where(style => style.SoundAtBirth).SelectMany(style => style.VariantSounds)) files.Add("sounds/export/特效/" + id);
            foreach (string relative in files)
            {
                string target = Path.Combine(root, relative); Directory.CreateDirectory(Path.GetDirectoryName(target));
                File.Copy(Path.Combine(ProjectRoot(), relative), target);
            }
            return root;
        }

        [Theory]
        [InlineData("p,1,{impact},100,40,90,100,123")]
        [InlineData("p,0,{blood},100,40,90,100,123")]
        [InlineData("p,1,{blood},NaN,40,90,100,123")]
        [InlineData("p,1,{blood},100,40,90,0,123")]
        [InlineData("p,1,{blood},100,40,90,100,0")]
        [InlineData("p,1,{blood},100,40,90,100,123,-1")]
        [InlineData("p,1,{blood},100,40,90,100,123,Infinity")]
        [InlineData("p,1,{blood},100,40,90,100,123,1,0")]
        [InlineData("b,1,{blood},100,40,90,-3,12,2,1,100,125,0,3")]
        [InlineData("k,1,0,0,0,0")]
        [InlineData("j,{impact},100,40,100,100,0,0,0")]
        [InlineData("n,{muzzle},100,40,100,100,0,0,0")]
        [InlineData("i,{blood},100,40,100,100,0,123,0")]
        public void ParticleWireRejectsMalformedInputsAndRetiredExperimentalRecords(string record)
        {
            record = record.Replace("{blood}", Style("子弹碎片-飞血").ToString())
                .Replace("{impact}", Style("火花").ToString()).Replace("{muzzle}", Style("突击步枪枪火").ToString());
            Assert.False(CombatFxFrame.TryParse("1|1|1|0;" + record, Catalog, out _));
        }

        [Fact]
        public void ParticleBirthsHaveAnIndependentWireBudgetAndOptionalGravity()
        {
            string payload = string.Join(";", Enumerable.Repeat(Muzzle(), 32).Concat(Enumerable.Repeat(Hit(), 32))
                .Concat(Enumerable.Range(1, 64).Select(id => Birth(id))));
            CombatFxFrame maximum = Frame(1, 1, payload);
            Assert.Equal(64, maximum.Spawns.Length); Assert.Equal(64, maximum.BloodEvents.Length);
            Assert.False(CombatFxFrame.TryParse("1|1|1|0;" + payload + ";" + Birth(65), Catalog, out _));
            Assert.False(CombatFxFrame.TryParse("1|1|1|0;" + payload + ";" + Hit(), Catalog, out _));
            Assert.False(CombatFxFrame.TryParse("1|1|1|0;" + payload + ";" + Muzzle(), Catalog, out _));
            var defaults = Assert.Single(Frame(1, 1, Birth(1)).BloodEvents);
            var explicitGravity = Assert.Single(Frame(1, 1, Birth(1) + ",2.8").BloodEvents);
            Assert.Equal(1d, defaults.Gravity); Assert.Equal(2.8d, explicitGravity.Gravity);
            Assert.Equal(123u, explicitGravity.Seed);
        }

        [Fact]
        public void EngineFreezesBloodOnPauseAndRejectsOldPackets()
        {
            var engine = new CombatFxEngine(Catalog);
            CombatFxFrame initial = Frame(1, 1, Birth(1));
            Assert.True(engine.Apply(initial, 2)); Assert.False(engine.Apply(initial, 2));
            Assert.False(engine.Apply(Frame(2, 2, Birth(2)), 1));
            engine.Apply(Frame(2, 500, Birth(2), paused: true), 2);
            var paused = engine.BuildDraw();
            Assert.Equal(1, paused.Count); Assert.Equal(100f, paused.Data[0]); Assert.Equal(40f, paused.Data[1]);
            engine.Apply(Frame(3, 501), 2);
            Assert.Equal(1, engine.BuildDraw().Count);
            for (int age = 2; age <= 60; age++) engine.Apply(Frame(age + 2, 500 + age), 2);
            Assert.Equal(0, engine.BuildDraw().Count); Assert.False(engine.HasDecorationState);
        }

        [Fact]
        public void NewSceneOrConnectionRetiresBloodAndAllowsANewIdentityNamespace()
        {
            var engine = new CombatFxEngine(Catalog);
            engine.Apply(Frame(1, 1, Birth(1, y: 80, z: 80)), 2); engine.Apply(Frame(2, 2), 2);
            Assert.True(engine.HasDecorationState);
            engine.Apply(Frame(1, 0, epoch: 2), 2);
            Assert.Equal(0, engine.BuildDraw().Count); Assert.False(engine.HasDecorationState); Assert.Null(engine.TakeEvents());
            Assert.False(engine.Apply(Frame(999, 999, Birth(2), epoch: 1), 2));
            engine.Apply(Frame(2, 1, Birth(1), epoch: 2), 2);
            Assert.Equal(1, engine.BuildDraw().Count);
            engine.Apply(Frame(1, 0, Birth(1, x: 300), epoch: 1), 3);
            Assert.Equal(1, engine.BuildDraw().Count); Assert.Equal(300f, engine.BuildDraw().Data[0]);
        }

        [Fact]
        public void BloodKeepsItsOwn64SlotsAlongsideTheExisting448FeedbackSprites()
        {
            var engine = new CombatFxEngine(Catalog);
            int sequence = 1;
            engine.Apply(Frame(sequence, 1, string.Join(";", Enumerable.Repeat(Shell(), 4))), 1);
            for (int index = 0; index < 4; index++) engine.Apply(Frame(++sequence, 1, string.Join(";", Enumerable.Repeat(Hit(), 32))), 1);
            for (int index = 0; index < 2; index++) engine.Apply(Frame(++sequence, 1, string.Join(";", Enumerable.Repeat(Muzzle(), 32))), 1);
            engine.Apply(Frame(++sequence, 1, string.Join(";", Enumerable.Range(1, 64).Select(id => Birth(id, 1000 + id)))), 1);
            var draw = engine.BuildDraw();
            Assert.Equal(512, draw.Count); Assert.Equal(256, draw.CasingCount); Assert.Equal(192, draw.ImpactCount);
            Assert.Equal(1001f, draw.Data[384 * 16]); Assert.Equal(1064f, draw.Data[447 * 16]); Assert.Equal(300f, draw.Data[448 * 16]);
            engine.Apply(Frame(++sequence, 1, Birth(65, x: 9000)), 1);
            Assert.Equal(512, engine.BuildDraw().Count); Assert.Equal(0, engine.ImpactDropped);
        }

        [Fact]
        public void LongGapClearsBothBloodAndPendingLandingsWithoutResettingTheBirthHighWaterMark()
        {
            var engine = new CombatFxEngine(Catalog);
            engine.Apply(Frame(1, 1, Birth(1, y: 80, z: 80) + ";" + Birth(2)), 1); engine.Apply(Frame(2, 2), 1);
            Assert.True(engine.HasDecorationState);
            engine.Apply(Frame(3, 20), 1);
            Assert.Equal(0, engine.BuildDraw().Count); Assert.False(engine.HasDecorationState); Assert.Null(engine.TakeEvents());
            engine.Apply(Frame(4, 20, Birth(1, x: 900) + ";" + Birth(2, x: 800) + ";" + Birth(3, x: 300)), 1);
            Assert.Equal(1, engine.BuildDraw().Count); Assert.Equal(300f, engine.BuildDraw().Data[0]);
        }

        [Fact]
        public void LandingBatchesStaySeparateFromCasingHitsAndDrainWithoutReplay()
        {
            var engine = new CombatFxEngine(Catalog);
            string births = string.Join(";", Enumerable.Range(1, 64).Select(id => Birth(id, x: id, y: 80, z: 80)));
            engine.Apply(Frame(1, 1, births), 1); engine.Apply(Frame(2, 2), 1);
            Assert.Equal(0, engine.BuildDraw().Count); Assert.True(engine.HasDecorationState);
            var seen = new HashSet<int>();
            for (int batch = 0; batch < 8; batch++)
            {
                var events = engine.TakeEvents(); Assert.NotNull(events);
                Assert.Equal(0, events.GroundHits); Assert.Empty(events.Settled); Assert.Empty(events.Sounds);
                Assert.InRange(events.BloodLandings.Length, 1, 8);
                foreach (var landing in events.BloodLandings) Assert.True(seen.Add(landing.Id));
                engine.Apply(Frame(3 + batch, 2), 1);
            }
            Assert.Equal(64, seen.Count); Assert.Null(engine.TakeEvents()); Assert.False(engine.HasDecorationState);
        }

        [Fact]
        public void NoneProjectionRejectsParticleBirthsWhileRetainingTheWorldClockAndResidentLights()
        {
            var consumers = new JObject();
            foreach (string name in WorkerProjectionPolicy.ConsumerNames)
                consumers[name] = name == "sceneLighting" || name == "equipmentLighting" ? "full" : "none";
            string root = Path.Combine(ProjectRoot(), "tmp", "blood-none-policy-" + Guid.NewGuid().ToString("N"));
            var configuration = new JObject { ["schema"] = "arena-worker.launch.v2", ["workerId"] = "w01", ["sessionEpoch"] = "s01",
                ["projectRoot"] = root, ["stateRoot"] = Path.Combine(root, "tmp", "arena-worker", "s01"), ["saveRoot"] = Path.Combine(root, "saves"),
                ["outputRoot"] = Path.Combine(root, "tmp", "arena-calibration"), ["swfOrigin"] = Path.Combine(root, "CRAZYFLASHER7MercenaryEmpire.swf"),
                ["slot"] = "cf7_agent_fixture", ["presentationPolicy"] = "full", ["projectionConsumers"] = consumers, ["controlFrameFormat"] = "f-visual-v1",
                ["visualSeedRevision"] = WorkerProjectionPolicy.VisualRevision, ["simulationRngConsumptionRevision"] = WorkerProjectionPolicy.SimulationRevision,
                ["sessionVisualSeed"] = 42 };
            var bindings = new JObject();
            foreach (string name in WorkerProjectionPolicy.CatalogNames) bindings[name] = "sha256:" + new string('a', 64);
            var offers = new List<JObject>(); var faults = new List<string>();
            var policy = ArenaWorkerPolicy.FromConfiguration(configuration, root);
            using var projection = new WorkerProjectionNegotiator(policy, bindings, (wire, generation) => {
                offers.Add(JObject.Parse(wire.TrimEnd('\0'))); return true;
            }, (reason, generation) => faults.Add(reason), () => DateTime.UtcNow, startTimer: false, clean: () => true, startupReady: () => true);
            projection.Ready(7);
            var prepared = (JObject)offers[0].DeepClone(); prepared["task"] = "worker_projection_prepared"; prepared["accepted"] = true; prepared["clean"] = true;
            var installed = JObject.Parse(projection.Prepared(prepared, 7)); installed["task"] = "worker_projection_committed";
            installed["installClockKind"] = "flashRootEnterFrame"; installed["installEpoch"] = 1; installed["installTick"] = 2;
            projection.Committed(installed, 7);
            Assert.True(projection.IsNone("combatDecoration", 7));
            Assert.False(projection.ObserveCombatDecorations("1|2|3|0;l,1,0,0,0,0,0,100,0,1,1,1,1", 7));
            Assert.True(projection.ObserveCombatDecorations("1|2|3|0;" + Birth(1), 7));
            Assert.Equal("unexpected_projection_after_none:combatDecoration", Assert.Single(faults));
        }
    }
}
