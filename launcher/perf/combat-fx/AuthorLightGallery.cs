#if !PERF_BASELINE
using System.Drawing;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    private static async Task RunAuthorLights(string root, string module, string output, IntPtr source, IntPtr target, string proof)
    {
        var settings=WorldLightSettings.Load(root);
        var catalog=CombatFxCatalog.ForResidentLights(settings);
        using var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target);
        await WaitFor(()=>session.Read().Presented>0,session,"author capture");
        var size=session.ReadCaptureSize();
        session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
        session.Matrix(Grade(.12f,.12f,.12f));
        var samples=new Dictionary<(string run,string label),byte[]>();
        var rows=new List<object>();
        byte[] verified=File.ReadAllBytes(Path.Combine(proof,"verified.json"));
        using var receipt=JsonDocument.Parse(verified);
        foreach(string run in new[]{"A","B-rocket","C-four"}) {
            string tracePath=Path.Combine(proof,run+".txt");
            string recorded=receipt.RootElement.GetProperty("runs").GetProperty(run).GetProperty("reportSha256").GetString();
            Require(string.Equals(recorded,Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(tracePath))),StringComparison.OrdinalIgnoreCase),
                    "Player 20 trace no longer matches its verified receipt");
            foreach(string line in File.ReadLines(tracePath)) {
                string label,wire;
                if(line.StartsWith("LightAuthorSample ",StringComparison.Ordinal)) {
                    int split=line.IndexOf(' ',"LightAuthorSample ".Length);
                    label=line["LightAuthorSample ".Length..split]; wire=line[(split+1)..];
                } else if(line.StartsWith("LightTimeline ice frame=",StringComparison.Ordinal)) {
                    const string prefix="LightTimeline ice frame=";
                    label="lady-frame"+line[prefix.Length..line.IndexOf(' ',prefix.Length)];
                    wire=line[line.IndexOf(";l,",StringComparison.Ordinal)..];
                } else continue;
                Require(CombatFxFrame.TryParse("1|1|1|0"+wire,catalog,out var frame),"Invalid Player 20 light records: "+label);
                var engine=new CombatFxEngine(catalog);
                Require(engine.Apply(frame,1),"Could not adopt Player 20 frame");
                var composer=new WorldLightComposer(settings.MaximumResponse);
                composer.SetCombatFx(engine.BuildDraw());
                var draw=composer.Compose(0,0,1);
                var before=Work(session);
                session.CombatFxFrame(draw,0,0,1);
                // A static surface with no sprite atlas repaints on changes and can then idle.
                await WaitFor(()=>Work(session).Compositions>before.Compositions,session,run+" "+label);
                var image=Grab(session,Path.Combine(output,run+"-"+label+".png"));
                samples.Add((run,label),image.bytes);
                if(run=="A") continue;
                byte[] other=samples[("A",label)];
                Require(other.Length==image.bytes.Length,"Capture geometry changed");
                int changed=0,peak=0;
                for(int i=0;i<other.Length;i+=4) {
                    int delta=Math.Max(Math.Abs(image.bytes[i]-other[i]),Math.Max(Math.Abs(image.bytes[i+1]-other[i+1]),Math.Abs(image.bytes[i+2]-other[i+2])));
                    if(delta>0) changed++;
                    peak=Math.Max(peak,delta);
                }
                bool shouldChange=label is "rpg" or "m3" || (run=="C-four" && !label.EndsWith("-before",StringComparison.Ordinal));
                Require(shouldChange ? changed>0 && peak>2 : changed==0,"Unexpected pixel comparison: "+run+" "+label+" count="+changed+" peak="+peak);
                rows.Add(new{run,label,draw.LightCount,changedPixels=changed,peakChannelChange=peak});
            }
        }
        Require(samples.Count==36,"Incomplete author sample matrix");
        Require(!session.CombatFxReady,"Unexpected decorative sprite atlas in the isolated light proof");
        var result=new{source="Flash Player 20 production light records on a controlled WGC material grid",
            playerReceipt=Convert.ToHexString(SHA256.HashData(verified)),
            managed=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(CombatFxEngine).Assembly.Location))),
            native=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module))),worldResponse=settings.MaximumResponse,
            spriteAtlasInstalled=false,rows};
        File.WriteAllText(Path.Combine(output,"author-light-pixels.json"),JsonSerializer.Serialize(result,new JsonSerializerOptions{WriteIndented=true}));
    }
}
#endif
