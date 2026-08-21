using System;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Flash HWND BitBlt 截图 + DPI 探针 + letterbox 检测 + 强制 alpha=255。
    ///
    /// DPI 策略：输出始终保持 GetClientRect 的物理尺寸。对于 DPI Unaware 的 Flash SA，
    /// GDI client DC 暴露的是 96-DPI 逻辑缓冲；在高 DPI 显示器上直接按物理尺寸 BitBlt
    /// 会把右侧/底部留黑。该模式按 windowDpi/monitorDpi 计算源缓冲，并 StretchBlt 回
    /// 物理输出尺寸；其他 awareness 模式仍按 1:1 捕获。
    ///
    /// Letterbox 用已知 16:9 设计宽高比检测，不做像素扫描——返回 contentRect 让 backdrop
    /// 仅对内容区做 dim，letterbox 黑边保留原样。
    /// </summary>
    public static class FlashSnapshot
    {
        #region Win32

        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("user32.dll")]
        private static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool BitBlt(IntPtr hdcDest, int xDest, int yDest, int wDest, int hDest,
            IntPtr hdcSrc, int xSrc, int ySrc, uint rop);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool StretchBlt(
            IntPtr hdcDest, int xDest, int yDest, int wDest, int hDest,
            IntPtr hdcSrc, int xSrc, int ySrc, int wSrc, int hSrc,
            uint rop);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern int SetStretchBltMode(IntPtr hdc, int mode);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool SetBrushOrgEx(
            IntPtr hdc, int x, int y, out POINT previous);

        // Win10 1607+; older systems get 96 fallback via try/catch
        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hWnd);

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int left, top, right, bottom; }

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int x, y; }

        private const uint SRCCOPY = 0x00CC0020;
        private const int HALFTONE = 4;

        #endregion

        public sealed class SnapshotResult
        {
            public Bitmap FullSnapshot;
            public Rectangle ContentRect;
            public int PhysicalW;
            public int PhysicalH;
            public int SourceW;
            public int SourceH;
        }

        internal struct FrameSampleStats
        {
            public int AverageLuminance;
            public int MinimumLuminance;
            public int MaximumLuminance;
            public int Variance;
            public int HighlightCount;
            public int SampleCount;
            public bool IsLikelyBlack;
        }

        private const float DESIGN_ASPECT = 1024f / 576f; // 16:9
        private const float ASPECT_TOLERANCE = 0.005f;

        private static int _dpiProbeCount;

        private static bool ShouldLogDpiProbe()
        {
            return Interlocked.Increment(ref _dpiProbeCount) <= 5;
        }

        private static uint SafeGetDpiForWindow(IntPtr hwnd)
        {
            try { return GetDpiForWindow(hwnd); }
            catch { return 96u; }
        }

        /// <summary>
        /// 抓 Flash HWND 当前显示内容到 32bpp Argb Bitmap（强制 alpha=255）。
        /// 失败抛 Exception；调用方走 ResetToClosedState。
        /// </summary>
        public static SnapshotResult Capture(IntPtr flashHwnd)
        {
            if (flashHwnd == IntPtr.Zero)
                throw new ArgumentException("flashHwnd is Zero", "flashHwnd");

            RECT clientRect;
            if (!GetClientRect(flashHwnd, out clientRect))
                throw new InvalidOperationException("GetClientRect failed for flashHwnd=0x" + flashHwnd.ToInt64().ToString("X"));

            int rectW = clientRect.right - clientRect.left;
            int rectH = clientRect.bottom - clientRect.top;
            if (rectW <= 0 || rectH <= 0)
                throw new InvalidOperationException("Flash client rect empty: " + rectW + "x" + rectH);

            EffectiveDpiAwareness awareness = DpiAwarenessBootstrap.GetEffectiveAwarenessForWindow(flashHwnd);
            uint dpi = SafeGetDpiForWindow(flashHwnd);
            uint monitorDpiX = 96u;
            uint monitorDpiY = 96u;
            DpiDiagnostics.TryGetMonitorDpi(
                DpiDiagnostics.GetMonitorFromWindow(flashHwnd),
                out monitorDpiX,
                out monitorDpiY);
            int physicalW, physicalH;
            ComputePhysicalSize(rectW, rectH, awareness, dpi, out physicalW, out physicalH);
            int sourceW, sourceH;
            ComputeCaptureSourceSize(
                physicalW,
                physicalH,
                awareness,
                dpi,
                monitorDpiX,
                monitorDpiY,
                out sourceW,
                out sourceH);
            bool virtualizedScale = sourceW != physicalW || sourceH != physicalH;

            if (ShouldLogDpiProbe())
            {
                LogManager.Log("[FlashSnapshot] probe: client=" + rectW + "x" + rectH
                    + " awareness=" + awareness
                    + " windowDpi=" + dpi
                    + " monitorDpi=" + monitorDpiX + "x" + monitorDpiY
                    + " source=" + sourceW + "x" + sourceH
                    + " output=" + physicalW + "x" + physicalH
                    + " virtualizedScale=" + virtualizedScale);
            }

            Bitmap bmp = new Bitmap(physicalW, physicalH, PixelFormat.Format32bppArgb);
            try
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    IntPtr srcDC = GetDC(flashHwnd);
                    if (srcDC == IntPtr.Zero)
                        throw new InvalidOperationException("GetDC returned Zero for flashHwnd=0x" + flashHwnd.ToInt64().ToString("X"));
                    try
                    {
                        IntPtr dstDC = IntPtr.Zero;
                        try
                        {
                            dstDC = g.GetHdc();
                            bool copied;
                            if (virtualizedScale)
                            {
                                int previousMode = SetStretchBltMode(dstDC, HALFTONE);
                                POINT previousOrigin;
                                bool hasPreviousOrigin = SetBrushOrgEx(
                                    dstDC,
                                    0,
                                    0,
                                    out previousOrigin);
                                try
                                {
                                    copied = StretchBlt(
                                        dstDC,
                                        0,
                                        0,
                                        physicalW,
                                        physicalH,
                                        srcDC,
                                        0,
                                        0,
                                        sourceW,
                                        sourceH,
                                        SRCCOPY);
                                }
                                finally
                                {
                                    if (hasPreviousOrigin)
                                    {
                                        POINT ignored;
                                        SetBrushOrgEx(
                                            dstDC,
                                            previousOrigin.x,
                                            previousOrigin.y,
                                            out ignored);
                                    }
                                    if (previousMode != 0)
                                        SetStretchBltMode(dstDC, previousMode);
                                }
                            }
                            else
                            {
                                copied = BitBlt(
                                    dstDC,
                                    0,
                                    0,
                                    physicalW,
                                    physicalH,
                                    srcDC,
                                    0,
                                    0,
                                    SRCCOPY);
                            }
                            if (!copied)
                            {
                                throw new Win32Exception(
                                    Marshal.GetLastWin32Error(),
                                    virtualizedScale
                                        ? "StretchBlt failed while capturing Flash"
                                        : "BitBlt failed while capturing Flash");
                            }
                        }
                        finally
                        {
                            if (dstDC != IntPtr.Zero) g.ReleaseHdc(dstDC);
                        }
                    }
                    finally { ReleaseDC(flashHwnd, srcDC); }
                }

                ForceAlphaOpaque(bmp);

                Rectangle contentRect = ComputeContentRectByAspectRatio(physicalW, physicalH);
                SnapshotResult result = new SnapshotResult();
                result.FullSnapshot = bmp;
                result.ContentRect = contentRect;
                result.PhysicalW = physicalW;
                result.PhysicalH = physicalH;
                result.SourceW = sourceW;
                result.SourceH = sourceH;
                bmp = null; // ownership transferred
                return result;
            }
            finally
            {
                if (bmp != null) bmp.Dispose();
            }
        }

        /// <summary>
        /// 输出保持 GetClientRect 的物理像素尺寸。internal static 便于单测。
        /// </summary>
        internal static void ComputePhysicalSize(int clientW, int clientH, EffectiveDpiAwareness awareness, uint dpi,
                                                 out int physicalW, out int physicalH)
        {
            physicalW = clientW;
            physicalH = clientH;
        }

        /// <summary>
        /// 计算 GDI 源 DC 的实际逻辑缓冲尺寸。DPI Unaware 窗口在高 DPI 显示器上由
        /// Windows 虚拟化放大：GetClientRect 对 PMv2 Host 可见的是物理尺寸，但该窗口
        /// 的 client DC 仍以 windowDpi（通常 96）解释。其他 awareness 或无有效高 DPI
        /// 差值时保持 1:1，避免重复缩放 DPI-aware 窗口。
        /// </summary>
        internal static void ComputeCaptureSourceSize(
            int outputW,
            int outputH,
            EffectiveDpiAwareness awareness,
            uint windowDpi,
            uint monitorDpiX,
            uint monitorDpiY,
            out int sourceW,
            out int sourceH)
        {
            sourceW = outputW;
            sourceH = outputH;
            if (outputW <= 0
                || outputH <= 0
                || awareness != EffectiveDpiAwareness.Unaware
                || windowDpi < 72u
                || (monitorDpiX <= windowDpi
                    && monitorDpiY <= windowDpi))
            {
                return;
            }

            if (monitorDpiX > windowDpi)
            {
                sourceW = Math.Max(
                    1,
                    Math.Min(
                        outputW,
                        (int)Math.Round(
                            outputW * (double)windowDpi / monitorDpiX,
                            MidpointRounding.AwayFromZero)));
            }
            if (monitorDpiY > windowDpi)
            {
                sourceH = Math.Max(
                    1,
                    Math.Min(
                        outputH,
                        (int)Math.Round(
                            outputH * (double)windowDpi / monitorDpiY,
                            MidpointRounding.AwayFromZero)));
            }
        }

        /// <summary>
        /// 用 LockBits + 复用 thread-local byte 缓冲强制 alpha=255。
        /// 不依赖 unsafe block；缓冲一次分配长期持有，避免每次分配 8MB byte[] 进 LOH。
        /// </summary>
        [ThreadStatic] private static byte[] _alphaBuffer;

        private static void ForceAlphaOpaque(Bitmap bmp)
        {
            BitmapData data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height),
                ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            try
            {
                int bytes = data.Stride * data.Height;
                if (_alphaBuffer == null || _alphaBuffer.Length < bytes)
                    _alphaBuffer = new byte[bytes];

                Marshal.Copy(data.Scan0, _alphaBuffer, 0, bytes);

                int width = data.Width;
                int height = data.Height;
                int stride = data.Stride;
                for (int y = 0; y < height; y++)
                {
                    int rowOffset = y * stride;
                    for (int x = 0; x < width; x++)
                        _alphaBuffer[rowOffset + x * 4 + 3] = 255; // BGRA: A 通道
                }

                Marshal.Copy(_alphaBuffer, 0, data.Scan0, bytes);
            }
            finally { bmp.UnlockBits(data); }
        }

        /// <summary>
        /// 基于 16:9 设计宽高比计算内容区。internal 便于单测访问。
        /// </summary>
        internal static Rectangle ComputeContentRectByAspectRatio(int w, int h)
        {
            if (w <= 0 || h <= 0) return new Rectangle(0, 0, w, h);
            float actual = (float)w / h;
            if (Math.Abs(actual - DESIGN_ASPECT) < ASPECT_TOLERANCE)
                return new Rectangle(0, 0, w, h);
            if (actual > DESIGN_ASPECT)
            {
                int contentW = (int)(h * DESIGN_ASPECT);
                int x = (w - contentW) / 2;
                return new Rectangle(x, 0, contentW, h);
            }
            else
            {
                int contentH = (int)(w / DESIGN_ASPECT);
                int y = (h - contentH) / 2;
                return new Rectangle(0, y, w, contentH);
            }
        }

        /// <summary>
        /// 黑帧检测：在 contentRect 内 16x16 固定均匀网格采样，不查 alpha。
        /// Flash 游戏本身有大量低亮场景，不能再把“平均亮度低于 30”直接等同空帧。
        /// 只有低亮且近乎均匀、没有成组高光或有效对比的画面才视为 BitBlt 空黑帧。
        /// </summary>
        public static bool IsLikelyBlackFrame(Bitmap b, Rectangle? contentRect)
        {
            return AnalyzeFrame(b, contentRect).IsLikelyBlack;
        }

        internal static FrameSampleStats AnalyzeFrame(Bitmap b, Rectangle? contentRect)
        {
            FrameSampleStats stats = new FrameSampleStats
            {
                MinimumLuminance = 255,
                IsLikelyBlack = true
            };
            if (b == null) return stats;

            Rectangle bounds = new Rectangle(0, 0, b.Width, b.Height);
            Rectangle requested = contentRect.HasValue ? contentRect.Value : bounds;
            Rectangle area = Rectangle.Intersect(bounds, requested);
            if (area.Width <= 0 || area.Height <= 0) return stats;

            const int GRID = 16;
            const int HIGHLIGHT_LUMINANCE = 52;
            long lumSum = 0;
            long lumSquaredSum = 0;
            for (int gy = 0; gy < GRID; gy++)
            {
                for (int gx = 0; gx < GRID; gx++)
                {
                    int x = area.X + (area.Width * (gx * 2 + 1)) / (GRID * 2);
                    int y = area.Y + (area.Height * (gy * 2 + 1)) / (GRID * 2);
                    if (x > area.Right - 1) x = area.Right - 1;
                    if (y > area.Bottom - 1) y = area.Bottom - 1;
                    Color c = b.GetPixel(x, y);
                    int luminance = (c.R + c.G + c.B) / 3;
                    lumSum += luminance;
                    lumSquaredSum += luminance * luminance;
                    if (luminance < stats.MinimumLuminance) stats.MinimumLuminance = luminance;
                    if (luminance > stats.MaximumLuminance) stats.MaximumLuminance = luminance;
                    if (luminance >= HIGHLIGHT_LUMINANCE) stats.HighlightCount++;
                    stats.SampleCount++;
                }
            }

            if (stats.SampleCount <= 0) return stats;
            stats.AverageLuminance = (int)(lumSum / stats.SampleCount);
            double average = (double)lumSum / stats.SampleCount;
            double variance = (double)lumSquaredSum / stats.SampleCount - average * average;
            stats.Variance = (int)Math.Round(Math.Max(0d, variance));
            int span = stats.MaximumLuminance - stats.MinimumLuminance;
            bool hasGroupedHighlights = stats.HighlightCount >= 2;
            bool hasVisibleContrast = span >= 18 && stats.Variance >= 24;
            stats.IsLikelyBlack = stats.AverageLuminance < 30
                && !hasGroupedHighlights
                && !hasVisibleContrast;
            return stats;
        }

        /// <summary>
        /// Backdrop 合成：从 fullSnapshot 中按 contentRect 裁切出 16:9 内容区，
        /// 输出尺寸 = contentRect 尺寸（与 backdrop 显示区域 = WebOverlay.Bounds = 扣 letterbox 后的 viewport 一致）。
        ///
        /// 修复 letterbox 错位：
        /// - WebOverlay.Bounds 来自 CalcViewport()，是已扣掉 letterbox 黑边的 16:9 区
        /// - FlashSnapshot.Capture 返回 flash HWND 全 client（含 letterbox 黑边）
        /// - 用户手动拉成非 16:9 时，旧实现 DrawImageUnscaled 会把 (0,0) 对齐 backdrop 左上 →
        ///   背景图带着 letterbox 黑边原点画进 16:9 backdrop → 错位 + 裁切
        /// 现在裁出 contentRect 与 backdrop 同尺寸；letterbox 黑边在 backdrop 之外（被 NativePanelBackdrop 自身的 BackColor=Black 覆盖）。
        /// </summary>
        public static Bitmap ComposeBackdrop(Bitmap fullSnapshot, Rectangle contentRect, byte dimAlpha)
        {
            if (fullSnapshot == null) throw new ArgumentNullException("fullSnapshot");
            // 防御：contentRect 退化时退回 full size
            int outW = contentRect.Width > 0 ? contentRect.Width : fullSnapshot.Width;
            int outH = contentRect.Height > 0 ? contentRect.Height : fullSnapshot.Height;
            Rectangle src = (contentRect.Width > 0 && contentRect.Height > 0)
                ? contentRect
                : new Rectangle(0, 0, fullSnapshot.Width, fullSnapshot.Height);

            Bitmap result = new Bitmap(outW, outH, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(result))
            {
                Rectangle dst = new Rectangle(0, 0, outW, outH);
                g.DrawImage(fullSnapshot, dst, src, GraphicsUnit.Pixel);
                if (dimAlpha > 0)
                {
                    using (SolidBrush brush = new SolidBrush(Color.FromArgb(dimAlpha, 0, 0, 0)))
                        g.FillRectangle(brush, dst);
                }
            }
            return result;
        }
    }
}
