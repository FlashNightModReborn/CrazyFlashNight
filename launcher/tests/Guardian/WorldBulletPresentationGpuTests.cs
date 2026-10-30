using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class WorldBulletPresentationGpuTests
    {
        [SharedWorldGpuFact]
        public void ControlledSkewKeepsWorldAdvancingAndProjectilesFrameAligned()
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            string candidate = Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"));
            string module = Path.Combine(candidate, "runtime", NativeCompositorSession.ModuleName);
            string manifest = Path.Combine(candidate, "runtime", "cf7-runtime-manifest.tsv");
            string[] row = File.ReadLines(manifest).Select(line => line.Split('\t')).Single(parts =>
                parts.Length == 4 && parts[0] == "file" && parts[1] == "runtime/" + NativeCompositorSession.ModuleName);
            string moduleHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module)));
            Assert.Equal(long.Parse(row[2]), new FileInfo(module).Length);
            Assert.Equal(row[3], moduleHash, true);
            using var metadata = JsonDocument.Parse(File.ReadAllText(Path.Combine(candidate, "runtime-build-metadata.v2.json")));
            string identity = metadata.RootElement.GetProperty("buildIdentityHash").GetString();
            string closure = metadata.RootElement.GetProperty("payloadClosureHash").GetString();
            Assert.Equal(64, identity.Length); Assert.Equal(64, closure.Length);
            string core = Path.Combine(candidate, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.dll");
            string coreHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(core)));
            string host = typeof(FrameTask).Assembly.Location;
            string hostHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(host)));
            Assert.Equal(104, Marshal.SizeOf<NativeCompositorSession.BulletSyncStats>());
            IntPtr loaded = NativeLibrary.Load(module);
            Exception failure = null;
            string output = null;
            var thread = new Thread(() =>
            {
                try
                {
                    using var fixture = new Fixture(candidate, module, moduleHash, coreHash, identity, closure, host, hostHash);
                    output = fixture.Output;
                    fixture.Execute();
                }
                catch (Exception error) { failure = error; }
            }) { IsBackground = true };
            try
            {
                thread.SetApartmentState(ApartmentState.STA);
                thread.Start();
                Assert.True(thread.Join(TimeSpan.FromSeconds(150)), "Bullet presentation GPU fixture timed out.");
                if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
                Assert.False(string.IsNullOrEmpty(output));
                Console.WriteLine("bullet-sync-evidence=" + output);
            }
            finally { NativeLibrary.Free(loaded); }
        }

        private sealed class Fixture : IDisposable
        {
            private const int W = 1024, H = 576;
            private readonly Stopwatch clock = Stopwatch.StartNew();
            private readonly JsonSerializerOptions json = new() { WriteIndented = true, IncludeFields = true };
            private readonly ConcurrentQueue<object> events = new();
            private readonly ConcurrentQueue<Sample> samples = new();
            private readonly ConcurrentQueue<string> failures = new();
            private readonly ConcurrentQueue<string> logs = new();
            private readonly List<CaseResult> cases = new();
            private readonly object pixelLock = new();
            private readonly string candidate, module, moduleHash, coreHash, identity, closure, host, hostHash;
            private PixelFrame latest;
            private string currentCase = "startup";
            private NativeCompositorSession native;
            private FrameTask consumer;
            private NetworkStream stream;
            private SourceForm source;
            private int lastEpoch = -1, lastTick = -1, rejects, epoch;
            private int lastExpectedCount, consumedPackets;
            private bool stopping;
            private NativeCompositorSession.BulletSyncStats finalSync;
            private static readonly string[] Styles = { "plain", "enhanced", "pierce", "secondary-pierce", "caseless-pierce", "pierce-chain" };
            private readonly ConcurrentDictionary<int, Scenario> scenarios = new();
            private double Now => clock.Elapsed.TotalMilliseconds;
            internal string Output { get; }

            internal Fixture(string candidate, string module, string moduleHash, string coreHash,
                string identity, string closure, string host, string hostHash)
            {
                this.candidate = candidate; this.module = module; this.moduleHash = moduleHash;
                this.coreHash = coreHash; this.identity = identity; this.closure = closure;
                this.host = host; this.hostHash = hostHash;
                string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
                Output = Path.Combine(root, "tmp", "bullet-visual-sync", "gpu-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff"));
                Directory.CreateDirectory(Output); Directory.CreateDirectory(Path.Combine(Output, "captures"));
            }

            internal void Execute()
            {
                CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;
                LogManager.SetSink(s => logs.Enqueue(s));
                Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
                using var source = new SourceForm(this); this.source = source;
                using var target = new QuietForm { Text = "CF7 bullet sync output", Location = new Point(48, 48) };
                int exit = 1;
                source.Shown += async (_, _) =>
                {
                    target.Show();
                    SetWindowPos(source.Handle, new IntPtr(1), 0, 0, 0, 0, 0x0013);
                    SetWindowPos(target.Handle, new IntPtr(1), 0, 0, 0, 0, 0x0013);
                    try { await Run(target); exit = 0; }
                    catch (Exception ex) { failures.Enqueue(ex.ToString()); Console.Error.WriteLine(ex); }
                    finally
                    {
                        stopping = true;
                        WriteJson("cases.json", cases);
                        File.WriteAllLines(Path.Combine(Output, "samples.jsonl"), samples.Select(s => JsonSerializer.Serialize(s)));
                        File.WriteAllLines(Path.Combine(Output, "events.jsonl"), events.Select(e => JsonSerializer.Serialize(e)));
                        File.WriteAllLines(Path.Combine(Output, "core-log.txt"), logs);
                        WriteJson("failures.json", failures.ToArray());
                        target.Close(); source.Close();
                    }
                };
                try { Application.Run(source); }
                finally { LogManager.SetSink(null); }
                if (exit != 0 || !failures.IsEmpty)
                    throw new InvalidOperationException("Bullet GPU fixture failed: " + string.Join(" | ", failures));
            }

            private async Task Run(Form target)
            {
                string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
                var catalog = BulletVisualCatalog.Load(root);
                native = new NativeCompositorSession(module, source.Handle, (uint)Environment.ProcessId, target.Handle);
                using var session = native;
                session.Mode(0);
                await Wait(() => session.Read().Presented > 0, "initial WGC frame", 15000);
                var size = session.ReadCaptureSize();
                Require(size.Width == W && size.Height == H, $"capture size {size} differs from fixture size");
                session.Viewport(new Rectangle(0, 0, W, H), 0);
                session.Matrix(new float[] { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 });
                session.Postprocess(false, 0, false);
                session.BulletStyles(catalog);
                await Wait(() => session.BulletResourcesReady, "bullet resources", 15000);
                consumer = new FrameTask(null, null);
                consumer.ConfigureBulletVisualShadow(catalog); consumer.ConfigureProjectileVisuals(catalog);
                consumer.BulletVisualRejected = () => { Interlocked.Increment(ref rejects); failures.Enqueue("F5 rejected"); };
                consumer.ChainVisualRejected = () => { Interlocked.Increment(ref rejects); failures.Enqueue("F8 rejected"); };
                consumer.BulletVisualObserved = (frame, x, y, scale) =>
                {
                    double at = Now;
                    var actual = frame.Instances.Where(i => i.Y > 200).Select(i => new PointF(i.X, i.Y)).OrderBy(i => i.X).ToArray();
                    if (scenarios.TryGetValue(frame.Epoch, out var scenario))
                    {
                        var expected = Expected(scenario.Chain, frame.Frame);
                        if (actual.Length != expected.Length || actual.Where((p, i) => i < expected.Length &&
                            (Math.Abs(p.X - expected[i].X) > .01 || Math.Abs(p.Y - expected[i].Y) > .01)).Any())
                            failures.Enqueue($"geometry mismatch epoch={frame.Epoch} tick={frame.Frame}");
                    }
                    session.BulletFrame(frame, x, y, scale);
                    Interlocked.Increment(ref consumedPackets);
                    events.Enqueue(new { kind = "consumed", ms = at, epoch = frame.Epoch, tick = frame.Frame,
                        chainEpoch = frame.ChainEpoch, chainTick = frame.ChainFrame,
                        normal = frame.NormalCount, chain = frame.ChainCount,
                        positions = actual.Select(p => new[] { p.X, p.Y }).ToArray(), camera = new[] { x, y, scale } });
                    Volatile.Write(ref lastExpectedCount, actual.Length);
                    Volatile.Write(ref lastTick, frame.Frame); Volatile.Write(ref lastEpoch, frame.Epoch);
                };
                using var server = new XmlSocketServer(new MessageRouter(), AllowLoopbackXmlSocketPeerAuthority.Instance);
                server.SetFrameHandler(consumer);
                server.OnClientDisconnectedForGeneration += consumer.ResetProjectileVisualsForGeneration;
                server.OnClientDisconnectedForGeneration += consumer.ResetBulletVisualShadowForGeneration;
                var portPicker = new TcpListener(IPAddress.Loopback, 0); portPicker.Start();
                int port = ((IPEndPoint)portPicker.LocalEndpoint).Port; portPicker.Stop();
                Require(server.Start(port), "isolated loopback listener start");
                using var client = new TcpClient(AddressFamily.InterNetwork) { NoDelay = true };
                await client.ConnectAsync(IPAddress.Loopback, port); stream = client.GetStream();
                await Wait(() => server.HasClient, "own socket accepted", 5000);
                var sampling = Task.Run(SampleLoop);
                try
                {
                    WriteJson("environment.json", new
                    {
                        utc = DateTimeOffset.UtcNow, process = Environment.ProcessId, port, candidate, native = module,
                        nativeSha256 = moduleHash, candidateCoreSha256 = coreHash, buildIdentityHash = identity,
                        payloadClosureHash = closure, testHost = host, testHostSha256 = hostHash,
                        hostRole = "Current-source test-seams FrameTask and XML socket; exact candidate native module and manifest.",
                        capture = new[] { size.Width, size.Height }, adapter = session.Read().Adapter,
                        scope = "Synthetic owned source -> WGC; real localhost TCP -> production FrameTask -> candidate native D3D compositor.",
                        readback = "Final composite GPU readback before Present. Not physical scanout, AS2 execution, gym E2E or performance benchmark."
                    });
                    for (int i = 0; i < 6; i++) await Staged(i == 5 ? 5 : i);
                    foreach (int fps in new[] { 30, 15, 10 })
                        foreach (int delayFrames in new[] { 0, 1 })
                            for (int style = 0; style < 6; style++) await Dynamic(style, fps, delayFrames);
                    await Burst(2); await Burst(5);
                    await WireAheadLiveness();
                    await EmptySnapshotLiveness();
                    Require(rejects == 0, "no rejected F5/F8 packets");
                    Require(failures.IsEmpty, "all geometry and pixel assertions pass");
                    finalSync = session.ReadBulletSync();
                    WriteJson("final-stats.json", new
                    {
                        cases = cases.Count, rejects, received = session.Read().Received,
                        presented = session.Read().Presented, adapter = session.Read().Adapter,
                        sync = finalSync, errors = failures.ToArray()
                    });
                }
                finally { stopping = true; await sampling; consumer.Stop(); }
            }

            private async Task<Scenario> Begin(int style, string label, int fps = 0, int delay = 0)
            {
                int current = ++epoch;
                var s = new Scenario(current, style, style == 5, $"{current:D2}-{Styles[style]}-{label}", fps, delay);
                scenarios[current] = s; currentCase = s.Id;
                source.Set(s, 0); GdiFlush(); Send(s, 0);
                var initialSource = await SourceWait(p => p.Scene == current && p.Tick == 0, "raw initial source");
                Save(initialSource, s.Id + "-source-initial");
                events.Enqueue(new { kind = "sync-debug", ms = Now, sync = CurrentSync() });
                await PixelWait(p => p.Scene == current && p.Tick == 0 && p.BulletEpoch == current % 16 && p.BulletTick == 0,
                    "aligned case start");
                await Sync(s, 0);
                events.Enqueue(new { kind = "case-start", ms = Now, id = s.Id, epoch = current, style, fps, delay });
                return s;
            }

            private async Task Staged(int style)
            {
                var s = await Begin(style, "staged");
                for (int tick = 1; tick <= 3; tick++) { source.Set(s, tick); GdiFlush(); Send(s, tick); await Consumed(s, tick); }
                var before = await PixelWait(p => Aligned(p, s, 3), "before hit aligned");
                string a = Save(before, s.Id + "-before");
                double sourceChange = Now; source.Set(s, 4); GdiFlush();
                await SourceWait(p => p.Scene == s.Epoch && p.Tick == 4 && p.Hit, "raw source reached tick 4");
                var mismatch = await PixelWait(p => p.Scene==s.Epoch && p.Tick==4 && p.Hit && p.BulletTick<0,
                    "source 4 advances while an unmatched projectile is suppressed");
                var mismatchSync = await Sync(s, 3);
                string b = Save(mismatch, s.Id + "-mismatch");
                await Task.Delay(250);
                var sustained = await PixelWait(p => p.Scene==s.Epoch && p.Tick==4 && p.Hit && p.BulletTick<0,
                    "missing packet never rewinds or freezes the world");
                string c = Save(sustained, s.Id + "-held");
                Require(CountMagicPixels(sustained) == 0, "source tag is hidden in final output");
                double released = Now; Send(s, 4);
                var recovered = await PixelWait(p => Aligned(p, s, 4) && p.Hit, "recovered aligned hit");
                var recoveredSync = await Sync(s, 4);
                string d = Save(recovered, s.Id + "-recovered");
                Send(s, 5);
                var ahead = await PixelWait(p => Aligned(p, s, 4) && p.Hit, "newer bullet waits for source 5");
                var aheadSync = await Sync(s, 5);
                string e = Save(ahead, s.Id + "-bullet-ahead");
                source.Set(s, 5); GdiFlush();
                for (int tick = 6; tick <= 7; tick++) { source.Set(s, tick); GdiFlush(); Send(s, tick); await Consumed(s, tick); }
                var clear = await PixelWait(p => Aligned(p, s, 7), "cleared projectile");
                await Sync(s, 7);
                Require(Volatile.Read(ref lastExpectedCount) == 0, "all projectiles cleared");
                Require(CountBulletPixels(clear) == 0, "projectiles absent in final composite after clear");
                Require(CountMagicPixels(clear) == 0, "source tag remains hidden after clear");
                cases.Add(new CaseResult(s, "staged", true, new
                {
                    sourceChange, firstAdvancedMs = mismatch.Ms, lastAdvancedMs = sustained.Ms,
                    observedSuppressionSpanMs = sustained.Ms - mismatch.Ms, released, recoveredMs = recovered.Ms,
                    releaseToRecoveryMs = recovered.Ms - released, captures = new[] { a, b, c, d, e },
                    clearPixels = CountBulletPixels(clear), reverseSkew = true,
                    mismatchSync, recoveredSync, aheadSync
                }));
                WriteJson("cases.json", cases);
            }

            private async Task Dynamic(int style, int fps, int delayFrames)
            {
                var s = await Begin(style, $"{fps}fps-delay{delayFrames}", fps, delayFrames);
                double interval = 1000.0 / fps, start = Now + 30, delay = delayFrames * interval;
                int world = 1, wire = 1;
                while (world <= 7 || wire <= 7)
                {
                    double at = Now;
                    if (world <= 7 && at >= start + world * interval) { source.Set(s, world++); GdiFlush(); }
                    if (wire <= 7 && at >= start + wire * interval + delay) Send(s, wire++);
                    await Task.Delay(1);
                }
                var done = await PixelWait(p => Aligned(p, s, 7), "dynamic final alignment");
                await Sync(s, 7);
                await Task.Delay(40);
                var rows = samples.Where(p => p.Case == s.Id && p.Ms >= start && p.Ms <= done.Ms &&
                    p.Scene == s.Epoch && p.BulletEpoch == s.Epoch % 16 && p.BulletTick >= 0).ToArray();
                var early = rows.Where(p => p.Hit && p.Tick >= 4 && p.BulletTick < 4).ToArray();
                Require(rows.Length > 0, "dynamic same-scene samples exist");
                Require(rows.All(p => p.Tick == p.BulletTick), "every valid same-scene composite is frame aligned");
                var skew = rows.Select(p => p.Tick - p.BulletTick).ToArray();
                cases.Add(new CaseResult(s, "dynamic", true, new
                {
                    start, end = done.Ms, samples = rows.Length,
                    worldAhead = skew.Count(n => n > 0), aligned = skew.Count(n => n == 0),
                    bulletAhead = skew.Count(n => n < 0), maxWorldLead = skew.Length > 0 ? skew.Max() : 0,
                    maxBulletLead = skew.Length > 0 ? -skew.Min() : 0, hitBeforeBulletSamples = early.Length,
                    firstHitBeforeBulletMs = early.Length > 0 ? (double?)early[0].Ms : null,
                    lastHitBeforeBulletMs = early.Length > 0 ? (double?)early[^1].Ms : null,
                    hitMismatchObservedSpanMs = early.Length > 1 ? early[^1].Ms - early[0].Ms : 0,
                    clearPixels = CountBulletPixels(done)
                }));
                Require(CountBulletPixels(done) == 0, "dynamic cleanup image");
                WriteJson("cases.json", cases);
            }

            private async Task Burst(int style)
            {
                var s = await Begin(style, "250ms-burst", 10, 0);
                for (int tick = 1; tick <= 3; tick++) { source.Set(s, tick); GdiFlush(); Send(s, tick); await Consumed(s, tick); }
                await PixelWait(p => Aligned(p, s, 3), "burst before");
                double start = Now;
                for (int tick = 4; tick <= 6; tick++) { source.Set(s, tick); GdiFlush(); await Task.Delay(tick == 6 ? 50 : 100); }
                await SourceWait(p => p.Scene == s.Epoch && p.Tick == 6 && p.Hit, "raw source reached burst tick 6");
                var mismatch = await PixelWait(p => p.Scene==s.Epoch && p.Tick==6 && p.BulletTick<0,
                    "burst advances world 6 without drawing packet 3");
                var mismatchSync = await Sync(s, 3);
                string image = Save(mismatch, s.Id + "-mismatch");
                for (int tick = 4; tick <= 7; tick++) Send(s, tick);
                source.Set(s, 7); GdiFlush(); await Consumed(s, 7);
                var done = await PixelWait(p => Aligned(p, s, 7), "burst recovery");
                var recoveredSync = await Sync(s, 7);
                Require(CountBulletPixels(done) == 0, "burst cleanup");
                cases.Add(new CaseResult(s, "burst", true, new
                {
                    start, advancedAt = mismatch.Ms, worldTick = 6, pendingPacketTick = 3, delta = 3,
                    recoveredMs = done.Ms, consumedTicks = new[] { 4, 5, 6, 7 }, capture = image,
                    clearPixels = CountBulletPixels(done), mismatchSync, recoveredSync
                }));
            }

            private async Task WireAheadLiveness()
            {
                var s=await Begin(0,"wire-ahead-liveness",30,-1);
                var latencies=new List<double>();
                for(int packet=1;packet<=7;packet++) {
                    Send(s,packet);await Consumed(s,packet);
                    double changed=Now;source.Set(s,packet-1);GdiFlush();
                    var shown=await PixelWait(p=>Aligned(p,s,packet-1),"history matches source despite newer socket packet");
                    latencies.Add(shown.Ms-changed);
                    Require(shown.Ms-changed<500,"wire-ahead world advances within bounded observation window");
                }
                source.Set(s,7);GdiFlush();
                await PixelWait(p=>Aligned(p,s,7),"wire-ahead final clear");
                cases.Add(new CaseResult(s,"wire-ahead-liveness",true,new {latencies,observedFrames=7}));
            }

            private async Task EmptySnapshotLiveness()
            {
                var s=new Scenario(++epoch,0,false,"empty-snapshot-liveness",30,-1);
                currentCase=s.Id;
                var latencies=new List<double>();
                for(int tick=0;tick<16;tick++) {
                    var empty=BulletVisualFrame.Compose(s.Epoch,tick+1,Array.Empty<BulletVisualInstance>(),
                        Array.Empty<BulletVisualInstance>(),IndependentChainEpoch(s),tick+1);
                    native.BulletFrame(empty,0,0,1);
                    double changed=Now;source.Set(s,tick);GdiFlush();
                    var shown=await PixelWait(p=>p.Scene==s.Epoch && p.Tick==tick && p.BulletTick<0,
                        "empty ahead packet cannot freeze world");
                    latencies.Add(shown.Ms-changed);
                    Require(shown.Ms-changed<500,"empty world advances within bounded observation window");
                    Require(CountBulletPixels(shown)==0 && CountMagicPixels(shown)==0,"no stale projectile or exposed source tag");
                }
                cases.Add(new CaseResult(s,"empty-snapshot-liveness",true,new {latencies,observedFrames=16,bulletCount=0}));
            }

            private static int IndependentChainEpoch(Scenario scenario) => scenario.Epoch + 17;
            private NativeCompositorSession.BulletSyncStats CurrentSync() => native.ReadBulletSync();
            private async Task<NativeCompositorSession.BulletSyncStats> Sync(Scenario s, int tick)
            {
                NativeCompositorSession.BulletSyncStats value = default;
                await Wait(() =>
                {
                    value = CurrentSync();
                    return value.PresentedVersion > 0 && value.PresentedOrdinaryEpoch == s.Epoch &&
                        value.PresentedOrdinaryFrame == tick && value.PresentedChainEpoch == IndependentChainEpoch(s) &&
                        value.PresentedChainFrame == tick;
                }, $"native presented identity {s.Epoch}/{tick}");
                Assert.True(value.SubmittedVersion >= value.PresentedVersion);
                Assert.True(value.PresentedQpcMs >= value.PresentedSubmittedQpcMs);
                return value;
            }

            private PointF[] Expected(bool chain, int tick)
            {
                if (tick >= 7) return Array.Empty<PointF>();
                if (!chain) return new[] { new PointF(80 + 120 * tick, 300) };
                var p = new List<PointF>();
                if (tick < 5) p.Add(new PointF(80 + 120 * tick, 300));
                p.Add(new PointF(-40 + 120 * tick, 300)); p.Add(new PointF(-160 + 120 * tick, 300));
                if (tick >= 6) p.Add(new PointF(-280 + 120 * tick, 300));
                return p.OrderBy(i => i.X).ToArray();
            }

            private string Packet(Scenario s, int tick)
            {
                var items = new List<string> { $"0,{48 + tick * 56},90,0,80,900,100",
                    $"0,{48 + s.Epoch % 16 * 48},130,0,80,900,100" };
                if (!s.Chain && tick < 7) items.Add($"{s.Style},{80 + tick * 120},300,0,100,100,100");
                string f5 = $"{s.Epoch}|{tick}|{items.Count}|0|0|1;" + string.Join(";", items);
                string f8 = $"1|{IndependentChainEpoch(s)}|{tick + 1}|{tick}";
                if (s.Chain && tick < 7)
                {
                    f8 += $";G,1,5,{tick},80,300,0,100,100,100,1,120,1";
                    if (tick == 0) f8 += ";B,1,1,0,0,0,1,0;B,1,2,-120,0,0,1,0;B,1,3,-240,0,0,1,0";
                    if (tick == 5) f8 += ";D,1,1";
                    if (tick == 6) f8 += ";B,1,4,360,0,0,1,0";
                }
                return "F0|0|1\u0001\u0005" + f5 + "\u0008" + f8 + "\0";
            }

            private void Send(Scenario s, int tick)
            {
                string packet = Packet(s, tick); byte[] bytes = Encoding.UTF8.GetBytes(packet);
                events.Enqueue(new { kind = "send", ms = Now, epoch = s.Epoch, tick, packet });
                stream.Write(bytes, 0, bytes.Length);
            }
            private Task Consumed(Scenario s, int tick) => Wait(() =>
                Volatile.Read(ref lastEpoch) == s.Epoch && Volatile.Read(ref lastTick) >= tick, $"packet consumed {s.Epoch}/{tick}");
            private static bool Aligned(PixelFrame p, Scenario s, int tick) =>
                p.Scene == s.Epoch && p.Tick == tick && p.BulletEpoch == s.Epoch % 16 && p.BulletTick == tick;

            private async Task Wait(Func<bool> check, string label, int timeout = 5000)
            {
                double until = Now + timeout;
                while (Now < until) { if (check()) return; await Task.Delay(5); }
                throw new InvalidOperationException("Timeout: " + label);
            }
            private async Task<PixelFrame> PixelWait(Func<PixelFrame, bool> check, string label)
            {
                PixelFrame result = null;
                try { await Wait(() => { lock (pixelLock) result = latest; return result != null && check(result); }, label); }
                catch { if (result != null) Save(result, "failure-" + currentCase); throw; }
                return result;
            }

            private async Task<PixelFrame> SourceWait(Func<PixelFrame, bool> check, string label)
            {
                byte[] buffer = new byte[W * H * 4];
                PixelFrame result = null;
                await Wait(() =>
                {
                    int code = native.GrabLatestFrame(buffer, out int w, out int h);
                    if (code != NativeCompositorSession.GrabOk || w != W || h != H) return false;
                    result = Decode(buffer, Now);
                    return check(result);
                }, label);
                return result;
            }

            private void SampleLoop()
            {
                byte[] buffer = new byte[W * H * 4];
                while (!Volatile.Read(ref stopping))
                {
                    double before = Now;
                    int code = native.GrabCompositeFrame(buffer, out int w, out int h);
                    if (code == NativeCompositorSession.GrabOk && w == W && h == H)
                    {
                        double after = Now; byte[] bytes = (byte[])buffer.Clone();
                        var p = Decode(bytes, after); var stats = native.Read(); var sync = native.ReadBulletSync();
                        samples.Enqueue(new Sample(currentCase, before, after, after - before, p.Scene, p.Tick,
                            p.BulletEpoch, p.BulletTick, p.Hit, stats.Presented, stats.Received, sync));
                        lock (pixelLock) latest = p;
                    }
                    else if (code != NativeCompositorSession.GrabBusy && code != NativeCompositorSession.GrabNoFrame)
                        events.Enqueue(new { kind = "grab", ms = Now, code, w, h });
                    Thread.Sleep(8);
                }
            }

            private static PixelFrame Decode(byte[] b, double ms)
            {
                int Bits(int y)
                {
                    int v = 0;
                    for (int i = 0; i < 8; i++) { int at = ((y + 6) * W + 20 + i * 18 + 6) * 4;
                        if (b[at + 2] > 200 && b[at + 1] > 200) v |= 1 << i; }
                    return v;
                }
                int Marker(int y, int step, int count)
                {
                    int result = -1;
                    for (int i = 0; i < count; i++) { int at = (y * W + 48 + i * step + 17) * 4;
                        if (b[at + 2] > 210 && b[at + 1] > 210 && b[at] > 140) { if (result >= 0) return -2; result = i; } }
                    return result;
                }
                int hit = (26 * W + 1000) * 4;
                return new PixelFrame(ms, Bits(20), Bits(42), Marker(130, 48, 16), Marker(90, 56, 8),
                    b[hit + 2] > 180 && b[hit + 1] < 120, b);
            }

            private static int CountBulletPixels(PixelFrame p)
            {
                int count = 0;
                for (int y = 287; y < 310; y++) for (int x = 20; x < 1000; x++)
                { int at = (y * W + x) * 4; if (p.Bytes[at + 2] > 170 && p.Bytes[at + 1] > 170 && p.Bytes[at] > 90) count++; }
                return count;
            }
            private static int CountMagicPixels(PixelFrame p)
            {
                int count = 0;
                for (int y = 560; y < 576; y++) for (int x = 0; x < 16; x++)
                {
                    int at = (y * W + x) * 4;
                    if (Math.Abs(p.Bytes[at + 2] - 0x13) <= 1 && Math.Abs(p.Bytes[at + 1] - 0x57) <= 1
                        && Math.Abs(p.Bytes[at] - 0x9B) <= 1) count++;
                }
                return count;
            }
            private string Save(PixelFrame p, string name)
            {
                string relative = "captures/" + name + ".png", path = Path.Combine(Output, relative);
                using var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb);
                var data = bmp.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.WriteOnly, bmp.PixelFormat);
                try { Marshal.Copy(p.Bytes, 0, data.Scan0, p.Bytes.Length); } finally { bmp.UnlockBits(data); }
                bmp.Save(path, ImageFormat.Png);
                events.Enqueue(new { kind = "capture", ms = p.Ms, path = relative, scene = p.Scene,
                    sourceTick = p.Tick, bulletEpoch = p.BulletEpoch, bulletTick = p.BulletTick, hit = p.Hit });
                return relative;
            }
            private static void Require(bool ok, string why) { if (!ok) throw new InvalidOperationException(why); }
            private void WriteJson(string file, object value) => File.WriteAllText(Path.Combine(Output, file), JsonSerializer.Serialize(value, json));

            public void Dispose()
            {
                WriteJson("summary.json", new
                {
                    fixture = "world-bullet-presentation-gpu-v1", cases = cases.Count, readbackSamples = samples.Count,
                    consumedPackets, rejects, failures = failures.ToArray(),
                    sync = finalSync, exactFrameSyncVerified = failures.IsEmpty,
                    sourceLogicalFrameDecodedByGpu = true, physicalScanoutVerified = false, gameplayExecuted = false
                });
            }

            private sealed record Scenario(int Epoch, int Style, bool Chain, string Id, int Fps, int DelayFrames);
            private sealed record CaseResult(Scenario Scenario, string Kind, bool Passed, object Evidence);
            private sealed record PixelFrame(double Ms, int Scene, int Tick, int BulletEpoch, int BulletTick, bool Hit, byte[] Bytes);
            private sealed record Sample(string Case, double RequestMs, double Ms, double ReadbackMs, int Scene,
                int Tick, int BulletEpoch, int BulletTick, bool Hit, ulong Presented, ulong Received,
                NativeCompositorSession.BulletSyncStats Sync);

            private class QuietForm : Form
            {
                internal QuietForm()
                {
                    AutoScaleMode = AutoScaleMode.None; ClientSize = new Size(W, H); FormBorderStyle = FormBorderStyle.None;
                    ShowInTaskbar = false; StartPosition = FormStartPosition.Manual; Location = new Point(24, 24); BackColor = Color.Black;
                }
                protected override bool ShowWithoutActivation => true;
                protected override CreateParams CreateParams
                { get { var p = base.CreateParams; p.ExStyle |= 0x08000080; return p; } }
            }

            private sealed class SourceForm : QuietForm
            {
                private readonly Fixture owner;
                private Scenario scene; private int tick;
                private readonly Font large = new("Segoe UI", 28, FontStyle.Bold, GraphicsUnit.Pixel);
                private readonly Font small = new("Segoe UI", 16, FontStyle.Regular, GraphicsUnit.Pixel);
                private readonly Font tiny = new("Consolas", 13, FontStyle.Regular, GraphicsUnit.Pixel);
                internal SourceForm(Fixture owner) { this.owner = owner; Text = "CF7 bullet sync source"; DoubleBuffered = true; }
                internal void Set(Scenario s, int value)
                {
                    scene = s; tick = value; Refresh();
                    owner.events.Enqueue(new { kind = "source-refresh", ms = owner.Now, epoch = s.Epoch, tick = value, hit = value >= 4 });
                }
                private static Color TagColor(int index, int epoch, int frame)
                {
                    if (index == 0) return Color.FromArgb(0x13, 0x57, 0x9B);
                    int f0 = frame % 256, f1 = (frame / 256) % 256, f2 = (frame / 65536) % 256;
                    if (index == 1) return Color.FromArgb(f0, f1, f2);
                    if (index == 3) return Color.FromArgb(255 - f0, 255 - f1, 255 - f2);
                    int e0 = epoch % 256, e1 = (epoch / 256) % 256;
                    return Color.FromArgb(e0, e1, (f0 + f1 + f2 + e0 + e1 + 167) % 256);
                }
                protected override void OnPaint(PaintEventArgs e)
                {
                    var g = e.Graphics; g.Clear(Color.FromArgb(18, 24, 35));
                    int current = scene?.Epoch ?? 0;
                    void Bits(int value, int y)
                    { for (int i = 0; i < 8; i++) g.FillRectangle((value & (1 << i)) != 0 ? Brushes.White : Brushes.Black, 20 + i * 18, y, 14, 14); }
                    Bits(current, 20); Bits(tick, 42);
                    g.DrawString($"WGC source: scene {current}, tick {tick}", small, Brushes.LightSteelBlue, 184, 21);
                    g.DrawString("NATIVE BULLET TICK (yellow marker below)", tiny, Brushes.SlateGray, 20, 65);
                    for (int i = 0; i < 8; i++) g.DrawString(i.ToString(), tiny, Brushes.SlateGray, 48 + i * 56, 102);
                    g.DrawString("NATIVE SCENE MOD 16", tiny, Brushes.SlateGray, 20, 145);
                    bool hit = tick >= 4; g.FillRectangle(hit ? Brushes.Crimson : Brushes.SeaGreen, 984, 16, 30, 24);
                    g.DrawString($"{Styles[scene?.Style ?? 0]} / controlled offline witness", large, Brushes.White, 28, 187);
                    g.DrawString(hit ? "DUMMY: HIT (world tick >= 4)" : "DUMMY: IDLE", large,
                        hit ? Brushes.Salmon : Brushes.LightGreen, 540, 233);
                    using var floor = new Pen(Color.FromArgb(50, 65, 80), 2); g.DrawLine(floor, 20, 380, 1000, 380);
                    g.FillRectangle(hit ? Brushes.Maroon : Brushes.DarkSlateGray, 580, 275, 44, 90);
                    g.FillRectangle(hit ? Brushes.Crimson : Brushes.SeaGreen, 584, 279, 36, 82);
                    if (hit) { using var impact = new Pen(Color.OrangeRed, 4); g.DrawLine(impact, 570, 270, 550, 250); g.DrawLine(impact, 630, 270, 650, 250); }
                    g.FillRectangle(Brushes.DimGray, 598, 365, 8, 15);
                    g.DrawString("Flight corridor: actual production bullet pixels at y=300", small, Brushes.LightSteelBlue, 28, 405);
                    g.DrawString("Source draws no projectile. Bullet pixels and markers come from the candidate native DLL.", small, Brushes.LightSteelBlue, 28, 434);
                    g.DrawString("Synthetic dummy reaction; this is not the original gym scene or an AS2 collision test.", small, Brushes.SlateGray, 28, 472);
                    g.DrawString("Hit tick 4: anchor x=560. Held tick 3: anchor x=440 (before dummy x=580).", small, Brushes.SlateGray, 28, 502);
                    for (int i = 0; i < 4; i++)
                        using (var brush = new SolidBrush(TagColor(i, current, tick))) g.FillRectangle(brush, i * 16, 560, 16, 16);
                }
                protected override void Dispose(bool disposing)
                { if (disposing) { large.Dispose(); small.Dispose(); tiny.Dispose(); } base.Dispose(disposing); }
            }
        }

        [DllImport("gdi32.dll")] private static extern bool GdiFlush();
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after,
            int x, int y, int cx, int cy, uint flags);
    }
}
