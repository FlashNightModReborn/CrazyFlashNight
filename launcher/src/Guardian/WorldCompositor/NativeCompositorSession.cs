using System;
using System.IO;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Explicit app-local world renderer module; never search PATH or another runtime for a substitute.
    internal sealed class NativeCompositorSession : IDisposable
    {
        internal const string ModuleName = "FlashCompositorNative.dll";
        private IntPtr _module, _session;
        private readonly StopDelegate _stop;
        private readonly ReadDelegate _read;
        private readonly CropDelegate _crop;
        private readonly ModeDelegate _mode;
        private readonly MatrixDelegate _matrix;
        private readonly ActiveDelegate _active;
        private readonly ViewportDelegate _viewport;
        private readonly SharpnessDelegate _sharpness;
        private readonly StopDelegate _holdViewport;

        internal NativeCompositorSession(string modulePath, IntPtr source, uint pid, IntPtr output, uint vendor = 0, bool borderless = false)
        {
            try
            {
                _module = NativeLibrary.Load(Path.GetFullPath(modulePath));
                if (Export<VersionDelegate>("ProbeGetAbiVersion")() != 3) throw new InvalidOperationException("Compositor ABI version mismatch");
                _stop = Export<StopDelegate>("ProbeStop"); _read = Export<ReadDelegate>("ProbeGetStats");
                _crop = Export<CropDelegate>("ProbeSetCrop"); _mode = Export<ModeDelegate>("ProbeSetMode");
                _matrix=Export<MatrixDelegate>("ProbeSetMatrix"); _active=Export<ActiveDelegate>("ProbeSetActive");
                _viewport=Export<ViewportDelegate>("ProbeSetViewport"); _sharpness=Export<SharpnessDelegate>("ProbeSetSharpness");
                _holdViewport=Export<StopDelegate>("ProbeHoldViewport");
                _session = Export<StartDelegate>("ProbeStartWorld")(source,pid,output,vendor,borderless ? 1 : 0);
                if (_session == IntPtr.Zero) throw new InvalidOperationException("Compositor initialization failed");
            }
            catch { Dispose(); throw; }
        }
        private T Export<T>(string name) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(_module,name));
        internal Stats Read()
        {
            var value = new Stats { Size = (uint)Marshal.SizeOf<Stats>() };
            if (_session == IntPtr.Zero || _read(_session,ref value) != 1) throw new InvalidOperationException("Compositor stats unavailable");
            return value;
        }
        internal void Crop(System.Drawing.Rectangle rect)
        {
            if (_session == IntPtr.Zero || _crop(_session,rect.X,rect.Y,rect.Width,rect.Height) != 1)
                throw new InvalidOperationException("Invalid compositor crop");
        }
        internal static int RequestBorderless(string modulePath)
        {
            IntPtr module=NativeLibrary.Load(Path.GetFullPath(modulePath));
            try { return Marshal.GetDelegateForFunctionPointer<PermissionDelegate>(NativeLibrary.GetExport(module,"ProbeRequestBorderless"))(); }
            finally { NativeLibrary.Free(module); }
        }
        internal void Viewport(System.Drawing.Rectangle rect,double notBefore)
        {
            if (_viewport(_session,rect.X,rect.Y,rect.Width,rect.Height,notBefore)!=1) throw new InvalidOperationException("Invalid render viewport");
        }
        internal void HoldViewport() { _holdViewport(_session); }
        internal void Sharpness(float value) { if (_sharpness(_session,value)!=1) throw new InvalidOperationException("Invalid sharpness"); }
        internal void Matrix(float[] values) { if (_matrix(_session,values)!=1) throw new InvalidOperationException("Invalid lighting matrix"); }
        internal void Active(bool active) { if (_session!=IntPtr.Zero) _active(_session,active ? 1 : 0); }
        internal void Mode(int mode) { if (_session != IntPtr.Zero) _mode(_session,mode); }
        public void Dispose()
        {
            if (_session != IntPtr.Zero) { _stop(_session); _session=IntPtr.Zero; }
            if (_module != IntPtr.Zero) { NativeLibrary.Free(_module); _module=IntPtr.Zero; }
        }
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
        internal struct Stats
        {
            public uint Size, State; public int Error;
            public uint Vendor, Device, FeatureLevel, Width, Height;
            public ulong Received, Presented, Superseded, Resizes, CpuReadbacks;
            public double AgeMs, MaxAgeMs, SubmitMs, PresentMs, LastFrameQpcMs;
            public uint ProofCount, ProofMode, ProofMaxError, ProofDistinct;
            [MarshalAs(UnmanagedType.ByValArray,SizeConst=3)] public uint[] InputPixels;
            [MarshalAs(UnmanagedType.ByValArray,SizeConst=3)] public uint[] OutputPixels;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Adapter;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)] public string Message;
        }
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate uint VersionDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ViewportDelegate(IntPtr handle,int x,int y,int width,int height,double notBefore);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SharpnessDelegate(IntPtr handle,float value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int PermissionDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int MatrixDelegate(IntPtr handle,[In] float[] values);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ActiveDelegate(IntPtr handle,int active);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr StartDelegate(IntPtr source,uint pid,IntPtr output,uint vendor,int borderless);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void StopDelegate(IntPtr handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ReadDelegate(IntPtr handle,ref Stats stats);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CropDelegate(IntPtr handle,int x,int y,int width,int height);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ModeDelegate(IntPtr handle,int mode);
    }
}
