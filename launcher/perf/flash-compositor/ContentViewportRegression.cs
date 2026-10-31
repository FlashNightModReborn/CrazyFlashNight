using System.Diagnostics;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using CF7Launcher.Guardian.WorldCompositor;

namespace FlashCompositorProbe;

internal static class ContentViewportRegression
{
    static readonly List<object> Results=new();
    static string Output="";
    static int ExitCode;
    static readonly List<string> Failures=new();
    record Case(string Name,int W,int H,int OW,int OH,string Tag="fit",bool? ExpectedBullet=true,int Lead=0,bool Recover=false,bool Hud=false,bool Sync=true,bool Post=false,float CamX=0,float CamY=0,float CamScale=1,int SourceEpoch=3,int SourceFrame=42,int OmitFrame=-1,uint ExpectedTagStatus=1);
    static readonly Case[] Cases={
        new("base-1024",1024,576,1024,576),
        new("360p-to-1600",640,360,1600,900),
        new("540p-to-1600",960,540,1600,900),
        new("720p-1280",1280,720,1280,720),
        new("900p-1600",1600,900,1600,900),
        new("odd-1365x768",1365,768,1365,768),
        new("one-pixel-1024x577",1024,577,1024,577),
        new("wide-1920x1017",1920,1017,1280,678),
        new("16x10-1280x800",1280,800,1280,800),
        new("4x3-1024x768",1024,768,1024,768),
        new("ultrawide-1720x720",1720,720,1290,540),
        new("tall-900x1000",900,1000,810,900),
        new("wide-wrong-tag-rejected",1088,576,1088,576,"stretch",false,ExpectedTagStatus:2),
        new("4x3-wrong-tag-rejected",1024,768,1024,768,"stretch",false,ExpectedTagStatus:2),
        new("output-only-bars",1024,576,1200,900),
        new("hud-sync-on",1024,576,1024,576,Hud:true),
        new("hud-sync-off-control",1024,576,1024,576,"none",Hud:true,Sync:false,ExpectedTagStatus:2),
        new("invalid-magic",1024,576,1024,576,"bad",false,ExpectedTagStatus:2),
        new("missing-tag",1024,576,1024,576,"none",false,ExpectedTagStatus:2),
        new("history-8-snapshots",1024,576,1024,576,Lead:7),
        new("history-9-snapshots",1024,576,1024,576,ExpectedBullet:false,Lead:8,ExpectedTagStatus:5),
        new("history-recover",1024,576,1024,576,Lead:8,Recover:true),
        new("history-empty",1024,576,1024,576,ExpectedBullet:false,Lead:-1,ExpectedTagStatus:3),
        new("history-gap",1024,576,1024,576,ExpectedBullet:false,Lead:7,SourceFrame:45,OmitFrame:45,ExpectedTagStatus:4),
        new("source-ahead",1024,576,1024,576,ExpectedBullet:false,SourceFrame:50,ExpectedTagStatus:6),
        new("epoch-mismatch",1024,576,1024,576,ExpectedBullet:false,SourceEpoch:4,ExpectedTagStatus:7),
        new("cas-feedback-360p",640,360,1600,900,Post:true),
        new("camera-pan-zoom-16x9",1280,720,1280,720,CamX:25,CamY:-10,CamScale:.8f),
        new("camera-pan-zoom-wide",1088,576,1088,576,CamX:25,CamY:-10,CamScale:.8f)
    };
    internal static int Run(string[] args)
    {
        if(args.Length!=2)throw new ArgumentException("viewport-regression expects a native DLL and a new evidence directory");
        if(args[0]=="--analyze")return AnalyzeSaved(args[1]);
        string dll=Path.GetFullPath(args[0]);Output=Path.GetFullPath(args[1]);
        if(Directory.Exists(Output)&&Directory.EnumerateFileSystemEntries(Output).Any())throw new IOException("Evidence directory must be empty");
        Directory.CreateDirectory(Output);
        nint module=NativeLibrary.Load(dll);
        NativeLibrary.SetDllImportResolver(typeof(ContentViewportRegression).Assembly,(name,_,_)=>name=="probe"?module:0);
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        using var source=new Source();using var target=new Quiet{Text="Owned geometry audit output",Location=new(64,64)};
        source.Shown+=async(_,_)=>{
            target.Show();
            try{
                foreach(var test in Cases)await Run(source,target,test);
                await Transitions(source,target);
                await EnvironmentEffects(source,target);
            }
            catch(Exception error){Results.Add(new{error=error.ToString()});ExitCode=1;Console.WriteLine(error);}
            finally{
                File.WriteAllText(Path.Combine(Output,"results.json"),JsonSerializer.Serialize(new{
                    dll,nativeSha256=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(dll))),
                    scope="Owned synthetic source, real WGC and unchanged production native DLL. Pointer check links actual production mapper; no physical input or game save.",
                    success=ExitCode==0,failures=Failures,results=Results},new JsonSerializerOptions{WriteIndented=true}));target.Close();source.Close();}
        };
        Application.Run(source);NativeLibrary.Free(module);return ExitCode;
    }
    static async Task Run(Source source,Quiet target,Case test)
    {
        Configure(source,target,test);await Task.Delay(100);
        nint session=ProbeStartWorld(source.Handle,(uint)Environment.ProcessId,target.Handle,0,1);
        if(session==0)throw new Exception("ProbeStartWorld failed");
        try{Setup(session,test);await Capture(source,session,test);}
        finally{ProbeStop(session);}
    }
    static void Configure(Source source,Quiet target,Case test)
    {source.Test=test;source.ClientSize=new(test.W,test.H);target.ClientSize=new(test.OW,test.OH);source.Refresh();GdiFlush();}
    static void Setup(nint session,Case test)
    {
        ProbeSetMode(session,0);Check(ProbeSetViewport(session,0,0,test.W,test.H,0),"viewport");
        Check(ProbeSetMatrix(session,new float[]{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}),"matrix");
        Check(ProbeSetPostprocess(session,test.Post?1:0,.4f,test.Post?1:0),"postprocess");
        var style=new float[32];style[0]=-12;style[1]=-5;style[2]=12;style[3]=0;style[4]=-12;style[5]=5;style[7]=1;
        Check(ProbeSetBulletStyles(session,style,1),"styles");
        for(int frame=42;frame<=42+test.Lead;frame++)if(frame!=test.OmitFrame)SubmitBullet(session,test,frame);
        if(test.Recover)SubmitBullet(session,test,42);
        byte[] redAtlas={0,0,255,255,0,0,255,255,0,0,255,255,0,0,255,255};
        Check(ProbeSetCombatFxAtlas(session,redAtlas,2,2,redAtlas.Length),"fx atlas");
        float[] fx={924,400,0,1,1,1,1,0,-5,-5,10,10,0,0,1,1};
        Check(ProbeSetCombatFxFrame(session,fx,1,0,Array.Empty<float>(),0,0,test.CamX,test.CamY,test.CamScale),"fx frame");
        var ray=new float[32];ray[0]=ray[2]=768;ray[1]=ray[3]=128;ray[6]=1;ray[7]=1;ray[10]=1;ray[11]=12;ray[15]=16;ray[16]=1;ray[20]=100;
        Check(ProbeSetRayFrame(session,ray,1,test.CamX,test.CamY,test.CamScale),"ray frame");
        if(test.Hud){var hud=new byte[32*10*4];for(int i=0;i<hud.Length;i+=4){hud[i]=255;hud[i+2]=255;hud[i+3]=255;}
            Check(ProbeSetHudRaster(session,0,hud,32,10,128,4,test.OH-12),"hud");}
    }
    static void SubmitBullet(nint session,Case test,int frame)
    {Check(ProbeSetBulletFrameV2(session,new float[]{0,100,160,0,100,100,100,0},1,test.CamX,test.CamY,test.CamScale,test.Sync?3:-1,test.Sync?frame:-1,test.Sync?9:-1,test.Sync?frame:-1),"bullet frame");}
    static async Task Capture(Source source,nint session,Case test)
    {
        byte[]? raw=null,composed=null;uint rw=0,rh=0,cw=0,ch=0;
        var diagnostic=new BulletSourceStats{Size=(uint)Marshal.SizeOf<BulletSourceStats>()};
        Check(ProbeGetBulletSourceStats(session,ref diagnostic),"source tag diagnostic request");
        for(int i=0;i<45;i++){
            source.Refresh();GdiFlush();await Task.Delay(100);
            raw=Grab(session,false,out rw,out rh);composed=Grab(session,true,out cw,out ch);
            if(raw!=null&&composed!=null&&rw==test.W&&rh==test.H&&cw==test.OW&&ch==test.OH&&i>=5)break;
        }
        if(raw==null||composed==null||rw!=test.W||rh!=test.H||cw!=test.OW||ch!=test.OH)throw new Exception(test.Name+": readback geometry timeout");
        Save(raw,(int)rw,(int)rh,Path.Combine(Output,test.Name+"-source.png"));
        Save(composed,(int)cw,(int)ch,Path.Combine(Output,test.Name+"-composite.png"));
        var bullet=Feature(composed,test,"bullet",100,160,(r,g,b)=>g>100&&g>r*2&&g>b*2);
        var fx=Feature(composed,test,"sprite",924,400,(r,g,b)=>r>180&&g<60&&b<60);
        var ray=Feature(composed,test,"ray",768,128,(r,g,b)=>b>100&&r<80&&g<80);
        int tagPixels=0,hudPixels=0;
        for(int y=0;y<test.OH;y++)for(int x=0;x<test.OW;x++){
            int p=(y*test.OW+x)*4,r=composed[p+2],g=composed[p+1],b=composed[p];
            if(y>test.OH*.65&&x<test.OW*.2&&((r<20&&g<20&&b>160)||(r>150&&g>245&&b>245)||(r>35&&r<48&&g<5&&b<5)||(r>10&&r<28&&g>78&&g<98&&b>145&&b<165)))tagPixels++;
            if(r>240&&b>240&&g<20)hudPixels++;
        }
        double pointerMax=PointerError(test);
        Check(ProbeGetBulletSourceStats(session,ref diagnostic),"source tag diagnostic result");
        for(int i=0;i<15 && (diagnostic.SampleNumber==0 || diagnostic.SourceWidth!=test.W || diagnostic.SourceHeight!=test.H);i++){
            await Task.Delay(100);Check(ProbeGetBulletSourceStats(session,ref diagnostic),"source tag diagnostic pending");
        }
        var row=new{test,bullet,fx,ray,tagPixels,hudPixels,pointerMaxStageError=pointerMax,sourceTag=new {
            diagnostic.Status,diagnostic.TagValid,diagnostic.SourceEpoch,diagnostic.SourceFrame,diagnostic.HistoryCount,
            diagnostic.MatchedItems,diagnostic.SampleNumber,diagnostic.SourceWidth,diagnostic.SourceHeight}};
        Results.Add(row);Console.WriteLine(JsonSerializer.Serialize(row));
        Require(!test.ExpectedBullet.HasValue||bullet.Visible==test.ExpectedBullet.Value,test.Name+": bullet visibility");
        Require(!bullet.Visible||bullet.ErrorPixels<=3,test.Name+": bullet anchor");
        Require(fx.Visible&&fx.ErrorPixels<=3,test.Name+": sprite anchor");
        Require(ray.Visible&&ray.ErrorPixels<=3,test.Name+": ray anchor");
        Require(pointerMax<=3,test.Name+": pointer quantization");
        if(test.Tag=="fit")Require(tagPixels==0,test.Name+": source metadata leaked");
        if(test.Hud)Require(hudPixels==320,test.Name+": HUD raster changed");
        Require(diagnostic.SampleNumber>0&&diagnostic.Status==test.ExpectedTagStatus,test.Name+": GPU source diagnostic status "+diagnostic.Status);
    }
    record FeatureResult(string Kind,bool Visible,int Pixels,double? CenterX,double? CenterY,double ExpectedX,double ExpectedY,double? ErrorPixels);
    static FeatureResult Feature(byte[] bytes,Case test,string kind,double x,double y,Func<int,int,int,bool> match)
    {
        int count=0,x0=int.MaxValue,y0=int.MaxValue,x1=-1,y1=-1;
        for(int py=0;py<test.OH*.8;py++)for(int px=0;px<test.OW;px++){
            if(py>test.OH*.6 && px<test.OW*.2)continue; // Exclude source tag colors in tall letterboxed canvases.
            int p=(py*test.OW+px)*4;if(!match(bytes[p+2],bytes[p+1],bytes[p]))continue;
            count++;x0=Math.Min(x0,px);x1=Math.Max(x1,px);y0=Math.Min(y0,py);y1=Math.Max(y1,py);
        }
        var expected=StageToOutput(test,x*test.CamScale+test.CamX,y*test.CamScale+test.CamY);
        double? cx=count>0?(x0+x1+1)/2.0:null,cy=count>0?(y0+y1+1)/2.0:null;
        double? error=count>0?Math.Sqrt(Math.Pow(cx!.Value-expected.X,2)+Math.Pow(cy!.Value-expected.Y,2)):null;
        return new(kind,count>8,count,cx,cy,expected.X,expected.Y,error);
    }
    static int AnalyzeSaved(string folder)
    {
        string path=Path.Combine(folder,"results.json");var root=JsonNode.Parse(File.ReadAllText(path))!;
        foreach(var row in root["results"]!.AsArray()){
            if(row?["test"]==null)continue;
            var test=row!["test"]!.Deserialize<Case>()!;
            using var bmp=new Bitmap(Path.Combine(folder,test.Name+"-composite.png"));
            var bytes=new byte[bmp.Width*bmp.Height*4];var locked=bmp.LockBits(new(0,0,bmp.Width,bmp.Height),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
            try{for(int y=0;y<bmp.Height;y++)Marshal.Copy(locked.Scan0+y*locked.Stride,bytes,y*bmp.Width*4,bmp.Width*4);}finally{bmp.UnlockBits(locked);}
            row["bullet"]=JsonSerializer.SerializeToNode(Feature(bytes,test,"bullet",100,160,(r,g,b)=>g>100&&g>r*2&&g>b*2));
            row["fx"]=JsonSerializer.SerializeToNode(Feature(bytes,test,"sprite",924,400,(r,g,b)=>r>180&&g<60&&b<60));
            row["ray"]=JsonSerializer.SerializeToNode(Feature(bytes,test,"ray",768,128,(r,g,b)=>b>100&&r<80&&g<80));
        }
        root["pixelAnalysis"]= "Analyzed saved native composite PNGs; bottom-left diagnostic tag ROI excluded from effect detection. Captures unchanged.";
        File.WriteAllText(path,root.ToJsonString(new JsonSerializerOptions{WriteIndented=true}));return 0;
    }
    static PointF StageToOutput(Case t,double x,double y)
    {
        double inner=Math.Min(t.W/1024.0,t.H/576.0),ix=(t.W-1024*inner)/2,iy=(t.H-576*inner)/2;
        double outer=Math.Min(t.OW/(double)t.W,t.OH/(double)t.H),ox=(t.OW-t.W*outer)/2,oy=(t.OH-t.H*outer)/2;
        return new((float)(ox+(ix+x*inner)*outer),(float)(oy+(iy+y*inner)*outer));
    }
    static double PointerError(Case t)
    {
        double max=0,inner=Math.Min(t.W/1024.0,t.H/576.0),ix=(t.W-1024*inner)/2,iy=(t.H-576*inner)/2;
        foreach(var p in new[]{new Point(100,160),new Point(768,128),new Point(924,400),new Point(512,288)}){
            var output=StageToOutput(t,p.X,p.Y);
            var mapped=WorldPointerMapper.Map(new((int)Math.Floor(output.X),(int)Math.Floor(output.Y)),new(t.OW,t.OH),new(t.W,t.H));
            double ex=(mapped.X-ix)/inner-p.X,ey=(mapped.Y-iy)/inner-p.Y;max=Math.Max(max,Math.Sqrt(ex*ex+ey*ey));
        }return max;
    }
    static async Task Transitions(Source source,Quiet target)
    {
        var sequence=new[]{new Case("transition-1-normal",1024,576,1024,576),new Case("transition-2-wide",1088,576,1088,576),new Case("transition-3-restored",1024,576,1024,576),new Case("transition-4-lowres",640,360,1024,576),new Case("transition-5-restored",1024,576,1024,576)};
        Configure(source,target,sequence[0]);await Task.Delay(100);
        nint session=ProbeStartWorld(source.Handle,(uint)Environment.ProcessId,target.Handle,0,1);
        try{foreach(var t in sequence){ProbeHoldViewport(session);Configure(source,target,t);Setup(session,t);await Capture(source,session,t);}}
        finally{ProbeStop(session);}
    }
    static async Task EnvironmentEffects(Source source,Quiet target)
    {
        var layouts=new[]{new Case("effects-16x9",1024,576,1024,576),new Case("effects-wide",1088,576,1088,576),
            new Case("effects-4x3",1024,768,1024,768),new Case("effects-360p",640,360,1600,900),
            new Case("effects-output-bars-zoom",1024,576,1200,900,CamX:25,CamY:-10,CamScale:.8f)};
        foreach(var layout in layouts){
            Configure(source,target,layout);await Task.Delay(100);
            nint session=ProbeStartWorld(source.Handle,(uint)Environment.ProcessId,target.Handle,0,1);
            try{
                Setup(session,layout);
                Check(ProbeSetBulletFrameV2(session,Array.Empty<float>(),0,0,0,1,3,42,9,42),"empty bullets");
                Check(ProbeSetRayFrame(session,Array.Empty<float>(),0,0,0,1),"empty rays");
                Check(ProbeSetCombatFxFrame(session,Array.Empty<float>(),0,0,Array.Empty<float>(),0,0,layout.CamX,layout.CamY,layout.CamScale),"empty effects");
                byte[] baseline=await StableComposite(source,session,layout);
                Save(baseline,layout.OW,layout.OH,Path.Combine(Output,layout.Name+"-baseline.png"));
                for(int type=1;type<=5;type++){
                    Check(ProbeSetWeatherStyle(session,type,256,new float[]{1,1,1,1,1,1,1,.9f,.1f,0,1,.6f,.8f,1,0,0}),"weather style");
                    Check(ProbeSetWeatherCamera(session,layout.CamX,layout.CamY,layout.CamScale,420,560),"weather camera");
                    Check(ProbeSetWeather(session,type,1,0,417),"weather");
                    await RecordEffect(source,session,layout,baseline,"weather-"+type,null);
                    Check(ProbeSetWeather(session,0,0,0,417),"weather clear");
                }
                float[] light={150,300,40,1,1,1,1,0,0,0,0,0,0,0,0,0};
                Check(ProbeSetCombatFxFrame(session,Array.Empty<float>(),0,0,light,1,.8f,layout.CamX,layout.CamY,layout.CamScale),"dynamic light");
                await RecordEffect(source,session,layout,baseline,"dynamic-light",new PointF(150,300));
                Check(ProbeSetCombatFxFrame(session,Array.Empty<float>(),0,0,Array.Empty<float>(),0,0,layout.CamX,layout.CamY,layout.CamScale),"dynamic light clear");
                Check(ProbeSetSceneLights(session,light,1,.8f),"scene light");
                await RecordEffect(source,session,layout,baseline,"scene-light",new PointF(150,300));
                Check(ProbeSetSceneLights(session,Array.Empty<float>(),0,0),"scene light clear");
                Check(ProbeSetAtmosphere(session,11,new float[]{.4f,.1f,.2f,.3f,1,0,0,0,0,0,0,0}),"custom atmosphere");
                await RecordEffect(source,session,layout,baseline,"atmosphere",null);
            }finally{ProbeStop(session);}
        }
    }
    static async Task<byte[]> StableComposite(Source source,nint session,Case layout)
    {
        byte[]? result=null;
        for(int i=0;i<6;i++){
            source.Refresh();GdiFlush();await Task.Delay(100);
            var current=Grab(session,true,out uint w,out uint h);
            if(current!=null&&w==layout.OW&&h==layout.OH)result=current;
        }
        return result??throw new Exception("Effect composite unavailable");
    }
    static async Task RecordEffect(Source source,nint session,Case layout,byte[] baseline,string family,PointF? anchor)
    {
        byte[] bytes=await StableComposite(source,session,layout);
        string name=layout.Name+"-"+family;Save(bytes,layout.OW,layout.OH,Path.Combine(Output,name+".png"));
        var a=StageToOutput(layout,0,0);var b=StageToOutput(layout,1024,576);
        int inside=0,outside=0;double weight=0,xsum=0,ysum=0;
        for(int y=0;y<layout.OH;y++)for(int x=0;x<layout.OW;x++){
            int p=(y*layout.OW+x)*4;
            int delta=Math.Max(Math.Abs(bytes[p]-baseline[p]),Math.Max(Math.Abs(bytes[p+1]-baseline[p+1]),Math.Abs(bytes[p+2]-baseline[p+2])));
            if(delta<5)continue;
            bool outer=x+.5<a.X-1||x+.5>b.X+1||y+.5<a.Y-1||y+.5>b.Y+1;
            if(outer)outside++;else inside++;
            int gain=bytes[p]+bytes[p+1]+bytes[p+2]-baseline[p]-baseline[p+1]-baseline[p+2];
            if(gain>0){weight+=gain;xsum+=(x+.5)*gain;ysum+=(y+.5)*gain;}
        }
        double? cx=weight>0?xsum/weight:null,cy=weight>0?ysum/weight:null,error=null;
        PointF? expected=null;
        if(anchor is {} at){expected=StageToOutput(layout,at.X*layout.CamScale+layout.CamX,at.Y*layout.CamScale+layout.CamY);
            if(cx.HasValue)error=Math.Sqrt(Math.Pow(cx.Value-expected.Value.X,2)+Math.Pow(cy!.Value-expected.Value.Y,2));}
        var row=new{kind="environment",name,family,layout,insideChanges=inside,outsideChanges=outside,centerX=cx,centerY=cy,expectedX=expected?.X,expectedY=expected?.Y,errorPixels=error};
        Results.Add(row);Console.WriteLine(JsonSerializer.Serialize(row));
        Require(inside>20,name+": effect absent");Require(outside==0,name+": effect changed letterbox pixels");
        if(anchor.HasValue)Require(error.HasValue&&error<=3,name+": light anchor");
    }
    static void Check(int value,string label){if(value!=1)throw new Exception(label+" rejected");}
    static void Require(bool pass,string label){if(pass)return;Failures.Add(label);ExitCode=1;Console.Error.WriteLine(label);}
    static byte[]? Grab(nint session,bool final,out uint w,out uint h){uint size=1920*1080*4;var bytes=new byte[size];int code=final?ProbeGrabCompositeFrame(session,bytes,size,out w,out h):ProbeGrabLatestFrame(session,bytes,size,out w,out h);return code==1?bytes:null;}
    static void Save(byte[] bytes,int w,int h,string path){using var bmp=new Bitmap(w,h,PixelFormat.Format32bppArgb);var locked=bmp.LockBits(new(0,0,w,h),ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);try{for(int y=0;y<h;y++)Marshal.Copy(bytes,y*w*4,locked.Scan0+y*locked.Stride,w*4);}finally{bmp.UnlockBits(locked);}bmp.Save(path,ImageFormat.Png);}
    class Quiet:Form{
        public Quiet(){AutoScaleMode=AutoScaleMode.None;FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;StartPosition=FormStartPosition.Manual;Location=new(0,0);ClientSize=new(1024,576);}
        protected override bool ShowWithoutActivation=>true;
        protected override CreateParams CreateParams{get{var p=base.CreateParams;p.ExStyle|=0x08000080;return p;}}
    }
    sealed class Source:Quiet{
        internal Case Test=Cases[0];
        public Source(){Text="Owned geometry audit source";DoubleBuffered=true;}
        protected override void OnPaint(PaintEventArgs e){var g=e.Graphics;g.Clear(Color.Black);double s=Math.Min(ClientSize.Width/1024.0,ClientSize.Height/576.0),left=(ClientSize.Width-1024*s)/2,top=(ClientSize.Height-576*s)/2;
            using var bg=new SolidBrush(Color.FromArgb(24,40,56));g.FillRectangle(bg,(float)left,(float)top,(float)(1024*s),(float)(576*s));
            foreach(var p in new[]{new Point(100,160),new Point(924,400),new Point(768,128)}){float x=(float)(left+(p.X*Test.CamScale+Test.CamX)*s),y=(float)(top+(p.Y*Test.CamScale+Test.CamY)*s);g.DrawLine(Pens.White,x-12,y,x+12,y);g.DrawLine(Pens.White,x,y-12,x,y+12);}
            if(Test.Tag=="none")return;
            int f0=Test.SourceFrame&255,f1=(Test.SourceFrame>>8)&255,f2=(Test.SourceFrame>>16)&255,e0=Test.SourceEpoch&255,e1=(Test.SourceEpoch>>8)&255;
            int[] colors={Test.Tag=="bad"?0x18579B:0x13579B,(f0<<16)|(f1<<8)|f2,
                (e0<<16)|(e1<<8)|((f0+f1+f2+e0+e1+167)&255),((255-f0)<<16)|((255-f1)<<8)|(255-f2)};
            for(int i=0;i<4;i++){using var brush=new SolidBrush(Color.FromArgb((colors[i]>>16)&255,(colors[i]>>8)&255,colors[i]&255));double x=Test.Tag=="stretch"?i*16*ClientSize.Width/1024.0:left+i*16*s,y=Test.Tag=="stretch"?560*ClientSize.Height/576.0:top+560*s,w=Test.Tag=="stretch"?16*ClientSize.Width/1024.0:16*s,h=Test.Tag=="stretch"?16*ClientSize.Height/576.0:16*s;g.FillRectangle(brush,(float)x,(float)y,(float)w,(float)h);}
        }
    }
    [DllImport("gdi32.dll")] static extern bool GdiFlush();
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern nint ProbeStartWorld(nint source,uint pid,nint output,uint vendor,int borderless);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern void ProbeStop(nint handle);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern void ProbeSetMode(nint handle,int mode);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetViewport(nint handle,int x,int y,int w,int h,double fence);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern void ProbeHoldViewport(nint handle);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetMatrix(nint handle,float[] settings);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetPostprocess(nint handle,int cas,float sharp,int feedback);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetBulletStyles(nint handle,float[] styles,int count);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetBulletFrameV2(nint handle,float[] items,int count,float x,float y,float scale,int epoch,int frame,int chainEpoch,int chainFrame);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetCombatFxAtlas(nint handle,byte[] pixels,int w,int h,int length);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetCombatFxFrame(nint handle,float[] items,int count,int casings,float[] lights,int lightCount,float response,float x,float y,float scale);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetRayFrame(nint handle,float[] items,int count,float x,float y,float scale);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetHudRaster(nint handle,int layer,byte[] pixels,int w,int h,int stride,int x,int y);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetWeather(nint handle,int type,float intensity,int quality,uint seed);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetWeatherStyle(nint handle,int type,int count,float[] settings);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetWeatherCamera(nint handle,float x,float y,float scale,float groundMin,float groundMax);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetSceneLights(nint handle,float[] lights,int count,float response);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeSetAtmosphere(nint handle,int family,float[] settings);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeGrabLatestFrame(nint handle,[Out]byte[] bytes,uint size,out uint w,out uint h);
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeGrabCompositeFrame(nint handle,[Out]byte[] bytes,uint size,out uint w,out uint h);
    [StructLayout(LayoutKind.Sequential)] struct BulletSourceStats {
        public uint Size,Status,TagValid,HistoryCount;
        public int SourceEpoch,SourceFrame,MatchedOrdinaryEpoch,MatchedOrdinaryFrame,MatchedChainEpoch,MatchedChainFrame;
        public uint MatchedItems,SourceWidth,SourceHeight,Reserved;
        public ulong SampleNumber;public double CaptureQpcMs,SampleQpcMs;
    }
    [DllImport("probe",CallingConvention=CallingConvention.Cdecl)] static extern int ProbeGetBulletSourceStats(nint handle,ref BulletSourceStats stats);
}
