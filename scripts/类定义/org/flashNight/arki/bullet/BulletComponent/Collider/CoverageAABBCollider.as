import org.flashNight.arki.bullet.BulletComponent.Collider.*;
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
        // 获取对方的 AABB 信息，并应用 zOffset
        var otherAABB:AABB = other.getAABB(zOffset);

        // 检查不相交的条件，并提前返回
        if (this.right <= otherAABB.left) {
            return CollisionResult.FALSE; // 提前返回
        }
        if (this.left >= otherAABB.right) {
            return CollisionResult.FALSE; // 提前返回
        }
        if (this.bottom <= otherAABB.top) {
            return CollisionResult.FALSE; // 提前返回
        }
        if (this.top >= otherAABB.bottom) {
            return CollisionResult.FALSE; // 提前返回
        }

        // 计算重叠区域的边界
        var overlapLeft:Number = (this.left > otherAABB.left) ? this.left : otherAABB.left;
        var overlapRight:Number = (this.right < otherAABB.right) ? this.right : otherAABB.right;
        var overlapTop:Number = (this.top > otherAABB.top) ? this.top : otherAABB.top;
        var overlapBottom:Number = (this.bottom < otherAABB.bottom) ? this.bottom : otherAABB.bottom;

        // 计算重叠面积
        var overlappingWidth:Number = overlapRight - overlapLeft;
        var overlappingHeight:Number = overlapBottom - overlapTop;
        var overlappingArea:Number = overlappingWidth * overlappingHeight;

        // 计算当前碰撞器的总面积
        var currentArea:Number = (this.right - this.left) * (this.bottom - this.top);

        // 计算覆盖率，确保当前面积不为零
        var overlapRatio:Number = (currentArea > 0) ? (overlappingArea / currentArea) : 0;

        // 计算碰撞中心点，使用位运算优化（舍弃小数部分）
        var overlapCenter:Vector = new Vector(
            (overlapLeft + overlapRight) >> 1,
            (overlapTop + overlapBottom) >> 1
        );

        // 创建并返回碰撞结果
        var result:CollisionResult = new CollisionResult(true);
        result.overlapRatio = overlapRatio;
        result.overlapCenter = overlapCenter;
        return result;
    }

    // 不需要覆写 getAABB，因为父类 AABBCollider 已经实现了 ICollider 接口的 getAABB 方法。

    /**
     * 从透明子弹 MovieClip 实例中提取 AABB 碰撞范围，返回 CoverageAABBCollider 实例
     * @param 透明子弹实际上不是影片剪辑，被裁剪至object，根据之前的业务实现，硬编码其碰撞箱的大小为25
     */
    public static function fromTransparentBullet(bullet:Object):CoverageAABBCollider {
        var bullet_x:Number = bullet._x;
        var bullet_y:Number = bullet._y;
        
        return new CoverageAABBCollider(bullet_x - 12.5, bullet_x + 12.5, bullet_y - 12.5, bullet_y + 12.5);
    }

    /**
     * 从子弹 MovieClip 实例中提取 AABB 碰撞范围，返回 CoverageAABBCollider 实例
     * @param bullet 子弹的 MovieClip 实例，应包含 area、子弹区域area、透明检测 等属性
     */
    public static function fromBullet(bullet:MovieClip ,detectionArea:MovieClip):CoverageAABBCollider {
        var bullet_x:Number = bullet._x;
        var bullet_y:Number = bullet._y;

        // 取哈希时错开宽高，避免正方形碰撞箱异或宽高置零
        var area_key:Number = (detectionArea._x << 16) | (detectionArea._height << 8) | (detectionArea._width ^ detectionArea._y)
        if (!bullet[area_key]) 
        {
            var areaRect:Object = detectionArea.getRect(_root.gameworld);
            bullet[area_key] = {area: new AABB(areaRect.xMin, areaRect.xMax, areaRect.yMin, areaRect.yMax), x: bullet_x, y: bullet_y};
            
        }
        var cache:Object = bullet[area_key];
        var cache_area:Object = cache.area;
        var x_offset:Number = bullet_x - cache.x;
        var y_offset:Number = bullet_y - cache.y;

        // 构造并返回一个 CoverageAABBCollider 实例
        return new CoverageAABBCollider(cache_area.left + x_offset, cache_area.right + x_offset, cache_area.top + y_offset, cache_area.bottom + y_offset);
    }

    /**
     * 从单位 MovieClip 实例中提取 AABB 碰撞范围，返回 CoverageAABBCollider 实例
     * @param 单位必须拥有area影片剪辑
     */
    public static function fromUnitArea(unit:MovieClip):CoverageAABBCollider {
        var unitRect = unit.area.getRect(_root.gameworld);

        // 构造并返回一个 CoverageAABBCollider 实例
        return new CoverageAABBCollider(unitRect.xMin, unitRect.xMax, unitRect.yMin, unitRect.yMax);
    }
}
