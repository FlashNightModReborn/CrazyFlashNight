using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Owns one native composition scene inside FlashCompositorNative.dll.
    // Every member, including Dispose, must run on the creating UI thread;
    // the component intentionally has no finalizer.
    internal sealed class CompositionSceneHost : IDisposable, IWorldRasterScene
    {
        private const int ExpectedAbiVersion = 1;
        private readonly int _ownerThreadId;
        private IntPtr _module, _scene;
        private readonly CreateDelegate _create;
        private readonly VisualDelegate _visual;
        private readonly UploadDelegate _upload;
        private readonly SnapshotDelegate _snapshot;
        private readonly PresentationDelegate _presentation;
        private readonly SceneDelegate _commit, _destroy;
        private bool _disposed;
        internal string ModulePath { get; }

        public CompositionSceneHost(IntPtr output, string modulePath = null)
        {
            _ownerThreadId = Thread.CurrentThread.ManagedThreadId;
            modulePath ??= Path.Combine(AppContext.BaseDirectory, NativeCompositorSession.ModuleName);
            if (!Path.IsPathFullyQualified(modulePath))
                throw new ArgumentException("Composition module must use an absolute path.", nameof(modulePath));
            ModulePath = Path.GetFullPath(modulePath);
            try
            {
                _module = NativeLibrary.Load(ModulePath);
                if (Export<AbiDelegate>("CompositionSceneAbiVersion")() != ExpectedAbiVersion)
                    throw new NotSupportedException(
                        "FlashCompositorNative composition scene ABI mismatch; expected version " + ExpectedAbiVersion + ".");
                _create = Export<CreateDelegate>("CompositionSceneCreate");
                _visual = Export<VisualDelegate>("CompositionSceneVisual");
                _upload = Export<UploadDelegate>("CompositionSceneUploadHud");
                _snapshot = Export<SnapshotDelegate>("CompositionSceneSnapshot");
                _presentation = Export<PresentationDelegate>("CompositionScenePresentation");
                _commit = Export<SceneDelegate>("CompositionSceneCommit");
                _destroy = Export<SceneDelegate>("CompositionSceneDestroy");
                _scene = _create(output);
                if (_scene == IntPtr.Zero)
                    throw new InvalidOperationException("CompositionSceneCreate failed for the supplied output window.");
            }
            catch
            {
                if (_module != IntPtr.Zero) NativeLibrary.Free(_module);
                _module = IntPtr.Zero;
                throw;
            }
        }

        public static CompositionSceneHost Create(IntPtr output, string modulePath = null)
        {
            return new CompositionSceneHost(output, modulePath);
        }

        private T Export<T>(string name) where T : Delegate
            => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(_module, name));

        // Borrowed delegates are valid only until this scene is disposed.
        internal T GetRequiredExport<T>(string name) where T : Delegate
        {
            EnsureUsable();
            return Export<T>(name);
        }

        // The returned pointer is AddRef'd; the caller must Marshal.Release it.
        public IntPtr AcquireVisual(int layer)
        {
            EnsureUsable();
            if (layer < 0 || layer > 2)
                throw new ArgumentOutOfRangeException(nameof(layer));
            IntPtr visual = _visual(_scene, layer);
            if (visual == IntPtr.Zero)
                throw new InvalidOperationException("CompositionSceneVisual returned no visual.");
            return visual;
        }

        public void UploadHud(IntPtr pixels, int width, int height, int stride, int x, int y)
        {
            EnsureUsable();
            ThrowIfFailed(_upload(_scene, pixels, width, height, stride, x, y));
        }

        public void Snapshot(IntPtr pixels, int width, int height, int stride)
        {
            EnsureUsable();
            ThrowIfFailed(_snapshot(_scene, pixels, width, height, stride));
        }

        public void Presentation(bool modal, bool frozen, int width, int height)
        {
            EnsureUsable();
            ThrowIfFailed(_presentation(_scene, modal ? 1 : 0, frozen ? 1 : 0, width, height));
        }

        public void Commit()
        {
            EnsureUsable();
            ThrowIfFailed(_commit(_scene));
        }

        public void Dispose()
        {
            if (_disposed) return;
            EnsureOwnerThread();
            // A failed native retirement retains the handle and module; never
            // unload code that may still own live composition objects.
            if (_scene != IntPtr.Zero) ThrowIfFailed(_destroy(_scene));
            _scene = IntPtr.Zero;
            if (_module != IntPtr.Zero) NativeLibrary.Free(_module);
            _module = IntPtr.Zero;
            _disposed = true;
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

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int AbiDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr CreateDelegate(IntPtr output);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr VisualDelegate(IntPtr scene, int layer);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int UploadDelegate(IntPtr scene, IntPtr pixels,
            int width, int height, int stride, int x, int y);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SnapshotDelegate(IntPtr scene, IntPtr pixels,
            int width, int height, int stride);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int PresentationDelegate(IntPtr scene,
            int modal, int frozen, int width, int height);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SceneDelegate(IntPtr scene);
    }
}
