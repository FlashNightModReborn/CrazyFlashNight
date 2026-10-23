#if !PERF_BASELINE
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    private static async Task RunExtendedFxGallery(string root,string module,string output,IntPtr source,IntPtr target)
    {
        Require(!Directory.EnumerateFileSystemEntries(output).Any(),"Extended FX needs a fresh output directory");
        string Hash(string path)=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
        string catalogPath=Path.Combine(root,CombatFxCatalog.RelativePath),atlasPath=Path.Combine(root,CombatFxCatalog.AtlasPath);
        using var document=JsonDocument.Parse(File.ReadAllBytes(catalogPath));
        var sourceFiles=document.RootElement.GetProperty("sources").EnumerateArray().Select(s=> {
            string path=s.GetProperty("path").GetString(),declared=s.GetProperty("sha256").GetString();
            return new {path,declaredSha256=declared,actualSha256=Hash(Path.Combine(root,path))};
        }).ToArray();
        string core=typeof(CombatFxEngine).Assembly.Location,fixture=typeof(ProbeWindow).Assembly.Location;
        var identity=new {schema="cf7-extended-fx-identity.v1",utc=DateTime.UtcNow,process=Environment.ProcessId,
            project=root,catalogPath,catalogSha256=Hash(catalogPath),atlasPath,atlasSha256=Hash(atlasPath),sourceFiles,
            nativeModule=module,nativeSha256=Hash(module),coreModule=core,coreSha256=Hash(core),
            fixtureModule=fixture,fixtureSha256=Hash(fixture),sourceHwnd=source.ToInt64(),targetHwnd=target.ToInt64(),
            boundary="Controlled WGC/D3D11 renderer fixture. No game, save, gameplay FPS, weak-hardware or human acceptance."};
        File.WriteAllText(Path.Combine(output,"extended-fx-identity.json"),JsonSerializer.Serialize(identity,new JsonSerializerOptions{WriteIndented=true}));
        Require(sourceFiles.All(s=>string.Equals(s.declaredSha256,s.actualSha256,StringComparison.OrdinalIgnoreCase)),"Stale effect source closure");
        var catalog=CombatFxCatalog.Load(root);
        string[] expected={"冰汽","烈焰火花","能量火花","空手攻击火花","铁枪能量弹枪火","飙血","子弹碎片-飞血"};
        var styles=expected.Select(name=>catalog.Styles.Single(s=>s.Linkage==name)).ToArray();
        using var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target);
        session.Mode(0);await WaitFor(()=>session.Read().Presented>0,session,"extended source capture");
        var size=session.ReadCaptureSize();session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
        session.Matrix(Grade(1,1,1));session.ClearRayFrame();session.ClearBulletFrame();session.ClearCombatFxFrame();
        session.CombatFxAtlas(catalog);await WaitFor(()=>session.CombatFxReady,session,"extended real atlas upload");
        var empty=new CombatFxDrawFrame(512);
        var baseline=await RenderExtendedFx(session,empty,Path.Combine(output,"extended-background.png"));
        var rows=new List<object>();var cards=new StringBuilder();
        foreach(var style in styles)for(int variant=0;variant<style.Variants.Length;variant++)
        {
            int[] sequence=style.Variants[variant],ages={0,sequence.Length/2,sequence.Length-1};
            var frames=ages.Select(age=>style.Frames[sequence[age]]).ToArray();
            float left=frames.Min(f=>f.OffsetX),top=frames.Min(f=>f.OffsetY);
            float right=frames.Max(f=>f.OffsetX+f.Width),bottom=frames.Max(f=>f.OffsetY+f.Height);
            float scale=Math.Min(1,Math.Min(280/(right-left),440/(bottom-top)));
            var draw=new CombatFxDrawFrame(3){Count=3,ImpactCount=style.IsMuzzle?0:3};
            for(int i=0;i<3;i++) {
                var f=frames[i];float x=170+i*342-(left+right)*.5f*scale,y=288-(top+bottom)*.5f*scale;
                Put(draw,i,x,y,0,scale,scale,style.WorldLit?1:0,f.OffsetX,f.OffsetY,f.Width,f.Height,f.U0,f.V0,f.U1,f.V1);
            }
            string file=$"extended-style-{style.Index}-variant-{variant}.png";
            var pixels=await RenderExtendedFx(session,draw,Path.Combine(output,file));
            var samples=Enumerable.Range(0,3).Select(i=> {
                int frame=sequence[ages[i]],changed=Changed(baseline,pixels,new Rectangle(i*342,0,i==2?340:342,576));
                bool visible=ExtendedFrameVisible(catalog,frames[i]);
                Require(!visible || changed>0,"Authored frame missing from GPU output: "+style.Linkage+"/"+variant+"/"+ages[i]);
                int sourceFrame=document.RootElement.GetProperty("styles")[style.Index].GetProperty("frames")[frame].GetProperty("sourceFrame").GetInt32();
                return new {age=ages[i],frame,sourceFrame,visible,changed};
            }).ToArray();
            rows.Add(new {style=style.Index,style.Linkage,variant,ticks=sequence.Length,file,samples});
            cards.Append("<figure><figcaption>").Append(System.Net.WebUtility.HtmlEncode(style.Linkage)).Append(" / ").Append(variant)
                .Append(" · first / middle / last</figcaption><img src=\"").Append(file).Append("\"></figure>");
        }
        object capacity=await ExtendedFxCapacity(session,catalog,output,baseline);
        object lifecycle=await ExtendedBloodLifecycle(session,catalog,output,baseline);
        var cleared=await RenderExtendedFx(session,empty,Path.Combine(output,"extended-cleared.png"));
        Require(baseline.bytes.SequenceEqual(cleared.bytes),"Extended FX cleanup retained pixels");
        Require(identity.catalogSha256==Hash(catalogPath) && identity.atlasSha256==Hash(atlasPath)
            && identity.nativeSha256==Hash(module),"Fixture inputs changed during execution");
        var proof=new {schema="cf7-extended-fx-proof.v1",success=true,utc=DateTime.UtcNow,identity,
            actualAtlasUpload=new{catalog.Width,catalog.Height,bytes=catalog.PremultipliedBgra.Length,ready=session.CombatFxReady},
            readbackBarrier="Existing composite size query, then an independent worker pixel request; no cached source-frame screenshot.",
            variants=rows.Count,rows,capacity,lifecycle,cleared=true,adapter=session.Read().Adapter,
            boundary=identity.boundary};
        File.WriteAllText(Path.Combine(output,"extended-fx-proof.json"),JsonSerializer.Serialize(proof,new JsonSerializerOptions{WriteIndented=true}));
        File.WriteAllText(Path.Combine(output,"index.html"),"<!doctype html><meta charset=\"utf-8\"><title>Extended FX fixture</title>"+
            "<style>body{margin:24px;background:#12161c;color:#eee;font:16px system-ui}figure{margin:16px 0;border:1px solid #38434c}figcaption{padding:10px}img{display:block;width:100%;max-width:1024px}</style>"+
            "<h1>新增特效 · 原生图集夹具</h1><p>每图依次为首帧、中帧、末帧。只验证受控渲染，不代表实战、游戏FPS或人类验收。</p>"+cards);
        Console.WriteLine("PASS: seven extended styles, all variant first/mid/last frames, 448+64 capacity, blood lifecycle and cleanup; renderer fixture only.");
    }

    private static bool ExtendedFrameVisible(CombatFxCatalog catalog,CombatFxImage frame)
    {
        int x0=(int)Math.Round(frame.U0*catalog.Width),x1=(int)Math.Round(frame.U1*catalog.Width);
        int y0=(int)Math.Round(frame.V0*catalog.Height),y1=(int)Math.Round(frame.V1*catalog.Height);
        for(int y=y0;y<y1;y++)for(int x=x0;x<x1;x++)if(catalog.PremultipliedBgra[(y*catalog.Width+x)*4+3]>32)return true;
        return false;
    }

    private static async Task<(byte[] bytes,int width,int height)> RenderExtendedFx(NativeCompositorSession session,CombatFxDrawFrame draw,string path)
    {
        ulong before=session.Read().Presented;session.CombatFxFrame(draw,0,0,1);
        await WaitFor(()=>session.Read().Presented>before,session,Path.GetFileName(path));
        // Presented alone can observe an in-flight previous frame. Existing Grab
        // makes two independent worker requests: size query, then pixel readback.
        // The latter forces another composition after the former has completed,
        // so it consumes the submitted FX even if the source itself is static.
        // Requiring two spontaneous presents would hang on an empty idle frame.
        return Grab(session,path);
    }

    private static void ApplyExtendedFx(CombatFxEngine engine,CombatFxCatalog catalog,int epoch,int sequence,int tick,string records="",bool paused=false)
    {
        string wire=FormattableString.Invariant($"{epoch}|{sequence}|{tick}|{(paused?1:0)}")+records;
        Require(CombatFxFrame.TryParse(wire,catalog,out var frame),"Extended fixture wire rejected");
        Require(engine.Apply(frame,1),"Extended fixture sequence rejected");
    }

    private static async Task<object> ExtendedFxCapacity(NativeCompositorSession session,CombatFxCatalog catalog,string output,
        (byte[] bytes,int width,int height) baseline)
    {
        int casing=catalog.Styles.First(s=>s.IsCasing).Index,impact=catalog.Styles.Single(s=>s.Linkage=="火花").Index;
        int muzzle=catalog.Styles.Single(s=>s.Linkage=="铁枪能量弹枪火").Index,blood=catalog.Styles.Single(s=>s.IsBlood).Index;
        var engine=new CombatFxEngine(catalog);engine.ConfigureVisualBudget(NativeVisualBudget.FromEffectLevel(0));int seq=0;
        ApplyExtendedFx(engine,catalog,71,++seq,0,string.Concat(Enumerable.Range(0,4).Select(i=>$";s,{casing},-10000,-10000,100,100,-9900,64,{i+1},0")));
        for(int group=0;group<2;group++)ApplyExtendedFx(engine,catalog,71,++seq,0,
            string.Concat(Enumerable.Range(0,32).Select(i=>$";m,{muzzle},-10000,-10000,100,100,0,{1+i+group*32},0")));
        for(int group=0;group<4;group++)ApplyExtendedFx(engine,catalog,71,++seq,0,
            string.Concat(Enumerable.Range(0,32).Select(i=>$";i,{impact},-10000,-10000,100,100,0,{1+i+group*32},0")));
        ApplyExtendedFx(engine,catalog,71,++seq,0,string.Concat(Enumerable.Range(1,64).Select(i=>
            $";p,{i},{blood},{600+(i-1)%8*45},{90+(i-1)/8*45},1000,100,{i},1")));
        var draw=engine.BuildDraw();
        Require(draw.Count==512 && draw.CasingCount==256 && draw.ImpactCount==192,"448 ordinary FX plus 64 blood did not retain 512 slots");
        // Keep three ordinary controls visible; all blood slots are visible. The
        // remaining ordinary records test capacity/clipping, not screen throughput.
        draw.Data[0]=120;draw.Data[1]=120;
        draw.Data[256*16]=300;draw.Data[256*16+1]=200;
        draw.Data[511*16]=120;draw.Data[511*16+1]=450;draw.LightCount=draw.CandidateLightCount=0;
        var ordinary=new CombatFxDrawFrame(448){Count=448,CasingCount=256,ImpactCount=128};
        Array.Copy(draw.Data,0,ordinary.Data,0,384*16);Array.Copy(draw.Data,448*16,ordinary.Data,384*16,64*16);
        var control=await RenderExtendedFx(session,ordinary,Path.Combine(output,"extended-capacity-ordinary-448.png"));
        var full=await RenderExtendedFx(session,draw,Path.Combine(output,"extended-capacity-full-512.png"));
        int bloodPixels=Changed(control,full,new Rectangle(550,50,450,400));
        Require(bloodPixels>0,"Full-capacity blood records produced no GPU pixels");
        Require(Changed(baseline,full,new Rectangle(60,400,220,160))>0,"Final native record was clipped by the upload limit");
        ApplyExtendedFx(engine,catalog,71,++seq,0,$";p,65,{blood},512,288,1000,100,65,1");
        Require(engine.BuildDraw().Count==512,"Blood overflow changed the independent ordinary FX capacity");
        return new{ordinary=448,blood=64,total=512,bloodPixels,lastRecordVisible=true,overflowRetainedCount=512,
            boundary="Capacity and clipping fixture; three ordinary controls and all blood are visible. Most ordinary records are offscreen. No throughput/FPS claim."};
    }

    private static async Task<object> ExtendedBloodLifecycle(NativeCompositorSession session,CombatFxCatalog catalog,string output,
        (byte[] bytes,int width,int height) baseline)
    {
        int style=catalog.Styles.Single(s=>s.IsBlood).Index;var engine=new CombatFxEngine(catalog);int seq=1;
        ApplyExtendedFx(engine,catalog,81,seq,0,$";p,1,{style},512,240,260,100,173,1");
        var bornDraw=engine.BuildDraw();Require(bornDraw.Count==1,"Lifecycle birth missing");
        float[] bornState=bornDraw.Data.Take(16).ToArray();
        var born=await RenderExtendedFx(session,bornDraw,Path.Combine(output,"extended-blood-born.png"));
        Require(Changed(baseline,born,new Rectangle(400,150,224,200))>0,"Blood birth missing from GPU output");
        ApplyExtendedFx(engine,catalog,81,++seq,0,paused:true);
        var paused=engine.BuildDraw();Require(paused.Count==1 && paused.Data.Take(16).SequenceEqual(bornState),"Pause advanced native blood");
        var frozen=await RenderExtendedFx(session,paused,Path.Combine(output,"extended-blood-paused.png"));
        Require(born.bytes.SequenceEqual(frozen.bytes),"Paused blood pixels changed");
        var rows=new List<object>();var landings=new List<BloodVisualLanding>();int landedAt=-1;
        for(int tick=1;tick<=20;tick++)
        {
            ApplyExtendedFx(engine,catalog,81,++seq,tick);var draw=engine.BuildDraw();var events=engine.TakeEvents();
            if(events!=null)landings.AddRange(events.BloodLandings);
            string file=null;
            if(tick==1 || tick==3 || tick==5 || landings.Count>0) {
                file=$"extended-blood-tick-{tick}.png";await RenderExtendedFx(session,draw,Path.Combine(output,file));
            }
            rows.Add(new{tick,draw.Count,file,landings=landings.Count});
            if(landings.Count>0){landedAt=tick;Require(draw.Count==0,"Landed blood retained an active sprite");break;}
        }
        Require(landings.Count==1 && landedAt>0,"Blood did not produce exactly one landing before its stochastic expiry");
        Require(engine.TakeEvents()==null,"Blood landing replayed without a new event");
        ApplyExtendedFx(engine,catalog,82,1,0,$";p,1,{style},512,240,260,100,173,1");
        ApplyExtendedFx(engine,catalog,83,1,0);Require(engine.BuildDraw().Count==0,"New scene retained old blood");
        var scene=await RenderExtendedFx(session,engine.BuildDraw(),Path.Combine(output,"extended-blood-scene-clear.png"));
        Require(scene.bytes.SequenceEqual(baseline.bytes),"Scene reset retained blood pixels");
        ApplyExtendedFx(engine,catalog,84,1,0,$";p,1,{style},512,240,1000,100,173,1");
        ApplyExtendedFx(engine,catalog,84,2,9);Require(engine.BuildDraw().Count==0,"Large tick gap retained blood");
        var gap=await RenderExtendedFx(session,engine.BuildDraw(),Path.Combine(output,"extended-blood-gap-clear.png"));
        Require(gap.bytes.SequenceEqual(baseline.bytes),"Large-gap cleanup retained blood pixels");
        return new{seed=173,paused=true,landedAt,landing=landings.Select(l=>new{l.Id,l.Variant,l.X,l.Y}).Single(),
            onceOnly=true,sceneReset=true,largeGap=true,rows,
            boundary="Production parser and managed visual lifecycle rendered through native D3D11. No AS2 collision, acid damage, save, real-game timing or human proof."};
    }
}
#endif
