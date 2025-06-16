// 改进后的 MetaBuff.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.component.*;

class org.flashNight.arki.component.Buff.MetaBuff extends BaseBuff {
    private var _components:Array;      // [IBuffComponent]
    private var _childBuffs:Array;      // 内嵌 PodBuff 等
    private var _isActive:Boolean;      // 激活状态
    private var _priority:Number;       // 优先级（影响update顺序）
    
    /**
     * @param childBuffs Array.<IBuff>  数值 Buff 列表
     * @param comps      Array.<IBuffComponent> 附加组件
     * @param priority   Number 优先级（可选）
     */
    public function MetaBuff(childBuffs:Array, comps:Array, priority:Number) {
        super();
        this._childBuffs = childBuffs || [];
        this._components = comps || [];
        this._isActive = true;
        this._priority = priority || 0;
        
        // 让组件知道宿主是谁
        this._attachAllComponents();
    }
    
    /**
     * 挂载所有组件
     */
    private function _attachAllComponents():Void {
        for (var i:Number = 0; i < this._components.length; i++) {
            var comp:IBuffComponent = this._components[i];
            if (comp) {
                comp.onAttach(this);
            }
        }
    }
    
    /**
     * 代理 applyEffect：把效果分派到子 Buff
     * 只有激活状态才应用效果
     */
    public function applyEffect(calc:IBuffCalculator, ctx:BuffContext):Void {
        if (!this._isActive) return;
        
        for (var i:Number = 0; i < this._childBuffs.length; i++) {
            var childBuff:IBuff = this._childBuffs[i];
            if (childBuff && childBuff.isActive()) {
                childBuff.applyEffect(calc, ctx);
            }
        }
    }
    
    /** 
     * 每帧推进，由 BuffManager 调用 
     * @param deltaFrames 增量帧数
     * @return Boolean 是否仍存活
     */
    public function update(deltaFrames:Number):Boolean {
        if (!this._isActive) return false;
        
        var hasActiveComponents:Boolean = false;
        
        // 逆序遍历，安全删除失效组件
        for (var i:Number = this._components.length - 1; i >= 0; i--) {
            var comp:IBuffComponent = this._components[i];
            if (comp) {
                if (comp.update(this, deltaFrames)) {
                    hasActiveComponents = true;
                } else {
                    // 组件失效：安全卸载
                    this._detachComponent(i);
                }
            }
        }
        
        // 检查子Buff是否还有激活的
        var hasActiveChildBuffs:Boolean = this._hasActiveChildBuffs();
        
        // MetaBuff存活条件：有激活组件 OR 有激活子Buff
        var shouldStayAlive:Boolean = hasActiveComponents || hasActiveChildBuffs;
        
        if (!shouldStayAlive) {
            this._isActive = false;
        }
        
        return shouldStayAlive;
    }
    
    /**
     * 安全卸载组件
     */
    private function _detachComponent(index:Number):Void {
        if (index >= 0 && index < this._components.length) {
            var comp:IBuffComponent = this._components[index];
            if (comp) {
                comp.onDetach();
            }
            this._components.splice(index, 1);
        }
    }
    
    /**
     * 检查是否有激活的子Buff
     */
    private function _hasActiveChildBuffs():Boolean {
        for (var i:Number = 0; i < this._childBuffs.length; i++) {
            var childBuff:IBuff = this._childBuffs[i];
            if (childBuff && childBuff.isActive()) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 重写isActive方法
     */
    public function isActive():Boolean {
        return this._isActive;
    }
    
    /**
     * 手动停用Buff
     */
    public function deactivate():Void {
        this._isActive = false;
    }
    
    /**
     * 动态添加组件（运行时扩展能力）
     */
    public function addComponent(comp:IBuffComponent):Void {
        if (comp && this._isActive) {
            this._components.push(comp);
            comp.onAttach(this);
        }
    }
    
    /**
     * 动态添加子Buff
     */
    public function addChildBuff(buff:IBuff):Void {
        if (buff && this._isActive) {
            this._childBuffs.push(buff);
        }
    }
    
    /**
     * 获取优先级（供BuffManager排序用）
     */
    public function getPriority():Number {
        return this._priority;
    }
    
    /**
     * 获取组件数量（调试用）
     */
    public function getComponentCount():Number {
        return this._components.length;
    }
    
    /**
     * 获取子Buff数量（调试用）
     */
    public function getChildBuffCount():Number {
        return this._childBuffs.length;
    }
    
    /**
     * 销毁MetaBuff
     */
    public function destroy():Void {
        // 清理所有组件
        for (var i:Number = 0; i < this._components.length; i++) {
            var comp:IBuffComponent = this._components[i];
            if (comp) {
                comp.onDetach();
            }
        }
        
        // 清理所有子Buff
        for (var j:Number = 0; j < this._childBuffs.length; j++) {
            var childBuff:IBuff = this._childBuffs[j];
            if (childBuff) {
                childBuff.destroy();
            }
        }
        
        // 清理引用
        this._components = null;
        this._childBuffs = null;
        this._isActive = false;
        
        super.destroy();
    }
    
    /**
     * 调试信息
     */
    public function toString():String {
        return "[MetaBuff id: " + this.getId() + 
               ", active: " + this._isActive +
               ", components: " + this._components.length + 
               ", childBuffs: " + this._childBuffs.length + 
               ", priority: " + this._priority + "]";
    }
}