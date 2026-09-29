using System;
using System.Globalization;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.HitNumbers;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    // Exercise the production partial FrameTask dispatch directly: no overlay, UI,
    // reflection, engine substitutes, or duplicate protocol reducer is involved.
    public sealed class FrameTaskProjectileTests
    {
        private static readonly Lazy<BulletVisualCatalog> Catalog = new(() => BulletVisualCatalog.Load(ProjectRoot()));
        private static readonly HitNumberCamera Camera = new(12, 34, 1.5f);

        private sealed class Probe
        {
            internal readonly FrameTask Task = new(null, null);
            internal int RayObserved, RayRejected, RayCleared, ChainRejected, RayCount;
            internal float[] RayData = Array.Empty<float>();
            internal BulletVisualFrame LastBullets;
            internal float CameraX, CameraY, CameraScale;
            internal Probe()
            {
                Task.ConfigureProjectileVisuals(Catalog.Value);
                Task.RayVisualObserved = (draw, x, y, scale) => {
                    RayObserved++; RayCount = draw.Count;
                    RayData = draw.Data.Take(draw.Count * RayVisualCatalog.Stride).ToArray();
                    CameraX = x; CameraY = y; CameraScale = scale;
                };
                Task.RayVisualRejected = () => RayRejected++;
                Task.RayVisualCleared = () => {
                    RayCleared++; RayCount = 0; RayData = Array.Empty<float>();
                };
                Task.ChainVisualRejected = () => ChainRejected++;
                Task.BulletVisualObserved = (draw, x, y, scale) => LastBullets = draw;
            }
            internal void Feed(string ray, string chain, int generation = 7) =>
                Task.ObserveProjectileVisuals(ray, chain, generation, Camera);
            internal BulletVisualFrame Bullets(bool ordinary = false)
            {
                var items = ordinary
                    ? new[] { new BulletVisualInstance(0, 500, 600, 0, 100, 100, 100) }
                    : Array.Empty<BulletVisualInstance>();
                Task.DispatchProjectileBullets(BulletVisualFrame.Compose(0, 0, items,
                    Array.Empty<BulletVisualInstance>()), Camera);
                return LastBullets;
            }
            internal void Start()
            {
                Feed(Ray(1, Config() + ";" + Spawn()), Chain(1, Group() + ";" + Birth));
                Assert.Equal(1, RayCount);
                Assert.Equal(1, Bullets().ChainCount);
            }
        }

        private static string Config(int style = 0)
        {
            float[] values = Enumerable.Repeat(1f, RayVisualCatalog.FieldNames.Length).ToArray();
            values[0] = 0xFF8800; values[1] = 0xFFDD88; values[2] = 4; values[3] = 20;
            values[4] = 3; values[5] = 0; values[6] = 70; values[7] = 100;
            values[10] = 35; values[11] = 40; values[14] = .7f; values[20] = 60;
            values[24] = 15; values[25] = 50; values[37] = 1; values[41] = 0x7A6F66;
            values[42] = 0xFFB347; values[49] = 0x34302A;
            return $"c,1,{style}," + string.Join(',', values.Select(x => x.ToString(CultureInfo.InvariantCulture))) + ",-";
        }
        private static string Spawn(int id = 1, int config = 1, int born = 0,
            int end = 200, bool flame = false) =>
            $"s,{id},{config},{born},0,100,50,{end},50,{(flame ? 4 : 0)},0,1,0,123,{(flame ? 1 : 0)},1,500,1,5,2,-,-,0";
        private static string Ray(int sequence, string body = "", int epoch = 5, int tick = 1) =>
            $"{epoch}|{sequence}|{tick}|0;o,0,0" + (body.Length > 0 ? ";" + body : "");
        private static string Group(int step = 0) => $"G,1,0,{step},100,200,0,100,100,100,1,10,0";
        private const string Birth = "B,1,1,2,3,0.6,0.8,20";
        private static string Chain(int sequence, string body, int epoch = 8, int tick = 1) =>
            $"1|{epoch}|{sequence}|{tick}" + (body.Length > 0 ? ";" + body : "");

        [Fact]
        public void DuplicateSequenceOldEpochAndOldGenerationKeepTheCurrentPictures()
        {
            var p = new Probe(); p.Start();
            int rayObserved = p.RayObserved, cleared = p.RayCleared;
            float[] rayData = p.RayData.ToArray();
            p.Feed("malformed", "malformed", generation: 6);
            p.Feed(Ray(1, Config() + ";" + Spawn()), Chain(1, Group() + ";" + Birth));
            p.Feed(Ray(99, Config() + ";" + Spawn(end: 900), epoch: 4),
                Chain(99, Group(80), epoch: 7));
            Assert.Equal(rayObserved, p.RayObserved);
            Assert.Equal(cleared, p.RayCleared);
            Assert.Equal(rayData, p.RayData);
            Assert.Equal(203f, Assert.Single(p.Bullets().Instances).Y);
            Assert.Equal(0, p.RayRejected); Assert.Equal(0, p.ChainRejected);
            p.Feed(Ray(2, tick: 2), Chain(2, Group(1), tick: 2));
            Assert.Equal(209f, Assert.Single(p.Bullets().Instances).Y);
            Assert.Equal(Camera.OffsetX, p.CameraX);
            Assert.Equal(Camera.OffsetY, p.CameraY);
            Assert.Equal(Camera.Scale, p.CameraScale);
        }

        [Fact]
        public void RayCapabilityCycleClearsOnlyRaysAndRequiresFreshEpochConfiguration()
        {
            var p = new Probe();
            p.Feed(Ray(1, Config(11) + ";" + Spawn(flame: true)), Chain(1, Group() + ";" + Birth));
            p.Task.InvalidateRayVisuals();
            p.Task.InvalidateRayVisuals(); // duplicate invalidation does not consume another epoch
            Assert.Equal(0, p.RayCount);
            Assert.Single(p.Bullets().Instances);
            int observed = p.RayObserved;
            p.Feed(Ray(2, Config(11) + ";" + Spawn(id: 2, end: 900, flame: true), tick: 2),
                Chain(2, Group(1), tick: 2));
            Assert.Equal(observed, p.RayObserved);
            Assert.Equal(0, p.RayCount);
            Assert.Equal(209f, Assert.Single(p.Bullets().Instances).Y);
            p.Feed(Ray(1, Config(11) + ";" + Spawn(end: 350, flame: true), epoch: 6), null);
            Assert.Equal(1, p.RayCount);
            Assert.Equal(350f, p.RayData[2]);
            Assert.Equal(0, p.RayRejected); Assert.Equal(0, p.ChainRejected);
        }

        [Fact]
        public void SceneResetFiltersOldEpochBeforeAnEmptyEngineSeesMissingBirths()
        {
            var p = new Probe(); p.Start();
            p.Task.ResetProjectileScene();
            Assert.Equal(0, p.RayCount);
            Assert.Empty(p.Bullets().Instances);
            p.Feed(Ray(2, Config() + ";" + Spawn()), Chain(2, Group(1)));
            Assert.Equal(0, p.RayCount);
            Assert.Empty(p.Bullets().Instances);
            Assert.Equal(0, p.RayRejected); Assert.Equal(0, p.ChainRejected);
            // A stale chain section must not suppress a legitimate ray in the same F packet.
            p.Feed(Ray(1, Config() + ";" + Spawn(end: 400), epoch: 6), Chain(3, Group(2)));
            Assert.Equal(400f, p.RayData[2]);
            Assert.Empty(p.Bullets().Instances);
            p.Feed(null, Chain(1, Group() + ";" + Birth, epoch: 9));
            Assert.Single(p.Bullets().Instances);
        }

        [Fact]
        public void DisconnectRetiresItsGenerationWhileTheNextConnectionCanRestartEpochs()
        {
            var p = new Probe(); p.Start();
            p.Task.ResetProjectileVisualsForGeneration(6);
            Assert.Equal(1, p.RayCount);
            Assert.Single(p.Bullets().Instances);
            p.Task.ResetProjectileVisualsForGeneration(7);
            p.Feed(Ray(90, Config() + ";" + Spawn(), epoch: 99),
                Chain(90, Group() + ";" + Birth, epoch: 99), generation: 7);
            Assert.Equal(0, p.RayCount); Assert.Empty(p.Bullets().Instances);
            p.Feed(Ray(1, Config() + ";" + Spawn(), epoch: 1),
                Chain(1, Group() + ";" + Birth, epoch: 1), generation: 8);
            Assert.Equal(1, p.RayCount); Assert.Single(p.Bullets().Instances);
            p.Task.ResetProjectileVisualsForGeneration(7);
            Assert.Equal(1, p.RayCount); Assert.Single(p.Bullets().Instances);
            Assert.Equal(0, p.RayRejected); Assert.Equal(0, p.ChainRejected);
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void MalformedAndSemanticRayRejectionsClearRaysButContinueTheChainSection(bool malformed)
        {
            var p = new Probe(); p.Start();
            string rejected = malformed ? "not a ray frame" : Ray(2, Spawn(id: 2, config: 2, born: 1), tick: 2);
            p.Feed(rejected, Chain(2, Group(1), tick: 2));
            Assert.Equal(1, p.RayRejected); Assert.Equal(0, p.ChainRejected);
            Assert.Equal(0, p.RayCount);
            Assert.Equal(209f, Assert.Single(p.Bullets().Instances).Y);
            int observed = p.RayObserved;
            p.Feed(Ray(3, Config() + ";" + Spawn(id: 2)), Chain(3, Group(2), tick: 3));
            Assert.Equal(observed, p.RayObserved);
            Assert.Equal(215f, Assert.Single(p.Bullets().Instances).Y);
            p.Feed(Ray(1, Config() + ";" + Spawn(end: 450), epoch: 6), null);
            Assert.Equal(1, p.RayCount); Assert.Equal(450f, p.RayData[2]);
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void MalformedAndSemanticChainRejectionsDoNotInvalidateRaysOrOrdinaryBullets(bool malformed)
        {
            var p = new Probe(); p.Start();
            int cleared = p.RayCleared;
            string rejected = malformed ? "not a chain frame" : Chain(2, Group(3), tick: 2);
            p.Feed(Ray(2, Spawn(id: 2, born: 1, end: 350), tick: 2), rejected);
            Assert.Equal(1, p.ChainRejected); Assert.Equal(0, p.RayRejected);
            Assert.Equal(cleared, p.RayCleared);
            Assert.Equal(2, p.RayCount);
            var ordinary = p.Bullets(ordinary: true);
            Assert.Equal(0, ordinary.ChainCount);
            Assert.Equal(500f, Assert.Single(ordinary.Instances).X);
            p.Feed(null, Chain(1, Group() + ";" + Birth, epoch: 9));
            Assert.Single(p.Bullets().Instances);
            Assert.Equal(2, p.RayCount);
        }

        [Fact]
        public void SemanticallyRejectedFreshRayEpochCannotBeReusedAfterTheCapabilityCycle()
        {
            var p = new Probe(); p.Start();
            p.Feed(Ray(1, Spawn(config: 2), epoch: 10), null);
            Assert.Equal(1, p.RayRejected); Assert.Equal(0, p.RayCount);
            p.Feed(Ray(2, Config() + ";" + Spawn(end: 900), epoch: 10), null);
            Assert.Equal(0, p.RayCount);
            p.Feed(Ray(1, Config() + ";" + Spawn(end: 700), epoch: 11), null);
            Assert.Equal(1, p.RayCount); Assert.Equal(700f, p.RayData[2]);
            Assert.Single(p.Bullets().Instances);
        }

        [Fact]
        public void FreshRayEpochWithoutConfigurationRevokesOnlyItsOwnCapability()
        {
            var p = new Probe(); p.Start();
            p.Task.InvalidateRayVisuals();
            p.Feed(Ray(1, Spawn(), epoch: 6), Chain(2, Group(1), tick: 2));
            Assert.Equal(1, p.RayRejected); Assert.Equal(0, p.RayCount);
            Assert.Equal(209f, Assert.Single(p.Bullets().Instances).Y);
            p.Feed(Ray(1, Config() + ";" + Spawn(), epoch: 7), null);
            Assert.Equal(1, p.RayCount);
        }

        [Fact]
        public void VisualFaultReportsAreBoundedAndRoutedToTheRenderFaultSink()
        {
            var p = new Probe();
            int calls = 0; string channel = null, reason = null;
            p.Task.VisualFaultReported = (c, r) => { calls++; channel = c; reason = r; };
            p.Task.HandleVisualFault("chain|reserve_overflow");
            Assert.Equal(1, calls);
            Assert.Equal("chain", channel);
            Assert.Equal("reserve_overflow", reason);
            // 畸形/未知通道/空原因/超长原因全部丢弃，不进入故障路径。
            p.Task.HandleVisualFault(null);
            p.Task.HandleVisualFault("hud|reserve_overflow");
            p.Task.HandleVisualFault("chain");
            p.Task.HandleVisualFault("ray|" + new string('x', 65));
            Assert.Equal(1, calls);
            p.Task.HandleVisualFault("bullet|caps_invalid");
            Assert.Equal(2, calls);
            Assert.Equal("bullet", channel);
            Assert.Equal("caps_invalid", reason);
        }

        [Fact]
        public void DuplicateOrOldRayPacketsWithUnresolvableReferencesAreIgnored()
        {
            var p = new Probe(); p.Start();
            p.Feed(Ray(1, Spawn(id: 2, config: 2)), null);
            p.Feed(Ray(50, Spawn(id: 2, config: 2), epoch: 4), null);
            Assert.Equal(1, p.RayCount);
            Assert.Equal(0, p.RayRejected);
            Assert.Single(p.Bullets().Instances);
        }

        private static string ProjectRoot()
        {
            for (var path = new DirectoryInfo(AppContext.BaseDirectory); path != null; path = path.Parent)
                if (File.Exists(Path.Combine(path.FullName, BulletVisualCatalog.RelativePath))) return path.FullName;
            throw new DirectoryNotFoundException(BulletVisualCatalog.RelativePath);
        }
    }
}