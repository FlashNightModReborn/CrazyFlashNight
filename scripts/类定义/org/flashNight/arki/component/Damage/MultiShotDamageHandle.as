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
     * 判断子弹是否具有联弹属性且不穿刺。
     * - 如果子弹的联弹检测为 true 且穿刺检测为 false，则返回 true。
     *
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有联弹属性且不穿刺则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        // _root.发布消息(!!(bullet.联弹检测 && !bullet.穿刺检测))
        return (bullet.联弹检测 && !bullet.穿刺检测);
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

        // 计算 A = bullet.最小霰弹值 + overlapRatio * (bullet.霰弹值 - bullet.最小霰弹值 + 1) * 1.2
        var A:Number = bullet.最小霰弹值 + overlapRatio * (bullet.霰弹值 - bullet.最小霰弹值 + 1) * 1.2;

        // 计算 B = target.hp / (target.损伤值 > 0 ? target.损伤值 : 1)
        var thp:Number = target.hp;
        var B:Number = target.损伤值 > 0 ? thp / target.损伤值 : thp;

        // 计算 min(A, B)
        var C:Number = A < B ? A : B;

        // 计算 ceil(C)
        // 使用位运算实现向下取整
        var floorC:Number = C >> 0;
        var ceilC:Number;
        if (C > floorC) {
            ceilC = floorC + 1;
        } else {
            ceilC = floorC;
        }
        // _root.发布消息( "A:" + A + ", B:" + B + ", ceilC:" + ceilC);

        // 计算 min(bullet.霰弹值, ceilC)
        var actualScatterUsed:Number;
        if (bullet.霰弹值 < ceilC) {
            actualScatterUsed = bullet.霰弹值;
        } else {
            actualScatterUsed = ceilC;
        }

        // 设置 DamageResult
        result.actualScatterUsed = actualScatterUsed;

        // 更新 bullet 和 target
        if(bullet.普通检测 && !bullet.透明检测) bullet.霰弹值 -= actualScatterUsed; // 只有非透明的普通子弹会降低联弹霰弹值
        result.finalScatterValue = bullet.霰弹值;

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