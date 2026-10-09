using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using CF7Launcher.Config;

namespace CF7Launcher.Guardian
{
    public partial class PerfDecisionEngine
    {
        private readonly object _renderLock=new();
        private RenderSchedule _renderSchedule;
        private PerformancePolicy _performancePolicy=PerformancePolicy.Default;
        private Action<long,RenderSelection> _applyRender;
        private Func<bool> _renderAdmission;
        private Func<int> _renderSourceHeight;
        private Func<double> _renderClock=() => Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency;
        private Action<string> _renderSender;
        private int _renderScene=-1;
        private string _renderWire;
        private long _renderSequence, _renderCommand, _awaitCommand;
        private RenderSelection? _sentSelection;
        private bool _awaitVisual, _renderFailed;
        private double _renderLastSend, _renderLastSample;
        private PerformanceDisplayState _renderDisplay=PerformanceDisplayState.Initial;

        internal void ConfigureRenderSchedule(RenderScheduleSettings settings,Action<long,RenderSelection> apply,
            Func<bool> admission,Func<int> sourceHeight,PerformancePolicy policy,
            Action<string> sender=null,Func<double> clock=null)
        {
            lock (_renderLock) {
                _performancePolicy=policy; _renderSourceHeight=sourceHeight;
                _renderSchedule=new RenderSchedule(settings,policy,sourceHeight());
                _applyRender=apply; _renderAdmission=admission;
                _renderSender=sender ?? (wire => _socket.PushToClient(wire));
                if(clock!=null) _renderClock=clock;
                _renderDisplay=_renderDisplay with {Preset=policy.Preset,Mode=policy.Mode,Status="waiting"};
                _buffer.SetPerformance(_renderDisplay);
            }
        }
        internal void ConfigurePerformancePolicy(PerformancePolicy policy)
        {
            lock (_renderLock) {
                _performancePolicy=policy;
                if(_renderSchedule?.Configure(policy,_renderSourceHeight())==true) InvalidateRenderRequest();
                _renderDisplay=_renderDisplay with {Preset=policy.Preset,Mode=policy.Mode,Status="switching"};
                _buffer.SetPerformance(_renderDisplay);
            }
        }
        private void InvalidateRenderRequest()
        {
            _awaitCommand=0; _awaitVisual=false; _sentSelection=null; _renderWire=null;
        }
        private void ResetRenderObservations() { lock (_renderLock) _renderSchedule?.ResetObservations(); }
        internal void ResetRenderSource()
        {
            lock (_renderLock) {
                _renderFailed=false;
                _renderScene=-1; _renderSequence=0; InvalidateRenderRequest();
                _renderLastSample=0; _renderSchedule?.RequireApplication();
                _renderDisplay=_renderDisplay with {Status="disconnected"};
                _buffer.SetPerformance(_renderDisplay);
            }
        }
        internal void NotifyRenderUnavailable()
        {
            lock(_renderLock) {
                _renderFailed=true; InvalidateRenderRequest();
                _renderSchedule?.RequireApplication();
                _renderDisplay=_renderDisplay with {Status="unavailable"};
                _buffer.SetPerformance(_renderDisplay);
            }
        }
        internal bool IsCurrentRenderRequest(long command)
        {
            lock(_renderLock) return _awaitVisual && command==_renderCommand && _sentSelection.HasValue;
        }
        internal void ConfirmRenderApplied(long command,RenderSelection selection,Size source)
        {
            lock(_renderLock) {
                if(!_awaitVisual || command!=_renderCommand || _sentSelection!=selection) return;
                if(source.Width<1 || source.Height<1 || source.Height>selection.Height+1) {
                    NotifyRenderUnavailable();
                    throw new InvalidOperationException("Flash 实际绘制尺寸未满足本次性能目标");
                }
                if(!_renderSchedule.ConfirmApplied(selection,_renderClock())) return;
                _awaitVisual=false;
                _renderDisplay=new PerformanceDisplayState(_performancePolicy.Preset,_performancePolicy.Mode,
                    "ready",source.Width,source.Height,selection.Quality,selection.EffectLevel,_renderSchedule.Reason);
                _buffer.SetPerformance(_renderDisplay);
                LogManager.Log("event=render_schedule_presented command="+command+" source="+source.Width+"x"+source.Height
                    +" quality="+selection.Quality+" effects="+selection.EffectLevel);
            }
        }
        internal bool EvaluateRenderSample(string[] parts)
        {
            lock (_renderLock) {
                // The retired two-tier path must never receive missing/old telemetry.
                if (_renderSchedule==null || !IsActive || !RenderSample.TryParse(parts,out var sample)) return true;
                if (sample.Scene<_renderScene || (sample.Scene==_renderScene && sample.Sequence<=_renderSequence)) return true;
                double now=_renderClock();
                if(sample.Scene!=_renderScene) {
                    _renderSchedule.RequireApplication(); InvalidateRenderRequest(); _renderScene=sample.Scene;
                }
                if(_renderSchedule.Configure(_performancePolicy,_renderSourceHeight())) InvalidateRenderRequest();
                if(now-_renderLastSample>2000) _renderSchedule.ResetObservations();
                _renderLastSample=now; _renderSequence=sample.Sequence;
                _buffer.Push((float)sample.Fps); _buffer.SetPerfLevel(sample.Tier);
                if(float.TryParse(parts[1],NumberStyles.Float,CultureInfo.InvariantCulture,out float hour)
                    && float.IsFinite(hour) && hour>=0 && hour<24) _buffer.SetGameHour(hour);
                _buffer.SetSceneEpoch(sample.Scene);
                if(_renderFailed) { _buffer.SetPerformance(_renderDisplay with {Status="unavailable"}); return true; }
                bool foreground=_activationState==null || (_activationState.IsAppActive && !_activationState.IsMinimized);
                bool surfaceReady=_renderAdmission();
                bool admitted=foreground && !sample.Paused && !sample.Held && surfaceReady;
                string gate=!foreground ? "inactive" : sample.Paused ? "paused" : sample.Held ? "held" : !surfaceReady ? "surface" : "ready";
                LogManager.Log(string.Format(CultureInfo.InvariantCulture,
                    "event=render_sample scene={0} seq={1} fps={2:F2} frames={3} ms={4} longFrames={5} maxMs={6} quality={7} tier={8} command={9} admitted={10} gate={11} recoveryMs={12}",
                    sample.Scene,sample.Sequence,sample.Fps,sample.Frames,sample.DurationMs,sample.LongFrames,
                    sample.MaxFrameMs,sample.Quality,sample.Tier,sample.AppliedCommand,admitted,gate,_renderSchedule.RecoveryMs));
                if(_awaitCommand>0 && sample.AppliedCommand==_awaitCommand && _sentSelection.HasValue
                    && sample.Quality==_sentSelection.Value.Quality && sample.Tier==_sentSelection.Value.Tier) {
                    long command=_awaitCommand; _awaitCommand=0; _awaitVisual=true;
                    _applyRender(command,_sentSelection.Value);
                }
                if(_awaitCommand==0 && !_awaitVisual && _sentSelection.HasValue
                    && (sample.AppliedCommand!=_renderCommand || sample.Quality!=_sentSelection.Value.Quality
                        || sample.Tier!=_sentSelection.Value.Tier)) {
                    _renderSchedule.RequireApplication(); InvalidateRenderRequest();
                }
                _renderDisplay=_renderDisplay with {
                    Quality=sample.Quality,
                    Status=!foreground ? "inactive" : sample.Paused ? "paused" :
                        (_awaitCommand>0 || _awaitVisual || !surfaceReady || _renderSchedule.Pending) ? "switching" : "ready"
                };
                _buffer.SetPerformance(_renderDisplay);
                if(_awaitCommand>0 || _awaitVisual) {
                    _renderSchedule.ResetObservations();
                    if(_awaitCommand>0 && now-_renderLastSend>=3000) SendRenderWire(now);
                    return true;
                }
                var selection=_renderSchedule.Observe(sample,now,admitted);
                if(!_sentSelection.HasValue || selection!=_sentSelection.Value || _renderSchedule.Pending) {
                    _sentSelection=selection; _awaitCommand=++_renderCommand;
                    _renderWire="P"+selection.Tier+"|"+selection.SoftPercent+"|"+selection.Quality+"|"+_awaitCommand+"|"+sample.Scene;
                    SendRenderWire(now);
                    _renderDisplay=_renderDisplay with {Status="switching",Reason=_renderSchedule.Reason};
                    _buffer.SetPerformance(_renderDisplay);
                    LogManager.Log(string.Format(CultureInfo.InvariantCulture,
                        "event=render_schedule_request command={0} scene={1} stage={2} height={3} quality={4} effects={5} reason={6}",
                        _awaitCommand,sample.Scene,selection.Stage,selection.Height,selection.Quality,selection.EffectLevel,_renderSchedule.Reason));
                }
                return true;
            }
        }
        private void SendRenderWire(double now)
        {
            if(_renderWire==null) return;
            _renderSender(_renderWire); _renderLastSend=now;
        }
    }
}
