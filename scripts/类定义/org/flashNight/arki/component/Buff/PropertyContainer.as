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
 *
 * 版本历史:
 * v2.2 (2026-01) - 契约文档化
 *   [DOC] 添加OVERRIDE遍历方向契约说明
 *
 * v2.1 (2026-01) - Bugfix Review
 *   [P1-3] changeCallback无值比较问题 - 仅在值变化时触发回调
 *
 * ==================== 设计契约 ====================
 *
 * 【契约】OVERRIDE 冲突决策（遍历方向）
 *   - _computeFinalValue 使用 while(i--) 逆序遍历 _buffs 数组
 *   - 即：后添加的buff先apply，先添加的buff后apply
 *   - BuffCalculator 的 OVERRIDE 采用"最后写入wins"语义
 *   - 结果：多个 OVERRIDE 并存时，**添加顺序最早的 OVERRIDE 生效**
 *
 *   示例：
 *   - addBuff(OVERRIDE=500, id="first")  // 先添加
 *   - addBuff(OVERRIDE=999, id="second") // 后添加
 *   - 最终值 = 500（因为first最后apply，覆盖了second）
 *
 *   若需"新覆盖旧"语义：
 *   - 使用同ID替换机制（BuffManager.addBuff同ID会先移除旧buff）
 *   - 或者只保持同时存在一个OVERRIDE
 *
 * ================================================
 *
 * @version 2.2
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
    private var _buffContext:BuffContext; // [优化] 缓存BuffContext实例，避免重复创建
    
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
        
        // [优化] 在构造时创建一次BuffContext，之后重复使用
        this._buffContext = new BuffContext(
            this._propertyName, 
            this._target, 
            null, 
            {}
        );
        
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
    
    // =========================================================================
    // 核心计算与集成
    // =========================================================================
    
    /**
     * 核心计算方法 - 只处理 PodBuff
     * [P1-3 修复] 添加值比较，仅在值变化时触发回调
     */
    private function _computeFinalValue():Number {
        if (!this._isDirty) {
            return this._cachedFinalValue;
        }

        this._calculator.reset();

        var i:Number = this._buffs.length;
        var buff:IBuff;
        while (i--) {
            buff = this._buffs[i];
            if (buff && buff.isActive()) {
                // 双重保险：即使通过了 addBuff 的检查，这里再次确认
                if (buff.isPod()) {
                    buff.applyEffect(this._calculator, this._buffContext);
                } else {
                    // 这种情况理论上不应该发生
                    trace("[PropertyContainer] 错误：发现非 PodBuff 在计算中: " + buff.getType());
                }
            }
        }

        // [P1-3 修复] 保存旧值用于比较
        var oldValue:Number = this._cachedFinalValue;
        var newValue:Number = this._calculator.calculate(this._baseValue);
        this._cachedFinalValue = newValue;
        this._isDirty = false;

        // [P1-3 修复] 仅在值变化时触发回调（注意处理NaN情况）
        if (this._changeCallback) {
            // 值变化的判断：旧值是NaN，或者新旧值不相等
            var valueChanged:Boolean = isNaN(oldValue) || (oldValue != newValue);
            if (valueChanged) {
                this._changeCallback(this._propertyName, newValue);
            }
        }

        return this._cachedFinalValue;
    }
    
    /**
     * 创建计算函数 - 给PropertyAccessor使用
     */
    private function _createComputeFunction():Function {
        var self:PropertyContainer = this;
        return function():Number {
            return self._computeFinalValue();
        };
    }
    
    /**
     * 创建一个合格的 setter 函数，用于外部直接设置属性值
     */
    private function _createSetterFunction():Function {
        var self:PropertyContainer = this;
        return function(newValue:Number):Void {
            if (!isNaN(newValue)) {
                self._baseValue = newValue;
                self._markDirtyAndInvalidate();
            }
        };
    }
    
    // =========================================================================
    // 公共接口 - Buff管理
    // =========================================================================
    
    /**
     * 添加buff - 只接受 PodBuff
     * @param buff 要添加的Buff
     */
    public function addBuff(buff:IBuff):Void {
        if (!buff) return;
        
        // 关键验证：只接受 PodBuff
        if (!buff.isPod()) {
            trace("[PropertyContainer] 警告：尝试添加非 PodBuff 类型: " + buff.getType() + 
                " 到属性 " + this._propertyName + "，已拒绝");
            return;
        }
        
        // 额外验证：确保 PodBuff 影响的是正确的属性
        var podBuff:PodBuff = PodBuff(buff);
        if (podBuff.getTargetProperty() != this._propertyName) {
            trace("[PropertyContainer] 警告：PodBuff 目标属性不匹配。" +
                " 期望: " + this._propertyName + 
                ", 实际: " + podBuff.getTargetProperty());
            return;
        }
        
        this._buffs.push(buff);
        this._markDirtyAndInvalidate();
    }
    
    /**
     * 移除buff
     *
     * [Phase D / P2-1] 默认shouldDestroy=false，避免外部代码意外销毁BuffManager拥有的buff
     * BuffManager负责buff的生命周期管理，外部不应销毁buff
     *
     * @param buffId 要移除的buff ID
     * @param shouldDestroy 是否销毁buff（默认false，由BuffManager管理生命周期）
     * @return Boolean 是否成功移除
     */
    public function removeBuff(buffId:String, shouldDestroy:Boolean):Boolean {
        // [Phase D / P2-1] 默认不销毁
        if (shouldDestroy == undefined) shouldDestroy = false;

        // [优化] 使用反向循环遍历，便于安全地使用splice
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i].getId() == buffId) {
                var removedBuff:IBuff = this._buffs.splice(i, 1)[0];
                if (shouldDestroy) {
                    removedBuff.destroy();
                }
                this._markDirtyAndInvalidate();
                return true;
            }
        }
        return false;
    }
    
    /**
     * 移除所有buff
     *
     * [Phase C / P1-5] 默认shouldDestroy=false，避免外部代码意外销毁BuffManager拥有的buff
     * BuffManager负责buff的生命周期管理，外部不应调用带destroy的版本
     */
    public function clearBuffs(shouldDestroy:Boolean):Void {
        // [Phase C / P1-5] 默认不销毁，由BuffManager管理生命周期
        if (shouldDestroy == undefined) shouldDestroy = false;

        if (shouldDestroy) {
            while (_buffs.length > 0) _buffs.pop().destroy();
        } else {
            _buffs.length = 0;              // 只清列表，保留对象生命周期
        }
        _markDirtyAndInvalidate();
    }

    
    // =========================================================================
    // 公共接口 - 值管理
    // =========================================================================
    
    /**
     * 设置基础值
     *
     * [Phase A / P1-6] 添加NaN防守
     */
    public function setBaseValue(value:Number):Void {
        // [Phase A / P1-6] NaN防守
        var v:Number = Number(value);
        if (isNaN(v)) {
            trace("[PropertyContainer] 警告：setBaseValue收到NaN，已忽略");
            return;
        }

        if (this._baseValue != v) {
            this._baseValue = v;
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
        return Number(this._target[this._propertyName]);
    }
    
    /**
     * 强制重新计算
     */
    public function forceRecalculate():Number {
        this._markDirtyAndInvalidate();
        return this.getFinalValue();
    }
    
    // =========================================================================
    // 公共接口 - 查询与调试
    // =========================================================================
    
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
        // [优化] 使用反向while循环
        var i:Number = this._buffs.length;
        while (i--) {
            if (this._buffs[i] && this._buffs[i].isActive()) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * 检查是否有特定ID的buff
     */
    public function hasBuff(buffId:String):Boolean {
        // [优化] 使用反向while循环
        var i:Number = this._buffs.length;
        while (i--) {
            if (this._buffs[i].getId() == buffId) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 获取所有buff的副本（调试用）
     */
    public function getBuffs():Array {
        return this._buffs.slice();
    }
    
    /**
     * 获取属性名
     */
    public function getPropertyName():String {
        return this._propertyName;
    }
    
    // =========================================================================
    // 内部方法和生命周期
    // =========================================================================
    
    /**
     * 标记为脏数据并使PropertyAccessor缓存失效
     */
    private function _markDirtyAndInvalidate():Void {
        this._isDirty = true;
        this._accessor.invalidate(); // 通知PropertyAccessor重新计算
    }
    
    // 建议：容器持有底层 accessor 的引用，例如 this._accessor
    public function finalizeToPlainProperty():Void {
        if (this._accessor != null) {
            this._accessor.detach();  // 固化“当前可见值”为普通数据属性，并与 target 解耦
        }
    }

    /**
     * 销毁容器
     */
    public function destroy():Void {
        this.clearBuffs();
        
        if (this._accessor) {
            this._accessor.destroy();
            this._accessor = null;
        }
        
        this._target = null;
        this._calculator = null;
        this._changeCallback = null;
        this._buffs = null;
        this._buffContext = null; // 清理缓存的Context
    }
    
    /**
     * 调试信息
     */
    public function toString():String {
        return "[PropertyContainer property: " + this._propertyName + 
               ", base: " + this._baseValue + 
               ", final: " + this.getFinalValue() + 
               ", buffs: " + this.getBuffCount() + "]";
    }
}