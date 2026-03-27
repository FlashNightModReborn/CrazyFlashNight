using System;
using System.IO;

namespace CF7Launcher.Config
{
    /// <summary>
    /// 读取根目录 config.toml 中的 flashPlayerPath 和 swfPath。
    /// 简单 key=value 解析，不引入 TOML 库。
    /// </summary>
    public class AppConfig
    {
        public string FlashPlayerPath { get; private set; }
        public string SwfPath { get; private set; }

        private static readonly string DefaultFlashPlayer = "Adobe Flash Player 20.exe";
        private static readonly string DefaultSwf = "CRAZYFLASHER7MercenaryEmpire.swf";

        public AppConfig(string projectRoot)
        {
            FlashPlayerPath = DefaultFlashPlayer;
            SwfPath = DefaultSwf;

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
                }
            }

            // 相对路径 → 绝对路径
            if (!Path.IsPathRooted(FlashPlayerPath))
                FlashPlayerPath = Path.Combine(projectRoot, FlashPlayerPath);
            if (!Path.IsPathRooted(SwfPath))
                SwfPath = Path.Combine(projectRoot, SwfPath);
        }
    }
}
