using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    internal sealed class RenderScheduleSettings
    {
        internal double DownFps=23, UpFps=28, PanicFps=12;
        internal int DownMs=1500, UpMs=6000, PanicMs=1000, SettleMs=1000, RetryUpMs=20000;
        internal int FixedStage=-1;
        internal float Sharpness=.15f;
        internal static RenderScheduleSettings Load(string path)
        {
            var j=JObject.Parse(File.ReadAllText(path));
            if (j.Value<int?>("version")!=1) throw new InvalidDataException("Unknown render schedule version");
            var s=new RenderScheduleSettings {
                DownFps=j.Value<double>("downFps"), UpFps=j.Value<double>("upFps"), PanicFps=j.Value<double>("panicFps"),
                DownMs=j.Value<int>("downMs"), UpMs=j.Value<int>("upMs"), PanicMs=j.Value<int>("panicMs"),
                SettleMs=j.Value<int>("settleMs"), RetryUpMs=j.Value<int>("retryUpMs"),
                FixedStage=j.Value<int>("fixedStage"), Sharpness=j.Value<float>("sharpness")
            };
            if (!double.IsFinite(s.PanicFps) || !double.IsFinite(s.DownFps) || !double.IsFinite(s.UpFps)
                || s.PanicFps<1 || s.PanicFps>=s.DownFps || s.DownFps>=s.UpFps || s.UpFps>=30
                || s.DownMs<500 || s.UpMs<s.DownMs || s.PanicMs<500 || s.SettleMs<500 || s.RetryUpMs<s.UpMs
                || s.UpMs>60000 || s.DownMs>10000 || s.PanicMs>10000 || s.SettleMs>10000 || s.RetryUpMs>120000
                || s.FixedStage< -1 || s.FixedStage>5 || !float.IsFinite(s.Sharpness) || s.Sharpness<0 || s.Sharpness>.4)
                throw new InvalidDataException("Invalid render schedule settings");
            return s;
        }
    }
    internal readonly record struct RenderSelection(int Stage,double Scale,string Quality)
    {
        internal int Tier => Quality=="LOW" ? 1 : 0;
    }
    internal sealed class RenderSample
    {
        internal int Scene, Frames, DurationMs, LongFrames, MaxFrameMs, Tier;
        internal long Sequence, AppliedCommand;
        internal string Preset, Quality;
        internal bool Held, Paused;
        internal double Fps => Frames*1000.0/DurationMs;
        // fps|hour|tier|scene|v2|frames|ms|longFrames|maxMs|preset|quality|held|paused|seq|appliedCommand
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
    // All durations below count fresh AS2 sample time, never wall time spent with no
    // messages, inactive, paused, loading, or waiting for a resized capture surface.
    internal sealed class RenderSchedule
    {
        private readonly RenderScheduleSettings _settings;
        private readonly Queue<RenderSample> _window=new Queue<RenderSample>();
        private RenderSelection[] _stages;
        private string _preset;
        private int _stage, _warmup, _down, _up, _panic, _windowMs;
        private double _settleUntil, _noUpgradeUntil, _lastUpgrade=double.NegativeInfinity;
        internal string Reason { get; private set; }="initial";
        internal double MeanFps { get; private set; }
        internal int RecoveryMs => _up;
        internal RenderSelection Current => _stages[_stage];
        internal RenderSchedule(RenderScheduleSettings settings) { _settings=settings; SetPreset("MEDIUM"); }
        internal static RenderSelection[] Stages(string preset)
        {
            var list=new List<RenderSelection>();
            if (preset=="HIGH" || preset=="BEST") list.Add(new RenderSelection(0,1,preset));
            if (preset!="LOW") {
                list.Add(new RenderSelection(list.Count,1,"MEDIUM"));
                list.Add(new RenderSelection(list.Count,.85,"MEDIUM"));
                list.Add(new RenderSelection(list.Count,.75,"MEDIUM"));
            } else {
                list.Add(new RenderSelection(0,1,"LOW")); list.Add(new RenderSelection(1,.85,"LOW"));
            }
            list.Add(new RenderSelection(list.Count,.75,"LOW"));
            list.Add(new RenderSelection(list.Count,.67,"LOW"));
            return list.ToArray();
        }
        private void SetPreset(string preset)
        {
            _preset=preset; _stages=Stages(preset); _stage=0;
            if (_settings.FixedStage>=0) _stage=Math.Min(_settings.FixedStage,_stages.Length-1);
            ResetObservations();
        }
        internal void ResetObservations()
        {
            _window.Clear(); _windowMs=_warmup=_down=_up=_panic=0; MeanFps=0;
        }
        internal RenderSelection Observe(RenderSample sample,double now,bool admitted)
        {
            if (_preset!=sample.Preset) SetPreset(sample.Preset);
            if (!admitted || sample.Held || sample.Paused || sample.DurationMs>2000) { ResetObservations(); return Current; }
            if (_settings.FixedStage>=0) return Current;
            if (now<_settleUntil) { ResetObservations(); return Current; }
            int dt=sample.DurationMs;
            _window.Enqueue(sample); _windowMs+=dt;
            while (_window.Count>1 && _windowMs-_window.Peek().DurationMs>=1000) _windowMs-=_window.Dequeue().DurationMs;
            int frames=0, slow=0; foreach(var s in _window) { frames+=s.Frames; slow+=s.LongFrames; }
            MeanFps=frames*1000.0/_windowMs;
            _warmup+=dt; if (_warmup<1000) return Current;
            _panic=sample.Fps<_settings.PanicFps ? _panic+dt : 0;
            _down=MeanFps<_settings.DownFps ? _down+dt : 0;
            // A frame-count window naturally oscillates around the 30 FPS cap.
            // Require sustained headroom, not six seconds of monotonically rising FPS.
            // A small dip spends accumulated credit; real pressure/long frames reset it.
            if (slow>0 || MeanFps<_settings.DownFps || now<_noUpgradeUntil) _up=0;
            else if (MeanFps>_settings.UpFps) _up+=dt;
            else _up=Math.Max(0,_up-dt);
            int next=_stage;
            if (_panic>=_settings.PanicMs && _stage<_stages.Length-1) {
                int emergency=Array.FindIndex(_stages,s=>s.Quality=="LOW" && s.Scale==.75);
                next=Math.Max(_stage+1,emergency); Reason="panic";
            } else if (_down>=_settings.DownMs && _stage<_stages.Length-1) { next++; Reason="sustained_low_fps"; }
            else if (_up>=_settings.UpMs && _stage>0) { next--; Reason="sustained_headroom"; }
            if (next!=_stage) {
                if (next>_stage && now-_lastUpgrade<10000) _noUpgradeUntil=now+_settings.RetryUpMs;
                if (next<_stage) _lastUpgrade=now;
                _stage=next; _settleUntil=now+_settings.SettleMs; ResetObservations();
            }
            return Current;
        }
    }
}
