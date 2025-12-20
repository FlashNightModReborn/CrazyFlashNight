import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

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
        // AS2 要求 super() 必须是构造函数的第一条语句
        // 先用临时值调用父类构造函数，后续再更新
        super(0, 0, 0, 0);

        // 初始化内部射线
        _ray = new Ray(origin, direction, maxDistance);
        // 根据射线的起点和终点计算包围盒并更新边界
        var endpoint:Vector = _ray.getEndpoint();
        this.left = Math.min(origin.x, endpoint.x);
        this.right = Math.max(origin.x, endpoint.x);
        this.top = Math.min(origin.y, endpoint.y);
        this.bottom = Math.max(origin.y, endpoint.y);
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
     *
     * 性能优化：直接复用构造时/setRay时已计算的 this.left/right/top/bottom，
     * 避免每次调用都重新计算端点和执行 Math.min/max。
     *
     * @param zOffset z轴偏移
     * @return 射线的 AABB 实例
     */
    public function getAABB(zOffset:Number):AABB {
        var aabb:AABB = AABBCollider.AABB;
        aabb.left = this.left;
        aabb.right = this.right;
        aabb.top = this.top + zOffset;
        aabb.bottom = this.bottom + zOffset;
        return aabb;
    }

    /**
     * 检查射线碰撞器与其他碰撞器的碰撞情况。
     * 检测方法：将射线作为有限线段（从起点到 endpoint）与其他碰撞器的 AABB 进行相交测试。
     * 若相交，则计算出一个近似交点作为碰撞结果。
     *
     * 性能优化：
     * - 使用零分配的数值计算替代 Vector 对象创建
     * - 内联 getEndpoint、getCenter、closestPointTo 逻辑
     *
     * @param other 其他 ICollider 实例
     * @param zOffset z轴偏移
     * @return 如果射线与其他碰撞器相交，返回 CollisionResult，
     *         并在 CollisionResult.overlapCenter 中存储近似交点；否则返回 CollisionResult.FALSE
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);

        // ========== 有序分离快速检测 ==========
        // 使用严格比较 (<) 保持"边界接触算命中"的语义
        // 与 AABBCollider/CoverageAABBCollider 保持一致的有序分离模式
        var otherLeft:Number = otherAABB.left;
        var otherRight:Number = otherAABB.right;
        var otherTop:Number = otherAABB.top;
        var otherBottom:Number = otherAABB.bottom;

        // 射线 AABB 完全在目标左侧 -> X轴有序分离
        if (this.right < otherLeft) return CollisionResult.ORDERFALSE;
        // 射线 AABB 完全在目标右侧 -> 普通分离
        if (this.left > otherRight) return CollisionResult.FALSE;
        // 射线 AABB 完全在目标上方 -> Y轴有序分离
        if (this.bottom < otherTop) return CollisionResult.YORDERFALSE;
        // 射线 AABB 完全在目标下方 -> 普通分离
        if (this.top > otherBottom) return CollisionResult.FALSE;

        // 内联获取射线参数（避免属性访问开销）
        var ox:Number = _ray.origin.x;
        var oy:Number = _ray.origin.y;
        var dx:Number = _ray.direction.x;
        var dy:Number = _ray.direction.y;
        var maxDist:Number = _ray.maxDistance;

        // 内联计算终点（零分配）
        var ex:Number = ox + dx * maxDist;
        var ey:Number = oy + dy * maxDist;

        // 利用 AABB 的线段相交检测
        if (otherAABB.intersectsLine(ox, oy, ex, ey)) {
            // 内联计算 AABB 中心（零分配，避免 getCenter() 创建 Vector）
            var cx:Number = (otherAABB.left + otherAABB.right) * 0.5;
            var cy:Number = (otherAABB.top + otherAABB.bottom) * 0.5;

            // 内联计算 closestPointTo（零分配）
            // t = dot(center - origin, direction)
            var opx:Number = cx - ox;
            var opy:Number = cy - oy;
            var t:Number = opx * dx + opy * dy;
            if (t < 0) t = 0;
            if (t > maxDist) t = maxDist;

            // 最近点坐标
            var closestX:Number = ox + dx * t;
            var closestY:Number = oy + dy * t;

            // 复用静态 CollisionResult
            var collisionResult:CollisionResult = AABBCollider.result;
            collisionResult.overlapCenter.x = closestX;
            collisionResult.overlapCenter.y = closestY;
            return collisionResult;
        }
        return CollisionResult.FALSE;
    }

    /**
     * 使用透明子弹对象更新射线碰撞器的起点（方向和长度保持不变）
     * 性能优化：完全内联版本，消除所有方法调用
     * @param bullet 透明子弹对象
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        var ox:Number = bullet._x;
        var oy:Number = bullet._y;
        _ray.origin.x = ox;
        _ray.origin.y = oy;

        // 内联端点计算：endpoint = origin + direction * maxDistance
        var dx:Number = _ray.direction.x;
        var dy:Number = _ray.direction.y;
        var maxDist:Number = _ray.maxDistance;
        var ex:Number = ox + dx * maxDist;
        var ey:Number = oy + dy * maxDist;

        if (ox < ex) { this.left = ox; this.right = ex; }
        else { this.left = ex; this.right = ox; }
        if (oy < ey) { this.top = oy; this.bottom = ey; }
        else { this.top = ey; this.bottom = oy; }
    }

    /**
     * 使用子弹和检测区域的 MovieClip 更新射线碰撞器的起点
     * 性能优化：完全内联版本
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 检测区域 MovieClip 实例（此处暂不使用，可供扩展）
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var ox:Number = bullet._x;
        var oy:Number = bullet._y;
        _ray.origin.x = ox;
        _ray.origin.y = oy;

        var dx:Number = _ray.direction.x;
        var dy:Number = _ray.direction.y;
        var maxDist:Number = _ray.maxDistance;
        var ex:Number = ox + dx * maxDist;
        var ey:Number = oy + dy * maxDist;

        if (ox < ex) { this.left = ox; this.right = ex; }
        else { this.left = ex; this.right = ox; }
        if (oy < ey) { this.top = oy; this.bottom = ey; }
        else { this.top = ey; this.bottom = oy; }
    }

    /**
     * 使用单位区域的 MovieClip 更新射线碰撞器的起点，
     * 取该区域的中心作为新的射线起点
     * 性能优化：完全内联版本
     * @param unit 包含 area 属性的单位 MovieClip 实例
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        var unitRect:Object = unit.area.getRect(_root.gameworld);
        var ox:Number = (unitRect.xMin + unitRect.xMax) * 0.5;
        var oy:Number = (unitRect.yMin + unitRect.yMax) * 0.5;
        _ray.origin.x = ox;
        _ray.origin.y = oy;

        var dx:Number = _ray.direction.x;
        var dy:Number = _ray.direction.y;
        var maxDist:Number = _ray.maxDistance;
        var ex:Number = ox + dx * maxDist;
        var ey:Number = oy + dy * maxDist;

        if (ox < ex) { this.left = ox; this.right = ex; }
        else { this.left = ex; this.right = ox; }
        if (oy < ey) { this.top = oy; this.bottom = ey; }
        else { this.top = ey; this.bottom = oy; }
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
