import org.flashNight.arki.component.Buff.*;

/**
 * BuffCalculator
 *
 * 核心逻辑:
 * 1. SoA (Struct of Arrays) 模式，无对象创建。
 * 2. 支持通用语义（叠加）和保守语义（独占）两种计算模式。
 * 3. 乘法使用乘区相加，有效抑制指数膨胀。
 * 4. 边界控制(OVERRIDE/MAX/MIN)使用标量追踪，无循环开销。
 * 5. 位掩码快速路径优化，对常见场景完全跳过循环。
 * 6. 增量累积模式，addModification时直接累加，calculate无需重新遍历。
 * 7. reset()负责完全的状态重置。
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
 * 快速路径策略:
 * - 仅ADD:        typeMask == 1   → return base + totalAdd
 * - 仅MULTIPLY:   typeMask == 2   → return base * (1 + totalMult)
 * - ADD+MULTIPLY: typeMask == 3   → return base * (1 + totalMult) + totalAdd
 * - 通用三件套:   typeMask == 7   → 标准计算路径
 * - 无边界控制:   mask & 896 == 0 → 跳过 MAX/MIN/OVERRIDE 检查
 *
 * 位值定义 (单一事实源 - 其他文件派生自此):
 * - ADD:           1 (1<<0)
 * - MULTIPLY:      2 (1<<1)
 * - PERCENT:       4 (1<<2)
 * - ADD_POSITIVE:  8 (1<<3)
 * - ADD_NEGATIVE:  16 (1<<4)
 * - MULT_POSITIVE: 32 (1<<5)
 * - MULT_NEGATIVE: 64 (1<<6)
 * - MAX:           128 (1<<7)
 * - MIN:           256 (1<<8)
 * - OVERRIDE:      512 (1<<9)
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
    // SoA: 存储原始修改记录（用于调试和状态检查）
    private var _types:Array;
    private var _values:Array;
    private var _count:Number;

    // 位掩码：追踪使用了哪些类型
    private var _typeMask:Number;

    // 增量累积：通用语义
    private var _totalAdd:Number;
    private var _totalMultiplier:Number;
    private var _totalPercent:Number;

    // 边界控制标量（用NaN表示未设置）
    private var _lastOverride:Number;
    private var _maxFloor:Number;
    private var _minCeiling:Number;

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

        // 初始化位掩码
        this._typeMask = 0;

        // 初始化增量累积
        this._totalAdd = 0;
        this._totalMultiplier = 0;
        this._totalPercent = 0;

        // 初始化边界控制标量为NaN（表示未设置）
        this._lastOverride = NaN;
        this._maxFloor = NaN;
        this._minCeiling = NaN;

        // 初始化保守语义极值为NaN（表示未设置）
        this._addPositiveMax = NaN;
        this._addNegativeMin = NaN;
        this._multPositiveMax = NaN;
        this._multNegativeMin = NaN;
    }

    /**
     * 添加修改项
     *
     * 热路径优化：单次分发同时完成位掩码设置和数值累积
     * 使用字面量常量，零运行时分配
     */
    public function addModification(type:String, value:Number):Void {
        if (_count >= MAX_MODIFICATIONS) {
            trace("Warning: BuffCalculator reached maximum modifications limit");
            return;
        }
        if (!type || isNaN(value)) {
            trace("Warning: Invalid modification parameters");
            return;
        }

        // 记录原始数据（用于调试）
        _types[_count] = type;
        _values[_count] = value;
        _count++;

        // 单次分发：同时设置位掩码和累积数值
        // 位值使用字面量常量，避免任何运行时对象创建
        if (type == "add") {
            _typeMask |= 1;  // BIT_ADD
            _totalAdd += value;
        } else if (type == "multiply") {
            _typeMask |= 2;  // BIT_MULTIPLY
            _totalMultiplier += (value - 1);
        } else if (type == "percent") {
            _typeMask |= 4;  // BIT_PERCENT
            _totalPercent += value;
        } else if (type == "add_positive") {
            _typeMask |= 8;  // BIT_ADD_POSITIVE
            if (isNaN(_addPositiveMax) || value > _addPositiveMax) {
                _addPositiveMax = value;
            }
        } else if (type == "add_negative") {
            _typeMask |= 16;  // BIT_ADD_NEGATIVE
            if (isNaN(_addNegativeMin) || value < _addNegativeMin) {
                _addNegativeMin = value;
            }
        } else if (type == "mult_positive") {
            _typeMask |= 32;  // BIT_MULT_POSITIVE
            if (isNaN(_multPositiveMax) || value > _multPositiveMax) {
                _multPositiveMax = value;
            }
        } else if (type == "mult_negative") {
            _typeMask |= 64;  // BIT_MULT_NEGATIVE
            if (isNaN(_multNegativeMin) || value < _multNegativeMin) {
                _multNegativeMin = value;
            }
        } else if (type == "max") {
            _typeMask |= 128;  // BIT_MAX
            if (isNaN(_maxFloor) || value > _maxFloor) {
                _maxFloor = value;
            }
        } else if (type == "min") {
            _typeMask |= 256;  // BIT_MIN
            if (isNaN(_minCeiling) || value < _minCeiling) {
                _minCeiling = value;
            }
        } else if (type == "override") {
            _typeMask |= 512;  // BIT_OVERRIDE
            _lastOverride = value;
        }
    }

    /**
     * 计算最终值
     *
     * 快速路径：根据位掩码分流到优化的计算路径
     */
    public function calculate(baseValue:Number):Number {
        if (_count == 0) return baseValue;

        var mask:Number = _typeMask;

        // ===== 快速路径 1：仅 ADD =====
        if (mask == 1) {
            return baseValue + _totalAdd;
        }

        // ===== 快速路径 2：仅 MULTIPLY =====
        if (mask == 2) {
            return baseValue * (1 + _totalMultiplier);
        }

        // ===== 快速路径 3：ADD + MULTIPLY =====
        if (mask == 3) {
            return baseValue * (1 + _totalMultiplier) + _totalAdd;
        }

        // ===== 快速路径 4：通用三件套 (ADD|MULTIPLY|PERCENT) =====
        if (mask == 7) {
            var r:Number = baseValue * (1 + _totalMultiplier);
            r *= (1 + _totalPercent);
            return r + _totalAdd;
        }

        // ===== 快速路径 5：无边界控制 (mask & 896 == 0) =====
        // 896 = BIT_MAX | BIT_MIN | BIT_OVERRIDE = 128 + 256 + 512
        if ((mask & 896) == 0) {
            return _calculateNoBounds(baseValue);
        }

        // ===== 完整计算路径 =====
        return _calculateFull(baseValue);
    }

    /**
     * 无边界控制的计算路径
     */
    private function _calculateNoBounds(baseValue:Number):Number {
        var result:Number = baseValue;

        // 步骤1: 通用乘法
        if (_totalMultiplier != 0) {
            result *= (1 + _totalMultiplier);
        }

        // 步骤2: 正向保守乘法
        if (!isNaN(_multPositiveMax)) {
            result *= _multPositiveMax;
        }

        // 步骤3: 负向保守乘法
        if (!isNaN(_multNegativeMin)) {
            result *= _multNegativeMin;
        }

        // 步骤4: 百分比
        if (_totalPercent != 0) {
            result *= (1 + _totalPercent);
        }

        // 步骤5: 通用加法
        result += _totalAdd;

        // 步骤6: 正向保守加法
        if (!isNaN(_addPositiveMax)) {
            result += _addPositiveMax;
        }

        // 步骤7: 负向保守加法
        if (!isNaN(_addNegativeMin)) {
            result += _addNegativeMin;
        }

        return result;
    }

    /**
     * 完整计算路径（包含边界控制）
     */
    private function _calculateFull(baseValue:Number):Number {
        var result:Number = _calculateNoBounds(baseValue);

        // 步骤8: MAX（下限保底）
        if (!isNaN(_maxFloor)) {
            if (result < _maxFloor) result = _maxFloor;
        }

        // 步骤9: MIN（上限封顶）
        if (!isNaN(_minCeiling)) {
            if (result > _minCeiling) result = _minCeiling;
        }

        // 步骤10: OVERRIDE
        if (!isNaN(_lastOverride)) {
            result = _lastOverride;
        }

        return result;
    }

    public function reset():Void {
        // 重置计数
        _count = 0;

        // 重置位掩码
        _typeMask = 0;

        // 重置增量累积
        _totalAdd = 0;
        _totalMultiplier = 0;
        _totalPercent = 0;

        // 重置边界控制标量
        _lastOverride = NaN;
        _maxFloor = NaN;
        _minCeiling = NaN;

        // 重置保守语义极值
        _addPositiveMax = NaN;
        _addNegativeMin = NaN;
        _multPositiveMax = NaN;
        _multNegativeMin = NaN;
    }

    public function getModificationCount():Number {
        return _count;
    }

    /**
     * 获取当前类型掩码（用于调试）
     */
    public function getTypeMask():Number {
        return _typeMask;
    }
}
