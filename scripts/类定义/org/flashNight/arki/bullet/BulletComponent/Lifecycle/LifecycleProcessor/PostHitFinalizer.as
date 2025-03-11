/**
 * File: org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor/PostHitFinalizer.as
 */
 

import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;


/**
 * 默认实现：直接继承基类，复用所有默认逻辑
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.PostHitFinalizer extends BasePostHitFinalizer  implements IPostHitFinalizer{
    public static var instance:PostHitFinalizer = new PostHitFinalizer();
    public function PostHitFinalizer() {
        super();
    }
    // 如无特殊需求，可不做任何覆盖，直接使用基类的默认实现
}