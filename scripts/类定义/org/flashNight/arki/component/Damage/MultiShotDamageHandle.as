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
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有联弹属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        // 使用位标志优化联弹检测性能
        #include "../macros/FLAG_CHAIN.as"
        return (bullet.flags & FLAG_CHAIN) != 0;
    }

    /**
     * 处理联弹伤害。
     * - 根据子弹的霰弹值、目标的血量和损伤值，计算实际消耗的霰弹值。
     * - 更新子弹的霰弹值和目标的损伤值，并将结果存储在 DamageResult 中。
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象
     * @param result  伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var overlapRatio:Number = manager.overlapRatio;
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_VERTICAL.as"
        #include "../macros/FLAG_NORMAL.as"
        #include "../macros/FLAG_TRANSPARENCY.as"

        var PIERCE_AND_VERTICAL_MASK:Number = FLAG_PIERCE | FLAG_VERTICAL;
        var RELEVANT_BITS_MASK:Number = FLAG_NORMAL | FLAG_TRANSPARENCY;
        var EXPECTED_STATE:Number = FLAG_NORMAL;

        var currentScatter:Number = (bullet.霰弹值 != undefined) ? Number(bullet.霰弹值) : 0;
        if (isNaN(currentScatter)) {
            currentScatter = 0;
        }

        var hasDeferredSnapshot:Boolean = (bullet.__dfScatterBase != undefined);
        var scatterBase:Number = hasDeferredSnapshot ? Number(bullet.__dfScatterBase) : currentScatter;
        if (isNaN(scatterBase)) {
            scatterBase = currentScatter;
        }

        var scatterShadow:Number = hasDeferredSnapshot ? ((bullet.__dfScatterShadow != undefined) ? Number(bullet.__dfScatterShadow) : scatterBase) : currentScatter;
        if (isNaN(scatterShadow)) {
            scatterShadow = scatterBase;
        }

        var isNormalNonTransparent:Boolean = (bullet.flags & RELEVANT_BITS_MASK) == EXPECTED_STATE;
        var useDeferred:Boolean = hasDeferredSnapshot && isNormalNonTransparent;
        var scatterForCalc:Number = useDeferred ? ((scatterBase + scatterShadow) * 0.5) : currentScatter;
        if (isNaN(scatterForCalc)) {
            scatterForCalc = currentScatter;
        }

        if ((bullet.flags & PIERCE_AND_VERTICAL_MASK) == PIERCE_AND_VERTICAL_MASK) 
        {
            overlapRatio = overlapRatio * 7 / 18;
        }

        var A:Number = bullet.最小霰弹值 + overlapRatio * (scatterForCalc - bullet.最小霰弹值 + 1) * 1.2;
        var thp:Number = target.hp;
        var B:Number = target.损伤值 > 0 ? thp / target.损伤值 : thp;
        var C:Number = A < B ? A : B;
        var floorC:Number = C >> 0;
        var ceilC:Number;
        if (C > floorC) {
            ceilC = floorC + 1;
        } else {
            ceilC = floorC;
        }

        var availableScatter:Number = useDeferred ? scatterShadow : currentScatter;
        if (isNaN(availableScatter) || availableScatter < 0) {
            availableScatter = 0;
        }

        var actualScatterUsed:Number;
        if (availableScatter < ceilC) {
            actualScatterUsed = availableScatter;
        } else {
            actualScatterUsed = ceilC;
        }
        if (isNaN(actualScatterUsed) || actualScatterUsed < 0) {
            actualScatterUsed = 0;
        }

        result.actualScatterUsed = actualScatterUsed;

        var finalScatter:Number = useDeferred ? scatterShadow : currentScatter;

        if (useDeferred) {
            var pendingScatter:Number = (bullet.__dfScatterPending != undefined) ? Number(bullet.__dfScatterPending) : 0;
            if (isNaN(pendingScatter)) {
                pendingScatter = 0;
            }
            pendingScatter += actualScatterUsed;
            bullet.__dfScatterPending = pendingScatter;

            var nextShadow:Number = scatterShadow - actualScatterUsed;
            if (isNaN(nextShadow) || nextShadow < 0) {
                nextShadow = 0;
            }
            bullet.__dfScatterShadow = nextShadow;
            finalScatter = nextShadow;
        } else if (isNormalNonTransparent) {
            currentScatter -= actualScatterUsed;
            if (currentScatter < 0) {
                currentScatter = 0;
            }
            bullet.霰弹值 = currentScatter;
            finalScatter = currentScatter;
        }

        result.finalScatterValue = finalScatter;

        // _root.发布消息("au:" + actualScatterUsed + ",fv:" + bullet.霰弹值 + ", dg:" + target.损伤值);

        // 乘以实际消耗霰弹值
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