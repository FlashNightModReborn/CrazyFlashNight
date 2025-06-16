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
        
        // [优化] 单独处理ADD类型，因为它总是最先且可累加
        var totalAdd:Number = 0;
        
        // 1. 单次循环分组：收集所有修改，并直接累积ADD类型
        var i:Number = _count;
        while (i--) {
            var currentType:String = _types[i];
            var currentValue:Number = _values[i];
            
            switch (currentType) {
                case BuffCalculationType.ADD:
                    totalAdd += currentValue;
                    break;
                // [修正] 其他类型不再累积，而是收集到数组中，以保证正确的乘法叠加顺序
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
        
        // 2. 按固定顺序应用计算
        var result:Number = baseValue;
        var len:Number;
        
        // 1. 应用累积的加法 (最高优先级)
        result += totalAdd;
        
        // 2. 应用所有乘法
        len = _multipliers.length;
        if (len > 0) {
            i = len;
            while (i--) result *= _multipliers[i];
        }
        
        // 3. 应用所有百分比
        len = _percentages.length;
        if (len > 0) {
            i = len;
            while (i--) result *= (1 + _percentages[i]);
        }
        
        // 4. 应用最大值限制
        len = _maxValues.length;
        if (len > 0) {
            i = len;
            while (i--) result = Math.max(result, _maxValues[i]);
        }
        
        // 5. 应用最小值限制
        len = _minValues.length;
        if (len > 0) {
            i = len;
            while (i--) result = Math.min(result, _minValues[i]);
        }
        
        // 6. 应用覆盖 (最后添加的覆盖生效)
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