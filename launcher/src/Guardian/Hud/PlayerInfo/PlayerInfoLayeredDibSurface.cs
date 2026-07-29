#nullable enable

using System;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using CF7Launcher.Diagnostic;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>
/// One reusable top-down PArgb DIB selected into a persistent memory DC.
/// The managed Bitmap is a non-owning view over the DIB pixels, so Skia
/// paints the exact bytes consumed by UpdateLayeredWindow without a
/// per-frame GetHbitmap copy.
/// Construction, painting, commit, and disposal are confined to the owning
/// PlayerInfo UI thread.
/// </summary>
internal sealed class PlayerInfoLayeredDibSurface : IDisposable
{
    private static readonly IntPtr InvalidGdiHandle = new(-1);
    private const uint DibRgbColors = 0;
    private const uint BiRgb = 0;

    private IntPtr _memoryDc;
    private IntPtr _bitmapHandle;
    private IntPtr _previousObject;
    private bool _bitmapSelected;
    private Bitmap? _bitmap;
    private bool _disposed;

    internal PlayerInfoLayeredDibSurface(int width, int height)
    {
        if (width <= 0 || height <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(width),
                "PlayerInfo prepared DIB must be non-empty.");
        }
        Width = width;
        Height = height;
        int stride = checked(width * 4);
        var info = new BitmapInfo
        {
            Header = new BitmapInfoHeader
            {
                Size = checked((uint)Marshal.SizeOf<BitmapInfoHeader>()),
                Width = width,
                Height = -height,
                Planes = 1,
                BitCount = 32,
                Compression = BiRgb,
                SizeImage = checked((uint)(stride * height))
            }
        };

        try
        {
            _memoryDc = CreateCompatibleDC(IntPtr.Zero);
            if (_memoryDc == IntPtr.Zero)
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "CreateCompatibleDC failed for PlayerInfo.");
            }
            _bitmapHandle = CreateDIBSection(
                IntPtr.Zero,
                ref info,
                DibRgbColors,
                out IntPtr pixels,
                IntPtr.Zero,
                0);
            if (_bitmapHandle == IntPtr.Zero || pixels == IntPtr.Zero)
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "CreateDIBSection failed for PlayerInfo.");
            }
            _previousObject = SelectObject(
                _memoryDc,
                _bitmapHandle);
            if (_previousObject == IntPtr.Zero ||
                _previousObject == InvalidGdiHandle)
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "SelectObject failed for PlayerInfo.");
            }
            _bitmapSelected = true;
            _bitmap = new Bitmap(
                width,
                height,
                stride,
                PixelFormat.Format32bppPArgb,
                pixels);
        }
        catch
        {
            ReleaseOwnedResources();
            throw;
        }
    }

    internal int Width { get; }
    internal int Height { get; }
    internal IntPtr MemoryDc =>
        !_disposed && _memoryDc != IntPtr.Zero
            ? _memoryDc
            : throw new ObjectDisposedException(
                nameof(PlayerInfoLayeredDibSurface));
    internal Bitmap Bitmap =>
        !_disposed && _bitmap is not null
            ? _bitmap
            : throw new ObjectDisposedException(
                nameof(PlayerInfoLayeredDibSurface));

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        ReleaseOwnedResources();
    }

    private void ReleaseOwnedResources()
    {
        string? managedViewDisposeError = null;
        try
        {
            _bitmap?.Dispose();
        }
        catch (Exception ex)
        {
            managedViewDisposeError =
                ex.GetType().Name + ": " + ex.Message;
        }
        finally
        {
            _bitmap = null;
        }

        bool managedViewDisposed = managedViewDisposeError is null;
        bool restored = !_bitmapSelected;
        bool bitmapDeleted = _bitmapHandle == IntPtr.Zero;
        bool bitmapIntentionallyRetained =
            _bitmapHandle != IntPtr.Zero && !managedViewDisposed;
        bool memoryDcDeleted = _memoryDc == IntPtr.Zero;
        int restoreError = 0;
        int bitmapDeleteError = 0;
        int memoryDcDeleteError = 0;
        if (_bitmapSelected && _memoryDc != IntPtr.Zero)
        {
            IntPtr restoreResult = SelectObject(
                _memoryDc,
                _previousObject);
            restored = restoreResult != IntPtr.Zero &&
                restoreResult != InvalidGdiHandle;
            if (!restored)
            {
                restoreError = Marshal.GetLastWin32Error();
            }
        }
        if (_bitmapHandle != IntPtr.Zero &&
            restored &&
            managedViewDisposed)
        {
            bitmapDeleted = DeleteObject(_bitmapHandle);
            if (!bitmapDeleted)
            {
                bitmapDeleteError = Marshal.GetLastWin32Error();
            }
        }
        if (_memoryDc != IntPtr.Zero)
        {
            memoryDcDeleted = DeleteDC(_memoryDc);
            if (!memoryDcDeleted)
            {
                memoryDcDeleteError = Marshal.GetLastWin32Error();
            }
        }
        if (_bitmapHandle != IntPtr.Zero &&
            !bitmapDeleted &&
            managedViewDisposed &&
            (restored || memoryDcDeleted))
        {
            bitmapDeleted = DeleteObject(_bitmapHandle);
            if (!bitmapDeleted)
            {
                bitmapDeleteError = Marshal.GetLastWin32Error();
            }
        }
        if (managedViewDisposeError is not null ||
            !restored ||
            (!bitmapDeleted && !bitmapIntentionallyRetained) ||
            !memoryDcDeleted)
        {
            LogBestEffort(
                "managedView=" +
                (managedViewDisposeError ?? "disposed") + " " +
                "restore=" + restored + "(" + restoreError + ") " +
                "bitmap=" + bitmapDeleted + "(" + bitmapDeleteError + ") " +
                "bitmapRetained=" + bitmapIntentionallyRetained + " " +
                "dc=" + memoryDcDeleted + "(" + memoryDcDeleteError + ").");
        }

        _bitmapSelected = false;
        _previousObject = IntPtr.Zero;
        _bitmapHandle = IntPtr.Zero;
        _memoryDc = IntPtr.Zero;
    }

    private static void LogBestEffort(string detail)
    {
        try
        {
            LogManager.Log(
                "[PlayerInfoLayeredDibSurface] cleanup " + detail);
        }
        catch
        {
            // Native cleanup diagnostics must not cause a second disposal
            // failure after the handles have already been released.
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        internal uint Size;
        internal int Width;
        internal int Height;
        internal ushort Planes;
        internal ushort BitCount;
        internal uint Compression;
        internal uint SizeImage;
        internal int XPixelsPerMeter;
        internal int YPixelsPerMeter;
        internal uint ColorsUsed;
        internal uint ColorsImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        internal BitmapInfoHeader Header;
        internal uint Colors;
    }

    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr CreateCompatibleDC(IntPtr dc);

    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr CreateDIBSection(
        IntPtr dc,
        ref BitmapInfo bitmapInfo,
        uint usage,
        out IntPtr pixels,
        IntPtr section,
        uint offset);

    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr SelectObject(IntPtr dc, IntPtr handle);

    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern bool DeleteObject(IntPtr handle);

    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern bool DeleteDC(IntPtr dc);
}
