using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class BloodVisualTests
    {
        private static readonly Lazy<CombatFxCatalog> Loaded = new(() => CombatFxCatalog.Load(ProjectRoot()));
        private static CombatFxCatalog Catalog => Loaded.Value;
        private static int BloodStyle
        {
            get
            {
                int index = Array.FindIndex(Catalog.Styles, style => style.Linkage == "子弹碎片-飞血");
                Assert.True(index >= 0, "The paired catalog must include the ordinary blood style.");
                return index;
            }
        }
        private static string ProjectRoot()
        {
            var path = new DirectoryInfo(AppContext.BaseDirectory);
            while (path != null && !File.Exists(Path.Combine(path.FullName, CombatFxCatalog.RelativePath))) path = path.Parent;
            return path?.FullName ?? throw new InvalidOperationException("Missing combat effect fixture catalog");
        }
        private static BloodVisualEvent Birth(int id, double x = 100, double y = 40, double z = 1000000,
            double scale = 100, uint seed = 123, double gravity = 1) =>
            BloodVisualEvent.Birth(id, BloodStyle, x, y, z, scale, seed, gravity);
        private static BloodVisualEvent[] Empty => Array.Empty<BloodVisualEvent>();
        private static float[] Draw(BloodVisualEngine engine)
        {
            var draw = new CombatFxDrawFrame(512);
            int count = engine.AppendDraw(draw, 0);
            return draw.Data.Take(count * 16).ToArray();
        }
        private static float[] Xs(BloodVisualEngine engine) => Draw(engine).Where((_, index) => index % 16 == 0).ToArray();

        [Fact]
        public void BirthKeepsItsSourcePoseAndTheSameSeedReplaysTheSameVisual()
        {
            var left = new BloodVisualEngine(Catalog);
            var right = new BloodVisualEngine(Catalog);
            left.Apply(new[] { Birth(1) }, 3);
            right.Apply(new[] { Birth(1) }, 3);
            Assert.Equal(100f, Draw(left)[0]); Assert.Equal(40f, Draw(left)[1]); Assert.Equal(0f, Draw(left)[2]);
            for (int tick = 0; tick < 20; tick++)
            {
                Assert.Equal(Draw(left), Draw(right));
                Assert.Equal(left.Count, right.Count);
                left.Apply(Empty, 1); right.Apply(Empty, 1);
            }
            Assert.Empty(left.TakeLandings()); Assert.Empty(right.TakeLandings());
        }

        [Fact]
        public void SeededAppearanceUsesAnAuthoredVariantAndPreservesMirroring()
        {
            var style = Catalog.Styles[BloodStyle];
            Assert.True(style.IsBlood); Assert.Equal(5, style.Variants.Length);
            Assert.All(style.Variants, variant => Assert.Single(variant));
            var engine = new BloodVisualEngine(Catalog);
            engine.Apply(new[] { Birth(1, scale: -100) }, 0);
            float[] draw = Draw(engine);
            Assert.InRange(draw[4], -1.5f, -.74f); Assert.Equal(1f, draw[5]);
            Assert.Equal(style.WorldLit ? 1f : 0f, draw[7]);
            Assert.True(style.Variants.Any(variant => {
                var image = style.Frames[variant[0]];
                return new[] { image.OffsetX, image.OffsetY, image.Width, image.Height, image.U0, image.V0, image.U1, image.V1 }.SequenceEqual(draw.Skip(8));
            }), "The chosen blood picture must retain an authored frame and registration.");
            engine.Apply(Empty, 3);
            Assert.Equal(draw.Skip(8).ToArray(), Draw(engine).Skip(8).ToArray());
        }

        [Fact]
        public void GroundIsCheckedBeforeMotionAndLandingIsEmittedOnlyOnce()
        {
            var engine = new BloodVisualEngine(Catalog);
            engine.Apply(new[] { Birth(10, x: 120, y: 80, z: 80) }, 0);
            Assert.Equal(1, engine.Count); Assert.Equal(0, engine.PendingLandings);
            engine.Apply(Empty, 1);
            Assert.Equal(0, engine.Count); Assert.True(engine.HasState);
            var landing = Assert.Single(engine.TakeLandings());
            Assert.Equal(120d, landing.X); Assert.Equal(80d, landing.Y); Assert.InRange(landing.Variant, 0, 7);
            Assert.Empty(engine.TakeLandings());
            engine.Apply(Empty, 1);
            Assert.Empty(engine.TakeLandings()); Assert.False(engine.HasState);
        }

        [Fact]
        public void LandingBacklogDrainsInUniqueBatchesOfEightAndKeepsStateUntilDrained()
        {
            var engine = new BloodVisualEngine(Catalog);
            engine.Apply(Enumerable.Range(1, 64).Select(id => Birth(id, x: id, y: 80, z: 80)).ToArray(), 0);
            engine.Apply(Empty, 1);
            Assert.Equal(0, engine.Count); Assert.Equal(64, engine.PendingLandings); Assert.True(engine.HasState);
            var landings = new List<BloodVisualLanding>();
            while (engine.PendingLandings > 0)
            {
                var batch = engine.TakeLandings();
                Assert.InRange(batch.Length, 1, BloodVisualEngine.LandingBatchLimit);
                landings.AddRange(batch);
            }
            Assert.Equal(64, landings.Count); Assert.Equal(64, landings.Select(landing => landing.Id).Distinct().Count());
            Assert.Equal(Enumerable.Range(1, 64).Select(id => (double)id).OrderBy(x => x), landings.Select(landing => landing.X).OrderBy(x => x));
            Assert.Empty(engine.TakeLandings()); Assert.False(engine.HasState);
        }

        [Fact]
        public void AirborneRetirementUsesOnlyTheVisualCheckpointsAndNeverExceedsSixtyTicks()
        {
            var retirementAges = new List<int>();
            for (uint seed = 1; seed <= 128; seed++)
            {
                var engine = new BloodVisualEngine(Catalog);
                engine.Apply(new[] { Birth(1, seed: seed) }, 0);
                int age = 0;
                while (engine.Count > 0 && age < 60) { engine.Apply(Empty, 1); age++; }
                Assert.Equal(0, engine.Count); Assert.Contains(age, new[] { 15, 30, 45, 60 });
                Assert.Empty(engine.TakeLandings()); retirementAges.Add(age);
            }
            Assert.Contains(retirementAges, age => age < 60);
            Assert.Contains(60, retirementAges);
        }

        [Fact]
        public void FullCapacityDropsOnlyNewDecorationAndDroppedBirthCannotBeRetried()
        {
            var engine = new BloodVisualEngine(Catalog);
            engine.Apply(Enumerable.Range(1, 64).Select(id => Birth(id, x: id, y: 80, z: 80)).ToArray(), 0);
            float[] before = Xs(engine);
            engine.Apply(new[] { Birth(65, x: 650) }, 0);
            Assert.Equal(before, Xs(engine)); Assert.Equal(1, engine.Dropped);
            engine.Apply(Empty, 1);
            engine.Apply(new[] { Birth(65, x: 650), Birth(66, x: 660) }, 0);
            Assert.Equal(new[] { 660f }, Xs(engine));
        }

        [Fact]
        public void DuplicateBirthDoesNotReappearAfterLandingButResetAllowsANewNamespace()
        {
            var engine = new BloodVisualEngine(Catalog);
            engine.Apply(new[] { Birth(1, y: 80, z: 80) }, 0); engine.Apply(Empty, 1); engine.TakeLandings();
            engine.Apply(new[] { Birth(1, x: 900) }, 0);
            Assert.Empty(Draw(engine)); Assert.Empty(engine.TakeLandings());
            engine.Reset(); engine.Apply(new[] { Birth(1, x: 900) }, 0);
            Assert.Equal(new[] { 900f }, Xs(engine));
        }

        [Fact]
        public void LongGapClearsActiveAndPendingDecorationWithoutReplayingOldBirths()
        {
            var engine = new BloodVisualEngine(Catalog);
            engine.Apply(new[] { Birth(1, y: 80, z: 80), Birth(2) }, 0);
            engine.Apply(Empty, 1);
            Assert.Equal(1, engine.Count); Assert.Equal(1, engine.PendingLandings);
            engine.Apply(Empty, 9);
            Assert.False(engine.HasState); Assert.Empty(engine.TakeLandings()); Assert.Empty(Draw(engine));
            engine.Apply(new[] { Birth(1), Birth(2), Birth(3, x: 300) }, 0);
            Assert.Equal(new[] { 300f }, Xs(engine));
        }

        [Fact]
        public void FullBloodBudgetAppendsToTheExisting448SpritesWithoutOverwritingThem()
        {
            var engine = new BloodVisualEngine(Catalog);
            engine.Apply(Enumerable.Range(1, 64).Select(id => Birth(id, x: id)).ToArray(), 0);
            var draw = new CombatFxDrawFrame(512);
            for (int index = 0; index < 448 * 16; index++) draw.Data[index] = -12345f;
            Assert.Equal(512, engine.AppendDraw(draw, 448));
            Assert.All(draw.Data.Take(448 * 16), value => Assert.Equal(-12345f, value));
            Assert.Equal(1f, draw.Data[448 * 16]); Assert.Equal(64f, draw.Data[511 * 16]);
        }

        [Fact]
        public void ZeroElapsedAllowsNewBirthsWithoutMovingExistingParticles()
        {
            var engine = new BloodVisualEngine(Catalog);
            engine.Apply(new[] { Birth(1) }, 0);
            engine.Apply(new[] { Birth(2, x: 300) }, 0);
            Assert.Equal(new[] { 100f, 300f }, Xs(engine));
            Assert.Equal(40f, Draw(engine)[1]); Assert.Equal(40f, Draw(engine)[17]);
        }
    }
}