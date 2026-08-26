using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using CF7Launcher.Guardian.HitNumbers;
using CF7Launcher.Guardian.Hud.PlayerInfo;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// C# 伤害数字分层窗口。ReadLoop 只发布不可变帧快照；UI mailbox 始终
    /// latest-wins。精确对账已迁入暂停态 Web 设置，不再轮询或占用任何战斗键。
    /// </summary>
    public sealed class HitNumberOverlay : OverlayBase
    {
        private readonly HitNumberFrameMailbox _mailbox = new HitNumberFrameMailbox();
        private readonly HitNumberPainter _painter = new HitNumberPainter();
        private readonly HitNumberScenePainter _scenePainter = new HitNumberScenePainter();
        private HitNumberRuntimeSnapshot _currentSnapshot;
        private PlayerInfoLayeredDibSurface _surface;
        private Graphics _surfaceGraphics;

        public HitNumberOverlay(Form owner, Control anchor)
            : base(owner, anchor, 1024f, 576f)
        {
        }

        internal int PendingDispatchCountForTests => _mailbox.PendingDispatchCount;

        protected override void OnOwnerBecameVisible()
        {
            if (_currentSnapshot != null && !_currentSnapshot.IsReset) PaintLayered();
        }

        public void SetReady()
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(SetReady));
                return;
            }
            if (_mailbox.SetReady()) DrainMailbox();
        }

        internal void UpdateFrame(HitNumberRuntimeSnapshot snapshot)
        {
            if (_mailbox.Publish(snapshot)) QueueDrain();
        }

        private void QueueDrain()
        {
            try
            {
                if (IsDisposed || Disposing || !IsHandleCreated)
                {
                    _mailbox.DispatchFailed();
                    return;
                }
                BeginInvoke(new Action(DrainMailbox));
            }
            catch (InvalidOperationException)
            {
                _mailbox.DispatchFailed();
            }
        }

        private void DrainMailbox()
        {
            HitNumberRuntimeSnapshot snapshot = _mailbox.DrainLatest();
            if (snapshot == null) return;
            if (snapshot.IsReset)
            {
                _currentSnapshot = null;
                DismissOverlay();
                return;
            }
            _currentSnapshot = snapshot;
            PaintLayered();
        }

        protected override void OnPositionChanged()
        {
            if (_shown && _ownerVisible && _currentSnapshot != null) PaintLayered();
        }

        private void PaintLayered()
        {
            HitNumberRuntimeSnapshot snapshot = _currentSnapshot;
            HitNumberLayoutFrame frame = snapshot != null ? snapshot.Frame : null;
            if (frame == null || frame.Items.Count == 0)
            {
                DismissOverlay();
                return;
            }

            _mapper.CalcViewport(out float vpX, out float vpY, out float vpW, out float vpH);
            HitNumberRenderRegion region = HitNumberRenderPlanner.Plan(frame, vpW, vpH);
            if (region.IsEmpty)
            {
                DismissOverlay();
                return;
            }
            EnsureSurface(region.PixelBounds.Width, region.PixelBounds.Height);

            _surfaceGraphics.ResetTransform();
            _surfaceGraphics.SetClip(
                new Rectangle(0, 0, region.PixelBounds.Width, region.PixelBounds.Height),
                CombineMode.Replace);
            _surfaceGraphics.CompositingMode = CompositingMode.SourceCopy;
            _surfaceGraphics.FillRectangle(
                Brushes.Transparent,
                0,
                0,
                region.PixelBounds.Width,
                region.PixelBounds.Height);
            _surfaceGraphics.CompositingMode = CompositingMode.SourceOver;
            _surfaceGraphics.SmoothingMode = SmoothingMode.AntiAlias;

            RectangleF viewport = region.LocalViewport;
            _scenePainter.DrawWorldRows(
                _surfaceGraphics,
                viewport,
                frame.WorldRows,
                snapshot.Mode);
            _painter.Paint(
                _surfaceGraphics,
                frame.Items,
                new HitNumberPaintContext(viewport));

            if (!GetAnchorScreenOrigin(out Point origin)) return;
            int screenX = origin.X + (int)vpX + region.PixelBounds.Left;
            int screenY = origin.Y + (int)vpY + region.PixelBounds.Top;
            CommitPreparedDib(
                _surface.MemoryDc,
                region.PixelBounds.Width,
                region.PixelBounds.Height,
                screenX,
                screenY,
                255);
            if (!_shown && _ownerVisible) ShowOverlay();
        }

        private void EnsureSurface(int width, int height)
        {
            if (_surface != null && _surface.Width >= width && _surface.Height >= height) return;
            int capacityWidth = HitNumberRenderPlanner.QuantizeSurfaceCapacity(
                Math.Max(width, _surface != null ? _surface.Width : 0));
            int capacityHeight = HitNumberRenderPlanner.QuantizeSurfaceCapacity(
                Math.Max(height, _surface != null ? _surface.Height : 0));
            _surfaceGraphics?.Dispose();
            _surfaceGraphics = null;
            _surface?.Dispose();
            _surface = new PlayerInfoLayeredDibSurface(capacityWidth, capacityHeight);
            _surfaceGraphics = Graphics.FromImage(_surface.Bitmap);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _mailbox.Dispose();
                _surfaceGraphics?.Dispose();
                _surfaceGraphics = null;
                _surface?.Dispose();
                _surface = null;
                _scenePainter.Dispose();
                _painter.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
