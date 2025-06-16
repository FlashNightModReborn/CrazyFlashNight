// org/flashNight/arki/component/Buff/PropertyContainer.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.gesh.property.*;

/**
 * 属性容器 - 与PropertyAccessor完美集成
 * 
 * 设计理念：
 * - PropertyContainer 负责buff逻辑和数值计算
 * - PropertyAccessor 负责属性访问接口和性能优化
 * - 两者协作提供完整的动态属性管理方案
 */
class org.flashNight.arki.component.Buff.PropertyContainer {
    
    // 核心数据
    private var _propertyName:String;
    private var _baseValue:Number;
    private var _buffs:Array;
    private var _calculator:IBuffCalculator;
    
    // 集成组件
    private var _target:Object;
    private var _accessor:PropertyAccessor;
    
    // 缓存和优化
    private var _cachedFinalValue:Number;
    private var _isDirty:Boolean = true;
    private var _changeCallback:Function;
    
    /**
     * 构造函数
     * @param target 目标对象
     * @param propertyName 属性名
     * @param baseValue 基础值
     * @param changeCallback 值变化回调（可选）
     */
    public function PropertyContainer(
        target:Object, 
        propertyName:String, 
        baseValue:Number, 
        changeCallback:Function
    ) {
        this._target = target;
        this._propertyName = propertyName;
        this._baseValue = baseValue;
        this._changeCallback = changeCallback;
        this._buffs = [];
        this._calculator = new BuffCalculator();
        
        // 创建PropertyAccessor，使用计算函数来获取最终值
        this._accessor = new PropertyAccessor(
            target,
            propertyName,
            baseValue,
            this._createComputeFunction(), // 计算函数
            this._createSetterFunction(),   // 设置回调
            null                          // 暂不使用验证函数
        );
    }
    
    /**
     * 创建计算函数 - 给PropertyAccessor使用
     * 这个函数会被PropertyAccessor的缓存机制优化
     */
    private function _createComputeFunction():Function {
        var self:PropertyContainer = this;
        return function():Number {
            return self._computeFinalValue();
        };
    }
    
    /**
     * 创建一个合格的 setter 函数，它接受新值作为参数。
     * 当外部直接设置属性时（如 target.hp = 150），此函数将被调用。
     */
    private function _createSetterFunction():Function {
        var self:PropertyContainer = this;
        // 这个函数将被 PropertyAccessor 作为 setter 使用，它会接收到外部赋的新值。
        return function(newValue:Number):Void {
            if (!isNaN(newValue)) {
                // 直接使用传入的新值更新基础值
                self._baseValue = newValue;
                // 使 PropertyContainer 和 PropertyAccessor 的缓存都失效
                self._markDirtyAndInvalidate();
            }
        };
    }

    
    /**
     * 核心计算方法 - 计算包含所有buff的最终值
     */
    private function _computeFinalValue():Number {
        if (!this._isDirty) {
            return this._cachedFinalValue;
        }
        
        // 重置计算器
        this._calculator.reset();
        
        // 应用所有激活的buff
        var context:BuffContext = new BuffContext(
            this._propertyName, 
            this._target, 
            null, 
            {}
        );
        
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isActive()) {
                buff.applyEffect(this._calculator, context);
            }
        }
        
        // 计算最终值
        this._cachedFinalValue = this._calculator.calculate(this._baseValue);
        this._isDirty = false;
        
        // 触发变化回调
        if (this._changeCallback) {
            this._changeCallback(this._propertyName, this._cachedFinalValue);
        }
        
        return this._cachedFinalValue;
    }
    
    /**
     * 添加buff
     */
    public function addBuff(buff:IBuff):Void {
        if (buff) {
            this._buffs.push(buff);
            this._markDirtyAndInvalidate();
        }
    }
    
    /**
     * 移除buff
     */
    public function removeBuff(buffId:String):Boolean {
        for (var i:Number = 0; i < this._buffs.length; i++) {
            if (this._buffs[i].getId() == buffId) {
                var removedBuff:IBuff = this._buffs.splice(i, 1)[0];
                removedBuff.destroy();
                this._markDirtyAndInvalidate();
                return true;
            }
        }
        return false;
    }
    
    /**
     * 移除所有buff
     */
    public function clearBuffs():Void {
        for (var i:Number = 0; i < this._buffs.length; i++) {
            this._buffs[i].destroy();
        }
        this._buffs.length = 0;
        this._markDirtyAndInvalidate();
    }
    
    /**
     * 设置基础值
     */
    public function setBaseValue(value:Number):Void {
        if (this._baseValue != value) {
            this._baseValue = value;
            this._markDirtyAndInvalidate();
        }
    }
    
    /**
     * 获取基础值
     */
    public function getBaseValue():Number {
        return this._baseValue;
    }
    
    /**
     * 获取最终计算值（通过PropertyAccessor的优化机制）
     */
    public function getFinalValue():Number {
        // 直接通过PropertyAccessor获取，利用其缓存优化
        return Number(this._target[this._propertyName]);
    }
    
    /**
     * 标记为脏数据并使PropertyAccessor缓存失效
     */
    private function _markDirtyAndInvalidate():Void {
        this._markDirty();
        this._accessor.invalidate(); // 通知PropertyAccessor重新计算
    }
    
    /**
     * 标记为脏数据
     */
    private function _markDirty():Void {
        this._isDirty = true;
    }
    
    /**
     * 强制重新计算
     */
    public function forceRecalculate():Number {
        this._markDirtyAndInvalidate();
        return this.getFinalValue();
    }
    
    /**
     * 获取buff数量
     */
    public function getBuffCount():Number {
        return this._buffs.length;
    }
    
    /**
     * 获取激活的buff数量
     */
    public function getActiveBuffCount():Number {
        var count:Number = 0;
        for (var i:Number = 0; i < this._buffs.length; i++) {
            if (this._buffs[i] && this._buffs[i].isActive()) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * 获取所有buff的副本（调试用）
     */
    public function getBuffs():Array {
        return this._buffs.slice();
    }
    
    /**
     * 检查是否有特定ID的buff
     */
    public function hasBuff(buffId:String):Boolean {
        for (var i:Number = 0; i < this._buffs.length; i++) {
            if (this._buffs[i].getId() == buffId) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 获取属性名
     */
    public function getPropertyName():String {
        return this._propertyName;
    }
    
    /**
     * 销毁容器
     */
    public function destroy():Void {
        // 清理所有buff
        this.clearBuffs();
        
        // 销毁PropertyAccessor
        if (this._accessor) {
            this._accessor.destroy();
            this._accessor = null;
        }
        
        // 清理引用
        this._target = null;
        this._calculator = null;
        this._changeCallback = null;
        this._buffs = null;
    }
    
    /**
     * 调试信息
     */
    public function toString():String {
        return "[PropertyContainer property: " + this._propertyName + 
               ", base: " + this._baseValue + 
               ", final: " + this.getFinalValue() + 
               ", buffs: " + this._buffs.length + "]";
    }
}