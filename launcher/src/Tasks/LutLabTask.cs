using System;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using SkiaSharp;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// LUT 实验室桥（dev-only）。信封随既有面板 task 总线（bridge.js 惯例：
    /// { type:"task", task:"lutlab.*", callId, payload:{...} } → { type:"taskResult", ... }）：
    ///   task:"lutlab.grabFrame"，payload {}
    ///       → { ok/success:true, url, width, height }；原生回读未调色 BGRA，
    ///         C# 编码 PNG 写 tmp/lut-lab/frames/&lt;时间戳&gt;.png，url 走 cf7-lutlab vhost。
    ///   task:"lutlab.bakeXml"，payload { level:0..10, mode:"光照"|"夜视" }
    ///       → { ok/success:true, size:32, rgbaBase64 }（RGBA8 共 32768*4 字节，R 最快）。
    ///   task:"lutlab.bakeXmlSet"，payload { mode:"光照"|"夜视" }
    ///       → { ok/success:true, size:32, levels:[{level:0..9, rgbaBase64}×10] }（v2 集合烘焙）。
    ///   task:"lutlab.savePreset"，payload { name, mode, preset:{...}, levels:[{level, rgbaBase64}×10] }
    ///       → 写 tmp/lut-lab/presets/&lt;name&gt;/（preset.json + 10 cubes）+ 原子 upsert manifest.sets.json，
    ///         重读字节自检后回 {ok, name, dir, files, manifestEntry, levels}。只写 tmp/lut-lab/。
    /// Program.cs 无条件构造并注册（dev 面板配套，刘海「其他 ▸ 工具」开发者领地入口）；
    /// Web ingress 由 WebOverlayForm.IsLutLabIngressAllowed 按 task 名放行，cf7-lutlab vhost 无条件映射。
    /// </summary>
    public sealed class LutLabTask
    {
        internal const string TaskNameGrabFrame = "lutlab.grabFrame";
        internal const string TaskNameBakeXml = "lutlab.bakeXml";
        internal const string TaskNameBakeXmlSet = "lutlab.bakeXmlSet";
        internal const string TaskNameSavePreset = "lutlab.savePreset";
        internal const string VirtualHost = "cf7-lutlab";
        private readonly string _lutLabRoot;
        private readonly string _presetXmlPath;
        private readonly Func<byte[], WorldCompositorController.LutLabGrabResult> _grab;
        private readonly double _gamma;

        internal LutLabTask(string projectRoot,
            Func<byte[], WorldCompositorController.LutLabGrabResult> grab, double gamma)
        {
            _lutLabRoot = Path.Combine(projectRoot, "tmp", "lut-lab");
            _presetXmlPath = Path.Combine(projectRoot, "data", "environment", "color_engine_preset.xml");
            _grab = grab;
            _gamma = gamma;
        }

        internal static bool IsLutLabTaskName(string taskName)
        {
            return string.Equals(taskName, TaskNameGrabFrame, StringComparison.Ordinal)
                || string.Equals(taskName, TaskNameBakeXml, StringComparison.Ordinal)
                || string.Equals(taskName, TaskNameBakeXmlSet, StringComparison.Ordinal)
                || string.Equals(taskName, TaskNameSavePreset, StringComparison.Ordinal);
        }

        public void HandleAsync(JObject message, Action<string> respond)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                string taskName = message != null ? message.Value<string>("task") : null;
                try
                {
                    if (string.Equals(taskName, TaskNameGrabFrame, StringComparison.Ordinal))
                    {
                        respond(HandleGrabFrame());
                        return;
                    }
                    if (string.Equals(taskName, TaskNameBakeXml, StringComparison.Ordinal))
                    {
                        respond(HandleBakeXml(message.Value<JObject>("payload")));
                        return;
                    }
                    if (string.Equals(taskName, TaskNameBakeXmlSet, StringComparison.Ordinal))
                    {
                        respond(HandleBakeXmlSet(message.Value<JObject>("payload")));
                        return;
                    }
                    if (string.Equals(taskName, TaskNameSavePreset, StringComparison.Ordinal))
                    {
                        respond(HandleSavePreset(message.Value<JObject>("payload")));
                        return;
                    }
                    respond(BuildError(taskName, "unknown lutlab task"));
                }
                catch (Exception ex)
                {
                    LogManager.Log("[LutLab] Exception: " + ex);
                    if (string.Equals(taskName, TaskNameGrabFrame, StringComparison.Ordinal))
                        LogManager.Log("event=lutlab_grab_frame result=error error=exception");
                    respond(BuildError(taskName, "lutlab exception: " + ex.Message));
                }
            });
        }

        private string HandleGrabFrame()
        {
            byte[] buffer; int width, height; string error;
            if (!GrabLoop(out buffer, out width, out height, out error))
            {
                LogManager.Log("event=lutlab_grab_frame result=error error=" + error);
                return BuildError(TaskNameGrabFrame, error);
            }
            string name = WriteFramePng(buffer, width, height, null);
            var resp = new JObject();
            resp["ok"] = true; resp["success"] = true; resp["task"] = TaskNameGrabFrame;
            resp["url"] = "https://" + VirtualHost + "/frames/" + name;
            resp["width"] = width; resp["height"] = height;
            return resp.ToString(Formatting.None);
        }

        /// <summary>
        /// 入场预抓帧（dev 面板 LUT_LAB_TEST 分发路径，由 LauncherCommandRouter 经 Program.cs 接线调用）：
        /// 成功 → PNG 落 tmp/lut-lab/frames/ 并返回 cf7-lutlab url；失败 → null（error 码已记结构化日志）。
        /// 不抛异常给调用方之外的路径；异常由调用方（router）兜底。
        /// </summary>
        internal string TryGrabEntryFrameUrl()
        {
            byte[] buffer; int width, height; string error;
            if (!GrabLoop(out buffer, out width, out height, out error))
            {
                LogManager.Log("event=lutlab_grab_frame result=error error=" + error + " origin=panel_entry");
                return null;
            }
            string name = WriteFramePng(buffer, width, height, "panel_entry");
            return "https://" + VirtualHost + "/frames/" + name;
        }

        // 三次重试的 buffer 尺寸协商；所有失败路径给出可直接进结构化日志的 error 码。
        private bool GrabLoop(out byte[] buffer, out int width, out int height, out string error)
        {
            buffer = null; width = 0; height = 0;
            if (_grab == null) { error = "grab unavailable"; return false; }
            for (int attempt = 0; attempt < 3; attempt++)
            {
                var result = _grab(buffer);
                if (result.Code == NativeCompositorSession.GrabBufferTooSmall
                    && result.Width > 0 && result.Height > 0)
                {
                    buffer = new byte[checked(result.Width * result.Height * 4)];
                    continue;
                }
                if (result.Code == NativeCompositorSession.GrabOk && buffer != null)
                {
                    width = result.Width; height = result.Height; error = null;
                    return true;
                }
                error = GrabError(result.Code);
                return false;
            }
            error = "grab_failed:size_unstable";
            return false;
        }

        private string WriteFramePng(byte[] bgra, int width, int height, string origin)
        {
            string framesDir = Path.Combine(_lutLabRoot, "frames");
            Directory.CreateDirectory(framesDir);
            string name = "frame-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff", CultureInfo.InvariantCulture) + ".png";
            string path = Path.Combine(framesDir, name);
            if (File.Exists(path))
            {
                name = "frame-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff", CultureInfo.InvariantCulture)
                    + "-" + Guid.NewGuid().ToString("N").Substring(0, 6) + ".png";
                path = Path.Combine(framesDir, name);
            }
            // 原生缓冲是 BGRA8；Skia Bgra8888 原样承载，PNG 编码时按 RGBA 写出。
            var info = new SKImageInfo(width, height, SKColorType.Bgra8888, SKAlphaType.Unpremul);
            using (var data = SKData.CreateCopy(bgra))
            using (var pixmap = new SKPixmap(info, data.Data, info.RowBytes))
            using (var encoded = pixmap.Encode(SKEncodedImageFormat.Png, 100))
            {
                File.WriteAllBytes(path, encoded.ToArray());
            }
            LogManager.Log("event=lutlab_grab_frame result=ok file=" + name + " size=" + width + "x" + height
                + (origin != null ? " origin=" + origin : ""));
            return name;
        }

        private string HandleBakeXml(JObject payload)
        {
            if (payload == null) return BuildError(TaskNameBakeXml, "missing payload");
            JToken levelToken = payload["level"];
            if (levelToken == null
                || (levelToken.Type != JTokenType.Integer && levelToken.Type != JTokenType.Float))
                return BuildError(TaskNameBakeXml, "level must be a number in [0,10]");
            double level = levelToken.Value<double>();
            if (!double.IsFinite(level) || level < 0 || level > 10)
                return BuildError(TaskNameBakeXml, "level out of range [0,10]: " + levelToken.ToString(Formatting.None));
            string mode = payload.Value<string>("mode");
            if (string.IsNullOrEmpty(mode)) return BuildError(TaskNameBakeXml, "missing mode");

            string resolvedMode;
            byte[] rgba;
            try
            {
                rgba = WorldLutBaker.BakeFromXml(_presetXmlPath, mode, level, _gamma, out resolvedMode);
            }
            catch (Exception ex)
            {
                return BuildError(TaskNameBakeXml, "preset xml unavailable: " + ex.Message);
            }
            if (resolvedMode == null) return BuildError(TaskNameBakeXml, "unknown mode: " + mode);
            if (rgba == null) return BuildError(TaskNameBakeXml, "interpolation rejected (non-finite or missing level)");

            var resp = new JObject();
            resp["ok"] = true; resp["success"] = true; resp["task"] = TaskNameBakeXml;
            resp["mode"] = resolvedMode; resp["level"] = level;
            resp["size"] = WorldLutBaker.LutSize;
            resp["rgbaBase64"] = Convert.ToBase64String(rgba);
            return resp.ToString(Formatting.None);
        }

        /// <summary>
        /// 集合烘焙（v2）：一次返回某模式 0–9 整数级共 10 档 LUT（回包约 1.7MB base64）。
        /// 信封 {ok, task, mode, size:32, levels:[{level, rgbaBase64}×10]}；级别逐一复用
        /// WorldLutBaker.BakeFromXml（与单档 lutlab.bakeXml 同公式同 gamma）。
        /// </summary>
        private string HandleBakeXmlSet(JObject payload)
        {
            string mode = payload != null ? payload.Value<string>("mode") : null;
            if (string.IsNullOrEmpty(mode)) return BuildError(TaskNameBakeXmlSet, "missing mode");
            var levels = new JArray();
            string resolvedMode = null;
            for (int level = 0; level <= 9; level++)
            {
                string resolved;
                byte[] rgba;
                try
                {
                    rgba = WorldLutBaker.BakeFromXml(_presetXmlPath, mode, level, _gamma, out resolved);
                }
                catch (Exception ex)
                {
                    return BuildError(TaskNameBakeXmlSet, "preset xml unavailable: " + ex.Message);
                }
                if (resolved == null) return BuildError(TaskNameBakeXmlSet, "unknown mode: " + mode);
                if (rgba == null)
                    return BuildError(TaskNameBakeXmlSet, "interpolation rejected at level " + level);
                resolvedMode = resolved;
                var entry = new JObject();
                entry["level"] = level;
                entry["rgbaBase64"] = Convert.ToBase64String(rgba);
                levels.Add(entry);
            }
            var resp = new JObject();
            resp["ok"] = true; resp["success"] = true; resp["task"] = TaskNameBakeXmlSet;
            resp["mode"] = resolvedMode; resp["size"] = WorldLutBaker.LutSize;
            resp["levels"] = levels;
            LogManager.Log("event=lutlab_bake_xml_set mode=" + resolvedMode + " levels=" + levels.Count);
            return resp.ToString(Formatting.None);
        }

        /// <summary>
        /// 预设保存（v2 三段式工作流③）：payload { name, mode:"光照"|"夜视", preset:{...}, levels:[{level, rgbaBase64}×10] }
        /// 写 tmp/lut-lab/presets/&lt;name&gt;/preset.json + {mode}-&lt;0..9&gt;.cube（WorldLutBaker.WriteCube 同序列化），
        /// 原子 upsert tmp/lut-lab/sets/manifest.sets.json（tmp 文件 + Replace/Move），
        /// 全部写出后逐文件重读字节自检。只写 tmp/lut-lab/，不碰 data/ 与生产配置（生产导入是后续人工步骤）。
        /// 回包 {ok, name, dir, files, manifestEntry, levels:[{level, rgbaBase64}]}（levels 即自检通过的内容）。
        /// </summary>
        private string HandleSavePreset(JObject payload)
        {
            if (payload == null) return BuildError(TaskNameSavePreset, "missing payload");
            string name = payload.Value<string>("name");
            string nameError;
            if (!TryValidatePresetName(name, out nameError))
                return BuildError(TaskNameSavePreset, nameError);
            string mode = payload.Value<string>("mode");
            if (!string.Equals(mode, "光照", StringComparison.Ordinal)
                && !string.Equals(mode, "夜视", StringComparison.Ordinal))
                return BuildError(TaskNameSavePreset, "mode must be 光照 or 夜视: " + (mode ?? "<null>"));
            JObject preset = payload["preset"] as JObject;
            if (preset == null) return BuildError(TaskNameSavePreset, "missing preset object");
            JArray levels = payload["levels"] as JArray;
            if (levels == null || levels.Count != 10)
                return BuildError(TaskNameSavePreset, "levels must be 10 entries");

            var levelLuts = new byte[10][];
            for (int i = 0; i < 10; i++)
            {
                JObject entry = levels[i] as JObject;
                if (entry == null) return BuildError(TaskNameSavePreset, "levels[" + i + "] not an object");
                if (entry.Value<int?>("level") != i)
                    return BuildError(TaskNameSavePreset, "levels[" + i + "] level mismatch");
                byte[] rgba;
                try { rgba = Convert.FromBase64String(entry.Value<string>("rgbaBase64") ?? ""); }
                catch (Exception) { return BuildError(TaskNameSavePreset, "levels[" + i + "] rgbaBase64 invalid"); }
                if (rgba.Length != WorldLutBaker.RgbaBytes)
                    return BuildError(TaskNameSavePreset, "levels[" + i + "] byte count " + rgba.Length);
                levelLuts[i] = rgba;
            }

            string presetDir = Path.Combine(_lutLabRoot, "presets", name);
            Directory.CreateDirectory(presetDir);
            string presetJsonPath = Path.Combine(presetDir, "preset.json");
            string presetJsonText = preset.ToString(Formatting.Indented);
            File.WriteAllText(presetJsonPath, presetJsonText + "\n", new UTF8Encoding(false));

            var files = new string[10];
            var cubeTexts = new string[10];
            for (int i = 0; i < 10; i++)
            {
                string fileName = mode + "-" + i + ".cube";
                WorldLutBaker.WriteCube(Path.Combine(presetDir, fileName),
                    name + " (" + mode + ", lut-lab preset) L" + i, levelLuts[i]);
                files[i] = fileName;
                cubeTexts[i] = File.ReadAllText(Path.Combine(presetDir, fileName), new UTF8Encoding(false));
            }

            var entryObj = new JObject();
            entryObj["name"] = name;
            entryObj["title"] = "预设 · " + name;
            entryObj["mode"] = mode;
            entryObj["dir"] = "presets/" + name;
            entryObj["files"] = new JArray(files);
            entryObj["source"] = "lut-lab 预设工作流";
            entryObj["license"] = "项目内部生成，随仓库";
            entryObj["notes"] = preset.Value<string>("notes") ?? "";
            string manifestPath = Path.Combine(_lutLabRoot, "sets", "manifest.sets.json");
            JArray manifest = new JArray();
            try
            {
                if (File.Exists(manifestPath))
                {
                    JArray existing = JArray.Parse(File.ReadAllText(manifestPath, new UTF8Encoding(false))) as JArray;
                    if (existing != null) manifest = existing;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[LutLab] savePreset manifest parse failed, rebuilding: " + ex.Message);
            }
            int replaced = -1;
            for (int i = 0; i < manifest.Count; i++)
            {
                JObject item = manifest[i] as JObject;
                if (item != null && string.Equals(item.Value<string>("name"), name, StringComparison.Ordinal)) { replaced = i; break; }
            }
            if (replaced >= 0) manifest[replaced] = entryObj; else manifest.Add(entryObj);
            Directory.CreateDirectory(Path.GetDirectoryName(manifestPath));
            string manifestTmp = manifestPath + ".tmp";
            string manifestText = manifest.ToString(Formatting.Indented) + "\n";
            File.WriteAllText(manifestTmp, manifestText, new UTF8Encoding(false));
            if (File.Exists(manifestPath)) File.Replace(manifestTmp, manifestPath, null);
            else File.Move(manifestTmp, manifestPath);

            string reread = File.ReadAllText(presetJsonPath, new UTF8Encoding(false));
            if (reread != presetJsonText + "\n")
                return BuildError(TaskNameSavePreset, "self-check failed: preset.json");
            for (int i = 0; i < 10; i++)
            {
                string rereadCube = File.ReadAllText(Path.Combine(presetDir, files[i]), new UTF8Encoding(false));
                if (rereadCube != cubeTexts[i])
                    return BuildError(TaskNameSavePreset, "self-check failed: " + files[i]);
            }
            string rereadManifest = File.ReadAllText(manifestPath, new UTF8Encoding(false));
            if (rereadManifest != manifestText)
                return BuildError(TaskNameSavePreset, "self-check failed: manifest.sets.json");

            LogManager.Log("event=lutlab_save_preset name=" + name + " mode=" + mode + " levels=10");
            var resp = new JObject();
            resp["ok"] = true; resp["success"] = true; resp["task"] = TaskNameSavePreset;
            resp["name"] = name; resp["dir"] = "presets/" + name;
            resp["files"] = new JArray(files);
            resp["manifestEntry"] = entryObj;
            var respLevels = new JArray();
            for (int i = 0; i < 10; i++)
            {
                var e = new JObject();
                e["level"] = i;
                e["rgbaBase64"] = Convert.ToBase64String(levelLuts[i]);
                respLevels.Add(e);
            }
            resp["levels"] = respLevels;
            return resp.ToString(Formatting.None);
        }

        internal static bool TryValidatePresetName(string name, out string error)
        {
            if (string.IsNullOrWhiteSpace(name)) { error = "name must be a non-empty single path segment"; return false; }
            if (name.Trim() != name) { error = "name has surrounding whitespace"; return false; }
            if (name.Length > 64) { error = "name too long (>64)"; return false; }
            if (name == "." || name == "..") { error = "name must be a single path segment"; return false; }
            if (name.IndexOfAny(new[] { '/', '\\' }) >= 0) { error = "name must not contain path separators"; return false; }
            if (name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) { error = "name contains invalid file name characters"; return false; }
            error = null;
            return true;
        }

        private static string GrabError(int code)
        {
            switch (code)
            {
                case NativeCompositorSession.GrabNoFrame: return "no_frame";
                case NativeCompositorSession.GrabExportUnavailable: return "grab_export_unavailable";
                case NativeCompositorSession.GrabBusy: return "grab_busy";
                case NativeCompositorSession.GrabTimeout: return "grab_timeout";
                case NativeCompositorSession.GrabGpuError: return "grab_gpu_error";
                case NativeCompositorSession.GrabNoWorldViewport: return "no_world_viewport";
                default: return "grab_failed:" + code;
            }
        }

        private static string BuildError(string taskName, string error)
        {
            var obj = new JObject();
            obj["ok"] = false;
            obj["success"] = false;
            obj["task"] = taskName;
            obj["error"] = error;
            return obj.ToString(Formatting.None);
        }
    }
}
