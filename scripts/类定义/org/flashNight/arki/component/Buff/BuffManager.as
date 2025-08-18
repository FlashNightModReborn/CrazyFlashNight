// BuffManager.as - 支持 MetaBuff 注入机制（升级版：Sticky PropertyContainer 设计）
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
    private var _dirtyProps:Object = {};           // 增量脏集 {propName:true}
    
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
    
    // =========================
    // 对外 API
    // =========================
    
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
        
        // 预先确保容器存在（PodBuff）
        if (buff.isPod()) {
            var pod:PodBuff = PodBuff(buff);
            var prop:String = pod.getTargetProperty();
            ensurePropertyContainerExists(prop);
            _markPropDirty(prop);
        } else {
            // 如果是 MetaBuff，立即处理初始注入（注入内会确保容器）
            var metaBuff:MetaBuff = MetaBuff(buff);
            this._injectMetaBuffPods(metaBuff);
        }
        
        this._markDirty();
        
        // 触发回调
        if (this._onBuffAdded) {
            this._onBuffAdded(finalId, buff);
        }
        return finalId;
    }

    /**
     * 移除Buff（延迟处理，避免迭代冲突）
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
     * 清空所有Buff —— 不再销毁容器，仅清空并回到 base 值
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
        // 不销毁容器：仅清空所有容器的 buffs 并刷新为 base
        for (var propName:String in this._propertyContainers) {
            var c:PropertyContainer = this._propertyContainers[propName];
            if (c) {
                c.clearBuffs(false);
                c.forceRecalculate();
            }
        }
    }

    /**
     * 更新（帧循环）
     */
    public function update(deltaFrames:Number):Void {
        this._updateCounter++;
        
        // 1. 处理待移除的Buff
        this._processPendingRemovals();
        
        // 2. 更新所有 MetaBuff 并处理状态变化
        this._updateMetaBuffsWithInjection(deltaFrames);
        
        // 3. 移除失效的独立 PodBuff
        this._removeInactivePodBuffs();
        
        // 4. 重新分配（不销毁容器）
        if (this._isDirty) {
            // 增量优先：如果有具体脏属性，仅确保这些属性存在
            if (this._hasAnyDirty()) {
                for (var prop:String in this._dirtyProps) {
                    ensurePropertyContainerExists(prop);
                }
                this._dirtyProps = {};
            } else {
                // 兜底：为当前活跃 Pod 的属性确保容器
                var affected:Object = {};
                for (var i:Number = 0; i < this._buffs.length; i++) {
                    var b:IBuff = this._buffs[i];
                    if (b && b.isPod() && b.isActive()) {
                        var pb:PodBuff = PodBuff(b);
                        affected[pb.getTargetProperty()] = true;
                    }
                }
                for (var p:String in affected) ensurePropertyContainerExists(p);
            }
            this._redistributePodBuffs();
            this._isDirty = false;
        }
    }

    /**
     * 主动解除对某个属性的管理
     * @param finalize true: 将当前可见值固化为普通数据属性；false: 直接销毁并删除属性
     */
    public function unmanageProperty(propertyName:String, finalize:Boolean):Void {
        var c:PropertyContainer = this._propertyContainers[propertyName];
        if (!c) return;
        if (finalize) {
            if (typeof c["finalizeToPlainProperty"] == "function") {
                c["finalizeToPlainProperty"]();
            } else if (c["_accessor"] && typeof c["_accessor"].detach == "function") {
                c["_accessor"].detach();
            } else {
                c.destroy();
            }
        } else {
            c.destroy();
        }
        delete this._propertyContainers[propertyName];
        delete this._dirtyProps[propertyName];
    }

    /**
     * 管理器销毁：默认 finalize 全部属性，保留最终可见值为普通属性
     */
    public function destroy():Void {
        // 清空所有 Buff，但不销毁属性容器
        this.clearAllBuffs();
        // 将现存容器 finalize 成普通数据属性，并解除管理
        this._finalizeAllProperties();
        this._propertyContainers = {};
        this._dirtyProps = {};
        
        // 释放引用
        this._target = null;
        this._onBuffAdded = null;
        this._onBuffRemoved = null;
        this._onPropertyChanged = null;
    }

    // =========================
    // 内部实现
    // =========================
    
    private function _markDirty():Void {
        this._isDirty = true;
    }

    private function _markPropDirty(propertyName:String):Void {
        this._dirtyProps[propertyName] = true;
        this._isDirty = true;
    }

    private function _hasAnyDirty():Boolean {
        for (var k:String in this._dirtyProps) return true;
        return false;
    }

    /** 统一 finalize 所有容器（把可见值固化为普通属性） */
    private function _finalizeAllProperties():Void {
        for (var propName:String in this._propertyContainers) {
            var c:PropertyContainer = this._propertyContainers[propName];
            if (c) {
                if (typeof c["finalizeToPlainProperty"] == "function") {
                    c["finalizeToPlainProperty"]();
                } else if (c["_accessor"] && typeof c["_accessor"].detach == "function") {
                    c["_accessor"].detach();
                } else {
                    c.destroy();
                }
            }
        }
    }

    /**
     * 处理待移除列表
     */
    private function _processPendingRemovals():Void {
        for (var i:Number = 0; i < this._pendingRemovals.length; i++) {
            var buffId:String = this._pendingRemovals[i];
            var buff:IBuff = this._idMap[buffId];
            
            if (buff) {
                if (buff.isPod()) {
                    // 检查是否是注入的 PodBuff
                    var isInjected:Boolean = Boolean(this._injectedPodBuffs[buffId]);
                    if (isInjected) {
                        // 从对应 Meta 的注入列表中移除
                        var metaId:String = this._injectedPodBuffs[buffId];
                        var injectedList:Array = this._metaBuffInjections[metaId];
                        if (injectedList) {
                            for (var j:Number = injectedList.length - 1; j >= 0; j--) {
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
     * 更新所有 MetaBuff 并根据状态变化注入/弹出 Pod
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
     * 注入 MetaBuff 生成的 PodBuff
     */
    private function _injectMetaBuffPods(metaBuff:MetaBuff):Void {
        var metaId:String = metaBuff.getId();
        
        // 创建并注入 PodBuff
        var podBuffs:Array = metaBuff.createPodBuffsForInjection();
        var injectedIds:Array = [];
        
        for (var i:Number = 0; i < podBuffs.length; i++) {
            var podBuff:PodBuff = podBuffs[i];
            var podId:String = podBuff.getId();
            // 确保目标属性容器存在
            var prop:String = podBuff.getTargetProperty();
            ensurePropertyContainerExists(prop);
            _markPropDirty(prop);
            
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
     * 弹出（移除）某个 MetaBuff 注入的所有 PodBuff
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
            this._onBuffRemoved(podId, podBuff);
        }
    }

    /**
     * 移除 MetaBuff（会顺带弹出其注入的 PodBuff）
     */
    private function _removeMetaBuff(metaBuff:MetaBuff):Void {
        var metaId:String = metaBuff.getId();
        
        // 先弹出它注入的所有Pod
        this._ejectMetaBuffPods(metaBuff);
        
        // 从数组中移除自己
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] === metaBuff) {
                this._buffs.splice(i, 1);
                break;
            }
        }
        
        // 清理映射
        delete this._idMap[metaId];
        
        // 销毁 Meta
        metaBuff.destroy();
        
        // 回调
        if (this._onBuffRemoved) {
            this._onBuffRemoved(metaId, metaBuff);
        }
        
        this._markDirty();
    }

    /**
     * 移除失效的独立 PodBuff（不处理注入的）
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
     * 重建容器（升级后：不再销毁容器，仅确保需要的容器存在，然后重新分配）
     */
    private function _rebuildPropertyContainers():Void {
        // 收集所有活跃的 Pod 对应属性
        var affectedProperties:Object = {};
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isPod() && buff.isActive()) {
                var pb:PodBuff = PodBuff(buff);
                affectedProperties[pb.getTargetProperty()] = true;
            }
        }
        // 确保需要的容器存在；不要销毁任何容器
        for (var prop:String in affectedProperties) {
            ensurePropertyContainerExists(prop);
        }
        // 重新分配 PodBuff（清空再重加）
        this._redistributePodBuffs();
    }

    /**
     * 重新分配 PodBuff 到 PropertyContainer（不会销毁/创建容器）
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
                var pc:PropertyContainer = ensurePropertyContainerExists(targetProp);
                pc.addBuff(podBuff);
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
     * 创建 PropertyContainer（保持单入口）
     */
    private function _createPropertyContainer(propertyName:String):Void {
        // 使用 ensurePropertyContainerExists 替代直接创建（保持单入口）
        ensurePropertyContainerExists(propertyName);
    }

    /**
     * 显式销毁某属性的容器（仅在真正需要彻底清理时调用）
     */
    private function _destroyPropertyContainer(propertyName:String):Void {
        var container:PropertyContainer = this._propertyContainers[propertyName];
        if (container) {
            container.destroy();
            delete this._propertyContainers[propertyName];
        }
    }

    /**
     * （旧）清理所有容器 —— 现在默认改为 finalize+解除管理
     */
    private function _cleanupAllPropertyContainers():Void {
        for (var propName:String in this._propertyContainers) {
            var c:PropertyContainer = this._propertyContainers[propName];
            if (!c) continue;
            if (typeof c["finalizeToPlainProperty"] == "function") {
                c["finalizeToPlainProperty"]();
            } else if (c["_accessor"] && typeof c["_accessor"].detach == "function") {
                c["_accessor"].detach();
            } else {
                c.destroy();
            }
            delete this._propertyContainers[propName];
        }
    }

    // =========================
    // 工具 & 调试
    // =========================
    
    /**
     * 获取当前激活Buff数量（Meta + 独立Pod；注入 Pod 计入 Pod）
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
    
    // =========================
    // 辅助：确保容器存在（唯一入口）
    // =========================
    private function ensurePropertyContainerExists(propertyName:String):PropertyContainer {
        var c:PropertyContainer = this._propertyContainers[propertyName];
        if (c) return c;
        
        // 安全地取得 base 值：区分 0 与 undefined/NaN
        var raw = this._target[propertyName];
        var baseValue:Number;
        if (typeof raw == "undefined") {
            baseValue = 0;
        } else {
            baseValue = Number(raw);
            if (isNaN(baseValue)) baseValue = 0;
        }
        
        c = new PropertyContainer(this._target, propertyName, baseValue, this._onPropertyChanged);
        this._propertyContainers[propertyName] = c;
        return c;
    }
}
