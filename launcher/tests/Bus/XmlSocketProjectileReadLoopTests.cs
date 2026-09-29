using System;
using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Bus;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    // Real localhost TCP -> authenticated test authority -> production ReadLoop ->
    // production FrameTask. No Flash process, compositor, or rendering stub is used.
    public sealed class XmlSocketProjectileReadLoopTests : IDisposable
    {
        private sealed record BulletObservation(int Frame, int NormalCount, int ChainCount,
            BulletVisualInstance[] Items, float X, float Y, float Scale);
        private sealed record RayObservation(int Count, float[] Data, float X, float Y, float Scale,
            WorldLightCandidate[] Lights);
        private static readonly Lazy<BulletVisualCatalog> Catalog = new(() => BulletVisualCatalog.Load(ProjectRoot()));
        private readonly FrameTask _frameTask = new(null, null);
        private readonly XmlSocketServer _server;
        private TcpClient _client;
        private readonly int _port;
        private readonly ConcurrentQueue<BulletObservation> _bullets = new();
        private readonly ConcurrentQueue<RayObservation> _rays = new();
        private readonly ConcurrentQueue<string> _order = new();
        private readonly ConcurrentQueue<string> _ui = new();
        private readonly ConcurrentQueue<string> _barriers = new();
        private readonly ConcurrentQueue<int> _readyGenerations = new();
        private readonly ConcurrentQueue<int> _disconnectedGenerations = new();
        private readonly SemaphoreSlim _barrierReady = new(0);
        private readonly SemaphoreSlim _bulletReady = new(0);
        private int _rayRejected, _chainRejected, _bulletRejected, _bulletCleared;

        public XmlSocketProjectileReadLoopTests()
        {
            var router = new MessageRouter();
            router.RegisterSync("projectile_test_barrier", msg => {
                _barriers.Enqueue(msg.Value<string>("tag"));
                _barrierReady.Release();
                return "{\"ok\":true}";
            });
            _frameTask.ConfigureBulletVisualShadow(Catalog.Value);
            _frameTask.ConfigureProjectileVisuals(Catalog.Value);
            _frameTask.RayVisualObserved = (frame, x, y, scale) => {
                _rays.Enqueue(new RayObservation(frame.Count,
                    frame.Data.Take(frame.Count * RayVisualCatalog.Stride).ToArray(), x, y, scale,
                    frame.Lights.Take(frame.LightCount).ToArray()));
                _order.Enqueue("ray:" + frame.Count);
            };
            _frameTask.BulletVisualObserved = (frame, x, y, scale) => {
                _bullets.Enqueue(new BulletObservation(frame.Frame, frame.NormalCount, frame.ChainCount,
                    frame.Instances.ToArray(), x, y, scale));
                _order.Enqueue("bullet:" + frame.Frame + ":" + frame.ChainCount);
                _bulletReady.Release();
            };
            _frameTask.RayVisualRejected = () => Interlocked.Increment(ref _rayRejected);
            _frameTask.ChainVisualRejected = () => Interlocked.Increment(ref _chainRejected);
            _frameTask.BulletVisualRejected = () => Interlocked.Increment(ref _bulletRejected);
            _frameTask.BulletVisualCleared = () => Interlocked.Increment(ref _bulletCleared);
            _server = new XmlSocketServer(router, AllowLoopbackXmlSocketPeerAuthority.Instance);
            _server.SetFrameHandler(_frameTask);
            _server.SetUiDataHandler(_ui.Enqueue);
            _server.OnClientReadyForGeneration += _readyGenerations.Enqueue;
            // Match the production disconnect wiring; no test-only state reset occurs.
            _server.OnClientDisconnectedForGeneration += _frameTask.ResetProjectileVisualsForGeneration;
            _server.OnClientDisconnectedForGeneration += _frameTask.ResetBulletVisualShadowForGeneration;
            _server.OnClientDisconnectedForGeneration += _disconnectedGenerations.Enqueue;
            _port = FreePort();
            Assert.True(_server.Start(_port));
            _client = new TcpClient(AddressFamily.InterNetwork) { NoDelay = true };
            _client.Connect(IPAddress.Loopback, _port);
            Assert.True(SpinWait.SpinUntil(() => _server.HasClient, TimeSpan.FromSeconds(2)));
        }

        public void Dispose()
        {
            _server.BeforeMessageTransitionForTests = null;
            _client?.Dispose();
            _server.Dispose();
            _frameTask.Stop();
            _barrierReady.Dispose();
            _bulletReady.Dispose();
        }

        [Fact]
        public async Task LightingOverridesReachTheActualTcpConsumerWithoutChangingBeamGeometry()
        {
            _frameTask.ConfigureRayLighting(RayLightingCatalog.Load(ProjectRoot()));
            string unlit=Config()+";l,1,none,1,1,-1,-1;"+Spawn();
            string red=Config()+";l,1,beam,1.5,2,16711680,1;"+Spawn();
            await SendBatch("lights", Wire(null,Ray(1,100,unlit),null),
                Wire(null,Ray(1,100,red,epoch:6),null));
            var frames=_rays.ToArray();Assert.Equal(2,frames.Length);
            Assert.Empty(frames[0].Lights);var light=Assert.Single(frames[1].Lights);
            Assert.Equal(frames[0].Data,frames[1].Data);
            Assert.Equal(2,light.Kind);Assert.Equal(100f,light.X);Assert.Equal(100f,light.Length);
            Assert.True(light.R>light.G && light.Energy>0);
            await SendBatch("retire-light", "R", Wire(null,Ray(2,101,epoch:6),null),
                Wire(null,Ray(1,100,unlit,epoch:7),null));
            var fresh=_rays.ToArray();Assert.Equal(3,fresh.Length);
            Assert.Empty(fresh[2].Lights);Assert.Equal(frames[0].Data,fresh[2].Data);
            AssertNoRejections();
        }

        [Fact]
        public async Task LargeFragmentedF5F7F8MessageReachesBothProductionDrawCallbacks()
        {
            string born = string.Join(';', Enumerable.Range(1, 600).Select(i => Birth(i, i)));
            string ui = "状态:" + string.Concat(Enumerable.Repeat("中文分段", 120));
            string payload = Wire(Ordinary(100), Ray(1, 100, Config() + ";" + Spawn(born: 100)),
                Chain(1, 100, Group() + ";" + born), ui) + "\0" + Barrier("fragmented") + "\0";
            byte[] bytes = Encoding.UTF8.GetBytes(payload);
            Assert.True(bytes.Length > 8192);
            var stream = _client.GetStream();
            for (int offset = 0; offset < bytes.Length; offset += 4093)
                await stream.WriteAsync(bytes.AsMemory(offset, Math.Min(4093, bytes.Length - offset)));
            await WaitBarrier("fragmented");
            var bullet = Assert.Single(_bullets);
            Assert.Equal(1, bullet.NormalCount);
            Assert.Equal(600, bullet.ChainCount);
            Assert.Equal(601, bullet.Items.Length);
            Assert.Equal(10f, bullet.Items[0].X);
            Assert.Equal(101f, bullet.Items[1].X);
            Assert.Equal(700f, bullet.Items[^1].X);
            Assert.Equal(203f, bullet.Items[^1].Y);
            Assert.Equal((12f, 34f, 1.5f), (bullet.X, bullet.Y, bullet.Scale));
            var ray = Assert.Single(_rays);
            Assert.Equal(1, ray.Count);
            Assert.Equal(200f, ray.Data[2]);
            Assert.Equal((12f, 34f, 1.5f), (ray.X, ray.Y, ray.Scale));
            Assert.Equal(ui, Assert.Single(_ui));
            Assert.Single(_readyGenerations);
            AssertNoRejections();
        }

        [Fact]
        public async Task OneTcpWriteWithMultipleNulFramesConsumesEveryBirthAndDeathInOrder()
        {
            string first = Wire(Ordinary(100), Ray(1, 100, Config() + ";" + Spawn(born: 100)),
                Chain(1, 100, Group() + ";" + Birth(1, 2)));
            string second = Wire(Ordinary(101), Ray(2, 101),
                Chain(2, 101, Group(1) + ";" + Birth(2, 10, 20, "0.5", "0.8660254037844386") + ";D,1,1"));
            string third = Wire(Ordinary(102), Ray(3, 102, Spawn(id: 2, born: 102, end: 350)),
                Chain(3, 102, Group(2)));
            string fourth = Wire(Ordinary(103), Ray(1, 103, epoch: 6), Chain(4, 103, ""));
            await SendBatch("ordered", first, second, third, fourth);
            var pictures = _bullets.ToArray();
            Assert.Equal(new[] { 100, 101, 102, 103 }, pictures.Select(x => x.Frame));
            Assert.Equal(new[] { 1, 1, 1, 0 }, pictures.Select(x => x.ChainCount));
            Assert.Equal(102f, pictures[0].Items[1].X);
            Assert.Equal(110f, pictures[1].Items[1].X);
            Assert.Equal(220f, pictures[1].Items[1].Y); // birth is already at its final step-1 pose
            Assert.Equal(225f, pictures[2].Items[1].Y); // next frame advances the replacement unit
            Assert.Single(pictures[3].Items); // ordinary bullet survives group retirement
            Assert.Equal(new[] {
                "ray:1", "bullet:100:1", "ray:1", "bullet:101:1",
                "ray:2", "bullet:102:1", "ray:0", "bullet:103:0"
            }, _order.ToArray());
            AssertNoRejections();
        }

        [Fact]
        public async Task ChainEventsAreConsumedEvenWhenAnIntermediateFrameHasNoOrdinarySnapshot()
        {
            string first = Wire(Ordinary(100), null, Chain(1, 100, Group() + ";" + Birth(1, 2)));
            string eventOnly = Wire(null, null,
                Chain(2, 101, Group(1) + ";" + Birth(2, 10, 20, "0.5", "0.8660254037844386") + ";D,1,1"));
            string last = Wire(Ordinary(102), null, Chain(3, 102, Group(2)));
            await SendBatch("event-only", first, eventOnly, last);
            var pictures = _bullets.ToArray();
            Assert.Equal(2, pictures.Length);
            Assert.Equal(110f, pictures[1].Items[1].X);
            Assert.Equal(225f, pictures[1].Items[1].Y);
            AssertNoRejections();
        }

        [Fact]
        public async Task SceneResetDropsLateSnapshotsAndAcceptsFreshEpochsThroughTheSameSocket()
        {
            await SendBatch("before-reset", Initial());
            string stale = Wire(Ordinary(101), Ray(2, 101, Config() + ";" + Spawn(id: 2, born: 101, end: 900)),
                Chain(2, 101, Group(1)));
            string fresh = Wire(Ordinary(200, epoch: 4),
                Ray(1, 200, Config() + ";" + Spawn(born: 200, end: 450), epoch: 6),
                Chain(1, 200, Group() + ";" + Birth(2, 77), epoch: 9));
            await SendBatch("after-reset", "R", stale, fresh);
            var pictures = _bullets.ToArray();
            Assert.Equal(new[] { 100, 200 }, pictures.Select(x => x.Frame));
            Assert.Equal(177f, pictures[1].Items[1].X);
            var rays = _rays.ToArray();
            Assert.Equal(2, rays.Length);
            Assert.Equal(450f, rays[1].Data[2]);
            Assert.Equal(1, Volatile.Read(ref _bulletCleared));
            Assert.Single(_readyGenerations); // an R scene transition is not a socket reconnect
            AssertNoRejections();
        }

        [Fact]
        public async Task DuplicateSnapshotsDoNotRevokeOwnershipAndMalformedSectionsStayIsolated()
        {
            string initial = Initial();
            await SendBatch("duplicates", initial, initial);
            Assert.Single(_bullets); Assert.Single(_rays);
            AssertNoRejections();
            // Invalid F7 still permits the ordered F8 and valid F5 sections to finish.
            string badRay = Wire(Ordinary(101), "malformed ray",
                Chain(2, 101, Group(1)));
            // Invalid F5 must not suppress a newly configured ray or lose a chain tick.
            string badBullet = Wire("malformed ordinary",
                Ray(1, 102, Config() + ";" + Spawn(born: 102, end: 500), epoch: 6),
                Chain(3, 102, Group(2)));
            string resume = Wire(Ordinary(103), Ray(2, 103, epoch: 6), Chain(4, 103, Group(3)));
            await SendBatch("recover", badRay, badBullet, resume);
            Assert.Equal(1, Volatile.Read(ref _rayRejected));
            Assert.Equal(1, Volatile.Read(ref _bulletRejected));
            Assert.Equal(0, Volatile.Read(ref _chainRejected));
            Assert.Equal(new[] { 100, 101, 103 }, _bullets.Select(x => x.Frame));
            Assert.Equal(221f, _bullets.Last().Items[1].Y);
            Assert.Equal(500f, _rays.Last().Data[2]);
        }

        [Fact]
        public async Task SharedBulletCapabilityCycleRejectsQueuedNativeF5AndF8UntilTheirNewEpochs()
        {
            await SendBatch("before-chain-cap-cycle", Initial());
            // Production controller invokes this exact callback after withdrawing
            // the shared ordinary/chain capability; no engine is replaced in the test.
            _frameTask.InvalidateChainVisuals();
            _frameTask.InvalidateChainVisuals();
            string oldEpoch = Wire(Ordinary(101), Ray(2, 101), Chain(2, 101, Group(1)));
            string regrantBeforeF8 = Wire(Ordinary(102, epoch: 5), null, null);
            string newEpoch = Wire(Ordinary(103, epoch: 5), Ray(3, 103),
                Chain(1, 103, Group() + ";" + Birth(2, 77), epoch: 9));
            await SendBatch("after-chain-cap-cycle", oldEpoch, regrantBeforeF8, newEpoch);
            var pictures = _bullets.ToArray();
            Assert.Equal(new[] { 100, 102, 103 }, pictures.Select(x => x.Frame));
            Assert.Equal(new[] { 1, 0, 1 }, pictures.Select(x => x.ChainCount));
            Assert.All(pictures, picture => Assert.Equal(1, picture.NormalCount));
            Assert.Equal(177f, pictures[2].Items[1].X);
            Assert.All(_rays, ray => Assert.Equal(1, ray.Count));
            AssertNoRejections();
        }

        [Fact]
        public async Task ReplacedSocketCannotDispatchABlockedOldFPacketIntoTheNewGeneration()
        {
            await SendBatch("initial-generation", Initial());
            int previousGeneration = _server.CurrentGeneration;
            using var releaseOld = new ManualResetEventSlim(false);
            var entered = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            int blocked = 0;
            _server.BeforeMessageTransitionForTests = generation => {
                if (generation != previousGeneration || Interlocked.CompareExchange(ref blocked, 1, 0) != 0) return;
                entered.TrySetResult(true);
                releaseOld.Wait(TimeSpan.FromSeconds(5));
            };
            TcpClient previous = _client;
            try
            {
                string stale = Wire(Ordinary(900, epoch: 90),
                    Ray(1, 900, Config() + ";" + Spawn(born: 900, end: 900), epoch: 90),
                    Chain(1, 900, Group() + ";" + Birth(9, 900), epoch: 90));
                await Write(previous, stale + "\0");
                await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
                var replacement = new TcpClient(AddressFamily.InterNetwork) { NoDelay = true };
                await replacement.ConnectAsync(IPAddress.Loopback, _port);
                _client = replacement;
                await Eventually(() => _server.CurrentGeneration > previousGeneration && _server.HasClient);
                int nextGeneration = _server.CurrentGeneration;
                string fresh = Wire(Ordinary(1, epoch: 1),
                    Ray(1, 1, Config() + ";" + Spawn(born: 1, end: 300), epoch: 1),
                    Chain(1, 1, Group() + ";" + Birth(1, 33), epoch: 1));
                await SendBatch("replacement", fresh);
                while (_bulletReady.Wait(0)) { }
                releaseOld.Set();
                Assert.False(await _bulletReady.WaitAsync(TimeSpan.FromMilliseconds(250)),
                    "retired ReadLoop dispatched its blocked projectile frame");
                Assert.Equal(new[] { 100, 1 }, _bullets.Select(x => x.Frame));
                Assert.Equal(133f, _bullets.Last().Items[1].X);
                Assert.Equal(300f, _rays.Last().Data[2]);
                Assert.Equal(new[] { previousGeneration, nextGeneration }, _readyGenerations.ToArray());
                Assert.Equal(new[] { previousGeneration }, _disconnectedGenerations.ToArray());
                AssertNoRejections();
            }
            finally
            {
                releaseOld.Set();
                _server.BeforeMessageTransitionForTests = null;
                previous.Dispose();
            }
        }

        private void AssertNoRejections()
        {
            Assert.Equal(0, Volatile.Read(ref _rayRejected));
            Assert.Equal(0, Volatile.Read(ref _chainRejected));
            Assert.Equal(0, Volatile.Read(ref _bulletRejected));
        }
        private async Task SendBatch(string tag, params string[] messages)
        {
            await Write(_client, string.Join('\0', messages) + "\0" + Barrier(tag) + "\0");
            await WaitBarrier(tag);
        }
        private async Task WaitBarrier(string expected)
        {
            Assert.True(await _barrierReady.WaitAsync(TimeSpan.FromSeconds(5)), "ReadLoop did not reach " + expected);
            Assert.True(_barriers.TryDequeue(out string actual));
            Assert.Equal(expected, actual);
        }
        private static async Task Write(TcpClient client, string bytes) =>
            await client.GetStream().WriteAsync(Encoding.UTF8.GetBytes(bytes));
        private static async Task Eventually(Func<bool> predicate)
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            while (!predicate()) await Task.Delay(5, timeout.Token);
        }
        private static string Barrier(string tag) => "{\"task\":\"projectile_test_barrier\",\"tag\":\"" + tag + "\"}";
        private static string Initial() => Wire(Ordinary(100),
            Ray(1, 100, Config() + ";" + Spawn(born: 100)), Chain(1, 100, Group() + ";" + Birth(1, 2)));
        private static string Wire(string ordinary, string ray, string chain, string ui = null) =>
            "F12|34|1.5\x01\x02" + "30|12|0|1" + (ui == null ? "" : "\x03" + ui) + "\x04"
            + (ordinary == null ? "" : "\x05" + ordinary)
            + (ray == null ? "" : "\x07" + ray) + (chain == null ? "" : "\x08" + chain);
        private static string Ordinary(int tick, int epoch = 3) => $"{epoch}|{tick}|1|0|0|1;0,10,20,0,100,100,100";
        private static string Group(int step = 0) => $"G,1,0,{step},100,200,0,100,100,100,1,10,0";
        private static string Birth(int id, int x, int y = 3, string sin = "0.6", string cos = "0.8") =>
            $"B,1,{id},{x},{y},{sin},{cos},20";
        private static string Chain(int sequence, int tick, string body, int epoch = 8) =>
            $"1|{epoch}|{sequence}|{tick}" + (body.Length == 0 ? "" : ";" + body);
        private static string Ray(int sequence, int tick, string body = "", int epoch = 5) =>
            $"{epoch}|{sequence}|{tick}|0;o,0,0" + (body.Length == 0 ? "" : ";" + body);
        private static string Spawn(int id = 1, int born = 100, int end = 200) =>
            $"s,{id},1,{born},0,100,50,{end},50,0,0,1,0,123,0,1,500,1,5,2,-,-,0";
        private static string Config()
        {
            float[] values = Enumerable.Repeat(1f, RayVisualCatalog.FieldNames.Length).ToArray();
            values[0] = 0xFF8800; values[1] = 0xFFDD88; values[2] = 4; values[3] = 20;
            values[4] = 3; values[5] = 0; values[6] = 70; values[7] = 100;
            values[10] = 35; values[11] = 40; values[14] = .7f; values[20] = 60;
            values[24] = 15; values[25] = 50; values[37] = 1; values[41] = 0x7A6F66;
            values[42] = 0xFFB347; values[49] = 0x34302A;
            return "c,1,0," + string.Join(',', values.Select(x => x.ToString(CultureInfo.InvariantCulture))) + ",-";
        }
        private static int FreePort()
        {
            var probe = new TcpListener(IPAddress.Loopback, 0);
            probe.Start();
            int port = ((IPEndPoint)probe.LocalEndpoint).Port;
            probe.Stop();
            return port;
        }
        private static string ProjectRoot()
        {
            for (var path = new DirectoryInfo(AppContext.BaseDirectory); path != null; path = path.Parent)
                if (File.Exists(Path.Combine(path.FullName, BulletVisualCatalog.RelativePath))) return path.FullName;
            throw new DirectoryNotFoundException(BulletVisualCatalog.RelativePath);
        }
    }
}
