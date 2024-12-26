import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * CoverageAABBCollider 类
 *
 * 基于轴对齐边界框（AABB）的碰撞检测器。
 * 继承自 AABBCollider 类，重写碰撞检测逻辑，计算重叠区域的中心点和覆盖率。
 * 
 * 功能概述：
 * 1. 通过 AABB 碰撞检测逻辑，精确计算两个碰撞器之间的重叠区域及覆盖率。
 * 2. 提供静态工厂方法，从透明子弹、普通子弹或单位区域动态实例化碰撞器。
 * 3. 适用于需要检测碰撞覆盖率的高级碰撞检测场景，如命中率、伤害计算等。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.CoverageAABBCollider 
    extends AABBCollider implements ICollider {

    /**
     * 用于coverageaabb碰撞器的碰撞结果，缓存避免频繁创建
     */
    public static var result:CollisionResult = CollisionResult.Create(true, new Vector(0,0) ,0);
    /**
     * 构造函数
     * 
     * @param left   左边界坐标
     * @param right  右边界坐标
     * @param top    上边界坐标
     * @param bottom 下边界坐标
     */
    public function CoverageAABBCollider(left:Number, right:Number, top:Number, bottom:Number) {
        super(left, right, top, bottom);
    }

    /**
     * 重写 checkCollision 方法。
     * 
     * 计算两个碰撞器的重叠区域、覆盖率和中心点。
     * 
     * 实现流程：
     * 1. 判断两个 AABB 是否相交，提前返回非碰撞结果。
     * 2. 计算重叠区域的边界坐标。
     * 3. 基于重叠区域面积与当前碰撞器的总面积，计算覆盖率。
     * 4. 计算重叠区域的中心点。
     * 
     * 检测边缘情况：边缘接触视作不碰撞，因为此时覆盖率为0
     * 
     * @param other   另一个 ICollider 实例
     * @param zOffset 碰撞体之间的 Z 轴差值，用于模拟 3D 高度差
     * @return CollisionResult 碰撞结果对象，包含碰撞标识、覆盖率及中心点
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        // 提前声明并初始化本地变量
        // 获取 other 的 AABB 并存储到本地变量中

        var otherAABB:AABB = other.getAABB(zOffset);

        // 优化：提前返回不碰撞的情况，减少计算量
        // 提前声明并初始化 this 的相关属性到本地变量中

        var myRight:Number = this.right;
        var otherLeft:Number = otherAABB.left;
        if (myRight <= otherLeft) return CollisionResult.ORDERFALSE;

        var myLeft:Number = this.left;
        var otherRight:Number = otherAABB.right;
        if (myLeft >= otherRight) return CollisionResult.FALSE;

        var myBottom:Number = this.bottom;
        var otherTop:Number = otherAABB.top;
        if (myBottom <= otherTop) return CollisionResult.FALSE;

        var myTop:Number = this.top;
        var otherBottom:Number = otherAABB.bottom;
        if (myTop >= otherBottom) return CollisionResult.FALSE;

        // 计算重叠区域边界
        var overlapLeft:Number = myLeft > otherLeft ? myLeft : otherLeft;
        var overlapRight:Number = myRight < otherRight ? myRight : otherRight;
        var overlapTop:Number = myTop > otherTop ? myTop : otherTop;
        var overlapBottom:Number = myBottom < otherBottom ? myBottom : otherBottom;

        // 创建碰撞结果对象
        var result:CollisionResult = CoverageAABBCollider.result;

        // 计算覆盖率
        result.overlapRatio = ((overlapRight - overlapLeft) * (overlapBottom - overlapTop)) / ((myRight - myLeft) * (myBottom - myTop));
        var center:Vector = result.overlapCenter;
        center.x = (overlapLeft + overlapRight) >> 1;
        center.y = (overlapTop + overlapBottom) >> 1;

        return result;
    }
}
