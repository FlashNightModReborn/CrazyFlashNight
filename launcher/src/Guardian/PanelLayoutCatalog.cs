using System;
using System.Drawing;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Panel 优先矩形表（屏幕坐标）。
    /// PanelHostController 调用 GetRect(panelName, anchorScreenRect) 决定 WebOverlay 在 panel 态的尺寸/位置。
    /// 默认居中于 anchor；若请求尺寸超出 anchor 则 clamp 到 anchor。
    ///
    /// 沉浸全屏化（2026-06-12）后所有 panel 一律返回全 anchor；Centered / ScalePanelSize 保留为
    /// 「未来 panel 重新走子矩形」的工具与 Centered_* 单测回归保护，生产路径不再使用。
    /// </summary>
    public static class PanelLayoutCatalog
    {
        public static Rectangle GetRect(string panelName, Rectangle anchorScreenRect)
        {
            // 沉浸全屏化（2026-06-12 收尾）：所有运行时 panel 一律全 anchor（return anchorScreenRect）。
            // jukebox / arena 原走 Centered 小矩形（居中卡片浮在暗 backdrop 上），现已改为固定 1024×576 画布
            // + web 端 .panel-scale-shell 整体等比缩放铺满全 16:9，与 tasks/kshop/stage-select 等一致。
            // Centered / ScalePanelSize 保留为「未来若有 panel 重新走子矩形」的工具 + 下方 unreachable 占位
            // 与 Centered_* 单测的回归保护，当前生产路径不使用。
            string name = panelName != null ? panelName.ToLowerInvariant() : "";
            return anchorScreenRect;

            #pragma warning disable 0162 // unreachable（保留小矩形配置作为其他 panel 适配 panel_viewport_set 后的目标值）
            switch (name)
            {
                case "kshop":    return Centered(anchorScreenRect, 1024, 720);
                case "help":     return Centered(anchorScreenRect, 720, 540);
                case "map":      return anchorScreenRect;
                case "stage-select": return anchorScreenRect;
                case "lockbox":  return Centered(anchorScreenRect, 720, 600);
                case "pinalign": return Centered(anchorScreenRect, 600, 480);
                case "gobang":   return Centered(anchorScreenRect, 720, 720);
                default:         return Centered(anchorScreenRect, 800, 600);
            }
            #pragma warning restore 0162
        }

        /// <summary>
        /// 把基准尺寸按 anchor.Height / 576 缩放（与 Hud.WidgetScaler.DESIGN_HEIGHT 同源）。
        /// 不直接 ref WidgetScaler 是因为 PanelLayoutCatalog 在 Guardian namespace、Hud 是子 namespace，
        /// 反向 ref 会引入循环依赖；常量 576 重复一次可接受。最低 0.5x 防极端窗口下退化为 0。
        /// </summary>
        private static void ScalePanelSize(int baseW, int baseH, Rectangle anchor, out int w, out int h)
        {
            const float DESIGN_HEIGHT = 576f;
            const float MIN_SCALE = 0.5f;
            float scale = anchor.Height > 0 ? anchor.Height / DESIGN_HEIGHT : 1f;
            if (scale < MIN_SCALE) scale = MIN_SCALE;
            w = Math.Max(1, (int)Math.Round(baseW * scale));
            h = Math.Max(1, (int)Math.Round(baseH * scale));
        }

        /// <summary>取 anchor 中央居中；若请求尺寸超过 anchor 则 clamp 到 anchor。</summary>
        internal static Rectangle Centered(Rectangle anchor, int w, int h)
        {
            int actualW = Math.Min(w, anchor.Width);
            int actualH = Math.Min(h, anchor.Height);
            int x = anchor.X + (anchor.Width - actualW) / 2;
            int y = anchor.Y + (anchor.Height - actualH) / 2;
            return new Rectangle(x, y, actualW, actualH);
        }
    }
}
