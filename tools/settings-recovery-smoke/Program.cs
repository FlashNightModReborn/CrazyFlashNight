using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;

public class FixtureParserProxy : DispatchProxy
{
    public object Result;
    protected override object Invoke(MethodInfo method,object[] arguments)
    {
        if(method.Name!="Parse")throw new InvalidOperationException("Unexpected parser fixture method");
        return Result;
    }
}

// Runs one candidate's actual recovery gate in a fresh process. No game or writer is launched.
internal static class Program
{
    private const BindingFlags Members=BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic;
    private static Assembly core;
    private static object New(string name,params object[] values)=>Activator.CreateInstance(
        core.GetType("CF7Launcher.Save."+name,true),Members,null,values,null);
    private static object Call(object target,string method,params object[] values)=>
        target.GetType().GetMethod(method,Members).Invoke(target,values);
    private static object Field(object target,string name)=>target?.GetType().GetField(name,Members)?.GetValue(target);
    private static string Sha(string file)=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))).ToLowerInvariant();
    private static void Within(string path,string parent)
    {
        if(!Path.GetFullPath(path).StartsWith(Path.GetFullPath(parent)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Probe output must remain inside its owned fixture evidence directory");
    }
    private static int Main(string[] args)
    {
        if(args.Length is not (4 or 5)) { Console.Error.WriteLine("candidate-root fixture.json journal-directory fresh-output-directory [future-receipt-noncanonical]");return 2; }
        bool derivedParser=args.Length==5 && args[4]=="future-receipt-noncanonical";
        if(args.Length==5 && !derivedParser)throw new ArgumentException("Unknown parser boundary fixture");
        string candidate=Path.GetFullPath(args[0]),fixturePath=Path.GetFullPath(args[1]);
        string journalDirectory=Path.GetFullPath(args[2]),output=Path.GetFullPath(args[3]);
        var fixture=JObject.Parse(File.ReadAllText(fixturePath));
        if(!Regex.IsMatch((string)fixture["slot"],@"\Acf7_env_set_[0-9a-f]{20}\z"))
            throw new ArgumentException("Only native owned-SOL fixture slots are admitted");
        string evidence=(string)fixture["evidenceDirectory"];
        Within(journalDirectory,evidence);Within(output,evidence);
        if(!File.Exists(Path.Combine(journalDirectory,"contexts.json")) || Directory.Exists(output))
            throw new ArgumentException("Supply a prepared journal copy and a fresh output directory");
        Directory.CreateDirectory(output);
        var report=new JObject { ["schema"]="cf7-settings-candidate-recovery-probe.v1",["startedUtc"]=DateTime.UtcNow,
            ["pid"]=Environment.ProcessId,["candidateRoot"]=candidate,["fixtureSha256"]=Sha(fixturePath),
            ["slot"]=fixture["slot"],["journalDirectory"]=journalDirectory,
            ["evidenceKind"]="actual candidate Core, native SOL parser and recovery admission; no full game, UI rollback or writer execution" };
        object journal=null;
        try {
            string runtime=Path.Combine(candidate,"runtime");
            report["candidateMetadata"]=JObject.Parse(File.ReadAllText(Path.Combine(candidate,"runtime-build-metadata.v2.json")));
            AssemblyLoadContext.Default.Resolving+=(_,name)=> {
                string file=Path.Combine(runtime,name.Name+".dll");
                return File.Exists(file)?AssemblyLoadContext.Default.LoadFromAssemblyPath(file):null;
            };
            string corePath=Path.Combine(runtime,"CRAZYFLASHER7MercenaryEmpire.Core.dll");
            core=AssemblyLoadContext.Default.LoadFromAssemblyPath(corePath);
            if(!string.Equals(Path.GetFullPath(core.Location),corePath,StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Loaded Core path differs from selected candidate");
            report["loadedCorePath"]=core.Location;report["coreSha256"]=Sha(corePath);report["coreMvid"]=core.ManifestModule.ModuleVersionId;
            string parserPath=Path.Combine(runtime,"sol_parser.dll");
            report["nativeParserPath"]=parserPath;report["nativeParserSha256"]=Sha(parserPath);
            NativeLibrary.SetDllImportResolver(core,(name,_,_)=> {
                string file=Path.Combine(runtime,Path.GetFileName(name));
                return File.Exists(file)?NativeLibrary.Load(file):IntPtr.Zero;
            });
            object context=New("SettingsSaveContext",(string)fixture["installRoot"],(string)fixture["swfPath"],(string)fixture["slot"]);
            object nativeParser=New("NativeSolParser");
            object reader=New("SettingsRawSolReader",New("SolFileLocator"),nativeParser,Path.Combine(output,"raw"));
            object before=Call(reader,"Read",context);
            string source=(string)Field(before,"SourcePath"),sourceHash=(string)Field(before,"SourceSha256");
            if(source==null || sourceHash==null)throw new InvalidOperationException("The actual owned SOL source was not found");
            report["sourcePath"]=source;report["sourceBeforeSha256"]=sourceHash;
            report["rawError"]=Field(before,"Error")?.ToString();report["rawCanonical"]=Field(before,"Canonical")?.ToString();
            report["rawReceipt"]=(Field(before,"Receipt") as JToken)?.DeepClone();
            if(derivedParser) {
                // Derive an in-memory parser-boundary result from this actual native SOL.
                // Never rewrite the source SOL or claim this mutation was a native flush.
                object parsed=Call(nativeParser,"Parse",(string)Field(before,"SnapshotPath"));
                var data=(JObject)((JObject)Field(parsed,"Data")).DeepClone();
                data["test"]["ext"]["settingsReceipt"]["schema"]=2;
                data["test"]["others"]["设置"]["setGlobalVolume"]=42.5;
                parsed.GetType().GetField("Data",Members).SetValue(parsed,data);
                var proxy=(FixtureParserProxy)DispatchProxy.Create(core.GetType("CF7Launcher.Save.ISolParser",true),typeof(FixtureParserProxy));
                proxy.Result=parsed;
                string derived=Path.Combine(output,"derived-parser-result.json");File.WriteAllText(derived,data.ToString());
                report["parserBoundaryMutation"]=new JObject { ["case"]="future-receipt-noncanonical",["sourceNativeSha256"]=sourceHash,
                    ["derivedJsonSha256"]=Sha(derived),["nativeFlushClaimed"]=false };
                report["evidenceKind"]="actual candidate recovery code with native-SOL-derived parser-boundary injection; source SOL unchanged; no UI or writer execution";
                reader=New("SettingsRawSolReader",New("SolFileLocator"),proxy,Path.Combine(output,"derived-raw-copies"));
            }
            journal=New("SettingsWriteJournal",journalDirectory,null);
            object gate=New("SettingsRecoveryGate",journal,reader,(string)fixture["installRoot"],(string)fixture["swfPath"],null);
            object admission=Call(gate,"Inspect",(string)fixture["slot"]);
            report["allowed"]=(bool)Field(admission,"Allowed");report["error"]=Field(admission,"Error")?.ToString();
            report["confirmation"]=Field(admission,"RecoveryConfirmation")?.ToString();
            report["record"]=(Field(admission,"Record") as JToken)?.DeepClone();
            report["mayWrite"]=(bool)Call(gate,"MayWrite",(string)fixture["slot"]);
            report["bootstrap"]=(JToken)Call(admission,"BootstrapMetadata");
            object gateObservation=Field(admission,"Observation");
            report["gateRawError"]=Field(gateObservation,"Error")?.ToString();
            report["gateReceipt"]=(Field(gateObservation,"Receipt") as JToken)?.DeepClone();
            string after=Sha(source);report["sourceAfterSha256"]=after;
            if(after!=sourceHash)throw new InvalidOperationException("Read-only recovery changed the owned SOL source");
            report["status"]="observed";return 0;
        } catch(Exception error) {
            report["status"]="failed";report["exception"]=(error.InnerException??error).ToString();return 1;
        } finally {
            (journal as IDisposable)?.Dispose();report["completedUtc"]=DateTime.UtcNow;
            File.WriteAllText(Path.Combine(output,"report.json"),report.ToString());
            Console.WriteLine(output);
        }
    }
}
