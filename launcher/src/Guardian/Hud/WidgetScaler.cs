using System;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Widget 缩放统一计算。所有 INativeHudWidget 用 anchor.Height / 576 作为 scale，
    /// 与 WebView2 ZoomFactor 同源（保证 web ↔ C# 视觉一致）。
    /// 防 0 / 防极小值，最低 0.5x 保证按钮仍可点击。
    /// </summary>
    public static class WidgetScaler
    {
        public const float DESIGN_HEIGHT = 576f;
        public const float MIN_SCALE = 0.5f;

        public static float GetScale(Control anchor)
        {
            if (anchor == null || anchor.Height <= 0) return 1f;
            return Math.Max(MIN_SCALE, anchor.Height / DESIGN_HEIGHT);
        }

        public static int Px(int basePx, float scale)
        {
            return Math.Max(1, (int)Math.Round(basePx * scale));
        }

        public static float Pxf(float basePx, float scale)
        {
            return Math.Max(1f, basePx * scale);
        }
    }
}
