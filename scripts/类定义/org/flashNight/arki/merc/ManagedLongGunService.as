import org.flashNight.arki.merc.*;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * 非主角托管长枪领域服务。
 *
 * 当前只登记 T800（petId=66），但所有权、冻结副本、库存 lease 与运行时克隆均集中在
 * 本服务，后续佣兵换装只需新增 policy，不应复制一套背包写入逻辑。
 *
 * 核心不变量：
 *  - 交付时从背包移除完整 BaseItem 存档快照；托管期间权威快照保持只读。
 *  - 出战单位始终持有快照克隆，射击、换弹与生命周期不得回写托管权威。
 *  - 取回时原样重建交付快照；不会把 AI 的免费换弹或武器被动收益带回背包。
 *  - 托管转移是所有权位置变化，不发布玩家资产 gain/loss 回执。
 */
class org.flashNight.arki.merc.ManagedLongGunService {
    private static var CUSTODY_KEY:String = "托管长枪";
    private static var DEFAULT_WEAPON:String = "L85A1";
    private static var T800_PET_ID:Number = 66;
    private static var _busy:Boolean = false;

    public static function isSupportedPet(petInfo:Array):Boolean {
        return petInfo != undefined && petInfo.length >= 5
            && Number(petInfo[0]) == T800_PET_ID;
    }

    public static function hasSupportedPet(pets:Array):Boolean {
        if (pets == undefined) return false;
        for (var i:Number = 0; i < pets.length; i++) {
            if (isSupportedPet(pets[i])) return true;
        }
        return false;
    }

    public static function hasCustody(petInfo:Array):Boolean {
        var attrs:Object = readAttrs(petInfo);
        var custody:Object = attrs == null ? null : attrs[CUSTODY_KEY];
        // 只要存在托管记录就不允许覆盖。未知版本或损坏记录必须
        // fail-closed，否则一次新交付会永久丢失旧快照的恢复机会。
        return custody != null;
    }

    public static function getRank(petInfo:Array):Number {
        var attrs:Object = readAttrs(petInfo);
        if (attrs != null && attrs.终结者全武装) return 2;
        if (attrs != null && attrs.终结者武器扩展) return 1;
        return 0;
    }

    public static function getWeaponLevelLimit(petInfo:Array):Number {
        var petLevel:Number = Math.max(1, Math.floor(Number(petInfo[1]) || 1));
        var rank:Number = getRank(petInfo);
        if (rank <= 0) return Math.min(15, petLevel);
        if (rank == 1) return Math.min(30, petLevel);
        return petLevel;
    }

    /** 纯 policy 入口，供资格投影和 TestLoader 使用。 */
    public static function evaluateDataForPet(petInfo:Array, data:Object):Object {
        if (!isSupportedPet(petInfo)) return fail("unsupported_pet");
        if (data == null || String(data.use) != "长枪") return fail("not_long_gun");

        var requirement:Number = data.data == undefined
            ? Number(data.level) : Number(data.data.level);
        if (isNaN(requirement) || !isFinite(requirement) || requirement < 1) {
            return fail("invalid_weapon_level");
        }
        requirement = Math.ceil(requirement);

        var rank:Number = getRank(petInfo);
        var subtype:String = data.weapontype == undefined
            ? String(data.weaponType == undefined ? "" : data.weaponType)
            : String(data.weapontype);
        if (rank == 0 && subtype != "冲锋枪" && subtype != "突击步枪") {
            return {
                success:false,
                error:"weapon_type_locked",
                requirementLevel:requirement,
                weaponType:subtype,
                rank:rank,
                levelLimit:getWeaponLevelLimit(petInfo)
            };
        }

        var levelLimit:Number = getWeaponLevelLimit(petInfo);
        if (requirement > levelLimit) {
            return {
                success:false,
                error:"weapon_level_locked",
                requirementLevel:requirement,
                weaponType:subtype,
                rank:rank,
                levelLimit:levelLimit
            };
        }
        return {
            success:true,
            requirementLevel:requirement,
            weaponType:subtype,
            rank:rank,
            levelLimit:levelLimit
        };
    }

    public static function evaluateItemForPet(petInfo:Array, item:Object):Object {
        if (item == null || typeof item.getData != "function"
                || typeof item.value != "object" || item.value == null) {
            return fail("invalid_weapon");
        }
        var data:Object = item.getData();
        if (data == null) return fail("invalid_weapon");
        return evaluateDataForPet(petInfo, data);
    }

    /** 构造单只宠物的安全 Web 投影；bagSnapshot 必须只生成一次后在同轮宠物间复用。 */
    public static function buildPanelState(petInfo:Array, bagSnapshot:Object):Object {
        if (!isSupportedPet(petInfo)) return null;
        var rank:Number = getRank(petInfo);
        var defaultWeaponItem:BaseItem = BaseItem.createFromString(DEFAULT_WEAPON);
        var defaultWeaponView:Object = defaultWeaponItem == null
            ? null : InventoryPanelService.buildItemProjection(defaultWeaponItem);
        var state:Object = {
            supported:true,
            rank:rank,
            rankLabel:rank == 0 ? "初始" : (rank == 1 ? "武器扩展" : "全武装"),
            levelLimit:getWeaponLevelLimit(petInfo),
            defaultWeapon:DEFAULT_WEAPON,
            defaultWeaponView:defaultWeaponView,
            combatLocked:_root.当前为战斗地图 == true,
            weapon:null,
            custodyCorrupt:false,
            candidates:[]
        };

        var attrs:Object = readAttrs(petInfo);
        var custody:Object = attrs == null ? null : attrs[CUSTODY_KEY];
        if (custody != null) {
            if (Number(custody.version) != 1 || custody.item == null) {
                state.custodyCorrupt = true;
                return state;
            }
            var runtime:BaseItem = createRuntimeWeapon(custody.item);
            if (runtime == null) {
                state.custodyCorrupt = true;
            } else {
                state.weapon = InventoryPanelService.buildItemProjection(runtime);
                if (state.weapon == null) state.custodyCorrupt = true;
                else {
                    state.weapon.frozenShot = readFrozenNumber(custody.item, "shot");
                    state.weapon.frozenSubweaponShot = readFrozenNumber(custody.item, "subweaponShot");
                }
            }
            return state;
        }

        if (bagSnapshot == null || !(bagSnapshot.slots instanceof Array)) return state;
        var bag:ArrayInventory = _root.物品栏 == undefined ? null : _root.物品栏.背包;
        if (bag == null) return state;
        for (var i:Number = 0; i < bagSnapshot.slots.length; i++) {
            var slotView:Object = bagSnapshot.slots[i];
            if (slotView == null || !slotView.occupied || slotView.item == null) continue;
            var item:Object = bag.getItem(String(slotView.physicalSlot));
            var check:Object = evaluateItemForPet(petInfo, item);
            // 面板只展示长枪；其它背包物品不需要把“不兼容”噪声带进战宠页。
            var itemUse:String = slotView.item.use == undefined ? "" : String(slotView.item.use);
            if (itemUse != "长枪") continue;
            state.candidates.push({
                source:{
                    containerId:"背包",
                    slot:Number(slotView.physicalSlot),
                    expectedLease:String(slotView.slotLease)
                },
                item:slotView.item,
                eligible:check.success === true,
                lockReason:check.success === true ? "" : String(check.error),
                requirementLevel:Number(check.requirementLevel),
                levelLimit:Number(check.levelLimit)
            });
        }
        return state;
    }

    /**
     * 为战宠面板生成当前托管/预设武器或 lease-bound 背包候选的完整物品注释。
     * source 为空时只从宠物托管权威解析；候选则重新验证当前背包 lease，绝不按名称猜测实例属性。
     */
    public static function buildWeaponTooltip(petInfo:Array, source:Object):Object {
        if (!isSupportedPet(petInfo)) return fail("unsupported_pet");

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
            if (data == null || String(data.use) != "长枪") return fail("not_long_gun");
        } else {
            var attrs:Object = readAttrs(petInfo);
            var custody:Object = attrs == null ? null : attrs[CUSTODY_KEY];
            if (custody != null) {
                if (Number(custody.version) != 1) return fail("custody_corrupt");
                item = createRuntimeWeapon(custody.item);
                if (item == null) return fail("custody_corrupt");
            } else {
                item = BaseItem.createFromString(DEFAULT_WEAPON);
                if (item == null) return fail("item_data_missing");
            }
        }
        return InventoryPanelService.buildTooltipProjection(item);
    }

    public static function handoff(petInfo:Array, source:Object):Object {
        if (_busy) return fail("busy");
        _busy = true;
        var result:Object = handoffInternal(petInfo, source);
        _busy = false;
        return result;
    }

    private static function handoffInternal(petInfo:Array, source:Object):Object {
        if (!isSupportedPet(petInfo)) return fail("unsupported_pet");
        if (_root.当前为战斗地图 == true) return fail("combat_locked");
        if (hasCustody(petInfo)) return fail("weapon_already_managed");

        var checked:Object = InventoryPanelService.validateExternalSlotRef(source, false);
        if (checked == null || checked.success !== true) {
            return checked == null ? fail("stale_state") : checked;
        }
        if (String(checked.containerId) != "背包") return fail("unsupported_container");
        var eligibility:Object = evaluateItemForPet(petInfo, checked.item);
        if (eligibility.success !== true) return eligibility;

        var frozen:Object = freezeItem(checked.item);
        if (frozen == null || createRuntimeWeapon(frozen) == null) return fail("invalid_weapon");
        var inventory:ArrayInventory = checked.inventory;
        var slot:Number = Number(checked.slot);
        var original:Object = checked.item;

        // 先把冻结权威放入宠物域，再在同一同步调用栈内移除背包原物。
        // 写失败时撤销未生效的托管记录，不会发布任何中间态事件。
        var attrs:Object = ensureAttrs(petInfo);
        attrs[CUSTODY_KEY] = {version:1, item:frozen};
        if (!inventory.transactionWrite(slot, null)) {
            delete attrs[CUSTODY_KEY];
            return fail("commit_failed");
        }
        if (inventory.getItem(String(slot)) != null) {
            var rollbackComplete:Boolean = inventory.transactionWrite(slot, original)
                && inventory.getItem(String(slot)) === original;
            if (rollbackComplete) delete attrs[CUSTODY_KEY];
            return fail(rollbackComplete ? "commit_failed" : "rollback_failed");
        }

        markDirty();
        publishCommittedSlot(inventory, slot, "removed");
        return {success:true, operation:"handoff", sourceSlot:slot};
    }

    /** 删除战宠前的无副作用预检；满包或损坏快照时必须在任何删除/返还写入前失败。 */
    public static function preflightWithdrawal(petInfo:Array):Object {
        if (!hasCustody(petInfo)) return {success:true, required:false};
        // 任何带托管字段但尚未登记 policy 的单位都必须失败关闭，不能借删除路径丢失物品。
        if (!isSupportedPet(petInfo)) return fail("unsupported_pet");
        var attrs:Object = readAttrs(petInfo);
        var custody:Object = attrs == null ? null : attrs[CUSTODY_KEY];
        if (custody == null || Number(custody.version) != 1
                || createRuntimeWeapon(custody.item) == null) {
            return fail("custody_corrupt");
        }
        var bag:ArrayInventory = _root.物品栏 == undefined ? null : _root.物品栏.背包;
        if (bag == null) return fail("inventory_unavailable");
        var vacancy:Number = bag.getFirstVacancy();
        if (isNaN(vacancy) || vacancy < 0) return fail("inventory_full");
        return {success:true, required:true, slot:vacancy};
    }

    public static function withdraw(petInfo:Array):Object {
        if (_busy) return fail("busy");
        _busy = true;
        var result:Object = withdrawInternal(petInfo);
        _busy = false;
        return result;
    }

    private static function withdrawInternal(petInfo:Array):Object {
        if (!isSupportedPet(petInfo)) return fail("unsupported_pet");
        if (_root.当前为战斗地图 == true) return fail("combat_locked");
        if (!hasCustody(petInfo)) return fail("no_managed_weapon");
        var preflight:Object = preflightWithdrawal(petInfo);
        if (preflight.success !== true) return preflight;

        var attrs:Object = readAttrs(petInfo);
        var custody:Object = attrs[CUSTODY_KEY];
        if (Number(custody.version) != 1) return fail("custody_corrupt");
        var frozen:Object = custody.item;
        var restored:BaseItem = createRuntimeWeapon(frozen);
        if (restored == null) return fail("custody_corrupt");
        var weaponProjection:Object = InventoryPanelService.buildItemProjection(restored);
        if (weaponProjection == null) return fail("custody_corrupt");
        var bag:ArrayInventory = _root.物品栏.背包;
        var slot:Number = Number(preflight.slot);
        if (!bag.transactionWrite(slot, restored)) return fail("commit_failed");
        if (bag.getItem(String(slot)) !== restored) {
            var rollbackComplete:Boolean = bag.transactionWrite(slot, null)
                && bag.getItem(String(slot)) == null;
            return fail(rollbackComplete ? "commit_failed" : "rollback_failed");
        }
        // 只有背包真实持有恢复对象后才清除托管权威。
        delete attrs[CUSTODY_KEY];
        markDirty();
        publishCommittedSlot(bag, slot, "added");
        return {
            success:true,
            operation:"withdraw",
            targetSlot:slot,
            weapon:weaponProjection
        };
    }

    /** T800 根时间轴在初始化敌人模板之前调用。 */
    public static function prepareUnit(target:Object):Void {
        if (target == null) return;

        // 普通敌人模板不会像人形模板那样挂接换装所需的战技/生命周期入口。
        // DressupInitializer 会先调用 装载主动战技，再调用 装载生命周期函数；任一入口
        // 缺失都会让初始化在装备数据与基础射击已就绪后中断，于是白板枪能开火，M134
        // 枪管、XM214 变速/光效等 lifecycle 却从未注册。这里只给明确调用本服务的
        // T800 补齐成熟的人形组件入口，不修改全局敌人模板，也不覆盖素材自带实现。
        installDressupLifecycleBridge(target);

        var attrs:Object = target.宠物属性;
        var isManagedPet:Boolean = attrs != null && target.是否为敌人 == false
            && Number(attrs.宠物库数组号) == T800_PET_ID;
        var custody:Object = attrs == null ? null : attrs[CUSTODY_KEY];
        var runtime:BaseItem = !isManagedPet || custody == null || Number(custody.version) != 1
            ? null : createRuntimeWeapon(custody.item);
        if (runtime != null) {
            target.长枪 = runtime;
            target.使用托管长枪 = true;
            target.攻击模式 = "长枪";
            target.enableShoot = true;
        } else {
            target.使用托管长枪 = false;
            if (isManagedPet) {
                target.长枪 = DEFAULT_WEAPON;
                target.攻击模式 = "长枪";
                target.enableShoot = true;
            } else if (isValidExplicitLongGun(target.长枪)) {
                // 普通敌人继续使用关卡/units.json 显式配置且能被现役物品表解析的长枪。
                // 旧数据中的“随机长枪”从未有对应物品或解析器，不能把这个失效占位
                // 误判成可射击状态，否则 DressupInitializer 会清空武器、Shoot 仍被启动。
                target.攻击模式 = "长枪";
                target.enableShoot = true;
            } else {
                // 非战宠 T800 未配置武器时只走原近战动作，不凭空生成默认枪。
                target.长枪 = null;
                target.攻击模式 = "空手";
                target.enableShoot = false;
            }
            if (isManagedPet && custody != null) target.托管长枪异常 = true;
        }

        // 复合刀枪与自动时间轴技能必须由单位显式声明；T800 只提供纯长枪能力。
        if (target.装备能力 == undefined || target.装备能力 == null) target.装备能力 = {};
        target.装备能力.复合枪械 = false;
        target.装备能力.自动抡枪 = false;
    }

    private static function installDressupLifecycleBridge(target:Object):Void {
        var shared:Object = _root.主角函数;
        if (shared == null) return;
        if (typeof target.装载主动战技 != "function"
                && typeof shared.装载主动战技 == "function") {
            target.装载主动战技 = shared.装载主动战技;
        }
        if (typeof target.装载副武器控制槽 != "function"
                && typeof shared.装载副武器控制槽 == "function") {
            target.装载副武器控制槽 = shared.装载副武器控制槽;
        }
        if (typeof target.装载生命周期函数 != "function"
                && typeof shared.装载生命周期函数 == "function") {
            target.装载生命周期函数 = shared.装载生命周期函数;
        }
        if (typeof target.完成生命周期函数装载 != "function"
                && typeof shared.完成生命周期函数装载 == "function") {
            target.完成生命周期函数装载 = shared.完成生命周期函数装载;
        }
    }

    private static function isValidExplicitLongGun(value):Boolean {
        if (value == undefined || value == null || String(value) == "") return false;
        var item:Object = value;
        if (typeof value == "string") item = BaseItem.createFromString(String(value));
        if (item == null || typeof item.getData != "function") return false;
        var data:Object = item.getData();
        return data != null && String(data.use) == "长枪";
    }

    /** 每次都深克隆，避免 BaseItem.createFromObject 对 mods 归一化时触及冻结权威。 */
    public static function createRuntimeWeapon(frozen:Object):BaseItem {
        if (frozen == null) return null;
        var clone:Object = ObjectUtil.clone(frozen);
        var item:BaseItem = clone == null ? null : BaseItem.createFromObject(clone);
        if (item == null) return null;
        // 不能只验证“仍是有效物品”：损坏/手改存档可能把 version=1 快照替换成
        // 手枪或防具。托管域与 T800 Shoot 运行态都必须再次确认 use=长枪。
        var data:Object = item.getData();
        return data != null && String(data.use) == "长枪" ? item : null;
    }

    public static function freezeItem(item:Object):Object {
        if (item == null || typeof item.toObject != "function") return null;
        var frozen:Object = item.toObject();
        if (frozen == null || typeof frozen.value != "object" || frozen.value == null) return null;
        return ObjectUtil.clone(frozen);
    }

    private static function readFrozenNumber(frozen:Object, key:String) {
        if (frozen == null || frozen.value == null || frozen.value[key] == undefined) return null;
        var value:Number = Number(frozen.value[key]);
        return isNaN(value) ? null : value;
    }

    private static function readAttrs(petInfo:Array):Object {
        if (petInfo == undefined || petInfo.length < 6
                || petInfo[5] == undefined || typeof petInfo[5] != "object") return null;
        return petInfo[5];
    }

    private static function ensureAttrs(petInfo:Array):Object {
        var attrs:Object = readAttrs(petInfo);
        if (attrs == null) {
            attrs = {};
            petInfo[5] = attrs;
        }
        return attrs;
    }

    private static function markDirty():Void {
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
    }

    /** 领域写已完成；通知失败不得把已提交的所有权转移误报为失败。 */
    private static function publishCommittedSlot(inventory:ArrayInventory,
                                                  slot:Number,
                                                  changeKind:String):Void {
        InventoryPanelService.invalidateExternalSlot("背包", slot);
        inventory.publishTransactionChange(slot, changeKind);
    }

    private static function fail(code:String):Object {
        return {success:false, error:code};
    }
}
