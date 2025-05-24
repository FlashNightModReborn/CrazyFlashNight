import org.flashNight.gesh.property.PropertyAccessor;
import org.flashNight.arki.component.Buff.BuffHandle.IBuff;

/**
 * BuffableProperty
 * 一个可以应用多个Buff的属性管理器
 * 基于PropertyAccessor实现
 */
class org.flashNight.arki.component.Buff.BuffableProperty {
    private var _baseValue:Number;
    private var _buffs:Array;
    private var _propertyAccessor:PropertyAccessor;
    private var _target:Object;
    private var _propertyName:String;
    
    /**
     * 构造函数
     * @param target 目标对象
     * @param propertyName 属性名
     * @param baseValue 基础值
     */
    public function BuffableProperty(target:Object, propertyName:String, baseValue:Number) {
        this._target = target;
        this._propertyName = propertyName;
        this._baseValue = baseValue;
        this._buffs = [];
        
        // 创建计算属性
        this._propertyAccessor = new PropertyAccessor(
            target,
            propertyName,
            baseValue,
            this.computeValue.bind(this), // 计算函数
            null,
            null
        );
    }
    
    /**
     * 计算属性值（应用所有buff）
     * @return 计算后的值
     */
    private function computeValue():Number {
        var result:Number = this._baseValue;
        
        // 先应用所有加法buff
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff.getType() == "addition") {
                result = buff.apply(result);
            }
        }
        
        // 再应用所有乘法buff
        for (var j:Number = 0; j < this._buffs.length; j++) {
            var multBuff:IBuff = this._buffs[j];
            if (multBuff.getType() == "multiplier") {
                result = multBuff.apply(result);
            }
        }
        
        // 最后应用所有meta buff
        for (var k:Number = 0; k < this._buffs.length; k++) {
            var metaBuff:IBuff = this._buffs[k];
            if (!metaBuff.isPOD()) {
                result = metaBuff.apply(result);
            }
        }
        
        return result;
    }
    
    /**
     * 添加buff
     * @param buff 要添加的buff
     */
    public function addBuff(buff:IBuff):Void {
        this._buffs.push(buff);
        this._propertyAccessor.invalidate();
    }
    
    /**
     * 移除指定类型的所有buff
     * @param buffType buff类型
     * @return 移除的buff数量
     */
    public function removeBuffsByType(buffType:String):Number {
        var count:Number = 0;
        var i:Number = this._buffs.length;
        
        while (i--) {
            if (this._buffs[i].getType() == buffType) {
                this._buffs.splice(i, 1);
                count++;
            }
        }
        
        if (count > 0) {
            this._propertyAccessor.invalidate();
        }
        
        return count;
    }
    
    /**
     * 移除特定的buff实例
     * @param buff 要移除的buff实例
     * @return 是否成功移除
     */
    public function removeBuff(buff:IBuff):Boolean {
        var index:Number = this._buffs.indexOf(buff);
        if (index >= 0) {
            this._buffs.splice(index, 1);
            this._propertyAccessor.invalidate();
            return true;
        }
        return false;
    }
    
    /**
     * 清除所有buff
     */
    public function clearBuffs():Void {
        if (this._buffs.length > 0) {
            this._buffs = [];
            this._propertyAccessor.invalidate();
        }
    }
    
    /**
     * 设置基础值
     * @param value 新的基础值
     */
    public function setBaseValue(value:Number):Void {
        if (this._baseValue != value) {
            this._baseValue = value;
            this._propertyAccessor.invalidate();
        }
    }
    
    /**
     * 获取基础值
     * @return 基础值
     */
    public function getBaseValue():Number {
        return this._baseValue;
    }
    
    /**
     * 获取当前应用所有buff后的值
     * @return 计算后的值
     */
    public function getCurrentValue():Number {
        return this._target[this._propertyName];
    }
    
    /**
     * 获取所有buff
     * @return buff数组
     */
    public function getBuffs():Array {
        return this._buffs.slice(); // 返回副本以防止外部修改
    }
}