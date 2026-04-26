using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Panel 态背景层。
    ///
    /// 故意不继承 OverlayBase（layered window）：
    /// 普通不透明 Form 让 DWM 按 opaque surface 合成，避免 per-pixel α traversal。
    /// 这是消除 ~15pp iGPU floor 的核心一环。
    ///
    /// 职责：
    /// - 在 panel 态显示一张 pre-composed 截图（Flash 当前帧 + dim 蒙版）作为背景
    /// - 接收 panel 矩形外的 click，转发为 panel_esc（等价 web backdrop click）
    ///
    /// z-order：在 Flash 之上、WebOverlayForm 之下（panel 态序列顺序保证）。
    /// </summary>
    public class NativePanelBackdrop : Form
    {
        #region Win32

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const int SW_HIDE = 0;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const uint SWP_SHOWWINDOW = 0x0040;
        private const uint SWP_FRAMECHANGED = 0x0020;
        private const uint SWP_NOZORDER = 0x0004;

        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;

        #endregion

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
                return cp;
            }
        }

        private Bitmap _composed;
        private Rectangle? _panelRectClient; // panel 矩形 → backdrop client 坐标，OnMouseDown 用

        /// <summary>
        /// panel 矩形外的 click。PanelHostController 订阅 → PostToWeb panel_esc。
        /// </summary>
        public event Action BackdropClickedOutsidePanel;

        public NativePanelBackdrop(Form owner)
        {
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            Owner = owner;
            BackColor = Color.Black;
            DoubleBuffered = true;

            // 创建时不可见；SetComposedAndShow 才显示
            this.CreateControl();
            ShowWindow(this.Handle, SW_HIDE);
        }

        /// <summary>
        /// 设置 pre-composed 背景图并显示在 anchorScreen（屏幕坐标）位置。
        /// PanelHostController.DoOpen step 3 调用。
        /// </summary>
        public void SetComposedAndShow(Bitmap composed, Rectangle anchorScreen)
        {
            if (_composed != null && _composed != composed)
            {
                _composed.Dispose();
            }
            _composed = composed;

            SetWindowPos(this.Handle, HWND_TOP,
                anchorScreen.X, anchorScreen.Y,
                anchorScreen.Width, anchorScreen.Height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
            this.Invalidate();
        }

        /// <summary>
        /// 通知 backdrop panel 矩形位置（屏幕坐标）。OnMouseDown 用此判断 click 是内/外。
        /// 必须在 SetComposedAndShow 之后调用（依赖 this.Bounds 已就绪）。
        /// </summary>
        public void SetPanelRect(Rectangle panelRectScreen)
        {
            _panelRectClient = new Rectangle(
                panelRectScreen.X - this.Bounds.X,
                panelRectScreen.Y - this.Bounds.Y,
                panelRectScreen.Width,
                panelRectScreen.Height);
        }

        /// <summary>
        /// owner 移动/大小变化时仅重定位 backdrop 自身（不重绘 _composed）。
        /// 由 PanelHostController.OnOwnerLayoutChanged 调用。
        /// SWP_NOZORDER 避免拖窗时高频 z-order 重排抢焦点；不加 SWP_FRAMECHANGED 跳过 NCPAINT。
        /// </summary>
        public void RepositionTo(Rectangle anchorScreen)
        {
            SetWindowPos(this.Handle, IntPtr.Zero,
                anchorScreen.X, anchorScreen.Y,
                anchorScreen.Width, anchorScreen.Height,
                SWP_NOACTIVATE | SWP_NOZORDER);
        }

        public new void Hide()
        {
            ShowWindow(this.Handle, SW_HIDE);
            if (_composed != null)
            {
                _composed.Dispose();
                _composed = null;
            }
            _panelRectClient = null;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            if (_composed != null)
            {
                e.Graphics.DrawImageUnscaled(_composed, 0, 0);
            }
            // 否则显示 BackColor=Black 兜底
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            // 抑制默认背景擦除：_composed 全覆盖时无意义；空图时 OnPaint 已绘 Black
            if (_composed == null)
                base.OnPaintBackground(e);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (!ShouldFireOutsidePanelClick(_panelRectClient, e.Location))
            {
                // panel 矩形内的 click 在 z-order 上由 WebOverlay 接（web 在 backdrop 之上）
                // 到这里说明 z-order 错位，记录 + swallow
                LogManager.Log("[Backdrop] click landed inside panel rect — z-order anomaly, swallowed");
                return;
            }

            Action handler = BackdropClickedOutsidePanel;
            if (handler != null)
            {
                try { handler(); }
                catch (Exception ex) { LogManager.Log("[Backdrop] click handler throw: " + ex.Message); }
            }
        }

        /// <summary>
        /// click 路由决策。internal static 便于单测。
        /// 返回 true 表示该 click 应该 fire BackdropClickedOutsidePanel；false 表示在 panel 矩形内（防御性 swallow）。
        ///
        /// 语义：
        /// - panelRectClient == null：尚未 SetPanelRect，视为"全部外部"（fire）。这是 panel 打开早期防御性默认
        /// - panelRectClient 已设 + clickPt 在内：z-order 错位，swallow
        /// - panelRectClient 已设 + clickPt 在外：正常外部 click，fire
        /// </summary>
        internal static bool ShouldFireOutsidePanelClick(Rectangle? panelRectClient, Point clickClientPt)
        {
            if (!panelRectClient.HasValue) return true;
            return !panelRectClient.Value.Contains(clickClientPt);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_composed != null) { _composed.Dispose(); _composed = null; }
            }
            base.Dispose(disposing);
        }
    }
}
