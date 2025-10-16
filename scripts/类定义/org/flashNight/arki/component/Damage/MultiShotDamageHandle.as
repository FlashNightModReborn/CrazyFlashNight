import org.flashNight.arki.component.Damage.*;

/**
 * MultiShotDamageHandle 类是用于处理联弹伤害的处理器。
 * - 当子弹具有联弹属性且不穿刺时，根据子弹的霰弹值、目标的血量和损伤值，计算实际消耗的霰弹值。
 * - 更新子弹的霰弹值和目标的损伤值，并将结果存储在 DamageResult 中。
 */
class org.flashNight.arki.component.Damage.MultiShotDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========

    /** 单例实例 */
    public static var instance:MultiShotDamageHandle = new MultiShotDamageHandle();

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
        var B:Number = target.损伤值 > 0 ? target.hp / target.损伤值 : target.hp;
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
        target.损伤值 *= actualScatterUsed;
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