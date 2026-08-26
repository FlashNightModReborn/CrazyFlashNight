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
    ///   LastPlayedSlot  — 上次启动的槽位名 (欢迎页默认槽位)
    ///   IntroEnabled    — "加载片头动画" 复选框状态
    ///   SfxEnabled      — Web Audio UI 音效 (hover / click / confirm / error 等), 默认 true
    ///   AmbientEnabled  — Web Audio 环境 hum (Idle 态背景低频 drone), 默认 false
    ///   UiFontScale     — 引导页字号缩放倍率, 网页侧作用于 :root --fs-scale (bootstrap/welcome.css)
    ///                    允许值 [FontScaleMin..FontScaleMax], 默认 FontScaleDefault (略放大基线)
    ///   SuppressedHighDpiWarningRaw — 用户选择不再提示的高 DPI 兼容性 raw value
    ///   MapDisplayPreference — 小地图显示偏好: auto/off/compact/expanded；与 AS2 mm 运行态分离
    ///   HitNumberMode — 打击伤害数字行为: off/balanced/total/classic/detail；默认 balanced
    ///   HitNumberWorldRowLimit — 世界内同时保留的攻击行全局上限；0 表示不设产品上限
    ///
    /// 未来扩展: 往 Load/Save 加字段, 并在 JSON schema 里读容错默认值.
    /// </summary>
    public class UserPrefs
    {
        public const double FontScaleMin = 0.7;
        public const double FontScaleMax = 1.9;
        public const double FontScaleDefault = 1.35;
        public const string HitNumberModeDefault = "balanced";
        public const int HitNumberWorldRowLimitDefault = 24;
        public const int HitNumberWorldRowLimitMax = 1000;

        public string LastPlayedSlot { get; set; }
        public bool IntroEnabled { get; set; }
        public bool SfxEnabled { get; set; }
        public bool AmbientEnabled { get; set; }
        public double UiFontScale { get; set; }
        public string SuppressedHighDpiWarningRaw { get; set; }
        public string MapDisplayPreference { get; set; }
        public string HitNumberMode { get; set; }
        public int HitNumberWorldRowLimit { get; set; }

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
            SfxEnabled = true;
            AmbientEnabled = false;
            UiFontScale = FontScaleDefault;
            SuppressedHighDpiWarningRaw = null;
            MapDisplayPreference = "auto";
            HitNumberMode = HitNumberModeDefault;
            HitNumberWorldRowLimit = HitNumberWorldRowLimitDefault;
            Load();
        }

        public static double ClampFontScale(double v)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return FontScaleDefault;
            if (v < FontScaleMin) return FontScaleMin;
            if (v > FontScaleMax) return FontScaleMax;
            return v;
        }

        public static string NormalizeMapDisplayPreference(string value)
        {
            string normalized = (value ?? "").Trim().ToLowerInvariant();
            if (normalized == "off" || normalized == "compact" || normalized == "expanded")
                return normalized;
            return "auto";
        }

        public static string NormalizeHitNumberMode(string value)
        {
            string normalized = (value ?? "").Trim().ToLowerInvariant();
            if (normalized == "off" || normalized == "detail"
                || normalized == "classic" || normalized == "total") return normalized;
            return HitNumberModeDefault;
        }

        public static int NormalizeHitNumberWorldRowLimit(int value)
        {
            if (value < 0) return HitNumberWorldRowLimitDefault;
            return Math.Min(value, HitNumberWorldRowLimitMax);
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
                bool? sfx = obj.Value<bool?>("sfxEnabled");
                if (sfx.HasValue) SfxEnabled = sfx.Value;
                bool? ambient = obj.Value<bool?>("ambientEnabled");
                if (ambient.HasValue) AmbientEnabled = ambient.Value;
                double? scale = obj.Value<double?>("uiFontScale");
                if (scale.HasValue) UiFontScale = ClampFontScale(scale.Value);
                SuppressedHighDpiWarningRaw = obj.Value<string>("suppressedHighDpiWarningRaw");
                MapDisplayPreference = NormalizeMapDisplayPreference(obj.Value<string>("mapDisplayPreference"));
                HitNumberMode = NormalizeHitNumberMode(obj.Value<string>("hitNumberMode"));
                int? hitNumberLimit = obj.Value<int?>("hitNumberWorldRowLimit");
                if (hitNumberLimit.HasValue)
                    HitNumberWorldRowLimit = NormalizeHitNumberWorldRowLimit(hitNumberLimit.Value);
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
                SfxEnabled = true;
                AmbientEnabled = false;
                UiFontScale = FontScaleDefault;
                SuppressedHighDpiWarningRaw = null;
                MapDisplayPreference = "auto";
                HitNumberMode = HitNumberModeDefault;
                HitNumberWorldRowLimit = HitNumberWorldRowLimitDefault;
            }
        }

        /// <summary>落盘到 appdata/launcher_user_prefs.json。
        /// 返回 true 表示落盘成功; false 表示磁盘写入失败 (日志已记)。
        /// 调用方 (ConfigCommandHandler) 据此回 {ok:false, error:"save_failed"},
        /// 避免前端以为设置已持久化、下次启动却回退。</summary>
        public bool Save()
        {
            try
            {
                JObject obj = new JObject();
                if (!string.IsNullOrEmpty(LastPlayedSlot)) obj["lastPlayedSlot"] = LastPlayedSlot;
                obj["introEnabled"] = IntroEnabled;
                obj["sfxEnabled"] = SfxEnabled;
                obj["ambientEnabled"] = AmbientEnabled;
                obj["uiFontScale"] = UiFontScale;
                obj["mapDisplayPreference"] = NormalizeMapDisplayPreference(MapDisplayPreference);
                obj["hitNumberMode"] = NormalizeHitNumberMode(HitNumberMode);
                obj["hitNumberWorldRowLimit"] =
                    NormalizeHitNumberWorldRowLimit(HitNumberWorldRowLimit);
                if (!string.IsNullOrEmpty(SuppressedHighDpiWarningRaw))
                    obj["suppressedHighDpiWarningRaw"] = SuppressedHighDpiWarningRaw;
                File.WriteAllText(_path, obj.ToString(Newtonsoft.Json.Formatting.Indented));
                return true;
            }
            catch (Exception ex)
            {
                LogManager.Log("[UserPrefs] save failed: " + ex.Message);
                return false;
            }
        }
    }
}
