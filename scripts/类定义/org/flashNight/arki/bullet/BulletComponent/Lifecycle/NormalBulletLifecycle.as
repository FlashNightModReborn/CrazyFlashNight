// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.NormalBulletLifecycle.as

import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;

/**
 * 普通子弹生命周期管理器
 * 实现子弹的存活判定、碰撞检测和生命周期绑定逻辑
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.NormalBulletLifecycle
extends TransparentBulletLifecycle 
implements ILifecycle {
    
    /** 静态实例 - 默认射程900像素的基础子弹生命周期管理器 */
    public static var BASIC:NormalBulletLifecycle = new NormalBulletLifecycle(900);

    /** 射程阈值（像素） */
    private var rangeThreshold:Number;
    
    /** 坐标转换临时对象（优化GC） */
    private static var point:Vector = new Vector(null, null);

    /**
     * 构造函数
     * @param rangeThreshold:Number 子弹的最大有效射程（像素）
     */
    public function NormalBulletLifecycle(rangeThreshold:Number) {
        this.rangeThreshold = rangeThreshold;
    }

    /**
     * 子弹销毁判定逻辑
     * 满足以下任一条件时销毁子弹：
     * 1. 超出射程范围（非远距离子弹）
     * 2. 与地图发生碰撞
     * 
     * @param target:MovieClip 要检测的子弹对象
     * @return Boolean 是否需要销毁子弹
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        // 获取发射者对象
        var shooter:MovieClip = _root.gameworld[target.发射者名];
        
        // 发射者不存在时不销毁（异常情况处理）
        if (shooter == undefined) return false;

        // 射程判定逻辑：
        // 1. 非远距离子弹才进行射程检测
        // 2. X或Y轴方向距离超过阈值则判定为超范围

        var dx:Number = shooter._x - target._x;
        var dy:Number = shooter._y - shooter._y;
        var rangeThreshold:Number = this.rangeThreshold;
        var isOutOfRange:Boolean = !target.远距离不消失 &&
            (dx > rangeThreshold || dx < -rangeThreshold ||
            dy > rangeThreshold || dy < -rangeThreshold);

        // 如果超出视觉距离，地图碰撞检测所影响到的碰撞特效或许也可以省略以节约性能开销
        if(isOutOfRange) return true;
        // 地图碰撞检测
        var isCollidedWithMap:Boolean = this.checkMapCollision(target);
        
        // 标记地图碰撞状态
        if (isCollidedWithMap) {
            target.击中地图 = true;
        }

        return isCollidedWithMap;
    }

    /**
     * 绑定子弹生命周期逻辑
     * 执行以下核心操作：
     * 1. 创建碰撞检测器（支持联弹检测）
     * 2. 初始化伤害管理器
     * 3. 绑定帧事件处理器
     * 
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindLifecycle(target:MovieClip):Void {
        var factory:IColliderFactory;

        // 使用ChainDetector统一处理联弹检测逻辑
        var chainResult:Object = ChainDetector.processChainDetection(target);
        factory = chainResult.factory;

        // 绑定碰撞检测器
        target.aabbCollider = factory.createFromBullet(target, target.area);
        
        // 初始化附加伤害值
        target.additionalEffectDamage = 0;

        // 配置伤害管理器
        target.damageManager = DamageManagerFactory.Basic.getDamageManager(target);

        // 绑定帧事件处理器
        // _root.子弹生命周期.call(target);
        target.onEnterFrame = _root.子弹生命周期;
    }

    /**
     * 地图碰撞检测实现
     * 检测逻辑包含：
     * 1. 超出地图边界检测
     * 2. Z轴坐标有效性检测
     * 3. 像素级精确碰撞检测
     * 
     * @param target:MovieClip 要检测的子弹对象
     * @return Boolean 是否发生地图碰撞
     */
    private function checkMapCollision(target:MovieClip):Boolean {
        var gameWorld:Object = _root.gameworld;
        var Z轴坐标:Number = target.Z轴坐标;

        // 地图边界检测
        var Xmin:Number = _root.Xmin;
        var Xmax:Number = _root.Xmax;
        var Ymin:Number = _root.Ymin;
        var Ymax:Number = _root.Ymax;

        var targetX:Number = target._x;
        var targetY:Number = target._y;

        // 快速边界检测（优化性能）
        if (targetX < Xmin || targetX > Xmax || Z轴坐标 < Ymin || Z轴坐标 > Ymax) {
            return true;
        } 
        // 非近战子弹的Y轴检测
        else if (targetY > Z轴坐标) {
            return true;
        } 
        // 精确碰撞检测
        else {
            // 转换为全局坐标进行检测
            var localPoint:Object = NormalBulletLifecycle.point;
            localPoint.x = targetX;
            localPoint.y = Z轴坐标;
            gameWorld.localToGlobal(localPoint);
            
            // 执行像素级碰撞检测
            return gameWorld.地图.hitTest(localPoint.x, localPoint.y, true);
        }
    }    
}
