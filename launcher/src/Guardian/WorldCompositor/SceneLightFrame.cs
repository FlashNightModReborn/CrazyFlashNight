using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal readonly record struct SceneLightPose(int Id,float X,float Y,float Dx,float Dy,float Scale,float Weight,float Handedness=1);
    internal sealed record SceneLightSnapshot(int Revision,string Key,JObject[] Definitions,SceneLightPose[] Poses)
    {
        internal static bool TryParse(JToken token,out SceneLightSnapshot snapshot)
        {
            snapshot=null;if(token==null || token.Type==JTokenType.Null)return true;
            if(token is not JObject o || o.Value<int?>("version")!=1 || o["revision"]?.Type!=JTokenType.Integer
                || o.Value<int>("revision")<1 || o["key"]?.Type!=JTokenType.String || o.Value<string>("key").Length>256
                || o["definitions"] is not JArray defs || defs.Count>SceneLightCatalog.Limit
                || o["poses"] is not JArray poses || poses.Count!=defs.Count)return false;
            var d=new JObject[defs.Count];var p=new SceneLightPose[defs.Count];var keys=new HashSet<string>(StringComparer.Ordinal);
            for(int i=0;i<d.Length;i++) {
                if(defs[i] is not JObject v || v["Key"]?.Type!=JTokenType.String || !keys.Add(v.Value<string>("Key"))
                    || poses[i] is not JArray a || a.Count!=8 || !Pose(string.Join(',',a.Select(v=>v.ToString(Newtonsoft.Json.Formatting.None))),out p[i]) || p[i].Id!=i+1)return false;
                d[i]=(JObject)v.DeepClone();
            }
            snapshot=new(o.Value<int>("revision"),o.Value<string>("key"),d,p);return true;
        }
        internal static bool Pose(string row,out SceneLightPose p)
        {
            p=default;string[] a=row.Split(',');if(a.Length!=8 || !int.TryParse(a[0],NumberStyles.None,CultureInfo.InvariantCulture,out int id)
                || id<1 || id>SceneLightCatalog.Limit)return false;
            var n=new float[7];for(int i=0;i<7;i++)if(!float.TryParse(a[i+1],NumberStyles.Float,CultureInfo.InvariantCulture,out n[i]) || !float.IsFinite(n[i]))return false;
            if(Math.Abs(n[0])>1000000 || Math.Abs(n[1])>1000000 || Math.Abs(n[2]*n[2]+n[3]*n[3]-1)>.01
                || n[4]<.001 || n[4]>20 || n[5]<0 || n[5]>1 || (n[6]!=1 && n[6]!=-1))return false;
            p=new(id,n[0],n[1],n[2],n[3],n[4],n[5],n[6]);return true;
        }
    }
    internal sealed record SceneLightState(long Scene,int Revision,long Sequence,SceneLightPose[] Poses)
    {
        internal static bool TryParse(string text,out SceneLightState frame)
        {
            frame=null;if(string.IsNullOrEmpty(text)||text.Length>24576)return false;
            string[] rows=text.Split(';'), header=rows[0].Split('|');
            if(rows.Length>SceneLightCatalog.Limit+1 || header.Length!=3
                || !long.TryParse(header[0],NumberStyles.None,CultureInfo.InvariantCulture,out long scene) || scene<1 || scene>1000000000
                || !int.TryParse(header[1],NumberStyles.None,CultureInfo.InvariantCulture,out int revision) || revision<1 || revision>1000000000
                || !long.TryParse(header[2],NumberStyles.None,CultureInfo.InvariantCulture,out long sequence) || sequence<1 || sequence>1000000000)return false;
            var poses=new SceneLightPose[rows.Length-1];var seen=new HashSet<int>();
            for(int i=1;i<rows.Length;i++)if(!SceneLightSnapshot.Pose(rows[i],out poses[i-1]) || !seen.Add(poses[i-1].Id))return false;
            frame=new(scene,revision,sequence,poses);return true;
        }
    }
}
