using System.Diagnostics;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

// Own source/output windows only. Does not launch Flash, open saves or drive a game.
internal static class Program
{
    private sealed class ProbeWindow : Form
    {
        internal bool Pattern,Black;
        protected override bool ShowWithoutActivation=>true;
        internal ProbeWindow(string title,int x,int y)
        {
            Text=title;FormBorderStyle=FormBorderStyle.None;StartPosition=FormStartPosition.Manual;
            AutoScaleMode=AutoScaleMode.None;Bounds=new Rectangle(x,y,1024,576);
            BackColor=Color.FromArgb(24,28,36);ShowInTaskbar=false;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);if(!Pattern)return;
            if(Black) {e.Graphics.Clear(Color.Black);return;}
            using var a=new SolidBrush(Color.FromArgb(96,112,130));
            using var b=new SolidBrush(Color.FromArgb(80,96,114));
            for(int y=0;y<576;y+=64)for(int x=0;x<1024;x+=64)
                e.Graphics.FillRectangle(((x+y)/64)%2==0?a:b,x,y,64,64);
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        if(args.Length!=3) { Console.Error.WriteLine("Usage: CombatFxProbe <project> <native-dll> <output-dir>");return 2; }
        string root=Path.GetFullPath(args[0]),native=Path.GetFullPath(args[1]),output=Path.GetFullPath(args[2]);
        Directory.CreateDirectory(output);
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        using var source=new ProbeWindow("Combat FX controlled source",20,20);
        source.Pattern=true;
        using var target=new ProbeWindow("Combat FX composed output",80,80);
        source.Show();target.Show();IntPtr sourceHwnd=source.Handle,targetHwnd=target.Handle;
        int result=1;
        Task.Run(async ()=>
        {
            try { await Run(root,native,output,sourceHwnd,targetHwnd,
                black=>source.Invoke(new Action(()=> {source.Black=black;source.Refresh();})));result=0; }
            catch(Exception error) { File.WriteAllText(Path.Combine(output,"failure.txt"),error.ToString());Console.Error.WriteLine(error); }
            finally { source.BeginInvoke(new Action(Application.ExitThread)); }
        });
        Application.Run();return result;
    }

    private static async Task WaitFor(Func<bool> condition,NativeCompositorSession session,string stage)
    {
        var watch=Stopwatch.StartNew();
        while(watch.ElapsedMilliseconds<12000)
        {
            var stats=session.Read();
            if(stats.State>1 || stats.Error<0)throw new InvalidOperationException(stage+": "+stats.Message+" hr="+stats.Error);
            if(condition())return;
            await Task.Delay(80);
        }
        throw new TimeoutException(stage+": "+session.Read().Message);
    }

    private static CombatFxDrawFrame Solid(bool muzzle)
    {
        var draw=new CombatFxDrawFrame(2) {Count=muzzle?2:1,CasingCount=1};
        // Red casing underneath a long existing plain bullet; blue muzzle above both.
        Put(draw,0,300,288,0,1,1,0,-40,-40,100,80,0,0,.5f,1);
        if(muzzle)Put(draw,1,300,288,0,1,1,0,-30,-30,80,60,.5f,0,1,1);
        return draw;
    }

    private static void Put(CombatFxDrawFrame draw,int index,float x,float y,float rotation,float sx,float sy,
        float lit,float ox,float oy,float width,float height,float u0,float v0,float u1,float v1)
    {
        float[] values={x,y,rotation,1,sx,sy,1,lit,ox,oy,width,height,u0,v0,u1,v1};
        Array.Copy(values,0,draw.Data,index*16,16);
    }

    private static (byte[] bytes,int width,int height) Grab(NativeCompositorSession session,string file)
    {
        int status=session.GrabCompositeFrame(null,out int width,out int height);
        if(status!=NativeCompositorSession.GrabBufferTooSmall)throw new InvalidOperationException("Composite size status "+status);
        var bytes=new byte[width*height*4];
        status=session.GrabCompositeFrame(bytes,out width,out height);
        if(status!=NativeCompositorSession.GrabOk)throw new InvalidOperationException("Composite pixels status "+status);
        using var bitmap=new Bitmap(width,height,PixelFormat.Format32bppArgb);
        var bits=bitmap.LockBits(new Rectangle(0,0,width,height),ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);
        try { for(int y=0;y<height;y++)Marshal.Copy(bytes,y*width*4,bits.Scan0+y*bits.Stride,width*4); }
        finally { bitmap.UnlockBits(bits); }
        bitmap.Save(file,ImageFormat.Png);return(bytes,width,height);
    }

    private static int[] Pixel((byte[] bytes,int width,int height) grab,int x,int y)
    {
        int at=(y*grab.width+x)*4;
        return new[]{(int)grab.bytes[at+2],grab.bytes[at+1],grab.bytes[at]};
    }
    private static void Require(bool condition,string message) { if(!condition)throw new InvalidOperationException(message); }

    private static float[] Grade(float r,float g,float b)=>new float[]{r,0,0,0, 0,g,0,0, 0,0,b,0, 0,0,0,1};
    private static double Luma(int[] rgb)=>rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;

    private static object CheckEquipmentVisibility(NativeCompositorSession session,CombatFxCatalog catalog,string output,
        (byte[] bytes,int width,int height) night,(byte[] bytes,int width,int height) muzzle)
    {
        string input=Path.Combine(output,"equipment-lighting-wires.json");
        if(!File.Exists(input))return null;
        var wires=JsonSerializer.Deserialize<Dictionary<string,string>>(File.ReadAllText(input));
        Require(wires.Count==3 && new[]{"blue-set","blue-same","blue-blood"}.All(wires.ContainsKey),"Incomplete AS2 lighting calibration wires");
        var old=LightFrame(catalog,1,118);old.Lights[3]=.525f;
        old.Lights[4]=116f/255;old.Lights[5]=150f/255;old.Lights[6]=240f/255;
        session.CombatFxFrame(old,0,0,1);
        var previous=Grab(session,Path.Combine(output,"equipment-previous-blue-set.png"));
        double beforeCenter=Luma(Pixel(previous,512,288))-Luma(Pixel(night,512,288));
        double beforeFeet=Luma(Pixel(previous,512,363))-Luma(Pixel(night,512,363));
        double muzzleDelta=Luma(Pixel(muzzle,512,288))-Luma(Pixel(night,512,288));
        var samples=new Dictionary<string,object>();
        foreach(var pair in wires)
        {
            Require(CombatFxFrame.TryParse("91|1|1|0"+pair.Value,catalog,out var frame),"AS2 visibility wire rejected: "+pair.Key);
            var engine=new CombatFxEngine(catalog);engine.Apply(frame,1);var draw=engine.BuildDraw();
            Require(draw.LightCount==(pair.Key=="blue-blood"?2:1),"AS2 visibility light grouping: "+pair.Key);
            int body=0;
            for(int i=1;i<draw.LightCount;i++)if(draw.Lights[i*16+2]>draw.Lights[body*16+2])body=i;
            float shiftX=512-draw.Lights[body*16],shiftY=288-draw.Lights[body*16+1];
            for(int i=0;i<draw.LightCount;i++){draw.Lights[i*16]+=shiftX;draw.Lights[i*16+1]+=shiftY;}
            double maxEnergy=0;
            for(int y=126;y<=450;y+=2)for(int x=350;x<=714;x+=2)
            {
                double energy=0;
                for(int i=0;i<draw.LightCount;i++)
                {
                    int at=i*16;double dx=x-draw.Lights[at],dy=y-draw.Lights[at+1],radius=draw.Lights[at+2];
                    double falloff=Math.Max(0,1-(dx*dx+dy*dy)/(radius*radius));
                    energy+=draw.Lights[at+3]*falloff*falloff;
                }
                maxEnergy=Math.Max(maxEnergy,energy);
            }
            Require(maxEnergy<=1.5003,"AS2 combined peak exceeded the ordinary muzzle reference: "+pair.Key);
            session.CombatFxFrame(draw,0,0,1);
            var rendered=Grab(session,Path.Combine(output,"equipment-visible-"+pair.Key+".png"));
            int[] center=Pixel(rendered,512,288),feet=Pixel(rendered,512,363);
            double centerDelta=Luma(center)-Luma(Pixel(night,512,288));
            double feetDelta=Luma(feet)-Luma(Pixel(night,512,363));
            if(pair.Key=="blue-set")
            {
                Require(centerDelta>beforeCenter*1.4,"Blue set center did not become meaningfully brighter");
                Require(feetDelta>beforeFeet*1.8 && feetDelta>beforeFeet+8,"Blue set still leaves the feet unreadable");
            }
            else Require(centerDelta>=muzzleDelta*.8 && centerDelta<=muzzleDelta*1.12,"Equipment combination does not match the muzzle brightness band: "+pair.Key);
            Require(Pixel(rendered,80,80).SequenceEqual(Pixel(night,80,80)),"Equipment visibility leaked outside its local footprint");
            samples[pair.Key]=new{lights=draw.LightCount,center,feet,centerDelta,feetDelta,maxEnergy,muzzleRatio=centerDelta/muzzleDelta};
        }
        session.ClearCombatFxFrame();
        return new{wireSha256=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(input))),
            beforeCenter,beforeFeet,muzzleDelta,samples,boundary="Actual AS2 XML/lifecycle snapshots on a controlled material; not game appearance or game FPS."};
    }
    private static CombatFxDrawFrame LightFrame(CombatFxCatalog catalog,int count=1,float? radius=null)
    {
        var light=catalog.Styles.Single(s=>s.Linkage=="枪火").Light;
        var draw=new CombatFxDrawFrame(1) {LightCount=count,MaximumLightResponse=catalog.MaximumLightResponse};
        for(int i=0;i<count;i++)
            Array.Copy(new float[]{512,288,radius??light.Radius,count==1?light.Energy:2,light.R,light.G,light.B,0,1,0,1,0,0,0,0,0},0,
                draw.Lights,i*CombatFxEngine.LightStride,CombatFxEngine.LightStride);
        return draw;
    }
    private static CombatFxDrawFrame DirectionalLight(CombatFxCatalog catalog,int kind,
        float x,float y,float dx,float dy,float length,float width,
        float nearX=0,float nearY=0,float nearRadius=0,float nearEnergy=0)
    {
        var draw=new CombatFxDrawFrame(1) {LightCount=1,MaximumLightResponse=catalog.MaximumLightResponse};
        Array.Copy(new float[]{x,y,length,kind==1?1.45f:.85f,1,kind==1?241f/255:102f/255,kind==1?208f/255:80f/255,
            kind,dx,dy,width,0,nearX,nearY,nearRadius,nearEnergy},draw.Lights,CombatFxEngine.LightStride);
        return draw;
    }
    private static object CheckEquipmentLights(NativeCompositorSession session,CombatFxCatalog catalog,string output,
        (byte[] bytes,int width,int height) dark)
    {
        session.CombatFxFrame(DirectionalLight(catalog,1,220,288,1,0,500,90),0,0,1);
        var cone=Grab(session,Path.Combine(output,"equipment-flashlight-cone.png"));
        Require(Pixel(cone,400,288)[0]>Pixel(dark,400,288)[0]+12,"Flashlight did not illuminate cone interior");
        Require(Pixel(cone,400,410).SequenceEqual(Pixel(dark,400,410)),"Flashlight leaked outside cone");
        Require(Pixel(cone,180,288).SequenceEqual(Pixel(dark,180,288)),"Flashlight illuminated behind its outlet");
        session.CombatFxFrame(DirectionalLight(catalog,1,512,100,0,1,400,90),0,0,1);
        var rotated=Grab(session,Path.Combine(output,"equipment-flashlight-rotated.png"));
        Require(Pixel(rotated,512,300)[0]>Pixel(dark,512,300)[0]+12,"Rotated flashlight lost its direction");
        session.CombatFxFrame(DirectionalLight(catalog,1,800,288,-1,0,500,90),0,0,1);
        var mirrored=Grab(session,Path.Combine(output,"equipment-flashlight-mirrored.png"));
        Require(Pixel(mirrored,600,288)[0]>Pixel(dark,600,288)[0]+12
            && Pixel(mirrored,920,288).SequenceEqual(Pixel(dark,920,288)),"Mirrored flashlight points backwards");
        session.CombatFxFrame(DirectionalLight(catalog,2,180,288,1,0,640,8),0,0,1);
        var laser=Grab(session,Path.Combine(output,"equipment-laser-illumination.png"));
        Require(Pixel(laser,500,288)[0]>Pixel(dark,500,288)[0]+12,"Laser failed to reveal covered material");
        Require(Pixel(laser,500,315).SequenceEqual(Pixel(dark,500,315)),"Laser illumination is wider than its configured band");
        float diagonal=(float)Math.Sqrt(.5);
        session.CombatFxFrame(DirectionalLight(catalog,2,180,100,diagonal,diagonal,550,.5f),0,0,1);
        var thin=Grab(session,Path.Combine(output,"equipment-laser-thin-diagonal.png"));
        for(int offset=80;offset<=240;offset+=80)
            Require(Pixel(thin,180+offset,100+offset)[0]>Pixel(dark,180+offset,100+offset)[0]+2,
                "Subpixel diagonal laser has a sampling hole at "+offset);
        session.CombatFxFrame(DirectionalLight(catalog,1,300,288,1,0,1000,260,210,330,140,1.15f),0,0,1);
        var practical=Grab(session,Path.Combine(output,"equipment-flashlight-practical.png"));
        Require(Pixel(practical,150,330)[0]>Pixel(dark,150,330)[0]+20,"Near fill failed to reveal the holder behind the muzzle");
        Require(Pixel(practical,210,405)[0]>Pixel(dark,210,405)[0]+12,"Near fill failed to reveal the holder's feet");
        Require(Pixel(practical,850,288)[0]>Pixel(dark,850,288)[0]+20,"Extended flashlight lost its useful midrange core");
        Require(Pixel(practical,5,550).SequenceEqual(Pixel(dark,5,550)),"Composite flashlight leaked outside cone and near circle");
        Require(Pixel(practical,40,330).SequenceEqual(Pixel(dark,40,330)),"Near fill retained its oversized rear footprint");
        // Same checkerboard material every 128 pixels: intensity must fall continuously,
        // rather than hiding a constant-bright section behind texture differences.
        var forwardProfile=new[]{450,578,706,834}.Select(x=>Pixel(practical,x,288)[0]).ToArray();
        Require(forwardProfile.Zip(forwardProfile.Skip(1),(a,b)=>a>b).All(v=>v),"Flashlight retained a flat forward plateau");
        var radialProfile=new[]{330,354,378,402,426,450}.Select(y=>
            Pixel(practical,180,y)[0]-Pixel(dark,180,y)[0]).ToArray();
        Require(radialProfile[0]>radialProfile[1] && radialProfile[1]>radialProfile[2]
            && radialProfile[2]>radialProfile[3] && radialProfile[3]>radialProfile[4]
            && radialProfile[4]>radialProfile[5],"Near fill retained a flat disk or hard rim");
        // A single lobe at its configured peak bounds the smooth union. Check the
        // whole overlap against it to catch a double-exposure seam, not just one pixel.
        var ceiling=DirectionalLight(catalog,1,300,288,1,0,1000,260,210,330,320,1.45f);
        ceiling.Lights[7]=0;ceiling.Lights[0]=280;ceiling.Lights[1]=310;ceiling.Lights[2]=1024;
        Array.Clear(ceiling.Lights,12,4);
        session.CombatFxFrame(ceiling,0,0,1);
        var maximum=Grab(session,Path.Combine(output,"equipment-flashlight-overlap-ceiling.png"));
        for(int y=260;y<=360;y+=10)for(int x=210;x<=370;x+=10)
            Require(Pixel(practical,x,y)[0]<=Pixel(maximum,x,y)[0]+1,"Near and forward lobes produced an overlap hotspot");
        session.CombatFxFrame(DirectionalLight(catalog,1,512,100,0,1,400,90,450,80,100,1.15f),0,0,1);
        var offsetNear=Grab(session,Path.Combine(output,"equipment-flashlight-offset-near.png"));
        Require(Pixel(offsetNear,420,80)[0]>Pixel(dark,420,80)[0]+20,"Rotated composite quad clipped its offset near field");
        Require(Pixel(offsetNear,700,80).SequenceEqual(Pixel(dark,700,80)),"Near field enabled an unbounded reverse cone");
        session.CombatFxFrame(DirectionalLight(catalog,2,180,288,1,0,750,28),0,0,1);
        var practicalLaser=Grab(session,Path.Combine(output,"equipment-laser-practical.png"));
        var laserCore=Pixel(practicalLaser,500,288);var laserEdge=Pixel(practicalLaser,500,302);
        Require(laserCore[0]>laserEdge[0]+8 && laserEdge[0]>Pixel(dark,500,302)[0]+4,
            "Laser lost its narrow core and soft transverse falloff");
        Require(laserCore[0]-Pixel(dark,500,288)[0]>laserCore[1]-Pixel(dark,500,288)[1]+8,
            "Laser illumination lost its red emphasis");
        Require(Pixel(practicalLaser,500,325).SequenceEqual(Pixel(dark,500,325)),"Laser retained an over-wide light panel");
        Require(Pixel(practicalLaser,100,288).SequenceEqual(Pixel(dark,100,288)),"Laser gained an unauthorized near field");
        // Route resident radials through the actual parser and engine, rather than
        // injecting a muzzle pulse or hand-packing a second interpretation of kind 0.
        Require(CombatFxFrame.TryParse("7|1|1|0;l,71,0,240,280,0,0,118,0,0.525,0.455,0.588,0.941,0,0,0,0;"
            +"l,72,0,500,280,0,0,70,0,0.6,1,0.333,0.4,0,0,0,0",catalog,out var radialFrame),"Resident radial fixture rejected");
        var radialEngine=new CombatFxEngine(catalog);radialEngine.Apply(radialFrame,1);
        var radialDraw=radialEngine.BuildDraw();
        Require(radialDraw.LightCount==2,"Independent body and blade radials did not retain two bounded records");
        session.CombatFxFrame(radialDraw,0,0,1);
        var radials=Grab(session,Path.Combine(output,"equipment-body-and-blade-radials.png"));
        var bodyCenter=Pixel(radials,240,280);var swordCenter=Pixel(radials,500,280);
        var darkBody=Pixel(dark,240,280);var darkSword=Pixel(dark,500,280);
        Require(bodyCenter[2]>darkBody[2]+12 && bodyCenter[2]-darkBody[2]>bodyCenter[0]-darkBody[0]+6,
            "Blue armor radial lost its visible blue material contribution");
        Require(swordCenter[0]>darkSword[0]+12 && swordCenter[0]-darkSword[0]>swordCenter[2]-darkSword[2]+3,
            "Red blade radial was averaged into the armor color");
        // These two diagonal positions use the same checker material.
        Require(bodyCenter[2]-darkBody[2]>Pixel(radials,272,344)[2]-Pixel(dark,272,344)[2]+8,
            "Armor radial retained a flat disk instead of a soft falloff");
        Require(Pixel(radials,368,408).SequenceEqual(Pixel(dark,368,408)),"Resident radial leaked beyond both radii");
        session.CombatFxFrame(radialDraw,-320,0,1);
        var movedRadials=Grab(session,Path.Combine(output,"equipment-radials-camera.png"));
        Require(Pixel(movedRadials,180,280)[0]>Pixel(dark,180,280)[0]+12,
            "Resident blade radial did not follow the world camera");
        Require(Pixel(movedRadials,500,280).SequenceEqual(Pixel(dark,500,280)),"Resident radial left light at its old camera position");
        session.ClearCombatFxFrame();
        var clear=Grab(session,Path.Combine(output,"equipment-lights-cleared.png"));
        Require(Pixel(clear,500,288).SequenceEqual(Pixel(dark,500,288)),"Equipment light survived explicit cleanup");
        return new {cone=Pixel(cone,400,288),rotated=Pixel(rotated,512,300),mirrored=Pixel(mirrored,600,288),
            laser=Pixel(laser,500,288),nearBody=Pixel(practical,150,330),nearFeet=Pixel(practical,210,405),
            farCore=Pixel(practical,850,288),practicalLaser=laserCore,laserEdge,forwardProfile,radialProfile,
            bodyCenter,swordCenter,residentRadialCamera=true,residentRadialSeparateColors=true,
            compositeBudgetSlots=1,offsetNear=true,noOverlapHotspot=true,continuousFalloff=true,thinDiagonal=true,cleared=true};
    }
    private static long RegionRed((byte[] bytes,int width,int height) grab,int radius)
    {
        long total=0;
        for(int y=288-radius;y<288+radius;y++)for(int x=512-radius;x<512+radius;x++)
            if((x-512)*(x-512)+(y-288)*(y-288)<radius*radius)total+=grab.bytes[(y*grab.width+x)*4+2];
        return total;
    }
    private static async Task<object> Measure(NativeCompositorSession session,CombatFxDrawFrame draw)
    {
        session.CombatFxFrame(draw,0,0,1);var values=new List<double>();var waits=new List<double>();
        ulong last=session.Read().Presented;var watch=Stopwatch.StartNew();
        while(values.Count<90 && watch.ElapsedMilliseconds<8000)
        {
            await Task.Delay(12);var s=session.Read();
            if(s.Presented==last)continue;
            last=s.Presented;values.Add(s.SubmitMs);waits.Add(s.PresentMs);
        }
        Require(values.Count>=60,"Insufficient real compositor timing samples");
        values.Sort();waits.Sort();
        return new {samples=values.Count,submitMedianMs=values[values.Count/2],submitP95Ms=values[(int)(values.Count*.95)],
            presentMedianMs=waits[waits.Count/2],boundary="CPU submission/present timings, not GPU timestamps or game FPS"};
    }

    private static async Task Run(string root,string module,string output,IntPtr source,IntPtr target,Action<bool> blackSource)
    {
        using var session=new NativeCompositorSession(module,source,(uint)Environment.ProcessId,target);
        session.Mode(0);
        await WaitFor(()=>session.Read().Presented>0,session,"initial capture");
        var size=session.ReadCaptureSize();session.Viewport(new Rectangle(0,0,size.Width,size.Height),0);
        byte[] colors=new byte[8*4*4];
        for(int y=0;y<4;y++)for(int x=0;x<8;x++)
        { int at=(y*8+x)*4;colors[at+(x<4?2:0)]=255;colors[at+3]=255; }
        session.CombatFxAtlas(colors,8,4);
        await WaitFor(()=>session.CombatFxReady,session,"atlas upload and shader readiness");
        var bullets=BulletVisualCatalog.Load(root);session.BulletStyles(bullets);
        Require(BulletVisualFrame.TryParse("1|1|1|0|0|1;0,260,288,0,400,2000,100",bullets.Styles.Count,out var bullet),"bullet fixture parse");
        session.BulletFrame(bullet,0,0,1);session.CombatFxFrame(Solid(false),0,0,1);
        var under=Grab(session,Path.Combine(output,"casing-under-bullet.png"));
        var underPixel=Pixel(under,320,288);
        Require(underPixel[0]>235 && underPixel[1]>235 && underPixel[2]>170,"Casing should be under the existing bullet: "+string.Join(",",underPixel));
        session.CombatFxFrame(Solid(true),0,0,1);
        var over=Grab(session,Path.Combine(output,"muzzle-over-bullet.png"));var overPixel=Pixel(over,320,288);
        Require(overPixel[2]>245 && overPixel[0]<8 && overPixel[1]<8,"Muzzle should be over the existing bullet: "+string.Join(",",overPixel));

        session.ClearBulletFrame();var graded=Solid(true);graded.Data[7]=1;
        // Separate the two quads; halve world red while keeping muzzle blue emissive.
        graded.Data[16]=600;session.CombatFxFrame(graded,0,0,1);
        session.Matrix(new float[]{.5f,0,0,0, 0,.5f,0,0, 0,0,.5f,0, 0,0,0,1});
        var lighting=Grab(session,Path.Combine(output,"world-grade-emissive.png"));
        var red=Pixel(lighting,300,288);var blue=Pixel(lighting,600,288);
        Require(red[0]>=126 && red[0]<=129 && red[1]<8,"Casing world grade failed: "+string.Join(",",red));
        Require(blue[2]>245 && blue[0]<8,"Muzzle emissive grade failed: "+string.Join(",",blue));
        session.Matrix(new float[]{1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1});

        var catalog=CombatFxCatalog.Load(root);session.CombatFxAtlas(catalog);
        await WaitFor(()=>session.CombatFxReady,session,"authored atlas upload");
        var gallery=new CombatFxDrawFrame(32);int count=0;
        foreach(var style in catalog.Styles.Where(s=>s.IsCasing))
        {
            var f=style.Frames[0];int index=count++;
            Put(gallery,index,85+index%9*110,75+index/9*110,index*23,2,2,1,f.OffsetX,f.OffsetY,f.Width,f.Height,f.U0,f.V0,f.U1,f.V1);
        }
        gallery.CasingCount=count;
        foreach(var style in catalog.Styles.Where(s=>s.IsMuzzle))
        {
            var f=style.Frames[style.Variants[Math.Min(1,style.Variants.Length-1)][0]];int index=count++;
            float factor=style.Linkage=="巴雷特枪火"?.45f:1;
            Put(gallery,index,50+(index-gallery.CasingCount)%5*200,320+(index-gallery.CasingCount)/5*150,0,factor,factor,0,
                f.OffsetX,f.OffsetY,f.Width,f.Height,f.U0,f.V0,f.U1,f.V1);
        }
        gallery.Count=count;session.CombatFxFrame(gallery,0,0,1);
        Grab(session,Path.Combine(output,"authored-gallery.png"));
        var hits=new CombatFxDrawFrame(16);
        foreach(var style in catalog.Styles.Where(s=>s.IsImpact))
        {
            int index=hits.Count++;int[] animation=style.Variants[0];var f=style.Frames[animation[Math.Min(3,animation.Length-1)]];
            Put(hits,index,120+index%4*245,140+index/4*280,0,1.3f,1.3f,style.WorldLit?1:0,
                f.OffsetX,f.OffsetY,f.Width,f.Height,f.U0,f.V0,f.U1,f.V1);
        }
        session.CombatFxFrame(hits,0,0,1);Grab(session,Path.Combine(output,"impact-gallery.png"));
        session.ClearCombatFxFrame();
        var neutral=Grab(session,Path.Combine(output,"neutral-world.png"));
        session.Matrix(Grade(.12f,.12f,.12f));
        var dark=Grab(session,Path.Combine(output,"night-before-light.png"));
        var local=LightFrame(catalog);session.CombatFxFrame(local,0,0,1);
        var lit=Grab(session,Path.Combine(output,"night-with-light.png"));
        Require(Pixel(lit,512,288)[0]>Pixel(dark,512,288)[0]+12,"Local light did not reveal world texture");
        Require(Pixel(lit,80,80).SequenceEqual(Pixel(dark,80,80)),"Local light leaked outside radius");
        session.CombatFxFrame(local,-280,-80,1.1f);
        var moved=Grab(session,Path.Combine(output,"light-camera-transform.png"));
        Require(Pixel(moved,283,237)[0]>Pixel(dark,283,237)[0]+12,"Light did not follow world camera");
        Require(Pixel(moved,512,288).SequenceEqual(Pixel(dark,512,288)),"Old light position was retained");
        var stacked=LightFrame(catalog,16);session.CombatFxFrame(stacked,0,0,1);
        var bright=Grab(session,Path.Combine(output,"overlapping-lights.png"));
        Require(Pixel(bright,512,288)[0]>Pixel(lit,512,288)[0]+5,"Light overlap did not accumulate");
        double exposedRed=255*(1-Math.Exp(-Pixel(neutral,512,288)[0]/255.0*1.8));
        double cappedRed=Pixel(dark,512,288)[0]*(1-catalog.MaximumLightResponse)+exposedRed*catalog.MaximumLightResponse;
        Require(Pixel(bright,512,288)[0]<=cappedRed+2,"Overlapping lights exceeded response cap");
        session.ClearCombatFxFrame();
        var cleared=Grab(session,Path.Combine(output,"light-cleared.png"));
        Require(Pixel(cleared,512,288).SequenceEqual(Pixel(dark,512,288)),"Retired light left residual brightness");
        var equipmentLights=CheckEquipmentLights(session,catalog,output,dark);

        // All-black source isolates weather illumination from world illumination.
        ulong beforeBlack=session.Read().Received;blackSource(true);
        await WaitFor(()=>session.Read().Received>beforeBlack,session,"black weather fixture source");
        session.WeatherCamera(0,0,1,360,520);
        session.WeatherStyle(2,160,new float[]{1,1,1,1, 1,1,1,1, .1f,0,1,1, .85f,1,0,0});
        session.Weather(2,1,0,413);
        var snowDark=Grab(session,Path.Combine(output,"weather-before-light.png"));
        var wide=LightFrame(catalog,1,320);wide.Lights[3]=2;session.CombatFxFrame(wide,0,0,1);
        var snowLit=Grab(session,Path.Combine(output,"weather-with-light.png"));
        long weatherBefore=RegionRed(snowDark,220),weatherAfter=RegionRed(snowLit,220);
        Require(weatherBefore>100 && weatherAfter>weatherBefore*1.4,"Weather did not sample local light field");
        session.Weather(0,0,0,413);
        beforeBlack=session.Read().Received;blackSource(false);
        await WaitFor(()=>session.Read().Received>beforeBlack,session,"restore patterned source");

        // The user's session included both night L0 and dusk L5. Ambient LUT colour
        // must not tint direct muzzle light; night vision uses a separate matrix route.
        var preset=WorldLightingPreset.Load(Path.Combine(root,"launcher/data/world-lighting/preset.json"),Console.Error.WriteLine);
        Require(preset.UsesLut("光照") && !preset.UsesLut("夜视"),"Production lighting route changed");
        session.ClearCombatFxFrame();session.SetLut(preset.LutSet.BlendLevel(0));
        var night=Grab(session,Path.Combine(output,"production-l0-before-light.png"));
        session.CombatFxFrame(local,0,0,1);
        var nightLit=Grab(session,Path.Combine(output,"production-l0-with-light.png"));
        int[] nightCenter=Pixel(night,512,288),nightLitCenter=Pixel(nightLit,512,288);
        Require(nightLitCenter[0]>=nightCenter[0]+50,"Muzzle light is still too faint under production L0");
        int[] material=Pixel(neutral,512,288);
        Require((nightLitCenter[0]-nightCenter[0])/(double)material[0]>
            (nightLitCenter[2]-nightCenter[2])/(double)material[2]*1.1,
            "Direct warm light inherited the ambient blue tint");
        Require(Pixel(nightLit,580,288)[0]>=Pixel(night,580,288)[0]+20,"Only the muzzle centre is illuminated");
        Require(Pixel(nightLit,80,80).SequenceEqual(Pixel(night,80,80)),"Production light leaked outside radius");
        var equipmentVisibility=CheckEquipmentVisibility(session,catalog,output,night,nightLit);

        var engine=new CombatFxEngine(catalog);int muzzle=Array.FindIndex(catalog.Styles,s=>s.Linkage=="枪火");
        var pulse=new List<object>();int peakRed=0;
        for(int age=0;age<=catalog.Styles[muzzle].Light.Ticks;age++) {
            string spawn=age==0?$";m,{muzzle},512,288,100,100,0,1,0":"";
            Require(CombatFxFrame.TryParse($"1|{age+1}|{age+1}|0"+spawn,catalog,out var tick),"Pulse fixture parse");
            engine.Apply(tick,1);var frame=engine.BuildDraw();
            // Isolate lighting from the bright authored sprite when measuring world pixels.
            frame.Count=0;session.CombatFxFrame(frame,0,0,1);
            var pulseFrame=Grab(session,Path.Combine(output,$"production-l0-pulse-{age}.png"));
            int[] center=Pixel(pulseFrame,512,288);if(age==0)peakRed=center[0];
            if(age==1)Require(center[0]>=peakRed-2,"Pulse peak does not survive a full game frame");
            if(age==catalog.Styles[muzzle].Light.Ticks-1)Require(center[0]>=nightCenter[0]+20,"Pulse tail is imperceptible");
            if(age==catalog.Styles[muzzle].Light.Ticks)Require(center.SequenceEqual(nightCenter),"Expired pulse left brightness");
            pulse.Add(new {age,energy=frame.LightCount==0?0:frame.Lights[3],center});
        }
        session.ClearCombatFxFrame();session.SetLut(preset.LutSet.BlendLevel(5));
        var dusk=Grab(session,Path.Combine(output,"production-l5-before-light.png"));
        session.CombatFxFrame(local,0,0,1);
        var duskLit=Grab(session,Path.Combine(output,"production-l5-with-light.png"));
        Require(Pixel(duskLit,512,288)[0]>=Pixel(dusk,512,288)[0]+25,"Dusk gunfire has no visible warm contribution");
        session.ClearLut();session.Matrix(new float[]{.04252f,.14304f,.01444f,0, .2126f,.7152f,.0722f,0,
            .02126f,.07152f,.00722f,0, 0,.035f,0,1});
        session.CombatFxFrame(local,0,0,1);
        var nightVision=Grab(session,Path.Combine(output,"light-with-night-vision.png"));
        var green=Pixel(nightVision,512,288);
        Require(green[1]>green[0]*1.7 && green[1]>green[2]*1.2,"Local light lost the night-vision palette");
        session.ClearLut();session.Matrix(Grade(.12f,.12f,.12f));
        gallery.MaximumLightResponse=catalog.MaximumLightResponse;gallery.LightCount=0;
        var noLightsTiming=await Measure(session,gallery);
        Array.Copy(stacked.Lights,gallery.Lights,stacked.Lights.Length);gallery.LightCount=16;
        var lightsTiming=await Measure(session,gallery);
        var stats=session.Read();
        var report=new {schema="cf7-combat-fx-gpu-probe.v1",utc=DateTime.UtcNow,process=Environment.ProcessId,
            module=Path.GetFullPath(module),atlas=catalog.Sha256,lighting=catalog.LightingSha256,adapter=stats.Adapter,
            proof=new {casingUnderBullet=underPixel,muzzleAboveBullet=overPixel,worldGradedCasing=red,emissiveMuzzle=blue,
                worldBefore=Pixel(dark,512,288),worldLit=Pixel(lit,512,288),overlap=Pixel(bright,512,288),cappedRed,
                productionL0Before=nightCenter,productionL0Lit=nightLitCenter,pulse,nightVision=green,
                productionL5Before=Pixel(dusk,512,288),productionL5Lit=Pixel(duskLit,512,288),
                weatherBefore,weatherAfter,equipmentLights,equipmentVisibility,cameraTransform=true,cleared=true},
            timings=new {noLights=noLightsTiming,sixteenLights=lightsTiming},
            images=Directory.GetFiles(output,"*.png").Select(Path.GetFileName).ToArray(),
            boundary="Controlled WGC source and real compositor GPU output; no gameplay or human visual acceptance."};
        File.WriteAllText(Path.Combine(output,"probe.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions {WriteIndented=true}));
        Console.WriteLine("PASS: atlas/layers, impact sprites, local world and weather illumination, camera, stacking, cleanup, production L0/L5, pulse and night vision.");
    }
}
