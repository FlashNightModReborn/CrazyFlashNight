using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed partial class WorldCompositorController
    {
        private readonly SceneLightEngine _sceneLights;
        private SceneLightSnapshot _pendingSceneLightSnapshot;
        private long _pendingSceneLightScene,_sentSceneLightVersion=-1;

        private void QueueSceneLights(WorldLightingFrame frame)
        {
            if(frame.SceneLights==null)return;
            lock(_weatherCameraLock) {
                if(frame.Scene>=_pendingSceneLightScene) {
                    _pendingSceneLightSnapshot=frame.SceneLights;_pendingSceneLightScene=frame.Scene;
                }
            }
        }
        internal void ObserveSceneLightState(SceneLightState state)
        {
            lock(_weatherCameraLock) {
                if(!_sceneLights.Adopt(state))return;
                if(_native!=null)SubmitWorldLightsLocked(_lightCameraX,_lightCameraY,_lightCameraScale);
            }
        }
        internal void ObserveSceneLightClock(int tick,bool paused)
        {
            lock(_weatherCameraLock)_sceneLights.Tick(tick,paused);
        }
        private bool ApplySceneLightsLocked()
        {
            bool changed=false;
            long ready=_lighting.ReadyScene;
            if(ready>0 && _pendingSceneLightSnapshot!=null && ready==_pendingSceneLightScene) {
                _sceneLights.Configure(ready,_pendingSceneLightSnapshot);_pendingSceneLightSnapshot=null;
                changed=true;
                LogManager.Log("event=scene_lights_adopt scene="+ready+" cached="+_sceneLights.CachedCount+" realtime="+_sceneLights.RealtimeCount);
            }
            bool active=ready>0 && ready==_sceneLights.Scene;
            _worldLights.SetSceneLights(active?_sceneLights.Realtime:Array.Empty<WorldLightCandidate>(),active?_sceneLights.RealtimeCount:0);
            long version=active?_sceneLights.StaticVersion:-2;
            if(_native!=null && version!=_sentSceneLightVersion) {
                _native.SceneLightField(active?_sceneLights.Cached:Array.Empty<float>(),active?_sceneLights.CachedCount:0,_sceneLights.MaximumResponse);
                _sentSceneLightVersion=version;
                changed=true;
            }
            return changed;
        }
        private void ResetSceneLights()
        {
            lock(_weatherCameraLock) {
                _sceneLights.Reset();_pendingSceneLightSnapshot=null;_pendingSceneLightScene=0;_sentSceneLightVersion=-1;
                _worldLights.SetSceneLights(Array.Empty<WorldLightCandidate>(),0);
                _native?.SceneLightField(Array.Empty<float>(),0,_sceneLights.MaximumResponse);
            }
        }
    }
}
