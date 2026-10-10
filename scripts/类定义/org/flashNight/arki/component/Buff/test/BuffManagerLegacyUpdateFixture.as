import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
/** Frozen 0c36a08a update passes, installed only on isolated real managers. */
class org.flashNight.arki.component.Buff.test.BuffManagerLegacyUpdateFixture {
    private static var DEBUG:Boolean = false;
    public static function install(manager:Object):Void {
        manager.update = function(deltaFrames:Number):Void {
            var manager:Object = this;
        // [Phase A / P1-3] 防止重入
        if (manager._inUpdate) {
            if (DEBUG) trace("[BuffManager] 警告：检测到update重入，已忽略");
            return;
        }
        if ((deltaFrames - deltaFrames) != 0) {
            if (DEBUG) trace("[BuffManager] 警告：update收到非法deltaFrames，已忽略");
            return;
        }

        manager._inUpdate = true;
        manager._updateCounter++;

        try {
            // 1. 处理待移除的Buff
            manager._processPendingRemovals();

            // 1.5 [v3.0] 同步路径绑定（检测对象替换，如换装）
            manager._syncPathBindings();

            // 2. 更新所有 MetaBuff 并处理状态变化
            manager._updateMetaBuffsWithInjection(deltaFrames);

            // 3. 移除失效的独立 PodBuff
            manager._removeInactivePodBuffs();

            // 4. 重新分配（不销毁容器）
            if (manager._isDirty) {
                if (manager._hasAnyDirty()) {
                    for (var prop:String in manager._dirtyProps) {
                        // [Phase A / P0-8] 校验属性名
                        if (prop != null && prop.length > 0 && prop != "undefined") {
                            manager.ensurePropertyContainerExists(prop);
                        }
                    }
                    manager._redistributeDirtyProps(manager._dirtyProps);
                    manager._dirtyProps = {};
                } else {
                    // 兜底：为当前活跃 Pod 的属性确保容器
                    var affected:Object = {};
                    for (var i:Number = 0; i < manager._buffs.length; i++) {
                        var b:IBuff = manager._buffs[i];
                        if (b && b.isPod() && b.isActive()) {
                            var pb:PodBuff = PodBuff(b);
                            var targetProp:String = pb.getTargetProperty();
                            if (targetProp != null && targetProp.length > 0 && targetProp != "undefined") {
                                affected[targetProp] = true;
                            }
                        }
                    }
                    for (var p:String in affected) manager.ensurePropertyContainerExists(p);
                    manager._redistributePodBuffs();
                }
                manager._isDirty = false;
            }

            // [Phase A] 处理延迟添加的Buff
            // [P1-2 修复] 移到 finally 之前，确保 flush 期间回调不会重入
            manager._flushPendingAdds();
        } finally {
            // [Phase A] [P1-2 修复] 在所有操作完成后才复位标志
            manager._inUpdate = false;
        }

        };
        manager._updateMetaBuffsWithInjection = function(deltaFrames:Number):Void {
            var manager:Object = this;
        for (var i:Number = manager._buffs.length - 1; i >= 0; i--) {
            var buff:IBuff = manager._buffs[i];
            if (buff && !buff.isPod()) {
                // 鸭子类型检测：必须有update方法
                if (typeof buff["update"] == "function") {
                    // [Phase A / P0-7] 异常隔离：单个 MetaBuff 异常不影响其他 Buff
                    // [v2.7] 使用StateInfo类型，提供编译期类型检查
                    var stateInfo:StateInfo = null;
                    try {
                        stateInfo = buff["update"](deltaFrames);
                    } catch (e) {
                        trace("[BuffManager] MetaBuff.update 异常: id=" + buff.getId() + ", error=" + e);
                        // [P0-2 修复] 异常时立即移除，避免僵尸Buff
                        manager._ejectMetaBuffPods(buff);
                        manager._removeMetaBuff(buff);
                        continue; // 跳过后续处理
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
                            manager._injectMetaBuffPods(buff);
                        } else if (stateInfo.needsEject) {
                            manager._ejectMetaBuffPods(buff);
                        }
                    }

                    // 如果 MetaBuff 死亡，移除它
                    if (typeof buff["isActive"] == "function" && !buff["isActive"]()) {
                        manager._removeMetaBuff(buff);
                    }
                }
            }
        }

        };
        manager._removeInactivePodBuffs = function():Void {
            var manager:Object = this;
        for (var i:Number = manager._buffs.length - 1; i >= 0; i--) {
            var buff:IBuff = manager._buffs[i];
            if (buff && buff.isPod() && !buff.isActive()) {
                // [Phase B] 内部ID用于检查是否为注入的Pod
                var internalId:String = buff.getId();
                if (!manager._injectedPodBuffs[internalId]) {
                    // 非注入的独立Pod，使用__regId获取注册ID来移除
                    var regId:String = buff["__regId"] || internalId;
                    // [v2.3] 直接传递索引，避免 _removePodBuff 内部再次遍历
                    manager._removePodBuffCore(regId, buff, i);
                }
            }
        }

        };
        manager._addBuffNow = function(buff:IBuff, finalId:String):String {
            var manager:Object = this;
        // [P1-2] 检查是否已在管理中（防止同一实例重复注册导致幽灵buff）
        if (buff["__inManager"] === true) {
            trace("[BuffManager] 警告：同一Buff实例已在管理中，拒绝重复注册。旧ID: " + buff["__regId"] + ", 新ID: " + finalId);
            return null;
        }

        // [Phase A / P0-4] 取消同ID的pending removal
        manager._cancelPendingRemoval(finalId);

        // [Phase B] 如果已存在同ID的Buff，先同步移除旧实例
        if (manager._byExternalId[finalId]) {
            manager._removeByIdImmediate(finalId);
        }

        manager._buffs.push(buff);

        // [Phase B] 只写入_byExternalId，用户注册的Buff
        manager._byExternalId[finalId] = buff;

        // 在buff上记录注册ID和管理状态
        buff["__regId"] = finalId;
        buff["__inManager"] = true;  // [P1-2] 标记为已在管理中

        // 预先确保容器存在（PodBuff）
        if (buff.isPod()) {
            var pod:PodBuff = PodBuff(buff);
            var prop:String = pod.getTargetProperty();
            // [Phase A / P0-8] 校验属性名
            if (prop != null && prop.length > 0 && prop != "undefined") {
                // [P0-1 修复] 如果该属性在黑名单中，移除黑名单（允许再次管理）
                if (manager._unmanagedProps[prop] === true) {
                    delete manager._unmanagedProps[prop];
                }
                manager.ensurePropertyContainerExists(prop);
                manager._markPropDirty(prop);
            } else {
                trace("[BuffManager] 警告：PodBuff属性名无效: " + prop);
            }
        } else {
            // 如果是 MetaBuff，立即处理初始注入（使用鸭子类型检测）
            if (typeof buff["createPodBuffsForInjection"] == "function") {
                // [v2.6] 注册到O(1)查找映射（在注入前，因为注入的pod需要查找parent）
                manager._metaByInternalId[buff.getId()] = buff;
                manager._injectMetaBuffPods(buff);
            }
        }

        manager._markDirty();

        // 触发回调
        if (manager._onBuffAdded) {
            manager._onBuffAdded(finalId, buff);
        }
        // 发布add事件
        manager.eventDispatcher.publish("add", finalId, buff);

        return finalId;

        };
        manager._removePodBuffCore = function(podId:String, podBuff:IBuff, arrayIndex:Number):Void {
            var manager:Object = this;
        // 获取目标属性并标记为脏（确保同帧重算）
        var podBuffCast:PodBuff = PodBuff(podBuff);
        if (podBuffCast) {
            var targetProp:String = podBuffCast.getTargetProperty();
            if (targetProp) {
                manager._markPropDirty(targetProp);
            }
        }

        // 从数组中移除（如果提供了有效索引则直接splice，否则已经移除）
        if (arrayIndex >= 0 && arrayIndex < manager._buffs.length) {
            manager._buffs.splice(arrayIndex, 1);
        }

        // [Phase B] 清理分离的ID映射（废弃_idMap）
        delete manager._byInternalId[podId];
        delete manager._byExternalId[podId]; // 独立Pod可能用外部ID注册

        // [v2.8] 若为注入 Pod，从 _metaBuffInjections 中清理（唯一数据源）
        // 移除对 MetaBuff.removeInjectedBuffId 的调用，消除双重维护
        var parentMetaId:String = manager._injectedPodBuffs[podId];
        if (parentMetaId) {
            var injectedIds:Array = manager._metaBuffInjections[parentMetaId];
            if (injectedIds) {
                for (var k:Number = 0; k < injectedIds.length; k++) {
                    if (injectedIds[k] == podId) {
                        injectedIds.splice(k, 1);
                        break;
                    }
                }
                // 如果注入列表空了，清理整个记录
                if (injectedIds.length == 0) {
                    delete manager._metaBuffInjections[parentMetaId];
                }
            }
        }

        delete manager._injectedPodBuffs[podId];

        // [P1-2] 清除管理状态标志
        podBuff["__inManager"] = false;

        // 销毁
        podBuff.destroy();

        // 触发回调
        if (manager._onBuffRemoved) {
            manager._onBuffRemoved(podId, podBuff);
        }
        // 发布remove事件
        manager.eventDispatcher.publish("remove", podId);

        };
        manager._removeMetaBuff = function(metaBuff:Object):Void {
            var manager:Object = this;
        if (!metaBuff || typeof metaBuff["getId"] != "function") return;

        // 优先使用__regId获取外部ID
        var externalId:String = metaBuff["__regId"];

        // [Phase B] 兜底：如果没有__regId，遍历_byExternalId查找
        if (externalId == null) {
            for (var key:String in manager._byExternalId) {
                if (manager._byExternalId[key] === metaBuff) {
                    externalId = key;
                    break;
                }
            }
        }

        // 先弹出它注入的所有Pod
        manager._ejectMetaBuffPods(metaBuff);

        // 从数组中移除自己
        for (var i:Number = manager._buffs.length - 1; i >= 0; i--) {
            if (manager._buffs[i] === metaBuff) {
                manager._buffs.splice(i, 1);
                break;
            }
        }

        // [Phase B] 清理分离的ID映射（废弃_idMap）
        if (externalId != null) {
            delete manager._byExternalId[externalId];
        }

        // [v2.6] 清理O(1)查找映射
        delete manager._metaByInternalId[metaBuff["getId"]()];

        // [P1-2] 清除管理状态标志
        metaBuff["__inManager"] = false;

        // 销毁
        if (typeof metaBuff["destroy"] == "function") {
            metaBuff["destroy"]();
        }

        // 触发回调（使用外部 ID，如果没有则使用内部 ID）
        var callbackId:String = externalId != null ? externalId : metaBuff["getId"]();
        if (manager._onBuffRemoved) {
            manager._onBuffRemoved(callbackId, metaBuff);
        }
        // 发布remove事件
        manager.eventDispatcher.publish("remove", callbackId);

        manager._markDirty();

        };
        manager.clearAllBuffs = function():Void {
            var manager:Object = this;
        // [v2.6] DEBUG警告：update期间调用可能导致状态不一致
        if (DEBUG && manager._inUpdate) {
            trace("[BuffManager] 警告：update期间调用clearAllBuffs可能导致状态不一致");
        }
        // 先移除所有 MetaBuff（会级联删除注入的 PodBuff）
        for (var i:Number = manager._buffs.length - 1; i >= 0; i--) {
            var buff:IBuff = manager._buffs[i];
            if (buff && !buff.isPod()) {
                manager._removeMetaBuff(buff);
            }
        }

        // 再移除剩余的独立 PodBuff（走统一逻辑以触发回调）
        // [Phase B] 使用__regId获取注册ID，而非buff.getId()
        for (var j:Number = manager._buffs.length - 1; j >= 0; j--) {
            var podBuff:IBuff = manager._buffs[j];
            if (podBuff && podBuff.isPod()) {
                var pid:String = podBuff["__regId"] || podBuff.getId();
                if (!manager._injectedPodBuffs[podBuff.getId()]) {
                    manager._removePodBuff(pid);
                }
            }
        }

        manager._buffs.length = 0;

        // [Phase B] 清理分离的ID映射（废弃_idMap）
        manager._byExternalId = {};
        manager._byInternalId = {};

        manager._metaBuffInjections = {};
        manager._injectedPodBuffs = {};
        manager._metaByInternalId = {};  // [v2.6] 清理O(1)查找映射
        manager._dirtyProps = {};

        // [Phase A] 清理延迟添加队列
        // [v2.3] 双缓冲队列都需要清空
        manager._pendingAddsA.length = 0;
        manager._pendingAddsB.length = 0;
        manager._pendingAdds = manager._pendingAddsA;

        manager._markDirty();
        // 不销毁容器：仅清空所有容器的 buffs 并刷新为 base
        for (var propName:String in manager._propertyContainers) {
            var c:PropertyContainer = manager._propertyContainers[propName];
            if (c) {
                c.clearBuffs(false);
                c.forceRecalculate();
            }
        }

        };
    }
}
