import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.unit.Action.Skill.EmergencyInjector;

/** 61系共用的玩家药剂授权；原槽亲和不等于自动用药授权。 */
class org.flashNight.arki.unit.Action.Skill.EmergencyInjectionService {
    public static var VERSION:Number = 1;
    public static var TRIGGER_RATIO:Number = 0.5;
    public static var RESET_RATIO:Number = 0.7;

    /** 只由读档/建角的既有输入会话边界调用，过图和换装不清危机。 */
    public static function resetSession(root:Object):Void {
        delete root.__emergencyInjectionMemory;
    }

    public static function read(root:Object):Object {
        var saved:Object = root._saveExt.emergencyInjection;
        if (saved == undefined) return {version:VERSION, enabled:false, physicalSlot:-1, itemKey:""};
        if (saved.version !== VERSION || typeof saved.enabled != "boolean"
                || typeof saved.physicalSlot != "number" || !isFinite(saved.physicalSlot)
                || saved.physicalSlot != Math.floor(saved.physicalSlot)
                || saved.physicalSlot < -1 || saved.physicalSlot > 7
                || typeof saved.itemKey != "string" || length(saved.itemKey) > 160
                || (saved.enabled && (saved.physicalSlot < 0 || saved.itemKey == ""))) return null;
        return saved;
    }

    public static function snapshot(root:Object):Object {
        var config:Object = read(root);
        if (!config) return {v:VERSION, enabled:false, physicalSlot:-1, itemKey:"", status:"unsupported_config"};
        if (config.__invalidated === true) return {v:VERSION, enabled:false, physicalSlot:-1, itemKey:"", status:"disabled"};
        var status:String = "disabled";
        if (config.enabled) {
            var item:Object = root.物品栏.药剂栏.getItem(String(config.physicalSlot));
            status = item == null ? "empty" : String(item.name) == config.itemKey ? "authorized" : "item_changed";
        }
        return {v:VERSION, enabled:config.enabled, physicalSlot:config.physicalSlot,
            itemKey:config.itemKey, status:status};
    }

    /** 配置写由面板会话提供当前玩家、槽位和预期物品名，不消费药剂。 */
    public static function authorize(root:Object, unit:Object, physicalSlot:Number,
                                     expectedName:String, enabled:Boolean):Object {
        if (!read(root)) return {success:false, error:"unsupported_config"};
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
        if (!root._saveExt) root._saveExt = {};
        root._saveExt.emergencyInjection = config;
        observeInventory(root);
        var provider:Object = unit.__emergencyInjectionProvider;
        if (provider) refresh(unit, provider, root);
        return {success:true, emergencyInjection:snapshot(root)};
    }

    /** 单一库存观察者跨套装存活；换物后立即撤销授权，同名耗尽/补充保持授权。 */
    public static function observeInventory(root:Object):Void {
        var config:Object = read(root);
        var watch:Object = root.__emergencyInjectionInventoryWatch;
        var inventory:Object = root.物品栏.药剂栏;
        var dispatcher:Object = inventory.getDispatcher();
        if (watch && (watch.inventory !== inventory || !config || !config.enabled
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
        if (!config || !config.enabled || !inventory) return;
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
        watch = {root:root, inventory:inventory, feature:config, dispatcher:dispatcher};
        watch.direct = direct;
        watch.handler = function(source:Object, key:String):Void {
            if (source !== this.inventory || this.root.物品栏.药剂栏 !== source
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

    /** 两个套装入口仅登记provider；未授权时不安装HP访问器。 */
    public static function refresh(unit:Object, provider:Object, root:Object):Void {
        unit.__emergencyInjectionProvider = provider;
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
