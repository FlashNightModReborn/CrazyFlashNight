using System;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Widget 缩放统一计算。
    ///
    /// 推荐入口 GetScale(FlashCoordinateMapper)：用 letterbox 内 viewport 高度（vpH）÷ 576。
    /// 与 widgets 的位置算法（CalcViewport 锚点）同源，保证 4:3 / 16:10 / 高瘦窗口下尺寸跟视口一起缩放，
    /// 不会出现"按 anchor 高度放大却按 vp 定位"的越界错位。
    ///
    /// 旧入口 GetScale(Control)：仅在 mapper 不可用的退化场景使用；用 anchor.Height ÷ 576，
    /// 在 letterbox 大时会偏大。新代码不要走这条路径。
    ///
    /// 防 0 / 防极小值，最低 0.5x 保证按钮仍可点击。
    /// </summary>
    public static class WidgetScaler
    {
        public const float DESIGN_HEIGHT = 576f;
        public const float MIN_SCALE = 0.5f;

        /// <summary>
        /// 用 Flash viewport（letterbox-stripped 16:9 区域）高度作为 scale 源。
        /// 这是 widgets 的 SCREENBOUNDS 锚点用的同一个坐标系，避免缩放/定位错位。
        /// </summary>
        public static float GetScale(FlashCoordinateMapper mapper)
        {
            if (mapper == null) return 1f;
            float vpX, vpY, vpW, vpH;
            mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
            if (vpH <= 0) return 1f;
            return Math.Max(MIN_SCALE, vpH / DESIGN_HEIGHT);
        }

        /// <summary>
        /// 退化路径：仅在没有 mapper 的极少数场景使用。优先用 mapper 重载。
        /// </summary>
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
