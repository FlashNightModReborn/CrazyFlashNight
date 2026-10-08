using System;
using System.IO;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class CompositionSceneBindingTests
    {
        [Theory]
        [InlineData("FlashCompositorNative.dll")]
        [InlineData("./FlashCompositorNative.dll")]
        public void RelativeModulePathIsRejectedBeforeNativeLookup(string path)
            => Assert.Throws<ArgumentException>(() => CompositionSceneHost.Create(IntPtr.Zero,path));

        [Fact]
        public void MissingAbsoluteModuleHasNoNameSearchFallback()
        {
            string missing=Path.Combine(Path.GetTempPath(),"cf7-scene-missing-"+Guid.NewGuid().ToString("N"),
                NativeCompositorSession.ModuleName);
            Assert.Throws<DllNotFoundException>(() => CompositionSceneHost.Create(IntPtr.Zero,missing));
        }

        [Fact]
        public void ModuleWithoutSceneExportsIsRejected()
        {
            string module=Path.Combine(Environment.SystemDirectory,"version.dll");
            Assert.Throws<EntryPointNotFoundException>(() => CompositionSceneHost.Create(IntPtr.Zero,module));
        }

        [SharedWorldGpuFact]
        public void ExplicitCandidateBindingKeepsThreadOwnershipAndNeverBorrowsAnotherLoadedModule()
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            string module=Path.Combine(Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE")),
                "runtime",NativeCompositorSession.ModuleName);
            Exception failure=null;
            var thread=new Thread(() =>
            {
                try
                {
                    using var output=new Form {ShowInTaskbar=false};
                    using var scene=CompositionSceneHost.Create(output.Handle,module);
                    Assert.Equal(module,scene.ModulePath);
                    var version=scene.GetRequiredExport<AbiDelegate>("CompositionSceneAbiVersion");
                    Assert.Equal(1,version());
                    var start=scene.GetRequiredExport<StartVisualDelegate>("ProbeStartVisual");
                    var stop=scene.GetRequiredExport<StopDelegate>("ProbeStop");
                    var read=scene.GetRequiredExport<ReadDelegate>("ProbeGetStats");
                    IntPtr visual=scene.AcquireVisual(0);
                    IntPtr capture=IntPtr.Zero;
                    try
                    {
                        // ProbeStartVisual returns an asynchronous session handle;
                        // an invalid source need not be rejected by its constructor.
                        capture=start(IntPtr.Zero,0,output.Handle,visual);
                    }
                    finally
                    {
                        if(capture!=IntPtr.Zero)stop(capture);
                        Marshal.Release(visual);
                    }
                    var stats=new NativeCompositorSession.Stats {Size=(uint)Marshal.SizeOf<NativeCompositorSession.Stats>()};
                    Assert.Equal(0,read(IntPtr.Zero,ref stats));stop(IntPtr.Zero);
                    IntPtr pixels=Marshal.AllocHGlobal(4);
                    try
                    {
                        Marshal.WriteInt32(pixels,unchecked((int)0xFFFFFFFF));
                        scene.UploadHud(pixels,1,1,4,0,0);
                        scene.Snapshot(pixels,1,1,4);
                        scene.Presentation(true,true,16,16);
                        scene.Presentation(false,false,16,16);
                    }
                    finally {Marshal.FreeHGlobal(pixels);}
                    string missing=Path.Combine(Path.GetTempPath(),"cf7-scene-missing-"+Guid.NewGuid().ToString("N"),
                        NativeCompositorSession.ModuleName);
                    Assert.Throws<DllNotFoundException>(() => CompositionSceneHost.Create(output.Handle,missing));
                    Assert.Throws<InvalidOperationException>(() => Task.Run(() => scene.Commit()).GetAwaiter().GetResult());
                    Assert.Throws<InvalidOperationException>(() => Task.Run(() => scene.Dispose()).GetAwaiter().GetResult());
                    scene.Commit();
                    scene.Dispose();
                    scene.Dispose();
                    Assert.Throws<ObjectDisposedException>(() => scene.Commit());
                    Assert.Throws<ObjectDisposedException>(() => scene.GetRequiredExport<AbiDelegate>("CompositionSceneAbiVersion"));
                    Assert.Throws<InvalidOperationException>(() => CompositionSceneHost.Create(IntPtr.Zero,module));
                }
                catch(Exception error) {failure=error;}
            }) {IsBackground=true};
            thread.SetApartmentState(ApartmentState.STA);thread.Start();
            Assert.True(thread.Join(TimeSpan.FromSeconds(15)),"Owned-scene module binding fixture timed out.");
            if(failure!=null)ExceptionDispatchInfo.Capture(failure).Throw();
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int AbiDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr StartVisualDelegate(IntPtr source,uint pid,IntPtr output,IntPtr visual);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void StopDelegate(IntPtr capture);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ReadDelegate(IntPtr capture,ref NativeCompositorSession.Stats stats);
    }
}
