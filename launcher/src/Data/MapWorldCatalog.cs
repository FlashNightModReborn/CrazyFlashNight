using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>由现役场景环境、已 Include 的源和实际 SWF Import/Export 闭包发现可绑定目标。</summary>
    public sealed class MapWorldCatalog
    {
        public readonly JObject Scenes = new JObject(), Occurrences = new JObject();
        public readonly JArray AssetSources = new JArray();
        private const string MainSwf = "CRAZYFLASHER7MercenaryEmpire.swf";
        private static string Attribute(XElement element, string name) => (string)element.Attribute(name) ?? "";
        private static string Key(string prefix, string value) => prefix + MapDefinition.Hash(MapDefinition.Utf8.GetBytes(value)).Substring(0, 24).ToLowerInvariant();

        public static MapWorldCatalog Load(string root)
        {
            var result = new MapWorldCatalog();
            var environments = MapProjectFiles.Xml(MapProjectFiles.Read(root, "data/environment/scene_environment.xml"));
            var map = MapProjectFiles.Xml(MapProjectFiles.Read(root, "data/items/asset_source_map.xml"));
            var sourceMap = map.Root.Elements("asset").ToLookup(e => Attribute(e, "id"), StringComparer.Ordinal);
            var mainLinks = MapSwfLinkages.Read(root, MainSwf);
            using var mainSource = new MapFlashSource(root, MainSwf);
            var placedImports = mainSource.Reachable(mainSource.Document).Where(s => Attribute(s.Document.Root, "linkageImportForRS") == "true").ToArray();
            var packages = new Dictionary<string, MapFlashSource>(StringComparer.OrdinalIgnoreCase);
            var swfs = new Dictionary<string, MapSwfLinkages>(StringComparer.OrdinalIgnoreCase);
            try
            {
                foreach (var environment in environments.Root.Elements("Environment"))
                {
                    string scene = environment.Element("BackgroundURL")?.Value.Trim() ?? "";
                    if (scene == "") continue;
                    MapRuleEvaluator.Need(result.Scenes[scene] == null, "场景环境重复：" + scene);
                    string linkage = scene.StartsWith("地图-", StringComparison.Ordinal) ? scene : "基地场景-" + scene;
                    var record = new JObject { ["sceneKey"] = scene, ["linkage"] = linkage, ["sceneKind"] = scene.StartsWith("地图-", StringComparison.Ordinal) ? "outdoor" : "base", ["ready"] = false };
                    result.Scenes[scene] = record;
                    try
                    {
                        var found = sourceMap[linkage].SelectMany(e => e.Attribute("swf") != null ? new[] { Attribute(e, "swf") } : e.Elements("source").Select(s => Attribute(s, "swf")))
                            .Where(s => s != "").Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
                        MapRuleEvaluator.Need(found.Length == 1, "来源索引未唯一定位场景 SWF。");
                        string swf = found[0].Replace('\\', '/');
                        MapRuleEvaluator.Need(swf.StartsWith("flashswf/levels/", StringComparison.Ordinal) && swf.EndsWith(".swf", StringComparison.OrdinalIgnoreCase), "场景来源不在现役关卡素材目录。");
                        record["sourceSwf"] = swf;
                        if (!swfs.TryGetValue(swf, out var published)) { published = MapSwfLinkages.Read(root, swf); swfs[swf] = published; }
                        MapRuleEvaluator.Need(published.Exports.TryGetValue(linkage, out var ids) && ids.Count == 1, "已发布 SWF 未唯一导出该场景链接。");
                        if (!packages.TryGetValue(swf, out var source)) { source = new MapFlashSource(root, swf); packages[swf] = source; }
                        var symbol = source.Export(linkage);
                        record["sourceFile"] = source.SourcePath; record["symbolName"] = symbol.Name;
                        var anchors = placedImports.Where(s => NormalizeImport(root, MainSwf, Attribute(s.Document.Root, "linkageURL")) == swf).ToArray();
                        MapRuleEvaluator.Need(anchors.Any(anchor => mainLinks.Imports.Any(i => NormalizeImport(root, MainSwf, i.Url) == swf && i.Name == Attribute(anchor.Document.Root, "linkageIdentifier")) &&
                            published.Exports.TryGetValue(Attribute(anchor.Document.Root, "linkageIdentifier"), out var exports) && exports.Count == 1), "主文件未闭合加载该场景素材库。");
                        var reachable = source.Reachable(symbol.Document).Prepend(symbol).GroupBy(s => s.Name, StringComparer.Ordinal).Select(g => g.First()).ToArray();
                        string digest = MapDefinition.Hash(MapDefinition.Utf8.GetBytes(mainLinks.Digest + "\n" + published.Digest + "\n" + source.DocumentDigest + "\n" +
                            string.Join("\n", reachable.OrderBy(s => s.Name, StringComparer.Ordinal).Select(s => s.Name + " " + s.Digest))));
                        record["sourceDigest"] = digest; record["swfSha256"] = published.Digest; record["ready"] = true; record["reason"] = "源 Include、场景导出与主文件加载闭包均已核对";
                        result.FindOccurrences(scene, swf, published.Digest, source, symbol.Name, reachable, digest);
                    }
                    catch (Exception ex) { record["reason"] = ex.Message; }
                }
                foreach (var pair in swfs.OrderBy(p => p.Key, StringComparer.Ordinal)) foreach (var export in pair.Value.Exports.OrderBy(p => p.Key, StringComparer.Ordinal))
                    if (export.Value.Count == 1 && pair.Value.SpriteFrames.TryGetValue(export.Value[0], out int frames))
                        result.AssetSources.Add(new JObject { ["sourceSwf"] = pair.Key, ["linkage"] = export.Key, ["sourceDigest"] = pair.Value.Digest,
                            ["frameCount"] = frames, ["ready"] = frames > 0 && pair.Value.Imports.Count == 0,
                            ["reason"] = pair.Value.Imports.Count == 0 ? "已发现的发布元件；可选择静态帧提取" : "素材库依赖外部链接，请从制作源导出图片后导入" });
            }
            finally { foreach (var package in packages.Values) package.Dispose(); }
            foreach (var group in result.Occurrences.Properties().GroupBy(p => (string)p.Value["sceneKey"] + "\n" + (string)p.Value["runtimeName"] + "\n" + (string)p.Value["instanceName"], StringComparer.Ordinal))
                if (group.Count() > 1) foreach (var p in group) { p.Value["ready"] = false; p.Value["reason"] = "同场景存在同名未区分实例，须先在来源中明确实例名称"; }
            return result;
        }
        private static string NormalizeImport(string root, string sourceSwf, string url)
        {
            if (string.IsNullOrWhiteSpace(url) || url.Contains(':') || url.StartsWith('/') || url.StartsWith('\\')) return "";
            string file = Path.GetFullPath(Path.Combine(root, Path.GetDirectoryName(sourceSwf), url.Replace('/', Path.DirectorySeparatorChar)));
            string relative = Path.GetRelativePath(root, file).Replace('\\', '/');
            return relative.StartsWith("../", StringComparison.Ordinal) ? "" : relative;
        }

        private void FindOccurrences(string scene, string swf, string swfDigest, MapFlashSource source, string rootSymbol, MapFlashSource.Symbol[] reachable, string sceneDigest)
        {
            var counts = reachable.ToDictionary(s => s.Name, _ => 0, StringComparer.Ordinal); counts[rootSymbol] = 1;
            // 只需区分唯一/重复；重复父实例的歧义沿可达图传播，不把同一子元件去重成一个真实人物。
            for (int pass = 0; pass <= reachable.Length; pass++)
            {
                var next = reachable.ToDictionary(s => s.Name, _ => 0, StringComparer.Ordinal); next[rootSymbol] = 1;
                foreach (var parent in reachable)
                    foreach (var child in parent.Document.Descendants().Where(e => e.Name.LocalName == "DOMSymbolInstance"))
                    {
                        string name = Attribute(child, "libraryItemName");
                        if (next.ContainsKey(name)) next[name] = Math.Min(2, next[name] + counts[parent.Name]);
                    }
                bool same = counts.All(p => next[p.Key] == p.Value); counts = next; if (same) break;
            }
            foreach (var symbol in reachable)
            {
                int occurrence = 0;
                foreach (var instance in symbol.Document.Descendants().Where(e => e.Name.LocalName == "DOMSymbolInstance"))
                {
                    occurrence++;
                    string script = string.Join("\n", instance.Elements().Where(e => e.Name.LocalName == "Actionscript").Descendants().Where(e => e.Name.LocalName == "script").Select(e => e.Value));
                    if (!script.Contains("初始化NPC", StringComparison.Ordinal) && !script.Contains("NPCTaskCheck", StringComparison.Ordinal)) continue;
                    string instanceName = Attribute(instance, "name"), library = Attribute(instance, "libraryItemName");
                    var info = ReadNpcScript(script);
                    string runtimeName = info.Value<string>("名字") ?? "", taskName = info.Value<string>("任务名") ?? runtimeName;
                    string identity = scene + "\n" + symbol.Name + "\n" + library + "\n" + instanceName + "\n" + runtimeName + "\n" + taskName;
                    string id = Key("occ_", identity);
                    // 无显式实例名的重复源必须保留为歧义记录，不能被字典覆盖成一个人物。
                    if (Occurrences[id] != null) id = Key("occ_", identity + "\n" + occurrence);
                    bool repeated = counts[symbol.Name] > 1;
                    bool ready = info.Value<bool>("literalReady") && runtimeName != "" && !repeated;
                    Occurrences[id] = new JObject { ["occurrenceId"] = id, ["sceneKey"] = scene, ["sourceSwf"] = swf, ["swfSha256"] = swfDigest, ["sourceFile"] = source.SourcePath,
                        ["sourceEntry"] = symbol.Entry, ["symbolName"] = library, ["parentSymbol"] = symbol.Name, ["instanceName"] = instanceName,
                        ["runtimeName"] = runtimeName, ["taskName"] = taskName, ["dialogueName"] = info["对话名"] ?? runtimeName,
                        ["shopName"] = info["商店检索名"] ?? runtimeName, ["skillName"] = info["技能检索名"] ?? runtimeName,
                        ["scriptDigest"] = MapDefinition.Hash(MapDefinition.Utf8.GetBytes(script)),
                        ["sourceDigest"] = MapDefinition.Hash(MapDefinition.Utf8.GetBytes(sceneDigest + "\n" + identity + "\n" + script)),
                        ["ready"] = ready, ["reason"] = ready ? "标准初始化与唯一字面量人物身份已识别；剧情条件由工作台显式配置" : repeated ? "人物所在父元件被重复实例化，需先区分真实实例" : (string)info["reason"],
                        ["legacyScript"] = script.Length <= 4096 ? script : script.Substring(0, 4096) + "…" };
                }
            }
        }
        public void ValidateDefinition(JObject definition)
        {
            foreach (var p in ((JObject)definition["locations"]).Properties())
            {
                string sceneName = (string)p.Value["sceneName"]; var scene = Scenes[sceneName] as JObject;
                MapRuleEvaluator.Need(scene?.Value<bool>("ready") == true, "地点“" + (string)p.Value["label"] + "”的场景尚未就绪：" + (scene?.Value<string>("reason") ?? "未登记"));
                MapRuleEvaluator.Need((string)scene["sceneKind"] == (string)p.Value["sceneKind"], "地点场景类型与真实来源不一致。");
            }
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var p in ((JObject)definition["placements"]).Properties())
            {
                if (p.Value["worldBinding"] is not JObject binding) continue;
                string id = (string)binding["occurrenceId"]; var occurrence = Occurrences[id] as JObject;
                MapRuleEvaluator.Need(occurrence?.Value<bool>("ready") == true && (string)occurrence["sourceDigest"] == (string)binding["sourceDigest"], "驻点“" + (string)p.Value["label"] + "”的真实 NPC 来源缺失、变化或仍有歧义。");
                MapRuleEvaluator.Need(seen.Add(id), "同一真实 NPC 实例不能被多个驻点同时管理。");
                var location = definition["locations"][(string)p.Value["locationId"]]; var npc = definition["npcs"][(string)p.Value["npcId"]];
                MapRuleEvaluator.Need((string)occurrence["sceneKey"] == (string)location["sceneName"], "所选真实 NPC 不在该驻点绑定的场景。");
                MapRuleEvaluator.Need(((JArray)npc["runtimeNames"]).Concat((JArray)npc["aliases"]).Any(n => (string)n == (string)occurrence["taskName"]), "真实 NPC 的任务检索名不属于所选人物；显示名称不能代替身份绑定。");
            }
        }
        public void EnrichBindings(JObject definition)
        {
            foreach (var p in ((JObject)definition["locations"]).Properties())
            {
                var scene = Scenes[(string)p.Value["sceneName"]];
                MapRuleEvaluator.Need(scene?.Value<bool>("ready") == true, "所选场景尚未完成发布闭包。");
                p.Value["sceneKind"] = scene["sceneKind"].DeepClone();
                p.Value["sceneBinding"] = new JObject { ["sourceSwf"] = scene["sourceSwf"], ["linkage"] = scene["linkage"] };
            }
            ValidateDefinition(definition);
            foreach (var p in ((JObject)definition["placements"]).Properties())
            {
                if (p.Value["worldBinding"] is not JObject binding) continue;
                var occurrence = Occurrences[(string)binding["occurrenceId"]];
                var runtime = new JObject();
                foreach (string key in new[] { "sourceSwf", "swfSha256", "sceneKey", "runtimeName", "taskName", "instanceName" }) runtime[key] = occurrence[key].DeepClone();
                binding["runtime"] = runtime;
            }
            MapDefinition.Validate(definition);
        }

        private sealed class Token { public string Value; public bool String; public Token(string value, bool text = false) { Value = value; String = text; } }
        private static List<Token> Tokens(string source)
        {
            var tokens = new List<Token>(); int i = 0;
            while (i < source.Length)
            {
                char c = source[i++];
                if (char.IsWhiteSpace(c)) continue;
                if (c == '/' && i < source.Length && source[i] == '/') { while (i < source.Length && source[i] != '\n') i++; continue; }
                if (c == '/' && i < source.Length && source[i] == '*') { i++; int end = source.IndexOf("*/", i, StringComparison.Ordinal); if (end < 0) return new List<Token>(); i = end + 2; continue; }
                if (c == '\'' || c == '"')
                {
                    var text = new StringBuilder(); bool closed = false;
                    while (i < source.Length)
                    {
                        char v = source[i++]; if (v == c) { closed = true; break; }
                        if (v == '\\') { if (i >= source.Length) return new List<Token>(); v = source[i++]; if (v != '\\' && v != '\'' && v != '"') return new List<Token>(); }
                        text.Append(v);
                    }
                    if (!closed) return new List<Token>(); tokens.Add(new Token(text.ToString(), true)); continue;
                }
                if (char.IsLetterOrDigit(c) || c == '_' || c == '$')
                {
                    int start = i - 1; while (i < source.Length && (char.IsLetterOrDigit(source[i]) || source[i] == '_' || source[i] == '$')) i++;
                    tokens.Add(new Token(source.Substring(start, i - start))); continue;
                }
                tokens.Add(new Token(c.ToString()));
            }
            return tokens;
        }
        private static JObject ReadNpcScript(string source)
        {
            var tokens = Tokens(source); var result = new JObject();
            var fields = new[] { "名字", "任务名", "对话名", "商店检索名", "技能检索名" };
            var values = fields.ToDictionary(k => k, _ => new List<string>(), StringComparer.Ordinal);
            bool unknown = tokens.Count == 0, extraGuard = false; int init = -1, calls = 0;
            for (int i = 0; i < tokens.Count; i++)
            {
                var token = tokens[i]; if (token.String) continue;
                if (new[] { "if", "switch", "while", "for", "_visible" }.Contains(token.Value)) extraGuard = true;
                if (token.Value == "初始化NPC" && i > 1 && i + 3 < tokens.Count && tokens[i - 2].Value == "_root" && tokens[i + 1].Value == "(" && tokens[i + 2].Value == "this" && tokens[i + 3].Value == ")") { calls++; init = i; }
                if (!fields.Contains(token.Value) || i + 1 >= tokens.Count || tokens[i + 1].Value != "=") continue;
                if (i > 0 && tokens[i - 1].Value == "." && (i < 2 || tokens[i - 2].Value != "this")) continue;
                if (i + 3 >= tokens.Count || !tokens[i + 2].String || !new[] { ";", "}" }.Contains(tokens[i + 3].Value)) { unknown = true; continue; }
                if (init >= 0) unknown = true;
                values[token.Value].Add(tokens[i + 2].Value);
            }
            foreach (var field in fields)
            {
                var distinct = values[field].Distinct(StringComparer.Ordinal).ToArray();
                if (distinct.Length == 1) result[field] = distinct[0];
                if (distinct.Length > 1) unknown = true;
            }
            result["literalReady"] = !unknown && !extraGuard && calls == 1 && result["名字"] != null;
            result["reason"] = calls != 1 ? "自定义初始化待解析；不会冒充标准 NPC 接入" : extraGuard ? "来源还有独立脚本门控；请先明确其与驻点条件的关系" : "人物身份含动态表达式或初始化顺序不明确";
            return result;
        }
        public JObject Json() => new JObject { ["scenes"] = Scenes.DeepClone(), ["occurrences"] = Occurrences.DeepClone(), ["assetSources"] = AssetSources.DeepClone() };
    }
}
