using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Presentation-only state. Tick order is supplied by AS2; no wall clock, collision,
    // target selection, damage, or game RNG is evaluated in this engine.
    internal sealed partial class RayVisualEngine
    {
        private sealed class Arc
        {
            internal RayVisualEvent Event;
            internal RayVisualConfig Config;
            internal float StartX,StartY,EndX,EndY;
            internal int Age,SerialFloor,EmissionBirth;
            internal float PhaseAge;
            internal uint Seed;
            internal bool Stopped;
            internal float OffsetX,OffsetY,HitOffsetX,HitOffsetY;
            internal bool AwaitingOffset;
        }
        private readonly Dictionary<int,RayVisualConfig> _configs=new();
        private readonly List<Arc> _arcs=new(RayVisualCatalog.ArcLimit);
        private readonly Dictionary<int,Arc> _arcsById=new(RayVisualCatalog.ArcLimit);
        // Retain a latest-owner tombstone while any older tail of the channel
        // survives, so stale events cannot resurrect a retired emission.
        private readonly Dictionary<int,Arc> _channelHeads=new(RayVisualCatalog.ArcLimit);
        private readonly HashSet<int> _liveChannels=new();
        private readonly List<int> _retiredChannels=new();
        private readonly Dictionary<int,Binding> _pendingBindings=new(RayVisualCatalog.ArcLimit);
        private readonly Dictionary<int,int> _pendingChannels=new(RayVisualCatalog.ArcLimit);
        private readonly HashSet<int> _pendingActiveChannels=new(),_pendingRetired=new();
        private readonly Dictionary<int,int> _retiredSerials=new(RayVisualCatalog.ArcLimit);
        private readonly int[] _retiredKeys=new int[RayVisualCatalog.ArcLimit],_retiredValues=new int[RayVisualCatalog.ArcLimit];
        private int _retiredCursor;
        private readonly List<RayVisualEvent> _acceptedEvents=new(RayVisualCatalog.MaxEvents);
        private readonly RayVisualDrawFrame _draw=new();
        private int _generation=-1,_epoch=-1,_sequence=-1,_tick;
        internal int ActiveCount => _arcs.Count;
        internal int Epoch => _epoch;
        internal int Rejected { get; private set; }
        internal int DecorationDropped { get; private set; }

        private struct Binding
        {
            internal int Config,Kind,Key,Serial;
            internal bool Stopped;
            internal Binding(RayVisualEvent item,int serial,bool stopped)
            { Config=item.ConfigId;Kind=item.Kind;Key=item.Key;Serial=serial;Stopped=stopped; }
            internal bool Matches(RayVisualEvent item) => Config==item.ConfigId&&Kind==item.Kind&&Key==item.Key;
        }

        internal void Reset()
        {
            _configs.Clear();ClearArcs();_draw.Count=0;
            _generation=-1;_epoch=-1;_sequence=-1;_tick=0;
        }

        internal bool Apply(RayVisualFrame frame,int generation)
        {
            if (frame==null || generation<_generation) return false;
            bool fresh=generation>_generation || frame.Epoch>_epoch;
            if (!fresh && (frame.Epoch<_epoch || frame.Sequence<=_sequence || frame.GameTick<_tick)) return false;
            // Validate references and capacity before mutating an accepted stream. A rejected
            // frame must be eligible for ownership revocation, not leave a partial visual frame.
            var available=fresh?new Dictionary<int,RayVisualConfig>():new Dictionary<int,RayVisualConfig>(_configs);
            foreach (RayVisualConfig cfg in frame.Configs)
            {
                if (available.TryGetValue(cfg.Id,out var old) && !SameConfig(old,cfg)) { Rejected++;return false; }
                available[cfg.Id]=cfg;
            }
            if (available.Count>RayVisualCatalog.ConfigLimit) { Rejected++;return false; }
            int elapsed=fresh || frame.Paused?0:frame.GameTick-_tick;
            bool staleGap=elapsed>8;
            _pendingBindings.Clear();_pendingChannels.Clear();_pendingActiveChannels.Clear();_pendingRetired.Clear();_acceptedEvents.Clear();
            if (!fresh && !staleGap)
            {
                foreach (Arc arc in _arcs)
                    if (arc.Age+elapsed<=arc.Config[3]+arc.Config[4])
                    {
                        _pendingBindings.Add(arc.Event.Id,new Binding(arc.Event,arc.SerialFloor,arc.Stopped));
                        if(arc.Event.Key>0)_pendingActiveChannels.Add(arc.Event.Key);
                    }
                foreach(var retired in _retiredSerials) {_pendingChannels[retired.Key]=retired.Value;_pendingRetired.Add(retired.Key);}
                foreach(var head in _channelHeads)
                {
                    _pendingChannels[head.Key]=head.Value.SerialFloor;
                    if(head.Value.Config.Style<=9&&!_pendingActiveChannels.Contains(head.Key))_pendingRetired.Add(head.Key);
                    else _pendingRetired.Remove(head.Key);
                }
            }
            foreach (RayVisualEvent item in frame.Events)
            {
                if (item.Operation=='x')
                {
                    if (_pendingBindings.TryGetValue(item.Id,out var stopped)&&item.Serial>=stopped.Serial)
                    {
                        stopped.Serial=item.Serial;stopped.Stopped=true;_pendingBindings[item.Id]=stopped;
                        if(stopped.Key>0&&(!_pendingChannels.TryGetValue(stopped.Key,out int prior)||item.Serial>prior))
                            _pendingChannels[stopped.Key]=item.Serial;
                        _acceptedEvents.Add(item);
                    }
                    continue;
                }
                if (!available.TryGetValue(item.ConfigId,out var cfg)
                    || !ValidChannel(cfg,item)) { Rejected++;return false; }
                bool existing=_pendingBindings.TryGetValue(item.Id,out var binding);
                if(existing&&!binding.Matches(item)) { Rejected++;return false; }
                if(existing&&(item.Serial<binding.Serial||(binding.Stopped&&item.Serial<=binding.Serial))) continue;
                if(item.Key>0&&_pendingChannels.TryGetValue(item.Key,out int serial)
                    &&(item.Serial<serial||(_pendingRetired.Contains(item.Key)&&item.Serial==serial))) continue;
                if(existing&&item.Operation=='s') continue;
                if(!existing&&InitialAge(item,frame.GameTick,frame.Paused)>cfg[3]+cfg[4]) continue;
                _pendingBindings[item.Id]=new Binding(item,item.Serial,false);
                if(item.Key>0) {_pendingChannels[item.Key]=item.Serial;_pendingRetired.Remove(item.Key);}
                _acceptedEvents.Add(item);
            }
            if (_pendingBindings.Count>RayVisualCatalog.ArcLimit) { Rejected++;return false; }
            if (fresh)
            {
                _configs.Clear();ClearArcs();_generation=generation;_epoch=frame.Epoch;
            }
            if (staleGap) { ClearArcs();elapsed=0; }
            _tick=frame.GameTick;_sequence=frame.Sequence;
            foreach (RayVisualConfig cfg in frame.Configs) _configs[cfg.Id]=cfg;
            int survivors=0;
            for (int i=0;i<_arcs.Count;i++)
            {
                Arc arc=_arcs[i];int previous=arc.Age;arc.Age+=elapsed;
                // Tesla/resonance retain their last drawing during fade. A new
                // channel emission restarts Age, then advances this same phase;
                // min(total phase,hold) would freeze a sustained channel forever.
                arc.PhaseAge+=PhaseClock(arc,arc.Age)-PhaseClock(arc,previous);
                MaterializeOffset(arc,frame.OffsetX,frame.OffsetY);
                if (arc.Age>arc.Config[3]+arc.Config[4]) _arcsById.Remove(arc.Event.Id);
                else _arcs[survivors++]=arc;
            }
            if(survivors<_arcs.Count) _arcs.RemoveRange(survivors,_arcs.Count-survivors);
            foreach (RayVisualEvent item in _acceptedEvents) ApplyEvent(item,frame.Paused,frame.OffsetX,frame.OffsetY);
            _liveChannels.Clear();_retiredChannels.Clear();
            foreach(Arc arc in _arcs) if(arc.Event.Key>0) _liveChannels.Add(arc.Event.Key);
            foreach(int key in _channelHeads.Keys) if(!_liveChannels.Contains(key)) _retiredChannels.Add(key);
            foreach(int key in _retiredChannels)
            {
                Arc head=_channelHeads[key];
                if(head.Config.Style<=9)RetireSerial(key,head.SerialFloor);
                _channelHeads.Remove(key);
            }
            return true;
        }

        private void ClearArcs()
        {
            _arcs.Clear();_arcsById.Clear();_channelHeads.Clear();_liveChannels.Clear();_retiredChannels.Clear();
            _retiredSerials.Clear();Array.Clear(_retiredKeys);Array.Clear(_retiredValues);_retiredCursor=0;ClearLighting();
        }

        private void RetireSerial(int key,int serial)
        {
            int evicted=_retiredKeys[_retiredCursor];
            if(_retiredSerials.TryGetValue(evicted,out int old)&&old==_retiredValues[_retiredCursor])_retiredSerials.Remove(evicted);
            _retiredKeys[_retiredCursor]=key;_retiredValues[_retiredCursor]=serial;_retiredSerials[key]=serial;
            _retiredCursor=(_retiredCursor+1)%RayVisualCatalog.ArcLimit;
        }

        private static bool ValidChannel(RayVisualConfig cfg,RayVisualEvent item)
        {
            if(item.Key==0) return item.Operation!='u';
            if(cfg.Style==11) return item.Kind==4; // compatible legacy flame serial 0
            return cfg.Style<=9&&item.Kind<=3&&item.Serial>0&&(item.Operation!='u'||item.Delay==0);
        }
        private static int InitialAge(RayVisualEvent item,int tick,bool paused) =>
            (paused?0:Math.Clamp(tick-item.BirthTick,0,1200))-(item.Delay>0?item.Delay-1:0);
        private static float PhaseClock(Arc arc,int age) =>
            arc.Config.Style is 0 or 4||(arc.Event.Key>0&&arc.Config.Style<=9)
                ?Math.Max(0,Math.Min(age,arc.Config[3])):Math.Max(0,age);

        private static bool SameConfig(RayVisualConfig a,RayVisualConfig b)
        {
            if (a.Style!=b.Style || a.Palette.Length!=b.Palette.Length || !a.Light.Equals(b.Light)) return false;
            for (int i=0;i<a.Values.Length;i++) if (a.Values[i]!=b.Values[i]) return false;
            for (int i=0;i<a.Palette.Length;i++) if (a.Palette[i]!=b.Palette[i]) return false;
            return true;
        }

        private void ApplyEvent(RayVisualEvent item,bool paused,float ox,float oy)
        {
            _arcsById.TryGetValue(item.Id,out var existing);
            if (item.Operation=='x')
            {
                if (existing!=null && item.Serial>=existing.SerialFloor)
                { existing.SerialFloor=item.Serial;existing.Stopped=true;RememberChannel(existing); }
                return; // Natural fade keeps the last authored hold/fade lifetime intact.
            }
            if (existing!=null && item.Serial<existing.SerialFloor) return;
            if (existing!=null && existing.Stopped && item.Serial<=existing.SerialFloor) return;
            var config=_configs[item.ConfigId];
            bool reuse=existing!=null && item.Operation=='u' && existing.Event.Key==item.Key;
            if (reuse)
            {
                // Generic same-serial updates only move the existing emission;
                // a new shot re-arms its age/alpha. Flame still refreshes each tick.
                bool rearm=config.Style==11||item.Serial>existing.SerialFloor;
                if(rearm)
                {
                    int pulseAge=InitialAge(item,_tick,paused);
                    if(config.Style<=9)
                    {
                        // AS2 emits before its F-frame clock advances. Replace
                        // the old emission's phase contribution after birth with
                        // the new pulse's contribution (usually one game tick).
                        existing.PhaseAge+=PhaseClock(existing,pulseAge)
                            -(PhaseClock(existing,existing.Age)-PhaseClock(existing,existing.Age-pulseAge));
                    }
                    existing.Age=pulseAge;existing.EmissionBirth=item.BirthTick;
                }
                existing.Event=item;existing.SerialFloor=item.Serial;existing.Stopped=false;
                existing.StartX=item.StartX;existing.StartY=item.StartY;existing.EndX=item.EndX;existing.EndY=item.EndY;
                existing.HitOffsetX=0;existing.HitOffsetY=0;
                RememberChannel(existing);
                return;
            }
            if (existing!=null) return; // A duplicate id cannot retrigger an expired-in-flight burst.
            int age=InitialAge(item,_tick,paused);
            if (age>config[3]+config[4]) return;
            var arc=new Arc {Event=item,Config=config,StartX=item.StartX,StartY=item.StartY,
                EndX=item.EndX,EndY=item.EndY,Age=age,SerialFloor=item.Serial,EmissionBirth=item.BirthTick,Seed=item.Seed,
                OffsetX=ox,OffsetY=oy,AwaitingOffset=item.Delay>0 && age<1};
            arc.PhaseAge=PhaseClock(arc,age);
            _arcs.Add(arc);_arcsById.Add(item.Id,arc);RememberChannel(arc);
        }

        private void RememberChannel(Arc arc)
        {
            int key=arc.Event.Key;
            if(key>0)_retiredSerials.Remove(key);
            if(key>0&&(!_channelHeads.TryGetValue(key,out var current)||arc.SerialFloor>current.SerialFloor
                ||(arc.SerialFloor==current.SerialFloor&&NewerChannel(arc,current))))
                _channelHeads[key]=arc;
        }

        private static void MaterializeOffset(Arc arc,float ox,float oy)
        {
            if (!arc.AwaitingOffset || arc.Age<1) return;
            float dx=ox-arc.OffsetX,dy=oy-arc.OffsetY;
            arc.StartX+=dx;arc.StartY+=dy;arc.EndX+=dx;arc.EndY+=dy;
            arc.HitOffsetX=dx;arc.HitOffsetY=dy;arc.AwaitingOffset=false;
        }

        internal RayVisualDrawFrame BuildDraw()
        {
            _draw.Count=0;DecorationDropped=0;
            // Primary bodies get first claim on the budget. A large hit-point list can only
            // reduce decorative ripples, never hide a damaging beam.
            foreach (Arc arc in _arcs) if (Visible(arc)) Write(arc,arc.Config.Style,arc.StartX,arc.StartY,arc.EndX,arc.EndY);
            foreach (Arc arc in _arcs)
            {
                if (!Visible(arc)) continue;
                RayVisualPoint[] hits=arc.Config.Style==11?(arc.Event.DamageHitPoints??arc.Event.HitPoints):arc.Event.HitPoints;
                if (arc.Config.Style==11 && (arc.Event.Flags&2)==0) continue;
                if (hits!=null)
                    foreach (RayVisualPoint hit in hits) Write(arc,arc.Config.Style+16,
                        hit.X+arc.HitOffsetX,hit.Y+arc.HitOffsetY,hit.X+arc.HitOffsetX,hit.Y+arc.HitOffsetY);
                else if (arc.Event.IsHit && arc.Config.Style!=11)
                    Write(arc,arc.Config.Style+16,arc.EndX,arc.EndY,arc.EndX,arc.EndY);
            }
            BuildLights();
            return _draw;
        }

        private static bool Visible(Arc arc) => arc.Age>=(arc.Event.Delay>0?1:0) && arc.Age<=arc.Config[3]+arc.Config[4];
        private void Write(Arc arc,int style,float sx,float sy,float ex,float ey)
        {
            if (_draw.Count>=RayVisualCatalog.DrawLimit) {DecorationDropped++;return;}
            int o=_draw.Count++*RayVisualCatalog.Stride;float[] d=_draw.Data;Array.Clear(d,o,RayVisualCatalog.Stride);
            RayVisualConfig cfg=arc.Config;RayVisualEvent meta=arc.Event;
            d[o]=sx;d[o+1]=sy;d[o+2]=ex;d[o+3]=ey;
            Color(d,o+4,(int)cfg[style==42?41:0]);Color(d,o+8,(int)cfg[style==42?42:1]);
            float alpha=arc.Age<=cfg[3]?1:Math.Clamp(1-(arc.Age-cfg[3])/Math.Max(.001f,cfg[4]),0,1);
            if (cfg[5]!=0 && arc.Age<=cfg[3])
            {
                uint noise=Hash(arc.Seed+(uint)arc.PhaseAge*747796405u);
                alpha*=Math.Clamp((cfg[6]+noise/(float)uint.MaxValue*(cfg[7]-cfg[6]))*.01f,0,1);
            }
            d[o+7]=alpha;d[o+11]=cfg[2];d[o+12]=arc.PhaseAge;d[o+13]=cfg[3]+cfg[4];
            // AS2 retains the final Tesla/resonance drawing during fade; only
            // its alpha changes. Keep the authoritative age advancing for life/lights.
            if(style==0) d[o+27]=arc.Age; // ABI 12: emission pulse age, independent from structural phase
            d[o+14]=arc.Seed%65521;d[o+15]=style;d[o+16]=meta.Intensity;d[o+17]=meta.Kind;
            d[o+18]=meta.HitIndex;d[o+19]=meta.IsHit?1:0;
            int[] fields=RayVisualCatalog.ParameterFields[cfg.Style];
            for (int k=0;k<fields.Length;k++) d[o+20+k]=cfg[fields[k]];
            if (cfg.Style is 3 or 4)
            {
                ReadOnlySpan<int> palette=cfg.Palette.Length>0?cfg.Palette:
                    cfg.Style==4?ResonancePalette:SpectrumPalette;
                int count=Math.Min(7,palette.Length);d[o+24]=count;
                for (int k=0;k<count;k++) d[o+25+k]=palette[k*palette.Length/count];
            }
            if (cfg.Style==11)
            {
                d[o+28]=meta.PulseCount>1?Math.Clamp(meta.PulseIndex/(float)(meta.PulseCount-1),0,1):0;
                d[o+29]=(meta.Flags&1)!=0?1:0;d[o+30]=(meta.Flags&2)!=0?1:0;d[o+31]=(meta.Flags&4)!=0?1:0;
            }
            if (style is >=16 and <28) {d[o+11]=Math.Max(.5f,cfg[24]);d[o+20]=cfg[25];}
            if (style==10)
            {
                // One shared Bagua geometry supplies outlines, braces,
                // diagonals and spine. Its authored hold clock must freeze on fade.
                d[o+13]=cfg[3];d[o+14]=cfg[42];
                d[o+17]=cfg[45];d[o+18]=cfg[46];d[o+19]=cfg[41];
            }
        }
        private static readonly int[] SpectrumPalette={0xFF00FF,0x00FFFF,0x0066FF};
        private static readonly int[] ResonancePalette={0xFF00FF,0x00FFFF,0x8800FF,0x0088FF,0xFF66FF};
        private static void Color(float[] output,int index,int rgb)
        {output[index]=((rgb>>16)&255)/255f;output[index+1]=((rgb>>8)&255)/255f;output[index+2]=(rgb&255)/255f;}
        private static uint Hash(uint value) {value^=value>>16;value*=0x7feb352d;value^=value>>15;value*=0x846ca68b;return value^(value>>16);}
    }
}
