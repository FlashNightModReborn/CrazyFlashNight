using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Data
{
    /// <summary>图片先进入内容寻址候选，只有地图批次应用才写发布图片目录。</summary>
    public sealed class MapAssetCandidates
    {
        private readonly string root;
        private const string CandidateFolder = "tmp/map-workbench/assets/";
        private static readonly Regex Imported = new Regex(@"\Aassets/map/imported/([a-f0-9]{64})\.webp\z", RegexOptions.CultureInvariant);
        public MapAssetCandidates(string root) { this.root = root; }
        public JArray Recent()
        {
            string folder = MapProjectFiles.Resolve(root, CandidateFolder.TrimEnd('/')); var result = new JArray();
            if (!Directory.Exists(folder)) return result;
            foreach (string path in Directory.EnumerateFiles(folder, "*.json").OrderByDescending(File.GetLastWriteTimeUtc).Take(32))
            {
                string hash = Path.GetFileNameWithoutExtension(path);
                if (!Regex.IsMatch(hash, @"\A[a-f0-9]{64}\z")) continue;
                var metadata = MapProjectFiles.Json(MapProjectFiles.Read(root, CandidateFolder + hash + ".json", 64 * 1024));
                MapRuleEvaluator.Need(string.Equals(metadata.Value<string>("sha256"), hash, StringComparison.OrdinalIgnoreCase), "素材候选记录被修改。");
                metadata["assetUrl"] = "assets/map/imported/" + hash + ".webp"; metadata["candidate"] = true; result.Add(metadata);
            }
            return result;
        }
        public JArray Existing(JObject definition)
        {
            var result = new JArray();
            var urls = ReferencedUrls(definition).Concat((definition["assets"] as JObject)?.Properties().Select(p => p.Name) ?? Array.Empty<string>()).Distinct(StringComparer.Ordinal);
            foreach (string url in urls.OrderBy(x => x, StringComparer.Ordinal))
                try { var metadata = (JObject)Describe(url, definition, false)["metadata"]; metadata["ready"] = true; result.Add(metadata); }
                catch (Exception error) { result.Add(new JObject { ["assetUrl"] = url, ["width"] = 0, ["height"] = 0, ["ready"] = false, ["error"] = error.Message }); }
            return result;
        }
        public JObject Describe(string url, JObject definition = null, bool includePreview = true)
        {
            MapDomainDefinition.Asset(url); string relative = "launcher/web/" + url; JObject provenance = null;
            if (!File.Exists(MapProjectFiles.Resolve(root, relative)))
            {
                var match = Imported.Match(url); MapRuleEvaluator.Need(match.Success, "地图图片不存在。"); string hash = match.Groups[1].Value;
                relative = CandidateFolder + hash + ".webp";
                provenance = MapProjectFiles.Json(MapProjectFiles.Read(root, CandidateFolder + hash + ".json", 64 * 1024));
            }
            else provenance = (definition ?? MapDefinition.Load(root))["assets"]?[url] as JObject;
            byte[] bytes = MapProjectFiles.Read(root, relative, MapAssetCodec.MaxBytes); var metadata = MapAssetCodec.InspectPublished(bytes);
            if (provenance != null)
            {
                MapRuleEvaluator.Need((string)provenance["sha256"] == (string)metadata["sha256"], "素材来源已发生变化。");
                foreach (var p in provenance.Properties()) if (metadata[p.Name] == null) metadata[p.Name] = p.Value.DeepClone();
            }
            metadata["assetUrl"] = url;
            if (relative.StartsWith(CandidateFolder, StringComparison.Ordinal)) metadata["candidate"] = true;
            return new JObject { ["assetUrl"] = url, ["metadata"] = metadata, ["previewDataUrl"] = includePreview ? "data:image/webp;base64," + Convert.ToBase64String(bytes) : null };
        }
        public JObject StageFile(string source)
        {
            string path = Path.GetFullPath(source); MapProjectFiles.PlainPath(path);
            using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            MapRuleEvaluator.Need(input.Length > 0 && input.Length <= MapAssetCodec.MaxBytes, "导入图片超过边界。");
            var bytes = new byte[(int)input.Length]; input.ReadExactly(bytes);
            return Stage(bytes, new JObject { ["kind"] = "file", ["name"] = Path.GetFileName(path) });
        }
        public static void ValidatePublished(string root, JObject definition)
        {
            foreach (string url in ReferencedUrls(definition))
            {
                MapDomainDefinition.Asset(url);
                byte[] bytes = MapProjectFiles.Read(root, "launcher/web/" + url, MapAssetCodec.MaxBytes);
                var actual = MapAssetCodec.InspectPublished(bytes); var recorded = definition["assets"]?[url];
                MapRuleEvaluator.Need((string)recorded?["sha256"] == (string)actual["sha256"] && (int?)recorded?["width"] == (int)actual["width"] && (int?)recorded?["height"] == (int)actual["height"], "地图图片未登记或已变化，请通过地图工作台校验后重启：" + url);
            }
        }
        public JObject Crop(string url, string expectedDigest, JObject crop)
        {
            MapDomainDefinition.Asset(url); string relative = "launcher/web/" + url;
            if (!File.Exists(MapProjectFiles.Resolve(root, relative)))
            {
                var match = Imported.Match(url); MapRuleEvaluator.Need(match.Success, "地图图片不存在。");
                relative = CandidateFolder + match.Groups[1].Value + ".webp";
            }
            byte[] source = MapProjectFiles.Read(root, relative, MapAssetCodec.MaxBytes);
            MapRuleEvaluator.Need(MapDefinition.Hash(source) == expectedDigest, "裁切来源已变化，请重新选择图片。");
            byte[] cropped = MapAssetCodec.Crop(source, crop);
            return Stage(cropped, new JObject { ["kind"] = "crop", ["assetUrl"] = url, ["sourceDigest"] = expectedDigest, ["rect"] = crop.DeepClone() });
        }
        public JObject Stage(byte[] source, JObject provenance)
        {
            var image = MapAssetCodec.Convert(source, bytes => MapAssetTools.EncodeExact(root, bytes));
            string hash = image.Metadata.Value<string>("sha256").ToLowerInvariant(), url = "assets/map/imported/" + hash + ".webp";
            string imagePath = MapProjectFiles.Resolve(root, CandidateFolder + hash + ".webp");
            string metadataPath = MapProjectFiles.Resolve(root, CandidateFolder + hash + ".json");
            bool reused = File.Exists(imagePath) && File.Exists(metadataPath);
            if (File.Exists(imagePath)) MapRuleEvaluator.Need(MapDefinition.Hash(File.ReadAllBytes(imagePath)) == image.Metadata.Value<string>("sha256"), "图片候选已被外部修改。");
            else MapProjectFiles.Atomic(imagePath, image.Bytes);
            image.Metadata["source"] = provenance.DeepClone(); image.Metadata["assetUrl"] = url;
            if (!File.Exists(metadataPath)) MapProjectFiles.Atomic(metadataPath, MapDefinition.Bytes(image.Metadata));
            var metadata = MapProjectFiles.Json(MapProjectFiles.Read(root, CandidateFolder + hash + ".json", 64 * 1024));
            return new JObject { ["assetUrl"] = url, ["metadata"] = metadata, ["reused"] = reused, ["previewDataUrl"] = "data:image/webp;base64," + Convert.ToBase64String(image.Bytes) };
        }
        public static HashSet<string> ReferencedUrls(JObject definition)
        {
            var urls = new HashSet<string>(StringComparer.Ordinal);
            foreach (var page in MapDefinition.Pages(definition))
            {
                if (page["backgroundAssetUrl"]?.Type == JTokenType.String && (string)page["backgroundAssetUrl"] != "") urls.Add((string)page["backgroundAssetUrl"]);
                foreach (JObject item in ((JArray)page["sceneVisuals"]).Concat((JArray)page["staticAvatars"]).Concat(page["dynamicAvatars"] as JArray ?? new JArray()))
                {
                    if (item["assetUrl"]?.Type == JTokenType.String) urls.Add((string)item["assetUrl"]);
                    if (item["variants"] is JArray variants) foreach (var variant in variants) urls.Add((string)variant["assetUrl"]);
                    if ((string)item["kind"] == "roommateGender") { urls.Add("assets/map/roommate-male.webp"); urls.Add("assets/map/roommate-female.webp"); }
                }
            }
            return urls;
        }
        public static void RequireNoExternalReferences(string root, IEnumerable<string> assetUrls)
        {
            var urls = assetUrls.Distinct(StringComparer.Ordinal).ToArray(); if (urls.Length == 0) return;
            var extensions = new HashSet<string>(new[] { ".js", ".ts", ".css", ".html", ".json", ".xml" }, StringComparer.OrdinalIgnoreCase);
            long totalBytes = 0; int count = 0;
            void Scan(string directory, int depth)
            {
                MapRuleEvaluator.Need(depth <= 16, "素材共享引用扫描层级过深，保留图片并停止撤回。"); MapProjectFiles.PlainPath(directory);
                foreach (string entry in Directory.EnumerateFileSystemEntries(directory))
                {
                    MapRuleEvaluator.Need(++count <= 50000, "素材共享引用扫描条目过多，保留图片并停止撤回。");
                    if (Directory.Exists(entry))
                    {
                        if (!new[] { "node_modules", "bin", "obj", ".git" }.Contains(Path.GetFileName(entry))) Scan(entry, depth + 1);
                        continue;
                    }
                    if (!extensions.Contains(Path.GetExtension(entry))) continue;
                    string relative = Path.GetRelativePath(root, entry).Replace('\\', '/');
                    if (relative == MapDefinition.RelativePath) continue; // 地图按撤回后的结构化引用检查，来源元数据不算消费者。
                    byte[] bytes = MapProjectFiles.Read(root, relative, 16 * 1024 * 1024); totalBytes += bytes.Length;
                    MapRuleEvaluator.Need(totalBytes <= 256L * 1024 * 1024, "素材共享引用扫描超过大小边界，保留图片并停止撤回。");
                    string text = MapDefinition.Utf8.GetString(bytes);
                    foreach (string url in urls)
                        MapRuleEvaluator.Need(!text.Contains(url, StringComparison.OrdinalIgnoreCase) && !text.Contains(url.Substring("assets/map/".Length), StringComparison.OrdinalIgnoreCase),
                            "新增图片已被其他内容引用，保留图片并停止撤回：" + relative);
                }
            }
            foreach (string folder in new[] { "data", "launcher/web" })
            {
                string directory = MapProjectFiles.Resolve(root, folder); if (Directory.Exists(directory)) Scan(directory, 0);
            }
        }
        public (JArray NewFiles, JObject PreviewData, JArray Catalogue) Resolve(JObject definition)
        {
            var files = new JArray(); var previews = new JObject(); var catalogue = new JArray();
            if (definition["assets"] == null) definition["assets"] = new JObject();
            foreach (string url in ReferencedUrls(definition).OrderBy(s => s, StringComparer.Ordinal))
            {
                MapDomainDefinition.Asset(url);
                string relative = "launcher/web/" + url, file = MapProjectFiles.Resolve(root, relative);
                byte[] bytes; JObject metadata;
                if (File.Exists(file))
                {
                    bytes = MapProjectFiles.Read(root, relative, MapAssetCodec.MaxBytes); metadata = MapAssetCodec.InspectPublished(bytes);
                    if (definition["assets"][url] is JObject recorded) MapRuleEvaluator.Need((string)recorded["sha256"] == (string)metadata["sha256"], "已登记素材字节发生变化：" + url);
                }
                else
                {
                    var match = Imported.Match(url); MapRuleEvaluator.Need(match.Success, "地图素材不存在：" + url);
                    string hash = match.Groups[1].Value;
                    bytes = MapProjectFiles.Read(root, CandidateFolder + hash + ".webp", MapAssetCodec.MaxBytes);
                    metadata = MapProjectFiles.Json(MapProjectFiles.Read(root, CandidateFolder + hash + ".json", 64 * 1024));
                    var actual = MapAssetCodec.InspectPublished(bytes);
                    MapRuleEvaluator.Need(string.Equals((string)actual["sha256"], hash, StringComparison.OrdinalIgnoreCase) && (string)metadata["sha256"] == (string)actual["sha256"] &&
                        (int)metadata["width"] == (int)actual["width"] && (int)metadata["height"] == (int)actual["height"], "地图候选图片与元数据不一致。");
                    definition["assets"][url] = metadata.DeepClone();
                    files.Add(MapChangeJournal.FileChange(relative, null, bytes));
                    previews[url] = "data:image/webp;base64," + Convert.ToBase64String(bytes);
                }
                var item = (JObject)metadata.DeepClone(); item["assetUrl"] = url;
                if (definition["assets"][url] is JObject authored)
                    foreach (var p in authored.Properties()) if (item[p.Name] == null) item[p.Name] = p.Value.DeepClone();
                definition["assets"][url] = item.DeepClone();
                catalogue.Add(item);
            }
            MapRuleEvaluator.Need(previews.Properties().Sum(p => ((string)p.Value).Length) <= 24 * 1024 * 1024, "待预览图片总量过大，请分批应用。");
            return (files, previews, catalogue);
        }
    }
}
