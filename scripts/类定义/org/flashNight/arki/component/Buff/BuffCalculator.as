import org.flashNight.arki.component.Buff.*;

/**
 * BuffCalculator
 *
 * 核心逻辑:
 * 1. SoA (Struct of Arrays) 模式，无对象创建。
 * 2. 对 ADD 类型的修改进行单次循环累积。
 * 3. 对 MULTIPLY, PERCENT, MAX, MIN, OVERRIDE 等类型先收集再按优先级顺序应用，保证计算正确性。
 * 4. 预分配工作数组，避免在 calculate() 中产生GC。
 * 5. reset()负责完全的状态重置。
 *
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
 * - 这种设计可以有效抑制数值膨胀：加算是固定值，不会被乘法放大
 */
class org.flashNight.arki.component.Buff.BuffCalculator implements IBuffCalculator {
    // SoA: 存储所有修改
    private var _types:Array;
    private var _values:Array;
    private var _count:Number;

    // 预分配的工作数组
    private var _overrides:Array;
    private var _multipliers:Array;
    private var _percentages:Array;
    private var _maxValues:Array;
    private var _minValues:Array;

    private static var MAX_MODIFICATIONS:Number = 100;

    public function BuffCalculator() {
        this._types = [];
        this._values = [];
        this._count = 0;

        // 预分配所有需要的工作数组
        this._overrides = [];
        this._multipliers = [];
        this._percentages = [];
        this._maxValues = [];
        this._minValues = [];
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

        // 单独累积ADD类型（后置加算）
        var totalAdd:Number = 0;

        // 1. 单次循环分组：收集所有修改
        var i:Number = _count;
        while (i--) {
            var currentType:String = _types[i];
            var currentValue:Number = _values[i];

            switch (currentType) {
                case BuffCalculationType.ADD:
                    // ADD现在是后置加算，在乘法之后应用
                    totalAdd += currentValue;
                    break;
                case BuffCalculationType.MULTIPLY:
                    _multipliers.push(currentValue);
                    break;
                case BuffCalculationType.PERCENT:
                    _percentages.push(currentValue);
                    break;
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

        // 2. 按固定顺序应用计算（对齐老系统: 基础值 × 倍率 + 加算）
        var result:Number = baseValue;
        var len:Number;

        // 步骤1: 应用所有乘法（对应老系统"倍率"）
        len = _multipliers.length;
        if (len > 0) {
            i = len;
            while (i--) result *= _multipliers[i];
        }

        // 步骤2: 应用所有百分比
        len = _percentages.length;
        if (len > 0) {
            i = len;
            while (i--) result *= (1 + _percentages[i]);
        }

        // 步骤3: 应用累积的加法（对应老系统"加算"，在乘法之后）
        result += totalAdd;

        // 步骤4: 应用最大值限制（最小保底）
        len = _maxValues.length;
        if (len > 0) {
            i = len;
            while (i--) result = Math.max(result, _maxValues[i]);
        }

        // 步骤5: 应用最小值限制（最大封顶）
        len = _minValues.length;
        if (len > 0) {
            i = len;
            while (i--) result = Math.min(result, _minValues[i]);
        }

        // 步骤6: 应用覆盖 (最后添加的覆盖生效)
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
        _multipliers.length = 0;
        _percentages.length = 0;
        _maxValues.length = 0;
        _minValues.length = 0;
    }

    public function getModificationCount():Number {
        return _count;
    }
}
