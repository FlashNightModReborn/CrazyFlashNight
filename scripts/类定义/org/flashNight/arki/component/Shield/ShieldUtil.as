// File: org/flashNight/arki/component/Shield/ShieldUtil.as

/**
 * ShieldUtil 护盾系统工具类。
 * 提供护盾相关的静态计算方法。
 *
 * 【设计目的】
 * 将通用计算逻辑从护盾类中提取出来，便于复用和维护。
 * 同时减少类实例方法，降低内存占用。
 */
class org.flashNight.arki.component.Shield.ShieldUtil {

    // ==================== 常量 ====================

    /** 抗性加成最大值 */
    public static var RESISTANCE_MAX:Number = 30;

    /** 抗性计算基数 */
    public static var RESISTANCE_BASE:Number = 100;

    /** 排序优先级：强度权重 */
    public static var SORT_STRENGTH_WEIGHT:Number = 10000;

    /** 排序优先级：ID权重 */
    public static var SORT_ID_WEIGHT:Number = 0.001;

    // ==================== 抗性计算 ====================

    /**
     * 根据护盾强度计算额外属性抗性加成。
     *
     * 【公式】
     * bonus = strength / (strength + 100) * 30
     *
     * 【数值示例】
     * 强度50  -> 10%抗性
     * 强度100 -> 15%抗性
     * 强度200 -> 20%抗性
     * 强度500 -> 25%抗性
     *
     * @param strength 护盾强度
     * @return Number 额外抗性百分比(0-30)
     */
    public static function calcResistanceBonus(strength:Number):Number {
        if (strength <= 0) return 0;
        return strength / (strength + RESISTANCE_BASE) * RESISTANCE_MAX;
    }

    // ==================== 排序优先级 ====================

    /**
     * 计算护盾的排序优先级。
     *
     * 【排序规则】
     * 1. 强度高者优先 (strength * 10000)
     * 2. 强度相同时，填充速度低者优先 (-rechargeRate)
     * 3. 以上都相同时，ID小者优先 (-id * 0.001)
     *
     * 【Infinity 处理】
     * 当 strength 为 Infinity 时，直接乘法会导致结果为 Infinity，
     * 使得多个 Infinity 护盾无法按 rechargeRate/id 区分。
     *
     * 解决方案：使用 1e12 作为基数代替 Infinity * 10000。
     * 必须使用 1e12 而非 1e18，因为 IEEE-754 双精度浮点数有效位数约 15-17 位，
     * 1e18 减去小数（如 rechargeRate=10）会因精度丢失而无法区分。
     * 1e12 保证 rechargeRate（通常 < 1000）和 id * 0.001（通常 < 1000）的差值可被正确比较。
     *
     * @param strength 护盾强度
     * @param rechargeRate 填充速度
     * @param id 护盾ID
     * @return Number 排序优先级
     */
    public static function calcSortPriority(strength:Number, rechargeRate:Number, id:Number):Number {
        // Infinity/极大强度使用 1e12 基数（保证浮点精度足够区分次级排序）
        // 阈值 1e8（1亿强度），对应正常优先级上限 1e8 * 10000 = 1e12
        // Infinity 基数也是 1e12，两者在边界处平滑过渡
        if (strength >= 1e8) {
            return 1e12 - rechargeRate - id * SORT_ID_WEIGHT;
        }
        return strength * SORT_STRENGTH_WEIGHT - rechargeRate - id * SORT_ID_WEIGHT;
    }

    // ==================== 伤害计算 ====================

    /**
     * 计算护盾可吸收的伤害量。
     *
     * @param damage 输入伤害
     * @param strength 护盾强度
     * @param capacity 当前容量
     * @return Number 可吸收量
     */
    public static function calcAbsorbable(damage:Number, strength:Number, capacity:Number):Number {
        var absorbable:Number = damage;
        if (absorbable > strength) absorbable = strength;
        if (absorbable > capacity) absorbable = capacity;
        return absorbable;
    }

    // ==================== 边界检查 ====================

    /**
     * 将容量限制在有效范围内。
     *
     * @param capacity 当前容量
     * @param maxCapacity 最大容量
     * @return Number 限制后的容量
     */
    public static function clampCapacity(capacity:Number, maxCapacity:Number):Number {
        if (capacity < 0) return 0;
        if (capacity > maxCapacity) return maxCapacity;
        return capacity;
    }

    /**
     * 将容量限制在目标容量和最大容量内。
     *
     * @param capacity 当前容量
     * @param targetCapacity 目标容量
     * @param maxCapacity 最大容量
     * @return Number 限制后的容量
     */
    public static function clampToTarget(capacity:Number, targetCapacity:Number, maxCapacity:Number):Number {
        if (capacity > targetCapacity) capacity = targetCapacity;
        if (capacity > maxCapacity) capacity = maxCapacity;
        return capacity;
    }
}
