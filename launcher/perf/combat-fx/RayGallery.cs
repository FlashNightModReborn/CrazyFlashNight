using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    private static async Task RunRayGallery(string root,string module,string output,IntPtr source,IntPtr target,
        Action<bool> blackSource,string tracePath)
    {
        var scenes=new Dictionary<string,List<string>>(StringComparer.Ordinal);
        string current=null;
        foreach(string line in File.ReadLines(tracePath)) {
            const string sceneTag="[RAY_GPU_SCENE] ",wireTag="[RAY_GPU_WIRE] ";
            if(line.StartsWith(sceneTag,StringComparison.Ordinal)) {
                current=line.Substring(sceneTag.Length).Trim();
                if(!scenes.TryAdd(current,new List<string>()))throw new InvalidDataException("Repeated GPU scene "+current);
            } else if(current!=null && line.StartsWith(wireTag,StringComparison.Ordinal))
                scenes[current].Add(line.Substring(wireTag.Length));
        }
        Require(scenes.TryGetValue("gallery",out var gallery) && gallery.Count>0,"Missing fresh CS6 gallery wires");
        Require(scenes.TryGetValue("flame",out var flame) && flame.Count>=40,"Missing fresh CS6 flame playback");
        using var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target);
        session.Mode(0);await WaitFor(()=>session.Read().Presented>0,session,"ray capture/shaders");
        var size=session.ReadCaptureSize();session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
        session.Matrix(Grade(1,1,1));session.ClearRayFrame();
        var before=Grab(session,Path.Combine(output,"baseline.png"));
        var rayLighting=RayLightingCatalog.Load(root);
        var engine=new RayVisualEngine();engine.ConfigureLighting(rayLighting);
        var worldLights=new WorldLightComposer(CombatFxCatalog.Load(root).MaximumLightResponse);
        var styles=new HashSet<int>();RayVisualFrame last=null;
        foreach(string payload in gallery) {
            Require(RayVisualFrame.TryParse(payload,out var frame),"CS6 gallery wire rejected");
            Require(engine.Apply(frame,1),"CS6 gallery sequence rejected");last=frame;
            foreach(var config in frame.Configs)styles.Add(config.Style);
        }
        Require(styles.Count==12,"Actual CS6 style coverage must be twelve");
        Require(RayVisualFrame.TryParse($"{last.Epoch}|{last.Sequence+1}|{last.GameTick+1}|0;o,0,0",out var next),"heartbeat parse");
        Require(engine.Apply(next,1),"gallery advance rejected");
        var draw=engine.BuildDraw();Require(draw.Count>=12,"Gallery lost main beams");
        // BuildDraw reuses its buffer; keep this fixture before subsequent engine resets.
        var pressureSource=new RayVisualDrawFrame(draw.Count){Count=draw.Count,LightCount=draw.LightCount};
        Array.Copy(draw.Data,pressureSource.Data,draw.Count*32);
        Array.Copy(draw.Lights,pressureSource.Lights,draw.LightCount);
        session.RayFrame(draw,0,0,1);
        var full=Grab(session,Path.Combine(output,"ray-gallery.png"));
        var cells=new List<object>();
        for(int row=0;row<6;row++)for(int col=0;col<2;col++) {
            var rect=new Rectangle(col*512,row*96,512,96);
            int pixels=Changed(before,full,rect);
            Require(pixels>12,$"Ray cell {row*2+col} is blank ({pixels} changed pixels)");
            cells.Add(new {style=RayVisualCatalog.Styles[row*2+col],changedPixels=pixels});
        }
        session.RayFrame(draw,65,-25,.8f);var moved=Grab(session,Path.Combine(output,"ray-gallery-camera.png"));
        Require(Changed(full,moved,new Rectangle(0,0,1024,576))>100,"Ray camera transform did not change output");
        var preset=WorldLightingPreset.Load(Path.Combine(root,"launcher/data/world-lighting/preset.json"),Console.Error.WriteLine);
        Require(preset.LutSet!=null,"Production lighting LUT set unavailable");
        session.SetLut(preset.LutSet.BlendLevel(0));session.RayFrame(draw,0,0,1);
        Grab(session,Path.Combine(output,"ray-gallery-night.png"));
        session.ClearRayFrame();session.ClearLut();
        var cleared=Grab(session,Path.Combine(output,"ray-cleared.png"));
        Require(Changed(before,cleared,new Rectangle(0,0,1024,576))<4,"Cleared rays left pixels");

        var lightingProof=await CheckRayLighting(root,session,output,draw,worldLights,preset);

        engine.Reset();worldLights.Reset();session.SetLut(preset.LutSet.BlendLevel(0));
        var animation=new List<string>();int index=0;byte[] previous=null;int animated=0;
        int maximumFlameLights=0;
        foreach(string payload in flame) {
            Require(RayVisualFrame.TryParse(payload,out var frame),"CS6 flame wire rejected");
            Require(engine.Apply(frame,1),"CS6 flame update rejected");var flameDraw=engine.BuildDraw();
            session.RayFrame(flameDraw,0,0,1);worldLights.SetRays(flameDraw);
            var flameLighting=worldLights.Compose(0,0,1);session.CombatFxFrame(flameLighting,0,0,1);
            maximumFlameLights=Math.Max(maximumFlameLights,flameLighting.LightCount);
            if(index%3==0 || index==flame.Count-1) {
                string name=$"flame-{index:D3}.png";var picture=Grab(session,Path.Combine(output,name));
                byte[] hash=SHA256.HashData(picture.bytes);
                if(previous!=null && !hash.SequenceEqual(previous))animated++;
                previous=hash;animation.Add(name);
            }
            index++;
        }
        Require(animated>4,"Flame frames did not animate");
        Require(maximumFlameLights==3,"Three continuous flame channels must reuse exactly three lights");
        Require(engine.BuildDraw().LightCount==0,"Expired flame left light candidates");
        session.ClearRayFrame();worldLights.Reset();session.ClearCombatFxFrame();session.ClearLut();
        var nullDraw=new RayVisualDrawFrame();var bad=new RayVisualDrawFrame(1){Count=1};bad.Data[0]=float.NaN;
        bool rejected=false;try { session.RayFrame(bad,0,0,1); }catch(InvalidOperationException){ rejected=true; }
        Require(rejected,"Native ray NaN was accepted");session.RayFrame(nullDraw,0,0,1);
        var bulletProof=await CheckBulletGallery(root,session,output,before);
        var pressure=await CheckProjectilePressure(session,pressureSource,output);
        session.SetLut(preset.LutSet.BlendLevel(0));
        var fullLightBudget=await CheckRayChannelBudget(session,CombatFxCatalog.Load(root).MaximumLightResponse,pressureSource,output);
        var report=new {schema="cf7-ray-gallery.v1",utc=DateTime.UtcNow,sourceTrace=tracePath,
            sourceTraceSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(tracePath))),
            nativeSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module))),styles=cells,fullLightBudget,
            frames=flame.Count,animatedFrames=animated,camera=true,cleared=true,invalidRejected=true,
            lighting=lightingProof,lightingCatalogSha256=rayLighting.Sha256,maximumFlameLights,
            bulletProof,pressure,
            boundary="Fresh CS6 protocol replay through production parser/engine and real WGC/D3D11 compositor; not game-entry or human visual acceptance."};
        File.WriteAllText(Path.Combine(output,"ray-proof.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));
        string animationJson=JsonSerializer.Serialize(animation);
        string labels=string.Join(" · ",RayVisualCatalog.Styles);
        File.WriteAllText(Path.Combine(output,"index.html"),"<!doctype html><meta charset='utf-8'><title>射线迁移验收演示</title>"+
            "<style>body{background:#151a22;color:#dce7f3;font:16px system-ui;max-width:1100px;margin:30px auto}img{width:100%;background:#10141b;border-radius:8px}button{padding:8px 18px;margin:8px}p{line-height:1.6}section{margin:30px 0}</style>"+
            "<h1>射线迁移验收演示</h1><p>真实 CS6 参数与事件经过 C# 和原生 GPU 绘制。以下是受控演示场景。</p>"+
            "<section><h2>全部十二种风格</h2><p>按行从左到右："+labels+"</p><img src='ray-gallery.png'></section>"+
            "<section><h2>生产夜间调色</h2><img src='ray-gallery-night.png'></section>"+
            "<section><h2>射线环境照明对照</h2><p>相同束体、相同夜间环境：先看自身辉光，再看加入材质照明的结果。独立光场图隐藏束体，便于检查实际被照亮的地面。</p><button onclick=\"document.getElementById('lit').src='lighting-body-only.png'\">仅束体</button><button onclick=\"document.getElementById('lit').src='lighting-combined.png'\">束体＋环境光</button><button onclick=\"document.getElementById('lit').src='lighting-environment-only.png'\">仅环境光</button><img id='lit' src='lighting-combined.png'></section>"+
            "<section><h2>子弹八种样式</h2><p>按行从左到右：普通、加强普通、穿刺、次级穿刺、无壳穿刺、联弹穿刺、联弹次级穿刺、联弹无壳穿刺。每格依次为原尺寸、三倍放大、三倍镜像半透明。</p><img src='bullet-gallery.png'></section>"+
            "<section><h2>喷火束与暖光：横向、斜向、短束与阻挡收缩</h2><button id='toggle'>暂停 / 播放</button><img id='flame'></section>"+
            "<script>const frames="+animationJson+";let at=0,play=true;const im=document.getElementById('flame');im.src=frames[0];document.getElementById('toggle').onclick=()=>play=!play;setInterval(()=>{if(play){at=(at+1)%frames.length;im.src=frames[at]}},100)</script>");
        Console.WriteLine("PASS: twelve actual-CS6 ray styles, flame sequence, camera, native validation and cleanup");
    }
    private static async Task<object> CheckBulletGallery(string root,NativeCompositorSession session,string output,
        (byte[] bytes,int width,int height) baseline)
    {
        var catalog=BulletVisualCatalog.Load(root);session.BulletStyles(catalog);
        await WaitFor(()=>session.BulletResourcesReady,session,"bullet sprite atlas readiness");
        // No body/FX/ray is active and the captured material is static. A texture-only
        // update must be serviced independently of bullet pose/style or WGC changes.
        await Task.Delay(200);
        session.BulletAtlas(catalog.AtlasBgraPremultiplied,catalog.AtlasWidth,catalog.AtlasHeight);
        await WaitFor(()=>session.BulletResourcesReady,session,"idle bullet atlas replacement");
        var items=new List<BulletVisualInstance>();
        for(int i=0;i<catalog.Styles.Count;i++) {
            float x=(i%2)*512,y=(i/2)*144+72;
            items.Add(new BulletVisualInstance(i,x+45,y,0,100,100,100));
            items.Add(new BulletVisualInstance(i,x+140,y,12,300,300,100));
            items.Add(new BulletVisualInstance(i,x+450,y,-12,-300,300,50));
        }
        session.BulletFrame(BulletVisualFrame.Compose(1,1,items.ToArray(),null),0,0,1);
        var gallery=Grab(session,Path.Combine(output,"bullet-gallery.png"));var cells=new List<object>();
        for(int i=0;i<catalog.Styles.Count;i++) {
            int changed=Changed(baseline,gallery,new Rectangle(i%2*512,i/2*144,512,144));
            Require(changed>15,"Bullet style is blank: "+catalog.Styles[i].Id);
            cells.Add(new{style=catalog.Styles[i].Id,changedPixels=changed});
        }
        session.ClearBulletFrame();
        var cleared=Grab(session,Path.Combine(output,"bullet-cleared.png"));
        Require(Changed(baseline,cleared,new Rectangle(0,0,1024,576))<4,"Bullet clear left sprite pixels");
        return new{styles=cells,atlasReady=true,idleAtlasReplacement=true,cleared=true};
    }
    private static async Task<object> CheckProjectilePressure(NativeCompositorSession session,RayVisualDrawFrame gallery,string output)
    {
        var rows=new List<object>();
        // Limits exercise upload batching, not weapon density or additional production effects.
        foreach(int rayCount in new[]{16,64,256,1024,4096}) {
            // The expanded hard limit is an admission/clip check. Keep one visible
            // record; a full-screen 4096-ray soak belongs to the separate GPU study.
            bool capacityOnly=rayCount>1024;
            int bullets=capacityOnly?NativeCompositorSession.NativeBulletItemLimit:rayCount>=1024?4096:rayCount*4;
            var ray=new RayVisualDrawFrame(rayCount){Count=rayCount};
            for(int i=0;i<rayCount;i++) {
                int a=i*32,b=(i%gallery.Count)*32;Array.Copy(gallery.Data,b,ray.Data,a,32);
                float y=(i%32)*17+15;ray.Data[a]=25;ray.Data[a+1]=y;ray.Data[a+2]=980;ray.Data[a+3]=y;
                if(capacityOnly && i>0) {ray.Data[a]+=5000;ray.Data[a+2]+=5000;}
                ray.Data[a+7]=Math.Min(ray.Data[a+7],.18f);ray.Data[a+11]=Math.Min(ray.Data[a+11],2.5f);
            }
            var instances=new BulletVisualInstance[bullets];
            for(int i=0;i<bullets;i++)instances[i]=new BulletVisualInstance(i%8,
                capacityOnly&&i>0?5000:15+i%64*15,15+i/64*8,0,100,100,70);
            var bulletFrame=BulletVisualFrame.Compose(1,1,null,instances);
            session.BulletFrame(bulletFrame,0,0,1);session.RayFrame(ray,0,0,1);
            await Task.Delay(200);var start=session.Read();var watch=Stopwatch.StartNew();
            double totalSubmit=0,maxSubmit=0;int samples=48;
            for(int tick=0;tick<samples;tick++) {
                for(int i=0;i<rayCount;i++)ray.Data[i*32+12]=tick*.3f;
                long began=Stopwatch.GetTimestamp();session.RayFrame(ray,0,0,1);session.BulletFrame(bulletFrame,0,0,1);
                double ms=Stopwatch.GetElapsedTime(began).TotalMilliseconds;totalSubmit+=ms;maxSubmit=Math.Max(maxSubmit,ms);
                await Task.Delay(20);
            }
            var end=session.Read();Require(end.State<=1&&end.Error>=0,"Compositor pressure failed: "+end.Message);
            Require(end.Presented>start.Presented,"Compositor pressure did not present");
            rows.Add(new{rayRecords=rayCount,bulletRecords=bullets,capacityOnly,samples,elapsedMs=watch.Elapsed.TotalMilliseconds,
                setterMeanMs=totalSubmit/samples,setterMaxMs=maxSubmit,presents=end.Presented-start.Presented,
                workerLastSubmitMs=end.SubmitMs,workerLastPresentMs=end.PresentMs,adapter=end.Adapter});
            if(rayCount==4096)Grab(session,Path.Combine(output,"batch-limits.png"));
        }
        session.ClearRayFrame();session.ClearBulletFrame();
        return new{rows,boundary="Controlled CPU setter timings and real compositor presents. Ray records include decoration. The largest tier checks expanded-capacity admission and clipping with one visible ray/bullet, not full-screen throughput. Not GPU timer queries, game collision, battle FPS or weak-machine qualification."};
    }
    private static int Changed((byte[] bytes,int width,int height) a,(byte[] bytes,int width,int height) b,Rectangle region)
    {
        Require(a.width==b.width&&a.height==b.height,"Capture geometry changed during a pixel comparison");
        int result=0;
        int left=region.Left*a.width/1024,right=region.Right*a.width/1024,top=region.Top*a.height/576,bottom=region.Bottom*a.height/576;
        for(int y=top;y<bottom;y++)for(int x=left;x<right;x++) {
            int at=(y*a.width+x)*4;
            if(Math.Abs(a.bytes[at]-b.bytes[at])>5||Math.Abs(a.bytes[at+1]-b.bytes[at+1])>5||Math.Abs(a.bytes[at+2]-b.bytes[at+2])>5)result++;
        }
        return result;
    }
}
