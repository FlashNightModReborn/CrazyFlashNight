using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 逐像素 Alpha Layered Window 覆盖层抽象基类。
    ///
    /// 提供：
    /// - Win32 P/Invoke 声明（UpdateLayeredWindow、ShowWindow、SetWindowPos 等）
    /// - CreateParams（WS_EX_LAYERED | TOOLWINDOW | NOACTIVATE，可选 WS_EX_TRANSPARENT）
    /// - WndProc HTTRANSPARENT（仅 IsClickThrough 时启用）
    /// - Owner 跟随（Activated/Deactivated/Minimized → Show/Hide）
    /// - CommitBitmap() 统一提交
    /// - ShowOverlay / HideOverlay / DismissOverlay 三分法
    ///
    /// 子类只需实现渲染逻辑（PaintLayered），无需关心 Win32 基础设施。
    /// </summary>
    public abstract class OverlayBase : Form
    {
        #region Win32

        [DllImport("user32.dll")]
        protected static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        protected static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst,
            ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc,
            ref POINT pptSrc, uint crKey, ref BLENDFUNCTION pblend, uint dwFlags);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll", ExactSpelling = true)]
        private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hObj);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteObject(IntPtr hObj);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteDC(IntPtr hdc);

        [StructLayout(LayoutKind.Sequential)]
        protected struct POINT { public int x, y; }

        [StructLayout(LayoutKind.Sequential)]
        protected struct SIZE { public int cx, cy; }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct BLENDFUNCTION
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        protected const int SW_SHOWNOACTIVATE = 4;
        protected const int SW_HIDE = 0;
        protected static readonly IntPtr HWND_TOP = new IntPtr(0);
        protected const uint SWP_NOMOVE = 0x0002;
        protected const uint SWP_NOSIZE = 0x0001;
        protected const uint SWP_NOACTIVATE = 0x0010;
        private const byte AC_SRC_OVER = 0x00;
        private const byte AC_SRC_ALPHA = 0x01;
        private const uint ULW_ALPHA = 0x02;

        protected const int WS_EX_TOOLWINDOW = 0x00000080;
        protected const int WS_EX_NOACTIVATE = 0x08000000;
        protected const int WS_EX_LAYERED = 0x00080000;
        protected const int WS_EX_TRANSPARENT = 0x00000020;
        protected const int WM_NCHITTEST = 0x0084;
        protected const int WM_DPICHANGED = 0x02E0;
        protected const int HTTRANSPARENT = -1;

        #endregion

        protected readonly Form _owner;
        protected readonly Control _anchor;
        protected readonly FlashCoordinateMapper _mapper;
        protected bool _shown;
        protected bool _ownerVisible;

        /// <summary>
        /// 是否点击穿透。默认 true（Toast/HitNumber）。
        /// NotchOverlay 需返回 false 以接收鼠标事件。
        /// </summary>
        protected virtual bool IsClickThrough { get { return true; } }

        private bool CanUseExistingHandle()
        {
            try
            {
                return !this.IsDisposed && !this.Disposing && this.IsHandleCreated;
            }
            catch
            {
                return false;
            }
        }

        protected OverlayBase(Form owner, Control anchor, float stageW, float stageH)
        {
            _owner = owner;
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, stageW, stageH);
            _shown = false;
            _ownerVisible = true;

            this.FormBorderStyle = FormBorderStyle.None;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.Manual;
            this.AutoScaleMode = AutoScaleMode.None;
            this.Owner = owner;

            CreateHandle();

            // 位置跟踪
            owner.Move += delegate { OnPositionChanged(); };
            owner.Resize += delegate { OnPositionChanged(); };
            anchor.Resize += delegate { OnPositionChanged(); };

            // Owner 可见性跟踪
            owner.Activated += delegate { OnOwnerActivated(); };
            owner.Deactivate += delegate { OnOwnerDeactivated(); };
            owner.Resize += delegate
            {
                if (owner.WindowState == FormWindowState.Minimized)
                    OnOwnerDeactivated();
                else
                    OnOwnerActivated();
            };
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED;
                if (IsClickThrough)
                    cp.ExStyle |= WS_EX_TRANSPARENT;
                return cp;
            }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_DPICHANGED)
            {
                OnPositionChanged();
            }

            if (IsClickThrough && m.Msg == WM_NCHITTEST)
            {
                m.Result = (IntPtr)HTTRANSPARENT;
                return;
            }
            base.WndProc(ref m);
        }

        #region Owner 跟随

        private void OnOwnerActivated()
        {
            if (this.IsDisposed || this.Disposing) return;
            _ownerVisible = true;
            if (_shown)
            {
                if (!CanUseExistingHandle()) return;
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                OnOwnerBecameVisible();
            }
        }

        private void OnOwnerDeactivated()
        {
            if (this.IsDisposed || this.Disposing) return;
            _ownerVisible = false;
            if (_shown)
                HideOverlay();
            if (!this.IsDisposed && !this.Disposing)
                OnOwnerBecameHidden();
        }

        /// <summary>Owner 回到前台时调用。子类可 override 以触发重绘。</summary>
        protected virtual void OnOwnerBecameVisible() { }

        /// <summary>Owner 离开前台时调用。</summary>
        protected virtual void OnOwnerBecameHidden() { }

        #endregion

        #region Show / Hide / Dismiss 三分法

        /// <summary>
        /// 显示 overlay：标记 _shown + 实际显示 + 置顶（HWND_TOP）。
        /// </summary>
        protected void ShowOverlay()
        {
            _shown = true;
            if (_ownerVisible)
            {
                if (!CanUseExistingHandle()) return;
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
        }

        /// <summary>
        /// 显示 overlay 并插在 insertAfter 之**后**（视觉上即 insertAfter 在本窗口之上）。
        ///
        /// MSDN SetWindowPos: hWndInsertAfter 是 "A handle to the window to precede the positioned window
        /// in the Z order."——即调用后 z-order 上 [insertAfter] 在前/在上、[本窗口] 紧跟其后。
        /// 名字 "Below" 指的就是本窗口被放在 insertAfter 之下。
        ///
        /// 用例：NativeHud 需要位于 HitNumber/Cursor 之下，不能用 HWND_TOP（会浮到这两层之上）。
        ///   ShowOverlayBelow(hitNumberOverlay.Handle)
        /// 之后 z-order：HitNumber → NativeHud → ...
        ///
        /// 特殊取值：HWND_TOP=(IntPtr)0 → 等同 ShowOverlay；HWND_BOTTOM=(IntPtr)1 → 沉到底。
        /// </summary>
        protected void ShowOverlayBelow(IntPtr insertAfter)
        {
            _shown = true;
            if (_ownerVisible)
            {
                if (!CanUseExistingHandle()) return;
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                SetWindowPos(this.Handle, insertAfter, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
        }

        /// <summary>
        /// 临时隐藏：仅隐藏窗口，保留 _shown。
        /// 用于 owner 失焦时临时隐藏，回焦后可通过 _shown 恢复。
        /// </summary>
        protected void HideOverlay()
        {
            if (!CanUseExistingHandle()) return;
            ShowWindow(this.Handle, SW_HIDE);
            // 注意：不改 _shown
        }

        /// <summary>
        /// 永久隐藏：清除 _shown + 隐藏窗口。
        /// 用于内容过期/reset 时，防止回焦误恢复。
        /// </summary>
        protected void DismissOverlay()
        {
            _shown = false;
            if (!CanUseExistingHandle()) return;
            ShowWindow(this.Handle, SW_HIDE);
        }

        #endregion

        #region 工具方法

        /// <summary>
        /// 获取 anchor 控件在屏幕上的原点坐标。封装 try-catch。
        /// </summary>
        protected bool GetAnchorScreenOrigin(out Point origin)
        {
            try
            {
                origin = _anchor.PointToScreen(Point.Empty);
                return true;
            }
            catch
            {
                origin = Point.Empty;
                return false;
            }
        }

        /// <summary>
        /// P2-3 perf：ULW 首帧预提交。在玩家可见之前提交一次 1×1 透明位图，让 DWM 把窗口
        /// 加入合成树 + per-pixel α 路径建立，避免第一次真实 commit 时叠加冷启动开销。
        /// 调用时机：handle 已创建即可，无需 ready 状态。1×1 位图不会闪烁。
        /// </summary>
        public void PreCommitTransparent()
        {
            if (!CanUseExistingHandle()) return;
            try
            {
                using (Bitmap warm = new Bitmap(1, 1, PixelFormat.Format32bppPArgb))
                {
                    warm.SetPixel(0, 0, Color.FromArgb(0, 0, 0, 0));
                    CommitBitmap(warm, 0, 0, 0);
                }
            }
            catch (Exception ex) { LogManager.Log("[OverlayBase] PreCommitTransparent failed: " + ex.Message); }
        }

        /// <summary>
        /// 将 GDI+ Bitmap 提交到屏幕（UpdateLayeredWindow）。
        /// </summary>
        protected void CommitBitmap(Bitmap bmp, int screenX, int screenY, byte globalAlpha)
        {
            if (!CanUseExistingHandle()) return;
            IntPtr hdcScreen = IntPtr.Zero;
            IntPtr hdcMem = CreateCompatibleDC(hdcScreen);
            IntPtr hBmp = bmp.GetHbitmap(Color.FromArgb(0));
            IntPtr hOld = SelectObject(hdcMem, hBmp);

            try
            {
                POINT ptDst = new POINT { x = screenX, y = screenY };
                SIZE sz = new SIZE { cx = bmp.Width, cy = bmp.Height };
                POINT ptSrc = new POINT { x = 0, y = 0 };
                BLENDFUNCTION blend = new BLENDFUNCTION
                {
                    BlendOp = AC_SRC_OVER,
                    BlendFlags = 0,
                    SourceConstantAlpha = globalAlpha,
                    AlphaFormat = AC_SRC_ALPHA
                };

                UpdateLayeredWindow(this.Handle, hdcScreen,
                    ref ptDst, ref sz, hdcMem, ref ptSrc, 0, ref blend, ULW_ALPHA);
            }
            finally
            {
                SelectObject(hdcMem, hOld);
                DeleteObject(hBmp);
                DeleteDC(hdcMem);
            }
        }

        #endregion

        /// <summary>
        /// Owner 移动/缩放或 anchor 缩放时调用。子类应 override 以重新定位和重绘。
        /// </summary>
        protected virtual void OnPositionChanged() { }

        public void RequestPositionSync()
        {
            if (this.IsDisposed || this.Disposing) return;
            OnPositionChanged();
        }
    }
}
