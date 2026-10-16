param([Parameter(Mandatory=$true)][string]$InputPath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Web.Extensions
# Offline geometry only: no window, runtime bitmap, or installed dependency.
Add-Type -ReferencedAssemblies @('PresentationCore','WindowsBase','System.Web.Extensions') -TypeDefinition @'
using System;
using System.IO;
using System.Globalization;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Windows.Media;
public class GuardClipJob { public string path; public int[] clips; public double weight; public string caps; public string joints; public bool fill; }
public class GuardClipInput { public string[][] clips; public GuardClipJob[] jobs; public double tolerance; }
public class GuardClipOutput { public string fill; public string stroke; }
public static class GuardVectorClipper {
    static Geometry Combine(Geometry a, Geometry b, GeometryCombineMode mode, double tolerance) {
        return Geometry.Combine(a,b,mode,null,tolerance,ToleranceType.Absolute);
    }
    static string Export(Geometry shape, double tolerance) {
        if(shape.IsEmpty()) return "";
        return shape.GetFlattenedPathGeometry(tolerance,ToleranceType.Absolute).ToString(CultureInfo.InvariantCulture);
    }
    public static void Run(string inputPath,string outputPath) {
        var json=new JavaScriptSerializer();json.MaxJsonLength=268435456;
        var input=json.Deserialize<GuardClipInput>(File.ReadAllText(inputPath));
        var clips=new Geometry[input.clips.Length];
        for(int i=0;i<clips.Length;i++) {
            Geometry clip=Geometry.Empty;
            foreach(string path in input.clips[i]) clip=Combine(clip,Geometry.Parse(path),GeometryCombineMode.Union,input.tolerance);
            clip.Freeze();clips[i]=clip;
        }
        var chains=new Dictionary<string,Geometry>();
        var output=new List<GuardClipOutput>();
        foreach(var job in input.jobs) {
            string key=String.Join(",",job.clips);Geometry clip;
            if(!chains.TryGetValue(key,out clip)) {
                foreach(int index in job.clips) clip=clip==null?clips[index]:Combine(clip,clips[index],GeometryCombineMode.Intersect,input.tolerance);
                chains[key]=clip;
            }
            var path=Geometry.Parse(job.path);
            Geometry fill=job.fill?path:Geometry.Empty,stroke=Geometry.Empty;
            if(job.weight>0) {
                var pen=new Pen(Brushes.Black,job.weight);
                pen.StartLineCap=pen.EndLineCap=job.caps=="round"?PenLineCap.Round:job.caps=="square"?PenLineCap.Square:PenLineCap.Flat;
                pen.LineJoin=job.joints=="round"?PenLineJoin.Round:job.joints=="bevel"?PenLineJoin.Bevel:PenLineJoin.Miter;
                pen.MiterLimit=3;
                stroke=path.GetWidenedPathGeometry(pen,input.tolerance,ToleranceType.Absolute);
            }
            if(clip!=null) {
                fill=Combine(fill,clip,GeometryCombineMode.Intersect,input.tolerance);
                stroke=Combine(stroke,clip,GeometryCombineMode.Intersect,input.tolerance);
            }
            output.Add(new GuardClipOutput{fill=Export(fill,input.tolerance),stroke=Export(stroke,input.tolerance)});
        }
        File.WriteAllText(outputPath,json.Serialize(output),new System.Text.UTF8Encoding(false));
    }
}
'@
[GuardVectorClipper]::Run((Resolve-Path -LiteralPath $InputPath).Path,$OutputPath)
