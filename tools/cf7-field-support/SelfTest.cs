using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;

namespace Cf7.FieldSupport;

internal static class SelfTest
{
    public static async Task<int> Run(string output,string? candidateRoot=null)
    {
        output=Path.GetFullPath(output);if(Directory.Exists(output))throw new IOException("测试输出必须是新目录");
        LocalState.PrivateDirectory(output);var results=new List<object>();int failures=0;
        async Task Check(string name,Func<Task> test)
        {
            try{await test();results.Add(new{name,passed=true});Console.WriteLine("PASS "+name);}
            catch(Exception ex){failures++;results.Add(new{name,passed=false,error=ex.ToString()});Console.WriteLine("FAIL "+name+" "+ex.Message);}
        }
        void Assert(bool value,string message){if(!value)throw new Exception(message);}
        async Task Reject(Func<Task> action){bool rejected=false;try{await action();}catch{rejected=true;}Assert(rejected,"必须拒绝");}
        string game=Path.Combine(output,"game");Directory.CreateDirectory(game);
        await Check("GUI journey identifies the next actor and action",()=>Task.Run(GuidanceChecks.Journey));
        await Check("question guidance rejects expired and stale authority",()=>Task.Run(GuidanceChecks.QuestionLifecycle));
        await Check("attention is once-only, muted correctly, and cancelled with request",()=>Task.Run(GuidanceChecks.Attention));
        await Check("GUI recovery discovers own records and preserves later changes",()=>Task.Run(()=>GuidanceChecks.Recovery(output)));
        using var session=new SupportSession(game,10,Path.Combine(output,"session"));
        session.Changed+=()=>{if(session.PairFingerprint!=null)session.DecidePair(true);};
        await session.Start(false);
        using var client=new Controller();
        await Check("TLS rejects wrong server pin",async()=>{using var wrong=new Controller();await Reject(()=>wrong.Connect(session.Ticket! with {CertificateSha256=new string('0',64)},"test"));await Task.Delay(100);});
        await Check("ticket secret rejected",async()=>{using var wrong=new Controller();await Reject(()=>wrong.Connect(session.Ticket! with {Secret=new string('0',64)},"test"));await Task.Delay(100);});
        await Check("real TLS pair and target consent",async()=>{try{await client.Connect(session.Ticket!,"local-test");}catch(Exception ex){await Task.Delay(200);throw new Exception(ex.Message+" / server: "+session.LastConnectionError);}Assert(session.State=="active","未激活");});
        await Check("single controller rejects second redemption",async()=>{using var second=new Controller();await Reject(()=>second.Connect(session.Ticket!,"second"));});
        await Check("status binds real workspace",async()=>{var status=await client.Request("status",new{});Assert(status.Text("workspace")==session.Root,"工作目录漂移");});
        await Check("ask rejects overlap and associates answer",async()=>
        {
            var q=await client.Request("ask",new{text="请确认本机测试",options=new[]{"已确认","未确认"},timeoutSeconds=10});
            await Reject(()=>client.Request("ask",new{text="不能覆盖",options=Array.Empty<string>()}));
            session.Answer(q.Text("id"),"已确认");var reply=await client.Request("question",new{id=q.Text("id")});Assert(reply.Text("state")=="answered","答复丢失");
            await Reject(()=>Task.Run(()=>session.Answer(q.Text("id"),"迟到")));
        });
        await Check("question cancellation rejects late answer",async()=>
        {
            var q=await client.Request("ask",new{text="待取消",options=Array.Empty<string>()});await client.Request("ask.cancel",new{id=q.Text("id")});
            await Reject(()=>Task.Run(()=>session.Answer(q.Text("id"),"迟到")));
        });
        string upload=Wire.Id();byte[] contents=Encoding.UTF8.GetBytes("新测试字节\n");
        await Check("partial upload cannot execute and wrong offsets reject",async()=>
        {
            await client.Request("put.begin",new{id=upload,name="probe.txt",size=contents.Length,sha256=Wire.Hash(contents)});
            await Reject(()=>client.Request("put.complete",new{id=upload}));
            await Reject(()=>client.Request("put.chunk",new{id=upload,offset=1,bytes=Convert.ToBase64String(contents)}));
            await client.Request("put.chunk",new{id=upload,offset=0,bytes=Convert.ToBase64String(contents)});
            var complete=await client.Request("put.complete",new{id=upload});Assert(complete.Text("sha256")==Wire.Hash(contents),"哈希不符");
        });
        await Check("replacement backs up, restores, and rejects drift",async()=>
        {
            string target=Path.Combine(game,"test.txt");File.WriteAllText(target,"original");string hash=Wire.FileHash(target);
            await Reject(()=>client.Request("replace",new{uploadId=upload,target="test.txt",expectedSha256=new string('0',64)}));
            var change=await client.Request("replace",new{uploadId=upload,target="test.txt",expectedSha256=hash});
            var restored=await client.Request("restore",new{id=change.Text("id")});Assert(restored.Text("state")=="restored"&&File.ReadAllText(target)=="original","恢复失败");
            var conflict=await client.Request("replace",new{uploadId=upload,target="test.txt",expectedSha256=hash});File.WriteAllText(target,"user changed");
            var preserved=await client.Request("restore",new{id=conflict.Text("id")});Assert(preserved.Text("state")=="conflict"&&File.ReadAllText(target)=="user changed","覆盖了现场差异");
        });
        await Check("save and formal runtime replacement denied",async()=>
        {
            foreach(string target in new[]{"saves/test.json","runtime/evil.dll","../escape.txt","CON.txt","foo:stream"})
                await Reject(()=>client.Request("replace",new{uploadId=upload,target,expectedSha256=new string('0',64)}));
        });
        await Check("archive traversal and case duplicates denied",async()=>
        {
            foreach(bool duplicate in new[]{false,true})
            {
                string zip=Path.Combine(output,Wire.Id()+".zip");using(var z=ZipFile.Open(zip,ZipArchiveMode.Create)){using(var w=new StreamWriter(z.CreateEntry(duplicate?"a":"../escape").Open()))w.Write("test");if(duplicate){using var w=new StreamWriter(z.CreateEntry("A").Open());w.Write("test");}}
                await Reject(()=>Task.Run(()=>Artifacts.Extract(zip,Path.Combine(output,Wire.Id()))));
            }
        });
        await Check("question timeout rejects late answer",async()=>
        {
            var q=await client.Request("ask",new{text="timeout fixture",options=Array.Empty<string>(),timeoutSeconds=10});
            await Task.Delay(10500);var result=await client.Request("question",new{id=q.Text("id")});Assert(result.Text("state")=="timed_out","问题未到期");
            await Reject(()=>Task.Run(()=>session.Answer(q.Text("id"),"too late")));
        });
        await Check("CLI broker survives CLI exit and reconnects through protected local pipe",async()=>
        {
            using var s=new SupportSession(game,10,Path.Combine(output,"broker-session"));s.Changed+=()=>{if(s.PairFingerprint!=null)s.DecidePair(true);};await s.Start(false);
            string ticketPath=Path.Combine(output,"broker.cf7ticket"),statePath=Path.Combine(output,"broker-state.json");LocalState.Save(ticketPath,s.Ticket!);
            string pipeName="cf7-field-selftest-"+Wire.Id();
            var psi=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};foreach(var arg in new[]{"broker","--ticket",ticketPath,"--developer","broker-selftest","--state",statePath,"--selftest-pipe",pipeName})psi.ArgumentList.Add(arg);
            using var broker=Process.Start(psi)!;
            try
            {
                for(int i=0;i<150&&s.State!="active"&&!broker.HasExited;i++)await Task.Delay(100);
                Assert(s.State=="active","代理未配对");await Task.Delay(250);
                var first=await Broker.Call("status",new{},selfTestPipe:pipeName);var second=await Broker.Call("status",new{},selfTestPipe:pipeName);
                Assert(first.Text("sessionId")==second.Text("sessionId"),"CLI 接班丢失会话");
                await Broker.Call("finish",new{},selfTestPipe:pipeName);await broker.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10));
                Assert(s.State=="ended","代理结束未撤权");
                var closed=LocalState.Read<JsonElement>(statePath);var diagnostic=closed.GetProperty("diagnostic");
                Assert(closed.GetProperty("session").Text("sessionId")==s.Id&&diagnostic.GetProperty("finishRequestedAt").ValueKind==JsonValueKind.String&&diagnostic.GetProperty("endedAt").ValueKind==JsonValueKind.String,"代理收尾缺少会话与主动结束证据");
            }
            finally{if(!broker.HasExited)broker.Kill(true);}
        });
        if(candidateRoot!=null)await Check("real producer candidate pack, TLS upload, canonical import, and tamper rejection",async()=>
        {
            foreach(string relative in new[]{"crossdomain.xml","launcher/web/bootstrap.html","automation/start.ps1","tools/dotnet-runtime-detect.ps1"})
            {string file=LocalState.Under(game,relative);Directory.CreateDirectory(Path.GetDirectoryName(file)!);File.WriteAllText(file,"local test sentinel only; never execute");}
            string zip=Path.Combine(output,"producer-candidate.zip");var expected=Candidate.Pack(candidateRoot,zip);
            string id=Wire.Id();long size=new FileInfo(zip).Length;await client.Request("put.begin",new{id,name="candidate.zip",size,sha256=Wire.FileHash(zip)});
            using(var f=File.OpenRead(zip)){byte[] buffer=new byte[Wire.Chunk];int n;long offset=0;while((n=await f.ReadAsync(buffer))>0){await client.Request("put.chunk",new{id,offset,bytes=Convert.ToBase64String(buffer,0,n)});offset+=n;}}
            await client.Request("put.complete",new{id});var imported=await client.Request("candidate.import",new{uploadId=id});string root=imported.Text("path");
            var actual=Candidate.Validate(root);Assert(expected==actual,"导入改变身份");
            File.AppendAllText(Path.Combine(root,"runtime","CRAZYFLASHER7MercenaryEmpire.Core.dll"),"tamper fixture");
            await Reject(()=>Task.Run(()=>Candidate.Validate(root)));
        });
        await Check("request replay executes one operation",async()=>
        {
            string id=Wire.Id();var request=new{script="Write-Output 'cf7_probe_ok'",timeoutSeconds=30};
            var first=await client.Request("exec",request,60,id);var again=await client.Request("exec",request,60,id);
            Assert(first.Text("operationId")==again.Text("operationId"),"重复执行");
            await session.Operations[id].Completion.WaitAsync(TimeSpan.FromSeconds(40));var op=Wire.Data(session.Operations[id].Snapshot());
            Assert(op.Text("state")=="completed"&&op.Text("output").Contains("cf7_probe_ok"),"命令未成功");
            await Reject(()=>client.Request("exec",new{script="Write-Output 'different'"},60,id));
        });
        await Check("long command does not block questions or stop; owned descendants terminate",async()=>
        {
            string pidFile=Path.Combine(session.Root,"child-pid.txt");
            string script="$p=Start-Process -FilePath $PSHOME\\powershell.exe -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 120' -PassThru -WindowStyle Hidden\n$p.Id | Set-Content -LiteralPath '"+pidFile.Replace("'","''")+"'\nStart-Sleep -Seconds 120";
            var launch=await client.Request("exec",new{script,timeoutSeconds=180});
            for(int i=0;i<100&&!File.Exists(pidFile);i++)await Task.Delay(100);
            Assert(File.Exists(pidFile),"子进程未启动");int pid=int.Parse(File.ReadAllText(pidFile).Trim());
            var q=await client.Request("ask",new{text="长命令期间仍可求助",options=new[]{"结束"}});Assert(q.Text("state")=="pending","问答阻塞");
            session.Stop("test_stop");await session.Operations[launch.Text("operationId")].Completion.WaitAsync(TimeSpan.FromSeconds(15));
            bool alive;try{using var process=Process.GetProcessById(pid);alive=!process.HasExited;}catch(ArgumentException){alive=false;}Assert(!alive,"本轮子进程残留");
            await Reject(()=>client.Request("status",new{},2));
        });
        await Check("handoff excludes ticket secrets",async()=>
        {
            await Task.Delay(100);string text=File.ReadAllText(Path.Combine(session.Root,"handoff.json"));Assert(!text.Contains("certificateSha256")&&!text.Contains("secret")&&!text.Contains("BEGIN PRIVATE"),"秘密进入接班文件");
        });
        await Check("connection closure ends authorization",async()=>
        {
            using var s=new SupportSession(game,10,Path.Combine(output,"disconnect"));s.Changed+=()=>{if(s.PairFingerprint!=null)s.DecidePair(true);};await s.Start(false);
            using var c=new Controller();await c.Connect(s.Ticket!,"disconnect-test");c.Dispose();
            for(int i=0;i<100&&s.State!="ended";i++)await Task.Delay(25);Assert(s.State=="ended","断连未撤权");
            Assert(s.EndedAt!=null&&s.EndReason=="connection_closed","目标端未记录断连原因和时间");
        });
        await Check("controller preserves remote closure diagnostics",async()=>
        {
            using var s=new SupportSession(game,10,Path.Combine(output,"remote-closure"));s.Changed+=()=>{if(s.PairFingerprint!=null)s.DecidePair(true);};await s.Start(false);
            using var c=new Controller();await c.Connect(s.Ticket!,"closure-diagnostics-test");s.Stop("fixture_remote_stop");
            for(int i=0;i<100&&c.Connected;i++)await Task.Delay(25);
            var d=Wire.Data(c.Diagnostic);Assert(!c.Connected&&d.Text("endReason")=="receive_failed"&&d.Text("endError").Length>0,"对端关闭的底层异常被吞掉");
            Assert(d.GetProperty("finishRequestedAt").ValueKind==JsonValueKind.Null,"没有 finish 却记录成主动结束");
        });
        LocalState.Save(Path.Combine(output,"test-report.json"),new{schema="cf7-field-support-selftest.v1",passed=failures==0,results,scope="single-machine real TLS, isolated files and process trees; no cross-network, GUI-human, or game execution qualification"});
        Console.WriteLine($"{results.Count-failures}/{results.Count} passed");return failures==0?0:1;
    }
}
