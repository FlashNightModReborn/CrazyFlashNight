// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/MissileMovement.as

import org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement;
import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;

/**
 * MissileMovement
 * ===============
 * 面向“寻的追踪弹 / 导弹”专用运动组件。
 *
 * • 继承自 BaseMissileMovement：获得 FSM、委托、速度/角度属性等通用能力。
 * • 实现 IMovement：保持与 BulletSystem 的 updateMovement(target) 统一接口。
 * • 仅在构造函数里把“策略回调”与外部参数注入；真正逻辑全走父类。
 *
 * 典型绑定流程：
 *   1. var movement:MissileMovement = MissileMovement.create(configObj);
 *   2. movement.targetObject = missileClip;
 *   3. missileClip.movement = movement;    // 供子弹管理器引用
 *   4. 在 BulletLoop 中调用 movement.updateMovement(missileClip);
 *
 * @author flashNight
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.MissileMovement
        extends BaseMissileMovement implements IMovement
{
    // --------------------------
    // 构造 & 工厂
    // --------------------------

    /**
     * 构造函数（直接透传给父类；建议走 create() 工厂方法）
     * @param params:Object 参见 BaseMissileMovement 文档
     */
    public function MissileMovement(params:Object)
    {
        super(params);   // BaseMissileMovement 会完成：委托绑定 + 状态机初始化
    }

    /**
     * 工厂方法 —— 与 LinearBulletMovement 的 create() 统一风格
     * @param params:Object 同构造函数
     */
    public static function create(params:Object):MissileMovement
    {
        return new MissileMovement(params);
    }

    // --------------------------
    // IMovement 实现
    // --------------------------

    /**
     * 每帧由 BulletManager 驱动。
     * 这里直接调用父类的 updateMovement，保持接口一致，
     * 你也可以在 super 之前 / 之后插入额外逻辑（粒子尾迹等）。
     *
     * @param target:MovieClip 当前导弹 Clip（外层系统负责传入）
     */
    public function updateMovement(target:MovieClip):Void
    {
        // ★ 若要附加通用尾焰等，可在此处写额外逻辑
        // beforeSuper(target);

        // 核心运动 & FSM 切换逻辑 —— 由 BaseMissileMovement 处理
        super.updateMovement(target);

        // afterSuper(target);
    }
}
