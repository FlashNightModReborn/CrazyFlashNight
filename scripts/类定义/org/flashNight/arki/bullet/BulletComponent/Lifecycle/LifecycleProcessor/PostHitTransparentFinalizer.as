/**
 * File: org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor/PostHitTransparentFinalizer.as
 */
 
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.PostHitTransparentFinalizer implements IPostHitFinalizer{
    public static var instance:PostHitTransparentFinalizer = new PostHitTransparentFinalizer();
    /**
     * 无需进行穿刺判定
     */
    public function preProcess(target:MovieClip, shooter:MovieClip, hitCount:Number):Boolean {
        if (hitCount > 0) return false;
        processPiercing(target);
        return true;
    }
}
