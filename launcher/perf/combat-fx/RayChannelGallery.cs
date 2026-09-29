using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    // A real parser/engine/light/native replay. The Flash suite owns collision
    // and settlement evidence; this process never opens a player save.
    private static async Task RunRayChannelGallery(string root,string module,string output,
        IntPtr source,IntPtr target,string trace)
    {
        var scenes=new Dictionary<string,List<string>>(StringComparer.Ordinal);
        string current=null;
        foreach(string line in File.ReadLines(trace)) {
            const string sceneTag="[RAY_RATE_SCENE] ",wireTag="[RAY_RATE_WIRE] ";
            if(line.StartsWith(sceneTag,StringComparison.Ordinal)) {
                current=line[sceneTag.Length..].Trim();
                Require(current.Length>0 && current.All(c=>char.IsAsciiLetterOrDigit(c)||c=='-'||c=='_'),"Unsafe scene key");
                Require(scenes.TryAdd(current,new()),"Repeated rate scene "+current);
            } else if(current!=null && line.StartsWith(wireTag,StringComparison.Ordinal))
                scenes[current].Add(line[wireTag.Length..]);
        }
        Require(scenes.Count>0,"No real AS2 rate wires in trace");
        using var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target);
        session.Mode(0);await WaitFor(()=>session.Read().Presented>0,session,"channel capture");
        var size=session.ReadCaptureSize();session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
        session.Matrix(Grade(1,1,1));
        var fx=CombatFxCatalog.Load(root);session.CombatFxAtlas(fx);
        await WaitFor(()=>session.CombatFxReady,session,"channel light resources");
        var preset=WorldLightingPreset.Load(Path.Combine(root,"launcher/data/world-lighting/preset.json"),Console.Error.WriteLine);
        Require(preset.LutSet!=null,"Missing production LUT");session.SetLut(preset.LutSet.BlendLevel(0));
        var lighting=RayLightingCatalog.Load(root);
        float response=fx.MaximumLightResponse;
        var rows=new List<object>();
        RayVisualDrawFrame budgetSource=null;
        string HashFile(string path)=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
        foreach(var scene in scenes) {
            Require(scene.Value.Count>=30,"Rate replay too short: "+scene.Key);
            var engine=new RayVisualEngine();engine.ConfigureLighting(lighting);
            var lights=new WorldLightComposer(response);
            session.ClearRayFrame();session.ClearCombatFxFrame();
            await Task.Delay(160);
            var before=session.Read();var timer=Stopwatch.StartNew();
            var cpu=new List<double>();var lateness=new List<double>();var presentObservations=new List<double>();
            int peakDraw=0,peakLights=0,peakActive=0,wireBytes=0,firstTick=-1,lastTick=-1;
            foreach(string wire in scene.Value) {
                long began=Stopwatch.GetTimestamp();
                Require(RayVisualFrame.TryParse(wire,out var frame),"Rate parse rejected: "+scene.Key);
                Require(engine.Apply(frame,1),"Rate sequence rejected: "+scene.Key);
                var draw=engine.BuildDraw();lights.SetRays(draw);var lightDraw=lights.Compose(0,0,1);
                if(budgetSource==null && draw.Count>0 && draw.LightCount>0) {
                    budgetSource=new RayVisualDrawFrame(draw.Count){Count=draw.Count,LightCount=draw.LightCount};
                    Array.Copy(draw.Data,budgetSource.Data,draw.Count*32);
                    Array.Copy(draw.Lights,budgetSource.Lights,draw.LightCount);
                }
                session.RayFrame(draw,0,0,1);session.CombatFxFrame(lightDraw,0,0,1);
                cpu.Add(Stopwatch.GetElapsedTime(began).TotalMilliseconds);
                peakDraw=Math.Max(peakDraw,draw.Count);peakLights=Math.Max(peakLights,lightDraw.LightCount);
                peakActive=Math.Max(peakActive,engine.ActiveCount);wireBytes+=wire.Length;
                if(firstTick<0)firstTick=frame.GameTick;
                lastTick=frame.GameTick;
                double due=(frame.GameTick-firstTick+1)*(1000.0/30.0);
                lateness.Add(Math.Max(0,timer.Elapsed.TotalMilliseconds-due));
                double wait=due-timer.Elapsed.TotalMilliseconds;
                if(wait>1)await Task.Delay(TimeSpan.FromMilliseconds(wait));
                var state=session.Read();
                Require(state.State<=1 && state.Error>=0,"Rate compositor failed: "+state.Message);
                presentObservations.Add(state.PresentMs);
            }
            timer.Stop();var after=session.Read();
            Require(after.Presented>before.Presented,"No presents in "+scene.Key);
            var row=new {name=scene.Key,ticks=lastTick-firstTick+1,wireFrames=scene.Value.Count,wireBytes,
                elapsedMs=timer.Elapsed.TotalMilliseconds,peakActive,peakDraw,peakLights,
                parserEngineLightsUploadMs=ChannelPercentiles(cpu),schedulerLatenessMs=ChannelPercentiles(lateness),
                workerPresentObservationsMs=ChannelPercentiles(presentObservations),
                presents=after.Presented-before.Presented,after.Adapter};
            rows.Add(row);
            File.WriteAllText(Path.Combine(output,scene.Key+".json"),JsonSerializer.Serialize(row,new JsonSerializerOptions{WriteIndented=true}));
            Console.WriteLine($"RATE {scene.Key}: {scene.Value.Count} ticks, active={peakActive}, draw={peakDraw}, lights={peakLights}, presents={after.Presented-before.Presented}");
            // Readback is outside the timed path. Real widths/opacity are never
            // reduced to make the pressure loop appear cheaper.
            var preview=new RayVisualEngine();preview.ConfigureLighting(lighting);lights.Reset();
            foreach(string wire in scene.Value.Take(45)) {
                Require(RayVisualFrame.TryParse(wire,out var frame) && preview.Apply(frame,1),"Preview replay rejected");
            }
            var picture=preview.BuildDraw();lights.SetRays(picture);
            session.RayFrame(picture,0,0,1);session.CombatFxFrame(lights.Compose(0,0,1),0,0,1);
            Grab(session,Path.Combine(output,scene.Key+".png"));
        }
        session.ClearRayFrame();session.ClearCombatFxFrame();
        Require(budgetSource!=null,"No actual AS2 ray lights were exercised");
        var fullLightBudget=await CheckRayChannelBudget(session,response,budgetSource,output);
        var proof=new {schema="cf7-ray-channel-replay.v1",utc=DateTime.UtcNow,trace,traceSha256=HashFile(trace),
            nativeDll=module,nativeSha256=HashFile(module),coreSha256=HashFile(typeof(RayVisualEngine).Assembly.Location),rows,fullLightBudget,
            boundary="Actual AS2 F7 replay at 30 Hz through parser, engine, world-light composer and GPU, with authored widths and opacity. No live socket, concurrent Flash/AI load, GPU timestamp queries or battle FPS. Worker Present observations can repeat a sample. Readback excluded from timed loop."};
        File.WriteAllText(Path.Combine(output,"channel-proof.json"),JsonSerializer.Serialize(proof,new JsonSerializerOptions{WriteIndented=true}));
    }

    private static object ChannelPercentiles(List<double> values)
    {
        double[] sorted=values.Order().ToArray();
        double At(double q)=>sorted[Math.Clamp((int)Math.Ceiling(sorted.Length*q)-1,0,sorted.Length-1)];
        return new {samples=sorted.Length,mean=sorted.Average(),p50=At(.50),p95=At(.95),p99=At(.99),max=sorted[^1]};
    }

    private static void CheckTeslaZeroLength(NativeCompositorSession session,string output,RayVisualDrawFrame source)
    {
        session.ClearRayFrame();var background=Grab(session,Path.Combine(output,"tesla-empty-background.png"));
        var empty=new RayVisualDrawFrame(1){Count=1};Array.Copy(source.Data,empty.Data,32);
        empty.Data[7]=1;empty.Data[27]=0;
        foreach(float fraction in new[]{0f,.25f,.75f}) {
            empty.Data[0]=empty.Data[2]=300+fraction;empty.Data[1]=empty.Data[3]=288+fraction;
            session.RayFrame(empty,0,0,1);
            var result=Grab(session,Path.Combine(output,"tesla-empty-"+fraction.ToString(CultureInfo.InvariantCulture)+".png"));
            Require(Changed(background,result,new Rectangle(0,0,1024,576))==0,"Coincident Tesla endpoints emitted a phantom flash");
        }
        session.ClearRayFrame();
    }

    private static async Task RenderTeslaStudy(NativeCompositorSession session,string output,RayVisualDrawFrame source)
    {
        string folder=Path.Combine(output,"tesla-motion");Directory.CreateDirectory(folder);
        var draw=new RayVisualDrawFrame(1){Count=1};
        Array.Copy(source.Data,draw.Data,32);float[] d=draw.Data;
        d[0]=60;d[1]=288;d[2]=960;d[3]=288;
        float totalLife=d[13];var frames=new List<string>();
        // This labelled clock study isolates the new electrical motion. The
        // rate replay above is the separate proof of actual AS2/channel timing.
        for(int tick=0;tick<60;tick++) {
            int shotAge=tick<42?tick%3:tick-39;
            d[12]=Math.Min(tick,42);d[27]=shotAge;
            d[7]=shotAge>=totalLife?0:shotAge<3?1:Math.Clamp(1-(shotAge-3)/Math.Max(1,totalLife-3),0,1);
            session.RayFrame(draw,0,0,1);
            await Task.Delay(34);
            string file=$"frame-{tick:D2}.png";
            try {Grab(session,Path.Combine(folder,file));}
            catch {
                File.WriteAllText(Path.Combine(folder,"capture-failure.json"),JsonSerializer.Serialize(
                    new {tick,native=session.Read()},new JsonSerializerOptions{IncludeFields=true,WriteIndented=true}));
                throw;
            }
            frames.Add(file);
            await Task.Yield();
        }
        File.WriteAllText(Path.Combine(folder,"frames.json"),JsonSerializer.Serialize(frames));
        File.WriteAllText(Path.Combine(folder,"index.html"),"""
<!doctype html><meta charset="utf-8"><title>磁暴放电动态样张</title>
<style>body{margin:24px;background:#10151c;color:#dce6ef;font:16px system-ui}canvas{display:block;width:100%;max-width:1200px;background:#000}button,input{margin:12px 12px 12px 0}p{max-width:960px;line-height:1.7}</style>
<h1>磁暴放电动态样张</h1><p>真实 XML 调色与束体参数；固定展示长度，30 Hz 播放原生 GPU 帧。演示连发、稳定通道和收束，不代表角色实战或伤害时序验收。</p>
<canvas width="1024" height="576"></canvas><button id="play">暂停</button><input id="frame" type="range" min="0" max="59" value="0"><span id="label"></span>
<script>const c=document.querySelector('canvas'),ctx=c.getContext('2d'),slider=document.querySelector('#frame'),label=document.querySelector('#label');let images=[],tick=0,playing=true;
Promise.all(Array.from({length:60},(_,i)=>new Promise(resolve=>{const im=new Image();im.onload=()=>resolve(im);im.src='frame-'+String(i).padStart(2,'0')+'.png';}))).then(a=>{images=a;setInterval(()=>{if(playing)tick=(tick+1)%60;ctx.drawImage(images[tick],0,0);slider.value=tick;label.textContent='帧 '+tick;},1000/30);});
document.querySelector('#play').onclick=e=>{playing=!playing;e.target.textContent=playing?'暂停':'播放';};slider.oninput=()=>{tick=+slider.value;playing=false;document.querySelector('#play').textContent='播放';};</script>
""");
    }
}
