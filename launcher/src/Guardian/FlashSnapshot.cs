using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Flash HWND BitBlt 截图 + DPI 探针 + letterbox 检测 + 强制 alpha=255。
    ///
    /// DPI 策略：默认假设所有 DPI-aware 模式下 GetClientRect 返回物理像素（按 MS 文档）；
    /// 启动期前 5 次记录探针 log（GetClientRect/GetDpiForWindow/awareness/物理尺寸），
    /// 若实测发现某模式需要缩放分支 → 在 ComputePhysicalSize 加 case + 单测固化（TDD）。
    /// 不预先硬编码"V1 vs 非 V1"分支。
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

        [DllImport("gdi32.dll")]
        private static extern bool BitBlt(IntPtr hdcDest, int xDest, int yDest, int wDest, int hDest,
            IntPtr hdcSrc, int xSrc, int ySrc, uint rop);

        // Win10 1607+; older systems get 96 fallback via try/catch
        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hWnd);

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int left, top, right, bottom; }

        private const uint SRCCOPY = 0x00CC0020;

        #endregion

        public sealed class SnapshotResult
        {
            public Bitmap FullSnapshot;
            public Rectangle ContentRect;
            public int PhysicalW;
            public int PhysicalH;
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
            int physicalW, physicalH;
            ComputePhysicalSize(rectW, rectH, awareness, dpi, out physicalW, out physicalH);

            if (ShouldLogDpiProbe())
            {
                LogManager.Log("[FlashSnapshot] probe: client=" + rectW + "x" + rectH
                    + " awareness=" + awareness
                    + " dpi=" + dpi
                    + " physical=" + physicalW + "x" + physicalH);
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
                            BitBlt(dstDC, 0, 0, physicalW, physicalH, srcDC, 0, 0, SRCCOPY);
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
                bmp = null; // ownership transferred
                return result;
            }
            finally
            {
                if (bmp != null) bmp.Dispose();
            }
        }

        /// <summary>
        /// 探针数据驱动的 DPI 缩放决策。internal static 便于 InternalsVisibleTo 单测。
        /// 默认：所有 awareness 模式下 GetClientRect = physical pixels（与 MS 文档对齐），不缩放。
        /// 若 Phase 2 启动期探针发现某模式实际偏差 → 在此函数加分支 + 单测覆盖。
        /// </summary>
        internal static void ComputePhysicalSize(int clientW, int clientH, EffectiveDpiAwareness awareness, uint dpi,
                                                 out int physicalW, out int physicalH)
        {
            physicalW = clientW;
            physicalH = clientH;
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
        /// 黑帧检测：在 contentRect 内 10x10 固定均匀网格采样，不查 alpha。
        /// 平均亮度 < 30 视为黑帧（Flash SA 偶发空窗）。
        /// </summary>
        public static bool IsLikelyBlackFrame(Bitmap b, Rectangle? contentRect)
        {
            if (b == null) return true;
            Rectangle area = contentRect.HasValue ? contentRect.Value : new Rectangle(0, 0, b.Width, b.Height);
            if (area.Width <= 0 || area.Height <= 0) return true;

            const int GRID = 10;
            long lumSum = 0;
            int count = 0;
            for (int gy = 0; gy < GRID; gy++)
            {
                for (int gx = 0; gx < GRID; gx++)
                {
                    int x = area.X + (area.Width * gx) / GRID + area.Width / (GRID * 2);
                    int y = area.Y + (area.Height * gy) / GRID + area.Height / (GRID * 2);
                    if (x < area.X) x = area.X;
                    if (x > area.Right - 1) x = area.Right - 1;
                    if (y < area.Y) y = area.Y;
                    if (y > area.Bottom - 1) y = area.Bottom - 1;
                    Color c = b.GetPixel(x, y);
                    lumSum += (c.R + c.G + c.B) / 3;
                    count++;
                }
            }
            return count > 0 && (lumSum / count) < 30;
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
