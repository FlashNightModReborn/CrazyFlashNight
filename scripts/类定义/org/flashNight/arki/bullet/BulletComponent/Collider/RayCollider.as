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
     *
     * 性能优化（零分配版本）：
     * - 使用 Ray.setToFast 直接修改坐标值，无 clone() 分配
     * - 内联终点计算，无 getEndpoint() 分配
     * - 使用条件赋值替代 Math.min/max
     *
     * @param origin 新的射线起点
     * @param direction 新的射线方向（传入后单位化）
     * @param maxDistance 新的射线最大长度
     */
    public function setRay(origin:Vector, direction:Vector, maxDistance:Number):Void {
        var ox:Number = origin.x;
        var oy:Number = origin.y;
        var dx:Number = direction.x;
        var dy:Number = direction.y;

        // 使用零分配快速版本
        _ray.setToFast(ox, oy, dx, dy, maxDistance);

        // 内联终点计算（使用归一化后的方向）
        var ndx:Number = _ray.direction.x;
        var ndy:Number = _ray.direction.y;
        var ex:Number = ox + ndx * maxDistance;
        var ey:Number = oy + ndy * maxDistance;

        // 条件赋值替代 Math.min/max
        if (ox < ex) { this.left = ox; this.right = ex; }
        else { this.left = ex; this.right = ox; }
        if (oy < ey) { this.top = oy; this.bottom = ey; }
        else { this.top = ey; this.bottom = oy; }
    }

    /**
     * 设置射线的属性（数值参数版本，完全零分配）
     *
     * 当调用者已有数值坐标时使用此版本，避免创建临时 Vector 对象。
     *
     * @param ox 起点 X 坐标
     * @param oy 起点 Y 坐标
     * @param dx 方向 X 分量（将被归一化）
     * @param dy 方向 Y 分量（将被归一化）
     * @param maxDistance 射线最大长度
     */
    public function setRayFast(ox:Number, oy:Number, dx:Number, dy:Number, maxDistance:Number):Void {
        _ray.setToFast(ox, oy, dx, dy, maxDistance);

        // 内联终点计算（使用归一化后的方向）
        var ndx:Number = _ray.direction.x;
        var ndy:Number = _ray.direction.y;
        var ex:Number = ox + ndx * maxDistance;
        var ey:Number = oy + ndy * maxDistance;

        if (ox < ex) { this.left = ox; this.right = ex; }
        else { this.left = ex; this.right = ox; }
        if (oy < ey) { this.top = oy; this.bottom = ey; }
        else { this.top = ey; this.bottom = oy; }
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
        var aabb:AABB = RayCollider.AABB;
        aabb.left = this.left;
        aabb.right = this.right;
        aabb.top = this.top + zOffset;
        aabb.bottom = this.bottom + zOffset;
        return aabb;
    }

    /**
     * 检查射线碰撞器与其他碰撞器的碰撞情况。
     *
     * 使用内联 Slab (Kay-Kajiya) 算法替代 AABB.intersectsLine()，
     * 同时输出精确入射参数 tEntry 和入射点坐标。
     *
     * 算法流程：
     * 1. AABB 宽相：有序分离快速检测（与 AABBCollider 一致）
     * 2. Slab 窄相：计算射线与 AABB 四条边的参数交点
     *    - tMin = max(t_enter_x, t_enter_y) → 射线进入 AABB 的参数
     *    - tMax = min(t_exit_x, t_exit_y)  → 射线离开 AABB 的参数
     *    - 相交条件: tMin <= tMax && tMax >= 0 && tMin <= maxDistance
     * 3. 输出 tEntry（clamp 到 [0, maxDistance]）和精确入射点
     *
     * 性能特征：
     * - 零分配：所有计算为内联数值运算
     * - 替换而非新增：Slab 计算取代了原 intersectsLine() + 中心投影，总指令数近似
     * - tEntry 零额外开销：Slab 天然产出 tMin，仅需一次 clamp + 写入
     *
     * 视觉改善：
     * - overlapCenter 从"射线到 AABB 中心的最近点"改为"射线进入 AABB 的精确入射点"
     * - 电弧终点从穿入目标体内移到目标体表面，视觉更自然
     *
     * @param other 其他 ICollider 实例
     * @param zOffset z轴偏移
     * @return 如果射线与其他碰撞器相交，返回 CollisionResult，
     *         其中 overlapCenter = 精确入射点，tEntry = 射线参数；
     *         否则返回 CollisionResult.FALSE / ORDERFALSE / YORDERFALSE
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);

        // ========== 有序分离快速检测 ==========
        // 使用宽松比较 (<=/>= ) 与 AABBCollider 保持一致：边界恰好接触视为分离。
        // 这避免了"擦边"情况进入 Slab 窄相的额外计算，且语义统一便于维护。
        var otherLeft:Number = otherAABB.left;
        var otherRight:Number = otherAABB.right;
        var otherTop:Number = otherAABB.top;
        var otherBottom:Number = otherAABB.bottom;

        // 射线 AABB 完全在目标左侧 -> X轴有序分离
        if (this.right <= otherLeft) return CollisionResult.ORDERFALSE;
        // 射线 AABB 完全在目标右侧 -> 普通分离
        if (this.left >= otherRight) return CollisionResult.FALSE;
        // 射线 AABB 完全在目标上方 -> Y轴有序分离
        if (this.bottom <= otherTop) return CollisionResult.YORDERFALSE;
        // 射线 AABB 完全在目标下方 -> 普通分离
        if (this.top >= otherBottom) return CollisionResult.FALSE;

        // 内联获取射线参数（避免属性访问开销）
        var ox:Number = _ray.origin.x;
        var oy:Number = _ray.origin.y;
        var dx:Number = _ray.direction.x;
        var dy:Number = _ray.direction.y;
        var maxDist:Number = _ray.maxDistance;

        // ========== 内联 Slab (Kay-Kajiya) 射线-AABB 相交检测 ==========
        //
        // 原理：将 AABB 视为 X/Y 两组平行平面（slab）的交集，
        // 分别计算射线与每组平面的进入/离开参数 t，取交集。
        //
        // 注意：当 dx 或 dy 为 0 时（射线平行于某轴），
        // 使用极大倒数 1e10 使得 t 值趋向 ±Infinity，
        // 由后续 tMin/tMax 比较自然处理平行情况。

        var invDx:Number = (dx != 0) ? (1.0 / dx) : 1e10;
        var invDy:Number = (dy != 0) ? (1.0 / dy) : 1e10;

        // X 轴 slab 参数
        var t1x:Number = (otherLeft - ox) * invDx;
        var t2x:Number = (otherRight - ox) * invDx;
        // 保证 t1x <= t2x（射线方向为负时交换）
        var tmp:Number;
        if (t1x > t2x) { tmp = t1x; t1x = t2x; t2x = tmp; }

        // Y 轴 slab 参数
        var t1y:Number = (otherTop - oy) * invDy;
        var t2y:Number = (otherBottom - oy) * invDy;
        if (t1y > t2y) { tmp = t1y; t1y = t2y; t2y = tmp; }

        // tMin = 射线进入 AABB 的参数（两轴进入参数取大）
        // tMax = 射线离开 AABB 的参数（两轴离开参数取小）
        var tMin:Number = (t1x > t1y) ? t1x : t1y;
        var tMax:Number = (t2x < t2y) ? t2x : t2y;

        // 相交判定：
        // 1. tMin <= tMax: 两个 slab 有交集
        // 2. tMax >= 0: AABB 不完全在射线起点后方
        // 3. tMin <= maxDist: 入射点在射线有效长度内
        if (tMin > tMax || tMax < 0 || tMin > maxDist) {
            return CollisionResult.FALSE;
        }

        // clamp tEntry 到 [0, maxDist]
        // tMin < 0 表示射线起点在 AABB 内部，此时入射点为起点
        var tEntry:Number = tMin;
        if (tEntry < 0) tEntry = 0;

        // 精确入射点坐标（零分配）
        var entryX:Number = ox + dx * tEntry;
        var entryY:Number = oy + dy * tEntry;

        // 复用 RayCollider 独立的静态 CollisionResult
        var collisionResult:CollisionResult = RayCollider.result;
        collisionResult.overlapCenter.x = entryX;
        collisionResult.overlapCenter.y = entryY;
        collisionResult.tEntry = tEntry;
        return collisionResult;
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
