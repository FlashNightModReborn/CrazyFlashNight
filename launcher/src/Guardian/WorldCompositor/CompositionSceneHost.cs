using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Owns one native composition scene inside FlashCompositorNative.dll.
    // Every member, including Dispose, must run on the creating UI thread;
    // the component intentionally has no finalizer.
    internal sealed class CompositionSceneHost : IDisposable
    {
        private const int ExpectedAbiVersion = 1;
        private readonly int _ownerThreadId;
        private IntPtr _scene;
        private bool _disposed;

        public CompositionSceneHost(IntPtr output)
        {
            _ownerThreadId = Thread.CurrentThread.ManagedThreadId;
            // Missing export on an older native DLL surfaces as
            // EntryPointNotFoundException; no fallback is attempted.
            if (NativeMethods.CompositionSceneAbiVersion() != ExpectedAbiVersion)
                throw new NotSupportedException(
                    "FlashCompositorNative composition scene ABI mismatch; expected version " + ExpectedAbiVersion + ".");
            _scene = NativeMethods.CompositionSceneCreate(output);
            if (_scene == IntPtr.Zero)
                throw new InvalidOperationException("CompositionSceneCreate failed for the supplied output window.");
        }

        public static CompositionSceneHost Create(IntPtr output)
        {
            return new CompositionSceneHost(output);
        }

        // The returned pointer is AddRef'd; the caller must Marshal.Release it.
        public IntPtr AcquireVisual(int layer)
        {
            EnsureUsable();
            if (layer < 0 || layer > 2)
                throw new ArgumentOutOfRangeException(nameof(layer));
            IntPtr visual = NativeMethods.CompositionSceneVisual(_scene, layer);
            if (visual == IntPtr.Zero)
                throw new InvalidOperationException("CompositionSceneVisual returned no visual.");
            return visual;
        }

        public void UploadHud(IntPtr pixels, int width, int height, int stride, int x, int y)
        {
            EnsureUsable();
            ThrowIfFailed(NativeMethods.CompositionSceneUploadHud(_scene, pixels, width, height, stride, x, y));
        }

        public void Snapshot(IntPtr pixels, int width, int height, int stride)
        {
            EnsureUsable();
            ThrowIfFailed(NativeMethods.CompositionSceneSnapshot(_scene, pixels, width, height, stride));
        }

        public void Presentation(bool modal, bool frozen, int width, int height)
        {
            EnsureUsable();
            ThrowIfFailed(NativeMethods.CompositionScenePresentation(_scene, modal ? 1 : 0, frozen ? 1 : 0, width, height));
        }

        public void Commit()
        {
            EnsureUsable();
            ThrowIfFailed(NativeMethods.CompositionSceneCommit(_scene));
        }

        public void Dispose()
        {
            if (_disposed) return;
            EnsureOwnerThread();
            _disposed = true;
            IntPtr scene = _scene;
            _scene = IntPtr.Zero;
            if (scene != IntPtr.Zero)
                ThrowIfFailed(NativeMethods.CompositionSceneDestroy(scene));
        }

        private void EnsureUsable()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(CompositionSceneHost));
            EnsureOwnerThread();
        }

        private void EnsureOwnerThread()
        {
            if (Thread.CurrentThread.ManagedThreadId != _ownerThreadId)
                throw new InvalidOperationException("CompositionSceneHost members run on the creating UI thread only.");
        }

        private static void ThrowIfFailed(int hr)
        {
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
        }

        private static class NativeMethods
        {
            private const string Dll = "FlashCompositorNative.dll";

            [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
            internal static extern int CompositionSceneAbiVersion();

            [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
            internal static extern IntPtr CompositionSceneCreate(IntPtr output);

            [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
            internal static extern IntPtr CompositionSceneVisual(IntPtr handle, int layer);

            [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
            internal static extern int CompositionSceneUploadHud(IntPtr handle, IntPtr pixels, int width, int height, int stride, int x, int y);

            [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
            internal static extern int CompositionSceneSnapshot(IntPtr handle, IntPtr pixels, int width, int height, int stride);

            [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
            internal static extern int CompositionScenePresentation(IntPtr handle, int modal, int frozen, int width, int height);

            [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
            internal static extern int CompositionSceneCommit(IntPtr handle);

            [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
            internal static extern int CompositionSceneDestroy(IntPtr handle);
        }
    }
}
