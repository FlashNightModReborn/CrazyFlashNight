/**
 * HealApplier - 治疗封顶统一入口
 *
 * 项目内所有"会增加 target.hp / target.mp"的路径在此聚合，统一封顶逻辑。
 * API 按属性 + 行为特化，避免 target[prop] 的 dynamic name 开销（吸血是热路径）。
 *
 *   applyHpCapped     —— HP 硬封顶到 capValue（药剂炼金加成 / Regen tick / 范围治疗 / 装备形态切换）
 *   applyHpOverflow   —— HP 满血以下 100% + 满血以上指数衰减（吸血；将来 buff 圣盾等可复用）
 *   applyMpCapped     —— MP 硬封顶到 capValue（炼金不抬 MP 封顶，永远是 target.mp满血值）
 *   applyMpOverflow   —— MP "蓄电池超充" 硬封顶到 mpBase·capRatio（capRatio ≥ 1，无衰减曲线）
 *
 * 不接管：
 *   - 复活 / 九命猫妖（语义=重置，hp 强写 = 满血值，不走治疗 buff 链）
 *   - TickComponent（仅周期框架，回调应调用本类）
 *
 * 调用方约定：
 *   - 返回真实回复量；主角 HP 成功变化后由本类请求主 HUD 合并刷新，浮字 / 音效仍由调用方决定
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
     * 返回治疗系统允许的安全 HP 比例。只用于本次结算的边界判断，
     * 不得拿来把当前 HP 按新装备上限做比例投影。超过溢出上界或非有限
     * 表示来源不可信，回退到 1.0 而不是替污染值补发临时生命资格。
     */
    public static function calculateSafeHpRatio(currentHp:Number, currentMaxHp:Number):Number {
        if (!(currentMaxHp > 0) || !isFinite(currentMaxHp)) return 0;

        var overflowRatio:Number = Number(OVERFLOW_CAP_RATIO);
        if (!(overflowRatio > 0) || !isFinite(overflowRatio)) overflowRatio = 0;
        var maximumRatio:Number = 1 + overflowRatio;

        if (!(currentHp > 0)) return 0;
        // 非有限或超过治疗系统上界的值没有合法 provenance；不得在击溃边界
        // 被重新认证为临时生命，保守回退到普通满血比例。
        if (!isFinite(currentHp)) return 1;

        var ratio:Number = currentHp / currentMaxHp;
        if (!(ratio > 0)) return 0;
        return ratio > maximumRatio ? 1 : ratio;
    }

    /**
     * 最大值重建后结算绝对 HP：不按比例回血，也不因降低上限制造临时生命。
     * 旧 HP 位于旧治疗溢出上界内时视为已存在的合法临时生命，只保留其绝对值，
     * 并夹到新治疗溢出上界；超过旧上界或非有限的污染值回退为新满血值。
     */
    public static function settleHpAfterMaxChange(currentHp:Number,
                                                   previousMaxHp:Number,
                                                   rebuiltMaxHp:Number):Number {
        if (!(rebuiltMaxHp > 0) || !isFinite(rebuiltMaxHp)) return 0;
        if (!isFinite(currentHp)) return rebuiltMaxHp;
        if (!(currentHp > 0)) return 0;
        if (!(previousMaxHp > 0) || !isFinite(previousMaxHp)) return rebuiltMaxHp;

        // 普通当前值只能受新 live 上限约束，降上限不能把它变成临时生命。
        if (currentHp <= previousMaxHp) return Math.min(currentHp, rebuiltMaxHp);

        var overflowRatio:Number = Number(OVERFLOW_CAP_RATIO);
        if (!(overflowRatio > 0) || !isFinite(overflowRatio)) overflowRatio = 0;
        var maximumRatio:Number = 1 + overflowRatio;
        var previousOverflowCap:Number = previousMaxHp * maximumRatio;
        if (!isFinite(previousOverflowCap) || currentHp > previousOverflowCap) {
            return rebuiltMaxHp;
        }

        // 合法临时生命保留绝对点数，不按 old/new max 比例复制。
        var rebuiltOverflowCap:Number = rebuiltMaxHp * maximumRatio;
        if (!isFinite(rebuiltOverflowCap)) return currentHp;
        return Math.min(currentHp, rebuiltOverflowCap);
    }

    /** MP 没有通用临时资源契约；最大值重建只保留受新上限约束的绝对当前值。 */
    public static function settleMpAfterMaxChange(currentMp:Number, rebuiltMaxMp:Number):Number {
        if (!(rebuiltMaxMp > 0) || !isFinite(rebuiltMaxMp)) return 0;
        if (!isFinite(currentMp)) return rebuiltMaxMp;
        if (!(currentMp > 0)) return 0;
        return Math.min(currentMp, rebuiltMaxMp);
    }

    /**
     * 成功治疗主角后只设置 HUD 待刷新位；玩家信息界面每帧至多消费一次。
     * 非玩家单位不承担 UI 写入，同帧后续治疗继续保持 pending，不会漏掉最终状态。
     */
    private static function requestHeroHpDisplayRefresh(target:Object):Void {
        var controlTarget = _root.控制目标;
        if (controlTarget == undefined || target._name !== controlTarget) return;
        var playerInfo:Object = _root.玩家信息界面;
        if (playerInfo) playerInfo._pendingHpDisplayRefresh = true;
    }

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
        requestHeroHpDisplayRefresh(target);
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
        requestHeroHpDisplayRefresh(target);
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

    /**
     * MP "蓄电池超充" 硬封顶。允许 MP 越过 mpBase（=mp满血值），最终硬封顶到 mpBase·capRatio。
     *
     * 与 applyMpCapped 的区别：
     *   - applyMpCapped 的 capValue 通常 = mp满血值（即 capRatio = 1.0）
     *   - 本方法专为"装备让 MP 可超充到 N 倍满血"的资源溢出语义（如梁上青/上古青萍 N=2）
     *
     * 与 applyHpOverflow 的区别：
     *   - HP overflow 走 (1-O/C) 边际衰减曲线（玩家心智模型："越满越难吸"）
     *   - MP overflow 不衰减、纯硬封顶（设计语义："蓄电池可超充，但有最大容量"）
     *
     * @param target    目标对象（需有 hp 字段判存活、mp 字段被修改）
     * @param amount    请求恢复量
     * @param mpBase    MP 基准（通常 = target.mp满血值）
     * @param capRatio  超充倍率（≥1.0；< 1 视为 1 防御）
     * @return 实际恢复量；0 表示无效
     */
    public static function applyMpOverflow(target:Object, amount:Number, mpBase:Number, capRatio:Number):Number {
        if (!target) return 0;
        if (target.hp <= 0) return 0;
        if (!(amount > 0)) return 0;
        if (!(mpBase > 0)) return 0;
        if (!(capRatio >= 1)) capRatio = 1; // 同时挡 NaN / <1 / 0

        var capValue:Number = mpBase * capRatio;
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
