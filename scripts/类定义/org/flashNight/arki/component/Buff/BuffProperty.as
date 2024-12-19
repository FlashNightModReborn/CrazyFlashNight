import org.flashNight.gesh.property.*;
import org.flashNight.arki.component.Buff.*;

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
        this._baseAccessor = new org.flashNight.gesh.property.PropertyAccessor(obj, propName + "_base", 0, null, function() {
            self.invalidate();
        });

        // 创建 PropertyAccessor 用于 buffed 属性，并提供计算函数
        this._buffedAccessor = new org.flashNight.gesh.property.PropertyAccessor(obj, propName, 0, function():Number {
            return self.computeBuffed();
        }, null);
    }

    /**
     * 添加乘算 buff
     * @param multiplier 乘算值
     */
    public function addMultiplier(multiplier:Number):Void {
        var buff:org.flashNight.gesh.property.MultiplierBuff = new org.flashNight.gesh.property.MultiplierBuff(multiplier);
        this._buffs.push(buff);
        trace("Added multiplier buff: " + multiplier);
        this.invalidate();
    }

    /**
     * 添加加算 buff
     * @param addition 加算值
     */
    public function addAddition(addition:Number):Void {
        var buff:org.flashNight.gesh.property.AdditionBuff = new org.flashNight.gesh.property.AdditionBuff(addition);
        this._buffs.push(buff);
        trace("Added addition buff: " + addition);
        this.invalidate();
    }

    /**
     * 添加通用 buff
     * @param buff buff 实例
     */
    public function addBuff(buff:org.flashNight.gesh.property.iBuff):Void {
        this._buffs.push(buff);
        trace("Added generic buff.");
        this.invalidate();
    }

    /**
     * 清除所有乘算 buff
     */
    public function clearMultipliers():Void {
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] instanceof org.flashNight.gesh.property.MultiplierBuff) {
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
            if (this._buffs[i] instanceof org.flashNight.gesh.property.AdditionBuff) {
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
            var buff:org.flashNight.gesh.property.iBuff = this._buffs[i];
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
