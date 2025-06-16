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
        this._targetProperty = targetProperty;
        this._calculationType = calculationType;
        this._value = value;
    }
    
    /**
     * 重写 applyEffect。
     * 现在它的逻辑非常纯粹和简单。
     */
    public override function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void {
        if (this._targetProperty == context.propertyName) {
            calculator.addModification(this._calculationType, this._value);
        }
    }
    
    /**
     * 重写 destroy。
     * 因为没有了 _dataContainer，这里甚至可以不需要重写了。
     * 但保留对super.destroy()的调用是好习惯。
     */
    public override function destroy():Void {
        super.destroy(); 
    }

    // --- 公共访问接口 ---
    public function getTargetProperty():String { return this._targetProperty; }
    public function getCalculationType():String { return this._calculationType; }
    public function getValue():Number { return this._value; }
    public function setValue(value:Number):Void { this._value = value; }
}