// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle.as

import org.flashNight.sara.util.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;

/**
 * 子弹生命周期基类
 * 封装子弹公共生命周期逻辑，如初始化附加伤害、伤害管理器及帧事件处理器绑定
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle implements ILifecycle {

    public function BulletLifecycle() {
    }

    /**
     * 绑定子弹生命周期逻辑
     *
     * 统一的子弹初始化流程，确保所有子弹类型都具备完整的生命周期管理能力：
     * 1. 联弹检测与碰撞器工厂获取：利用位掩码技术快速识别子弹类型
     * 2. 碰撞器绑定：根据子弹类型选择专用的碰撞检测策略
     * 3. 伤害系统初始化：配置附加伤害和伤害管理器
     * 4. 帧处理器绑定：建立每帧更新的生命周期逻辑
     * 5. 安全销毁绑定：重写removeMovieClip确保碰撞器正确回收
     *
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindLifecycle(target:MovieClip):Void {
        // === 第1步：联弹检测与碰撞器工厂获取 ===
        // ChainDetector 内部使用位掩码技术进行高效的联弹类型检测
        var factory:IColliderFactory = ChainDetector.processChainDetection(target);

        // === 第2步：绑定专用碰撞检测器 ===
        // 委托给子类实现，支持不同子弹类型的特化碰撞逻辑
        this.bindCollider(target, factory);

        // === 第3步：初始化伤害系统组件 ===
        target.additionalEffectDamage = 0;  // 重置附加效果伤害计数器
        target.damageManager = DamageManagerFactory.Basic.getDamageManager(target);  // 创建伤害管理器实例

        // === 第4步：绑定帧事件处理器 ===
        // 建立每帧更新机制，支持子弹的运动、碰撞检测和生命周期管理
        this.bindFrameHandler(target);

        // === 第5步：绑定安全销毁机制 ===
        // 重写removeMovieClip，确保碰撞器在子弹销毁时正确回收到对象池
        // 解决问题：消失动画期间碰撞器被提前回收导致的AABB污染
        this.bindSafeRemove(target);
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
     * 绑定帧事件处理器
     * 
     * 建立子弹的每帧更新机制，负责子弹的运动、碰撞检测和状态管理。
     * 使用优化的函数工厂模式消除转发开销。
     *
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindFrameHandler(target:MovieClip):Void {
        // === 高度优化的帧处理器绑定策略 ===
        // 
        // 非透明子弹专用的优化处理器
        // • 分支消除：在创建时生成特化函数，避免每帧重复判断
        // • 仅检测 area 属性决定是否进入执行段
        // • 性能提升：消除运行时的类型检测开销
        target.onEnterFrame = BulletQueueProcessor.createNormalPreCheck(target);
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

    /**
     * 绑定安全销毁机制
     *
     * 重写子弹的removeMovieClip方法，确保碰撞器在子弹真正销毁时才回收。
     * 这解决了消失动画播放期间碰撞器被提前回收导致的AABB污染问题。
     *
     * 设计说明：
     * - MovieClip子弹：保存原始removeMovieClip，在回收碰撞器后调用原始方法
     * - 透明子弹(Object)：安装removeMovieClip方法使其行为与MovieClip一致
     * - 统一出口：无论从何种路径销毁子弹，碰撞器都能正确回收
     *
     * @param target 要绑定的子弹对象
     */
    public function bindSafeRemove(target):Void {
        // 使用位掩码检测透明子弹类型
        // FLAG_TRANSPARENCY = 1 << 3 = 8，标识透明子弹（浅拷贝创建的Object）
        #include "../macros/FLAG_TRANSPARENCY.as"
        var isTransparent:Boolean = (target.flags & FLAG_TRANSPARENCY) != 0;

        if (isTransparent) {
            // === 透明子弹：安装removeMovieClip方法 ===
            // 透明子弹是纯Object，原本没有removeMovieClip
            // 安装此方法使队列处理器的销毁调用对两种类型统一生效
            target.removeMovieClip = function():Void {
                // 回收AABB碰撞器
                var aabb:AABBCollider = this.aabbCollider;
                if (aabb) {
                    aabb.getFactory().releaseCollider(aabb);
                    this.aabbCollider = null;
                }
                // 回收多边形碰撞器（如果存在）
                var poly:ICollider = this.polygonCollider;
                if (poly) {
                    poly.getFactory().releaseCollider(poly);
                    this.polygonCollider = null;
                }
                // 透明子弹无需额外操作，对象会被GC回收
            };
        } else {
            // === MovieClip子弹：重写removeMovieClip ===
            // 保存原始方法引用，在回收碰撞器后调用
            var originalRemove:Function = target.removeMovieClip;
            target.removeMovieClip = function():Void {
                // 回收AABB碰撞器
                var aabb:AABBCollider = this.aabbCollider;
                if (aabb) {
                    aabb.getFactory().releaseCollider(aabb);
                    this.aabbCollider = null;
                }
                // 回收多边形碰撞器（如果存在）
                var poly:ICollider = this.polygonCollider;
                if (poly) {
                    poly.getFactory().releaseCollider(poly);
                    this.polygonCollider = null;
                }
                // 调用原始的removeMovieClip完成MovieClip销毁
                originalRemove.call(this);
            };
        }
    }
}
