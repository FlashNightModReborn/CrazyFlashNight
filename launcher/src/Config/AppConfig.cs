using System;
using System.Globalization;
using System.IO;

namespace CF7Launcher.Config
{
    /// <summary>
    /// 读取根目录 config.toml 中的配置。
    /// 简单 key=value 解析，不引入 TOML 库。
    /// </summary>
    public class AppConfig
    {
        public string FlashPlayerPath { get; private set; }
        public string SwfPath { get; private set; }
        public bool GpuSharpeningEnabled { get; private set; }
        public float Sharpness { get; private set; }

        private static readonly string DefaultFlashPlayer = "Adobe Flash Player 20.exe";
        private static readonly string DefaultSwf = "CRAZYFLASHER7MercenaryEmpire.swf";

        public AppConfig(string projectRoot)
        {
            FlashPlayerPath = DefaultFlashPlayer;
            SwfPath = DefaultSwf;
            GpuSharpeningEnabled = true;
            Sharpness = 0.5f;

            string configPath = Path.Combine(projectRoot, "config.toml");
            if (File.Exists(configPath))
            {
                string[] lines = File.ReadAllLines(configPath);
                foreach (string line in lines)
                {
                    string trimmed = line.Trim();
                    if (trimmed.StartsWith("#") || !trimmed.Contains("="))
                        continue;

                    int eq = trimmed.IndexOf('=');
                    string key = trimmed.Substring(0, eq).Trim();
                    string val = trimmed.Substring(eq + 1).Trim().Trim('"');

                    if (string.Equals(key, "flashPlayerPath", StringComparison.OrdinalIgnoreCase))
                        FlashPlayerPath = val;
                    else if (string.Equals(key, "swfPath", StringComparison.OrdinalIgnoreCase))
                        SwfPath = val;
                    else if (string.Equals(key, "gpuSharpening", StringComparison.OrdinalIgnoreCase))
                        GpuSharpeningEnabled = ParseBool(val, true);
                    else if (string.Equals(key, "sharpness", StringComparison.OrdinalIgnoreCase))
                        Sharpness = ParseFloat(val, 0.5f);
                }
            }

            // 相对路径 → 绝对路径
            if (!Path.IsPathRooted(FlashPlayerPath))
                FlashPlayerPath = Path.Combine(projectRoot, FlashPlayerPath);
            if (!Path.IsPathRooted(SwfPath))
                SwfPath = Path.Combine(projectRoot, SwfPath);
        }

        private static bool ParseBool(string val, bool fallback)
        {
            bool result;
            if (bool.TryParse(val, out result)) return result;
            return fallback;
        }

        private static float ParseFloat(string val, float fallback)
        {
            float result;
            if (float.TryParse(val, NumberStyles.Float, CultureInfo.InvariantCulture, out result))
                return result;
            return fallback;
        }
    }
}
