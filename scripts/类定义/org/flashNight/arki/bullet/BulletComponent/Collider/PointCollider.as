import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * PointCollider 类
 *
 * 基于 AABBCollider 实现的点碰撞器。
 * 其 AABB 被坍缩为零体积（left==right==x, top==bottom==y）。
 * 检测碰撞时，只需判断点是否位于其他 AABB 内（考虑 zOffset）。
 *
 * 性能优势（相比 AABBCollider）：
 * - updateFromTransparentBullet: 直接取 _x/_y，无需 ±12.5 边界计算
 * - updateFromBullet: 直接取 _x/_y，无需缓存逻辑和坐标转换
 * - updateFromUnitArea: 直接取 _x/_y，无需 getRect() 调用
 *
 * 适用场景：
 * - 精确命中检测（狙击枪、激光指示器）
 * - 点击/拾取判定
 * - 不需要碰撞体积的子弹
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
     * 静态 CollisionResult 缓存，用于 checkCollision() 返回值复用
     * 每个碰撞器类型使用独立的静态 result，避免跨类型调用时相互覆盖
     */
    public static var result:CollisionResult = CollisionResult.Create(true, new Vector(0, 0), 1);

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
     * @return 如果检测到碰撞，返回 CollisionResult（重叠中心为该点）；
     *         否则返回 ORDERFALSE（点在目标左侧）/ YORDERFALSE（点在目标上方）/ FALSE
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);
        // 使用当前点位置（不加 zOffset，与其他碰撞器语义一致）
        var x:Number = _position.x;
        var y:Number = _position.y;

        // 有序分离检测（使用严格比较，边界接触算命中）
        // 点在目标左侧 -> X轴有序分离
        if (x < otherAABB.left) return CollisionResult.ORDERFALSE;
        // 点在目标右侧 -> 普通分离
        if (x > otherAABB.right) return CollisionResult.FALSE;
        // 点在目标上方 -> Y轴有序分离
        if (y < otherAABB.top) return CollisionResult.YORDERFALSE;
        // 点在目标下方 -> 普通分离
        if (y > otherAABB.bottom) return CollisionResult.FALSE;

        // 点在 AABB 内（含边界），返回碰撞结果
        var collisionResult:CollisionResult = PointCollider.result;
        collisionResult.overlapCenter.x = x;
        collisionResult.overlapCenter.y = y;
        return collisionResult;
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
     *
     * 性能优势：直接取 _x/_y，无需 AABBCollider 的 ±12.5 边界计算
     *
     * @param bullet 透明子弹对象
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        // 直接内联，避免 setPosition 方法调用开销
        var x:Number = bullet._x;
        var y:Number = bullet._y;
        _position.x = x;
        _position.y = y;
        this.left   = x;
        this.right  = x;
        this.top    = y;
        this.bottom = y;
    }

    /**
     * 使用子弹和检测区域的 MovieClip 更新点位置
     *
     * 性能优势：直接取 _x/_y，无需 AABBCollider 的缓存逻辑和坐标转换
     * 注意：detectionArea 参数被忽略，点碰撞器只关心子弹中心点
     *
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 检测区域 MovieClip 实例（点碰撞器忽略）
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        // 直接内联，避免 setPosition 方法调用开销
        var x:Number = bullet._x;
        var y:Number = bullet._y;
        _position.x = x;
        _position.y = y;
        this.left   = x;
        this.right  = x;
        this.top    = y;
        this.bottom = y;
    }

    /**
     * 使用单位的注册点更新点位置
     *
     * 语义说明：
     * - 本方法使用 unit._x/_y（单位注册点），而非 unit.area 的中心
     * - 这与 AABBCollider/PolygonCollider/RayCollider 的 updateFromUnitArea 语义不同
     *   （它们使用 unit.area.getRect().center）
     * - 当单位注册点位于脚底而非中心时，点碰撞器位置将与其他碰撞器不同
     *
     * 性能优势：直接取 _x/_y，无需 getRect() 调用
     *
     * 适用场景：
     * - 单位注册点在中心时，行为与其他碰撞器一致
     * - 需要精确命中单位注册点（如锚点检测）
     *
     * @param unit 单位 MovieClip 实例
     */
    public function updateFromUnitRegistrationPoint(unit:MovieClip):Void {
        var x:Number = unit._x;
        var y:Number = unit._y;
        _position.x = x;
        _position.y = y;
        this.left   = x;
        this.right  = x;
        this.top    = y;
        this.bottom = y;
    }

    /**
     * 使用单位区域中心更新点位置（与其他碰撞器语义一致）
     *
     * 语义说明：
     * - 本方法使用 unit.area.getRect() 的中心，与 AABBCollider/PolygonCollider/RayCollider 一致
     * - 当单位注册点不在中心时，应使用此方法保持语义统一
     *
     * @param unit 单位 MovieClip 实例
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        var unitRect:Object = unit.area.getRect(_root.gameworld);
        var x:Number = (unitRect.xMin + unitRect.xMax) * 0.5;
        var y:Number = (unitRect.yMin + unitRect.yMax) * 0.5;
        _position.x = x;
        _position.y = y;
        this.left   = x;
        this.right  = x;
        this.top    = y;
        this.bottom = y;
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
