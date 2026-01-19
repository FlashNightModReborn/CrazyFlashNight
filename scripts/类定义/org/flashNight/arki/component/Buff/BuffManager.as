/**
 * BuffManager.as - 支持 MetaBuff 注入机制（升级版：Sticky PropertyContainer 设计）
 *
 * 版本历史:
 * v2.6 (2026-01) - 代码审查修复 & 性能优化（Claude审阅）
 *   [FIX] 注入PodBuff补设__inManager/__regId标记 - 与独立buff保持一致性
 *   [FIX] _processPendingRemovals移除预splice - 由_removePodBuffCore统一处理
 *   [PERF] 新增_metaByInternalId映射 - _removePodBuffCore从O(m)降为O(1)
 *
 * v2.5 (2026-01) - 新增 addBuffImmediate API
 *   [FEAT] 新增 addBuffImmediate(buff, buffId) - 添加Buff并立即应用效果
 *   [USE] 适用于添加buff后需要立即读取更新后属性值的场景（如播报数值）
 *
 * v2.4 (2026-01) - 代码审查修复 & 性能优化
 *   [FIX] 导入路径大小写修复 - component -> Component
 *   [FIX] MetaBuff新增removeInjectedBuffId方法 - 修复注入列表不同步问题
 *   [PERF] MetaBuff移除try/catch - 契约化设计，组件不得throw
 *   [PERF] PodBuff.applyEffect移除冗余属性检查 - PropertyContainer已保证匹配
 *
 * v2.3 (2026-01) - 重入安全 & 性能优化
 *   [P0-CRITICAL] _flushPendingAdds重入丢失修复 - 双缓冲队列方案
 *   [PERF] _removeInactivePodBuffs优化 - 消除重复线性扫描
 *   [DOC] addBuff/removeBuff/getBuffById添加返回值vs buff.getId()警告
 *
 * v2.2 (2026-01) - Bugfix Review
 *   [P0-1] unmanageProperty脏标记问题 - 添加_unmanagedProps黑名单和_suppressDirty抑制
 *   [P0-2] MetaBuff异常后僵尸问题 - catch块直接移除而非延迟
 *   [P0-3] _redistribute*空容器保护 - 添加属性名校验和null检查
 *   [P1-1] _flushPendingAdds性能 - 改用索引遍历避免shift()的O(n²)
 *   [P1-2] _inUpdate标志复位时机 - 移到flush之后确保回调延迟处理
 *
 * v2.1 - P1-1(auto_前缀) / P1-2(__inManager防重复) / P1-3(注入容错+尽力回滚)
 *
 * 核心特性:
 * - Sticky PropertyContainer: 属性容器持久化，避免重复创建销毁
 * - MetaBuff注入机制: MetaBuff管理PodBuff的生命周期和注入
 * - 增量脏集优化: 只重算变化的属性，提升性能
 * - ID命名空间分离: external/internal ID隔离避免冲突
 * - 重入保护: update期间的addBuff延迟处理
 *
 * ==================== 设计契约 ====================
 *
 * 【契约1】延迟添加生效时机
 *   - 在 update() 期间调用 addBuff/removeBuff，效果从本次 update() 结束时生效
 *   - 具体时序：重算 → flush延迟添加 → _inUpdate复位
 *   - 新增的buff在本帧末尾被添加，但不参与本帧的属性重算
 *   - 若需"同帧立即生效"，应在 update() 外部调用 addBuff
 *
 * 【契约2】OVERRIDE 冲突决策（遍历方向）
 *   - PropertyContainer 逆序遍历buff列表（后添加的先apply）
 *   - BuffCalculator 的 OVERRIDE 采用"最后写入wins"
 *   - 结果：多个 OVERRIDE 并存时，**添加顺序最早的 OVERRIDE 生效**
 *   - 若需"新覆盖旧"语义，应使用同ID替换机制（addBuff同ID会先移除旧buff）
 *
 * 【契约3】重入安全保证
 *   - 在任何回调（onBuffAdded/onBuffRemoved/onPropertyChanged）中调用 addBuff() 是安全的
 *   - 使用双缓冲队列，重入期间添加的buff不会丢失
 *   - 回调中调用 removeBuff() 会加入延迟队列，下次 update() 处理
 *
 * 【契约4】ID命名空间
 *   - 外部ID（用户传入的buffId）：禁止使用纯数字，避免与内部ID冲突
 *   - 内部ID（系统自增）：仅用于注入的PodBuff
 *   - buffId为null时自动生成 "auto_" 前缀的外部ID
 *
 * ================================================
 */
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

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
    private var _metaByInternalId:Object;          // [v2.6] { metaInternalId -> MetaBuff实例 } O(1)查找优化

    // 性能优化
    private var _updateCounter:Number = 0;
    private var _isDirty:Boolean = false;
    private var _dirtyProps:Object = {};           // 增量脏集 {propName:true}

    // [P0-1 修复] unmanageProperty 保护机制
    private var _unmanagedProps:Object = {};       // 已解除管理的属性黑名单 {propName:true}
    private var _suppressDirty:Boolean = false;   // 临时抑制脏标记

    // [Phase A] 重入保护
    private var _inUpdate:Boolean = false;         // 是否正在update中
    private var _pendingAdds:Array;                // 延迟添加队列 [{buff:IBuff, id:String}]

    // [v2.3] 双缓冲队列：解决 _flushPendingAdds 重入期间丢失新增buff的问题
    private var _pendingAddsA:Array;               // 缓冲队列A
    private var _pendingAddsB:Array;               // 缓冲队列B

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
        this._metaByInternalId = {};  // [v2.6] O(1)查找优化

        // [P0-1 修复] 初始化 unmanageProperty 保护机制
        this._unmanagedProps = {};
        this._suppressDirty = false;

        // [Phase A] 初始化重入保护
        this._inUpdate = false;
        // [v2.3] 双缓冲队列初始化
        this._pendingAddsA = [];
        this._pendingAddsB = [];
        this._pendingAdds = this._pendingAddsA;  // 当前写入队列指向A

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
     * @param buff 要添加的Buff实例
     * @param buffId 外部ID（可选，为null时自动生成"auto_"前缀ID）
     * @return String 注册ID，用于后续 removeBuff() 操作
     *
     * 【重要警告】返回值 vs buff.getId()
     *   - 返回值是用于 removeBuff() 的正确ID
     *   - buff.getId() 返回的是内部自增ID，**禁止**用于 removeBuff()
     *   - 正确用法: var regId = addBuff(buff, null); removeBuff(regId);
     *   - 错误用法: addBuff(buff, null); removeBuff(buff.getId()); // 无效！
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

        // [Phase D / P1-1 修复] 外部ID契约校验
        // 1. 用户显式传入的 buffId 禁止纯数字
        // 2. buffId 为 null 时，自动加 "auto_" 前缀，确保外部映射不含纯数字
        var finalId:String;
        if (buffId != null && buffId.length > 0) {
            // 用户显式传入ID，校验是否为纯数字
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
            finalId = buffId;
        } else {
            // [P1-1] buffId 为 null，自动生成带前缀的外部ID，避免纯数字进入 _byExternalId
            finalId = "auto_" + buff.getId();
        }

        // [Phase A / P0-5] 重入保护：update期间延迟添加
        if (this._inUpdate) {
            this._pendingAdds.push({buff: buff, id: finalId});
            return finalId;
        }

        // 实际添加逻辑
        return this._addBuffNow(buff, finalId);
    }

    /**
     * 添加Buff并立即应用效果
     *
     * 适用场景：
     * - 添加buff后需要立即读取更新后的属性值（如播报数值）
     * - 需要buff效果在当前帧立即生效
     *
     * 与addBuff的区别：
     * - addBuff: 添加后属性值在下一帧update时才更新
     * - addBuffImmediate: 添加后立即调用update(0)，属性值当场更新
     *
     * 注意：如果在update()期间调用，buff会进入延迟队列，
     * 此时不会额外调用update(0)以避免递归问题。
     *
     * @param buff IBuff Buff实例
     * @param buffId String 外部ID（可选，null时自动生成）
     * @return String 实际注册的ID，失败返回null
     *
     * @example
     * // 添加buff并立即播报更新后的属性值
     * target.buffManager.addBuffImmediate(metaBuff, "狮子之力");
     * _root.发布消息("攻击力提升至" + target.空手攻击力 + "点！");
     */
    public function addBuffImmediate(buff:IBuff, buffId:String):String {
        var id:String = this.addBuff(buff, buffId);
        // 只有成功添加且不在update期间才立即刷新
        // _inUpdate期间addBuff会进入延迟队列，此时不应再调用update
        if (id != null && !this._inUpdate) {
            this.update(0);
        }
        return id;
    }

    /**
     * [Phase A] 立即添加Buff的内部实现
     *
     * [Phase B] 使用_byExternalId作为唯一来源，废弃_idMap
     * [Phase D] 外部ID契约校验已移至addBuff入口处
     * [P1-2] 防止同一实例重复注册
     */
    private function _addBuffNow(buff:IBuff, finalId:String):String {
        // [P1-2] 检查是否已在管理中（防止同一实例重复注册导致幽灵buff）
        if (buff["__inManager"] === true) {
            trace("[BuffManager] 警告：同一Buff实例已在管理中，拒绝重复注册。旧ID: " + buff["__regId"] + ", 新ID: " + finalId);
            return null;
        }

        // [Phase A / P0-4] 取消同ID的pending removal
        this._cancelPendingRemoval(finalId);

        // [Phase B] 如果已存在同ID的Buff，先同步移除旧实例
        if (this._byExternalId[finalId]) {
            this._removeByIdImmediate(finalId);
        }

        this._buffs.push(buff);

        // [Phase B] 只写入_byExternalId，用户注册的Buff
        this._byExternalId[finalId] = buff;

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
                if (this._unmanagedProps[prop] === true) {
                    delete this._unmanagedProps[prop];
                }
                ensurePropertyContainerExists(prop);
                _markPropDirty(prop);
            } else {
                trace("[BuffManager] 警告：PodBuff属性名无效: " + prop);
            }
        } else {
            // 如果是 MetaBuff，立即处理初始注入（使用鸭子类型检测）
            if (typeof buff["createPodBuffsForInjection"] == "function") {
                // [v2.6] 注册到O(1)查找映射（在注入前，因为注入的pod需要查找parent）
                this._metaByInternalId[buff.getId()] = buff;
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
     * @param buffId addBuff()的返回值，**不是**buff.getId()
     * @return Boolean 是否找到并标记为待移除
     *
     * 【重要警告】buffId 必须使用 addBuff() 的返回值：
     *   - ✅ 正确: removeBuff(addBuff返回的ID)
     *   - ❌ 错误: removeBuff(buff.getId()) // 无效，找不到buff！
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
     * 【契约】仅在update()外部调用，update期间调用可能导致状态不一致
     */
    public function clearAllBuffs():Void {
        // [v2.6] DEBUG警告：update期间调用可能导致状态不一致
        if (DEBUG && this._inUpdate) {
            trace("[BuffManager] 警告：update期间调用clearAllBuffs可能导致状态不一致");
        }
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
        this._metaByInternalId = {};  // [v2.6] 清理O(1)查找映射
        this._dirtyProps = {};

        // [Phase A] 清理延迟添加队列
        // [v2.3] 双缓冲队列都需要清空
        this._pendingAddsA.length = 0;
        this._pendingAddsB.length = 0;
        this._pendingAdds = this._pendingAddsA;

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

            // [Phase A] 处理延迟添加的Buff
            // [P1-2 修复] 移到 finally 之前，确保 flush 期间回调不会重入
            this._flushPendingAdds();
        } finally {
            // [Phase A] [P1-2 修复] 在所有操作完成后才复位标志
            this._inUpdate = false;
        }
    }

    /**
     * [Phase A] 处理延迟添加队列
     * [P1-1 修复] 改用索引遍历 + length=0，避免 shift() 的 O(n²) 复杂度
     * [v2.3 修复] 使用双缓冲队列解决重入期间新增buff丢失的问题
     *
     * 【契约】重入安全保证：
     * - 在 _addBuffNow 触发的回调（onBuffAdded等）中调用 addBuff() 是安全的
     * - 重入期间添加的 buff 会在本次 flush 循环中被处理（不会丢失）
     * - 最坏情况下会多次循环直到队列稳定，但不会无限循环（因为正常逻辑不会无限添加）
     */
    private function _flushPendingAdds():Void {
        // 双缓冲循环：处理当前队列，重入新增的写入另一队列，交替处理直到两队列都空
        while (this._pendingAddsA.length > 0 || this._pendingAddsB.length > 0) {
            // 确定本轮处理的队列（非空的那个），将 _pendingAdds 指向另一个作为写入目标
            var processing:Array;
            if (this._pendingAddsA.length > 0) {
                processing = this._pendingAddsA;
                this._pendingAdds = this._pendingAddsB;  // 新增写入B
            } else {
                processing = this._pendingAddsB;
                this._pendingAdds = this._pendingAddsA;  // 新增写入A
            }

            // 处理当前队列
            var len:Number = processing.length;
            for (var i:Number = 0; i < len; i++) {
                var entry:Object = processing[i];
                this._addBuffNow(entry.buff, entry.id);
                processing[i] = null;  // 帮助GC
            }
            processing.length = 0;
        }

        // 确保 _pendingAdds 指向A（保持一致性）
        this._pendingAdds = this._pendingAddsA;
    }

    /**
     * 主动解除对某个属性的管理
     * @param finalize true: 将当前可见值固化为普通数据属性；false: 直接销毁并删除属性
     *
     * [P0-1 修复] 使用 _suppressDirty 和 _unmanagedProps 防止下一帧重建容器
     * 【契约】仅在update()外部调用，update期间调用可能导致状态不一致
     */
    public function unmanageProperty(propertyName:String, finalize:Boolean):Void {
        // [v2.6] DEBUG警告
        if (DEBUG && this._inUpdate) {
            trace("[BuffManager] 警告：update期间调用unmanageProperty可能导致状态不一致");
        }
        var c:PropertyContainer = this._propertyContainers[propertyName];
        if (!c) return;

        // [P0-1 修复] 1) 立即加入黑名单，阻止下一帧重建
        this._unmanagedProps[propertyName] = true;

        // [P0-1 修复] 2) 开启抑制模式，防止 _removePodBuff 标记脏
        this._suppressDirty = true;

        // 同步清理该属性上的独立 Pod（注入 Pod 交由 Meta 生命周期维护）
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            var b:IBuff = this._buffs[i];
            if (b && b.isPod()) {
                var pb:PodBuff = PodBuff(b);
                if (pb.getTargetProperty() == propertyName) {
                    var internalId:String = pb.getId();
                    if (!this._injectedPodBuffs[internalId]) {
                        // [P1-1 修复] 使用 __regId（注册时的外部ID）而非纯数字内部ID
                        var regId:String = b["__regId"];
                        if (regId != null) {
                            this._removePodBuff(regId);
                        } else {
                            // 兼容：无 __regId 时尝试使用内部ID
                            this._removePodBuff(internalId);
                        }
                    }
                }
            }
        }

        // [P0-1 修复] 3) 关闭抑制模式
        this._suppressDirty = false;

        // 解绑/销毁容器
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

        // [P0-1 修复] 4) 清理脏标记，确保 update() 不会误触发
        delete this._dirtyProps[propertyName];
    }

    /**
     * 销毁（用于宿主释放）
     * 【契约】仅在update()外部调用，update期间调用可能导致状态不一致
     */
    public function destroy():Void {
        // [v2.6] DEBUG警告
        if (DEBUG && this._inUpdate) {
            trace("[BuffManager] 警告：update期间调用destroy可能导致状态不一致");
        }
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

    /**
     * [P0-1 修复] 标记属性为脏
     * 支持 _suppressDirty 临时抑制和 _unmanagedProps 黑名单
     */
    private function _markPropDirty(propertyName:String):Void {
        // [P0-1] 临时抑制模式下不标记
        if (this._suppressDirty) return;
        // [P0-1] 已解除管理的属性不标记
        if (this._unmanagedProps[propertyName] === true) return;

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
                    // [v2.6 优化] 移除预splice，由_removePodBuffCore统一处理注入列表清理
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
                        // [P0-2 修复] 异常时立即移除，避免僵尸Buff
                        this._ejectMetaBuffPods(buff);
                        this._removeMetaBuff(buff);
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
     * 注入 MetaBuff 生成的 PodBuff
     *
     * [Phase 0 / P1-1] 添加幂等检查，防止重复注入
     * [Phase A / P0-8] 添加属性名校验
     * [P1-3] 容错与尽力回滚：鸭子类型跳过无效pod，异常时回滚引用（非ACID）
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
        var podBuffs:Array;
        try {
            podBuffs = metaBuff["createPodBuffsForInjection"]();
        } catch (createErr) {
            trace("[BuffManager] 错误：createPodBuffsForInjection 异常: " + createErr);
            return;
        }

        if (!podBuffs || podBuffs.length == 0) {
            return;
        }

        var injectedIds:Array = [];

        // [P1-3] 容错注入：try/catch 包裹，异常时尽力回滚引用（不撤销回调/destroy）
        try {
            for (var i:Number = 0; i < podBuffs.length; i++) {
                var podBuff:PodBuff = podBuffs[i];

                // 防御性检查：跳过 null 或非 PodBuff（使用鸭子类型避免无 isPod 方法时抛异常）
                if (!podBuff || typeof podBuff["isPod"] != "function" || !podBuff.isPod()) {
                    trace("[BuffManager] 警告：跳过无效的注入Pod（null或非PodBuff）");
                    continue;
                }

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

                // [v2.6 修复] 设置管理状态标记，与独立buff保持一致
                podBuff["__inManager"] = true;
                podBuff["__regId"] = podId;

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
        } catch (injectErr) {
            // [P1-3] 尽力回滚：仅清理引用，不 destroy/不撤销回调
            trace("[BuffManager] 错误：注入过程异常，回滚已注入的 " + injectedIds.length + " 个Pod: " + injectErr);
            for (var r:Number = injectedIds.length - 1; r >= 0; r--) {
                var rollbackId:String = injectedIds[r];
                // 从 _buffs 中移除
                for (var b:Number = this._buffs.length - 1; b >= 0; b--) {
                    if (this._buffs[b] && this._buffs[b].getId() == rollbackId) {
                        this._buffs.splice(b, 1);
                        break;
                    }
                }
                // 从映射中移除
                delete this._byInternalId[rollbackId];
                delete this._injectedPodBuffs[rollbackId];
            }
            // 清空注入列表，不记录到 _metaBuffInjections
            return;
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

        // 从数组中移除（需要遍历查找索引）
        var foundIndex:Number = -1;
        for (var i:Number = this._buffs.length - 1; i >= 0; i--) {
            if (this._buffs[i] === podBuff) {
                foundIndex = i;
                break;
            }
        }

        // 调用带索引的内部方法完成实际移除
        this._removePodBuffCore(podId, podBuff, foundIndex);
    }

    /**
     * [v2.3] 移除 PodBuff 的核心实现（已知索引版本）
     *
     * 供 _removePodBuff 和 _removeInactivePodBuffs 共用，避免重复线性扫描
     *
     * @param podId     buff的ID（外部或内部）
     * @param podBuff   buff实例引用（已验证非null）
     * @param arrayIndex 在 _buffs 数组中的索引，-1 表示未知/已移除
     */
    private function _removePodBuffCore(podId:String, podBuff:IBuff, arrayIndex:Number):Void {
        // 获取目标属性并标记为脏（确保同帧重算）
        var podBuffCast:PodBuff = PodBuff(podBuff);
        if (podBuffCast) {
            var targetProp:String = podBuffCast.getTargetProperty();
            if (targetProp) {
                _markPropDirty(targetProp);
            }
        }

        // 从数组中移除（如果提供了有效索引则直接splice，否则已经移除）
        if (arrayIndex >= 0 && arrayIndex < this._buffs.length) {
            this._buffs.splice(arrayIndex, 1);
        }

        // 若为注入 Pod，同步 Meta 内部记录
        var parentMetaId:String = this._injectedPodBuffs[podId];
        if (parentMetaId) {
            // [v2.6 优化] 使用O(1)查找替代for..in遍历
            var metaRef:Object = this._metaByInternalId[parentMetaId];
            if (metaRef && typeof metaRef["removeInjectedBuffId"] == "function") {
                metaRef["removeInjectedBuffId"](podId);
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

        // [P1-2] 清除管理状态标志
        podBuff["__inManager"] = false;

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

        // [v2.6] 清理O(1)查找映射
        delete this._metaByInternalId[metaBuff["getId"]()];

        // [P1-2] 清除管理状态标志
        metaBuff["__inManager"] = false;

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
     * [v2.3 优化] 直接传递索引给 _removePodBuffCore，消除重复线性扫描
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
                    // [v2.3] 直接传递索引，避免 _removePodBuff 内部再次遍历
                    this._removePodBuffCore(regId, buff, i);
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
                // [P0-3 修复] 添加属性名校验和空容器保护
                if (dirty[tp] && tp != null && tp.length > 0 && tp != "undefined" && tp != "null") {
                    var pc:PropertyContainer = ensurePropertyContainerExists(tp);
                    if (pc != null) {
                        pc.addBuff(pb);
                    }
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
                // [P0-3 修复] 添加属性名校验和空容器保护
                if (prop != null && prop.length > 0 && prop != "undefined" && prop != "null") {
                    var c:PropertyContainer = ensurePropertyContainerExists(prop);
                    if (c != null) {
                        c.addBuff(pod);
                    }
                }
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
     * [P0-1 修复] 跳过已解除管理的属性
     */
    private function ensurePropertyContainerExists(propertyName:String):PropertyContainer {
        // [Phase A / P0-8] 校验属性名
        if (propertyName == null || propertyName == undefined ||
            propertyName.length == 0 || propertyName == "undefined" || propertyName == "null") {
            trace("[BuffManager] 警告：尝试创建无效属性名的容器: " + propertyName);
            return null;
        }

        // [P0-1 修复] 已解除管理的属性不创建容器
        if (this._unmanagedProps[propertyName] === true) {
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
     * @param buffId addBuff()的返回值，**不是**buff.getId()
     * @return IBuff实例或null
     *
     * 【提示】buffId 应使用 addBuff() 的返回值
     */
    public function getBuffById(buffId:String):IBuff {
        return this._lookupById(buffId);
    }
}
