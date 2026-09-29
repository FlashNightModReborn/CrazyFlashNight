using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    // Separate, controlled occupancy proof. The normal rate replay is the
    // authority for AS2 shot/channel timing; this stage holds one captured
    // emission at sixteen translated locations without inventing more shots.
    private static async Task<object> CheckRayChannelBudget(NativeCompositorSession session,float response,
        RayVisualDrawFrame source,string output)
    {
        const int count=16,frames=60;
        Require(source!=null&&source.Count>0&&source.LightCount>0,"Full-light budget needs an actual lit AS2 draw");
        Require(source.Count*RayVisualCatalog.Stride<=source.Data.Length&&source.LightCount<=source.Lights.Length,
            "Invalid source frame for full-light budget");
        Require(response>0&&session.CombatFxReady,"Full-light budget requires ready light resources and nonzero response");
        int primary=-1,lightIndex=-1;
        for(int light=0;light<source.LightCount&&primary<0;light++) {
            var candidate=source.Lights[light];
            if(candidate.Kind is not (1 or 2)||candidate.Energy<=0)continue;
            for(int body=0;body<source.Count;body++) {
                int at=body*RayVisualCatalog.Stride;
                if(source.Data[at+15]<0||source.Data[at+15]>=12||source.Data[at+7]<=0)continue;
                double dx=source.Data[at+2]-source.Data[at],dy=source.Data[at+3]-source.Data[at+1];
                double length=Math.Sqrt(dx*dx+dy*dy);
                if(length<1||Math.Abs(source.Data[at]-candidate.X)>.01||Math.Abs(source.Data[at+1]-candidate.Y)>.01)continue;
                // The light may have an authored length cap, but it must follow
                // this exact primary's axis, never an unrelated branch/ornament.
                if(candidate.Length>length+.01||Math.Abs(dx/length-candidate.DirectionX)>.001
                    ||Math.Abs(dy/length-candidate.DirectionY)>.001)continue;
                primary=body;lightIndex=light;break;
            }
        }
        Require(primary>=0,"No real main body matches a source light's origin and direction");
        int sourceAt=primary*RayVisualCatalog.Stride;
        float[] original=source.Data.Skip(sourceAt).Take(RayVisualCatalog.Stride).ToArray();
        var originalLight=source.Lights[lightIndex];var originalLightData=new float[16];originalLight.WriteTo(originalLightData,0);
        float vx=original[2]-original[0],vy=original[3]-original[1];
        double originalLength=Math.Sqrt((double)vx*vx+(double)vy*vy);
        bool longBeam=originalLength>512,horizontal=Math.Abs(vx)>=Math.Abs(vy);
        string layout=longBeam?(horizontal?"sixteen horizontal rows":"sixteen vertical columns"):"four by four grid";
        var draw=new RayVisualDrawFrame(count){Count=count,LightCount=count};
        var positions=new List<object>();
        for(int i=0;i<count;i++) {
            float centerX=longBeam?(horizontal?512:32+i*64):128+(i%4)*256;
            float centerY=longBeam?(horizontal?18+i*36:288):72+(i/4)*144;
            float dx=centerX-(original[0]+original[2])*.5f,dy=centerY-(original[1]+original[3])*.5f;
            int at=i*RayVisualCatalog.Stride;Array.Copy(original,0,draw.Data,at,RayVisualCatalog.Stride);
            draw.Data[at]+=dx;draw.Data[at+1]+=dy;draw.Data[at+2]+=dx;draw.Data[at+3]+=dy;
            long key=-1000L-i; // Explicit fixture-local identities, not forged F7 events.
            draw.Lights[i]=new WorldLightCandidate(key,originalLight.Priority,originalLight.X+dx,originalLight.Y+dy,
                originalLight.Length,originalLight.Energy,originalLight.R,originalLight.G,originalLight.B,
                originalLight.Kind,originalLight.DirectionX,originalLight.DirectionY,originalLight.HalfWidth,
                originalLight.NearRadius>0?originalLight.NearX+dx:0,
                originalLight.NearRadius>0?originalLight.NearY+dy:0,originalLight.NearRadius,originalLight.NearEnergy);
            Require(original.Skip(4).SequenceEqual(draw.Data.Skip(at+4).Take(RayVisualCatalog.Stride-4)),
                "Full-light fixture changed an authored non-position field");
            positions.Add(new {key,centerX,centerY,translationX=dx,translationY=dy});
        }
        Require(draw.Lights.Take(count).Select(p=>p.Key).Distinct().Count()==count,"Full-light identities are not independent");
        var composer=new WorldLightComposer(response);composer.SetRays(draw);
        var selected=composer.Compose(0,0,1);
        Require(selected.LightCount==count&&selected.LightIds.Take(count).Distinct().Count()==count,
            "Composer did not admit all sixteen distinct on-screen lights");
        var options=new JsonSerializerOptions{WriteIndented=true};
        byte[] sourceBytes=new byte[original.Length*sizeof(float)];Buffer.BlockCopy(original,0,sourceBytes,0,sourceBytes.Length);
        File.WriteAllText(Path.Combine(output,"channel-budget-input.json"),JsonSerializer.Serialize(new {
            schema="cf7-ray-channel-budget-input.v1",sourcePrimaryIndex=primary,sourceLightIndex=lightIndex,
            sourcePrimary=original,sourcePrimarySha256=Convert.ToHexString(SHA256.HashData(sourceBytes)),
            sourceLightKey=originalLight.Key,sourceLightPriority=originalLight.Priority,sourceLight=originalLightData,
            layout,positions,primaryCount=count,lightCount=selected.LightCount,
            translatedPrimaryRecords=draw.Data,selectedLights=selected.Lights.Take(count*16).ToArray(),
            boundary="Sixteen translated copies of one actual AS2 primary and its actual light. Every width, alpha, length, color, energy and captured clock is retained. A controlled occupancy stage, not sixteen AS2 shooters or a weapon-rate measurement."
        },options));
        session.ClearRayFrame();session.ClearCombatFxFrame();
        var dark=Grab(session,Path.Combine(output,"channel-budget-baseline.png"));
        try {
            ulong warmStart=session.Read().Presented;
            session.RayFrame(draw,0,0,1);session.CombatFxFrame(selected,0,0,1);
            await WaitFor(()=>session.Read().Presented>warmStart,session,"full-light warmup");
            var before=session.Read();var timer=Stopwatch.StartNew();
            var cpu=new List<double>(frames);var lateness=new List<double>(frames);var presentObservations=new List<double>(frames);
            for(int tick=0;tick<frames;tick++) {
                long began=Stopwatch.GetTimestamp();
                composer.SetRays(draw);selected=composer.Compose(0,0,1);
                Require(selected.LightCount==count,"Full-light occupancy dropped during the timed stage");
                session.RayFrame(draw,0,0,1);session.CombatFxFrame(selected,0,0,1);
                cpu.Add(Stopwatch.GetElapsedTime(began).TotalMilliseconds);
                double due=(tick+1)*(1000d/30);
                lateness.Add(Math.Max(0,timer.Elapsed.TotalMilliseconds-due));
                double wait=due-timer.Elapsed.TotalMilliseconds;
                if(wait>1)await Task.Delay(TimeSpan.FromMilliseconds(wait));
                var state=session.Read();
                Require(state.State<=1&&state.Error>=0,"Full-light compositor failure: "+state.Message);
                presentObservations.Add(state.PresentMs);
            }
            timer.Stop();var after=session.Read();
            Require(after.Presented>before.Presented,"Full-light stage produced no real presents");
            Require(after.CpuReadbacks==before.CpuReadbacks,"A GPU readback entered the full-light timed interval");
            // No screenshot or CPU texture readback occurs before timer.Stop.
            Grab(session,Path.Combine(output,"channel-budget-16-combined.png"));
            session.ClearRayFrame();
            var environment=Grab(session,Path.Combine(output,"channel-budget-16-environment.png"));
            int litPixels=Changed(dark,environment,new Rectangle(0,0,1024,576));
            Require(litPixels>0,"Sixteen selected lights produced no environment-light pixels");
            session.ClearCombatFxFrame();
            var cleared=Grab(session,Path.Combine(output,"channel-budget-cleared.png"));
            Require(Changed(dark,cleared,new Rectangle(0,0,1024,576))<4,"Full-light cleanup retained pixels");
            Require(original.SequenceEqual(source.Data.Skip(sourceAt).Take(RayVisualCatalog.Stride)),
                "Full-light fixture mutated its source body");
            object result=new {schema="cf7-ray-channel-budget.v1",primaryCount=count,lightCount=count,frames,
                targetHz=30,elapsedMs=timer.Elapsed.TotalMilliseconds,layout,sourceStyle=(int)original[15],
                sourceWidth=original[11],sourceAlpha=original[7],sourceLength=originalLength,
                composeAndUploadMs=ChannelPercentiles(cpu),schedulerLatenessMs=ChannelPercentiles(lateness),
                workerPresentObservationsMs=ChannelPercentiles(presentObservations),
                presents=after.Presented-before.Presented,workerLastSubmitMs=after.SubmitMs,workerLastPresentMs=after.PresentMs,
                timedCpuReadbacks=after.CpuReadbacks-before.CpuReadbacks,after.Adapter,litPixels,cleared=true,
                boundary="Controlled 16-primary / 16-light occupancy through the production composer and native GPU using one real AS2 snapshot. Captured clocks are held; only positions and source-local identities differ. Timing excludes readback and is not parser/AS2/shot scheduling, GPU timestamp timing or game FPS. Worker Present samples may repeat."
            };
            File.WriteAllText(Path.Combine(output,"channel-budget-proof.json"),JsonSerializer.Serialize(result,options));
            Console.WriteLine("BUDGET: sixteen authored primary records and sixteen distinct lights, sixty timed uploads; readback excluded");
            return result;
        } finally {
            session.ClearRayFrame();session.ClearCombatFxFrame();composer.Reset();
        }
    }
}
