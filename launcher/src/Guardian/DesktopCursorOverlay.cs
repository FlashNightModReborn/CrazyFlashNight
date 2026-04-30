using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Desktop 顶层 layered window cursor。**不继承 OverlayBase**：cursor 的可绘制区域 = desktop 全屏，
    /// 和 OverlayBase（anchor-bound flash overlay）的设计前提相反。
    ///
    /// 解决的具体问题：
    ///   1. 离开旧 anchor 区域 → 退化为 OS cursor（OverlayBase 受 anchor bounds 制约）
    ///   2. scale 跟随依赖 anchor.SizeChanged 事件链，全屏切换有时不触发
    ///   3. 5 个并发可见性字段（_visible/_idleHidden/_shown/_ownerVisible/Cursor.Hide）冲突
    ///
    /// 核心设计：
    ///   • 单一可见性状态机：CursorVisibility enum，唯一 entrypoint = ApplyVisibility
    ///   • 自订阅 GuardianForm.Resize 算 scale（冗余路径，与 SetScale 推送并行）
    ///   • idle-hide @3s 内置（与状态机融合，不引入额外字段）
    ///   • 任何 SW_HIDE 路径必伴 Cursor.Show()，避免"全黑"死区（NI-2）
    ///
    /// Phase 1：feature flag 控制装配，默认 OFF，旧 CursorOverlayForm 仍是默认路径。
    /// </summary>
    public class DesktopCursorOverlay : Form, INativeCursor
    {
        public bool UsesDesktopCoordinates { get { return true; } }

        #region Win32 P/Invoke

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst,
            ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc,
            ref POINT pptSrc, uint crKey, ref BLENDFUNCTION pblend, uint dwFlags);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll", ExactSpelling = true)]
        private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hObj);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteObject(IntPtr hObj);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteDC(IntPtr hdc);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int x, y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct SIZE { public int cx, cy; }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct BLENDFUNCTION
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left, Top, Right, Bottom; }

        private const int SW_SHOWNOACTIVATE = 4;
        private const int SW_HIDE = 0;
        private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const byte AC_SRC_OVER = 0x00;
        private const byte AC_SRC_ALPHA = 0x01;
        private const uint ULW_ALPHA = 0x02;

        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_LAYERED = 0x00080000;
        private const int WS_EX_TRANSPARENT = 0x00000020;
        private const int WS_EX_TOPMOST = 0x00000008;
        private const int WM_NCHITTEST = 0x0084;
        private const int HTTRANSPARENT = -1;

        #endregion

        #region 常量（与旧 CursorOverlayForm 1:1 对齐）

        // base PNG 64×64；CursorScaleBoost 是 base→渲染像素的整体倍率。0.60 见 CursorOverlayForm.cs 注释。
        private const int CursorSize = 64;
        private const double CursorScaleBoost = 0.60;
        private const double MinCursorScale = 0.5;
        private const double MaxCursorScale = 2.5;
        private const int HotspotX = 16;
        private const int HotspotY = 16;

        private const int IDLE_HIDE_MS = 3000;
        private const int IDLE_CHECK_INTERVAL_MS = 500;

        // 设计基准（与 OverlayCoordinateContext.DesignHeight 一致）
        private const float DesignHeight = 576f;

        #endregion

        #region 状态字段

        private readonly Form _guardianForm;
        private readonly string _assetDir;
        private readonly Dictionary<string, Bitmap> _assetFrames = new Dictionary<string, Bitmap>();

        // 视觉状态
        private string _stateName = "normal";
        private bool _dragging;
        private int _screenX = Int32.MinValue;
        private int _screenY = Int32.MinValue;
        private int _lastCommitX = Int32.MinValue;
        private int _lastCommitY = Int32.MinValue;
        private Bitmap _frame;
        private double _cursorScale = CursorScaleBoost;
        private bool _contentDirty = true;

        // 唯一可见性状态机（5 字段折叠到 1 个 enum）
        // - Hidden       : SetReady 之前 / 全部条件都不满足
        // - Active       : 鼠标活动中、可见
        // - Idle         : 3s 静止后；mouse activity 唤醒
        // - CallerOff    : SetCursorVisible(false) 主控关闭；SetCursorVisible(true) 解锁
        // - GameForced   : SetForceHidden(true) 强制；优先级最高，mouse activity 不唤醒
        internal enum CursorVisibility { Hidden, Active, Idle, CallerOff, GameForced }
        private CursorVisibility _visibility = CursorVisibility.Hidden;
        private bool _callerWantsHidden;
        private bool _gameForcedHidden;
        private bool _systemCursorHidden;

        private long _lastActivityTick;
        private System.Windows.Forms.Timer _idleCheckTimer;

        #endregion

        public DesktopCursorOverlay(Form guardianForm, string assetDir)
        {
            _guardianForm = guardianForm;
            _assetDir = assetDir;

            this.FormBorderStyle = FormBorderStyle.None;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.Manual;
            this.AutoScaleMode = AutoScaleMode.None;
            // 离屏初始化避免首次 SW_SHOWNOACTIVATE 在 (0,0) 闪一帧
            this.Bounds = new Rectangle(-10000, -10000, 1, 1);
            // 不设 Owner —— desktop 顶层 ULW，跨 anchor bounds 自由移动

            CreateHandle();
            LoadCursorAssets();

            if (_guardianForm != null)
            {
                _guardianForm.Resize += OnGuardianResize;
                _guardianForm.SizeChanged += OnGuardianResize;
            }

            LogManager.Log("[DesktopCursor] ctor handle=0x" + this.Handle.ToString("X")
                + " assetDir=" + (_assetDir ?? "null")
                + " assetCount=" + _assetFrames.Count);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED
                            | WS_EX_TRANSPARENT | WS_EX_TOPMOST;
                return cp;
            }
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_NCHITTEST)
            {
                m.Result = (IntPtr)HTTRANSPARENT;
                return;
            }
            base.WndProc(ref m);
        }

        #region INativeCursor — 输入接口（与旧 CursorOverlayForm 签名 1:1）

        public void SetReady()
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(SetReady));
                return;
            }
            EnsureIdleCheckTimer();
            LogManager.Log("[DesktopCursor] SetReady");
            // SetReady 不直接进 Active —— 等 UpdateCursorPosition 第一次推送再点亮。
            // 避免 ready 时鼠标在屏幕角落 / 未知位置导致 cursor 闪烁。
        }

        public void SetCursorState(string state, bool dragging)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action<string, bool>(SetCursorState), state, dragging);
                return;
            }

            string next = NormalizeState(state);
            if (_stateName == next && _dragging == dragging)
                return;

            _stateName = next;
            _dragging = dragging;
            _contentDirty = true;
            PresentCursor();
        }

        public void UpdateCursorPosition(Point screen)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action<Point>(UpdateCursorPosition), screen);
                return;
            }

            // 任何位置更新都刷新 activity tick；mouse hook 已对位置去重，调用频率受控。
            _lastActivityTick = Environment.TickCount;

            _screenX = screen.X;
            _screenY = screen.Y;

            // mouse activity 是 wantActive 信号；CallerOff / GameForced 优先级覆盖。
            CursorVisibility target = ResolveTargetVisibility(
                _visibility, _callerWantsHidden, _gameForcedHidden, true, true);
            ApplyVisibility(target, "mouse_activity");

            if (_visibility == CursorVisibility.Active)
                PresentCursor();
        }

        public void SetCursorVisible(bool visible)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action<bool>(SetCursorVisible), visible);
                return;
            }

            _callerWantsHidden = !visible;
            // SetCursorVisible(true) 视为 wantActive 信号（与老 CursorOverlayForm.ShowOverlay+PresentCursor 行为一致）。
            CursorVisibility target = ResolveTargetVisibility(
                _visibility, _callerWantsHidden, _gameForcedHidden,
                _screenX != Int32.MinValue, visible);
            ApplyVisibility(target, "SetCursorVisible(" + visible + ")");
        }

        public void SetForceHidden(bool forceHidden)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action<bool>(SetForceHidden), forceHidden);
                return;
            }

            _gameForcedHidden = forceHidden;
            // 解除 force 不算 mouse activity，等下一次真实 mouse 移动唤醒。
            CursorVisibility target = ResolveTargetVisibility(
                _visibility, _callerWantsHidden, _gameForcedHidden,
                _screenX != Int32.MinValue, false);
            ApplyVisibility(target, "SetForceHidden(" + forceHidden + ")");
        }

        public void SetScale(double viewportScale, int dpiX, int dpiY)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action<double, int, int>(SetScale), viewportScale, dpiX, dpiY);
                return;
            }

            int dpi = Math.Max(dpiX, dpiY);
            double dpiScale = dpi > 0 ? dpi / 96.0 : 1.0;
            double effective = ComputeEffectiveScale(viewportScale, dpiScale);
            double rawNext = effective * CursorScaleBoost;
            double next = ClampScale(rawNext);
            bool noop = Math.Abs(_cursorScale - next) < 0.01;
            int renderedPx = (int)System.Math.Round(CursorSize * next);
            LogManager.Log("[Cursor] SetScale vp=" + viewportScale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " dpi=" + dpi + " (=" + dpiScale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture) + ")"
                + " effective=" + effective.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " boost=" + CursorScaleBoost.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
                + " raw=" + rawNext.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " final=" + next.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " rendered=" + renderedPx + "px"
                + (noop ? " (noop)" : "")
                + " [DesktopCursor]");
            if (noop) return;

            _cursorScale = next;
            _contentDirty = true;
            if (_visibility == CursorVisibility.Active)
                PresentCursor();
        }

        public void SetDpiScale(int dpiX, int dpiY)
        {
            SetScale(1.0, dpiX, dpiY);
        }

        public void PreCommitTransparent()
        {
            if (!this.IsHandleCreated) return;
            try
            {
                using (Bitmap warm = new Bitmap(1, 1, PixelFormat.Format32bppPArgb))
                {
                    warm.SetPixel(0, 0, Color.FromArgb(0, 0, 0, 0));
                    CommitBitmapInternal(warm, -10000, -10000, 0);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[DesktopCursor] PreCommitTransparent failed: " + ex.Message);
            }
        }

        #endregion

        #region 状态机 — ApplyVisibility 是唯一切换 entrypoint

        /// <summary>
        /// 唯一可见性切换 entrypoint。**禁止**任何路径绕过此方法直接调 ShowWindow。
        /// NI-2: 任何 SW_HIDE 路径都伴 Cursor.Show()，让 OS cursor 立即接管，避免"全黑"死区。
        /// </summary>
        private void ApplyVisibility(CursorVisibility next, string reason)
        {
            if (_visibility == next) return;
            CursorVisibility prev = _visibility;
            _visibility = next;
            LogManager.Log("[DesktopCursor] state " + prev + " -> " + next + " (" + reason + ")");

            bool show = (next == CursorVisibility.Active);
            if (show)
            {
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                SetWindowPos(this.Handle, HWND_TOPMOST, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                TryHideSystemCursor();
                _contentDirty = true;
                PresentCursor();
            }
            else
            {
                ShowWindow(this.Handle, SW_HIDE);
                TryShowSystemCursor();
            }
        }

        /// <summary>
        /// 纯函数：给定输入标志推导目标可见性。state machine 单测的桥接点 + 生产代码 entrypoint。
        ///
        /// 优先级：GameForced &gt; CallerOff &gt; (wantActive + hasPos → Active) &gt; (no pos → Hidden) &gt; 保持 prev (Active/Idle)
        ///
        /// wantActiveSignal: 来自 SetCursorVisible(true) 或 UpdateCursorPosition（mouse activity）。
        /// 不处理 Idle 转入（仅 timer 驱动；调用方在 OnIdleCheckTick 中单独处理 Active→Idle）。
        /// </summary>
        internal static CursorVisibility ResolveTargetVisibility(
            CursorVisibility prev,
            bool callerWantsHidden,
            bool gameForcedHidden,
            bool hasPosition,
            bool wantActiveSignal)
        {
            if (gameForcedHidden) return CursorVisibility.GameForced;
            if (callerWantsHidden) return CursorVisibility.CallerOff;
            if (wantActiveSignal && hasPosition) return CursorVisibility.Active;
            if (!hasPosition) return CursorVisibility.Hidden;
            // 有位置但本次调用非 wantActive：保持 prev 的 Active/Idle，否则 Hidden。
            if (prev == CursorVisibility.Active) return CursorVisibility.Active;
            if (prev == CursorVisibility.Idle) return CursorVisibility.Idle;
            return CursorVisibility.Hidden;
        }

        public static string ResolveTargetVisibilityForTest(
            string prevName,
            bool callerWantsHidden,
            bool gameForcedHidden,
            bool hasPosition,
            bool mouseActiveSignal)
        {
            CursorVisibility prev;
            try { prev = (CursorVisibility)Enum.Parse(typeof(CursorVisibility), prevName); }
            catch { prev = CursorVisibility.Hidden; }
            return ResolveTargetVisibility(prev, callerWantsHidden, gameForcedHidden,
                hasPosition, mouseActiveSignal).ToString();
        }

        private void TryHideSystemCursor()
        {
            if (_systemCursorHidden) return;
            try { Cursor.Hide(); _systemCursorHidden = true; }
            catch (Exception ex) { LogManager.Log("[DesktopCursor] Cursor.Hide failed: " + ex.Message); }
        }

        private void TryShowSystemCursor()
        {
            if (!_systemCursorHidden) return;
            try { Cursor.Show(); _systemCursorHidden = false; }
            catch (Exception ex) { LogManager.Log("[DesktopCursor] Cursor.Show failed: " + ex.Message); }
        }

        private void EnsureIdleCheckTimer()
        {
            if (_idleCheckTimer != null) return;
            _idleCheckTimer = new System.Windows.Forms.Timer();
            _idleCheckTimer.Interval = IDLE_CHECK_INTERVAL_MS;
            _idleCheckTimer.Tick += OnIdleCheckTick;
            _lastActivityTick = Environment.TickCount;
            _idleCheckTimer.Start();
        }

        private void OnIdleCheckTick(object sender, EventArgs e)
        {
            if (_visibility != CursorVisibility.Active) return;
            // unchecked 减法处理 TickCount 49 天溢出
            int elapsed = unchecked(Environment.TickCount - (int)_lastActivityTick);
            if (elapsed >= IDLE_HIDE_MS)
                ApplyVisibility(CursorVisibility.Idle, "idle_3s");
        }

        #endregion

        #region GuardianForm 自订阅 — scale 冗余路径

        private void OnGuardianResize(object sender, EventArgs e)
        {
            if (_guardianForm == null) return;
            // 注意：ClientSize 包含 letterbox 黑边；与 OverlayCoordinateContext.FlashViewportHeight 不完全等价。
            // 这是冗余 fallback，主路径仍是 WebOverlayForm.SetScale 推送（精确 viewport，不含黑边）。
            try
            {
                int h = _guardianForm.ClientSize.Height;
                if (h <= 0) return;
                double vp = h / DesignHeight;
                SetScale(vp, 0, 0);
            }
            catch (Exception ex)
            {
                LogManager.Log("[DesktopCursor] OnGuardianResize failed: " + ex.Message);
            }
        }

        #endregion

        #region Scale 计算（与 CursorOverlayForm 一致；单测共享）

        /// <summary>
        /// viewport-first，DPI fallback。Per-Monitor V2 awareness 下物理 viewport 已反映 OS DPI 缩放，
        /// 不再叠加 DPI scale。
        /// </summary>
        internal static double ComputeEffectiveScale(double viewportScale, double dpiScale)
        {
            bool vpValid = !Double.IsNaN(viewportScale) && viewportScale > 0;
            if (vpValid) return viewportScale;
            bool dpValid = !Double.IsNaN(dpiScale) && dpiScale > 0;
            if (dpValid) return dpiScale;
            return 1.0;
        }

        public static double ComputeEffectiveScaleForTest(double viewportScale, double dpiScale)
        {
            return ComputeEffectiveScale(viewportScale, dpiScale);
        }

        private static double ClampScale(double scale)
        {
            if (Double.IsNaN(scale) || Double.IsInfinity(scale) || scale <= 0)
                return CursorScaleBoost;
            if (scale < MinCursorScale) return MinCursorScale;
            if (scale > MaxCursorScale) return MaxCursorScale;
            return scale;
        }

        private static string NormalizeState(string state)
        {
            switch (state)
            {
                case "click":
                case "hoverGrab":
                case "grab":
                case "attack":
                case "openDoor":
                    return state;
                default:
                    return "normal";
            }
        }

        #endregion

        #region 单测桥接

        // Test-only：检查当前 visibility 状态用，避免暴露 enum 给 production 调用方
        internal CursorVisibility GetVisibilityForTest() { return _visibility; }

        #endregion

        #region 渲染 — 与 CursorOverlayForm 等价

        private void PresentCursor()
        {
            if (_visibility != CursorVisibility.Active
                || _screenX == Int32.MinValue || _screenY == Int32.MinValue)
            {
                LogManager.Log("[Cursor] PresentCursor SKIP visible=" + (_visibility == CursorVisibility.Active)
                    + " screenX=" + (_screenX == Int32.MinValue ? "MIN" : _screenX.ToString())
                    + " state=" + _visibility
                    + " [DesktopCursor]");
                return;
            }

            Bitmap asset = GetAssetFrame();
            double scale = ClampScale(_cursorScale);
            int baseWidth = asset != null ? asset.Width : CursorSize;
            int baseHeight = asset != null ? asset.Height : CursorSize;
            int width = Math.Max(1, (int)Math.Round(baseWidth * scale));
            int height = Math.Max(1, (int)Math.Round(baseHeight * scale));

            int hotspotX = (int)Math.Round(HotspotX * scale);
            int hotspotY = (int)Math.Round(HotspotY * scale);
            int windowX = _screenX - hotspotX;
            int windowY = _screenY - hotspotY;
            bool sizeChanged = _frame == null || _frame.Width != width || _frame.Height != height;
            if (!_contentDirty && !sizeChanged)
            {
                LogManager.Log("[Cursor] PresentCursor PATH=move-only scale="
                    + scale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                    + " sz=" + width + "x" + height
                    + " [DesktopCursor]");
                MoveCommittedWindow(windowX, windowY);
                return;
            }

            LogManager.Log("[Cursor] PresentCursor PATH=render scale="
                + scale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " sz=" + width + "x" + height
                + " sizeChanged=" + sizeChanged + " contentDirty=" + _contentDirty
                + " [DesktopCursor]");
            RenderAndCommit(asset, scale, width, height, windowX, windowY);
        }

        private void RenderAndCommit(Bitmap asset, double scale, int width, int height, int windowX, int windowY)
        {
            if (_frame == null || _frame.Width != width || _frame.Height != height)
            {
                if (_frame != null) _frame.Dispose();
                _frame = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
            }

            using (Graphics g = Graphics.FromImage(_frame))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.Clear(Color.FromArgb(0, 0, 0, 0));
                if (asset != null)
                {
                    g.DrawImage(asset, new Rectangle(0, 0, width, height),
                        0, 0, asset.Width, asset.Height, GraphicsUnit.Pixel);
                }
                else
                {
                    g.ScaleTransform((float)scale, (float)scale);
                    DrawCursor(g);
                }
            }

            CommitBitmapInternal(_frame, windowX, windowY, 255);
            _contentDirty = false;
            _lastCommitX = windowX;
            _lastCommitY = windowY;
            // 显式置顶，避免被新创建的 topmost 窗口遮盖
            SetWindowPos(this.Handle, HWND_TOPMOST, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

            Rectangle realBounds;
            try { realBounds = GetWindowRectSafe(); }
            catch { realBounds = Rectangle.Empty; }
            LogManager.Log("[Cursor] RenderAndCommit committed sz=" + width + "x" + height
                + " realWindowRect=" + realBounds.Width + "x" + realBounds.Height
                + " @ (" + realBounds.X + "," + realBounds.Y + ")"
                + " [DesktopCursor]");
        }

        private void MoveCommittedWindow(int windowX, int windowY)
        {
            if (_lastCommitX == windowX && _lastCommitY == windowY)
                return;

            SetWindowPos(this.Handle, HWND_TOPMOST, windowX, windowY, 0, 0,
                SWP_NOSIZE | SWP_NOACTIVATE);
            _lastCommitX = windowX;
            _lastCommitY = windowY;
        }

        private void CommitBitmapInternal(Bitmap bmp, int screenX, int screenY, byte globalAlpha)
        {
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

        private Rectangle GetWindowRectSafe()
        {
            RECT r;
            if (!GetWindowRect(this.Handle, out r)) return Rectangle.Empty;
            return new Rectangle(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
        }

        #endregion

        #region 资产加载 + 矢量绘制（与 CursorOverlayForm 一致；Phase 3 删旧后只剩一份）

        private void LoadCursorAssets()
        {
            if (string.IsNullOrEmpty(_assetDir) || !Directory.Exists(_assetDir))
                return;

            TryLoadAsset("normal", "normal.png");
            TryLoadAsset("click", "click.png");
            TryLoadAsset("hoverGrab", "hoverGrab.png");
            TryLoadAsset("grab", "grab.png");
            TryLoadAsset("attack", "attack.png");
            TryLoadAsset("openDoor", "openDoor.png");
        }

        private void TryLoadAsset(string state, string fileName)
        {
            string path = Path.Combine(_assetDir, fileName);
            if (!File.Exists(path)) return;
            try
            {
                using (Bitmap src = new Bitmap(path))
                {
                    _assetFrames[state] = new Bitmap(src);
                }
            }
            catch { }
        }

        private Bitmap GetAssetFrame()
        {
            Bitmap frame;
            if (_assetFrames.TryGetValue(_stateName, out frame)) return frame;
            if (_dragging && _assetFrames.TryGetValue("grab", out frame)) return frame;
            if (_assetFrames.TryGetValue("normal", out frame)) return frame;
            return null;
        }

        private void DrawCursor(Graphics g)
        {
            if (_stateName == "attack") { DrawAttack(g); return; }
            if (_stateName == "openDoor") { DrawOpenDoor(g); return; }

            bool closed = _stateName == "grab" || _dragging;
            bool hover = _stateName == "hoverGrab";
            bool click = _stateName == "click";

            Color skin = Color.FromArgb(255, 255, 204, 153);
            Color shade = Color.FromArgb(255, 51, 102, 90);
            Color line = Color.FromArgb(255, 20, 20, 20);
            Color glow = hover ? Color.FromArgb(130, 92, 214, 194) : Color.FromArgb(90, 255, 255, 255);

            using (Pen glowPen = new Pen(glow, 3.0f))
            using (Pen linePen = new Pen(line, 1.6f))
            using (SolidBrush skinBrush = new SolidBrush(skin))
            using (SolidBrush shadeBrush = new SolidBrush(shade))
            {
                using (GraphicsPath path = closed ? CreateGrabPath() : CreateHandPath(click))
                {
                    g.DrawPath(glowPen, path);
                    g.FillPath(skinBrush, path);
                    g.DrawPath(linePen, path);
                }

                if (!closed)
                {
                    g.FillEllipse(shadeBrush, 18, 19, 10, 8);
                    g.DrawEllipse(linePen, 18, 19, 10, 8);
                }
                else
                {
                    g.FillEllipse(shadeBrush, 19, 18, 11, 9);
                    g.DrawEllipse(linePen, 19, 18, 11, 9);
                }

                if (click)
                {
                    using (Pen clickPen = new Pen(Color.FromArgb(220, 255, 245, 190), 2.0f))
                        g.DrawLine(clickPen, 8, 5, 15, 13);
                }
            }
        }

        private static GraphicsPath CreateHandPath(bool click)
        {
            GraphicsPath p = new GraphicsPath();
            p.AddBezier(4, 4, 6, 1, 10, 2, 13, 7);
            p.AddLine(13, 7, 18, 15);
            p.AddBezier(17, 8, 22, 5, 25, 10, 26, 18);
            p.AddBezier(28, 16, 32, 17, 33, 22, 31, 29);
            p.AddBezier(31, 29, 27, 37, 15, 38, 10, 30);
            p.AddLine(10, 30, 2, 18);
            p.AddBezier(2, 18, 0, 14, 3, 11, 7, 14);
            p.AddLine(7, 14, 11, 20);
            p.AddLine(11, 20, click ? 4 : 3, click ? 11 : 9);
            p.CloseFigure();
            return p;
        }

        private static GraphicsPath CreateGrabPath()
        {
            GraphicsPath p = new GraphicsPath();
            p.AddBezier(7, 13, 10, 4, 20, 4, 25, 11);
            p.AddBezier(25, 11, 31, 12, 35, 18, 33, 26);
            p.AddBezier(33, 26, 30, 36, 14, 38, 7, 30);
            p.AddBezier(7, 30, 1, 23, 2, 16, 7, 13);
            p.CloseFigure();
            p.AddBezier(7, 13, 9, 16, 14, 19, 21, 18);
            p.AddBezier(21, 18, 24, 17, 26, 16, 28, 15);
            return p;
        }

        private void DrawAttack(Graphics g)
        {
            using (Pen line = new Pen(Color.FromArgb(255, 20, 20, 20), 2.0f))
            using (Pen red = new Pen(Color.FromArgb(255, 255, 92, 76), 2.0f))
            using (SolidBrush core = new SolidBrush(Color.FromArgb(230, 255, 220, 120)))
            {
                g.DrawEllipse(red, 8, 8, 22, 22);
                g.DrawLine(red, 19, 2, 19, 36);
                g.DrawLine(red, 2, 19, 36, 19);
                g.FillEllipse(core, 16, 16, 6, 6);
                g.DrawEllipse(line, 8, 8, 22, 22);
            }
        }

        private void DrawOpenDoor(Graphics g)
        {
            using (Pen line = new Pen(Color.FromArgb(255, 20, 20, 20), 1.8f))
            using (SolidBrush fill = new SolidBrush(Color.FromArgb(255, 255, 204, 153)))
            using (SolidBrush knob = new SolidBrush(Color.FromArgb(255, 80, 190, 160)))
            {
                PointF[] door = {
                    new PointF(10, 5), new PointF(29, 9), new PointF(29, 34), new PointF(10, 30)
                };
                g.FillPolygon(fill, door);
                g.DrawPolygon(line, door);
                g.FillEllipse(knob, 23, 20, 4, 4);
                g.DrawEllipse(line, 23, 20, 4, 4);
            }
        }

        #endregion

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_idleCheckTimer != null)
                {
                    _idleCheckTimer.Stop();
                    _idleCheckTimer.Dispose();
                    _idleCheckTimer = null;
                }
                if (_frame != null)
                {
                    _frame.Dispose();
                    _frame = null;
                }
                foreach (Bitmap asset in _assetFrames.Values)
                    asset.Dispose();
                _assetFrames.Clear();

                if (_guardianForm != null)
                {
                    try
                    {
                        _guardianForm.Resize -= OnGuardianResize;
                        _guardianForm.SizeChanged -= OnGuardianResize;
                    }
                    catch { }
                }
                // NI-2: dispose 时同样恢复 OS cursor
                TryShowSystemCursor();
            }
            base.Dispose(disposing);
        }
    }
}
