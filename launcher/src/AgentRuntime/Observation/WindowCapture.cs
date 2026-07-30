using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.Guardian;

namespace CF7Launcher.AgentRuntime.Observation
{
    internal interface IWindowFrameSourceFactory
    {
        IWindowFrameSource Create(ObservationSurfacePlan surface);
    }

    /// <summary>
    /// A frame source returns only its newest completed frame. It must not queue
    /// historical frames and must never synchronously marshal work onto the UI
    /// thread.
    /// </summary>
    internal interface IWindowFrameSource : IDisposable
    {
        Task<WindowFrameCaptureResult> CaptureLatestAsync(
            CancellationToken cancellationToken);
    }

    internal sealed class WindowFrameCaptureResult : IDisposable
    {
        private byte[] _pixels;

        private WindowFrameCaptureResult(
            byte[] pixels,
            int width,
            int height,
            Contracts.PixelFormat pixelFormat,
            ObservationMode sourceMode,
            string reasonCode)
        {
            _pixels = pixels;
            Width = width;
            Height = height;
            PixelFormat = pixelFormat;
            SourceMode = sourceMode;
            ReasonCode = reasonCode;
        }

        public bool Success
        {
            get { return _pixels != null; }
        }

        public byte[] Pixels
        {
            get { return _pixels; }
        }

        public int Width { get; }
        public int Height { get; }
        public Contracts.PixelFormat PixelFormat { get; }
        public ObservationMode SourceMode { get; }
        public string ReasonCode { get; }

        public static WindowFrameCaptureResult Captured(
            byte[] pixels,
            int width,
            int height,
            ObservationMode sourceMode)
        {
            if (pixels == null)
                throw new ArgumentNullException(nameof(pixels));
            if (width <= 0 || height <= 0)
                throw new ArgumentOutOfRangeException(nameof(width));
            long expected = checked((long)width * height * 4L);
            if (expected != pixels.LongLength)
                throw new ArgumentException(
                    "BGRA frame length does not match its dimensions.",
                    nameof(pixels));
            return new WindowFrameCaptureResult(
                pixels,
                width,
                height,
                Contracts.PixelFormat.Bgra8Premultiplied,
                sourceMode,
                null);
        }

        public static WindowFrameCaptureResult Unavailable(
            string reasonCode)
        {
            if (string.IsNullOrWhiteSpace(reasonCode))
                throw new ArgumentException(
                    "A reason code is required.",
                    nameof(reasonCode));
            return new WindowFrameCaptureResult(
                null,
                0,
                0,
                Contracts.PixelFormat.Bgra8Premultiplied,
                ObservationMode.WindowGraphicsCapture,
                reasonCode);
        }

        public void Dispose()
        {
            byte[] pixels = Interlocked.Exchange(ref _pixels, null);
            if (pixels != null)
                CryptographicOperations.ZeroMemory(pixels);
        }
    }

    /// <summary>
    /// Production WGC source. The activation factory performs the exact
    /// CreateForWindow interop call against the host-authoritative HWND and the
    /// pixel producer owns the D3D11 frame-pool lifetime. Capture runs on a
    /// worker and has a hard response deadline; a late native completion is
    /// observed and securely disposed in the background.
    /// </summary>
    internal sealed class WindowsGraphicsCaptureSourceFactory
        : IWindowFrameSourceFactory
    {
        internal static readonly TimeSpan DefaultCaptureTimeout =
            TimeSpan.FromSeconds(2);

        private readonly IGraphicsCaptureItemFactory _captureItems;
        private readonly IWindowCapturePreflight _preflight;
        private readonly IWgcPixelProducer _pixels;
        private readonly TimeSpan _captureTimeout;

        public WindowsGraphicsCaptureSourceFactory()
            : this(
                new WindowsGraphicsCaptureItemFactory(),
                new WindowsWindowCapturePreflight(),
                new WindowsGraphicsCapturePixelProducer(),
                DefaultCaptureTimeout)
        {
        }

        internal WindowsGraphicsCaptureSourceFactory(
            IGraphicsCaptureItemFactory captureItems,
            IWindowCapturePreflight preflight)
            : this(
                captureItems,
                preflight,
                new WindowsGraphicsCapturePixelProducer(),
                DefaultCaptureTimeout)
        {
        }

        internal WindowsGraphicsCaptureSourceFactory(
            IGraphicsCaptureItemFactory captureItems,
            IWindowCapturePreflight preflight,
            IWgcPixelProducer pixels,
            TimeSpan captureTimeout)
        {
            _captureItems = captureItems
                ?? throw new ArgumentNullException(nameof(captureItems));
            _preflight = preflight
                ?? throw new ArgumentNullException(nameof(preflight));
            _pixels = pixels
                ?? throw new ArgumentNullException(nameof(pixels));
            if (captureTimeout <= TimeSpan.Zero
                || captureTimeout > TimeSpan.FromSeconds(10))
            {
                throw new ArgumentOutOfRangeException(
                    nameof(captureTimeout));
            }
            _captureTimeout = captureTimeout;
        }

        public IWindowFrameSource Create(ObservationSurfacePlan surface)
        {
            return new WgcFrameSource(
                surface
                    ?? throw new ArgumentNullException(nameof(surface)),
                _captureItems,
                _preflight,
                _pixels,
                _captureTimeout);
        }

        private sealed class WgcFrameSource : IWindowFrameSource
        {
            private readonly ObservationSurfacePlan _surface;
            private readonly IGraphicsCaptureItemFactory _captureItems;
            private readonly IWindowCapturePreflight _preflight;
            private readonly IWgcPixelProducer _pixels;
            private readonly TimeSpan _captureTimeout;
            private int _disposed;

            public WgcFrameSource(
                ObservationSurfacePlan surface,
                IGraphicsCaptureItemFactory captureItems,
                IWindowCapturePreflight preflight,
                IWgcPixelProducer pixels,
                TimeSpan captureTimeout)
            {
                _surface = surface;
                _captureItems = captureItems;
                _preflight = preflight;
                _pixels = pixels;
                _captureTimeout = captureTimeout;
            }

            public async Task<WindowFrameCaptureResult> CaptureLatestAsync(
                CancellationToken cancellationToken)
            {
                if (Volatile.Read(ref _disposed) != 0)
                    throw new ObjectDisposedException(GetType().Name);

                var deadline = CancellationTokenSource
                    .CreateLinkedTokenSource(cancellationToken);
                deadline.CancelAfter(_captureTimeout);
                Task<WindowFrameCaptureResult> work = Task.Run(
                    () => CaptureOnWorker(deadline.Token),
                    CancellationToken.None);
                try
                {
                    WindowFrameCaptureResult result =
                        await work.WaitAsync(
                            _captureTimeout,
                            cancellationToken)
                            .ConfigureAwait(false);
                    deadline.Dispose();
                    return result;
                }
                catch (TimeoutException)
                {
                    deadline.Cancel();
                    DisposeLateCompletion(work, deadline);
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                catch (OperationCanceledException)
                    when (cancellationToken.IsCancellationRequested)
                {
                    deadline.Cancel();
                    DisposeLateCompletion(work, deadline);
                    throw;
                }
                catch (OperationCanceledException)
                    when (deadline.IsCancellationRequested)
                {
                    deadline.Dispose();
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                catch (Exception exception) when (
                    exception is COMException
                    || exception is DllNotFoundException
                    || exception is EntryPointNotFoundException
                    || exception is InvalidOperationException
                    || exception is PlatformNotSupportedException
                    || exception is ExternalException)
                {
                    deadline.Dispose();
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                catch
                {
                    deadline.Dispose();
                    throw;
                }
            }

            private WindowFrameCaptureResult CaptureOnWorker(
                CancellationToken cancellationToken)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (!_preflight.TryValidate(
                        _surface,
                        out _))
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "target_not_authoritative");
                }
                if (!_captureItems.TryCreateForWindow(
                        new IntPtr(_surface.WindowHandle),
                        out IGraphicsCaptureItemHandle item,
                        out _))
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                using (item)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    WindowFrameCaptureResult result =
                        _pixels.CaptureLatest(
                            item,
                            cancellationToken);
                    return result
                        ?? WindowFrameCaptureResult.Unavailable(
                            "capture_unavailable");
                }
            }

            private static void DisposeLateCompletion(
                Task<WindowFrameCaptureResult> work,
                CancellationTokenSource deadline)
            {
                _ = work.ContinueWith(
                    completed =>
                    {
                        try
                        {
                            if (completed.Status
                                == TaskStatus.RanToCompletion)
                            {
                                completed.Result?.Dispose();
                            }
                            else
                            {
                                _ = completed.Exception;
                            }
                        }
                        finally
                        {
                            deadline.Dispose();
                        }
                    },
                    CancellationToken.None,
                    TaskContinuationOptions.ExecuteSynchronously,
                    TaskScheduler.Default);
            }

            public void Dispose()
            {
                Interlocked.Exchange(ref _disposed, 1);
            }
        }
    }

    internal interface IWindowCapturePreflight
    {
        bool TryValidate(
            ObservationSurfacePlan surface,
            out string reasonCode);
    }

    /// <summary>
    /// Revalidates the exact registered process and HWND immediately before
    /// CreateForWindow. This is not discovery: all expected identity values
    /// originate in the host-owned session registry.
    /// </summary>
    internal sealed class WindowsWindowCapturePreflight
        : IWindowCapturePreflight
    {
        public bool TryValidate(
            ObservationSurfacePlan surface,
            out string reasonCode)
        {
            if (surface == null)
            {
                reasonCode = "arguments_invalid";
                return false;
            }
            if (!OperatingSystem.IsWindows())
            {
                reasonCode = "capture_unavailable";
                return false;
            }

            IntPtr window = new IntPtr(surface.WindowHandle);
            if (!IsWindow(window))
            {
                reasonCode = "target_not_authoritative";
                return false;
            }
            GetWindowThreadProcessId(
                window,
                out uint processId);
            if (processId != surface.OwnerProcessId)
            {
                reasonCode = "target_not_authoritative";
                return false;
            }
            if (surface.OwnerWindowHandle != 0
                && GetWindow(window, 4)
                    != new IntPtr(surface.OwnerWindowHandle))
            {
                reasonCode = "target_not_authoritative";
                return false;
            }

            try
            {
                using Process process =
                    Process.GetProcessById(surface.OwnerProcessId);
                if (process.HasExited)
                {
                    reasonCode = "target_not_authoritative";
                    return false;
                }
                DateTimeOffset start = new DateTimeOffset(
                    process.StartTime.ToUniversalTime());
                string path = process.MainModule?.FileName;
                if (start.UtcDateTime.Ticks
                        != surface.OwnerProcessStartTimeUtc
                            .UtcDateTime.Ticks
                    || path == null
                    || !string.Equals(
                        Path.GetFullPath(path),
                        surface.OwnerExecutablePath,
                        StringComparison.OrdinalIgnoreCase))
                {
                    reasonCode = "target_not_authoritative";
                    return false;
                }
            }
            catch (Exception exception) when (
                exception is ArgumentException
                || exception is InvalidOperationException
                || exception is System.ComponentModel.Win32Exception
                || exception is NotSupportedException)
            {
                reasonCode = "target_not_authoritative";
                return false;
            }

            reasonCode = null;
            return true;
        }

        [DllImport("user32.dll", ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr windowHandle);

        [DllImport("user32.dll", ExactSpelling = true)]
        private static extern uint GetWindowThreadProcessId(
            IntPtr windowHandle,
            out uint processId);

        [DllImport("user32.dll", ExactSpelling = true)]
        private static extern IntPtr GetWindow(
            IntPtr windowHandle,
            uint command);
    }

    internal interface IGraphicsCaptureItemFactory
    {
        bool TryCreateForWindow(
            IntPtr windowHandle,
            out IGraphicsCaptureItemHandle captureItem,
            out string reasonCode);
    }

    internal interface IGraphicsCaptureItemHandle : IDisposable
    {
        IntPtr AbiPointer { get; }
    }

    /// <summary>
    /// Native pixel boundary kept separate from HWND authorization and item
    /// creation so timeout and ownership behavior can be tested without a GPU.
    /// Implementations return a tightly packed premultiplied BGRA8 frame.
    /// </summary>
    internal interface IWgcPixelProducer
    {
        WindowFrameCaptureResult CaptureLatest(
            IGraphicsCaptureItemHandle captureItem,
            CancellationToken cancellationToken);
    }

    /// <summary>
    /// Minimal WinRT activation implementation for
    /// IGraphicsCaptureItemInterop.CreateForWindow. It never enumerates the
    /// desktop, windows, titles, or executable names.
    /// </summary>
    internal sealed class WindowsGraphicsCaptureItemFactory
        : IGraphicsCaptureItemFactory
    {
        private const string RuntimeClassName =
            "Windows.Graphics.Capture.GraphicsCaptureItem";
        private const int RpcEChangedMode = unchecked((int)0x80010106);

        private static readonly Guid GraphicsCaptureItemInteropIid =
            new Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
        private static readonly Guid GraphicsCaptureItemIid =
            new Guid("79C3F95B-31F7-4EC2-A464-632EF5D30760");

        public bool TryCreateForWindow(
            IntPtr windowHandle,
            out IGraphicsCaptureItemHandle captureItem,
            out string reasonCode)
        {
            captureItem = null;
            if (!OperatingSystem.IsWindows())
            {
                reasonCode = "capture_unavailable";
                return false;
            }
            if (windowHandle == IntPtr.Zero || !IsWindow(windowHandle))
            {
                reasonCode = "target_not_authoritative";
                return false;
            }

            int initializeResult = RoInitialize(1);
            bool shouldUninitialize =
                initializeResult == 0 || initializeResult == 1;
            if (initializeResult < 0
                && initializeResult != RpcEChangedMode)
            {
                reasonCode = "capture_unavailable";
                return false;
            }

            IntPtr className = IntPtr.Zero;
            IntPtr factoryPointer = IntPtr.Zero;
            object runtimeCallableWrapper = null;
            try
            {
                int result = WindowsCreateString(
                    RuntimeClassName,
                    RuntimeClassName.Length,
                    out className);
                if (result < 0)
                {
                    reasonCode = "capture_unavailable";
                    return false;
                }

                Guid interopIid = GraphicsCaptureItemInteropIid;
                result = RoGetActivationFactory(
                    className,
                    ref interopIid,
                    out factoryPointer);
                if (result < 0 || factoryPointer == IntPtr.Zero)
                {
                    reasonCode = "capture_unavailable";
                    return false;
                }

                runtimeCallableWrapper =
                    Marshal.GetObjectForIUnknown(factoryPointer);
                if (runtimeCallableWrapper
                    is not IGraphicsCaptureItemInterop interop)
                {
                    reasonCode = "capture_unavailable";
                    return false;
                }

                Guid itemIid = GraphicsCaptureItemIid;
                result = interop.CreateForWindow(
                    windowHandle,
                    ref itemIid,
                    out IntPtr itemPointer);
                if (result < 0 || itemPointer == IntPtr.Zero)
                {
                    if (itemPointer != IntPtr.Zero)
                        Marshal.Release(itemPointer);
                    reasonCode = "capture_unavailable";
                    return false;
                }

                captureItem = new GraphicsCaptureItemHandle(itemPointer);
                reasonCode = null;
                return true;
            }
            catch (
                Exception exception)
                when (exception is COMException
                    || exception is DllNotFoundException
                    || exception is EntryPointNotFoundException
                    || exception is PlatformNotSupportedException
                    || exception is InvalidCastException)
            {
                reasonCode = "capture_unavailable";
                return false;
            }
            finally
            {
                if (runtimeCallableWrapper != null
                    && Marshal.IsComObject(runtimeCallableWrapper))
                {
                    Marshal.ReleaseComObject(
                        runtimeCallableWrapper);
                }
                if (factoryPointer != IntPtr.Zero)
                    Marshal.Release(factoryPointer);
                if (className != IntPtr.Zero)
                    WindowsDeleteString(className);
                if (shouldUninitialize)
                    RoUninitialize();
            }
        }

        [ComImport]
        [Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IGraphicsCaptureItemInterop
        {
            [PreserveSig]
            int CreateForWindow(
                IntPtr window,
                ref Guid interfaceId,
                out IntPtr result);

            [PreserveSig]
            int CreateForMonitor(
                IntPtr monitor,
                ref Guid interfaceId,
                out IntPtr result);
        }

        private sealed class GraphicsCaptureItemHandle
            : IGraphicsCaptureItemHandle
        {
            private IntPtr _pointer;

            public GraphicsCaptureItemHandle(IntPtr pointer)
            {
                _pointer = pointer;
            }

            public IntPtr AbiPointer
            {
                get { return Volatile.Read(ref _pointer); }
            }

            public void Dispose()
            {
                IntPtr pointer = Interlocked.Exchange(
                    ref _pointer,
                    IntPtr.Zero);
                if (pointer != IntPtr.Zero)
                    Marshal.Release(pointer);
            }
        }

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern int RoInitialize(uint initializationType);

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern void RoUninitialize();

        [DllImport(
            "combase.dll",
            CharSet = CharSet.Unicode,
            ExactSpelling = true)]
        private static extern int WindowsCreateString(
            string sourceString,
            int length,
            out IntPtr hstring);

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern int WindowsDeleteString(IntPtr hstring);

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern int RoGetActivationFactory(
            IntPtr activatableClassId,
            ref Guid interfaceId,
            out IntPtr factory);

        [DllImport("user32.dll", ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr windowHandle);
    }

    internal interface IFlashSnapshotQualification
    {
        bool IsValidatedLocalKeyframeSource(
            ObservationCapturePlan plan,
            ObservationSurfacePlan surface,
            out string reasonCode);
    }

    internal interface IFlashKeyframeFallback
    {
        Task<WindowFrameCaptureResult> CaptureAsync(
            ObservationCapturePlan plan,
            ObservationSurfacePlan surface,
            CancellationToken cancellationToken);
    }

    /// <summary>
    /// FlashSnapshot is available only behind an independent, host-owned
    /// qualification decision. It is marked as a local keyframe source and
    /// never represented as successful WGC.
    /// </summary>
    internal sealed class VerifiedFlashSnapshotKeyframeFallback
        : IFlashKeyframeFallback
    {
        private readonly IFlashSnapshotQualification _qualification;

        public VerifiedFlashSnapshotKeyframeFallback(
            IFlashSnapshotQualification qualification)
        {
            _qualification = qualification
                ?? throw new ArgumentNullException(nameof(qualification));
        }

        public Task<WindowFrameCaptureResult> CaptureAsync(
            ObservationCapturePlan plan,
            ObservationSurfacePlan surface,
            CancellationToken cancellationToken)
        {
            if (plan == null)
                throw new ArgumentNullException(nameof(plan));
            if (surface == null)
                throw new ArgumentNullException(nameof(surface));
            if (surface.Kind != SurfaceKind.Flash
                || !_qualification.IsValidatedLocalKeyframeSource(
                    plan,
                    surface,
                    out _))
            {
                return Task.FromResult(
                    WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable"));
            }

            return Task.Run(
                () =>
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    FlashSnapshot.SnapshotResult snapshot = null;
                    try
                    {
                        snapshot = FlashSnapshot.Capture(
                            new IntPtr(surface.WindowHandle));
                        if (snapshot?.FullSnapshot == null
                            || FlashSnapshot.IsLikelyBlackFrame(
                                snapshot.FullSnapshot,
                                snapshot.ContentRect))
                        {
                            return WindowFrameCaptureResult.Unavailable(
                                "capture_unavailable");
                        }
                        long byteCount = checked(
                            (long)snapshot.FullSnapshot.Width
                            * snapshot.FullSnapshot.Height
                            * 4L);
                        if (byteCount
                            > AgentProtocolV1
                                .MaximumBinaryObjectBytes)
                        {
                            return WindowFrameCaptureResult.Unavailable(
                                "capture_object_too_large");
                        }

                        byte[] pixels = CopyTightBgra(
                            snapshot.FullSnapshot);
                        return WindowFrameCaptureResult.Captured(
                            pixels,
                            snapshot.FullSnapshot.Width,
                            snapshot.FullSnapshot.Height,
                            ObservationMode.FlashSnapshotKeyframe);
                    }
                    catch (
                        Exception exception)
                        when (exception is ArgumentException
                            || exception is InvalidOperationException
                            || exception is ExternalException)
                    {
                        return WindowFrameCaptureResult.Unavailable(
                            "capture_unavailable");
                    }
                    finally
                    {
                        snapshot?.FullSnapshot?.Dispose();
                    }
                },
                cancellationToken);
        }

        private static byte[] CopyTightBgra(Bitmap bitmap)
        {
            var rectangle = new Rectangle(
                0,
                0,
                bitmap.Width,
                bitmap.Height);
            BitmapData data = bitmap.LockBits(
                rectangle,
                ImageLockMode.ReadOnly,
                System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            try
            {
                int tightStride = checked(bitmap.Width * 4);
                byte[] pixels = new byte[
                    checked(tightStride * bitmap.Height)];
                for (int row = 0; row < bitmap.Height; row++)
                {
                    IntPtr source = IntPtr.Add(
                        data.Scan0,
                        data.Stride >= 0
                            ? row * data.Stride
                            : (bitmap.Height - 1 - row)
                                * -data.Stride);
                    Marshal.Copy(
                        source,
                        pixels,
                        row * tightStride,
                        tightStride);
                }
                return pixels;
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
        }
    }

    internal static class CapturedFrameSafety
    {
        public static bool IsAcceptableBgra(
            WindowFrameCaptureResult result,
            out string reasonCode)
        {
            if (result == null || !result.Success)
            {
                reasonCode = result?.ReasonCode
                    ?? "capture_unavailable";
                return false;
            }
            if (result.Width <= 0
                || result.Height <= 0
                || result.Pixels == null)
            {
                reasonCode = "capture_unavailable";
                return false;
            }
            long expected;
            try
            {
                expected = checked(
                    (long)result.Width * result.Height * 4L);
            }
            catch (OverflowException)
            {
                reasonCode = "capture_object_too_large";
                return false;
            }
            if (expected != result.Pixels.LongLength)
            {
                reasonCode = "capture_unavailable";
                return false;
            }
            if (expected > AgentProtocolV1.MaximumBinaryObjectBytes)
            {
                reasonCode = "capture_object_too_large";
                return false;
            }
            if (IsLikelyBlack(result.Pixels, result.Width, result.Height))
            {
                reasonCode = "capture_unavailable";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static bool IsLikelyBlack(
            byte[] pixels,
            int width,
            int height)
        {
            const int grid = 10;
            long luminance = 0;
            int count = 0;
            for (int row = 0; row < grid; row++)
            {
                int y = Math.Min(
                    height - 1,
                    (height * row) / grid
                        + Math.Max(1, height / (grid * 2)));
                for (int column = 0; column < grid; column++)
                {
                    int x = Math.Min(
                        width - 1,
                        (width * column) / grid
                            + Math.Max(1, width / (grid * 2)));
                    int offset = checked((y * width + x) * 4);
                    luminance += (
                        pixels[offset]
                        + pixels[offset + 1]
                        + pixels[offset + 2]) / 3;
                    count++;
                }
            }
            return count == 0 || luminance / count < 8;
        }
    }
}
