import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * MultiShotDamageHandle 类是用于处理联弹伤害的处理器。
 * - 当子弹具有联弹属性且不穿刺时，根据子弹的霰弹值、目标的血量和损伤值，计算实际消耗的霰弹值。
 * - 更新子弹的霰弹值和目标的损伤值，并将结果存储在 DamageResult 中。
 */
class org.flashNight.arki.component.Damage.MultiShotDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========

    /** 单例实例 */
    public static var instance:MultiShotDamageHandle = new MultiShotDamageHandle();

    // ========== 随机数引擎（联弹分段躲闪建模用） ==========

    private static var RNG:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

    // 预分配的采样结果数组（避免每次调用时创建新数组）
    // [missCount, bounceCount, penCount, instantCount]
    private static var sampleCounts:Array = [0, 0, 0, 0];

    // ========== 构造函数 ==========

    /**
     * 构造函数。
     * 调用父类构造函数以初始化基类。
     */
    public function MultiShotDamageHandle() {
        super();
    }

    /**
     * 获取 MultiShotDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 MultiShotDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return MultiShotDamageHandle 单例实例
     */
    public static function getInstance():MultiShotDamageHandle {
        if (instance == null) {
            instance = new MultiShotDamageHandle();
            getInstance = function():MultiShotDamageHandle {
                return instance;
            };
        }
        return instance;
    }

    // ========== 公共方法 ==========

    /**
     * 判断子弹是否具有联弹属性
     *
     * 历史变更：
     * - 早期版本：判断条件为 bullet.联弹检测 && !bullet.穿刺检测（联弹且不穿刺）
     * - 位运算优化：使用位标志 FLAG_CHAIN 替代布尔属性检测，提升性能
     * - 当前版本：仅检测联弹标志，穿刺处理逻辑移至 handleBulletDamage 中
     *
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有联弹属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        // 使用位标志优化联弹检测性能
        // FLAG_CHAIN 为联弹属性的位掩码
        #include "../macros/FLAG_CHAIN.as"
        return (bullet.flags & FLAG_CHAIN) != 0;
    }

    /**
     * 处理联弹伤害
     *
     * 核心功能：
     * - 根据子弹霰弹值、目标血量和损伤值计算实际消耗
     * - 使用影子记账机制优化对群手感
     * - 支持纵向穿刺联弹的覆盖率削弱
     *
     * 性能优化（2025年9月）：
     * - 信任BulletQueueProcessor的初始化，移除冗余检查
     * - 使用位运算优化类型检测和数值计算
     * - 简化为单一快速路径，减少分支判断
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象
     * @param result  伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 位标志常量注入（编译时零开销）
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_VERTICAL.as"
        #include "../macros/FLAG_NORMAL.as"
        #include "../macros/FLAG_TRANSPARENCY.as"

        var PIERCE_AND_VERTICAL_MASK:Number = FLAG_PIERCE | FLAG_VERTICAL;
        var RELEVANT_BITS_MASK:Number = FLAG_NORMAL | FLAG_TRANSPARENCY;
        var EXPECTED_STATE:Number = FLAG_NORMAL;

        var overlapRatio:Number = manager.overlapRatio;
        var isNormalNonTransparent:Boolean = (bullet.flags & RELEVANT_BITS_MASK) == EXPECTED_STATE;
        // 临时用的防御，仅在测试路径使用
        var hasDeferredSnapshot:Boolean = (bullet.__dfScatterBase != undefined);

        // DodgeStateDamageHandle 若提前退出，会设置该标记：联弹需要在此处做分段躲闪建模（方案B）
        var useSegmentDodgeModel:Boolean = (result.deferChainDodgeState === true);

        // 获取霰弹值（根据是否有影子记账选择数据源）
        var currentScatter:Number, scatterBase:Number, scatterForCalc:Number;

        if (hasDeferredSnapshot && isNormalNonTransparent) {
            // 影子记账模式：BulletQueueProcessor已保证数据有效
            scatterBase = bullet.__dfScatterBase;
            scatterForCalc = scatterBase;

        } else {
            // 直接模式：使用当前霰弹值
            currentScatter = bullet.霰弹值 || 0;
            scatterForCalc = currentScatter;
        }

        // 纵向穿刺削弱（覆盖率降至39%）
        if ((bullet.flags & PIERCE_AND_VERTICAL_MASK) == PIERCE_AND_VERTICAL_MASK) {
            overlapRatio = overlapRatio * 7 / 18;
        }

        // 核心伤害计算
        var A:Number = bullet.最小霰弹值 + overlapRatio * (scatterForCalc - bullet.最小霰弹值 + 1) * 1.2;
        var B:Number;

        var rawDamage:Number, bounceDamage:Number, penetrationDamage:Number;
        var dodgeProb:Number, bounceProb:Number;

        if (useSegmentDodgeModel) {
            rawDamage = target.损伤值;
            if (rawDamage != rawDamage) rawDamage = 0;

            var def:Number = target.防御力;

            // 跳弹/过穿单段伤害（内联，避免函数调用开销）
            var t:Number = (rawDamage - (def / 5)) | 0;
            bounceDamage = (t < 1) ? 1 : t;
            t = (rawDamage * 300 / (def + 300)) >> 0;
            penetrationDamage = (t < 1) ? 1 : t;

            // 躲闪系统内：MISS概率（与 DodgeHandler.checkDodgeState 一致）
            var weight:Number = target.重量;
            var tmp:Number = (target.等级 - weight);
            dodgeProb = (tmp < 0) ? 0 : ((tmp > 100) ? 1 : (tmp / 100));
            if (dodgeProb != dodgeProb) dodgeProb = 0;

            // 躲闪系统内：跳弹概率（条件于未MISS，逻辑与 DodgeHandler.checkDodgeState 一致）
            tmp = weight - DodgeHandler.PENETRATION_BASE_WEIGHT;
            bounceProb = (tmp < 0) ? 0 : (weight >= DodgeHandler.JUMP_BOUNCE_BASE_WEIGHT ? 1 : (tmp / DodgeHandler.BOUNCE_PENETRATION_RANGE_WEIGHT));
            if (bounceProb != bounceProb) bounceProb = 0;

            // 期望单段伤害（系统内）：用于估算B（命中段数）
            var expectedPelletDamage:Number = (1 - dodgeProb) * (bounceProb * bounceDamage + (1 - bounceProb) * penetrationDamage);
            B = (expectedPelletDamage > 0) ? (target.hp / expectedPelletDamage) : target.hp;

        } else {
            B = target.损伤值 > 0 ? target.hp / target.损伤值 : target.hp;
        }
        var C:Number = A < B ? A : B;
        var ceilC:Number = (C > (C >> 0)) ? (C >> 0) + 1 : (C >> 0);

        // 计算实际消耗
        var availableScatter:Number;
        if (hasDeferredSnapshot && isNormalNonTransparent) {
            // 影子记账模式：从基准值减去已累计的消耗
            availableScatter = scatterBase - (bullet.__dfScatterPending || 0);
            if (availableScatter < 0) availableScatter = 0;
        } else {
            availableScatter = currentScatter;
        }
        var actualScatterUsed:Number = availableScatter < ceilC ? availableScatter : ceilC;

        // 向上取整避免0段
        if (actualScatterUsed < 1) actualScatterUsed = 1;

        // 更新霰弹值
        if (hasDeferredSnapshot && isNormalNonTransparent) {
            // 影子记账更新：累加消耗并计算剩余值
            bullet.__dfScatterPending = (bullet.__dfScatterPending || 0) + actualScatterUsed;
            var remaining:Number = scatterBase - bullet.__dfScatterPending;
            if (remaining < 0) remaining = 0;
            result.finalScatterValue = remaining;
        } else if (isNormalNonTransparent) {
            // 直接更新
            bullet.霰弹值 = currentScatter - actualScatterUsed;
            if (bullet.霰弹值 < 0) bullet.霰弹值 = 0;
            result.finalScatterValue = bullet.霰弹值;
        } else {
            // 非普通子弹不消耗霰弹值
            result.finalScatterValue = currentScatter;
        }

        // 设置结果
        result.actualScatterUsed = actualScatterUsed;

        // ==================== 方案B：联弹分段躲闪建模 ====================
        // 将联弹视作"n次独立命中试验"的统计模型：每段独立进入躲闪系统，
        // 并在系统内落在{直感(懒闪避)/MISS/跳弹/过穿}四类之一。
        // 这样在不生成多发真实子弹的前提下，让联弹更贴近多发子弹的数值/视觉表现。
        if (useSegmentDodgeModel) {
            // ========== 计算各类别概率 ==========
            // 躲闪系统内概率分布：
            // 1. P(直感) - 懒闪避概率，基于单段伤害而非整串伤害
            // 2. P(MISS) - 传统躲闪概率
            // 3. P(跳弹) - 条件于未躲闪
            // 4. P(过穿) - 剩余概率

            // 计算懒闪避概率（基于单段伤害）
            var lazyMissValue:Number = target.懒闪避;
            var instantProb:Number = 0;
            if (lazyMissValue > 0) {
                // 使用单段期望伤害计算懒闪避概率
                // 这确保联弹的每段按其实际伤害（而非整串伤害）进行懒闪避判定
                var perPelletDamage:Number = (bounceProb * bounceDamage + (1 - bounceProb) * penetrationDamage);
                instantProb = RNG.calcLazyMissProbability(target.hp, target.hp满血值, lazyMissValue, perPelletDamage);
            }

            // 系统内概率：归一化后的 P(MISS)、P(跳弹)
            // 注意：各概率在非直感情况下需要重新归一化
            var pMiss:Number = dodgeProb;
            var pBounce:Number = (1 - dodgeProb) * bounceProb;
            // pPenetration = (1 - dodgeProb) * (1 - bounceProb) = 1 - pMiss - pBounce

            // ========== 四类别多项式采样 ==========
            // 使用优化的 multinomialSample4 方法：
            // - n ≤ 16 时直接循环（低开销）
            // - n > 16 时使用高斯近似（O(1) 复杂度）
            RNG.multinomialSample4(actualScatterUsed, pMiss, pBounce, instantProb, sampleCounts);

            var missCount:Number = sampleCounts[0];
            var bounceCount:Number = sampleCounts[1];
            var penCount:Number = sampleCounts[2];
            var instantCount:Number = sampleCounts[3];

            // ========== 汇总主伤害 ==========
            // 只有跳弹和过穿造成伤害，MISS和直感不造成伤害
            var totalDamage:Number = bounceCount * bounceDamage + penCount * penetrationDamage;
            target.损伤值 = totalDamage;

            // ========== 颜色选择 ==========
            // 无法逐段染色，取占比最高的分支作为整串颜色（近似）
            // 优先级：直感(淡紫) > 跳弹(暗红/暗黄) > 过穿(浅红/浅黄)
            var hitCount:Number = bounceCount + penCount;
            if (instantCount > hitCount && instantCount > missCount) {
                // 直感占主导：使用淡紫色（与单发直感一致的视觉反馈）
                result.setDamageColor(bullet.是否为敌人 ? "#9966CC" : "#CC99FF");
            } else if (bounceCount >= penCount) {
                result.setDamageColor(bullet.是否为敌人 ? "#7F0000" : "#7F6A00");
            } else {
                result.setDamageColor(bullet.是否为敌人 ? "#FF7F7F" : "#FFE770");
            }

            // ========== 近似缩放伤害数字大小 ==========
            // 对齐旧的跳弹/过穿视觉反馈
            var denom:Number = actualScatterUsed * rawDamage;
            if (denom > 0) {
                result.damageSize *= (0.5 + 0.5 * (totalDamage / denom));
            }

            // ========== 将分布信息写入 DamageResult ==========
            // 最终在 calculateScatterDamage 中生成 n 个数字（并与护盾/额外伤害对齐）
            result.scatterModelEnabled = true;
            result.scatterNormalCount = 0;
            result.scatterBounceCount = bounceCount;
            result.scatterPenetrationCount = penCount;
            result.scatterMissCount = missCount + instantCount; // MISS和直感合并显示为MISS
            result.scatterNormalDamage = 0;
            result.scatterBounceDamage = bounceDamage;
            result.scatterPenetrationDamage = penetrationDamage;

        } else {
            // 旧行为：直接按段数放大本次伤害
            target.损伤值 *= actualScatterUsed;
        }
        // ==================== 分段躲闪建模结束 ====================
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "MultiShotDamageHandle";
    }
}
