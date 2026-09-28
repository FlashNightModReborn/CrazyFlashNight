using System;
using System.Collections.Generic;
using System.Globalization;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // F section 6: epoch|sequence|gameTick|paused; s,... / m,... / i,... / a,... / l,...
    // s/m/i/a are one-shot visual events, not a latest-wins position snapshot.
    // l records instead carry the complete resident equipment light snapshot.
    internal sealed class CombatFxFrame
    {
        internal readonly int Epoch, Sequence, GameTick;
        internal readonly bool Paused;
        internal readonly CombatFxSpawn[] Spawns;
        internal readonly CombatFxAck[] Acks;
        internal readonly CombatFxEquipmentLight[] EquipmentLights;
        private CombatFxFrame(int epoch,int sequence,int tick,bool paused,CombatFxSpawn[] spawns,CombatFxAck[] acks,CombatFxEquipmentLight[] lights)
        { Epoch=epoch;Sequence=sequence;GameTick=tick;Paused=paused;Spawns=spawns;Acks=acks;EquipmentLights=lights; }

        internal static bool TryParse(string payload,CombatFxCatalog catalog,out CombatFxFrame frame)
        {
            frame=null;
            if (catalog==null || string.IsNullOrEmpty(payload) || payload.Length>32768) return false;
            string[] records=payload.Split(';');
            if (records.Length>193) return false;
            string[] header=records[0].Split('|');
            if (header.Length!=4 || !Int(header[0],0,1000000000,out int epoch)
                || !Int(header[1],0,1000000000,out int sequence)
                || !Int(header[2],0,1000000000,out int tick) || !Int(header[3],0,1,out int paused)) return false;
            var spawns=new List<CombatFxSpawn>();
            var acks=new List<CombatFxAck>();
            var lights=new List<CombatFxEquipmentLight>();
            var lightIds=new HashSet<int>();
            int shooting=0,impacts=0;
            for (int i=1;i<records.Length;i++)
            {
                string[] f=records[i].Split(',');
                if (f[0]=="a")
                {
                    if (f.Length!=3 || acks.Count>=64 || !Int(f[1],1,int.MaxValue,out int id)
                        || !Int(f[2],0,1,out int drawn)) return false;
                    acks.Add(new CombatFxAck(id,drawn==1));continue;
                }
                if (f[0]=="l")
                {
                    // Legacy 13-field records stay valid; ABI9 adds a 4-field near-fill tail.
                    if ((f.Length!=13 && f.Length!=17) || lightIds.Count>=64
                        || !Int(f[1],1,1000000000,out int lightId) || !lightIds.Add(lightId)
                        || !Int(f[2],0,2,out int kind)
                        || !Float(f[3],-1000000,1000000,out float lx) || !Float(f[4],-1000000,1000000,out float ly)
                        || !Float(f[5],-1,1,out float dx) || !Float(f[6],-1,1,out float dy)
                        || !Float(f[7],1,1024,out float length) || !Float(f[8],0,512,out float halfWidth)
                        || !Float(f[9],0,2,out float energy)
                        || !Float(f[10],0,1,out float lr) || !Float(f[11],0,1,out float lg) || !Float(f[12],0,1,out float lb)) return false;
                    // Kind 0 is a resident radial source, not a muzzle-spawn event.
                    // Direction and half-width are reserved zero; the existing native
                    // ABI9 radial shader consumes length as radius without an ABI change.
                    if (kind==0 ? (length>320 || dx!=0 || dy!=0 || halfWidth!=0)
                        : (!Unit(dx,dy) || halfWidth<0.5f)) return false;
                    float nearX=0,nearY=0,nearRadius=0,nearEnergy=0;
                    if (f.Length==17
                        && (!Float(f[13],-1000000,1000000,out nearX) || !Float(f[14],-1000000,1000000,out nearY)
                            || !Float(f[15],0,320,out nearRadius) || !Float(f[16],0,2,out nearEnergy)
                            || (nearRadius>0)!=(nearEnergy>0)
                            || (kind!=1 && (nearX!=0 || nearY!=0 || nearRadius!=0 || nearEnergy!=0))
                            || (nearRadius==0 && (nearX!=0 || nearY!=0)))) return false;
                    lights.Add(new CombatFxEquipmentLight(lightId,kind,lx,ly,dx,dy,length,halfWidth,energy,lr,lg,lb,
                        nearX,nearY,nearRadius,nearEnergy));continue;
                }
                bool casing=f[0]=="s";
                bool impact=f[0]=="i";
                if ((!casing && !impact && f[0]!="m") || f.Length!=(casing?10:9)
                    || (impact?++impacts>32:++shooting>32)
                    || !Int(f[1],0,catalog.Styles.Length-1,out int style)
                    || catalog.Styles[style].IsCasing!=casing
                    || catalog.Styles[style].IsImpact!=impact
                    || !Float(f[2],-1000000,1000000,out float x) || !Float(f[3],-1000000,1000000,out float y)
                    || !Float(f[4],-1000,1000,out float sx) || !Float(f[5],0.01f,1000,out float sy)
                    || !Float(f[6],-1000000,1000000,out float argument)) return false;
                int count=1,seed;
                if (casing)
                {
                    if (!Int(f[7],1,64,out count) || !Int(f[8],1,int.MaxValue,out seed) || f[9]!="0") return false;
                }
                else if (!Int(f[7],1,int.MaxValue,out seed) || f[8]!="0") return false;
                spawns.Add(new CombatFxSpawn(style,x,y,sx*.01f,sy*.01f,argument,count,(uint)seed));
            }
            frame=new CombatFxFrame(epoch,sequence,tick,paused!=0,spawns.ToArray(),acks.ToArray(),lights.ToArray());
            return true;
        }
        private static bool Int(string s,int min,int max,out int v) =>
            int.TryParse(s,NumberStyles.None,CultureInfo.InvariantCulture,out v) && v>=min && v<=max;
        private static bool Float(string s,float min,float max,out float v) =>
            float.TryParse(s,NumberStyles.Float,CultureInfo.InvariantCulture,out v) && float.IsFinite(v) && v>=min && v<=max;
        private static bool Unit(float x,float y) { float m=x*x+y*y; return m>=0.99f && m<=1.01f; }
    }

    internal readonly struct CombatFxSpawn
    {
        internal readonly int Style,Count;
        internal readonly float X,Y,ScaleX,ScaleY,Argument;
        internal readonly uint Seed;
        internal CombatFxSpawn(int style,float x,float y,float sx,float sy,float argument,int count,uint seed)
        { Style=style;X=x;Y=y;ScaleX=sx;ScaleY=sy;Argument=argument;Count=count;Seed=seed; }
    }
    internal readonly struct CombatFxAck
    {
        internal readonly int Id; internal readonly bool Drawn;
        internal CombatFxAck(int id,bool drawn) { Id=id;Drawn=drawn; }
    }
    internal readonly struct CombatFxEquipmentLight
    {
        internal readonly int Id,Kind;
        internal readonly float X,Y,DirectionX,DirectionY,Length,HalfWidth,Energy,R,G,B;
        internal readonly float NearX,NearY,NearRadius,NearEnergy;
        internal CombatFxEquipmentLight(int id,int kind,float x,float y,float dx,float dy,
            float length,float halfWidth,float energy,float r,float g,float b,
            float nearX=0,float nearY=0,float nearRadius=0,float nearEnergy=0)
        { Id=id;Kind=kind;X=x;Y=y;DirectionX=dx;DirectionY=dy;Length=length;HalfWidth=halfWidth;
            Energy=energy;R=r;G=g;B=b;NearX=nearX;NearY=nearY;NearRadius=nearRadius;NearEnergy=nearEnergy; }
    }
}
