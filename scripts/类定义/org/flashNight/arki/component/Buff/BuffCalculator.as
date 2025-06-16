import org.flashNight.arki.component.Buff.*;

class org.flashNight.arki.component.Buff.BuffCalculator
       implements IBuffCalculator {


    private var _modifications:Array;
    private static var MAX_MODIFICATIONS:Number = 100;
    
    public function BuffCalculator() {
        this._modifications = [];
    }

    /**
     * 简化的addModification - 不再需要priority
     * 按添加顺序和类型内置优先级处理
     */
    public function addModification(type:String, value:Number):Void {
        if (_modifications.length >= MAX_MODIFICATIONS) {
            trace("Warning: BuffCalculator reached maximum modifications limit");
            return;
        }
        
        if (!type || isNaN(value)) {
            trace("Warning: Invalid modification parameters");
            return;
        }
        
        _modifications.push({type: type, value: value});
    }

    /**
     * 使用固定的类型优先级进行计算
     * 这覆盖了99%的使用场景
     */
    public function calculate(baseValue:Number):Number {
        if (_modifications.length == 0) return baseValue;
        
        // 按类型分组，而不是按priority排序
        var overrides:Array = [];
        var multipliers:Array = [];
        var percentages:Array = [];
        var additions:Array = [];
        var maxValues:Array = [];
        var minValues:Array = [];
        
        // 分组收集
        for (var i:Number = 0; i < _modifications.length; i++) {
            var mod:Object = _modifications[i];
            switch (mod.type) {
                case BuffCalculationType.OVERRIDE:
                    overrides.push(mod.value);
                    break;
                case BuffCalculationType.MULTIPLY:
                    multipliers.push(mod.value);
                    break;
                case BuffCalculationType.PERCENT:
                    percentages.push(mod.value);
                    break;
                case BuffCalculationType.ADD:
                    additions.push(mod.value);
                    break;
                case BuffCalculationType.MAX:
                    maxValues.push(mod.value);
                    break;
                case BuffCalculationType.MIN:
                    minValues.push(mod.value);
                    break;
            }
        }
        
        // 固定顺序计算：基础值 -> 加法 -> 乘法 -> 百分比 -> 最大值 -> 最小值 -> 覆盖
        var result:Number = baseValue;
        
        // 1. 应用所有加法
        for (var j:Number = 0; j < additions.length; j++) {
            result += additions[j];
        }
        
        // 2. 应用所有乘法
        for (var k:Number = 0; k < multipliers.length; k++) {
            result *= multipliers[k];
        }
        
        // 3. 应用所有百分比
        for (var l:Number = 0; l < percentages.length; l++) {
            result *= (1 + percentages[l]);
        }
        
        // 4. 应用最大值限制
        for (var m:Number = 0; m < maxValues.length; m++) {
            result = Math.max(result, maxValues[m]);
        }
        
        // 5. 应用最小值限制
        for (var n:Number = 0; n < minValues.length; n++) {
            result = Math.min(result, minValues[n]);
        }
        
        // 6. 应用覆盖（最后添加的覆盖生效）
        if (overrides.length > 0) {
            result = overrides[overrides.length - 1]; // 最后的override生效
        }
        
        return result;
    }

    public function reset():Void {
        _modifications.length = 0;
    }
    
    public function getModificationCount():Number {
        return _modifications.length;
    }
}