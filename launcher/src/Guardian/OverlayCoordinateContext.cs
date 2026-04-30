using System;
using System.Drawing;

namespace CF7Launcher.Guardian
{
    public sealed class OverlayCoordinateContext
    {
        private const double MinScale = 0.05;

        public Rectangle OverlayPhysicalBounds { get; private set; }
        public float FlashViewportX { get; private set; }
        public float FlashViewportY { get; private set; }
        public float FlashViewportWidth { get; private set; }
        public float FlashViewportHeight { get; private set; }
        public double WebCssWidth { get; private set; }
        public double WebCssHeight { get; private set; }
        public double DevicePixelRatio { get; private set; }
        public double VisualViewportWidth { get; private set; }
        public double VisualViewportHeight { get; private set; }
        public int WindowDpiX { get; private set; }
        public int WindowDpiY { get; private set; }
        public IntPtr MonitorHandle { get; private set; }
        public string LastReason { get; private set; }
        public bool HasWebMetrics { get; private set; }
        public bool LastDpiResolved { get; private set; }

        // Flash 设计基准高度（与 ComboWidget / RightContextWidget 等 widget 用的 stageH 一致）。
        // viewport scale = 实际内容区物理高度 / 576。
        public const float DesignHeight = 576f;

        /// <summary>
        /// Flash 内容区物理像素 / 设计高度的比值；letterbox 黑边不计入（用 FlashViewportHeight 而非 OverlayPhysicalBounds.Height）。
        /// 全屏 1920×1080 → ~1.875；窗口化 1024×576 → ~1.0；尚未 update 时退回 1.0。
        /// </summary>
        public double ViewportScale
        {
            get
            {
                if (FlashViewportHeight > 0f) return FlashViewportHeight / DesignHeight;
                return 1.0;
            }
        }

        private double _fallbackZoom;

        public OverlayCoordinateContext()
        {
            OverlayPhysicalBounds = Rectangle.Empty;
            WindowDpiX = 96;
            WindowDpiY = 96;
            DevicePixelRatio = 1.0;
            LastDpiResolved = false;
            _fallbackZoom = 1.0;
            LastReason = "init";
        }

        public void UpdateOverlay(Rectangle physicalBounds, float vpX, float vpY, float vpW, float vpH,
            IntPtr hwnd, double fallbackZoom, string reason)
        {
            OverlayPhysicalBounds = physicalBounds;
            FlashViewportX = vpX;
            FlashViewportY = vpY;
            FlashViewportWidth = vpW;
            FlashViewportHeight = vpH;
            _fallbackZoom = NormalizeScale(fallbackZoom);
            LastReason = reason ?? "overlay";

            uint dpiX, dpiY;
            LastDpiResolved = DpiDiagnostics.TryGetWindowDpi(hwnd, out dpiX, out dpiY);
            if (LastDpiResolved)
            {
                WindowDpiX = (int)dpiX;
                WindowDpiY = (int)dpiY;
            }
            MonitorHandle = DpiDiagnostics.GetMonitorFromWindow(hwnd);
        }

        public void UpdateWebMetrics(double innerWidth, double innerHeight,
            double clientWidth, double clientHeight,
            double devicePixelRatio, double visualViewportWidth, double visualViewportHeight,
            string reason)
        {
            double cssW = FirstPositive(clientWidth, innerWidth, visualViewportWidth);
            double cssH = FirstPositive(clientHeight, innerHeight, visualViewportHeight);

            if (cssW > 0 && cssH > 0)
            {
                WebCssWidth = cssW;
                WebCssHeight = cssH;
                HasWebMetrics = true;
            }

            if (devicePixelRatio > 0)
                DevicePixelRatio = devicePixelRatio;
            VisualViewportWidth = visualViewportWidth;
            VisualViewportHeight = visualViewportHeight;
            LastReason = reason ?? "web_metrics";
        }

        public double CssToPhysicalX
        {
            get
            {
                if (HasWebMetrics && WebCssWidth > 0 && OverlayPhysicalBounds.Width > 0)
                    return NormalizeScale(OverlayPhysicalBounds.Width / WebCssWidth);
                return _fallbackZoom;
            }
        }

        public double CssToPhysicalY
        {
            get
            {
                if (HasWebMetrics && WebCssHeight > 0 && OverlayPhysicalBounds.Height > 0)
                    return NormalizeScale(OverlayPhysicalBounds.Height / WebCssHeight);
                return _fallbackZoom;
            }
        }

        public double PhysicalToCssX
        {
            get { return 1.0 / CssToPhysicalX; }
        }

        public double PhysicalToCssY
        {
            get { return 1.0 / CssToPhysicalY; }
        }

        public Rectangle CssRectToPhysical(double x, double y, double width, double height)
        {
            double sx = CssToPhysicalX;
            double sy = CssToPhysicalY;
            int left = (int)Math.Floor(x * sx);
            int top = (int)Math.Floor(y * sy);
            int right = (int)Math.Ceiling((x + width) * sx);
            int bottom = (int)Math.Ceiling((y + height) * sy);
            return new Rectangle(left, top, Math.Max(0, right - left), Math.Max(0, bottom - top));
        }

        public Point PhysicalPointToCss(int physicalX, int physicalY)
        {
            if (physicalX < 0 || physicalY < 0)
                return new Point(physicalX, physicalY);

            return new Point(
                (int)Math.Round(physicalX * PhysicalToCssX),
                (int)Math.Round(physicalY * PhysicalToCssY));
        }

        public string Describe()
        {
            return "bounds=" + OverlayPhysicalBounds
                + " css=" + WebCssWidth.ToString("0.##") + "x" + WebCssHeight.ToString("0.##")
                + " dpr=" + DevicePixelRatio.ToString("0.###")
                + " scale=" + CssToPhysicalX.ToString("0.###") + "x" + CssToPhysicalY.ToString("0.###")
                + " dpi=" + WindowDpiX + "x" + WindowDpiY
                + " dpiResolved=" + LastDpiResolved
                + " monitor=0x" + MonitorHandle.ToString("X")
                + " metrics=" + HasWebMetrics
                + " reason=" + LastReason;
        }

        private static double FirstPositive(double a, double b, double c)
        {
            if (a > 0) return a;
            if (b > 0) return b;
            if (c > 0) return c;
            return 0;
        }

        private static double NormalizeScale(double value)
        {
            if (double.IsNaN(value) || double.IsInfinity(value) || value < MinScale)
                return 1.0;
            return value;
        }
    }
}
