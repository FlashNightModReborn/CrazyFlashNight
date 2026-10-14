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
        private IntPtr _focusHwnd;
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
            // 以本实例 HWND 为键注册：多 HUD 共存时按归属取 probe，而不是抢占全局槽。
            _focusHwnd = Handle;
            FocusWindowSnapshot.RegisterHud(_focusHwnd,
                _owner != null && _owner.IsHandleCreated ? _owner.Handle : IntPtr.Zero,
                _focusInputProbe);
        }

        private void DisposeFocusInputProbe()
        {
            if (_focusHwnd != IntPtr.Zero)
            {
                FocusWindowSnapshot.UnregisterHud(_focusHwnd);
                _focusHwnd = IntPtr.Zero;
            }
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
                NativeMouseCorrelation corr = FocusTrace.PeekNativeMouseCorrelation(point, 0x0201);
                FocusTrace.Record("hud.native_hit_test", new {
                    receiver = Handle.ToInt64(), point, mouseId = corr.MouseId, correlation = corr,
                    widget = hit?.GetType().Name, result = result.ToInt64(),
                    hudInput = FocusTrace.CaptureHudInput(Handle, point) });
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
                bool inSend = InSendMessage();
                uint messageTime = unchecked((uint)GetMessageTime());
                // activate 由正在派发的输入消息触发；GetMessageTime 指向上一条泵取消息，
                // inSendMessage=true 时它仍是触发点击的入队时间，作为上下文记录但不参与认领。
                bool messageTimeAvailable = HasQueuedPointerTimestamp();
                NativeMouseCorrelation corr = FocusTrace.PeekNativeMouseCorrelation(
                    point, triggerMessage, messageTime, messageTimeAvailable);
                FocusTrace.Record("hud.native_mouse_activate", new {
                    receiver = message.HWnd.ToInt64(), triggerMessage,
                    hitTest = (short)(message.LParam.ToInt64() & 0xffff), point, pointSource = "GetMessagePos",
                    messageTime, messageTimeAvailable, inSendMessage = inSend,
                    mouseId = corr.MouseId, correlation = corr, result = message.Result.ToInt64(),
                    windows = FocusWindowSnapshot.At(point, message.HWnd),
                    hudInput = FocusTrace.CaptureHudInput(message.HWnd, point) });
            }
            catch { /* 观察不能改变 MA_NOACTIVATE。 */ }
        }

        private static bool IsFocusMouseMessage(int message)
        {
            return message == 0x0201 || message == 0x0202 || message == 0x0203;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct InputMessageSource { public uint DeviceType; public uint OriginId; }
        [DllImport("user32.dll")]
        private static extern bool GetCurrentInputMessageSource(out InputMessageSource source);

        private bool? _pointerSourceSucceeded;
        private uint? _pointerSourceDevice, _pointerSourceOrigin;
        private string _pointerSourceFailure;
        protected virtual bool HasQueuedPointerTimestamp()
        {
            try {
                if (InSendMessage()) return false;
                bool ok = TryReadCurrentPointerSource(out uint device, out uint origin);
                _pointerSourceSucceeded = ok; _pointerSourceDevice = device; _pointerSourceOrigin = origin;
                _pointerSourceFailure = ok ? null : "api_failed";
                return ok && device != 0;
            } catch (Exception error) {
                _pointerSourceSucceeded = false; _pointerSourceFailure = error.GetType().Name;
                return false;
            }
        }

#if CF7_TEST_SEAMS
        protected virtual bool TryReadCurrentPointerSource(out uint device, out uint origin)
#else
        private bool TryReadCurrentPointerSource(out uint device, out uint origin)
#endif
        {
            bool ok = GetCurrentInputMessageSource(out InputMessageSource source);
            device = source.DeviceType; origin = source.OriginId; return ok;
        }

        protected virtual uint QueuedPointerMessageTime() { return unchecked((uint)GetMessageTime()); }

        private sealed class NativeMouseFocusSample
        {
            internal FocusTrace.TraceLease Lease;
            internal FocusTrace.NativeTraceData Entry;
        }
        private NativeMouseFocusSample TraceFocusNativeMouse(Message message, string phase, long started,
            NativeMouseFocusSample sample = null, FocusTrace.TraceLease lease = null,
            bool available = false, uint messageTime = 0, string outcome = null)
        {
            try {
                if (phase == "exit") {
                    if (sample != null) FocusTrace.TryEndNative(sample.Lease, sample.Entry, message.Result.ToInt64(),
                        (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency, outcome);
                    return sample;
                }
                if (lease == null) return null;
                long packed = message.LParam.ToInt64();
                Point client = new Point((short)packed, (short)(packed >> 16));
                Point point = PointToScreen(client);
                int? age = null; bool? ambiguous = null;
                if (available) { age = FocusTrace.WrappingTickDeltaMs(unchecked((uint)Environment.TickCount),
                    messageTime, out bool value); ambiguous = value; }
                var entry = new FocusTrace.NativeTraceData {
                    receiver = message.HWnd.ToInt64(), message = message.Msg, client = client, point = point,
                    messageTime = messageTime, messageTimeAvailable = available, messageAgeMs = age,
                    messageAgeAmbiguous = ambiguous, inSendMessage = InSendMessage(),
                    sourceQuerySucceeded = _pointerSourceSucceeded, sourceDevice = _pointerSourceDevice,
                    sourceOrigin = _pointerSourceOrigin, sourceFailure = _pointerSourceFailure,
                    result = message.Result.ToInt64(), ObservedTick = Environment.TickCount64,
                    elapsedMs = (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency,
                    windows = FocusWindowSnapshot.At(point, message.HWnd), hudInput = FocusTrace.CaptureHudInput(message.HWnd, point)
                };
                return FocusTrace.TryBeginNative(lease, entry) ? new NativeMouseFocusSample { Lease = lease, Entry = entry } : null;
            } catch { return sample; }
        }

        [DllImport("user32.dll")] private static extern uint GetMessagePos();
        [DllImport("user32.dll")] private static extern int GetMessageTime();
        [DllImport("user32.dll")] private static extern bool InSendMessage();
        private static Point MessageScreenPoint()
        {
            uint packed = GetMessagePos();
            return new Point((short)(packed & 0xffff), (short)(packed >> 16));
        }
    }
}
