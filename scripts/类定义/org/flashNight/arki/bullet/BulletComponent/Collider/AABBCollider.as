import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.Server.*;

/**
 * AABBCollider 类
 * 
 * 基于 AABB（轴对齐边界框）的碰撞检测器，通过继承 AABB 类并实现 ICollider 接口，
 * 提供基本的碰撞检测功能，包括碰撞检查和边界信息提取。
 * 
 * 使用 Vector 类作为点和向量的数据结构，支持动态生成 AABB。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider extends AABB implements ICollider {

    public var _factory:AbstractColliderFactory;
    public var _update:Function;
    public var _currentFrame:Number;
    
    /**
     * 构造函数，初始化 AABB 碰撞器的边界
     * 
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
     * 
     * 逻辑流程：
     * 1. 获取另一个碰撞器的 AABB 信息。
     * 2. 检查 AABB 是否相交，通过多个简单的条件判断优化性能。
     * 3. 如果相交，计算碰撞中心点并返回结果。
     * 
     * @param other 另一个 ICollider 实例
     * @param zOffset Z轴偏移量，用于模拟 3D 高度差
     * @return 碰撞结果 CollisionResult 实例
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        // 获取对方的 AABB 信息，并应用 zOffset 偏移
        var otherAABB:AABB = other.getAABB(zOffset);

        // 提前返回检查不相交条件，优化性能
        if (this.right <= otherAABB.left)  return CollisionResult.FALSE;
        if (this.left >= otherAABB.right)  return CollisionResult.FALSE;
        if (this.bottom <= otherAABB.top)  return CollisionResult.FALSE;
        if (this.top >= otherAABB.bottom)  return CollisionResult.FALSE;

        // 计算碰撞结果，包括重叠中心点
        var result:CollisionResult = new CollisionResult(true);
        result.overlapRatio = 1; // 默认覆盖率为 1（完全覆盖）
        result.overlapCenter = new Vector(
            (((this.left > otherAABB.left) ? this.left : otherAABB.left) + ((this.right < otherAABB.right) ? this.right : otherAABB.right)) >> 1,
            (((this.top > otherAABB.top) ? this.top : otherAABB.top) + ((this.bottom < otherAABB.bottom) ? this.bottom : otherAABB.bottom)) >> 1
        );
        return result;
    }

    /**
     * 获取 AABB 信息
     * 
     * 根据 zOffset 偏移量，返回一个新的 AABB 实例，用于碰撞计算。
     * 
     * @param zOffset Z轴偏移量，用于模拟 3D 高度差
     * @return 当前碰撞器的 AABB 实例
     */
    public function getAABB(zOffset:Number):AABB {
        return new AABB(this.left, this.right, this.top + zOffset, this.bottom + zOffset);
    }

    // 静态辅助方法区域

    /**
     * 从子弹和检测区域中提取边界信息
     * 
     * 计算并返回子弹在指定检测区域内的 AABB 坐标信息。
     * 
     * @param bullet 子弹 MovieClip 实例
     * @return 包含边界坐标的 Object 对象
     */
    private static function getBulletCoordinates(bullet:MovieClip, detectionArea:MovieClip):Object {
        var areaRect:Object = detectionArea.getRect(_root.gameworld);

        return {
            left: areaRect.xMin,
            right: areaRect.xMax,
            top: areaRect.yMin,
            bottom: areaRect.yMax
        };
    }

    /**
     * 从透明子弹中提取边界信息
     * 
     * 硬编码透明子弹的碰撞箱大小为 25x25，并根据子弹的坐标计算其 AABB 信息。
     * 
     * @param bullet 透明子弹对象
     * @return 包含边界坐标的 Object 对象
     */
    private static function getTransparentBulletCoordinates(bullet:Object):Object {
        var bullet_x:Number = bullet._x;
        var bullet_y:Number = bullet._y;
        return {
            left: bullet_x - 12.5, 
            right: bullet_x + 12.5, 
            top: bullet_y - 12.5, 
            bottom: bullet_y + 12.5
        };
    }

    /**
     * 从单位区域中提取边界信息
     * 
     * 计算单位区域在游戏世界中的 AABB 坐标信息。
     * 
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return 包含边界坐标的 Object 对象
     */
    private static function getUnitAreaCoordinates(unit:MovieClip):Object {
        var unitRect:Object = unit.area.getRect(_root.gameworld);
        return {
            left: unitRect.xMin,
            right: unitRect.xMax,
            top: unitRect.yMin,
            bottom: unitRect.yMax
        };
    }

    // 实例化方法区域

    /**
     * 更新 AABBCollider 实例的边界信息，基于透明子弹对象
     * 
     * @param bullet 透明子弹对象
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        var coords:Object = getTransparentBulletCoordinates(bullet);
        this.left = coords.left;
        this.right = coords.right;
        this.top = coords.top;
        this.bottom = coords.bottom;
    }

    /**
     * 更新 AABBCollider 实例的边界信息，基于子弹和检测区域的 MovieClip 实例
     * 
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var bullet_x:Number = bullet._x;
        var bullet_y:Number = bullet._y;

        // 生成唯一哈希键，用于缓存计算结果
        var area_key:Number = (detectionArea._x << 16) | (detectionArea._height << 8) | (detectionArea._width ^ detectionArea._y);
        if (!bullet[area_key]) bullet[area_key] = {area: getBulletCoordinates(bullet, detectionArea), x: bullet_x, y: bullet_y};

        var cache:Object = bullet[area_key];
        var cache_area:AABB = cache.area;
        var x_offset:Number = bullet_x - cache.x;
        var y_offset:Number = bullet_y - cache.y;

        this.left = cache_area.left + x_offset;
        this.right = cache_area.right + x_offset;
        this.top = cache_area.top + y_offset;
        this.bottom = cache_area.bottom + y_offset;
    }

    /**
     * 更新 AABBCollider 实例的边界信息，基于单位区域的 MovieClip 实例
     * 
     * @param unit 包含 area 属性的单位 MovieClip 实例
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        var frame = _root.帧计时器.当前帧数;
        if(this._currentFrame == frame) return;

        this._currentFrame = frame;
        var coords:Object = getUnitAreaCoordinates(unit);
        this.left = coords.left;
        this.right = coords.right;
        this.top = coords.top;
        this.bottom = coords.bottom;
    }

    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }
}
