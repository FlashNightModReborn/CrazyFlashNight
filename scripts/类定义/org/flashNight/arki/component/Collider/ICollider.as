import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * ICollider 碰撞器接口
 *
 * 定义碰撞检测器的统一契约，所有碰撞器实现必须遵守以下规范。
 *
 * ========================= 碰撞管线契约 =========================
 *
 * 【C1 两阶段碰撞管线】
 *   碰撞检测分为宽相（broadphase）和窄相（narrowphase）两个阶段：
 *   - 宽相：始终为 AABB vs AABB 检测，用于快速排除不可能碰撞的对。
 *     宽相碰撞器挂载于 bullet.aabbCollider / unit.aabbCollider。
 *     BulletQueueProcessor 的扫描线算法对宽相进行了内联优化，
 *     直接读取碰撞器的 left/right/top/bottom 属性（不经过 getAABB）。
 *   - 窄相（可选）：在宽相通过后进行精确碰撞检测。
 *     窄相碰撞器挂载于 bullet.polygonCollider 等专用字段。
 *     窄相通过 checkCollision(other, zOffset) 的标准接口调用。
 *     当前窄相类型：PolygonCollider。未来扩展：RayCollider。
 *
 * 【C2 AABB 自维护不变量（broadphase-only）】
 *   作为宽相碰撞器（挂载到 .aabbCollider）的实现类必须满足：
 *   - 实例必须拥有 left, right, top, bottom 四个 Number 属性
 *   - 所有 update 方法（updateFromBullet / updateFromTransparentBullet /
 *     updateFromUnitArea）在返回前必须将 left/right/top/bottom 更新为
 *     当前几何形状的精确轴对齐包围盒
 *   - BulletQueueProcessor 在宽相阶段会直接读取这四个属性并内联应用
 *     zOffset（uTop = top + zOffset），而不调用 getAABB(zOffset)
 *   - 违反此不变量将导致宽相碰撞检测结果不正确
 *   适用类型：AABBCollider, CoverageAABBCollider, RayCollider, PointCollider
 *   （均 extends AABBCollider extends AABB，天然持有 left/right/top/bottom）
 *
 * 【C3 getAABB 语义】
 *   getAABB(zOffset) 返回碰撞器的轴对齐包围盒，zOffset 仅应用于 Y 轴：
 *   - 返回的 AABB.left/right = 碰撞器的 X 范围（不受 zOffset 影响）
 *   - 返回的 AABB.top = 碰撞器的 top + zOffset
 *   - 返回的 AABB.bottom = 碰撞器的 bottom + zOffset
 *   此方法主要供窄相碰撞器的 checkCollision 内部调用（获取 other 的包围盒）。
 *   宽相碰撞器也必须实现此方法以满足接口契约，但宽相内联路径不依赖它。
 *
 * 【C4 窄相碰撞器例外】
 *   纯窄相碰撞器（如 PolygonCollider）不挂载到 .aabbCollider，
 *   不需要满足 C2 的自维护不变量。其 getAABB 可从内部几何实时计算。
 *
 * 【C5 CollisionResult 静态复用】
 *   每个碰撞器类型必须维护独立的静态 CollisionResult 和静态 AABB 缓存，
 *   避免跨类型调用时相互覆盖。碰撞路径禁止分配新对象（零分配契约）。
 *
 * 【C6 有序分离语义】
 *   checkCollision 返回的 CollisionResult 携带有序分离信息：
 *   - ORDERFALSE: X 轴左侧分离（碰撞器在目标左侧，扫描线可安全推进）
 *   - YORDERFALSE: Y 轴上方分离（X 轴已确认无左侧分离）
 *   - FALSE: 其他方向分离
 *   扫描线算法依赖此语义进行右边界截断优化。
 *
 * ================================================================
 */
interface org.flashNight.arki.component.Collider.ICollider {
    /**
     * 检查与另一个碰撞器是否发生碰撞
     *
     * @param other 另一个 ICollider 实例
     * @param zOffset 碰撞体之间的Z轴差，用于模拟3d高度
     * @return CollisionResult 实例，包含碰撞结果及相关信息
     */
    function checkCollision(other:ICollider ,zOffset:Number):CollisionResult;

    /**
     * 获取碰撞器的 AABB 信息
     *
     * 语义契约（见 C3）：
     * - left/right: 碰撞器 X 范围，不受 zOffset 影响
     * - top/bottom: 碰撞器 Y 范围 + zOffset
     * - 返回的 AABB 为类级静态缓存，调用者不得持有引用跨帧使用
     *
     * @param zOffset 碰撞体之间的Z轴差，用于模拟3d高度
     * @return AABB 实例，表示碰撞器的轴对齐边界框
     */
    function getAABB(zOffset:Number):AABB;

    /**
     * 更新碰撞器边界信息，基于透明子弹对象
     *
     * 契约（见 C2）：宽相碰撞器必须在返回前更新 left/right/top/bottom
     *
     * @param bullet 透明子弹对象
     */
    function updateFromTransparentBullet(bullet:Object):Void;

    /**
     * 更新碰撞器边界信息，基于子弹和检测区域的 MovieClip 实例
     *
     * 契约（见 C2）：宽相碰撞器必须在返回前更新 left/right/top/bottom
     *
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     */
    function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void;

    /**
     * 更新碰撞器边界信息，基于单位区域的 MovieClip 实例
     *
     * 契约（见 C2）：宽相碰撞器必须在返回前更新 left/right/top/bottom
     *
     * @param unit 包含 area 属性的单位 MovieClip 实例
     */
    function updateFromUnitArea(unit:MovieClip):Void;

    function setFactory(factory:AbstractColliderFactory):Void;  // 设置工厂引用
    function getFactory():AbstractColliderFactory;             // 获取工厂引用
}
