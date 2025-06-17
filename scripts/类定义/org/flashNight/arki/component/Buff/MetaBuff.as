// 改进后的 MetaBuff.as - 专注于状态管理
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.component.Buff.MetaBuff extends BaseBuff {
    // 状态枚举
    private static var STATE_INACTIVE:Number = 0;
    private static var STATE_ACTIVE:Number = 1;
    private static var STATE_PENDING_DEACTIVATE:Number = 2;
    
    private var _components:Array;      // [IBuffComponent]
    private var _childBuffs:Array;      // 内嵌 PodBuff 模板
    private var _priority:Number;       
    private var _componentBased:Boolean;
    
    // 状态管理
    private var _currentState:Number;
    private var _lastState:Number;
    private var _injectedBuffIds:Array; // 已注入的 PodBuff ID 列表
    
    /**
     * @param childBuffs Array.<PodBuff>  数值 Buff 模板列表
     * @param comps      Array.<IBuffComponent> 附加组件
     * @param priority   Number 优先级（可选）
     */
    public function MetaBuff(childBuffs:Array, comps:Array, priority:Number) {
        super();
        this._type = "MetaBuff";
        this._childBuffs = childBuffs || [];
        this._components = comps || [];
        this._priority = priority || 0;
        this._componentBased = this._components.length > 0;
        
        // 初始状态
        this._currentState = STATE_ACTIVE; // 初始即激活
        this._lastState = STATE_INACTIVE;
        this._injectedBuffIds = [];
        
        // 验证子 Buff 必须是 PodBuff
        for (var i:Number = 0; i < this._childBuffs.length; i++) {
            if (!this._childBuffs[i].isPod()) {
                trace("[MetaBuff] 警告：只接受 PodBuff 作为子 Buff");
                this._childBuffs.splice(i, 1);
                i--;
            }
        }
        
        // 挂载组件
        this._attachAllComponents();
    }
    
    /**
     * 重写 applyEffect - MetaBuff 不参与计算
     * BuffCalculator 永远不会调用这个方法
     */
    public function applyEffect(calc:IBuffCalculator, ctx:BuffContext):Void {
        // 空实现 - MetaBuff 不直接参与数值计算
    }
    
    /**
     * 核心更新方法 - 返回状态变化信息
     * @param deltaFrames 增量帧数
     * @return Object 状态变化信息 {alive:Boolean, stateChanged:Boolean, needsInject:Boolean, needsEject:Boolean}
     */
    public function update(deltaFrames:Number):Object {
        // 保存上一次状态
        this._lastState = this._currentState;
        
        // 更新组件
        var compsAlive:Boolean = this._updateComponents(deltaFrames);
        var childAlive:Boolean = this._hasValidChildBuffs();
        
        // 根据类型决定存活条件
        var shouldBeActive:Boolean = this._componentBased ? compsAlive : childAlive;
        
        // 状态机更新
        switch (this._currentState) {
            case STATE_INACTIVE:
                if (shouldBeActive) {
                    this._currentState = STATE_ACTIVE;
                }
                break;
                
            case STATE_ACTIVE:
                if (!shouldBeActive) {
                    this._currentState = STATE_PENDING_DEACTIVATE;
                }
                break;
                
            case STATE_PENDING_DEACTIVATE:
                // 给一帧的缓冲时间，确保 BuffManager 能处理注销
                this._currentState = STATE_INACTIVE;
                break;
        }
        
        // 构建状态变化信息
        var stateInfo:Object = {
            alive: this._currentState != STATE_INACTIVE,
            stateChanged: this._currentState != this._lastState,
            needsInject: false,
            needsEject: false
        };
        
        // 判断是否需要注入/注销
        if (this._lastState == STATE_INACTIVE && this._currentState == STATE_ACTIVE) {
            stateInfo.needsInject = true;
        } else if (this._lastState == STATE_ACTIVE && this._currentState == STATE_PENDING_DEACTIVATE) {
            stateInfo.needsEject = true;
        }
        
        return stateInfo;
    }
    
    /**
     * 获取需要注入的 PodBuff 列表
     * @return Array 新创建的 PodBuff 实例数组
     */
    public function createPodBuffsForInjection():Array {
        var podBuffs:Array = [];
        
        for (var i:Number = 0; i < this._childBuffs.length; i++) {
            var template:PodBuff = PodBuff(this._childBuffs[i]);
            if (template && template.isActive()) {
                // 创建新的 PodBuff 实例（复制模板）
                var newPod:PodBuff = new PodBuff(
                    template.getTargetProperty(),
                    template.getCalculationType(),
                    template.getValue()
                );
                podBuffs.push(newPod);
                // 记录注入的 ID
                this._injectedBuffIds.push(newPod.getId());
            }
        }
        
        return podBuffs;
    }
    
    /**
     * 获取需要注销的 PodBuff ID 列表
     * @return Array Buff ID 数组
     */
    public function getInjectedBuffIds():Array {
        return this._injectedBuffIds.slice(); // 返回副本
    }
    
    /**
     * 清空已注入记录（在注销完成后调用）
     */
    public function clearInjectedBuffIds():Void {
        this._injectedBuffIds.length = 0;
    }
    
    /**
     * 更新所有组件
     */
    private function _updateComponents(deltaFrames:Number):Boolean {
        var anyAlive:Boolean = false;
        
        for (var i:Number = this._components.length - 1; i >= 0; i--) {
            var comp:IBuffComponent = this._components[i];
            if (comp && comp.update(this, deltaFrames)) {
                anyAlive = true;
            } else {
                this._detachComponent(i);
            }
        }
        
        return anyAlive;
    }
    
    /**
     * 检查是否有有效的子 Buff
     */
    private function _hasValidChildBuffs():Boolean {
        for (var i:Number = 0; i < this._childBuffs.length; i++) {
            var childBuff:IBuff = this._childBuffs[i];
            if (childBuff && childBuff.isActive()) {
                return true;
            }
        }
        return false;
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
     * 重写 isActive
     */
    public function isActive():Boolean {
        return this._currentState != STATE_INACTIVE;
    }
    
    /**
     * 重写 isPod
     */
    public function isPod():Boolean {
        return false;
    }
    
    /**
     * 获取当前状态（调试用）
     */
    public function getCurrentState():Number {
        return this._currentState;
    }
    
    /**
     * 手动停用
     */
    public function deactivate():Void {
        if (this._currentState == STATE_ACTIVE) {
            this._currentState = STATE_PENDING_DEACTIVATE;
        }
    }
    
    /**
     * 动态添加组件
     */
    public function addComponent(comp:IBuffComponent):Void {
        if (comp && this.isActive()) {
            this._components.push(comp);
            comp.onAttach(this);
            
            // 如果之前没有组件，现在变成基于组件的
            if (!this._componentBased && this._components.length > 0) {
                this._componentBased = true;
            }
        }
    }
    
    /**
     * 获取子 Buff（只读访问）
     */
    public function getChildBuff(index:Number):IBuff {
        return this._childBuffs[index];
    }
    
    /**
     * 获取子 Buff 数量
     */
    public function getChildBuffCount():Number {
        return this._childBuffs.length;
    }
    
    /**
     * 获取优先级
     */
    public function getPriority():Number {
        return this._priority;
    }
    
    /**
     * 销毁
     */
    public function destroy():Void {
        // 清理组件
        for (var i:Number = 0; i < this._components.length; i++) {
            var comp:IBuffComponent = this._components[i];
            if (comp) {
                comp.onDetach();
            }
        }
        
        // 注意：不销毁子 Buff 模板，它们可能被复用
        
        // 清理引用
        this._components = null;
        this._childBuffs = null;
        this._injectedBuffIds = null;
        this._currentState = STATE_INACTIVE;
        
        super.destroy();
    }
    
    /**
     * 调试信息
     */
    public function toString():String {
        var stateStr:String = "UNKNOWN";
        switch (this._currentState) {
            case STATE_INACTIVE: stateStr = "INACTIVE"; break;
            case STATE_ACTIVE: stateStr = "ACTIVE"; break;
            case STATE_PENDING_DEACTIVATE: stateStr = "PENDING_DEACTIVATE"; break;
        }
        
        return "[MetaBuff id: " + this.getId() + 
               ", state: " + stateStr +
               ", components: " + this._components.length + 
               ", childBuffs: " + this._childBuffs.length + 
               ", injected: " + this._injectedBuffIds.length + "]";
    }
}