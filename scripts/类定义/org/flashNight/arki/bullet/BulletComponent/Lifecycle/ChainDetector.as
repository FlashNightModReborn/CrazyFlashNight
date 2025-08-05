import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.ILifecycle;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.ChainDetector {
    /**
     * 处理目标的联弹检测逻辑，封装判断和碰撞器获取逻辑
     * @param target 子弹实例
     * @return Object {factory:IColliderFactory}
     */
    public static function processChainDetection(target:MovieClip):Object {
        var result:Object = {};
        #include "../macros/FLAG_CHAIN.as"
        if ((target.flags & FLAG_CHAIN) != 0) {
            var chainResult:Object = createChainCollider(target);
            result.factory = chainResult.factory;
            if (chainResult.collider) {
                target.polygonCollider = chainResult.collider;
            }
        } else {
            result.factory = ColliderFactoryRegistry.getFactory(
                ColliderFactoryRegistry.AABBFactory
            );
        }
        return result;
    }
    
    /**
     * 创建联弹检测专用碰撞器
     * @param target 子弹实例
     * @return Object {factory:IColliderFactory, collider:ICollider}
     */
    public static function createChainCollider(target:MovieClip):Object {
        var result:Object = {};
    
        if ((target._rotation % 180) != 0) {
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
