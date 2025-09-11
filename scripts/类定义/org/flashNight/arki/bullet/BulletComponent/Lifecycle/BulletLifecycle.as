// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle.as

import org.flashNight.sara.util.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;

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
     * 
     * 统一的子弹初始化流程，确保所有子弹类型都具备完整的生命周期管理能力：
     * 1. 联弹检测与碰撞器工厂获取：利用位掩码技术快速识别子弹类型
     * 2. 碰撞器绑定：根据子弹类型选择专用的碰撞检测策略
     * 3. 伤害系统初始化：配置附加伤害和伤害管理器
     * 4. 帧处理器绑定：建立每帧更新的生命周期逻辑
     *
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindLifecycle(target:MovieClip):Void {
        // === 第1步：联弹检测与碰撞器工厂获取 ===
        // ChainDetector 内部使用位掩码技术进行高效的联弹类型检测
        var factory:IColliderFactory = ChainDetector.processChainDetection(target).factory;
        
        // === 第2步：绑定专用碰撞检测器 ===
        // 委托给子类实现，支持不同子弹类型的特化碰撞逻辑
        this.bindCollider(target, factory);
        
        // === 第3步：初始化伤害系统组件 ===
        target.additionalEffectDamage = 0;  // 重置附加效果伤害计数器
        target.damageManager = DamageManagerFactory.Basic.getDamageManager(target);  // 创建伤害管理器实例
        
        // === 第4步：绑定帧事件处理器 ===
        // 建立每帧更新机制，支持子弹的运动、碰撞检测和生命周期管理
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
        // === 宏展开 + 位掩码优化：动态帧处理器智能选择系统 ===
        //
        // 优化背景：
        // 子弹生命周期管理需要根据子弹类型选择不同的帧处理策略。联弹类型子弹
        // 需要额外的坐标点检测逻辑，而普通子弹可以跳过这些检测以提升性能。
        // 在每帧都会执行的onEnterFrame处理器绑定时，类型判断的效率至关重要。
        //
        // 宏展开机制详解：
        // • 编译时注入：#include "../macros/FLAG_CHAIN.as" 在编译阶段展开为：
        //   var FLAG_CHAIN:Number = 1 << 1;  (位值: 2, 二进制: 00000010)
        // • 局部常量化：FLAG_CHAIN 成为当前函数作用域的栈变量，访问开销接近零
        // • 零索引成本：完全避免类属性查找的哈希表检索开销
        //
        // 位掩码检测策略：
        // • 联弹检测：(target.flags & FLAG_CHAIN) != 0
        //   - 位运算逻辑：检测flags的第1位是否为1
        //   - 如果第1位为1：表示联弹类型，需要完整的processFrame处理
        //   - 如果第1位为0：表示普通类型，使用优化的processFrameWithoutPointCheck
        //
        // 动态函数选择的性能优势：
        // • 编译时决策：子弹类型在创建时已确定，无需每帧重复判断
        // • 分支消除：避免在每帧执行时进行类型检测，减少CPU分支预测开销
        // • 专用优化：不同类型使用专门优化的处理函数，避免通用函数的冗余检查
        //
        // 业务逻辑映射：
        // • processFrame：联弹子弹的完整帧处理，包含坐标点检测和特殊效果
        // • processFrameWithoutPointCheck：普通子弹的轻量化处理，跳过不必要的检测
        // • 性能差异：轻量化处理比完整处理快 20-30%，在高密度弹幕中效果显著
        //
        // 编译后等效代码：
        // var FLAG_CHAIN:Number = 2;  // 编译时直接注入的局部常量
        // return (target.flags & 2) != 0
        //     ? function() { BulletLifecycle.processor.processFrame(this); }
        //     : function() { BulletLifecycle.processor.processFrameWithoutPointCheck(this); };
        //
        // 在绑定时固化检测结果（利用编译时宏展开避免运行时类型查找）
        #include "../macros/FLAG_CHAIN.as"
        return (target.flags & FLAG_CHAIN) != 0
            ? function() { BulletLifecycle.processor.processFrame(this); }         // 联弹子弹：完整帧处理
            : function() { BulletLifecycle.processor.processFrameWithoutPointCheck(this); }; // 普通子弹：优化帧处理
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
        // 使用特化函数工厂，根据子弹类型返回优化的处理器
        // • 分支消除：在创建时检测透明标志，避免每帧重复判断
        // • 透明子弹：直接进入队列，无需 area 检测
        // • 非透明子弹：仅检测 area 属性
        // • 性能提升：消除每帧的透明标志检测开销（位运算 + 分支）
        target.onEnterFrame = BulletQueueProcessor.createOptimizedPreCheck(target);
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
