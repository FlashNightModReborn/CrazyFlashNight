using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>GUI/CLI 共用的地图维护内核：具名操作、摘要冲突、候选资产与可恢复批次。</summary>
    public sealed class MapAuthoringStore
    {
        private readonly string root, file;
        private readonly MapChangeJournal journal;
        private MapWorldCatalog world;
        public MapAuthoringStore(string projectRoot)
        {
            root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(projectRoot));
            file = MapProjectFiles.Resolve(root, MapDefinition.RelativePath);
            journal = new MapChangeJournal(root);
        }
        private T Locked<T>(Func<T> action)
        {
            using var mutex = new Mutex(false, "Local\\CF7MapAuthoring-" + MapDefinition.Hash(MapDefinition.Utf8.GetBytes(root.ToUpperInvariant())));
            bool owned = false;
            try
            {
                try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
                if (!owned) throw new IOException("另一个地图操作正在保存，请稍后重试。");
                return action();
            }
            finally { if (owned) mutex.ReleaseMutex(); }
        }
        public static void RecoverForStartup(string root) => new MapAuthoringStore(root).Locked(() => { new MapChangeJournal(root).RecoverPending(); return true; });
        public JObject Read() => Execute(new JObject { ["op"] = "read" });
        private JObject ReadCore()
        {
            byte[] bytes = MapProjectFiles.Read(root, MapDefinition.RelativePath);
            var definition = MapDefinition.Parse(bytes); var recent = new JArray();
            string history = MapProjectFiles.Resolve(root, MapChangeJournal.History.TrimEnd('/'));
            if (Directory.Exists(history))
                foreach (var path in Directory.EnumerateFiles(history, "*.json").OrderByDescending(File.GetLastWriteTimeUtc).Take(12))
                    recent.Add(journal.Metadata(Path.GetFileNameWithoutExtension(path)));
            var result = new JObject { ["definition"] = definition, ["renderDefinition"] = MapDomainDefinition.WebProjection(definition),
                ["digest"] = MapDefinition.Hash(bytes), ["recent"] = recent };
            if (definition.Value<int>("version") == 2)
            {
                var tasks = MapTaskCatalog.Load(root); result["taskDigest"] = tasks.Digest; result["initialFacts"] = InitialFacts(definition, tasks);
            }
            return result;
        }
        public JObject Catalogue() => Locked(() =>
        {
            journal.RecoverPending();
            var definition = MapDefinition.Load(root); var tasks = MapTaskCatalog.Load(root);
            world = MapWorldCatalog.Load(root);
            var result = world.Json(); result["tasks"] = tasks.Summary(); result["taskDigest"] = tasks.Digest;
            result["chains"] = new JArray(tasks.Chains); result["infrastructure"] = new JArray(tasks.Infrastructure.Properties().Select(p => p.Name));
            result["infrastructureSpecs"] = tasks.Infrastructure.DeepClone(); result["flags"] = new JArray();
            // 目录仍可解释缺失/漂移图片，让作者替换；preview/apply 与运行时继续严格拒绝未修复资源。
            result["assets"] = new MapAssetCandidates(root).Existing(definition);
            foreach (var candidate in new MapAssetCandidates(root).Recent())
                if (!((JArray)result["assets"]).Any(a => (string)a["assetUrl"] == (string)candidate["assetUrl"])) ((JArray)result["assets"]).Add(candidate);
            return result;
        });
        // 路径只由 native 文件选择器或显式本地 CLI 提供；Web/HTTP JSON 不开放 sourcePath。
        public JObject StageFile(string source) => Locked(() => new MapAssetCandidates(root).StageFile(source));
        public JObject StageImage(byte[] bytes, string name) => Locked(() => new MapAssetCandidates(root).Stage(bytes,
            new JObject { ["kind"] = "file", ["name"] = Path.GetFileName(name ?? "导入图片") }));
        public JObject Execute(JObject request)
        {
            string op = request.Value<string>("op");
            if (op == "catalog") return Catalogue();
            return Locked(() =>
            {
                if (op == "query") return Query(request.Value<string>("operationId"));
                if (op == "recover")
                {
                    var pending = journal.Read(request.Value<string>("operationId"));
                    MapRuleEvaluator.Need(pending != null && (string)pending["schema"] == MapChangeJournal.Schema, "没有可恢复的地图批次。");
                    journal.Recover(pending); return Query((string)pending["operationId"]);
                }
                journal.RecoverPending();
                if (op == "read") return ReadCore();
                if (op == "asset-inspect") return new MapAssetCandidates(root).Describe(request.Value<string>("assetUrl"));
                if (op == "open-source") return SourceInfo(request.Value<string>("kind"), request.Value<string>("id"));
                if (op == "asset-crop") return new MapAssetCandidates(root).Crop(request.Value<string>("assetUrl"), request.Value<string>("sourceDigest"), request["crop"] as JObject);
                if (op == "asset-extract")
                {
                    world ??= MapWorldCatalog.Load(root);
                    return MapSwfAssetExtractor.Extract(root, world, request);
                }
                if (op == "preview" || op == "apply")
                {
                    string id = request.Value<string>("operationId");
                    string binding = MapDefinition.Hash(MapDefinition.Bytes(new JObject { ["expectedDigest"] = request["expectedDigest"],
                        ["expectedTaskDigest"] = request["expectedTaskDigest"], ["changes"] = request["changes"] }));
                    if (op == "apply")
                    {
                        var existing = journal.Read(id);
                        if (existing != null)
                        {
                            MapRuleEvaluator.Need((string)existing["binding"] == binding, "同一操作编号不能用于不同修改。");
                            return Query(id);
                        }
                    }
                    byte[] before = MapProjectFiles.Read(root, MapDefinition.RelativePath);
                    CheckDigest(MapDefinition.Hash(before), request.Value<string>("expectedDigest"));
                    var definition = MapDefinition.Parse(before);
                    MapTaskCatalog tasks = null;
                    if (definition.Value<int>("version") == 2)
                    {
                        tasks = MapTaskCatalog.Load(root);
                        CheckDigest(tasks.Digest, request.Value<string>("expectedTaskDigest"), "任务内容已变化，请刷新目录；当前草稿仍保留。");
                        if (world == null || op == "apply") world = MapWorldCatalog.Load(root);
                    }
                    var plan = MapAuthoringPlan.Create(root, before, request["changes"] as JArray, tasks, world);
                    if (op == "preview")
                    {
                        var result = ReadCore(); result["definition"] = plan.Definition; result["renderDefinition"] = MapDomainDefinition.WebProjection(plan.Definition);
                        result["preview"] = true; result["impact"] = plan.Impact; result["previewAssets"] = plan.PreviewAssets;
                        if (definition.Value<int>("version") == 2)
                        {
                            var facts = request["facts"] as JObject ?? InitialFacts(plan.Definition, tasks);
                            MapSimulationFacts.Validate(facts, tasks);
                            result["projection"] = MapDomainService.Project(plan.Definition, facts, plan.Tasks, world.Occurrences);
                            result["baseProjection"] = MapDomainService.Project(definition, facts, tasks.Tasks, world.Occurrences);
                            result["facts"] = facts.DeepClone();
                            result["references"] = MapReferenceIndex.Build(plan.Definition, plan.Tasks);
                            result["assets"] = plan.AssetCatalogue;
                            if (request["compareFacts"] is JObject compare)
                            {
                                MapSimulationFacts.Validate(compare, tasks);
                                result["compareProjection"] = MapDomainService.Project(plan.Definition, compare, plan.Tasks, world.Occurrences);
                                result["compareBaseProjection"] = MapDomainService.Project(definition, compare, tasks.Tasks, world.Occurrences);
                            }
                        }
                        return result;
                    }
                    string afterDigest = (string)((JArray)plan.Files).First(x => (string)x["path"] == MapDefinition.RelativePath)["afterDigest"];
                    var record = journal.Prepare(id, binding, MapDefinition.Hash(before), afterDigest, request["changes"] as JArray, plan.Files);
                    journal.Commit(record); return Query(id);
                }
                if (op == "undo")
                {
                    string id = request.Value<string>("operationId"); var record = journal.Read(id);
                    MapRuleEvaluator.Need(record != null, "未找到该修改的撤回记录。");
                    if ((string)record["schema"] != MapChangeJournal.Schema) return UndoLegacy(record);
                    string state = (string)journal.State(record)["state"];
                    if (state == "original") return Query(id);
                    MapRuleEvaluator.Need(state == "applied", "批次已被后续修改影响，不能整批撤回。");
                    ValidateUndo(record);
                    journal.Undo(record); return Query(id);
                }
                throw new InvalidDataException("未知地图操作。");
            });
        }
        public static JObject InitialFacts(JObject definition, MapTaskCatalog tasks)
        {
            var chains = new JObject(); foreach (string chain in tasks.Chains) chains[chain] = 0;
            var taskFacts = new JObject(); foreach (var task in tasks.Tasks.Properties()) taskFacts[task.Name] = new JObject {
                ["finished"] = 0, ["active"] = false, ["deliverable"] = false, ["available"] = false };
            string scene = (string)((JObject)definition["locations"]).Properties().First().Value["sceneName"];
            var infrastructure = new JObject(); foreach (var project in tasks.Infrastructure.Properties()) infrastructure[project.Name] = 0;
            return new JObject { ["chains"] = chains, ["tasks"] = taskFacts, ["activeOrder"] = new JArray(),
                ["infrastructure"] = infrastructure, ["flags"] = new JObject(), ["dynamic"] = new JObject { ["roommateGender"] = "男" },
                ["scene"] = new JObject { ["stageFlag"] = scene, ["frameLabel"] = "", ["entrance"] = "", ["mapFrame"] = "", ["inCombat"] = false },
                ["navigation"] = new JObject { ["reason"] = "" } };
        }
        private JObject SourceInfo(string kind, string id)
        {
            string source;
            if (kind == "task")
            {
                var tasks = MapTaskCatalog.Load(root); MapRuleEvaluator.Need(tasks.TaskFiles.TryGetValue(id, out source), "任务制作源不存在。");
            }
            else
            {
                world ??= MapWorldCatalog.Load(root);
                var item = kind == "scene" ? world.Scenes[id] : kind == "npc" ? world.Occurrences[id] : null;
                source = item?.Value<string>("sourceFile"); MapRuleEvaluator.Need(!string.IsNullOrEmpty(source), "尚未定位制作源，请先刷新来源目录。");
            }
            string file = MapProjectFiles.Resolve(root, source), entry = file;
            MapRuleEvaluator.Need(File.Exists(file), "制作源文件不存在。");
            if (Path.GetFileName(file) == "DOMDocument.xml")
            {
                var xfl = Directory.EnumerateFiles(Path.GetDirectoryName(file), "*.xfl", SearchOption.TopDirectoryOnly).ToArray();
                entry = xfl.Length == 1 ? xfl[0] : Path.GetDirectoryName(file);
            }
            MapProjectFiles.PlainPath(entry);
            return new JObject { ["sourceFile"] = source, ["path"] = file, ["entry"] = entry };
        }
        private void ValidateUndo(JObject record)
        {
            var mapFile = ((JArray)record["files"]).OfType<JObject>().Single(f => (string)f["path"] == MapDefinition.RelativePath);
            var definition = MapDefinition.Parse(MapChangeJournal.Body(mapFile, "before"));
            if (definition.Value<int>("version") != 2) return;
            var overrides = ((JArray)record["files"]).OfType<JObject>().Where(f => ((string)f["path"]).StartsWith("data/task/", StringComparison.Ordinal))
                .ToDictionary(f => (string)f["path"], f => MapChangeJournal.Body(f, "before"), StringComparer.Ordinal);
            var tasks = MapTaskCatalog.Load(root, overrides); tasks.ValidateBindings(definition);
            MapAuthoringPlan.ValidateTaskReferences(definition, tasks.Tasks);
            var referenced = MapAssetCandidates.ReferencedUrls(definition);
            foreach (JObject file in (JArray)record["files"])
                if ((string)file["beforeDigest"] == "" && ((string)file["path"]).StartsWith("launcher/web/assets/map/", StringComparison.Ordinal))
                    MapRuleEvaluator.Need(!referenced.Contains(((string)file["path"]).Substring("launcher/web/".Length)), "新增图片仍被其他地图内容引用，不能删除。");
            MapAssetCandidates.RequireNoExternalReferences(root, ((JArray)record["files"]).OfType<JObject>()
                .Where(file => (string)file["beforeDigest"] == "" && ((string)file["path"]).StartsWith("launcher/web/assets/map/", StringComparison.Ordinal))
                .Select(file => ((string)file["path"]).Substring("launcher/web/".Length)));
        }
        private JObject UndoLegacy(JObject receipt)
        {
            byte[] bytes = MapProjectFiles.Read(root, MapDefinition.RelativePath); string digest = MapDefinition.Hash(bytes);
            if (digest != (string)receipt["beforeDigest"])
            {
                CheckDigest(digest, (string)receipt["afterDigest"]);
                byte[] restore = Convert.FromBase64String((string)receipt["beforeBytes"]);
                CheckDigest(MapDefinition.Hash(restore), (string)receipt["beforeDigest"]); MapDefinition.Parse(restore);
                MapProjectFiles.Atomic(file, restore);
            }
            return Query((string)receipt["operationId"]);
        }
        private JObject Query(string id)
        {
            var receipt = journal.Read(id); if (receipt == null) return new JObject { ["state"] = "not_found" };
            if ((string)receipt["schema"] == MapChangeJournal.Schema)
            {
                var state = journal.State(receipt);
                if ((string)state["state"] == "partial" || (string)state["state"] == "recovery_required") return state;
                var current = ReadCore();
                foreach (var p in state.Properties()) current[p.Name] = p.Value.DeepClone();
                return current;
            }
            var value = ReadCore(); string digest = (string)value["digest"];
            value["operationId"] = id; value["state"] = digest == (string)receipt["afterDigest"] ? "applied" : digest == (string)receipt["beforeDigest"] ? "original" : "superseded";
            return value;
        }
        private static void CheckDigest(string actual, string expected, string message = null)
        {
            if (string.IsNullOrEmpty(expected) || !string.Equals(actual, expected, StringComparison.Ordinal))
                throw new IOException(message ?? "地图配置已被修改，请重新读取；当前草稿保留供对比，撤回不会覆盖后续修改。");
        }
    }
}
