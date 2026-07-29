using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using CF7Launcher.Diagnostic;

namespace CF7Launcher.Guardian.Hud
{
    internal enum LayeredWindowCommitError
    {
        None = 0,
        WindowHandleUnavailable,
        InvalidBitmap,
        ScreenDcAcquireFailed,
        CompatibleDcCreateFailed,
        BitmapHandleCreateFailed,
        BitmapSelectFailed,
        UpdateLayeredWindowFailed,
        CleanupFailed,
        UnexpectedFailure
    }

    /// <summary>
    /// One UpdateLayeredWindow attempt. Elapsed time covers every operation
    /// performed by that transaction: the general bitmap path includes its
    /// per-call GDI setup/cleanup, while a prepared-DIB path owns those
    /// resources across calls and reports only its real prepared-DC commit.
    /// The result is immutable so observers may safely retain it.
    /// </summary>
    internal sealed class LayeredWindowCommitResult
    {
        internal LayeredWindowCommitResult(
            bool succeeded,
            int screenX,
            int screenY,
            int width,
            int height,
            byte globalAlpha,
            long elapsedTicks,
            long updateLayeredWindowTicks,
            LayeredWindowCommitError error,
            int nativeErrorCode,
            string errorMessage,
            string cleanupError)
        {
            Succeeded = succeeded;
            ScreenX = screenX;
            ScreenY = screenY;
            Width = width;
            Height = height;
            PixelCount = width > 0 && height > 0 ? (long)width * height : 0;
            ByteCount = PixelCount * 4L;
            GlobalAlpha = globalAlpha;
            ElapsedTicks = elapsedTicks;
            ElapsedMilliseconds = ToMilliseconds(elapsedTicks);
            UpdateLayeredWindowTicks = updateLayeredWindowTicks;
            UpdateLayeredWindowMilliseconds = ToMilliseconds(updateLayeredWindowTicks);
            Error = error;
            ErrorValue = ToContractValue(error);
            NativeErrorCode = nativeErrorCode;
            ErrorMessage = errorMessage;
            CleanupError = cleanupError;
        }

        public bool Succeeded { get; private set; }
        public int ScreenX { get; private set; }
        public int ScreenY { get; private set; }
        public int Width { get; private set; }
        public int Height { get; private set; }
        public long PixelCount { get; private set; }
        public long ByteCount { get; private set; }
        public byte GlobalAlpha { get; private set; }
        public long ElapsedTicks { get; private set; }
        public double ElapsedMilliseconds { get; private set; }
        public long UpdateLayeredWindowTicks { get; private set; }
        public double UpdateLayeredWindowMilliseconds { get; private set; }
        public LayeredWindowCommitError Error { get; private set; }
        public string ErrorValue { get; private set; }
        public int NativeErrorCode { get; private set; }
        public string ErrorMessage { get; private set; }
        public string CleanupError { get; private set; }

        private static double ToMilliseconds(long ticks)
        {
            return ticks <= 0 ? 0.0 : ticks * 1000.0 / Stopwatch.Frequency;
        }

        private static string ToContractValue(LayeredWindowCommitError error)
        {
            switch (error)
            {
                case LayeredWindowCommitError.None: return "none";
                case LayeredWindowCommitError.WindowHandleUnavailable: return "window_handle_unavailable";
                case LayeredWindowCommitError.InvalidBitmap: return "invalid_bitmap";
                case LayeredWindowCommitError.ScreenDcAcquireFailed: return "screen_dc_acquire_failed";
                case LayeredWindowCommitError.CompatibleDcCreateFailed: return "compatible_dc_create_failed";
                case LayeredWindowCommitError.BitmapHandleCreateFailed: return "bitmap_handle_create_failed";
                case LayeredWindowCommitError.BitmapSelectFailed: return "bitmap_select_failed";
                case LayeredWindowCommitError.UpdateLayeredWindowFailed: return "update_layered_window_failed";
                case LayeredWindowCommitError.CleanupFailed: return "cleanup_failed";
                default: return "unexpected_failure";
            }
        }
    }

    internal interface ILayeredWindowCommitObserver
    {
        void OnCommit(LayeredWindowCommitResult result);
    }

    /// <summary>
    /// Allocation-free observer slot for OverlayBase. The default value is disabled;
    /// observers opt a surface into structured commit instrumentation.
    /// </summary>
    internal struct LayeredWindowCommitObserverSlot
    {
        private ILayeredWindowCommitObserver _observer;

        internal bool IsEnabled
        {
            get { return Volatile.Read(ref _observer) != null; }
        }

        internal void Set(ILayeredWindowCommitObserver observer)
        {
            Interlocked.Exchange(ref _observer, observer);
        }

        internal void Publish(LayeredWindowCommitResult result)
        {
            ILayeredWindowCommitObserver observer = Volatile.Read(ref _observer);
            if (observer == null) return;
            try
            {
                observer.OnCommit(result);
            }
            catch (Exception ex)
            {
                LogManager.Log("[OverlayBase] commit observer failed: " + ex.Message);
            }
        }
    }

    internal interface ILayeredWindowCommitNativeApi
    {
        IntPtr AcquireScreenDc();
        int ReleaseScreenDc(IntPtr screenDc);
        IntPtr CreateCompatibleDc(IntPtr screenDc);
        bool DeleteDc(IntPtr memoryDc);
        IntPtr CreateBitmapHandle(Bitmap bitmap);
        bool DeleteObject(IntPtr handle);
        IntPtr SelectObject(IntPtr memoryDc, IntPtr handle);
        bool UpdateLayeredWindow(
            IntPtr windowHandle,
            IntPtr screenDc,
            IntPtr memoryDc,
            int screenX,
            int screenY,
            int width,
            int height,
            byte globalAlpha);
        int GetLastError();
    }

    internal static class LayeredWindowCommitExecutor
    {
        private static readonly IntPtr InvalidGdiHandle = new IntPtr(-1);

        internal static LayeredWindowCommitResult Execute(
            IntPtr windowHandle,
            Bitmap bitmap,
            int screenX,
            int screenY,
            byte globalAlpha,
            ILayeredWindowCommitNativeApi nativeApi)
        {
            if (nativeApi == null) throw new ArgumentNullException("nativeApi");

            long started = Stopwatch.GetTimestamp();
            long updateTicks = 0;
            int width = 0;
            int height = 0;
            LayeredWindowCommitError error = LayeredWindowCommitError.None;
            int nativeErrorCode = 0;
            string errorMessage = null;
            string cleanupError = null;
            int cleanupNativeErrorCode = 0;
            LayeredWindowCommitError currentOperation = LayeredWindowCommitError.UnexpectedFailure;
            IntPtr screenDc = IntPtr.Zero;
            IntPtr memoryDc = IntPtr.Zero;
            IntPtr bitmapHandle = IntPtr.Zero;
            IntPtr previousObject = IntPtr.Zero;
            bool bitmapSelected = false;

            if (windowHandle == IntPtr.Zero)
            {
                SetFailure(
                    ref error,
                    ref nativeErrorCode,
                    ref errorMessage,
                    LayeredWindowCommitError.WindowHandleUnavailable,
                    0,
                    "The layered window handle is not available.");
            }
            else if (bitmap == null)
            {
                SetFailure(
                    ref error,
                    ref nativeErrorCode,
                    ref errorMessage,
                    LayeredWindowCommitError.InvalidBitmap,
                    0,
                    "The commit bitmap is null.");
            }
            else
            {
                try
                {
                    currentOperation = LayeredWindowCommitError.InvalidBitmap;
                    width = bitmap.Width;
                    height = bitmap.Height;
                    if (width <= 0 || height <= 0)
                    {
                        SetFailure(
                            ref error,
                            ref nativeErrorCode,
                            ref errorMessage,
                            LayeredWindowCommitError.InvalidBitmap,
                            0,
                            "The commit bitmap has an empty size.");
                    }
                    else
                    {
                        currentOperation = LayeredWindowCommitError.ScreenDcAcquireFailed;
                        screenDc = nativeApi.AcquireScreenDc();
                        if (screenDc == IntPtr.Zero)
                        {
                            int code = nativeApi.GetLastError();
                            SetFailure(
                                ref error,
                                ref nativeErrorCode,
                                ref errorMessage,
                                LayeredWindowCommitError.ScreenDcAcquireFailed,
                                code,
                                "GetDC returned a null screen DC.");
                        }
                        else
                        {
                            currentOperation = LayeredWindowCommitError.CompatibleDcCreateFailed;
                            memoryDc = nativeApi.CreateCompatibleDc(screenDc);
                            if (memoryDc == IntPtr.Zero)
                            {
                                int code = nativeApi.GetLastError();
                                SetFailure(
                                    ref error,
                                    ref nativeErrorCode,
                                    ref errorMessage,
                                    LayeredWindowCommitError.CompatibleDcCreateFailed,
                                    code,
                                    "CreateCompatibleDC returned a null memory DC.");
                            }
                            else
                            {
                                currentOperation = LayeredWindowCommitError.BitmapHandleCreateFailed;
                                bitmapHandle = nativeApi.CreateBitmapHandle(bitmap);
                                if (bitmapHandle == IntPtr.Zero)
                                {
                                    int code = nativeApi.GetLastError();
                                    SetFailure(
                                        ref error,
                                        ref nativeErrorCode,
                                        ref errorMessage,
                                        LayeredWindowCommitError.BitmapHandleCreateFailed,
                                        code,
                                        "Bitmap.GetHbitmap returned a null handle.");
                                }
                                else
                                {
                                    currentOperation = LayeredWindowCommitError.BitmapSelectFailed;
                                    previousObject = nativeApi.SelectObject(memoryDc, bitmapHandle);
                                    if (previousObject == IntPtr.Zero ||
                                        previousObject == InvalidGdiHandle)
                                    {
                                        int code = nativeApi.GetLastError();
                                        SetFailure(
                                            ref error,
                                            ref nativeErrorCode,
                                            ref errorMessage,
                                            LayeredWindowCommitError.BitmapSelectFailed,
                                            code,
                                            "SelectObject rejected the bitmap handle.");
                                    }
                                    else
                                    {
                                        bitmapSelected = true;
                                        currentOperation =
                                            LayeredWindowCommitError.UpdateLayeredWindowFailed;
                                        long updateStarted = Stopwatch.GetTimestamp();
                                        long monitorStarted = UlwCommitMonitor.StartTick();
                                        bool updated;
                                        int updateError;
                                        try
                                        {
                                            updated = nativeApi.UpdateLayeredWindow(
                                                windowHandle,
                                                screenDc,
                                                memoryDc,
                                                screenX,
                                                screenY,
                                                width,
                                                height,
                                                globalAlpha);
                                            updateError = updated
                                                ? 0
                                                : nativeApi.GetLastError();
                                        }
                                        finally
                                        {
                                            updateTicks =
                                                Stopwatch.GetTimestamp() - updateStarted;
                                            UlwCommitMonitor.RecordCommit(monitorStarted);
                                        }

                                        if (!updated)
                                        {
                                            SetFailure(
                                                ref error,
                                                ref nativeErrorCode,
                                                ref errorMessage,
                                                LayeredWindowCommitError.UpdateLayeredWindowFailed,
                                                updateError,
                                                "UpdateLayeredWindow returned false.");
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    SetFailure(
                        ref error,
                        ref nativeErrorCode,
                        ref errorMessage,
                        currentOperation,
                        ex.HResult,
                        ex.GetType().Name + ": " + ex.Message);
                }
                finally
                {
                    bool restored = !bitmapSelected;
                    bool bitmapDeleted = false;
                    bool memoryDcDeleted = memoryDc == IntPtr.Zero;

                    if (bitmapSelected)
                    {
                        restored = TryRestoreObject(
                            nativeApi,
                            memoryDc,
                            previousObject,
                            ref cleanupError,
                            ref cleanupNativeErrorCode);
                    }

                    // Never call DeleteObject while the HBITMAP may still be selected
                    // into a live DC. A restore failure is recovered by destroying the
                    // memory DC first, then deleting the now-unselected bitmap.
                    if (bitmapHandle != IntPtr.Zero && restored)
                    {
                        bitmapDeleted = TryDeleteObject(
                            nativeApi,
                            bitmapHandle,
                            ref cleanupError,
                            ref cleanupNativeErrorCode);
                    }

                    if (memoryDc != IntPtr.Zero)
                    {
                        memoryDcDeleted = TryDeleteDc(
                            nativeApi,
                            memoryDc,
                            ref cleanupError,
                            ref cleanupNativeErrorCode);
                    }

                    if (bitmapHandle != IntPtr.Zero &&
                        !bitmapDeleted &&
                        (restored || memoryDcDeleted))
                    {
                        TryDeleteObject(
                            nativeApi,
                            bitmapHandle,
                            ref cleanupError,
                            ref cleanupNativeErrorCode);
                    }

                    TryReleaseScreenDc(
                        nativeApi,
                        screenDc,
                        ref cleanupError,
                        ref cleanupNativeErrorCode);
                }
            }

            if (!string.IsNullOrEmpty(cleanupError) && error == LayeredWindowCommitError.None)
            {
                error = LayeredWindowCommitError.CleanupFailed;
                nativeErrorCode = cleanupNativeErrorCode;
                errorMessage = "The native commit completed, but GDI cleanup failed.";
            }

            long elapsedTicks = Stopwatch.GetTimestamp() - started;
            return new LayeredWindowCommitResult(
                error == LayeredWindowCommitError.None,
                screenX,
                screenY,
                width,
                height,
                globalAlpha,
                elapsedTicks,
                updateTicks,
                error,
                nativeErrorCode,
                errorMessage,
                cleanupError);
        }

        /// <summary>
        /// Commits an already selected, caller-owned 32-bit source DIB.
        /// Resource creation and disposal remain the caller's responsibility;
        /// this method measures only the real prepared-DC transaction.
        /// </summary>
        internal static LayeredWindowCommitResult ExecutePrepared(
            IntPtr windowHandle,
            IntPtr sourceDc,
            int width,
            int height,
            int screenX,
            int screenY,
            byte globalAlpha,
            ILayeredWindowCommitNativeApi nativeApi)
        {
            if (nativeApi == null) throw new ArgumentNullException("nativeApi");

            long started = Stopwatch.GetTimestamp();
            long updateTicks = 0;
            LayeredWindowCommitError error = LayeredWindowCommitError.None;
            int nativeErrorCode = 0;
            string errorMessage = null;

            if (windowHandle == IntPtr.Zero)
            {
                SetFailure(
                    ref error,
                    ref nativeErrorCode,
                    ref errorMessage,
                    LayeredWindowCommitError.WindowHandleUnavailable,
                    0,
                    "The layered window handle is not available.");
            }
            else if (sourceDc == IntPtr.Zero || width <= 0 || height <= 0)
            {
                SetFailure(
                    ref error,
                    ref nativeErrorCode,
                    ref errorMessage,
                    LayeredWindowCommitError.InvalidBitmap,
                    0,
                    "The prepared layered-window source DIB is unavailable or empty.");
            }
            else
            {
                try
                {
                    long updateStarted = Stopwatch.GetTimestamp();
                    long monitorStarted = UlwCommitMonitor.StartTick();
                    bool updated;
                    int updateError;
                    try
                    {
                        updated = nativeApi.UpdateLayeredWindow(
                            windowHandle,
                            IntPtr.Zero,
                            sourceDc,
                            screenX,
                            screenY,
                            width,
                            height,
                            globalAlpha);
                        updateError = updated
                            ? 0
                            : nativeApi.GetLastError();
                    }
                    finally
                    {
                        updateTicks =
                            Stopwatch.GetTimestamp() - updateStarted;
                        UlwCommitMonitor.RecordCommit(monitorStarted);
                    }
                    if (!updated)
                    {
                        SetFailure(
                            ref error,
                            ref nativeErrorCode,
                            ref errorMessage,
                            LayeredWindowCommitError.UpdateLayeredWindowFailed,
                            updateError,
                            "UpdateLayeredWindow returned false.");
                    }
                }
                catch (Exception ex)
                {
                    SetFailure(
                        ref error,
                        ref nativeErrorCode,
                        ref errorMessage,
                        LayeredWindowCommitError.UpdateLayeredWindowFailed,
                        ex.HResult,
                        ex.GetType().Name + ": " + ex.Message);
                }
            }

            long elapsedTicks = Stopwatch.GetTimestamp() - started;
            return new LayeredWindowCommitResult(
                error == LayeredWindowCommitError.None,
                screenX,
                screenY,
                width,
                height,
                globalAlpha,
                elapsedTicks,
                updateTicks,
                error,
                nativeErrorCode,
                errorMessage,
                null);
        }

        private static void SetFailure(
            ref LayeredWindowCommitError currentError,
            ref int currentNativeErrorCode,
            ref string currentMessage,
            LayeredWindowCommitError error,
            int nativeErrorCode,
            string message)
        {
            if (currentError != LayeredWindowCommitError.None) return;
            currentError = error;
            currentNativeErrorCode = nativeErrorCode;
            currentMessage = message;
        }

        private static bool TryRestoreObject(
            ILayeredWindowCommitNativeApi nativeApi,
            IntPtr memoryDc,
            IntPtr previousObject,
            ref string cleanupError,
            ref int cleanupNativeErrorCode)
        {
            try
            {
                IntPtr restored = nativeApi.SelectObject(memoryDc, previousObject);
                if (restored == IntPtr.Zero || restored == InvalidGdiHandle)
                {
                    int code = nativeApi.GetLastError();
                    AppendCleanup(
                        ref cleanupError,
                        ref cleanupNativeErrorCode,
                        code,
                        "SelectObject(restore)");
                    return false;
                }
                return true;
            }
            catch (Exception ex)
            {
                AppendCleanup(
                    ref cleanupError,
                    ref cleanupNativeErrorCode,
                    ex.HResult,
                    "SelectObject(restore): " + ex.Message);
                return false;
            }
        }

        private static bool TryDeleteObject(
            ILayeredWindowCommitNativeApi nativeApi,
            IntPtr bitmapHandle,
            ref string cleanupError,
            ref int cleanupNativeErrorCode)
        {
            if (bitmapHandle == IntPtr.Zero) return true;
            try
            {
                if (!nativeApi.DeleteObject(bitmapHandle))
                {
                    int code = nativeApi.GetLastError();
                    AppendCleanup(
                        ref cleanupError,
                        ref cleanupNativeErrorCode,
                        code,
                        "DeleteObject");
                    return false;
                }
                return true;
            }
            catch (Exception ex)
            {
                AppendCleanup(
                    ref cleanupError,
                    ref cleanupNativeErrorCode,
                    ex.HResult,
                    "DeleteObject: " + ex.Message);
                return false;
            }
        }

        private static bool TryDeleteDc(
            ILayeredWindowCommitNativeApi nativeApi,
            IntPtr memoryDc,
            ref string cleanupError,
            ref int cleanupNativeErrorCode)
        {
            if (memoryDc == IntPtr.Zero) return true;
            try
            {
                if (!nativeApi.DeleteDc(memoryDc))
                {
                    int code = nativeApi.GetLastError();
                    AppendCleanup(
                        ref cleanupError,
                        ref cleanupNativeErrorCode,
                        code,
                        "DeleteDC");
                    return false;
                }
                return true;
            }
            catch (Exception ex)
            {
                AppendCleanup(
                    ref cleanupError,
                    ref cleanupNativeErrorCode,
                    ex.HResult,
                    "DeleteDC: " + ex.Message);
                return false;
            }
        }

        private static void TryReleaseScreenDc(
            ILayeredWindowCommitNativeApi nativeApi,
            IntPtr screenDc,
            ref string cleanupError,
            ref int cleanupNativeErrorCode)
        {
            if (screenDc == IntPtr.Zero) return;
            try
            {
                if (nativeApi.ReleaseScreenDc(screenDc) == 0)
                {
                    int code = nativeApi.GetLastError();
                    AppendCleanup(
                        ref cleanupError,
                        ref cleanupNativeErrorCode,
                        code,
                        "ReleaseDC");
                }
            }
            catch (Exception ex)
            {
                AppendCleanup(
                    ref cleanupError,
                    ref cleanupNativeErrorCode,
                    ex.HResult,
                    "ReleaseDC: " + ex.Message);
            }
        }

        private static void AppendCleanup(
            ref string cleanupError,
            ref int cleanupNativeErrorCode,
            int nativeErrorCode,
            string operation)
        {
            if (cleanupNativeErrorCode == 0) cleanupNativeErrorCode = nativeErrorCode;
            string item = operation + " failed (nativeError=" + nativeErrorCode + ")";
            cleanupError = string.IsNullOrEmpty(cleanupError)
                ? item
                : cleanupError + "; " + item;
        }
    }

    internal sealed class Win32LayeredWindowCommitNativeApi : ILayeredWindowCommitNativeApi
    {
        public static readonly Win32LayeredWindowCommitNativeApi Instance =
            new Win32LayeredWindowCommitNativeApi();

        private const byte AcSrcOver = 0x00;
        private const byte AcSrcAlpha = 0x01;
        private const uint UlwAlpha = 0x02;

        private Win32LayeredWindowCommitNativeApi() { }

        [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr GetDC(IntPtr windowHandle);

        [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern int ReleaseDC(IntPtr windowHandle, IntPtr dc);

        [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool UpdateLayeredWindow(
            IntPtr windowHandle,
            IntPtr destinationDc,
            ref NativePoint destination,
            ref NativeSize size,
            IntPtr sourceDc,
            ref NativePoint source,
            uint colorKey,
            ref BlendFunction blend,
            uint flags);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr CreateCompatibleDC(IntPtr dc);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteDC(IntPtr dc);

        [StructLayout(LayoutKind.Sequential)]
        private struct NativePoint
        {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeSize
        {
            public int Width;
            public int Height;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct BlendFunction
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        public IntPtr AcquireScreenDc()
        {
            return GetDC(IntPtr.Zero);
        }

        public int ReleaseScreenDc(IntPtr screenDc)
        {
            return ReleaseDC(IntPtr.Zero, screenDc);
        }

        public IntPtr CreateCompatibleDc(IntPtr screenDc)
        {
            return CreateCompatibleDC(screenDc);
        }

        public bool DeleteDc(IntPtr memoryDc)
        {
            return DeleteDC(memoryDc);
        }

        public IntPtr CreateBitmapHandle(Bitmap bitmap)
        {
            return bitmap.GetHbitmap(Color.FromArgb(0, 0, 0, 0));
        }

        public bool DeleteObject(IntPtr handle)
        {
            return DeleteObjectNative(handle);
        }

        [DllImport("gdi32.dll", EntryPoint = "DeleteObject", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteObjectNative(IntPtr handle);

        public IntPtr SelectObject(IntPtr memoryDc, IntPtr handle)
        {
            return SelectObjectNative(memoryDc, handle);
        }

        [DllImport("gdi32.dll", EntryPoint = "SelectObject", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr SelectObjectNative(IntPtr dc, IntPtr handle);

        public bool UpdateLayeredWindow(
            IntPtr windowHandle,
            IntPtr screenDc,
            IntPtr memoryDc,
            int screenX,
            int screenY,
            int width,
            int height,
            byte globalAlpha)
        {
            NativePoint destination = new NativePoint { X = screenX, Y = screenY };
            NativeSize size = new NativeSize { Width = width, Height = height };
            NativePoint source = new NativePoint { X = 0, Y = 0 };
            BlendFunction blend = new BlendFunction
            {
                BlendOp = AcSrcOver,
                BlendFlags = 0,
                SourceConstantAlpha = globalAlpha,
                AlphaFormat = AcSrcAlpha
            };
            return UpdateLayeredWindow(
                windowHandle,
                screenDc,
                ref destination,
                ref size,
                memoryDc,
                ref source,
                0,
                ref blend,
                UlwAlpha);
        }

        public int GetLastError()
        {
            return Marshal.GetLastWin32Error();
        }
    }
}
