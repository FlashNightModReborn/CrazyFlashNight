using System;
using System.Collections.Generic;
using System.IO;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // No gameplay state or RNG. AS2 owns scene/pose/state; this engine owns only
    // bounded presentation curves, the cached field and realtime candidates.
    internal sealed class SceneLightEngine
    {
        private readonly SceneLightCatalog _catalog;
        private SceneLightDefinition[] _definitions=Array.Empty<SceneLightDefinition>();
        private SceneLightPose[] _poses=Array.Empty<SceneLightPose>();
        private SceneLightState _pendingState;
        private long _scene,_sequence;
        private int _revision,_tick;
        private bool _animated;
        private readonly WorldLightCandidate[] _realtime=new WorldLightCandidate[SceneLightCatalog.Limit];
        private readonly float[] _cached=new float[SceneLightCatalog.Limit*16];
        private readonly float[] _record=new float[16];
        internal long StaticVersion {get;private set;}
        internal int CachedCount {get;private set;}
        internal int RealtimeCount {get;private set;}
        internal float[] Cached=>_cached;
        internal WorldLightCandidate[] Realtime=>_realtime;
        internal float MaximumResponse=>_catalog.MaximumResponse;
        internal long Scene=>_scene;
        internal SceneLightEngine(SceneLightCatalog catalog)=>_catalog=catalog;
        internal void Configure(long scene,SceneLightSnapshot snapshot)
        {
            if(scene<_scene || (scene==_scene && snapshot.Revision<=_revision))return;
            var definitions=new SceneLightDefinition[snapshot.Definitions.Length];
            for(int i=0;i<definitions.Length;i++)definitions[i]=_catalog.Resolve(snapshot.Definitions[i],i+1);
            _scene=scene;_revision=snapshot.Revision;_sequence=0;_definitions=definitions;
            _poses=(SceneLightPose[])snapshot.Poses.Clone();
            _animated=false;foreach(var d in definitions)if(d.Animation!="constant" || d.Color!=d.Color2){_animated=true;break;}
            if(_pendingState!=null && _pendingState.Scene==scene && _pendingState.Revision==_revision){var p=_pendingState;_pendingState=null;if(!Adopt(p))throw new InvalidDataException("Invalid pending scene pose");}
            else if(_pendingState?.Scene<scene || (_pendingState?.Scene==scene && _pendingState.Revision<_revision))_pendingState=null;
            Rebuild();
        }
        internal bool Adopt(SceneLightState state)
        {
            if(state.Scene<_scene || (state.Scene==_scene && state.Revision<_revision))return false;
            if(state.Scene>_scene || state.Revision>_revision) {
                if(_pendingState!=null && (state.Scene<_pendingState.Scene || (state.Scene==_pendingState.Scene && state.Revision<_pendingState.Revision)
                    || (state.Scene==_pendingState.Scene && state.Revision==_pendingState.Revision && state.Sequence<=_pendingState.Sequence)))return false;
                var rows=new Dictionary<int,SceneLightPose>();
                if(_pendingState!=null && state.Scene==_pendingState.Scene && state.Revision==_pendingState.Revision)foreach(var p in _pendingState.Poses)rows[p.Id]=p;
                foreach(var p in state.Poses)rows[p.Id]=p;
                var merged=new SceneLightPose[rows.Count];rows.Values.CopyTo(merged,0);
                _pendingState=new(state.Scene,state.Revision,state.Sequence,merged);return true;
            }
            if(state.Sequence<=_sequence)return false;
            foreach(var p in state.Poses)if(p.Id>_poses.Length)return false;
            foreach(var p in state.Poses)_poses[p.Id-1]=p;
            _sequence=state.Sequence;Rebuild();return true;
        }
        internal void Tick(int tick,bool paused)
        {if(!paused && _tick!=tick){_tick=tick;if(_animated)Rebuild();}}
        internal void Reset(){_scene=0;_sequence=0;_revision=0;_tick=0;_pendingState=null;_definitions=Array.Empty<SceneLightDefinition>();_poses=Array.Empty<SceneLightPose>();CachedCount=RealtimeCount=0;StaticVersion++;}
        private void Rebuild()
        {
            int cached=0,realtime=0;bool changed=false;
            for(int i=0;i<_definitions.Length;i++) {
                var d=_definitions[i];var p=_poses[i];if(!d.Enabled || p.Weight<=0 || d.Mode=="visualOnly")continue;
                double seconds=_tick/30.0,phase=seconds*d.Rate*2*Math.PI+d.Phase*Math.PI/180;
                float pulse=d.Animation switch {"pulse"=>(float)Math.Sin(phase),"flicker"=>(float)(.65*Math.Sin(phase+Hash(d.Key))+.35*Math.Sin(phase*2.173+Hash(d.Key)*.37)),_=>0};
                float energy=Math.Clamp(d.Energy*(1+d.Amplitude*pulse)*p.Weight,0,2),baseEnergy=d.Mode=="cached"?energy:d.Mode=="hybrid"?d.BaseEnergy*p.Weight:0;
                float angle=(float)((d.Angle+(d.Animation=="sweep"?d.SweepAngle*Math.Sin(phase):0))*p.Handedness*Math.PI/180);
                float dx=p.Dx*(float)Math.Cos(angle)-p.Dy*(float)Math.Sin(angle),dy=p.Dx*(float)Math.Sin(angle)+p.Dy*(float)Math.Cos(angle);
                float mix=d.Color==d.Color2?0:(float)(.5+.5*Math.Sin(phase));
                float r=(((d.Color>>16)&255)*(1-mix)+((d.Color2>>16)&255)*mix)/255f;
                float g=(((d.Color>>8)&255)*(1-mix)+((d.Color2>>8)&255)*mix)/255f;
                float b=((d.Color&255)*(1-mix)+(d.Color2&255)*mix)/255f;
                var light=new WorldLightCandidate(d.Id,d.Priority,p.X,p.Y,Math.Clamp(d.Extent*p.Scale,1,1024),energy,r,g,b,d.Kind,
                    d.Kind==0?0:dx,d.Kind==0?0:dy,d.Kind==0?0:Math.Clamp(d.HalfWidth*p.Scale,.5f,512));
                if(baseEnergy>0) {
                    var c=new WorldLightCandidate(d.Id,d.Priority,light.X,light.Y,light.Length,baseEnergy,r,g,b,d.Kind,light.DirectionX,light.DirectionY,light.HalfWidth);
                    c.WriteTo(_record,0);
                    for(int n=0;n<16;n++){if(_cached[cached*16+n]!=_record[n])changed=true;_cached[cached*16+n]=_record[n];}cached++;
                }
                float remaining=d.Mode=="cached"?0:Math.Max(0,energy-baseEnergy);
                if(remaining>0)_realtime[realtime++]=new WorldLightCandidate(d.Id,d.Priority,light.X,light.Y,light.Length,remaining,r,g,b,d.Kind,
                    light.DirectionX,light.DirectionY,light.HalfWidth,sceneReserved:d.Reserved);
            }
            if(changed || cached!=CachedCount)StaticVersion++;
            CachedCount=cached;RealtimeCount=realtime;
        }
        private static double Hash(string key){uint h=2166136261;foreach(char c in key)h=unchecked((h^c)*16777619);return (h%10000)/1000.0;}
    }
}
