using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>从已发现的发布 linkage 提取明确静态帧；数字定位只在同一源摘要下临时使用。</summary>
    public static class MapSwfAssetExtractor
    {
        public static JObject Extract(string root, MapWorldCatalog world, JObject request)
        {
            MapRuleEvaluator.Keys(request, "op", "sourceSwf", "sourceDigest", "linkage", "frame", "zoom");
            string swf = MapRuleEvaluator.Text(request, "sourceSwf", 220), digest = MapRuleEvaluator.Text(request, "sourceDigest", 64), linkage = MapRuleEvaluator.Text(request, "linkage", 160);
            var source = world.AssetSources.OfType<JObject>().SingleOrDefault(x => (string)x["sourceSwf"] == swf && (string)x["linkage"] == linkage && (string)x["sourceDigest"] == digest);
            MapRuleEvaluator.Need(source != null && source.Value<bool>("ready"), "提取来源已变化、未就绪或不是已发现的导出元件，请刷新来源目录。");
            int frame = checked((int)MapRuleEvaluator.Integer(request["frame"], "静态帧")); double zoom = MapDefinition.Number(request["zoom"]);
            MapRuleEvaluator.Need(frame > 0 && frame <= source.Value<int>("frameCount") && frame <= 512 && zoom >= .125 && zoom <= 2, "静态帧或提取倍率超出边界。");
            var published = MapSwfLinkages.Read(root, swf);
            MapRuleEvaluator.Need(published.Digest == digest && published.Exports.TryGetValue(linkage, out var ids) && ids.Count == 1 && published.Imports.Count == 0, "发布来源已变化或依赖外部链接，请先从制作源导出静态图片。");
            int spriteId = published.Exports[linkage][0];
            byte[] frozen = MapProjectFiles.Read(root, swf, 64 * 1024 * 1024);
            MapRuleEvaluator.Need(MapDefinition.Hash(frozen) == digest, "提取源在读取期间发生变化。");
            string folder = MapProjectFiles.Resolve(root, "tmp/map-workbench/swf-extract/" + Guid.NewGuid().ToString("N"));
            MapRuleEvaluator.Need(!Directory.Exists(folder), "临时提取目录冲突。"); Directory.CreateDirectory(folder);
            try
            {
                string input = Path.Combine(folder, "source.swf"), output = Path.Combine(folder, "output"); MapProjectFiles.Atomic(input, frozen);
                MapAssetTools.Run(MapProjectFiles.Resolve(root, "tools/ffdec/ffdec-cli.exe"), new[] {
                    "-config", "parallelSpeedUp=false", "-onerror", "abort", "-exportTimeout", "45", "-ignorebackground", "-zoom", zoom.ToString(CultureInfo.InvariantCulture),
                    "-select", frame.ToString(CultureInfo.InvariantCulture), "-selectid", spriteId.ToString(CultureInfo.InvariantCulture), "-format", "sprite:png", "-export", "sprite", output, input }, root, 55);
                MapProjectFiles.PlainPath(output);
                var files = FindFrames(output, 0).ToArray();
                MapRuleEvaluator.Need(files.Length == 1 && Path.GetFileNameWithoutExtension(files[0]) == frame.ToString(CultureInfo.InvariantCulture), "导出没有唯一生成所选帧，未选择其他帧替代。");
                MapProjectFiles.PlainPath(files[0]);
                using var stream = new FileStream(files[0], FileMode.Open, FileAccess.Read, FileShare.Read);
                MapRuleEvaluator.Need(stream.Length > 0 && stream.Length <= MapAssetCodec.MaxBytes, "导出图片为空或过大，请降低倍率。");
                byte[] image = new byte[(int)stream.Length]; stream.ReadExactly(image); stream.Dispose();
                return new MapAssetCandidates(root).Stage(image, new JObject { ["kind"] = "swf", ["sourceSwf"] = swf, ["sourceDigest"] = digest, ["linkage"] = linkage,
                    ["frame"] = frame, ["zoom"] = zoom, ["locatorSpriteId"] = spriteId, ["note"] = "静态导出不执行场景脚本；SpriteId 仅属于上述源摘要" });
            }
            finally { ClearOwned(folder, folder, 0); }
        }
        private static IEnumerable<string> FindFrames(string directory, int depth)
        {
            MapRuleEvaluator.Need(depth < 8, "导出目录层级超出边界。"); MapProjectFiles.PlainPath(directory);
            var entries = Directory.EnumerateFileSystemEntries(directory).Take(1025).ToArray();
            MapRuleEvaluator.Need(entries.Length <= 1024, "导出目录条目超出边界。");
            foreach (string entry in entries)
            {
                MapProjectFiles.PlainPath(entry);
                if (Directory.Exists(entry)) { foreach (string file in FindFrames(entry, depth + 1)) yield return file; }
                else if (Path.GetExtension(entry).Equals(".png", StringComparison.OrdinalIgnoreCase)) yield return entry;
            }
        }
        private static void ClearOwned(string owner, string directory, int depth)
        {
            MapRuleEvaluator.Need(depth < 8 && (directory == owner || directory.StartsWith(owner + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)), "临时提取清理越界。");
            MapProjectFiles.PlainPath(directory);
            foreach (string entry in Directory.EnumerateFileSystemEntries(directory))
            {
                MapProjectFiles.PlainPath(entry);
                if (Directory.Exists(entry)) ClearOwned(owner, entry, depth + 1); else File.Delete(entry);
            }
            Directory.Delete(directory);
        }
    }
}
