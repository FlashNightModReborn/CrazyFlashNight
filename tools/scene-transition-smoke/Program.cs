using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

// Real isolated HWND/WebView2/DirectComposition probe. No Flash, slots, navigation or game E2E.
internal sealed class Probe : Form
{
    private readonly string root, output, candidate;
    private object surface;
    private object controller;
    private Type surfaceType;
    private bool reportPixelsVerified;
    private readonly List<JObject> messages=new();
    private readonly List<object> checks=new();
    private readonly Color source=Color.FromArgb(255,22,113,171);
    private Process peer;
    private readonly TextBox inputTarget=new() { Location=new Point(10,530),Width=160 };
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd,uint command);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int width,int height,uint flags);
    [STAThread] private static void Main(string[] args) {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);Application.EnableVisualStyles();
        if(args.Length==3&&args[0]=="--foreground-peer") {
            Application.Run(new ForegroundPeer(args[1],new IntPtr(long.Parse(args[2]))));return;
        }
        if(args.Length!=3){Environment.ExitCode=2;return;}
        Application.Run(new Probe(Path.GetFullPath(args[0]),Path.GetFullPath(args[1]),Path.GetFullPath(args[2])));
    }
    private Probe(string root,string output,string candidate) {
        this.root=root;this.output=output;this.candidate=candidate;
        Directory.CreateDirectory(output);
        ClientSize=new Size(1024,576);StartPosition=FormStartPosition.Manual;Location=new Point(60,70);
        Text="U12 isolated composition probe";BackColor=source;ShowInTaskbar=false;
        Controls.Add(inputTarget);
        Shown+=async(_,_)=>await Run();
    }
    private object Call(string name,params object[] args)=>surfaceType.GetMethod(name,BindingFlags.Instance|BindingFlags.NonPublic).Invoke(surface,args);
    private async Task Wait(Func<bool> done,string label) {
        var clock=Stopwatch.StartNew();while(!done()&&clock.ElapsedMilliseconds<20000)await Task.Delay(30);
        if(!done()) {
            await RecordProjectionDiagnostic(label);
            throw new Exception("probe timed out: "+label);
        }
        checks.Add(new{label,passed=true});
    }
    private async Task RecordProjectionDiagnostic(string label) {
        if(controller==null)return;
        try {
            var active=(Form)controller.GetType().GetField("_surface",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller);
            var endpoint=surfaceType.GetField("_web",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(active);
            var core=endpoint?.GetType().GetProperty("CoreWebView2").GetValue(endpoint);
            string dom=core==null?null:await (Task<string>)core.GetType().GetMethod("ExecuteScriptAsync").Invoke(core,new object[]{
                "JSON.stringify({url:location.href,rootHidden:document.getElementById('transition').hidden,reportHidden:document.getElementById('transition-report').hidden,text:document.body.innerText,errors:window.fixtureErrors||[]})"});
            File.WriteAllText(Path.Combine(output,"projection-diagnostic.json"),JsonConvert.SerializeObject(new {
                label,foreground=GetForegroundWindow().ToInt64(),owner=Handle.ToInt64(),surface=active.Handle.ToInt64(),surfaceVisible=active.Visible,
                latest=controller.GetType().GetField("_latest",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller),dom
            },Formatting.Indented));
        } catch(Exception e) { File.WriteAllText(Path.Combine(output,"projection-diagnostic-error.txt"),e.ToString()); }
    }
    private void Message(JObject p)=>messages.Add((JObject)p.DeepClone());
    private JObject Snapshot(string phase,int revision)=>new JObject {
        ["type"]="scene_transition",["version"]=1,["requestId"]="tr:1",["revision"]=revision,
        ["phase"]=phase,["imageId"]="Andy",["tip"]="合成窗口自动检查",["targetScene"]=2,
        ["generation"]=0,["connected"]=true,["actionPending"]=false,["revealAllowed"]=phase=="reveal" };
    private new Bitmap Capture(string file) {
        var rect=RectangleToScreen(ClientRectangle);var pixels=new Bitmap(rect.Width,rect.Height,PixelFormat.Format32bppArgb);
        using(var g=Graphics.FromImage(pixels))g.CopyFromScreen(rect.Location,Point.Empty,rect.Size);
        pixels.Save(Path.Combine(output,file),ImageFormat.Png);return pixels;
    }
    private static int Difference(Color a,Color b)=>Math.Abs(a.R-b.R)+Math.Abs(a.G-b.G)+Math.Abs(a.B-b.B);
    private async Task CheckReportGeometry(object core,string label) {
        JObject value=null;
        var deadline=Stopwatch.StartNew();
        while(deadline.ElapsedMilliseconds<3000) {
            string json=await (Task<string>)core.GetType().GetMethod("ExecuteScriptAsync").Invoke(core,new object[]{
                "(()=>{const e=document.getElementById('transition-report'),r=e.getBoundingClientRect(),b=e.querySelector('.loot-close-btn').getBoundingClientRect();return {visible:!e.hidden&&!document.getElementById('transition').hidden,width:r.width,height:r.height,x:r.x,y:r.y,viewportWidth:innerWidth,viewportHeight:innerHeight,closeX:b.x+b.width/2,closeY:b.y+b.height/2,closeHit:e.querySelector('.loot-close-btn').contains(document.elementFromPoint(b.x+b.width/2,b.y+b.height/2))};})()"});
            value=JObject.Parse(json);
            double scale=Math.Min(value.Value<double>("viewportWidth")/1024,value.Value<double>("viewportHeight")/576);
            if(value.Value<bool>("visible")&&Math.Abs(value.Value<double>("width")-1024*scale)<1
                &&Math.Abs(value.Value<double>("height")-576*scale)<1&&value.Value<bool>("closeHit")) break;
            await Task.Delay(30);
        }
        File.WriteAllText(Path.Combine(output,label+".json"),value.ToString(Formatting.Indented));
        double expectedScale=Math.Min(ClientSize.Width/1024.0,ClientSize.Height/576.0);
        if(!value.Value<bool>("visible")||value.Value<double>("viewportWidth")!=ClientSize.Width
            ||value.Value<double>("viewportHeight")!=ClientSize.Height
            ||Math.Abs(value.Value<double>("width")-1024*expectedScale)>=1
            ||Math.Abs(value.Value<double>("height")-576*expectedScale)>=1||!value.Value<bool>("closeHit"))
            throw new Exception("report viewport geometry or close hit target mismatch: "+value);
        checks.Add(new{label,passed=true});
    }
    private async Task CheckReportPixels(object core) {
        var capture=core.GetType().GetMethod("CapturePreviewAsync");
        var format=Enum.Parse(capture.GetParameters()[0].ParameterType,"Png");
        string previewPath=Path.Combine(output,"parallel-report-webview.png");
        using(var stream=File.Create(previewPath))
            await (Task)capture.Invoke(core,new object[]{format,stream});
        using var preview=new Bitmap(previewPath);
        var samples=new JArray();
        var deadline=Stopwatch.StartNew();
        do {
            using var screen=Capture("parallel-report-loading.png");
            samples.Clear();
            reportPixelsVerified=preview.Size==screen.Size;
            foreach(var point in new[]{new Point(100,40),new Point(510,100),new Point(970,150)}) {
                int x=point.X*screen.Width/1024,y=point.Y*screen.Height/576;
                var expected=preview.GetPixel(x,y);var actual=screen.GetPixel(x,y);
                int difference=Difference(expected,actual);
                samples.Add(new JObject { ["x"]=x,["y"]=y,["expectedArgb"]=expected.ToArgb(),
                    ["actualArgb"]=actual.ToArgb(),["difference"]=difference });
                reportPixelsVerified &= difference<=30;
            }
            if(reportPixelsVerified)break;
            await Task.Delay(100);
        } while(deadline.ElapsedMilliseconds<3000);
        var active=(Form)controller.GetType().GetField("_surface",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller);
        var endpoint=surfaceType.GetField("_web",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(active);
        File.WriteAllText(Path.Combine(output,"report-screen-pixels.json"),JsonConvert.SerializeObject(new {
            passed=reportPixelsVerified,samples,foreground=GetForegroundWindow().ToInt64(),owner=Handle.ToInt64(),
            surface=active.Handle.ToInt64(),surfaceVisible=active.Visible,surfaceBounds=active.Bounds,
            browserVisible=endpoint.GetType().GetProperty("IsVisible").GetValue(endpoint)
        },Formatting.Indented));
        if(!reportPixelsVerified)throw new Exception("report screen pixels differ from the current WebView2 report preview");
        checks.Add(new{label="current report screen pixels match the WebView2 report canvas",passed=true});
    }
    private int PeerActivations()=>File.Exists(Path.Combine(output,"peer-activated.jsonl"))
        ?File.ReadAllLines(Path.Combine(output,"peer-activated.jsonl")).Length:0;
    private async Task StartPeer() {
        var start=new ProcessStartInfo(Environment.ProcessPath) { UseShellExecute=false,CreateNoWindow=true };
        if(Path.GetFileNameWithoutExtension(Environment.ProcessPath).Equals("dotnet",StringComparison.OrdinalIgnoreCase))
            start.ArgumentList.Add(Assembly.GetEntryAssembly().Location);
        start.ArgumentList.Add("--foreground-peer");start.ArgumentList.Add(output);start.ArgumentList.Add(Handle.ToInt64().ToString());
        peer=Process.Start(start);
        await Wait(()=>File.Exists(Path.Combine(output,"peer-ready.json")),"separate process background window ready");
        // Shown precedes WinForms' final Show activation in the peer process.
        await Task.Delay(200);SetForegroundWindow(Handle);BringToFront();Activate();inputTarget.Focus();
        if(GetForegroundWindow()!=Handle)throw new Exception("fixture owner did not regain foreground");
    }
    private async Task Run() {
        string failure=null;
        try {
            await CheckInputLatencyProbe();
            var assembly=typeof(SceneTransitionTask).Assembly;
            string native=Path.Combine(candidate,"runtime","FlashCompositorNative.dll");
            if(!File.Exists(native))throw new FileNotFoundException("accepted CompositionScene ABI DLL required",native);
            NativeLibrary.SetDllImportResolver(assembly,(name,_,_)=>name=="FlashCompositorNative.dll"?NativeLibrary.Load(native):IntPtr.Zero);
            surfaceType=assembly.GetType("CF7Launcher.Guardian.CompositionHelpSurface",true);
            surface=Activator.CreateInstance(surfaceType,BindingFlags.Instance|BindingFlags.NonPublic,null,
                new object[]{this,Path.Combine(root,"launcher","web"),Path.Combine(output,"profile"),true},null);
            surfaceType.GetEvent("TransitionMessage",BindingFlags.Instance|BindingFlags.NonPublic).GetAddMethod(true)
                .Invoke(surface,new object[]{(Action<JObject>)Message});
            await (Task)Call("PrepareAsync");checks.Add(new{label="real WebView2 endpoint ready",passed=true});
            SetForegroundWindow(Handle);BringToFront();Activate();inputTarget.Focus();
            if(GetForegroundWindow()!=Handle)throw new Exception("fixture initial foreground was not admitted; visible="+IsWindowVisible(Handle)+" foreground="+GetForegroundWindow()+" owner="+Handle);
            if(!(bool)Call("PresentTransition",RectangleToScreen(ClientRectangle)))throw new Exception("projection admission refused");
            Call("PostTransition",Snapshot("cover",1));
            await Wait(()=>messages.Exists(p=>p.Value<string>("kind")=="covered"),"decoded curtain receipt");
            Call("RaiseTransition");
            await Task.Delay(300);
            using(var pixels=Capture("covered.png"))using(var original=new Bitmap(Path.Combine(root,"launcher","web","assets","bg","remake-andy.png"))) {
                if(Difference(pixels.GetPixel(800,200),original.GetPixel(800,200))>15)throw new Exception("opaque original background pixels differ; foreground="+GetForegroundWindow()+" owner="+Handle+" visible="+Visible+" surface="+((Form)surface).Visible+" bounds="+RectangleToScreen(ClientRectangle));
                checks.Add(new{label="opaque curtain retains original brightness pixels",passed=true});
            }
            CheckTransitionOrder();
            var denied=Snapshot("reveal",2);denied["revealAllowed"]=false;Call("PostTransition",denied);
            await Task.Delay(450);
            if(messages.Exists(p=>p.Value<string>("kind")=="revealed"))throw new Exception("reveal ignored capture gate");
            checks.Add(new{label="withheld capture gate retains curtain",passed=true});
            Call("PostTransition",Snapshot("reveal",2));
            await Wait(()=>messages.Exists(p=>p.Value<string>("kind")=="revealed"),"reveal receipt");await Task.Delay(300);
            using(var pixels=Capture("revealed.png")) {
                if(Difference(pixels.GetPixel(800,200),source)>5)throw new Exception("transparent reveal did not expose source HWND");
                checks.Add(new{label="transparent DirectComposition reveals underlying HWND",passed=true});
            }
            Call("HideTransition");
            Call("PresentTransition",RectangleToScreen(ClientRectangle));
            var error=Snapshot("error",3);error["requestId"]="tr:2";Call("PostTransition",error);await Task.Delay(450);
            using(var pixels=Capture("error.png"))checks.Add(new{label="warm endpoint reuse renders failure projection",passed=true});
            Activate();inputTarget.Focus();
            (surface as IDisposable)?.Dispose();surface=null;
            // Exercise actual Host admission as well as the underlying composition surface.
            await StartPeer();int peerActivations=PeerActivations();
            var controllerType=assembly.GetType("CF7Launcher.Guardian.SceneTransitionController",true);
            var wire=new List<JObject>();bool sceneReady=false,inputHeld=false,handoffDelivery=true;
            int successfulReportHandoffs=0;
            var handoffs=new List<(bool Covered,bool OwnedForeground,bool InputHeld)>();
            var focusManager=new WindowManager();
            typeof(WindowManager).GetField("_flashHwnd",BindingFlags.Instance|BindingFlags.NonPublic)
                .SetValue(focusManager,inputTarget.Handle);
            Func<IntPtr,bool> handoff=expected=> {
                var current=(Form)controllerType.GetField("_surface",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller);
                var fallback=(Form)controllerType.GetField("_fallback",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller);
                GetWindowThreadProcessId(GetForegroundWindow(),out uint foregroundPid);
                handoffs.Add((current.Visible||fallback.Visible,foregroundPid==Environment.ProcessId,inputHeld));
                return (bool)typeof(WindowManager).GetMethod("HandoffFlashFocusBeforePanelHide",BindingFlags.Instance|BindingFlags.NonPublic)
                    .Invoke(focusManager,new object[]{"scene_transition_probe:before_hide",expected});
            };
            // Also run this regression against the previous candidate, whose callback ran after Hide.
            object focusCallback=controllerType.GetConstructors(BindingFlags.Instance|BindingFlags.NonPublic)[0]
                .GetParameters()[7].ParameterType==typeof(Action)
                ?(object)(Action)(()=>{handoff(GetForegroundWindow());focusManager.RestoreFlashInputFocus("scene_transition_probe:after_hide");})
                :handoff;
            controller=Activator.CreateInstance(controllerType,BindingFlags.Instance|BindingFlags.NonPublic,null,
                new object[]{this,this,root,(Action<Action>)(a=>a()),
                    (Func<string,bool>)(s=>{
                        var p=JObject.Parse(s.TrimEnd('\0'));wire.Add(p);
                        bool delivered=p.Value<string>("kind")!="handoff"||handoffDelivery;
                        if(delivered && p.Value<string>("kind")=="handoff" && p.Value<string>("requestId")=="tr:4") successfulReportHandoffs++;
                        return delivered;
                    }),
                    (Func<bool>)(()=>true),(Func<long,bool>)(_=>sceneReady),focusCallback,
                    Array.CreateInstance(assembly.GetType("CF7Launcher.Guardian.OverlayBase",true),0),
                    (Action<bool>)(held=>inputHeld=held),Path.Combine(output,"controller-profile")},null);
            var task=(SceneTransitionTask)controllerType.GetField("Task",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller);
            var backing=(Form)controllerType.GetField("_fallback",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller);
            Action<JObject> project=p=>{
                p.Remove("type");p.Remove("generation");p.Remove("connected");p.Remove("revealAllowed");
                task.Handle(new JObject{["payload"]=p});
            };
            project(Snapshot("cover",1));
            if(!backing.Visible||!inputHeld)throw new Exception("Host admission left the source exposed before Web acknowledgement");
            checks.Add(new{label="Host installs opaque backing and input hold before Web acknowledgement",passed=true});
            backing.Update();
            using(var pixels=Capture("admission.png")) {
                if(Difference(pixels.GetPixel(800,200),Color.Black)>5)throw new Exception("native admission backing is not opaque");
                checks.Add(new{label="native admission backing pixels conceal the source HWND",passed=true});
            }
            await Wait(()=>wire.Exists(p=>p.Value<string>("kind")=="covered"),"Host receives painted curtain acknowledgement");
            if(backing.Visible)throw new Exception("native backing survived the current curtain acknowledgement");
            checks.Add(new{label="Host removes backing only after current painted acknowledgement",passed=true});
            project(Snapshot("reveal",2));await Task.Delay(450);
            if(wire.Exists(p=>p.Value<string>("kind")=="revealed")||!inputHeld)throw new Exception("Host revealed before the target capture gate");
            checks.Add(new{label="Host preserves curtain and input hold before target capture gate",passed=true});
            sceneReady=true;
            await Wait(()=>wire.Exists(p=>p.Value<string>("kind")=="revealed"),"Host reveals after target capture gate");
            if(inputHeld||backing.Visible)throw new Exception("Host reveal left a native curtain or input hold");
            checks.Add(new{label="Host reveal releases native curtain and input hold",passed=true});
            if(handoffs.Count!=1||!handoffs[0].Covered||!handoffs[0].OwnedForeground||!handoffs[0].InputHeld)
                throw new Exception("reveal handoff occurred after curtain hiding or foreground loss: "+JsonConvert.SerializeObject(handoffs));
            checks.Add(new{label="reveal hands foreground to owner while curtain still exists and input remains held",passed=true});
            await Task.Delay(100);
            if(GetForegroundWindow()!=Handle||!inputTarget.Focused||PeerActivations()!=peerActivations)
                throw new Exception("reveal activated the background process or lost exact input focus");
            checks.Add(new{label="background process receives no activation during reveal; owner and input focus remain current",passed=true});
            var next=Snapshot("cover",1);next["requestId"]="tr:2";project(next);
            if(!backing.Visible) {
                var active=controllerType.GetField("_surface",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller);
                bool focus=(bool)surfaceType.GetProperty("CanRestoreGameFocus",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(active);
                throw new Exception("warm Host admission omitted its opaque backing; fixture foreground admitted="+focus);
            }
            checks.Add(new{label="warm Host admission conceals source before next Web delivery",passed=true});
            await Wait(()=>wire.Exists(p=>p.Value<string>("requestId")=="tr:2"&&p.Value<string>("kind")=="covered"),"warm Host receives current curtain acknowledgement");
            var retire=Snapshot("hide",2);retire["requestId"]="tr:2";project(retire);await Task.Delay(100);
            if(handoffs.Count!=2||!handoffs[1].Covered||!handoffs[1].OwnedForeground||!handoffs[1].InputHeld
                ||inputHeld||GetForegroundWindow()!=Handle||PeerActivations()!=peerActivations)
                throw new Exception("retirement hid its foreground curtain before returning input to owner");
            checks.Add(new{label="explicit retirement also hands off before hiding, without activating background process",passed=true});
            var external=Snapshot("cover",1);external["requestId"]="tr:3";project(external);
            await Wait(()=>wire.Exists(p=>p.Value<string>("requestId")=="tr:3"&&p.Value<string>("kind")=="covered"),"external-switch curtain covered");
            var peerWindow=new IntPtr(JObject.Parse(File.ReadAllText(Path.Combine(output,"peer-ready.json"))).Value<long>("hwnd"));
            if(!SetForegroundWindow(peerWindow)||GetForegroundWindow()!=peerWindow)
                throw new Exception("fixture external foreground switch was not admitted");
            retire=Snapshot("hide",2);retire["requestId"]="tr:3";project(retire);await Task.Delay(100);
            if(handoffs.Count!=2||inputHeld||GetForegroundWindow()!=peerWindow)
                throw new Exception("retirement stole foreground after an intentional external switch");
            checks.Add(new{label="intentional external foreground switch suppresses handoff and remains untouched",passed=true});

            // The foreground peer models the user's return gesture. The inactive owner
            // cannot grant itself foreground after the intentional external-switch case.
            File.WriteAllText(Path.Combine(output,"peer-return"),"1");
            await Wait(()=>GetForegroundWindow()==Handle,"fixture external foreground yields to the returning owner");
            inputTarget.Focus();
            var reportSurface=controllerType.GetField("_surface",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(controller);
            var reportEndpoint=surfaceType.GetField("_web",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(reportSurface);
            var reportCore=reportEndpoint.GetType().GetProperty("CoreWebView2").GetValue(reportEndpoint);
            await (Task<string>)reportCore.GetType().GetMethod("ExecuteScriptAsync").Invoke(reportCore,new object[]{
                "window.fixtureErrors=[];window.addEventListener('unhandledrejection',e=>fixtureErrors.push(String(e.reason)));window.addEventListener('error',e=>fixtureErrors.push(e.message));"});
            sceneReady=false;
            var report=new JObject { ["v"]=1,["runId"]="run.parallel.1",["stageName"]="联合大学 · 并行返回",
                ["difficulty"]="简单",["outcome"]="victory",["activeFrames"]=900,["totalKills"]=0,["omittedKillTypes"]=0,
                ["totalItemGains"]=2,["totalItemLosses"]=0,["omittedItemFlowTypes"]=0,["rewardRollOmissions"]=0,
                ["kills"]=new JArray(),["itemFlows"]=new JArray(new JObject {
                    ["direction"]="gain",["kind"]="item",["itemKey"]="强化石",["displayName"]="强化石",
                    ["iconName"]="强化石",["tier"]="",["source"]="stage_settlement",["reason"]="stage_reward_stashed",["count"]=2
                }),["rewardStashed"]=true };
            JObject parallel(string id,string phase,int revision,bool opening=false) {
                var p=Snapshot(phase,revision);p["version"]=2;p["requestId"]=id;p["report"]=report.DeepClone();
                p["targetScene"]=phase is "cover" or "loading" ? 1 : 2;
                p["reportVisible"]=true;p["reportHandoff"]=opening;p["actionPending"]=opening;return p;
            }
            int requests=0,snapshots=0,completions=0;
            var bindingType=assembly.GetType("CF7Launcher.Guardian.LootPanelCoordinator+Binding",true);
            var binding=Activator.CreateInstance(bindingType,BindingFlags.Instance|BindingFlags.NonPublic,null,
                new object[]{new LootPanelCoordinator.OpenRequest { ChestSessionId="chest.parallel.1",LootContainerId="container.parallel.1",
                    ContainerEpoch=1,SourceKind="stage_settlement",SettlementReport=report },"loot.parallel.1"},null);
            var matcher=typeof(SceneTransitionTask).GetMethod("MatchesSettlementReceipt",BindingFlags.Static|BindingFlags.NonPublic);
            controllerType.GetMethod("ConfigureSettlement",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(controller,new object[]{
                (Func<JObject,bool>)(p=>(bool)matcher.Invoke(null,new object[]{p,binding,true,"loot","loot.parallel.1"})),
                (Func<long,bool>)(scene=>sceneReady&&scene==2)});
            controllerType.GetEvent("SceneCompleted",BindingFlags.Instance|BindingFlags.NonPublic).GetAddMethod(true)
                .Invoke(controller,new object[]{(Action)(()=>completions++)});
            var postPanel=surfaceType.GetMethod("TryPostTransitionPanel",BindingFlags.Instance|BindingFlags.NonPublic);
            bool post(JObject p)=>(bool)postPanel.Invoke(reportSurface,new object[]{p.ToString(Formatting.None)});
            JObject window(string id,int capacity) {
                var slots=new JArray();for(int i=0;i<capacity;i++)slots.Add(new JObject{["physicalSlot"]=i,["occupied"]=false,["slotLease"]="empty."+i});
                return new JObject { ["containerId"]=id,["capacity"]=capacity,["accessibleCapacity"]=capacity,["viewCapacity"]=capacity,
                    ["filterKey"]="all",["pageSizeHint"]=capacity,["locked"]=false,["snapshotSeq"]=1,["containerEpoch"]=1,["containerVersion"]=1,
                    ["offset"]=0,["limit"]=capacity,["slots"]=slots,["filterFacets"]=new JArray(),["filterItemCount"]=0,
                    ["setFacets"]=new JArray(),["setFilterItemCount"]=0};
            }
            surfaceType.GetEvent("SettlementMessage",BindingFlags.Instance|BindingFlags.NonPublic).GetAddMethod(true)
                .Invoke(reportSurface,new object[]{(Action<JObject>)(p=> {
                    if(p.Value<string>("task")!="loot_request")return;
                    requests++;if(p.Value<string>("cmd")=="snapshot")snapshots++;
                    post(new JObject { ["type"]="panel_resp",["task"]="loot_response",["domain"]="loot",["panel"]="loot",
                        ["cmd"]=p["cmd"],["callId"]=p["callId"],["panelInstanceId"]=p["panelInstanceId"],
                        ["chestSessionId"]=p["chestSessionId"],["lootContainerId"]=p["lootContainerId"],["containerEpoch"]=p["containerEpoch"],
                        ["success"]=true,["error"]="",["authorityRevision"]=1,["lastAppliedOperationId"]="",["state"]="LOOT_ACTIVE",["remainingCount"]=0,
                        ["closeLease"]="close.parallel.1",["snapshots"]=new JArray(window("container.parallel.1",8),window("背包",50),window("药剂栏",8)),
                        ["tooltip"]=null,["materials"]=p.Value<string>("cmd")=="materials"?new JArray():null,["terminal"]=null });
                })});
            async Task<string> js(string source)=>(string)await (Task<string>)reportCore.GetType().GetMethod("ExecuteScriptAsync").Invoke(reportCore,new object[]{source});
            async Task waitScript(string source,string label) {
                var end=DateTime.UtcNow.AddSeconds(8);
                while(DateTime.UtcNow<end){if(await js(source)=="true"){checks.Add(new{label,passed=true});return;}await Task.Delay(25);}
                throw new Exception("timeout: "+label+" errors="+await js("JSON.stringify(fixtureErrors)"));
            }
            var sameSurface=(Form)reportSurface;var sameHandle=sameSurface.Handle;
            // Hold the real page's one automatic intent in the fixture transport, advance
            // the simulated AS2 producer, then release the unchanged message through WebView2.
            await js("(function(){var post=chrome.webview.postMessage.bind(chrome.webview);window.fixtureHeldReportCount=0;"
                +"window.fixtureReleaseReport=function(){post(window.fixtureHeldReport);};chrome.webview.postMessage=function(m){"
                +"if(m.type==='scene_transition_action'&&m.requestId==='tr:4'&&m.verb==='manageReport'){fixtureHeldReportCount++;window.fixtureHeldReport=m;return;}post(m);};})();");
            ClientSize=new Size(1600,900);await Task.Delay(250);
            project(parallel("tr:4","cover",1));
            await Wait(()=>wire.Exists(p=>p.Value<string>("requestId")=="tr:4"&&p.Value<string>("kind")=="covered"),"parallel frozen report paints before base readiness");
            await CheckReportGeometry(reportCore,"report-first-1600x900");await Task.Delay(300);await CheckReportPixels(reportCore);
            await js("window.sameReport=document.querySelector('.loot-settlement-report');window.sameShell=document.querySelector('.loot-stage-settlement');");
            await waitScript("LootPanel.reportPresentation().density==='compact'&&document.querySelectorAll('[data-settlement-stashed-rewards] .loot-settlement-flow-card').length===1&&document.querySelector('[data-settlement-stashed-rewards] strong').textContent==='+2'",
                "isolated profile starts compact and shows committed rewards without another claim");
            using(var pixels=Capture("parallel-report-compact-rewards.png")) { }
            await js("document.querySelector('.item-grid-mode-option[data-layout-mode=full]').click();document.querySelector('[data-settlement-side-tab=materials]').click();document.querySelector('.loot-settlement-material-toolbar input').value='金属';");
            await waitScript("fixtureHeldReportCount===1&&fixtureHeldReport.revision===1","real page issues one report intent before display advancement");
            project(parallel("tr:4","loading",2));
            await js("fixtureReleaseReport();");
            await Wait(()=>wire.Exists(p=>p.Value<string>("requestId")=="tr:4"&&p.Value<string>("verb")=="manageReport"),"covered report requests reward admission before scene capture");
            var admission=wire.FindAll(p=>p.Value<string>("requestId")=="tr:4"&&p.Value<string>("verb")=="manageReport");
            if(admission.Count!=1 || admission[0].Value<int>("revision")!=2)
                throw new Exception("in-flight report intent did not survive Host display advancement exactly once");
            checks.Add(new{label="delayed report intent crosses cover/loading advancement through the production Host ingress once",passed=true});
            if(sceneReady||requests!=0)throw new Exception("preview issued business commands without binding");
            checks.Add(new{label="preview has no business authority while native scene remains loading",passed=true});
            project(parallel("tr:4","loading",3,true));
            var init=new JObject { ["v"]=1,["panelInstanceId"]="loot.parallel.1",["chestSessionId"]="chest.parallel.1",
                ["lootContainerId"]="container.parallel.1",["containerEpoch"]=1,["displayName"]="关卡结算",["capacity"]=8,["columns"]=4,
                ["sourceKind"]="stage_settlement",["report"]=report.DeepClone() };
            if(!(bool)controllerType.GetMethod("CanAdmitSettlement",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(controller,new object[]{init.ToString(Formatting.None)}))
                throw new Exception("current report could not admit its exact business session");
            if(!post(new JObject{["type"]="panel_cmd",["cmd"]="open",["panel"]="loot",["initData"]=init}))throw new Exception("early reward bind post rejected");
            await waitScript("LootPanel.debugState().phase==='active'","production Loot session binds while scene is still loading");
            await waitScript("LootPanel.debugState().remainingCount===0&&document.querySelector('[data-settlement-stashed-rewards] strong').textContent==='+2'&&!document.querySelector('.loot-source-grid')",
                "bound authority stays empty while committed reward history remains visible");
            await waitScript("sameReport===document.querySelector('.loot-settlement-report')&&sameShell===document.querySelector('.loot-stage-settlement')&&LootPanel.reportPresentation().density==='full'&&LootPanel.reportPresentation().materialSearch==='金属'",
                "reward binding preserves the same report nodes, density and search");
            if(snapshots!=1||requests<2||!inputHeld||sceneReady)throw new Exception("early session proof is incomplete");
            checks.Add(new{label="existing snapshot and materials commands complete before scene readiness without world release",passed=true});
            // A warm, unchanged surface must leave the UI pump free while Flash loads.
            // Count actual WebView messages, rather than timing an empty/mock controller.
            await js("window.fixtureViewportMessages=0;chrome.webview.addEventListener('message',e=>{if(e.data.type==='panel_viewport_set')fixtureViewportMessages++;});");
            await Task.Delay(100);
            int viewportBefore=int.Parse(await js("fixtureViewportMessages"));
            var repeatedPresentation=Stopwatch.StartNew();
            var present=surfaceType.GetMethod("PresentTransition",BindingFlags.Instance|BindingFlags.NonPublic);
            for(int repeat=0;repeat<40;repeat++)
                if(!(bool)present.Invoke(reportSurface,new object[]{sameSurface.Bounds}))
                    throw new Exception("unchanged settlement presentation rejected");
            repeatedPresentation.Stop();
            await Task.Delay(120);
            int viewportDuplicates=int.Parse(await js("fixtureViewportMessages"))-viewportBefore;
            File.WriteAllText(Path.Combine(output,"steady-presentation.json"),JsonConvert.SerializeObject(new {
                repetitions=40,elapsedMs=repeatedPresentation.Elapsed.TotalMilliseconds,viewportDuplicates
            },Formatting.Indented));
            if(viewportDuplicates!=0)throw new Exception("unchanged settlement repeatedly posted viewport: "+viewportDuplicates);
            checks.Add(new{label="unchanged settlement submits no repeated viewport messages across 40 presentations",passed=true});
            using(var pixels=Capture("parallel-report-bound.png")) { }
            ClientSize=new Size(1280,720);await Task.Delay(250);await CheckReportGeometry(reportCore,"report-resized-1280x720");
            ClientSize=new Size(1024,576);await Task.Delay(250);await CheckReportGeometry(reportCore,"report-restored-1024x576");
            project(parallel("tr:4","reveal",4,true));await Task.Delay(150);
            if(wire.Exists(p=>p.Value<string>("requestId")=="tr:4"&&p.Value<string>("kind")=="prepared"))throw new Exception("uncaptured target granted scene completion");
            checks.Add(new{label="early reward readiness never substitutes for native scene capture",passed=true});
            handoffDelivery=false;sceneReady=true;
            await Wait(()=>wire.Exists(p=>p.Value<string>("requestId")=="tr:4"&&p.Value<string>("kind")=="prepared"),"native target capture prepares the existing report");
            await Task.Delay(100);if(!inputHeld||completions!=0)throw new Exception("failed scene ACK withdrew loading ownership");
            checks.Add(new{label="unknown scene completion delivery retains the existing curtain",passed=true});
            handoffDelivery=true;
            await Wait(()=>successfulReportHandoffs==1,"captured target and bound report successfully queue one scene completion");
            var tombstone=parallel("tr:4","hide",5);tombstone["reportVisible"]=false;tombstone["reportHandoff"]=false;tombstone["actionPending"]=false;
            int beforePeer=PeerActivations();project(tombstone);
            await Wait(()=>completions==1&&!inputHeld,"AS2 timeline retirement releases loading ownership without closing settlement");
            await waitScript("sameReport===document.querySelector('.loot-settlement-report')&&sameShell===document.querySelector('.loot-stage-settlement')&&window.__LOOT_PANEL_CONFIG__.sceneReady===true",
                "scene completion updates capabilities on the same live report");
            if(sameSurface.Handle!=sameHandle||!sameSurface.Visible||snapshots!=1||PeerActivations()!=beforePeer)
                throw new Exception("scene completion changed the native endpoint, remounted business or exposed the background application");
            checks.Add(new{label="same HWND and Core remain visible; no second snapshot or background activation",passed=true});
            await waitScript("document.querySelector('.workbench-status').textContent==='结算状态已同步'",
                "scene readiness updates the existing status label");
            await Task.Delay(120); // Allow the already-confirmed DOM update to reach screen capture.
            using(var pixels=Capture("parallel-report-scene-ready.png")) { }
            project(tombstone);await Task.Delay(80);
            if(completions!=1||inputHeld)throw new Exception("duplicate tombstone repeated scene completion");
            checks.Add(new{label="duplicate timeline retirement is inert for the live settlement",passed=true});
            SetForegroundWindow(peerWindow);await Task.Delay(80);
            if(GetForegroundWindow()!=peerWindow)throw new Exception("live settlement stole external foreground");
            checks.Add(new{label="live settlement preserves intentional external foreground",passed=true});
            // The foreground process performs the return gesture again. Calling
            // SetForegroundWindow from the inactive owner can be rejected by Windows;
            // an unchanged hidden DOM is not proof of successful reactivation.
            File.WriteAllText(Path.Combine(output,"peer-return"),"2");
            // The resumed production surface may activate within the 25ms tick,
            // before this fixture's 30ms poll observes the transient owner activation.
            await Wait(()=>GetForegroundWindow()==Handle||GetForegroundWindow()==sameHandle,
                "external foreground returns to the exact owner or live settlement window");
            inputTarget.Focus();
            await Wait(()=>sameSurface.Visible,"reactivation actually restores the shared settlement window");
            await waitScript("sameReport===document.querySelector('.loot-settlement-report')","reactivation retains the same report node");
            if(!post(new JObject{["type"]="panel_cmd",["cmd"]="close",["panel"]="loot",["panelInstanceId"]="loot.parallel.1"}))throw new Exception("exact settlement close failed");
            controllerType.GetMethod("ReleaseSettlement",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(controller,null);
            await Wait(()=>!sameSurface.Visible,"exact business retirement finally hides the shared endpoint");
            sceneReady=false;
            int nextViewportBefore=int.Parse(await js("fixtureViewportMessages"));
            report["runId"]="run.parallel.2";
            project(parallel("tr:5","cover",1));
            await Wait(()=>wire.Exists(p=>p.Value<string>("requestId")=="tr:5"&&p.Value<string>("kind")=="covered"),
                "the same endpoint paints the next run before that scene is ready");
            await waitScript("LootPanel.isPreview()&&window.__LOOT_PANEL_CONFIG__.sceneReady===false",
                "consecutive settlement clears the previous run's ready status");
            if(int.Parse(await js("fixtureViewportMessages"))-nextViewportBefore!=1)
                throw new Exception("new presentation session must receive exactly one fresh viewport");
            checks.Add(new{label="new session at unchanged size receives exactly one fresh viewport",passed=true});
            retire=Snapshot("hide",2);retire["requestId"]="tr:5";retire["version"]=2;
            retire["report"]=report.DeepClone();retire["reportVisible"]=true;retire["reportHandoff"]=false;
            project(retire);
        } catch(Exception e) { failure=e.ToString();Environment.ExitCode=1; }
        finally {
            (surface as IDisposable)?.Dispose();
            (controller as IDisposable)?.Dispose();
            if(peer!=null) {
                File.WriteAllText(Path.Combine(output,"peer-stop"),"");
                if(!peer.HasExited && !peer.WaitForExit(2000))peer.Kill();
                peer.Dispose();
            }
            File.WriteAllText(Path.Combine(output,"result.json"),JsonConvert.SerializeObject(new {
                kind="isolated-composition-fixture",state=failure==null?"fixture_executed":"failed",checks,
                core=typeof(SceneTransitionTask).Assembly.Location,native=Path.Combine(candidate,"runtime","FlashCompositorNative.dll"),
                candidate,coreSha256=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(SceneTransitionTask).Assembly.Location))),
                identity=JObject.Parse(File.ReadAllText(Path.Combine(candidate,"runtime-build-metadata.v2.json"))),
                reportPixelsVerified,gameE2e=false,slotsTouched=false,failure },Formatting.Indented));
            Close();
        }
    }

    private void CheckTransitionOrder() {
        var curtain=(Form)surface;
        using var curtainMessages=new PositionObserver(curtain.Handle);
        using var ownerMessages=new PositionObserver(Handle);
        var elapsed=Stopwatch.StartNew();
        for(int i=0;i<40;i++)Call("RaiseTransition");
        elapsed.Stop();
        File.WriteAllText(Path.Combine(output,"transition-order.json"),JsonConvert.SerializeObject(new {
            repetitions=40,elapsedMs=elapsed.Elapsed.TotalMilliseconds,
            curtainPositionRequests=curtainMessages.Changes,ownerPositionRequests=ownerMessages.Changes
        },Formatting.Indented));
        if(curtainMessages.Changes!=0||ownerMessages.Changes!=0)
            throw new Exception("unchanged curtain repeatedly submitted native window positioning");
        checks.Add(new{label="40 unchanged production raises submit no native window positioning requests",passed=true});
        using var hud=new PassiveReport {Owner=this,Bounds=curtain.Bounds,BackColor=Color.Magenta,ShowInTaskbar=false};
        hud.Show();SetWindowPos(hud.Handle,IntPtr.Zero,0,0,0,0,0x0213);
        bool above(IntPtr upper,IntPtr lower) {
            for(int i=0;lower!=IntPtr.Zero&&i<512;i++,lower=GetWindow(lower,3))if(lower==upper)return true;
            return false;
        }
        if(!above(hud.Handle,curtain.Handle))throw new Exception("fixture did not place sibling over curtain");
        IntPtr foreground=GetForegroundWindow();var bounds=curtain.Bounds;
        ownerMessages.Changes=curtainMessages.Changes=0;
        Call("RaiseTransition");
        if(!above(curtain.Handle,hud.Handle)||ownerMessages.Changes!=0||curtainMessages.Changes!=1
            ||GetForegroundWindow()!=foreground||curtain.Bounds!=bounds)
            throw new Exception("covered curtain repair moved owner, changed focus/bounds or failed to restore order");
        for(int i=0;i<40;i++)Call("RaiseTransition");
        if(curtainMessages.Changes!=1)throw new Exception("repaired curtain did not return to a stable stack");
        checks.Add(new{label="new sibling coverage repairs once without owner movement, focus change or repeated requests",passed=true});
    }
    private sealed class PositionObserver : NativeWindow,IDisposable {
        internal int Changes;
        internal PositionObserver(IntPtr window)=>AssignHandle(window);
        protected override void WndProc(ref Message m) { if(m.Msg==0x0046)Changes++;base.WndProc(ref m); }
        public void Dispose()=>ReleaseHandle();
    }
    private async Task CheckInputLatencyProbe() {
        var assembly=typeof(SceneTransitionTask).Assembly;
        var trace=assembly.GetType("CF7Launcher.Diagnostic.FocusTrace",true);
        var probeType=assembly.GetType("CF7Launcher.Diagnostic.InputLatencyProbe",true);
        var lines=new System.Collections.Concurrent.ConcurrentQueue<string>();
        const BindingFlags flags=BindingFlags.Static|BindingFlags.NonPublic;
        string previous=Environment.GetEnvironmentVariable("CF7_INPUT_LATENCY");
        object probe=null;
        try {
            trace.GetMethod("Start",flags).Invoke(null,new object[]{(Action<string>)lines.Enqueue,true,false,null});
            Environment.SetEnvironmentVariable("CF7_INPUT_LATENCY","1");
            probe=probeType.GetMethod("StartConfigured",flags).Invoke(null,new object[]{this,"fixture"});
            probeType.GetMethod("BeginTransition",BindingFlags.Instance|BindingFlags.NonPublic)
                .Invoke(probe,new object[]{"fixture-ui-stall",1L,"loading"});
            await Task.Delay(70);
            // Synthetic host stall validates the measuring path, not a gameplay performance fix.
            System.Threading.Thread.Sleep(150);
            await Task.Delay(100);
            probeType.GetMethod("SetPhase",BindingFlags.Instance|BindingFlags.NonPublic)
                .Invoke(probe,new object[]{"base_ready",true});
            await Task.Delay(2200);
            trace.GetMethod("Flush",flags).Invoke(null,new object[]{true});
            var events=lines.SelectMany(batch=>batch.Split('\n')).Where(l=>l.StartsWith("[FocusTrace] "))
                .Select(l=>JObject.Parse(l.Substring("[FocusTrace] ".Length))).ToArray();
            if(!events.Any(e=>e.Value<string>("event")=="input_latency.slow"
                && e["data"].Value<string>("metric")=="ui_dispatch"&&e["data"].Value<double>("ms")>=80))
                throw new Exception("latency probe did not detect the intentional UI stall");
            if(!events.Any(e=>e.Value<string>("event")=="input_latency.summary"))
                throw new Exception("latency probe did not end its bounded scene window");
            checks.Add(new{label="real UI heartbeat detects an intentional 150ms stall and closes its recording window",passed=true});
        } finally {
            (probe as IDisposable)?.Dispose();
            trace.GetMethod("Stop",flags).Invoke(null,null);
            File.WriteAllText(Path.Combine(output,"input-latency.log"),string.Join(Environment.NewLine,lines));
            Environment.SetEnvironmentVariable("CF7_INPUT_LATENCY",previous);
        }
    }
}

internal sealed class PassiveReport : Form { protected override bool ShowWithoutActivation=>true; }

// A fixture-owned second process stands in for an application behind the game.
internal sealed class ForegroundPeer : Form {
    private readonly string output;
    private readonly System.Windows.Forms.Timer stop=new() { Interval=40 };
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    internal ForegroundPeer(string output,IntPtr fixtureOwner) {
        this.output=output;Text="U12 fixture background process";BackColor=Color.Magenta;
        ClientSize=new Size(1024,576);StartPosition=FormStartPosition.Manual;Location=new Point(60,70);
        Shown+=(_,_)=> {
            SetForegroundWindow(fixtureOwner);
            File.WriteAllText(Path.Combine(output,"peer-ready.json"),
                JsonConvert.SerializeObject(new { hwnd=Handle.ToInt64(),pid=Environment.ProcessId }));
        };
        string returned=null;
        stop.Tick+=(_,_)=>{
            string request=Path.Combine(output,"peer-return");
            if(File.Exists(request)) {
                string token=File.ReadAllText(request);
                if(token.Length>0&&token!=returned) { returned=token;SetForegroundWindow(fixtureOwner); }
            }
            if(File.Exists(Path.Combine(output,"peer-stop")))Close();
        };stop.Start();
    }
    protected override void WndProc(ref Message message) {
        base.WndProc(ref message);
        if(message.Msg==0x0006&&(message.WParam.ToInt64()&0xFFFF)!=0&&GetForegroundWindow()==Handle)
            File.AppendAllText(Path.Combine(output,"peer-activated.jsonl"),
                JsonConvert.SerializeObject(new { hwnd=Handle.ToInt64(),pid=Environment.ProcessId,time=DateTime.UtcNow })+Environment.NewLine);
    }
    protected override void Dispose(bool disposing) { if(disposing)stop.Dispose();base.Dispose(disposing); }
}
