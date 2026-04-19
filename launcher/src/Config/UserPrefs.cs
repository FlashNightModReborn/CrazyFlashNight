using System;
using System.IO;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Config
{
    /// <summary>
    /// 用户级可变偏好。持久化到 PROJECT_ROOT/launcher_user_prefs.json。
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

        public UserPrefs(string projectRoot)
        {
            _path = Path.Combine(projectRoot, "launcher_user_prefs.json");
            LastPlayedSlot = null;
            IntroEnabled = false;
            Load();
        }

        private void Load()
        {
            if (!File.Exists(_path)) return;
            try
            {
                string text = File.ReadAllText(_path);
                JObject obj = JObject.Parse(text);
                LastPlayedSlot = obj.Value<string>("lastPlayedSlot");
                bool? intro = obj.Value<bool?>("introEnabled");
                if (intro.HasValue) IntroEnabled = intro.Value;
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
