using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 幽灵输入层：不可见的 GDI+ Layered Window，负责拦截 Web UI 交互区域的鼠标事件。
    ///
    /// 架构（Z-order 从上到下）：
    ///   InputShieldForm   ← 本类：α=1 命中区拦截鼠标 → CDP 注入 WebView2
    ///   WebOverlayForm    ← WS_EX_TRANSPARENT 纯视觉层，WebView2 渲染
    ///   Flash HWND        ← 正常接收所有穿透的点击
    ///   GuardianForm
    ///
    /// 边界问题处理：
    /// - TrackMouseEvent + WM_MOUSELEAVE：鼠标离开 α=1 区域时向 WebView2 发送 mouseMoved(-1,-1)
    ///   触发 CSS :hover 移除和 JS mouseleave，使 notch 自动收起
    /// - hitRect 变更时检查鼠标是否仍在区域内，若不在则发送 mouseReleased 清理按压状态
    ///   防止展开/收起导致的 Chromium 拖拽幻影
    /// </summary>
    public class InputShieldForm : OverlayBase
    {
        #region Win32 (TrackMouseEvent)

        [DllImport("user32.dll")]
        private static extern bool TrackMouseEvent(ref TRACKMOUSEEVENT lpEventTrack);

        [DllImport("user32.dll")]
        private static extern IntPtr SetCapture(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool ReleaseCapture();

        [StructLayout(LayoutKind.Sequential)]
        private struct TRACKMOUSEEVENT
        {
            public int cbSize;
            public uint dwFlags;
            public IntPtr hwndTrack;
            public int dwHoverTime;
        }

        private const uint TME_LEAVE = 0x00000002;

        #endregion

        private const int HTCLIENT = 1;
        private const int WM_MOUSEMOVE = 0x0200;
        private const int WM_LBUTTONDOWN = 0x0201;
        private const int WM_LBUTTONUP = 0x0202;
        private const int WM_RBUTTONDOWN = 0x0204;
        private const int WM_RBUTTONUP = 0x0205;
        private const int WM_MOUSELEAVE = 0x02A3;

        private const int WM_MOUSEACTIVATE = 0x0021;
        private const int MA_NOACTIVATE = 3;

        /// <summary>不穿透——本层需要在命中区域接收鼠标。</summary>
        protected override bool IsClickThrough { get { return false; } }

        /// <summary>JS 上报的交互区域（相对于本 Form 客户区）。</summary>
        private readonly List<Rectangle> _hitRects = new List<Rectangle>();

        /// <summary>当前 alpha 位图（缓存避免每帧重建）。</summary>
        private Bitmap _maskBitmap;
        private int _maskW;
        private int _maskH;

        /// <summary>WebOverlayForm 的 CoreWebView2 引用，用于 CDP 注入。</summary>
        private CoreWebView2 _targetWebView;

        /// <summary>当前 overlay 的屏幕坐标（CommitBitmap 需要）。</summary>
        private int _screenX;
        private int _screenY;

        /// <summary>鼠标是否在命中区域内（用于 leave 检测）。</summary>
        private bool _mouseTracking;
        private bool _mouseInside;

        /// <summary>鼠标按钮按下期间是否持有 capture。</summary>
        private bool _captured;

        public InputShieldForm(Form owner, Control anchor)
            : base(owner, anchor, 1024f, 576f)
        {
        }

        /// <summary>
        /// 注入 WebView2 引用。在 WebOverlayForm 初始化完成后调用。
        /// </summary>
        public void SetTargetWebView(CoreWebView2 webView)
        {
            _targetWebView = webView;
        }

        #region 命中区域管理

        /// <summary>
        /// 更新交互区域矩形列表。由 WebOverlayForm 在收到 JS hitRects 消息后调用。
        /// </summary>
        public void UpdateHitRects(List<Rectangle> rects)
        {
            _hitRects.Clear();
            _hitRects.AddRange(rects);
            RebuildMask();

            // hitRect 变更后，鼠标可能落在新 rect 之外（如 notch 收起）
            // 此时必须清理 CDP 状态，否则 Chromium 认为按钮仍被按住
            // 但 capture 期间不做 cleanup——down/up 配对由 SetCapture 保证
            if (_mouseInside && !_captured)
                CleanupIfMouseOutside();
        }

        /// <summary>
        /// 检查鼠标是否仍在命中区域内。若不在，发送 CDP mouseReleased + mouseMoved 清理状态。
        /// </summary>
        private void CleanupIfMouseOutside()
        {
            Point cursor = Cursor.Position;
            int lx = cursor.X - _screenX;
            int ly = cursor.Y - _screenY;

            bool still = false;
            foreach (Rectangle r in _hitRects)
            {
                if (r.Contains(lx, ly)) { still = true; break; }
            }

            if (!still)
            {
                _mouseInside = false;
                // 清理可能残留的按压状态
                DispatchCdpMouseAt("mouseReleased", lx, ly, "left");
                // 发送到视口外触发 CSS mouseleave
                DispatchCdpMouseAt("mouseMoved", -1, -1, "none");
            }
        }

        /// <summary>
        /// 重建 alpha 位图：命中区域 α=1，其余 α=0。
        /// </summary>
        private void RebuildMask()
        {
            if (_maskW <= 0 || _maskH <= 0) return;

            if (_maskBitmap == null || _maskBitmap.Width != _maskW || _maskBitmap.Height != _maskH)
            {
                if (_maskBitmap != null) _maskBitmap.Dispose();
                _maskBitmap = new Bitmap(_maskW, _maskH, PixelFormat.Format32bppPArgb);
            }

            using (Graphics g = Graphics.FromImage(_maskBitmap))
            {
                g.Clear(Color.FromArgb(0, 0, 0, 0));

                // 命中区域填充 α=1（肉眼不可见，但命中测试视为实心）
                using (SolidBrush b = new SolidBrush(Color.FromArgb(1, 0, 0, 0)))
                {
                    foreach (Rectangle r in _hitRects)
                    {
                        if (r.Width > 0 && r.Height > 0)
                            g.FillRectangle(b, r);
                    }
                }
            }

            CommitBitmap(_maskBitmap, _screenX, _screenY, 255);
        }

        #endregion

        #region 位置同步

        protected override void OnPositionChanged()
        {
            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);

            Point origin;
            if (!GetAnchorScreenOrigin(out origin)) return;

            _screenX = origin.X + (int)vpX;
            _screenY = origin.Y + (int)vpY;
            _maskW = Math.Max(1, (int)vpW);
            _maskH = Math.Max(1, (int)vpH);

            if (_shown)
                RebuildMask();
        }

        #endregion

        #region 命中测试 + 鼠标事件

        protected override void WndProc(ref Message m)
        {
            switch (m.Msg)
            {
                case WM_NCHITTEST:
                {
                    int lp = m.LParam.ToInt32();
                    int sx = (short)(lp & 0xFFFF);
                    int sy = (short)((lp >> 16) & 0xFFFF);
                    Point pt = new Point(sx - _screenX, sy - _screenY);

                    foreach (Rectangle r in _hitRects)
                    {
                        if (r.Contains(pt))
                        {
                            m.Result = (IntPtr)HTCLIENT;
                            return;
                        }
                    }
                    m.Result = (IntPtr)HTTRANSPARENT;
                    return;
                }

                case WM_MOUSEACTIVATE:
                    m.Result = (IntPtr)MA_NOACTIVATE;
                    return;

                case WM_MOUSEMOVE:
                {
                    // 首次进入命中区域时注册 WM_MOUSELEAVE 追踪
                    if (!_mouseTracking)
                    {
                        TRACKMOUSEEVENT tme = new TRACKMOUSEEVENT();
                        tme.cbSize = Marshal.SizeOf(typeof(TRACKMOUSEEVENT));
                        tme.dwFlags = TME_LEAVE;
                        tme.hwndTrack = this.Handle;
                        tme.dwHoverTime = 0;
                        TrackMouseEvent(ref tme);
                        _mouseTracking = true;
                    }
                    _mouseInside = true;

                    DispatchCdpMouse("mouseMoved", m.LParam, "none");
                    return;
                }

                case WM_MOUSELEAVE:
                {
                    _mouseTracking = false;
                    _mouseInside = false;

                    if (_captured)
                    {
                        _captured = false;
                        ReleaseCapture();
                    }

                    // 清理可能残留的按压状态
                    DispatchCdpMouseAt("mouseReleased", -1, -1, "left");
                    // 发送到视口外触发 CSS :hover 移除和 notch 自动收起
                    DispatchCdpMouseAt("mouseMoved", -1, -1, "none");
                    return;
                }

                case WM_LBUTTONDOWN:
                    // SetCapture 确保 WM_LBUTTONUP 一定回到本窗口
                    // 防止 hitRect 缩小后 mouseUp 漏给 Flash 导致状态污染
                    SetCapture(this.Handle);
                    _captured = true;
                    DispatchCdpMouse("mousePressed", m.LParam, "left");
                    return;

                case WM_LBUTTONUP:
                    if (_captured)
                    {
                        _captured = false;
                        ReleaseCapture();
                    }
                    DispatchCdpMouse("mouseReleased", m.LParam, "left");
                    return;

                case WM_RBUTTONDOWN:
                    SetCapture(this.Handle);
                    _captured = true;
                    DispatchCdpMouse("mousePressed", m.LParam, "right");
                    return;

                case WM_RBUTTONUP:
                    if (_captured)
                    {
                        _captured = false;
                        ReleaseCapture();
                    }
                    DispatchCdpMouse("mouseReleased", m.LParam, "right");
                    return;
            }

            base.WndProc(ref m);
        }

        #endregion

        #region CDP 注入

        /// <summary>从 WM_xxx 的 lParam 提取客户区坐标并注入 CDP。</summary>
        private void DispatchCdpMouse(string type, IntPtr lParam, string button)
        {
            if (_targetWebView == null) return;

            int lp = lParam.ToInt32();
            int x = (short)(lp & 0xFFFF);
            int y = (short)((lp >> 16) & 0xFFFF);

            DispatchCdpMouseAt(type, x, y, button);
        }

        /// <summary>向 WebView2 注入 CDP 鼠标事件。坐标为 viewport 相对。</summary>
        private void DispatchCdpMouseAt(string type, int x, int y, string button)
        {
            if (_targetWebView == null) return;

            string clickCount = (type == "mousePressed") ? ",\"clickCount\":1" : "";
            string json = "{\"type\":\"" + type + "\""
                + ",\"x\":" + x
                + ",\"y\":" + y
                + ",\"button\":\"" + button + "\""
                + clickCount + "}";

            try
            {
                _targetWebView.CallDevToolsProtocolMethodAsync("Input.dispatchMouseEvent", json);
            }
            catch
            {
                // WebView2 可能已 disposed
            }
        }

        #endregion

        #region 生命周期

        /// <summary>
        /// 激活 shield 层。在 WebOverlayForm.SetReady() 之后调用。
        /// </summary>
        public void SetReady()
        {
            OnPositionChanged();
            ShowOverlay();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_maskBitmap != null)
                {
                    _maskBitmap.Dispose();
                    _maskBitmap = null;
                }
            }
            base.Dispose(disposing);
        }

        #endregion
    }
}
