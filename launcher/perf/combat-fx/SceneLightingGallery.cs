#if !PERF_BASELINE
using System.Drawing;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    private static async Task RunSceneLightGallery(string root,string module,string output,IntPtr source,IntPtr target)
    {
        var rows=new List<object>();
        using var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target);
        await WaitFor(()=>session.Read().Presented>0,session,"scene capture");
        var size=session.ReadCaptureSize();session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
        byte[] atlas=new byte[8*4*4];for(int y=0;y<4;y++)for(int x=0;x<8;x++){int at=(y*8+x)*4;atlas[at+(x<4?2:0)]=255;atlas[at+3]=255;}
        session.CombatFxAtlas(atlas,8,4);await WaitFor(()=>session.CombatFxReady,session,"scene atlas");
        var draw=Solid(true);draw.MaximumLightResponse=.78f;
        session.Matrix(Grade(.12f,.12f,.12f));session.CombatFxFrame(draw,0,0,1);
        await WaitFor(()=>Work(session).Compositions>4,session,"scene baseline");
        var baseline=Grab(session,Path.Combine(output,"scene-baseline.png"));
        var lamps=new float[32*16];
        for(int i=0;i<32;i++) {int at=i*16;lamps[at]=100+(i%8)*110;lamps[at+1]=110+(i/8)*110;lamps[at+2]=70;
            lamps[at+3]=.55f;lamps[at+4]=1;lamps[at+5]=.7f;lamps[at+6]=.35f;}
        session.SceneLightField(lamps,32,.78f);
        await WaitFor(()=>session.ReadSceneLights().Builds>=1,session,"32 scene lights");
        var first=Grab(session,Path.Combine(output,"scene-static-32.png"));
        Require(!baseline.bytes.SequenceEqual(first.bytes),"Cached scene field did not affect material pixels");
        var stable=session.ReadSceneLights();var before=Work(session);
        await WaitFor(()=>Work(session).Compositions>=before.Compositions+12,session,"scene reuse");
        Require(session.ReadSceneLights().Builds==stable.Builds,"Static scene rebuilt without changes");
        Require(first.bytes.SequenceEqual(Grab(session,Path.Combine(output,"scene-static-steady.png")).bytes),"Cached scene pixels changed");
        rows.Add(new{stage="static-32",count=32,builds=session.ReadSceneLights().Builds,cacheHits=session.ReadSceneLights().CacheHits,width=stable.Width,height=stable.Height,pixelsChanged=true});
        var draws=Work(session);session.CombatFxFrame(draw,-120,-40,1.25f);
        await WaitFor(()=>Work(session).Compositions>draws.Compositions+3,session,"scene camera");
        Require(session.ReadSceneLights().Builds==stable.Builds,"Camera pan/zoom rebuilt world scene field");
        var moved=Grab(session,Path.Combine(output,"scene-camera.png"));Require(!first.bytes.SequenceEqual(moved.bytes),"Scene field did not follow camera");
        rows.Add(new{stage="camera-pan-zoom",additionalSceneBuilds=0});
        draw.LightCount=1;float[] dynamic={512,288,130,1.2f,1,.4f,.2f,0,0,0,0,0,0,0,0,0,0};Array.Copy(dynamic,draw.Lights,16);
        draws=Work(session);session.CombatFxFrame(draw,-120,-40,1.25f);
        await WaitFor(()=>Work(session).LightDraws>draws.LightDraws,session,"scene mixed dynamic");
        Grab(session,Path.Combine(output,"scene-mixed.png"));
        draws=Work(session);draw.Lights[3]=.4f;session.CombatFxFrame(draw,-120,-40,1.25f);
        await WaitFor(()=>Work(session).LightDraws>draws.LightDraws,session,"dynamic energy");
        Require(session.ReadSceneLights().Builds==stable.Builds,"Dynamic light invalidated cached scene field");
        rows.Add(new{stage="dynamic-energy",additionalSceneBuilds=0});
        session.Matrix(Grade(.08f,.45f,.08f));draws=Work(session);
        await WaitFor(()=>Work(session).Compositions>draws.Compositions+3,session,"scene night palette");
        Grab(session,Path.Combine(output,"scene-night-vision.png"));Require(session.ReadSceneLights().Builds==stable.Builds,"Palette invalidated cached scene field");
        lamps[3]=.2f;session.SceneLightField(lamps,32,.78f);
        await WaitFor(()=>session.ReadSceneLights().Builds>stable.Builds,session,"scene state change");
        rows.Add(new{stage="scene-state-update",builds=session.ReadSceneLights().Builds});
        session.SceneLightField(Array.Empty<float>(),0,.78f);draw.LightCount=0;session.Matrix(Grade(.12f,.12f,.12f));
        draws=Work(session);session.CombatFxFrame(draw,0,0,1);
        await WaitFor(()=>session.ReadSceneLights().Count==0 && Work(session).Compositions>draws.Compositions+3,session,"scene clear");
        var cleared=Grab(session,Path.Combine(output,"scene-cleared.png"));Require(baseline.bytes.SequenceEqual(cleared.bytes),"Scene clear retained light");
        rows.Add(new{stage="scene-clear",pixelsEqual=true});
        var report=new{success=true,kind="scene-light-v1",nativeSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module))),rows,
            final=new{scene=session.ReadSceneLights().Count,builds=session.ReadSceneLights().Builds,cacheHits=session.ReadSceneLights().CacheHits}};
        File.WriteAllText(Path.Combine(output,"scene-light-proof.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));
        Console.WriteLine("SCENE: 32 cached lights, stable pixels, pan/zoom reuse, dynamic isolation, palette, state and clear passed");
    }
}
#endif
