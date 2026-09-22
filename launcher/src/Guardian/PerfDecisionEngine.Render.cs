using System;
using System.Diagnostics;
using System.Globalization;

namespace CF7Launcher.Guardian
{
    public partial class PerfDecisionEngine
    {
        private readonly object _renderLock=new object();
        private RenderSchedule _renderSchedule;
        private Action<RenderSelection> _applyRender;
        private Func<bool> _renderAdmission;
        private int _renderScene=-1;
        private string _renderPreset, _renderWire;
        private long _renderSequence, _renderCommand, _awaitCommand;
        private RenderSelection? _sentSelection;
        private double _renderLastSend, _renderLastSample;
        private float _renderSoftU;

        internal void ConfigureRenderSchedule(RenderScheduleSettings settings,Action<RenderSelection> apply,Func<bool> admission)
        {
            lock (_renderLock) { _renderSchedule=new RenderSchedule(settings); _applyRender=apply; _renderAdmission=admission; }
        }
        private void ResetRenderObservations() { lock (_renderLock) _renderSchedule?.ResetObservations(); }
        internal void ResetRenderSource()
        {
            lock (_renderLock) {
                _renderScene=-1; _renderSequence=0; _awaitCommand=0; _sentSelection=null; _renderWire=null;
                _renderLastSample=0; _renderSchedule?.ResetObservations();
            }
        }
        // True also for malformed/legacy samples when configured: never let synthetic
        // old-format feed-forward FPS re-enter the old two-tier controller in parallel.
        internal bool EvaluateRenderSample(string[] parts)
        {
            lock (_renderLock) {
                if (_renderSchedule==null) return false;
                if (!IsActive || !RenderSample.TryParse(parts,out var sample)) return true;
                if (sample.Scene<_renderScene || sample.Sequence<=_renderSequence) return true;
                double now=Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency;
                if (sample.Scene!=_renderScene || sample.Preset!=_renderPreset) {
                    _renderSchedule.ResetObservations(); _awaitCommand=0; _sentSelection=null;
                    _renderScene=sample.Scene; _renderPreset=sample.Preset;
                }
                if (now-_renderLastSample>2000) _renderSchedule.ResetObservations();
                _renderLastSample=now; _renderSequence=sample.Sequence;
                bool foreground=_activationState==null || (_activationState.IsAppActive && !_activationState.IsMinimized);
                bool surfaceReady=_renderAdmission();
                string gate=!foreground ? "inactive" : sample.Paused ? "paused" : sample.Held ? "held" : !surfaceReady ? "surface" : "ready";
                bool admitted=gate=="ready";
                if (_awaitCommand>0 && sample.AppliedCommand==_awaitCommand && _sentSelection.HasValue
                    && sample.Quality==_sentSelection.Value.Quality && sample.Tier==_sentSelection.Value.Tier) {
                    _awaitCommand=0; _applyRender(_sentSelection.Value);
                    LogManager.Log("event=render_schedule_applied command="+sample.AppliedCommand+" scene="+sample.Scene
                        +" stage="+_sentSelection.Value.Stage+" quality="+sample.Quality);
                }
                LogManager.Log(string.Format(CultureInfo.InvariantCulture,
                    "event=render_sample scene={0} seq={1} fps={2:F2} frames={3} ms={4} longFrames={5} maxMs={6} quality={7} tier={8} command={9} admitted={10} gate={11} recoveryMs={12}",
                    sample.Scene,sample.Sequence,sample.Fps,sample.Frames,sample.DurationMs,sample.LongFrames,sample.MaxFrameMs,sample.Quality,sample.Tier,sample.AppliedCommand,admitted,gate,_renderSchedule.RecoveryMs));
                if (_awaitCommand>0) {
                    _renderSchedule.ResetObservations();
                    if (now-_renderLastSend>=3000) SendRenderWire(now);
                    return true;
                }
                var selection=_renderSchedule.Observe(sample,now,admitted);
                float soft=_renderSoftU;
                if (admitted && _renderSchedule.MeanFps>0) soft=(float)Math.Clamp((26-_renderSchedule.MeanFps)/3,0,1);
                if (!_sentSelection.HasValue || selection!=_sentSelection.Value || (admitted && Math.Abs(soft-_renderSoftU)>.1f)) {
                    _sentSelection=selection; _renderSoftU=soft; _awaitCommand=++_renderCommand;
                    _renderWire="P"+selection.Tier+"|"+(int)Math.Round(soft*100)+"|"+selection.Quality+"|"+_awaitCommand+"|"+sample.Scene;
                    SendRenderWire(now);
                    LogManager.Log(string.Format(CultureInfo.InvariantCulture,
                        "event=render_schedule_request command={0} scene={1} stage={2} scale={3:F2} quality={4} softU={5:F2} reason={6}",
                        _awaitCommand,sample.Scene,selection.Stage,selection.Scale,selection.Quality,soft,_renderSchedule.Reason));
                } else if (now-_renderLastSend>=3000) SendRenderWire(now);
                return true;
            }
        }
        private void SendRenderWire(double now)
        {
            if (_renderWire==null) return;
            _socket.PushToClient(_renderWire); _renderLastSend=now;
        }
    }
}
