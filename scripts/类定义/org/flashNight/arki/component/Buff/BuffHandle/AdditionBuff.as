import org.flashNight.arki.component.Buff.BuffHandle.*;

/**
 * AdditionBuff
 * 加法类型Buff，将指定值加到原始值上
 */
class org.flashNight.arki.component.Buff.BuffHandle.AdditionBuff extends PODBuff {
    
    /**
     * 构造函数
     * @param value 要添加的值
     */
    public function AdditionBuff(value:Number) {
        super(BuffTypes.ADDITION, value);
    }
    
    /**
     * 应用加法计算到输入值
     * @param value 原始值
     * @return 加上buff值后的结果
     */
    public function apply(value:Number):Number {
        return value + this._value;
    }
    
    /**
     * 设置新的加法值
     * @param newValue 新的加法值
     */
    public function setValue(newValue:Number):Void {
        this._value = newValue;
    }
    
    /**
     * 获取当前加法值
     * @return 当前加法值
     */
    public function getValue():Number {
        return this._value;
    }
}