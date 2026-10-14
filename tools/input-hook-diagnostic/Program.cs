using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.Tasks;

// Hook registration on one self-owned, windowless child thread. Never uses a global hook.
internal static class Program
{
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X,Y; }
    [StructLayout(LayoutKind.Sequential)] private struct Message { public IntPtr Hwnd;public uint Id;public UIntPtr W;public IntPtr L;public uint Time;public Point Point;public uint Private; }
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr OpenThread(uint access,bool inherit,uint thread);
    [DllImport("kernel32.dll")] private static extern uint GetProcessIdOfThread(IntPtr thread);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern IntPtr LoadLibraryExW(string file,IntPtr reserved,uint flags);
    [DllImport("kernel32.dll",CharSet=CharSet.Ansi,SetLastError=true)] private static extern IntPtr GetProcAddress(IntPtr module,string name);
    [DllImport("kernel32.dll",SetLastError=true)] private static extern bool FreeLibrary(IntPtr module);
    [DllImport("user32.dll")] private static extern bool PeekMessageW(out Message message,IntPtr hwnd,uint min,uint max,uint remove);
    [DllImport("user32.dll",SetLastError=true)] private static extern int GetMessageW(out Message message,IntPtr hwnd,uint min,uint max);
    [DllImport("user32.dll",SetLastError=true)] private static extern bool PostThreadMessageW(uint thread,uint message,UIntPtr w,IntPtr l);
    [DllImport("user32.dll",SetLastError=true)] private static extern IntPtr SetWindowsHookExW(int kind,IntPtr callback,IntPtr module,uint thread);
    [DllImport("user32.dll",SetLastError=true)] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    private static string Sha(string file)=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))).ToLowerInvariant();
    private static object Probe(string file,uint thread,string expected)
    {
        if(Sha(file)!=expected)throw new InvalidOperationException("Hook DLL bytes drifted");
        IntPtr module=IntPtr.Zero,hook=IntPtr.Zero;
        int loadError=0,exportError=0,hookError=0;bool loaded=false,exported=false,installed=false,unhooked=false,freed=false;
        try {
            module=LoadLibraryExW(file,IntPtr.Zero,8);loaded=module!=IntPtr.Zero;
            if(!loaded)loadError=Marshal.GetLastWin32Error();
            IntPtr callback=loaded?GetProcAddress(module,"InputHook"):IntPtr.Zero;exported=callback!=IntPtr.Zero;
            if(loaded&&!exported)exportError=Marshal.GetLastWin32Error();
            if(exported) { hook=SetWindowsHookExW(3,callback,module,thread);installed=hook!=IntPtr.Zero;if(!installed)hookError=Marshal.GetLastWin32Error(); }
        } finally {
            if(hook!=IntPtr.Zero)unhooked=UnhookWindowsHookEx(hook);
            if(module!=IntPtr.Zero)freed=FreeLibrary(module);
        }
        if(installed&&!unhooked)throw new InvalidOperationException("Owned thread hook was not released");
        return new {path=file,pathLength=file.Length,sha256=Sha(file),loaded,loadError,exported,exportError,installed,hookError,unhooked,freed};
    }
    private static async Task<int> Main(string[] args)
    {
        if(args.Length==2&&args[0]=="--owned-target") {
            PeekMessageW(out _,IntPtr.Zero,0,0,0);
            Console.WriteLine(JsonSerializer.Serialize(new {pid=Environment.ProcessId,thread=GetCurrentThreadId(),nonce=args[1],is64Bit=Environment.Is64BitProcess}));
            while(GetMessageW(out _,IntPtr.Zero,0,0)>0) { }
            return 0;
        }
        if(args.Length!=3) {Console.Error.WriteLine("formal-bridge candidate-bridge fresh-evidence-directory");return 2;}
        string formal=Path.GetFullPath(args[0]),candidate=Path.GetFullPath(args[1]),output=Path.GetFullPath(args[2]);
        if(Directory.Exists(output))throw new ArgumentException("Evidence directory must be fresh");
        if(!Environment.Is64BitProcess||Sha(formal)!=Sha(candidate))throw new InvalidOperationException("Compare equal x64 input bridge bytes only");
        Directory.CreateDirectory(output);
        var report=new Dictionary<string,object> { ["schema"]="cf7-owned-thread-hook-path-diagnostic.v1",["startedUtc"]=DateTime.UtcNow,
            ["scope"]="one self-owned windowless child thread; no global hook, Flash, UI or saves; copied path is diagnostic only" };
        var rows=new List<object>();report["paths"]=rows;Process child=null;uint thread=0;IntPtr ownedThread=IntPtr.Zero;
        try {
            string nonce=Guid.NewGuid().ToString("N");
            string temporary=Path.Combine(Path.GetTempPath(),"cf7-hook-"+nonce);Directory.CreateDirectory(temporary);
            string shortFile=Path.Combine(temporary,"FlashInputBridge.dll");File.Copy(candidate,shortFile,false);
            report["retainedShortCopy"]=shortFile;
            string executable=Environment.ProcessPath;
            var start=new ProcessStartInfo(executable) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
            if(Path.GetFileNameWithoutExtension(executable).Equals("dotnet",StringComparison.OrdinalIgnoreCase))
                start.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
            start.ArgumentList.Add("--owned-target");start.ArgumentList.Add(nonce);
            child=Process.Start(start);
            string line=await child.StandardOutput.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(10));
            using var hello=JsonDocument.Parse(line);var root=hello.RootElement;
            if(root.GetProperty("pid").GetInt32()!=child.Id||root.GetProperty("nonce").GetString()!=nonce||!root.GetProperty("is64Bit").GetBoolean())
                throw new InvalidOperationException("Child ownership handshake mismatch");
            thread=root.GetProperty("thread").GetUInt32();
            ownedThread=OpenThread(0x800,false,thread);
            if(ownedThread==IntPtr.Zero||GetProcessIdOfThread(ownedThread)!=(uint)child.Id)
                throw new InvalidOperationException("Child thread ownership could not be pinned");
            report["child"]=new {pid=child.Id,thread,birthUtc=child.StartTime.ToUniversalTime(),executable};
            foreach(string file in new[] {formal,candidate,shortFile,formal}) {
                if(child.HasExited)throw new InvalidOperationException("Owned target exited before hook registration");
                rows.Add(Probe(file,thread,Sha(formal)));
            }
            report["status"]="observed";return 0;
        } catch(Exception error) {report["status"]="failed";report["error"]=error.ToString();return 1;}
        finally {
            if(child!=null) {
                bool quitPosted=thread!=0&&PostThreadMessageW(thread,0x12,UIntPtr.Zero,IntPtr.Zero);
                try {await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));}
                catch {if(!child.HasExited){child.Kill();await child.WaitForExitAsync();report["ownedChildForcedStop"]=true;}}
                report["cleanup"]=new {quitPosted,exited=child.HasExited,exitCode=child.ExitCode};child.Dispose();
            }
            if(ownedThread!=IntPtr.Zero)CloseHandle(ownedThread);
            report["completedUtc"]=DateTime.UtcNow;
            File.WriteAllText(Path.Combine(output,"report.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions {WriteIndented=true}));
            Console.WriteLine(output);
        }
    }
}
