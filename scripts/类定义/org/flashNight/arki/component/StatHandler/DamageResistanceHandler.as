/**
 * DamageResistanceHandler
 * 负责与防御、伤害计算相关的逻辑，包括但不限于：
 *  - 防御减伤比例
 *  - 跳弹伤害计算
 *  - 过穿伤害计算
 * 
 * 此类通过对常用公式的优化，避免不必要的函数调用，使用位运算等方法提高性能。
 */
class org.flashNight.arki.component.StatHandler.DamageResistanceHandler
{
    // 防御计算相关的基础数值
    // 性能优化角度硬编码，这里仅做注释
    // public static var BASE_DEF:Number = 300;

    // 跳弹模式相关系数
    // 性能优化角度硬编码，这里仅做注释
    // public static var BOUNCE_DEF_COEFF:Number = 5;
    
    /**
     * 防御减伤比例
     * 根据目标的防御力计算其伤害减免比例。
     * 
     * 公式：
     * \[
     * \text{防御减伤比} = \frac{300}{\text{防御力} + 300}
     * \]
     * 
     * - 类反比例公式，防御力基数较高时，可直接使用 hp * defense 来评估单位的等价生存力
     * - `300` 是固定参数，用于调整曲线的陡峭程度。
     * 
     * @param defense Number 防御力（非负值）
     * @return Number 减伤系数（0-1之间）
     */
    public static function defenseDamageRatio(defense:Number):Number
    {
        // 不使用内建函数计算，直接返回公式结果
        return 300 / (defense + 300);
    }

    /**
     * 跳弹伤害计算
     * 计算当伤害受到目标防御力影响后，跳弹机制下的最终伤害值。
     * 
     * 公式：
     * \[
     * \text{最终伤害} = \max\left(\left\lfloor \text{伤害值} - \frac{\text{防御力}}{5} \right\rfloor, 1\right)
     * \]
     * 
     * - **跳弹机制**：
     *   - 对于较高的防御力，部分伤害会被弹开，最终伤害值减少。
     *   - 伤害值最低为 1，确保不会完全被吸收。
     *   - 适合对抗弱火力密集弹幕。
     * 
     * - **公式分解**：
     *   - `t = damage - (defense / 5)`：计算基准伤害。
     *   - 使用 `| 0` 模拟 `Math.floor`，对非负数等效。
     *   - 若 `t < 1`，直接返回 1。
     * 
     * @param damage Number 初始伤害值（非负整数）
     * @param defense Number 防御力（非负整数）
     * @return Number 最终伤害值
     */
    public static function bounceDamageCalculation(damage:Number, defense:Number):Number
    {
        // 按公式计算跳弹伤害，使用位运算优化 floor
        var t:Number = (damage - (defense / 5)) | 0;
        return (t < 1) ? 1 : t;
    }

    /**
     * 过穿伤害计算
     * 计算当伤害受到目标防御力影响后，过穿机制下的最终伤害值。
     * 
     * 公式：
     * \[
     * \text{最终伤害} = \max\left(\left\lfloor \text{伤害值} \times \frac{300}{\text{防御力} + 300} \right\rfloor, 1\right)
     * \]
     * 
     * - **过穿机制**：
     *   
     *  - 稳定的二次减伤
     * 
     * - **公式分解**：
     *   - `ratio = 300 / (defense + 300)`：计算防御减伤比。
     *   - `t = damage * ratio`：计算防御后的伤害值。
     *   - 使用 `>> 0` 模拟 `Math.floor`，对非负数等效。
     *   - 若 `t < 1`，返回 1。
     * 
     * @param damage Number 初始伤害值（非负整数）
     * @param defense Number 防御力（非负整数）
     * @return Number 最终伤害值
     */
    public static function penetrationDamageCalculation(damage:Number, defense:Number):Number
    {
        // 按公式计算过穿伤害，使用位运算优化 floor
        var t:Number = (damage * 300 / (defense + 300)) >> 0;
        return (t < 1) ? 1 : t;
    }
}
