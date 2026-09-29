using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    private const int StartupDeadlineMs=10000;

    // A real child HWND supplies the animated pixels. It deliberately has no
    // game, Flash process, input bridge, socket or save dependency.
    private sealed class StartupChild : Control
    {
        internal int PaintCount {get;private set;}
        internal StartupChild()
        {
            Dock=DockStyle.Fill;
            SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            PaintCount++;
            e.Graphics.Clear(Color.FromArgb(28,40,58));
            using var cells=new SolidBrush(Color.FromArgb(75,105,145));
            for(int y=0;y<Height;y+=64)for(int x=0;x<Width;x+=64)
                if(((x+y)/64)%2==0)e.Graphics.FillRectangle(cells,x,y,64,64);
            using var marker=new SolidBrush(Color.FromArgb(230,70+(PaintCount%100),35));
            e.Graphics.FillRectangle(marker,20+(PaintCount*11)%Math.Max(1,Width-80),Height/2,40,40);
        }
    }

    private sealed class StartupTarget : Form
    {
        internal StartupTarget(Form owner,Rectangle bounds)
        {
            Owner=owner;Text="CF7 startup composed output";
            FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;
            StartPosition=FormStartPosition.Manual;AutoScaleMode=AutoScaleMode.None;
            Bounds=bounds;BackColor=Color.Black;
        }
        protected override bool ShowWithoutActivation=>true;
        protected override CreateParams CreateParams {
            get {var cp=base.CreateParams;cp.ExStyle=(cp.ExStyle|0x08000000|0x80|0x80000)&~(0x40000|0x20);return cp;}
        }
        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            if(!StartupNative.SetLayeredWindowAttributes(Handle,0,255,2))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    private sealed class StartupEvidence : IDisposable
    {
        private readonly StreamWriter _events;
        private readonly Stopwatch _elapsed=Stopwatch.StartNew();
        internal readonly List<object> Phases=new();
        internal StartupEvidence(string output)
        {
            _events=new StreamWriter(Path.Combine(output,"startup-events.jsonl"),false) {AutoFlush=true};
        }
        internal void Write(string phase,string stage,object detail)
        {
            var entry=new {phase,stage,elapsedMs=_elapsed.Elapsed.TotalMilliseconds,qpcMs=StartupNowMs(),detail};
            _events.WriteLine(JsonSerializer.Serialize(entry));
            Console.WriteLine($"startup phase={phase} stage={stage} elapsedMs={_elapsed.Elapsed.TotalMilliseconds:F1}");
        }
        public void Dispose()=>_events.Dispose();
    }

    private sealed class StartupGeometry
    {
        internal Rectangle Crop;
        internal double FenceMs;
        internal Size CaptureSize;
        internal ulong Generation;
        internal bool ViewportHeld;
    }

    private static int RunStartupProbe(string root,string module,string output)
    {
        if(File.Exists(Path.Combine(output,"startup-events.jsonl")) || File.Exists(Path.Combine(output,"startup-probe.json")))
            throw new InvalidOperationException("Startup evidence requires a new output directory");
        using var evidence=new StartupEvidence(output);
        string moduleHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module))).ToLowerInvariant();
        var identity=new {projectRoot=root,nativeDll=module,nativeSha256=moduleHash,
            pid=Environment.ProcessId,coreModule=typeof(NativeCompositorSession).Assembly.Location,
            fixtureModule=typeof(StartupEvidence).Assembly.Location,
            topology="bordered S owner / actual child HWND / owned layered P created hidden; capture=S",
            borderlessPermissionRequested=false,deadlineMs=StartupDeadlineMs,sessions=3,
            boundary="render startup topology only; controlled same-process child, no Flash/input bridge/game/save or standard-entry acceptance"};
        File.WriteAllText(Path.Combine(output,"startup-identity.json"),JsonSerializer.Serialize(identity,new JsonSerializerOptions {WriteIndented=true}));
        using var owner=new Form {Text="CF7 controlled embedded startup source",FormBorderStyle=FormBorderStyle.Sizable,
            StartPosition=FormStartPosition.Manual,AutoScaleMode=AutoScaleMode.None,
            Location=new Point(120,70),ClientSize=new Size(1600,900),ShowInTaskbar=false};
        using var child=new StartupChild();owner.Controls.Add(child);
        using var pulse=new System.Windows.Forms.Timer {Interval=33};
        pulse.Tick+=(_,_)=>child.Invalidate();
        int result=1;string failure=null;bool completed=false;
        owner.FormClosing+=(_,e)=> {if(!completed)e.Cancel=true;};
        owner.Shown+=async (_,_)=>
        {
            try {
                pulse.Start();await Task.Yield();
                Require(StartupNative.GetParent(child.Handle)==owner.Handle,"Controlled source is not an actual child HWND");
                var fx=CombatFxCatalog.Load(root);var bullets=BulletVisualCatalog.Load(root);
                for(int index=1;index<=3;index++)
                    await RunStartupSession(module,owner,child,fx,bullets,evidence,index);
                string finalHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module))).ToLowerInvariant();
                Require(finalHash==moduleHash,"Native DLL bytes changed during startup probe");
                result=0;
            }
            catch(Exception error) {
                failure=error.ToString();File.WriteAllText(Path.Combine(output,"failure.txt"),failure);
                evidence.Write("run","failed",new {error=failure});Console.Error.WriteLine(error);
            }
            finally {
                pulse.Stop();
                File.WriteAllText(Path.Combine(output,"startup-probe.json"),JsonSerializer.Serialize(new {
                    success=result==0,identity,phases=evidence.Phases,failure
                },new JsonSerializerOptions {WriteIndented=true}));
                completed=true;owner.Close();
            }
        };
        Application.Run(owner);return result;
    }

    private static async Task RunStartupSession(string module,Form owner,StartupChild child,
        CombatFxCatalog fx,BulletVisualCatalog bullets,StartupEvidence evidence,int index)
    {
        owner.ClientSize=new Size(1600,900);child.Refresh();StartupNative.GdiFlush();
        using var target=new StartupTarget(owner,child.RectangleToScreen(child.ClientRectangle));
        IntPtr output=target.Handle; // create the layered HWND without showing P
        Require(!target.Visible && !StartupNative.IsWindowVisible(output),"P was visible before first capture");
        string prefix="session-"+index;
        evidence.Write(prefix,"handles",new {sourceOwner=$"0x{owner.Handle.ToInt64():X}",child=$"0x{child.Handle.ToInt64():X}",
            output=$"0x{output.ToInt64():X}",sourcePid=Environment.ProcessId,ownerVisible=owner.Visible,targetVisible=target.Visible});
        double started=StartupNowMs();
        var geometry=new StartupGeometry {FenceMs=started};
        var session=new NativeCompositorSession(module,owner.Handle,(uint)Environment.ProcessId,output);
        try {
            try {
                // Production queues authored resources before capture readiness.
                // Do not wait for shader-ready, generation 1, or Presented here:
                // that would remove slow native initialization from the deadline.
                session.CombatFxAtlas(fx);session.BulletStyles(bullets);session.Mode(0);
                await WaitStartupReady(prefix+"/initial",session,owner,child,target,geometry,evidence,started,0,0,0);

                session.Active(false);target.Hide();
                evidence.Write(prefix+"/suspend","inactive_requested",StartupSnapshot(session,owner,child,target,geometry));
                await WaitStartupInactive(session,child);
                var paused=session.Read();session.ReadCaptureSize();ulong previousGeneration=session.CaptureGeneration;
                Require(!target.Visible && !StartupNative.IsWindowVisible(output),"P remained visible while inactive");
                evidence.Write(prefix+"/suspend","counters_stopped",StartupSnapshot(session,owner,child,target,geometry));
                started=StartupNowMs();geometry.FenceMs=started;session.Active(true);
                await WaitStartupReady(prefix+"/resume",session,owner,child,target,geometry,evidence,started,
                    paused.Received,paused.Presented,previousGeneration);

                var beforeResize=session.Read();
                session.HoldViewport();geometry.ViewportHeld=true;
                owner.ClientSize=new Size(1280,720);child.Refresh();StartupNative.GdiFlush();
                // A controlled child paint supplies this fixture's repaint fence.
                // It does not claim the production Flash input-bridge WM_PAINT ACK.
                started=StartupNowMs();geometry.FenceMs=started;
                evidence.Write(prefix+"/resize","viewport_held_after_source_paint",StartupSnapshot(session,owner,child,target,geometry));
                await WaitStartupReady(prefix+"/resize",session,owner,child,target,geometry,evidence,started,
                    beforeResize.Received,beforeResize.Presented,0,targetMustBeHidden:false);
            }
            finally {evidence.Write(prefix,"before_dispose",StartupSnapshot(session,owner,child,target,geometry));}
        }
        finally {
            double disposalStarted=StartupNowMs();session.Dispose();
            evidence.Write(prefix,"disposed",new {disposalElapsedMs=StartupNowMs()-disposalStarted,targetVisible=target.Visible});
        }
        target.Hide();
    }

    private static async Task WaitStartupInactive(NativeCompositorSession session,StartupChild child)
    {
        var watch=Stopwatch.StartNew();var last=session.Read();int stable=0,paints=child.PaintCount;
        while(watch.ElapsedMilliseconds<2000) {
            await Task.Delay(100);var now=session.Read();
            Require(now.State<2 && now.Error>=0,"Native failure while suspending: "+now.Message);
            stable=now.Received==last.Received && now.Presented==last.Presented ? stable+1 : 0;
            if(stable>=3 && child.PaintCount>paints)return;
            last=now;
        }
        throw new TimeoutException("Active(false) did not stop presentation while the controlled source kept repainting");
    }

    private static async Task WaitStartupReady(string phase,NativeCompositorSession session,Form owner,StartupChild child,
        StartupTarget target,StartupGeometry geometry,StartupEvidence evidence,double started,
        ulong beforeReceived,ulong beforePresented,ulong beforeGeneration,bool targetMustBeHidden=true)
    {
        ulong loggedGeneration=ulong.MaxValue;uint loggedState=uint.MaxValue;double lastSample=0;
        evidence.Write(phase,"begin",new {beforeReceived,beforePresented,beforeGeneration,startedMs=started,
            targetVisible=target.Visible,deadlineMs=StartupDeadlineMs});
        while(true) {
            Require(!targetMustBeHidden || (!target.Visible && !StartupNative.IsWindowVisible(target.Handle)),
                phase+": P became visible before fresh-frame readiness");
            var stats=session.Read();
            geometry.CaptureSize=session.ReadCaptureSize();geometry.Generation=session.CaptureGeneration;
            Require(stats.State<2 && stats.Error>=0,"Native startup failure: "+stats.Message+" hr="+stats.Error);
            bool synchronized=SynchronizeStartup(session,owner,child,target,geometry,evidence,phase);
            double now=StartupNowMs();
            if(loggedGeneration!=geometry.Generation || loggedState!=stats.State || now-lastSample>=1000) {
                evidence.Write(phase,"sample",StartupSnapshot(session,owner,child,target,geometry));
                loggedGeneration=geometry.Generation;loggedState=stats.State;lastSample=now;
            }
            bool ready=synchronized && stats.Received>beforeReceived && stats.Presented>beforePresented
                && stats.Width==geometry.Crop.Width && stats.Height==geometry.Crop.Height
                && stats.LastFrameQpcMs>=geometry.FenceMs && geometry.Generation>beforeGeneration;
            double deadlineOrigin=Math.Max(started,geometry.FenceMs);
            // Match the production ten-second fresh-frame gate. Valid WGC
            // dimensions alone never reset the deadline or make capture ready.
            if(now-deadlineOrigin>StartupDeadlineMs) {
                var failed=new {phase,success=false,elapsedMs=now-started,waitSinceFenceMs=now-deadlineOrigin,
                    snapshot=StartupSnapshot(session,owner,child,target,geometry)};
                evidence.Phases.Add(failed);evidence.Write(phase,"deadline_failed",failed);
                throw new TimeoutException(phase+": world capture did not produce a fresh matching frame within 10000 ms");
            }
            if(ready) {
                bool hiddenAtReady=!target.Visible && !StartupNative.IsWindowVisible(target.Handle);
                var passed=new {phase,success=true,elapsedMs=now-started,waitSinceFenceMs=now-deadlineOrigin,hiddenAtReady,
                    snapshot=StartupSnapshot(session,owner,child,target,geometry)};
                evidence.Phases.Add(passed);evidence.Write(phase,"fresh_frame_ready",passed);
                if(!target.Visible) {target.Show();evidence.Write(phase,"target_shown",new {target.Visible});}
                return;
            }
            await Task.Delay(40);
        }
    }

    private static bool SynchronizeStartup(NativeCompositorSession session,Form owner,StartupChild child,
        StartupTarget target,StartupGeometry geometry,StartupEvidence evidence,string phase)
    {
        if(StartupNative.DwmGetWindowAttribute(owner.Handle,9,out StartupNative.Rect extended,Marshal.SizeOf<StartupNative.Rect>())!=0
            || !StartupNative.GetWindowRect(owner.Handle,out StartupNative.Rect window)
            || !StartupNative.GetClientRect(child.Handle,out StartupNative.Rect client))
            throw new InvalidOperationException("Cannot resolve controlled source geometry");
        var origin=new Point();
        if(!StartupNative.ClientToScreen(child.Handle,ref origin))throw new InvalidOperationException("Cannot resolve child client origin");
        var source=new Rectangle(origin,client.Rectangle.Size);
        if(!WorldCompositorController.TryResolveCaptureFrame(extended.Rectangle,window.Rectangle,geometry.CaptureSize,out var capture)
            || !WorldCompositorController.TryCalculateCrop(source,capture,out var crop))return false;
        Rectangle bounds=child.RectangleToScreen(child.ClientRectangle);
        if(crop!=geometry.Crop || target.Bounds!=bounds || geometry.ViewportHeld) {
            if(!geometry.ViewportHeld)geometry.FenceMs=StartupNowMs();
            session.Viewport(crop,geometry.FenceMs);geometry.ViewportHeld=false;geometry.Crop=crop;target.Bounds=bounds;
            evidence.Write(phase,"viewport",new {source,capture,extended=extended.Rectangle,window=window.Rectangle,
                wgc=geometry.CaptureSize,crop,bounds,frameFenceMs=geometry.FenceMs,captureGeneration=geometry.Generation});
        }
        return true;
    }

    private static object StartupSnapshot(NativeCompositorSession session,Form owner,StartupChild child,
        StartupTarget target,StartupGeometry geometry)
    {
        var stats=session.Read();var size=session.ReadCaptureSize();
        return new {stats.State,stats.Error,stats.Message,stats.Adapter,stats.Received,stats.Presented,
            readyWidth=stats.Width,readyHeight=stats.Height,stats.LastFrameQpcMs,
            captureWidth=size.Width,captureHeight=size.Height,captureGeneration=session.CaptureGeneration,
            crop=geometry.Crop,frameFenceMs=geometry.FenceMs,
            ownerVisible=owner.Visible,childVisible=child.Visible,targetVisible=target.Visible,child.PaintCount};
    }

    private static double StartupNowMs()=>Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency;

    private static class StartupNative
    {
        [StructLayout(LayoutKind.Sequential)] internal struct Rect {
            internal int Left,Top,Right,Bottom;
            internal Rectangle Rectangle=>System.Drawing.Rectangle.FromLTRB(Left,Top,Right,Bottom);
        }
        [DllImport("user32.dll")] internal static extern IntPtr GetParent(IntPtr hwnd);
        [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll",SetLastError=true)] internal static extern bool SetLayeredWindowAttributes(IntPtr hwnd,uint color,byte alpha,uint flags);
        [DllImport("user32.dll")] internal static extern bool GetWindowRect(IntPtr hwnd,out Rect rect);
        [DllImport("user32.dll")] internal static extern bool GetClientRect(IntPtr hwnd,out Rect rect);
        [DllImport("user32.dll")] internal static extern bool ClientToScreen(IntPtr hwnd,ref Point point);
        [DllImport("dwmapi.dll")] internal static extern int DwmGetWindowAttribute(IntPtr hwnd,int attribute,out Rect value,int size);
        [DllImport("gdi32.dll")] internal static extern bool GdiFlush();
    }
}
