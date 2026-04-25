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
            // ⚠️ Phase 3 临时：所有 panel 都用全 anchor。
            // 原因：web 端 panels.js 还没 handle panel_viewport_set 消息，CSS 仍按全 anchor 假设
            // 渲染；缩到小矩形会导致 panel 内容被物理裁切（实测 help 720x540 显示错位）。
            // 后续 web 端 CSS 接 panel_viewport_set 后再恢复下方 switch 的小矩形分配。
            return anchorScreenRect;

            #pragma warning disable 0162 // unreachable code（保留小矩形配置作为 Phase 3+ web CSS 适配后的目标值）
            string name = panelName != null ? panelName.ToLowerInvariant() : "";
            switch (name)
            {
                case "kshop":    return Centered(anchorScreenRect, 1024, 720);
                case "help":     return Centered(anchorScreenRect, 720, 540);
                case "map":      return anchorScreenRect;
                case "lockbox":  return Centered(anchorScreenRect, 720, 600);
                case "pinalign": return Centered(anchorScreenRect, 600, 480);
                case "gobang":   return Centered(anchorScreenRect, 720, 720);
                case "jukebox":  return Centered(anchorScreenRect, 880, 620);
                default:         return Centered(anchorScreenRect, 800, 600);
            }
            #pragma warning restore 0162
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
