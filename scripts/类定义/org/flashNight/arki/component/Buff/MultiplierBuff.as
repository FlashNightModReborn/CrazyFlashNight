// org/flashNight/gesh/property/MultiplierBuff.as
import org.flashNight.arki.component.Buff.*;

class org.flashNight.arki.component.Buff.MultiplierBuff extends BaseBuff {
    private var _multiplier:Number;

    /**
     * 构造函数
     * @param multiplier 乘算值
     */
    public function MultiplierBuff(multiplier:Number) {
        this._multiplier = multiplier;
    }

    /**
     * 应用乘算 buff 到一个值
     * @param value 原始值
     * @return 修改后的值
     */
    public function apply(value:Number):Number {
        var result:Number = value * this._multiplier;
        trace("Applied multiplier " + this._multiplier + ": " + result);
        return result;
    }

    /**
     * 使 buff 的缓存失效
     */
    public function invalidate():Void {
        // 对于乘算 buff，通常不需要额外操作
        // 如果有复杂逻辑，可在此实现
    }

    /**
     * 获取乘算值
     * @return 乘算值
     */
    public function getMultiplier():Number {
        return this._multiplier;
    }
}
