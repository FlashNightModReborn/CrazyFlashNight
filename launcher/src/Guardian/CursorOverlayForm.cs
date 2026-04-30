using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 原生鼠标视觉层。独立 layered window，避免 WebView2 动画/特效队列影响 cursor 延迟。
    /// Phase 1 (cursor decoupling)：实现 INativeCursor，与新 DesktopCursorOverlay 共存切换。
    /// </summary>
    public class CursorOverlayForm : OverlayBase, INativeCursor
    {
        public bool UsesDesktopCoordinates { get { return false; } }

        // Matches launcher/web/assets/cursor/native/manifest.json.
        // base PNG 64×64；CursorScaleBoost 是 base→渲染像素的整体倍率。
        // 早期 1.20 在全屏 1440 + DPI 150% 下算出 raw=3.0 → clamp 2.5 → 渲染 160px，玩家反馈"严重偏大"。
        // 砍半到 0.60 后：全屏 1440 → raw=1.5 不触顶 → 渲染 96px；窗口 vp=1 → 渲染 38px；
        // 设计基准下视觉占比贴近 Flash 内 UI 元素（按钮 ~30-40px 高）。
        // MinCursorScale 同步 0.5：bootstrap 折叠期 vp<<1 时 cursor 不被 clamp 抬到怪异大小。
        private const int CursorSize = 64;
        private const double CursorScaleBoost = 0.60;
        private const double MinCursorScale = 0.5;
        private const double MaxCursorScale = 2.5;
        private const int HotspotX = 16;
        private const int HotspotY = 16;

        private readonly string _assetDir;
        private readonly Dictionary<string, Bitmap> _assetFrames = new Dictionary<string, Bitmap>();
        private string _state = "normal";
        private bool _dragging;
        private bool _visible;
        private int _screenX = Int32.MinValue;
        private int _screenY = Int32.MinValue;
        private int _lastCommitX = Int32.MinValue;
        private int _lastCommitY = Int32.MinValue;
        private Bitmap _frame;
        private double _cursorScale = CursorScaleBoost;
        private bool _contentDirty = true;

        // ── Idle-hide：业界标准（YouTube/Steam OS）3s 静止后 SW_HIDE，鼠标移动立即唤醒 ──
        // 触发源：UpdateCursorPosition 每次调用 = 真实鼠标移动（WebOverlayForm 已做位置去重）。
        // 键盘事件不触发 UpdateCursorPosition → 自动满足"键盘不唤醒"业界惯例。
        // 唤醒延迟：~0 ms（同一 BeginInvoke 内 ShowWindow + 提交）。
        // SW_HIDE 期间该 ULW 不参与 DWM 合成，省一层全屏 layered window α traversal。
        private const int IDLE_HIDE_MS = 3000;
        private const int IDLE_CHECK_INTERVAL_MS = 500;
        private long _lastActivityTick;
        private bool _idleHidden;
        private System.Windows.Forms.Timer _idleCheckTimer;

        public CursorOverlayForm(Form owner, Control anchor, string assetDir)
            : base(owner, anchor, 1024f, 576f)
        {
            _assetDir = assetDir;
            LoadCursorAssets();
        }

        public void SetReady()
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(SetReady));
                return;
            }

            ShowOverlay();
            PresentCursor();
            EnsureIdleCheckTimer();
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
            if (_idleHidden || !_visible) return;
            // unchecked 减法处理 TickCount 49 天溢出（rollover 后差值仍正确）
            int elapsed = unchecked(Environment.TickCount - (int)_lastActivityTick);
            if (elapsed >= IDLE_HIDE_MS)
            {
                _idleHidden = true;
                try { ShowWindow(this.Handle, SW_HIDE); } catch { }
            }
        }

        private void WakeFromIdle()
        {
            if (!_idleHidden) return;
            _idleHidden = false;
            try { ShowWindow(this.Handle, SW_SHOWNOACTIVATE); } catch { }
        }

        public void SetCursorState(string state, bool dragging)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action<string, bool>(SetCursorState), state, dragging);
                return;
            }

            string next = NormalizeState(state);
            if (_state == next && _dragging == dragging)
                return;

            _state = next;
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

            // 任何位置更新 = 鼠标真实移动（WebOverlayForm.SendCursorPosition 已做坐标去重）。
            // 刷新 activity tick + 从 idle 唤醒。
            _lastActivityTick = Environment.TickCount;
            if (_idleHidden) WakeFromIdle();

            _screenX = screen.X;
            _screenY = screen.Y;
            _visible = true;
            // 直接 SW_SHOWNOACTIVATE 强制 show，绕过 OverlayBase.ShowOverlay 的 _ownerVisible guard。
            // 场景：panel 操作期间 owner 短暂 deactivate → OverlayBase.HideOverlay (SW_HIDE) + _ownerVisible=false；
            // 若 owner Activated 事件没及时回触，后续 ShowOverlay() 因 guard early return → cursor 永远 SW_HIDE。
            // 用底层 ShowWindow 绕过这个 state 假设。
            if (!this.Visible)
            {
                try { ShowWindow(this.Handle, SW_SHOWNOACTIVATE); } catch { }
            }
            PresentCursor();
        }

        public void SetCursorVisible(bool visible)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action<bool>(SetCursorVisible), visible);
                return;
            }

            if (_visible == visible)
                return;

            _visible = visible;
            if (!_visible)
                DismissOverlay();
            else
            {
                ShowOverlay();
                PresentCursor();
            }
        }

        /// <summary>
        /// 设置 cursor 渲染 scale。**只跟 viewport scale**（窗口大小相对 Flash 设计高度 576）。
        ///
        /// 为什么不用 DPI：
        ///   - Per-Monitor V2 awareness 下 OverlayPhysicalBounds 已经是物理像素，viewport scale
        ///     已经反映了 OS 的 DPI 缩放（高 DPI 屏 → 物理 viewport 大 → viewport scale 大）。
        ///   - 再叠加 DPI scale 等于双重放大；这是之前"窗口模式 cursor 偏大"bug 的根因
        ///     （DPI 125%/150% 玩家窗口化时 max(1.0, 1.5) 让 DPI 主导）。
        ///   - DPI 仅在 viewport 数据缺失（启动早期、跨屏切换瞬间）时做 fallback。
        ///
        /// 全屏 1920×1080 / DPI 100% → viewport=1.875 → × 1.20 = 2.25 → cursor 144px
        /// 窗口化 1024×576 / DPI 100% → viewport=1.0   → × 1.20 = 1.20 → cursor  77px
        /// 全屏 1920×1080 / DPI 150% → viewport=1.875 → × 1.20 = 2.25 → cursor 144px（与 100% 一致）
        /// 窗口化 1024×576 / DPI 150% → viewport=1.0   → × 1.20 = 1.20 → cursor  77px（修复前是 115px）
        /// 启动早期 viewport 未就绪 → 回退 DPI fallback
        /// </summary>
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
            // 诊断日志：每次调用都记录（入参 + 计算 + 是否 noop），方便定位"切全屏后 SetScale 没被刷新"vs
            // "SetScale 被调但算出同一 final 早 return"两种不同路径。
            bool noop = Math.Abs(_cursorScale - next) < 0.01;
            int renderedPx = (int)System.Math.Round(CursorSize * next);
            LogManager.Log("[Cursor] SetScale vp=" + viewportScale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " dpi=" + dpi + " (=" + dpiScale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture) + ")"
                + " effective=" + effective.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " boost=" + CursorScaleBoost.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
                + " raw=" + rawNext.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " final=" + next.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " rendered=" + renderedPx + "px"
                + (noop ? " (noop)" : ""));
            if (noop)
                return;

            _cursorScale = next;
            _contentDirty = true;
            PresentCursor();
        }

        /// <summary>
        /// 纯函数：viewport-first，DPI fallback。InternalsVisibleTo 单测覆盖。
        ///   viewport > 0       → 直接用 viewport（DPI 已经反映在物理 viewport 像素里，不再叠加）
        ///   viewport 失效      → 用 DPI 兜底（启动早期、跨屏切换瞬间 OverlayPhysicalBounds 还没就绪）
        ///   两者都失效         → 1.0
        /// </summary>
        internal static double ComputeEffectiveScale(double viewportScale, double dpiScale)
        {
            bool vpValid = !Double.IsNaN(viewportScale) && viewportScale > 0;
            if (vpValid) return viewportScale;
            bool dpValid = !Double.IsNaN(dpiScale) && dpiScale > 0;
            if (dpValid) return dpiScale;
            return 1.0;
        }

        /// <summary>测试桥接：ComputeEffectiveScale 是 internal，外部 test 通过 public 包装访问。</summary>
        public static double ComputeEffectiveScaleForTest(double viewportScale, double dpiScale)
        {
            return ComputeEffectiveScale(viewportScale, dpiScale);
        }

        /// <summary>
        /// 兼容入口：旧调用点只传 DPI（viewportScale 默认 1.0）。新代码请用 SetScale。
        /// 保留是为了在没拿到 viewport scale 的早期路径（如 SetReady 之前的 DPI 探针）仍可工作。
        /// </summary>
        public void SetDpiScale(int dpiX, int dpiY)
        {
            SetScale(1.0, dpiX, dpiY);
        }

        /// <summary>
        /// Phase 1 stub：旧 CursorOverlayForm 暂以 SetCursorVisible 兜底。
        /// 真正的 game-forced 优先级状态机在 DesktopCursorOverlay 上实现；旧路径不引入新状态字段。
        /// </summary>
        public void SetForceHidden(bool forceHidden)
        {
            SetCursorVisible(!forceHidden);
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

        private static double ClampScale(double scale)
        {
            if (Double.IsNaN(scale) || Double.IsInfinity(scale) || scale <= 0)
                return CursorScaleBoost;
            if (scale < MinCursorScale) return MinCursorScale;
            if (scale > MaxCursorScale) return MaxCursorScale;
            return scale;
        }

        private void PresentCursor()
        {
            if (!_visible || _screenX == Int32.MinValue || _screenY == Int32.MinValue)
            {
                LogManager.Log("[Cursor] PresentCursor SKIP visible=" + _visible
                    + " screenX=" + (_screenX == Int32.MinValue ? "MIN" : _screenX.ToString())
                    + " idleHidden=" + _idleHidden);
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
            if (!_contentDirty && !sizeChanged && _shown)
            {
                LogManager.Log("[Cursor] PresentCursor PATH=move-only scale=" + scale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                    + " sz=" + width + "x" + height + " frameSz=" + (_frame == null ? "null" : _frame.Width + "x" + _frame.Height)
                    + " contentDirty=" + _contentDirty + " shown=" + _shown);
                MoveCommittedWindow(windowX, windowY);
                return;
            }

            LogManager.Log("[Cursor] PresentCursor PATH=render scale=" + scale.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                + " sz=" + width + "x" + height + " frameSz=" + (_frame == null ? "null" : _frame.Width + "x" + _frame.Height)
                + " contentDirty=" + _contentDirty + " sizeChanged=" + sizeChanged + " shown=" + _shown);
            RenderAndCommit(asset, scale, width, height, windowX, windowY);
        }

        private void RenderAndCommit(Bitmap asset, double scale, int width, int height, int windowX, int windowY)
        {
            if (_frame == null || _frame.Width != width || _frame.Height != height)
            {
                if (_frame != null) _frame.Dispose();
                _frame = new Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
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

            CommitBitmap(_frame, windowX, windowY, 255);
            _contentDirty = false;
            _lastCommitX = windowX;
            _lastCommitY = windowY;
            ShowOverlay();
            SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            // 诊断：取窗口实际物理大小，验证 ULW commit 是否真生效
            Rectangle realBounds;
            try { realBounds = GetWindowRectSafe(); }
            catch { realBounds = Rectangle.Empty; }
            LogManager.Log("[Cursor] RenderAndCommit committed sz=" + width + "x" + height
                + " realWindowRect=" + realBounds.Width + "x" + realBounds.Height
                + " @ (" + realBounds.X + "," + realBounds.Y + ")");
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        private struct RECT { public int Left, Top, Right, Bottom; }

        private Rectangle GetWindowRectSafe()
        {
            RECT r;
            if (!GetWindowRect(this.Handle, out r)) return Rectangle.Empty;
            return new Rectangle(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
        }

        private void MoveCommittedWindow(int windowX, int windowY)
        {
            if (_lastCommitX == windowX && _lastCommitY == windowY)
                return;

            ShowOverlay();
            SetWindowPos(this.Handle, HWND_TOP, windowX, windowY, 0, 0,
                SWP_NOSIZE | SWP_NOACTIVATE);
            _lastCommitX = windowX;
            _lastCommitY = windowY;
        }

        private void DrawCursor(Graphics g)
        {
            if (_state == "attack")
            {
                DrawAttack(g);
                return;
            }
            if (_state == "openDoor")
            {
                DrawOpenDoor(g);
                return;
            }

            bool closed = _state == "grab" || _dragging;
            bool hover = _state == "hoverGrab";
            bool click = _state == "click";

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
            if (!File.Exists(path))
                return;

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
            if (_assetFrames.TryGetValue(_state, out frame))
                return frame;
            if (_dragging && _assetFrames.TryGetValue("grab", out frame))
                return frame;
            if (_assetFrames.TryGetValue("normal", out frame))
                return frame;
            return null;
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

        protected override void Dispose(bool disposing)
        {
            if (disposing && _idleCheckTimer != null)
            {
                _idleCheckTimer.Stop();
                _idleCheckTimer.Dispose();
                _idleCheckTimer = null;
            }
            if (disposing && _frame != null)
            {
                _frame.Dispose();
                _frame = null;
            }
            if (disposing)
            {
                foreach (Bitmap asset in _assetFrames.Values)
                    asset.Dispose();
                _assetFrames.Clear();
            }
            base.Dispose(disposing);
        }
    }
}
