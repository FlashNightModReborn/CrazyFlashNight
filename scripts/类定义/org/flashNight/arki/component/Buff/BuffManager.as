// BuffManager.as - 支持 MetaBuff 注入机制
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.component.*;

class org.flashNight.arki.component.Buff.BuffManager {
    
    // 核心数据结构
    private var _target:Object;                    // 宿主对象（Unit）
    private var _buffs:Array;                      // 所有Buff列表（包含 MetaBuff 和独立 PodBuff）
    private var _idMap:Object;                     // { id:String -> IBuff }
    private var _propertyContainers:Object;        // 属性容器映射 {propName: PropertyContainer}
    private var _pendingRemovals:Array;            // 待移除的Buff ID列表
    
    // MetaBuff 注入管理
    private var _metaBuffInjections:Object;        // { metaBuffId -> [injectedPodBuffIds] }
    private var _injectedPodBuffs:Object;          // { podBuffId -> parentMetaBuffId }
    
    // 性能优化
    private var _updateCounter:Number = 0;         
    private var _isDirty:Boolean = false;          
    
    // 事件回调
    private var _onBuffAdded:Function;
    private var _onBuffRemoved:Function;
    private var _onPropertyChanged:Function;
    
    /**
     * 构造函数
     */
    public function BuffManager(target:Object, callbacks:Object) {
        this._target = target;
        this._buffs = [];
        this._propertyContainers = {};
        this._pendingRemovals = [];
        this._idMap = {};
        
        // 初始化注入管理
        this._metaBuffInjections = {};
        this._injectedPodBuffs = {};
        
        // 设置回调
        if (callbacks) {
            this._onBuffAdded = callbacks.onBuffAdded;
            this._onBuffRemoved = callbacks.onBuffRemoved;
            this._onPropertyChanged = callbacks.onPropertyChanged;
        }
    }
    
    /**
     * 添加Buff（支持 MetaBuff 和 PodBuff）
     */
    public function addBuff(buff:IBuff, buffId:String):String {
        if (!buff) return null;
        
        var finalId:String = buffId || buff.getId();
        
        // 如果已存在同ID的Buff，先移除
        if (buffId && this._idMap[buffId]) {
            this.removeBuff(buffId);
        }

        this._buffs.push(buff);
        this._idMap[finalId] = buff;
        
        // 如果是 MetaBuff，立即处理初始注入
        if (!buff.isPod()) {
            var metaBuff:MetaBuff = MetaBuff(buff);
            this._injectMetaBuffPods(metaBuff);
        }
        
        this._markDirty();
        
        // 触发回调
        if (this._onBuffAdded) {
            this._onBuffAdded(buff, finalId);
        }
        
        return finalId;
    }
    
    /**
     * 移除Buff（自动处理级联删除）
     */
    public function removeBuff(buffId:String):Boolean {
        if (this._idMap[buffId]) {
            this._pendingRemovals.push(buffId);
            this._markDirty();
            return true;
        }
        return false;
    }
    
    /**
     * 核心更新方法
     */
    public function update(deltaFrames:Number):Void {
        this._updateCounter++;
        
        // 1. 处理待移除的Buff
        this._processPendingRemovals();
        
        // 2. 更新所有 MetaBuff 并处理状态变化
        this._updateMetaBuffsWithInjection(deltaFrames);
        
        // 3. 移除失效的独立 PodBuff
        this._removeInactivePodBuffs();
        
        // 4. 重建 PropertyContainer（如果需要）
        if (this._isDirty) {
            this._rebuildPropertyContainers();
            this._isDirty = false;
        }
    }
    
    /**
     * 更新 MetaBuff 并处理注入/注销
     */
    private function _updateMetaBuffsWithInjection(deltaFrames:Number):Void {
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            var buff:IBuff = this._buffs[i];
            if (buff && !buff.isPod()) {
                var metaBuff:MetaBuff = MetaBuff(buff);
                var stateInfo:Object = metaBuff.update(deltaFrames);
                
                // 处理状态变化
                if (stateInfo.stateChanged) {
                    if (stateInfo.needsInject) {
                        this._injectMetaBuffPods(metaBuff);
                    } else if (stateInfo.needsEject) {
                        this._ejectMetaBuffPods(metaBuff);
                    }
                }
                
                // 如果 MetaBuff 死亡，移除它
                if (!stateInfo.alive) {
                    this._removeMetaBuff(metaBuff);
                }
            }
        }
    }
    
    /**
     * 注入 MetaBuff 的 PodBuff
     */
    private function _injectMetaBuffPods(metaBuff:MetaBuff):Void {
        var metaId:String = metaBuff.getId();
        
        // 创建并注入 PodBuff
        var podBuffs:Array = metaBuff.createPodBuffsForInjection();
        var injectedIds:Array = [];
        
        for (var i:Number = 0; i < podBuffs.length; i++) {
            var podBuff:PodBuff = podBuffs[i];
            var podId:String = podBuff.getId();
            
            // 添加到系统
            this._buffs.push(podBuff);
            this._idMap[podId] = podBuff;
            
            // 记录注入关系
            injectedIds.push(podId);
            this._injectedPodBuffs[podId] = metaId;
        }
        
        // 记录该 MetaBuff 注入的所有 PodBuff
        this._metaBuffInjections[metaId] = injectedIds;
        
        this._markDirty();
    }
    
    /**
     * 注销 MetaBuff 的 PodBuff
     */
    private function _ejectMetaBuffPods(metaBuff:MetaBuff):Void {
        var metaId:String = metaBuff.getId();
        var injectedIds:Array = this._metaBuffInjections[metaId];
        
        if (injectedIds) {
            // 移除所有注入的 PodBuff
            for (var i:Number = 0; i < injectedIds.length; i++) {
                var podId:String = injectedIds[i];
                this._removePodBuff(podId);
            }
            
            // 清理注入记录
            delete this._metaBuffInjections[metaId];
            metaBuff.clearInjectedBuffIds();
        }
        
        this._markDirty();
    }
    
    /**
     * 移除单个 PodBuff
     */
    private function _removePodBuff(podId:String):Void {
        var podBuff:IBuff = this._idMap[podId];
        if (!podBuff) return;
        
        // 从数组中移除
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] === podBuff) {
                this._buffs.splice(i, 1);
                break;
            }
        }
        
        // 清理映射
        delete this._idMap[podId];
        delete this._injectedPodBuffs[podId];
        
        // 销毁
        podBuff.destroy();
        
        // 触发回调
        if (this._onBuffRemoved) {
            this._onBuffRemoved(podBuff, podId);
        }
    }
    
    /**
     * 移除 MetaBuff（包括其注入的所有 PodBuff）
     */
    private function _removeMetaBuff(metaBuff:MetaBuff):Void {
        var metaId:String = metaBuff.getId();
        
        // 先注销所有注入的 PodBuff
        this._ejectMetaBuffPods(metaBuff);
        
        // 从数组中移除 MetaBuff
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] === metaBuff) {
                this._buffs.splice(i, 1);
                break;
            }
        }
        
        // 清理映射
        delete this._idMap[metaId];
        
        // 销毁
        metaBuff.destroy();
        
        // 触发回调
        if (this._onBuffRemoved) {
            this._onBuffRemoved(metaBuff, metaId);
        }
    }
    
    /**
     * 处理待移除的Buff
     */
    private function _processPendingRemovals():Void {
        for (var i:Number = 0; i < this._pendingRemovals.length; i++) {
            var buffId:String = this._pendingRemovals[i];
            var buff:IBuff = this._idMap[buffId];
            
            if (buff) {
                if (buff.isPod()) {
                    // 检查是否是注入的 PodBuff
                    var parentMetaId:String = this._injectedPodBuffs[buffId];
                    if (parentMetaId) {
                        // 从父 MetaBuff 的注入列表中移除
                        var injectedList:Array = this._metaBuffInjections[parentMetaId];
                        if (injectedList) {
                            for (var j:Number = 0; j < injectedList.length; j++) {
                                if (injectedList[j] == buffId) {
                                    injectedList.splice(j, 1);
                                    break;
                                }
                            }
                        }
                    }
                    this._removePodBuff(buffId);
                } else {
                    this._removeMetaBuff(MetaBuff(buff));
                }
            }
        }
        this._pendingRemovals.length = 0;
    }
    
    /**
     * 移除失效的独立 PodBuff（非注入的）
     */
    private function _removeInactivePodBuffs():Void {
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isPod() && !buff.isActive()) {
                // 只移除非注入的 PodBuff
                var buffId:String = buff.getId();
                if (!this._injectedPodBuffs[buffId]) {
                    this._removePodBuff(buffId);
                }
            }
        }
    }
    
    /**
     * 重建 PropertyContainer（只包含激活的 PodBuff）
     */
    private function _rebuildPropertyContainers():Void {
        // 收集所有需要的属性
        var affectedProperties:Object = {};
        
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isPod() && buff.isActive()) {
                var podBuff:PodBuff = PodBuff(buff);
                affectedProperties[podBuff.getTargetProperty()] = true;
            }
        }
        
        // 移除不再需要的 PropertyContainer
        for (var propName:String in this._propertyContainers) {
            if (!affectedProperties[propName]) {
                this._destroyPropertyContainer(propName);
            }
        }
        
        // 创建新的 PropertyContainer
        for (var newProp:String in affectedProperties) {
            if (!this._propertyContainers[newProp]) {
                this._createPropertyContainer(newProp);
            }
        }
        
        // 重新分配 PodBuff
        this._redistributePodBuffs();
    }
    
    /**
     * 重新分配 PodBuff 到 PropertyContainer
     */
    private function _redistributePodBuffs():Void {
        // 清空所有 PropertyContainer
        for (var propName:String in this._propertyContainers) {
            var container:PropertyContainer = this._propertyContainers[propName];
            if (container) {
                container.clearBuffs(false);
            }
        }
        
        // 只添加激活的 PodBuff
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isPod() && buff.isActive()) {
                var podBuff:PodBuff = PodBuff(buff);
                var targetProp:String = podBuff.getTargetProperty();
                var pc:PropertyContainer = this._propertyContainers[targetProp];
                if (pc) {
                    pc.addBuff(podBuff);
                }
            }
        }
        
        // 触发重新计算
        for (var prop:String in this._propertyContainers) {
            var container2:PropertyContainer = this._propertyContainers[prop];
            if (container2) {
                container2.forceRecalculate();
            }
        }
    }
    
    /**
     * 创建 PropertyContainer
     */
    private function _createPropertyContainer(propertyName:String):Void {
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
     * 销毁 PropertyContainer
     */
    private function _destroyPropertyContainer(propertyName:String):Void {
        var container:PropertyContainer = this._propertyContainers[propertyName];
        if (container) {
            container.destroy();
            delete this._propertyContainers[propertyName];
        }
    }
    
    /**
     * 清空所有Buff
     */
    public function clearAllBuffs():Void {
        // 先移除所有 MetaBuff（会级联删除注入的 PodBuff）
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            var buff:IBuff = this._buffs[i];
            if (buff && !buff.isPod()) {
                this._removeMetaBuff(MetaBuff(buff));
            }
        }
        
        // 再移除剩余的独立 PodBuff
        for (var j:Number = this._buffs.length - 1; j >= 0; j--) {
            var podBuff:IBuff = this._buffs[j];
            if (podBuff) {
                podBuff.destroy();
            }
        }
        
        this._buffs.length = 0;
        this._idMap = {};
        this._metaBuffInjections = {};
        this._injectedPodBuffs = {};
        
        this._markDirty();
        this._cleanupAllPropertyContainers();
    }
    
    /**
     * 清理所有 PropertyContainer
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
    
    /**
     * 查找Buff
     */
    public function findBuff(buffId:String):IBuff {
        return this._idMap[buffId] || null;
    }
    
    /**
     * 获取所有Buff（包括 MetaBuff 和 PodBuff）
     */
    public function getAllBuffs():Array {
        return this._buffs.slice();
    }
    
    /**
     * 获取激活的Buff数量
     */
    public function getActiveBuffCount():Number {
        var count:Number = 0;
        
        // 统计 MetaBuff
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff && !buff.isPod() && buff.isActive()) {
                count++;
            }
        }
        
        // 统计独立的 PodBuff（非注入的）
        for (var j:Number = 0; j < this._buffs.length; j++) {
            var podBuff:IBuff = this._buffs[j];
            if (podBuff && podBuff.isPod() && !this._injectedPodBuffs[podBuff.getId()]) {
                if (podBuff.isActive()) {
                    count++;
                }
            }
        }
        
        return count;
    }
    
    /**
     * 获取调试信息
     */
    public function getDebugInfo():Object {
        var info:Object = {
            totalBuffs: this._buffs.length,
            metaBuffs: 0,
            podBuffs: 0,
            injectedPods: 0,
            independentPods: 0,
            properties: 0
        };
        
        // 统计各类型 Buff
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff) {
                if (buff.isPod()) {
                    info.podBuffs++;
                    if (this._injectedPodBuffs[buff.getId()]) {
                        info.injectedPods++;
                    } else {
                        info.independentPods++;
                    }
                } else {
                    info.metaBuffs++;
                }
            }
        }
        
        // 统计属性容器
        for (var prop:String in this._propertyContainers) {
            info.properties++;
        }
        
        return info;
    }
    
    /**
     * 销毁
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
        var info:Object = this.getDebugInfo();
        return "[BuffManager total: " + info.totalBuffs + 
               " (meta: " + info.metaBuffs + 
               ", pods: " + info.podBuffs + 
               " [inj: " + info.injectedPods + 
               ", ind: " + info.independentPods + "])" +
               ", props: " + info.properties + 
               ", updates: " + this._updateCounter + "]";
    }
}