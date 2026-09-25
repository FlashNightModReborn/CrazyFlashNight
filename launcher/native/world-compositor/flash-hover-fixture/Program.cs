using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;

// Disposable real-projector fixture. SendInput/SetCursorPos are explicit injected
// stimuli, not evidence of physical user input or a gameplay/save journey.
internal sealed partial class HoverHost : Form
{
    private readonly string root, evidence;
    private readonly ConcurrentQueue<Sample> samples = new();
    private readonly List<object> assertions = new();
    private readonly object logLock = new();
    private readonly TcpListener listener = new(IPAddress.Loopback,32187);
    private Process flash;
    private IntPtr source, hook;
    private HookProc hookProc;
    private WorldCompositorController controller;
    private NativePointerBridge directBridge;
    private readonly bool direct = Environment.GetEnvironmentVariable("CF7_HOVER_DIRECT_CONTROL")=="1";
    private WorldCompositionSurface surface;
    private string phase="startup";
    private long stimulusId, phaseMark=Stopwatch.GetTimestamp();
    private int hookDropped;
    private readonly ConcurrentQueue<object> hookObservations=new();
    private Process externalProbe;
    private static readonly FieldInfo EpochField=typeof(WorldCompositionSurface).GetField("_inputEpoch",BindingFlags.NonPublic|BindingFlags.Instance);
    private static readonly FieldInfo SequenceField=typeof(WorldCompositionSurface).GetField("_sequence",BindingFlags.NonPublic|BindingFlags.Instance);
    private static readonly string[] PoisonCounters={"pressCommits","releaseCommits","outsideCommits","dragCommits","keyCommits","deferredCommits","globalDown","globalUp"};
    private static long Value(Sample sample,string key){using var j=JsonDocument.Parse(sample.Raw);return j.RootElement.GetProperty(key).GetInt64();}
    private long Mark(string label){phase=label;phaseMark=Stopwatch.GetTimestamp();Log("MARK "+JsonSerializer.Serialize(new{label,qpc=phaseMark,as2Seq=samples.IsEmpty?0:Value(samples.Last(),"seq")}));return phaseMark;}
    private void FlushHookObservations(){while(hookObservations.TryDequeue(out var item))Log("LL "+JsonSerializer.Serialize(item));}
    private int failures;
    internal int Result=2;
    private record Sample(long Tick,string Phase,string Event,string Target,double X,double Y,bool HoverA,bool HoverB,string Raw);
    [STAThread] private static int Main(string[] args)
    {
        if(args.Length==1 && args[0]=="--external") {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.Run(new Form{Text="CF7 separate-process focus target",StartPosition=FormStartPosition.Manual,Location=new Point(1250,120),ClientSize=new Size(270,180),TopMost=true});return 0;
        }
        if(args.Length!=2)throw new ArgumentException("FlashHoverHost <repo> <evidence>");
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        using var form=new HoverHost(Path.GetFullPath(args[0]),Path.GetFullPath(args[1]));
        Application.Run(form);return form.Result;
    }
    private HoverHost(string projectRoot,string output)
    {
        root=projectRoot;evidence=output;Directory.CreateDirectory(evidence);
        Text="CF7 disposable Flash hover fixture";StartPosition=FormStartPosition.Manual;
        Location=new Point(100,90);ClientSize=new Size(960,540);BackColor=Color.Magenta;TopMost=true;
        LogManager.SetSink(Log);
        Shown+=async(_,__)=>await Run();
    }
    private void Log(string message)
    {
        lock(logLock)File.AppendAllText(Path.Combine(evidence,"host.log"),DateTime.UtcNow.ToString("O")+" "+message+Environment.NewLine);
        Console.WriteLine(message);
    }
    private void Check(bool okay,string name,object detail)
    {
        assertions.Add(new {name,okay,detail,phase,startQpc=phaseMark,endQpc=Stopwatch.GetTimestamp(),lastAs2Seq=samples.IsEmpty?0:Value(samples.Last(),"seq")});if(!okay)failures++;
        Log("ASSERT "+(okay?"PASS ":"FAIL ")+name+" "+JsonSerializer.Serialize(detail));
    }
    private async Task ReadProbe()
    {
        try {
            using var client=await listener.AcceptTcpClientAsync();
            using var stream=client.GetStream();probeStream=stream;var buffer=new byte[4096];var pending=new List<byte>();
            int count;
            while((count=await stream.ReadAsync(buffer))>0) {
                for(int i=0;i<count;i++) {
                    if(buffer[i]!=0){if(pending.Count>=65536)throw new InvalidDataException("oversized probe record");pending.Add(buffer[i]);continue;}
                    string raw=Encoding.UTF8.GetString(pending.ToArray());pending.Clear();
                    using var json=JsonDocument.Parse(raw);var j=json.RootElement;
                    var sample=new Sample(Stopwatch.GetTimestamp(),phase,j.GetProperty("event").GetString(),j.GetProperty("target").GetString(),
                        j.GetProperty("x").GetDouble(),j.GetProperty("y").GetDouble(),j.GetProperty("hoverA").GetBoolean(),j.GetProperty("hoverB").GetBoolean(),raw);
                    samples.Enqueue(sample);
                    if(cooperative) ObserveCooperative(sample);
                    FlushHookObservations();
                    lock(logLock)File.AppendAllText(Path.Combine(evidence,"as2.jsonl"),JsonSerializer.Serialize(sample)+Environment.NewLine);
                }
            }
        } catch(Exception e) {Log("probe_receiver "+e.Message);}
        finally {if(cooperative){mOpen=false;mBroken=true;}}
    }
    private async Task WaitFor(Func<bool> condition,string name,int timeout=12000)
    {
        var watch=Stopwatch.StartNew();while(!condition() && watch.ElapsedMilliseconds<timeout)await Task.Delay(25);
        if(!condition())throw new InvalidOperationException("Timeout: "+name);
    }
    private async Task Run()
    {
        try {
            listener.Start();_ = ReadProbe();
            var movie=Path.Combine(root,"launcher/native/world-compositor/flash-hover-fixture/"+(cooperative?"CooperativeProbe.swf":"HoverProbe.swf"));
            var start=new ProcessStartInfo(Path.Combine(root,"Adobe Flash Player 20.exe")){UseShellExecute=false};start.ArgumentList.Add(movie);
            flash=Process.Start(start);
            await WaitFor(()=>{flash.Refresh();return flash.MainWindowHandle!=IntPtr.Zero;},"projector HWND");
            source=flash.MainWindowHandle;
            SetMenu(source,IntPtr.Zero);SetWindowLongPtr(source,-16,new IntPtr(0x50000000));SetParent(source,Handle);
            ResizeSource(1);
            await WaitFor(()=>samples.Any(x=>x.Event=="ready"),"actual AS2 ready");
            var identityFiles=new[]{movie,Path.Combine(root,"Adobe Flash Player 20.exe"),Path.Combine(AppContext.BaseDirectory,"FlashHoverHost.dll"),Path.Combine(AppContext.BaseDirectory,"FlashInputBridge.dll"),Path.Combine(AppContext.BaseDirectory,"FlashInputBroker.exe"),Path.Combine(AppContext.BaseDirectory,"FlashCompositorNative.dll")}.ToList();
            if(cooperative)identityFiles.Add(Path.Combine(Path.GetDirectoryName(movie),"CooperativeChild.swf"));
            File.WriteAllText(Path.Combine(evidence,"identity.json"),JsonSerializer.Serialize(new {pid=flash.Id,source=source.ToInt64(),movie,cooperative,
                artifacts=identityFiles.ToDictionary(p=>p,p=>Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(p)))),
                movieSha256=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(movie))),directNativeControl=direct,stimulus="injected SendInput; production LL route or explicit direct-native control"}));
            Log("SETUP_RAW_FLASH_READY owner="+Handle+" source="+source);
            if(Environment.GetEnvironmentVariable("CF7_HOVER_SETUP_WAIT")=="1") await WaitFor(()=>File.Exists(Path.Combine(evidence,"continue.flag")),"setup continuation",120000);
            if(GetForegroundWindow()!=Handle && GetForegroundWindow()!=source)throw new InvalidOperationException("Fixture setup is not foreground; no test stimulus may run; actual="+GetForegroundWindow()+" expected="+Handle+" source="+source);
            if(direct) {directBridge=await NativePointerBridge.Start(source,Handle);} else {
            controller=new WorldCompositorController(this,this,()=>source,()=>true,Log,root,()=>true,ResizeSource,FocusFlash);
            controller.Adopt(new WorldLightingFrame{Sequence=1,Scene=1,Ready=true,Light=7,Mode="光照",Parameters=new double[]{1,1,1,1,0,0,0,0}});
            controller.ApplyRenderSelection(new RenderSelection(3,.67,"LOW"),0);
            await WaitFor(()=>controller.SchedulingAllowed,"capture ready",18000);
            surface=(WorldCompositionSurface)typeof(WorldCompositorController).GetField("_surface",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller);
            }
            Log("fixture ownerVisible="+Visible+" surfaceVisible="+(surface?.Visible??false)+" owner="+Handle+" P="+(surface?.Handle??IntPtr.Zero)+" direct="+direct);

            hookProc=Hook;hook=SetWindowsHookEx(14,hookProc,GetModuleHandle(null),0);
            if(hook==IntPtr.Zero)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            if(cooperative) {
                await RunCooperative();
                Check(hookDropped==0,"ll_observation_no_loss",hookDropped);
                Result=failures==0?0:1;return;
            }
            SetForegroundWindow(Handle); SetCursorPos(Left+120,Top+15); Edge(2); await Task.Delay(80); Edge(4);
            FocusFlash();await Task.Delay(300);
            // One click primes normal input ownership. No activation before each later hover/click.
            MovePointer(170,150);await Task.Delay(150);Edge(2);await Task.Delay(80);Edge(4);await Task.Delay(300);
            if(direct) {await Hover("native-stationary",false);await Hover("native-motion",true);await Clicks("native-clicks");}
            else if(Environment.GetEnvironmentVariable("CF7_HOVER_BOUNDARIES_ONLY")!="1") {
            await Hover("stationary-67",false);
            await Hover("motion-67",true);
            await Clicks("clicks-67");
            controller.ApplyRenderSelection(new RenderSelection(0,1,"HIGH"),0);
            await WaitFor(()=>controller.SchedulingAllowed,"100 percent settled");await Task.Delay(300);
            await Hover("stationary-100",false);
            await Hover("motion-100",true);
            await Clicks("clicks-100");
            } else {
                controller.ApplyRenderSelection(new RenderSelection(0,1,"HIGH"),0);
                await WaitFor(()=>controller.SchedulingAllowed,"boundary scale settled");await Task.Delay(300);
            }
            await Boundaries();
            Check(samples.Any(x=>x.Event=="press") && samples.Any(x=>x.Event=="release"),"actual_as2_callbacks",samples.Count);
            Check(hookDropped==0,"ll_observation_no_loss",hookDropped);
            Result=failures==0?0:1;
        } catch(Exception e){Log("FATAL "+e);Result=2;}
        finally {
            mOpen=false;mAwaitReady=false;mBroken=true;
            if(hook!=IntPtr.Zero)UnhookWindowsHookEx(hook);
            controller?.Dispose();directBridge?.Dispose();listener.Stop();
            if(externalProbe!=null && !externalProbe.HasExited){externalProbe.CloseMainWindow();if(!externalProbe.WaitForExit(3000))externalProbe.Kill();}
            externalProbe?.Dispose();FlushHookObservations();
            if(flash!=null && !flash.HasExited){flash.CloseMainWindow();if(!flash.WaitForExit(3000))flash.Kill();}
            File.WriteAllText(Path.Combine(evidence,"summary.json"),JsonSerializer.Serialize(new {result=Result,failures,assertions},new JsonSerializerOptions{WriteIndented=true}));
            LogManager.SetSink(_=>{});Close();
        }
    }
    private void ResizeSource(double scale)=>SetWindowPos(source,IntPtr.Zero,0,0,(int)(ClientSize.Width*scale),(int)(ClientSize.Height*scale),0x34);
    private void FocusFlash()
    {
        uint other=GetWindowThreadProcessId(source,out _),current=GetCurrentThreadId();
        bool attached=other==current || AttachThreadInput(current,other,true);
        if(attached){SetFocus(source);if(other!=current)AttachThreadInput(current,other,false);}
    }
    private void MovePointer(double x,double y)
    {
        Control viewport=surface??(Control)this;
        Point p=viewport.PointToScreen(new Point((int)(x/640*viewport.ClientSize.Width),(int)(y/360*viewport.ClientSize.Height)));
        long id=++stimulusId;
        Log("STIMULUS "+JsonSerializer.Serialize(new{id,phase,qpc=Stopwatch.GetTimestamp(),kind="move",x,y,foreground=GetForegroundWindow().ToInt64()}));
        var desktop=SystemInformation.VirtualScreen;
        var input=new INPUT{type=0,mouse=new MOUSEINPUT{dx=(int)Math.Round((p.X-desktop.Left)*65535.0/(desktop.Width-1)),dy=(int)Math.Round((p.Y-desktop.Top)*65535.0/(desktop.Height-1)),flags=0xC001,extra=new UIntPtr((ulong)id)}};
        if(SendInput(1,new[]{input},Marshal.SizeOf<INPUT>())!=1)throw new InvalidOperationException("Move SendInput failed");
    }
    private void Edge(uint flags)
    {
        long id=++stimulusId;
        Log("STIMULUS "+JsonSerializer.Serialize(new{id,phase,qpc=Stopwatch.GetTimestamp(),kind=flags==2?"down":"up",foreground=GetForegroundWindow().ToInt64()}));
        var input=new INPUT{type=0,mouse=new MOUSEINPUT{flags=flags,extra=new UIntPtr((ulong)id)}};
        if(SendInput(1,new[]{input},Marshal.SizeOf<INPUT>())!=1)throw new InvalidOperationException("SendInput failed");
    }
    private async Task Hover(string name,bool moving)
    {
        MovePointer(160,150);await Task.Delay(300);long mark=Mark(name);
        for(int i=0;i<60;i++){if(moving)MovePointer(155+i%10,150);await Task.Delay(40);}
        var observed=samples.Where(x=>x.Tick>=mark && x.Phase==name).ToArray();
        Check(observed.Count(x=>x.Event=="sample")>=10,name+"_sampling",observed.Length);
        Check(observed.Where(x=>x.Event=="sample").All(x=>Math.Abs(x.X-160)<14 && Math.Abs(x.Y-150)<5),name+"_coordinates",new{minX=observed.Min(x=>x.X),maxX=observed.Max(x=>x.X)});
        Check(observed.All(x=>x.Event!="out" && x.Event!="releaseOutside") && observed.Where(x=>x.Event=="sample").All(x=>x.HoverA),
            name+"_stable_hover",new{outs=observed.Count(x=>x.Event=="out"),notHover=observed.Count(x=>x.Event=="sample" && !x.HoverA),minX=observed.Min(x=>x.X),maxX=observed.Max(x=>x.X)});
        using var bitmap=new Bitmap(ClientSize.Width,ClientSize.Height);using(var g=Graphics.FromImage(bitmap))g.CopyFromScreen(PointToScreen(Point.Empty),Point.Empty,ClientSize);
        bitmap.Save(Path.Combine(evidence,name+".png"));
    }
    private async Task Clicks(string name)
    {
        long mark=Mark(name);
        for(int i=0;i<10;i++){MovePointer(i%2==0?160:430,150);await Task.Delay(120);Edge(2);await Task.Delay(90);Edge(4);await Task.Delay(130);}
        await Task.Delay(200);var observed=samples.Where(x=>x.Tick>=mark && x.Phase==name).ToArray();
        Check(observed.Count(x=>x.Event=="press")==10 && observed.Count(x=>x.Event=="release")==10,name+"_exact_callbacks",
            new{press=observed.Count(x=>x.Event=="press"),release=observed.Count(x=>x.Event=="release"),outside=observed.Count(x=>x.Event=="releaseOutside")});
        var edges=observed.Where(x=>x.Event=="press" || x.Event=="release" || x.Event=="releaseOutside").ToArray();
        bool exact=edges.Length==20;
        for(int i=0;exact && i<10;i++){string target=i%2==0?"A":"B";exact &= edges[i*2].Event=="press" && edges[i*2+1].Event=="release" && edges[i*2].Target==target && edges[i*2+1].Target==target && Value(edges[i*2],"pressId")==Value(edges[i*2+1],"pressId");}
        Check(exact,name+"_target_order_and_press_identity",edges.Select(x=>new{x.Event,x.Target,press=Value(x,"pressId")}).ToArray());
        Check(observed.Count(x=>x.Event=="deferredCommit")==10,name+"_deferred_positive_control",observed.Count(x=>x.Event=="deferredCommit"));
    }
    private async Task Boundaries()
    {
        phase="leave-reenter";MovePointer(160,150);await Task.Delay(250);long mark=Stopwatch.GetTimestamp();
        MovePointer(280,270);await Task.Delay(250);
        var last=samples.Last();
        Check(!last.HoverA && !last.HoverB && samples.Any(x=>x.Tick>=mark && x.Event=="out" && x.Target=="A"),"real_mapped_leave",last);
        MovePointer(160,150);await Task.Delay(250);Check(samples.Last().HoverA,"real_reenter",samples.Last());
        phase="presentation-leave";MovePointer(-60,150);await Task.Delay(300);last=samples.Last();
        Check(!last.HoverA && !last.HoverB,"leave_presentation_clears_hover",last);
        Check(last.X<0 || last.Y<0,"leave_presentation_has_outside_coordinates",last);
        MovePointer(160,150);await Task.Delay(250);Check(samples.Last().HoverA,"presentation_reenter",samples.Last());
        phase="drag-outside";mark=Stopwatch.GetTimestamp();Edge(2);await Task.Delay(100);MovePointer(280,270);await Task.Delay(200);Edge(4);await Task.Delay(250);
        var drag=samples.Where(x=>x.Tick>=mark).ToArray();
        Check(drag.Count(x=>x.Event=="press")==1 && drag.Count(x=>x.Event=="releaseOutside")==1 && !drag.Any(x=>x.Event=="release"),"drag_outside_does_not_click",drag.Select(x=>x.Event).ToArray());
        Mark("external-focus");MovePointer(160,150);await Task.Delay(300);
        var beforeDown=samples.Last();mark=Stopwatch.GetTimestamp();Edge(2);
        await WaitFor(()=>samples.Any(x=>x.Tick>=mark && x.Event=="press" && x.Target=="A"),"old press observed",2500);
        await Task.Delay(100);var atCancel=samples.Last();long cancelMark=Stopwatch.GetTimestamp();
        Log("CANCEL_MARK "+JsonSerializer.Serialize(new{qpc=cancelMark,as2Seq=Value(atCancel,"seq"),pressId=Value(atCancel,"pressId")}));
        externalProbe=Process.Start(new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory,"FlashHoverHost.exe"),"--external"){UseShellExecute=false});
        await WaitFor(()=>{externalProbe.Refresh();return externalProbe.MainWindowHandle!=IntPtr.Zero;},"external process window");
        SetForegroundWindow(externalProbe.MainWindowHandle);await Task.Delay(300);
        Check(GetForegroundWindow()==externalProbe.MainWindowHandle,"external_foreground",new{hwnd=GetForegroundWindow().ToInt64(),pid=externalProbe.Id});
        // Release over the external window; keep it open during the subsequent return.
        MovePointer(900,120);await Task.Delay(150);Edge(4);await Task.Delay(300);
        Check(!samples.Any(x=>x.Tick>=cancelMark && x.Event=="release"),"focus_loss_no_button_commit",samples.Where(x=>x.Tick>=cancelMark).Select(x=>x.Event).ToArray());
        var afterCancel=samples.Last();
        Check(PoisonCounters.All(k=>Value(afterCancel,k)==Value(atCancel,k)),"cancel_all_poison_counters_unchanged",PoisonCounters.ToDictionary(k=>k,k=>Value(afterCancel,k)-Value(atCancel,k)));
        for(int i=0;i<10;i++){await Task.Delay(40);Check(GetForegroundWindow()==externalProbe.MainWindowHandle,"external_foreground_sample_"+i,GetForegroundWindow().ToInt64());}
        Check(GetForegroundWindow()==externalProbe.MainWindowHandle,"no_background_focus_reclaim",GetForegroundWindow().ToInt64());
        Mark("return-fresh");Activate();FocusFlash();await Task.Delay(300);
        MovePointer(280,270);await Task.Delay(200);MovePointer(160,150);await Task.Delay(250);mark=Stopwatch.GetTimestamp();
        Edge(2);await Task.Delay(100);Edge(4);await Task.Delay(300);
        var returned=samples.Where(x=>x.Tick>=mark && (x.Event=="press" || x.Event=="release" || x.Event=="releaseOutside")).ToArray();
        Check(returned.Count(x=>x.Event=="press")==1 && returned.Count(x=>x.Event=="release")==1,"fresh_click_after_focus_return",returned.Select(x=>x.Event).ToArray());
        Check(returned.Length==2 && returned[0].Event=="press" && returned[1].Event=="release" && returned.All(x=>x.Target=="A") && Value(returned[0],"pressId")==Value(returned[1],"pressId") && Value(returned[0],"pressId")>Value(atCancel,"pressId"),"fresh_click_has_new_press_identity",returned.Select(x=>new{x.Event,x.Target,press=Value(x,"pressId")}).ToArray());
        phase="owner-move";Location=new Point(180,140);await Task.Delay(500);await Hover("hover-after-move",true);
        phase="owner-resize";ClientSize=new Size(1120,630);ResizeSource(1);await Task.Delay(700);await Hover("hover-after-resize",true);
        phase="minimize-restore";WindowState=FormWindowState.Minimized;await Task.Delay(250);WindowState=FormWindowState.Normal;Activate();FocusFlash();await Task.Delay(700);
        MovePointer(280,270);await Task.Delay(150);MovePointer(160,150);Edge(2);await Task.Delay(100);Edge(4);await Task.Delay(200);
        await Hover("hover-after-restore",true);
    }
    private IntPtr Hook(int code,IntPtr wp,IntPtr lp)
    {
        if(code>=0){
            var data=Marshal.PtrToStructure<MouseHook>(lp);
            bool consumed=cooperative ? RouteCooperative(data,wp.ToInt32()) : controller!=null && controller.RouteCapturedPointer(data.point.X,data.point.Y,wp.ToInt32(),data.data);
            if(wp.ToInt32()!=0x200) {
                if(hookObservations.Count<1024)hookObservations.Enqueue(new{qpc=Stopwatch.GetTimestamp(),message=wp.ToInt32(),stimulusId=data.extra.ToUInt64(),flags=data.flags,consumed,foreground=GetForegroundWindow().ToInt64(),epoch=surface==null?0u:(uint)EpochField.GetValue(surface),sequence=surface==null?0L:(long)SequenceField.GetValue(surface)});
                else hookDropped++;
            }
            if(consumed)return new IntPtr(1);
        }
        return CallNextHookEx(hook,code,wp,lp);
    }
    private delegate IntPtr HookProc(int code,IntPtr wp,IntPtr lp);
    [StructLayout(LayoutKind.Sequential)] private struct MouseHook{public Point point;public uint data,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] private struct MOUSEINPUT{public int dx,dy;public uint data,flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Sequential)] private struct KEYBDINPUT{public ushort vk,scan;public uint flags,time;public UIntPtr extra;}
    [StructLayout(LayoutKind.Explicit)] private struct INPUT{[FieldOffset(0)]public uint type;[FieldOffset(8)]public MOUSEINPUT mouse;[FieldOffset(8)]public KEYBDINPUT keyboard;}
    [DllImport("user32.dll")]private static extern IntPtr SetParent(IntPtr child,IntPtr parent);
    [DllImport("user32.dll")]private static extern IntPtr SetWindowLongPtr(IntPtr h,int index,IntPtr value);
    [DllImport("user32.dll")]private static extern bool SetMenu(IntPtr h,IntPtr menu);
    [DllImport("user32.dll")]private static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
    [DllImport("user32.dll")]private static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")]private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]private static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")]private static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    [DllImport("kernel32.dll")]private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")]private static extern bool AttachThreadInput(uint a,uint b,bool attach);
    [DllImport("user32.dll")]private static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll",SetLastError=true)]private static extern uint SendInput(uint count,INPUT[] values,int size);
    [DllImport("user32.dll",SetLastError=true)]private static extern IntPtr SetWindowsHookEx(int kind,HookProc fn,IntPtr module,uint thread);
    [DllImport("user32.dll")]private static extern bool UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")]private static extern IntPtr CallNextHookEx(IntPtr h,int code,IntPtr wp,IntPtr lp);
    [DllImport("kernel32.dll")]private static extern IntPtr GetModuleHandle(string name);
}
