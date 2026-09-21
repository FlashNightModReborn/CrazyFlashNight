using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;

namespace Cf7.FieldSupport;

internal sealed class Question
{
    public string Id {get;init;}=Wire.Id();
    public string Text {get;init;}="";
    public string[] Options {get;init;}=[];
    public DateTimeOffset Deadline {get;init;}
    public string State {get;set;}="pending";
    public string Answer {get;set;}="";
}
internal sealed class SupportSession : IDisposable
{
    public string Id {get;}=Wire.Id();
    public string Root {get;}
    public string Game {get;}
    public string State {get;private set;}="waiting";
    public string EndReason {get;private set;}="";
    public DateTimeOffset? EndedAt {get;private set;}
    public DateTimeOffset? ConnectedAt {get;private set;}
    public DateTimeOffset ExpiresAt {get;}
    public Ticket? Ticket {get;private set;}
    public Question? Question {get;private set;}
    public NetworkHelper? Network {get;private set;}
    public string? PairFingerprint {get;private set;}
    public string Developer {get;private set;}="";
    public string LastConnectionError {get;private set;}="";
    public event Action? Changed;
    public readonly ConcurrentDictionary<string,ExperimentOperation> Operations=new();
    public readonly Artifacts Artifacts;
    private readonly CancellationTokenSource lifetime=new();
    private readonly X509Certificate2 certificate=Wire.Certificate();
    private readonly TcpListener listener=new(IPAddress.Loopback,0);
    private readonly SemaphoreSlim mutation=new(1,1);
    private readonly object stateGate=new();
    private readonly object recordGate=new();
    private string journalError="";
    private readonly ConcurrentDictionary<string,(string hash,Lazy<Task<Packet>> result)> requests=new();
    private readonly Dictionary<string,Question> questions=new();
    private TaskCompletionSource<bool>? pairDecision;
    private TcpClient? activeSocket;
    private bool paired;
    private int admission;
    private long lastMessage=Stopwatch.GetTimestamp();
    private readonly long began=Stopwatch.GetTimestamp();
    private readonly TimeSpan duration;
    private readonly DateTime ownerStartUtc=Process.GetCurrentProcess().StartTime.ToUniversalTime();
    public SupportSession(string game,int minutes,string? testRoot=null)
    {
        if(minutes is < 1 or > 120) throw new ArgumentOutOfRangeException(nameof(minutes));
        Game=Path.GetFullPath(game);duration=TimeSpan.FromMinutes(minutes);ExpiresAt=DateTimeOffset.UtcNow+duration;
        Root=testRoot??Path.Combine(LocalState.Root,"sessions",Id);LocalState.PrivateDirectory(Root);
        Artifacts=new(Root,Game,lifetime.Token);Save();
    }
    public async Task Start(bool network,CancellationToken ct=default)
    {
        listener.Start();_ = Accept();_ = Monitor();
        int port=((IPEndPoint)listener.LocalEndpoint).Port;string host="127.0.0.1";
        if(network)
        {
            Network=new();Network.Changed+=()=>Changed?.Invoke();
            using var linked=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token,ct);
            var result=await Network.Start(Path.Combine(Root,"network-private"),port,null,linked.Token);
            host=result.Text("host");port=(int)result.Number("port");
        }
        Ticket=new(1,Id,host,port,Wire.Fingerprint(certificate),Convert.ToHexString(RandomNumberGenerator.GetBytes(32)),DateTimeOffset.UtcNow.AddMinutes(10),Environment.MachineName);
        Changed?.Invoke();
    }
    private async Task Accept()
    {
        try
        {
            while(!lifetime.IsCancellationRequested)
            {
                var client=await listener.AcceptTcpClientAsync(lifetime.Token);
                if(Interlocked.CompareExchange(ref admission,1,0)!=0){client.Dispose();continue;}
                _=Handle(client);
            }
        }
        catch(OperationCanceledException){} catch(SocketException){} catch(ObjectDisposedException){}
    }
    private async Task Handle(TcpClient socket)
    {
        bool authorized=false;var send=new SemaphoreSlim(1,1);
        try
        {
            using(socket)
            using(var tls=new SslStream(socket.GetStream(),false,(_,cert,_,_)=>cert!=null))
            {
                using var initial=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);initial.CancelAfter(TimeSpan.FromMinutes(3));
                await tls.AuthenticateAsServerAsync(new SslServerAuthenticationOptions{ServerCertificate=certificate,ClientCertificateRequired=true,EnabledSslProtocols=SslProtocols.Tls12|SslProtocols.Tls13,CertificateRevocationCheckMode=X509RevocationMode.NoCheck},initial.Token);
                var hello=await Wire.Read(tls,initial.Token);
                if(hello.Method!="pair"||Ticket==null||paired||DateTimeOffset.UtcNow>Ticket.ExpiresAt||hello.Data.Text("sessionId")!=Id||!CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(hello.Data.Text("secret")),Encoding.UTF8.GetBytes(Ticket.Secret))) throw new AuthenticationException("配对票据无效、已消费或到期");
                string fingerprint=Wire.Fingerprint(tls.RemoteCertificate!);
                lock(stateGate)
                {
                    PairFingerprint=fingerprint;Developer=hello.Data.Text("developer");
                    if(Developer.Length is <1 or >80) throw new InvalidDataException("维护者名称长度无效");
                    pairDecision=new(TaskCreationOptions.RunContinuationsAsynchronously);
                }
                Changed?.Invoke();
                if(!await pairDecision.Task.WaitAsync(initial.Token)) throw new AuthenticationException("目标端拒绝配对");
                lock(stateGate)
                {
                    lifetime.Token.ThrowIfCancellationRequested();if(paired||Ticket==null||DateTimeOffset.UtcNow>Ticket.ExpiresAt)throw new AuthenticationException("票据已消费或到期");
                    paired=true;authorized=true;State="active";ConnectedAt=DateTimeOffset.UtcNow;activeSocket=socket;lastMessage=Stopwatch.GetTimestamp();PairFingerprint=null;
                }
                Save();Changed?.Invoke();
                await Wire.Send(tls,new(hello.Id,"pair",Wire.Data(new{sessionId=Id,ExpiresAt,workspace=Root,Game,developer=Developer})),send,lifetime.Token);
                while(!lifetime.IsCancellationRequested)
                {
                    var request=await Wire.Read(tls,lifetime.Token);Interlocked.Exchange(ref lastMessage,Stopwatch.GetTimestamp());
                    if(request.Method=="ping") {await Wire.Send(tls,new(request.Id,"ping",Wire.Data(new{State})),send,lifetime.Token);continue;}
                    _=Respond(request,tls,send);
                }
            }
        }
        catch(Exception ex) { LastConnectionError=ex.GetType().Name+": "+ex.Message; }
        finally
        {
            if(authorized) Stop("connection_closed");
            else {PairFingerprint=null;pairDecision?.TrySetResult(false);Changed?.Invoke();}
            Interlocked.Exchange(ref admission,0);
        }
    }
    private async Task Respond(Packet request,SslStream tls,SemaphoreSlim send)
    {
        try
        {
            if(request.Id.Length is <1 or >64) throw new InvalidDataException("请求 ID 无效");
            string hash=Wire.Hash(Encoding.UTF8.GetBytes(request.Method+request.Data.GetRawText()));
            bool cache=request.Method is "exec" or "replace" or "restore" or "candidate.import" or "candidate.launch" or "ask";
            if(requests.Count>=1024 && cache&&!requests.ContainsKey(request.Id)) throw new InvalidOperationException("本次操作数量已达上限，请结束后开启新会话");
            Packet response;
            if(cache)
            {
                var entry=requests.GetOrAdd(request.Id,_=>(hash,new Lazy<Task<Packet>>(()=>Dispatch(request),LazyThreadSafetyMode.ExecutionAndPublication)));
                response=entry.hash==hash?await entry.result.Value:new Packet(request.Id,request.Method,Wire.Data(null),false,"相同请求 ID 的内容发生改变");
            }
            else response=await Dispatch(request);
            await Wire.Send(tls,response,send,lifetime.Token);
            if(request.Method=="finish" && response.Ok) Stop("developer_finished");
        }
        catch(Exception ex)
        {try {await Wire.Send(tls,new(request.Id,request.Method,Wire.Data(null),false,ex.Message),send,lifetime.Token);}catch{}}
    }
    private async Task<Packet> Dispatch(Packet packet)
    {
        bool held=false;
        string? record=null;
        try
        {
            lifetime.Token.ThrowIfCancellationRequested();
            if(State!="active") throw new InvalidOperationException("会话已结束");
            bool mutable=packet.Method is not ("status" or "operation" or "question" or "get.info" or "get.chunk" or "finish" or "cancel" or "ask.cancel");
            if(mutable) {if(journalError.Length>0)throw new IOException("记录写入失败，拒绝继续修改现场："+journalError);held=await mutation.WaitAsync(0);if(!held)throw new InvalidOperationException("busy：另一个修改正在执行");}
            if(mutable&&packet.Method!="put.chunk")
            {
                if(!System.Text.RegularExpressions.Regex.IsMatch(packet.Id,"^[A-Za-z0-9_-]{1,64}$"))throw new InvalidDataException("修改请求 ID 格式无效");
                record=Path.Combine(Root,"requests",packet.Id+".json");
                LocalState.Save(record,new{requestId=packet.Id,method=packet.Method,state="accepted_result_unknown",requestHash=Wire.Hash(Encoding.UTF8.GetBytes(packet.Data.GetRawText())),time=DateTimeOffset.UtcNow});
            }
            object? result=await Task.Run(()=>Execute(packet),lifetime.Token);
            if(record!=null)LocalState.Save(record,new{requestId=packet.Id,method=packet.Method,state="responded",result,time=DateTimeOffset.UtcNow});
            Save();Changed?.Invoke();return new(packet.Id,packet.Method,Wire.Data(result));
        }
        catch(Exception ex){if(record!=null)try{LocalState.Save(record,new{requestId=packet.Id,method=packet.Method,state="failed_or_unknown",error=ex.Message});}catch{}return new(packet.Id,packet.Method,Wire.Data(null),false,ex.Message);}
        finally{if(held)mutation.Release();}
    }
    private object? Execute(Packet request)
    {
        lifetime.Token.ThrowIfCancellationRequested();
        var d=request.Data;
        switch(request.Method)
        {
            case "status": return Snapshot();
            case "finish": return new{state="ending"};
            case "operation": return Operations[d.Text("id")].Snapshot();
            case "cancel": Operations[d.Text("id")].Stop();return new{state="cancellation_requested"};
            case "exec":
                if(Operations.Values.Any(x=>x.State=="running"))throw new InvalidOperationException("已有命令运行；请查询或取消后再执行");
                string script=d.Text("script");if(script.Length>256*1024)throw new InvalidDataException("脚本过大");
                return StartOperation(request.Id,"exec","[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)\n$ErrorActionPreference='Stop'\n"+script,(int)(d.TryGetProperty("timeoutSeconds",out var t)?Math.Clamp(t.GetInt32(),1,3600):1800));
            case "put.begin":return Artifacts.Begin(d);
            case "put.chunk":return Artifacts.Chunk(d);
            case "put.complete":return Artifacts.Complete(d);
            case "get.info":
                string path=Path.GetFullPath(d.Text("path"));LocalState.Plain(path);DenyPrivate(path);
                return new{size=new FileInfo(path).Length,sha256=Wire.FileHash(path)};
            case "get.chunk":
                string p=Path.GetFullPath(d.Text("path"));LocalState.Plain(p);DenyPrivate(p);long offset=d.Number("offset");
                using(var file=File.OpenRead(p)){if(offset<0||offset>file.Length)throw new InvalidDataException("偏移越界");file.Position=offset;byte[] bytes=new byte[Wire.Chunk];int n=file.Read(bytes);return new{offset,bytes=Convert.ToBase64String(bytes,0,n)};}
            case "replace": EnsureNoRunning();return Artifacts.Replace(d);
            case "restore": EnsureNoRunning();return Artifacts.Restore(d.Text("id"));
            case "candidate.import":
                EnsureNoRunning();return new{path=Artifacts.ImportCandidate(d.Text("uploadId")),state="imported_not_executed"};
            case "candidate.launch":
                EnsureNoRunning();Artifacts.RequireGameStopped(Game);string candidate=Path.GetFullPath(d.Text("path"));
                if(!candidate.StartsWith(Path.Combine(Game,"tmp","runtime-candidates","v2")+"\\",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("候选不在规范目录");
                var identity=Candidate.Validate(candidate,false);
                string entry=LocalState.Under(Game,"automation/start.ps1");
                string expected=d.Text("startScriptSha256").ToUpperInvariant();if(Wire.FileHash(entry)!=expected)throw new IOException("候选入口脚本版本不同，请先核对两机源码");
                string quote(string s)=>"'"+s.Replace("'","''")+"'";
                string launch="$ErrorActionPreference='Stop'\n& "+quote(entry)+" -CandidateRoot "+quote(candidate)+"\nif (!$?) { exit 1 }\n";
                return new{operation=StartOperation(request.Id,"candidate.launch",launch,180),expected=identity,state="launch_requested"};
            case "ask":
                lock(stateGate)
                {
                    RefreshQuestion();if(Question?.State=="pending")throw new InvalidOperationException("已有未回答问题");
                    if(questions.Count>=128)throw new InvalidOperationException("本次问答数量已达上限，请结束后重新开启");
                    string text=d.Text("text");if(text.Length>4000)throw new InvalidDataException("问题过长");
                    string[] options=d.TryGetProperty("options",out var opts)?opts.EnumerateArray().Select(x=>x.GetString()??"").ToArray():[];
                    if(options.Length>6||options.Any(x=>x.Length>100))throw new InvalidDataException("选项过多或过长");
                    Question=new(){Id=request.Id,Text=text,Options=options,Deadline=DateTimeOffset.UtcNow.AddSeconds(d.TryGetProperty("timeoutSeconds",out var time)?Math.Clamp(time.GetInt32(),10,1800):600)};
                    questions.Add(Question.Id,Question);return Question;
                }
            case "question":lock(stateGate){RefreshQuestion();return questions[d.Text("id")];}
            case "ask.cancel":lock(stateGate){var q=questions[d.Text("id")];if(q.State=="pending")q.State="cancelled";return q;}
            default:throw new InvalidDataException("未知命令："+request.Method);
        }
    }
    private void DenyPrivate(string path)
    {
        if(path.Split(Path.DirectorySeparatorChar).Any(x=>x.Equals("network-private",StringComparison.OrdinalIgnoreCase)) || path.EndsWith(".cf7ticket",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("认证资料不能作为诊断产物导出");
    }
    private void EnsureNoRunning(){if(Operations.Values.Any(x=>x.State=="running"))throw new InvalidOperationException("先结束正在运行的操作，再修改实验文件");lifetime.Token.ThrowIfCancellationRequested();}
    private object StartOperation(string id,string kind,string script,int seconds)
    {
        if(Operations.Count>=128)throw new InvalidOperationException("本次实验操作已达上限");
        var operation=new ExperimentOperation(id,kind);if(!Operations.TryAdd(id,operation))throw new InvalidOperationException("重复操作");
        operation.Start(script,Root,lifetime.Token,()=>{Save();Changed?.Invoke();},seconds);return new{operationId=id};
    }
    public void DecidePair(bool accept){pairDecision?.TrySetResult(accept);}
    public void Answer(string id,string text,bool reject=false)
    {
        lock(stateGate){RefreshQuestion();if(State!="active"||Question==null||Question.Id!=id||Question.State!="pending")throw new InvalidOperationException("问题已到期、取消或会话结束");if(text.Length>4000)throw new InvalidDataException("回复过长");Question.Answer=text;Question.State=reject?"rejected":"answered";}
        Save();Changed?.Invoke();
    }
    private void RefreshQuestion(){if(Question?.State=="pending" && DateTimeOffset.UtcNow>Question.Deadline)Question.State="timed_out";}
    public object Snapshot()
    {
        lock(stateGate){RefreshQuestion();return new{sessionId=Id,ownerPid=Environment.ProcessId,ownerStartUtc,State,EndReason,ConnectedAt,EndedAt,lastMessageAgeSeconds=Stopwatch.GetElapsedTime(Interlocked.Read(ref lastMessage)).TotalSeconds,ExpiresAt,Game,workspace=Root,Developer,LastConnectionError,journalError,question=Question,questions=questions.Values.ToArray(),operations=Operations.Values.Select(x=>x.Snapshot(false)).ToArray(),changes=Artifacts.Changes,route=Network?.Route};}
    }
    private void Save(){lock(recordGate){try{LocalState.Save(Path.Combine(Root,"handoff.json"),Snapshot());}catch(Exception ex){journalError=ex.Message;}}}
    private async Task Monitor()
    {
        try{while(!lifetime.IsCancellationRequested){await Task.Delay(1000,lifetime.Token);if(Stopwatch.GetElapsedTime(began)>duration){Stop("expired");break;}if(State=="active"&&Stopwatch.GetElapsedTime(Interlocked.Read(ref lastMessage))>TimeSpan.FromSeconds(Wire.LostSeconds)){Stop("heartbeat_timeout");break;}lock(stateGate)RefreshQuestion();Changed?.Invoke();}}
        catch(OperationCanceledException){}
    }
    public void Stop(string reason)
    {
        lock(stateGate){if(State=="ended")return;State="ended";EndReason=reason;EndedAt=DateTimeOffset.UtcNow;Ticket=null;pairDecision?.TrySetResult(false);if(Question?.State=="pending")Question.State="cancelled";}
        lifetime.Cancel();listener.Stop();activeSocket?.Dispose();foreach(var op in Operations.Values)op.Stop();
        _=Task.Run(()=>Network?.Dispose());Save();Changed?.Invoke();
    }
    public void Dispose(){Stop("assistant_closed");foreach(var op in Operations.Values)op.Dispose();Network?.Dispose();certificate.Dispose();}
}
