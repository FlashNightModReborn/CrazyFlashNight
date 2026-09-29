namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed partial class WorldCompositorController
    {
        // One owner combines the borrowed F6/F7 outputs. Native receives only the
        // selected sixteen lights; clearing either source retains the other one.
        private readonly WorldLightComposer _worldLights;
        private float _lightCameraX,_lightCameraY,_lightCameraScale=1;

        // All callers hold _weatherCameraLock and submit the borrowed result immediately.
        private void SubmitWorldLightsLocked(float x,float y,float scale)
        {
            _lightCameraX=x;_lightCameraY=y;_lightCameraScale=scale;
            if(_native==null)return;
            _native.CombatFxFrame(_worldLights.Compose(x,y,scale),x,y,scale);
        }
    }
}
