// org/flashNight/arki/component/Buff/BuffManager.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.gesh.property.*;

/**
 * Buff管理器 - 第二层：管理所有Buff并与PropertyAccessor集成
 */
class org.flashNight.arki.component.Buff.BuffManager {
    private var _targetObject:Object;
    private var _buffs:Object;              // Map: buffId -> IBuff
    private var _propertyBuffs:Object;      // Map: propertyName -> Array of buffIds
    private var _propertyAccessors:Object;  // Map: propertyName -> PropertyAccessor
    private var _calculator:BuffCalculator;
    private var _baseValues:Object;         // 存储基础值
    
    public function BuffManager(targetObject:Object) {
        this._targetObject = targetObject;
        this._buffs = {};
        this._propertyBuffs = {};
        this._propertyAccessors = {};
        this._calculator = new BuffCalculator();
        this._baseValues = {};
    }
    
    /**
     * 注册一个属性到Buff系统
     * @param propertyName 属性名
     * @param baseValue 基础值
     * @param onChangeCallback 值变化回调（可选）
     */
    public function registerProperty(
        propertyName:String, 
        baseValue:Number,
        onChangeCallback:Function
    ):Void {
        // 保存基础值
        this._baseValues[propertyName] = baseValue;
        
        // 初始化该属性的Buff列表
        this._propertyBuffs[propertyName] = [];
        
        // 创建计算属性，集成Buff系统
        var self:BuffManager = this;
        var accessor:PropertyAccessor = new PropertyAccessor(
            this._targetObject,
            propertyName,
            baseValue,
            // 计算函数：应用所有相关Buff
            function():Number {
                return self._calculatePropertyValue(propertyName);
            },
            // 变化回调
            onChangeCallback,
            null // 不使用验证，由Buff系统控制
        );
        
        this._propertyAccessors[propertyName] = accessor;
    }
    
    /**
     * 添加Buff
     */
    public function addBuff(buff:IBuff):Void {
        var buffId:String = buff.getId();
        
        // 避免重复添加
        if (this._buffs[buffId] != null) {
            trace("Warning: Buff " + buffId + " already exists, replacing...");
            this.removeBuff(buffId);
        }
        
        this._buffs[buffId] = buff;
        
        // 如果是PodBuff，注册到对应属性
        if (buff instanceof PodBuff) {
            var podBuff:PodBuff = PodBuff(buff);
            var propName:String = podBuff.getTargetProperty();
            
            if (this._propertyBuffs[propName] != null) {
                this._propertyBuffs[propName].push(buffId);
                this._invalidateProperty(propName);
            }
        } else {
            // MetaBuff可能影响多个属性，需要全局刷新
            this._invalidateAllProperties();
        }
        
        trace("Added buff: " + buffId + " (" + buff.getType() + ")");
    }
    
    /**
     * 移除Buff
     */
    public function removeBuff(buffId:String):Boolean {
        var buff:IBuff = this._buffs[buffId];
        if (buff == null) return false;
        
        // 从属性Buff列表中移除
        if (buff instanceof PodBuff) {
            var podBuff:PodBuff = PodBuff(buff);
            var propName:String = podBuff.getTargetProperty();
            var buffList:Array = this._propertyBuffs[propName];
            
            if (buffList != null) {
                var index:Number = -1;
                for (var i:Number = 0; i < buffList.length; i++) {
                    if (buffList[i] == buffId) {
                        index = i;
                        break;
                    }
                }
                if (index >= 0) {
                    buffList.splice(index, 1);
                    this._invalidateProperty(propName);
                }
            }
        } else {
            this._invalidateAllProperties();
        }
        
        // 清理Buff
        buff.destroy();
        delete this._buffs[buffId];
        
        trace("Removed buff: " + buffId);
        return true;
    }
    
    /**
     * 核心计算方法：计算属性的最终值
     */
    private function _calculatePropertyValue(propertyName:String):Number {
        var baseValue:Number = this._baseValues[propertyName];
        var context:BuffContext = new BuffContext(this._targetObject, propertyName, baseValue);
        
        // 重置计算器
        this._calculator.reset();
        
        // 应用所有相关的Buff
        for (var buffId:String in this._buffs) {
            var buff:IBuff = this._buffs[buffId];
            if (buff.isActive()) {
                buff.applyEffect(this._calculator, context);
            }
        }
        
        // 计算最终值
        return this._calculator.calculate(baseValue);
    }
    
    /**
     * 使特定属性失效，触发重新计算
     */
    private function _invalidateProperty(propertyName:String):Void {
        var accessor:PropertyAccessor = this._propertyAccessors[propertyName];
        if (accessor != null) {
            accessor.invalidate();
        }
    }
    
    /**
     * 使所有属性失效
     */
    private function _invalidateAllProperties():Void {
        for (var propName:String in this._propertyAccessors) {
            this._invalidateProperty(propName);
        }
    }
    
    /**
     * 清理过期的Buff
     */
    public function cleanupExpiredBuffs():Void {
        var expiredBuffs:Array = [];
        
        for (var buffId:String in this._buffs) {
            var buff:IBuff = this._buffs[buffId];
            if (!buff.isActive()) {
                expiredBuffs.push(buffId);
            }
        }
        
        for (var i:Number = 0; i < expiredBuffs.length; i++) {
            this.removeBuff(expiredBuffs[i]);
        }
        
        if (expiredBuffs.length > 0) {
            trace("Cleaned up " + expiredBuffs.length + " expired buffs");
        }
    }
    
    /**
     * 获取属性的当前值
     */
    public function getPropertyValue(propertyName:String):Number {
        return this._targetObject[propertyName];
    }
    
    /**
     * 获取属性的基础值
     */
    public function getBaseValue(propertyName:String):Number {
        return this._baseValues[propertyName];
    }
    
    /**
     * 更新基础值
     */
    public function setBaseValue(propertyName:String, newBaseValue:Number):Void {
        this._baseValues[propertyName] = newBaseValue;
        this._invalidateProperty(propertyName);
    }
    
    /**
     * 获取影响特定属性的Buff列表
     */
    public function getPropertyBuffs(propertyName:String):Array {
        var result:Array = [];
        var buffIds:Array = this._propertyBuffs[propertyName];
        
        if (buffIds != null) {
            for (var i:Number = 0; i < buffIds.length; i++) {
                var buff:IBuff = this._buffs[buffIds[i]];
                if (buff != null && buff.isActive()) {
                    result.push(buff);
                }
            }
        }
        
        return result;
    }
    
    /**
     * 销毁管理器
     */
    public function destroy():Void {
        // 清理所有Buff
        for (var buffId:String in this._buffs) {
            this._buffs[buffId].destroy();
        }
        
        // 清理所有PropertyAccessor
        for (var propName:String in this._propertyAccessors) {
            this._propertyAccessors[propName].destroy();
        }
        
        this._buffs = null;
        this._propertyBuffs = null;
        this._propertyAccessors = null;
        this._calculator = null;
        this._baseValues = null;
        this._targetObject = null;
    }
}