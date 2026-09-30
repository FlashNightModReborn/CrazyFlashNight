#if !PERF_BASELINE
using System.Drawing;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    private static async Task RunCacheGallery(string root,string module,string output,IntPtr source,IntPtr target,Action<Rectangle> resize)
    {
        var rows=new List<object>();
        byte[] atlas=new byte[8*4*4];
        for(int y=0;y<4;y++)for(int x=0;x<8;x++) {int at=(y*8+x)*4;atlas[at+(x<4?2:0)]=255;atlas[at+3]=255;}
        using(var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target)) {
            await WaitFor(()=>session.Read().Presented>0,session,"cache initial capture");
            var size=session.ReadCaptureSize();session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
            session.CombatFxAtlas(atlas,8,4);
            await WaitFor(()=>session.CombatFxReady,session,"cache atlas");
            session.Matrix(Grade(.12f,.12f,.12f));
            var draw=Solid(true);draw.LightCount=1;draw.MaximumLightResponse=.8f;
            float[] lamp={512,288,140,1,1,.7f,.3f,0,0,0,0,0,0,0,0,0};
            Array.Copy(lamp,draw.Lights,16);
            float cameraX=0,cameraY=0,cameraScale=1;
            var before=Work(session);session.CombatFxFrame(draw,0,0,1);
            await WaitFor(()=>Work(session).LightDraws>before.LightDraws && Work(session).FxUploads>before.FxUploads,session,"first cache content");
            var first=Work(session);
            Require(first.FxUploads-before.FxUploads==1,"Two sprite layers uploaded the same buffer twice");
            var original=Grab(session,Path.Combine(output,"cache-first.png"));
            var steadyStart=Work(session);
            await WaitFor(()=>Work(session).Compositions>=steadyStart.Compositions+12,session,"static cache reuse");
            var steadyEnd=Work(session);
            Require(steadyEnd.LightDraws==steadyStart.LightDraws && steadyEnd.FxUploads==steadyStart.FxUploads,"Static content still rebuilds/uploads");
            Require(steadyEnd.LightCacheHits>=steadyStart.LightCacheHits+12,"Static light field did not hit the cache");
            Require(original.bytes.SequenceEqual(Grab(session,Path.Combine(output,"cache-steady.png")).bytes),"Cached output differs from its first draw");
            rows.Add(new {stage="static",firstUploadCount=first.FxUploads-before.FxUploads,
                frames=steadyEnd.Compositions-steadyStart.Compositions,lightDraws=steadyEnd.LightDraws-steadyStart.LightDraws,
                fxUploads=steadyEnd.FxUploads-steadyStart.FxUploads,cacheHits=steadyEnd.LightCacheHits-steadyStart.LightCacheHits,pixelsEqual=true});

            async Task Invalidate(string stage,Action update,bool spriteChanged=false) {
                var a=Work(session);update();
                await WaitFor(()=>Work(session).LightDraws>a.LightDraws,session,stage);
                var b=Work(session);
                if(!spriteChanged)Require(b.FxUploads==a.FxUploads,stage+" unnecessarily uploaded unchanged sprite data");
                Grab(session,Path.Combine(output,"cache-"+stage+".png"));
                rows.Add(new {stage,lightDraws=b.LightDraws-a.LightDraws,fxUploads=b.FxUploads-a.FxUploads});
            }
            await Invalidate("lamp-move",()=>{draw.Lights[0]+=64;session.CombatFxFrame(draw,cameraX,cameraY,cameraScale);});
            await Invalidate("lamp-energy",()=>{draw.Lights[3]=.5f;session.CombatFxFrame(draw,cameraX,cameraY,cameraScale);});
            await Invalidate("camera",()=>{cameraX=30;cameraY=-10;cameraScale=1.25f;session.CombatFxFrame(draw,cameraX,cameraY,cameraScale);});
            await Invalidate("palette",()=>session.Matrix(Grade(.1f,.2f,.3f)));
            await Invalidate("viewport",()=>resize(new Rectangle(80,80,1152,648)));

            var changed=Work(session);draw.Data[0]+=35;session.CombatFxFrame(draw,cameraX,cameraY,cameraScale);
            await WaitFor(()=>Work(session).FxUploads>changed.FxUploads,session,"sprite change");
            var afterSprite=Work(session);
            Require(afterSprite.FxUploads-changed.FxUploads==1,"Changed sprite data did not upload exactly once");
            Require(afterSprite.LightDraws==changed.LightDraws,"Sprite-only change rebuilt the light field");
            rows.Add(new {stage="sprite-only",fxUploads=afterSprite.FxUploads-changed.FxUploads,lightDraws=0});

            draw.LightCount=0;session.CombatFxFrame(draw,cameraX,cameraY,cameraScale);
            var dark=Grab(session,Path.Combine(output,"cache-cleared.png"));
            draw.LightCount=1;
            await Invalidate("relight",()=>session.CombatFxFrame(draw,cameraX,cameraY,cameraScale));
            var lit=Grab(session,Path.Combine(output,"cache-relit.png"));
            Require(!dark.bytes.SequenceEqual(lit.bytes),"Restored light did not affect the world");
            draw.LightCount=0;session.CombatFxFrame(draw,cameraX,cameraY,cameraScale);
            Require(dark.bytes.SequenceEqual(Grab(session,Path.Combine(output,"cache-recleared.png")).bytes),"Cleared light left cached pixels");
            draw.LightCount=1;session.CombatFxFrame(draw,cameraX,cameraY,cameraScale);
            await WaitFor(()=>Work(session).LightDraws>afterSprite.LightDraws,session,"light before suspend");
            session.Active(false);await Task.Delay(180);var stopped=Work(session);await Task.Delay(150);
            Require(Work(session).Compositions==stopped.Compositions,"Inactive cache session kept composing");
            session.Active(true);
            await WaitFor(()=>Work(session).LightDraws>stopped.LightDraws,session,"capture generation resume");
            rows.Add(new {stage="resume",lightDraws=Work(session).LightDraws-stopped.LightDraws,stopped=true});
        }
        // New renderer resources must never inherit an old session's cache readiness.
        using(var restarted=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target)) {
            await WaitFor(()=>restarted.Read().Presented>0,restarted,"new cache session");
            restarted.CombatFxAtlas(atlas,8,4);
            await WaitFor(()=>restarted.CombatFxReady,restarted,"new cache atlas");
            var draw=Solid(true);draw.LightCount=1;draw.MaximumLightResponse=.8f;
            float[] lamp={512,288,140,1,1,.7f,.3f,0,0,0,0,0,0,0,0,0,0};Array.Copy(lamp,draw.Lights,16);
            restarted.CombatFxFrame(draw,0,0,1);
            await WaitFor(()=>Work(restarted).LightDraws>0 && Work(restarted).FxUploads>0,restarted,"new resources first draw");
            rows.Add(new {stage="new-session",firstLightDraw=true,firstSpriteUpload=true});
        }
        File.WriteAllText(Path.Combine(output,"cache-proof.json"),JsonSerializer.Serialize(new {
            schema="cf7-native-cache-proof.v1",module=Path.GetFullPath(module),
            nativeSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module))),rows,
            boundary="Real WGC/D3D output and worker counters on controlled source/output windows. No Flash gameplay, GPU timing, power or thermal qualification."
        },new JsonSerializerOptions{WriteIndented=true}));
        Console.WriteLine("CACHE: reuse, pixel equality, lamp/camera/palette/viewport invalidation, clear, resume and new session passed");
    }
    private static NativeCompositorSession.WorkStats Work(NativeCompositorSession session) =>
        session.ReadWork() ?? throw new InvalidOperationException("Paired native work counters unavailable");
}
#endif
