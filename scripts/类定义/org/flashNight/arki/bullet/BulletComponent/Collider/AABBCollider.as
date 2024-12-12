import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

/**
 * AABBCollider 类
 * 
 * 通过继承 AABB 类，实现 ICollider 接口，
 * 提供基于轴对齐边界框（AABB）的碰撞检测功能。
 * 使用 Vector 类作为点和向量的数据结构。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider extends AABB implements ICollider {
    
    /**
     * 构造函数，初始化 AABB 碰撞器的边界
     * @param left 左边界坐标
     * @param right 右边界坐标
     * @param top 上边界坐标
     * @param bottom 下边界坐标
     */
    public function AABBCollider(left:Number, right:Number, top:Number, bottom:Number) {
        super(left, right, top, bottom);
    }

    /**
     * 实现 ICollider 接口的碰撞检查方法。
     * 注意:计算顺序上要求为子弹的碰撞器调用checkCollision方法，检测单位的碰撞器，否则zOffset需要取反
     * 逻辑：
     * 1. 获取对方的 AABB 信息。
     * 2. 使用 AABB 的 intersects 方法进行初步碰撞检测。
     * 3. 如果 AABB 相交，计算碰撞中心点并返回 CollisionResult。
     * 
     * @param other 另一个 ICollider 实例
     * @return 碰撞结果 CollisionResult 实例
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        // 获取对方的 AABB 信息，并应用 zOffset
        var otherAABB:AABB = other.getAABB(zOffset);

        // 检查不相交的条件，并提前返回，经测试，多个简单if提前返回性能略好于一个复杂逻辑运算的组合if
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

        // 如果相交，计算碰撞中心点,创建碰撞结果并返回
        var result:CollisionResult = new CollisionResult(true);
        result.overlapRatio = 1;
        result.overlapCenter = new Vector(
            (((this.left > otherAABB.left) ? this.left : otherAABB.left) + ((this.right < otherAABB.right) ? this.right : otherAABB.right)) >> 1,
            (((this.top > otherAABB.top) ? this.top : otherAABB.top) + ((this.bottom < otherAABB.bottom) ? this.bottom : otherAABB.bottom)) >> 1
        );
        return result;
    }


    /**
     * 获取 AABB 信息
     * 
     * @return 当前实例作为 AABB 返回
     */
    public function getAABB(zOffset:Number):AABB {
        return new AABB(this.left, this.right, this.top + zOffset, this.bottom + zOffset);
    }

    /**
     * 从透明子弹 MovieClip 实例中提取 AABB 碰撞范围，返回 AABBCollider 实例
     * @param 透明子弹实际上不是影片剪辑，被裁剪至object，根据之前的业务实现，硬编码其碰撞箱的大小为25
     */
    public static function fromTransparentBullet(bullet:Object):AABBCollider {
        var bullet_x:Number = bullet._x;
        var bullet_y:Number = bullet._y;
        
        return new AABBCollider(bullet_x - 12.5, bullet_x + 12.5, bullet_y - 12.5, bullet_y + 12.5);
    }

    /**
     * 从子弹 MovieClip 实例中提取 AABB 碰撞范围，返回 AABBCollider 实例
     * @param bullet 子弹的 MovieClip 实例，应包含 area、子弹区域area、透明检测 等属性
     */
    public static function fromBullet(bullet:MovieClip ,detectionArea:MovieClip):AABBCollider {
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

        // 构造并返回一个 AABBCollider 实例
        return new AABBCollider(cache_area.left + x_offset, cache_area.right + x_offset, cache_area.top + y_offset, cache_area.bottom + y_offset);
    }

    /**
     * 从单位 MovieClip 实例中提取 AABB 碰撞范围，返回 AABBCollider 实例
     * @param 单位必须拥有area影片剪辑
     */
    public static function fromUnitArea(unit:MovieClip):AABBCollider {
        var unitRect = unit.area.getRect(_root.gameworld);

        // 构造并返回一个 AABBCollider 实例
        return new AABBCollider(unitRect.xMin, unitRect.xMax, unitRect.yMin, unitRect.yMax);
    }
}