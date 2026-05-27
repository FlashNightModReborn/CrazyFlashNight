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

    // ========== 溢出治疗曲线参数（项目级单一来源） ==========
    //
    // 【不变量 — 改动需重审设计契约】
    //   η₀ = 1.0      满血处边际效率 100%，曲线在 HP=baseMax 处导数连续，
    //                 玩家跨过满血时不会感到"突然变弱"
    //   C  = 0.5×baseMax  溢出渐近上限。HP 渐近趋于 1.5×baseMax
    //                     （理论不可达，整数截断会形成事实封顶）
    //
    // 【曲线】dO/dx = η₀·(1 - O/C)
    //   闭式：ΔO = (C - O₀)·(1 - exp(-η₀·Δx/C))
    //
    // 【派生行为参考表 — 累计原始溢出输入 X（从 O₀=0 起）→ 溢出量 O】
    //   X=0.5M  → O=0.316M (63%)
    //   X=1.0M  → O=0.432M (87%)
    //   X=1.15M → O=0.450M (90%)
    //   X=2.0M  → O=0.491M (98%)   实际"封顶"门槛
    //   X=2.3M  → O=0.495M (99%)
    //
    // 【取整副作用】
    //   单段输入不变性仅在连续域成立。每段 < 1 点的小输入会被 (x | 0) 截断丢弃，
    //   高分段下事实回血量低于一次性大段。由于实战伤害普遍高到可忽略取整影响，简化实现。
    //
    // 【调参指引】
    //   - 体感过强 → 优先下调 OVERFLOW_CAP_RATIO（如 0.4 / 0.3），保留 η₀=1 的导数连续契约
    //   - 不建议下调 OVERFLOW_INITIAL_EFFICIENCY：会破坏满血处平滑过渡，
    //     玩家会感到"100% HP 是一道墙"
    //
    // 【共享原则】
    //   所有走 applyHpOverflow 的路径（吸血 / 扭转乾坤 / 未来类似机制）共享此曲线。
    //   如设计意图差异化，应新增独立 applyXxxOverflow 而非加参数侵入主路径。

    public static var OVERFLOW_INITIAL_EFFICIENCY:Number = 1.0;
    public static var OVERFLOW_CAP_RATIO:Number = 0.5;

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
     * HP 溢出衰减治疗。满血以下 100% 效率，满血以上按项目级共享曲线衰减。
     * 曲线参数见类顶部 OVERFLOW_CAP_RATIO / OVERFLOW_INITIAL_EFFICIENCY；
     * 所有走本方法的调用方共享同一条曲线，调参一处生效。
     *
     * 注意：满血处效率 100% 的"满血"指 baseMax，**不**含外部封顶提升（如炼金）。
     * 若炼金把玩家长期托在 1.30·baseMax，则在该点的边际效率已是 40%
     * （这是有意的：炼金给地板、本曲线给天花板，分工不重叠）。
     *
     * @param target  目标对象（需有 hp 字段）
     * @param amount  请求恢复量
     * @param baseMax 曲线基准（通常 = target.hp满血值；不含炼金加成）
     * @return 实际恢复量（已取整）；0 表示衰减后 < 1 点 或 已死亡 或 amount<=0
     */
    public static function applyHpOverflow(target:Object, amount:Number, baseMax:Number):Number {
        if (!target) return 0;
        var current:Number = target.hp;
        if (current <= 0) return 0;
        if (!(amount > 0)) return 0;
        if (!(baseMax > 0)) return 0;

        var M:Number = baseMax;
        var C:Number = M * OVERFLOW_CAP_RATIO;

        // 满血以下段：100% 效率
        var roomToMax:Number = M - current;
        if (roomToMax < 0) roomToMax = 0;
        var part1:Number = amount < roomToMax ? amount : roomToMax;
        var overflowInput:Number = amount - part1;

        // 满血以上段：(1 - O/C) 边际衰减
        var part2:Number = 0;
        var O0:Number = current > M ? current - M : 0;
        if (overflowInput > 0 && O0 < C) {
            part2 = (C - O0) * (1 - Math.exp(-OVERFLOW_INITIAL_EFFICIENCY * overflowInput / C));
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
