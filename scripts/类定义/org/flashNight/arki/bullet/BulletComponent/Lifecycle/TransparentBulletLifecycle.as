// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.TransparentBulletLifecycle.as

import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;

/**
 * 透明子弹生命周期管理器
 * 继承自BulletLifecycle，专门处理穿透性/瞬时子弹的生命周期逻辑
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.TransparentBulletLifecycle extends BulletLifecycle implements ILifecycle {

    /** 静态实例 - 默认透明子弹生命周期管理器 */
    public static var BASIC:TransparentBulletLifecycle = new TransparentBulletLifecycle();

    /**
     * 默认构造函数
     * 初始化无参数的透明子弹生命周期管理器
     */
    public function TransparentBulletLifecycle() {
        super();
    }

    /**
     * 立即销毁判定
     * 透明子弹在触发检测后立即销毁，始终返回true
     * 
     * @param target:MovieClip 要检测的子弹对象
     * @return Boolean 恒为true（立即销毁）
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        return true;
    }

    /**
     * 绑定碰撞检测器
     * 透明子弹根据是否存在子弹区域决定使用不同的创建方法
     * 
     * @param target:MovieClip 要绑定的子弹对象
     * @param factory:IColliderFactory 碰撞检测器工厂
     */
    public function bindCollider(target:MovieClip, factory:IColliderFactory):Void {
        if(target.子弹区域area) {
            target.aabbCollider = factory.createFromBullet(target, target.子弹区域area);
        }
        else {
            target.aabbCollider = factory.createFromTransparentBullet(target);
        }
    }

    /**
     * 重写帧事件处理器绑定
     * 透明子弹在触发后立即调用全局子弹生命周期处理器
     *
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindFrameHandler(target:MovieClip):Void {
        BulletQueueProcessor.preCheck(target)
        // getDynamicFrameHandler(target).call(target);
    }
}
