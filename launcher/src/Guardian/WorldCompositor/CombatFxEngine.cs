using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // All motion here is decorative. The AS2 game clock gates progression;
    // no wall-clock extrapolation, collision, damage or gameplay RNG is used.
    internal sealed class CombatFxEngine
    {
        internal const int CasingLimit=256, MuzzleLimit=64, ImpactLimit=128, LightLimit=16, StampBatchLimit=8, LightStride=16;
        private const int TotalLimit=CasingLimit+MuzzleLimit+ImpactLimit;
        private readonly CombatFxCatalog _catalog;
        private readonly Particle[] _particles=new Particle[TotalLimit];
        private readonly FlashLight[] _lights=new FlashLight[LightLimit];
        private readonly CombatFxEquipmentLight[] _resident=new CombatFxEquipmentLight[LightLimit];
        private readonly CombatFxDrawFrame _draw=new CombatFxDrawFrame(TotalLimit);
        private int _generation=-1,_epoch=-1,_sequence=-1,_tick,_nextId,_eventSequence;
        private long _nextLightId;
        private readonly List<CombatFxSettlement> _settled=new List<CombatFxSettlement>(StampBatchLimit);
        private int _groundHits;
        internal int Dropped { get; private set; }
        internal int ImpactDropped { get; private set; }
        internal int LightDropped { get; private set; }
        internal int Epoch => _epoch;
        internal CombatFxEngine(CombatFxCatalog catalog) { _catalog=catalog ?? throw new ArgumentNullException(nameof(catalog)); }

        private struct Particle
        {
            // 0 free; 1 moving/playing; 2 unsent rest; 3 awaiting AS2; 4 acknowledged/fading.
            internal int Phase,Id,Style,Variant,Age,RestAge,FadeTicks,HoldTicks;
            internal float X,Y,VX,VY,Rotation,Spin,ScaleX,ScaleY,Ground;
            internal bool Rolling,HitGround;
        }
        private struct FlashLight
        {
            internal long Id;
            internal int Age,Ticks;
            internal float X,Y,Radius,Energy,R,G,B;
            // Keep the first two game frames visible across capture/presentation cadence,
            // then fade linearly. A two-tick quadratic pulse was barely perceptible in game.
            internal readonly float Strength => Ticks==0?0:Energy*(Age<2?1:(Ticks-Age)/(float)Math.Max(1,Ticks-1));
        }

        internal void Reset()
        {
            Array.Clear(_particles);Array.Clear(_lights);Array.Clear(_resident);_generation=-1;_epoch=-1;_sequence=-1;
            _tick=0;_nextId=0;_nextLightId=0;_eventSequence=0;_settled.Clear();_groundHits=0;
            _draw.Count=0;_draw.CasingCount=0;_draw.ImpactCount=0;_draw.LightCount=0;
            _draw.ResidentLightCount=0;_draw.CandidateLightCount=0;
        }

        internal bool Apply(CombatFxFrame frame,int generation)
        {
            if (generation<_generation) return false;
            bool fresh=generation>_generation || frame.Epoch>_epoch;
            if (!fresh && (frame.Epoch<_epoch || frame.Sequence<=_sequence || frame.GameTick<_tick)) return false;
            if (fresh)
            {
                Array.Clear(_particles);Array.Clear(_lights);Array.Clear(_resident);_epoch=frame.Epoch;_sequence=-1;_tick=frame.GameTick;
                _nextId=0;_nextLightId=0;_eventSequence=0;_generation=generation;
            }
            _settled.Clear();_groundHits=0;
            int elapsed=frame.Paused?0:frame.GameTick-_tick;
            _tick=frame.GameTick;_sequence=frame.Sequence;
            // A disconnected/stalled visual stream must not replay a long burst on recovery.
            if (elapsed>8) { Array.Clear(_particles);Array.Clear(_lights);Array.Clear(_resident);elapsed=0; }
            foreach (CombatFxAck ack in frame.Acks)
                for (int i=0;i<CasingLimit;i++)
                    if (_particles[i].Phase==3 && _particles[i].Id==ack.Id)
                    {
                        _particles[i].Phase=4;_particles[i].HoldTicks=ack.Drawn?2:0;
                        _particles[i].FadeTicks=3;break;
                    }
            ApplyEquipmentLights(frame.EquipmentLights);
            for (int step=0;step<elapsed;step++) Advance();
            if (!frame.Paused)
                foreach (CombatFxSpawn spawn in frame.Spawns) Spawn(spawn);
            if (!frame.Paused)
                for (int i=0;i<CasingLimit && _settled.Count<StampBatchLimit;i++)
                    if (_particles[i].Phase==2)
                    {
                        ref Particle p=ref _particles[i];p.Phase=3;
                        _settled.Add(new CombatFxSettlement(p.Id,p.Style,p.X,p.Y,p.Rotation,p.ScaleX*100,p.ScaleY*100));
                    }
            return true;
        }

        private void Spawn(CombatFxSpawn spawn)
        {
            CombatFxStyle style=_catalog.Styles[spawn.Style];
            if (style.SkipOriginYZero && spawn.Y==0) return;
            // A muzzle flash can have an authored empty visual variant. The shot still
            // emits its light; neither sprite capacity nor chosen frame controls lighting.
            if(style.IsMuzzle) SpawnLight(spawn,style.Light);
            uint random=spawn.Seed;
            int start=style.IsCasing?0:(style.IsImpact?CasingLimit+MuzzleLimit:CasingLimit);
            int end=style.IsCasing?CasingLimit:(style.IsImpact?TotalLimit:CasingLimit+MuzzleLimit);
            int cursor=start;
            for (int n=0;n<spawn.Count;n++)
            {
                while (cursor<end && _particles[cursor].Phase!=0) cursor++;
                if (cursor==end) { Dropped+=spawn.Count-n;if(style.IsImpact)ImpactDropped+=spawn.Count-n;break; }
                ref Particle p=ref _particles[cursor++];
                _nextId=_nextId==int.MaxValue?1:_nextId+1;
                p=default;p.Phase=1;p.Id=_nextId;p.Style=spawn.Style;
                p.X=spawn.X;p.Y=spawn.Y;p.ScaleX=spawn.ScaleX;p.ScaleY=spawn.ScaleY;
                if (style.IsCasing)
                {
                    float ox=spawn.Count>1?(Random(ref random)*2-1)*8:0;
                    float oy=spawn.Count>1?(Random(ref random)*2-1)*4:0;
                    p.X+=ox;p.Y+=oy;p.Ground=spawn.Argument+oy;
                    p.VX=(spawn.ScaleX<0?1:-1)*(2.5f+Random(ref random)*3.5f);
                    p.VY=-12-Random(ref random)*10;p.Spin=(Random(ref random)*2-1)*30;
                }
                else
                {
                    p.Rotation=spawn.Argument;
                    p.Variant=Math.Min(style.Variants.Length-1,(int)(Random(ref random)*style.Variants.Length));
                }
            }
        }

        private void SpawnLight(CombatFxSpawn spawn,CombatFxLightProfile profile)
        {
            if(profile==null || profile.Energy<=0 || _catalog.MaximumLightResponse<=0)return;
            int slot=-1;float weakest=float.MaxValue;
            for(int i=0;i<_lights.Length;i++)
            {
                if(_lights[i].Ticks==0) {slot=i;break;}
                float strength=_lights[i].Strength;
                if(strength<weakest) {weakest=strength;slot=i;}
            }
            if(_lights[slot].Ticks!=0)
            {
                LightDropped++;
                if(weakest>=profile.Energy)return;
            }
            _nextLightId=_nextLightId==long.MaxValue?1:_nextLightId+1;
            _lights[slot]=new FlashLight {Id=-_nextLightId,X=spawn.X,Y=spawn.Y,Ticks=profile.Ticks,
                Radius=Math.Clamp(profile.Radius*Math.Abs(spawn.ScaleX),16,320),Energy=profile.Energy,
                R=profile.R,G=profile.G,B=profile.B};
        }

        // Equipment lights are a full per-frame snapshot owned by AS2: absent ids are
        // evicted, surviving ids keep their slot, new ids fill free slots by ascending id.
        private void ApplyEquipmentLights(CombatFxEquipmentLight[] lights)
        {
            for (int i=0;i<LightLimit;i++)
            {
                if (_resident[i].Id==0) continue;
                bool keep=false;
                for (int j=0;j<lights.Length;j++) if (lights[j].Id==_resident[i].Id) { keep=true;break; }
                if (!keep) _resident[i]=default;
            }
            for (int j=0;j<lights.Length;j++)
                for (int i=0;i<LightLimit;i++)
                    if (_resident[i].Id==lights[j].Id) { _resident[i]=lights[j];break; }
            for (int i=0;i<LightLimit;i++)
            {
                if (_resident[i].Id!=0) continue;
                int best=-1;
                for (int j=0;j<lights.Length;j++)
                    if (ResidentIndex(lights[j].Id)<0 && (best<0 || lights[j].Id<lights[best].Id)) best=j;
                if (best<0) break;
                _resident[i]=lights[best];
            }
            for (int j=0;j<lights.Length;j++) if (ResidentIndex(lights[j].Id)<0) LightDropped++;
        }
        private int ResidentIndex(int id)
        { for (int i=0;i<LightLimit;i++) if (_resident[i].Id==id) return i; return -1; }

        private void Advance()
        {
            for(int n=0;n<_lights.Length;n++)
                if(_lights[n].Ticks>0 && ++_lights[n].Age>=_lights[n].Ticks)_lights[n]=default;
            for (int i=0;i<TotalLimit;i++)
            {
                ref Particle p=ref _particles[i];
                if (p.Phase==0) continue;
                if (i>=CasingLimit)
                { if (++p.Age>=_catalog.Styles[p.Style].Variants[p.Variant].Length) p.Phase=0;continue; }
                if (p.Phase==4)
                {
                    if (p.HoldTicks>0) p.HoldTicks--;
                    else if (--p.FadeTicks<=0) p.Phase=0;
                    continue;
                }
                if (p.Phase>=2)
                { if (++p.RestAge>45) { p.Phase=4;p.FadeTicks=3; } continue; }
                if (++p.Age>=120) { p.Phase=4;p.FadeTicks=3;continue; }
                if (p.Rolling)
                {
                    p.X+=p.VX;p.VX*=.82f;p.Spin*=.82f;p.Rotation+=p.Spin;
                    if (Math.Abs(p.VX)<1.5f) p.Phase=2;
                    continue;
                }
                p.VY+=2.8f;p.X+=p.VX;p.Y+=p.VY;p.Rotation+=Math.Clamp(p.Spin,-35,35);
                if (p.Y<p.Ground) continue;
                p.Y=p.Ground;
                if (!p.HitGround) { p.HitGround=true;_groundHits=Math.Min(3,_groundHits+1); }
                if (p.VY<5)
                {
                    p.VY=0;
                    if (Math.Abs(p.VX)<1.5f) p.Phase=2;
                    else p.Rolling=true;
                }
                else { p.VY*= -.6f;p.VX*=.72f;p.Spin*=.7f; }
            }
        }

        // Returned storage is borrowed until the next Apply/BuildDraw call.
        // NativeCompositorSession copies synchronously; never queue this object to the UI.
        internal CombatFxDrawFrame BuildDraw()
        {
            int count=0,casings=0,impacts=0;
            for (int order=0;order<TotalLimit;order++)
            {
                // Draw order: casings, impacts, muzzles. Native inserts bullets after casings.
                int i=order<CasingLimit?order:(order<CasingLimit+ImpactLimit?order+MuzzleLimit:order-ImpactLimit);
                ref Particle p=ref _particles[i];if(p.Phase==0)continue;
                CombatFxStyle style=_catalog.Styles[p.Style];
                int frame=style.IsCasing?0:style.Variants[p.Variant][Math.Min(p.Age,style.Variants[p.Variant].Length-1)];
                CombatFxImage f=style.Frames[frame];int at=count*16;
                float alpha=p.Phase==4 && p.HoldTicks==0 ? p.FadeTicks/3f : 1;
                _draw.Data[at]=p.X;_draw.Data[at+1]=p.Y;_draw.Data[at+2]=p.Rotation;_draw.Data[at+3]=alpha;
                _draw.Data[at+4]=p.ScaleX;_draw.Data[at+5]=p.ScaleY;
                _draw.Data[at+6]=style.IsCasing && p.Phase>=2?.7f:1;_draw.Data[at+7]=style.WorldLit?1:0;
                _draw.Data[at+8]=f.OffsetX;_draw.Data[at+9]=f.OffsetY;_draw.Data[at+10]=f.Width;_draw.Data[at+11]=f.Height;
                _draw.Data[at+12]=f.U0;_draw.Data[at+13]=f.V0;_draw.Data[at+14]=f.U1;_draw.Data[at+15]=f.V1;
                count++;if(style.IsCasing)casings++;if(style.IsImpact)impacts++;
            }
            int lights=0,candidates=0;
            for(int n=0;n<_resident.Length;n++)
            {
                ref CombatFxEquipmentLight p=ref _resident[n];if(p.Id==0)continue;
                _draw.CandidateLights[candidates++]=new WorldLightCandidate(p.Id,p.Kind==0?70:100,
                    p.X,p.Y,p.Length,p.Energy,p.R,p.G,p.B,p.Kind,p.DirectionX,p.DirectionY,p.HalfWidth,
                    p.NearX,p.NearY,p.NearRadius,p.NearEnergy);
                _draw.LightIds[lights]=p.Id;
                int at=lights++*LightStride;
                _draw.Lights[at]=p.X;_draw.Lights[at+1]=p.Y;_draw.Lights[at+2]=p.Length;_draw.Lights[at+3]=p.Energy;
                _draw.Lights[at+4]=p.R;_draw.Lights[at+5]=p.G;_draw.Lights[at+6]=p.B;_draw.Lights[at+7]=p.Kind;
                _draw.Lights[at+8]=p.DirectionX;_draw.Lights[at+9]=p.DirectionY;_draw.Lights[at+10]=p.HalfWidth;
                _draw.Lights[at+11]=0;
                _draw.Lights[at+12]=p.NearX;_draw.Lights[at+13]=p.NearY;
                _draw.Lights[at+14]=p.NearRadius;_draw.Lights[at+15]=p.NearEnergy;
            }
            _draw.ResidentLightCount=lights;
            for(int n=0;n<_lights.Length;n++)
            {
                ref FlashLight p=ref _lights[n];if(p.Ticks==0)continue;
                _draw.CandidateLights[candidates++]=new WorldLightCandidate(p.Id,75,
                    p.X,p.Y,p.Radius,p.Strength,p.R,p.G,p.B,0);
                if(lights>=LightLimit)continue;
                _draw.LightIds[lights]=p.Id;
                int at=lights++*LightStride;
                _draw.Lights[at]=p.X;_draw.Lights[at+1]=p.Y;_draw.Lights[at+2]=p.Radius;_draw.Lights[at+3]=p.Strength;
                _draw.Lights[at+4]=p.R;_draw.Lights[at+5]=p.G;_draw.Lights[at+6]=p.B;
                _draw.Lights[at+7]=0;_draw.Lights[at+8]=0;_draw.Lights[at+9]=0;_draw.Lights[at+10]=0;_draw.Lights[at+11]=0;
                _draw.Lights[at+12]=0;_draw.Lights[at+13]=0;_draw.Lights[at+14]=0;_draw.Lights[at+15]=0;
            }
            _draw.Count=count;_draw.CasingCount=casings;_draw.ImpactCount=impacts;
            _draw.LightCount=lights;_draw.CandidateLightCount=candidates;
            _draw.MaximumLightResponse=_catalog.MaximumLightResponse;return _draw;
        }

        internal CombatFxEvents TakeEvents()
        {
            if (_settled.Count==0 && _groundHits==0) return null;
            var events=new CombatFxEvents(_epoch,++_eventSequence,_groundHits,_settled.ToArray());
            _settled.Clear();_groundHits=0;return events;
        }
        private static float Random(ref uint s)
        { s^=s<<13;s^=s>>17;s^=s<<5;return (s>>8)*(1f/16777216f); }
    }

    internal sealed class CombatFxDrawFrame
    {
        internal readonly float[] Data;
        internal readonly float[] Lights=new float[CombatFxEngine.LightLimit*CombatFxEngine.LightStride];
        internal readonly long[] LightIds=new long[CombatFxEngine.LightLimit];
        // The original Lights remain the exact legacy selection. The composer
        // can additionally consider muzzle lights hidden by saturated residents.
        internal readonly WorldLightCandidate[] CandidateLights=new WorldLightCandidate[CombatFxEngine.LightLimit*2];
        internal int Count,CasingCount,ImpactCount,LightCount,ResidentLightCount,CandidateLightCount;
        internal float MaximumLightResponse;
        internal CombatFxDrawFrame(int capacity) { Data=new float[capacity*16]; }
    }
    internal sealed class CombatFxEvents
    {
        internal readonly int Epoch,Sequence,GroundHits;
        internal readonly CombatFxSettlement[] Settled;
        internal CombatFxEvents(int epoch,int sequence,int hits,CombatFxSettlement[] settled)
        { Epoch=epoch;Sequence=sequence;GroundHits=hits;Settled=settled; }
    }
    internal readonly struct CombatFxSettlement
    {
        internal readonly int Id,Style;
        internal readonly float X,Y,Rotation,ScaleX,ScaleY;
        internal CombatFxSettlement(int id,int style,float x,float y,float rotation,float sx,float sy)
        { Id=id;Style=style;X=x;Y=y;Rotation=rotation;ScaleX=sx;ScaleY=sy; }
    }
}
