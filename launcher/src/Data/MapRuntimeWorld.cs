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
        public readonly Dictionary<string, string> SourceHashes = new Dictionary<string, string>(StringComparer.Ordinal);
        public MapRuntimeWorld(string root, JObject definition)
        {
            const string mainPath = "CRAZYFLASHER7MercenaryEmpire.swf";
            var main = MapSwfLinkages.Read(root, mainPath); SourceHashes[mainPath] = main.Digest;
            var sources = new Dictionary<string, MapSwfLinkages>(StringComparer.Ordinal);
            foreach (var property in ((JObject)definition["locations"]).Properties())
            {
                var location = (JObject)property.Value; var binding = location["sceneBinding"] as JObject;
                MapRuleEvaluator.Need(binding != null, "地点尚未生成发布绑定，请通过地图工作台重新应用：" + (string)location["label"]);
                string swf = (string)binding["sourceSwf"], linkage = (string)binding["linkage"];
                if (!sources.TryGetValue(swf, out var source)) { source = MapSwfLinkages.Read(root, swf); sources[swf] = source; SourceHashes[swf] = source.Digest; }
                MapRuleEvaluator.Need(source.Exports.TryGetValue(linkage, out var exports) && exports.Count == 1, "发布 SWF 中的地点导出缺失或冲突：" + (string)location["label"]);
                MapRuleEvaluator.Need(main.Imports.Any(import => Normalize(import.Url) == swf && source.Exports.TryGetValue(import.Name, out var anchor) && anchor.Count == 1), "主文件没有加载地点的发布素材库：" + (string)location["label"]);
            }
            foreach (var p in ((JObject)definition["placements"]).Properties())
            {
                if (p.Value["worldBinding"] is not JObject binding) continue;
                var runtime = binding["runtime"] as JObject;
                MapRuleEvaluator.Need(runtime != null, "NPC 驻点缺少发布绑定，请通过地图工作台重新应用。");
                string swf = (string)runtime["sourceSwf"], id = (string)binding["occurrenceId"];
                bool ready = sources.TryGetValue(swf, out var source) && source.Digest == (string)runtime["swfSha256"];
                var record = (JObject)runtime.DeepClone(); record["ready"] = ready; record["sourceDigest"] = binding["sourceDigest"];
                record["occurrenceId"] = id; record["placementId"] = p.Name; record["npcId"] = p.Value["npcId"]; record["locationId"] = p.Value["locationId"];
                record["reason"] = ready ? "" : "NPC 的发布 SWF 已变化，请刷新来源绑定后重启";
                MapRuleEvaluator.Need(Occurrences[id] == null, "NPC 发布实例存在重复绑定。"); Occurrences[id] = record;
            }
        }
        private static string Normalize(string path)
        {
            path = path.Replace('\\', '/'); while (path.StartsWith("./", StringComparison.Ordinal)) path = path.Substring(2); return path;
        }
    }
}
