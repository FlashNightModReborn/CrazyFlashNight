import org.flashNight.arki.component.Buff.*;

class org.flashNight.arki.component.Buff.AdditionBuff extends BaseBuff {
    private var _addition:Number;

    /**
     * 构造函数
     * @param addition 加算值
     */
    public function AdditionBuff(addition:Number) {
        this._addition = addition;
    }

    /**
     * 应用加算 buff 到一个值
     * @param value 原始值
     * @return 修改后的值
     */
    public function apply(value:Number):Number {
        var result:Number = value + this._addition;
        trace("Applied addition " + this._addition + ": " + result);
        return result;
    }

    /**
     * 使 buff 的缓存失效
     */
    public function invalidate():Void {
        // 对于加算 buff，通常不需要额外操作
        // 如果有复杂逻辑，可在此实现
    }

    /**
     * 获取加算值
     * @return 加算值
     */
    public function getAddition():Number {
        return this._addition;
    }
}
