import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.ILifecycle;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;

// 文件路径：org.flashNight.arki.bullet.BulletComponent.ChainDetector.as
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.ChainDetector {
    /**
     * 创建联弹检测专用碰撞器
     * @param target 子弹实例
     * @return Object {factory:IColliderFactory, collider:ICollider} 
     */
    public static function createChainCollider(target:MovieClip):Object {
        var bulletRotation:Number = target._rotation;
        var isRotated:Boolean = (bulletRotation != 0 && bulletRotation != 180);
        var result:Object = {};

        if (isRotated) {
            result.factory = ColliderFactoryRegistry.getFactory(
                ColliderFactoryRegistry.AABBFactory
            );
            result.collider = ColliderFactoryRegistry.getFactory(
                ColliderFactoryRegistry.PolygonFactory
            ).createFromBullet(target);
        } else {
            result.factory = ColliderFactoryRegistry.getFactory(
                ColliderFactoryRegistry.CoverageAABBFactory
            );
        }
        
        return result;
    }
}
