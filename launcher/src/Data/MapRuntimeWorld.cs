using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>玩家运行时只读取发布 SWF，不依赖作者的 XFL/FLA 或派生来源索引。</summary>
    public sealed class MapRuntimeWorld
    {
        public readonly JObject Occurrences = new JObject();
        public readonly JObject UnreadyLocations = new JObject();
        public readonly Dictionary<string, string> SourceHashes = new Dictionary<string, string>(StringComparer.Ordinal);
        public MapRuntimeWorld(string root, JObject definition, bool strict = false, Action<string> warn = null)
        {
            const string mainPath = "CRAZYFLASHER7MercenaryEmpire.swf";
            MapSwfLinkages main = null;
            try
            {
                main = MapSwfLinkages.Read(root, mainPath);
                SourceHashes[mainPath] = main.Digest;
            }
            catch (Exception ex) when (!strict)
            {
                warn?.Invoke("主 SWF 链接检查降级（" + mainPath + "）：" + ex.Message);
            }
            var sources = new Dictionary<string, MapSwfLinkages>(StringComparer.Ordinal);
            var readyLocations = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in ((JObject)definition["locations"]).Properties())
            {
                var location = (JObject)property.Value; var binding = location["sceneBinding"] as JObject;
                try
                {
                    MapRuleEvaluator.Need(binding != null, "地点尚未生成发布绑定，请通过地图工作台重新应用：" + (string)location["label"]);
                    string swf = (string)binding["sourceSwf"], linkage = (string)binding["linkage"];
                    if (!sources.TryGetValue(swf, out var source)) { source = MapSwfLinkages.Read(root, swf); sources[swf] = source; SourceHashes[swf] = source.Digest; }
                    MapRuleEvaluator.Need(source.Exports.TryGetValue(linkage, out var exports) && exports.Count == 1, "发布 SWF 中的地点导出缺失或冲突：" + (string)location["label"]);
                    if (main != null)
                        MapRuleEvaluator.Need(main.Imports.Any(import => Normalize(import.Url) == swf && source.Exports.TryGetValue(import.Name, out var anchor) && anchor.Count == 1), "主文件没有加载地点的发布素材库：" + (string)location["label"]);
                    readyLocations.Add(property.Name);
                }
                catch (Exception ex) when (!strict)
                {
                    UnreadyLocations[property.Name] = ex.Message;
                    warn?.Invoke("地点发布绑定降级（" + property.Name + "）：" + ex.Message);
                }
            }
            foreach (var p in ((JObject)definition["placements"]).Properties())
            {
                if (p.Value["worldBinding"] is not JObject binding) continue;
                var runtime = binding["runtime"] as JObject;
                if (runtime == null)
                {
                    if (strict) MapRuleEvaluator.Need(false, "NPC 驻点缺少发布绑定，请通过地图工作台重新应用。");
                    warn?.Invoke("NPC 驻点缺少发布绑定，回退原世界逻辑：" + p.Name);
                    continue;
                }
                string swf = (string)runtime["sourceSwf"], id = (string)binding["occurrenceId"];
                string locId = (string)p.Value["locationId"];
                string expectedScene = (string)definition["locations"]?[locId]?["sceneName"] ?? "";
                // 只核对场景导出可达与归属一致，不再因重发布 SWF 导致整包 SHA-256 变化而锁死现场 NPC。
                bool ready = sources.ContainsKey(swf) && readyLocations.Contains(locId) && (string)runtime["sceneKey"] == expectedScene;
                var record = (JObject)runtime.DeepClone(); record["ready"] = ready; record["sourceDigest"] = binding["sourceDigest"];
                record["occurrenceId"] = id; record["placementId"] = p.Name; record["npcId"] = p.Value["npcId"]; record["locationId"] = locId;
                record["reason"] = ready ? "" : "NPC 所在场景的发布导出不可用或场景归属不一致";
                if (Occurrences[id] != null)
                {
                    if (strict) MapRuleEvaluator.Need(false, "NPC 发布实例存在重复绑定。");
                    warn?.Invoke("NPC 发布实例重复绑定已跳过：" + id);
                    continue;
                }
                Occurrences[id] = record;
            }
        }
        private static string Normalize(string path)
        {
            path = path.Replace('\\', '/'); while (path.StartsWith("./", StringComparison.Ordinal)) path = path.Substring(2); return path;
        }
    }
}
