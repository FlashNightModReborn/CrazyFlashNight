// org/flashNight/arki/component/Buff/BuffCalculator.as
import org.flashNight.arki.component.Buff.*;

class org.flashNight.arki.component.Buff.BuffCalculator implements IBuffCalculator {
    private var _modifications:Array;
    
    public function BuffCalculator() {
        this._modifications = [];
    }
    
    public function addModification(type:String, value:Number, priority:Number):Void {
        this._modifications.push({
            type: type,
            value: value,
            priority: priority || 0
        });
    }
    
    public function calculate(baseValue:Number):Number {
        if (this._modifications.length == 0) {
            return baseValue;
        }
        
        // 按优先级排序
        this._modifications.sortOn("priority", Array.NUMERIC);
        
        var result:Number = baseValue;
        var additive:Number = 0;        // 累加修改
        var multiplicative:Number = 1;  // 累乘修改
        var percentageBonus:Number = 0; // 百分比加成
        var finalOverride:Number = NaN; // 最终覆盖值
        
        // 分类处理不同类型的修改
        for (var i:Number = 0; i < this._modifications.length; i++) {
            var mod:Object = this._modifications[i];
            
            switch (mod.type) {
                case BuffCalculationType.ADD:
                    additive += mod.value;
                    break;
                    
                case BuffCalculationType.MULTIPLY:
                    multiplicative *= mod.value;
                    break;
                    
                case BuffCalculationType.PERCENT:
                    percentageBonus += mod.value;
                    break;
                    
                case BuffCalculationType.OVERRIDE:
                    finalOverride = mod.value; // 最后一个覆盖值生效
                    break;
                    
                case BuffCalculationType.MAX:
                    result = Math.max(result, mod.value);
                    break;
                    
                case BuffCalculationType.MIN:
                    result = Math.min(result, mod.value);
                    break;
            }
        }
        
        // 标准计算顺序：基础值 -> 加法 -> 乘法 -> 百分比 -> 覆盖
        if (!isNaN(finalOverride)) {
            result = finalOverride;
        } else {
            result = ((baseValue + additive) * multiplicative) * (1 + percentageBonus);
        }
        
        return result;
    }
    
    public function reset():Void {
        this._modifications = [];
    }
}