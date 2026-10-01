using System;
using System.IO;
using System.Buffers;
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
        private readonly WorkReadDelegate _readWork;
        private readonly CaptureSizeDelegate _captureSize;
        private readonly CropDelegate _crop;
        private readonly ModeDelegate _mode;
        private readonly MatrixDelegate _matrix;
        private readonly ActiveDelegate _active;
        private readonly ViewportDelegate _viewport;
        private readonly SharpnessDelegate _sharpness;
        private readonly StopDelegate _holdViewport;
        // Dev-only LUT lab export; absent on older companion builds (grab reports unavailable).
        private readonly GrabDelegate _grab,_grabComposite;
        // lut-set-v1 生产 LUT 路径（32^3 RGBA8 整块上传 + 清除回退矩阵）。
        // Additive exports require the paired native DLL.
        // 严格 Export 拒绝未配套旧 DLL（与 ProbeGetCaptureSize 同模式）。
        private readonly LutDelegate _lut;
        private readonly StopDelegate _clearLut;
        private readonly WeatherDelegate _weather;
        private readonly WeatherCameraDelegate _weatherCamera;
        private readonly AtmosphereDelegate _atmosphere;
        private readonly WeatherStyleDelegate _weatherStyle;
        private readonly AtmosphereStyleDelegate _atmosphereStyle;
        private readonly BulletStylesDelegate _bulletStyles;
        private readonly BulletFrameDelegate _bulletFrame;
        private readonly CombatFxAtlasDelegate _bulletAtlas;
        private readonly CombatFxReadyDelegate _bulletReady;
        private readonly BulletFrameDelegate _rayFrame;
        private readonly CombatFxAtlasDelegate _combatFxAtlas;
        private readonly CombatFxReadyDelegate _combatFxReady;
        private readonly CombatFxFrameDelegate _combatFxFrame;
        private readonly SceneLightsDelegate _sceneLights;
        private readonly SceneLightsReadDelegate _sceneLightsRead;

        internal NativeCompositorSession(string modulePath, IntPtr source, uint pid, IntPtr output, uint vendor = 0, bool borderless = false)
        {
            try
            {
                _module = NativeLibrary.Load(Path.GetFullPath(modulePath));
                if (Export<VersionDelegate>("ProbeGetAbiVersion")() != 12) throw new InvalidOperationException("Compositor ABI version mismatch");
                _stop = Export<StopDelegate>("ProbeStop"); _read = Export<ReadDelegate>("ProbeGetStats");
                _readWork=TryExport<WorkReadDelegate>("ProbeGetWorkStats");
                _captureSize=Export<CaptureSizeDelegate>("ProbeGetCaptureSize"); // reject an old unpaired DLL
                _crop = Export<CropDelegate>("ProbeSetCrop"); _mode = Export<ModeDelegate>("ProbeSetMode");
                _matrix=Export<MatrixDelegate>("ProbeSetMatrix"); _active=Export<ActiveDelegate>("ProbeSetActive");
                _viewport=Export<ViewportDelegate>("ProbeSetViewport"); _sharpness=Export<SharpnessDelegate>("ProbeSetSharpness");
                _holdViewport=Export<StopDelegate>("ProbeHoldViewport");
                _grab=TryExport<GrabDelegate>("ProbeGrabLatestFrame");
                _grabComposite=TryExport<GrabDelegate>("ProbeGrabCompositeFrame");
                _lut=Export<LutDelegate>("ProbeSetLut"); _clearLut=Export<StopDelegate>("ProbeClearLut");
                _weather=Export<WeatherDelegate>("ProbeSetWeather"); // paired native presentation capability
                _weatherCamera=Export<WeatherCameraDelegate>("ProbeSetWeatherCamera");
                _atmosphere=Export<AtmosphereDelegate>("ProbeSetAtmosphere");
                _weatherStyle=Export<WeatherStyleDelegate>("ProbeSetWeatherStyle");
                _atmosphereStyle=Export<AtmosphereStyleDelegate>("ProbeSetAtmosphereStyle");
                _bulletStyles=Export<BulletStylesDelegate>("ProbeSetBulletStyles");
                _bulletFrame=Export<BulletFrameDelegate>("ProbeSetBulletFrame");
                _bulletAtlas=Export<CombatFxAtlasDelegate>("ProbeSetBulletAtlas");
                _bulletReady=Export<CombatFxReadyDelegate>("ProbeBulletReady");
                _rayFrame=Export<BulletFrameDelegate>("ProbeSetRayFrame");
                _combatFxAtlas=Export<CombatFxAtlasDelegate>("ProbeSetCombatFxAtlas");
                _combatFxReady=Export<CombatFxReadyDelegate>("ProbeCombatFxReady");
                _combatFxFrame=Export<CombatFxFrameDelegate>("ProbeSetCombatFxFrame");
                _sceneLights=Export<SceneLightsDelegate>("ProbeSetSceneLights");
                _sceneLightsRead=Export<SceneLightsReadDelegate>("ProbeGetSceneLightStats");
                _session = Export<StartDelegate>("ProbeStartWorld")(source,pid,output,vendor,borderless ? 1 : 0);
                if (_session == IntPtr.Zero) throw new InvalidOperationException("Compositor initialization failed");
            }
            catch { Dispose(); throw; }
        }
        private T Export<T>(string name) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(_module,name));
        private T TryExport<T>(string name) where T : Delegate
        {
            IntPtr address;
            try { address = NativeLibrary.GetExport(_module, name); } catch { return null; }
            return address == IntPtr.Zero ? null : Marshal.GetDelegateForFunctionPointer<T>(address);
        }
        internal const int GrabOk = 1, GrabInvalidArgument = 0, GrabNoFrame = -1, GrabBufferTooSmall = -2,
            GrabBusy = -3, GrabTimeout = -4, GrabGpuError = -5, GrabExportUnavailable = -6,
            // C# 侧合成码（不进原生 ABI）：合成器未呈现或世界视口裁剪未建立，
            // 此时原生回读会退化为整窗内容（含标题栏），不允许当作世界帧抓出。
            GrabNoWorldViewport = -7;
        // 与 Compositor.cpp 的 BulletItemCap/RayItemCap 镜像的硬上限；配对能力合同另验。
        internal const int NativeBulletItemLimit = 16384, NativeRayItemLimit = 4096;
        // Dev-only LUT lab：buffer=null 为尺寸查询（返回 GrabBufferTooSmall 并给出宽高）。
        internal int GrabLatestFrame(byte[] buffer, out int width, out int height)
            => GrabFrame(_grab,buffer,out width,out height);
        internal int GrabCompositeFrame(byte[] buffer,out int width,out int height)
            => GrabFrame(_grabComposite,buffer,out width,out height);
        private int GrabFrame(GrabDelegate grab,byte[] buffer,out int width,out int height)
        {
            width = 0; height = 0;
            if (_session == IntPtr.Zero) return GrabNoFrame;
            if (grab == null) return GrabExportUnavailable;
            uint w, h;
            int result = grab(_session, buffer, buffer == null ? 0u : (uint)buffer.Length, out w, out h);
            if (result == GrabOk || result == GrabBufferTooSmall) { width = checked((int)w); height = checked((int)h); }
            return result;
        }
        internal Stats Read()
        {
            var value = new Stats { Size = (uint)Marshal.SizeOf<Stats>() };
            if (_session == IntPtr.Zero || _read(_session,ref value) != 1) throw new InvalidOperationException("Compositor stats unavailable");
            return value;
        }
        internal WorkStats? ReadWork()
        {
            if (_readWork==null || _session==IntPtr.Zero) return null;
            var value=new WorkStats { Size=(uint)Marshal.SizeOf<WorkStats>() };
            return _readWork(_session,ref value)==1 ? value : null;
        }
        internal System.Drawing.Size ReadCaptureSize()
        {
            if(_session==IntPtr.Zero || _captureSize(_session,out int width,out int height,out ulong generation)!=1)
                throw new InvalidOperationException("Capture geometry unavailable");
            CaptureGeneration=generation;
            return new System.Drawing.Size(width,height);
        }
        internal ulong CaptureGeneration {get;private set;}
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
        // lut-set-v1：整块 32^3 RGBA8（131072 字节）上传并启用 LUT 路径；变更时才调用（勿逐帧）。
        // 严格导出：未配套 ABI 5 DLL 在建会话时即拒绝。
        internal void SetLut(byte[] rgba)
        {
            if (rgba==null || rgba.Length!=32768*4 || _lut(_session,rgba)!=1)
                throw new InvalidOperationException("Invalid lighting LUT");
        }
        internal void ClearLut() { if (_session!=IntPtr.Zero) _clearLut(_session); }
        internal void Active(bool active) { if (_session!=IntPtr.Zero) _active(_session,active ? 1 : 0); }
        internal void Mode(int mode) { if (_session != IntPtr.Zero) _mode(_session,mode); }
        internal void Weather(int type,float intensity,int quality,uint seed)
        {
            if (_session == IntPtr.Zero || _weather(_session,type,intensity,quality,seed)!=1)
                throw new InvalidOperationException("Invalid native weather state");
        }
        internal void WeatherCamera(float x,float y,float scale,float groundMin,float groundMax)
        {
            if (_session == IntPtr.Zero || _weatherCamera(_session,x,y,scale,groundMin,groundMax)!=1)
                throw new InvalidOperationException("Invalid native weather camera");
        }
        internal void Atmosphere(int preset,float[] parameters)
        {
            if (_session==IntPtr.Zero || parameters==null || parameters.Length!=12
                || _atmosphere(_session,preset,parameters)!=1)
                throw new InvalidOperationException("Invalid native atmosphere state");
        }
        internal void WeatherStyle(int type,int count,float[] parameters)
        {
            if (_session==IntPtr.Zero || parameters==null || parameters.Length!=16
                || _weatherStyle(_session,type,count,parameters)!=1)
                throw new InvalidOperationException("Invalid native weather style");
        }
        internal void AtmosphereStyle(int family,float[] parameters)
        {
            if (_session==IntPtr.Zero || parameters==null || parameters.Length!=16
                || _atmosphereStyle(_session,family,parameters)!=1)
                throw new InvalidOperationException("Invalid native atmosphere style");
        }
        internal void BulletStyles(BulletVisualCatalog catalog)
        {
            if (_session == IntPtr.Zero || catalog == null) throw new InvalidOperationException("Bullet catalog unavailable");
            float[] values = new float[catalog.Styles.Count * 32];
            for (int i = 0; i < catalog.Styles.Count; i++)
            {
                BulletVisualStyle style = catalog.Styles[i];
                int at = i * 32;
                if(!style.IsSprite) Array.Copy(style.VerticesPx, 0, values, at, 6);
                values[at + 6] = ((style.FillRgb >> 16) & 255) / 255f;
                values[at + 7] = ((style.FillRgb >> 8) & 255) / 255f;
                values[at + 8] = (style.FillRgb & 255) / 255f;
                values[at + 9] = ((style.GlowRgb >> 16) & 255) / 255f;
                values[at + 10] = ((style.GlowRgb >> 8) & 255) / 255f;
                values[at + 11] = (style.GlowRgb & 255) / 255f;
                values[at + 12] = style.GlowX;
                values[at + 13] = style.GlowY;
                values[at + 14] = style.GlowX > 0 || style.GlowY > 0 ? 1 : 0;
                if(style.IsSprite) {
                    CombatFxImage sprite=style.Sprite;values[at+15]=1;
                    values[at+16]=sprite.OffsetX;values[at+17]=sprite.OffsetY;
                    values[at+18]=sprite.Width;values[at+19]=sprite.Height;
                    values[at+20]=sprite.U0;values[at+21]=sprite.V0;values[at+22]=sprite.U1;values[at+23]=sprite.V1;
                }
            }
            if (_bulletStyles(_session, values, catalog.Styles.Count) != 1)
                throw new InvalidOperationException("Native bullet styles rejected");
            if(catalog.AtlasBgraPremultiplied!=null)
                BulletAtlas(catalog.AtlasBgraPremultiplied,catalog.AtlasWidth,catalog.AtlasHeight);
        }
        internal void BulletAtlas(byte[] pixels,int width,int height)
        {
            if(_session==IntPtr.Zero || pixels==null
                || _bulletAtlas(_session,pixels,width,height,pixels.Length)!=1)
                throw new InvalidOperationException("Native bullet atlas rejected");
        }
        internal bool BulletResourcesReady => _session!=IntPtr.Zero && _bulletReady(_session)==1;
        internal void RayFrame(RayVisualDrawFrame frame,float x,float y,float scale) {
            if(_session==IntPtr.Zero || frame==null || frame.Count<0 || frame.Count>NativeRayItemLimit
                || frame.Data.Length<frame.Count*32 || _rayFrame(_session,frame.Data,frame.Count,x,y,scale)!=1)
                throw new InvalidOperationException("Native ray frame rejected");
        }
        internal void ClearRayFrame() { if(_session!=IntPtr.Zero) _rayFrame(_session,null,0,0,0,1); }
        internal void BulletFrame(BulletVisualFrame frame, float cameraX, float cameraY, float cameraScale)
        {
            if (_session == IntPtr.Zero || frame == null) throw new InvalidOperationException("Bullet frame unavailable");
            int count = frame.NativeOwned ? frame.InstanceCount : 0;
            if (count > NativeBulletItemLimit) throw new InvalidOperationException("Native bullet frame rejected");
            float[] values = ArrayPool<float>.Shared.Rent(Math.Max(1, count * 8));
            try
            {
                if(count>0) PackBulletFrame(frame,values);
                if (_bulletFrame(_session, values, count, cameraX, cameraY, cameraScale) != 1)
                    throw new InvalidOperationException("Native bullet frame rejected");
            }
            finally { ArrayPool<float>.Shared.Return(values); }
        }
        internal static void PackBulletFrame(BulletVisualFrame frame,float[] values)
        {
            if(values.Length<frame.InstanceCount*8) throw new ArgumentException("Bullet packing buffer too small",nameof(values));
            frame.ReadSegments(out var first,out var second);
            PackBulletSegment(first,values,0);PackBulletSegment(second,values,first.Length*8);
        }
        private static void PackBulletSegment(ReadOnlySpan<BulletVisualInstance> items,float[] values,int at)
        {
            foreach(ref readonly var item in items) {
                values[at]=item.Style;values[at+1]=item.X;values[at+2]=item.Y;
                values[at+3]=item.Rotation;values[at+4]=item.ScaleX;values[at+5]=item.ScaleY;
                values[at+6]=item.Alpha;values[at+7]=0;at+=8;
            }
        }
        internal void ClearBulletFrame()
        {
            if (_session != IntPtr.Zero && _bulletFrame(_session, Array.Empty<float>(), 0, 0, 0, 1) != 1)
                throw new InvalidOperationException("Native bullet clear rejected");
        }
        internal void CombatFxAtlas(CombatFxCatalog catalog)
        {
            if(catalog==null) throw new ArgumentNullException(nameof(catalog));
            CombatFxAtlas(catalog.PremultipliedBgra,catalog.Width,catalog.Height);
        }
        internal void CombatFxAtlas(byte[] pixels,int width,int height)
        {
            if (_session==IntPtr.Zero || pixels==null
                || _combatFxAtlas(_session,pixels,width,height,pixels.Length)!=1)
                throw new InvalidOperationException("Native effect atlas rejected");
        }
        internal bool CombatFxReady => _session!=IntPtr.Zero && _combatFxReady(_session)==1;
        internal void CombatFxFrame(CombatFxDrawFrame frame,float x,float y,float scale)
        {
            if (_session==IntPtr.Zero || frame==null || frame.Count<0 || frame.Count>512
                || frame.Data.Length<frame.Count*16 || frame.CasingCount<0 || frame.CasingCount>frame.Count
                || frame.LightCount<0 || frame.LightCount>CombatFxEngine.LightLimit
                || (frame.Lights==null ? 0 : frame.Lights.Length)<frame.LightCount*CombatFxEngine.LightStride
                || _combatFxFrame(_session,frame.Data,frame.Count,frame.CasingCount,frame.Lights,frame.LightCount,
                    frame.MaximumLightResponse,x,y,scale)!=1)
                throw new InvalidOperationException("Native decorative frame rejected");
        }
        internal void ClearCombatFxFrame()
        {
            if (_session!=IntPtr.Zero && _combatFxFrame(_session,Array.Empty<float>(),0,0,Array.Empty<float>(),0,0,0,0,1)!=1)
                throw new InvalidOperationException("Native decorative frame clear rejected");
        }
        public void Dispose()
        {
            if (_session != IntPtr.Zero) { _stop(_session); _session=IntPtr.Zero; }
            if (_module != IntPtr.Zero) { NativeLibrary.Free(_module); _module=IntPtr.Zero; }
        }
        internal void SceneLightField(float[] lights,int count,float response)
        {
            if(_session==IntPtr.Zero || count<0 || count>SceneLightCatalog.Limit || lights==null || lights.Length<count*16
                || _sceneLights(_session,lights,count,response)!=1)throw new InvalidOperationException("Native scene light field rejected");
        }
        internal SceneLightsStats ReadSceneLights()
        {
            var stats=new SceneLightsStats {Size=(uint)Marshal.SizeOf<SceneLightsStats>()};
            if(_session==IntPtr.Zero || _sceneLightsRead(_session,ref stats)!=1)throw new InvalidOperationException("Scene light counters unavailable");return stats;
        }
        [StructLayout(LayoutKind.Sequential)]
        internal struct SceneLightsStats {internal uint Size,Count,Width,Height;internal ulong Builds,CacheHits,Updates;}
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SceneLightsDelegate(IntPtr handle,[In] float[] lights,int count,float response);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SceneLightsReadDelegate(IntPtr handle,ref SceneLightsStats stats);
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
        [StructLayout(LayoutKind.Sequential)]
        internal struct WorkStats
        {
            public uint Size, Reserved;
            public ulong Compositions, LightDraws, LightCacheHits, FxUploads;
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
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int WorkReadDelegate(IntPtr handle,ref WorkStats stats);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CaptureSizeDelegate(IntPtr handle,out int width,out int height,out ulong generation);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CropDelegate(IntPtr handle,int x,int y,int width,int height);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ModeDelegate(IntPtr handle,int mode);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int GrabDelegate(IntPtr handle,[In,Out] byte[] buffer,uint bufferSize,out uint width,out uint height);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int LutDelegate(IntPtr handle,[In] byte[] rgba);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int WeatherDelegate(IntPtr handle,int type,float intensity,int quality,uint seed);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int WeatherCameraDelegate(IntPtr handle,float x,float y,float scale,float groundMin,float groundMax);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int AtmosphereDelegate(IntPtr handle,int preset,[In] float[] parameters);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int WeatherStyleDelegate(IntPtr handle,int type,int count,[In] float[] parameters);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int AtmosphereStyleDelegate(IntPtr handle,int family,[In] float[] parameters);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int BulletStylesDelegate(IntPtr handle,[In] float[] styles,int count);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int BulletFrameDelegate(IntPtr handle,[In] float[] items,int count,float cameraX,float cameraY,float cameraScale);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CombatFxAtlasDelegate(IntPtr handle,[In] byte[] pixels,int width,int height,int length);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CombatFxReadyDelegate(IntPtr handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CombatFxFrameDelegate(IntPtr handle,[In] float[] items,int count,int casings,
            [In] float[] lights,int lightCount,float maximumResponse,float cameraX,float cameraY,float cameraScale);
    }
}
