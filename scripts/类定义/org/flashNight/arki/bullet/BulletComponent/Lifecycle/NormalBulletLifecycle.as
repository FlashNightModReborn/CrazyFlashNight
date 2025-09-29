// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.NormalBulletLifecycle.as

import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;

/**
 * 普通子弹生命周期管理器
 * 继承自BulletLifecycle，封装普通子弹的生命周期逻辑
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.NormalBulletLifecycle extends BulletLifecycle implements ILifecycle {
    
    /** 静态实例 - 默认射程900像素的基础子弹生命周期管理器 */
    public static var BASIC:NormalBulletLifecycle = new NormalBulletLifecycle(900);

    /** 射程阈值（像素） */
    private var rangeThreshold:Number;

    /**
     * 构造函数
     * @param rangeThreshold:Number 子弹的最大有效射程（像素）
     */
    public function NormalBulletLifecycle(rangeThreshold:Number) {
        super();
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
        //  发射者不存在：只做地图碰撞检测
        if (shooter == undefined) {
            var hitOnly:Boolean = this.checkMapCollision(target);
            if (hitOnly) target.击中地图 = true;
            return hitOnly;
        }

        // 射程判定逻辑：仅对需要进行射程检测的子弹进行判断
        // 当子弹类型不具备“远距离不消失”的特性时，检查其水平和垂直位移是否超过预设的射程阈值

        // 计算子弹从发射位置到当前的位置在水平方向上的位移
        var dx:Number = target.shootX - target._x;
        // 计算子弹从发射位置到当前的位置在垂直方向上的位移
        var dy:Number = target.shootY - target._y; 

        // 判断：如果目标不是“远距离不消失”类型，并且水平方向或垂直方向上的位移超出了射程阈值
        // 这里使用位运算:
        //    (dx > rangeThreshold ^ dx < -rangeThreshold)
        //      通过异或运算，确保 dx 超出正阈值或者小于负阈值时返回 true（因为两者不可能同时为真）
        //    (dy > rangeThreshold ^ dy < -rangeThreshold)
        //      同理判断 dy 是否超出正负射程阈值
        // 使用按位或 | 将两个方向的判断结果合并，只要有一个方向超出射程阈值就返回 true
        if (!target.远距离不消失 && 
            ((dx > rangeThreshold ^ dx < -rangeThreshold) | 
            (dy > rangeThreshold ^ dy < -rangeThreshold))) {
            return true;
        }

        // 地图碰撞检测
        var isCollidedWithMap:Boolean = this.checkMapCollision(target);
        // 标记地图碰撞状态
        if (isCollidedWithMap) {
            target.击中地图 = true;
        }
        return isCollidedWithMap;
    }

    /**
     * 绑定碰撞检测器
     * 普通子弹采用 factory.createFromBullet 方法
     * 
     * @param target:MovieClip 要绑定的子弹对象
     * @param factory:IColliderFactory 碰撞检测器工厂
     */
    public function bindCollider(target:MovieClip, factory:IColliderFactory):Void {
        target.aabbCollider = factory.createFromBullet(target, target.area);
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
        var Z轴坐标:Number = target.Z轴坐标;

        // 非近战子弹的Y轴检测
        if (target._y > Z轴坐标) {
            return true;
        } 
        // 精确碰撞检测
        else {
            return _root.collisionLayer.hitTest(target._x, Z轴坐标, true);
        }
    }    
}
