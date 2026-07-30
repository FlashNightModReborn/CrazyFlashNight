using System;
using System.Runtime.InteropServices;
using System.Threading;
using CF7Launcher.AgentRuntime.Contracts;

namespace CF7Launcher.AgentRuntime.Observation
{
    /// <summary>
    /// Single-frame Windows Graphics Capture producer implemented at the ABI
    /// boundary. It creates a private BGRA-capable D3D11 device, binds a
    /// free-threaded frame pool to the already-authorized GraphicsCaptureItem,
    /// copies only the newest frame into a CPU-readable staging texture, and
    /// returns tightly packed BGRA8 bytes.
    ///
    /// No monitor, desktop, title, or process discovery API exists here. The
    /// sole capture item is the CreateForWindow result supplied by the caller.
    /// </summary>
    internal sealed class WindowsGraphicsCapturePixelProducer
        : IWgcPixelProducer
    {
        private static readonly TimeSpan NativeCaptureTimeout =
            TimeSpan.FromMilliseconds(1750);

        public WindowFrameCaptureResult CaptureLatest(
            IGraphicsCaptureItemHandle captureItem,
            CancellationToken cancellationToken)
        {
            if (captureItem == null)
                throw new ArgumentNullException(nameof(captureItem));
            if (!OperatingSystem.IsWindows()
                || captureItem.AbiPointer == IntPtr.Zero)
            {
                return WindowFrameCaptureResult.Unavailable(
                    "capture_unavailable");
            }

            try
            {
                return CaptureCore(
                    captureItem.AbiPointer,
                    cancellationToken);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception exception) when (
                exception is COMException
                || exception is DllNotFoundException
                || exception is EntryPointNotFoundException
                || exception is ExternalException
                || exception is InvalidOperationException
                || exception is PlatformNotSupportedException
                || exception is OverflowException)
            {
                return WindowFrameCaptureResult.Unavailable(
                    "capture_unavailable");
            }
        }

        private static WindowFrameCaptureResult CaptureCore(
            IntPtr captureItem,
            CancellationToken cancellationToken)
        {
            const int rpcEChangedMode =
                unchecked((int)0x80010106);

            int initializeResult = RoInitialize(1);
            bool shouldUninitialize =
                initializeResult == 0 || initializeResult == 1;
            if (initializeResult < 0
                && initializeResult != rpcEChangedMode)
            {
                return WindowFrameCaptureResult.Unavailable(
                    "capture_unavailable");
            }

            IntPtr d3dDevice = IntPtr.Zero;
            IntPtr d3dContext = IntPtr.Zero;
            IntPtr dxgiDevice = IntPtr.Zero;
            IntPtr inspectableDevice = IntPtr.Zero;
            IntPtr direct3DDevice = IntPtr.Zero;
            IntPtr framePoolStatics = IntPtr.Zero;
            IntPtr framePool = IntPtr.Zero;
            IntPtr captureSession = IntPtr.Zero;
            IntPtr frame = IntPtr.Zero;
            IntPtr surface = IntPtr.Zero;
            IntPtr surfaceAccess = IntPtr.Zero;
            IntPtr sourceTexture = IntPtr.Zero;
            IntPtr stagingTexture = IntPtr.Zero;
            long nativeDeadline = unchecked(
                Environment.TickCount64
                + (long)NativeCaptureTimeout.TotalMilliseconds);

            try
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (!TryCreateD3D11Device(
                        out d3dDevice,
                        out d3dContext))
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                Guid dxgiDeviceIid = NativeIds.IdxgiDevice;
                if (Marshal.QueryInterface(
                        d3dDevice,
                        ref dxgiDeviceIid,
                        out dxgiDevice) < 0
                    || dxgiDevice == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                if (CreateDirect3D11DeviceFromDXGIDevice(
                        dxgiDevice,
                        out inspectableDevice) < 0
                    || inspectableDevice == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                Guid direct3DDeviceIid =
                    NativeIds.Direct3DDevice;
                if (Marshal.QueryInterface(
                        inspectableDevice,
                        ref direct3DDeviceIid,
                        out direct3DDevice) < 0
                    || direct3DDevice == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                if (!TryGetItemSize(
                        captureItem,
                        out SizeInt32 initialSize)
                    || !TryValidateDimensions(
                        initialSize.Width,
                        initialSize.Height,
                        out _))
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_object_too_large");
                }

                if (!TryGetFramePoolStatics(
                        out framePoolStatics))
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                var createFreeThreaded =
                    GetMethod<CreateFreeThreadedDelegate>(
                        framePoolStatics,
                        6);
                int result = createFreeThreaded(
                    framePoolStatics,
                    direct3DDevice,
                    NativeConstants.DxgiFormatBgra8Unorm,
                    2,
                    initialSize,
                    out framePool);
                if (result < 0 || framePool == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                var createSession =
                    GetMethod<CreateCaptureSessionDelegate>(
                        framePool,
                        10);
                result = createSession(
                    framePool,
                    captureItem,
                    out captureSession);
                if (result < 0 || captureSession == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                var startCapture =
                    GetMethod<StartCaptureDelegate>(
                        captureSession,
                        6);
                if (startCapture(captureSession) < 0)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                frame = WaitForNewestFrame(
                    framePool,
                    cancellationToken,
                    nativeDeadline);
                if (frame == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                var getContentSize =
                    GetMethod<GetSizeDelegate>(frame, 8);
                if (getContentSize(
                        frame,
                        out SizeInt32 contentSize) < 0)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                if (!TryValidateDimensions(
                        contentSize.Width,
                        contentSize.Height,
                        out int tightByteCount))
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_object_too_large");
                }

                var getSurface =
                    GetMethod<GetObjectDelegate>(frame, 6);
                if (getSurface(frame, out surface) < 0
                    || surface == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                Guid accessIid =
                    NativeIds.Direct3DDxgiInterfaceAccess;
                if (Marshal.QueryInterface(
                        surface,
                        ref accessIid,
                        out surfaceAccess) < 0
                    || surfaceAccess == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                var getInterface =
                    GetMethod<GetInterfaceDelegate>(
                        surfaceAccess,
                        3);
                Guid textureIid = NativeIds.D3D11Texture2D;
                if (getInterface(
                        surfaceAccess,
                        ref textureIid,
                        out sourceTexture) < 0
                    || sourceTexture == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                var getDescription =
                    GetMethod<GetTextureDescriptionDelegate>(
                        sourceTexture,
                        10);
                getDescription(
                    sourceTexture,
                    out D3D11Texture2DDescription sourceDescription);
                if (sourceDescription.Format
                        != NativeConstants.DxgiFormatBgra8Unorm
                    || sourceDescription.SampleDescription.Count != 1
                    || contentSize.Width
                        > sourceDescription.Width
                    || contentSize.Height
                        > sourceDescription.Height)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                D3D11Texture2DDescription stagingDescription =
                    D3D11Texture2DDescription.Staging(
                        contentSize.Width,
                        contentSize.Height);
                var createTexture =
                    GetMethod<CreateTexture2DDelegate>(
                        d3dDevice,
                        5);
                if (createTexture(
                        d3dDevice,
                        ref stagingDescription,
                        IntPtr.Zero,
                        out stagingTexture) < 0
                    || stagingTexture == IntPtr.Zero)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                if (GetDeviceRemovedReason(d3dDevice) < 0)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                var copyRegion =
                    GetMethod<CopySubresourceRegionDelegate>(
                        d3dContext,
                        46);
                var sourceBox = new D3D11Box
                {
                    Left = 0,
                    Top = 0,
                    Front = 0,
                    Right = checked((uint)contentSize.Width),
                    Bottom = checked((uint)contentSize.Height),
                    Back = 1
                };
                copyRegion(
                    d3dContext,
                    stagingTexture,
                    0,
                    0,
                    0,
                    0,
                    sourceTexture,
                    0,
                    ref sourceBox);
                var flush = GetMethod<FlushDelegate>(
                    d3dContext,
                    111);
                flush(d3dContext);

                var map = GetMethod<MapDelegate>(
                    d3dContext,
                    14);
                if (!TryMapUntilDeadline(
                        map,
                        d3dContext,
                        stagingTexture,
                        cancellationToken,
                        nativeDeadline,
                        out D3D11MappedSubresource mapped)
                    || mapped.Data == IntPtr.Zero
                    || mapped.RowPitch
                        < checked((uint)contentSize.Width * 4U)
                    || mapped.RowPitch > int.MaxValue)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                byte[] pixels = new byte[tightByteCount];
                try
                {
                    int tightStride =
                        checked(contentSize.Width * 4);
                    for (int row = 0;
                        row < contentSize.Height;
                        row++)
                    {
                        cancellationToken
                            .ThrowIfCancellationRequested();
                        Marshal.Copy(
                            IntPtr.Add(
                                mapped.Data,
                                checked(
                                    row
                                    * (int)mapped.RowPitch)),
                            pixels,
                            checked(row * tightStride),
                            tightStride);
                    }
                }
                catch
                {
                    System.Security.Cryptography
                        .CryptographicOperations
                        .ZeroMemory(pixels);
                    throw;
                }
                finally
                {
                    var unmap = GetMethod<UnmapDelegate>(
                        d3dContext,
                        15);
                    unmap(
                        d3dContext,
                        stagingTexture,
                        0);
                }

                if (GetDeviceRemovedReason(d3dDevice) < 0)
                {
                    System.Security.Cryptography
                        .CryptographicOperations
                        .ZeroMemory(pixels);
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }

                WindowFrameCaptureResult captured =
                    WindowFrameCaptureResult.Captured(
                        pixels,
                        contentSize.Width,
                        contentSize.Height,
                        ObservationMode.WindowGraphicsCapture);
                if (!CapturedFrameSafety.IsAcceptableBgra(
                        captured,
                        out string safetyReason))
                {
                    captured.Dispose();
                    return WindowFrameCaptureResult.Unavailable(
                        safetyReason);
                }
                return captured;
            }
            finally
            {
                Release(ref stagingTexture);
                Release(ref sourceTexture);
                Release(ref surfaceAccess);
                Release(ref surface);
                CloseAndRelease(ref frame);
                CloseAndRelease(ref captureSession);
                CloseAndRelease(ref framePool);
                Release(ref framePoolStatics);
                Release(ref direct3DDevice);
                CloseAndRelease(ref inspectableDevice);
                Release(ref dxgiDevice);
                Release(ref d3dContext);
                Release(ref d3dDevice);
                if (shouldUninitialize)
                    RoUninitialize();
            }
        }

        private static IntPtr WaitForNewestFrame(
            IntPtr framePool,
            CancellationToken cancellationToken,
            long deadline)
        {
            var nextFrame =
                GetMethod<TryGetNextFrameDelegate>(
                    framePool,
                    7);
            while (Environment.TickCount64 < deadline)
            {
                cancellationToken.ThrowIfCancellationRequested();
                int result = nextFrame(
                    framePool,
                    out IntPtr candidate);
                if (result < 0)
                {
                    if (candidate != IntPtr.Zero)
                        CloseAndRelease(ref candidate);
                    return IntPtr.Zero;
                }
                if (candidate != IntPtr.Zero)
                {
                    IntPtr newest = candidate;
                    for (int index = 0; index < 8; index++)
                    {
                        result = nextFrame(
                            framePool,
                            out candidate);
                        if (result < 0)
                        {
                            CloseAndRelease(ref newest);
                            if (candidate != IntPtr.Zero)
                                CloseAndRelease(ref candidate);
                            return IntPtr.Zero;
                        }
                        if (candidate == IntPtr.Zero)
                            break;
                        CloseAndRelease(ref newest);
                        newest = candidate;
                    }
                    return newest;
                }

                int remaining = checked(
                    (int)Math.Min(
                        5,
                        Math.Max(
                            0,
                            deadline
                            - Environment.TickCount64)));
                if (remaining > 0
                    && cancellationToken.WaitHandle
                        .WaitOne(remaining))
                {
                    cancellationToken
                        .ThrowIfCancellationRequested();
                }
            }
            return IntPtr.Zero;
        }

        private static bool TryMapUntilDeadline(
            MapDelegate map,
            IntPtr context,
            IntPtr stagingTexture,
            CancellationToken cancellationToken,
            long deadline,
            out D3D11MappedSubresource mapped)
        {
            mapped = default;
            while (Environment.TickCount64 < deadline)
            {
                cancellationToken.ThrowIfCancellationRequested();
                int result = map(
                    context,
                    stagingTexture,
                    0,
                    NativeConstants.D3D11MapRead,
                    NativeConstants.D3D11MapFlagDoNotWait,
                    out mapped);
                if (result >= 0)
                    return true;
                if (result
                    != NativeConstants
                        .DxgiErrorWasStillDrawing)
                {
                    return false;
                }

                if (cancellationToken.WaitHandle.WaitOne(2))
                {
                    cancellationToken
                        .ThrowIfCancellationRequested();
                }
            }
            mapped = default;
            return false;
        }

        private static bool TryCreateD3D11Device(
            out IntPtr device,
            out IntPtr context)
        {
            int featureLevel;
            int result = D3D11CreateDevice(
                IntPtr.Zero,
                NativeConstants.D3DDriverTypeHardware,
                IntPtr.Zero,
                NativeConstants.D3D11CreateDeviceBgraSupport,
                IntPtr.Zero,
                0,
                NativeConstants.D3D11SdkVersion,
                out device,
                out featureLevel,
                out context);
            if (result >= 0
                && device != IntPtr.Zero
                && context != IntPtr.Zero)
            {
                return true;
            }
            Release(ref context);
            Release(ref device);

            result = D3D11CreateDevice(
                IntPtr.Zero,
                NativeConstants.D3DDriverTypeWarp,
                IntPtr.Zero,
                NativeConstants.D3D11CreateDeviceBgraSupport,
                IntPtr.Zero,
                0,
                NativeConstants.D3D11SdkVersion,
                out device,
                out featureLevel,
                out context);
            if (result >= 0
                && device != IntPtr.Zero
                && context != IntPtr.Zero)
            {
                return true;
            }
            Release(ref context);
            Release(ref device);
            return false;
        }

        private static bool TryGetItemSize(
            IntPtr captureItem,
            out SizeInt32 size)
        {
            var getSize =
                GetMethod<GetSizeDelegate>(captureItem, 7);
            return getSize(captureItem, out size) >= 0;
        }

        private static bool TryValidateDimensions(
            int width,
            int height,
            out int byteCount)
        {
            byteCount = 0;
            if (width <= 0 || height <= 0)
                return false;
            try
            {
                long count = checked(
                    (long)width * height * 4L);
                if (count
                        > AgentProtocolV1
                            .MaximumBinaryObjectBytes
                    || count > int.MaxValue)
                {
                    return false;
                }
                byteCount = checked((int)count);
                return true;
            }
            catch (OverflowException)
            {
                return false;
            }
        }

        private static bool TryGetFramePoolStatics(
            out IntPtr framePoolStatics)
        {
            framePoolStatics = IntPtr.Zero;
            const string classNameText =
                "Windows.Graphics.Capture.Direct3D11CaptureFramePool";
            IntPtr className = IntPtr.Zero;
            try
            {
                if (WindowsCreateString(
                        classNameText,
                        classNameText.Length,
                        out className) < 0)
                {
                    return false;
                }
                Guid iid =
                    NativeIds.Direct3D11CaptureFramePoolStatics2;
                return RoGetActivationFactory(
                        className,
                        ref iid,
                        out framePoolStatics) >= 0
                    && framePoolStatics != IntPtr.Zero;
            }
            finally
            {
                if (className != IntPtr.Zero)
                    WindowsDeleteString(className);
            }
        }

        private static int GetDeviceRemovedReason(
            IntPtr device)
        {
            var removedReason =
                GetMethod<GetDeviceRemovedReasonDelegate>(
                    device,
                    39);
            return removedReason(device);
        }

        private static TDelegate GetMethod<TDelegate>(
            IntPtr instance,
            int slot)
            where TDelegate : Delegate
        {
            if (instance == IntPtr.Zero)
                throw new InvalidOperationException(
                    "COM instance is null.");
            IntPtr table = Marshal.ReadIntPtr(instance);
            if (table == IntPtr.Zero)
                throw new InvalidOperationException(
                    "COM vtable is null.");
            IntPtr method = Marshal.ReadIntPtr(
                table,
                checked(slot * IntPtr.Size));
            if (method == IntPtr.Zero)
                throw new InvalidOperationException(
                    "COM method is null.");
            return Marshal.GetDelegateForFunctionPointer<TDelegate>(
                method);
        }

        private static void CloseAndRelease(
            ref IntPtr pointer)
        {
            IntPtr value = pointer;
            pointer = IntPtr.Zero;
            if (value == IntPtr.Zero)
                return;

            IntPtr closable = IntPtr.Zero;
            try
            {
                Guid iid = NativeIds.Closable;
                if (Marshal.QueryInterface(
                        value,
                        ref iid,
                        out closable) >= 0
                    && closable != IntPtr.Zero)
                {
                    var close =
                        GetMethod<CloseDelegate>(
                            closable,
                            6);
                    _ = close(closable);
                }
            }
            finally
            {
                Release(ref closable);
                Marshal.Release(value);
            }
        }

        private static void Release(ref IntPtr pointer)
        {
            IntPtr value = pointer;
            pointer = IntPtr.Zero;
            if (value != IntPtr.Zero)
                Marshal.Release(value);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SizeInt32
        {
            public int Width;
            public int Height;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SampleDescription
        {
            public uint Count;
            public uint Quality;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct D3D11Texture2DDescription
        {
            public uint Width;
            public uint Height;
            public uint MipLevels;
            public uint ArraySize;
            public int Format;
            public SampleDescription SampleDescription;
            public uint Usage;
            public uint BindFlags;
            public uint CpuAccessFlags;
            public uint MiscFlags;

            public static D3D11Texture2DDescription Staging(
                int width,
                int height)
            {
                return new D3D11Texture2DDescription
                {
                    Width = checked((uint)width),
                    Height = checked((uint)height),
                    MipLevels = 1,
                    ArraySize = 1,
                    Format =
                        NativeConstants.DxgiFormatBgra8Unorm,
                    SampleDescription = new SampleDescription
                    {
                        Count = 1,
                        Quality = 0
                    },
                    Usage = NativeConstants.D3D11UsageStaging,
                    BindFlags = 0,
                    CpuAccessFlags =
                        NativeConstants.D3D11CpuAccessRead,
                    MiscFlags = 0
                };
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct D3D11MappedSubresource
        {
            public IntPtr Data;
            public uint RowPitch;
            public uint DepthPitch;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct D3D11Box
        {
            public uint Left;
            public uint Top;
            public uint Front;
            public uint Right;
            public uint Bottom;
            public uint Back;
        }

        private static class NativeConstants
        {
            public const int DxgiFormatBgra8Unorm = 87;
            public const uint D3D11SdkVersion = 7;
            public const uint D3D11CreateDeviceBgraSupport = 0x20;
            public const int D3DDriverTypeHardware = 1;
            public const int D3DDriverTypeWarp = 5;
            public const uint D3D11UsageStaging = 3;
            public const uint D3D11CpuAccessRead = 0x20000;
            public const uint D3D11MapRead = 1;
            public const uint D3D11MapFlagDoNotWait = 0x100000;
            public const int DxgiErrorWasStillDrawing =
                unchecked((int)0x887A000A);
        }

        private static class NativeIds
        {
            public static readonly Guid IdxgiDevice =
                new Guid(
                    "54EC77FA-1377-44E6-8C32-88FD5F44C84C");
            public static readonly Guid Direct3DDevice =
                new Guid(
                    "A37624AB-8D5F-4650-9D3E-9EAE3D9BC670");
            public static readonly Guid
                Direct3D11CaptureFramePoolStatics2 =
                    new Guid(
                        "589B103F-6BBC-5DF5-A991-02E28B3B66D5");
            public static readonly Guid
                Direct3DDxgiInterfaceAccess =
                    new Guid(
                        "A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1");
            public static readonly Guid D3D11Texture2D =
                new Guid(
                    "6F15AAF2-D208-4E89-9AB4-489535D34F9C");
            public static readonly Guid Closable =
                new Guid(
                    "30D5A829-7FA4-4026-83BB-D75BAE4EA99E");
        }

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int CreateFreeThreadedDelegate(
            IntPtr instance,
            IntPtr device,
            int pixelFormat,
            int numberOfBuffers,
            SizeInt32 size,
            out IntPtr framePool);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int CreateCaptureSessionDelegate(
            IntPtr instance,
            IntPtr item,
            out IntPtr captureSession);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int StartCaptureDelegate(
            IntPtr instance);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int TryGetNextFrameDelegate(
            IntPtr instance,
            out IntPtr frame);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetSizeDelegate(
            IntPtr instance,
            out SizeInt32 size);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetObjectDelegate(
            IntPtr instance,
            out IntPtr value);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetInterfaceDelegate(
            IntPtr instance,
            ref Guid interfaceId,
            out IntPtr value);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate void GetTextureDescriptionDelegate(
            IntPtr instance,
            out D3D11Texture2DDescription description);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int CreateTexture2DDelegate(
            IntPtr instance,
            ref D3D11Texture2DDescription description,
            IntPtr initialData,
            out IntPtr texture);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate void CopySubresourceRegionDelegate(
            IntPtr instance,
            IntPtr destinationResource,
            uint destinationSubresource,
            uint destinationX,
            uint destinationY,
            uint destinationZ,
            IntPtr sourceResource,
            uint sourceSubresource,
            ref D3D11Box sourceBox);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int MapDelegate(
            IntPtr instance,
            IntPtr resource,
            uint subresource,
            uint mapType,
            uint mapFlags,
            out D3D11MappedSubresource mapped);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate void UnmapDelegate(
            IntPtr instance,
            IntPtr resource,
            uint subresource);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetDeviceRemovedReasonDelegate(
            IntPtr instance);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate void FlushDelegate(
            IntPtr instance);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int CloseDelegate(
            IntPtr instance);

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern int RoInitialize(
            uint initializationType);

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
        private static extern int WindowsDeleteString(
            IntPtr hstring);

        [DllImport("combase.dll", ExactSpelling = true)]
        private static extern int RoGetActivationFactory(
            IntPtr activatableClassId,
            ref Guid interfaceId,
            out IntPtr factory);

        [DllImport("d3d11.dll", ExactSpelling = true)]
        private static extern int D3D11CreateDevice(
            IntPtr adapter,
            int driverType,
            IntPtr software,
            uint flags,
            IntPtr featureLevels,
            uint featureLevelCount,
            uint sdkVersion,
            out IntPtr device,
            out int selectedFeatureLevel,
            out IntPtr immediateContext);

        [DllImport("d3d11.dll", ExactSpelling = true)]
        private static extern int
            CreateDirect3D11DeviceFromDXGIDevice(
                IntPtr dxgiDevice,
                out IntPtr graphicsDevice);
    }
}
