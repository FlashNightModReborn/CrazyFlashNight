import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * CoverageAABBCollider 类
 * 
 * 继承自 AABBCollider，实现 ICollider 接口，
 * 提供基于轴对齐边界框（AABB）的碰撞检测功能，并计算覆盖率。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.CoverageAABBCollider extends AABBCollider implements ICollider {
    
    /**
     * 构造函数
     * @param left 左边界坐标
     * @param right 右边界坐标
     * @param top 上边界坐标
     * @param bottom 下边界坐标
     */
    public function CoverageAABBCollider(left:Number, right:Number, top:Number, bottom:Number) {
        super(left, right, top, bottom);
    }

    /**
     * 重写 checkCollision 方法
     * 计算覆盖率与更精确的碰撞中心点
     * 
     * @param other 另一个 ICollider 实例
     * @param zOffset 碰撞体之间的Z轴差，用于模拟3D高度
     * @return CollisionResult 实例，包含碰撞结果及相关信息
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);

        // 提前返回检查不相交条件，优化性能
        if (this.right <= otherAABB.left)  return CollisionResult.FALSE;
        if (this.left >= otherAABB.right)  return CollisionResult.FALSE;
        if (this.bottom <= otherAABB.top)  return CollisionResult.FALSE;
        if (this.top >= otherAABB.bottom)  return CollisionResult.FALSE;

        // 基于上述条件判断，如果能走到这里，说明有实际重叠区域
        // 计算当前碰撞器的宽高
        var currentWidth:Number = this.right - this.left;
        var currentHeight:Number = this.bottom - this.top;

        // 计算重叠区域的边界
        var overlapLeft:Number = (this.left > otherAABB.left) ? this.left : otherAABB.left;
        var overlapRight:Number = (this.right < otherAABB.right) ? this.right : otherAABB.right;
        var overlapTop:Number = (this.top > otherAABB.top) ? this.top : otherAABB.top;
        var overlapBottom:Number = (this.bottom < otherAABB.bottom) ? this.bottom : otherAABB.bottom;

        // 创建碰撞结果
        var result:CollisionResult = new CollisionResult(true);

        // 计算覆盖率
        // 因为已确认当前碰撞器有正面积且存在重叠，此时重叠宽高必然 > 0，无需再次判断
        result.overlapRatio = ((overlapRight - overlapLeft) * (overlapBottom - overlapTop)) / (currentWidth * currentHeight);
        result.overlapCenter = new Vector(
            (overlapLeft + overlapRight) >> 1,
            (overlapTop + overlapBottom) >> 1
        );;
        return result;
    }

    // 不需要覆写 剩余接口方法，因为父类 AABBCollider 已经实现了 ICollider 接口的 对应方法。

    /**
     * 从透明子弹实例化 CoverageAABBCollider
     * 
     * @param bullet 透明子弹对象
     * @return CoverageAABBCollider 实例
     */
    public static function fromTransparentBullet(bullet:Object):CoverageAABBCollider {
        var collider:CoverageAABBCollider = new CoverageAABBCollider(null);
        collider.updateFromTransparentBullet(bullet);
        return collider;
    }

    /**
     * 从子弹和检测区域实例化 CoverageAABBCollider
     * 
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     * @return CoverageAABBCollider 实例
     */
    public static function fromBullet(bullet:MovieClip, detectionArea:MovieClip):CoverageAABBCollider {
        var collider:CoverageAABBCollider = new CoverageAABBCollider(null);
        collider.updateFromBullet(bullet, detectionArea);
        return collider;
    }

    /**
     * 从单位区域实例化 CoverageAABBCollider
     * 
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return CoverageAABBCollider 实例
     */
    public static function fromUnitArea(unit:MovieClip):CoverageAABBCollider {
        var collider:CoverageAABBCollider = new CoverageAABBCollider(null);
        collider.updateFromUnitArea(unit);
        return collider;
    }
}
