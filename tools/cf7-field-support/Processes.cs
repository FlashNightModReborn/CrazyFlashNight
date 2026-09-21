using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Text;

namespace Cf7.FieldSupport;

internal sealed class ProcessJob : IDisposable
{
    private readonly SafeFileHandle handle;
    [StructLayout(LayoutKind.Sequential)] private struct Basic { public long ProcessTime, JobTime; public uint Flags; public UIntPtr Min, Max; public uint Active; public UIntPtr Affinity; public uint Priority, Scheduling; }
    [StructLayout(LayoutKind.Sequential)] private struct Counters { public ulong A, B, C, D, E, F; }
    [StructLayout(LayoutKind.Sequential)] private struct Extended { public Basic Basic; public Counters Io; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern SafeFileHandle CreateJobObject(IntPtr attributes, string? name);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool SetInformationJobObject(SafeFileHandle job, int type, ref Extended info, uint length);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool TerminateJobObject(SafeFileHandle job, uint code);
    public ProcessJob()
    {
        handle = CreateJobObject(IntPtr.Zero, null);
        var info = new Extended { Basic = new Basic { Flags = 0x2000 } };
        if (handle.IsInvalid || !SetInformationJobObject(handle, 9, ref info, (uint)Marshal.SizeOf<Extended>()))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    public void Assign(Process process)
    {
        if (!AssignProcessToJobObject(handle, process.Handle)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    public void Stop() { if (!handle.IsClosed) TerminateJobObject(handle, 125); }
    public void Dispose() => handle.Dispose();
}
internal sealed class ExperimentOperation
{
    public string Id { get; }
    public string Kind { get; }
    public string State { get; private set; } = "running";
    public int? ExitCode { get; private set; }
    public int? Pid { get; private set; }
    public DateTimeOffset StartedAt { get; } = DateTimeOffset.UtcNow;
    public string? Error { get; private set; }
    private readonly object gate = new();
    private readonly StringBuilder tail = new();
    private ProcessJob? job;
    private Process? process;
    private volatile bool stopRequested;
    public Task Completion { get; private set; } = Task.CompletedTask;
    public ExperimentOperation(string id, string kind) { Id=id; Kind=kind; }
    public object Snapshot(bool includeOutput=true) { lock(gate) return new {Id,Kind,State,ExitCode,Pid,StartedAt,Error,output=includeOutput?tail.ToString():null}; }
    public void Start(string script, string directory, CancellationToken session, Action changed, int timeoutSeconds = 1800)
    {
        Completion = Run();
        async Task Run()
        {
            string folder=Path.Combine(directory,"operations",Id); Directory.CreateDirectory(folder);
            string scriptFile=Path.Combine(folder,"command.ps1"), go=Path.Combine(folder,"go");
            File.WriteAllText(scriptFile, script, new UTF8Encoding(true));
            LocalState.Save(Path.Combine(folder,"operation.json"), Snapshot());
            try
            {
                session.ThrowIfCancellationRequested();
                job = new ProcessJob();
                var psi = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute=false, CreateNoWindow=true, RedirectStandardOutput=true, RedirectStandardError=true, WorkingDirectory=directory, StandardOutputEncoding=Encoding.UTF8, StandardErrorEncoding=Encoding.UTF8 };
                foreach (var a in new[]{"worker","--gate",go,"--script",scriptFile}) psi.ArgumentList.Add(a);
                process = Process.Start(psi) ?? throw new IOException("进程未启动"); Pid=process.Id;
                try { job.Assign(process); } catch { process.Kill(true); throw; }
                session.ThrowIfCancellationRequested(); if(stopRequested){job.Stop();throw new OperationCanceledException();}File.WriteAllText(go,"go");
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(session); timeout.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));
                using var registration = timeout.Token.Register(() => job.Stop());
                async Task Drain(StreamReader reader, string prefix)
                {
                    char[] buffer=new char[2048]; int count;
                    using var log=new StreamWriter(Path.Combine(folder,prefix+".txt"),false,Encoding.UTF8);
                    long written=0;
                    while((count=await reader.ReadAsync(buffer))>0)
                    {
                        if(written<4*1024*1024) { await log.WriteAsync(buffer.AsMemory(0,count)); written+=count; }
                        lock(gate) { tail.Append(buffer,0,count); if(tail.Length>24000) tail.Remove(0,tail.Length-24000); }
                    }
                }
                await Task.WhenAll(Drain(process.StandardOutput,"stdout"),Drain(process.StandardError,"stderr"),process.WaitForExitAsync());
                lock(gate) { ExitCode=process.ExitCode; State=timeout.IsCancellationRequested||stopRequested ? "cancelled_or_unknown" : (ExitCode==0 ? "completed" : "failed"); }
            }
            catch(Exception ex) { lock(gate) { State="failed_or_unknown"; Error=ex.Message; } job?.Stop(); }
            finally { LocalState.Save(Path.Combine(folder,"operation.json"),Snapshot()); changed(); }
        }
    }
    public void Stop() {stopRequested=true;job?.Stop();}
    public void Dispose() { job?.Stop(); job?.Dispose(); process?.Dispose(); }
    public static int Worker(string go, string script)
    {
        var deadline=DateTime.UtcNow.AddSeconds(15);
        while(!File.Exists(go) && DateTime.UtcNow<deadline) Thread.Sleep(25);
        if(!File.Exists(go)) return 126;
        var psi=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell","v1.0","powershell.exe")){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
        psi.Environment.Remove("PSModulePath");
        foreach(var a in new[]{"-NoLogo","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",script}) psi.ArgumentList.Add(a);
        using var process=Process.Start(psi)!;
        var output=process.StandardOutput.BaseStream.CopyToAsync(Console.OpenStandardOutput());
        var error=process.StandardError.BaseStream.CopyToAsync(Console.OpenStandardError());
        process.WaitForExit();Task.WhenAll(output,error).GetAwaiter().GetResult();return process.ExitCode;
    }
}
