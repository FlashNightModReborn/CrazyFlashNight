import org.flashNight.arki.component.Buff.*;

class org.flashNight.arki.component.Buff.DefaultBuffCalculator
       implements IBuffCalculator {

    private var _mods:Array;   // [{t,v,p}]
    public function DefaultBuffCalculator() {
        this._mods = [];
    }

    // ----------------------------------------------------------------
    // IBuffCalculator 实现
    // ----------------------------------------------------------------
    public function addModification(type:String,
                                    value:Number,
                                    priority:Number):Void {
        // 容错：未传优先级则默认为 0
        if (isNaN(priority)) priority = 0;
        this._mods.push({t:type, v:value, p:priority});
    }

    public function calculate(baseValue:Number):Number {
        if (this._mods.length == 0) return baseValue;   // 无 Buff

        // 1. 按优先级排序（升序）
        this._mods.sortOn("p", Array.NUMERIC);

        // 2. 统计
        var totalMul:Number  = 1;
        var totalAdd:Number  = 0;
        var maxVal:Number    = null;
        var minVal:Number    = null;
        var overrideVal:Number = null;

        for (var i:Number = 0; i < this._mods.length; ++i) {
            var m:Object = this._mods[i];
            switch (m.t) {
                case BuffCalculationType.MULTIPLY:
                    totalMul *= m.v; break;
                case BuffCalculationType.PERCENT:
                    totalMul *= (1 + m.v); break;
                case BuffCalculationType.ADD:
                    totalAdd += m.v; break;
                case BuffCalculationType.MAX:
                    maxVal = (maxVal == null) ? m.v : Math.max(maxVal, m.v); break;
                case BuffCalculationType.MIN:
                    minVal = (minVal == null) ? m.v : Math.min(minVal, m.v); break;
                case BuffCalculationType.OVERRIDE:
                    overrideVal = m.v; break;
            }
        }

        // 3. 应用
        var result:Number = baseValue * totalMul + totalAdd;
        if (maxVal != null) result = Math.max(result, maxVal);
        if (minVal != null) result = Math.min(result, minVal);
        if (overrideVal != null) result = overrideVal;

        return result;
    }

    public function reset():Void {
        this._mods.length = 0;
    }
}
