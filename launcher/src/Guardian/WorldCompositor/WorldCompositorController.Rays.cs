using System;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed partial class WorldCompositorController
    {
        internal Func<bool,bool> RayCapabilityChanged;
        internal Action RayInvalidated;
        private bool _rayCapabilityAdvertised,_rayHealthy=true;
        private readonly VisualCapabilityRevocation _rayRevocation = new();
        private double _lastRayCapAttemptMs;
        private double _rayCaptureNotReadyMs;
        private void PublishRayCapability(bool ready)
        {
            if(ready) _rayCaptureNotReadyMs=0;
            if(_rayRevocation.Pending) return;
            if(!ready || !_rayHealthy || _rayCapabilityAdvertised || _native==null
                || RayCapabilityChanged==null || NowMs()-_lastRayCapAttemptMs<500)return;
            _lastRayCapAttemptMs=NowMs();
            lock(_weatherCameraLock) _rayCapabilityAdvertised=true;
            bool sent=false;
            try { sent=RayCapabilityChanged(true); }
            catch(Exception error) { LogManager.Log("event=ray_visual_cap_failed "+error.Message); }
            if(!sent) RevokeRayCapability("cap_send_failed");
        }
        internal void ObserveRayFrame(RayVisualDrawFrame frame,float x,float y,float scale)
        {
            Exception failure=null;
            lock(_weatherCameraLock) {
                if(!_rayCapabilityAdvertised || _native==null)return;
                try {
                    _native.RayFrame(frame,x,y,scale);
                    _worldLights.SetRays(frame);
                    SubmitWorldLightsLocked(x,y,scale,ray:true);
                }
                catch(Exception error) { failure=error;LogManager.Log("event=ray_visual_native_failed "+error.Message); }
            }
            if(failure!=null) ProjectileRenderFault("ray_native_frame_failed",failure);
        }
        internal void ClearRayFrame()
        {
            lock(_weatherCameraLock) {
                _worldLights.ClearRays();
                try {
                    _native?.ClearRayFrame();
                    SubmitWorldLightsLocked(_lightCameraX,_lightCameraY,_lightCameraScale,ray:true,immediate:true);
                }
                catch(Exception error) { LogManager.Log("event=ray_visual_clear_failed "+error.Message); }
            }
        }
        internal void RejectRayFrame() { _rayHealthy=false;ProjectileRenderFault("ray_frame_rejected",null); }
        internal void RayConnectionLost() { RevokeRayCapability("socket_disconnected");_rayRevocation.Reset();_rayHealthy=true; }
        private void RetryRayRevocation()
        {
            try { _rayRevocation.TrySend(NowMs(), () => RayCapabilityChanged?.Invoke(false) == true); }
            catch(Exception error) { LogManager.Log("event=ray_visual_revoke_retry_failed "+error.Message); }
        }
        private void NoteRayCaptureNotReady(string reason)
        {
            if(!_rayCapabilityAdvertised){_rayCaptureNotReadyMs=0;return;}
            double now=NowMs();
            if(_rayCaptureNotReadyMs==0){
                _rayCaptureNotReadyMs=now;
                LogManager.Log("event=ray_visual_capture_wait reason="+reason);
            }
        }
        private void RevokeRayCapability(string reason)
        {
            bool advertised;
            lock(_weatherCameraLock) { advertised=_rayCapabilityAdvertised;_rayCapabilityAdvertised=false; }
            ClearRayFrame();
            if(!advertised)return;
            RayInvalidated?.Invoke();
            _rayRevocation.Request();
            RetryRayRevocation();
            LogManager.Log("event=ray_visual_cap_revoke reason="+reason);
        }
    }
}
