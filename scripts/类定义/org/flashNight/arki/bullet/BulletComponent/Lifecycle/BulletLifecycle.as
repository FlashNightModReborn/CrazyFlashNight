// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle.as

import org.flashNight.sara.util.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;

/**
 * 子弹生命周期基类
 * 封装子弹公共生命周期逻辑，如初始化附加伤害、伤害管理器及帧事件处理器绑定
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle implements ILifecycle {

    /** 坐标转换临时对象（优化GC） */
    private static var point:Vector = new Vector(null, null);
    private static var processor:BulletLifecycleProcessor = new BulletLifecycleProcessor();


    public function BulletLifecycle() {
    }

    /**
     * 绑定子弹生命周期逻辑
     * 统一执行以下操作：
     * 1. 通过ChainDetector处理联弹检测，获取碰撞器工厂
     * 2. 调用子类实现的bindCollider绑定具体的碰撞器
     * 3. 初始化附加伤害和伤害管理器
     * 4. 绑定帧事件处理器
     *
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindLifecycle(target:MovieClip):Void {
        // 使用ChainDetector统一处理联弹检测逻辑
        var factory:IColliderFactory = ChainDetector.processChainDetection(target).factory;
        // 绑定碰撞检测器，由子类具体实现
        this.bindCollider(target, factory);
        // 初始化附加伤害和伤害管理器
        target.additionalEffectDamage = 0;
        target.damageManager = DamageManagerFactory.Basic.getDamageManager(target);
        // 绑定帧事件处理器（默认采用onEnterFrame绑定）
        this.bindFrameHandler(target);
    }

    /**
     * 绑定碰撞检测器
     * 由子类重写，实现各自的碰撞器创建逻辑
     *
     * @param target:MovieClip 要绑定的子弹对象
     * @param factory:IColliderFactory 碰撞检测器工厂
     */
    public function bindCollider(target:MovieClip, factory:IColliderFactory):Void {
        // 默认不实现，由子类重写
    }

    /**
     * 获取动态帧处理器
     * 根据联弹检测状态返回对应的处理函数
     * 
     * @param target:MovieClip 子弹对象
     * @return Function 绑定到onEnterFrame的处理函数
     */
    private function getDynamicFrameHandler(target:MovieClip):Function {
        // 在绑定时固化检测结果（假设此时状态已确定）
        #include "../macros/FLAG_CHAIN.as"
        return (target.flags & FLAG_CHAIN) != 0
            ? function() { BulletLifecycle.processor.processFrame(this); }
            : function() { BulletLifecycle.processor.processFrameWithoutPointCheck(this); };
    }


    /**
     * 绑定帧事件处理器
     * 默认实现为将全局子弹生命周期处理器赋值给target.onEnterFrame
     *
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindFrameHandler(target:MovieClip):Void {
        // target.onEnterFrame = getDynamicFrameHandler(target)
        target.onEnterFrame = _root.子弹生命周期;
    }

    /**
     * 子弹销毁判定，默认实现返回false
     * 子类可以根据需要重写该方法
     *
     * @param target:MovieClip 要检测的子弹对象
     * @return Boolean 默认不销毁
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        return false;
    }
}
