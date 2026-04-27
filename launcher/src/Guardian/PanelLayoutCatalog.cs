using System;
using System.Drawing;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Panel 优先矩形表（屏幕坐标）。
    /// PanelHostController 调用 GetRect(panelName, anchorScreenRect) 决定 WebOverlay 在 panel 态的尺寸/位置。
    /// 默认居中于 anchor；若请求尺寸超出 anchor 则 clamp 到 anchor。
    ///
    /// Phase 5 jukebox 升格 panel 后按实际 UX 微调 880x620 占位尺寸。
    /// </summary>
    public static class PanelLayoutCatalog
    {
        public static Rectangle GetRect(string panelName, Rectangle anchorScreenRect)
        {
            // Phase 3 遗留：除 jukebox 外其他 panel 仍按全 anchor 打开——
            // 它们的 web CSS 假设全 anchor viewport（kshop/help 等缩到小矩形会物理裁切）。
            // 待 panels.js 接 panel_viewport_set 后再逐个开启下方 switch 中的小矩形分配。
            //
            // Phase 5：jukebox 已是新 panel（jukebox-panel.js 用 inset:6% 12% 百分比布局，
            // 与 panelRect 大小解耦），可以直接使用基准 880×620 小矩形——
            // 这是 Phase 4 收尾后真正缩小 panel 态 α blend 表面的第一个例子。
            //
            // 基准尺寸按 anchorScreenRect.Height / DESIGN_HEIGHT 缩放，与 WidgetScaler 同源
            // （anchor 已是 letterbox-stripped viewport），保证大窗口下 panel 跟 widgets 比例一致放大、
            // 4:3 / 16:10 / 紧凑窗口下整体小一档但布局不裁切。
            string name = panelName != null ? panelName.ToLowerInvariant() : "";
            if (name == "jukebox")
            {
                int w, h;
                ScalePanelSize(880, 620, anchorScreenRect, out w, out h);
                return Centered(anchorScreenRect, w, h);
            }
            return anchorScreenRect;

            #pragma warning disable 0162 // unreachable（保留小矩形配置作为其他 panel 适配 panel_viewport_set 后的目标值）
            switch (name)
            {
                case "kshop":    return Centered(anchorScreenRect, 1024, 720);
                case "help":     return Centered(anchorScreenRect, 720, 540);
                case "map":      return anchorScreenRect;
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
