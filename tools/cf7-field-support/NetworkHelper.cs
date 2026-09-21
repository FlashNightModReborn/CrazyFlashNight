using System.Diagnostics;
using System.Text.Json;

namespace Cf7.FieldSupport;

internal sealed class NetworkHelper : IDisposable
{
    private Process? process;
    private string? privateState;
    private int disposed;
    private readonly TaskCompletionSource<JsonElement> ready = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public string? AuthorizationUrl { get; private set; }
    public JsonElement? Route { get; private set; }
    public event Action? Changed;
    public async Task<JsonElement> Start(string state, int localPort, string? target, CancellationToken ct)
    {
        LocalState.PrivateDirectory(state);
        privateState=Path.GetFullPath(state);
        var psi=new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory,"cf7-network.exe")){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true};
        foreach(var a in new[]{"--state",state,"--hostname","cf7-support-"+Wire.Id()[..8]}) psi.ArgumentList.Add(a);
        psi.ArgumentList.Add(target==null?"--local":"--target"); psi.ArgumentList.Add(target??("127.0.0.1:"+localPort));
        process=Process.Start(psi)??throw new IOException("组网组件启动失败");
        _=Task.Run(async()=>
        {
            try
            {
                while(await process.StandardOutput.ReadLineAsync() is {} line)
                {
                    using var doc=JsonDocument.Parse(line); var data=doc.RootElement;
                    switch(data.Text("event"))
                    {
                        case "authorization": AuthorizationUrl=data.Text("url"); Changed?.Invoke(); break;
                        case "ready": AuthorizationUrl=null; ready.TrySetResult(data.Clone()); Changed?.Invoke(); break;
                        case "route": Route=data.Clone(); Changed?.Invoke(); break;
                        case "error": ready.TrySetException(new IOException(data.Text("message"))); break;
                    }
                }
                ready.TrySetException(new IOException("组网组件已退出"));
            }
            catch(Exception ex){ready.TrySetException(ex);}
        });
        // Do not persist helper stderr: upstream logs may contain enrollment URLs.
        _=Task.Run(async()=>{try {while(await process.StandardError.ReadLineAsync() is not null) {}} catch {}});
        using var registration=ct.Register(Dispose);
        return await ready.Task.WaitAsync(ct);
    }
    public void Dispose()
    {
        if(Interlocked.Exchange(ref disposed,1)!=0)return;
        try {if(process is {HasExited:false}) {process.StandardInput.WriteLine("stop"); process.StandardInput.Close(); if(!process.WaitForExit(1500)) {process.Kill(true);process.WaitForExit(3000);}}} catch {}
        try
        {
            // Only this helper's explicitly created private directory, never its parent.
            if(privateState!=null&&Path.GetFileName(privateState)=="network-private"&&(process==null||process.HasExited))
            {LocalState.Plain(privateState);if(Directory.Exists(privateState))Directory.Delete(privateState,true);}
        }
        catch{ /* The UI still shows the session directory for residual inspection. */ }
    }
}
