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
        public bool WebOverlayLowEffects { get; private set; }
        public bool WebOverlayDisableCssAnimations { get; private set; }
        public bool WebOverlayDisableVisualizers { get; private set; }
        public int WebOverlayFrameRateLimit { get; private set; }
        public bool WebView2DisableGpu { get; private set; }
        public string WebView2AdditionalArgs { get; private set; }
        public bool NativeCursorOverlayEnabled { get; private set; }
        /// <summary>"off" | "auto" | "on"。控制是否把 launcher 与 WebView2 标记为高性能 GPU。见 GpuPreferenceManager。</summary>
        public string GpuPreference { get; private set; }
        /// <summary>开发用：Ctrl+G 切换 WebView2 opaque + Flash 隐藏的合成成本探针。玩家版必须 false。</summary>
        public bool DevGpuProbeHotkey { get; private set; }
        /// <summary>开关 Native HUD + PanelHostController 装配。Phase 1 默认 false（仅装配骨架，不接管 panel 路由）。</summary>
        public bool UseNativeHud { get; private set; }
        /// <summary>
        /// Cursor 解耦 Phase 1 flag。OFF（默认）= 旧 CursorOverlayForm（OverlayBase 体系）；
        /// ON = 新 DesktopCursorOverlay（desktop 顶层 ULW，跨 anchor 自由 + 单一 visibility 状态机）。
        /// 见 plans/cursor-overlay-decoupling.md。env: CF7_DESKTOP_CURSOR=1
        /// </summary>
        public bool UseDesktopCursorOverlay { get; private set; }

        private static readonly string DefaultFlashPlayer = "Adobe Flash Player 20.exe";
        private static readonly string DefaultSwf = "CRAZYFLASHER7MercenaryEmpire.swf";

        public AppConfig(string projectRoot)
        {
            FlashPlayerPath = DefaultFlashPlayer;
            SwfPath = DefaultSwf;
            GpuSharpeningEnabled = true;
            Sharpness = 0.5f;
            WebOverlayLowEffects = false;
            WebOverlayDisableCssAnimations = false;
            WebOverlayDisableVisualizers = false;
            WebOverlayFrameRateLimit = 60;
            WebView2DisableGpu = false;
            WebView2AdditionalArgs = "";
            NativeCursorOverlayEnabled = true;
            GpuPreference = "off";
            DevGpuProbeHotkey = false;
            UseNativeHud = false;
            UseDesktopCursorOverlay = false;

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
                    else if (string.Equals(key, "webOverlayLowEffects", StringComparison.OrdinalIgnoreCase))
                        WebOverlayLowEffects = ParseBool(val, false);
                    else if (string.Equals(key, "webOverlayDisableCssAnimations", StringComparison.OrdinalIgnoreCase))
                        WebOverlayDisableCssAnimations = ParseBool(val, false);
                    else if (string.Equals(key, "webOverlayDisableVisualizers", StringComparison.OrdinalIgnoreCase))
                        WebOverlayDisableVisualizers = ParseBool(val, false);
                    else if (string.Equals(key, "webOverlayFrameRateLimit", StringComparison.OrdinalIgnoreCase))
                        WebOverlayFrameRateLimit = ParseFrameRateLimit(val, 60);
                    else if (string.Equals(key, "webView2DisableGpu", StringComparison.OrdinalIgnoreCase))
                        WebView2DisableGpu = ParseBool(val, false);
                    else if (string.Equals(key, "webView2AdditionalArgs", StringComparison.OrdinalIgnoreCase))
                        WebView2AdditionalArgs = val;
                    else if (string.Equals(key, "nativeCursorOverlay", StringComparison.OrdinalIgnoreCase))
                        NativeCursorOverlayEnabled = ParseBool(val, true);
                    else if (string.Equals(key, "gpuPreference", StringComparison.OrdinalIgnoreCase))
                        GpuPreference = NormalizeGpuPreference(val, "off");
                    else if (string.Equals(key, "devGpuProbeHotkey", StringComparison.OrdinalIgnoreCase))
                        DevGpuProbeHotkey = ParseBool(val, false);
                    else if (string.Equals(key, "useNativeHud", StringComparison.OrdinalIgnoreCase))
                        UseNativeHud = ParseBool(val, false);
                    else if (string.Equals(key, "useDesktopCursorOverlay", StringComparison.OrdinalIgnoreCase))
                        UseDesktopCursorOverlay = ParseBool(val, false);
                }
            }

            ApplyEnvironmentOverrides();

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

        private void ApplyEnvironmentOverrides()
        {
            string lowEffects = Environment.GetEnvironmentVariable("CF7_WEB_LOW_EFFECTS");
            if (!string.IsNullOrEmpty(lowEffects))
                WebOverlayLowEffects = ParseBoolLike(lowEffects, WebOverlayLowEffects);

            string disableCssAnimations = Environment.GetEnvironmentVariable("CF7_WEB_DISABLE_CSS_ANIMATIONS");
            if (!string.IsNullOrEmpty(disableCssAnimations))
                WebOverlayDisableCssAnimations = ParseBoolLike(disableCssAnimations, WebOverlayDisableCssAnimations);

            string disableVisualizers = Environment.GetEnvironmentVariable("CF7_WEB_DISABLE_VISUALIZERS");
            if (!string.IsNullOrEmpty(disableVisualizers))
                WebOverlayDisableVisualizers = ParseBoolLike(disableVisualizers, WebOverlayDisableVisualizers);

            string frameRateLimit = Environment.GetEnvironmentVariable("CF7_WEB_FRAME_RATE_LIMIT");
            if (!string.IsNullOrEmpty(frameRateLimit))
                WebOverlayFrameRateLimit = ParseFrameRateLimit(frameRateLimit, WebOverlayFrameRateLimit);

            string disableGpu = Environment.GetEnvironmentVariable("CF7_WEBVIEW2_DISABLE_GPU");
            if (!string.IsNullOrEmpty(disableGpu))
                WebView2DisableGpu = ParseBoolLike(disableGpu, WebView2DisableGpu);

            string extraArgs = Environment.GetEnvironmentVariable("CF7_WEBVIEW2_ARGS");
            if (!string.IsNullOrEmpty(extraArgs))
                WebView2AdditionalArgs = extraArgs;

            string nativeCursorOverlay = Environment.GetEnvironmentVariable("CF7_NATIVE_CURSOR_OVERLAY");
            if (!string.IsNullOrEmpty(nativeCursorOverlay))
                NativeCursorOverlayEnabled = ParseBoolLike(nativeCursorOverlay, NativeCursorOverlayEnabled);

            string gpuPref = Environment.GetEnvironmentVariable("CF7_GPU_PREFERENCE");
            if (!string.IsNullOrEmpty(gpuPref))
                GpuPreference = NormalizeGpuPreference(gpuPref, GpuPreference);

            string gpuProbe = Environment.GetEnvironmentVariable("CF7_DEV_GPU_PROBE");
            if (!string.IsNullOrEmpty(gpuProbe))
                DevGpuProbeHotkey = ParseBoolLike(gpuProbe, DevGpuProbeHotkey);

            string nativeHud = Environment.GetEnvironmentVariable("CF7_NATIVE_HUD");
            if (!string.IsNullOrEmpty(nativeHud))
                UseNativeHud = ParseBoolLike(nativeHud, UseNativeHud);

            string desktopCursor = Environment.GetEnvironmentVariable("CF7_DESKTOP_CURSOR");
            if (!string.IsNullOrEmpty(desktopCursor))
                UseDesktopCursorOverlay = ParseBoolLike(desktopCursor, UseDesktopCursorOverlay);
        }

        private static string NormalizeGpuPreference(string val, string fallback)
        {
            if (string.IsNullOrEmpty(val)) return fallback;
            string n = val.Trim().ToLowerInvariant();
            if (n == "off" || n == "auto" || n == "on") return n;
            // 容忍 bool-like 输入：true→on / false→off
            if (n == "1" || n == "yes" || n == "true") return "on";
            if (n == "0" || n == "no" || n == "false") return "off";
            return fallback;
        }

        private static bool ParseBoolLike(string val, bool fallback)
        {
            if (string.IsNullOrEmpty(val)) return fallback;
            string normalized = val.Trim().ToLowerInvariant();
            if (normalized == "1" || normalized == "yes" || normalized == "on") return true;
            if (normalized == "0" || normalized == "no" || normalized == "off") return false;
            return ParseBool(val, fallback);
        }

        private static int ParseFrameRateLimit(string val, int fallback)
        {
            if (string.IsNullOrEmpty(val)) return fallback;
            string normalized = val.Trim().ToLowerInvariant();
            if (normalized == "0" || normalized == "off" || normalized == "full" ||
                normalized == "unlimited" || normalized == "uncapped")
                return 0;

            int parsed;
            if (!int.TryParse(normalized, NumberStyles.Integer, CultureInfo.InvariantCulture, out parsed))
                return fallback;

            if (parsed <= 0) return 0;
            if (parsed < 15) return 15;
            if (parsed > 240) return 240;
            return parsed;
        }
    }
}
