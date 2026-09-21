using System.Diagnostics;

namespace Cf7.FieldSupport;

internal static class ConnectionCheck
{
    public static async Task<int> Run(string output,int seconds)
    {
        if(seconds is <190 or >600)throw new ArgumentOutOfRangeException(nameof(seconds));
        output=Path.GetFullPath(output);if(Directory.Exists(output))throw new IOException("测试输出必须是新目录");
        LocalState.PrivateDirectory(output);string game=Path.Combine(output,"game");Directory.CreateDirectory(game);
        using var session=new SupportSession(game,15,Path.Combine(output,"session"));
        session.Changed+=()=>{if(session.PairFingerprint!=null)session.DecidePair(true);};
        using var controller=new Controller();var elapsed=Stopwatch.StartNew();
        bool passed=false;string error="";var samples=new List<object>();
        try
        {
            await session.Start(false);await controller.Connect(session.Ticket!,"isolated-continuity-check");elapsed.Restart();
            var question=await controller.Request("ask",new{text="offline continuity fixture",options=new[]{"ready"}});
            session.Answer(question.Text("id"),"ready");
            while(elapsed.Elapsed.TotalSeconds<seconds)
            {
                await Task.Delay(1000);
                if(!controller.Connected||session.State!="active")throw new IOException("持续连接提前结束");
                if((int)elapsed.Elapsed.TotalSeconds/30>samples.Count)
                {
                    samples.Add(new{elapsedSeconds=elapsed.Elapsed.TotalSeconds,diagnostic=controller.Diagnostic,target=session.Snapshot()});
                    Console.WriteLine($"Connection active at {(int)elapsed.Elapsed.TotalSeconds}s");
                }
            }
            var status=await controller.Request("status",new{});
            if(status.Text("state")!="active")throw new IOException("持续连接后查询失败");
            passed=true;
        }
        catch(Exception ex){error=ex.ToString();}
        finally
        {
            LocalState.Save(Path.Combine(output,"connection-report.json"),new{passed,requestedSeconds=seconds,elapsedSeconds=elapsed.Elapsed.TotalSeconds,error,diagnostic=controller.Diagnostic,target=session.Snapshot(),samples,scope="loopback real TLS with production heartbeat beyond the three-minute pairing window; no tsnet or remote-network qualification"});
            session.Stop("local_check_finished");
        }
        Console.WriteLine(passed?"PASS sustained real TLS connection":"FAIL sustained real TLS connection: "+error);return passed?0:1;
    }
}
