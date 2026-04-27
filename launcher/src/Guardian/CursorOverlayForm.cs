using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 原生鼠标视觉层。独立 layered window，避免 WebView2 动画/特效队列影响 cursor 延迟。
    /// </summary>
    public class CursorOverlayForm : OverlayBase
    {
        // Matches launcher/web/assets/cursor/native/manifest.json.
        private const int CursorSize = 64;
        private const double CursorScaleBoost = 1.20;
        private const double MinCursorScale = 1.0;
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

        public void SetDpiScale(int dpiX, int dpiY)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action<int, int>(SetDpiScale), dpiX, dpiY);
                return;
            }

            int dpi = Math.Max(dpiX, dpiY);
            double dpiScale = dpi > 0 ? dpi / 96.0 : 1.0;
            double next = ClampScale(dpiScale * CursorScaleBoost);
            if (Math.Abs(_cursorScale - next) < 0.01)
                return;

            _cursorScale = next;
            _contentDirty = true;
            PresentCursor();
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
                return;

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
                MoveCommittedWindow(windowX, windowY);
                return;
            }

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
