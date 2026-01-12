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

            // 缓存类级常量（避免重复属性查找开销）
            var PENETRATION_BASE:Number = DodgeHandler.PENETRATION_BASE_WEIGHT;
            var BOUNCE_BASE:Number = DodgeHandler.JUMP_BOUNCE_BASE_WEIGHT;
            var BOUNCE_RANGE:Number = DodgeHandler.BOUNCE_PENETRATION_RANGE_WEIGHT;

            // 躲闪系统内：跳弹概率（条件于未MISS，逻辑与 DodgeHandler.checkDodgeState 一致）
            tmp = weight - PENETRATION_BASE;
            bounceProb = (tmp < 0) ? 0 : (weight >= BOUNCE_BASE ? 1 : (tmp / BOUNCE_RANGE));
            if (bounceProb != bounceProb) bounceProb = 0;

            // 躲闪系统内单段命中伤害期望（不考虑懒闪避）
            var hitDamageInDodgeSystem:Number = bounceProb * bounceDamage + (1 - bounceProb) * penetrationDamage;

            // 预计算懒闪避概率（用于期望伤害估算）
            // 注意：此处使用躲闪系统内的期望伤害来估算懒闪避触发概率
            var lazyMissValueForB:Number = target.懒闪避;
            var instantProbForB:Number = 0;
            if (lazyMissValueForB > 0) {
                instantProbForB = RNG.calcLazyMissProbability(target.hp, target.hp满血值, lazyMissValueForB, hitDamageInDodgeSystem);
            }

            // 期望单段伤害（考虑懒闪避）：
            // E[伤害] = P(非懒闪避) * P(非MISS|非懒闪避) * E[命中伤害]
            //         = (1 - instantProb) * (1 - dodgeProb) * hitDamageInDodgeSystem
            var expectedPelletDamage:Number = (1 - instantProbForB) * (1 - dodgeProb) * hitDamageInDodgeSystem;
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
        // 将联弹视作"n次独立命中试验"的统计模型。
        //
        // 【概率模型说明】
        // 原始流程中事件发生顺序：
        //   1. 懒闪避判定（独立于躲闪系统，优先级最高）
        //   2. 躲闪系统判定（进入后分为 MISS/跳弹/过穿）
        //
        // 四类别互斥概率分布（需归一化到和为1）：
        //   P(直感) = pInstant                           - 懒闪避触发
        //   P(MISS) = (1-pInstant) * dodgeProb           - 未懒闪避 → 躲闪系统 → MISS
        //   P(跳弹) = (1-pInstant) * (1-dodgeProb) * bounceProb   - 未懒闪避 → 躲闪系统 → 未MISS → 跳弹
        //   P(过穿) = (1-pInstant) * (1-dodgeProb) * (1-bounceProb) - 剩余
        if (useSegmentDodgeModel) {
            // ========== 计算懒闪避概率 ==========
            var lazyMissValue:Number = target.懒闪避;
            var instantProb:Number = 0;

            if (lazyMissValue > 0) {
                // 使用单段期望伤害（考虑躲闪系统内部分布）计算懒闪避概率
                // 单段期望伤害 = P(跳弹|命中) * 跳弹伤害 + P(过穿|命中) * 过穿伤害
                var perPelletDamage:Number = bounceProb * bounceDamage + (1 - bounceProb) * penetrationDamage;
                instantProb = RNG.calcLazyMissProbability(target.hp, target.hp满血值, lazyMissValue, perPelletDamage);
            }

            // ========== 计算归一化的四类别概率 ==========
            // 关键：必须保证 pInstant + pMiss + pBounce + pPen = 1
            var notInstant:Number = 1 - instantProb;
            var pMiss:Number = notInstant * dodgeProb;
            var pBounce:Number = notInstant * (1 - dodgeProb) * bounceProb;
            // pPen = notInstant * (1 - dodgeProb) * (1 - bounceProb) = 1 - pInstant - pMiss - pBounce

            // ========== 多项式采样 ==========
            var missCount:Number;
            var bounceCount:Number;
            var penCount:Number;
            var instantCount:Number;

            // 优化路径选择：
            // - instantProb == 0 时走三类别简化版本（省一次类别判定）
            // - n ≤ 24 时直接循环（游戏中霰弹值典型范围 3-20）
            // - n > 24 时使用高斯近似
            if (instantProb == 0) {
                // 无懒闪避：使用三类别采样
                RNG.multinomialSample3(actualScatterUsed, dodgeProb, (1 - dodgeProb) * bounceProb, sampleCounts);
                missCount = sampleCounts[0];
                bounceCount = sampleCounts[1];
                penCount = sampleCounts[2];
                instantCount = 0;
            } else {
                // 有懒闪避：使用四类别采样
                RNG.multinomialSample4(actualScatterUsed, pMiss, pBounce, instantProb, sampleCounts);
                missCount = sampleCounts[0];
                bounceCount = sampleCounts[1];
                penCount = sampleCounts[2];
                instantCount = sampleCounts[3];
            }

            // ========== 汇总主伤害 ==========
            // 只有跳弹和过穿造成伤害，MISS和直感不造成伤害
            var totalDamage:Number = bounceCount * bounceDamage + penCount * penetrationDamage;
            target.损伤值 = totalDamage;

            // ========== 颜色选择 ==========
            // 无法逐段染色，取占比最高的命中分支作为整串颜色
            if (bounceCount >= penCount) {
                result.setDamageColor(bullet.是否为敌人 ? "#7F0000" : "#7F6A00");
            } else {
                result.setDamageColor(bullet.是否为敌人 ? "#FF7F7F" : "#FFE770");
            }

            // ========== 近似缩放伤害数字大小 ==========
            var denom:Number = actualScatterUsed * rawDamage;
            if (denom > 0) {
                result.damageSize *= (0.5 + 0.5 * (totalDamage / denom));
            }

            // ========== 将分布信息写入 DamageResult ==========
            result.scatterModelEnabled = true;
            result.scatterNormalCount = 0;
            result.scatterBounceCount = bounceCount;
            result.scatterPenetrationCount = penCount;
            result.scatterMissCount = missCount + instantCount; // MISS和直感合并显示
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
