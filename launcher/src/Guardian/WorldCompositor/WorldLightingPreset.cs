using System;
using System.IO;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // 世界光照宿主预设入口（launcher/data/world-lighting/preset.json）：
    //   version 1 = legacy-matrix-v1（8 参数 → 颜色矩阵 + gamma，既有语义原样保留）；
    //   version 2 = lut-set-v1（32^3 × 10 档 LUT 集合，CF7LUTSET v1 二进制 + 内嵌 SHA-256）。
    // v2 的任何加载失败（文件缺失/格式/哈希不符/字段非法）都回退 legacy 矩阵路径并打警告日志——
    // 绝不允许黑屏或启动失败；回退方法 = preset.json 改回 version 1（连同 file 字段移除即可）。
    internal sealed class WorldLightingPreset
    {
        private readonly WorldColorMatrix _legacy;

        private WorldLightingPreset(WorldColorMatrix legacy, WorldLutSet lutSet, string lutFile)
        {
            _legacy = legacy;
            LutSet = lutSet;
            LutFile = lutFile;
        }

        internal float Gamma => _legacy.Gamma;
        internal WorldLutSet LutSet { get; private set; }
        internal string LutFile { get; private set; }

        // 生产分派契约：仅 mode=="光照" 走 LUT 路径；夜视与其他未知 mode 保持 legacy 矩阵不动。
        internal bool UsesLut(string mode) =>
            LutSet != null && string.Equals(mode, "光照", StringComparison.Ordinal);

        internal float[] ShaderSettings(double[] matrix) => _legacy.ShaderSettings(matrix);

        internal static WorldLightingPreset Load(string path, Action<string> warn)
        {
            // preset.json 缺失/畸形/未知版本：保持 WorldColorMatrix.Load 既有抛错语义（部署级破损，不静默）。
            var json = JObject.Parse(File.ReadAllText(path));
            var version = json.Value<int?>("version");
            if (version == 1)
                return new WorldLightingPreset(WorldColorMatrix.Load(path), null, null);
            if (version != 2)
                throw new InvalidDataException("Unsupported world lighting preset");
            try
            {
                if (json.Value<string>("algorithm") != "lut-set-v1")
                    throw new InvalidDataException("Unsupported lut-set algorithm");
                double gamma = json.Value<double?>("gamma") ?? 1;
                if (!double.IsFinite(gamma) || gamma < 0.25 || gamma > 4)
                    throw new InvalidDataException("Invalid gamma");
                // file 必须是纯文件名：拒绝目录分隔符/父目录引用，组装不越出预设目录。
                string file = json.Value<string>("file");
                if (string.IsNullOrEmpty(file) || file.Length > 128
                    || file.IndexOfAny(new[] { '/', '\\' }) >= 0 || file.Contains(".."))
                    throw new InvalidDataException("Invalid lut-set file name");
                string lutPath = Path.Combine(Path.GetDirectoryName(path), file);
                var lutSet = WorldLutSet.Load(lutPath);
                return new WorldLightingPreset(WorldColorMatrix.Create(gamma), lutSet, file);
            }
            catch (Exception error)
            {
                warn?.Invoke("event=world_lighting_preset_fallback reason=\"" + error.Message
                    + "\" path=\"" + path + "\" fallback=legacy-matrix-v1");
                return new WorldLightingPreset(new WorldColorMatrix(), null, null);
            }
        }
    }
}
