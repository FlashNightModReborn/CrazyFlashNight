using System;
using System.Globalization;
using System.IO;
using System.Diagnostics;
using System.Security.Cryptography;
using Newtonsoft.Json;
using System.Reflection;
using Xunit.Sdk;
using System.Runtime.InteropServices;
namespace CF7Launcher.Tests.Guardian {
 [AttributeUsage(AttributeTargets.Class|AttributeTargets.Method)]
 public sealed class ResourceCaseGuardAttribute:BeforeAfterTestAttribute {
  public override void Before(MethodInfo m){FixtureResourceGuard.Before("case.begin "+m.Name);}
  public override void After(MethodInfo m){FixtureResourceGuard.Before("case.end "+m.Name);}
 }
 internal static class FixtureResourceGuard {
  [StructLayout(LayoutKind.Sequential)] struct Last {public uint Size,Tick;}
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref Last x);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  static FixtureResourceGuard(){
   string dir=Environment.GetEnvironmentVariable("CF7_EVIDENCE_ROOT");
   if(string.IsNullOrEmpty(dir))throw new InvalidOperationException("Missing evidence root");
   Directory.CreateDirectory(dir);
   var core=typeof(CF7Launcher.Guardian.WindowManager).Assembly;var tests=typeof(FixtureResourceGuard).Assembly;
   File.WriteAllText(Path.Combine(dir,"loaded-binaries.json"),JsonConvert.SerializeObject(new{
    utc=DateTimeOffset.UtcNow,pid=Environment.ProcessId,processStartUtc=Process.GetCurrentProcess().StartTime.ToUniversalTime(),runtime=Environment.Version.ToString(),
    corePath=core.Location,coreSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(core.Location))),coreMvid=core.ManifestModule.ModuleVersionId,
    testsPath=tests.Location,testsSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(tests.Location))),testsMvid=tests.ManifestModule.ModuleVersionId},Formatting.Indented));
  }
  static readonly object FileGate=new object();
  internal static void SaveTrace(string batch){
   string dir=Environment.GetEnvironmentVariable("CF7_EVIDENCE_ROOT");
   if(string.IsNullOrEmpty(dir))throw new InvalidOperationException("Missing evidence directory");
   lock(FileGate){Directory.CreateDirectory(dir);File.AppendAllText(Path.Combine(dir,"FocusTrace.jsonl"),batch.Replace("[FocusTrace] ","").TrimEnd('\r','\n')+Environment.NewLine);}
  }
  internal static void Before(string boundary,IntPtr target=default){
   string raw=Environment.GetEnvironmentVariable("CF7_TEST_WINDOW_END"),tick=Environment.GetEnvironmentVariable("CF7_TEST_INPUT_TICK");
   if(!DateTimeOffset.TryParse(raw,CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal,out var end)||!uint.TryParse(tick,out uint anchor))throw new OperationCanceledException("No acknowledged resource window/input anchor");
   var x=new Last{Size=(uint)Marshal.SizeOf<Last>()};
   bool expired=DateTimeOffset.UtcNow>=end,inputReadSucceeded=GetLastInputInfo(ref x);
   if(expired||!inputReadSucceeded||x.Tick!=anchor)throw new OperationCanceledException("Resource qualification cancelled at "+boundary
    +" expired="+expired+" inputReadSucceeded="+inputReadSucceeded+" expectedTick="+anchor+" observedTick="+x.Tick);
   if(target!=IntPtr.Zero&&(!IsWindow(target)||GetWindowThreadProcessId(target,out uint pid)==0||pid!=(uint)Environment.ProcessId))throw new OperationCanceledException("Owned HWND proof failed at "+boundary);
   Console.WriteLine("RESOURCE_BOUNDARY "+DateTimeOffset.UtcNow.ToString("O")+" "+boundary+" tick="+x.Tick+" hwnd="+target.ToInt64()+" pid="+Environment.ProcessId);
  }
 }
}
