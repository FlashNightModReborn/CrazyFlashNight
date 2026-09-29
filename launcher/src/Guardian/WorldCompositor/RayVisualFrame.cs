using System;
using System.Collections.Generic;
using System.Globalization;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // F section 7 is an ordered event stream. Never put it through a latest-wins frame mailbox.
    // Header epoch|sequence|gameTick|paused. Config: c,id,style,<FieldNames>,palette(:).
    // Optional light override directly after its c: l,id,profile,energy,width,color,fadeTicks.
    // Spawn/upsert: s/u,id,config,birthTick,delay,sx,sy,ex,ey,kind,hitIndex,intensity,isHit,
    // seed,key,serial,targetLength,pulseIndex,pulseCount,flags,hitPoints,damageHitPoints.
    // Stop: x,id,serial. Point lists use x:y/x:y; '-'=null, '!'=empty.
    internal sealed class RayVisualFrame
    {
        internal readonly int Epoch, Sequence, GameTick;
        internal readonly bool Paused;
        internal readonly float OffsetX,OffsetY;
        internal readonly RayVisualConfig[] Configs;
        internal readonly RayVisualEvent[] Events;
        private RayVisualFrame(int epoch, int seq, int tick, bool paused, float ox,float oy,RayVisualConfig[] configs, RayVisualEvent[] events)
        { Epoch=epoch; Sequence=seq; GameTick=tick; Paused=paused; OffsetX=ox;OffsetY=oy;Configs=configs; Events=events; }

        internal static bool TryParse(string payload, out RayVisualFrame frame)
        {
            frame=null;
            if (string.IsNullOrEmpty(payload) || payload.Length>4*1024*1024) return false;
            string[] records=payload.Split(';');
            // header+offset+ConfigLimit config/light pairs+MaxEvents spawn/update/stop rows
            if (records.Length>2+RayVisualCatalog.ConfigLimit*2+RayVisualCatalog.MaxEvents) return false;
            string[] h=records[0].Split('|');
            if (h.Length!=4 || !Int(h[0],0,1000000000,out int epoch) || !Int(h[1],1,1000000000,out int seq)
                || !Int(h[2],0,1000000000,out int tick) || !Int(h[3],0,1,out int paused)) return false;
            var configs=new List<RayVisualConfig>();
            var ids=new HashSet<int>();
            var events=new List<RayVisualEvent>();
            bool hasOffset=false;float ox=0,oy=0;
            RayVisualConfig pendingLight=null;
            for (int i=1;i<records.Length;i++)
            {
                string[] f=records[i].Split(',');
                if(f[0]=="l")
                {
                    // An l belongs to this packet's immediately preceding immutable c.
                    // It cannot patch a previous packet, repeat, or skip over an event.
                    if(pendingLight==null || f.Length!=7
                        || !Int(f[1],1,RayVisualCatalog.ConfigLimit,out int lightId) || lightId!=pendingLight.Id
                        || !RayLightOverrides.IsKnownProfile(f[2])
                        || !Float(f[3],0,2,out float energy) || !Float(f[4],.25f,4,out float width)
                        || !SignedInt(f[5],-1,0xFFFFFF,out int color)
                        || !SignedInt(f[6],-1,30,out int fadeTicks)) return false;
                    configs[^1]=new RayVisualConfig(pendingLight.Id,pendingLight.Style,pendingLight.Values,pendingLight.Palette,
                        new RayLightOverrides(f[2],energy,width,color,fadeTicks));
                    pendingLight=null;continue;
                }
                pendingLight=null;
                if (f[0]=="o")
                {
                    if (hasOffset || f.Length!=3 || !Float(f[1],-1000000,1000000,out ox)
                        || !Float(f[2],-1000000,1000000,out oy)) return false;
                    hasOffset=true;continue;
                }
                if (f[0]=="c")
                {
                    if (f.Length!=RayVisualCatalog.FieldNames.Length+4 || configs.Count>=RayVisualCatalog.ConfigLimit
                        || !Int(f[1],1,RayVisualCatalog.ConfigLimit,out int id) || !ids.Add(id)
                        || !Int(f[2],0,RayVisualCatalog.Styles.Length-1,out int style)) return false;
                    float[] values=new float[RayVisualCatalog.FieldNames.Length];
                    for (int k=0;k<values.Length;k++)
                        if (!Float(f[k+3],-16777215,16777215,out values[k]) || !RayVisualCatalog.ValidField(k,values[k])) return false;
                    int[] palette=Array.Empty<int>();
                    if (f[^1]!="-")
                    {
                        string[] colors=f[^1].Split(':');
                        if (colors.Length<1 || colors.Length>16) return false;
                        palette=new int[colors.Length];
                        for (int k=0;k<colors.Length;k++) if (!Int(colors[k],0,16777215,out palette[k])) return false;
                    }
                    pendingLight=new RayVisualConfig(id,style,values,palette);
                    configs.Add(pendingLight);
                    continue;
                }
                if (events.Count>=RayVisualCatalog.MaxEvents) return false;
                if (f[0]=="x")
                {
                    if (f.Length!=3 || !Int(f[1],1,1000000000,out int id) || !Int(f[2],0,1000000000,out int serial)) return false;
                    events.Add(new RayVisualEvent(id,serial)); continue;
                }
                if ((f[0]!="s" && f[0]!="u") || f.Length!=23
                    || !Int(f[1],1,1000000000,out int arcId) || !Int(f[2],1,RayVisualCatalog.ConfigLimit,out int cfg)
                    || !Int(f[3],0,1000000000,out int birth) || birth>tick+1 || !Int(f[4],0,600,out int delay)
                    || !Float(f[5],-1000000,1000000,out float sx) || !Float(f[6],-1000000,1000000,out float sy)
                    || !Float(f[7],-1000000,1000000,out float ex) || !Float(f[8],-1000000,1000000,out float ey)
                    || !Int(f[9],0,4,out int kind) || !Int(f[10],0,1000000,out int hitIndex)
                    || !Float(f[11],0,1000,out float intensity) || !Int(f[12],0,1,out int isHit)
                    || !Int(f[13],1,int.MaxValue,out int seed) || !Int(f[14],0,1000000000,out int key)
                    || !Int(f[15],0,1000000000,out int flameSerial) || !Float(f[16],0,1000000,out float targetLength)
                    || !Int(f[17],0,1000000,out int pulseIndex) || !Int(f[18],0,1000000,out int pulseCount)
                    || !Int(f[19],0,7,out int flags) || !Points(f[20],out RayVisualPoint[] points)
                    || !Points(f[21],out RayVisualPoint[] damagePoints) || f[22]!="0") return false;
                // A channel upsert must have an identity. Style/kind and immutable
                // binding checks require the config table and run atomically in Apply.
                if (f[0]=="u" && key==0) return false;
                events.Add(new RayVisualEvent(f[0][0],arcId,cfg,birth,delay,sx,sy,ex,ey,kind,hitIndex,intensity,
                    isHit!=0,(uint)seed,key,flameSerial,targetLength,pulseIndex,pulseCount,flags,points,damagePoints));
            }
            frame=new RayVisualFrame(epoch,seq,tick,paused!=0,ox,oy,configs.ToArray(),events.ToArray());
            return true;
        }
        private static bool Points(string value,out RayVisualPoint[] points)
        {
            points=null;
            if (value=="-") return true;
            if (value=="!") { points=Array.Empty<RayVisualPoint>(); return true; }
            string[] pairs=value.Split('/');
            if (pairs.Length>128) return false;
            points=new RayVisualPoint[pairs.Length];
            for (int i=0;i<pairs.Length;i++)
            {
                string[] xy=pairs[i].Split(':');
                if (xy.Length!=2 || !Float(xy[0],-1000000,1000000,out float x)
                    || !Float(xy[1],-1000000,1000000,out float y)) return false;
                points[i]=new RayVisualPoint(x,y);
            }
            return true;
        }
        private static bool Int(string s,int min,int max,out int v) =>
            int.TryParse(s,NumberStyles.None,CultureInfo.InvariantCulture,out v) && v>=min && v<=max;
        private static bool SignedInt(string s,int min,int max,out int v) =>
            int.TryParse(s,NumberStyles.AllowLeadingSign,CultureInfo.InvariantCulture,out v) && v>=min && v<=max;
        private static bool Float(string s,float min,float max,out float v) =>
            float.TryParse(s,NumberStyles.Float,CultureInfo.InvariantCulture,out v) && float.IsFinite(v) && v>=min && v<=max;
    }

    internal readonly struct RayVisualPoint
    {
        internal readonly float X,Y;
        internal RayVisualPoint(float x,float y) { X=x;Y=y; }
    }

    internal sealed class RayVisualEvent
    {
        internal readonly char Operation;
        internal readonly int Id, ConfigId, BirthTick, Delay, Kind, HitIndex, Key, Serial, PulseIndex, PulseCount, Flags;
        internal readonly float StartX, StartY, EndX, EndY, Intensity, TargetLength;
        internal readonly uint Seed;
        internal readonly bool IsHit;
        internal readonly RayVisualPoint[] HitPoints, DamageHitPoints;
        internal RayVisualEvent(int id,int serial) { Operation='x';Id=id;Serial=serial; }
        internal RayVisualEvent(char operation,int id,int cfg,int birth,int delay,float sx,float sy,float ex,float ey,
            int kind,int hitIndex,float intensity,bool isHit,uint seed,int key,int serial,float targetLength,
            int pulseIndex,int pulseCount,int flags,RayVisualPoint[] points,RayVisualPoint[] damagePoints)
        {
            Operation=operation;Id=id;ConfigId=cfg;BirthTick=birth;Delay=delay;StartX=sx;StartY=sy;EndX=ex;EndY=ey;
            Kind=kind;HitIndex=hitIndex;Intensity=intensity;IsHit=isHit;Seed=seed;Key=key;Serial=serial;
            TargetLength=targetLength;PulseIndex=pulseIndex;PulseCount=pulseCount;Flags=flags;HitPoints=points;DamageHitPoints=damagePoints;
        }
    }
}
