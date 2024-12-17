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
     * @param other   另一个 ICollider 实例
     * @param zOffset 碰撞体之间的 Z 轴差值，用于模拟 3D 高度差
     * @return CollisionResult 碰撞结果对象，包含碰撞标识、覆盖率及中心点
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);

        // 提前检查不相交的情况，提高性能
        if (this.right <= otherAABB.left)  return CollisionResult.FALSE;
        if (this.left >= otherAABB.right)  return CollisionResult.FALSE;
        if (this.bottom <= otherAABB.top)  return CollisionResult.FALSE;
        if (this.top >= otherAABB.bottom)  return CollisionResult.FALSE;

        // 计算重叠区域边界
        var overlapLeft:Number = Math.max(this.left, otherAABB.left);
        var overlapRight:Number = Math.min(this.right, otherAABB.right);
        var overlapTop:Number = Math.max(this.top, otherAABB.top);
        var overlapBottom:Number = Math.min(this.bottom, otherAABB.bottom);

        // 当前碰撞器的总面积
        var currentWidth:Number = this.right - this.left;
        var currentHeight:Number = this.bottom - this.top;

        // 创建碰撞结果对象
        var result:CollisionResult = new CollisionResult(true);

        // 计算覆盖率
        result.overlapRatio = ((overlapRight - overlapLeft) * (overlapBottom - overlapTop)) / (currentWidth * currentHeight);

        // 计算重叠区域的中心点
        result.overlapCenter = new Vector(
            (overlapLeft + overlapRight) >> 1,
            (overlapTop + overlapBottom) >> 1
        );
        return result;
    }

    /**
     * 静态方法：从透明子弹实例化 CoverageAABBCollider。
     *
     * @param bullet 透明子弹对象，包含坐标信息
     * @return CoverageAABBCollider 实例
     */
    public static function fromTransparentBullet(bullet:Object):CoverageAABBCollider {
        var collider:CoverageAABBCollider = new CoverageAABBCollider(0, 0, 0, 0);
        collider.updateFromTransparentBullet(bullet);
        return collider;
    }

    /**
     * 静态方法：从普通子弹和检测区域实例化 CoverageAABBCollider。
     *
     * @param bullet        子弹的 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     * @return CoverageAABBCollider 实例
     */
    public static function fromBullet(bullet:MovieClip, detectionArea:MovieClip):CoverageAABBCollider {
        var collider:CoverageAABBCollider = new CoverageAABBCollider(0, 0, 0, 0);
        collider.updateFromBullet(bullet, detectionArea);
        return collider;
    }

    /**
     * 静态方法：从单位区域实例化 CoverageAABBCollider。
     *
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return CoverageAABBCollider 实例
     */
    public static function fromUnitArea(unit:MovieClip):CoverageAABBCollider {
        var collider:CoverageAABBCollider = new CoverageAABBCollider(0, 0, 0, 0);
        collider.updateFromUnitArea(unit);
        return collider;
    }
}
