// org/flashNight/arki/component/Buff/BuffCalculationType.as
class org.flashNight.arki.component.Buff.BuffCalculationType {
    public static var ADD:String = "add";           // 加算: 在乘法之后应用，对应老系统"加算"
    public static var MULTIPLY:String = "multiply"; // 乘算: base * value，对应老系统"倍率"
    public static var PERCENT:String = "percent";   // 百分比: base * (1 + value)
    public static var OVERRIDE:String = "override"; // 覆盖: value
    public static var MAX:String = "max";           // 取最大值: Math.max(base, value)，最小保底
    public static var MIN:String = "min";           // 取最小值: Math.min(base, value)，最大封顶

    /**
     * 计算顺序（对齐老系统语义: 基础值 × 倍率 + 加算）:
     * 1. MULTIPLY (乘算) - 直接乘数，对应老系统"倍率"
     * 2. PERCENT (百分比) - result *= (1 + value)
     * 3. ADD (加算) - 在乘法之后加算，对应老系统"加算"
     * 4. MAX (最小保底) - 确保结果不低于某值
     * 5. MIN (最大封顶) - 确保结果不超过某值
     * 6. OVERRIDE (覆盖) - 直接设置为指定值
     *
     * 语义对齐说明:
     * - 老系统公式: 基础值 × 倍率 + 加算
     * - 新系统公式: 基础值 × MULTIPLY × (1+PERCENT) + ADD
     *
     * 这种设计可以有效抑制数值膨胀：
     * - 加算(ADD)是固定值，不会被乘法放大
     * - 乘法(MULTIPLY)只影响基础值，不会放大加算部分
     *
     * 使用示例:
     * - 老系统 buff.赋值("防御力", "倍率", 1.2) → 新系统 MULTIPLY, 1.2
     * - 老系统 buff.赋值("防御力", "加算", 50) → 新系统 ADD, 50
     * - 老系统 buff.调整("攻击力", "倍率", 0.1) → 新系统 PERCENT, 0.1 (增量转百分比)
     */
}
