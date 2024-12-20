// org/flashNight.arki.component.Buff.BuffProperty.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.BuffHandle.*;

class org.flashNight.arki.component.Buff.BuffProperty extends BaseBuffProperty implements IBuffProperty {
    public function BuffProperty(obj:Object, propName:String, defaultBaseValue:Number) {
        super(obj, propName, defaultBaseValue, null);
    }

    // 假设先应用所有加算 Buff，再应用所有乘算 Buff
    public function computeBuffed():Number {
        var baseVal:Number = this.getBaseValue();
        var additionSum:Number = 0;
        var multiplierProduct:Number = 1;

        var buffs:Array = this.getBuffs();
        for (var i:Number = 0; i < buffs.length; i++) {
            var buff:IBuff = buffs[i]; // 修正此处，使用 buffs[i] 而非 this._buffs[i]
            if (buff instanceof AdditionBuff) {
                additionSum += buff.apply(0); // apply(0) 返回加算值
            } else if (buff instanceof MultiplierBuff) {
                multiplierProduct *= buff.apply(1); // apply(1) 返回乘算值
            } else {
                baseVal = buff.apply(baseVal); // 其他 Buff 按默认逻辑应用
            }
        }

        var result:Number = (baseVal + additionSum) * multiplierProduct;
        return result;
    }
}
