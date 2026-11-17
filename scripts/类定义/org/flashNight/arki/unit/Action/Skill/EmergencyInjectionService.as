import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.unit.Action.Skill.EmergencyInjector;

/** 61系胸甲实例持有的应急药剂授权；仅穿戴统合/钛合金61式胸甲时激活，原槽亲和不等于自动用药授权。 */
class org.flashNight.arki.unit.Action.Skill.EmergencyInjectionService {
    public static var VERSION:Number = 1;
    public static var TRIGGER_RATIO:Number = 0.5;
    public static var RESET_RATIO:Number = 0.7;

    public static function supportsItemName(name:String):Boolean {
        return name == "统合61式胸甲" || name == "钛合金61式胸甲";
    }

    public static function wornChestItem(root:Object):Object {
        if (!root || !root.物品栏 || !root.物品栏.装备栏) return null;
        return root.物品栏.装备栏.getItem("上装装备");
    }

    /** 只由读档/建角的既有输入会话边界调用，过图和换装不清危机。 */
    public static function resetSession(root:Object):Void {
        delete root.__emergencyInjectionMemory;
    }

    public static function readValue(value:Object):Object {
        var saved:Object = value == undefined || value == null ? undefined : value.emergencyInjection;
        if (saved == undefined) return {version:VERSION, enabled:false, physicalSlot:-1, itemKey:""};
        if (typeof saved != "object" || saved == null
                || saved.version !== VERSION || typeof saved.enabled != "boolean"
                || typeof saved.physicalSlot != "number" || !isFinite(saved.physicalSlot)
                || saved.physicalSlot != Math.floor(saved.physicalSlot)
                || saved.physicalSlot < -1 || saved.physicalSlot > 7
                || typeof saved.itemKey != "string" || length(saved.itemKey) > 160
                || (saved.enabled ? (saved.physicalSlot < 0 || saved.itemKey == "")
                    : (saved.physicalSlot !== -1 || saved.itemKey != ""))) return null;
        return saved;
    }

    public static function readItem(item:Object):Object {
        if (!item || !supportsItemName(String(item.name))
                || typeof item.value != "object" || item.value == null) return null;
        return readValue(item.value);
    }

    public static function read(root:Object):Object {
        var chest:Object = wornChestItem(root);
        if (!chest || !supportsItemName(String(chest.name))) {
            return {version:VERSION, enabled:false, physicalSlot:-1, itemKey:""};
        }
        return readItem(chest);
    }

    public static function snapshotValue(itemName:String, value:Object, root:Object):Object {
        if (!supportsItemName(itemName) || typeof value != "object" || value == null) {
            return {v:VERSION, enabled:false, physicalSlot:-1, itemKey:"", status:"unsupported_config"};
        }
        var config:Object = readValue(value);
        if (!config) return {v:VERSION, enabled:false, physicalSlot:-1, itemKey:"", status:"unsupported_config"};
        if (config.__invalidated === true) return {v:VERSION, enabled:false, physicalSlot:-1, itemKey:"", status:"disabled"};
        var status:String = "disabled";
        if (config.enabled) {
            var item:Object = root && root.物品栏 && root.物品栏.药剂栏
                ? root.物品栏.药剂栏.getItem(String(config.physicalSlot)) : null;
            status = item == null ? "empty" : String(item.name) == config.itemKey ? "authorized" : "item_changed";
        }
        return {v:VERSION, enabled:config.enabled, physicalSlot:config.physicalSlot,
            itemKey:config.itemKey, status:status};
    }

    public static function snapshotItem(item:Object, root:Object):Object {
        if (!item) return {v:VERSION, enabled:false, physicalSlot:-1, itemKey:"", status:"unsupported_config"};
        return snapshotValue(String(item.name), item.value, root);
    }

    public static function snapshot(root:Object):Object {
        var chest:Object = wornChestItem(root);
        if (!chest || !supportsItemName(String(chest.name))) {
            return {v:VERSION, enabled:false, physicalSlot:-1, itemKey:"", status:"disabled"};
        }
        return snapshotItem(chest, root);
    }

    /** 配置写由面板会话提供目标61胸甲实例、玩家、槽位和预期物品名，不消费药剂。 */
    public static function authorizeItem(root:Object, unit:Object, chestItem:Object,
                                         physicalSlot:Number, expectedName:String,
                                         enabled:Boolean):Object {
        if (!chestItem || !supportsItemName(String(chestItem.name))) {
            return {success:false, error:"incompatible_item"};
        }
        if (!readItem(chestItem)) return {success:false, error:"unsupported_config"};
        if (typeof enabled != "boolean") return {success:false, error:"invalid_authorization"};
        if (!root || !root.存档系统 || !unit) return {success:false, error:"service_not_ready"};
        var config:Object = {version:VERSION, enabled:enabled, physicalSlot:-1, itemKey:""};
        if (enabled) {
            if (!isFinite(physicalSlot) || physicalSlot != Math.floor(physicalSlot)
                    || physicalSlot < 0 || physicalSlot > 7 || typeof expectedName != "string"
                    || length(expectedName) < 1 || length(expectedName) > 160) {
                return {success:false, error:"invalid_authorization"};
            }
            var item:Object = root.物品栏.药剂栏.getItem(String(physicalSlot));
            if (!item || item.name !== expectedName || typeof item.value != "number"
                    || !isFinite(item.value) || !(item.value > 0)) return {success:false, error:"stale_source"};
            var data:Object = root.getItemData(expectedName);
            if (data.use != "药剂") return {success:false, error:"invalid_drug"};
            config.physicalSlot = physicalSlot;
            config.itemKey = expectedName;
        }
        PlayerAssetTransaction.markDirtyRequired(root.存档系统);
        chestItem.value.emergencyInjection = config;
        observeInventory(root);
        if (wornChestItem(root) === chestItem) {
            var provider:Object = unit.__emergencyInjectionProvider;
            if (provider) refresh(unit, provider, root);
        }
        return {success:true, emergencyInjection:snapshotItem(chestItem, root)};
    }

    public static function authorize(root:Object, unit:Object, physicalSlot:Number,
                                     expectedName:String, enabled:Boolean):Object {
        var chest:Object = wornChestItem(root);
        if (!chest || !supportsItemName(String(chest.name))) {
            return {success:false, error:"incompatible_item"};
        }
        return authorizeItem(root, unit, chest, physicalSlot, expectedName, enabled);
    }

    /** 单一库存观察者跟随当前穿戴的61胸甲；换物后立即撤销授权，同名耗尽/补充保持授权。 */
    public static function observeInventory(root:Object):Void {
        var chest:Object = wornChestItem(root);
        var config:Object = read(root);
        var watch:Object = root.__emergencyInjectionInventoryWatch;
        var inventory:Object = root.物品栏.药剂栏;
        var dispatcher:Object = inventory.getDispatcher();
        if (watch && (watch.inventory !== inventory || watch.chest !== chest || !config || !config.enabled
                || watch.feature !== config || (!watch.direct && watch.dispatcher !== dispatcher))) {
            if (watch.direct) watch.inventory.unbindSlotChangeObserver(watch);
            else {
                watch.dispatcher.unsubscribe("ItemAdded", watch.handler, watch);
                watch.dispatcher.unsubscribe("ItemRemoved", watch.handler, watch);
                watch.dispatcher.unsubscribe("ItemValueChanged", watch.handler, watch);
            }
            delete root.__emergencyInjectionInventoryWatch;
            watch = null;
        }
        if (!chest || !supportsItemName(String(chest.name)) || !config || !config.enabled || !inventory) return;
        try {
            invalidateChangedItem(root, inventory, config);
        } catch (authorizationWriteError) {
            config.__invalidated = true;
            trace("[EmergencyInjection] authorization persistence unavailable: " + authorizationWriteError);
            return;
        }
        if (!config.enabled || watch) return;
        var direct:Boolean = typeof inventory.bindSlotChangeObserver == "function";
        if (!direct && !dispatcher) return;
        watch = {root:root, inventory:inventory, chest:chest, feature:config, dispatcher:dispatcher};
        watch.direct = direct;
        watch.handler = function(source:Object, key:String):Void {
            if (source !== this.inventory || this.root.物品栏.药剂栏 !== source
                    || EmergencyInjectionService.wornChestItem(this.root) !== this.chest
                    || EmergencyInjectionService.read(this.root) !== this.feature) return;
            try {
                EmergencyInjectionService.invalidateChangedItem(this.root, source, this.feature);
            } catch (authorizationError) {
                // 不让配置写异常遮盖库存原提交；内存失效保持关闭，下一次维护只重试记脏。
                this.feature.__invalidated = true;
                trace("[EmergencyInjection] authorization invalidation: " + authorizationError);
            }
        };
        if (direct) {
            if (!inventory.bindSlotChangeObserver(watch.handler, watch)) {
                config.__invalidated = true;
                try { invalidateChangedItem(root, inventory, config); } catch (observerError) {}
                return;
            }
        } else {
            dispatcher.subscribe("ItemAdded", watch.handler, watch);
            dispatcher.subscribe("ItemRemoved", watch.handler, watch);
            dispatcher.subscribe("ItemValueChanged", watch.handler, watch);
        }
        root.__emergencyInjectionInventoryWatch = watch;
    }

    public static function invalidateChangedItem(root:Object, inventory:Object, config:Object):Void {
        var item:Object = inventory.getItem(String(config.physicalSlot));
        if (config.__invalidated === true || (item && item.name !== config.itemKey)) {
            config.__invalidated = true;
            PlayerAssetTransaction.markDirtyRequired(root.存档系统);
            config.enabled = false;
            config.physicalSlot = -1;
            config.itemKey = "";
            delete config.__invalidated;
        }
    }

    /** 两个套装入口仅登记provider；未授权或换下61胸甲时不安装HP访问器。 */
    public static function refresh(unit:Object, provider:Object, root:Object):Void {
        unit.__emergencyInjectionProvider = provider;
        observeInventory(root);
        var context:EmergencyInjector = unit.__emergencyInjector;
        var config:Object = read(root);
        if (!config || !config.enabled || config.__invalidated === true
                || root.当前玩家总数 != 1 || root.gameworld[root.控制目标] !== unit) {
            if (context) context.dispose();
            return;
        }
        if (context && context.matches(provider, config, root)) return;
        if (context) context.dispose();
        var next:EmergencyInjector = new EmergencyInjector(unit, provider, config, root);
        next.install();
    }

    public static function release(unit:Object, provider:Object):Void {
        if (unit.__emergencyInjectionProvider !== provider) return;
        var context:EmergencyInjector = unit.__emergencyInjector;
        if (context) context.dispose();
        delete unit.__emergencyInjectionProvider;
    }
}
