import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * PointCollider 类
 *
 * 基于 AABBCollider 实现的点碰撞器。内部组合一个 Vector 用于存储位置，
 * 其 AABB 被坍缩为零体积（左右边界均为 x 坐标，上下边界均为 y 坐标）。
 * 检测碰撞时，只需判断点是否位于其他 AABB 内（考虑 zOffset）。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.PointCollider extends AABBCollider implements ICollider {
    // 内部存储点的位置
    private var _position:Vector;

    /**
     * 静态 AABB 缓存，用于 getAABB() 返回值复用
     * 每个碰撞器类型使用独立的静态 AABB，避免跨类型调用时相互覆盖
     */
    public static var AABB:AABB = new AABB(null);

    /**
     * 构造函数
     * @param x 初始 x 坐标
     * @param y 初始 y 坐标
     */
    public function PointCollider(x:Number, y:Number) {
        // 直接将 AABB 边界设为 x, x 和 y, y（零体积）
        super(x, x, y, y);
        _position = new Vector(x, y);
    }

    /**
     * 重写碰撞检测方法，对点碰撞器进行优化
     * 当点位于其他 AABB（经 zOffset 调整后）内时视为碰撞
     *
     * 注意：zOffset 仅应用于目标 AABB（通过 other.getAABB(zOffset)），
     * 点本身的坐标不加 zOffset，与其他碰撞器的语义一致。
     *
     * @param other 其他 ICollider 实例
     * @param zOffset z轴偏移，应用于目标 AABB
     * @return 如果检测到碰撞，返回 CollisionResult（重叠中心为该点）；否则返回 FALSE
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);
        // 使用当前点位置（不加 zOffset，与其他碰撞器语义一致）
        var x:Number = _position.x;
        var y:Number = _position.y;
        // 只要点位于其他碰撞器的 AABB 内，即视为碰撞
        if (x >= otherAABB.left && x <= otherAABB.right &&
            y >= otherAABB.top  && y <= otherAABB.bottom) {
            // 更新静态 CollisionResult 中的重叠中心为该点
            var collisionResult:CollisionResult = AABBCollider.result;
            collisionResult.overlapCenter.x = x;
            collisionResult.overlapCenter.y = y;
            return collisionResult;
        }
        return CollisionResult.FALSE;
    }

    /**
     * 更新点的位置，同时同步 AABB 边界
     * @param x 新的 x 坐标
     * @param y 新的 y 坐标
     */
    public function setPosition(x:Number, y:Number):Void {
        _position.x = x;
        _position.y = y;
        this.left   = x;
        this.right  = x;
        this.top    = y;
        this.bottom = y;
    }

    /**
     * 获取当前点的位置。每次返回新的 Vector 实例，保证数据安全性
     * @return 当前点的 Vector 实例
     */
    public function get position():Vector {
        return new Vector(_position.x, _position.y);
    }

    /**
     * 重写 getAABB 方法，返回点对应的 AABB（经过 zOffset 调整）
     * @param zOffset z轴偏移
     * @return 点的 AABB 实例
     */
    public function getAABB(zOffset:Number):AABB {
        var aabb:AABB = PointCollider.AABB;
        aabb.left   = _position.x;
        aabb.right  = _position.x;
        aabb.top    = _position.y + zOffset;
        aabb.bottom = _position.y + zOffset;
        return aabb;
    }

    /**
     * 使用透明子弹对象更新点位置
     * @param bullet 透明子弹对象
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        setPosition(bullet._x, bullet._y);
    }

    /**
     * 使用子弹和检测区域的 MovieClip 更新点位置
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 检测区域 MovieClip 实例
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        setPosition(bullet._x, bullet._y);
    }

    /**
     * 使用单位区域的 MovieClip 更新点位置，取区域中心
     * @param unit 包含 area 属性的单位 MovieClip 实例
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        var unitRect:Object = unit.area.getRect(_root.gameworld);
        var centerX:Number = (unitRect.xMin + unitRect.xMax) / 2;
        var centerY:Number = (unitRect.yMin + unitRect.yMax) / 2;
        setPosition(centerX, centerY);
    }

    /**
     * 设置碰撞器工厂引用
     * @param factory 工厂实例
     */
    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    /**
     * 获取碰撞器工厂引用
     * @return 工厂实例
     */
    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }
}
