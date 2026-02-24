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
 * 2. 射线碰撞器 - 使用 RayCollider + Slab 算法进行射线-AABB相交检测
 * 3. 视觉独立 - 射线视觉效果由 RayVfxManager 独立管理（支持多风格）
 * 4. 多模式支持 - single / pierce / chain / fork 四种射线模式
 *
 * 射线模式（由 TeslaRayConfig.rayMode 控制）：
 * • single  - 命中最近单目标（默认行为）
 * • pierce  - 穿透射线，命中路径上所有目标，按 tEntry 距离排序
 * • chain   - 连锁弹跳，命中后从命中点搜索附近下一目标继续连锁
 * • fork    - 光棱折射，命中后从命中点搜索附近目标定向折射
 *
 * 【pierceLimit 设计决策】
 * 所有模式的目标数量统一由 bullet.pierceLimit（<attribute> 层）控制：
 *   bullet.pierceLimit = 1（默认）→ 任何模式都退化为 single 行为
 *   bullet.pierceLimit = N →
 *     pierce: 沿路径命中 N 个目标
 *     chain:  主命中 + (N-1) 次弹跳
 *     fork:   主命中 + (N-1) 条折射光束（搜索半径内最近的 N-1 个目标）
 *
 * 与普通子弹的 pierceLimit 不冲突：射线子弹不进入主碰撞循环，
 * 在 processRayBullets 的 FLAG_RAY 分支中独立处理。
 *
 * 伤害衰减由 TeslaRayConfig.damageFalloff（<rayConfig> 内）控制。
 *
 * 调用链路：
 *   BulletFactory 检测 FLAG_RAY -> 选择 TeslaRayLifecycle
 *   -> bindLifecycle -> bindCollider (创建 RayCollider)
 *   -> bindFrameHandler (加入 preCheckRay 队列)
 *   -> BulletQueueProcessor.processRayBullets -> 碰撞检测 + 模式分派
 *   -> RayVfxManager.spawn (视觉效果，支持 Tesla/Prism/Spectrum/Wave 风格)
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
