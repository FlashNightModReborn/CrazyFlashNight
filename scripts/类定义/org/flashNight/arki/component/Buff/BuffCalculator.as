import org.flashNight.arki.component.Buff.*;

/**
 * BuffCalculator
 *
 * 核心逻辑:
 * 1. SoA (Struct of Arrays) 模式，无对象创建。
 * 2. 支持通用语义（叠加）和保守语义（独占）两种计算模式。
 * 3. 乘法使用乘区相加，有效抑制指数膨胀。
 * 4. 预分配工作数组，避免在 calculate() 中产生GC。
 * 5. reset()负责完全的状态重置。
 *
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
 * - 保守语义: 同类型只取效果最强的一个
 *   - ADD_POSITIVE/ADD_NEGATIVE: 用于防止同来源加法膨胀
 *   - MULT_POSITIVE/MULT_NEGATIVE: 用于防止同来源乘法膨胀
 */
class org.flashNight.arki.component.Buff.BuffCalculator implements IBuffCalculator {
    // SoA: 存储所有修改
    private var _types:Array;
    private var _values:Array;
    private var _count:Number;

    // 预分配的工作数组
    private var _overrides:Array;
    private var _maxValues:Array;
    private var _minValues:Array;

    // 保守语义极值追踪（用NaN表示未设置）
    private var _addPositiveMax:Number;
    private var _addNegativeMin:Number;
    private var _multPositiveMax:Number;
    private var _multNegativeMin:Number;

    private static var MAX_MODIFICATIONS:Number = 100;

    public function BuffCalculator() {
        this._types = [];
        this._values = [];
        this._count = 0;

        // 预分配所有需要的工作数组
        this._overrides = [];
        this._maxValues = [];
        this._minValues = [];

        // 初始化保守语义极值为NaN（表示未设置）
        this._addPositiveMax = NaN;
        this._addNegativeMin = NaN;
        this._multPositiveMax = NaN;
        this._multNegativeMin = NaN;
    }

    public function addModification(type:String, value:Number):Void {
        if (_count >= MAX_MODIFICATIONS) {
            trace("Warning: BuffCalculator reached maximum modifications limit");
            return;
        }
        if (!type || isNaN(value)) {
            trace("Warning: Invalid modification parameters");
            return;
        }

        _types[_count] = type;
        _values[_count] = value;
        _count++;
    }

    public function calculate(baseValue:Number):Number {
        if (_count == 0) return baseValue;

        // 通用加法累积
        var totalAdd:Number = 0;
        // 通用乘法累积（乘区相加）
        var totalMultiplier:Number = 0;
        // 百分比累积
        var totalPercent:Number = 0;

        // 1. 单次循环分组：收集所有修改
        var i:Number = _count;
        while (i--) {
            var currentType:String = _types[i];
            var currentValue:Number = _values[i];

            switch (currentType) {
                // ===== 通用语义 =====
                case BuffCalculationType.ADD:
                    totalAdd += currentValue;
                    break;
                case BuffCalculationType.MULTIPLY:
                    // 乘区相加：累积 (multiplier - 1)
                    totalMultiplier += (currentValue - 1);
                    break;
                case BuffCalculationType.PERCENT:
                    // 百分比累积
                    totalPercent += currentValue;
                    break;

                // ===== 保守语义 =====
                case BuffCalculationType.ADD_POSITIVE:
                    // 正向保守加法：取最大值
                    if (isNaN(_addPositiveMax) || currentValue > _addPositiveMax) {
                        _addPositiveMax = currentValue;
                    }
                    break;
                case BuffCalculationType.ADD_NEGATIVE:
                    // 负向保守加法：取最小值
                    if (isNaN(_addNegativeMin) || currentValue < _addNegativeMin) {
                        _addNegativeMin = currentValue;
                    }
                    break;
                case BuffCalculationType.MULT_POSITIVE:
                    // 正向保守乘法：取最大值
                    if (isNaN(_multPositiveMax) || currentValue > _multPositiveMax) {
                        _multPositiveMax = currentValue;
                    }
                    break;
                case BuffCalculationType.MULT_NEGATIVE:
                    // 负向保守乘法：取最小值
                    if (isNaN(_multNegativeMin) || currentValue < _multNegativeMin) {
                        _multNegativeMin = currentValue;
                    }
                    break;

                // ===== 限制与覆盖 =====
                case BuffCalculationType.OVERRIDE:
                    _overrides.push(currentValue);
                    break;
                case BuffCalculationType.MAX:
                    _maxValues.push(currentValue);
                    break;
                case BuffCalculationType.MIN:
                    _minValues.push(currentValue);
                    break;
            }
        }

        // 2. 按固定顺序应用计算
        var result:Number = baseValue;
        var len:Number;

        // 步骤1: 应用通用乘法（乘区相加）
        // result = base * (1 + Σ(multiplier - 1))
        if (totalMultiplier != 0) {
            result *= (1 + totalMultiplier);
        }

        // 步骤2: 应用正向保守乘法
        if (!isNaN(_multPositiveMax)) {
            result *= _multPositiveMax;
        }

        // 步骤3: 应用负向保守乘法
        if (!isNaN(_multNegativeMin)) {
            result *= _multNegativeMin;
        }

        // 步骤4: 应用百分比（乘区相加）
        // result *= (1 + Σpercent)
        if (totalPercent != 0) {
            result *= (1 + totalPercent);
        }

        // 步骤5: 应用通用加法
        result += totalAdd;

        // 步骤6: 应用正向保守加法
        if (!isNaN(_addPositiveMax)) {
            result += _addPositiveMax;
        }

        // 步骤7: 应用负向保守加法
        if (!isNaN(_addNegativeMin)) {
            result += _addNegativeMin;
        }

        // 步骤8: 应用最大值限制（最小保底）
        len = _maxValues.length;
        if (len > 0) {
            i = len;
            while (i--) result = Math.max(result, _maxValues[i]);
        }

        // 步骤9: 应用最小值限制（最大封顶）
        len = _minValues.length;
        if (len > 0) {
            i = len;
            while (i--) result = Math.min(result, _minValues[i]);
        }

        // 步骤10: 应用覆盖 (最后添加的覆盖生效)
        // 因为我们用反向循环收集，所以数组中第一个元素就是最后添加的
        len = _overrides.length;
        if (len > 0) {
            result = _overrides[0];
        }

        return result;
    }

    public function reset():Void {
        // 重置主数据
        _count = 0;

        // [重要] 清理所有工作数组，为下次计算做准备
        _overrides.length = 0;
        _maxValues.length = 0;
        _minValues.length = 0;

        // 重置保守语义极值
        _addPositiveMax = NaN;
        _addNegativeMin = NaN;
        _multPositiveMax = NaN;
        _multNegativeMin = NaN;
    }

    public function getModificationCount():Number {
        return _count;
    }
}
