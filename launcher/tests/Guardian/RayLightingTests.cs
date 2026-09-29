using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class RayLightingTests
    {
        private static readonly Lazy<RayLightingCatalog> Catalog = new(() => RayLightingCatalog.Load(ProjectRoot()));
        private static float[] Values(float hold = 6, float fade = 4, float width = 4, int color = 0xFF8800)
        {
            var v = new float[RayVisualCatalog.FieldNames.Length];
            v[0] = color; v[1] = 0xFFFFFF; v[2] = width; v[3] = hold; v[4] = fade;
            v[6] = 70; v[7] = 100; v[10] = 35; v[11] = 40; v[14] = .7f;
            v[20] = 60; v[24] = 15; v[25] = 50; v[37] = 1;
            v[41] = 0x7A6F66; v[42] = 0xFFB347; v[49] = 0x34302A;
            return v;
        }
        private static string Config(int style = 1, int id = 1, float[] values = null,
            RayLightOverrides? light = null, string palette = "-")
        {
            string record = $"c,{id},{style}," + string.Join(',', (values ?? Values()).Select(v => v.ToString(CultureInfo.InvariantCulture))) + "," + palette;
            if (light is { } l)
                record += FormattableString.Invariant($";l,{id},{l.Profile},{l.EnergyScale},{l.WidthScale},{l.Color},{l.FadeTicks}");
            return record;
        }
        private static string Spawn(int id = 1, int config = 1, int born = 0, int delay = 0,
            float sx = 100, float sy = 50, float ex = 200, float ey = 50, int kind = 0,
            int key = 0, int serial = 1, string operation = "s", string points = "-", int seed = 123) =>
            FormattableString.Invariant($"{operation},{id},{config},{born},{delay},{sx},{sy},{ex},{ey},{kind},0,1,0,{seed},{key},{serial},900,1,5,2,{points},-,0");
        private static RayVisualFrame Frame(int seq, int tick, string records = "", int epoch = 1,
            bool paused = false, float ox = 0, float oy = 0)
        {
            string payload = FormattableString.Invariant($"{epoch}|{seq}|{tick}|{(paused ? 1 : 0)};o,{ox},{oy}")
                + (records.Length > 0 ? ";" + records : "");
            Assert.True(RayVisualFrame.TryParse(payload, out var frame), payload);
            return frame;
        }
        private static RayVisualEngine Engine()
        {
            var result = new RayVisualEngine(); result.ConfigureLighting(Catalog.Value); return result;
        }
        private static WorldLightCandidate OnlyLight(RayVisualEngine engine)
        {
            var draw = engine.BuildDraw(); Assert.Equal(1, draw.LightCount); return draw.Lights[0];
        }
        private static float[] Body(RayVisualEngine engine)
        {
            var draw = engine.BuildDraw(); return draw.Data.Take(draw.Count * RayVisualCatalog.Stride).ToArray();
        }

        [Fact]
        public void AuthoredCatalogCoversAllTwelveStylesWithTheAgreedIndependentProfiles()
        {
            string[] names = { "arc", "beam", "heavy", "beam", "beam", "heavy", "heavy", "beam", "heavy", "heavy", "glyph", "flame" };
            int[] priorities = { 55, 65, 80, 65, 65, 80, 80, 65, 80, 80, 35, 85 };
            Assert.Equal(12, RayVisualCatalog.Styles.Length);
            for (int i = 0; i < names.Length; i++)
            {
                var profile = Catalog.Value.ForStyle(i);
                Assert.Equal(names[i], profile.Name); Assert.Equal(priorities[i], profile.Priority);
                Assert.InRange(profile.MaxLength, 1, 1024);
            }
            Assert.Equal(1.9f, Catalog.Value.ForStyle(11).Energy);
            Assert.Equal(1.25f, Catalog.Value.ForStyle(1).Energy);
            Assert.Equal(1.65f, Catalog.Value.ForStyle(2).Energy);
            Assert.Equal(1.25f, Catalog.Value.ForStyle(0).Energy);
            Assert.Equal(.9f, Catalog.Value.ForStyle(10).Energy);
            Assert.Equal(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(
                Path.Combine(ProjectRoot(), RayLightingCatalog.RelativePath)))), Catalog.Value.Sha256);
        }

        [Theory]
        [InlineData("missing-style")]
        [InlineData("unknown-style")]
        [InlineData("missing-profile")]
        [InlineData("unknown-field")]
        [InlineData("bad-profile")]
        [InlineData("energy")]
        [InlineData("width-order")]
        [InlineData("length")]
        [InlineData("color")]
        [InlineData("unused-color")]
        [InlineData("hold")]
        [InlineData("fade")]
        [InlineData("flicker")]
        [InlineData("near-on-beam")]
        [InlineData("partial-near")]
        [InlineData("invalid-near-energy")]
        public void MalformedCatalogsFailClosedInsteadOfSilentlyInventingDefaults(string mutation)
        {
            var json = JsonNode.Parse(File.ReadAllText(Path.Combine(ProjectRoot(), RayLightingCatalog.RelativePath)));
            var beam = json["profiles"]["beam"];
            switch (mutation)
            {
                case "missing-style": json["styles"].AsObject().Remove("tesla"); break;
                case "unknown-style": json["styles"]["not-a-ray"] = "beam"; break;
                case "missing-profile": json["profiles"].AsObject().Remove("arc"); break;
                case "unknown-field": beam["power"] = 1; break;
                case "bad-profile": json["styles"]["tesla"] = "none"; break;
                case "energy": beam["energy"] = 2.1; break;
                case "width-order": beam["minWidth"] = 100; beam["maxWidth"] = 50; break;
                case "length": beam["maxLength"] = 1025; break;
                case "color": json["profiles"]["flame"]["color"] = "#FFFFFZ"; break;
                case "unused-color": beam["color"] = "#FFFFFF"; break;
                case "hold": beam["holdTicks"] = -2; break;
                case "fade": beam["fadeTicks"] = 31; break;
                case "flicker": beam["flicker"] = .26; break;
                case "near-on-beam": beam["nearWidthRatio"] = .3; beam["maxNearRadius"] = 28; beam["nearEnergyRatio"] = .45; break;
                case "partial-near": json["profiles"]["flame"].AsObject().Remove("maxNearRadius"); break;
                case "invalid-near-energy": json["profiles"]["flame"]["nearEnergyRatio"] = 1.01; break;
            }
            Assert.Throws<InvalidDataException>(() => RayLightingCatalog.Parse(Encoding.UTF8.GetBytes(json.ToJsonString())));
        }

        [Fact]
        public void DuplicatePropertiesInvalidNumbersAndOversizedJsonAreRejected()
        {
            string text = File.ReadAllText(Path.Combine(ProjectRoot(), RayLightingCatalog.RelativePath));
            Assert.Throws<InvalidDataException>(() => RayLightingCatalog.Parse(Encoding.UTF8.GetBytes(
                text.Insert(text.IndexOf('{') + 1, "\"schema\":\"cf7-ray-lights.v1\","))));
            Assert.Throws<InvalidDataException>(() => RayLightingCatalog.Parse(Encoding.UTF8.GetBytes(
                text.Replace("\"energy\": 1.25", "\"energy\": 1e999", StringComparison.Ordinal))));
            Assert.Throws<InvalidDataException>(() => RayLightingCatalog.Parse(new byte[32769]));
        }

        [Fact]
        public void NullCatalogAndNoneOverridesNeverChangeTheBeamBody()
        {
            var engine = new RayVisualEngine();
            Assert.True(engine.Apply(Frame(1, 0, Config() + ";" + Spawn()), 1));
            float[] before = Body(engine); Assert.Equal(0, engine.BuildDraw().LightCount);
            engine.ConfigureLighting(Catalog.Value); Assert.Equal(1, engine.BuildDraw().LightCount);
            Assert.Equal(before, Body(engine));
            engine.ConfigureLighting(null); Assert.Equal(0, engine.BuildDraw().LightCount);
            Assert.Equal(before, Body(engine));
            var disabled = Engine();
            Assert.True(disabled.Apply(Frame(1, 0, Config(light: new RayLightOverrides("none", 1, 1, -1, -1)) + ";" + Spawn()), 1));
            Assert.Equal(before, Body(disabled)); Assert.Equal(0, disabled.BuildDraw().LightCount);
        }

        [Fact]
        public void AllStylesEmitOnePrimaryCandidateWithStableWarmColdAndWeakColors()
        {
            var engine = Engine();
            string records = string.Join(';', Enumerable.Range(0, 12).Select(i =>
                Config(i, i + 1) + ";" + Spawn(i + 1, i + 1, kind: i == 11 ? 4 : 0, key: i == 11 ? 7 : 0)));
            Assert.True(engine.Apply(Frame(1, 0, records), 1));
            var draw = engine.BuildDraw(); Assert.Equal(12, draw.LightCount);
            Assert.Equal(12, draw.Lights.Take(12).Select(x => x.Key).Distinct().Count());
            for (int i = 0; i < 12; i++) Assert.Equal(Catalog.Value.ForStyle(i).Priority, draw.Lights[i].Priority);
            Assert.True(draw.Lights[0].B > draw.Lights[0].R); // short cold arc
            Assert.True(draw.Lights[11].R > draw.Lights[11].G && draw.Lights[11].G > draw.Lights[11].B);
            Assert.Equal(1, draw.Lights[11].Kind); Assert.Equal(2, draw.Lights[1].Kind);
            Assert.Equal(.9f, draw.Lights[10].Energy);
        }

        [Fact]
        public void GeometryUsesActualMirroredEndpointsAndCapsOnlyTheLightLength()
        {
            var engine = Engine();
            string records = Config() + ";" + Spawn(ex: -300)
                + ";" + Spawn(id: 2, sx: 10, sy: 20, ex: 10, ey: 220)
                + ";" + Spawn(id: 3, sx: 0, sy: 0, ex: .3f, ey: .4f)
                + ";" + Spawn(id: 4, ex: 100)
                + ";" + Spawn(id: 5, ex: 3000);
            Assert.True(engine.Apply(Frame(1, 0, records), 1));
            var draw = engine.BuildDraw(); Assert.Equal(3, draw.LightCount); Assert.Equal(5, draw.Count);
            Assert.Equal(400f, draw.Lights[0].Length); Assert.Equal(-1f, draw.Lights[0].DirectionX);
            Assert.Equal(0f, draw.Lights[0].DirectionY);
            Assert.Equal(200f, draw.Lights[1].Length); Assert.Equal(1f, draw.Lights[1].DirectionY);
            Assert.Equal(1024f, draw.Lights[2].Length);
            Assert.Equal(3000f, draw.Data[4 * RayVisualCatalog.Stride + 2]); // art geometry is not truncated
        }

        [Fact]
        public void BlockedShortFlameShrinksItsWidthWithItsActualLength()
        {
            var engine = Engine();
            Assert.True(engine.Apply(Frame(1, 0, Config(11, values: Values(width: 100)) + ";"
                + Spawn(ex: 104, kind: 4, key: 7)), 1));
            var light = OnlyLight(engine);
            Assert.Equal(4f, light.Length); Assert.Equal(8f, light.HalfWidth);
            Assert.Equal(4f, light.NearRadius);
            Assert.Equal(light.Energy * .9f, light.NearEnergy);
            Assert.Equal((light.X, light.Y), (light.NearX, light.NearY));
        }

        [Fact]
        public void ConeNearFillSharesOneRecordAndDoesNotChangeBodiesOrCandidateBudget()
        {
            var oldJson = JsonNode.Parse(File.ReadAllText(Path.Combine(ProjectRoot(), RayLightingCatalog.RelativePath)));
            var flame = oldJson["profiles"]["flame"].AsObject();
            flame.Remove("nearWidthRatio"); flame.Remove("maxNearRadius"); flame.Remove("nearEnergyRatio");
            var withoutNear = new RayVisualEngine();
            withoutNear.ConfigureLighting(RayLightingCatalog.Parse(Encoding.UTF8.GetBytes(oldJson.ToJsonString())));
            var withNear = Engine();
            string records = Config(11, values: Values(width: 14)) + ";" + string.Join(';',
                Enumerable.Range(1, 3).Select(i => Spawn(i, sx: 100, ex: 600, kind: 4, key: i)));
            var frame = Frame(1, 0, records);
            withoutNear.Apply(frame, 1); withNear.Apply(frame, 1);
            Assert.Equal(Body(withoutNear), Body(withNear));
            Assert.Equal(3, withoutNear.BuildDraw().LightCount); Assert.Equal(3, withNear.BuildDraw().LightCount);
            var light = withNear.BuildDraw().Lights[0];
            Assert.Equal(224f, light.HalfWidth); Assert.Equal(140f, light.NearRadius);
            Assert.Equal(light.Energy * .9f, light.NearEnergy);
            var packed = new float[16]; light.WriteTo(packed, 0);
            Assert.Equal(0f, packed[11]); Assert.Equal(100f, packed[12]); Assert.Equal(50f, packed[13]);
            Assert.Equal(light.NearRadius, packed[14]); Assert.Equal(light.NearEnergy, packed[15]);
            Assert.Equal(0f, withoutNear.BuildDraw().Lights[0].NearRadius);
            var disabled = Engine();
            disabled.Apply(Frame(1, 0, Config(11, light: new RayLightOverrides("none", 1, 1, -1, -1))
                + ";" + Spawn(kind: 4, key: 1)), 1);
            Assert.Equal(0, disabled.BuildDraw().LightCount);
        }

        [Fact]
        public void DelayAndPauseFollowTheSameMaterializedWorldGeometryAndGameClock()
        {
            var engine = Engine();
            Assert.True(engine.Apply(Frame(1, 1, Config(2) + ";" + Spawn(delay: 3, kind: 3), ox: 10, oy: 20), 1));
            Assert.Equal(0, engine.BuildDraw().LightCount);
            engine.Apply(Frame(2, 2, ox: 30, oy: 40), 1); Assert.Equal(0, engine.BuildDraw().LightCount);
            engine.Apply(Frame(3, 3, ox: 50, oy: 70), 1);
            var first = OnlyLight(engine); Assert.Equal(140f, first.X); Assert.Equal(100f, first.Y);
            engine.Apply(Frame(4, 500, paused: true, ox: 300, oy: 400), 1);
            var paused = OnlyLight(engine); Assert.Equal(first, paused);
            engine.Apply(Frame(5, 501, ox: 300, oy: 400), 1);
            var resumed = OnlyLight(engine); Assert.Equal(first.X, resumed.X); Assert.Equal(first.Y, resumed.Y);
        }

        [Fact]
        public void LightFadeNeverOutlivesVisualLifetimeAndArcLightIsIntentionallyShort()
        {
            var engine = Engine();
            var longFade = new RayLightOverrides("auto", 1, 1, -1, 30);
            engine.Apply(Frame(1, 0, Config(values: Values(1, 1), light: longFade) + ";" + Spawn()), 1);
            Assert.Equal(1, engine.BuildDraw().LightCount);
            engine.Apply(Frame(2, 1), 1); Assert.Equal(1, engine.BuildDraw().LightCount);
            engine.Apply(Frame(3, 2), 1); Assert.Equal(0, engine.BuildDraw().LightCount);
            engine.Apply(Frame(4, 3), 1); Assert.Equal(0, engine.BuildDraw().Count);
            engine.Reset();
            engine.Apply(Frame(1, 0, Config(0, values: Values(20, 3)) + ";" + Spawn(), epoch: 2), 1);
            Assert.Equal(1, engine.BuildDraw().LightCount);
            engine.Apply(Frame(2, 3, epoch: 2), 1);
            Assert.Equal(0, engine.BuildDraw().LightCount); Assert.Equal(1, engine.BuildDraw().Count);
        }

        [Fact]
        public void AnAuthoredLongLightHoldCannotRemainAtTheZeroAlphaVisualEndpoint()
        {
            var json = JsonNode.Parse(File.ReadAllText(Path.Combine(ProjectRoot(), RayLightingCatalog.RelativePath)));
            json["profiles"]["beam"]["holdTicks"] = 30;
            var engine = new RayVisualEngine();
            engine.ConfigureLighting(RayLightingCatalog.Parse(Encoding.UTF8.GetBytes(json.ToJsonString())));
            engine.Apply(Frame(1, 0, Config(values: Values(1, 1)) + ";" + Spawn()), 1);
            Assert.Equal(1, engine.BuildDraw().LightCount);
            engine.Apply(Frame(2, 2), 1);
            Assert.Equal(0, engine.BuildDraw().LightCount);
            Assert.Equal(0f, engine.BuildDraw().Data[7]);
        }

        [Fact]
        public void BranchesAndHitOrnamentsNeverAllocateIndependentLights()
        {
            var engine = Engine();
            string hits = "120:50/140:50/160:50/180:50";
            string records = Config() + ";" + Config(11, 2)
                + ";" + Spawn(points: hits)
                + ";" + Spawn(id: 2, kind: 1, points: hits)
                + ";" + Spawn(id: 3, kind: 2, points: hits)
                + ";" + Spawn(id: 4, kind: 3, points: hits)
                + ";" + Spawn(id: 5, config: 2, kind: 4, key: 7, points: hits);
            engine.Apply(Frame(1, 0, records), 1);
            var draw = engine.BuildDraw(); Assert.Equal(3, draw.LightCount); Assert.True(draw.Count > 5);
        }

        [Fact]
        public void PersistentFlameUpsertKeepsOneKeyAndUsesItsShortenedGeometry()
        {
            var engine = Engine();
            engine.Apply(Frame(1, 1, Config(11) + ";" + Spawn(born: 1, ex: 600, kind: 4, key: 7)), 1);
            var first = OnlyLight(engine);
            engine.Apply(Frame(2, 2, Spawn(born: 2, sx: 110, ex: 140, kind: 4, key: 7, serial: 2, operation: "u", seed: 999)), 1);
            var next = OnlyLight(engine);
            Assert.Equal(first.Key, next.Key); Assert.Equal(110f, next.X); Assert.Equal(30f, next.Length);
            Assert.Equal(60f, next.HalfWidth); Assert.Equal(1, engine.BuildDraw().Count);
            Assert.Equal(123f, engine.BuildDraw().Data[14]); // lighting did not replace the renderer's retained seed
        }

        [Fact]
        public void SameKeyDiscontinuousFlamesShareOneLightAndNewestNoneDoesNotReviveTheOldTail()
        {
            var engine = Engine();
            engine.Apply(Frame(1, 1, Config(11) + ";" + Spawn(born: 1, ex: 400, kind: 4, key: 7, serial: 5)), 1);
            var first = OnlyLight(engine);
            engine.Apply(Frame(2, 2, Spawn(id: 2, born: 2, sx: 200, ex: 225, kind: 4, key: 7, serial: 5)), 1);
            var later = OnlyLight(engine);
            Assert.Equal(first.Key, later.Key); Assert.Equal(200f, later.X); Assert.Equal(25f, later.Length);
            Assert.Equal(2, engine.BuildDraw().Count); // both authored bodies are still visible
            engine.Apply(Frame(3, 3, Spawn(id: 3, born: 2, sx: 300, ex: 340, kind: 4, key: 7, serial: 5)), 1);
            Assert.Equal(300f, OnlyLight(engine).X); // same serial and birth: later id wins
            engine.Apply(Frame(4, 4, Config(11, 2, values: Values(0, 1), light: new RayLightOverrides("none", 1, 1, -1, -1)) + ";"
                + Spawn(id: 4, config: 2, born: 4, sx: 400, ex: 440, kind: 4, key: 7, serial: 6)), 1);
            Assert.Equal(4, engine.BuildDraw().Count); Assert.Equal(0, engine.BuildDraw().LightCount);
            engine.Apply(Frame(5, 6), 1);
            Assert.Equal(3, engine.BuildDraw().Count); Assert.Equal(0, engine.BuildDraw().LightCount);
            engine.ConfigureLighting(null); engine.ConfigureLighting(Catalog.Value);
            Assert.Equal(0, engine.BuildDraw().LightCount); // changing the lighting table does not revive retired tails
            engine.Reset();
            engine.Apply(Frame(1, 0, Config(11) + ";" + Spawn(kind: 4, key: 7), epoch: 2), 1);
            Assert.Equal(1, engine.BuildDraw().LightCount); // a new scene owns a fresh channel
        }

        [Fact]
        public void RainbowPaletteAndVisualFlickerCannotChangeLightColorOrTheBeamRandomSequence()
        {
            var unlit = new RayVisualEngine(); var lit = Engine(); var overridden = Engine();
            var values = Values(color: 0x1122CC); values[5] = 1; values[15] = 7;
            string normal = Config(3, values: values, palette: "16711680:65280:255") + ";" + Spawn();
            string changed = Config(3, values: values, palette: "16711680:65280:255",
                light: new RayLightOverrides("heavy", .5f, 2, 0x0040FF, 1)) + ";" + Spawn();
            unlit.Apply(Frame(1, 0, normal), 1); lit.Apply(Frame(1, 0, normal), 1); overridden.Apply(Frame(1, 0, changed), 1);
            var initial = OnlyLight(lit);
            for (int tick = 0; tick < 5; tick++)
            {
                Assert.Equal(Body(unlit), Body(lit)); Assert.Equal(Body(unlit), Body(overridden));
                var current = OnlyLight(lit);
                Assert.Equal((initial.R, initial.G, initial.B), (current.R, current.G, current.B));
                var specific = OnlyLight(overridden);
                Assert.Equal((0f, 64 / 255f, 1f), (specific.R, specific.G, specific.B));
                var frame = Frame(tick + 2, tick + 1);
                unlit.Apply(frame, 1); lit.Apply(frame, 1); overridden.Apply(frame, 1);
            }
        }

        [Fact]
        public void ResetSceneGenerationAndNullConfigurationRemoveAllOldLightCandidates()
        {
            var engine = Engine(); engine.Apply(Frame(1, 0, Config() + ";" + Spawn()), 1);
            long oldKey = OnlyLight(engine).Key;
            engine.Reset(); Assert.Equal(0, engine.BuildDraw().LightCount);
            engine.Apply(Frame(1, 0, Config() + ";" + Spawn(), epoch: 2), 1);
            Assert.NotEqual(oldKey, OnlyLight(engine).Key);
            engine.Apply(Frame(1, 0, epoch: 1), 2); Assert.Equal(0, engine.BuildDraw().LightCount);
            engine.Apply(Frame(2, 1, Config() + ";" + Spawn(born: 1)), 2);
            Assert.Equal(1, engine.BuildDraw().LightCount);
            engine.ConfigureLighting(null); Assert.Equal(0, engine.BuildDraw().LightCount);
            Assert.Equal(1, engine.BuildDraw().Count);
        }

        [Fact]
        public void CandidateCapacityIsBoundedByActualMainArcsNotOrnamentCount()
        {
            var engine = Engine();
            engine.Apply(Frame(1, 1, Config() + ";" + string.Join(';', Enumerable.Range(1, 128).Select(i => Spawn(i, born: 1)))), 1);
            engine.Apply(Frame(2, 2, string.Join(';', Enumerable.Range(129, 128).Select(i => Spawn(i, born: 2)))), 1);
            var draw = engine.BuildDraw(); Assert.Equal(256, draw.LightCount); Assert.Equal(RayVisualCatalog.ArcLimit, draw.Lights.Length);
            Assert.Equal(256, draw.Lights.Take(draw.LightCount).Select(x => x.Key).Distinct().Count());
        }

        [Fact]
        public void CandidateWritesTheExistingSixteenFloatLayoutWithReservedZero()
        {
            var candidate = new WorldLightCandidate(123, 85, 10, 20, 30, .7f, 1, .5f, .25f,
                1, -1, 0, 7, 10, 20, 5, .2f);
            var data = Enumerable.Repeat(-99f, 20).ToArray();
            candidate.WriteTo(data, 2);
            Assert.Equal(new[] { 10f, 20f, 30f, .7f, 1f, .5f, .25f, 1f, -1f, 0f, 7f, 0f, 10f, 20f, 5f, .2f }, data.Skip(2).Take(16));
            Assert.Equal(-99f, data[1]); Assert.Equal(-99f, data[18]);
            Assert.Throws<ArgumentOutOfRangeException>(() => candidate.WriteTo(new float[16], 1));
            Assert.Throws<ArgumentNullException>(() => candidate.WriteTo(null, 0));
        }

        [Theory]
        [InlineData(0)] [InlineData(1)] [InlineData(2)] [InlineData(3)] [InlineData(4)]
        [InlineData(5)] [InlineData(6)] [InlineData(7)] [InlineData(8)] [InlineData(9)]
        public void GenericUpsertsKeepOneLightIdentityWhileNewShotsRearmTheEnvelope(int style)
        {
            var engine=Engine();
            engine.Apply(Frame(1,0,Config(style)+";"+Spawn(key:7,serial:1)),1);
            long key=OnlyLight(engine).Key;
            for(int tick=1;tick<=20;tick++)
            {
                Assert.True(engine.Apply(Frame(tick+1,tick,Spawn(born:tick,key:7,serial:tick+1,
                    operation:"u",ex:300+tick)),1));
                var light=OnlyLight(engine);
                Assert.Equal(key,light.Key);Assert.Equal(200+tick,light.Length);
                Assert.True(light.Energy>0);Assert.Equal(1,engine.ActiveCount);
            }
        }

        [Fact]
        public void NewNoneOwnerCanExpireBetweenDrawsWithoutRevivingOldChannelLight()
        {
            var engine=Engine();
            engine.Apply(Frame(1,0,Config(1,values:Values(20,4))+";"+Spawn(key:7,serial:1)),1);
            Assert.Equal(1,engine.BuildDraw().LightCount);
            engine.Apply(Frame(2,1,Config(2,2,values:Values(0,1),
                light:new RayLightOverrides("none",1,1,-1,-1))+";"
                +Spawn(id:2,config:2,born:1,sx:300,ex:400,key:7,serial:2)),1);
            // No BuildDraw while the newer, short-lived replacement exists.
            engine.Apply(Frame(3,3),1);
            Assert.Equal(1,engine.BuildDraw().Count);Assert.Equal(0,engine.BuildDraw().LightCount);
            engine.Apply(Frame(4,4,Spawn(id:3,born:4,key:7,serial:1)),1);
            Assert.Equal(1,engine.ActiveCount);Assert.Equal(0,engine.BuildDraw().LightCount);
            engine.ConfigureLighting(null);engine.ConfigureLighting(Catalog.Value);
            Assert.Equal(0,engine.BuildDraw().LightCount);
            engine.Reset();engine.Apply(Frame(1,0,Config()+";"+Spawn(key:7,serial:1),epoch:2),1);
            Assert.Equal(1,engine.BuildDraw().LightCount);
        }

        [Fact]
        public void AnOlderSameSerialBodySnapshotCannotTakeBackTheNewerChannelLamp()
        {
            var engine=Engine();
            engine.Apply(Frame(1,0,Config()+";"+Spawn(key:7,serial:3)),1);
            long key=OnlyLight(engine).Key;
            engine.Apply(Frame(2,1,Spawn(id:2,born:1,sx:300,ex:500,key:7,serial:3)),1);
            Assert.Equal(300,OnlyLight(engine).X);
            engine.Apply(Frame(3,2,Spawn(born:2,sx:700,ex:900,key:7,serial:3,operation:"u")),1);
            var current=OnlyLight(engine);
            Assert.Equal(300,current.X);Assert.Equal(key,current.Key);Assert.Equal(2,engine.ActiveCount);
        }

        [Fact]
        public void ReusedChainAndForkSegmentsStillShareTheirParentsEnvironmentLight()
        {
            var engine=Engine();
            engine.Apply(Frame(1,0,Config()+";"+Spawn(key:7,serial:1)+";"
                +Spawn(id:2,kind:1,key:8,serial:1)+";"+Spawn(id:3,kind:2,key:9,serial:1)),1);
            Assert.Equal(3,engine.ActiveCount);Assert.Equal(1,engine.BuildDraw().LightCount);
            engine.Apply(Frame(2,1,Spawn(id:2,born:1,kind:1,key:8,serial:2,operation:"u")+";"
                +Spawn(id:3,born:1,kind:2,key:9,serial:2,operation:"u")),1);
            Assert.Equal(3,engine.ActiveCount);Assert.Equal(1,engine.BuildDraw().LightCount);
        }

        [Fact]
        public void AuthoredFlameLightsTheShooterAndOffAxisGroundAtUsefulFlashlightRelativeStrength()
        {
            var flame = AuthoredLight("喷火束");
            var torch = EquipmentReference(true);
            Assert.Equal(620f, flame.Length); Assert.Equal(224f, flame.HalfWidth);
            Assert.Equal(140f, flame.NearRadius);
            // The hand lamp's near fill is on the actor; the fire source is at
            // the muzzle. Test behind the muzzle and at foot height, away from
            // the flame's bright body, rather than sampling its white center.
            Assert.True(ReferenceField(flame, -55, 0) >= ReferenceField(torch, -55, 0) * .9);
            Assert.True(ReferenceField(flame, -55, 100) >= .12);
            Assert.True(ReferenceField(flame, -55, 100) >= ReferenceField(torch, -55, 100) * .4);
            Assert.True(ReferenceField(flame, 100, 60) >= ReferenceField(torch, 100, 60) * .9);
            Assert.True(ReferenceField(flame, 300, 60) >= ReferenceField(torch, 300, 60) * .85);
            Assert.True(ReferenceField(flame, 300, 100) >= ReferenceField(torch, 300, 100) * .8);
            // A dedicated lamp keeps the sustained far-field reach. Fire does
            // not illuminate past its actual endpoint to win this comparison.
            Assert.Equal(0, ReferenceField(flame, 700, 0));
            Assert.True(ReferenceField(torch, 700, 0) > .1);
        }

        [Theory]
        [InlineData("磁暴射线", .28)]
        [InlineData("光棱射线", .20)]
        [InlineData("光棱射线-强化", .20)]
        [InlineData("光谱射线", .20)]
        [InlineData("谐振波射线", .20)]
        [InlineData("涡旋射线", .20)]
        [InlineData("辉光射线", .65)]
        [InlineData("辉光射线-强化", .65)]
        [InlineData("波能射线", .65)]
        [InlineData("热能射线", .65)]
        [InlineData("热能射线-强化", .65)]
        [InlineData("等离子射线", .65)]
        [InlineData("铁枪聚束射线", .65)]
        [InlineData("镇暴射线", .20)]
        public void ActualWeaponGeometryHasReadableOffAxisLightingBeyondTheEquipmentLaser(string weapon, double minimum)
        {
            var ray = AuthoredLight(weapon);
            var laser = EquipmentReference(false);
            double rayMean = OffAxisMean(ray), laserMean = OffAxisMean(laser, ray.Length);
            Assert.True(rayMean >= minimum, $"{weapon}: off-axis field={rayMean:F4}, required={minimum:F4}");
            Assert.True(rayMean >= laserMean * 20, $"{weapon}: ray={rayMean:F4}, laser={laserMean:F4}");
        }

        [Fact]
        public void ShortFlameGrowthRetainsLocalReflectionButARealBlockCollapsesIt()
        {
            var start = AuthoredLight("喷火束", 80);
            var full = AuthoredLight("喷火束");
            var blocked = AuthoredLight("喷火束", 4);
            Assert.Equal(80f, start.Length); Assert.Equal(160f, start.HalfWidth); Assert.Equal(80f, start.NearRadius);
            Assert.True(ReferenceField(start, -40, 0) > .7);
            Assert.Equal(4f, blocked.Length); Assert.Equal(8f, blocked.HalfWidth); Assert.Equal(4f, blocked.NearRadius);
            Assert.Equal(0, ReferenceField(blocked, -40, 0));
            Assert.Equal(0, ReferenceField(blocked, 20, 0));
            Assert.True(ReferenceField(full, 300, 60) > ReferenceField(start, 300, 60));
        }

        [Fact]
        public void StrongerRayLightingStillUsesOneSlotAndPreservesBothEquipmentLightRecords()
        {
            var torch = EquipmentReference(true); var laser = EquipmentReference(false);
            var equipment = new CombatFxDrawFrame(0) {
                LightCount = 2, ResidentLightCount = 2, CandidateLightCount = 2
            };
            equipment.CandidateLights[0] = torch; equipment.CandidateLights[1] = laser;
            torch.WriteTo(equipment.Lights, 0); laser.WriteTo(equipment.Lights, 16);
            equipment.LightIds[0] = torch.Key; equipment.LightIds[1] = laser.Key;
            var rays = new RayVisualDrawFrame { LightCount = 1 };
            rays.Lights[0] = AuthoredLight("喷火束");
            var composer = new WorldLightComposer(.78f);
            composer.SetCombatFx(equipment); composer.SetRays(rays);
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(3, draw.LightCount); Assert.Equal(2, draw.ResidentLightCount);
            Assert.Equal(equipment.Lights.Take(32), draw.Lights.Take(32));
            Assert.Equal(rays.Lights[0], draw.CandidateLights[2]);
            Assert.Equal(.78f, draw.MaximumLightResponse);
        }

        // These tests use production bullet XML geometry and the existing light
        // shader's scalar field as a reference. They do not simulate color grading,
        // scene textures, ray-body occlusion or GPU rasterization; those need the
        // separate on/off environment ROI fixture.
        private static WorldLightCandidate AuthoredLight(string weapon, float? actualLength = null)
        {
            var config = XDocument.Load(Path.Combine(ProjectRoot(), "data/items/bullets_cases.xml"))
                .Descendants("bullet").Single(x => (string)x.Element("name") == weapon)
                .Element("attribute").Element("rayConfig");
            string styleName = (string)config.Element("vfxStyle");
            int style = Array.IndexOf(RayVisualCatalog.Styles, styleName);
            Assert.InRange(style, 0, 11);
            string presets = File.ReadAllText(Path.Combine(ProjectRoot(),
                "scripts/类定义/org/flashNight/arki/render/VfxPresets.as"));
            var preset = Regex.Match(presets, @"public static var " + Regex.Escape((string)config.Element("vfxPreset"))
                + @":Object\s*=\s*\{(?<fields>[\s\S]*?)\};");
            Assert.True(preset.Success, "Missing authored preset for " + weapon);
            float Field(string name, float fallback)
            {
                string text = (string)config.Element(name);
                if (text == null)
                {
                    var field = Regex.Match(preset.Groups["fields"].Value,
                        @"(?m)^\s*" + name + @":\s*(0x[0-9a-fA-F]+|[0-9.]+)");
                    if (!field.Success) return fallback;
                    text = field.Groups[1].Value;
                }
                return text.StartsWith("0x", StringComparison.Ordinal)
                    ? int.Parse(text.AsSpan(2), NumberStyles.HexNumber, CultureInfo.InvariantCulture)
                    : float.Parse(text, CultureInfo.InvariantCulture);
            }
            // Read only fields that determine this light's authored geometry,
            // color and lifetime; XML overrides its real VfxPresets values.
            var values = Values(Field("visualDuration", 5), Field("fadeOutDuration", 3),
                Field("thickness", 3), (int)Field("primaryColor", 0x99CCFF));
            float length = actualLength ?? Field("rayLength", 0);
            var engine = Engine();
            Assert.True(engine.Apply(Frame(1, 0, Config(style, values: values) + ";"
                + Spawn(sx: 100, sy: 200, ex: 100 + length, ey: 200, kind: style == 11 ? 4 : 0,
                    key: style == 11 ? 7 : 0)), 1));
            var composer = new WorldLightComposer(.78f);
            composer.SetRays(engine.BuildDraw());
            var result = composer.Compose(0, 0, 1);
            Assert.Equal(1, result.LightCount);
            return result.CandidateLights[0];
        }

        private static WorldLightCandidate EquipmentReference(bool flashlight)
        {
            // Read the AS2 authority's actual defaults, rather than comparing
            // against a weaker hand-copied lamp fixture after a future edit.
            string[] source = File.ReadAllLines(Path.Combine(ProjectRoot(),
                "scripts/类定义/org/flashNight/arki/render/EquipmentLightBridge.as"));
            float Default(string field)
            {
                string line = source.Single(x => x.Contains("var " + field + ":Number =", StringComparison.Ordinal)
                    && x.Contains("numberOr(", StringComparison.Ordinal));
                var match = Regex.Match(line, @"kind == 1 \? ([0-9.]+) : ([0-9.]+)");
                Assert.True(match.Success, "EquipmentLightBridge default changed: " + field);
                return float.Parse(match.Groups[flashlight ? 1 : 2].Value, CultureInfo.InvariantCulture);
            }
            return new WorldLightCandidate(flashlight ? -100 : -101, 100, 100, 200,
                Default("extent"), Default("energy"), 1, 1, 1, flashlight ? 1 : 2,
                1, 0, Default("width"), flashlight ? 45 : 0, flashlight ? 200 : 0,
                Default("nearRadius"), Default("nearEnergy"));
        }

        private static double OffAxisMean(WorldLightCandidate light, float? sampledLength = null)
        {
            double sum = 0;
            foreach (double fraction in new[] { .2, .4, .6 })
                foreach (double side in new[] { 30d, 40d, 50d })
                    sum += ReferenceField(light, (sampledLength ?? light.Length) * fraction, side);
            return sum / 9;
        }

        private static double Smooth(double a, double b, double x)
        {
            double t = Math.Clamp((x - a) / (b - a), 0, 1);
            return t * t * (3 - 2 * t);
        }

        private static double ReferenceField(WorldLightCandidate light, double along, double side)
        {
            // ShaderSources.h LVS/LPS, scale=1 (one field texel is 4 world px).
            // Test points are away from narrow AA boundaries.
            const double aa = 4;
            double t = along / light.Length, distance = Math.Abs(side);
            if (light.Kind == 2)
            {
                double normalized = distance / Math.Max(light.HalfWidth, aa);
                double lateral = Math.Exp(-3.5 * normalized * normalized)
                    * (1 - Smooth(light.HalfWidth * .65, light.HalfWidth + aa, distance));
                return light.Energy * lateral * (1 - .35 * Math.Clamp(t, 0, 1))
                    * Smooth(0, Math.Min(18, light.Length * .1), along) * (1 - Smooth(.72, 1, t));
            }
            Assert.Equal(1, light.Kind);
            double forward = t, width = Math.Max(t, .02) * light.HalfWidth;
            double gate = t >= 0 ? 1 : 0, disk = 0, centerSide = 0;
            if (light.NearRadius > 0)
            {
                double nx = light.NearX - light.X, ny = light.NearY - light.Y;
                double nearAlong = nx * light.DirectionX + ny * light.DirectionY;
                double nearSide = -nx * light.DirectionY + ny * light.DirectionX;
                double fromBase = along - nearAlong;
                forward = Math.Clamp(fromBase / Math.Max(light.Length - nearAlong, 1), 0, 1);
                width = light.NearRadius * .9 + (light.HalfWidth - light.NearRadius * .9) * Math.Sqrt(forward);
                centerSide = nearSide * (1 - Smooth(0, light.NearRadius * 1.2, fromBase));
                gate = Smooth(-light.NearRadius * .35, light.NearRadius * .7, fromBase);
                double radial = Math.Sqrt(fromBase * fromBase + Math.Pow(side - nearSide, 2)) / light.NearRadius;
                disk = light.NearEnergy * Math.Exp(-2 * radial * radial)
                    * (1 - Smooth(.6, 1 + aa / light.NearRadius, radial));
            }
            double lateralDistance = Math.Abs(side - centerSide);
            double cross = lateralDistance / Math.Max(width, aa);
            double cone = light.Energy * Math.Exp(-2.4 * cross * cross)
                * (1 - Smooth(width * .7, width + aa, lateralDistance))
                * Math.Exp(-1.15 * Math.Max(forward, 0)) * (1 - Smooth(.72, 1, forward)) * gate;
            return disk + cone - disk * cone / Math.Max(Math.Max(light.Energy, light.NearEnergy), .0001);
        }

        private static string ProjectRoot()
        {
            for (var path = new DirectoryInfo(AppContext.BaseDirectory); path != null; path = path.Parent)
                if (File.Exists(Path.Combine(path.FullName, RayLightingCatalog.RelativePath))) return path.FullName;
            throw new DirectoryNotFoundException(RayLightingCatalog.RelativePath);
        }
    }
}
