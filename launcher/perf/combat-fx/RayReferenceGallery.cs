using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

internal static partial class Program
{
    private static async Task RunRayReferenceGallery(string root,string module,string output,
        IntPtr source,IntPtr target,string trace)
    {
        var scenes=new Dictionary<string,List<string>>(StringComparer.Ordinal);
        string current=null;
        foreach(string line in File.ReadLines(trace)) {
            const string sceneTag="[RAY_GPU_SCENE] ",wireTag="[RAY_GPU_WIRE] ";
            if(line.StartsWith(sceneTag,StringComparison.Ordinal)) {
                current=line.Substring(sceneTag.Length).Trim();
                if(!scenes.TryAdd(current,new()))throw new InvalidDataException("Repeated reference scene "+current);
            } else if(current!=null && line.StartsWith(wireTag,StringComparison.Ordinal))
                scenes[current].Add(line.Substring(wireTag.Length));
        }
        Require(scenes.Keys.Any(k=>k.StartsWith("bagua_",StringComparison.Ordinal)),"Missing original Bagua reference scenes");
        Require(scenes.Keys.Any(k=>k.StartsWith("resonance_",StringComparison.Ordinal)),"Missing original resonance reference scenes");
        using var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target);
        session.Mode(0);await WaitFor(()=>session.Read().Presented>0,session,"reference capture");
        var size=session.ReadCaptureSize();session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
        session.Matrix(Grade(1,1,1));session.ClearRayFrame();session.ClearCombatFxFrame();
        var black=Grab(session,Path.Combine(output,"reference-background.png"));
        var rows=new List<object>();var cards=new StringBuilder();
        foreach(var scene in scenes) {
            if(!(scene.Key.StartsWith("bagua_",StringComparison.Ordinal)
                || scene.Key.StartsWith("tesla_",StringComparison.Ordinal)
                || scene.Key.StartsWith("resonance_",StringComparison.Ordinal)))continue;
            var engine=new RayVisualEngine();RayVisualFrame last=null;
            foreach(string wire in scene.Value) {
                Require(RayVisualFrame.TryParse(wire,out var frame),"Reference wire rejected "+scene.Key);
                Require(engine.Apply(frame,1),"Reference sequence rejected "+scene.Key);last=frame;
            }
            Require(last!=null,"Empty reference scene "+scene.Key);
            var draw=engine.BuildDraw();Require(draw.Count>0,"Missing body in "+scene.Key);
            if(scene.Key=="tesla_age0") {
                CheckTeslaZeroLength(session,output,draw);
                await RenderTeslaStudy(session,output,draw);
                cards.Append("<p><a href=\"tesla-motion/index.html\">磁暴：原生动态样张（含连发与收束）</a></p>");
            }
            string file=scene.Key+".png";session.RayFrame(draw,0,0,1);
            var rendered=Grab(session,Path.Combine(output,file));
            float[] d=draw.Data;
            var first=new {startX=d[0],startY=d[1],endX=d[2],endY=d[3],alpha=d[7],width=d[11],phase=d[12],
                holdOrLife=d[13],style=d[15],metadata=d.Skip(16).Take(4).ToArray(),parameters=d.Skip(20).Take(12).ToArray()};
            int changed=Changed(black,rendered,new Rectangle(0,0,1024,576));
            Require(changed>8,"Reference output is blank "+scene.Key);
            var raster=ReferencePixels(black,rendered);
            rows.Add(new {name=scene.Key,file,draw.Count,first,changed,raster});
            cards.Append("<figure><figcaption>").Append(System.Net.WebUtility.HtmlEncode(scene.Key))
                .Append("</figcaption><img src=\"").Append(file).Append("\"></figure>");
        }
        // Sloping beams use the same world dimensions and shader geometry;
        // preserve their authored length while moving them into this viewport.
        foreach(string name in new[]{"bagua_age4","tesla_age2","resonance_age2"}) {
            if(!scenes.TryGetValue(name,out var wires))continue;
            var engine=new RayVisualEngine();
            foreach(string wire in wires) {Require(RayVisualFrame.TryParse(wire,out var f),"Diagonal reference parse");Require(engine.Apply(f,1),"Diagonal reference sequence");}
            var draw=engine.BuildDraw();
            const float dx=.94f,dy=.34117445f;
            for(int i=0;i<draw.Count;i++) {
                int p=i*32;float x0=draw.Data[p],y0=draw.Data[p+1],x1=draw.Data[p+2],y1=draw.Data[p+3];
                float length=MathF.Sqrt((x1-x0)*(x1-x0)+(y1-y0)*(y1-y0));
                draw.Data[p]=70;draw.Data[p+1]=145;draw.Data[p+2]=70+dx*length;draw.Data[p+3]=145+dy*length;
            }
            string file=name+"-diagonal.png";session.RayFrame(draw,0,0,1);var picture=Grab(session,Path.Combine(output,file));
            rows.Add(new {name=name+"-diagonal",file,draw.Count,changed=Changed(black,picture,new Rectangle(0,0,1024,576)),raster=ReferencePixels(black,picture)});
            cards.Append("<figure><figcaption>").Append(name).Append(" / 斜向</figcaption><img src=\"").Append(file).Append("\"></figure>");
        }
        var paletteProof=CheckPackedRayPalette(session,output);
        session.ClearRayFrame();var cleared=Grab(session,Path.Combine(output,"reference-cleared.png"));
        Require(Changed(black,cleared,new Rectangle(0,0,1024,576))<4,"Reference cleanup left pixels");
        string core=typeof(RayVisualEngine).Assembly.Location;
        var proof=new {schema="cf7-ray-reference-gallery.v1",utc=DateTime.UtcNow,sourceTrace=trace,
            sourceTraceSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(trace))),
            nativeDll=module,nativeSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(module))),
            coreModule=core,coreSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(core))),rows,paletteProof,cleared=true,
            teslaZeroLengthChecked=scenes.ContainsKey("tesla_age0"),
            boundary="Real GPU replay of actual XML resolved by original AS2. Raster metrics describe this renderer; separate AS2 TestLoader images supply the original reference. No claim of pixel equality or game acceptance."};
        File.WriteAllText(Path.Combine(output,"reference-proof.json"),JsonSerializer.Serialize(proof,new JsonSerializerOptions{WriteIndented=true}));
        File.WriteAllText(Path.Combine(output,"index.html"),"<!doctype html><meta charset=\"utf-8\"><title>射线原版配置对照</title>"+
            "<style>body{margin:24px;background:#12161c;color:#eee;font:16px system-ui}figure{margin:16px 0;border:1px solid #38434c}figcaption{padding:10px}img{display:block;width:100%;max-width:1024px}</style>"+
            "<h1>真实 AS2 配置 · 原生绘制</h1><p>同一 XML、年龄和世界坐标；黑底仅查看束体。环境照明见车库场景对照。AS2 原版参考另见 TestLoader。</p>"+cards);
        Console.WriteLine("PASS: actual-XML reference replay, diagonal rendering and cleanup; visual comparison remains explicit.");
    }

    private static object CheckPackedRayPalette(NativeCompositorSession session,string output)
    {
        var draw=new RayVisualDrawFrame(1){Count=1};float[] d=draw.Data;
        d[0]=60;d[1]=288;d[2]=960;d[3]=288;
        for(int i=4;i<11;i++)d[i]=1;
        d[11]=4;d[13]=12;d[14]=123;d[15]=4;d[16]=1;d[17]=2;
        d[20]=1;d[22]=30;d[23]=80;d[24]=1;
        // A black palette removes only the tested coloured fork. Its unchanged
        // cyan underglow / white axis cancel when measuring the coloured contribution.
        session.RayFrame(draw,0,0,1);
        var baseline=Grab(session,Path.Combine(output,"palette-control.png"));
        var results=new List<object>();
        foreach(int rgb in new[]{0xFF00FF,0x8800FF,0xFF66FF,0xFFFFFF}) {
            d[25]=rgb;session.RayFrame(draw,0,0,1);
            string name="palette-"+rgb.ToString("X6",CultureInfo.InvariantCulture)+".png";
            var sample=Grab(session,Path.Combine(output,name));long[] gain=new long[3];
            for(int y=258;y<318;y++)for(int x=60;x<960;x++) {
                if(Math.Abs(y-288)<5)continue;
                int at=(y*sample.width+x)*4;
                for(int channel=0;channel<3;channel++)
                    gain[channel]+=Math.Max(0,sample.bytes[at+2-channel]-baseline.bytes[at+2-channel]);
            }
            results.Add(new {rgb=rgb.ToString("X6",CultureInfo.InvariantCulture),file=name,rgbContribution=gain});
            File.WriteAllText(Path.Combine(output,"palette-proof.json"),JsonSerializer.Serialize(results,new JsonSerializerOptions{WriteIndented=true}));
            for(int channel=0;channel<3;channel++) {
                int expected=(rgb>>(16-channel*8))&255;
                Require(expected==0 ? gain[channel]<=8 : gain[channel]>100,
                    "RGB24 channel corruption: "+rgb.ToString("X6",CultureInfo.InvariantCulture)+" channel="+channel+" gain="+gain[channel]);
            }
        }
        return new {passed=true,results,boundary="Actual ps_4_0 palette decoding over a controlled black source; checks all authored nonzero channels and exact zero channels."};
    }

    private static object ReferencePixels((byte[] bytes,int width,int height) background,
        (byte[] bytes,int width,int height) picture)
    {
        int left=picture.width,top=picture.height,right=-1,bottom=-1,redOnly=0,cold=0;
        for(int y=0;y<picture.height;y++)for(int x=0;x<picture.width;x++) {
            int at=(y*picture.width+x)*4;
            int b=picture.bytes[at],g=picture.bytes[at+1],r=picture.bytes[at+2];
            if(Math.Max(Math.Abs(r-background.bytes[at+2]),Math.Max(Math.Abs(g-background.bytes[at+1]),Math.Abs(b-background.bytes[at])))<=8)continue;
            left=Math.Min(left,x);right=Math.Max(right,x);top=Math.Min(top,y);bottom=Math.Max(bottom,y);
            if(r>180 && b<60 && g<100)redOnly++;
            if(b>130 && b>r*.7)cold++;
        }
        return new {left,top,right,bottom,redOnlyPixels=redOnly,coldPixels=cold};
    }
}
