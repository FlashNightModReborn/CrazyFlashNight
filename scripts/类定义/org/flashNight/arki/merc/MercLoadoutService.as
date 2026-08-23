import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.EventBus;

/**
 * 佣兵装备托管领域服务（一期）。
 *
 * 设计契约：docs/佣兵装备托管-设计-2026-08-23.md。
 * 三层装备权威：merc[6..15] 固有预设（终身不变）、merc[19].装备托管 版本化冻结域、
 * 出战生成时逐槽取「托管有效克隆 ?? 预设字符串」。
 *
 * 核心不变量（复制 ManagedLongGunService 模式）：
 *  - 交付时从背包移除完整 BaseItem 存档快照；托管期间权威快照保持只读。
 *  - 出战单位始终持有快照克隆，战斗变化（弹量/插件/形态）不得回写托管权威。
 *  - 取回始终返还交付瞬间的冻结物品。
 *  - 托管转移是所有权位置变化，不发布玩家资产 gain/loss 回执。
 *  - 损坏/未知版本托管记录占据该槽：出战安全回退预设，交付/替换/取回全部
 *    fail-closed（custody_corrupt），恢复走存档修复通道。
 */
class org.flashNight.arki.merc.MercLoadoutService {
    private static var CUSTODY_KEY:String = "装备托管";
    private static var SLOT_MIN:Number = 6;
    private static var SLOT_MAX:Number = 15;
    // merc[6..15] → 槽名（use 匹配规则与 CharacterBuildService.equipmentUseMatchesSlot 同口径）
    private static var SLOT_USE_KEYS:Array = [
        "头部装备", "上装装备", "手部装备", "下装装备", "脚部装备",
        "颈部装备", "长枪", "手枪", "手枪2", "刀"
    ];
    private static var _busy:Boolean = false;

    /** 仅 merc[6..15] 可写；16 手雷槽属纯经济消耗模型，一期不开放。 */
    public static function isWritableSlot(slot):Boolean {
        var s:Number = Number(slot);
        if (isNaN(s) || s != Math.floor(s)) return false;
        return s >= SLOT_MIN && s <= SLOT_MAX;
    }

    /** 槽下标 → use 槽名；非法槽返回 null。 */
    public static function slotUseKey(slot):String {
        if (!isWritableSlot(slot)) return null;
        return String(SLOT_USE_KEYS[Number(slot) - SLOT_MIN]);
    }

    /** 解雇守卫：slots 有任何键（含损坏记录）即视为存在托管。 */
    public static function hasAnyCustody(merc:Array):Boolean {
        var custody:Object = readCustody(merc);
        if (custody == null) return false;
        // 结构异常的托管域按损坏占位处理：阻塞解雇，避免未知版本数据
        // 随「回池→深拷贝→再雇佣」复制通道丢失或复制。
        if (Number(custody.version) != 1) return true;
        var slots:Object = custody.slots;
        if (slots == undefined || typeof slots != "object") return true;
        for (var key:String in slots) {
            if (slots[key] != null) return true;
        }
        return false;
    }

    /** 无托管对象返回 0（旧档兼容，同 价格倍率 先例）。 */
    public static function getLoadoutRevision(merc:Array):Number {
        var custody:Object = readCustody(merc);
        if (custody == null) return 0;
        var revision:Number = Number(custody.loadoutRevision);
        if (isNaN(revision) || revision < 0) return 0;
        return revision;
    }

    /**
     * §2 资格 policy：装备实例 + use 匹配槽名（手枪2 接受手枪）+ type 武器/防具
     * + 需求等级 <= 佣兵自身等级（merc[0]）。无性别/兵种门（代码库不存在该维度）。
     */
    public static function evaluateItemForSlot(merc:Array, slot, item:Object):Object {
        if (!isWritableSlot(slot)) return fail("slot_locked");
        if (item == null || typeof item.getData != "function"
                || typeof item.value != "object" || item.value == null) {
            return fail("invalid_item");
        }
        var data:Object = item.getData();
        if (data == null) return fail("invalid_item");
        var itemUse:String = data.use == undefined ? "" : String(data.use);
        if (!useMatchesSlot(itemUse, slotUseKey(slot))) return fail("slot_mismatch");
        var itemType:String = data.type == undefined ? "" : String(data.type);
        if (itemType != "武器" && itemType != "防具") return fail("not_equipment");
        var requirement:Number = data.data == undefined ? NaN : Number(data.data.level);
        if (isNaN(requirement) || !isFinite(requirement) || requirement < 1) {
            return fail("invalid_item");
        }
        requirement = Math.ceil(requirement);
        var mercLevel:Number = Number(merc[0]);
        if (requirement > mercLevel) {
            return {
                success:false,
                error:"level_locked",
                requirementLevel:requirement,
                mercLevel:mercLevel
            };
        }
        return {success:true, requirementLevel:requirement};
    }

    /**
     * 面板投影：逐槽三态（preset/custody/custody_corrupt）+ 预设/托管双向概览。
     * canOperate = !combatLocked && deployState==0；slotIndex<0 的池佣兵仅 preset，
     * canOperate=false。预设槽应用 getEquipmentDefaultLevel 默认强化，与
     * MercPanelService.buildMercSummary 口径一致。
     */
    public static function buildLoadoutProjection(merc:Array, slotIndex:Number):Object {
        var combatLocked:Boolean = _root.当前为战斗地图 == true;
        var hasDeploySlot:Boolean = !isNaN(slotIndex) && slotIndex >= 0;
        var deployState = !hasDeploySlot ? null
            : (_root.佣兵是否出战信息 == undefined
                ? 0 : (Number(_root.佣兵是否出战信息[slotIndex]) || 0));
        var projection:Object = {
            version:1,
            loadoutRevision:getLoadoutRevision(merc),
            canOperate:hasDeploySlot && !combatLocked && deployState == 0,
            combatLocked:combatLocked,
            deployState:deployState,
            writableSlots:[6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
            slots:{}
        };
        for (var slot:Number = SLOT_MIN; slot <= SLOT_MAX; slot++) {
            projection.slots[String(slot)] = buildSlotProjection(merc, slot);
        }
        return projection;
    }

    /**
     * 候选列表：现场签发背包快照，只列 use 匹配该槽的物品（不产生跨槽
     * 「不兼容」噪声，同 T800 只列长枪口径）；逐候选跑 §2 policy 盖 eligible 章。
     */
    public static function buildCandidates(merc:Array, slot):Object {
        if (!isWritableSlot(slot)) return fail("slot_locked");
        var slotNum:Number = Number(slot);
        var useKey:String = slotUseKey(slotNum);
        var snapshot:Object = InventoryPanelService.buildExternalSnapshot("背包", 0, 50);
        if (snapshot == null || !(snapshot.slots instanceof Array)) {
            return fail("inventory_unavailable");
        }
        var bag:ArrayInventory = _root.物品栏 == undefined ? null : _root.物品栏.背包;
        if (bag == null) return fail("inventory_unavailable");
        var result:Object = {
            success:true,
            slot:slotNum,
            useKey:useKey,
            loadoutRevision:getLoadoutRevision(merc),
            candidates:[]
        };
        for (var i:Number = 0; i < snapshot.slots.length; i++) {
            var slotView:Object = snapshot.slots[i];
            if (slotView == null || !slotView.occupied || slotView.item == null) continue;
            var itemUse:String = slotView.item.use == undefined ? "" : String(slotView.item.use);
            if (!useMatchesSlot(itemUse, useKey)) continue;
            var item:Object = bag.getItem(String(slotView.physicalSlot));
            var check:Object = evaluateItemForSlot(merc, slotNum, item);
            result.candidates.push({
                source:{
                    containerId:"背包",
                    slot:Number(slotView.physicalSlot),
                    expectedLease:String(slotView.slotLease)
                },
                item:slotView.item,
                eligible:check.success === true,
                lockReason:check.success === true ? "" : String(check.error),
                requirementLevel:Number(check.requirementLevel)
            });
        }
        return result;
    }

    /**
     * 槽位 tooltip：source 非空 = 背包候选（lease 复证 + 背包限定 + use 匹配）；
     * source 空 = 托管冻结克隆，无托管则预设字符串（应用默认强化，与
     * buildMercSummary 口径一致）。展示投影统一走 canonical buildTooltipProjection。
     */
    public static function buildSlotTooltip(merc:Array, slot, source:Object):Object {
        if (!isWritableSlot(slot)) return fail("slot_locked");
        var slotNum:Number = Number(slot);
        var useKey:String = slotUseKey(slotNum);
        var item:Object = null;
        if (source != null) {
            var checked:Object = InventoryPanelService.validateExternalSlotRef(source, false);
            if (checked == null || checked.success !== true) {
                return checked == null ? fail("stale_state") : checked;
            }
            if (String(checked.containerId) != "背包") return fail("unsupported_container");
            item = checked.item;
            var data:Object = item == null || typeof item.getData != "function"
                ? null : item.getData();
            var itemUse:String = data == null || data.use == undefined ? "" : String(data.use);
            if (!useMatchesSlot(itemUse, useKey)) return fail("slot_mismatch");
        } else {
            var record:Object = readSlotRecord(merc, slotNum);
            if (record != null) {
                if (Number(record.version) != 1) return fail("custody_corrupt");
                item = createRuntimeItem(slotNum, record.item);
                if (item == null) return fail("custody_corrupt");
            } else {
                var raw = merc[slotNum];
                if (raw == undefined || String(raw) == "" || String(raw) == "null") {
                    return fail("item_data_missing");
                }
                item = BaseItem.createFromString(String(raw));
                if (item == null) return fail("item_data_missing");
                if (!(item.value != undefined && item.value.level > 1)) {
                    item.value.level = DressupInitializer.getEquipmentDefaultLevel(
                        Number(merc[0]), String(merc[1]));
                }
            }
        }
        return InventoryPanelService.buildTooltipProjection(item);
    }

    public static function deliver(mercIndex, mercId, slotKey,
                                   expectedLoadoutRevision, source):Object {
        if (_busy) return fail("busy");
        _busy = true;
        var result:Object;
        try {
            result = deliverInternal(mercIndex, mercId, slotKey,
                expectedLoadoutRevision, source);
        } finally {
            _busy = false;
        }
        return result;
    }

    public static function replace(mercIndex, mercId, slotKey,
                                   expectedLoadoutRevision, source):Object {
        if (_busy) return fail("busy");
        _busy = true;
        var result:Object;
        try {
            result = replaceInternal(mercIndex, mercId, slotKey,
                expectedLoadoutRevision, source);
        } finally {
            _busy = false;
        }
        return result;
    }

    public static function withdraw(mercIndex, mercId, slotKey,
                                    expectedLoadoutRevision):Object {
        if (_busy) return fail("busy");
        _busy = true;
        var result:Object;
        try {
            result = withdrawInternal(mercIndex, mercId, slotKey, expectedLoadoutRevision);
        } finally {
            _busy = false;
        }
        return result;
    }

    /**
     * 出战生成解析：恒返回十键（头部装备/上装装备/手部装备/下装装备/脚部装备/
     * 颈部装备/长枪/手枪/手枪2/刀）。托管槽经 createRuntimeItem 复证成功放
     * BaseItem 克隆（DressupInitializer.loadEquipment 对非字符串值原样透传），
     * 损坏/无托管放预设字符串；每次调用全新克隆。不返回手雷键。
     */
    public static function buildSpawnLoadout(merc:Array):Object {
        var loadout:Object = {};
        for (var slot:Number = SLOT_MIN; slot <= SLOT_MAX; slot++) {
            var resolved = merc == undefined ? undefined : merc[slot];
            var record:Object = readSlotRecord(merc, slot);
            if (record != null && Number(record.version) == 1) {
                var runtime:BaseItem = createRuntimeItem(slot, record.item);
                if (runtime != null) resolved = runtime;
            }
            loadout[slotUseKey(slot)] = resolved;
        }
        return loadout;
    }

    /** 每次都深克隆，避免 BaseItem.createFromObject 对 mods 归一化时触及冻结权威。 */
    public static function createRuntimeItem(slot, frozen:Object):BaseItem {
        if (frozen == null || !isWritableSlot(slot)) return null;
        var clone:Object = ObjectUtil.clone(frozen);
        var item:BaseItem = clone == null ? null : BaseItem.createFromObject(clone);
        if (item == null) return null;
        // 不能只验证「仍是有效物品」：损坏/手改存档可能把 version=1 快照替换成
        // 其它槽位装备。托管域与出战运行态都必须再次确认 use 匹配槽名。
        var data:Object = item.getData();
        var itemUse:String = data == null || data.use == undefined ? "" : String(data.use);
        return useMatchesSlot(itemUse, slotUseKey(slot)) ? item : null;
    }

    public static function freezeItem(item:Object):Object {
        if (item == null || typeof item.toObject != "function") return null;
        var frozen:Object = item.toObject();
        if (frozen == null || typeof frozen.value != "object" || frozen.value == null) return null;
        return ObjectUtil.clone(frozen);
    }

    // ═══════════════════════════════════════════════════════════
    // 写操作内部实现（公共门 → policy → 三段式事务，顺序即断言顺序）
    // ═══════════════════════════════════════════════════════════

    private static function deliverInternal(mercIndex, mercId, slotKey,
                                            expectedLoadoutRevision, source):Object {
        var ctx:Object = validateWriteContext(mercIndex, mercId, slotKey,
            expectedLoadoutRevision);
        if (ctx.success !== true) return ctx;
        var checked:Object = InventoryPanelService.validateExternalSlotRef(source, false);
        if (checked == null || checked.success !== true) {
            return checked == null ? fail("stale_state") : checked;
        }
        if (String(checked.containerId) != "背包") return fail("unsupported_container");
        var merc:Array = ctx.merc;
        var slot:Number = ctx.slot;
        var eligibility:Object = evaluateItemForSlot(merc, slot, checked.item);
        if (eligibility.success !== true) return eligibility;

        var custody:Object = ensureCustody(merc);
        if (!isHealthyCustody(custody)) return fail("custody_corrupt");
        var slots:Object = custody.slots;
        var key:String = String(slot);
        var existing:Object = slots[key];
        if (existing != null) {
            // 有效记录提示改用 replace；损坏记录占据该槽时 fail-closed。
            if (Number(existing.version) == 1
                    && createRuntimeItem(slot, existing.item) != null) {
                return fail("custody_exists");
            }
            return fail("custody_corrupt");
        }

        var frozen:Object = freezeItem(checked.item);
        if (frozen == null || createRuntimeItem(slot, frozen) == null) {
            return fail("invalid_item");
        }
        var inventory:ArrayInventory = checked.inventory;
        var srcSlot:Number = Number(checked.slot);
        var original:Object = checked.item;

        // 先把冻结权威写入托管槽，再在同一同步调用栈内移除背包原物。
        // 写失败时撤销未生效的托管记录，不会发布任何中间态事件。
        slots[key] = {version:1, item:frozen};
        if (!tryTransactionWrite(inventory, srcSlot, null)) {
            delete slots[key];
            return fail("commit_failed");
        }
        if (inventory.getItem(String(srcSlot)) != null) {
            var rollbackComplete:Boolean = tryTransactionWrite(inventory, srcSlot, original)
                && inventory.getItem(String(srcSlot)) === original;
            if (rollbackComplete) delete slots[key];
            return fail(rollbackComplete ? "commit_failed" : "rollback_failed");
        }

        custody.loadoutRevision = getLoadoutRevision(merc) + 1;
        markDirty();
        publishCommittedSlot(inventory, srcSlot, "removed");
        return {
            success:true,
            operation:"deliver",
            mercIndex:ctx.index,
            slotKey:key,
            sourceSlot:srcSlot,
            loadoutRevision:Number(custody.loadoutRevision)
        };
    }

    private static function replaceInternal(mercIndex, mercId, slotKey,
                                            expectedLoadoutRevision, source):Object {
        var ctx:Object = validateWriteContext(mercIndex, mercId, slotKey,
            expectedLoadoutRevision);
        if (ctx.success !== true) return ctx;
        var checked:Object = InventoryPanelService.validateExternalSlotRef(source, false);
        if (checked == null || checked.success !== true) {
            return checked == null ? fail("stale_state") : checked;
        }
        if (String(checked.containerId) != "背包") return fail("unsupported_container");
        var merc:Array = ctx.merc;
        var slot:Number = ctx.slot;
        var eligibility:Object = evaluateItemForSlot(merc, slot, checked.item);
        if (eligibility.success !== true) return eligibility;

        var custody:Object = readCustody(merc);
        if (custody == null) return fail("no_custody");
        if (!isHealthyCustody(custody)) return fail("custody_corrupt");
        var slots:Object = custody.slots;
        var key:String = String(slot);
        var oldRecord:Object = slots[key];
        if (oldRecord == null) return fail("no_custody");
        if (Number(oldRecord.version) != 1) return fail("custody_corrupt");
        var restoredOld:BaseItem = createRuntimeItem(slot, oldRecord.item);
        if (restoredOld == null) return fail("custody_corrupt");

        var frozen:Object = freezeItem(checked.item);
        if (frozen == null || createRuntimeItem(slot, frozen) == null) {
            return fail("invalid_item");
        }
        var inventory:ArrayInventory = checked.inventory;
        var srcSlot:Number = Number(checked.slot);
        var original:Object = checked.item;

        // 旧冻结物重建后写入新物品原来的背包格（无需空位）。
        // 任一步失败都把托管还原为旧记录；背包回滚失败时保留新冻结，
        // 保证物品至少在托管域留有权威副本，不暴露半份所有权转移。
        slots[key] = {version:1, item:frozen};
        if (!tryTransactionWrite(inventory, srcSlot, restoredOld)) {
            slots[key] = oldRecord;
            return fail("commit_failed");
        }
        if (inventory.getItem(String(srcSlot)) !== restoredOld) {
            var rollbackComplete:Boolean = tryTransactionWrite(inventory, srcSlot, original)
                && inventory.getItem(String(srcSlot)) === original;
            if (rollbackComplete) slots[key] = oldRecord;
            return fail(rollbackComplete ? "commit_failed" : "rollback_failed");
        }

        custody.loadoutRevision = getLoadoutRevision(merc) + 1;
        markDirty();
        publishCommittedSlot(inventory, srcSlot, "replaced");
        return {
            success:true,
            operation:"replace",
            mercIndex:ctx.index,
            slotKey:key,
            sourceSlot:srcSlot,
            loadoutRevision:Number(custody.loadoutRevision)
        };
    }

    private static function withdrawInternal(mercIndex, mercId,
                                             slotKey, expectedLoadoutRevision):Object {
        var ctx:Object = validateWriteContext(mercIndex, mercId, slotKey,
            expectedLoadoutRevision);
        if (ctx.success !== true) return ctx;
        var merc:Array = ctx.merc;
        var slot:Number = ctx.slot;
        var custody:Object = readCustody(merc);
        if (custody == null) return fail("no_custody");
        if (!isHealthyCustody(custody)) return fail("custody_corrupt");
        var key:String = String(slot);
        var record:Object = custody.slots[key];
        if (record == null) return fail("no_custody");
        if (Number(record.version) != 1) return fail("custody_corrupt");

        var bag:ArrayInventory = _root.物品栏 == undefined ? null : _root.物品栏.背包;
        if (bag == null) return fail("inventory_unavailable");
        var vacancy:Number = bag.getFirstVacancy();
        if (isNaN(vacancy) || vacancy < 0) return fail("inventory_full");

        var restored:BaseItem = createRuntimeItem(slot, record.item);
        if (restored == null) return fail("custody_corrupt");

        if (!tryTransactionWrite(bag, vacancy, restored)) return fail("commit_failed");
        if (bag.getItem(String(vacancy)) !== restored) {
            var rollbackComplete:Boolean = tryTransactionWrite(bag, vacancy, null)
                && bag.getItem(String(vacancy)) == null;
            return fail(rollbackComplete ? "commit_failed" : "rollback_failed");
        }
        // 只有背包真实持有恢复对象后才清除托管记录，槽位自动回落预设。
        delete custody.slots[key];

        custody.loadoutRevision = getLoadoutRevision(merc) + 1;
        markDirty();
        publishCommittedSlot(bag, vacancy, "added");
        return {
            success:true,
            operation:"withdraw",
            mercIndex:ctx.index,
            slotKey:key,
            targetSlot:vacancy,
            loadoutRevision:Number(custody.loadoutRevision)
        };
    }

    /**
     * 写操作公共门（顺序即断言顺序）：mercIndex 合法 → 同伴数据存在 → mercId 匹配
     * → 槽位可写 → 非战斗地图 → 出战（1=merc_deployed）/阵亡（-1=merc_dead）
     * → loadoutRevision 乐观锁。lease 复证在各 Internal 内 policy 之前完成。
     */
    private static function validateWriteContext(mercIndex, mercId, slotKey,
                                                 expectedLoadoutRevision):Object {
        var index:Number = Number(mercIndex);
        if (isNaN(index) || index < 0) return fail("invalid_index");
        var merc:Array = _root.同伴数据 == undefined ? undefined : _root.同伴数据[index];
        if (merc == undefined || merc[0] == undefined) return fail("merc_not_found");
        if (String(merc[2]) != String(mercId)) return fail("merc_id_mismatch");
        if (!isWritableSlot(slotKey)) return fail("slot_locked");
        if (_root.当前为战斗地图 == true) return fail("combat_locked");
        var deployState:Number = _root.佣兵是否出战信息 == undefined
            ? 0 : (Number(_root.佣兵是否出战信息[index]) || 0);
        if (deployState == 1) return fail("merc_deployed");
        if (deployState == -1) return fail("merc_dead");
        if (Number(expectedLoadoutRevision) != getLoadoutRevision(merc)) {
            return fail("stale_state");
        }
        return {success:true, merc:merc, index:index, slot:Number(slotKey)};
    }

    // ═══════════════════════════════════════════════════════════
    // 托管域读写辅助
    // ═══════════════════════════════════════════════════════════

    private static function readCustody(merc:Array):Object {
        if (merc == undefined || merc.length < 20) return null;
        var meta:Object = merc[19];
        if (meta == undefined || typeof meta != "object") return null;
        var custody:Object = meta[CUSTODY_KEY];
        if (custody == undefined || typeof custody != "object") return null;
        return custody;
    }

    private static function ensureCustody(merc:Array):Object {
        var custody:Object = readCustody(merc);
        if (custody != null) return custody;
        var meta:Object = merc[19];
        if (meta == undefined || typeof meta != "object") {
            meta = {};
            merc[19] = meta;
        }
        custody = {version:1, loadoutRevision:0, slots:{}};
        meta[CUSTODY_KEY] = custody;
        return custody;
    }

    private static function isHealthyCustody(custody:Object):Boolean {
        return custody != null && Number(custody.version) == 1
            && custody.slots != undefined && typeof custody.slots == "object";
    }

    private static function readSlotRecord(merc:Array, slot:Number):Object {
        var custody:Object = readCustody(merc);
        if (custody == null) return null;
        var slots:Object = custody.slots;
        if (slots == undefined || typeof slots != "object") return null;
        var record:Object = slots[String(slot)];
        if (record == undefined || typeof record != "object") return null;
        return record;
    }

    private static function buildSlotProjection(merc:Array, slot:Number):Object {
        var view:Object = {
            state:"preset",
            preset:buildPresetProjection(merc, slot),
            custody:null
        };
        var record:Object = readSlotRecord(merc, slot);
        if (record != null) {
            var runtime:BaseItem = Number(record.version) == 1
                ? createRuntimeItem(slot, record.item) : null;
            if (runtime != null) {
                view.state = "custody";
                view.custody = buildItemBrief(runtime);
            } else {
                view.state = "custody_corrupt";
            }
        }
        return view;
    }

    /** 预设槽投影：应用默认强化度，与 MercPanelService.buildMercSummary 同口径。 */
    private static function buildPresetProjection(merc:Array, slot:Number):Object {
        var raw = merc == undefined ? undefined : merc[slot];
        if (raw == undefined || String(raw) == "" || String(raw) == "null") return null;
        var item:BaseItem = BaseItem.createFromString(String(raw));
        if (item == null) return null;
        var lvl:Number = (item.value != undefined && item.value.level > 1)
            ? Number(item.value.level)
            : DressupInitializer.getEquipmentDefaultLevel(Number(merc[0]), String(merc[1]));
        item.value.level = lvl;
        var calcData:Object = item.getData();
        return {
            name:String(item.name),
            displayname:(calcData && calcData.displayname)
                ? String(calcData.displayname) : String(item.name),
            icon:(calcData && calcData.icon) ? String(calcData.icon) : String(item.name),
            level:lvl,
            raw:String(raw)
        };
    }

    private static function buildItemBrief(item:BaseItem):Object {
        var data:Object = item.getData();
        var lvl:Number = item.value == undefined ? NaN : Number(item.value.level);
        if (isNaN(lvl) || lvl < 1) lvl = 1;
        return {
            name:String(item.name),
            displayname:(data && data.displayname)
                ? String(data.displayname) : String(item.name),
            icon:(data && data.icon) ? String(data.icon) : String(item.name),
            level:lvl
        };
    }

    private static function useMatchesSlot(useName:String, useKey:String):Boolean {
        return useName == useKey || (useKey == "手枪2" && useName == "手枪");
    }

    private static function markDirty():Void {
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
    }

    /** 领域写已完成；通知失败不得把已提交的所有权转移误报为失败。 */
    private static function publishCommittedSlot(inventory:ArrayInventory,
                                                 slot:Number,
                                                 changeKind:String):Void {
        try {
            InventoryPanelService.invalidateExternalSlot("背包", slot);
        } catch (invalidationError) {
            // authority 已提交；下一次 snapshot 会按 inventory revision 重建缓存。
        }
        var recoverDispatch:Function = EventBus.getInstance().createDispatchRecoveryToken();
        try {
            inventory.publishTransactionChange(slot, changeKind);
        } catch (publishError) {
            // authority 已提交；只回退本次通知留下的内层 dispatch 槽。
            // 令牌不会抬高 depth，也不会清空可能存在的外层事件快照。
            recoverDispatch();
        }
    }

    /**
     * ArrayInventory 会把提交内部异常原子回滚并返回 false；
     * 此边界再隔离一次未来实现可能逸出的异常，确保交付/替换可撤销
     * custody，取回则继续保留 custody，不暴露半份所有权转移。
     */
    private static function tryTransactionWrite(inventory:ArrayInventory,
                                                slot:Number,
                                                item:Object):Boolean {
        if (inventory == null) return false;
        try {
            return inventory.transactionWrite(slot, item) === true;
        } catch (commitError) {
            return false;
        }
    }

    private static function fail(code:String):Object {
        return {success:false, error:code};
    }
}
