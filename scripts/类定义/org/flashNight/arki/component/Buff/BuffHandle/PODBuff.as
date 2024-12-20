import org.flashNight.arki.component.Buff.BuffHandle.*
class org.flashNight.arki.component.Buff.BuffHandle.PODBuff extends BaseBuff implements IBuff {
    private var _value:Number;

    /**
     * 构造函数
     * @param type Buff 的类型标志
     * @param value Buff 的固定值
     */
    public function PODBuff(type:String, value:Number) {
        super(type);
        this._value = value;
    }

    /**
     * 获取 Buff 的固定值
     * @return Buff 值
     */
    public function getValue():Number {
        return this._value;
    }

    /**
     * 应用 buff 到一个值
     * @param value 原始值
     * @return 修改后的值
     */
    public function apply(value:Number):Number {
        if (this.getType() === BuffTypes.ADDITION) {
            return value + this._value;
        } else if (this.getType() === BuffTypes.MULTIPLIER) {
            return value * this._value;
        }
        return value;
    }

    /**
     * 判断 Buff 是否为 POD 类型
     * @return true
     */
    public function isPOD():Boolean {
        return true;
    }
}
