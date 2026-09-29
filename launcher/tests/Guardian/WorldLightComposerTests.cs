using System;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class WorldLightComposerTests
    {
        private static WorldLightCandidate Radial(long key, int priority = 65, float x = 300,
            float y = 200, float radius = 30, float energy = 1) =>
            new(key, priority, x, y, radius, energy, 1, .5f, .25f, 0);

        private static RayVisualDrawFrame Rays(params WorldLightCandidate[] lights)
        {
            var result = new RayVisualDrawFrame { LightCount = lights.Length };
            Array.Copy(lights, result.Lights, lights.Length); return result;
        }

        private static CombatFxDrawFrame Fx(int residents, params WorldLightCandidate[] candidates)
        {
            var result = new CombatFxDrawFrame(3) { Count = 3, CasingCount = 1, ImpactCount = 1,
                LightCount = Math.Min(16, candidates.Length), ResidentLightCount = residents,
                CandidateLightCount = candidates.Length, MaximumLightResponse = .78f };
            for (int i = 0; i < result.Data.Length; i++) result.Data[i] = i * .03125f;
            Array.Copy(candidates, result.CandidateLights, candidates.Length);
            for (int i = 0; i < result.LightCount; i++)
            {
                candidates[i].WriteTo(result.Lights, i * 16); result.LightIds[i] = candidates[i].Key;
            }
            return result;
        }

        [Fact]
        public void SettersSnapshotBorrowedEngineBuffersBeforeTheProducerReusesThem()
        {
            var fx = Fx(1, Radial(1, 70, x:100));
            float[] spriteBytes = (float[])fx.Data.Clone();
            var rays = Rays(Radial(20, 65, x:500));
            var composer = new WorldLightComposer(.78f);
            composer.SetCombatFx(fx); composer.SetRays(rays);
            Array.Fill(fx.Data, 999f); Array.Fill(fx.Lights, 999f); Array.Fill(fx.LightIds, 999L);
            Array.Clear(fx.CandidateLights); fx.Count = fx.LightCount = fx.CandidateLightCount = 0;
            rays.Lights[0] = default; rays.LightCount = 0;
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(3, draw.Count); Assert.Equal(1, draw.CasingCount); Assert.Equal(1, draw.ImpactCount);
            Assert.Equal(spriteBytes, draw.Data.Take(spriteBytes.Length));
            Assert.Equal(2, draw.LightCount);
            Assert.Equal(new long[] { 1, 20 }, draw.LightIds.Take(2));
            Assert.Equal(100f, draw.Lights[0]); Assert.Equal(500f, draw.Lights[16]);
        }

        [Fact]
        public void WithoutContributingRayLightsLegacyFxSelectionAndSpriteBytesAreExact()
        {
            var all = Enumerable.Range(1, 16).Select(i => Radial(i, 70, x:100 + i))
                .Concat(Enumerable.Range(1, 16).Select(i => Radial(-i, 75, x:500 + i))).ToArray();
            var fx = Fx(16, all);
            var composer = new WorldLightComposer(.78f); composer.SetCombatFx(fx);
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(16, draw.LightCount); Assert.Equal(16, draw.ResidentLightCount);
            Assert.Equal(fx.Lights, draw.Lights); Assert.Equal(fx.LightIds, draw.LightIds);
            Assert.Equal(fx.Data, draw.Data.Take(fx.Data.Length));
            // A ray whose entire light lies off screen must not rotate the FX budget.
            composer.SetRays(Rays(Radial(900, 85, x:5000)));
            draw = composer.Compose(0, 0, 1);
            Assert.Equal(fx.Lights, draw.Lights); Assert.Equal(fx.LightIds, draw.LightIds);
        }

        [Fact]
        public void UnifiedBudgetCanSelectMuzzleCandidatesPreviouslyHiddenBehindResidents()
        {
            var all = Enumerable.Range(1, 16).Select(i => Radial(i, 70, x:100 + i))
                .Concat(Enumerable.Range(1, 16).Select(i => Radial(-i, 75, x:500 + i))).ToArray();
            var composer = new WorldLightComposer(.78f); composer.SetCombatFx(Fx(16, all));
            composer.SetRays(Rays(Radial(900, 85)));
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(16, draw.LightCount); Assert.Equal(0, draw.ResidentLightCount);
            Assert.Equal(15, draw.LightIds.Take(16).Count(id => id < 0));
            Assert.Contains(900L, draw.LightIds.Take(16));
            composer.ClearRays();
            Assert.Equal(Enumerable.Range(1, 16).Select(i => (long)i), composer.Compose(0, 0, 1).LightIds.Take(16));
        }

        [Fact]
        public void DirectionalEquipmentKeepsItsPriorityUnderFullRayPressure()
        {
            var equipment = Enumerable.Range(1, 16).Select(i => new WorldLightCandidate(i, 100,
                100 + i, 200, 200, .8f, 1, 1, 1, 1, 1, 0, 30)).ToArray();
            var composer = new WorldLightComposer(.78f); composer.SetCombatFx(Fx(16, equipment));
            composer.SetRays(Rays(Enumerable.Range(1, 256).Select(i => Radial(1000 + i, 85)).ToArray()));
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(16, draw.LightCount); Assert.Equal(16, draw.ResidentLightCount);
            Assert.Equal(Enumerable.Range(1, 16).Select(i => (long)i), draw.LightIds.Take(16));
        }

        [Fact]
        public void SourceDomainsDoNotCollideWhenEquipmentMuzzleAndRayKeysAreEqual()
        {
            var composer = new WorldLightComposer(.78f);
            composer.SetCombatFx(Fx(1, Radial(7, 70, x:100), Radial(7, 75, x:200)));
            composer.SetRays(Rays(Radial(7, 65, x:300)));
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(3, draw.LightCount);
            Assert.Equal(new[] { 100f, 200f, 300f }, Enumerable.Range(0, 3).Select(i => draw.Lights[i * 16]));
        }

        [Fact]
        public void ClearingEitherSourceImmediatelyKeepsTheOtherAndDoesNotReplaySprites()
        {
            var composer = new WorldLightComposer(.61f);
            var fx = Fx(1, Radial(1, 70));
            composer.SetCombatFx(fx); composer.SetRays(Rays(Radial(2, 85)));
            Assert.Equal(2, composer.Compose(0, 0, 1).LightCount);
            composer.ClearCombatFx();
            var raysOnly = composer.Compose(0, 0, 1);
            Assert.Equal(0, raysOnly.Count); Assert.Equal(1, raysOnly.LightCount);
            Assert.Equal(.61f, raysOnly.MaximumLightResponse);
            Assert.Equal(2, raysOnly.LightIds[0]);
            composer.SetCombatFx(fx); composer.ClearRays();
            var fxOnly = composer.Compose(0, 0, 1);
            Assert.Equal(3, fxOnly.Count); Assert.Equal(1, fxOnly.LightCount); Assert.Equal(1, fxOnly.LightIds[0]);
            composer.Reset();
            var empty = composer.Compose(0, 0, 1);
            Assert.Equal(0, empty.Count); Assert.Equal(0, empty.LightCount); Assert.Equal(.61f, empty.MaximumLightResponse);
        }

        [Fact]
        public void RayOnlyLightUsesConfiguredResponseBeforeAnyF6Arrives()
        {
            var composer = new WorldLightComposer(.73f); composer.SetRays(Rays(Radial(1)));
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(0, draw.Count); Assert.Equal(1, draw.LightCount); Assert.Equal(.73f, draw.MaximumLightResponse);
        }

        [Fact]
        public void CameraPanZoomAndMirroredProjectionChangeEligibilityWithoutChangingWorldRecords()
        {
            var composer = new WorldLightComposer(.78f);
            composer.SetRays(Rays(Radial(1, x:2000, y:100)));
            Assert.Equal(0, composer.Compose(0, 0, 1).LightCount);
            var panned = composer.Compose(-1900, 0, 1);
            Assert.Equal(1, panned.LightCount); Assert.Equal(2000f, panned.Lights[0]);
            composer.SetRays(Rays(Radial(2, x:100, y:100)));
            Assert.Equal(1, composer.Compose(1024, 576, -1).LightCount);
            Assert.Equal(0, composer.Compose(0, 0, -1).LightCount);
            Assert.Equal(1, composer.Compose(0, 0, .5f).LightCount);
        }

        [Fact]
        public void DirectionalFootprintRejectsEmptyAabbCornersAndKeepsMirroredBeams()
        {
            var composer = new WorldLightComposer(.78f);
            float diagonal = MathF.Sqrt(.5f);
            composer.SetRays(Rays(new WorldLightCandidate(1, 65, -400, 100, 707.1068f,
                1, 1, 1, 1, 2, diagonal, -diagonal, 4)));
            Assert.Equal(0, composer.Compose(0, 0, 1).LightCount);
            composer.SetRays(Rays(new WorldLightCandidate(2, 65, 200, 200, 300,
                1, 1, 1, 1, 2, -1, 0, 4)));
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(1, draw.LightCount); Assert.Equal(-1f, draw.Lights[8]);
        }

        [Fact]
        public void BoundaryAlignedAndDegenerateQuadsStayBounded()
        {
            var composer = new WorldLightComposer(.78f);
            // The top clip emits the same two boundary vertices from both
            // intersections and current endpoints; the visible area is zero.
            composer.SetRays(Rays(new WorldLightCandidate(1, 65, .5f, -10, 8,
                1, 1, 1, 1, 2, 0, 1, .5f)));
            Assert.Equal(0, composer.Compose(0, 0, 1).LightCount);
            float[] xs = { -1026, -2, 0, 1024, 1026 };
            float[] ys = { -578, -2, 0, 576, 578 };
            foreach (float x in xs) foreach (float y in ys) for (int angle = 0; angle < 8; angle++)
            {
                float radians = angle * MathF.PI / 4;
                composer.SetRays(Rays(new WorldLightCandidate(1, 65, x, y, 1024,
                    1, 1, 1, 1, 2, MathF.Cos(radians), MathF.Sin(radians), 512)));
                var draw = composer.Compose(0, 0, 1);
                Assert.InRange(draw.LightCount, 0, 1);
                Assert.All(draw.Lights.Take(draw.LightCount * 16), value => Assert.True(float.IsFinite(value)));
            }
        }

        [Fact]
        public void RadialCandidatesKeepTheReviewed320UnitRadiusBound()
        {
            var composer = new WorldLightComposer(.78f);
            composer.SetRays(Rays(Radial(1, radius:321)));
            Assert.Equal(0, composer.Compose(0, 0, 1).LightCount);
            composer.SetRays(Rays(Radial(1, radius:320)));
            Assert.Equal(1, composer.Compose(0, 0, 1).LightCount);
        }

        [Fact]
        public void NearFillMayContributeWhenTheDirectionalOriginIsOffscreenAndBaseEnergyIsZero()
        {
            var composer = new WorldLightComposer(.78f);
            composer.SetRays(Rays(new WorldLightCandidate(1, 85, 1800, 100, 100,
                0, 1, 1, 1, 1, 1, 0, 10, 100, 100, 80, 1)));
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(1, draw.LightCount); Assert.Equal(80f, draw.Lights[14]); Assert.Equal(1f, draw.Lights[15]);
        }

        [Fact]
        public void SelectionHasSmallHysteresisButRemovedLightsNeverKeepTheirSlots()
        {
            var composer = new WorldLightComposer(.78f);
            composer.SetRays(Rays(Enumerable.Range(1, 16).Select(i => Radial(i, 55)).ToArray()));
            Assert.Equal(16, composer.Compose(0, 0, 1).LightCount);
            var nearTie = Enumerable.Range(1, 16).Reverse().Select(i => Radial(i, 55))
                .Append(Radial(17, 55, energy:1.04f)).ToArray();
            composer.SetRays(Rays(nearTie));
            Assert.DoesNotContain(17L, composer.Compose(0, 0, 1).LightIds.Take(16));
            nearTie[^1] = Radial(17, 55, energy:1.2f); composer.SetRays(Rays(nearTie));
            Assert.Contains(17L, composer.Compose(0, 0, 1).LightIds.Take(16));
            composer.SetRays(Rays(Radial(99, 55)));
            var replaced = composer.Compose(0, 0, 1);
            Assert.Equal(1, replaced.LightCount); Assert.Equal(99, replaced.LightIds[0]);
        }

        [Fact]
        public void InvalidCandidatesAreDroppedAndDuplicateIdentityConsumesOnlyOneSlot()
        {
            var composer = new WorldLightComposer(.78f);
            composer.SetRays(Rays(Radial(1), Radial(1, energy:1.5f), Radial(2, x:float.NaN),
                Radial(3, radius:0), Radial(4, energy:0),
                new WorldLightCandidate(5, 65, 100, 100, 200, 1, 1, 1, 1, 2, 0, 0, 10)));
            var draw = composer.Compose(0, 0, 1);
            Assert.Equal(1, draw.LightCount); Assert.Equal(1.5f, draw.Lights[3]);
        }

        [Fact]
        public void ARejectedBorrowedFrameDoesNotPartiallyOverwriteTheLastSnapshot()
        {
            var composer = new WorldLightComposer(.78f); composer.SetRays(Rays(Radial(1)));
            var invalid = new RayVisualDrawFrame { LightCount = RayVisualCatalog.ArcLimit + 1 };
            Assert.Throws<ArgumentException>(() => composer.SetRays(invalid));
            Assert.Equal(1, composer.Compose(0, 0, 1).LightCount);
            Assert.Throws<ArgumentOutOfRangeException>(() => composer.Compose(0, 0, 0));
            Assert.Throws<ArgumentOutOfRangeException>(() => new WorldLightComposer(float.NaN));
        }

        [Fact]
        public void FxEngineExposesStableResidentAndMuzzleIdsWithoutChangingItsLegacyBudget()
        {
            CombatFxCatalog catalog = CombatFxCatalog.Load(ProjectRoot());
            int muzzle = Array.FindIndex(catalog.Styles, style => style.Linkage == "突击步枪枪火");
            string residents = string.Join(";", Enumerable.Range(1, 16)
                .Select(id => $"l,{id},0,{100 + id},200,0,0,60,0,0.5,1,0.5,0.25"));
            string muzzleEvent = $"m,{muzzle},300,200,100,100,0,123,0";
            Assert.True(CombatFxFrame.TryParse("1|1|1|0;" + residents + ";"
                + string.Join(";", Enumerable.Repeat(muzzleEvent, 32)), catalog, out var initial));
            var engine = new CombatFxEngine(catalog); engine.Apply(initial, 1);
            var frame = engine.BuildDraw();
            Assert.Equal(16, frame.LightCount); Assert.Equal(16, frame.ResidentLightCount);
            Assert.Equal(32, frame.CandidateLightCount); Assert.Equal(32, frame.Count); Assert.Equal(16, engine.LightDropped);
            Assert.All(frame.LightIds, id => Assert.True(id > 0));
            long[] ids = frame.CandidateLights.Take(32).Select(candidate => candidate.Key).ToArray();
            Assert.All(ids.Skip(16), id => Assert.True(id < 0)); Assert.Equal(32, ids.Distinct().Count());
            Assert.True(CombatFxFrame.TryParse("1|2|200|1;" + residents, catalog, out var paused));
            engine.Apply(paused, 1);
            Assert.Equal(ids, engine.BuildDraw().CandidateLights.Take(32).Select(candidate => candidate.Key));
            engine.Reset(); Assert.Equal(0, engine.BuildDraw().LightCount); Assert.Equal(0, engine.BuildDraw().CandidateLightCount);
        }

        private static string ProjectRoot()
        {
            for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory != null; directory = directory.Parent)
                if (File.Exists(Path.Combine(directory.FullName, CombatFxCatalog.RelativePath))) return directory.FullName;
            throw new FileNotFoundException(CombatFxCatalog.RelativePath);
        }
    }
}
