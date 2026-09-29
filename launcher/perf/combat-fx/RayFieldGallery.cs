using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    private static readonly (string Key,Rectangle Bounds)[] FieldRegions={
        ("near-behind-muzzle",new Rectangle(145,235,90,105)),
        ("feet-below-muzzle",new Rectangle(155,380,140,90)),
        ("near-ground",new Rectangle(280,332,180,100)),
        ("mid-ground",new Rectangle(440,332,280,100)),
        ("far-ground",new Rectangle(780,332,180,100)),
        ("upper-side",new Rectangle(280,190,440,86))
    };

    private static async Task RunRayFieldGallery(string root,string module,string output,
        IntPtr source,IntPtr target,string tracePath)
    {
        Require(!File.Exists(Path.Combine(output,"field-identity.json")),"Field evidence requires a new output directory");
        string sourcePath=Path.Combine(output,"source.png"),oldPath=Path.Combine(output,"old-ray-lights.json");
        Require(File.Exists(oldPath),"Missing output/old-ray-lights.json: provide the explicitly identified previous profile fixture");
        byte[] oldBytes=File.ReadAllBytes(oldPath),newBytes=File.ReadAllBytes(Path.Combine(root,RayLightingCatalog.RelativePath));
        var beforeCatalog=RayLightingCatalog.Parse(oldBytes);var afterCatalog=RayLightingCatalog.Parse(newBytes);
        var scenes=ReadFieldScenes(tracePath);
        string[] required={"flame_field","thermal_field","prism_field","tesla_age0","bagua_age0"};
        foreach(string key in required)Require(scenes.TryGetValue(key,out var packets)&&packets.Count>0,"Missing actual-XML CS6 field scene: "+key);
        string[] selected={"flame_field","thermal_field","thermal_enhanced_field","prism_field",
            "tesla_age0","tesla_age2","tesla_basic_age2","bagua_age0","bagua_age4","bagua_age8","bagua_fade11",
            "resonance_age0","resonance_age2"};
        var options=new JsonSerializerOptions{WriteIndented=true};
        string HashFile(string path)=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
        var identity=new {schema="cf7-ray-field.v1",utc=DateTime.UtcNow,sourcePath,sourceSha256=HashFile(sourcePath),
            sourceCrop=new{x=160,y=205,width=1024,height=576},origin=new{x=240,y=300},
            sourceDescription="Read-only FFDec raster of 基地场景-基地车库; static map art and its placeholder NPCs, not a player/save capture",
            tracePath,traceSha256=HashFile(tracePath),nativePath=module,nativeSha256=HashFile(module),
            corePath=typeof(RayVisualEngine).Assembly.Location,coreSha256=HashFile(typeof(RayVisualEngine).Assembly.Location),
            fixturePath=typeof(ProbeWindow).Assembly.Location,fixtureSha256=HashFile(typeof(ProbeWindow).Assembly.Location),
            beforeCatalogSha256=beforeCatalog.Sha256,afterCatalogSha256=afterCatalog.Sha256,
            beforeBoundary="Previous authored profile values on the current production light engine and shader; not an old-binary replay. Standard long rays leave the old/new short-length caps inactive.",
            boundary="Actual CS6 resolved configurations replayed through production parser, engine, composer and real WGC/D3D11 over static map art. Not game E2E, battle acceptance or physical photometry."};
        File.WriteAllText(Path.Combine(output,"field-identity.json"),JsonSerializer.Serialize(identity,options));
        File.WriteAllBytes(Path.Combine(output,"lighting-before.json"),oldBytes);
        File.WriteAllBytes(Path.Combine(output,"lighting-after.json"),newBytes);
        var metadata=File.ReadLines(tracePath).Where(line=>line.StartsWith("[RAY_REFERENCE_CASE] ",StringComparison.Ordinal)).ToArray();
        File.WriteAllText(Path.Combine(output,"trace-cases.json"),JsonSerializer.Serialize(metadata,options));

        using var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target);
        session.Mode(0);await WaitFor(()=>session.Read().Presented>0,session,"field initial capture");
        var size=session.ReadCaptureSize();session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
        var fx=CombatFxCatalog.Load(root);session.CombatFxAtlas(fx);
        await WaitFor(()=>session.CombatFxReady,session,"field light resources");
        var preset=WorldLightingPreset.Load(Path.Combine(root,"launcher/data/world-lighting/preset.json"),Console.Error.WriteLine);
        Require(preset.LutSet!=null,"Field production L0 LUT is unavailable");
        session.Matrix(Grade(1,1,1));session.ClearCombatFxFrame();session.ClearRayFrame();
        var neutral=Grab(session,Path.Combine(output,"source-captured.png"));
        session.SetLut(preset.LutSet.BlendLevel(0));
        var dark=Grab(session,Path.Combine(output,"night-L0.png"));
        Require(Changed(neutral,dark,new Rectangle(0,0,1024,576))>1000,"Production L0 did not grade the static map source");
        // These are the unchanged production equipment defaults. The existing
        // helper preserves their exact tint and energy (torch 1.45 / laser .85).
        var torch=DirectionalLight(fx,1,240,300,1,0,1000,260,185,300,140,1.15f);
        var laser=DirectionalLight(fx,2,240,300,1,0,750,28);
        session.CombatFxFrame(torch,0,0,1);var torchPicture=Grab(session,Path.Combine(output,"torch-original.png"));
        session.CombatFxFrame(laser,0,0,1);var laserPicture=Grab(session,Path.Combine(output,"laser-original.png"));
        var equipmentMetrics=new {torch=FieldMetrics(dark,torchPicture,neutral),laser=FieldMetrics(dark,laserPicture,neutral)};
        File.WriteAllText(Path.Combine(output,"equipment-reference.json"),JsonSerializer.Serialize(new {
            torch=torch.Lights.Take(16),laser=laser.Lights.Take(16),metrics=equipmentMetrics},options));
        var reports=new List<object>();var caseNames=new List<string>();
        foreach(string key in selected.Where(scenes.ContainsKey)) {
            var oldEngine=new RayVisualEngine();oldEngine.ConfigureLighting(beforeCatalog);
            var newEngine=new RayVisualEngine();newEngine.ConfigureLighting(afterCatalog);
            var configs=new Dictionary<int,RayVisualConfig>();
            foreach(string wire in scenes[key]) {
                Require(RayVisualFrame.TryParse(wire,out var frame),"Field CS6 packet rejected: "+key);
                Require(oldEngine.Apply(frame,1)&&newEngine.Apply(frame,1),"Field CS6 sequence rejected: "+key);
                foreach(var config in frame.Configs)configs[config.Id]=config;
            }
            var previous=oldEngine.BuildDraw();var current=newEngine.BuildDraw();
            Require(current.Count>0,"Field reference has no visible body: "+key);
            float[] geometry=current.Data.Take(current.Count*RayVisualCatalog.Stride).ToArray();
            Require(previous.Count==current.Count&&geometry.SequenceEqual(previous.Data.Take(previous.Count*RayVisualCatalog.Stride)),
                "Lighting catalogs altered body geometry: "+key);
            float cameraX=240-current.Data[0],cameraY=300-current.Data[1];
            var oldComposer=new WorldLightComposer(fx.MaximumLightResponse);oldComposer.SetRays(previous);
            var newComposer=new WorldLightComposer(fx.MaximumLightResponse);newComposer.SetRays(current);
            var oldLights=oldComposer.Compose(cameraX,cameraY,1);var newLights=newComposer.Compose(cameraX,cameraY,1);
            Require(oldLights.LightCount<=1&&newLights.LightCount<=1,"Field case allocated more than one primary light: "+key);
            if(required.Contains(key))Require(newLights.LightCount==1,"Required live field case lost its light: "+key);
            session.ClearRayFrame();session.CombatFxFrame(oldLights,cameraX,cameraY,1);
            var oldEnvironment=Grab(session,Path.Combine(output,key+"-old-environment.png"));
            session.CombatFxFrame(newLights,cameraX,cameraY,1);
            var newEnvironment=Grab(session,Path.Combine(output,key+"-new-environment.png"));
            session.ClearCombatFxFrame();session.RayFrame(current,cameraX,cameraY,1);
            var body=Grab(session,Path.Combine(output,key+"-body.png"));
            session.CombatFxFrame(oldLights,cameraX,cameraY,1);
            var oldCombined=Grab(session,Path.Combine(output,key+"-old-combined.png"));
            session.CombatFxFrame(newLights,cameraX,cameraY,1);
            var newCombined=Grab(session,Path.Combine(output,key+"-new-combined.png"));
            var bodyBytes=new byte[geometry.Length*sizeof(float)];Buffer.BlockCopy(geometry,0,bodyBytes,0,bodyBytes.Length);
            var record=new {key,packets=scenes[key].Count,bodyCount=current.Count,bodyGeometrySha256=Convert.ToHexString(SHA256.HashData(bodyBytes)),
                bodyGeometryUnchanged=true,cameraX,cameraY,bodyGeometry=geometry,
                configs=configs.Values.Select(c=>new{id=c.Id,style=RayVisualCatalog.Styles[c.Style],
                    fields=RayVisualCatalog.FieldNames.Select((name,i)=>new{name,value=c.Values[i]}).ToDictionary(x=>x.name,x=>x.value),
                    palette=c.Palette,light=new{profile=c.Light.Profile,energyScale=c.Light.EnergyScale,widthScale=c.Light.WidthScale,
                        color=c.Light.Color,fadeTicks=c.Light.FadeTicks}}),
                oldLightCount=oldLights.LightCount,newLightCount=newLights.LightCount,
                oldLights=oldLights.Lights.Take(oldLights.LightCount*16).ToArray(),newLights=newLights.Lights.Take(newLights.LightCount*16).ToArray(),
                oldEnvironment=FieldMetrics(dark,oldEnvironment,neutral),newEnvironment=FieldMetrics(dark,newEnvironment,neutral),
                oldCombinedLightGain=FieldMetrics(body,oldCombined,neutral),newCombinedLightGain=FieldMetrics(body,newCombined,neutral),
                sourcePackets=scenes[key]};
            // Preserve each completed case even if a later GPU capture fails.
            File.WriteAllText(Path.Combine(output,key+".json"),JsonSerializer.Serialize(record,options));
            reports.Add(record);caseNames.Add(key);
            File.WriteAllText(Path.Combine(output,"index.html"),FieldHtml(caseNames));
            Console.WriteLine("FIELD captured "+key+" lights="+oldLights.LightCount+"/"+newLights.LightCount);
        }
        session.ClearRayFrame();session.ClearCombatFxFrame();
        var cleared=Grab(session,Path.Combine(output,"field-cleared.png"));
        Require(Changed(dark,cleared,new Rectangle(0,0,1024,576))<4,"Field clear retained ray or light pixels");
        Require(HashFile(sourcePath)==identity.sourceSha256&&HashFile(tracePath)==identity.traceSha256
            &&HashFile(module)==identity.nativeSha256,"Field input bytes changed during capture");
        File.WriteAllText(Path.Combine(output,"field-proof.json"),JsonSerializer.Serialize(new {
            identity,caseCount=reports.Count,regions=FieldRegions.Select(r=>new {r.Key,x=r.Bounds.X,y=r.Bounds.Y,width=r.Bounds.Width,height=r.Bounds.Height}),
            excludedCore="x >= 240 and abs(y - 300) < 24 stage pixels; all ROI metrics exclude this band",
            metrics="Captured BGRA pixels: signed mean sRGB-code luma gain, sRGB-decoded linear luma gain, positive area >1 code value and effective area >=10. No brightness pass threshold is claimed before field calibration.",
            equipmentMetrics,cases=reports,cleared=true,
            completed="Capture/protocol/geometry/cleanup checks passed. Inspect the recorded ROI values and side-by-side images for lighting acceptance."},options));
        Console.WriteLine("FIELD COMPLETE: "+reports.Count+" actual-CS6 static-map comparisons; ROI measurements require visual review");
    }

    private static Dictionary<string,List<string>> ReadFieldScenes(string tracePath)
    {
        var scenes=new Dictionary<string,List<string>>(StringComparer.Ordinal);string current=null;
        foreach(string line in File.ReadLines(tracePath)) {
            const string scene="[RAY_GPU_SCENE] ",wire="[RAY_GPU_WIRE] ";
            if(line.StartsWith(scene,StringComparison.Ordinal)) {
                current=line.Substring(scene.Length).Trim();
                Require(scenes.TryAdd(current,new List<string>()),"Repeated field scene: "+current);
            } else if(current!=null&&line.StartsWith(wire,StringComparison.Ordinal))scenes[current].Add(line.Substring(wire.Length));
        }
        return scenes;
    }

    private static object[] FieldMetrics((byte[] bytes,int width,int height) baseline,
        (byte[] bytes,int width,int height) picture,(byte[] bytes,int width,int height) neutral)
    {
        Require(baseline.width==picture.width&&baseline.height==picture.height
            &&neutral.width==picture.width&&neutral.height==picture.height,"Field capture size changed");
        var output=new List<object>();
        foreach(var region in FieldRegions) {
            int count=0,material=0,positive=0,effective=0;double codeGain=0,linearGain=0,positiveGain=0;
            int left=region.Bounds.Left*picture.width/1024,right=region.Bounds.Right*picture.width/1024;
            int top=region.Bounds.Top*picture.height/576,bottom=region.Bounds.Bottom*picture.height/576;
            for(int y=top;y<bottom;y++)for(int x=left;x<right;x++) {
                double sx=x*1024d/picture.width,sy=y*576d/picture.height;
                if(sx>=240&&Math.Abs(sy-300)<24)continue;
                int at=(y*picture.width+x)*4;
                double delta=FieldLuma(picture.bytes,at,false)-FieldLuma(baseline.bytes,at,false);
                codeGain+=delta;positiveGain+=Math.Max(0,delta);
                linearGain+=FieldLuma(picture.bytes,at,true)-FieldLuma(baseline.bytes,at,true);
                count++;if(FieldLuma(neutral.bytes,at,false)>8)material++;
                if(delta>1)positive++;if(delta>=10)effective++;
            }
            Require(count>0,"Empty field ROI: "+region.Key);
            output.Add(new {region=region.Key,sampledPixels=count,sourceMaterialPixels=material,
                meanCodeLumaGain=codeGain/count,meanPositiveCodeLumaGain=positiveGain/count,
                meanLinearLumaGain=linearGain/count,positivePixels=positive,positiveFraction=positive/(double)count,
                effectivePixels=effective,effectiveFraction=effective/(double)count});
        }
        return output.ToArray();
    }

    private static double FieldLuma(byte[] bytes,int offset,bool linear)
    {
        double Channel(byte value) {
            if(!linear)return value;double x=value/255d;
            return x<=.04045?x/12.92:Math.Pow((x+.055)/1.055,2.4);
        }
        return .2126*Channel(bytes[offset+2])+.7152*Channel(bytes[offset+1])+.0722*Channel(bytes[offset]);
    }

    private static string FieldHtml(List<string> cases)
    {
        string scenes=JsonSerializer.Serialize(cases);
        string boxes=string.Join("",FieldRegions.Select(r=>FormattableString.Invariant($"<div class='roi' style='left:{r.Bounds.X/10.24:F3}%;top:{r.Bounds.Y/5.76:F3}%;width:{r.Bounds.Width/10.24:F3}%;height:{r.Bounds.Height/5.76:F3}%'>{r.Key}</div>")));
        return "<!doctype html><meta charset='utf-8'><title>车库射线照明对照</title>"+
            "<style>body{background:#161b23;color:#e3e9f1;font:15px system-ui;max-width:1100px;margin:24px auto}button,select{padding:8px;margin:4px}.stage{position:relative}img{width:100%;display:block}.roi{position:absolute;border:1px solid #6febd7;font-size:11px;color:#8ff;pointer-events:none;box-sizing:border-box}#regions{display:none}p{line-height:1.6}a{color:#8cf}</style>"+
            "<h1>车库素材上的射线照明</h1><p>真实 CS6 配置与实际 GPU 合成。背景是只读导出的静态地图素材，人物为素材占位 NPC；这不是玩家存档或游戏实战。旧灯光为旧配置在当前引擎的重放。所有按钮使用同一背景与同一束体几何。</p>"+
            "<select id='scene'></select><button data-mode='old-environment'>旧：仅环境光</button><button data-mode='new-environment'>新：仅环境光</button><button data-mode='body'>仅束体</button><button data-mode='old-combined'>旧：束体＋环境光</button><button data-mode='new-combined'>新：束体＋环境光</button>"+
            "<button data-global='night-L0.png'>L0 无灯</button><button data-global='torch-original.png'>原手电</button><button data-global='laser-original.png'>原镭射</button><button data-global='source-captured.png'>未调色素材</button><label><input id='overlay' type='checkbox'>ROI</label>"+
            "<p id='caption'></p><div class='stage'><img id='picture'><div id='regions'>"+boxes+"</div></div>"+
            "<p><a id='metrics'>当前场景配置与像素指标</a> · <a href='field-proof.json'>汇总证据</a> · <a href='field-identity.json'>输入身份与边界</a></p>"+
            "<p>指标剔除束心 ±24 像素。分别报告近身、脚下和远近地面的增亮均值，以及达到 10 级增亮的面积；亮度判断需结合环境光单独画面，不能把束体变亮当成环境可辨。</p>"+
            "<script>const names="+scenes+";let mode='new-combined';const s=document.getElementById('scene'),p=document.getElementById('picture'),c=document.getElementById('caption');for(const n of names)s.add(new Option(n,n));function show(file){p.src=file;c.textContent=file;document.getElementById('metrics').href=s.value+'.json'}function local(){show(s.value+'-'+mode+'.png')}s.onchange=local;document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{mode=b.dataset.mode;local()});document.querySelectorAll('[data-global]').forEach(b=>b.onclick=()=>show(b.dataset.global));document.getElementById('overlay').onchange=e=>document.getElementById('regions').style.display=e.target.checked?'block':'none';local();</script>";
    }
}
