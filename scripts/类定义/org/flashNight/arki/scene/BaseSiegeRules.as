/** Only explicit relay operation and existing battle completion gate the exterior. */
class org.flashNight.arki.scene.BaseSiegeRules {
    public static function canDeploy(explained:Boolean,deployed:Boolean,near:Boolean,
            alive:Boolean,paused:Boolean,ready:Boolean):Boolean {
        return explained && !deployed && near && alive && !paused && ready;
    }
    public static function canClearRelay(deployed:Boolean,guardReady:Boolean,
            wavesFinished:Boolean,guardAlive:Boolean):Boolean {
        return deployed && guardReady && wavesFinished && guardAlive;
    }
}
