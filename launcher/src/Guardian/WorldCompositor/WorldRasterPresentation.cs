using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal interface IWorldRasterScene
    {
        void UploadHud(IntPtr pixels, int width, int height, int stride, int x, int y);
    }

    internal readonly record struct WorldRasterRegion(int Width, int Height, int X, int Y, int OffsetBytes)
    {
        internal static WorldRasterRegion Clip(Rectangle source, Rectangle output, int stride)
        {
            if (source.Width < 1 || source.Height < 1 || stride < checked(source.Width * 4) || stride % 4 != 0)
                throw new ArgumentOutOfRangeException(nameof(stride));
            Rectangle visible = Rectangle.Intersect(source, output);
            if (visible.IsEmpty) return default;
            return new WorldRasterRegion(visible.Width, visible.Height,
                visible.Left - output.Left, visible.Top - output.Top,
                checked((visible.Top - source.Top) * stride + (visible.Left - source.Left) * 4));
        }
    }

    // Borrows pixels only for the synchronous upload. It never keeps a DIB
    // pointer or copies a full-screen image into managed memory.
    internal sealed class WorldRasterPresentation : IDisposable
    {
        private IWorldRasterScene _scene;
        private Rectangle _bounds;
        private bool _available, _hasContent, _disposed;
        private long _adoptionVersion, _faultVersion;
        private readonly IntPtr _transparent = Marshal.AllocHGlobal(4);
        internal event Action Changed;
        internal event Action<Exception> Faulted;
        internal bool IsAvailable => !_disposed && _available && _scene != null;
        internal ulong Uploads { get; private set; }
        internal ulong UploadedBytes { get; private set; }

        internal WorldRasterPresentation() => Marshal.WriteInt32(_transparent, 0);

        internal void Adopt(IWorldRasterScene scene, Rectangle bounds, bool available)
        {
            if (_disposed) return;
            available &= scene != null && bounds.Width > 0 && bounds.Height > 0;
            if (ReferenceEquals(_scene, scene) && _bounds == bounds && _available == available) return;
            long adoption = ++_adoptionVersion;
            long faults = _faultVersion;
            if (_hasContent && (!available || !ReferenceEquals(_scene, scene))) Hide();
            // Failure notification can synchronously retire the entire scene.
            // Never re-adopt its stale pointer after the owner tears it down.
            if (adoption != _adoptionVersion || faults != _faultVersion || _disposed) return;
            _scene = scene; _bounds = bounds; _available = available;
            Changed?.Invoke();
        }

        internal bool TryPresent(IntPtr pixels, int width, int height, int stride, Point screenOrigin)
        {
            if (!IsAvailable) return false;
            if (pixels == IntPtr.Zero || width < 1 || height < 1 || width > 4096 || height > 4096 || stride > 16384)
                return false;
            var region = WorldRasterRegion.Clip(new Rectangle(screenOrigin, new Size(width, height)), _bounds, stride);
            if (region.Width == 0 || region.Height == 0) { Hide(); return true; }
            if (!Upload(IntPtr.Add(pixels, region.OffsetBytes), region.Width, region.Height,
                stride, region.X, region.Y)) return true;
            _hasContent = true;
            Uploads++;
            UploadedBytes += checked((ulong)region.Width * (ulong)region.Height * 4);
            return true;
        }

        internal void Hide()
        {
            if (!_hasContent || _scene == null) return;
            Upload(_transparent, 1, 1, 4, 0, 0);
            _hasContent = false;
        }

        private bool Upload(IntPtr pixels, int width, int height, int stride, int x, int y)
        {
            try { _scene.UploadHud(pixels, width, height, stride, x, y); return true; }
            catch (Exception error)
            {
                _scene = null; _available = false; _hasContent = false;
                _faultVersion++;
                Faulted?.Invoke(error);
                Changed?.Invoke();
                return false;
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            Adopt(null, Rectangle.Empty, false);
            _disposed = true;
            Changed = null;
            Faulted = null;
            Marshal.FreeHGlobal(_transparent);
        }
    }
}
