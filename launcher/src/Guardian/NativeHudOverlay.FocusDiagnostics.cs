using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Diagnostic;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Guardian
{
    public partial class NativeHudOverlay
    {
        private Func<Point, object> _focusInputProbe;
        private Action _focusCacheRefresh;
        private int _focusInputThread;
        private long _focusPlacementGeneration, _focusPaintGeneration;
        private long _focusSubmittedPaint, _focusSubmittedPlacement, _focusLoggedPlacement = -1;
        private Rectangle _focusSubmittedBounds;
        private LayeredWindowCommitResult _focusLastCommit;
        internal long FocusPaintGeneration { get { return _focusPaintGeneration; } }
        internal long FocusPlacementGeneration { get { return _focusPlacementGeneration; } }

        private void InitializeFocusInputProbe()
        {
            _focusInputThread = Thread.CurrentThread.ManagedThreadId;
            _focusInputProbe = CaptureFocusInput;
            FocusTrace.HudInputSnapshot = _focusInputProbe;
            _focusCacheRefresh = () => FocusTrace.SetTarget(_rightContextWidget?.ScreenBounds ?? Rectangle.Empty,
                !IsDisposed && !Disposing && _ready && !_suspendedForPanel && _shown && _ownerVisible && Enabled);
            FocusTrace.RefreshTargetCache = _focusCacheRefresh;
        }

        private void DisposeFocusInputProbe()
        {
            if (ReferenceEquals(FocusTrace.HudInputSnapshot, _focusInputProbe))
                FocusTrace.HudInputSnapshot = null;
            if (ReferenceEquals(FocusTrace.RefreshTargetCache, _focusCacheRefresh))
                FocusTrace.RefreshTargetCache = null;
        }

        // 接收原提交的返回值；失败不重试、不改窗口或输入策略。
        internal void ObserveFocusBitmapCommit(LayeredWindowCommitResult result, long paintGeneration, long placementGeneration)
        {
            _focusLastCommit = result;
            if (_focusLastCommit.Succeeded)
            {
                _focusSubmittedPaint = paintGeneration;
                _focusSubmittedPlacement = placementGeneration;
                _focusSubmittedBounds = new Rectangle(result.ScreenX, result.ScreenY, result.Width, result.Height);
            }
            if (!_focusLastCommit.Succeeded || _focusLoggedPlacement != _focusPlacementGeneration
                || _focusLastCommit.ElapsedMilliseconds >= 25)
            {
                _focusLoggedPlacement = _focusPlacementGeneration;
                FocusTrace.Record("hud.surface_commit", new {
                    placementGeneration, paintGeneration,
                    submittedPaint = _focusSubmittedPaint, submittedPlacement = _focusSubmittedPlacement,
                    result = _focusLastCommit });
            }
        }

        private object CaptureFocusInput(Point point)
        {
            if (Thread.CurrentThread.ManagedThreadId != _focusInputThread)
                return new { unavailable = "different_thread" };
            if (IsDisposed || Disposing || !IsHandleCreated)
                return new { unavailable = "hud_unavailable" };
            INativeHudWidget hit = HitTestScreen(point);
            int? paintedAlpha = null;
            Point sourcePoint = new Point(point.X - _hudOrigin.X, point.Y - _hudOrigin.Y);
            if (_composedBitmap != null && sourcePoint.X >= 0 && sourcePoint.Y >= 0
                && sourcePoint.X < _composedW && sourcePoint.Y < _composedH)
            {
                try { paintedAlpha = _composedBitmap.GetPixel(sourcePoint.X, sourcePoint.Y).A; }
                catch { /* 绘制重入或表面不可用时明确保持 unknown。 */ }
            }
            bool submittedSource = _focusSubmittedPaint > 0
                && _focusSubmittedPaint == _focusPaintGeneration
                && _focusSubmittedPlacement == _focusPlacementGeneration;
            return new {
                logicalWidget = hit?.GetType().Name, logicalBounds = hit?.ScreenBounds,
                targetBounds = _rightContextWidget?.ScreenBounds,
                ready = _ready, suspended = _suspendedForPanel, shown = _shown,
                ownerVisible = _ownerVisible, canShow = CanShowOverlayNow, enabled = Enabled,
                placementGeneration = _focusPlacementGeneration, paintGeneration = _focusPaintGeneration,
                submittedPlacement = _focusSubmittedPlacement, submittedPaint = _focusSubmittedPaint,
                intendedBounds = new Rectangle(_hudOrigin, _hudSize), submittedBounds = _focusSubmittedBounds,
                sourcePoint, paintedAlpha, submittedSourceAlpha = submittedSource ? paintedAlpha : null,
                alphaProof = submittedSource ? "last_successful_source_bitmap_not_screen_pixels" : "unconfirmed_source",
                commitProof = "original_update_layered_window_return",
                lastCommit = _focusLastCommit
            };
        }

        private void TraceFocusHitTest(Point point, INativeHudWidget hit, IntPtr result)
        {
            if (!FocusTrace.Enabled || !FocusTrace.ShouldTraceNativeHitTest(point)) return;
            try
            {
                FocusTrace.Input("hud.native_hit_test", new InputData {
                    receiver = Handle.ToInt64(), point = point, mouseId = FocusTrace.NativeMouseCandidate(point),
                    widget = hit?.GetType().Name, result = result.ToInt64(), coordinateSource = "screen" });
            }
            catch { /* 不改变原始命中结果。 */ }
        }

        private void TraceFocusMouseActivate(Message message)
        {
            if (!FocusTrace.Enabled) return;
            try
            {
                int triggerMessage = (int)((message.LParam.ToInt64() >> 16) & 0xffff);
                if (!IsFocusMouseMessage(triggerMessage)) return;
                Point point = MessageScreenPoint();
                FocusTrace.Input("hud.native_mouse_activate", new InputData {
                    receiver = message.HWnd.ToInt64(), message = triggerMessage, point = point,
                    coordinateSource = "GetMessagePos", mouseId = FocusTrace.NativeMouseCandidate(point),
                    result = message.Result.ToInt64() });
            }
            catch { /* 观察不能改变 MA_NOACTIVATE。 */ }
        }

        private static bool IsFocusMouseMessage(int message)
        {
            return message == 0x0201 || message == 0x0202 || message == 0x0203;
        }

        [DllImport("user32.dll")] private static extern uint GetMessagePos();
        private static Point MessageScreenPoint()
        {
            uint packed = GetMessagePos();
            return new Point((short)(packed & 0xffff), (short)(packed >> 16));
        }
    }
}
