// GPU 渲染管线所需的 Win32 P/Invoke 声明
// Phase 0 Spike + Phase 1 GpuRenderer 共用

using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace CF7Launcher.Render
{
    static class RenderNativeMethods
    {
        // ── PrintWindow ──

        [DllImport("user32.dll")]
        public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);

        /// <summary>Win7 兼容：flag=0。PW_CLIENTONLY=1 仅客户区。PW_RENDERFULLCONTENT=2 仅 Win8.1+。</summary>
        public const uint PW_CLIENTONLY = 1;

        // ── BitBlt ──

        [DllImport("gdi32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool BitBlt(
            IntPtr hdcDest, int xDest, int yDest, int width, int height,
            IntPtr hdcSrc, int xSrc, int ySrc, uint rop);

        public const uint SRCCOPY = 0x00CC0020;

        // ── DC 操作 ──

        [DllImport("user32.dll")]
        public static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        // ── 窗口区域（SetWindowRgn 隐藏窗口可见区域但保持渲染）──

        [DllImport("gdi32.dll")]
        public static extern IntPtr CreateRectRgn(int x1, int y1, int x2, int y2);

        [DllImport("user32.dll")]
        public static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);

        // ── 窗口尺寸 ──

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;

            public int Width { get { return Right - Left; } }
            public int Height { get { return Bottom - Top; } }
        }
    }
}
