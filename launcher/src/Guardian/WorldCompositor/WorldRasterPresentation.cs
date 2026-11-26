using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal interface IWorldRasterScene
    {
        void UploadHud(IntPtr pixels, int width, int height, int stride, int x, int y);
        void ClearHud(IntPtr transparent) => UploadHud(transparent,1,1,4,0,0);
    }

    internal interface IWorldRasterDamageScene
    {
        bool SupportsDamage { get; }
        bool TryUploadDamage(IntPtr pixels, int width, int height, int stride, int x, int y,
            int[] rectangles, int count);
    }

    internal interface ISharedWorldAnchoredScene
    {
        bool SupportsSharedWorldTransform { get; }
    }

    internal sealed class OpaqueHudRasterScene : IWorldRasterScene, IWorldRasterDamageScene, ISharedWorldAnchoredScene
    {
        private readonly NativeCompositorSession _native;
        private readonly int _layer;
        internal OpaqueHudRasterScene(NativeCompositorSession native,int layer)
        {
            if(layer<0 || layer>4)throw new ArgumentOutOfRangeException(nameof(layer));
            _native=native ?? throw new ArgumentNullException(nameof(native));_layer=layer;
        }
        public bool SupportsDamage => _layer == 1 && _native.SupportsRasterDamageFor(_layer);
        // Native applies the world offset only to the damage-number layer.
        public bool SupportsSharedWorldTransform => _layer == 0;
        public bool TryUploadDamage(IntPtr pixels,int width,int height,int stride,int x,int y,int[] rectangles,int count)
            => _native.TrySetHudRasterRects(_layer,pixels,width,height,stride,x,y,rectangles,count);
        public void UploadHud(IntPtr pixels,int width,int height,int stride,int x,int y)
            => _native.SetHudRaster(_layer,pixels,width,height,stride,x,y);
        public void ClearHud(IntPtr transparent)
            => _native.SetHudRaster(_layer,IntPtr.Zero,0,0,0,0,0);
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
        private readonly Func<Rectangle> _currentOutputBounds;
        private readonly IntPtr _transparent = Marshal.AllocHGlobal(4);
        internal event Action Changed;
        internal event Action<Exception> Faulted;
        internal bool IsAvailable => !_disposed && _available && _scene != null;
        internal bool SupportsDamage => _scene is IWorldRasterDamageScene { SupportsDamage: true };
        internal bool SupportsSharedWorldTransform =>
            IsAvailable && _scene is ISharedWorldAnchoredScene { SupportsSharedWorldTransform: true };
        private WorldRasterRegion _lastRegion;
        internal ulong Uploads { get; private set; }
        internal ulong UploadedBytes { get; private set; }

        internal WorldRasterPresentation(Func<Rectangle> currentOutputBounds = null)
        {
            _currentOutputBounds = currentOutputBounds;
            Marshal.WriteInt32(_transparent, 0);
        }

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
            => TryPresent(pixels,width,height,stride,screenOrigin,null);

        internal bool TryPresent(IntPtr pixels, int width, int height, int stride, Point screenOrigin, Rectangle[] damage)
        {
            if (!IsAvailable) return false;
            if (pixels == IntPtr.Zero || width < 1 || height < 1 || width > 4096 || height > 4096 || stride > 16384)
                return false;
            // Owner.Move can update a HUD before the world's LocationChanged
            // callback moves P. Resolve both in the current anchor coordinate
            // space; clipping against the previous desktop origin truncates and
            // offsets the retained raster until a queued repaint gets dispatched.
            Rectangle output = _currentOutputBounds?.Invoke() ?? _bounds;
            var region = WorldRasterRegion.Clip(new Rectangle(screenOrigin, new Size(width, height)), output, stride);
            if (region.Width == 0 || region.Height == 0) { Hide(); return true; }
            IntPtr visiblePixels = IntPtr.Add(pixels, region.OffsetBytes);
            if (_hasContent && _lastRegion == region && damage is { Length: > 0 and <= 16 } &&
                _scene is IWorldRasterDamageScene { SupportsDamage: true } sparse)
            {
                var visible = new Rectangle(output.Left + region.X - screenOrigin.X, output.Top + region.Y - screenOrigin.Y,
                    region.Width, region.Height);
                var rectangles = new int[damage.Length * 4];
                int count = 0;
                ulong bytes = 0;
                foreach (var rect in damage)
                {
                    var clipped = Rectangle.Intersect(visible, rect);
                    if (clipped.Width <= 0 || clipped.Height <= 0) continue;
                    rectangles[count * 4] = clipped.X - visible.X;
                    rectangles[count * 4 + 1] = clipped.Y - visible.Y;
                    rectangles[count * 4 + 2] = clipped.Width;
                    rectangles[count * 4 + 3] = clipped.Height;
                    bytes += (ulong)clipped.Width * (ulong)clipped.Height * 4;
                    count++;
                }
                if (count == 0) return true;
                try
                {
                    if (bytes < (ulong)region.Width * (ulong)region.Height * 4 &&
                        sparse.TryUploadDamage(visiblePixels,region.Width,region.Height,stride,region.X,region.Y,rectangles,count))
                    {
                        Uploads++; UploadedBytes += bytes;
                        return true;
                    }
                }
                catch (Exception error) { Reject(error); return true; }
            }
            if (!Upload(visiblePixels, region.Width, region.Height,
                stride, region.X, region.Y)) return true;
            _lastRegion = region;
            _hasContent = true;
            Uploads++;
            UploadedBytes += checked((ulong)region.Width * (ulong)region.Height * 4);
            return true;
        }

        internal void Hide()
        {
            if (!_hasContent || _scene == null) return;
            Upload(_transparent, 1, 1, 4, 0, 0,clear:true);
            _hasContent = false;
        }

        private bool Upload(IntPtr pixels, int width, int height, int stride, int x, int y,bool clear=false)
        {
            try {
                if(clear)_scene.ClearHud(_transparent);
                else _scene.UploadHud(pixels, width, height, stride, x, y);
                return true;
            }
            catch (Exception error)
            {
                Reject(error);
                return false;
            }
        }

        internal void Reject(Exception error)
        {
            if(_disposed)return;
            _scene=null;_available=false;_hasContent=false;_faultVersion++;
            Faulted?.Invoke(error);
            Changed?.Invoke();
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
