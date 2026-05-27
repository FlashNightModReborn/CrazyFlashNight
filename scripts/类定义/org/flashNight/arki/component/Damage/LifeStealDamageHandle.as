import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;

/**
 * LifeStealDamageHandle 类是用于处理吸血伤害的处理器。
 * - 当子弹具有吸血属性时，根据目标的损伤值和吸血比例，计算吸血量并恢复射击者的血量。
 * - 吸血量受目标当前血量、射击者最大血量和吸血比例的限制。
 * - 吸血效果会显示在伤害结果中。
 *
 * 【护盾交互】
 * - 吸血会检查目标护盾强度，只有子弹威力 > 护盾强度时才能生效
 * - 护盾强度代表"能挡住的单次伤害上限"，高强度护盾可阻止吸血效果
 */
class org.flashNight.arki.component.Damage.LifeStealDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========

    /** 单例实例 */
    public static var instance:LifeStealDamageHandle = new LifeStealDamageHandle();

    // 溢出衰减曲线参数现在统一在 HealApplier（OVERFLOW_CAP_RATIO / OVERFLOW_INITIAL_EFFICIENCY）
    // 所有走 applyHpOverflow 的路径共享一条曲线，调参一处生效

    // ========== 构造函数 ==========

    /**
     * 构造函数。
     * 调用父类构造函数以初始化基类。
     */
    public function LifeStealDamageHandle() {
        super();
    }

    /**
     * 获取 LifeStealDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 LifeStealDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return LifeStealDamageHandle 单例实例
     */
    public static function getInstance():LifeStealDamageHandle {
        return instance;
    }

    // ========== 公共方法 ==========

    /**
     * 判断子弹是否具有吸血属性。
     * - 如果子弹的吸血属性值大于 0，则返回 true。
     *
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有吸血属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        return !(bullet.吸血 <= 0);
    }

    /**
     * 处理吸血伤害。
     * - 根据目标的损伤值和吸血比例，计算原始吸血量。
     * - 吸血量上限不超过目标当前血量。
     * - 治疗分两段：
     *   1. 满血以下部分以 100% 效率治疗。
     *   2. 满血以上部分（溢出治疗）应用边际效率衰减：
     *      微分形式  dO/dx = η₀·(1 - O/C)^1
     *      闭式积分  ΔO = (C - O₀)·(1 - exp(-η₀·Δx/C))
     *      其中 C = OVERFLOW_CAP_RATIO × hp满血值，O 渐近趋于 C（永远不到）。
     * - 显示数值为应用衰减后的实际治疗量。
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象
     * @param result  伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 护盾强度足以阻挡：子弹威力 ≤ 护盾强度，吸血不触发
        var shield:IShield = target.shield;
        if (shield && bullet.子弹威力 <= shield.getStrength()) return;

        // 伤害过小，不触发吸血
        if (target.损伤值 <= 1) return;

        // 原始吸血量（不超过目标当前血量，不小于 0）
        var lifeStealAmount:Number = (target.损伤值 * bullet.吸血 / 100) | 0;
        if (lifeStealAmount > target.hp) lifeStealAmount = target.hp;
        if (lifeStealAmount <= 0) return;

        // 委托 HealApplier 执行衰减曲线；曲线参数、存活检查、取整事实封顶在内部完成
        var healAmount:Number = HealApplier.applyHpOverflow(shooter, lifeStealAmount, shooter.hp满血值);
        if (healAmount <= 0) return;

        // 每弹显示量：联弹/霰弹下 healAmount < actualScatterUsed 会被取整成 0，
        // 此时仍然完成了真实治疗，但不冒 "+0 吸血" 飘字
        var perPellet:Number = (healAmount / result.actualScatterUsed) | 0;
        if (perPellet <= 0) return;

        // 延迟 HTML 构建：位标记 + 吸血槽（显示实际治疗量）
        result._efFlags |= 32; // EF_LIFESTEAL
        result._efLifeSteal = perPellet;
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "LifeStealDamageHandle";
    }
}
