using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.Guardian.HitNumbers;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;

internal static partial class Program
{
    private static int RunHostCosts(string root, string output)
    {
        Directory.CreateDirectory(output);
        try {
            var catalog=BulletVisualCatalog.Load(root);
            var results=new List<object>();
            foreach(int count in new[]{128,2048,8192}) {
                var wires=CostWires(count);
                var time=new List<double>();var allocations=new List<double>();
                string fingerprint=null;
                var warmup=Stopwatch.StartNew();int rounds=0;
                while(time.Count<7) {
                    var task=new FrameTask(null,null);task.ConfigureProjectileVisuals(catalog);
                    var ordinary=BulletVisualFrame.Compose(1,0,new[]{new BulletVisualInstance(0,500,600,0,100,100,100)},Array.Empty<BulletVisualInstance>());
                    var packed=new float[(count+1)*8];
                    task.BulletVisualObserved=(frame,x,y,scale)=> {
#if PERF_BASELINE
                        int length=frame.NativeOwned?frame.NormalCount+frame.ChainCount:0;
                        for(int i=0;i<length;i++) {
                            var item=frame.Instances[i];
                            int at=i*8;packed[at]=item.Style;packed[at+1]=item.X;packed[at+2]=item.Y;
                            packed[at+3]=item.Rotation;packed[at+4]=item.ScaleX;packed[at+5]=item.ScaleY;
                            packed[at+6]=item.Alpha;packed[at+7]=0;
                        }
#else
                        NativeCompositorSession.PackBulletFrame(frame,packed);
#endif
                    };
                    long allocated=GC.GetAllocatedBytesForCurrentThread(),start=Stopwatch.GetTimestamp();
                    foreach(string wire in wires) {
                        task.ObserveProjectileVisuals(null,wire,7,new HitNumberCamera(0,0,1));
                        task.DispatchProjectileBullets(ordinary,new HitNumberCamera(0,0,1));
                    }
                    double elapsed=Stopwatch.GetElapsedTime(start).TotalMilliseconds;
                    long bytes=GC.GetAllocatedBytesForCurrentThread()-allocated;
                    string hash=Convert.ToHexString(SHA256.HashData(MemoryMarshal.AsBytes(packed.AsSpan())));
                    if(fingerprint!=null)Require(fingerprint==hash,"Host workload changed between rounds");
                    fingerprint=hash;
                    if(++rounds>=3 && warmup.ElapsedMilliseconds>=1000){time.Add(elapsed);allocations.Add(bytes);}
                }
                results.Add(new {units=count,frames=wires.Length,samples=time.Count,warmupRounds=rounds-time.Count,
                    elapsedMs=CostPercentiles(time),allocatedBytes=CostPercentiles(allocations),outputSha256=fingerprint,
                    inputSha256=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\n',wires))))});
            }
            string[] grammar=CostGrammar();
            var accepted=grammar.Select(w=>ChainVisualFrame.TryParse(w,8,out _)).ToArray();
            var assembly=typeof(ChainVisualEngine).Assembly.Location;
            var report=new {schema="cf7-host-visual-cost.v1",core=assembly,coreSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(assembly))),
                tieredCompilation=Environment.GetEnvironmentVariable("DOTNET_TieredCompilation")??"runtime-default",
                results,parserAcceptance=accepted,
                boundary="CPU-only production F8 parser, engine, dispatcher and native-record packing. Same inputs include births, multiple groups, mirror, pause and movement. Excludes F5 parsing, socket, HUD, native setter, GPU, Flash gameplay, power and FPS."};
            File.WriteAllText(Path.Combine(output,"host-costs.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));
            Console.WriteLine("Host cost comparison: three bounded workloads, seven warmed samples each");return 0;
        } catch(Exception error){File.WriteAllText(Path.Combine(output,"failure.txt"),error.ToString());Console.Error.WriteLine(error);return 1;}
    }

    private static string[] CostWires(int units)
    {
        int groups=(units+7)/8,step=0;
        var wires=new string[31];
        for(int frame=0;frame<wires.Length;frame++) {
            if(frame>0 && frame%7!=0)step++;
            var body=new StringBuilder();body.Append("1|1|").Append(frame+1).Append('|').Append(frame);
            for(int group=1;group<=groups;group++) {
                body.Append(";G,").Append(group).Append(",0,").Append(step).Append(",100,200,").Append(frame%9)
                    .Append(group%3==0?",-100,100,100,1,3,1":",100,100,100,1,3,1");
            }
            if(frame==0)for(int unit=0;unit<units;unit++) {
                body.Append(";B,").Append(unit/8+1).Append(',').Append(unit%8+1).Append(',').Append(unit%17)
                    .Append(",3,0.6,0.8,20");
            }
            wires[frame]=body.ToString();
        }
        return wires;
    }
    private static string[] CostGrammar()
    {
        const string group="G,1,0,0,100,200,0,100,100,100,1,3,1",birth="B,1,1,2,3,0.6,0.8,20";
        string good="1|1|1|0;"+group+";"+birth;
        return new[]{"1|1|1|0",good,good+";",good+";;",good+";D,1,1",good+";D,1,1,",
            "1|+1|1|0;"+group,"1|1|1|0|1;"+group,"1|1|1|0;"+birth,
            good+";"+group,good.Replace("0.6","NaN"),good.Replace("0.8","Infinity"),
            good.Replace("0.6","1.1"),good.Replace("0.6","6e-1"),good.Replace("100,200","-100,200"),
            "1|1|1|0;"+group+",;"+birth,"1|1|1|0;"+group+";;"+birth};
    }
    private static object CostPercentiles(List<double> values)
    {
        values.Sort();return new {median=values[values.Count/2],p95=values[(int)Math.Ceiling(values.Count*.95)-1],min=values[0],max=values[^1]};
    }
}
