using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Bus;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Tasks;
using CF7Launcher.Tooltips;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

internal static partial class Program
{
    private static int _passed;
    private static readonly TimeSpan Deadline = TimeSpan.FromSeconds(10);

    private static async Task<int> Main(string[] args)
    {
        try
        {
            string root = args.Length > 1 ? Path.GetFullPath(args[1]) : FindRoot();
            if (args.Length > 0 && args[0] == "--evaluate")
            {
                using var engine = new TooltipV8Engine(root);
                foreach (string line in File.ReadLines(args[2]).Where(x => !string.IsNullOrWhiteSpace(x)))
                    Console.WriteLine(engine.BuildProjection(line));
                return 0;
            }
            if (args.Length > 0 && args[0] == "--validate-service")
            {
                using var service = new TooltipService(() => new TooltipV8Engine(root));
                await service.Ready.WaitAsync(Deadline);
                int count = 0;
                foreach (string line in File.ReadLines(args[2]).Where(x => !string.IsNullOrWhiteSpace(x)))
                {
                    count++;
                    try { await service.BuildAsync(JObject.Parse(line), Id("service-corpus", count)).WaitAsync(Deadline); }
                    catch (Exception ex) { throw new InvalidOperationException("Production service rejected input line " + count, ex); }
                }
                Console.WriteLine(new JObject { ["validatedInputs"] = count, ["engineIdentity"] = service.GetMetrics().EngineIdentity,
                    ["built"] = service.GetMetrics().Built, ["cacheEntries"] = service.GetMetrics().CacheEntries,
                    ["cacheEstimatedBytes"] = service.GetMetrics().CacheBytes }.ToString(Formatting.Indented));
                return 0;
            }
            if (args.Length > 0 && args[0] == "--bench")
            {
                await Benchmark(root, args.Length > 2 ? args[2] : null);
                return 0;
            }
            await Tests(root);
            Console.WriteLine("PASS " + _passed + " tooltip host checks (production C#; fake surfaces are protocol evidence only)");
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }

    private static string FindRoot()
    {
        var dir = new DirectoryInfo(Environment.CurrentDirectory);
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "launcher", "scripts", "dist", "tooltip-catalog-compiler.js"))
                || File.Exists(Path.Combine(dir.FullName, "data", "tooltip", "tooltip-catalog.json"))) return dir.FullName;
            dir = dir.Parent;
        }
        throw new DirectoryNotFoundException("Run from the repository or pass --test <project-root>.");
    }

    private sealed class FakeEngine : ITooltipContentEngine
    {
        internal readonly ManualResetEventSlim Entered = new ManualResetEventSlim();
        internal readonly ManualResetEventSlim Release = new ManualResetEventSlim(true);
        internal int Calls, ThreadId, Disposals;
        internal bool AlwaysFail;
        public string Identity => "fake-content-v1";
        public string BuildProjection(string inputJson)
        {
            ThreadId = Environment.CurrentManagedThreadId;
            Interlocked.Increment(ref Calls); Entered.Set();
            if (!Release.Wait(Deadline)) throw new TimeoutException("fake engine was not released");
            if (AlwaysFail) throw new InvalidOperationException("test_content_failure");
            var input = JObject.Parse(inputJson);
            string text = input.Value<string>("html") ?? "value";
            if (input.Value<string>("output") == "details")
                return new JObject { ["details"] = text }.ToString(Formatting.None);
            return new JObject
            {
                ["document"] = new JObject { ["version"] = 1, ["title"] = text,
                    ["profile"] = input.Value<string>("profile") ?? "simple",
                    ["sections"] = new JArray(new JObject { ["role"] = "body", ["runs"] = new JArray(new JObject { ["text"] = text }) }) },
                ["introHTML"] = text, ["descHTML"] = text, ["details"] = text
            }.ToString(Formatting.None);
        }
        public void Dispose() { Interlocked.Increment(ref Disposals); }
    }

    private sealed class FakeUi
    {
        private readonly ConcurrentQueue<Action> _queue = new ConcurrentQueue<Action>();
        internal void Post(Action action) => _queue.Enqueue(action);
        internal void Pump() { while (_queue.TryDequeue(out var action)) action(); }
        internal async Task Until(Func<bool> predicate)
        {
            var timeout = Stopwatch.StartNew();
            while (!predicate())
            {
                Pump();
                if (timeout.Elapsed > Deadline) throw new TimeoutException("fake UI did not reach expected state");
                await Task.Delay(1);
            }
            Pump();
        }
    }

    private static JObject Input(string html = "sample", string profile = "simple") => new JObject
    { ["version"] = 1, ["kind"] = "body", ["html"] = html, ["profile"] = profile };
    private static TooltipRequestIdentity Id(string owner, int sequence = 1, string revision = "", string lease = "", string scene = "scene",
        TooltipRequestKind kind = TooltipRequestKind.Hover) => new TooltipRequestIdentity(owner, "r" + sequence, scene, revision, lease, kind, sequence);
    private static JObject Native(string op, string requestId, string scene, JObject input = null, int revision = 0, string kind = "tooltip")
    {
        var payload = new JObject { ["kind"] = kind, ["op"] = op, ["version"] = 1,
            ["requestId"] = requestId, ["sceneId"] = scene, ["x"] = 3, ["y"] = 5, ["revision"] = revision };
        if (input != null) payload["tooltipInput"] = input;
        return new JObject { ["task"] = "native_interaction", ["payload"] = payload };
    }
    private static async Task Check(string name, Func<Task> test)
    { await test(); _passed++; Console.WriteLine("ok " + _passed + " - " + name); }
    private static void Assert(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Canceled(Task task)
    {
        try { await task.WaitAsync(Deadline); }
        catch (OperationCanceledException) { return; }
        throw new InvalidOperationException("expected cancellation");
    }
    private static async Task Fails(Task task)
    {
        try { await task.WaitAsync(Deadline); }
        catch (Exception ex) when (ex is not TimeoutException) { return; }
        throw new InvalidOperationException("expected failure");
    }

    private static async Task Tests(string root)
    {
        await Check("one persistent engine, dedicated worker, bounded projection", async () =>
        {
            var engine = new FakeEngine(); int created = 0;
            using var service = new TooltipService(() => { Interlocked.Increment(ref created); return engine; });
            await service.Ready.WaitAsync(Deadline);
            var result = await service.BuildAsync(Input("甲"), Id("a")).WaitAsync(Deadline);
            Assert(result.ToObject()["document"].Value<string>("title") == "甲", "content lost");
            Assert(engine.ThreadId != Environment.CurrentManagedThreadId && created == 1, "engine ran on requester");
        });
        await Check("invalid version, kind, prototype, depth and non-finite numbers fail before V8", async () =>
        {
            var engine = new FakeEngine(); using var service = new TooltipService(() => engine);
            var values = new List<JObject> { new JObject { ["version"] = 2, ["kind"] = "body" },
                new JObject { ["version"] = 1, ["kind"] = "unknown" }, Input(), Input(), Input() };
            values[2]["__proto__"] = new JObject(); values[3]["number"] = double.NaN;
            JObject node = values[4]; for (int i = 0; i < 26; i++) { var next = new JObject(); node["nested"] = next; node = next; }
            foreach (var value in values) await Fails(service.BuildAsync(value, Id("invalid")));
            Assert(engine.Calls == 0, "invalid input reached engine");
        });
        await Check("identical snapshots coalesce across independent owners", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            var first = service.BuildAsync(Input(), Id("a")); Assert(engine.Entered.Wait(Deadline), "worker not entered");
            var second = service.BuildAsync(Input(), Id("b")); engine.Release.Set();
            await Task.WhenAll(first, second).WaitAsync(Deadline);
            Assert(engine.Calls == 1 && service.GetMetrics().Coalesced == 1, "coalescing failed");
        });
        await Check("latest owner wins, older late response cannot overwrite a completed frontier", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            var old = service.BuildAsync(Input("old"), Id("owner", 1)); Assert(engine.Entered.Wait(Deadline), "worker not entered");
            var fresh = service.BuildAsync(Input("new"), Id("owner", 2)); await Canceled(old);
            engine.Release.Set(); Assert((await fresh.WaitAsync(Deadline)).ToObject().Value<string>("details") == "new", "new result lost");
            await Canceled(service.BuildAsync(Input("late old"), Id("owner", 1)));
            Assert(engine.Calls == 2, "old sequence recomputed");
        });
        await Check("500 hover replacements keep one queued latest input", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine, queueCapacity: 2, subscriberCapacity: 4);
            var requests = new List<Task<TooltipBuildResult>> { service.BuildAsync(Input("0"), Id("hover", 1)) };
            Assert(engine.Entered.Wait(Deadline), "worker not entered");
            for (int i = 1; i <= 500; i++) requests.Add(service.BuildAsync(Input(i.ToString()), Id("hover", i + 1)));
            Assert(service.GetMetrics().Queued == 1 && service.GetMetrics().MaxQueueDepth <= 1, "hover queue grew");
            foreach (var task in requests.Take(requests.Count - 1)) await Canceled(task);
            engine.Release.Set(); await requests.Last().WaitAsync(Deadline);
            Assert(engine.Calls == 2, "obsolete hover content executed");
        });
        await Check("queue and subscribers are bounded; cancellation frees queued capacity", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine, queueCapacity: 1, subscriberCapacity: 3);
            var active = service.BuildAsync(Input("active"), Id("a")); Assert(engine.Entered.Wait(Deadline), "worker not entered");
            using var cancellation = new CancellationTokenSource();
            var queued = service.BuildAsync(Input("queued"), Id("b"), cancellation.Token);
            await Fails(service.BuildAsync(Input("full"), Id("c"))); cancellation.Cancel(); await Canceled(queued);
            var admitted = service.BuildAsync(Input("admitted"), Id("c", 2)); engine.Release.Set();
            await Task.WhenAll(active, admitted).WaitAsync(Deadline);
            Assert(service.GetMetrics().Rejected == 1, "queue bound not measured");
        });
        await Check("Inspector has an independent lane and exact cancellation cannot hide a newer request", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            var pinned = service.BuildAsync(Input("pin"), Id("shared", kind: TooltipRequestKind.Inspector));
            Assert(engine.Entered.Wait(Deadline), "worker not entered");
            var hover = service.BuildAsync(Input("hover"), Id("shared", 2));
            service.Cancel("shared", TooltipRequestKind.Hover, "r1", "scene");
            Assert(!pinned.IsCanceled && !hover.IsCanceled, "wrong identity canceled active request");
            engine.Release.Set(); await Task.WhenAll(pinned, hover).WaitAsync(Deadline);
        });
        await Check("cache distinguishes revision, lease, scene and snapshot; cached object is immutable", async () =>
        {
            var engine = new FakeEngine(); using var service = new TooltipService(() => engine, cacheCapacity: 2, cacheByteLimit: 4096);
            var a = await service.BuildAsync(Input("a"), Id("a", 1, "1", "lease1", "scene1"));
            a.ToObject()["document"]["title"] = "mutated";
            var b = await service.BuildAsync(Input("a"), Id("b", 1, "1", "lease1", "scene1"));
            Assert(b.ToObject()["document"].Value<string>("title") == "a" && engine.Calls == 1, "cache alias or missed hit");
            await service.BuildAsync(Input("a"), Id("b", 2, "2", "lease1", "scene1"));
            await service.BuildAsync(Input("a"), Id("b", 3, "2", "lease2", "scene1"));
            await service.BuildAsync(Input("a"), Id("b", 4, "2", "lease2", "scene2"));
            Assert(engine.Calls == 4 && service.GetMetrics().CacheEntries <= 2 && service.GetMetrics().CacheBytes <= 4096, "cache identity/bounds failed");
        });
        await Check("cache hits recheck cancellation and fences without admitting expired owners", async () =>
        {
            var engine = new FakeEngine(); using var service = new TooltipService(() => engine);
            await service.BuildAsync(Input("cached"), Id("seed"));
            engine.Entered.Reset(); engine.Release.Reset();
            var old = service.BuildAsync(Input("old"), Id("lane", 1));
            Assert(engine.Entered.Wait(Deadline), "old request not running");
            int checks = 0;
            await Canceled(service.BuildAsync(Input("cached"), Id("lane", 9), isCurrent: () => ++checks == 1));
            Assert(!old.IsCompleted, "expired owner retired a current request");
            using var cancellation = new CancellationTokenSource(); checks = 0;
            await Canceled(service.BuildAsync(Input("cached"), Id("lane", 10), cancellation.Token,
                () => { if (++checks == 2) cancellation.Cancel(); return true; }));
            Assert(!old.IsCompleted, "canceled cache lookup retired a current request");
            engine.Release.Set(); await old.WaitAsync(Deadline);
            var fresh = await service.BuildAsync(Input("cached"), Id("lane", 2));
            Assert(fresh != null, "canceled cache lookup advanced sequence frontier");
            checks = 0;
            await Canceled(service.BuildAsync(Input("cached"), Id("lane", 3), isCurrent: () => ++checks < 3));
        });
        await Check("disconnect retires queued/running requests and permits a new sequence epoch", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            var old = service.BuildAsync(Input("old"), Id("a", 100)); Assert(engine.Entered.Wait(Deadline), "worker not entered");
            service.ResetRequests(); await Canceled(old);
            var fresh = service.BuildAsync(Input("fresh"), Id("a", 1)); engine.Release.Set(); await fresh.WaitAsync(Deadline);
            Assert(service.GetMetrics().ActiveRequests == 0, "subscriber retained");
        });
        await Check("initialization failure settles all work without per-request engine retries", async () =>
        {
            int attempts = 0; using var service = new TooltipService(() => { attempts++; throw new IOException("missing bundle"); });
            await Fails(service.Ready); await Fails(service.BuildAsync(Input(), Id("a")));
            await Fails(service.BuildAsync(Input(), Id("b"))); Assert(attempts == 1, "engine retried per request");
        });
        await Check("fake socket enriches before original strict response handler, ordinary route is synchronous", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            using var enricher = new TooltipResponseEnricher(service);
            var router = new MessageRouter { TooltipResponses = enricher };
            var arrived = new TaskCompletionSource<JObject>(TaskCreationOptions.RunContinuationsAsynchronously);
            router.RegisterAsync("inventory_response", (msg, respond) => { arrived.TrySetResult(msg); respond(null); });
            router.RegisterSync("echo", msg => "{\"success\":true}");
            Assert(router.ProcessMessage("{\"task\":\"echo\",\"callId\":1}", null) != null, "ordinary route became deferred");
            var response = new JObject { ["task"] = "inventory_response", ["callId"] = 7, ["success"] = true, ["tooltipInput"] = Input("socket") };
            Assert(router.ProcessMessage(response.ToString(Formatting.None), null) == null && !arrived.Task.IsCompleted, "socket waited for tooltip");
            Assert(engine.Entered.Wait(Deadline), "worker not entered"); engine.Release.Set();
            var result = await arrived.Task.WaitAsync(Deadline);
            Assert(result.Value<int>("callId") == 7 && result["tooltipInput"] == null && result["document"] != null, "response shape lost");
        });
        await Check("nested details-only preview remains one response without extra document fields", async () =>
        {
            using var service = new TooltipService(() => new FakeEngine()); using var enricher = new TooltipResponseEnricher(service);
            var input = Input("choice"); input["output"] = "details";
            var msg = new JObject { ["task"] = "item_use_response", ["callId"] = 9, ["success"] = true,
                ["data"] = new JObject { ["success"] = true, ["items"] = new JArray(new JObject { ["itemName"] = "x", ["tooltipInput"] = input }) } };
            var arrived = new TaskCompletionSource<JObject>(TaskCreationOptions.RunContinuationsAsynchronously);
            Assert(enricher.TryEnrich(msg, 0, result => arrived.SetResult(result)), "not intercepted");
            var result = await arrived.Task.WaitAsync(Deadline);
            var row = (JObject)result["data"]["items"][0];
            Assert(row.Count == 2 && row.Value<string>("details") == "choice", "details polluted exact item schema");
        });
        await Check("content failure preserves committed business acknowledgement and is visibly unavailable", async () =>
        {
            using var service = new TooltipService(() => new FakeEngine { AlwaysFail = true }); using var enricher = new TooltipResponseEnricher(service);
            var msg = new JObject { ["task"] = "item_use_response", ["callId"] = 11, ["success"] = true,
                ["data"] = new JObject { ["success"] = true, ["operationId"] = "committed-op", ["tooltip"] = new JObject { ["tooltipInput"] = Input() } } };
            var arrived = new TaskCompletionSource<JObject>(TaskCreationOptions.RunContinuationsAsynchronously);
            enricher.TryEnrich(msg, 0, result => arrived.SetResult(result));
            var result = await arrived.Task.WaitAsync(Deadline);
            Assert(result.Value<bool>("success") && result["data"].Value<bool>("success")
                && result["data"].Value<string>("operationId") == "committed-op", "business fact changed");
            Assert(result["data"]["tooltip"]["document"].Value<string>("title") == "注释暂不可用"
                && result["data"]["tooltip"].Value<string>("introHTML").Length > 0, "failure disguised as empty success");
        });
        await Check("response disconnect and closed pending owner never resume stale callbacks", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            int generation = 1, delivered = 0; using var enricher = new TooltipResponseEnricher(service, () => generation);
            var msg = new JObject { ["task"] = "inventory_response", ["callId"] = 1, ["tooltipInput"] = Input() };
            enricher.TryEnrich(msg, 1, _ => Interlocked.Increment(ref delivered)); Assert(engine.Entered.Wait(Deadline), "not started");
            generation = 2; enricher.Reset(); service.ResetRequests(); engine.Release.Set();
            await Task.Delay(30); Assert(delivered == 0, "old connection callback dispatched");
        });
        await Check("closed pending owner is pruned before queued V8 work and cannot deliver", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            var blocker = service.BuildAsync(Input("blocker"), Id("other-owner"));
            Assert(engine.Entered.Wait(Deadline), "blocker not started");
            using var enricher = new TooltipResponseEnricher(service);
            int current = 1, delivered = 0;
            enricher.RegisterOwnerResolver("inventory_response", fid => new TooltipResponseOwner {
                Identity = Id("closed-panel", fid), IsCurrent = () => Volatile.Read(ref current) == 1,
                RetireSuperseded = () => { } });
            enricher.TryEnrich(new JObject { ["task"] = "inventory_response", ["callId"] = 2, ["tooltipInput"] = Input("closed") },
                0, _ => Interlocked.Increment(ref delivered));
            Assert(service.GetMetrics().Queued == 1, "read not queued");
            Volatile.Write(ref current, 0); engine.Release.Set(); await blocker.WaitAsync(Deadline);
            for (int i = 0; i < 100 && service.GetMetrics().ActiveRequests > 0; i++) await Task.Delay(1);
            Assert(engine.Calls == 1 && service.GetMetrics().ActiveRequests == 0 && delivered == 0,
                "closed owner consumed V8 or delivered");
        });
        await Check("stable Web owner supersedes pure reads and retires their original pending entries", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            using var enricher = new TooltipResponseEnricher(service);
            var current = new ConcurrentDictionary<int, bool>(); current[1] = true; current[2] = true;
            int retired = 0; var delivered = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
            enricher.RegisterOwnerResolver("inventory_response", fid => new TooltipResponseOwner {
                Identity = Id("panel:inventory", fid), IsCurrent = () => current.ContainsKey(fid),
                RetireSuperseded = () => { current.TryRemove(fid, out _); Interlocked.Increment(ref retired); } });
            JObject Response(int id) => new JObject { ["task"] = "inventory_response", ["callId"] = id, ["tooltipInput"] = Input(id.ToString()) };
            enricher.TryEnrich(Response(1), 0, msg => delivered.TrySetResult(msg.Value<int>("callId")));
            Assert(engine.Entered.Wait(Deadline), "not started");
            enricher.TryEnrich(Response(2), 0, msg => delivered.TrySetResult(msg.Value<int>("callId")));
            engine.Release.Set(); Assert(await delivered.Task.WaitAsync(Deadline) == 2, "old owner delivered");
            for (int i = 0; i < 100 && retired == 0; i++) await Task.Delay(1);
            Assert(retired == 1 && !current.ContainsKey(1), "superseded pending leaked");
        });
        await ManagedTaskTests(root);
        await EquipmentTuningTests(root);
        await NativeTests();
        await Check("package integrity covers its snapshot and needs no authoring sources", async () =>
        {
            string temp = Path.Combine(Path.GetTempPath(), "cf7-tooltip-stale-" + Guid.NewGuid().ToString("N"));
            try
            {
                string bundleDest = Path.Combine(temp, "launcher/scripts/dist/tooltip-bundle.js");
                Directory.CreateDirectory(Path.GetDirectoryName(bundleDest));
                File.Copy(Path.Combine(root, "launcher/scripts/dist/tooltip-bundle.js"), bundleDest);
                var snap = new TooltipCatalogSource(root).Snapshot;
                string catalogPath = Path.Combine(temp, "data/tooltip/tooltip-catalog.json");
                string manifestPath = Path.Combine(temp, "data/tooltip/tooltip-catalog.manifest.json");
                Directory.CreateDirectory(Path.GetDirectoryName(catalogPath));
                File.WriteAllText(catalogPath, snap.Catalog);
                var manifest = new JObject
                {
                    ["version"] = 1,
                    ["output"] = "data/tooltip/tooltip-catalog.json",
                    ["outputSha256"] = snap.Digest,
                    ["contentVersion"] = JObject.Parse(snap.Catalog).Value<string>("contentVersion")
                };
                File.WriteAllText(manifestPath, manifest.ToString(Formatting.None));
                File.AppendAllText(catalogPath, " ");
                using (var changed = new TooltipService(() => new TooltipV8Engine(temp)))
                    await Fails(changed.Ready);
                var lf = snap.Catalog.Replace("\r\n", "\n");
                File.WriteAllText(catalogPath, lf.Replace("\n", "\r\n"));
                using var packaged = new TooltipService(() => new TooltipV8Engine(temp));
                await packaged.Ready.WaitAsync(Deadline);
                Assert(packaged.GetMetrics().EngineIdentity.StartsWith("tooltip-v1:"), "prepared snapshot did not load");
            }
            finally { Directory.Delete(temp, true); }
        });
        await Check("source archive without .git compiles live sources and tolerates empty crafting files", async () =>
        {
            string temp = Path.Combine(Path.GetTempPath(), "cf7-tooltip-archive-" + Guid.NewGuid().ToString("N"));
            try
            {
                foreach (string relative in new[]
                {
                    "tools/tooltip-catalog.cjs",
                    "launcher/scripts/dist/tooltip-catalog-compiler.js",
                    "launcher/scripts/dist/tooltip-bundle.js",
                    "data/equipment/equipment_config.xml"
                })
                {
                    string target = Path.Combine(temp, relative);
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    File.Copy(Path.Combine(root, relative), target);
                }
                void WriteTempFile(string relative, string content)
                {
                    string target = Path.Combine(temp, relative);
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    File.WriteAllText(target, content);
                }
                WriteTempFile("data/items/list.xml", "<root><items>test.xml</items></root>");
                WriteTempFile("data/items/test.xml", "<root><item><name>测试刀</name><displayname>源包测试刀</displayname><type>武器</type><use>刀</use><price>10</price><description>说明</description><data><level>1</level><power>50</power></data></item></root>");
                WriteTempFile("data/items/equipment_mods/list.xml", "<root/>");
                WriteTempFile("data/enemy_properties/list.xml", "<root/>");
                WriteTempFile("data/crafting/list.xml", "<root><list>empty</list></root>");
                string emptyRecipePath = Path.Combine(temp, "data/crafting/empty.json");
                Directory.CreateDirectory(Path.GetDirectoryName(emptyRecipePath));
                File.WriteAllBytes(emptyRecipePath, Array.Empty<byte>());
                WriteTempFile("data/tooltip/tooltip-catalog.json", "{}");

                var logs = new List<string>();
                var source = new TooltipCatalogSource(temp, logs.Add);
                Assert(source.IsCheckout, "source archive carrying tools/tooltip-catalog.cjs must run in checkout mode");
                using var service = new TooltipService(() => new TooltipV8Engine(temp, source), logs.Add);
                await service.Ready.WaitAsync(Deadline);
                Assert(logs.Any(l => l.Contains("data/crafting/empty.json")), "empty recipe diagnostic missing");
                Assert(JObject.Parse(source.Snapshot.Catalog).Value<bool>("recipesUnavailable"), "recipesUnavailable not flagged");
            }
            finally { Directory.Delete(temp, true); }
        });
        await Check("real V8 item Inspector keeps pinned identity after content generation", async () =>
        {
            var catalog = JObject.Parse(new TooltipCatalogSource(root).Snapshot.Catalog);
            var itemEntry = ((JObject)catalog["items"]).Properties().First(entry => entry.Value.Value<string>("type") == "武器");
            var item = (JObject)itemEntry.Value;
            var input = new JObject { ["version"] = 1, ["kind"] = "item", ["itemName"] = itemEntry.Name,
                ["value"] = new JObject { ["level"] = 1 }, ["presentation"] = "native", ["profile"] = "pinned",
                ["projection"] = new JObject { ["isEquipment"] = true, ["isMaterial"] = false, ["isInformation"] = false,
                    ["calculated"] = null, ["baselineData"] = item["data"]?.DeepClone(), ["bladeCount"] = 0,
                    ["isVerticalBullet"] = false, ["electric"] = false, ["registeredModName"] = null,
                    ["tierOptions"] = new JArray(), ["drugEffects"] = new JArray(), ["mods"] = new JObject(), ["obtainRecords"] = new JArray() } };
            using var service = new TooltipService(() => new TooltipV8Engine(root));
            var ui = new FakeUi(); var surface = new NativeTooltipSurfaceAdapter();
            var task = new NativeInteractionTask(null, new NpcMenuWidget(), surface, ui.Post, null, service);
            task.Handle(Native("show", "ni:1", "s1", input)); ui.Pump();
            await ui.Until(() => surface.HasPinnedSession);
            task.Handle(Native("show", "ni:2", "s1", Input("hover"))); ui.Pump();
            Assert(surface.CurrentRequestId == "ni:1" && surface.Shows == 1, "item Inspector was downgraded to hover");
        });
        await Check("real ClearScript 7.4.5 executes production bundle and details-only mode", async () =>
        {
            using var service = new TooltipService(() => new TooltipV8Engine(root)); await service.Ready.WaitAsync(Deadline);
            var input = Input("<font color=\"#abc\">真实 V8 &amp; 测试</font>");
            var normal = (await service.BuildAsync(input, Id("real"))).ToObject();
            Assert(normal["document"] != null && normal.Value<string>("descHTML").Contains("真实 V8"), "production V8 document missing");
            input["output"] = "details";
            var details = (await service.BuildAsync(input, Id("real", 2))).ToObject();
            Assert(details.Count == 1 && details.Value<string>("details").Contains("真实 V8"), "production details-only rejected");
            await Fails(service.BuildAsync(new JObject { ["version"] = 1, ["kind"] = "item", ["itemName"] = "missing item" }, Id("bad")));
            input.Remove("output");
            var after = (await service.BuildAsync(input, Id("after"))).ToObject();
            Assert(JToken.DeepEquals(normal, after), "exception leaked engine state");
            using var enricher = new TooltipResponseEnricher(service);
            var choiceInput = Input("<b>选择奖励说明</b>"); choiceInput["output"] = "details";
            var choice = new JObject { ["task"] = "item_use_response", ["callId"] = 21, ["success"] = true,
                ["data"] = new JObject { ["success"] = true, ["operationId"] = "committed-choice",
                    ["offers"] = new JArray(new JObject { ["options"] = new JArray(new JObject {
                        ["items"] = new JArray(new JObject { ["itemName"] = "reward", ["tooltipInput"] = choiceInput }) }) }) } };
            var arrived = new TaskCompletionSource<JObject>(TaskCreationOptions.RunContinuationsAsynchronously);
            enricher.TryEnrich(choice, 0, response => arrived.SetResult(response));
            var enriched = await arrived.Task.WaitAsync(Deadline);
            var row = (JObject)enriched["data"]["offers"][0]["options"][0]["items"][0];
            Assert(row.Count == 2 && row.Value<string>("details").Contains("选择奖励说明")
                && enriched["data"].Value<string>("operationId") == "committed-choice", "real V8 choice response lost details or business identity");
        });
    }

    private static async Task NativeTests()
    {
        await Check("native hide-before-result never materializes a tooltip", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            var ui = new FakeUi(); var surface = new NativeTooltipSurfaceAdapter();
            var task = new NativeInteractionTask(null, new NpcMenuWidget(), surface, ui.Post, null, service);
            task.Handle(Native("show", "ni:1", "s1", Input("old"))); ui.Pump(); Assert(engine.Entered.Wait(Deadline), "not started");
            task.Handle(Native("hide", "ni:1", "s1")); ui.Pump(); engine.Release.Set();
            await Task.Delay(20); ui.Pump(); Assert(surface.Shows == 0, "late show revived after hide");
        });
        await Check("native rapid switch delivers only latest, wrong-scene hide leaves it alive", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            var ui = new FakeUi(); var surface = new NativeTooltipSurfaceAdapter();
            var task = new NativeInteractionTask(null, new NpcMenuWidget(), surface, ui.Post, null, service);
            task.Handle(Native("show", "ni:1", "s1", Input("old"))); ui.Pump(); Assert(engine.Entered.Wait(Deadline), "not started");
            task.Handle(Native("show", "ni:2", "s1", Input("new"))); ui.Pump(); engine.Release.Set();
            await ui.Until(() => surface.CurrentRequestId == "ni:2");
            task.Handle(Native("hide", "ni:2", "foreign")); ui.Pump();
            Assert(surface.Shows == 1 && surface.CurrentRequestId == "ni:2", "wrong native identity won");
        });
        await Check("native pending Inspector rejects hover without advancing its identity", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            var ui = new FakeUi(); var surface = new NativeTooltipSurfaceAdapter();
            var task = new NativeInteractionTask(null, new NpcMenuWidget(), surface, ui.Post, null, service);
            task.Handle(Native("show", "ni:1", "s1", Input("pinned", "pinned"), 1)); ui.Pump(); Assert(engine.Entered.Wait(Deadline), "not started");
            task.Handle(Native("show", "ni:2", "s1", Input("hover"))); ui.Pump(); engine.Release.Set();
            await ui.Until(() => surface.HasPinnedSession);
            task.Handle(Native("show", "ni:1", "s1", Input("pinned refreshed", "pinned"), 2)); ui.Pump();
            await ui.Until(() => surface.Shows == 2);
            Assert(surface.CurrentRequestId == "ni:1" && engine.Calls == 2, "hover invalidated Inspector");
        });
        await Check("native scene roll, owner suppression and disconnect invalidate in-flight builds", async () =>
        {
            foreach (string mode in new[] { "scene", "suppression", "disconnect", "escape" })
            {
                var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
                var ui = new FakeUi(); var surface = new NativeTooltipSurfaceAdapter();
                var task = new NativeInteractionTask(null, new NpcMenuWidget(), surface, ui.Post, null, service);
                task.Handle(Native("show", "ni:1", "s1", Input("stale", mode == "escape" ? "pinned" : "simple"))); ui.Pump();
                Assert(engine.Entered.Wait(Deadline), "not started");
                if (mode == "scene") task.Handle(Native("show", "ni:2", "s2", kind: "menu"));
                if (mode == "suppression") task.OnHostSuppressed("owner_hidden");
                if (mode == "disconnect") task.HandleTransportDisconnected();
                if (mode == "escape") task.NotifyInteractionEscape();
                ui.Pump(); engine.Release.Set(); await Task.Delay(20); ui.Pump();
                Assert(surface.Shows == 0, "native request revived after " + mode);
            }
        });
        await Check("native revision regression is rejected before computation", async () =>
        {
            var engine = new FakeEngine(); engine.Release.Reset(); using var service = new TooltipService(() => engine);
            var ui = new FakeUi(); var surface = new NativeTooltipSurfaceAdapter();
            var task = new NativeInteractionTask(null, new NpcMenuWidget(), surface, ui.Post, null, service);
            task.Handle(Native("show", "ni:1", "s1", Input("revision2"), 2)); ui.Pump(); Assert(engine.Entered.Wait(Deadline), "not started");
            task.Handle(Native("show", "ni:1", "s1", Input("revision1"), 1)); ui.Pump(); engine.Release.Set();
            await ui.Until(() => surface.Shows > 0);
            Assert(engine.Calls == 1 && surface.LastPayload.Value<int>("revision") == 2, "revision regressed");
        });
    }

    private static async Task Benchmark(string root, string inputsPath)
    {
        string[] inputs = inputsPath == null
            ? Enumerable.Range(0, 128).Select(i => Input("<font color=\"#aabbcc\">性能 " + i + "</font>\n正文").ToString(Formatting.None)).ToArray()
            : File.ReadAllLines(inputsPath).Where(x => !string.IsNullOrWhiteSpace(x)).ToArray();
        if (inputs.Length == 0) throw new ArgumentException("Empty benchmark corpus");
        GC.Collect(); GC.WaitForPendingFinalizers();
        long before = Process.GetCurrentProcess().WorkingSet64;
        var initialization = Stopwatch.StartNew();
        using var engine = new TooltipV8Engine(root);
        double initMs = initialization.Elapsed.TotalMilliseconds;
        long initialized = Process.GetCurrentProcess().WorkingSet64;
        var timings = new List<double>();
        var batch = Stopwatch.StartNew();
        foreach (string input in inputs)
        {
            var time = Stopwatch.StartNew(); engine.BuildProjection(input); timings.Add(time.Elapsed.TotalMilliseconds);
        }
        double batchMs = batch.Elapsed.TotalMilliseconds;
        for (int round = 0; round < 5; round++) foreach (string input in inputs)
        {
            var time = Stopwatch.StartNew(); engine.BuildProjection(input); timings.Add(time.Elapsed.TotalMilliseconds);
        }
        long after = Process.GetCurrentProcess().WorkingSet64;
        using var service = new TooltipService(() => new TooltipV8Engine(root)); await service.Ready;
        var repeated = JObject.Parse(inputs[0]); await service.BuildAsync(repeated, Id("cache", 1));
        var cacheTimes = new List<double>();
        for (int i = 0; i < 1000; i++)
        {
            var time = Stopwatch.StartNew(); await service.BuildAsync(repeated, Id("cache", i + 2)); cacheTimes.Add(time.Elapsed.TotalMilliseconds);
        }
        var beforeSwitch = service.GetMetrics();
        var switchTasks = new List<Task<TooltipBuildResult>>();
        var switching = Stopwatch.StartNew();
        double latestSubmittedAt = 0;
        for (int i = 0; i < 1000; i++)
        {
            latestSubmittedAt = switching.Elapsed.TotalMilliseconds;
            switchTasks.Add(service.BuildAsync(JObject.Parse(inputs[i % inputs.Length]), Id("rapid-hover", i + 1)));
        }
        await switchTasks[^1].WaitAsync(Deadline);
        double latestTail = switching.Elapsed.TotalMilliseconds - latestSubmittedAt;
        int switchCanceled = 0, switchCompleted = 0;
        foreach (var task in switchTasks)
        {
            try { await task; switchCompleted++; }
            catch (OperationCanceledException) { switchCanceled++; }
        }
        var afterSwitch = service.GetMetrics();
        timings.Sort(); cacheTimes.Sort();
        double P(List<double> values, double p) => values[Math.Clamp((int)Math.Ceiling(values.Count * p) - 1, 0, values.Count - 1)];
        Console.WriteLine(new JObject
        {
            ["evidence"] = "Actual production bundle in standalone ClearScript host; no AVM1/CS6 or player UI evidence",
            ["hostOS"] = System.Runtime.InteropServices.RuntimeInformation.OSDescription,
            ["processArchitecture"] = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),
            ["framework"] = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
            ["hostProcessId"] = Environment.ProcessId,
            ["clearScript"] = "7.4.5", ["engineIdentity"] = engine.Identity,
            ["inputs"] = inputs.Length, ["samples"] = timings.Count, ["initializationMs"] = initMs,
            ["batchDistinctMs"] = batchMs, ["p50Ms"] = P(timings, .5), ["p95Ms"] = P(timings, .95), ["p99Ms"] = P(timings, .99),
            ["workingSetBeforeBytes"] = before, ["workingSetInitializedBytes"] = initialized, ["workingSetAfterBytes"] = after,
            ["cacheSamples"] = cacheTimes.Count, ["cacheP50Ms"] = P(cacheTimes, .5), ["cacheP95Ms"] = P(cacheTimes, .95), ["cacheP99Ms"] = P(cacheTimes, .99),
            ["cacheHits"] = beforeSwitch.CacheHits, ["cacheEstimatedBytes"] = beforeSwitch.CacheBytes,
            ["rapidSwitchRequests"] = switchTasks.Count, ["rapidSwitchCompleted"] = switchCompleted,
            ["rapidSwitchCanceled"] = switchCanceled, ["rapidSwitchBuilt"] = afterSwitch.Built - beforeSwitch.Built,
            ["rapidSwitchCacheHits"] = afterSwitch.CacheHits - beforeSwitch.CacheHits,
            ["rapidSwitchMaxQueueDepth"] = afterSwitch.MaxQueueDepth, ["rapidSwitchLatestTailMs"] = latestTail,
            ["rapidSwitchRemainingQueue"] = afterSwitch.Queued, ["rapidSwitchRemainingActive"] = afterSwitch.ActiveRequests,
            ["gameInputMeasured"] = false
        }.ToString(Formatting.Indented));
    }
}
