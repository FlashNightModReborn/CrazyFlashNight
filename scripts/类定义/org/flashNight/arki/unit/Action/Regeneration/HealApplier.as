/**
 * HealApplier - 治疗封顶统一入口
 *
 * 项目内所有"会增加 target.hp / target.mp"的路径在此聚合，统一封顶逻辑。
 * API 按属性 + 行为特化，避免 target[prop] 的 dynamic name 开销（吸血是热路径）。
 *
 *   applyHpCapped     —— HP 硬封顶到 capValue（药剂炼金加成 / Regen tick / 范围治疗 / 装备形态切换）
 *   applyHpOverflow   —— HP 满血以下 100% + 满血以上指数衰减（吸血；将来 buff 圣盾等可复用）
 *   applyMpCapped     —— MP 硬封顶到 capValue（炼金不抬 MP 封顶，永远是 target.mp满血值）
 *
 * 不接管：
 *   - 复活 / 九命猫妖（语义=重置，hp 强写 = 满血值，不走治疗 buff 链）
 *   - TickComponent（仅周期框架，回调应调用本类）
 *
 * 调用方约定：
 *   - 返回真实回复量；UI 刷新 / 浮字 / 音效由调用方根据返回值决定
 *   - target 死亡（hp <= 0）一律返回 0，不修改任何属性（MP 路径同样以 hp 判存活）
 *   - amount <= 0 或 NaN 一律返回 0
 *
 * @see LifeStealDamageHandle  (applyHpOverflow 调用方)
 * @see HealEffect             (applyHpCapped + applyMpCapped；HP 走炼金封顶)
 * @see RegenEffect            (applyHpCapped + applyMpCapped tick 回调)
 * @see RegenerationCore       (applyHpCapped + applyMpCapped 通用回血)
 */
class org.flashNight.arki.unit.Action.Regeneration.HealApplier {

    /**
     * HP 硬封顶治疗。把 target.hp 向上推到 capValue，超过的部分丢弃。
     *
     * 典型场景：
     *   - 药剂即时回血：capValue = ctx.getMaxHPWithAlchemy()  （含炼金加成的硬封顶）
     *   - 普通范围回血：capValue = target.hp满血值
     *
     * @param target   目标对象（需有 hp 字段）
     * @param amount   请求恢复量
     * @param capValue 实际封顶值
     * @return 实际恢复量；0 表示无效（死亡 / 已达封顶 / 请求<=0）
     */
    public static function applyHpCapped(target:Object, amount:Number, capValue:Number):Number {
        if (!target) return 0;
        var current:Number = target.hp;
        if (current <= 0) return 0;
        if (!(amount > 0)) return 0; // 同时挡 NaN / 负数 / 0
        if (!(capValue > 0)) return 0;
        if (current >= capValue) return 0;

        var newValue:Number = current + amount;
        if (newValue > capValue) newValue = capValue;

        var actual:Number = newValue - current;
        if (actual <= 0) return 0;

        target.hp = newValue;
        return actual;
    }

    /**
     * HP 溢出衰减治疗。满血以下 100% 效率，满血以上按
     *     dO/dx = eta0 · (1 - O/C)
     *     闭式：ΔO = (C - O₀) · (1 - exp(-eta0·Δx/C))
     * 其中 C = baseMax · capRatio，O 渐近趋于 C（理论不可达，整数截断形成事实封顶）。
     *
     * 设计契约：eta0=1.0 时曲线在 HP=baseMax 处导数连续，跨越满血无突变。
     *
     * 注意：满血处效率 100% 的"满血"指 baseMax，**不**含外部封顶提升（如炼金）。
     * 若炼金把玩家长期托在 1.30·baseMax，则吸血输入在该点的边际效率已是 40%
     * （这是有意的：炼金给地板、吸血给天花板，分工不重叠）。
     *
     * @param target    目标对象（需有 hp 字段）
     * @param amount    请求恢复量
     * @param baseMax   曲线基准（吸血传 target.hp满血值；不含炼金加成）
     * @param capRatio  渐近上限比例（吸血 = 0.5 → 渐近 1.5·baseMax）
     * @param eta0      满血处边际效率（吸血 = 1.0，导数连续）
     * @return 实际恢复量（已取整）；0 表示衰减后 < 1 点 或 已死亡 或 amount<=0
     */
    public static function applyHpOverflow(target:Object, amount:Number, baseMax:Number, capRatio:Number, eta0:Number):Number {
        if (!target) return 0;
        var current:Number = target.hp;
        if (current <= 0) return 0;
        if (!(amount > 0)) return 0;
        if (!(baseMax > 0) || !(capRatio > 0) || !(eta0 > 0)) return 0;

        var M:Number = baseMax;
        var C:Number = M * capRatio;

        // 满血以下段：100% 效率
        var roomToMax:Number = M - current;
        if (roomToMax < 0) roomToMax = 0;
        var part1:Number = amount < roomToMax ? amount : roomToMax;
        var overflowInput:Number = amount - part1;

        // 满血以上段：(1 - O/C) 边际衰减
        var part2:Number = 0;
        var O0:Number = current > M ? current - M : 0;
        if (overflowInput > 0 && O0 < C) {
            part2 = (C - O0) * (1 - Math.exp(-eta0 * overflowInput / C));
        }

        var healed:Number = (part1 + part2) | 0;
        if (healed <= 0) return 0;

        target.hp = current + healed;
        return healed;
    }

    /**
     * MP 硬封顶治疗。把 target.mp 向上推到 capValue。
     *
     * 注：炼金不抬升 MP 封顶（DrugContext 只有 getMaxHPWithAlchemy），
     * 所以本方法的 capValue 通常恒为 target.mp满血值。存在 capValue 参数仅为对称 + 防御性。
     * 存活判断仍按 target.hp（死亡单位不应回 MP）。
     *
     * @param target   目标对象（需有 hp 字段判存活、mp 字段被修改）
     * @param amount   请求恢复量
     * @param capValue 实际封顶值（通常 = target.mp满血值）
     * @return 实际恢复量；0 表示无效
     */
    public static function applyMpCapped(target:Object, amount:Number, capValue:Number):Number {
        if (!target) return 0;
        if (target.hp <= 0) return 0;
        if (!(amount > 0)) return 0;
        if (!(capValue > 0)) return 0;

        var current:Number = target.mp;
        if (current >= capValue) return 0;

        var newValue:Number = current + amount;
        if (newValue > capValue) newValue = capValue;

        var actual:Number = newValue - current;
        if (actual <= 0) return 0;

        target.mp = newValue;
        return actual;
    }
}
