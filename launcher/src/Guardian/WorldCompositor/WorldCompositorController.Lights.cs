using System;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // A visual frame may compose F6 then F7. Keep both selection/hysteresis steps,
    // but publish only the last result. Lifecycle clears always publish immediately.
    internal sealed class WorldLightSubmitBatch
    {
        private readonly Action<CombatFxDrawFrame,float,float,float> _submit;
        private int _depth;
        private int _ownerThread;
        private CombatFxDrawFrame _pending;
        private float _x, _y, _scale;
        private bool _ray;
        internal bool FailureWasRay { get; private set; }
        internal WorldLightSubmitBatch(Action<CombatFxDrawFrame,float,float,float> submit) => _submit = submit;
        internal void Begin()
        {
            int thread = Environment.CurrentManagedThreadId;
            if (_depth == 0) _ownerThread = thread;
            if (_ownerThread == thread) _depth++;
        }
        internal void Submit(CombatFxDrawFrame frame, float x, float y, float scale, bool ray, bool immediate = false)
        {
            if (_depth > 0 && _ownerThread == Environment.CurrentManagedThreadId && !immediate) {
                _pending = frame; _x = x; _y = y; _scale = scale; _ray |= ray; return;
            }
            _pending = null; _ray = false;
            _submit(frame, x, y, scale);
        }
        internal void End()
        {
            if (_ownerThread != Environment.CurrentManagedThreadId) return;
            if (_depth <= 0) throw new InvalidOperationException("Unbalanced world-light frame");
            if (--_depth != 0 || _pending == null) return;
            var frame = _pending; _pending = null;
            FailureWasRay = _ray; _ray = false;
            _submit(frame, _x, _y, _scale);
        }
    }

    internal sealed partial class WorldCompositorController
    {
        // One owner combines the borrowed F6/F7 outputs. Native receives only the
        // selected sixteen lights; clearing either source retains the other one.
        private readonly WorldLightComposer _worldLights;
        private readonly WorldLightSubmitBatch _worldLightSubmissions;
        private float _lightCameraX,_lightCameraY,_lightCameraScale=1;

        internal void BeginVisualFrame()
        {
            // Do not hold this lock while FrameTask parses under its domain locks.
            // Foreign-thread updates/clears publish immediately and cancel pending data.
            lock (_weatherCameraLock) _worldLightSubmissions.Begin();
        }
        internal void EndVisualFrame()
        {
            Exception failure = null; bool ray = false;
            lock (_weatherCameraLock) {
                try { _worldLightSubmissions.End(); }
                catch (Exception error) { failure = error; ray = _worldLightSubmissions.FailureWasRay; }
            }
            if (failure == null) return;
            LogManager.Log("event=world_light_frame_failed " + failure.Message);
            if (ray) ProjectileRenderFault("ray_native_frame_failed", failure);
            else RejectCombatFx();
        }

        // All callers hold _weatherCameraLock and submit the borrowed result immediately.
        private void SubmitWorldLightsLocked(float x,float y,float scale, bool ray = false, bool immediate = false)
        {
            _lightCameraX=x;_lightCameraY=y;_lightCameraScale=scale;
            if(_native==null)return;
            ApplySceneLightsLocked();
            _worldLightSubmissions.Submit(_worldLights.Compose(x,y,scale),x,y,scale,ray,immediate);
        }
    }
}
