// BuffManager.as - 核心Buff管理器
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.component.*;

class org.flashNight.arki.component.Buff.BuffManager {
    
    // 核心数据结构
    private var _target:Object;                    // 宿主对象（Unit）
    private var _buffs:Array;                      // 所有Buff列表
    private var _idMap:Object;                     // { id:String -> IBuff }
    private var _propertyContainers:Object;        // 属性容器映射 {propName: PropertyContainer}
    private var _pendingRemovals:Array;            // 待移除的Buff ID列表
    
    // 性能优化
    private var _updateCounter:Number = 0;         // 更新计数器
    private var _isDirty:Boolean = false;          // 是否需要重新计算
    
    // 事件回调
    private var _onBuffAdded:Function;
    private var _onBuffRemoved:Function;
    private var _onPropertyChanged:Function;
    
    /**
     * 构造函数
     * @param target 宿主对象
     * @param callbacks 回调函数集合（可选）
     */
    public function BuffManager(target:Object, callbacks:Object) {
        this._target = target;
        this._buffs = [];
        this._propertyContainers = {};
        this._pendingRemovals = [];
        this._idMap  = {};
        
        // 设置回调
        if (callbacks) {
            this._onBuffAdded = callbacks.onBuffAdded;
            this._onBuffRemoved = callbacks.onBuffRemoved;
            this._onPropertyChanged = callbacks.onPropertyChanged;
        }
    }
    
    // === 静态工厂方法 ===
    
    // === 占位 ===
    
    // === 核心Buff管理 ===
    
    /**
     * 添加Buff
     * @param buff 要添加的Buff
     * @param buffId 自定义ID（可选，用于替换现有Buff）
     */
    public function addBuff(buff:IBuff, buffId:String):String {
        if (!buff) return null;
        
        var finalId:String = buffId || buff.getId();
        
        // 如果已存在同ID的Buff，先移除
        if (buffId) {
            this.removeBuff(buffId);
        }
        
        this._buffs.push(buff);
        this._idMap[finalId] = buff;
        this._markDirty();
        
        // 触发回调
        if (this._onBuffAdded) {
            this._onBuffAdded(buff, finalId);
        }
        
        return finalId;
    }
    
    /**
     * 移除Buff,真正删除时同步清理
     * @param buffId Buff ID
     * @return Boolean 是否成功移除
     */
    public function removeBuff(buffId:String):Boolean {
        if (_idMap[buffId]) {
            _pendingRemovals.push(buffId);
            _markDirty();
            return true;
        }
        return false;
    }

    
    /**
     * 清空所有Buff
     */
    public function clearAllBuffs():Void {
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff) {
                buff.destroy();
            }
        }
        this._buffs.length = 0;
        this._markDirty();
        
        // 清理所有PropertyContainer
        this._cleanupAllPropertyContainers();
    }
    
    /**
     * 核心更新方法 - 由Unit每4帧调用
     * @param deltaFrames 增量帧数
     */
    public function update(deltaFrames:Number):Void {
        this._updateCounter++;
        
        // 1. 处理待移除的Buff
        this._processPendingRemovals();
        
        // 2. 更新所有MetaBuff
        this._updateMetaBuffs(deltaFrames);
        
        // 3. 移除失效的Buff
        this._removeInactiveBuffs();
        
        // 4. 重建PropertyContainer（如果需要）
        if (this._isDirty) {
            this._rebuildPropertyContainers();
            this._isDirty = false;
        }
    }
    
    /**
     * 处理待移除的Buff
     */
    private function _processPendingRemovals():Void {
        for (var i:Number = 0; i < this._pendingRemovals.length; i++) {
            var buffId:String = this._pendingRemovals[i];
            this._removeBuffById(buffId);
        }
        this._pendingRemovals.length = 0;
    }
    
    /**
     * 实际移除Buff
     */
    private function _removeBuffById(buffId:String):Void {
        var buff:IBuff = _idMap[buffId];
        if (!buff) return;

        // 从数组里删
        for (var i:Number=_buffs.length-1; i>=0; i--) {
            if (_buffs[i] === buff) {
                buff.destroy();
                _buffs.splice(i,1);
                break;
            }
        }
        delete _idMap[buffId];           // <-- 清理映射
        if (_onBuffRemoved) _onBuffRemoved(buff, buffId);
        _markDirty();
    }

    
    /**
     * 更新所有MetaBuff
     */
    private function _updateMetaBuffs(deltaFrames:Number):Void {
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff instanceof MetaBuff) {
                var metaBuff:MetaBuff = MetaBuff(buff);
                // MetaBuff的update方法会处理自身组件的生命周期
                metaBuff.update(deltaFrames);
            }
        }
    }
    
    /**
     * 移除失效的Buff
     */
    private function _removeInactiveBuffs():Void {
        for (var i:Number=_buffs.length-1; i>=0; i--) {
            var buff:IBuff = _buffs[i];
            if (buff && !buff.isActive()) {
                // 找到对应 key
                for (var id:String in _idMap) {
                    if (_idMap[id] === buff) { delete _idMap[id]; break; }
                }
                buff.destroy();
                _buffs.splice(i,1);
                _markDirty();
                if (_onBuffRemoved) _onBuffRemoved(buff, id);
            }
        }
    }

    
    /**
     * 重建PropertyContainer
     */
    private function _rebuildPropertyContainers():Void {
        // 收集所有受影响的属性
        var affectedProperties:Object = {};
        
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isActive()) {
                var properties:Array = this._getAffectedProperties(buff);
                for (var j:Number = 0; j < properties.length; j++) {
                    affectedProperties[properties[j]] = true;
                }
            }
        }
        
        // 移除不再需要的PropertyContainer
        for (var propName:String in this._propertyContainers) {
            if (!affectedProperties[propName]) {
                this._destroyPropertyContainer(propName);
            }
        }
        
        // 创建新的PropertyContainer
        for (var newProp:String in affectedProperties) {
            if (!this._propertyContainers[newProp]) {
                this._createPropertyContainer(newProp);
            }
        }
        
        // 重新分配Buff到PropertyContainer
        this._redistributeBuffs();
    }
    
    /**
     * 获取Buff影响的属性列表
     */
    private function _getAffectedProperties(buff:IBuff):Array {
        var properties:Array = [];
        
        if (buff instanceof PodBuff) {
            var podBuff:PodBuff = PodBuff(buff);
            properties.push(podBuff.getTargetProperty());
        } else if (buff instanceof MetaBuff) {
            // MetaBuff通过子Buff影响属性
            // 这里需要遍历其子Buff
            // 暂时简化处理
        }
        
        return properties;
    }
    
    /**
     * 创建PropertyContainer
     */
    private function _createPropertyContainer(propertyName:String):Void {
        // 获取基础值
        var baseValue:Number = this._target[propertyName] || 0;
        
        var container:PropertyContainer = new PropertyContainer(
            this._target,
            propertyName,
            baseValue,
            this._onPropertyChanged
        );
        
        this._propertyContainers[propertyName] = container;
    }
    
    /**
     * 销毁PropertyContainer
     */
    private function _destroyPropertyContainer(propertyName:String):Void {
        var container:PropertyContainer = this._propertyContainers[propertyName];
        if (container) {
            container.destroy();
            delete this._propertyContainers[propertyName];
        }
    }
    
    /**
     * 重新分配Buff到PropertyContainer
     */
    private function _redistributeBuffs():Void {
        // 清空所有PropertyContainer的Buff
        for (var propName:String in this._propertyContainers) {
            var container:PropertyContainer = this._propertyContainers[propName];
            if (container) {
                container.clearBuffs();
            }
        }
        
        // 重新添加所有激活的Buff
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isActive()) {
                this._addBuffToContainers(buff);
            }
        }
    }
    
    /**
     * 将Buff添加到对应的PropertyContainer
     */
    private function _addBuffToContainers(buff:IBuff):Void {
        if (buff instanceof PodBuff) {
            var podBuff:PodBuff = PodBuff(buff);
            var propName:String = podBuff.getTargetProperty();
            var container:PropertyContainer = this._propertyContainers[propName];
            if (container) {
                container.addBuff(buff);
            }
        }
        // MetaBuff的处理...
    }
    
    /**
     * 清理所有PropertyContainer
     */
    private function _cleanupAllPropertyContainers():Void {
        for (var propName:String in this._propertyContainers) {
            this._destroyPropertyContainer(propName);
        }
    }
    
    /**
     * 标记为需要重建
     */
    private function _markDirty():Void {
        this._isDirty = true;
    }
    
    // === 查询接口 ===
    
    /**
     * 查找Buff
     */
    public function findBuff(buffId:String):IBuff {
        return _idMap[buffId] || null;
    }

    
    /**
     * 获取所有Buff
     */
    public function getAllBuffs():Array {
        return this._buffs.slice(); // 返回副本
    }
    
    /**
     * 获取激活的Buff数量
     */
    public function getActiveBuffCount():Number {
        var count:Number = 0;
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isActive()) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * 销毁BuffManager
     */
    public function destroy():Void {
        this.clearAllBuffs();
        this._target = null;
        this._onBuffAdded = null;
        this._onBuffRemoved = null;
        this._onPropertyChanged = null;
    }
    
    /**
     * 调试信息
     */
    public function toString():String {
        return "[BuffManager buffs: " + this._buffs.length + 
               ", properties: " + this._getPropertyContainerCount() + 
               ", updateCount: " + this._updateCounter + "]";
    }
    
    private function _getPropertyContainerCount():Number {
        var count:Number = 0;
        for (var prop:String in this._propertyContainers) {
            count++;
        }
        return count;
    }
}