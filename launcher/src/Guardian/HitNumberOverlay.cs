using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian.HitNumbers;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Guardian
{
    internal readonly record struct HitNumberPaintDiagnostics(
        double PlanMs, double ClearMs, double ScenePaintMs, double NumberPaintMs,
        double GraphicsFlushMs, double GdiFlushMs, double PresentSubmitMs,
        int PlannedWidth, int PlannedHeight, int DibCapacityWidth, int DibCapacityHeight,
        int WorldRowCount, int ItemCount);

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
        private float _surfaceDpiY;
        private WorldRasterPresentation _sharedPresentation;
        private bool _sharedFallbackLogged, _usingLegacyDamage;
        internal Action<bool> DamageLegacyFallbackChanged;
        internal Action<HitNumberPaintDiagnostics> PaintDiagnosticsObserver;

        private void SetLegacyDamageFallback(bool fallback)
        {
            if (_usingLegacyDamage == fallback) return;
            _usingLegacyDamage = fallback;
            DamageLegacyFallbackChanged?.Invoke(fallback);
        }

        public HitNumberOverlay(Form owner, Control anchor)
            : base(owner, anchor, 1024f, 576f)
        {
        }

        internal int PendingDispatchCountForTests => _mailbox.PendingDispatchCount;

        internal void SetSharedPresentation(WorldRasterPresentation presentation)
        {
            if (InvokeRequired) throw new InvalidOperationException("Damage presentation belongs to the UI thread.");
            if (_sharedPresentation != null) _sharedPresentation.Changed -= OnSharedPresentationChanged;
            DismissOverlay();
            SetLegacyDamageFallback(false);
            _sharedPresentation = presentation;
            if (_sharedPresentation != null) _sharedPresentation.Changed += OnSharedPresentationChanged;
            OnSharedPresentationChanged();
        }

        private void OnSharedPresentationChanged()
        {
            if (!IsDisposed && !Disposing && _currentSnapshot != null) PaintLayered();
        }

        private void HideNumbers()
        {
            _sharedPresentation?.Hide();
            DismissOverlay();
            SetLegacyDamageFallback(false);
        }

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
                HideNumbers();
                return;
            }
            _currentSnapshot = snapshot;
            PaintLayered();
        }

        protected override void OnPositionChanged()
        {
            if ((_shown || _sharedPresentation?.IsAvailable == true) && _ownerVisible && _currentSnapshot != null) PaintLayered();
        }

        private void PaintLayered()
        {
            if (_sharedPresentation != null && !_sharedPresentation.IsAvailable)
            {
                DismissOverlay();
                SetLegacyDamageFallback(false);
                return;
            }
            HitNumberRuntimeSnapshot snapshot = _currentSnapshot;
            HitNumberLayoutFrame frame = snapshot != null ? snapshot.Frame : null;
            if (frame == null || frame.Items.Count == 0)
            {
                HideNumbers();
                return;
            }

            var observer = PaintDiagnosticsObserver;
            long planStart = observer != null ? Stopwatch.GetTimestamp() : 0;
            _mapper.CalcViewport(out float vpX, out float vpY, out float vpW, out float vpH);
            HitNumberRenderRegion region = HitNumberRenderPlanner.Plan(frame, vpW, vpH);
            if (region.IsEmpty)
            {
                HideNumbers();
                return;
            }
            long planEnd = observer != null ? Stopwatch.GetTimestamp() : 0;
            int width = region.PixelBounds.Width;
            int height = region.PixelBounds.Height;
            EnsureSurface(width, height);
            int stride = checked(_surface.Width * 4);
            long clearStart = observer != null ? Stopwatch.GetTimestamp() : 0;
            ClearSurface(_surface.Pixels, width, height, stride);
            long clearEnd = observer != null ? Stopwatch.GetTimestamp() : 0;

            RectangleF viewport = region.LocalViewport;
            bool drawScene = frame.WorldRows.Count > 0 &&
                snapshot.Mode != HitNumberDisplayMode.Balanced && snapshot.Mode != HitNumberDisplayMode.Classic;
            long sceneEnd = clearEnd;
            long graphicsFlushEnd = clearEnd;
            long gdiFlushEnd = clearEnd;
            if (drawScene)
            {
                _surfaceGraphics.ResetTransform();
                _surfaceGraphics.SetClip(new Rectangle(0, 0, width, height), CombineMode.Replace);
                _surfaceGraphics.CompositingMode = CompositingMode.SourceOver;
                _surfaceGraphics.SmoothingMode = SmoothingMode.AntiAlias;
                _scenePainter.DrawWorldRows(_surfaceGraphics, viewport, frame.WorldRows, snapshot.Mode);
                sceneEnd = observer != null ? Stopwatch.GetTimestamp() : 0;

                // Finish writing the anchors before the CPU draws the numbers over them.
                _surfaceGraphics.Flush(FlushIntention.Sync);
                graphicsFlushEnd = observer != null ? Stopwatch.GetTimestamp() : 0;
                if (!GdiFlush()) throw new InvalidOperationException("Damage-number raster flush failed.");
                gdiFlushEnd = observer != null ? Stopwatch.GetTimestamp() : 0;
            }

            _painter.PaintToPArgbSurface(_surface.Pixels, width, height, stride, _surfaceDpiY,
                frame.Items, new HitNumberPaintContext(viewport));
            long numberEnd = observer != null ? Stopwatch.GetTimestamp() : 0;

            if (!GetAnchorScreenOrigin(out Point origin)) return;
            int screenX = origin.X + (int)vpX + region.PixelBounds.Left;
            int screenY = origin.Y + (int)vpY + region.PixelBounds.Top;
            double submitMs = 0.0;
            if (_sharedPresentation != null)
            {
                long sharedStart = observer != null ? Stopwatch.GetTimestamp() : 0;
                bool presented = _sharedPresentation.TryPresent(_surface.Pixels, width, height, stride,
                    new Point(screenX, screenY)) || !_sharedPresentation.IsAvailable;
                if (observer != null) submitMs = Stopwatch.GetElapsedTime(sharedStart).TotalMilliseconds;
                if (presented)
                {
                    ObservePaint(submitMs);
                    if (_shown) DismissOverlay();
                    SetLegacyDamageFallback(false);
                    _sharedFallbackLogged = false;
                    return;
                }
                SetLegacyDamageFallback(true);
                _sharedPresentation.Hide();
                if (!_sharedFallbackLogged)
                {
                    _sharedFallbackLogged = true;
                    LogManager.Log("event=world_raster_fallback kind=hit_numbers reason=unsupported_extent");
                }
            }
            long dibStart = observer != null ? Stopwatch.GetTimestamp() : 0;
            CommitPreparedDib(_surface.MemoryDc, width, height, screenX, screenY, 255);
            if (observer != null) ObservePaint(submitMs + Stopwatch.GetElapsedTime(dibStart).TotalMilliseconds);
            if (!_shown && _ownerVisible) ShowOverlay();

            void ObservePaint(double presentSubmitMs)
            {
                if (observer == null) return;
                observer(new HitNumberPaintDiagnostics(
                    Stopwatch.GetElapsedTime(planStart, planEnd).TotalMilliseconds,
                    Stopwatch.GetElapsedTime(clearStart, clearEnd).TotalMilliseconds,
                    Stopwatch.GetElapsedTime(clearEnd, sceneEnd).TotalMilliseconds,
                    Stopwatch.GetElapsedTime(gdiFlushEnd, numberEnd).TotalMilliseconds,
                    Stopwatch.GetElapsedTime(sceneEnd, graphicsFlushEnd).TotalMilliseconds,
                    Stopwatch.GetElapsedTime(graphicsFlushEnd, gdiFlushEnd).TotalMilliseconds,
                    presentSubmitMs,
                    width, height, _surface.Width, _surface.Height, frame.WorldRows.Count, frame.Items.Count));
            }
        }

        private static unsafe void ClearSurface(IntPtr pixels, int width, int height, int stride)
        {
            int rowBytes = checked(width * 4);
            byte* start = (byte*)pixels;
            if (rowBytes == stride)
            {
                new Span<byte>(start, checked(stride * height)).Clear();
                return;
            }

            for (int y = 0; y < height; y++)
                new Span<byte>(start + y * stride, rowBytes).Clear();
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
            _surfaceDpiY = _surfaceGraphics.DpiY;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_sharedPresentation != null) _sharedPresentation.Changed -= OnSharedPresentationChanged;
                _sharedPresentation = null;
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
        [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GdiFlush();
    }
}
