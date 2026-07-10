using System;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// AS2 `mm` 的运行态语义。只描述游戏当前是否允许地图态展示/导航；
    /// 不能被用户显示偏好覆盖。Combat=3 仍参与任务远程交付门控。
    /// </summary>
    public enum RuntimeMapMode
    {
        Unknown = -1,
        None = 0,
        Navigation = 1,
        Alternate = 2,
        Combat = 3
    }

    /// <summary>用户级持久化的小地图显示偏好。</summary>
    public enum MapDisplayPreference
    {
        Auto,
        Off,
        Compact,
        Expanded
    }

    /// <summary>由 runtime + preference + capability 纯派生出的当前显示态。</summary>
    public enum EffectiveMapDisplayMode
    {
        Hidden,
        Compact,
        Expanded
    }

    public static class MapDisplayPolicy
    {
        public static RuntimeMapMode ParseRuntimeMode(string raw)
        {
            int value;
            if (!int.TryParse((raw ?? "").Trim(), out value)) return RuntimeMapMode.Unknown;
            switch (value)
            {
                case 0: return RuntimeMapMode.None;
                case 1: return RuntimeMapMode.Navigation;
                case 2: return RuntimeMapMode.Alternate;
                case 3: return RuntimeMapMode.Combat;
                default: return RuntimeMapMode.Unknown;
            }
        }

        public static bool IsRenderableRuntime(RuntimeMapMode mode)
        {
            return mode == RuntimeMapMode.Navigation || mode == RuntimeMapMode.Alternate;
        }

        public static MapDisplayPreference ParsePreference(string raw)
        {
            string normalized = (raw ?? "").Trim().ToLowerInvariant();
            switch (normalized)
            {
                case "off": return MapDisplayPreference.Off;
                case "compact": return MapDisplayPreference.Compact;
                case "expanded": return MapDisplayPreference.Expanded;
                case "auto":
                default:
                    return MapDisplayPreference.Auto;
            }
        }

        public static string ToPersistedValue(MapDisplayPreference preference)
        {
            switch (preference)
            {
                case MapDisplayPreference.Off: return "off";
                case MapDisplayPreference.Compact: return "compact";
                case MapDisplayPreference.Expanded: return "expanded";
                default: return "auto";
            }
        }

        public static string ToDisplayLabel(MapDisplayPreference preference)
        {
            switch (preference)
            {
                case MapDisplayPreference.Off: return "关闭";
                case MapDisplayPreference.Compact: return "紧凑";
                case MapDisplayPreference.Expanded: return "展开";
                default: return "自动";
            }
        }

        /// <summary>
        /// 纯派生函数：不得写回 runtimeMapMode 或 mapDisplayPreference。
        /// 当前 tacticalDataAvailable=false 时 Auto 保持 Hidden；未来战术层上线后 Auto 才默认 Compact。
        /// </summary>
        public static EffectiveMapDisplayMode Resolve(
            RuntimeMapMode runtimeMapMode,
            MapDisplayPreference preference,
            bool mapAvailable,
            bool tacticalDataAvailable)
        {
            if (!mapAvailable || !IsRenderableRuntime(runtimeMapMode))
                return EffectiveMapDisplayMode.Hidden;

            switch (preference)
            {
                case MapDisplayPreference.Off:
                    return EffectiveMapDisplayMode.Hidden;
                case MapDisplayPreference.Compact:
                    return EffectiveMapDisplayMode.Compact;
                case MapDisplayPreference.Expanded:
                    return EffectiveMapDisplayMode.Expanded;
                default:
                    return tacticalDataAvailable
                        ? EffectiveMapDisplayMode.Compact
                        : EffectiveMapDisplayMode.Hidden;
            }
        }

        /// <summary>
        /// 刘海“地图开关”只负责可见性：隐藏时以 compact 打开，可见时关闭。
        /// Auto 仍只能通过设置入口恢复，且不得写回 runtimeMapMode。
        /// </summary>
        public static MapDisplayPreference ToggleVisibility(EffectiveMapDisplayMode current)
        {
            return current == EffectiveMapDisplayMode.Hidden
                ? MapDisplayPreference.Compact
                : MapDisplayPreference.Off;
        }

        /// <summary>地图卡片内的尺寸按钮只在 compact / expanded 之间往返，不承担关闭。</summary>
        public static MapDisplayPreference ToggleSize(EffectiveMapDisplayMode current)
        {
            if (current == EffectiveMapDisplayMode.Compact) return MapDisplayPreference.Expanded;
            return MapDisplayPreference.Compact;
        }
    }
}
