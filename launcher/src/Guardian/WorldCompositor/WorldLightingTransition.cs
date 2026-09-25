using System;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Only predicts display continuity: hold the last validated grade while a scene is
    // loading. Never infer scene contents, game time, or night-vision entitlement.
    internal sealed class WorldLightingTransition
    {
        private long _sequence, _scene, _readyScene;
        private double _pendingSince, _blendStarted, _estimatedGapMs=160;
        private double[] _from=WorldColorMatrix.Identity(), _target=WorldColorMatrix.Identity();
        // LUT 路径（lut-set-v1）：插值语义由矩阵改为 light 等级——同一过渡状态机/时序窗口，
        // _fromLight/_targetLight 与 _from/_target 在同一 Commit/Hold 点同步采样，Sample 与
        // SampleLight 共享同一 t。矩阵字段对 legacy 路径语义不变。
        private double _fromLight=7, _targetLight=7;
        internal bool HasValidState { get; private set; }
        internal bool Pending { get; private set; }
        internal double BlendDurationMs { get; private set; }
        internal double LastReadyLight { get; private set; } = 7;
        private string _mode;
        // 最近一次 Commit 的模式（hold/pending 期间保持）：LUT/legacy 分派只认它，不看在途报文。
        internal string CurrentMode => _mode;
        private WorldLightingFrame _pendingReady;
        private double _captureNotBefore;
        internal bool WaitingForCapture => _pendingReady != null;
        internal long ReadyScene => _readyScene;

        internal bool Adopt(WorldLightingFrame frame, double now)
        {
            if (frame.Sequence<=_sequence || frame.Scene<_scene) return false;
            bool newObservedScene=frame.Scene!=_scene;
            _sequence=frame.Sequence; _scene=frame.Scene;
            if (!frame.Ready) {
                Hold(now,newObservedScene);
                _pendingReady=null;
                return true;
            }

            if (HasValidState && (Pending || frame.Scene!=_readyScene)) {
                // Scene state can arrive while WGC is still presenting an older frame.
                // Later heartbeats may update the target but must not move the fence forever.
                Hold(now,newObservedScene);
                if (_pendingReady==null || _pendingReady.Scene!=frame.Scene) _captureNotBefore=now;
                _pendingReady=frame;
                return true;
            }
            Commit(frame,now);
            return true;
        }
        private void Hold(double now,bool newScene)
        {
            if (!Pending || newScene) {
                _pendingSince=now;
                _from=_target=Sample(now);
                _fromLight=_targetLight=SampleLight(now);
                BlendDurationMs=0;
            }
            Pending=true;
        }
        internal bool ConfirmCapturedFrame(double capturedQpcMs,double now)
        {
            if (_pendingReady==null || !double.IsFinite(capturedQpcMs) || capturedQpcMs<_captureNotBefore) return false;
            var frame=_pendingReady;
            _pendingReady=null;
            Commit(frame,now);
            return true;
        }
        private void Commit(WorldLightingFrame frame,double now)
        {
            bool sceneHandoff=HasValidState && (Pending || frame.Scene!=_readyScene);
            if (HasValidState && Pending)
                _estimatedGapMs=0.75*_estimatedGapMs+0.25*Math.Clamp(now-_pendingSince,0,2000);
            _from=Sample(now);
            _fromLight=SampleLight(now);
            _target=WorldColorMatrix.Generate(frame.Parameters);
            _targetLight=frame.Light;
            BlendDurationMs=!HasValidState ? 0 : sceneHandoff ? Math.Clamp(_estimatedGapMs*0.5,80,180)
                : frame.Mode!=_mode || frame.Immediate || frame.Paused ? 0 : 350;
            _blendStarted=now;
            HasValidState=true; Pending=false; _readyScene=frame.Scene;
            LastReadyLight=frame.Light; _mode=frame.Mode;
        }

        internal double[] Sample(double now)
        {
            double t=BlendDurationMs<=0 ? 1 : Math.Clamp((now-_blendStarted)/BlendDurationMs,0,1);
            var result=new double[20];
            for (int i=0;i<20;i++) result[i]=_from[i]+(_target[i]-_from[i])*t;
            return result;
        }
        // 与 Sample 共享同一过渡窗口/时序：输出当前连续 light 等级（LUT 路径再经相邻整数档混合）。
        internal double SampleLight(double now)
        {
            double t=BlendDurationMs<=0 ? 1 : Math.Clamp((now-_blendStarted)/BlendDurationMs,0,1);
            return _fromLight+(_targetLight-_fromLight)*t;
        }
        internal bool ShouldPresent(bool viewportAdmitted) => viewportAdmitted && HasValidState;
        internal bool IsOverdue(double now) => HasValidState && Pending && now-_pendingSince>10000;
    }
}
