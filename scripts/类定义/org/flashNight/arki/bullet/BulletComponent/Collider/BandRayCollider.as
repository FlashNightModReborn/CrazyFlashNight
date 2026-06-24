import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * BandRayCollider —— 带宽射线碰撞器（RayCollider 的屏幕-Y 加宽变体）。
 *
 * 从 RayCollider 隔离出来（2026-06-24，§8.1 带宽模组组件化）：**严格细线 RayCollider 保持本特性
 * 出现前逐字节不变、零带宽开销**；带宽逻辑仅存在于本子类。绝大多数射线消费者是细线，经多态
 * `areaAABB.checkCollision(...)` 自然分派——细线永不触碰带宽逻辑。
 *
 * 带宽语义：checkCollision 把目标 AABB 在 top/bottom 各膨胀 ±_halfWidth（Minkowski，屏幕-Y），
 * 使细线命中半径 _halfWidth 内的矮碰撞箱目标。对齐 Z→屏幕-Y 投影 + 近水平射线垂直容差；
 * 陡斜射线非真垂距（v2 胶囊再精修）。_halfWidth 由 TeslaRayLifecycle.bindCollider 从
 * rayConfig.rayWidthFactor 计算写入（半宽 = Z轴攻击范围 * 系数 * 0.5）。
 *
 * 【零复制实现】不复刻 RayCollider 的 slab：把目标 AABB（已 Z-shift）膨胀进复用代理 AABBCollider，
 * 再 `super.checkCollision(proxy, 0)` 委托父类 slab（proxy.getAABB(0) 不再二次平移）。故无 slab
 * 重复、无父类私有访问、RayCollider 100% 不动。代理是静态复用（同步消费安全，类比 RayCollider.result）。
 *
 * 【创建/池】带宽射线稀有 → 由 TeslaRayLifecycle 直接 `new BandRayCollider`（非池化），不进
 * RayColliderFactory 的细线共享池：其 getFactory()=null → BulletLifecycle.bindSafeRemove 的
 * releaseCollider 静默 no-op，随 Object GC。故细线池纯净，无需 createX 重置。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.BandRayCollider extends RayCollider {

    /** 带宽半宽（屏幕-Y，像素）。0 = 退化细线（但带宽射线一般 >0）。 */
    private var _halfWidth:Number;

    /**
     * 膨胀代理（静态复用，零分配）：装入"目标 AABB 已 Z-shift + 带宽膨胀"后的边界，
     * 委托给 super.checkCollision 跑 slab。懒创建（避免 eager 静态初始化跨类调用 AVM1 陷阱）。
     */
    private static var _bandProxy:AABBCollider = null;

    /**
     * 构造函数：几何同 RayCollider，半宽初始 0（由 setHalfWidth 配置）。
     */
    public function BandRayCollider(origin:Vector, direction:Vector, maxDistance:Number) {
        super(origin, direction, maxDistance);
        _halfWidth = 0;
        if (BandRayCollider._bandProxy == null) {
            BandRayCollider._bandProxy = new AABBCollider(0, 0, 0, 0);
        }
    }

    /** 设置带宽半宽（屏幕-Y，像素）。负值/NaN 归零。 */
    public function setHalfWidth(w:Number):Void {
        _halfWidth = (w > 0) ? w : 0;
    }

    /** 获取带宽半宽（像素）。 */
    public function getHalfWidth():Number {
        return _halfWidth;
    }

    /**
     * 带宽 checkCollision：目标 AABB（Z-shift 后）在 top/bottom 各膨胀 ±_halfWidth 装入代理，
     * 委托 super 的 Kay-Kajiya slab。先把目标 4 边读进局部再写代理——规避目标与代理可能共享
     * 同一静态 AABB（如目标也是 AABBCollider）导致的别名覆盖。
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var oa:AABB = other.getAABB(zOffset);   // 目标 AABB（已 Z-shift）
        var oLeft:Number = oa.left;
        var oRight:Number = oa.right;
        var oTop:Number = oa.top;
        var oBottom:Number = oa.bottom;

        var hw:Number = _halfWidth;
        var proxy:AABBCollider = BandRayCollider._bandProxy;
        proxy.left = oLeft;
        proxy.right = oRight;
        proxy.top = oTop - hw;
        proxy.bottom = oBottom + hw;

        // 委托父类 slab：proxy.getAABB(0) 返回已膨胀边界（不再二次 Z-shift）。
        // super 内部用自己的 _ray/_isValid，故无需访问父类私有。
        return super.checkCollision(proxy, 0);
    }
}
