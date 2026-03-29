using System;
using System.Drawing;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Flash 舞台坐标 ↔ 屏幕像素坐标 映射器。
    /// 考虑 Flash Player SA 的等比缩放和 letterbox 黑边。
    /// 可复用于所有需要在 Flash 内容上叠加 UI 的场景。
    /// </summary>
    public class FlashCoordinateMapper
    {
        private readonly Control _anchor;  // Flash 宿主 panel

        /// <summary>Flash 舞台设计分辨率。</summary>
        public float StageWidth { get; private set; }
        public float StageHeight { get; private set; }

        public FlashCoordinateMapper(Control anchor, float stageWidth, float stageHeight)
        {
            _anchor = anchor;
            StageWidth = stageWidth;
            StageHeight = stageHeight;
        }

        /// <summary>
        /// 计算 Flash 内容在 panel 中的实际渲染区域（考虑 letterbox 黑边）。
        /// Flash Player SA 保持宽高比居中显示。
        /// </summary>
        public void CalcViewport(out float vpX, out float vpY, out float vpW, out float vpH)
        {
            int panelW = _anchor.Width;
            int panelH = _anchor.Height;
            float stageAspect = StageWidth / StageHeight;
            float panelAspect = (float)panelW / panelH;

            if (panelAspect > stageAspect)
            {
                vpH = panelH;
                vpW = panelH * stageAspect;
                vpX = (panelW - vpW) / 2f;
                vpY = 0;
            }
            else
            {
                vpW = panelW;
                vpH = panelW / stageAspect;
                vpX = 0;
                vpY = (panelH - vpH) / 2f;
            }
        }

        /// <summary>
        /// Flash 舞台坐标 → 屏幕像素坐标。
        /// </summary>
        public void FlashToScreen(float flashX, float flashY, out int screenX, out int screenY)
        {
            float vpX, vpY, vpW, vpH;
            CalcViewport(out vpX, out vpY, out vpW, out vpH);

            Point origin;
            try { origin = _anchor.PointToScreen(Point.Empty); }
            catch { origin = Point.Empty; }

            screenX = origin.X + (int)(vpX + flashX / StageWidth * vpW);
            screenY = origin.Y + (int)(vpY + flashY / StageHeight * vpH);
        }

        /// <summary>Flash 舞台水平像素 → 屏幕像素。</summary>
        public int ScaleW(float flashPx)
        {
            float vpX, vpY, vpW, vpH;
            CalcViewport(out vpX, out vpY, out vpW, out vpH);
            return Math.Max(1, (int)(flashPx / StageWidth * vpW));
        }

        /// <summary>Flash 舞台垂直像素 → 屏幕像素。</summary>
        public int ScaleH(float flashPx)
        {
            float vpX, vpY, vpW, vpH;
            CalcViewport(out vpX, out vpY, out vpW, out vpH);
            return Math.Max(1, (int)(flashPx / StageHeight * vpH));
        }

        /// <summary>当前视口宽度（屏幕像素）。</summary>
        public float ViewportWidth
        {
            get
            {
                float vpX, vpY, vpW, vpH;
                CalcViewport(out vpX, out vpY, out vpW, out vpH);
                return vpW;
            }
        }
    }
}
