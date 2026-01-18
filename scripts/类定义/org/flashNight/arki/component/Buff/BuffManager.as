// BuffManager.as - 支持 MetaBuff 注入机制（升级版：Sticky PropertyContainer 设计）
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.component.*;

class org.flashNight.arki.component.Buff.BuffManager {

    // 调试开关 (设为 false 可关闭所有调试输出)
    private static var DEBUG:Boolean = false;

    // 核心数据结构
    private var _target:Object;                    // 宿主对象（Unit）
    private var _buffs:Array;                      // 所有Buff列表（包含 MetaBuff 和独立 PodBuff）
    private var _propertyContainers:Object;        // 属性容器映射 {propName: PropertyContainer}
    private var _pendingRemovals:Array;            // 待移除的Buff ID列表

    // [Phase B] ID命名空间完全分离（废弃_idMap）
    private var _byExternalId:Object;              // { externalId -> IBuff } 用户注册ID（独立Pod/MetaBuff）
    private var _byInternalId:Object;              // { internalId -> IBuff } 系统自增ID（注入Pod专用）

    // MetaBuff 注入管理
    private var _metaBuffInjections:Object;        // { metaBuffId -> [injectedPodBuffIds] }
    private var _injectedPodBuffs:Object;          // { podBuffId -> parentMetaBuffId }

    // 性能优化
    private var _updateCounter:Number = 0;
    private var _isDirty:Boolean = false;
    private var _dirtyProps:Object = {};           // 增量脏集 {propName:true}

    // [Phase A] 重入保护
    private var _inUpdate:Boolean = false;         // 是否正在update中
    private var _pendingAdds:Array;                // 延迟添加队列 [{buff:IBuff, id:String}]

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

        // [Phase B] 初始化分离的ID映射（废弃_idMap）
        this._byExternalId = {};
        this._byInternalId = {};

        // 初始化注入管理
        this._metaBuffInjections = {};
        this._injectedPodBuffs = {};

        // [Phase A] 初始化重入保护
        this._inUpdate = false;
        this._pendingAdds = [];

        // 设置回调
        if (callbacks) {
            this._onBuffAdded = callbacks.onBuffAdded;
            this._onBuffRemoved = callbacks.onBuffRemoved;
            this._onPropertyChanged = callbacks.onPropertyChanged;
        }
    }
    
    /**
     * 新增Buff（支持 Meta / Pod）
     *
     * [Phase A 修复]:
     * - P0-4: 取消pending removal，防止同帧remove+add删错新buff
     * - P0-5: 重入保护，update期间的add延迟到帧尾处理
     * - P0-6: 检查MetaBuff是否已销毁，拒绝复用
     */
    public function addBuff(buff:IBuff, buffId:String):String {
        if (!buff) return null;

        // [Phase A / P0-6] 检查MetaBuff是否已销毁
        if (!buff.isPod() && typeof buff["isDestroyed"] == "function") {
            if (buff["isDestroyed"]()) {
                trace("[BuffManager] 警告：尝试添加已销毁的MetaBuff，已拒绝");
                return null;
            }
        }

        // [Phase D] 外部ID契约校验：用户显式传入的buffId禁止纯数字
        // 只对非null的buffId校验，null时使用内部自增ID（允许纯数字）
        if (buffId != null && buffId.length > 0) {
            var isPureNumeric:Boolean = true;
            for (var c:Number = 0; c < buffId.length; c++) {
                var charCode:Number = buffId.charCodeAt(c);
                if (charCode < 48 || charCode > 57) { // 不是 '0'-'9'
                    isPureNumeric = false;
                    break;
                }
            }
            if (isPureNumeric) {
                trace("[BuffManager] 错误：外部ID禁止使用纯数字（与内部ID命名空间冲突风险），已拒绝: " + buffId);
                return null;
            }
        }

        var finalId:String = buffId || buff.getId();

        // [Phase A / P0-5] 重入保护：update期间延迟添加
        if (this._inUpdate) {
            this._pendingAdds.push({buff: buff, id: finalId});
            return finalId;
        }

        // 实际添加逻辑
        return this._addBuffNow(buff, finalId);
    }

    /**
     * [Phase A] 立即添加Buff的内部实现
     *
     * [Phase B] 使用_byExternalId作为唯一来源，废弃_idMap
     * [Phase D] 外部ID契约校验已移至addBuff入口处
     */
    private function _addBuffNow(buff:IBuff, finalId:String):String {
        // [Phase A / P0-4] 取消同ID的pending removal
        this._cancelPendingRemoval(finalId);

        // [Phase B] 如果已存在同ID的Buff，先同步移除旧实例
        if (this._byExternalId[finalId]) {
            this._removeByIdImmediate(finalId);
        }

        this._buffs.push(buff);

        // [Phase B] 只写入_byExternalId，用户注册的Buff
        this._byExternalId[finalId] = buff;

        // 在buff上记录注册ID（用于快速反查）
        buff["__regId"] = finalId;

        // 预先确保容器存在（PodBuff）
        if (buff.isPod()) {
            var pod:PodBuff = PodBuff(buff);
            var prop:String = pod.getTargetProperty();
            // [Phase A / P0-8] 校验属性名
            if (prop != null && prop.length > 0 && prop != "undefined") {
                ensurePropertyContainerExists(prop);
                _markPropDirty(prop);
            } else {
                trace("[BuffManager] 警告：PodBuff属性名无效: " + prop);
            }
        } else {
            // 如果是 MetaBuff，立即处理初始注入（使用鸭子类型检测）
            if (typeof buff["createPodBuffsForInjection"] == "function") {
                this._injectMetaBuffPods(buff);
            }
        }

        this._markDirty();

        // 触发回调
        if (this._onBuffAdded) {
            this._onBuffAdded(finalId, buff);
        }
        return finalId;
    }

    /**
     * [Phase A / P0-4] 取消指定ID的pending removal
     */
    private function _cancelPendingRemoval(buffId:String):Void {
        for (var i:Number = this._pendingRemovals.length - 1; i >= 0; i--) {
            if (this._pendingRemovals[i] == buffId) {
                this._pendingRemovals.splice(i, 1);
            }
        }
    }


    /**
     * [Phase B] 统一查询：先查外部ID，再查内部ID
     */
    private function _lookupById(buffId:String):IBuff {
        var buff:IBuff = this._byExternalId[buffId];
        if (buff) return buff;
        return this._byInternalId[buffId];
    }

    /**
     * [Phase B] 检查ID是否存在（任一映射）
     */
    private function _hasId(buffId:String):Boolean {
        return this._byExternalId[buffId] != null || this._byInternalId[buffId] != null;
    }

    /**
     * 同步移除指定 ID（用于同 ID 替换，避免 pending 删除误伤新实例）
     *
     * [Phase B] 使用_lookupById替代_idMap
     */
    private function _removeByIdImmediate(buffId:String):Void {
        var old:IBuff = this._lookupById(buffId);
        if (!old) return;
        if (old.isPod()) {
            this._removePodBuff(buffId);
        } else {
            this._removeMetaBuff(old);
        }
    }

    /**
     * 移除Buff（延迟处理，避免迭代冲突）
     *
     * [Phase B] 使用_hasId替代_idMap检查
     */
    public function removeBuff(buffId:String):Boolean {
        if (this._hasId(buffId)) {
            var exists:Boolean = false;
            for (var k:Number = 0; k < this._pendingRemovals.length; k++) {
                if (this._pendingRemovals[k] == buffId) { exists = true; break; }
            }
            if (!exists) this._pendingRemovals.push(buffId);
            this._markDirty();
            return true;
        }
        return false;
    }

    /**
     * 清空所有Buff
     *
     * [Phase B] 完全使用分离的ID映射，废弃_idMap
     */
    public function clearAllBuffs():Void {
        // 先移除所有 MetaBuff（会级联删除注入的 PodBuff）
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            var buff:IBuff = this._buffs[i];
            if (buff && !buff.isPod()) {
                this._removeMetaBuff(buff);
            }
        }

        // 再移除剩余的独立 PodBuff（走统一逻辑以触发回调）
        // [Phase B] 使用__regId获取注册ID，而非buff.getId()
        for (var j:Number = this._buffs.length - 1; j >= 0; j--) {
            var podBuff:IBuff = this._buffs[j];
            if (podBuff && podBuff.isPod()) {
                var pid:String = podBuff["__regId"] || podBuff.getId();
                if (!this._injectedPodBuffs[podBuff.getId()]) {
                    this._removePodBuff(pid);
                }
            }
        }

        this._buffs.length = 0;

        // [Phase B] 清理分离的ID映射（废弃_idMap）
        this._byExternalId = {};
        this._byInternalId = {};

        this._metaBuffInjections = {};
        this._injectedPodBuffs = {};
        this._dirtyProps = {};

        // [Phase A] 清理延迟添加队列
        this._pendingAdds.length = 0;

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
     *
     * [Phase A] 重入保护：
     * - 设置_inUpdate标志防止递归调用
     * - update期间的addBuff延迟到帧尾处理
     */
    public function update(deltaFrames:Number):Void {
        // [Phase A / P1-3] 防止重入
        if (this._inUpdate) {
            if (DEBUG) trace("[BuffManager] 警告：检测到update重入，已忽略");
            return;
        }

        this._inUpdate = true;
        this._updateCounter++;

        try {
            // 1. 处理待移除的Buff
            this._processPendingRemovals();

            // 2. 更新所有 MetaBuff 并处理状态变化
            this._updateMetaBuffsWithInjection(deltaFrames);

            // 3. 移除失效的独立 PodBuff
            this._removeInactivePodBuffs();

            // 4. 重新分配（不销毁容器）
            if (this._isDirty) {
                if (this._hasAnyDirty()) {
                    for (var prop:String in this._dirtyProps) {
                        // [Phase A / P0-8] 校验属性名
                        if (prop != null && prop.length > 0 && prop != "undefined") {
                            ensurePropertyContainerExists(prop);
                        }
                    }
                    this._redistributeDirtyProps(this._dirtyProps);
                    this._dirtyProps = {};
                } else {
                    // 兜底：为当前活跃 Pod 的属性确保容器
                    var affected:Object = {};
                    for (var i:Number = 0; i < this._buffs.length; i++) {
                        var b:IBuff = this._buffs[i];
                        if (b && b.isPod() && b.isActive()) {
                            var pb:PodBuff = PodBuff(b);
                            var targetProp:String = pb.getTargetProperty();
                            if (targetProp != null && targetProp.length > 0 && targetProp != "undefined") {
                                affected[targetProp] = true;
                            }
                        }
                    }
                    for (var p:String in affected) ensurePropertyContainerExists(p);
                    this._redistributePodBuffs();
                }
                this._isDirty = false;
            }
        } finally {
            // [Phase A] 确保标志复位
            this._inUpdate = false;
        }

        // [Phase A] 处理延迟添加的Buff
        this._flushPendingAdds();
    }

    /**
     * [Phase A] 处理延迟添加队列
     */
    private function _flushPendingAdds():Void {
        while (this._pendingAdds.length > 0) {
            var entry:Object = this._pendingAdds.shift();
            this._addBuffNow(entry.buff, entry.id);
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
        
        // 同步清理该属性上的独立 Pod（注入 Pod 交由 Meta 生命周期维护）
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            var b:IBuff = this._buffs[i];
            if (b && b.isPod()) {
                var pb:PodBuff = PodBuff(b);
                if (pb.getTargetProperty() == propertyName) {
                    var bid:String = pb.getId();
                    if (!this._injectedPodBuffs[bid]) {
                        this._removePodBuff(bid);
                    }
                }
            }
        }
        this._markDirty();
    }

    /**
     * 销毁（用于宿主释放）
     */
    public function destroy():Void {
        // 先清所有Buff
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
     * 处理延迟移除（包括注入 Pod 的关系维护）
     *
     * [Phase B] 使用_lookupById替代_idMap
     */
    private function _processPendingRemovals():Void {
        for (var i:Number = 0; i < this._pendingRemovals.length; i++) {
            var buffId:String = this._pendingRemovals[i];
            var buff:IBuff = this._lookupById(buffId);

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
                    this._removeMetaBuff(buff);
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
                // 鸭子类型检测：必须有update方法
                if (typeof buff["update"] == "function") {
                    // [Phase A / P0-7] 异常隔离：单个 MetaBuff 异常不影响其他 Buff
                    var stateInfo:Object = null;
                    try {
                        stateInfo = buff["update"](deltaFrames);
                    } catch (e) {
                        trace("[BuffManager] MetaBuff.update 异常: id=" + buff.getId() + ", error=" + e);
                        // 异常时标记为死亡，下一帧移除
                        stateInfo = {alive: false, stateChanged: true, needsEject: true};
                    }

                    // 处理状态变化
                    if (stateInfo && stateInfo.stateChanged) {
                        if (DEBUG) {
                            trace("[BuffManager] Meta stateChanged: id=" + buff.getId() +
                                  ", needsInject=" + stateInfo.needsInject +
                                  ", needsEject=" + stateInfo.needsEject +
                                  ", currentState=" + (typeof buff["getCurrentState"] == "function" ? buff["getCurrentState"]() : "N/A"));
                        }
                        if (stateInfo.needsInject) {
                            this._injectMetaBuffPods(buff);
                        } else if (stateInfo.needsEject) {
                            this._ejectMetaBuffPods(buff);
                        }
                    }

                    // 如果 MetaBuff 死亡，移除它
                    if (typeof buff["isActive"] == "function" && !buff["isActive"]()) {
                        this._removeMetaBuff(buff);
                    }
                }
            }
        }
    }

    /**
     * 注入 MetaBuff 生成的 PodBuff（支持鸭子类型）
     */
    /**
     * 注入 MetaBuff 生成的 PodBuff
     *
     * [Phase 0 / P1-1] 添加幂等检查，防止重复注入
     * [Phase A / P0-8] 添加属性名校验
     */
    private function _injectMetaBuffPods(metaBuff:Object):Void {
        if (!metaBuff || typeof metaBuff["getId"] != "function" || typeof metaBuff["createPodBuffsForInjection"] != "function") {
            return;
        }

        var metaId:String = metaBuff["getId"]();

        // [Phase 0 / P1-1] 幂等检查：如果已注入，先弹出旧的
        if (this._metaBuffInjections[metaId] != null) {
            if (DEBUG) trace("[BuffManager] 检测到重复注入，先弹出旧Pod: " + metaId);
            this._ejectMetaBuffPods(metaBuff);
        }

        // 创建并注入 PodBuff
        var podBuffs:Array = metaBuff["createPodBuffsForInjection"]();
        var injectedIds:Array = [];

        for (var i:Number = 0; i < podBuffs.length; i++) {
            var podBuff:PodBuff = podBuffs[i];
            var podId:String = podBuff.getId();

            // [Phase A / P0-8] 校验属性名
            var prop:String = podBuff.getTargetProperty();
            if (prop == null || prop.length == 0 || prop == "undefined") {
                trace("[BuffManager] 警告：跳过无效属性名的PodBuff: " + prop);
                continue;
            }

            // 确保目标属性容器存在
            var container:PropertyContainer = ensurePropertyContainerExists(prop);
            if (container == null) {
                continue; // 容器创建失败，跳过
            }
            _markPropDirty(prop);

            // [Phase B] 添加到系统，只写入_byInternalId（废弃_idMap）
            this._buffs.push(podBuff);
            this._byInternalId[podId] = podBuff;

            // 记录注入关系
            injectedIds.push(podId);
            this._injectedPodBuffs[podId] = metaId;

            // （可选）让 Meta 维护自身注入列表
            if (typeof metaBuff["recordInjectedBuffId"] == "function") {
                metaBuff["recordInjectedBuffId"](podId);
            }
            // 触发新增回调
            if (this._onBuffAdded) {
                this._onBuffAdded(podId, podBuff);
            }
        }

        // 记录该 MetaBuff 注入的所有 PodBuff
        this._metaBuffInjections[metaId] = injectedIds;

        if (DEBUG) {
            trace("[BuffManager] Injected Meta=" + metaId + " pods=" + injectedIds.join(",") + " count=" + injectedIds.length);
        }

        this._markDirty();
    }

    /**
     * 弹出（移除）某个 MetaBuff 注入的所有 PodBuff（支持鸭子类型）
     */
    private function _ejectMetaBuffPods(metaBuff:Object):Void {
        if (!metaBuff || typeof metaBuff["getId"] != "function") return;

        var metaId:String = metaBuff["getId"]();
        var injectedIds:Array = this._metaBuffInjections[metaId];

        if (DEBUG) {
            trace("[BuffManager] Ejecting Meta=" + metaId + " injectedIds=" + (injectedIds ? injectedIds.join(",") : "null") + " count=" + (injectedIds ? injectedIds.length : 0));
        }

        if (injectedIds) {
            // 从后往前遍历，避免 splice 导致跳过元素
            // (_removePodBuff 内部会从 injectedIds 中 splice 删除对应元素)
            for (var i:Number = injectedIds.length - 1; i >= 0; i--) {
                var podId:String = injectedIds[i];
                if (DEBUG) {
                    trace("[BuffManager]   Removing injected Pod: " + podId);
                }
                this._removePodBuff(podId);
            }

            // 清理注入记录
            delete this._metaBuffInjections[metaId];
            if (typeof metaBuff["clearInjectedBuffIds"] == "function") {
                metaBuff["clearInjectedBuffIds"]();
            }
        }

        this._markDirty();
    }

    /**
     * 移除单个 PodBuff
     *
     * [Phase B] 使用_lookupById替代_idMap，完全分离ID命名空间
     */
    private function _removePodBuff(podId:String):Void {
        var podBuff:IBuff = this._lookupById(podId);
        if (!podBuff) return;

        // 获取目标属性并标记为脏（确保同帧重算）
        var podBuffCast:PodBuff = PodBuff(podBuff);
        if (podBuffCast) {
            var targetProp:String = podBuffCast.getTargetProperty();
            if (targetProp) {
                _markPropDirty(targetProp);
            }
        }

        // 从数组中移除
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] === podBuff) {
                this._buffs.splice(i, 1);
                break;
            }
        }

        // 若为注入 Pod，同步 Meta 内部记录
        var parentMetaId:String = this._injectedPodBuffs[podId];
        if (parentMetaId) {
            // [Phase 0 / P1-2 修复] 使用_byExternalId查找Meta（外部ID注册）
            var regId:String = null;
            // 先尝试从Meta的__regId获取
            for (var key:String in this._byExternalId) {
                var m:Object = this._byExternalId[key];
                if (m && typeof m["getId"] == "function" && m["getId"]() == parentMetaId) {
                    regId = key;
                    break;
                }
            }
            if (regId != null) {
                var metaRef:IBuff = this._byExternalId[regId];
                if (metaRef && !metaRef.isPod()) {
                    if (typeof metaRef["removeInjectedBuffId"] == "function") {
                        metaRef["removeInjectedBuffId"](podId);
                    }
                }
            }
        }

        // [Phase B] 清理分离的ID映射（废弃_idMap）
        delete this._byInternalId[podId];
        delete this._byExternalId[podId]; // 独立Pod可能用外部ID注册

        // 如果是注入的Pod，还需从父MetaBuff的注入列表中移除
        if (parentMetaId) {
            var injectedIds:Array = this._metaBuffInjections[parentMetaId];
            if (injectedIds) {
                for (var k:Number = 0; k < injectedIds.length; k++) {
                    if (injectedIds[k] == podId) {
                        injectedIds.splice(k, 1);
                        break;
                    }
                }
                // 如果注入列表空了，清理整个记录
                if (injectedIds.length == 0) {
                    delete this._metaBuffInjections[parentMetaId];
                }
            }
        }

        delete this._injectedPodBuffs[podId];

        // 销毁
        podBuff.destroy();

        // 触发回调
        if (this._onBuffRemoved) {
            this._onBuffRemoved(podId, podBuff);
        }
    }

    /**
     * 移除 MetaBuff
     *
     * [Phase B] 使用__regId获取外部ID，遍历_byExternalId兜底，废弃_idMap
     */
    private function _removeMetaBuff(metaBuff:Object):Void {
        if (!metaBuff || typeof metaBuff["getId"] != "function") return;

        // 优先使用__regId获取外部ID
        var externalId:String = metaBuff["__regId"];

        // [Phase B] 兜底：如果没有__regId，遍历_byExternalId查找
        if (externalId == null) {
            for (var key:String in this._byExternalId) {
                if (this._byExternalId[key] === metaBuff) {
                    externalId = key;
                    break;
                }
            }
        }

        // 先弹出它注入的所有Pod
        this._ejectMetaBuffPods(metaBuff);

        // 从数组中移除自己
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] === metaBuff) {
                this._buffs.splice(i, 1);
                break;
            }
        }

        // [Phase B] 清理分离的ID映射（废弃_idMap）
        if (externalId != null) {
            delete this._byExternalId[externalId];
        }

        // 销毁
        if (typeof metaBuff["destroy"] == "function") {
            metaBuff["destroy"]();
        }

        // 触发回调（使用外部 ID，如果没有则使用内部 ID）
        if (this._onBuffRemoved) {
            var callbackId:String = externalId != null ? externalId : metaBuff["getId"]();
            this._onBuffRemoved(callbackId, metaBuff);
        }

        this._markDirty();
    }

    /**
     * 移除失效的独立 PodBuff（不处理注入的）
     *
     * [Phase B] 使用__regId获取注册ID（独立Pod），内部ID用于检查注入状态
     */
    private function _removeInactivePodBuffs():Void {
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isPod() && !buff.isActive()) {
                // [Phase B] 内部ID用于检查是否为注入的Pod
                var internalId:String = buff.getId();
                if (!this._injectedPodBuffs[internalId]) {
                    // 非注入的独立Pod，使用__regId获取注册ID来移除
                    var regId:String = buff["__regId"] || internalId;
                    this._removePodBuff(regId);
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
     * 仅重分配给定脏属性集合下的容器：先清空这些容器，再把活跃 Pod 归位到对应容器，并仅对这些容器重算
     */
    private function _redistributeDirtyProps(dirty:Object):Void {
        if (DEBUG) {
            var dirtyPropsStr:String = "";
            for (var dpk:String in dirty) dirtyPropsStr += dpk + ",";
            trace("[BuffManager] _redistributeDirtyProps for: " + dirtyPropsStr);
        }

        // 1) 清该集合内容器
        for (var prop:String in dirty) {
            var c:PropertyContainer = this._propertyContainers[prop];
            if (c) c.clearBuffs(false);
        }
        // 2) 将活跃 Pod 按属性归位（仅目标在 dirty 内）
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var buff:IBuff = this._buffs[i];
            if (buff && buff.isPod() && buff.isActive()) {
                var pb:PodBuff = PodBuff(buff);
                var tp:String = pb.getTargetProperty();
                if (dirty[tp]) {
                    var pc:PropertyContainer = ensurePropertyContainerExists(tp);
                    pc.addBuff(pb);
                }
            }
        }
        // 3) 只让脏属性容器触发重算
        for (var prop2:String in dirty) {
            var c2:PropertyContainer = this._propertyContainers[prop2];
            if (c2 && typeof c2["forceRecalculate"] == "function") {
                c2["forceRecalculate"]();
            } else if (c2) {
                // 回退：调用一次 clear+重加也会触发重算，已在上面完成
            }
        }
    }
    
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
                var pod:PodBuff = PodBuff(buff);
                var prop:String = pod.getTargetProperty();
                var c:PropertyContainer = ensurePropertyContainerExists(prop);
                c.addBuff(pod);
            }
        }
        
        // 触发容器重算
        for (var pn:String in this._propertyContainers) {
            var c2:PropertyContainer = this._propertyContainers[pn];
            if (c2) {
                if (typeof c2["forceRecalculate"] == "function") {
                    c2["forceRecalculate"]();
                } else {
                    // 容器内部添加 Pod 时应已触发重算，这里仅兜底
                }
            }
        }
    }

    // ====== 旧式容器生命周期封装（保留以兼容老调用） ======
    private function _createPropertyContainer(propName:String, baseValue:Number):PropertyContainer {
        var c:PropertyContainer = this._propertyContainers[propName];
        if (c) return c;
        c = new PropertyContainer(this._target, propName, baseValue, this._onPropertyChanged);
        this._propertyContainers[propName] = c;
        return c;
    }

    private function _destroyPropertyContainer(propName:String, finalize:Boolean):Void {
        var c:PropertyContainer = this._propertyContainers[propName];
        if (!c) return;
        if (finalize) {
            if (typeof c["finalizeToPlainProperty"] == "function") {
                c["finalizeToPlainProperty"]();
            } else {
                c.destroy();
            }
        } else {
            c.destroy();
        }
        delete this._propertyContainers[propName];
    }

    private function _cleanupAllPropertyContainers(finalize:Boolean):Void {
        for (var propName:String in this._propertyContainers) {
            _destroyPropertyContainer(propName, finalize);
        }
        this._propertyContainers = {};
    }

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
     * 获取属性容器（供外部访问基础值等信息）
     * @param propertyName 属性名
     * @return PropertyContainer 或 null
     */
    public function getPropertyContainer(propertyName:String):PropertyContainer {
        return this._propertyContainers[propertyName];
    }

    /**
     * 获取调试信息
     */
    public function getDebugInfo():Object {
        var info:Object = {
            total:this._buffs.length,
            metaBuffs:0,
            podBuffs:0,
            injectedPods:0,
            independentPods:0,
            properties:0
        };
        for (var i:Number = 0; i < this._buffs.length; i++) {
            var b:IBuff = this._buffs[i];
            if (b) {
                if (b.isPod()) {
                    info.podBuffs++;
                    if (this._injectedPodBuffs[b.getId()]) info.injectedPods++;
                    else info.independentPods++;
                } else {
                    info.metaBuffs++;
                }
            }
        }
        for (var pn:String in this._propertyContainers) info.properties++;
        return info;
    }
    
    public function toString():String {
        var info:Object = getDebugInfo();
        return "[BuffManager total: " + info.total + 
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
    /**
     * [Phase A / P0-8] 确保属性容器存在
     *
     * 添加propertyName校验，拒绝null/undefined/空字符串
     */
    private function ensurePropertyContainerExists(propertyName:String):PropertyContainer {
        // [Phase A / P0-8] 校验属性名
        if (propertyName == null || propertyName == undefined ||
            propertyName.length == 0 || propertyName == "undefined" || propertyName == "null") {
            trace("[BuffManager] 警告：尝试创建无效属性名的容器: " + propertyName);
            return null;
        }

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

    // =========================
    // 批量移除辅助方法
    // =========================

    /**
     * 根据ID前缀批量移除Buff
     * 用于净化系统清除debuff（约定debuff使用统一前缀如"debuff_"）
     *
     * [Phase B] 只遍历_byExternalId，用户不应使用内部ID前缀
     * [Phase A / P1-3 修复] 移除内部update(0)调用，防止重入
     */
    public function removeBuffsByIdPrefix(prefix:String):Number {
        if (!prefix || prefix.length == 0) return 0;

        var removed:Number = 0;
        var toRemove:Array = [];

        // [Phase B] 只从外部ID映射收集匹配前缀的buffId
        for (var id:String in this._byExternalId) {
            if (id.indexOf(prefix) == 0) {
                toRemove.push(id);
            }
        }

        // 批量移除（延迟处理，通过removeBuff加入pending队列）
        for (var i:Number = 0; i < toRemove.length; i++) {
            if (this.removeBuff(toRemove[i])) {
                removed++;
            }
        }

        // [Phase A / P1-3] 不再内部调用update(0)，避免重入风险
        this._markDirty();

        return removed;
    }

    /**
     * 根据ID前缀批量获取Buff
     *
     * [Phase B] 只遍历_byExternalId，用户不应使用内部ID前缀
     *
     * @param prefix 要匹配的buffId前缀
     * @return 匹配的IBuff数组
     */
    public function getBuffsByIdPrefix(prefix:String):Array {
        var result:Array = [];
        if (!prefix || prefix.length == 0) return result;

        // [Phase B] 只从外部ID映射查找
        for (var id:String in this._byExternalId) {
            if (id.indexOf(prefix) == 0) {
                result.push(this._byExternalId[id]);
            }
        }

        return result;
    }

    /**
     * 检查是否存在指定前缀的Buff
     *
     * [Phase B] 只遍历_byExternalId，用户不应使用内部ID前缀
     *
     * @param prefix 要匹配的buffId前缀
     * @return 是否存在匹配的buff
     */
    public function hasBuffWithIdPrefix(prefix:String):Boolean {
        if (!prefix || prefix.length == 0) return false;

        // [Phase B] 只从外部ID映射查找
        for (var id:String in this._byExternalId) {
            if (id.indexOf(prefix) == 0) {
                return true;
            }
        }

        return false;
    }

    /**
     * 根据ID获取Buff
     *
     * [Phase B] 使用_lookupById统一查询（先外部，后内部）
     *
     * @param buffId buff的ID
     * @return IBuff实例或null
     */
    public function getBuffById(buffId:String):IBuff {
        return this._lookupById(buffId);
    }
}
