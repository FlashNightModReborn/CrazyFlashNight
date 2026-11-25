using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal readonly struct HitNumberPreviewRequest
    {
        internal HitNumberPreviewRequest(
            string presetId,
            HitNumberDisplayMode mode,
            int worldRowLimit,
            int timeMs,
            int width,
            int height,
            bool showTargets)
        {
            PresetId = presetId;
            Mode = mode;
            WorldRowLimit = worldRowLimit;
            TimeMs = timeMs;
            Width = width;
            Height = height;
            ShowTargets = showTargets;
        }

        internal string PresetId { get; }
        internal HitNumberDisplayMode Mode { get; }
        internal int WorldRowLimit { get; }
        internal int TimeMs { get; }
        internal int Width { get; }
        internal int Height { get; }
        internal bool ShowTargets { get; }
    }

    internal readonly struct HitNumberPreviewFrameResult
    {
        internal HitNumberPreviewFrameResult(
            byte[] pngBytes,
            int activeRows,
            int activeItems,
            int omittedRows,
            int omittedSegments)
        {
            PngBytes = pngBytes;
            ActiveRows = activeRows;
            ActiveItems = activeItems;
            OmittedRows = omittedRows;
            OmittedSegments = omittedSegments;
        }

        internal byte[] PngBytes { get; }
        internal int ActiveRows { get; }
        internal int ActiveItems { get; }
        internal int OmittedRows { get; }
        internal int OmittedSegments { get; }
    }

    /// <summary>
    /// 设置页专用的只读伤害数字实时预览沙盒。
    /// 完全独立于 FrameTask 的真实战斗 HitNumberRuntime 与 LedgerStore：
    /// 复用同一套生产 HitNumberRuntime / HitNumberLayoutEngine / HitNumberScenePainter / HitNumberPainter，
    /// 仅在设置页打开并请求帧时延迟分配 GDI 资源，关闭或重绑面板时立即释放，防止 GDI 句柄泄漏。
    /// </summary>
    internal sealed class HitNumberPreviewSandbox : IDisposable
    {
        internal const int DefaultWidth = 512;
        internal const int DefaultHeight = 288;
        internal const int MinimumWidth = 256;
        internal const int MaximumWidth = 640;
        internal const int SimulationFps = 60;

        private readonly object _gate = new object();
        private readonly List<HitNumberPreviewTarget> _targets = new List<HitNumberPreviewTarget>(6);
        private HitNumberRuntime _runtime;
        private HitNumberPainter _painter;
        private HitNumberScenePainter _scenePainter;
        private Bitmap _surface;
        private Graphics _graphics;
        private double _simClockSeconds;
        private string _sessionPresetId;
        private HitNumberDisplayMode _sessionMode = HitNumberDisplayMode.Balanced;
        private int _sessionWorldRowLimit = -1;
        private int _lastTickIndex = -1;
        private HitNumberLayoutFrame _lastFrame;
        private bool _disposed;

        internal bool HasAllocatedResourcesForTests
        {
            get
            {
                lock (_gate)
                {
                    return _surface != null || _painter != null || _scenePainter != null || _runtime != null;
                }
            }
        }

        internal HitNumberPreviewFrameResult RenderFrame(HitNumberPreviewRequest request)
        {
            if (!HitNumberPreviewPresets.TryGet(request.PresetId, out HitNumberPreviewPreset preset))
                throw new ArgumentException("Unknown preview preset: " + request.PresetId, nameof(request));
            if (request.Width < MinimumWidth || request.Width > MaximumWidth || request.Height <= 0)
                throw new ArgumentOutOfRangeException(nameof(request));

            lock (_gate)
            {
                if (_disposed) throw new ObjectDisposedException(nameof(HitNumberPreviewSandbox));

                EnsureSurface(request.Width, request.Height);
                int clampedMs = preset.DurationMs > 0
                    ? ((request.TimeMs % preset.DurationMs) + preset.DurationMs) % preset.DurationMs
                    : 0;
                int targetTick = (int)Math.Round(clampedMs * (SimulationFps / 1000.0));
                double nowSeconds = targetTick / (double)SimulationFps;

                HitNumberLayoutFrame frame = null;
                if (request.Mode != HitNumberDisplayMode.Off)
                {
                    frame = AdvanceSimulation(request.PresetId, request.Mode, request.WorldRowLimit, targetTick);
                }
                else
                {
                    ResetSimulationState();
                }

                _graphics.Clear(Color.Transparent);
                var viewport = new RectangleF(0f, 0f, request.Width, request.Height);

                if (request.ShowTargets)
                {
                    HitNumberPreviewPresets.FillTargets(request.PresetId, nowSeconds, _targets);
                    DrawTargetMarkers(_graphics, viewport, _targets);
                }

                int activeRows = 0;
                int activeItems = 0;
                int omittedRows = 0;
                int omittedSegments = 0;

                if (frame != null && (frame.WorldRows.Count > 0 || frame.Items.Count > 0))
                {
                    EnsurePainters();
                    _scenePainter.DrawWorldRows(_graphics, viewport, frame.WorldRows, request.Mode);
                    _painter.Paint(_graphics, frame.Items, new HitNumberPaintContext(viewport));
                    activeRows = frame.WorldRows.Count;
                    activeItems = frame.Items.Count;
                    omittedRows = frame.WorldRowOmittedCount;
                    omittedSegments = frame.WorldSegmentOmittedCount;
                }

                using (var stream = new MemoryStream(16384))
                {
                    _surface.Save(stream, ImageFormat.Png);
                    return new HitNumberPreviewFrameResult(
                        stream.ToArray(),
                        activeRows,
                        activeItems,
                        omittedRows,
                        omittedSegments);
                }
            }
        }

        internal void ReleaseResources()
        {
            lock (_gate)
            {
                ReleaseResourcesLocked();
            }
        }

        public void Dispose()
        {
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true;
                ReleaseResourcesLocked();
            }
        }

        private HitNumberLayoutFrame AdvanceSimulation(
            string presetId,
            HitNumberDisplayMode mode,
            int worldRowLimit,
            int targetTick)
        {
            bool sameSession =
                _runtime != null &&
                string.Equals(_sessionPresetId, presetId, StringComparison.Ordinal) &&
                _sessionMode == mode &&
                _sessionWorldRowLimit == worldRowLimit &&
                _lastTickIndex >= 0 &&
                targetTick >= _lastTickIndex &&
                (targetTick - _lastTickIndex) <= 30;

            if (!sameSession)
            {
                _runtime = new HitNumberRuntime(() => _simClockSeconds);
                _runtime.Configure(new HitNumberRuntimeOptions(mode, worldRowLimit));
                _sessionPresetId = presetId;
                _sessionMode = mode;
                _sessionWorldRowLimit = worldRowLimit;
                _lastTickIndex = -1;
                _lastFrame = null;
            }

            if (targetTick == _lastTickIndex)
                return _lastFrame;

            for (int tick = _lastTickIndex + 1; tick <= targetTick; tick++)
            {
                _simClockSeconds = tick / (double)SimulationFps;
                string payload = HitNumberPreviewPresets.BuildTickPayload(presetId, tick, SimulationFps);
                HitNumberRuntimeSnapshot snapshot = _runtime.ProcessFrame("0|0|1", payload);
                if (snapshot != null)
                {
                    _lastFrame = snapshot.IsReset || snapshot.IsDismiss ? null : snapshot.Frame;
                }
            }
            _lastTickIndex = targetTick;
            return _lastFrame;
        }

        private void ResetSimulationState()
        {
            _runtime = null;
            _sessionPresetId = null;
            _sessionWorldRowLimit = -1;
            _lastTickIndex = -1;
            _lastFrame = null;
        }

        private void EnsurePainters()
        {
            if (_painter == null) _painter = new HitNumberPainter();
            if (_scenePainter == null) _scenePainter = new HitNumberScenePainter();
        }

        private void EnsureSurface(int width, int height)
        {
            if (_surface != null && _surface.Width == width && _surface.Height == height)
                return;

            _graphics?.Dispose();
            _surface?.Dispose();
            _surface = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
            _graphics = Graphics.FromImage(_surface);
            _graphics.SmoothingMode = SmoothingMode.AntiAlias;
            _graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            _graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            _graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        }

        private void ReleaseResourcesLocked()
        {
            ResetSimulationState();
            _graphics?.Dispose();
            _graphics = null;
            _surface?.Dispose();
            _surface = null;
            _painter?.Dispose();
            _painter = null;
            _scenePainter?.Dispose();
            _scenePainter = null;
            _targets.Clear();
        }

        private static void DrawTargetMarkers(
            Graphics graphics,
            RectangleF viewport,
            List<HitNumberPreviewTarget> targets)
        {
            float scaleX = viewport.Width / HitNumberLayoutEngine.StageWidth;
            float scaleY = viewport.Height / HitNumberLayoutEngine.StageHeight;
            for (int i = 0; i < targets.Count; i++)
            {
                HitNumberPreviewTarget target = targets[i];
                float cx = viewport.Left + target.X * scaleX;
                float cy = viewport.Top + target.Y * scaleY;
                Color ringColor = target.IsAlly
                    ? Color.FromArgb(148, 120, 188, 115)
                    : Color.FromArgb(156, 61, 213, 255);
                Color fillColor = target.IsAlly
                    ? Color.FromArgb(42, 120, 188, 115)
                    : Color.FromArgb(38, 61, 213, 255);

                float rx = Math.Max(10f, 20f * scaleX);
                float ry = Math.Max(4f, 7f * scaleY);
                float bodyW = Math.Max(12f, 24f * scaleX);
                float bodyH = Math.Max(22f, 44f * scaleY);

                using (var fillBrush = new SolidBrush(fillColor))
                using (var pen = new Pen(ringColor, Math.Max(1f, 1.4f * scaleX)))
                {
                    // 轻量战术锚点底座 + 轮廓剪影（不喧宾夺主，让飘字锚定一目了然）
                    graphics.FillEllipse(fillBrush, cx - rx, cy - ry + bodyH * 0.15f, rx * 2f, ry * 2f);
                    graphics.DrawEllipse(pen, cx - rx, cy - ry + bodyH * 0.15f, rx * 2f, ry * 2f);
                    graphics.FillRectangle(fillBrush, cx - bodyW * 0.42f, cy - bodyH * 0.72f, bodyW * 0.84f, bodyH * 0.82f);
                    graphics.DrawRectangle(pen, cx - bodyW * 0.42f, cy - bodyH * 0.72f, bodyW * 0.84f, bodyH * 0.82f);
                }
            }
        }
    }
}
