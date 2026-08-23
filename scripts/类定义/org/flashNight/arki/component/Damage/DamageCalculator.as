/**
 * DamageCalculator 计算伤害的核心类
 *
 * 本类包含静态方法 calculateDamage，用于计算子弹击中目标后的伤害值，
 * 并更新目标血量及相关状态。血量结算使用 Number 域，不把合法的大血量压入
 * signed-int32；只有显示等明确的 32 位字段仍可使用位运算取整。
 *
 * 详细说明：
 * 1. 参数说明：
 *    - bullet: 子弹对象，使用了内部以下属性：
 *         • damageManager：伤害管理器对象，用于后续伤害执行。
 *         • 子弹威力：子弹的基础威力。
 *         • 破坏力：最终计算得到的破坏力，会在方法中重新计算。
 *         • 百分比伤害：用于根据目标血量计算附加伤害的百分比。
 *         • 固伤：固定附加伤害值。
 *         • 霰弹值：对联弹会在DamageResult内使用模拟的方法创建伤害显示。
 *    - shooter: 射手对象，包含伤害加成等属性（伤害加成利用按位或(|)操作符确保转换为整数）。
 *    - hitTarget: 被击中的目标对象，包含以下属性：
 *         • hp: 目标血量。
 *         • 防御力: 防御属性，若值不大于0则被重置为1，以防止异常情况。
 *         • 无敌、man.无敌标签、NPC: 目标状态标识，满足任一条件则视为无效攻击（不计算伤害）。
 *         • 损伤值: 在执行伤害后计算得到的伤害量，用于更新目标血量和伤害显示计算。
 *         • damageTakenMultiplier: 承伤系数，默认为1，可通过BuffManager调整。
 *    - overlapRatio: 子弹与目标的重叠比例，用于影响伤害管理器中的计算。
 *    - dodgeState: 目标闪避状态，同样传递给伤害管理器。
 *
 * 2. 伤害计算流程：
 *    - 更新 DamageManager 的 overlapRatio 和 dodgeState 属性。
 *    - 检查目标是否处于无敌状态（包括 hitTarget.无敌、hitTarget.man.无敌标签 或 hitTarget.NPC），
 *      若满足则直接返回空伤害（DamageResult.NULL）。
 *    - 获取目标当前血量 (hp) 并判断是否小于等于 0，若是则返回空伤害结果。
 *    - 通过 DamageResult.getIMPACT() 方法获取一个 DamageResult 对象，
 *      该对象将存储伤害计算后的结果。
 *    - 判断目标的防御力是否大于 0，若不满足则将防御力重置为 1。这里利用隐式转换：若 hitTarget.防御力 为
 *      undefined 或其他非正数，逻辑判断会进入条件分支，从而实现异常防护。
 *    - 计算子弹基础破坏力：将子弹威力与射手的伤害加成相加，其中 (shooter.伤害加成 | 0)
 *      利用按位或操作符将可能为 undefined 或浮点数的伤害加成转换为整数，确保计算的一致性。
 *    - 伤害波动：破坏力乘以 PinkNoiseEngine 随机波动系数（0.85~1.15），增加游戏随机性。
 *    - 计算百分比伤害：
 *         如果 bullet.百分比伤害 大于 0，则计算百分比伤害为 (hp * bullet.百分比伤害 / 100)；
 *         否则设置百分比伤害为 0。
 *    - 最终子弹破坏力重新计算为：(damageVariance + bullet.固伤 + percentageDamage) * damageTakenMultiplier。
 *    - 【承伤系数】hitTarget.damageTakenMultiplier 用于统一控制目标承受伤害的倍率：
 *         • 默认值为 1（正常承伤）
 *         • 小于 1 表示减伤（如 0.5 = 减伤50%）
 *         • 大于 1 表示增伤（如 1.5 = 增伤50%）
 *         • 可通过 BuffManager 动态调整，实现霸体减伤、易伤增伤等效果
 *    - 调用 manager.execute() 方法执行伤害计算，将 bullet、shooter、hitTarget 和 damageResult 传递进去，
 *      由内部逻辑决定最终的损伤值 (hitTarget.损伤值)。
 *    - 将 hitTarget.损伤值 存入局部变量 damageNumber，以便后续使用。
 *    - 【护盾吸收】在扣血前，调用目标护盾的 absorbDamage 方法：
 *         • 真伤类型 (bullet.伤害类型 === "真伤") 会尝试绕过护盾（bypassShield = true）
 *         • 使用 damageResult.actualScatterUsed（实际消耗的霰弹值）作为联弹段数
 *         • absorbDamage 返回穿透护盾后的剩余伤害，并更新 hitTarget.损伤值
 *    - 调用 damageResult.calculateScatterDamage() 方法对散射伤害进行进一步计算，
 *      参数为 damageNumber（已经过护盾吸收处理）。
 *    - 更新目标血量 (hitTarget.hp)：在 Number 域做减法与向下取整，再把非正结果夹到 0；
 *      这样 hp 超过 2^31-1 时不会因 signed-int32 回绕而瞬间归零。
 *
 * 3. 性能与代码技巧说明：
 *    - 通过局部变量缓存常用属性（例如 damageNumber）可以减少对象属性查找次数，提高运行效率。
 *    - 常规正数且结果不超过 signed-int32 上限时继续用位运算快路取整；
 *      超大调试 HP 与异常值才进入 Number 安全慢路，不能发生 signed-int32 回绕。
 *
 */
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.naki.RandomNumberEngine.*;
class org.flashNight.arki.component.Damage.DamageCalculator {

    /**
     * 在 Number 域结算扣血，保留超过 2^31-1 的合法 HP。
     * 非正/NaN 伤害按 0 处理；正无穷伤害仍视为致死，异常当前 HP 则安全归零。
     */
    public static function calculateRemainingHp(currentHp:Number, damage:Number):Number {
        if (!(currentHp > 0)) return 0;

        if (damage > 0) {
            var remainingHp:Number = currentHp - damage;
            if (!(remainingHp > 0)) return 0;

            // 绝大多数命中留在原有 signed-int32 安全快路。
            if (remainingHp <= 2147483647) return remainingHp | 0;

            // 超大调试 HP 才付 Number 域校验与取整成本。
            if (!isFinite(remainingHp)) return 0;
            return Math.floor(remainingHp);
        }

        // 非正/NaN 伤害不扣血；同样优先走常规整数快路。
        if (currentHp <= 2147483647) return currentHp | 0;
        if (!isFinite(currentHp)) return 0;
        return Math.floor(currentHp);
    }

    /**
     * 击溃降低 live 满血值后，HP 比例不得越过受击前已经合法持有的比例。
     * 该门只在本次确有击溃时启用；普通伤害、吸血与其他治疗仍完全由
     * HealApplier 的溢出曲线管理，不做全局 HP clamp。
     */
    private static function enforceCrumbleHpInvariant(remainingHp:Number,
                                                       liveMaxHp:Number,
                                                       preHitHpRatio:Number,
                                                       crumbleDamage:Number):Number {
        if (!(crumbleDamage > 0) || !isFinite(crumbleDamage)) return remainingHp;
        if (!(liveMaxHp > 0) || !isFinite(liveMaxHp)) return 0;
        if (!(preHitHpRatio > 0) || !isFinite(preHitHpRatio)) return 0;

        var allowedHp:Number = liveMaxHp * preHitHpRatio;
        if (!(allowedHp > 0) || !isFinite(allowedHp)) return 0;
        if (remainingHp > allowedHp) return Math.floor(allowedHp);
        return remainingHp;
    }

    /**
     * 计算伤害值并更新目标状态的静态方法。
     *
     * @param bullet       子弹对象，包含威力、百分比伤害、固伤、霰弹值等属性，
     *                     以及一个 DamageManager 对象，用于执行伤害计算逻辑。
     * @param shooter      射手对象，包含伤害加成等属性，用于影响子弹破坏力的计算。
     * @param hitTarget    被击中目标对象，包含血量 (hp)、防御力、无敌状态（无敌、无敌标签）、
     *                     NPC 标识和损伤值，决定是否进行伤害计算以及如何更新目标血量。
     * @param overlapRatio 子弹与目标的重叠比例，传递给 DamageManager 用于计算时考虑重叠影响。
     * @param dodgeState   目标的闪避状态，同样传递给 DamageManager 以影响最终伤害。
     * @return DamageResult 返回一个 DamageResult 对象，记录本次伤害计算的详细结果。
     */
    public static function calculateDamage(bullet, shooter, hitTarget, overlapRatio, dodgeState):DamageResult {
        // 获取子弹关联的 DamageManager 对象
        var manager:DamageManager = bullet.damageManager;

        // 设置伤害管理器中的重叠比例与闪避状态
        manager.overlapRatio = overlapRatio;
        manager.dodgeState = dodgeState;

        // 判断目标是否处于无敌状态：直接返回空伤害结果
        if (hitTarget.无敌 || hitTarget.man.无敌标签 || hitTarget.NPC) {
            return DamageResult.NULL; 
        }

        // 获取目标当前血量
        var hp:Number = hitTarget.hp;

        // 如果目标血量已耗尽，则返回空伤害结果
        if (hp <= 0) return DamageResult.NULL;

        // 获取一个 DamageResult 对象（联弹使用专用 IMPACT，避免普通热路径额外字段清洗）
        #include "../macros/FLAG_CHAIN.as"
        var damageResult:DamageResult = ((bullet.flags & FLAG_CHAIN) != 0) ? DamageResult.getIMPACT_CHAIN() : DamageResult.getIMPACT();

        // 检查目标防御力，如果未定义或小于等于0，则将其重置为1
        // 此处利用隐式转换：undefined 在逻辑判断中视为 false，从而进入异常防护分支
        if(!(hitTarget.防御力 > 0)) hitTarget.防御力 = 1;

        // 计算子弹基础破坏力：子弹威力加上射手的伤害加成
        // 使用 (shooter.伤害加成 | 0) 来确保伤害加成为整数（按位或操作符会隐式转换非数值为0）
        bullet.破坏力 = bullet.子弹威力 + (shooter.伤害加成 | 0);
        
        // 伤害波动：破坏力在 0.85~1.15 倍之间随机波动
        var damageVariance:Number = bullet.破坏力 * PinkNoiseEngine.instance.randomFluctuation(15);
        
        // 计算百分比伤害：若子弹的百分比伤害属性大于0，则根据目标血量计算百分比伤害，否则为0
        var percentageDamage:Number;
        if(!(bullet.百分比伤害 > 0))
        {
            percentageDamage = 0;
        } else {
            percentageDamage = hp * bullet.百分比伤害 / 100;
        }
        
        // 最终子弹破坏力为伤害波动、固伤和百分比伤害之和
        bullet.破坏力 = damageVariance + bullet.固伤 + percentageDamage;

        // ==================== 承伤系数应用 ====================
        // damageTakenMultiplier: 目标的承伤系数，影响所有后续伤害计算
        // - 默认值为 1（正常承伤）
        // - 小于 1 表示减伤（如霸体状态 0.5 = 减伤50%）
        // - 大于 1 表示增伤（如易伤状态 1.5 = 增伤50%）
        // - 通过 BuffManager 管理，支持多源叠加
        var damageTakenMultiplier:Number = hitTarget.damageTakenMultiplier;
        if (damageTakenMultiplier != 1 && damageTakenMultiplier > 0) {
            bullet.破坏力 *= damageTakenMultiplier;
        }
        // ==================== 承伤系数应用结束 ====================

        // 执行伤害计算，通过 DamageManager 处理，更新目标的损伤值等信息
        manager.execute(bullet, shooter, hitTarget, damageResult);

        // 显式终结弹的专用 manager 只会在 actual 后提交 hp=0。先判 HP 可让绝大多数
        // 普通命中短路，避免为极少数终结弹在 DamageResult 热复用槽增加每发清零写入。
        if (hitTarget.hp <= 0 && bullet.实际命中强制击杀 === true) return damageResult;

        // 将目标的损伤值存入局部变量 damageNumber，以便后续使用
        var damageNumber:Number = hitTarget.损伤值;

        // ==================== 护盾伤害吸收 ====================
        // 护盾系统接入点：在伤害计算完成后、扣血前处理护盾吸收
        // - 真伤类型 (bullet.伤害类型 === "真伤") 会尝试绕过护盾
        // - 使用 damageResult.actualScatterUsed 作为联弹段数（由 MultiShotDamageHandle 计算得出）
        // - absorbDamage 返回穿透护盾后的剩余伤害
        var shield:IShield = hitTarget.shield;

        // 调用护盾吸收：返回穿透伤害，原伤害被护盾部分或全部吸收。
        // 性能边界：不在 Calculator 再次分类极少发生的 resolved MISS，否则所有真实命中
        // 都要重复支付字符串/分段比较。MISS 的 damageNumber 为 0，仍可能触发旧盾 onHit(0)
        // 并重置回充；这是明确接受的稀有兼容误差，事件/视觉/冲击由 BQP 冷分支继续截断。
        // hitCount 使用实际消耗的霰弹值，而非子弹原始霰弹值
        var actualScatterUsed:Number = damageResult.actualScatterUsed;

        var crumbleDamage:Number = Number(damageResult._crumbleDamage);
        if (!(crumbleDamage > 0) || !isFinite(crumbleDamage)
                || !(damageNumber > 0) || !isFinite(damageNumber)) {
            // 无击溃热路径保持原有顺序，不计算比例、不拆分伤害。
            var normalPenetratingDamage:Number = shield.absorbDamage(
                damageNumber, bullet.伤害类型 === "真伤", actualScatterUsed);
            var normalAbsorbedDamage:Number = damageNumber - normalPenetratingDamage;
            if (normalAbsorbedDamage > 0) {
                damageResult._efFlags |= 256; // EF_SHIELD
                damageResult._efShieldAbsorb = (normalAbsorbedDamage / actualScatterUsed) | 0;
            }

            hitTarget.损伤值 = normalPenetratingDamage;
            damageResult.calculateScatterDamage(normalPenetratingDamage);
            hitTarget.hp = calculateRemainingHp(hp, normalPenetratingDamage);
            return damageResult;
        }

        // 击溃已经用 bullet.子弹威力 > shield.getStrength() 完成盾强门控。
        // 只把其余普通伤害交给容量盾；否则容量盾可以吸收击溃配对的当前 HP
        // 损失，却无法回滚已经发生的 hp满血值扣减。
        if (crumbleDamage > damageNumber) crumbleDamage = damageNumber;
        var shieldableDamage:Number = damageNumber - crumbleDamage;
        if (!(shieldableDamage > 0) || !isFinite(shieldableDamage)) shieldableDamage = 0;
        var shieldPenetratingDamage:Number = shield.absorbDamage(
            shieldableDamage, bullet.伤害类型 === "真伤", actualScatterUsed);

        // 如果护盾吸收了伤害，添加视觉反馈
        var absorbedDamage:Number = shieldableDamage - shieldPenetratingDamage;
        if (absorbedDamage > 0) {
            // 延迟 HTML 构建：护盾效果位标记 + 吸收量槽
            damageResult._efFlags |= 256; // EF_SHIELD
            damageResult._efShieldAbsorb = (absorbedDamage / actualScatterUsed) | 0;
        }

        // 更新损伤值以反映护盾吸收后的实际伤害
        damageNumber = shieldPenetratingDamage + crumbleDamage;
        hitTarget.损伤值 = damageNumber;
        // ==================== 护盾伤害吸收结束 ====================

        // 计算并应用散射伤害，传入目标的损伤值
        damageResult.calculateScatterDamage(damageNumber);

        // 先单独结算与 max-loss 配对的当前 HP 损失并维持受击前比例边界，
        // 再独立扣除普通穿透伤害；不能把两者合并后 clamp，否则会吞掉普通伤害。
        var liveMaxHp:Number = Number(hitTarget.hp满血值);
        var preHitMaxHp:Number = liveMaxHp + crumbleDamage;
        var preHitHpRatio:Number =
            org.flashNight.arki.unit.Action.Regeneration.HealApplier.calculateSafeHpRatio(
                hp, preHitMaxHp);
        var crumbleRemainingHp:Number = calculateRemainingHp(hp, crumbleDamage);
        var constrainedCrumbleHp:Number = enforceCrumbleHpInvariant(
            crumbleRemainingHp, liveMaxHp, preHitHpRatio, crumbleDamage);
        hitTarget.hp = calculateRemainingHp(constrainedCrumbleHp, shieldPenetratingDamage);

        // 返回本次伤害计算的结果对象
        return damageResult;
    }
}
