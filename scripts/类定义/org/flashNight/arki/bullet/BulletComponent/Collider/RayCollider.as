import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.component.Collider.ICollider;

/**
 * RayCollider 类
 *
 * 基于 Ray 实现的射线碰撞器。内部组合一个 Ray 对象，
 * 用于射线碰撞检测。其 AABB 为射线起点与终点构成的最小包围盒，
 * 并通过 zOffset 调整以适应 2.5D 碰撞检测需求。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.RayCollider extends AABBCollider implements ICollider {
    // 内部存储射线对象
    private var _ray:Ray;

    /**
     * 构造函数
     * @param origin 射线起点
     * @param direction 射线方向（传入后单位化）
     * @param maxDistance 射线最大长度
     */
    public function RayCollider(origin:Vector, direction:Vector, maxDistance:Number) {
        // 初始化内部射线
        _ray = new Ray(origin, direction, maxDistance);
        // 根据射线的起点和终点计算包围盒
        var endpoint:Vector = _ray.getEndpoint();
        var left:Number = Math.min(origin.x, endpoint.x);
        var right:Number = Math.max(origin.x, endpoint.x);
        var top:Number = Math.min(origin.y, endpoint.y);
        var bottom:Number = Math.max(origin.y, endpoint.y);
        // 调用父类构造函数初始化 AABB
        super(left, right, top, bottom);
    }

    /**
     * 设置射线的属性，更新内部 Ray 对象及 AABB 边界
     * @param origin 新的射线起点
     * @param direction 新的射线方向（传入后单位化）
     * @param maxDistance 新的射线最大长度
     */
    public function setRay(origin:Vector, direction:Vector, maxDistance:Number):Void {
        _ray.setTo(origin, direction, maxDistance);
        var endpoint:Vector = _ray.getEndpoint();
        this.left = Math.min(origin.x, endpoint.x);
        this.right = Math.max(origin.x, endpoint.x);
        this.top = Math.min(origin.y, endpoint.y);
        this.bottom = Math.max(origin.y, endpoint.y);
    }

    /**
     * 获取射线的 AABB，即由射线起点与终点构成的最小包围盒，
     * 并在 y 坐标上加上 zOffset 以实现 2.5D 效果。
     * @param zOffset z轴偏移
     * @return 射线的 AABB 实例
     */
    public function getAABB(zOffset:Number):AABB {
        var origin:Vector = _ray.origin;
        var endpoint:Vector = _ray.getEndpoint();
        var left:Number = Math.min(origin.x, endpoint.x);
        var right:Number = Math.max(origin.x, endpoint.x);
        var top:Number = Math.min(origin.y, endpoint.y) + zOffset;
        var bottom:Number = Math.max(origin.y, endpoint.y) + zOffset;
        var aabb:AABB = AABBCollider.AABB;
        aabb.left = left;
        aabb.right = right;
        aabb.top = top;
        aabb.bottom = bottom;
        return aabb;
    }

    /**
     * 检查射线碰撞器与其他碰撞器的碰撞情况。
     * 检测方法：将射线作为有限线段（从起点到 endpoint）与其他碰撞器的 AABB 进行相交测试。
     * 若相交，则利用 Ray.closestPointTo 计算出一个近似交点作为碰撞结果。
     * @param other 其他 ICollider 实例
     * @param zOffset z轴偏移
     * @return 如果射线与其他碰撞器相交，返回 CollisionResult，
     *         并在 CollisionResult.overlapCenter 中存储近似交点；否则返回 CollisionResult.FALSE
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);
        var rayOrigin:Vector = _ray.origin;
        var rayEndpoint:Vector = _ray.getEndpoint();
        // 利用 AABB 的线段相交检测
        if (otherAABB.intersectsLine(rayOrigin.x, rayOrigin.y, rayEndpoint.x, rayEndpoint.y)) {
            // 计算交点：取其他 AABB 的中心与射线上最近的点
            var otherCenter:Vector = otherAABB.getCenter();
            var intersectionPoint:Vector = _ray.closestPointTo(otherCenter);
            var collisionResult:CollisionResult = AABBCollider.result;
            collisionResult.overlapCenter.x = intersectionPoint.x;
            collisionResult.overlapCenter.y = intersectionPoint.y;
            return collisionResult;
        }
        return CollisionResult.FALSE;
    }

    /**
     * 使用透明子弹对象更新射线碰撞器的起点（方向和长度保持不变）
     * @param bullet 透明子弹对象
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        var newOrigin:Vector = new Vector(bullet._x, bullet._y);
        _ray.origin = newOrigin;
        var endpoint:Vector = _ray.getEndpoint();
        this.left = Math.min(newOrigin.x, endpoint.x);
        this.right = Math.max(newOrigin.x, endpoint.x);
        this.top = Math.min(newOrigin.y, endpoint.y);
        this.bottom = Math.max(newOrigin.y, endpoint.y);
    }

    /**
     * 使用子弹和检测区域的 MovieClip 更新射线碰撞器的起点
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 检测区域 MovieClip 实例（此处暂不使用，可供扩展）
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var newOrigin:Vector = new Vector(bullet._x, bullet._y);
        _ray.origin = newOrigin;
        var endpoint:Vector = _ray.getEndpoint();
        this.left = Math.min(newOrigin.x, endpoint.x);
        this.right = Math.max(newOrigin.x, endpoint.x);
        this.top = Math.min(newOrigin.y, endpoint.y);
        this.bottom = Math.max(newOrigin.y, endpoint.y);
    }

    /**
     * 使用单位区域的 MovieClip 更新射线碰撞器的起点，
     * 取该区域的中心作为新的射线起点
     * @param unit 包含 area 属性的单位 MovieClip 实例
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        var unitRect:Object = unit.area.getRect(_root.gameworld);
        var centerX:Number = (unitRect.xMin + unitRect.xMax) / 2;
        var centerY:Number = (unitRect.yMin + unitRect.yMax) / 2;
        var newOrigin:Vector = new Vector(centerX, centerY);
        _ray.origin = newOrigin;
        var endpoint:Vector = _ray.getEndpoint();
        this.left = Math.min(newOrigin.x, endpoint.x);
        this.right = Math.max(newOrigin.x, endpoint.x);
        this.top = Math.min(newOrigin.y, endpoint.y);
        this.bottom = Math.max(newOrigin.y, endpoint.y);
    }

    /**
     * 设置碰撞器的工厂对象引用
     * @param factory 工厂实例
     */
    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    /**
     * 获取碰撞器的工厂对象引用
     * @return 工厂实例
     */
    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }
}
