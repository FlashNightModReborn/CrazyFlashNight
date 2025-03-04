// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.TransparentBulletLifecycle.as
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.TransparentBulletLifecycle implements ILifecycle {
    // 新增：联弹检测模块引用

    public static var BASIC:TransparentBulletLifecycle = new TransparentBulletLifecycle();

    /**
     * 构造函数
     */
    public function TransparentBulletLifecycle() {
    }

    private var chainDetector:Function = ChainDetector.createChainCollider;
    
    public function shouldDestroy(target:MovieClip):Boolean {
        return true;
    }

    public function bindLifecycle(target:MovieClip):Void {
        var factory:IColliderFactory;
        var areaAABB:ICollider;

        // 组合使用联弹检测模块
        if (target.联弹检测) {
            var chainResult:Object = this.chainDetector(target);
            factory = chainResult.factory;
            if (chainResult.collider) {
                target.polygonCollider = chainResult.collider;
            }
        } else {
            factory = ColliderFactoryRegistry.getFactory(
                ColliderFactoryRegistry.AABBFactory
            );
        }

        // 碰撞区域创建逻辑
        if (target.子弹区域area) {
            areaAABB = factory.createFromBullet(target, target.子弹区域area);
        } else {
            areaAABB = factory.createFromTransparentBullet(target);
        }

        // 组件绑定
        target.aabbCollider = areaAABB;
        target.additionalEffectDamage = 0;
        target.damageManager = DamageManagerFactory.Basic.getDamageManager(target);
        
        _root.子弹生命周期.call(target);
    }
}
