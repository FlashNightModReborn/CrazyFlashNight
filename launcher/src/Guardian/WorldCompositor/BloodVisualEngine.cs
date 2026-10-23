using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // A single decorative birth. No MovieClip, gameplay RNG or per-frame AS2 ledger.
    internal readonly struct BloodVisualEvent
    {
        internal readonly int Id, Style;
        internal readonly double X, Y, Z, ScaleX, Gravity;
        internal readonly uint Seed;
        private BloodVisualEvent(int id,int style,double x,double y,double z,double scale,uint seed,double gravity)
        { Id=id;Style=style;X=x;Y=y;Z=z;ScaleX=scale*.01;Seed=seed;Gravity=gravity; }
        internal static BloodVisualEvent Birth(int id,int style,double x,double y,double z,
            double sxPercent,uint seed,double gravity=1) => new BloodVisualEvent(id,style,x,y,z,sxPercent,seed,gravity);
    }

    internal readonly struct BloodVisualLanding
    {
        internal readonly int Id, Variant;
        internal readonly double X, Y;
        internal BloodVisualLanding(int id,int variant,double x,double y)
        { Id=id;Variant=variant;X=x;Y=y; }
    }

    // Visual approximation of the original flying blood. Game ticks gate all motion;
    // overload may discard decoration, while damage and acid blood remain in AS2.
    internal sealed class BloodVisualEngine
    {
        internal const int Limit=64, LandingBatchLimit=8;
        private readonly CombatFxCatalog _catalog;
        private readonly Particle[] _particles=new Particle[Limit];
        private readonly Queue<BloodVisualLanding> _landings=new Queue<BloodVisualLanding>(Limit);
        private int _highestId, _nextStampId;
        internal int Dropped { get; private set; }
        internal int Count { get; private set; }
        internal int PendingLandings => _landings.Count;
        internal bool HasState => Count!=0 || _landings.Count!=0;
        private struct Particle
        {
            internal int Id,Style,Variant,Age;
            internal uint Random;
            internal double X,Y,Z,Vz,Spin,Dx,Dy,ScaleX,Gravity,Rotation;
        }
        internal BloodVisualEngine(CombatFxCatalog catalog) { _catalog=catalog; }
        internal void Reset()
        { Array.Clear(_particles);_landings.Clear();_highestId=0;_nextStampId=0;Count=0;Dropped=0; }

        internal void Apply(IReadOnlyList<BloodVisualEvent> events,int elapsed)
        {
            // Do not replay a large visual burst after a disconnected/stalled stream.
            if(elapsed>8) { Array.Clear(_particles);_landings.Clear();Count=0;elapsed=0; }
            for(int tick=0;tick<elapsed;tick++)
                for(int i=0;i<Limit;i++)
                {
                    ref Particle p=ref _particles[i];
                    if(p.Id==0)continue;
                    // The original checks ground before movement and moves its ground
                    // plane with planar Y. Keep that feel without twip quantization.
                    if(p.Y>=p.Z)
                    {
                        if(_landings.Count<Limit && _nextStampId<int.MaxValue)
                            _landings.Enqueue(new BloodVisualLanding(++_nextStampId,NextInt(ref p.Random,8),p.X,p.Y));
                        else Dropped++;
                        p=default;Count--;continue;
                    }
                    p.Rotation=(p.Rotation+p.Spin)%360;
                    p.X+=p.Dx;p.Y+=p.Dy;p.Z+=p.Dy;p.Vz+=p.Gravity;p.Y+=p.Vz;
                    p.Age++;
                    if(p.Age>=60 || (p.Age%15==0 && NextInt(ref p.Random,3)==0))
                    { p=default;Count--; }
                }
            foreach(BloodVisualEvent e in events)
            {
                if(e.Id<=_highestId)continue;
                _highestId=e.Id;
                int slot=-1;
                for(int i=0;i<Limit;i++)if(_particles[i].Id==0) { slot=i;break; }
                if(slot<0) { Dropped++;continue; }
                uint random=e.Seed==0?1:e.Seed;
                double vz=-NextInt(ref random,5),spin=30-NextInt(ref random,61);
                double angle=NextInt(ref random,360)*Math.PI/180,speed=NextInt(ref random,8);
                double childScale=(75+NextInt(ref random,75))*.01;
                int variant=NextInt(ref random,_catalog.Styles[e.Style].Variants.Length);
                _particles[slot]=new Particle {Id=e.Id,Style=e.Style,Variant=variant,
                    X=e.X,Y=e.Y,Z=e.Z,Vz=vz,Spin=spin,Dx=speed*Math.Cos(angle),
                    Dy=speed*Math.Sin(angle)*.5,ScaleX=e.ScaleX*childScale,Gravity=e.Gravity,Random=random};
                Count++;
            }
        }

        internal BloodVisualLanding[] TakeLandings()
        {
            int count=Math.Min(LandingBatchLimit,_landings.Count);
            if(count==0)return Array.Empty<BloodVisualLanding>();
            var batch=new BloodVisualLanding[count];
            for(int i=0;i<count;i++)batch[i]=_landings.Dequeue();
            return batch;
        }

        // Append within the 64 slots reserved after the ordinary 448 FX slots.
        internal int AppendDraw(CombatFxDrawFrame draw,int count)
        {
            foreach(Particle p in _particles)
            {
                if(p.Id==0)continue;
                CombatFxStyle style=_catalog.Styles[p.Style];
                CombatFxImage f=style.Frames[style.Variants[p.Variant][0]];
                int at=count*16;
                draw.Data[at]=(float)p.X;draw.Data[at+1]=(float)p.Y;
                draw.Data[at+2]=(float)p.Rotation;draw.Data[at+3]=1;
                draw.Data[at+4]=(float)p.ScaleX;draw.Data[at+5]=1;
                draw.Data[at+6]=1;draw.Data[at+7]=style.WorldLit?1:0;
                draw.Data[at+8]=f.OffsetX;draw.Data[at+9]=f.OffsetY;
                draw.Data[at+10]=f.Width;draw.Data[at+11]=f.Height;
                draw.Data[at+12]=f.U0;draw.Data[at+13]=f.V0;
                draw.Data[at+14]=f.U1;draw.Data[at+15]=f.V1;
                count++;
            }
            return count;
        }
        private static int NextInt(ref uint s,int max)
        { s^=s<<13;s^=s>>17;s^=s<<5;return (int)((s>>8)*(1.0/16777216)*max); }
    }
}
