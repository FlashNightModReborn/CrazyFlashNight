_root.preloaders.push(function()
{
    this.shops_jsons_list = new XML();
    this.shops_jsons_list.ignoreWhite = true;
    this.shops_strarrs = [];
    this.shops_jsons_list.onLoad = function(success)
    {
        var files = [];
        _root.XmlNodeToDict(this.lastChild,null,function(name, value)
        {
            if(name == "shops")
            {
                files.push(value);
            }
            return null;
        });
        for (var i = 0; i < files.length; i++)
        {
            _root.preloaders.shops_strarrs.push([]);
            _root.GetFileByPath("data/shops/" + files[i], _root.preloaders.shops_strarrs[i]);
        }
    };

    this.shops_jsons_list.load("data/shops/list.xml");
})

_root.loaders.push(function ()
{
    this.shops_srcs = [];
    this.shops = {};
    this.shopLayouts = {};
    this.json_parser = new LiteJSON();

    for (var i = 0; i < _root.preloaders.shops_strarrs.length; i++)
    {
        this.shops_srcs.push(_root.preloaders.shops_strarrs[i].join(""));
    }

    for (var i = 0; i < this.shops_srcs.length; i++)
    {
        this.parsedshop = this.json_parser.parse(this.shops_srcs[i]);
        if (this.parsedshop.schema == "npc-shop.v2" && this.parsedshop.shopId != undefined)
        {
            var shopId:String = String(this.parsedshop.shopId);
            this.shops[shopId] = this.parsedshop.catalog || {};
            this.shopLayouts[shopId] = {
                title:this.parsedshop.title == undefined ? shopId : String(this.parsedshop.title),
                defaultSection:this.parsedshop.defaultSection == undefined ? "" : String(this.parsedshop.defaultSection),
                sections:this.parsedshop.sections instanceof Array ? this.parsedshop.sections : []
            };
        }
        else
        {
            for (var key in this.parsedshop)
            {
                this.shops[key] = this.parsedshop[key];
            }
        }
    }

    _root.shops = this.shops;
    _root.shopLayouts = this.shopLayouts;
});

// ============================================================
// NPC 金币商店 Web Panel 权威服务
// ============================================================
// 目录仍以 data/shops/*.json → _root.shops 为唯一来源；Web 只提交 shopId、目录位置与
// 数量。价格、情报门槛、口才倍率、真实落点、出售收益和批售计划全部在 AS2 重算。
_root.UI系统 = _root.UI系统 || {};
_root.UI系统.NPC商店WebView = _root.UI系统.NPC商店WebView || {};
_root.UI系统.NPC商店WebView.json = new LiteJSON();
_root.UI系统.NPC商店WebView.busy = false;
_root.UI系统.NPC商店WebView.sessionSeq = 0;
_root.UI系统.NPC商店WebView.leaseSeq = 0;
_root.UI系统.NPC商店WebView.collectionLeases = {};
_root.UI系统.NPC商店WebView.batchSeq = 0;
_root.UI系统.NPC商店WebView.batchPlan = null;
_root.UI系统.NPC商店WebView.tradeSeq = 0;
_root.UI系统.NPC商店WebView.tradePlan = null;
_root.UI系统.NPC商店WebView.activeShopId = "";

// 兼容仍只持有目录对象的旧 Flash 入口。地图 NPC 初始化会把
// _root.shops[shopId] 的对象引用直接挂到 NPC.物品栏，因此可以用引用反查，
// 无需按目录内容猜测或在 Web/C# 复制商店数据。
_root.UI系统.NPC商店WebView.resolveShopIdByCatalog = function(catalog:Object):String {
    if (catalog == undefined || _root.shops == undefined) return "";
    for (var shopId in _root.shops) {
        if (_root.shops[shopId] === catalog) return String(shopId);
    }
    return "";
};

_root.UI系统.NPC商店WebView.fail = function(errorCode:String):Object {
    return {success:false, error:errorCode};
};

_root.UI系统.NPC商店WebView.log = function(message:String):Void {
    if (_root.server != undefined && _root.server.sendServerMessage != undefined) {
        _root.server.sendServerMessage("[NpcShopWV] " + message);
    }
};

_root.UI系统.NPC商店WebView.sendResponse = function(response:Object):Boolean {
    if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return false;
    // 商城 WebView 的 LiteJSON 出口已在生产链长期使用；NPC 商店复用它，避免维护第二个
    // 运行时序列化实例。初始化顺序异常时才回退本服务自有实例。
    var serializer:Object = _root.UI系统.商城WebView == undefined
        ? this.json : _root.UI系统.商城WebView.json;
    if (serializer == undefined || serializer.stringify == undefined) return false;
    var payload:String = serializer.stringify(response);
    if (payload == undefined || payload == "") {
        if (_root.server.sendServerMessage != undefined) {
            _root.server.sendServerMessage("[NpcShopWV] response stringify failed");
        }
        return false;
    }
    return _root.server.sendSocketMessage(payload);
};

_root.UI系统.NPC商店WebView.isWholeNumber = function(value):Boolean {
    var numberValue:Number = Number(value);
    return !isNaN(numberValue) && numberValue >= 0 && Math.floor(numberValue) == numberValue;
};

_root.UI系统.NPC商店WebView.beginCollectionSession = function(shopId:String):Void {
    this.sessionSeq++;
    this.leaseSeq = 0;
    this.sessionNonce = "npc" + getTimer() + "." + this.sessionSeq;
    this.activeShopId = shopId;
    this.collectionLeases = {};
    this.batchPlan = null;
    this.tradePlan = null;
};

_root.UI系统.NPC商店WebView.issueCollectionLease = function(viewId:String, key:String, count:Number):String {
    this.leaseSeq++;
    var token:String = this.sessionNonce + ".c" + this.leaseSeq;
    this.collectionLeases[token] = {viewId:viewId, key:key, count:Number(count)};
    return token;
};

_root.UI系统.NPC商店WebView.getBuyMultiplier = function():Number {
    var multiplier:Number = 1;
    if (_root.主角被动技能 != undefined && _root.主角被动技能.口才 != undefined
            && _root.主角被动技能.口才.启用) {
        multiplier = 1 - Number(_root.主角被动技能.口才.等级) * 0.03;
    }
    return multiplier;
};

_root.UI系统.NPC商店WebView.resolveSaleEntry = function(shopId:String, catalogIndex:Number):Object {
    var shop:Object = _root.shops == undefined ? null : _root.shops[shopId];
    if (shop == null) return null;
    var entry = shop[String(catalogIndex)];
    if (entry == undefined) entry = shop[catalogIndex];
    if (entry == undefined) return null;
    var itemName:String = typeof entry == "string" ? String(entry) : String(entry.name);
    if (!org.flashNight.arki.item.ItemUtil.isItem(itemName)) return null;
    return {raw:entry, itemName:itemName};
};

_root.UI系统.NPC商店WebView.getPurchaseLimit = function(resolved:Object):Number {
    var fallback:Number = org.flashNight.arki.item.ItemUtil.isEquipment(resolved.itemName) ? 50 : 100;
    var raw:Object = resolved.raw;
    if (typeof raw == "string" || raw.purchaseLimit == undefined) return fallback;
    var configured:Number = Number(raw.purchaseLimit);
    if (isNaN(configured) || Math.floor(configured) != configured || configured < 1) return fallback;
    return Math.min(100, configured);
};

_root.UI系统.NPC商店WebView.buildCatalog = function(shopId:String):Array {
    var result:Array = [];
    var shop:Object = _root.shops == undefined ? null : _root.shops[shopId];
    if (shop == null) return result;
    var keys:Array = [];
    for (var key in shop) {
        var index:Number = Number(key);
        if (!isNaN(index) && Math.floor(index) == index && index >= 0) keys.push(index);
    }
    keys.sort(Array.NUMERIC);
    var multiplier:Number = this.getBuyMultiplier();
    for (var i:Number = 0; i < keys.length; i++) {
        var resolved:Object = this.resolveSaleEntry(shopId, keys[i]);
        if (resolved == null) continue;
        var raw:Object = resolved.raw;
        var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(resolved.itemName);
        if (itemData == null) continue;
        var requiredInfo:String = typeof raw == "string" || raw.requiredInfo == undefined
            ? "" : String(raw.requiredInfo);
        var locked:Boolean = requiredInfo != ""
            && (_root.收集品栏 == undefined || _root.收集品栏.情报 == undefined
                || _root.收集品栏.情报.getValue(requiredInfo) <= 0);
        var basePrice:Number = Number(itemData.price);
        if (isNaN(basePrice)) basePrice = 0;
        result.push({
            catalogIndex:keys[i],
            itemName:resolved.itemName,
            displayName:String(itemData.displayname || resolved.itemName),
            icon:String(itemData.icon || resolved.itemName),
            majorType:String(itemData.type || ""),
            use:String(itemData.use || ""),
            actionType:String(itemData.actiontype || ""),
            weaponType:String(itemData.weapontype || ""),
            basePrice:basePrice,
            unitPrice:Math.floor(basePrice * multiplier),
            maxQuantity:this.getPurchaseLimit(resolved),
            requiredInfo:requiredInfo,
            locked:locked
        });
    }
    return result;
};

_root.UI系统.NPC商店WebView.buildLayout = function(shopId:String):Object {
    var raw:Object = _root.shopLayouts == undefined ? null : _root.shopLayouts[shopId];
    var result:Object = {title:shopId, defaultSection:"", sections:[]};
    if (raw == null) return result;
    if (raw.title != undefined && String(raw.title) != "") result.title = String(raw.title);
    if (raw.defaultSection != undefined) result.defaultSection = String(raw.defaultSection);
    var sections:Array = raw.sections instanceof Array ? raw.sections : [];
    for (var i:Number = 0; i < sections.length; i++) {
        var section:Object = sections[i];
        if (section == null || section.entries == undefined || !(section.entries instanceof Array)) continue;
        var entries:Array = [];
        for (var j:Number = 0; j < section.entries.length; j++) {
            var index:Number = Number(section.entries[j]);
            if (!isNaN(index) && Math.floor(index) == index && index >= 0) entries.push(index);
        }
        result.sections.push({
            id:String(section.id || ""),
            label:String(section.label || section.id || ""),
            kind:String(section.kind || ""),
            entries:entries
        });
    }
    return result;
};

_root.UI系统.NPC商店WebView.buildCollectionView = function(viewId:String, collection:Object):Object {
    var slots:Array = [];
    var values:Object = collection == undefined ? {} : collection.getItems();
    var names:Array = [];
    for (var name in values) {
        if (Number(values[name]) > 0) names.push(String(name));
    }
    names.sort();
    for (var i:Number = 0; i < names.length; i++) {
        var itemName:String = names[i];
        var quantity:Number = Number(values[itemName]);
        var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(itemName);
        if (itemData == null) continue;
        slots.push({
            physicalSlot:i,
            collectionKey:itemName,
            occupied:true,
            slotLease:this.issueCollectionLease(viewId, itemName, quantity),
            item:{
                itemKind:"stack",
                name:itemName,
                displayName:String(itemData.displayname || itemName),
                icon:String(itemData.icon || itemName),
                majorType:String(itemData.type || "收集品"),
                use:String(itemData.use || ""),
                quantity:quantity,
                enhancementLevel:0,
                rarity:String(itemData.rarity || itemData.品质 || "")
            }
        });
    }
    return {
        containerId:viewId == "material" ? "材料" : "情报",
        capacity:slots.length,
        accessibleCapacity:slots.length,
        viewCapacity:slots.length,
        offset:0,
        limit:slots.length,
        filterKey:"all",
        slots:slots
    };
};

_root.UI系统.NPC商店WebView.buildState = function(shopId:String):Object {
    var inventoryResult:Object = org.flashNight.arki.item.InventoryPanelService.execute("snapshot", {
        v:1, requests:[{containerId:"背包", offset:0, limit:50, filterKey:"all"}]
    });
    if (!inventoryResult.success) return inventoryResult;
    this.beginCollectionSession(shopId);
    var catalog:Array = this.buildCatalog(shopId);
    var materialView:Object = this.buildCollectionView("material", _root.收集品栏.材料);
    var intelligenceView:Object = this.buildCollectionView("intelligence", _root.收集品栏.情报);
    return {
        success:true,
        v:1,
        shopId:shopId,
        balance:Number(_root.金钱),
        buyMultiplier:this.getBuyMultiplier(),
        catalog:catalog,
        layout:this.buildLayout(shopId),
        views:{
            bag:inventoryResult.snapshots[0],
            material:materialView,
            intelligence:intelligenceView
        }
    };
};

_root.UI系统.NPC商店WebView.resolvePurchaseDestination = function(itemName:String):String {
    if (org.flashNight.arki.item.ItemUtil.isMaterial(itemName)) return "material";
    if (org.flashNight.arki.item.ItemUtil.isInformation(itemName)) return "intelligence";
    var drugs:Object = _root.物品栏 == undefined ? null : _root.物品栏.药剂栏;
    if (drugs != null) {
        var indexes:Array = drugs.getIndexes();
        for (var i:Number = 0; i < indexes.length; i++) {
            var item:Object = drugs.getItem(indexes[i]);
            if (item != null && item.name == itemName && typeof item.value == "number") return "quickslot";
        }
    }
    return "bag";
};

_root.UI系统.NPC商店WebView.executeSnapshot = function(params:Object):Object {
    var shopId:String = params == undefined ? "" : String(params.shopId);
    if (shopId == "" || _root.shops == undefined || _root.shops[shopId] == undefined) return this.fail("shop_not_found");
    return this.buildState(shopId);
};

_root.UI系统.NPC商店WebView.executeTooltip = function(params:Object):Object {
    if (params != undefined && params.source != undefined
            && String(params.source.containerId) == "背包") {
        return org.flashNight.arki.item.InventoryPanelService.execute("tooltip", {v:1, source:params.source});
    }
    var itemName:String = params == undefined ? "" : String(params.itemName || "");
    if (!org.flashNight.arki.item.ItemUtil.isItem(itemName)) return this.fail("item_not_found");
    var tt:Object = _root.Web物品注释HTML(itemName);
    if (tt == null) return this.fail("tooltip_failed");
    return {
        success:true,
        v:1,
        itemName:itemName,
        displayname:String(tt.displayname || itemName),
        descHTML:String(tt.descHTML || "").split('"').join("'"),
        introHTML:String(tt.introHTML || "").split('"').join("'")
    };
};

_root.UI系统.NPC商店WebView.executeBuy = function(params:Object):Object {
    var shopId:String = params == undefined ? "" : String(params.shopId);
    if (shopId == "" || _root.shops == undefined || _root.shops[shopId] == undefined) return this.fail("shop_not_found");
    if (shopId != this.activeShopId) return this.fail("stale_state");
    if (!this.isWholeNumber(params.catalogIndex) || !this.isWholeNumber(params.quantity)
            || Number(params.quantity) <= 0) return this.fail("invalid_payload");
    var resolved:Object = this.resolveSaleEntry(shopId, Number(params.catalogIndex));
    if (resolved == null) return this.fail("item_not_found");
    var itemName:String = resolved.itemName;
    var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(itemName);
    var quantity:Number = Number(params.quantity);
    // legacy buy 保持原版“一次一件装备”；npc-shop.v2 purchaseLimit 只作用于
    // 新 tradePreview/tradeCommit 协议，后者会把复数装备展开为独立实例。
    var maxQuantity:Number = org.flashNight.arki.item.ItemUtil.isEquipment(itemName) ? 1 : 100;
    if (quantity > maxQuantity) return this.fail("invalid_quantity");
    var requiredInfo:String = typeof resolved.raw == "string" || resolved.raw.requiredInfo == undefined
        ? "" : String(resolved.raw.requiredInfo);
    if (requiredInfo != "" && _root.收集品栏.情报.getValue(requiredInfo) <= 0) return this.fail("locked");
    var basePrice:Number = Number(itemData.price);
    if (isNaN(basePrice)) basePrice = 0;
    var total:Number = Math.floor(basePrice * quantity * this.getBuyMultiplier());
    if (isNaN(_root.金钱) || isNaN(total) || total > Number(_root.金钱)) return this.fail("insufficient_money");
    var destination:String = this.resolvePurchaseDestination(itemName);
    if (!org.flashNight.arki.item.ItemUtil.singleAcquire(itemName, quantity)) return this.fail("inventory_full");
    _root.金钱 -= total;
    if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
        org.flashNight.arki.achievement.AchievementMetrics.record("购买物品次数", 1);
        org.flashNight.arki.achievement.AchievementMetrics.record("购买花费金币", total);
    }
    _root.soundEffectManager.playSound("收银机.mp3");
    _root.存档系统.dirtyMark = true;
    var state:Object = this.buildState(shopId);
    if (!state.success) return state;
    state.operation = "buy";
    state.destinationView = destination;
    state.itemName = itemName;
    state.quantity = quantity;
    state.total = total;
    return state;
};

_root.UI系统.NPC商店WebView.validateCollectionSource = function(source:Object):Object {
    if (source == undefined || String(source.viewId) != "material") return this.fail("sell_forbidden");
    var token:String = String(source.expectedLease || "");
    var lease:Object = this.collectionLeases[token];
    var key:String = String(source.key || "");
    if (lease == undefined || lease.viewId != "material" || lease.key != key) return this.fail("stale_state");
    var count:Number = Number(_root.收集品栏.材料.getValue(key));
    if (count != Number(lease.count)) return this.fail("stale_state");
    return {success:true, collection:_root.收集品栏.材料, key:key, count:count};
};

_root.UI系统.NPC商店WebView.executeSell = function(params:Object):Object {
    var shopId:String = params == undefined ? "" : String(params.shopId);
    if (shopId == "" || _root.shops == undefined || _root.shops[shopId] == undefined) return this.fail("shop_not_found");
    if (shopId != this.activeShopId) return this.fail("stale_state");
    var quantity:Number = Number(params == undefined ? NaN : params.quantity);
    if (!this.isWholeNumber(quantity) || quantity <= 0) return this.fail("invalid_quantity");
    var source:Object = params.source;
    var item:Object;
    var itemName:String;
    var collection:Object;
    var key;
    var bagCheck:Object;
    if (source != undefined && String(source.containerId) == "背包") {
        bagCheck = org.flashNight.arki.item.InventoryPanelService.validateExternalSlotRef(source, false);
        if (!bagCheck.success) return bagCheck;
        item = bagCheck.item;
        if (typeof item.value == "number") {
            bagCheck = org.flashNight.arki.item.InventoryPanelService.validateExternalSlotRef(source, true);
            if (!bagCheck.success) return bagCheck;
            if (quantity > Number(item.value)) return this.fail("insufficient_quantity");
        } else if (quantity != 1) return this.fail("invalid_quantity");
        itemName = String(item.name);
        collection = bagCheck.inventory;
        key = String(bagCheck.slot);
    } else {
        var collectionCheck:Object = this.validateCollectionSource(source);
        if (!collectionCheck.success) return collectionCheck;
        if (quantity > collectionCheck.count) return this.fail("insufficient_quantity");
        itemName = collectionCheck.key;
        item = {name:itemName, value:collectionCheck.count};
        collection = collectionCheck.collection;
        key = itemName;
    }
    var priceInfo:Object = _root.物品UI函数.计算售卖总价(item, quantity);
    if (bagCheck != undefined && typeof item.value == "object" && item.value.mods != undefined
            && item.value.mods.length > 0) {
        var returned:Array = [];
        for (var modIndex:Number = 0; modIndex < item.value.mods.length; modIndex++) {
            returned.push({name:item.value.mods[modIndex], value:1});
        }
        org.flashNight.arki.item.ItemUtil.acquire(returned);
        item.value.mods = [];
    }
    if (typeof item.value == "number" && Number(item.value) > quantity) collection.addValue(key, -quantity);
    else collection.remove(key);
    if (bagCheck != undefined) {
        org.flashNight.arki.item.InventoryPanelService.invalidateExternalSlot("背包", Number(bagCheck.slot));
    }
    _root.金钱 += Number(priceInfo.总价);
    if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
        org.flashNight.arki.achievement.AchievementMetrics.record("出售次数", 1);
        org.flashNight.arki.achievement.AchievementMetrics.record("出售所得金币", Number(priceInfo.总价));
    }
    _root.soundEffectManager.playSound("收银机.mp3");
    _root.存档系统.dirtyMark = true;
    var state:Object = this.buildState(String(params.shopId));
    if (!state.success) return state;
    state.operation = "sell";
    state.itemName = itemName;
    state.quantity = quantity;
    state.total = Number(priceInfo.总价);
    return state;
};

_root.UI系统.NPC商店WebView.executeBatchPreview = function(params:Object):Object {
    if (this.activeShopId == "" || _root.shops == undefined || _root.shops[this.activeShopId] == undefined) return this.fail("stale_state");
    var names:Array = params == undefined ? null : params.itemNames;
    if (!(names instanceof Array) || names.length < 1 || names.length > 5) return this.fail("invalid_payload");
    var unique:Object = {};
    var summary:Array = [];
    var entries:Array = [];
    var skipped:Number = 0;
    var totalQuantity:Number = 0;
    var totalMoney:Number = 0;
    var bag:Object = _root.物品栏.背包;
    for (var i:Number = 0; i < names.length; i++) {
        var itemName:String = String(names[i]);
        if (itemName == "" || unique[itemName] == true) return this.fail("invalid_payload");
        unique[itemName] = true;
        var nameQuantity:Number = 0;
        var nameMoney:Number = 0;
        for (var slot:Number = 0; slot < bag.capacity; slot++) {
            var item:Object = bag.getItem(String(slot));
            if (item == null || String(item.name) != itemName) continue;
            if (!_root.物品UI函数.是否普通物品(item)) {
                skipped++;
                continue;
            }
            var quantity:Number = typeof item.value == "number" ? Number(item.value) : 1;
            var price:Object = _root.物品UI函数.计算售卖总价(item, quantity);
            entries.push({slot:slot, ref:item, name:itemName, count:quantity, money:Number(price.总价)});
            nameQuantity += quantity;
            nameMoney += Number(price.总价);
        }
        if (nameQuantity > 0) {
            var data:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(itemName);
            summary.push({itemName:itemName, displayName:String(data == null ? itemName : data.displayname || itemName), quantity:nameQuantity, money:nameMoney});
            totalQuantity += nameQuantity;
            totalMoney += nameMoney;
        }
    }
    if (entries.length == 0) return this.fail("nothing_to_sell");
    this.batchSeq++;
    var token:String = "npcbatch" + getTimer() + "." + this.batchSeq;
    this.batchPlan = {token:token, entries:entries, totalMoney:totalMoney, totalQuantity:totalQuantity};
    return {success:true, v:1, batchToken:token, summary:summary, totalQuantity:totalQuantity, totalMoney:totalMoney, skipped:skipped};
};

_root.UI系统.NPC商店WebView.executeBatchSell = function(params:Object):Object {
    var shopId:String = params == undefined ? "" : String(params.shopId);
    if (shopId == "" || _root.shops == undefined || _root.shops[shopId] == undefined) return this.fail("shop_not_found");
    if (shopId != this.activeShopId) return this.fail("stale_state");
    var plan:Object = this.batchPlan;
    if (plan == null || String(params.expectedBatchToken || "") != String(plan.token)) return this.fail("stale_state");
    var bag:Object = _root.物品栏.背包;
    for (var i:Number = 0; i < plan.entries.length; i++) {
        var entry:Object = plan.entries[i];
        var current:Object = bag.getItem(String(entry.slot));
        if (current !== entry.ref || !_root.物品UI函数.是否普通物品(current)
                || (typeof current.value == "number" && Number(current.value) != Number(entry.count))) {
            this.batchPlan = null;
            return this.fail("stale_state");
        }
    }
    for (var j:Number = 0; j < plan.entries.length; j++) {
        var sellEntry:Object = plan.entries[j];
        bag.remove(String(sellEntry.slot));
        org.flashNight.arki.item.InventoryPanelService.invalidateExternalSlot("背包", Number(sellEntry.slot));
        if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
            org.flashNight.arki.achievement.AchievementMetrics.record("出售次数", 1);
            org.flashNight.arki.achievement.AchievementMetrics.record("出售所得金币", Number(sellEntry.money));
        }
    }
    _root.金钱 += Number(plan.totalMoney);
    _root.soundEffectManager.playSound("收银机.mp3");
    _root.存档系统.dirtyMark = true;
    this.batchPlan = null;
    var state:Object = this.buildState(String(params.shopId));
    if (!state.success) return state;
    state.operation = "batchSell";
    state.quantity = Number(plan.totalQuantity);
    state.total = Number(plan.totalMoney);
    return state;
};

_root.UI系统.NPC商店WebView.resolveTradePurchase = function(shopId:String, request:Object):Object {
    if (request == undefined || !this.isWholeNumber(request.catalogIndex)
            || !this.isWholeNumber(request.quantity) || Number(request.quantity) <= 0) return this.fail("invalid_payload");
    var catalogIndex:Number = Number(request.catalogIndex);
    var quantity:Number = Number(request.quantity);
    var resolved:Object = this.resolveSaleEntry(shopId, catalogIndex);
    if (resolved == null) return this.fail("item_not_found");
    var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(resolved.itemName);
    if (itemData == null) return this.fail("item_not_found");
    var maxQuantity:Number = this.getPurchaseLimit(resolved);
    if (quantity > maxQuantity) return this.fail("invalid_quantity");
    var requiredInfo:String = typeof resolved.raw == "string" || resolved.raw.requiredInfo == undefined
        ? "" : String(resolved.raw.requiredInfo);
    if (requiredInfo != "" && _root.收集品栏.情报.getValue(requiredInfo) <= 0) return this.fail("locked");
    var basePrice:Number = Number(itemData.price);
    if (isNaN(basePrice)) basePrice = 0;
    var unitPrice:Number = Math.floor(basePrice * this.getBuyMultiplier());
    var total:Number = Math.floor(basePrice * quantity * this.getBuyMultiplier());
    return {
        success:true,
        catalogIndex:catalogIndex,
        itemName:resolved.itemName,
        displayName:String(itemData.displayname || resolved.itemName),
        icon:String(itemData.icon || resolved.itemName),
        quantity:quantity,
        unitPrice:unitPrice,
        total:total,
        maxQuantity:maxQuantity,
        itemKind:org.flashNight.arki.item.ItemUtil.isEquipment(resolved.itemName) ? "equipment" : "stack",
        destinationView:this.resolvePurchaseDestination(resolved.itemName)
    };
};

_root.UI系统.NPC商店WebView.resolveExactTradeSale = function(request:Object):Object {
    if (request == undefined || !this.isWholeNumber(request.quantity) || Number(request.quantity) <= 0) {
        return this.fail("invalid_payload");
    }
    var quantity:Number = Number(request.quantity);
    var source:Object = request.source;
    var item:Object;
    var itemName:String;
    var collection:Object;
    var key:String;
    var kind:String;
    var slot:Number = -1;
    var oldCount:Number;
    if (source != undefined && String(source.containerId) == "背包") {
        var bagCheck:Object = org.flashNight.arki.item.InventoryPanelService.validateExternalSlotRef(source, false);
        if (!bagCheck.success) return bagCheck;
        item = bagCheck.item;
        if (typeof item.value == "number") {
            bagCheck = org.flashNight.arki.item.InventoryPanelService.validateExternalSlotRef(source, true);
            if (!bagCheck.success) return bagCheck;
            oldCount = Number(item.value);
            if (quantity > oldCount) return this.fail("insufficient_quantity");
        } else {
            oldCount = 1;
            if (quantity != 1) return this.fail("invalid_quantity");
        }
        itemName = String(item.name);
        collection = bagCheck.inventory;
        key = String(bagCheck.slot);
        slot = Number(bagCheck.slot);
        kind = "bag";
    } else {
        var collectionCheck:Object = this.validateCollectionSource(source);
        if (!collectionCheck.success) return collectionCheck;
        oldCount = Number(collectionCheck.count);
        if (quantity > oldCount) return this.fail("insufficient_quantity");
        itemName = String(collectionCheck.key);
        item = {name:itemName, value:oldCount};
        collection = collectionCheck.collection;
        key = itemName;
        kind = "material";
    }
    var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(itemName);
    if (itemData == null) return this.fail("item_not_found");
    var priceInfo:Object = _root.物品UI函数.计算售卖总价(item, quantity);
    var money:Number = Number(priceInfo.总价);
    if (isNaN(money) || money < 0) return this.fail("invalid_price");
    var returnedMods:Array = [];
    if (kind == "bag" && typeof item.value == "object" && item.value.mods instanceof Array) {
        for (var modIndex:Number = 0; modIndex < item.value.mods.length; modIndex++) {
            returnedMods.push({name:String(item.value.mods[modIndex]), value:1});
        }
    }
    return {
        success:true,
        identity:kind + ":" + key,
        kind:kind,
        collection:collection,
        key:key,
        slot:slot,
        ref:item,
        itemName:itemName,
        displayName:String(itemData.displayname || itemName),
        icon:String(itemData.icon || itemName),
        oldCount:oldCount,
        quantity:quantity,
        money:money,
        full:quantity >= oldCount,
        returnedMods:returnedMods
    };
};

_root.UI系统.NPC商店WebView.resolveTradeSale = function(request:Object):Object {
    var scope:String = request == undefined || request.scope == undefined ? "slot" : String(request.scope);
    if (scope == "slot") {
        var exact:Object = this.resolveExactTradeSale(request);
        if (!exact.success) return exact;
        return {
            success:true,
            scope:"slot",
            groupIdentity:exact.identity,
            requestIdentity:exact.identity,
            entries:[exact],
            itemName:exact.itemName,
            displayName:exact.displayName,
            icon:exact.icon,
            itemKind:org.flashNight.arki.item.ItemUtil.isEquipment(exact.itemName) ? "equipment" : "stack",
            quantity:exact.quantity,
            money:exact.money,
            matchedCount:1,
            eligibleCount:1,
            protectedCount:0
        };
    }
    if (scope != "same_name" || String(request.policy || "") != "plain_only") return this.fail("invalid_payload");
    var source:Object = request.source;
    if (source == undefined || String(source.containerId) != "背包") return this.fail("sell_forbidden");
    var seedCheck:Object = org.flashNight.arki.item.InventoryPanelService.validateExternalSlotRef(source, false);
    if (!seedCheck.success) return seedCheck;
    var seed:Object = seedCheck.item;
    var itemName:String = String(seed.name);
    var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(itemName);
    if (itemData == null) return this.fail("item_not_found");
    var bag:Object = _root.物品栏.背包;
    var entries:Array = [];
    var matched:Number = 0;
    var protectedCount:Number = 0;
    var totalQuantity:Number = 0;
    var totalMoney:Number = 0;
    for (var slot:Number = 0; slot < bag.capacity; slot++) {
        var current:Object = bag.getItem(String(slot));
        if (current == null || String(current.name) != itemName) continue;
        matched++;
        if (!_root.物品UI函数.是否普通物品(current)) {
            protectedCount++;
            continue;
        }
        var quantity:Number = typeof current.value == "number" ? Number(current.value) : 1;
        var priceInfo:Object = _root.物品UI函数.计算售卖总价(current, quantity);
        var money:Number = Number(priceInfo.总价);
        if (isNaN(money) || money < 0) return this.fail("invalid_price");
        entries.push({
            success:true,
            identity:"bag:" + slot,
            kind:"bag",
            collection:bag,
            key:String(slot),
            slot:slot,
            ref:current,
            itemName:itemName,
            displayName:String(itemData.displayname || itemName),
            icon:String(itemData.icon || itemName),
            oldCount:quantity,
            quantity:quantity,
            money:money,
            full:true,
            plainOnly:true,
            returnedMods:[]
        });
        totalQuantity += quantity;
        totalMoney += money;
    }
    if (entries.length == 0) return this.fail("nothing_to_sell");
    return {
        success:true,
        scope:"same_name",
        policy:"plain_only",
        groupIdentity:"same_name:" + itemName,
        requestIdentity:"bag:" + Number(seedCheck.slot),
        entries:entries,
        itemName:itemName,
        displayName:String(itemData.displayname || itemName),
        icon:String(itemData.icon || itemName),
        itemKind:org.flashNight.arki.item.ItemUtil.isEquipment(itemName) ? "equipment" : "stack",
        quantity:totalQuantity,
        money:totalMoney,
        matchedCount:matched,
        eligibleCount:entries.length,
        protectedCount:protectedCount
    };
};

_root.UI系统.NPC商店WebView.buildAcquireItems = function(purchases:Array, sales:Array):Array {
    var result:Array = [];
    var collectionTotals:Object = {};
    for (var i:Number = 0; i < purchases.length; i++) {
        var purchase:Object = purchases[i];
        if (org.flashNight.arki.item.ItemUtil.isEquipment(purchase.itemName)) {
            for (var instance:Number = 0; instance < Number(purchase.quantity); instance++) {
                result.push({name:purchase.itemName, value:1});
            }
        } else if (org.flashNight.arki.item.ItemUtil.isMaterial(purchase.itemName)
                || org.flashNight.arki.item.ItemUtil.isInformation(purchase.itemName)) {
            collectionTotals[purchase.itemName] = Number(collectionTotals[purchase.itemName] || 0)
                + Number(purchase.quantity);
        } else {
            result.push({name:purchase.itemName, value:purchase.quantity});
        }
    }
    for (var j:Number = 0; j < sales.length; j++) {
        var sale:Object = sales[j];
        for (var modIndex:Number = 0; modIndex < sale.returnedMods.length; modIndex++) {
            var returned:Object = sale.returnedMods[modIndex];
            collectionTotals[returned.name] = Number(collectionTotals[returned.name] || 0)
                + Number(returned.value);
        }
    }
    for (var collectionName:String in collectionTotals) {
        result.push({name:collectionName, value:Number(collectionTotals[collectionName])});
    }
    return result;
};

_root.UI系统.NPC商店WebView.analyzeTradeCapacity = function(plan:Object):Object {
    var bag:Object = _root.物品栏.背包;
    var vacancies:Array = bag.getVacancies(bag.capacity);
    var available:Number = vacancies.length;
    var saleBySlot:Object = {};
    for (var i:Number = 0; i < plan.sales.length; i++) {
        var sale:Object = plan.sales[i];
        if (sale.kind == "bag") {
            saleBySlot[String(sale.slot)] = sale;
            if (sale.full) available++;
        }
    }
    var required:Number = 0;
    var mergeable:Object = {};
    for (var j:Number = 0; j < plan.acquireItems.length; j++) {
        var requested:Object = plan.acquireItems[j];
        var name:String = String(requested.name);
        var quantity:Number = Number(requested.value);
        if (org.flashNight.arki.item.ItemUtil.isMaterial(name)
                || org.flashNight.arki.item.ItemUtil.isInformation(name)
                || this.resolvePurchaseDestination(name) == "quickslot") continue;
        if (org.flashNight.arki.item.ItemUtil.isEquipment(name)) {
            required += quantity;
        } else {
            mergeable[name] = true;
        }
    }
    for (var mergeName:String in mergeable) {
        var remains:Boolean = false;
        var indexes:Array = bag.getIndexes();
        for (var k:Number = 0; k < indexes.length; k++) {
            var slot:Number = Number(indexes[k]);
            var current:Object = bag.getItem(slot);
            if (current == null || String(current.name) != mergeName || typeof current.value != "number") continue;
            var selected:Object = saleBySlot[String(slot)];
            if (selected == undefined || Number(current.value) > Number(selected.quantity)) {
                remains = true;
                break;
            }
        }
        if (!remains) required++;
    }
    return {requiredSlots:required, availableSlots:available, missingSlots:Math.max(0, required - available), enough:required <= available};
};

_root.UI系统.NPC商店WebView.checkTradeCapacity = function(plan:Object):Boolean {
    return this.analyzeTradeCapacity(plan).enough;
};

_root.UI系统.NPC商店WebView.getPurchaseBounds = function(plan:Object, target:Object):Object {
    var otherBuyTotal:Number = Number(plan.buyTotal) - Number(target.total);
    var budget:Number = Number(plan.balance) + Number(plan.sellTotal) - otherBuyTotal;
    var limit:Number = Number(target.maxQuantity);
    var low:Number = 1;
    var high:Number = limit;
    var maxAffordable:Number = 0;
    while (low <= high) {
        var affordableMid:Number = Math.floor((low + high) / 2);
        var affordableCandidate:Object = this.resolveTradePurchase(plan.shopId, {
            catalogIndex:target.catalogIndex,
            quantity:affordableMid
        });
        if (affordableCandidate.success && Number(affordableCandidate.total) <= budget) {
            maxAffordable = affordableMid;
            low = affordableMid + 1;
        } else {
            high = affordableMid - 1;
        }
    }

    low = 1;
    high = limit;
    var maxByCapacity:Number = 0;
    while (low <= high) {
        var capacityMid:Number = Math.floor((low + high) / 2);
        var candidate:Object = this.resolveTradePurchase(plan.shopId, {
            catalogIndex:target.catalogIndex,
            quantity:capacityMid
        });
        if (!candidate.success) {
            high = capacityMid - 1;
            continue;
        }
        var trialPurchases:Array = [];
        for (var i:Number = 0; i < plan.purchases.length; i++) {
            trialPurchases.push(plan.purchases[i] === target ? candidate : plan.purchases[i]);
        }
        var trial:Object = {purchases:trialPurchases, sales:plan.sales};
        trial.acquireItems = this.buildAcquireItems(trialPurchases, plan.sales);
        if (this.checkTradeCapacity(trial)) {
            maxByCapacity = capacityMid;
            low = capacityMid + 1;
        } else {
            high = capacityMid - 1;
        }
    }
    return {
        purchaseLimit:limit,
        maxAffordable:maxAffordable,
        maxByCapacity:maxByCapacity,
        maxPurchasable:Math.min(limit, Math.min(maxAffordable, maxByCapacity))
    };
};

_root.UI系统.NPC商店WebView.executeTradePreview = function(params:Object):Object {
    var shopId:String = params == undefined ? "" : String(params.shopId);
    if (shopId == "" || _root.shops == undefined || _root.shops[shopId] == undefined) return this.fail("shop_not_found");
    if (shopId != this.activeShopId) return this.fail("stale_state");
    var purchases:Array = params.purchases instanceof Array ? params.purchases : [];
    var sales:Array = params.sales instanceof Array ? params.sales : [];
    if (purchases.length > 40 || sales.length > 50 || purchases.length + sales.length < 1) return this.fail("invalid_payload");
    var plan:Object = {shopId:shopId, purchases:[], sales:[], publicSales:[], acquireItems:[], buyTotal:0, sellTotal:0, balance:Number(_root.金钱)};
    var purchaseIds:Object = {};
    var saleIds:Object = {};
    var expandedSaleIds:Object = {};
    for (var i:Number = 0; i < purchases.length; i++) {
        var purchase:Object = this.resolveTradePurchase(shopId, purchases[i]);
        if (!purchase.success) return purchase;
        var purchaseKey:String = String(purchase.catalogIndex);
        if (purchaseIds[purchaseKey]) return this.fail("duplicate_line");
        purchaseIds[purchaseKey] = true;
        plan.purchases.push(purchase);
        plan.buyTotal += Number(purchase.total);
    }
    for (var j:Number = 0; j < sales.length; j++) {
        var saleGroup:Object = this.resolveTradeSale(sales[j]);
        if (!saleGroup.success) return saleGroup;
        if (saleIds[saleGroup.groupIdentity]) return this.fail("duplicate_line");
        saleIds[saleGroup.groupIdentity] = true;
        for (var entryIndex:Number = 0; entryIndex < saleGroup.entries.length; entryIndex++) {
            var expandedSale:Object = saleGroup.entries[entryIndex];
            if (expandedSaleIds[expandedSale.identity]) return this.fail("duplicate_line");
            expandedSaleIds[expandedSale.identity] = true;
            plan.sales.push(expandedSale);
        }
        plan.publicSales.push({
            itemName:saleGroup.itemName,
            displayName:saleGroup.displayName,
            icon:saleGroup.icon,
            itemKind:saleGroup.itemKind == undefined
                ? (org.flashNight.arki.item.ItemUtil.isEquipment(saleGroup.itemName) ? "equipment" : "stack") : saleGroup.itemKind,
            quantity:saleGroup.quantity,
            total:saleGroup.money,
            sourceIdentity:saleGroup.requestIdentity,
            scope:saleGroup.scope,
            matchedCount:saleGroup.matchedCount,
            eligibleCount:saleGroup.eligibleCount,
            protectedCount:saleGroup.protectedCount
        });
        plan.sellTotal += Number(saleGroup.money);
    }
    plan.acquireItems = this.buildAcquireItems(plan.purchases, plan.sales);
    var enoughMoney:Boolean = plan.balance + plan.sellTotal >= plan.buyTotal;
    var capacity:Object = this.analyzeTradeCapacity(plan);
    var enoughSpace:Boolean = capacity.enough;
    for (var purchaseIndex:Number = 0; purchaseIndex < plan.purchases.length; purchaseIndex++) {
        var bounds:Object = this.getPurchaseBounds(plan, plan.purchases[purchaseIndex]);
        plan.purchases[purchaseIndex].purchaseLimit = bounds.purchaseLimit;
        plan.purchases[purchaseIndex].maxAffordable = bounds.maxAffordable;
        plan.purchases[purchaseIndex].maxByCapacity = bounds.maxByCapacity;
        plan.purchases[purchaseIndex].maxPurchasable = bounds.maxPurchasable;
    }
    this.tradeSeq++;
    plan.token = "npctrade" + getTimer() + "." + this.tradeSeq;
    this.tradePlan = plan;
    return {
        success:true,
        v:1,
        tradeToken:plan.token,
        purchaseLines:plan.purchases,
        saleLines:plan.publicSales,
        buyTotal:plan.buyTotal,
        sellTotal:plan.sellTotal,
        netDelta:plan.sellTotal - plan.buyTotal,
        projectedBalance:plan.balance + plan.sellTotal - plan.buyTotal,
        requiredSlots:capacity.requiredSlots,
        availableSlots:capacity.availableSlots,
        missingSlots:capacity.missingSlots,
        canCommit:enoughMoney && enoughSpace,
        blockingError:enoughMoney ? (enoughSpace ? "" : "inventory_full") : "insufficient_money"
    };
};

_root.UI系统.NPC商店WebView.validateTradePlan = function(plan:Object):Object {
    if (plan == null || String(plan.shopId) != this.activeShopId || Number(_root.金钱) != Number(plan.balance)) {
        return this.fail("stale_state");
    }
    var buyTotal:Number = 0;
    for (var i:Number = 0; i < plan.purchases.length; i++) {
        var oldPurchase:Object = plan.purchases[i];
        var purchase:Object = this.resolveTradePurchase(plan.shopId, oldPurchase);
        if (!purchase.success || purchase.itemName != oldPurchase.itemName
                || Number(purchase.total) != Number(oldPurchase.total)) return this.fail("stale_state");
        buyTotal += Number(purchase.total);
    }
    var sellTotal:Number = 0;
    for (var j:Number = 0; j < plan.sales.length; j++) {
        var sale:Object = plan.sales[j];
        if (sale.plainOnly && !_root.物品UI函数.是否普通物品(sale.ref)) return this.fail("stale_state");
        if (sale.kind == "bag") {
            var current:Object = _root.物品栏.背包.getItem(sale.slot);
            if (current !== sale.ref || (typeof current.value == "number" && Number(current.value) != Number(sale.oldCount))) {
                return this.fail("stale_state");
            }
        } else if (Number(_root.收集品栏.材料.getValue(sale.key)) != Number(sale.oldCount)) {
            return this.fail("stale_state");
        }
        var price:Object = _root.物品UI函数.计算售卖总价(sale.ref, sale.quantity);
        if (Number(price.总价) != Number(sale.money)) return this.fail("stale_state");
        sellTotal += Number(sale.money);
    }
    if (buyTotal != Number(plan.buyTotal) || sellTotal != Number(plan.sellTotal)) return this.fail("stale_state");
    if (Number(_root.金钱) + sellTotal < buyTotal) return this.fail("insufficient_money");
    if (!this.checkTradeCapacity(plan)) return this.fail("inventory_full");
    return {success:true};
};

_root.UI系统.NPC商店WebView.rollbackTradeSales = function(plan:Object):Void {
    for (var i:Number = plan.sales.length - 1; i >= 0; i--) {
        var sale:Object = plan.sales[i];
        if (sale.kind == "bag") {
            if (sale.full) sale.collection.add(Number(sale.key), sale.ref);
            else sale.collection.addValue(sale.key, sale.quantity);
        } else {
            var current:Number = Number(sale.collection.getValue(sale.key));
            if (current <= 0) sale.collection.add(sale.key, sale.oldCount);
            else sale.collection.addValue(sale.key, sale.oldCount - current);
        }
    }
};

_root.UI系统.NPC商店WebView.executeTradeCommit = function(params:Object):Object {
    var shopId:String = params == undefined ? "" : String(params.shopId);
    var plan:Object = this.tradePlan;
    var expectedToken:String = params == undefined ? "" : String(params.expectedTradeToken || "");
    if (plan == null || expectedToken != String(plan.token)
            || shopId != String(plan.shopId)) return this.fail("stale_state");
    this.tradePlan = null;
    var validation:Object = this.validateTradePlan(plan);
    if (!validation.success) return validation;
    for (var i:Number = 0; i < plan.sales.length; i++) {
        var sale:Object = plan.sales[i];
        if (sale.full) sale.collection.remove(sale.key);
        else sale.collection.addValue(sale.key, -sale.quantity);
    }
    if (!org.flashNight.arki.item.ItemUtil.acquire(plan.acquireItems)) {
        this.rollbackTradeSales(plan);
        return this.fail("inventory_full");
    }
    for (var j:Number = 0; j < plan.sales.length; j++) {
        var sold:Object = plan.sales[j];
        if (sold.kind == "bag") {
            org.flashNight.arki.item.InventoryPanelService.invalidateExternalSlot("背包", sold.slot);
            if (typeof sold.ref.value == "object" && sold.ref.value.mods instanceof Array) sold.ref.value.mods = [];
        }
    }
    _root.金钱 = Number(plan.balance) + Number(plan.sellTotal) - Number(plan.buyTotal);
    if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
        if (plan.purchases.length > 0) {
            org.flashNight.arki.achievement.AchievementMetrics.record("购买物品次数", plan.purchases.length);
            org.flashNight.arki.achievement.AchievementMetrics.record("购买花费金币", plan.buyTotal);
        }
        if (plan.sales.length > 0) {
            org.flashNight.arki.achievement.AchievementMetrics.record("出售次数", plan.sales.length);
            org.flashNight.arki.achievement.AchievementMetrics.record("出售所得金币", plan.sellTotal);
        }
    }
    _root.soundEffectManager.playSound("收银机.mp3");
    _root.存档系统.dirtyMark = true;
    var state:Object = this.buildState(shopId);
    if (!state.success) return state;
    state.operation = "tradeCommit";
    state.trade = {buyTotal:plan.buyTotal, sellTotal:plan.sellTotal, netDelta:plan.sellTotal - plan.buyTotal};
    return state;
};

_root.UI系统.NPC商店WebView.execute = function(commandName:String, params:Object):Object {
    if (this.busy && commandName != "snapshot" && commandName != "tooltip" && commandName != "tradePreview") return this.fail("busy");
    if (commandName == "snapshot") return this.executeSnapshot(params);
    if (commandName == "tooltip") return this.executeTooltip(params);
    if (commandName == "batchPreview") return this.executeBatchPreview(params);
    if (commandName == "tradePreview") return this.executeTradePreview(params);
    this.busy = true;
    var result:Object;
    if (commandName == "buy") result = this.executeBuy(params);
    else if (commandName == "sell") result = this.executeSell(params);
    else if (commandName == "batchSell") result = this.executeBatchSell(params);
    else if (commandName == "tradeCommit") result = this.executeTradeCommit(params);
    else result = this.fail("unsupported_cmd");
    this.busy = false;
    return result;
};

_root.UI系统.NPC商店WebView.handle = function(commandName:String, params:Object):Void {
    var response:Object;
    try {
        response = this.execute(commandName, params || {});
    } catch (error) {
        this.busy = false;
        this.log("handle exception cmd=" + commandName + " error=" + String(error));
        response = this.fail("internal_error");
    }
    response.task = "npcshop_response";
    response.callId = params == undefined ? undefined : params.callId;
    if (!this.sendResponse(response)) {
        this.log("response send failed cmd=" + commandName);
    }
};

_root.gameCommands = _root.gameCommands || {};
_root.gameCommands["npcShopSnapshot"] = function(params) { _root.UI系统.NPC商店WebView.handle("snapshot", params); };
_root.gameCommands["npcShopTooltip"] = function(params) { _root.UI系统.NPC商店WebView.handle("tooltip", params); };
_root.gameCommands["npcShopBuy"] = function(params) { _root.UI系统.NPC商店WebView.handle("buy", params); };
_root.gameCommands["npcShopSell"] = function(params) { _root.UI系统.NPC商店WebView.handle("sell", params); };
_root.gameCommands["npcShopBatchPreview"] = function(params) { _root.UI系统.NPC商店WebView.handle("batchPreview", params); };
_root.gameCommands["npcShopBatchSell"] = function(params) { _root.UI系统.NPC商店WebView.handle("batchSell", params); };
_root.gameCommands["npcShopTradePreview"] = function(params) { _root.UI系统.NPC商店WebView.handle("tradePreview", params); };
_root.gameCommands["npcShopTradeCommit"] = function(params) { _root.UI系统.NPC商店WebView.handle("tradeCommit", params); };

_root.gameCommands["openNpcShop"] = function(params):Boolean {
    var shopId:String = params == undefined ? "" : String(params.shopId || "");
    if (shopId == "" || _root.shops == undefined || _root.shops[shopId] == undefined) return false;
    if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return false;
    var source:String = params.source == undefined ? "world_npc" : String(params.source);
    if (source != "world_npc" && source != "world_npc_dialogue"
            && source != "tablet_contacts" && source != "legacy_shop_refresh") source = "world_npc";
    var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
        "npcshop",
        source,
        [],
        [{name:"shopId", value:shopId}]
    );
    return _root.server.sendSocketMessage(payload);
};
