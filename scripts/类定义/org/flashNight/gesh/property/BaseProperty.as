// org/flashNight/gesh/property/BuffProperty.as
import org.flashNight.gesh.property.PropertyAccessor;
import org.flashNight.arki.component.Buff.IBuff;
import org.flashNight.arki.component.Buff.MultiplierBuff;
import org.flashNight.arki.component.Buff.AdditionBuff;

class org.flashNight.gesh.property.BuffProperty {
    private var _baseAccessor:PropertyAccessor;
    private var _buffedAccessor:PropertyAccessor;
    private var _buffs:Array;

    /**
     * 构造函数
     * @param obj      目标对象
     * @param propName 属性名称
     */
    public function BuffProperty(obj:Object, propName:String) {
        this._buffs = [];

        var self:BuffProperty = this;

        // 创建 PropertyAccessor 用于基础属性
        this._baseAccessor = new PropertyAccessor(obj, propName + "_base", 0, null, function() {
            self.invalidate();
        });

        // 创建 PropertyAccessor 用于 buffed 属性，并提供计算函数
        this._buffedAccessor = new PropertyAccessor(obj, propName, 0, function():Number {
            return self.computeBuffed();
        }, null);
    }

    /**
     * 添加乘算 buff
     * @param multiplier 乘算值
     */
    public function addMultiplier(multiplier:Number):Void {
        var buff:MultiplierBuff = new MultiplierBuff(multiplier);
        this._buffs.push(buff);
        trace("Added multiplier buff: " + multiplier);
        this.invalidate();
    }

    /**
     * 添加加算 buff
     * @param addition 加算值
     */
    public function addAddition(addition:Number):Void {
        var buff:AdditionBuff = new AdditionBuff(addition);
        this._buffs.push(buff);
        trace("Added addition buff: " + addition);
        this.invalidate();
    }

    /**
     * 添加通用 buff
     * @param buff buff 实例
     */
    public function addBuff(buff:IBuff):Void {
        this._buffs.push(buff);
        trace("Added generic buff.");
        this.invalidate();
    }

    /**
     * 移除指定 buff
     * @param buff buff 实例
     */
    public function removeBuff(buff:IBuff):Void {
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] === buff) {
                this._buffs.splice(i, 1);
                trace("Removed buff.");
                this.invalidate();
                return;
            }
        }
        trace("Buff not found.");
    }

    /**
     * 清除所有乘算 buff
     */
    public function clearMultipliers():Void {
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] instanceof MultiplierBuff) {
                this._buffs.splice(i, 1);
                trace("Removed multiplier buff.");
            }
        }
        this.invalidate();
    }

    /**
     * 清除所有加算 buff
     */
    public function clearAdditions():Void {
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] instanceof AdditionBuff) {
                this._buffs.splice(i, 1);
                trace("Removed addition buff.");
            }
        }
        this.invalidate();
    }

    /**
     * 计算 buffed 属性值，通过应用所有 buff
     * @return buffed 值
     */
    private function computeBuffed():Number {
        var baseValue:Number = this._baseAccessor.get();
        var result:Number = baseValue;

        trace("Computing buffed '" + this._buffedAccessor.getPropName() + "' from base value: " + baseValue);

        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            result = buff.apply(result);
        }

        trace("Computed '" + this._buffedAccessor.getPropName() + "': " + result);
        return result;
    }

    /**
     * 使 buffed 属性缓存失效
     */
    public function invalidate():Void {
        this._buffedAccessor.invalidate();
    }
}
