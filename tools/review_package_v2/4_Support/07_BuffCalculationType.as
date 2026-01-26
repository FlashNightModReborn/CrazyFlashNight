// org/flashNight/arki/component/Buff/BuffCalculationType.as
class org.flashNight.arki.component.Buff.BuffCalculationType {
    // ==================== 通用语义（叠加型） ====================
    public static var ADD:String = "add";           // 通用加算: 累加所有值
    public static var MULTIPLY:String = "multiply"; // 通用乘算: 乘区相加后统一乘 base * (1 + Σ(m-1))
    public static var PERCENT:String = "percent";   // 百分比: base * (1 + Σp)

    // ==================== 保守语义（独占型） ====================
    public static var ADD_POSITIVE:String = "add_positive";     // 正向保守加法: 同类取max（用于正向buff）
    public static var ADD_NEGATIVE:String = "add_negative";     // 负向保守加法: 同类取min（用于负向debuff）
    public static var MULT_POSITIVE:String = "mult_positive";   // 正向保守乘法: 同类取max（用于增益乘数）
    public static var MULT_NEGATIVE:String = "mult_negative";   // 负向保守乘法: 同类取min（用于减益乘数）

    // ==================== 限制与覆盖 ====================
    public static var OVERRIDE:String = "override"; // 覆盖: 直接设置为指定值
    public static var MAX:String = "max";           // 取最大值: Math.max(result, value)，最小保底
    public static var MIN:String = "min";           // 取最小值: Math.min(result, value)，最大封顶

    /**
     * 计算顺序:
     * 1. MULTIPLY (通用乘算) - 乘区相加: base * (1 + Σ(multiplier - 1))
     * 2. MULT_POSITIVE (正向保守乘法) - 取极大值后乘
     * 3. MULT_NEGATIVE (负向保守乘法) - 取极小值后乘
     * 4. PERCENT (百分比) - result *= (1 + Σpercent)
     * 5. ADD (通用加算) - 累加所有值
     * 6. ADD_POSITIVE (正向保守加法) - 取极大值后加
     * 7. ADD_NEGATIVE (负向保守加法) - 取极小值后加
     * 8. MAX (最小保底) - 确保结果不低于某值
     * 9. MIN (最大封顶) - 确保结果不超过某值
     * 10. OVERRIDE (覆盖) - 直接设置为指定值
     *
     * 语义说明:
     * - 通用语义: 所有同类型buff叠加
     *   - MULTIPLY: 乘区相加 (3个10%增益 = 30%，而非33.1%)
     *   - ADD: 累加 (3个+100 = +300)
     *
     * - 保守语义: 同类型只取效果最强的一个
     *   - ADD_POSITIVE: 正向加法取max (200基础, 100词条, 300限时 → 只算300)
     *   - ADD_NEGATIVE: 负向加法取min (-50诅咒, -100虚弱 → 只算-100)
     *   - MULT_POSITIVE: 正向乘法取max (1.2, 1.5, 1.3 → 只算1.5)
     *   - MULT_NEGATIVE: 负向乘法取min (0.8, 0.6, 0.7 → 只算0.6)
     *
     * 数值膨胀控制:
     * - 加算(ADD)是固定值，不会被乘法放大
     * - 乘法(MULTIPLY)改为乘区相加，避免指数膨胀
     * - 保守语义确保同来源buff不叠加
     *
     * 使用示例:
     * - 装备基础属性: ADD_POSITIVE (同类装备不叠加)
     * - 技能增益: ADD_POSITIVE (同类技能不叠加)
     * - 叠层buff: ADD (允许累加)
     * - 速度倍率: MULT_POSITIVE (防止速度爆炸)
     * - 减速debuff: MULT_NEGATIVE (取最强减速)
     */
}
