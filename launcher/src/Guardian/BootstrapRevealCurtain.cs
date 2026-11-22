using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Diagnostic;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Bootstrap → Flash 切入阶段的原生轻量化过渡遮幕。
    ///
    /// 使用纯色 WS_EX_LAYERED + SetLayeredWindowAttributes(LWA_ALPHA) 在 DWM 合成层
    /// 执行常数值淡出（零位图分配、零额外 GPU 上下文、100% 穿透不抢焦点）：
    /// 1. 在 WebView2 退场前瞬间同步铺满 FlashHostPanel 区域（玄黑 #06090c，与 Web
    ///    端加载收敛色一致），彻底遮蔽 WebView2 销毁与 Flash HWND 显现间的裸切换；
    /// 2. 短暂驻留让 Flash 首帧稳定绘制，随后在 ~340ms 内平滑降至 alpha=0 并自毁；
    /// 3. 任意异常、最小化、外部失焦或 Reset 均立即降级自毁，绝不阻塞游戏或残留桌面。
    /// </summary>
    internal sealed class BootstrapRevealCurtain : Form
    {
        internal static readonly Color CurtainColor = Color.FromArgb(6, 9, 12);
        internal const int DefaultHoldMs = 48;
        internal const int DefaultFadeMs = 340;
        private const int FrameIntervalMs = 15;

        #region Win32

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetLayeredWindowAttributes(
            IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

        [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool SetWindowPos(
            IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool UpdateWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern bool IsChild(IntPtr hWndParent, IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SystemParametersInfo(
            uint uiAction, uint uiParam, out int pvParam, uint fWinIni);

        private const int WS_EX_TRANSPARENT = 0x00000020;
        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_LAYERED = 0x00080000;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WM_MOUSEACTIVATE = 0x0021;
        private const int MA_NOACTIVATE = 3;
        private const int WM_NCHITTEST = 0x0084;
        private const int HTTRANSPARENT = -1;
        private const uint LWA_ALPHA = 0x02;
        private const int SW_HIDE = 0;
        private static readonly IntPtr HWND_TOP = IntPtr.Zero;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const uint SWP_SHOWWINDOW = 0x0040;
        private const uint SWP_NOOWNERZORDER = 0x0200;
        private const uint SPI_GETCLIENTAREAANIMATION = 0x1042;

        #endregion

        private readonly Form _owner;
        private readonly Control _anchor;
        private Action _onCompleted;
        private Timer _fadeTimer;
        private Stopwatch _fadeStopwatch;
        private int _holdMs = DefaultHoldMs;
        private int _fadeMs = DefaultFadeMs;
        private byte _lastAlpha = 255;
        private bool _cleanupStarted;

        private readonly EventHandler _boundsChangedHandler;
        private readonly EventHandler _ownerResizeHandler;
        private readonly EventHandler _ownerDeactivateHandler;
        private readonly FormClosingEventHandler _ownerClosingHandler;

        private BootstrapRevealCurtain(Form owner, Control anchor, Action onCompleted)
        {
            _owner = owner;
            _anchor = anchor;
            _onCompleted = onCompleted;

            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = CurtainColor;
            Enabled = false;
            Owner = owner;

            _boundsChangedHandler = delegate { SyncBoundsAndOrder(); };
            _ownerResizeHandler = delegate
            {
                if (_owner == null || _owner.IsDisposed || _owner.WindowState == FormWindowState.Minimized)
                {
                    CancelAndDispose();
                    return;
                }
                SyncBoundsAndOrder();
            };
            _ownerDeactivateHandler = delegate { HandleOwnerDeactivate(); };
            _ownerClosingHandler = delegate { CancelAndDispose(); };
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
                return cp;
            }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_NCHITTEST)
            {
                m.Result = (IntPtr)HTTRANSPARENT;
                return;
            }
            if (m.Msg == WM_MOUSEACTIVATE)
            {
                m.Result = (IntPtr)MA_NOACTIVATE;
                return;
            }
            base.WndProc(ref m);
        }

        internal static bool AreClientAnimationsEnabled()
        {
            try
            {
                if (!SystemInformation.UIEffectsEnabled) return false;
                int enabled;
                if (SystemParametersInfo(SPI_GETCLIENTAREAANIMATION, 0, out enabled, 0))
                {
                    return enabled != 0;
                }
                return true;
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// 确定性缓出透明曲线：驻留期恒为 255，随后按二次缓出 (1 - t)^2 平滑收敛至 0。
        /// 开场响应迅速、尾段羽化无跳变。
        /// </summary>
        internal static byte ComputeFadeAlpha(double elapsedMs, int holdMs, int fadeMs)
        {
            if (holdMs < 0) holdMs = 0;
            if (elapsedMs <= holdMs) return 255;
            if (fadeMs <= 0) return 0;
            double progress = (elapsedMs - holdMs) / fadeMs;
            if (progress >= 1.0) return 0;
            double remaining = 1.0 - progress;
            int alpha = (int)Math.Round(255.0 * remaining * remaining);
            if (alpha <= 0) return 0;
            if (alpha >= 255) return 255;
            return (byte)alpha;
        }

        /// <summary>
        /// 在目标锚点控件的屏幕矩形上同步铺设一层全不透明玄黑遮幕。
        /// 若宿主不可见、最小化、未建句柄、已关闭系统动画或任意异常，安全返回 null。
        /// </summary>
        internal static BootstrapRevealCurtain TryCover(Form owner, Control anchor, Action onCompleted = null)
        {
            if (owner == null || anchor == null) return null;
            if (owner.IsDisposed || owner.Disposing || anchor.IsDisposed || anchor.Disposing) return null;
            if (!owner.IsHandleCreated || !anchor.IsHandleCreated) return null;
            if (!owner.Visible || owner.WindowState == FormWindowState.Minimized) return null;
            if (!AreClientAnimationsEnabled()) return null;

            Rectangle rect;
            try
            {
                rect = anchor.RectangleToScreen(anchor.ClientRectangle);
            }
            catch
            {
                return null;
            }
            if (rect.Width <= 0 || rect.Height <= 0) return null;

            BootstrapRevealCurtain curtain = null;
            try
            {
                curtain = new BootstrapRevealCurtain(owner, anchor, onCompleted);
                curtain.CreateHandle();
                IntPtr handle = curtain.Handle;
                if (handle == IntPtr.Zero)
                {
                    curtain.Dispose();
                    return null;
                }
                if (!SetLayeredWindowAttributes(handle, 0, 255, LWA_ALPHA))
                {
                    curtain.Dispose();
                    return null;
                }
                curtain.HookOwnerEvents();
                SetWindowPos(
                    handle,
                    HWND_TOP,
                    rect.X,
                    rect.Y,
                    rect.Width,
                    rect.Height,
                    SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_NOOWNERZORDER);
                UpdateWindow(handle);
                return curtain;
            }
            catch (Exception ex)
            {
                LogManager.Log("[RevealCurtain] TryCover failed: " + ex.Message);
                if (curtain != null)
                {
                    try { curtain.CancelAndDispose(); } catch { }
                }
                return null;
            }
        }

        internal void SyncBoundsAndOrder()
        {
            if (_cleanupStarted || IsDisposed || Disposing || !IsHandleCreated) return;
            if (_owner == null || _owner.IsDisposed || !_owner.Visible || _owner.WindowState == FormWindowState.Minimized)
            {
                CancelAndDispose();
                return;
            }
            if (_anchor == null || _anchor.IsDisposed || !_anchor.IsHandleCreated)
            {
                CancelAndDispose();
                return;
            }
            try
            {
                Rectangle rect = _anchor.RectangleToScreen(_anchor.ClientRectangle);
                if (rect.Width <= 0 || rect.Height <= 0)
                {
                    CancelAndDispose();
                    return;
                }
                SetWindowPos(
                    Handle,
                    HWND_TOP,
                    rect.X,
                    rect.Y,
                    rect.Width,
                    rect.Height,
                    SWP_NOACTIVATE | SWP_NOOWNERZORDER);
            }
            catch
            {
                CancelAndDispose();
            }
        }

        internal void BeginFadeOut(int holdMs = DefaultHoldMs, int fadeMs = DefaultFadeMs)
        {
            if (_cleanupStarted || IsDisposed || Disposing || !IsHandleCreated) return;
            if (_fadeTimer != null) return;

            _holdMs = holdMs < 0 ? 0 : holdMs;
            _fadeMs = fadeMs < 0 ? 0 : fadeMs;
            _fadeStopwatch = Stopwatch.StartNew();

            _fadeTimer = new Timer();
            _fadeTimer.Interval = FrameIntervalMs;
            _fadeTimer.Tick += OnFadeTick;
            _fadeTimer.Start();
        }

        internal void CancelAndDispose()
        {
            if (_cleanupStarted) return;
            _cleanupStarted = true;

            StopTimer();
            UnhookOwnerEvents();

            try
            {
                if (!IsDisposed && IsHandleCreated)
                {
                    ShowWindow(Handle, SW_HIDE);
                }
            }
            catch { }

            NotifyCompletedOnce();

            try
            {
                if (!IsDisposed && !Disposing)
                {
                    Dispose();
                }
            }
            catch { }
        }

        private void OnFadeTick(object sender, EventArgs e)
        {
            if (_cleanupStarted || IsDisposed || Disposing || !IsHandleCreated)
            {
                CancelAndDispose();
                return;
            }
            if (_owner == null || _owner.IsDisposed || !_owner.Visible || _owner.WindowState == FormWindowState.Minimized)
            {
                CancelAndDispose();
                return;
            }

            double elapsed = _fadeStopwatch != null ? _fadeStopwatch.Elapsed.TotalMilliseconds : (_holdMs + _fadeMs);
            byte alpha = ComputeFadeAlpha(elapsed, _holdMs, _fadeMs);
            if (alpha == 0)
            {
                CancelAndDispose();
                return;
            }

            if (alpha != _lastAlpha)
            {
                _lastAlpha = alpha;
                try
                {
                    if (!SetLayeredWindowAttributes(Handle, 0, alpha, LWA_ALPHA))
                    {
                        CancelAndDispose();
                    }
                }
                catch
                {
                    CancelAndDispose();
                }
            }
        }

        private void HandleOwnerDeactivate()
        {
            if (_cleanupStarted || IsDisposed || Disposing) return;
            if (_owner == null || _owner.IsDisposed || !_owner.IsHandleCreated)
            {
                CancelAndDispose();
                return;
            }

            // 嵌入的 Flash 子进程窗口拿到焦点时会让 GuardianForm 失活，此时仍在同一游戏窗口内，
            // 允许遮幕走完剩余 ~300ms 淡出；只有真正切到外部应用才立刻撤幕。
            try
            {
                IntPtr fg = GetForegroundWindow();
                IntPtr ownerHwnd = _owner.Handle;
                if (fg != IntPtr.Zero && (fg == ownerHwnd || IsChild(ownerHwnd, fg)))
                {
                    return;
                }
            }
            catch { }

            CancelAndDispose();
        }

        private void HookOwnerEvents()
        {
            if (_owner != null && !_owner.IsDisposed)
            {
                _owner.Move += _boundsChangedHandler;
                _owner.Resize += _ownerResizeHandler;
                _owner.Deactivate += _ownerDeactivateHandler;
                _owner.FormClosing += _ownerClosingHandler;
            }
            if (_anchor != null && !_anchor.IsDisposed)
            {
                _anchor.Resize += _boundsChangedHandler;
                _anchor.LocationChanged += _boundsChangedHandler;
            }
        }

        private void UnhookOwnerEvents()
        {
            try
            {
                if (_owner != null)
                {
                    _owner.Move -= _boundsChangedHandler;
                    _owner.Resize -= _ownerResizeHandler;
                    _owner.Deactivate -= _ownerDeactivateHandler;
                    _owner.FormClosing -= _ownerClosingHandler;
                }
            }
            catch { }
            try
            {
                if (_anchor != null)
                {
                    _anchor.Resize -= _boundsChangedHandler;
                    _anchor.LocationChanged -= _boundsChangedHandler;
                }
            }
            catch { }
        }

        private void StopTimer()
        {
            if (_fadeTimer != null)
            {
                try
                {
                    _fadeTimer.Stop();
                    _fadeTimer.Tick -= OnFadeTick;
                    _fadeTimer.Dispose();
                }
                catch { }
                _fadeTimer = null;
            }
        }

        private void NotifyCompletedOnce()
        {
            Action cb = _onCompleted;
            _onCompleted = null;
            if (cb != null)
            {
                try { cb(); } catch { }
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _cleanupStarted = true;
                StopTimer();
                UnhookOwnerEvents();
                NotifyCompletedOnce();
            }
            base.Dispose(disposing);
        }
    }
}
