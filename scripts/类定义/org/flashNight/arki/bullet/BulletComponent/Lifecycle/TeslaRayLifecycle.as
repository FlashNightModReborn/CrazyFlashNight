// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.TeslaRayLifecycle.as

import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.sara.util.*;

/**
 * TeslaRayLifecycle - 磁暴射线子弹生命周期管理器
 *
 * 继承自 TransparentBulletLifecycle，专门处理射线类型子弹的生命周期逻辑。
 *
 * 特点：
 * 1. 单帧检测 - 子弹发射瞬间完成全部碰撞检测
 * 2. 射线碰撞器 - 使用 RayCollider 进行射线-AABB相交检测
 * 3. 视觉独立 - 电弧视觉效果由 LightningRenderer 独立管理
 * 4. 命中最近 - 射线碰撞返回最近命中点
 *
 * 【设计决策：穿透(pierce)机制不适用于射线子弹】
 * 射线子弹走透明子弹(TransparentBullet)的碰撞路径以复用其性能优化，
 * 但碰撞逻辑为"单帧扫描全部候选→只命中最近目标"。
 * pierceLimit 属性在射线分支中被静默跳过，这是有意为之：
 * - 物理语义：射线是瞬时能量释放，与穿透的"依次贯穿"语义不同
 * - 性能优化：射线复用透明子弹的 preCheckTransparent 队列路径，
 *   避免为射线单独维护一套队列管理逻辑
 * - 如需"射线穿透多目标"效果，应在 BulletQueueProcessor 的
 *   FLAG_RAY 分支中按距离排序后依次处理前 N 个目标，而非复用 pierceLimit
 *
 * 调用链路：
 *   BulletFactory 检测 FLAG_RAY -> 选择 TeslaRayLifecycle
 *   -> bindLifecycle -> bindCollider (创建 RayCollider)
 *   -> bindFrameHandler (加入队列，复用 preCheckTransparent 路径)
 *   -> BulletQueueProcessor 射线窄相分支 -> 碰撞检测
 *   -> LightningRenderer.spawn (视觉效果)
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.TeslaRayLifecycle
    extends TransparentBulletLifecycle implements ILifecycle {

    /** 静态实例 - 默认射线子弹生命周期管理器 */
    public static var BASIC:TeslaRayLifecycle = new TeslaRayLifecycle();

    /** 角度转弧度常量 */
    private static var DEG_TO_RAD:Number = Math.PI / 180;

    /**
     * 默认构造函数
     */
    public function TeslaRayLifecycle() {
        super();
    }

    /**
     * 绑定射线碰撞检测器
     *
     * 从子弹的 rayConfig 读取射线长度，根据子弹的位置和旋转角度
     * 创建射线碰撞器。
     *
     * 工程约束：
     * - target.rayConfig 必须存在（由 AttributeLoader 解析 XML 时设置）
     * - target._rotation 用于确定射线方向
     * - target._x, target._y 用于确定射线起点
     *
     * @param target:MovieClip 要绑定的子弹对象
     * @param factory:IColliderFactory 碰撞检测器工厂（被忽略，使用 RayColliderFactory）
     */
    public function bindCollider(target:MovieClip, factory:IColliderFactory):Void {
        // 获取射线配置
        var config:TeslaRayConfig = target.rayConfig;
        var rayLength:Number = config ? config.rayLength : 900;

        // 计算射线方向（基于子弹旋转角度）
        var angle:Number = target._rotation * DEG_TO_RAD;
        var dirX:Number = Math.cos(angle);
        var dirY:Number = Math.sin(angle);
        var rayDir:Vector = new Vector(dirX, dirY);

        // 创建射线起点（子弹当前位置）
        var origin:Vector = new Vector(target._x, target._y);

        // 从注册表获取 RayColliderFactory 并创建射线碰撞器
        // 注意：IColliderFactory 接口没有 createCustomRay，需要强转为 RayColliderFactory
        var rayFactory:RayColliderFactory = RayColliderFactory(
            ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.RayFactory)
        );
        target.aabbCollider = rayFactory.createCustomRay(origin, rayDir, rayLength);
    }

    /**
     * 重写帧事件处理器绑定
     *
     * 射线子弹是单帧检测，发射后立即加入碰撞队列。
     * 碰撞检测和视觉效果触发由 BulletQueueProcessor 的 FLAG_RAY 分支处理。
     *
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindFrameHandler(target:MovieClip):Void {
        // 加入射线独立处理队列（不进入主碰撞循环）
        BulletQueueProcessor.preCheckRay(target);
    }

    /**
     * 立即销毁判定
     *
     * 射线子弹在触发检测后立即销毁，始终返回 true。
     *
     * @param target:MovieClip 要检测的子弹对象
     * @return Boolean 恒为 true（立即销毁）
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        return true;
    }
}
