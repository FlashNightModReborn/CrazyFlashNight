using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    // Replays actual CS6 production registration across lazy layer creation / scene retirement.
    // Does not launch the game, enter a save, or claim battle frame-rate qualification.
    private static async Task RunChainSceneGallery(string root,string module,string output,
        IntPtr source,IntPtr target,string tracePath)
    {
        var catalog=BulletVisualCatalog.Load(root);
        var engine=new ChainVisualEngine();
        using var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target);
        session.Mode(0);await WaitFor(()=>session.Read().Presented>0,session,"chain scene capture");
        var size=session.ReadCaptureSize();session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
        session.Matrix(Grade(1,1,1));session.BulletStyles(catalog);
        await WaitFor(()=>session.BulletResourcesReady,session,"chain atlas upload");
        session.ClearBulletFrame();
        var before=Grab(session,Path.Combine(output,"baseline.png"));
        var rows=new List<object>();var cases=new HashSet<string>();string key=null;int step=0;
        foreach(string line in File.ReadLines(tracePath))
        {
            const string caseTag="[CHAIN_SCENE_CASE] ",wireTag="[CHAIN_SCENE_WIRE] ";
            if(line.StartsWith(caseTag,StringComparison.Ordinal)) {
                key=line.Substring(caseTag.Length).Trim();step=0;
                Require(cases.Add(key),"Repeated chain scene case");
            } else if(key!=null && line.StartsWith(wireTag,StringComparison.Ordinal)) {
                string payload=line.Substring(wireTag.Length);
                Require(ChainVisualFrame.TryParse(payload,catalog.Styles.Count,out var frame),"Actual CS6 F8 is invalid: "+key);
                var items=engine.Consume(1,payload,catalog.Styles.Count);
                Require(items!=null && items.Length>0 && !engine.NeedsResync,"Production F8 has no visible units: "+key);
                string linkage=key.Contains("secondary",StringComparison.Ordinal)?"单元体-次级穿刺子弹":
                    key.Contains("pierce",StringComparison.Ordinal)?"单元体-穿刺子弹":"单元体-普通子弹";
                int style=catalog.Styles.ToList().FindIndex(s=>s.GunChainUnitLinkage==linkage);
                Require(style>=0 && items.All(i=>i.Style==style),"F8 lost the authored chain style: "+key);
                var draw=BulletVisualFrame.Compose(frame.Epoch,frame.Tick,Array.Empty<BulletVisualInstance>(),items);
                session.BulletFrame(draw,0,0,1);
                string name=key.Replace(' ','-').Replace('=','-')+"-"+(step++);
                var pixels=Grab(session,Path.Combine(output,name+".png"));
                int changed=Changed(before,pixels,new Rectangle(0,0,1024,576));
                Require(changed>8,"Production chain is blank on GPU: "+key);
                rows.Add(new {key,step,style,units=items.Length,changedPixels=changed,file=name+".png"});
            }
        }
        Require(cases.Count==8 && rows.Count==16,"Need four actual-parameter cases in each of two scenes");
        session.ClearBulletFrame();var clear=Grab(session,Path.Combine(output,"cleared.png"));
        Require(Changed(before,clear,new Rectangle(0,0,1024,576))<4,"Chain cleanup left GPU pixels");
        string Hash(string path)=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
        File.WriteAllText(Path.Combine(output,"chain-scene-proof.json"),JsonSerializer.Serialize(new {
            success=true,sourceTrace=tracePath,traceSha256=Hash(tracePath),nativeModule=module,nativeSha256=Hash(module),
            coreModule=typeof(ChainVisualEngine).Assembly.Location,coreSha256=Hash(typeof(ChainVisualEngine).Assembly.Location),
            catalogSha256=Hash(Path.Combine(root,BulletVisualCatalog.RelativePath)),cases=cases.Count,rows,
            boundary="Actual CS6 F8 production-registration replay through candidate Core/native and GPU; not live battle or save validation"
        },new JsonSerializerOptions{WriteIndented=true}));
        Console.WriteLine("PASS: 8 production chain scene cases / 16 GPU frames, authored styles and cleanup");
    }
}
