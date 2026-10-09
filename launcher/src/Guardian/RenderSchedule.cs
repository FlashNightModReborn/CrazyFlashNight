using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using CF7Launcher.Config;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    internal sealed class RenderScheduleSettings
    {
        internal double DownFps=23, UpFps=28, PanicFps=12;
        internal int DownMs=1500, UpMs=6000, PanicMs=1000, SettleMs=1000, RetryUpMs=20000;
        internal float Sharpness=.15f;
        internal static RenderScheduleSettings Load(string path)
        {
            var j=JObject.Parse(File.ReadAllText(path));
            if (j.Value<int?>("version")!=1) throw new InvalidDataException("Unknown render schedule version");
            var s=new RenderScheduleSettings {
                DownFps=j.Value<double>("downFps"), UpFps=j.Value<double>("upFps"), PanicFps=j.Value<double>("panicFps"),
                DownMs=j.Value<int>("downMs"), UpMs=j.Value<int>("upMs"), PanicMs=j.Value<int>("panicMs"),
                SettleMs=j.Value<int>("settleMs"), RetryUpMs=j.Value<int>("retryUpMs"), Sharpness=j.Value<float>("sharpness")
            };
            if (!double.IsFinite(s.PanicFps) || !double.IsFinite(s.DownFps) || !double.IsFinite(s.UpFps)
                || s.PanicFps<1 || s.PanicFps>=s.DownFps || s.DownFps>=s.UpFps || s.UpFps>=30
                || s.DownMs<500 || s.UpMs<s.DownMs || s.PanicMs<500 || s.SettleMs<500 || s.RetryUpMs<s.UpMs
                || s.UpMs>60000 || s.DownMs>10000 || s.PanicMs>10000 || s.SettleMs>10000 || s.RetryUpMs>120000
                || !float.IsFinite(s.Sharpness) || s.Sharpness<0 || s.Sharpness>.4)
                throw new InvalidDataException("Invalid render schedule settings");
            return s;
        }
    }
    // Height is the Flash raster budget, before Windows DPI virtualization, never output height.
    internal readonly record struct RenderSelection(int Stage,int Height,string Quality,int EffectLevel)
    {
        internal int Tier => Quality=="LOW" ? 1 : 0;
        internal int SoftPercent => EffectLevel*50;
    }
    internal sealed class RenderSample
    {
        internal int Scene, Frames, DurationMs, LongFrames, MaxFrameMs, Tier;
        internal long Sequence, AppliedCommand;
        internal string Preset, Quality;
        internal bool Held, Paused;
        internal double Fps => Frames*1000.0/DurationMs;
        // v2 retains the old preset/tier slots for paired wire compatibility; neither owns policy.
        internal static bool TryParse(string[] p,out RenderSample result)
        {
            result=null;
            if (p.Length!=15 || p[4]!="v2" || !I(p[2],out int tier) || tier<0 || tier>1
                || !I(p[3],out int scene) || scene<0 || !I(p[5],out int frames) || frames<1 || frames>100000
                || !I(p[6],out int ms) || ms<1 || ms>60000 || !I(p[7],out int slow) || slow<0 || slow>frames
                || !I(p[8],out int max) || max<0 || max>ms || !QualityValid(p[9]) || !QualityValid(p[10])
                || (p[11]!="0" && p[11]!="1") || (p[12]!="0" && p[12]!="1")
                || !long.TryParse(p[13],NumberStyles.None,CultureInfo.InvariantCulture,out long seq) || seq<1
                || !long.TryParse(p[14],NumberStyles.None,CultureInfo.InvariantCulture,out long command) || command<0
                || frames*1000.0/ms>120) return false;
            result=new RenderSample { Scene=scene,Frames=frames,DurationMs=ms,LongFrames=slow,MaxFrameMs=max,
                Preset=p[9],Quality=p[10],Tier=tier,Held=p[11]=="1",Paused=p[12]=="1",Sequence=seq,AppliedCommand=command };
            return true;
        }
        private static bool I(string s,out int value) => int.TryParse(s,NumberStyles.None,CultureInfo.InvariantCulture,out value);
        internal static bool QualityValid(string value) => value=="LOW" || value=="MEDIUM" || value=="HIGH" || value=="BEST";
    }
    internal sealed class RenderSchedule
    {
        private readonly RenderScheduleSettings _settings;
        private readonly Queue<RenderSample> _window=new();
        private RenderSelection[] _stages;
        private PerformancePolicy _policy;
        private int _sourceHeight, _stage, _warmup, _down, _up, _panic, _windowMs;
        private double _settleUntil, _noUpgradeUntil, _lastUpgrade=double.NegativeInfinity;
        private bool _pendingUpgrade, _pendingFailedUpgrade;
        internal bool Pending { get; private set; }
        internal string Reason { get; private set; }="initial";
        internal double MeanFps { get; private set; }
        internal int RecoveryMs => _up;
        internal RenderSelection Current => _stages[_stage];
        internal RenderSchedule(RenderScheduleSettings settings,PerformancePolicy policy=null,int sourceHeight=2160)
        {
            _settings=settings;
            Configure(policy ?? PerformancePolicy.Default,sourceHeight);
        }
        internal static RenderSelection[] Stages(PerformancePolicy policy,int sourceHeight)
        {
            var specs=policy.Preset switch {
                "performance" => new[] {(100,"LOW",1),(75,"LOW",2),(50,"LOW",2)},
                "quality" => new[] {(100,"HIGH",0),(85,"HIGH",0),(85,"MEDIUM",1),(75,"MEDIUM",1),(75,"LOW",2)},
                _ => new[] {(100,"MEDIUM",0),(85,"MEDIUM",1),(75,"MEDIUM",1),(75,"LOW",2),(67,"LOW",2)}
            };
            int ceiling=policy.Preset=="quality" ? 1440 : policy.Preset=="performance" ? 720 : 1080;
            int limit=Math.Min(ceiling,Math.Max(1,sourceHeight));
            if (policy.MaxRenderHeight>0) limit=Math.Min(limit,policy.MaxRenderHeight);
            var list=new List<RenderSelection>();
            for(int i=0;i<specs.Length;i++) {
                var (percent,quality,effects)=specs[i];
                // The absolute ceiling survives fullscreen; scaling within that
                // budget still gives small windows a real resolution lever.
                var next=new RenderSelection(i,Math.Max(1,(int)Math.Round(limit*percent/100.0)),quality,effects);
                list.Add(next);
            }
            return list.ToArray();
        }
        internal bool Configure(PerformancePolicy policy,int sourceHeight)
        {
            sourceHeight=Math.Max(1,sourceHeight);
            if (_policy==policy && _sourceHeight==sourceHeight) return false;
            bool samePolicy=_policy==policy;
            int previousStage=_stages==null ? 0 : Current.Stage;
            _policy=policy; _sourceHeight=sourceHeight; _stages=Stages(policy,sourceHeight);
            _stage=0;
            if(samePolicy && policy.Mode=="auto") {
                int retained=Array.FindIndex(_stages,s=>s.Stage>=previousStage);
                _stage=retained>=0 ? retained : _stages.Length-1;
            }
            _pendingUpgrade=_pendingFailedUpgrade=false;
            _settleUntil=0;
            if(!samePolicy) { _noUpgradeUntil=0; _lastUpgrade=double.NegativeInfinity; }
            Pending=true; Reason=samePolicy ? "viewport_changed" : "policy_changed"; ResetObservations();
            return true;
        }
        internal void RequireApplication()
        {
            Pending=true; _pendingUpgrade=_pendingFailedUpgrade=false; ResetObservations();
        }
        internal bool ConfirmApplied(RenderSelection selection,double now)
        {
            if (!Pending || selection!=Current) return false;
            if (_pendingUpgrade) _lastUpgrade=now;
            if (_pendingFailedUpgrade) _noUpgradeUntil=now+_settings.RetryUpMs;
            _pendingUpgrade=_pendingFailedUpgrade=false;
            Pending=false; _settleUntil=now+_settings.SettleMs; ResetObservations();
            return true;
        }
        internal void ResetObservations()
        {
            _window.Clear(); _windowMs=_warmup=_down=_up=_panic=0; MeanFps=0;
        }
        private bool SameTarget(int index) => _stages[index].Height==Current.Height
            && _stages[index].Quality==Current.Quality && _stages[index].EffectLevel==Current.EffectLevel;
        private int NextDistinct(int direction)
        {
            for(int i=_stage+direction;i>=0 && i<_stages.Length;i+=direction)
                if(!SameTarget(i)) return i;
            return _stage;
        }
        internal RenderSelection Observe(RenderSample sample,double now,bool admitted)
        {
            if (!admitted || Pending || sample.Held || sample.Paused || sample.DurationMs>2000 || now<_settleUntil) {
                ResetObservations(); return Current;
            }
            int dt=sample.DurationMs;
            _window.Enqueue(sample); _windowMs+=dt;
            while (_window.Count>1 && _windowMs-_window.Peek().DurationMs>=1000) _windowMs-=_window.Dequeue().DurationMs;
            int frames=0, slow=0; foreach(var s in _window) { frames+=s.Frames; slow+=s.LongFrames; }
            MeanFps=frames*1000.0/_windowMs;
            if (_policy.Mode=="fixed") return Current;
            _warmup+=dt; if (_warmup<1000) return Current;
            _panic=sample.Fps<_settings.PanicFps ? _panic+dt : 0;
            _down=MeanFps<_settings.DownFps ? _down+dt : 0;
            if (slow>0 || MeanFps<_settings.DownFps || now<_noUpgradeUntil) _up=0;
            else if (MeanFps>_settings.UpFps) _up+=dt;
            else _up=Math.Max(0,_up-dt);
            int next=_stage;
            if (_panic>=_settings.PanicMs && !SameTarget(_stages.Length-1)) {
                next=_stages.Length-1; Reason="panic";
            } else if (_down>=_settings.DownMs) { next=NextDistinct(1); Reason="sustained_low_fps"; }
            else if (_up>=_settings.UpMs) { next=NextDistinct(-1); Reason="sustained_headroom"; }
            if (next!=_stage) {
                _pendingFailedUpgrade=next>_stage && now-_lastUpgrade<10000;
                _pendingUpgrade=next<_stage;
                _stage=next; Pending=true; ResetObservations();
            }
            return Current;
        }
    }
}
