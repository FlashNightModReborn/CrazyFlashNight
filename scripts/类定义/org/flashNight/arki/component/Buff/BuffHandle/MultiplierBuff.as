import org.flashNight.arki.component.Buff.BuffHandle.*;


/**
 * MultiplierBuff
 * 乘法类型Buff，将原始值乘以指定系数
 */
class org.flashNight.arki.component.Buff.BuffHandle.MultiplierBuff extends PODBuff {
    
    /**
     * 构造函数
     * @param value 乘法系数
     */
    public function MultiplierBuff(value:Number) {
        super(BuffTypes.MULTIPLIER, value);
    }
    
    /**
     * 应用乘法计算到输入值
     * @param value 原始值
     * @return 乘以系数后的结果
     */
    public function apply(value:Number):Number {
        return value * this._value;
    }
    
    /**
     * 设置新的乘法系数
     * @param newValue 新的乘法系数
     */
    public function setValue(newValue:Number):Void {
        this._value = newValue;
    }
    
    /**
     * 获取当前乘法系数
     * @return 当前乘法系数
     */
    public function getValue():Number {
        return this._value;
    }
}