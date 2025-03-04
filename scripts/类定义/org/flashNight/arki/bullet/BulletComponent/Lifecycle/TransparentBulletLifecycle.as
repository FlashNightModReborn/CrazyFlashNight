// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.TransparentBulletLifecycle.as

import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;

/**
 * 透明子弹生命周期管理器
 * 特化处理穿透性/瞬时子弹的生命周期逻辑，子弹触发后立即销毁
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.TransparentBulletLifecycle implements ILifecycle {
    
    /** 静态实例 - 默认透明子弹生命周期管理器 */
    public static var BASIC:TransparentBulletLifecycle = new TransparentBulletLifecycle();

    /** 联弹碰撞检测器生成器 */
    private var chainDetector:Function = ChainDetector.createChainCollider;

    /**
     * 默认构造函数
     * 初始化无参数的透明子弹生命周期管理器
     */
    public function TransparentBulletLifecycle() {
    }

    /**
     * 立即销毁判定
     * 透明子弹在触发检测后立即销毁，始终返回true
     * 
     * @param target:MovieClip 要检测的子弹对象
     * @return Boolean 恒为true（立即销毁）
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        return true; // 透明子弹触即毁
    }

    /**
     * 绑定子弹生命周期逻辑
     * 执行以下核心操作：
     * 1. 根据配置创建碰撞检测器（支持联弹检测）
     * 2. 初始化伤害管理器
     * 3. 绑定帧事件处理器
     * 
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindLifecycle(target:MovieClip):Void {
        var factory:IColliderFactory;
        var areaAABB:ICollider;

        // 联弹子弹检测模块
        if (target.联弹检测) {
            var chainResult:Object = this.chainDetector(target);
            factory = chainResult.factory;
            if (chainResult.collider) {
                target.polygonCollider = chainResult.collider;
            }
        } else {
            // 默认使用AABB碰撞工厂
            factory = ColliderFactoryRegistry.getFactory(
                ColliderFactoryRegistry.AABBFactory
            );
        }

        // 碰撞区域创建逻辑
        if (target.子弹区域area) {
            // 使用自定义子弹区域
            areaAABB = factory.createFromBullet(target, target.子弹区域area);
        } else {
            // 使用透明子弹默认区域
            areaAABB = factory.createFromTransparentBullet(target);
        }

        // 组件绑定
        target.aabbCollider = areaAABB;          // 碰撞检测器
        target.additionalEffectDamage = 0;       // 附加效果伤害初始化
        target.damageManager = DamageManagerFactory.Basic.getDamageManager(target); // 伤害管理器

        // 绑定全局子弹生命周期处理器
        _root.子弹生命周期.call(target);
    }
}
