using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Security.Cryptography;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;

// Real owned HWND, DirectComposition and WebView2 lifecycle. No Flash, slots or physical input.
internal sealed class Probe : Form
{
    private readonly string root,candidate,output;
    private object surface;
    private Type surfaceType;
    private readonly List<double> samples=new();
    private readonly List<WeakReference> adapters=new();
    private int closes;
    private readonly Stopwatch elapsed=new();
    [STAThread] private static void Main(string[] args) {
        if(args.Length!=3) { Environment.ExitCode=2;return; }
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);Application.EnableVisualStyles();
        Application.Run(new Probe(Path.GetFullPath(args[0]),Path.GetFullPath(args[1]),Path.GetFullPath(args[2])));
    }
    private Probe(string root,string candidate,string output) {
        this.root=root;this.candidate=candidate;this.output=output;Directory.CreateDirectory(output);
        Text="CF7 自有面板生命周期验证";ClientSize=new Size(1024,576);ShowInTaskbar=false;
        StartPosition=FormStartPosition.Manual;Location=new Point(40,40);
        Shown+=async(_,_)=>await Run();
    }
    private object Call(string method,params object[] args)=>surfaceType.GetMethod(method,BindingFlags.Instance|BindingFlags.NonPublic).Invoke(surface,args);
    private object Field(string field)=>surfaceType.GetField(field,BindingFlags.Instance|BindingFlags.NonPublic).GetValue(surface);
    private async Task Wait(Func<bool> ready,string label) {
        var clock=Stopwatch.StartNew();while(!ready() && clock.Elapsed<TimeSpan.FromSeconds(20))await Task.Delay(10);
        if(!ready())throw new Exception("Timed out: "+label);
    }
    private async Task WaitDom() {
        var clock=Stopwatch.StartNew();
        while(clock.Elapsed<TimeSpan.FromSeconds(20)) {
            if(await Script("!!document.querySelector('.help-close-btn')")=="true")return;
            await Task.Delay(10);
        }
        throw new Exception("Timed out: help DOM");
    }
    private Task<string> Script(string script) {
        object core=Field("_endpointCore");
        return (Task<string>)core.GetType().GetMethod("ExecuteScriptAsync").Invoke(core,new object[] {script});
    }
    private string Sha(string file)=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file)));
    private async Task Run() {
        var report=new JObject { ["schema"]="cf7-panel-lifetime-native-probe.v1",["evidenceKind"]="owned production composition surface and actual WebView2 close adapter; no full Launcher or physical input proof",
            ["candidateRoot"]=candidate,["candidateMetadata"]=JObject.Parse(File.ReadAllText(Path.Combine(candidate,"runtime-build-metadata.v2.json"))) };
        try {
            var assembly=typeof(SettingsTask).Assembly;
            string core=Path.Combine(candidate,"runtime","CRAZYFLASHER7MercenaryEmpire.Core.dll");
            if(Sha(core)!=Sha(assembly.Location))throw new Exception("Loaded Core differs from candidate bytes");
            report["loadedCorePath"]=assembly.Location;report["coreSha256"]=Sha(core);
            report["mvid"]=assembly.ManifestModule.ModuleVersionId.ToString();
            AssemblyLoadContext.Default.Resolving+=(_,name)=> {
                string file=Path.Combine(candidate,"runtime",name.Name+".dll");return File.Exists(file)?AssemblyLoadContext.Default.LoadFromAssemblyPath(file):null;
            };
            NativeLibrary.SetDllImportResolver(assembly,(name,_,_)=> {
                string file=Path.Combine(candidate,"runtime",name);return File.Exists(file)?NativeLibrary.Load(file):IntPtr.Zero;
            });
            surfaceType=assembly.GetType("CF7Launcher.Guardian.CompositionHelpSurface",true);
            surface=Activator.CreateInstance(surfaceType,BindingFlags.Instance|BindingFlags.NonPublic,null,
                new object[] {this,Path.Combine(root,"launcher","web"),Path.Combine(output,"profile"),null,false,null,null},null);
            var closeEvent=surfaceType.GetEvent("HostCloseRequested",BindingFlags.Instance|BindingFlags.NonPublic);
            var handler=Delegate.CreateDelegate(closeEvent.EventHandlerType,this,GetType().GetMethod(nameof(OnExactClose),BindingFlags.Instance|BindingFlags.NonPublic));
            closeEvent.GetAddMethod(true).Invoke(surface,new object[] {handler});
            long baseline=GC.GetTotalMemory(true);elapsed.Start();
            for(int i=0;i<1000;i++) {
                var lap=Stopwatch.StartNew();await (Task)Call("PrepareAsync");
                if(!(bool)Call("ResumePanel",RectangleToScreen(ClientRectangle)))throw new Exception("Surface admission refused");
                string id="owned."+Guid.NewGuid().ToString("N");
                var open=new JObject { ["type"]="panel_cmd",["panel"]="help",["cmd"]="open",["initData"]=new JObject { ["panelInstanceId"]=id } };
                if(!(bool)Call("TryPost",open.ToString()))throw new Exception("Open publication failed");
                await WaitDom();
                adapters.Add(new WeakReference(Field("_messageAdapter")));
                int before=closes;await Script("document.querySelector('.help-close-btn').click()");
                await Wait(()=>closes==before+1,"actual native close event");
                foreach(string field in new[] {"_messageAdapter","_failureAdapter","_acceleratorAdapter","_callbackCore","_callbackController","_pendingHostClose"}) {
                    // Detachment removes registrations; delegate fields may retain one inert last adapter.
                    if(field.StartsWith("_callback") || field=="_pendingHostClose")if(Field(field)!=null)throw new Exception("Registration survived retirement: "+field);
                }
                samples.Add(lap.Elapsed.TotalMilliseconds);
                long delay=(i+1)*300L-elapsed.ElapsedMilliseconds;if(delay>0)await Task.Delay((int)delay);
            }
            long after=GC.GetTotalMemory(true);int live=0;foreach(var adapter in adapters)if(adapter.IsAlive)live++;
            samples.Sort();report["cycles"]=closes;report["elapsedMs"]=elapsed.ElapsedMilliseconds;
            report["managedBytesBefore"]=baseline;report["managedBytesAfter"]=after;report["liveOldAdapters"]=live;
            report["cycleP50Ms"]=samples[499];report["cycleP95Ms"]=samples[949];report["cycleP99Ms"]=samples[989];
            if(closes!=1000 || elapsed.Elapsed<TimeSpan.FromMinutes(5) || live>1)throw new Exception("Lifecycle budget did not drain");
            report["status"]="passed";
        } catch(Exception error) { report["status"]="failed";report["error"]=error.ToString();Environment.ExitCode=1; }
        finally { (surface as IDisposable)?.Dispose();File.WriteAllText(Path.Combine(output,"report.json"),report.ToString());Close(); }
    }
    private void OnExactClose(object context) {
        var endpoint=context.GetType().GetField("Endpoint",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(context);
        if(!(bool)Call("RetireExact",endpoint))throw new Exception("Original endpoint could not retire");
        closes++;
    }
}
