using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class SharedWorldGpuFactAttribute : FactAttribute
    {
        public SharedWorldGpuFactAttribute(bool requireDisplayOn=false)
        {
            if (Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE") == null)
                Skip = "Explicit verified candidate required for the owned-window shared presentation GPU fixture.";
            else if(requireDisplayOn && DisplayPowerObservation.ReadSessionState()!=1)
                Skip = "Sustained presentation qualification requires an explicitly on session display; never wake it automatically.";
        }
    }

    public sealed class WorldSharedPresentationGpuTests
    {
        private sealed class Source : Form
        {
            protected override bool ShowWithoutActivation => true;
        }
        private sealed class Output : Form
        {
            protected override bool ShowWithoutActivation => true;
            protected override CreateParams CreateParams
            {
                get { var value = base.CreateParams; value.ExStyle |= 0x80000 | 0x80 | 0x08000000; return value; }
            }
            protected override void OnHandleCreated(EventArgs e)
            {
                base.OnHandleCreated(e);
                Assert.True(SetLayeredWindowAttributes(Handle,0,255,2));
            }
        }

        [SharedWorldGpuFact]
        public void SharedRoot_PreservesWorldPixelsAndClipsShrinkingDamageWithoutFeedback()
            => RunOwnedFixture(false);

        [SharedWorldGpuFact(requireDisplayOn:true)]
        public void SharedRoot_AnimatedTimingRingWrapsWithoutUiPresentationPolling()
            => RunOwnedFixture(true);

        private static void RunOwnedFixture(bool exerciseTiming)
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            int displayState=DisplayPowerObservation.ReadSessionState();
            if(exerciseTiming)Assert.Equal(1,displayState);
            string candidate = Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"));
            string module = Path.Combine(candidate,"runtime",NativeCompositorSession.ModuleName);
            JObject metadata = JObject.Parse(File.ReadAllText(Path.Combine(candidate,"runtime-build-metadata.v2.json")));
            string[] row = File.ReadLines(Path.Combine(candidate,"runtime","cf7-runtime-manifest.tsv"))
                .Select(line=>line.Split('\t')).Single(parts=>parts.Length==4 && parts[0]=="file"
                    && parts[1]=="runtime/"+NativeCompositorSession.ModuleName);
            Assert.Equal(long.Parse(row[2]),new FileInfo(module).Length);
            string moduleHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module)));
            Assert.Equal(row[3],moduleHash,true);
            Assert.Equal(64,metadata.Value<string>("buildIdentityHash").Length);
            Exception failure = null;
            var thread = new Thread(()=>
            {
                try { Run(module,moduleHash,metadata,exerciseTiming,displayState); }
                catch(Exception error) { failure=error; }
            }) { IsBackground=true };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            Assert.True(thread.Join(TimeSpan.FromSeconds(45)),"Owned-window shared GPU fixture timed out.");
            if(failure!=null)ExceptionDispatchInfo.Capture(failure).Throw();
        }

        private static void Run(string module,string moduleHash,JObject metadata,bool exerciseTiming,int displayState)
        {
            var execution=Stopwatch.StartNew();
            IntPtr loaded = NativeLibrary.Load(module);
            try
            {
                using var source = new Source {Text="CF7 shared source fixture",FormBorderStyle=FormBorderStyle.None,
                    ShowInTaskbar=false,TopMost=true,AutoScaleMode=AutoScaleMode.None,StartPosition=FormStartPosition.Manual,
                    Location=new Point(70,70),ClientSize=new Size(192,128),BackColor=Color.FromArgb(30,80,140)};
                using var output = new Output {Text="CF7 shared output fixture",FormBorderStyle=FormBorderStyle.None,
                    ShowInTaskbar=false,TopMost=true,AutoScaleMode=AutoScaleMode.None,StartPosition=FormStartPosition.Manual,
                    Location=new Point(350,70),ClientSize=new Size(192,128),BackColor=Color.Black};
                using var observerWindow = new Form {ShowInTaskbar=false,FormBorderStyle=FormBorderStyle.None,
                    ClientSize=new Size(192,128)};
                source.Show(); output.Show();
                observerWindow.CreateControl();
                Application.DoEvents();
                using var scene = CompositionSceneHost.Create(output.Handle,module);
                IntPtr visual = scene.AcquireVisual(0);
                NativeCompositorSession world;
                try { world = new NativeCompositorSession(module,source.Handle,(uint)Environment.ProcessId,
                    output.Handle,sharedWorldVisual:visual); }
                finally { Marshal.Release(visual); }
                using(world)
                {
                    world.Mode(0);
                    Pump(()=>world.Read().Received>0,scene,"world capture");
                    using var observer = new NativeCompositorSession(module,output.Handle,(uint)Environment.ProcessId,observerWindow.Handle);
                    observer.Mode(0);
                    Pump(()=>observer.Read().Received>0,scene,"output capture");
                    var reference = Grab(world);
                    Console.WriteLine(JsonConvert.SerializeObject(new { phase="fixture_binding",sourceWidth=reference.Width,
                        sourceHeight=reference.Height,outputDpi=output.DeviceDpi,clientWidth=output.ClientSize.Width,
                        modules=Process.GetCurrentProcess().Modules.Cast<ProcessModule>()
                            .Where(value=>value.ModuleName.Equals(NativeCompositorSession.ModuleName,StringComparison.OrdinalIgnoreCase))
                            .Select(value=>value.FileName).ToArray(),sourceB=reference.Pixels[(30*reference.Width+25)*4],
                        sourceG=reference.Pixels[(30*reference.Width+25)*4+1],sourceR=reference.Pixels[(30*reference.Width+25)*4+2] }));
                    Assert.InRange(reference.Pixels[(30*reference.Width+25)*4],138,142);
                    Assert.InRange(reference.Pixels[(30*reference.Width+25)*4+1],78,82);
                    Assert.InRange(reference.Pixels[(30*reference.Width+25)*4+2],28,32);
                    var initial = WaitPixels(observer,scene,frame=>SamePixel(frame,25,30,reference,25,30),"world pixel preservation");
                    using var raster = new WorldRasterPresentation();
                    raster.Faulted += error => throw new InvalidOperationException("Shared raster fixture upload failed.",error);
                    raster.Adopt(scene,new Rectangle(output.PointToScreen(Point.Empty),output.ClientSize),true);
                    const int stride=128, width=24, height=18;
                    byte[] pixels = new byte[stride*height];
                    for(int y=0;y<height;y++)for(int x=0;x<width;x++)
                    {
                        int index=y*stride+x*4;
                        pixels[index]=60; pixels[index+1]=40; pixels[index+2]=230; pixels[index+3]=255;
                    }
                    IntPtr dib=Marshal.AllocHGlobal(pixels.Length);
                    try
                    {
                        Marshal.Copy(pixels,0,dib,pixels.Length);
                        Point position=output.PointToScreen(new Point(20,25));
                        Assert.True(raster.TryPresent(dib,width,height,stride,position));
                        var withDamage=WaitPixels(observer,scene,frame=>IsDamage(frame,25,30),"damage pixels in shared root");
                        var sourceAfterDamage=Grab(world);
                        Assert.True(SamePixel(sourceAfterDamage,25,30,reference,25,30),"Output damage fed back into the source.");
                        Assert.True(raster.TryPresent(dib,8,6,stride,position));
                        WaitPixels(observer,scene,frame=>SamePixel(frame,35,35,reference,35,35),"old raster extent cleared after shrink");
                        raster.Hide();
                        var cleared=WaitPixels(observer,scene,frame=>SamePixel(frame,25,30,reference,25,30),"damage clear");
                        // Pixel observation is a second WGC/Present pipeline. Retire it
                        // before measuring the isolated world's submission progress.
                        observer.Dispose();
                        NativeCompositorSession.TimingStats? timing=world.ReadTiming();
                        if(exerciseTiming)
                        {
                        ulong before=world.Read().Presented;
                        // A static WGC source legitimately sleeps. Change native settings
                        // from a separate producer while the fixture's UI does not pump.
                        var producer = new Thread(() =>
                        {
                            for (int i=0;i<4;i++) { world.Mode(i%2+1); Thread.Sleep(60); }
                        });
                        producer.Start();
                        producer.Join();
                        Assert.True(world.Read().Presented>before+1,"The native worker incorrectly depends on the UI polling timer.");
                        // Exercise a sustained source, like gameplay, for the ring wrap.
                        // Static-only submission waits are recorded by the separate
                        // legacy/shared observation, not treated as a 30fps source.
                        using var sourceTimer=new System.Windows.Forms.Timer {Interval=16};
                        sourceTimer.Tick += (_,_) => source.BackColor=source.BackColor.R==30
                            ? Color.FromArgb(31,80,140) : Color.FromArgb(30,80,140);
                        sourceTimer.Start();
                        var settings=new float[] {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
                        for(int i=0;i<270;i++)
                        {
                            Assert.True(execution.ElapsedMilliseconds<35000,"Sustained timing fixture exceeded its bounded execution budget.");
                            ulong previous=world.Read().Presented;
                            settings[12]=i/1024f;
                            world.Matrix(settings);
                            var pending=Stopwatch.StartNew();
                            while(world.Read().Presented<=previous && pending.ElapsedMilliseconds<500)
                            { Application.DoEvents();Thread.Sleep(2); }
                            var progress=world.Read();
                            if(i%64==0 || progress.Presented<=previous)
                                Console.WriteLine(JsonConvert.SerializeObject(new {phase="timing_ring",iteration=i,
                                    elapsedMs=pending.Elapsed.TotalMilliseconds,progress.Presented,progress.SubmitMs,
                                    progress.PresentMs,progress.State,timing=world.ReadTiming()}));
                            Assert.True(progress.Presented>previous,"Native timing fixture did not advance at iteration "+i
                                +"; state="+progress.State+" message="+progress.Message);
                        }
                        sourceTimer.Stop();
                        Assert.Equal(88,Marshal.SizeOf<NativeCompositorSession.TimingStats>());
                        timing=world.ReadTiming();
                        Assert.True(timing.HasValue,"Candidate presentation timing export is missing.");
                        Assert.Equal(256u,timing.Value.Count);
                        Assert.InRange(timing.Value.IntervalCount,0u,256u);
                        Assert.InRange(timing.Value.FreshCount,0u,256u);
                        Assert.True(timing.Value.FreshCount>0,"Animated source did not reach the native timing window.");
                        Assert.True(timing.Value.Presented>=timing.Value.Count);
                        Assert.True(timing.Value.IntervalP50Ms<=timing.Value.IntervalP95Ms);
                        Assert.True(timing.Value.IntervalP95Ms<=timing.Value.IntervalP99Ms);
                        Assert.True(timing.Value.IntervalP99Ms<=timing.Value.IntervalMaxMs);
                        Assert.True(double.IsFinite(timing.Value.PresentP95Ms) && timing.Value.PresentP95Ms>=0);
                        }
                        Console.WriteLine(JsonConvert.SerializeObject(new {
                            fixture="world-shared-raster-v1",nativeModule=module,nativeModuleSha256=moduleHash,
                            buildIdentityHash=metadata.Value<string>("buildIdentityHash"),
                            payloadClosureHash=metadata.Value<string>("payloadClosureHash"),
                            hostAssembly=typeof(CompositionSceneHost).Assembly.Location,
                            sourceHwnd=source.Handle.ToInt64(),outputHwnd=output.Handle.ToInt64(),
                            sourcePid=Environment.ProcessId,adapter=world.Read().Adapter,
                            initialHash=Convert.ToHexString(SHA256.HashData(initial.Pixels)),
                            damageHash=Convert.ToHexString(SHA256.HashData(withDamage.Pixels)),
                            clearedHash=Convert.ToHexString(SHA256.HashData(cleared.Pixels)),
                            rasterUploads=raster.Uploads,rasterUploadedBytes=raster.UploadedBytes,
                            timing=timing,
                            timingSource=exerciseTiming ? "owned_animated_window" : "owned_static_window",
                            timingRingVerified=exerciseTiming,
                            sessionDisplayState=displayState,
                            sourceFeedback=false,physicalScanoutVerified=false,gameplayExecuted=false
                        }));
                    }
                    finally { Marshal.FreeHGlobal(dib); }
                }
            }
            finally { NativeLibrary.Free(loaded); }
        }

        private readonly record struct Frame(byte[] Pixels,int Width,int Height);

        [SharedWorldGpuFact]
        public void SharedAndLegacy_ObserveStaticSubmissionWait()
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            int displayState=DisplayPowerObservation.ReadSessionState();
            string candidate=Path.GetFullPath(Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE"));
            string module=Path.Combine(candidate,"runtime",NativeCompositorSession.ModuleName);
            string[] binding=File.ReadLines(Path.Combine(candidate,"runtime","cf7-runtime-manifest.tsv"))
                .Select(line=>line.Split('\t')).Single(row=>row.Length==4 && row[0]=="file"
                    && row[1]=="runtime/"+NativeCompositorSession.ModuleName);
            string hash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module)));
            Assert.Equal(binding[3],hash,true);
            Exception failure=null;
            var thread=new Thread(() =>
            {
                try
                {
                    IntPtr loaded=NativeLibrary.Load(module);
                    try
                    {
                        foreach(bool shared in new[] {false,true})
                        {
                            using var source=new Source {FormBorderStyle=FormBorderStyle.None,ShowInTaskbar=false,TopMost=true,
                                AutoScaleMode=AutoScaleMode.None,StartPosition=FormStartPosition.Manual,Location=new Point(70,70),
                                ClientSize=new Size(192,128),BackColor=Color.FromArgb(30,80,140)};
                            using var output=new Output {FormBorderStyle=FormBorderStyle.None,ShowInTaskbar=false,TopMost=true,
                                AutoScaleMode=AutoScaleMode.None,StartPosition=FormStartPosition.Manual,Location=new Point(350,70),
                                ClientSize=new Size(192,128)};
                            source.Show();output.Show();Application.DoEvents();
                            using var scene=shared ? CompositionSceneHost.Create(output.Handle,module) : null;
                            IntPtr visual=scene?.AcquireVisual(0) ?? IntPtr.Zero;
                            NativeCompositorSession world;
                            try { world=new NativeCompositorSession(module,source.Handle,(uint)Environment.ProcessId,
                                output.Handle,sharedWorldVisual:visual); }
                            finally { if(visual!=IntPtr.Zero)Marshal.Release(visual); }
                            using(world)
                            {
                                world.Mode(0);Pump(()=>world.Read().Received>0,scene,"control source capture");
                                var settings=new float[] {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
                                for(int i=0;i<6;i++)
                                {
                                    ulong previous=world.Read().Presented;settings[12]=i/1024f;world.Matrix(settings);
                                    var watch=Stopwatch.StartNew();
                                    while(world.Read().Presented<=previous && watch.ElapsedMilliseconds<2000)
                                    {Application.DoEvents();scene?.Commit();Thread.Sleep(5);}
                                    var stats=world.Read();
                                    Console.WriteLine(JsonConvert.SerializeObject(new {phase="legacy_shared_control",shared,iteration=i,sessionDisplayState=displayState,
                                        elapsedMs=watch.Elapsed.TotalMilliseconds,advanced=stats.Presented>previous,stats.Presented,
                                        stats.PresentMs,stats.SubmitMs,stats.State,stats.Error,timing=world.ReadTiming(),nativeModule=module,nativeSha256=hash}));
                                    Assert.NotEqual(3u,stats.State);
                                }
                            }
                        }
                    }
                    finally {NativeLibrary.Free(loaded);}
                }
                catch(Exception error) {failure=error;}
            }) {IsBackground=true};
            thread.SetApartmentState(ApartmentState.STA);thread.Start();
            Assert.True(thread.Join(TimeSpan.FromSeconds(60)));
            if(failure!=null)ExceptionDispatchInfo.Capture(failure).Throw();
        }
        private static Frame Grab(NativeCompositorSession capture)
        {
            int status=capture.GrabLatestFrame(null,out int width,out int height);
            Assert.Equal(NativeCompositorSession.GrabBufferTooSmall,status);
            byte[] pixels=new byte[checked(width*height*4)];
            Assert.Equal(NativeCompositorSession.GrabOk,capture.GrabLatestFrame(pixels,out width,out height));
            return new Frame(pixels,width,height);
        }
        private static Frame WaitPixels(NativeCompositorSession capture,CompositionSceneHost scene,Func<Frame,bool> predicate,string phase)
        {
            Frame frame=default;
            Pump(()=> { frame=Grab(capture);return predicate(frame); },scene,phase);
            return frame;
        }
        private static void Pump(Func<bool> ready,CompositionSceneHost scene,string phase)
        {
            var watch=Stopwatch.StartNew();
            do
            {
                Application.DoEvents();scene?.Commit();
                if(ready())return;
                Thread.Sleep(20);
            }while(watch.Elapsed<TimeSpan.FromSeconds(6));
            Assert.Fail("Shared GPU fixture did not reach "+phase+".");
        }
        private static bool IsDamage(Frame frame,int x,int y)
        {
            int index=(y*frame.Width+x)*4;
            return frame.Pixels[index+2]>200 && frame.Pixels[index+1]<70 && frame.Pixels[index]<90;
        }
        private static bool SamePixel(Frame left,int lx,int ly,Frame right,int rx,int ry)
        {
            int li=(ly*left.Width+lx)*4,ri=(ry*right.Width+rx)*4;
            for(int c=0;c<3;c++)if(Math.Abs(left.Pixels[li+c]-right.Pixels[ri+c])>2)return false;
            return true;
        }
        [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetLayeredWindowAttributes(IntPtr hwnd,uint key,byte alpha,uint flags);
    }
}
