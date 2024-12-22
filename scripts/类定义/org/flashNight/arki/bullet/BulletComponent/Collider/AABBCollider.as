import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.Server.*;

/**
 * AABBCollider 类
 *
 * 基于轴对齐边界框 (Axis-Aligned Bounding Box, AABB) 的碰撞检测器。
 * 继承 AABB 类并实现 ICollider 接口，提供碰撞检测功能、边界坐标获取和碰撞信息计算。
 * 
 * 功能概述：
 * 1. 碰撞检测逻辑：通过比较两个 AABB 的边界坐标判断是否发生碰撞。
 * 2. 提供多种静态辅助方法，用于获取不同类型的对象 (如子弹、透明子弹、单位区域) 的边界信息。
 * 3. 支持动态更新边界信息，适配游戏中实时变化的对象坐标。
 * 4. 提供碰撞结果，包括重叠中心点与重叠范围。
 * 
 * 使用场景：主要用于游戏中的子弹碰撞检测、单位区域碰撞等。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider extends AABB implements ICollider {

    /**
     * 碰撞器工厂实例，用于管理碰撞器的创建与复用。
     */
    public var _factory:AbstractColliderFactory;

    /**
     * 更新函数引用，用于多态表达当前使用的更新路径
     */
    public var _update:Function;

    /**
     * 当前帧数，避免在同一帧内重复更新边界。
     */
    public var _currentFrame:Number;

    /**
     * 构造函数，初始化 AABB 的边界坐标。
     * 
     * @param left   左边界坐标
     * @param right  右边界坐标
     * @param top    上边界坐标
     * @param bottom 下边界坐标
     */
    public function AABBCollider(left:Number, right:Number, top:Number, bottom:Number) {
        super(left, right, top, bottom);
    }

    /**
     * 检查与其他碰撞器的碰撞情况。
     *
     * 实现流程：
     * 1. 获取另一个碰撞器的 AABB 信息，并根据 zOffset 偏移值调整。
     * 2. 通过边界坐标比较，快速判断是否发生碰撞。
     * 3. 如果碰撞，计算重叠区域的中心点和覆盖率。
     * 
     * @param other   另一个 ICollider 实例
     * @param zOffset Z轴偏移量，用于模拟 3D 高度差
     * @return CollisionResult 实例，包含碰撞结果、重叠中心点等信息
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);

        // 优化：提前返回不碰撞的情况，减少计算量
        if (this.right <= otherAABB.left)  return CollisionResult.FALSE;
        if (this.left >= otherAABB.right)  return CollisionResult.FALSE;
        if (this.bottom <= otherAABB.top)  return CollisionResult.FALSE;
        if (this.top >= otherAABB.bottom)  return CollisionResult.FALSE;

        // 计算碰撞结果
        var result:CollisionResult = new CollisionResult(true);
        result.overlapRatio = 1; // 默认完全重叠覆盖率为 1
        result.overlapCenter = new Vector(
            (((this.left > otherAABB.left) ? this.left : otherAABB.left) + ((this.right < otherAABB.right) ? this.right : otherAABB.right)) >> 1,
            (((this.top > otherAABB.top) ? this.top : otherAABB.top) + ((this.bottom < otherAABB.bottom) ? this.bottom : otherAABB.bottom)) >> 1
        );
        return result;
    }

    /**
     * 获取当前碰撞器的 AABB 信息。
     *
     * @param zOffset Z轴偏移量，用于模拟高度差
     * @return AABB 实例，包含边界坐标
     */
    public function getAABB(zOffset:Number):AABB {
        return new AABB(this.left, this.right, this.top + zOffset, this.bottom + zOffset);
    }

    // ========================= 静态辅助方法区域 ========================= //

    /**
     * 提取子弹与检测区域的边界坐标。
     *
     * @param bullet        子弹的 MovieClip 实例
     * @param detectionArea 子弹检测区域的 MovieClip 实例
     * @return 包含边界坐标的 Object：left, right, top, bottom
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
     * 提取透明子弹的边界坐标 (默认尺寸为 25x25)。
     *
     * @param bullet 透明子弹对象
     * @return 包含边界坐标的 Object：left, right, top, bottom
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
     * 提取单位区域的边界坐标。
     *
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return 包含边界坐标的 Object：left, right, top, bottom
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

    // ========================= 动态更新方法区域 ========================= //

    /**
     * 基于透明子弹对象更新碰撞器的边界。
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
     * 基于子弹和检测区域的 MovieClip 实例更新碰撞器的边界。
     *
     * @param bullet        子弹 MovieClip 实例
     * @param detectionArea 检测区域的 MovieClip 实例
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var bullet_x:Number = bullet._x;
        var bullet_y:Number = bullet._y;

        // 生成唯一缓存键值
        var area_key:Number = (detectionArea._x << 16) | (detectionArea._height << 8) | (detectionArea._width ^ detectionArea._y);
        if (!bullet[area_key]) bullet[area_key] = {area: getBulletCoordinates(bullet, detectionArea), x: bullet_x, y: bullet_y};

        var cache:Object = bullet[area_key];
        var x_offset:Number = bullet_x - cache.x;
        var y_offset:Number = bullet_y - cache.y;

        this.left = cache.area.left + x_offset;
        this.right = cache.area.right + x_offset;
        this.top = cache.area.top + y_offset;
        this.bottom = cache.area.bottom + y_offset;
    }

    /**
     * 基于单位区域的 MovieClip 实例更新碰撞器的边界。
     *
     * @param unit 包含 area 属性的单位 MovieClip 实例
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        var frame = _root.帧计时器.当前帧数;
        if (this._currentFrame == frame) return;

        this._currentFrame = frame;
        var coords:Object = getUnitAreaCoordinates(unit);
        this.left = coords.left;
        this.right = coords.right;
        this.top = coords.top;
        this.bottom = coords.bottom;
    }

    /**
     * 设置碰撞器的工厂对象。
     *
     * @param factory 工厂实例
     */
    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    /**
     * 获取碰撞器的工厂对象。
     *
     * @return 工厂实例
     */
    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }
}
