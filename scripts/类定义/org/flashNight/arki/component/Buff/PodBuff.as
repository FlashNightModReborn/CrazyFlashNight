// org/flashNight/arki/component/Buff/PodBuff.as (修改后)
import org.flashNight.arki.component.Buff.*;

class org.flashNight.arki.component.Buff.PodBuff extends BaseBuff {
    private var _type:String = "PodBuff";

    private var _targetProperty:String;
    private var _calculationType:String;
    private var _value:Number;
    
    public function PodBuff(
        targetProperty:String, 
        calculationType:String,
        value:Number
    ) {
        super();
        this._targetProperty = targetProperty;
        this._calculationType = calculationType;
        this._value = value;
    }
    
    /**
     * 重写 applyEffect。
     *
     * 【契约】PropertyContainer.addBuff()已保证只接收匹配的PodBuff
     * 因此无需再次验证 targetProperty == context.propertyName
     */
    public function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void {
        calculator.addModification(this._calculationType, this._value);
    }
    
    /**
     * 重写 destroy。
     * 因为没有了 _dataContainer，这里甚至可以不需要重写了。
     * 但保留对super.destroy()的调用是好习惯。
     */
    public function destroy():Void {
        super.destroy(); 
    }

    /**
     * 返回 PodBuff 的字符串表示形式，包含类型、ID、目标属性、计算类型与数值信息。
     */
    public function toString():String {
        return "[ " + this._type +  " id: " + this.getId() +
               ", property: " + this._targetProperty +
               ", calcType: " + this._calculationType +
               ", value: " + this._value + "]";
    }


    // --- 公共访问接口 ---
    public function getTargetProperty():String { return this._targetProperty; }
    public function getCalculationType():String { return this._calculationType; }
    public function getValue():Number { return this._value; }
    public function setValue(value:Number):Void { this._value = value; }
}