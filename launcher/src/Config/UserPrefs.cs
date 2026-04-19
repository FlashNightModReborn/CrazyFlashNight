using System;
using System.IO;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Config
{
    /// <summary>
    /// 用户级可变偏好。持久化到 %LOCALAPPDATA%/CF7FlashNight/launcher_user_prefs.json。
    /// 和 AppConfig (config.toml, 只读机器配置) 分离: 用户偏好随游玩变化, 频繁读写.
    ///
    /// 当前字段 (Phase 2b):
    ///   LastPlayedSlot — 上次启动的槽位名 (欢迎页默认槽位)
    ///   IntroEnabled   — "加载片头动画" 复选框状态
    ///
    /// 未来扩展: 往 Load/Save 加字段, 并在 JSON schema 里读容错默认值.
    /// </summary>
    public class UserPrefs
    {
        public string LastPlayedSlot { get; set; }
        public bool IntroEnabled { get; set; }

        private readonly string _path;
        private readonly string _legacyPath;

        public UserPrefs(string projectRoot)
        {
            _legacyPath = Path.Combine(projectRoot, "launcher_user_prefs.json");
            try
            {
                string localDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "CF7FlashNight");
                Directory.CreateDirectory(localDir);
                _path = Path.Combine(localDir, "launcher_user_prefs.json");
            }
            catch (Exception ex)
            {
                LogManager.Log("[UserPrefs] appdata unavailable, fallback to project root: " + ex.Message);
                _path = _legacyPath;
            }
            LastPlayedSlot = null;
            IntroEnabled = false;
            Load();
        }

        private void Load()
        {
            string readPath = null;
            if (File.Exists(_path)) readPath = _path;
            else if (File.Exists(_legacyPath)) readPath = _legacyPath;
            if (readPath == null) return;
            try
            {
                string text = File.ReadAllText(readPath);
                JObject obj = JObject.Parse(text);
                LastPlayedSlot = obj.Value<string>("lastPlayedSlot");
                bool? intro = obj.Value<bool?>("introEnabled");
                if (intro.HasValue) IntroEnabled = intro.Value;
                if (readPath == _legacyPath && _path != _legacyPath)
                {
                    // One-shot migration: stop mutating repo-root prefs after first successful read.
                    Save();
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[UserPrefs] load failed (using defaults): " + ex.Message);
                LastPlayedSlot = null;
                IntroEnabled = false;
            }
        }

        public void Save()
        {
            try
            {
                JObject obj = new JObject();
                if (!string.IsNullOrEmpty(LastPlayedSlot)) obj["lastPlayedSlot"] = LastPlayedSlot;
                obj["introEnabled"] = IntroEnabled;
                File.WriteAllText(_path, obj.ToString(Newtonsoft.Json.Formatting.Indented));
            }
            catch (Exception ex)
            {
                LogManager.Log("[UserPrefs] save failed: " + ex.Message);
            }
        }
    }
}
