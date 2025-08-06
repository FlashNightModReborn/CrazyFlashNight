/**
 * File: org/flashNight/arki/bullet/BulletComponent/Lifecycle/LifecycleProcessor/ColliderUpdater.as
 */
 
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.arki.component.Collider.*;    // 碰撞系统

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ColliderUpdater implements IColliderUpdater {
    public static var instance:ColliderUpdater = new ColliderUpdater();
    public function ColliderUpdater() { }
    
    /**
     * 更新子弹的碰撞器
     * @param target 当前子弹实例
     * @return 如果无需后续处理则返回 true，否则返回 false
     */
    public function updateCollider(target:MovieClip):Boolean {
        // 1. 在编译时注入宏，定义局部常量
        #include "../macros/FLAG_TRANSPARENCY.as"

        // 2. 执行一次位运算，并将布尔结果缓存到局部变量中
        //    这个变量名清晰地表达了其意图，提高了代码可读性
        var isTransparent:Boolean = (target.flags & FLAG_TRANSPARENCY) != 0;

        // 3. 在后续逻辑中，直接重用缓存的布尔变量
        if (!target.area && !isTransparent) {
            target.updateMovement(target);
            return true;
        }
        
        var detectionArea:MovieClip;
        var areaAABB:ICollider = target.aabbCollider;

        // 4. 再次重用缓存的变量，无需重复计算
        if (isTransparent && !target.子弹区域area) {
            areaAABB.updateFromTransparentBullet(this);
        } else {
            detectionArea = target.子弹区域area || target.area;
            areaAABB.updateFromBullet(target, detectionArea);
        }
        
        return false; // 返回 false 表示继续后续处理
    }
}
