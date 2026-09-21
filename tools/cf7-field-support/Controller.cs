using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO.Pipes;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

namespace Cf7.FieldSupport;

internal sealed class Controller : IDisposable
{
    private readonly CancellationTokenSource done=new();
    private readonly ConcurrentDictionary<string,TaskCompletionSource<Packet>> pending=new();
    private readonly SemaphoreSlim send=new(1,1);
    private readonly TcpClient socket=new();
    private SslStream? tls;
    private X509Certificate2? certificate;
    private readonly object diagnosticGate=new();
    private string endReason="",endError="";
    private DateTimeOffset? endedAt,lastReceivedAt,lastHeartbeatAt,finishRequestedAt;
    public object Diagnostic {get{lock(diagnosticGate)return new{endReason,endError,endedAt,lastReceivedAt,lastHeartbeatAt,finishRequestedAt};}}
    public string Fingerprint {get;private set;}="";
    public JsonElement Session {get;private set;}
    public bool Connected=>tls!=null&&!done.IsCancellationRequested;
    public async Task Connect(Ticket ticket,string developer,Action<string>? showFingerprint=null,Action<string>? progress=null)
    {
        if(ticket.Version!=1 || !Artifacts.IsHash(ticket.CertificateSha256)||!Artifacts.IsHash(ticket.Secret)||ticket.Port is <1 or >65535||DateTimeOffset.UtcNow>ticket.ExpiresAt)throw new InvalidDataException("票据无效或到期");
        certificate=Wire.Certificate();Fingerprint=Wire.Fingerprint(certificate);showFingerprint?.Invoke(Fingerprint);
        await socket.ConnectAsync(ticket.Host,ticket.Port,done.Token).AsTask().WaitAsync(TimeSpan.FromSeconds(45));
        tls=new SslStream(socket.GetStream(),false,(_,cert,_,_)=>cert!=null&&Wire.Fingerprint(cert)==ticket.CertificateSha256);
        await tls.AuthenticateAsClientAsync(new SslClientAuthenticationOptions{TargetHost="CF7 Field Support",ClientCertificates=new(){certificate},EnabledSslProtocols=SslProtocols.Tls12|SslProtocols.Tls13,CertificateRevocationCheckMode=X509RevocationMode.NoCheck},done.Token);
        progress?.Invoke("awaiting_target_consent");
        _=Read();
        var result=await Request("pair",new{ticket.SessionId,ticket.Secret,developer},180);
        Session=result;_ = Heartbeat();
    }
    private async Task Read()
    {
        try{while(!done.IsCancellationRequested){var reply=await Wire.Read(tls!,done.Token);lock(diagnosticGate)lastReceivedAt=DateTimeOffset.UtcNow;if(pending.TryRemove(reply.Id,out var completion))completion.TrySetResult(reply);}}
        catch(Exception ex){Close("receive_failed",ex);}
    }
    public async Task<JsonElement> Request(string method,object? data,int seconds=120,string? id=null)
    {
        if(tls==null||done.IsCancellationRequested)throw new IOException("没有活动连接");
        if(method=="finish")lock(diagnosticGate)finishRequestedAt=DateTimeOffset.UtcNow;
        string requestId=id??Wire.Id();var completion=new TaskCompletionSource<Packet>(TaskCreationOptions.RunContinuationsAsynchronously);
        if(!pending.TryAdd(requestId,completion))throw new InvalidOperationException("请求仍在等待");
        try
        {
            await Wire.Send(tls,new(requestId,method,Wire.Data(data)),send,done.Token);
            var response=await completion.Task.WaitAsync(TimeSpan.FromSeconds(seconds),done.Token);
            if(!response.Ok)throw new InvalidOperationException(response.Error);return response.Data;
        }
        catch(TimeoutException){throw new TimeoutException("请求超时，结果未知。requestId="+requestId+"；不要盲重放写操作。");}
        finally{pending.TryRemove(requestId,out _);}
    }
    private async Task Heartbeat()
    {
        try{while(!done.IsCancellationRequested){await Task.Delay(TimeSpan.FromSeconds(Wire.HeartbeatSeconds),done.Token);await Request("ping",new{},Wire.LostSeconds);lock(diagnosticGate)lastHeartbeatAt=DateTimeOffset.UtcNow;}}
        catch(Exception ex){Close("heartbeat_failed",ex);}
    }
    private void Close(string reason,Exception? error=null)
    {
        lock(diagnosticGate){if(endedAt!=null)return;endedAt=DateTimeOffset.UtcNow;endReason=reason;endError=error?.ToString()??"";}
        done.Cancel();socket.Dispose();
        foreach(var item in pending.Values)item.TrySetException(new IOException("连接中断；操作结果可能未知，请核对现场",error));
    }
    public void Dispose(){Close("controller_disposed");tls?.Dispose();certificate?.Dispose();}
}
internal static class Broker
{
    private static readonly SemaphoreSlim writer=new(1,1);
    [System.Runtime.InteropServices.DllImport("kernel32.dll",SetLastError=true)]
    private static extern bool GetNamedPipeClientProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle pipe,out uint pid);
    public static async Task Run(string ticketFile,string developer,string stateFile,string? selfTestPipe=null)
    {
        var ticket=LocalState.Read<Ticket>(ticketFile);
        if(selfTestPipe!=null&&(!System.Text.RegularExpressions.Regex.IsMatch(selfTestPipe,"^cf7-field-selftest-[a-f0-9]{32}$")||ticket.Host!="127.0.0.1"||ticket.Machine!=Environment.MachineName))
            throw new InvalidOperationException("隔离测试代理仅允许本机回环票据");
        string pipeName=selfTestPipe??LocalState.PipeName;
        using var unique=new Mutex(false,"Local\\"+pipeName);
        try{if(!unique.WaitOne(0))throw new InvalidOperationException("开发机已有连接代理，请先 status/finish");}catch(AbandonedMutexException){/* previous process ended; old connection cannot be restored */}
        using var controller=new Controller();
        try
        {
            await controller.Connect(ticket,developer,
                fp=>LocalState.Save(stateFile,new{state="connecting",fingerprint=Wire.ShortFingerprint(fp),pid=Environment.ProcessId}),
                phase=>LocalState.Save(stateFile,new{state=phase,fingerprint=Wire.ShortFingerprint(controller.Fingerprint),pid=Environment.ProcessId}));
            // Imported ticket is private and no longer needed after successful pairing.
            File.Delete(ticketFile);
            LocalState.Save(stateFile,new{state="connected",pid=Environment.ProcessId,session=controller.Session});
            using var quit=new CancellationTokenSource();
            _=Task.Run(async()=>{while(controller.Connected){await Task.Delay(1000);}quit.Cancel();});
            while(controller.Connected)
            {
                var pipe=new NamedPipeServerStream(pipeName,PipeDirection.InOut,8,PipeTransmissionMode.Byte,PipeOptions.Asynchronous|PipeOptions.CurrentUserOnly);
                try{await pipe.WaitForConnectionAsync(quit.Token);}catch{pipe.Dispose();break;}
                _=Serve(pipe,controller);
            }
            LocalState.Save(stateFile,new{state="ended",pid=Environment.ProcessId,session=controller.Session,diagnostic=controller.Diagnostic});
        }
        catch(Exception ex){LocalState.Save(stateFile,new{state="failed",error=ex.Message,pid=Environment.ProcessId,diagnostic=controller.Diagnostic});}
        // The process owns the mutex until exit. Do not ReleaseMutex after an await
        // on a different thread (Windows mutex ownership is thread-affine).
    }
    private static async Task Serve(NamedPipeServerStream pipe,Controller controller)
    {
        using(pipe)
        using(var timeout=new CancellationTokenSource(TimeSpan.FromMinutes(10)))
        {
            bool held=false;
            try
            {
                if(!GetNamedPipeClientProcessId(pipe.SafePipeHandle,out uint peerPid))throw new IOException("无法核对本地调用者");
                using(var peer=Process.GetProcessById((int)peerPid))
                    if(peer.SessionId!=Process.GetCurrentProcess().SessionId)throw new UnauthorizedAccessException("本地调用者不在当前 Windows 会话");
                var p=await Wire.Read(pipe,timeout.Token);
                if(p.Method is not ("status" or "operation" or "question" or "finish" or "cancel" or "ask.cancel"))
                {held=await writer.WaitAsync(0);if(!held)throw new InvalidOperationException("busy：另一个 Agent 正在使用修改通道");}
                object data=p.Data;JsonElement result;
                if(p.Method=="put.local") result=await Put(controller,p.Data.Text("path"));
                else if(p.Method=="get.local") result=await Get(controller,p.Data.Text("remote"),p.Data.Text("local"));
                else result=await controller.Request(p.Method,data,300,p.Id);
                await Wire.Send(pipe,new(p.Id,p.Method,result),new(1,1),timeout.Token);
            }
            catch(Exception ex){try{await Wire.Send(pipe,new("error","error",Wire.Data(null),false,ex.Message),new(1,1),timeout.Token);}catch{}}
            finally{if(held)writer.Release();}
        }
    }
    public static async Task<JsonElement> Call(string method,object data,string? id=null,string? selfTestPipe=null)
    {
        using var pipe=new NamedPipeClientStream(".",selfTestPipe??LocalState.PipeName,PipeDirection.InOut,PipeOptions.Asynchronous);
        try{await pipe.ConnectAsync(3000);}
        catch(TimeoutException){throw new IOException("当前没有可用的活动连接。配对期间请查看 connect 返回的状态文件，并等待 B 端点击允许；已结束的会话需要新票据。");}
        using var timeout=new CancellationTokenSource(TimeSpan.FromMinutes(10));
        await Wire.Send(pipe,new(id??Wire.Id(),method,Wire.Data(data)),new(1,1),timeout.Token);
        var answer=await Wire.Read(pipe,timeout.Token);if(!answer.Ok)throw new IOException(answer.Error);return answer.Data;
    }
    private static async Task<JsonElement> Put(Controller c,string path)
    {
        LocalState.Plain(path);string id=Wire.Id();long size=new FileInfo(path).Length;string hash=Wire.FileHash(path);
        await c.Request("put.begin",new{id,name=Path.GetFileName(path),size,sha256=hash});
        using var file=File.OpenRead(path);byte[] bytes=new byte[Wire.Chunk];int n;long offset=0;
        while((n=await file.ReadAsync(bytes))>0){await c.Request("put.chunk",new{id,offset,bytes=Convert.ToBase64String(bytes,0,n)},180);offset+=n;}
        return await c.Request("put.complete",new{id},300);
    }
    private static async Task<JsonElement> Get(Controller c,string remote,string local)
    {
        LocalState.Plain(local);if(File.Exists(local)||File.Exists(local+".partial"))throw new IOException("本地目标已存在，拒绝覆盖");
        var info=await c.Request("get.info",new{path=remote},300);long size=info.Number("size");
        if(size>2L*1024*1024*1024)throw new IOException("单文件超过 2 GiB 上限");
        using(var file=new FileStream(local+".partial",FileMode.CreateNew,FileAccess.Write,FileShare.None))
        {
            while(file.Position<size){var part=await c.Request("get.chunk",new{path=remote,offset=file.Position});byte[] bytes=Convert.FromBase64String(part.Text("bytes"));if(bytes.Length==0||file.Position+bytes.Length>size)throw new IOException("下载长度变化");await file.WriteAsync(bytes);}
            file.Flush(true);
        }
        if(Wire.FileHash(local+".partial")!=info.Text("sha256"))throw new IOException("下载哈希不符，保留 partial");
        File.Move(local+".partial",local);return Wire.Data(new{path=local,sha256=info.Text("sha256"),size});
    }
}
