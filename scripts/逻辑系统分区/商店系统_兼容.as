_root.preloaders.push(function()
{
    if (_root.__boot == undefined) _root.__boot = {};
    _root.__boot.shopCatalogReady = false;
    _root.__boot.shopCatalogFailed = false;
    this.shops_jsons_list = new XML();
    this.shops_jsons_list.ignoreWhite = true;
    this.shops_strarrs = [];
    this.shops_list_loaded = false;
    this.shops_expected_file_count = 0;
    this.shops_jsons_list.onLoad = function(success)
    {
        // 失败粘滞：S6 的 150 帧兜底可能先执行 loader；此后的迟到 XML success
        // 不得重新发起二级加载、更不得把失败目录提升为 ready。
        if (_root.__boot.shopCatalogFailed == true) return;
        if (success != true || this.lastChild == null)
        {
            _root.__boot.shopCatalogReady = false;
            _root.__boot.shopCatalogFailed = true;
            return;
        }
        var files = [];
        var validList:Boolean = true;
        try
        {
            _root.XmlNodeToDict(this.lastChild,null,function(name, value)
            {
                if(name == "shops")
                {
                    if (typeof value != "string" || value.length == 0) validList = false;
                    else files.push(value);
                }
                return null;
            });
        }
        catch (error)
        {
            validList = false;
        }
        if (!validList || files.length < 1)
        {
            _root.__boot.shopCatalogReady = false;
            _root.__boot.shopCatalogFailed = true;
            return;
        }
        _root.preloaders.shops_expected_file_count = files.length;
        for (var i = 0; i < files.length; i++)
        {
            _root.preloaders.shops_strarrs.push([]);
            _root.GetFileByPath("data/shops/" + files[i], _root.preloaders.shops_strarrs[i]);
        }
        _root.preloaders.shops_list_loaded = true;
    };

    this.shops_jsons_list.load("data/shops/list.xml");
})

_root.loaders.push(function ()
{
    if (_root.__boot.shopCatalogFailed == true
            || _root.preloaders.shops_list_loaded != true)
    {
        _root.__boot.shopCatalogReady = false;
        _root.__boot.shopCatalogFailed = true;
        return;
    }

    this.shops_srcs = [];
    this.shops = {};
    this.shopLayouts = {};
    this.shopIdsSeen = {};
    this.json_parser = new LiteJSON();

    var expectedCount:Number = Number(_root.preloaders.shops_expected_file_count);
    if (isNaN(expectedCount) || expectedCount < 1 || Math.floor(expectedCount) != expectedCount
            || _root.preloaders.shops_strarrs.length != expectedCount)
    {
        _root.__boot.shopCatalogReady = false;
        _root.__boot.shopCatalogFailed = true;
        return;
    }
    for (var i = 0; i < _root.preloaders.shops_strarrs.length; i++)
    {
        var chunks:Array = _root.preloaders.shops_strarrs[i];
        if (!(chunks instanceof Array) || chunks.length != 1
                || typeof chunks[0] != "string" || chunks[0].length == 0)
        {
            _root.__boot.shopCatalogReady = false;
            _root.__boot.shopCatalogFailed = true;
            return;
        }
        this.shops_srcs.push(chunks[0]);
    }

    for (var i = 0; i < this.shops_srcs.length; i++)
    {
        try
        {
            this.parsedshop = this.json_parser.parse(this.shops_srcs[i]);
        }
        catch (error)
        {
            _root.__boot.shopCatalogReady = false;
            _root.__boot.shopCatalogFailed = true;
            return;
        }
        if (this.parsedshop == null || typeof this.parsedshop != "object"
                || this.parsedshop instanceof Array)
        {
            _root.__boot.shopCatalogReady = false;
            _root.__boot.shopCatalogFailed = true;
            return;
        }
        var parsedShopEntryCount:Number = 0;
        // 只允许完全没有 schema 的历史对象进入 legacy 分支。任何显式 schema
        // 都必须是完整 npc-shop.v2；缺 shopId、非对象 catalog 或重复 identity 一律
        // fail closed，不能把 schema/title/catalog 元数据误当成三个旧商店。
        if (this.parsedshop.schema !== undefined)
        {
            if (typeof this.parsedshop.schema != "string"
                    || this.parsedshop.schema !== "npc-shop.v2"
                    || typeof this.parsedshop.shopId != "string"
                    || this.parsedshop.shopId.length < 1)
            {
                _root.__boot.shopCatalogReady = false;
                _root.__boot.shopCatalogFailed = true;
                return;
            }
            var shopId:String = this.parsedshop.shopId;
            var shopCatalog:Object = this.parsedshop.catalog;
            if (shopCatalog == null || typeof shopCatalog != "object"
                    || shopCatalog instanceof Array)
            {
                _root.__boot.shopCatalogReady = false;
                _root.__boot.shopCatalogFailed = true;
                return;
            }
            var shopIdentityKey:String = "$" + shopId;
            // 显式 v2 单店允许 catalog:{}：这是保留 NPC identity、停用其交易目录的
            // authored 状态。unknown/missing schema、非对象 catalog 与重复 identity 仍在
            // 上下分支 fail closed；S9 另行要求全局 shops identity 集合非空。
            if (this.shopIdsSeen[shopIdentityKey] === true)
            {
                _root.__boot.shopCatalogReady = false;
                _root.__boot.shopCatalogFailed = true;
                return;
            }
            this.shopIdsSeen[shopIdentityKey] = true;
            this.shops[shopId] = shopCatalog;
            this.shopLayouts[shopId] = {
                title:this.parsedshop.title == undefined ? shopId : String(this.parsedshop.title),
                defaultSection:this.parsedshop.defaultSection == undefined ? "" : String(this.parsedshop.defaultSection),
                sections:this.parsedshop.sections instanceof Array ? this.parsedshop.sections : []
            };
            parsedShopEntryCount = 1;
        }
        else
        {
            for (var key in this.parsedshop)
            {
                var legacyShopId:String = String(key);
                var legacyCatalog:Object = this.parsedshop[key];
                var legacyIdentityKey:String = "$" + legacyShopId;
                var legacyCatalogEntryCount:Number = 0;
                if (legacyCatalog != null && typeof legacyCatalog == "object"
                        && !(legacyCatalog instanceof Array))
                {
                    for (var legacyCatalogKey in legacyCatalog) legacyCatalogEntryCount++;
                }
                if (legacyShopId.length < 1 || legacyCatalogEntryCount < 1
                        || this.shopIdsSeen[legacyIdentityKey] === true)
                {
                    _root.__boot.shopCatalogReady = false;
                    _root.__boot.shopCatalogFailed = true;
                    return;
                }
                this.shopIdsSeen[legacyIdentityKey] = true;
                this.shops[legacyShopId] = legacyCatalog;
                parsedShopEntryCount++;
            }
        }
        if (parsedShopEntryCount < 1)
        {
            _root.__boot.shopCatalogReady = false;
            _root.__boot.shopCatalogFailed = true;
            return;
        }
    }

    if (_root.__boot.shopCatalogFailed == true) return;
    _root.shops = this.shops;
    _root.shopLayouts = this.shopLayouts;
    _root.__boot.shopCatalogReady = true;
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
_root.UI系统.NPC商店WebView.collectionLeaseIds = {};
_root.UI系统.NPC商店WebView.batchSeq = 0;
_root.UI系统.NPC商店WebView.batchPlan = null;
_root.UI系统.NPC商店WebView.tradeSeq = 0;
_root.UI系统.NPC商店WebView.tradePlan = null;
_root.UI系统.NPC商店WebView.activeShopId = "";
_root.UI系统.NPC商店WebView.collectionQuarantineSignature = "0:0";

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
    if (serializer == undefined || serializer.stringifySafe == undefined) return false;
    var payload:String = serializer.stringifySafe(response);
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
    return !isNaN(numberValue) && numberValue != Infinity && numberValue != -Infinity
        && numberValue >= 0 && Math.floor(numberValue) == numberValue;
};

_root.UI系统.NPC商店WebView.projectLegacyIdentityField = function(value, itemName:String):String {
    if (typeof value != "string") return itemName;
    var projected:String = String(value);
    var start:Number = 0;
    var end:Number = projected.length - 1;
    while (start <= end && this.isLegacyIdentityWhitespace(projected.charCodeAt(start))) start++;
    while (end >= start && this.isLegacyIdentityWhitespace(projected.charCodeAt(end))) end--;
    if (start > end || projected.substring(start, end + 1).toLowerCase() == "undefined") return itemName;
    return projected;
};

_root.UI系统.NPC商店WebView.isLegacyIdentityWhitespace = function(code:Number):Boolean {
    return code <= 32 || code == 160;
};

_root.UI系统.NPC商店WebView.beginCollectionSnapshot = function(shopId:String):Void {
    // 交易计划是一次性的，显式重同步后必须重新预览；资源 lease 则只在切换商店或资源变化时轮换。
    this.batchPlan = null;
    this.tradePlan = null;
    if (this.activeShopId == shopId && this.sessionNonce != undefined && this.sessionNonce != "") return;
    this.sessionSeq++;
    this.leaseSeq = 0;
    this.sessionNonce = "npc" + getTimer() + "." + this.sessionSeq;
    this.activeShopId = shopId;
    this.collectionLeases = {};
    this.collectionLeaseIds = {};
};

_root.UI系统.NPC商店WebView.issueCollectionLease = function(viewId:String, key:String, count:Number):String {
    var viewIds:Object = this.collectionLeaseIds[viewId];
    if (viewIds == undefined) {
        viewIds = {};
        this.collectionLeaseIds[viewId] = viewIds;
    }
    var identity:String = "$" + key;
    var existingToken:String = viewIds[identity] == undefined ? "" : String(viewIds[identity]);
    var existing:Object = existingToken == "" ? null : this.collectionLeases[existingToken];
    if (existing != null && existing.shopId == this.activeShopId
            && existing.viewId == viewId && existing.key == key && Number(existing.count) == Number(count)) {
        return existingToken;
    }
    if (existingToken != "") delete this.collectionLeases[existingToken];
    this.leaseSeq++;
    var token:String = this.sessionNonce + ".c" + this.leaseSeq;
    viewIds[identity] = token;
    this.collectionLeases[token] = {shopId:this.activeShopId, viewId:viewId, key:key, count:Number(count)};
    return token;
};

_root.UI系统.NPC商店WebView.pruneCollectionLeases = function(viewId:String, seen:Object):Void {
    var viewIds:Object = this.collectionLeaseIds[viewId];
    if (viewIds == undefined) return;
    for (var identity:String in viewIds) {
        if (seen[identity] === true) continue;
        delete this.collectionLeases[String(viewIds[identity])];
        delete viewIds[identity];
    }
};

_root.UI系统.NPC商店WebView.getBuyRatePermille = function():Number {
    var ratePermille:Number = 1000;
    if (_root.主角被动技能 != undefined && _root.主角被动技能.口才 != undefined
            && _root.主角被动技能.口才.启用) {
        var level:Number = Number(_root.主角被动技能.口才.等级);
        var discountPermille:Number =
            org.flashNight.gesh.number.NumberUtil.multiplySafeNonNegativeIntegers(level, 30);
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(discountPermille)) return NaN;
        ratePermille = org.flashNight.gesh.number.NumberUtil.subtractSafeIntegers(
            1000, discountPermille);
    }
    return org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(ratePermille)
        ? ratePermille : NaN;
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
    var equipment:Boolean = org.flashNight.arki.item.ItemUtil.isEquipment(resolved.itemName);
    var bagCapacity:Number = _root.物品栏 == undefined || _root.物品栏.背包 == undefined
        ? 50 : Number(_root.物品栏.背包.capacity);
    if (isNaN(bagCapacity) || bagCapacity < 1) bagCapacity = 50;
    var technicalLimit:Number = equipment ? Math.floor(bagCapacity) : 999999;
    var raw:Object = resolved.raw;
    if (typeof raw != "string" && raw.purchaseLimit != undefined) {
        var configured:Number = Number(raw.purchaseLimit);
        if (!isNaN(configured) && Math.floor(configured) == configured && configured >= 1) {
            technicalLimit = Math.min(technicalLimit, configured);
        }
    }
    if (org.flashNight.arki.item.ItemUtil.isInformation(resolved.itemName)) {
        technicalLimit = Math.min(technicalLimit,
            org.flashNight.arki.item.ItemUtil.getInformationRemaining(resolved.itemName));
    }
    return Math.max(0, technicalLimit);
};

_root.UI系统.NPC商店WebView.buildCatalog = function(
        shopId:String, buyRatePermille:Number):Array {
    var result:Array = [];
    var shop:Object = _root.shops == undefined ? null : _root.shops[shopId];
    if (shop == null) return result;
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(buyRatePermille)) return null;
    var procurementIndex:Object = org.flashNight.arki.item.ProcurementPlanService.buildDemandIndex();
    var keys:Array = [];
    for (var key in shop) {
        var index:Number = Number(key);
        if (!isNaN(index) && Math.floor(index) == index && index >= 0) keys.push(index);
    }
    keys.sort(Array.NUMERIC);
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
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(basePrice)) return null;
        var unitPrice:Number = org.flashNight.gesh.number.NumberUtil.floorPermille(
            basePrice, buyRatePermille);
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(unitPrice)) return null;
        var catalogItem:Object = {
            catalogIndex:keys[i],
            itemName:resolved.itemName,
            displayName:this.projectLegacyIdentityField(itemData.displayname, resolved.itemName),
            icon:this.projectLegacyIdentityField(itemData.icon, resolved.itemName),
            majorType:String(itemData.type || ""),
            use:String(itemData.use || ""),
            actionType:String(itemData.actiontype || ""),
            weaponType:String(itemData.weapontype || ""),
            setId:String(itemData.setId || ""),
            setName:String(itemData.setName || ""),
            setOrder:Number(itemData.setOrder || 0),
            basePrice:basePrice,
            unitPrice:unitPrice,
            maxQuantity:this.getPurchaseLimit(resolved),
            requiredInfo:requiredInfo,
            locked:locked
        };
        var balanceSummary:Object = org.flashNight.arki.item.InventoryPanelService.buildBalanceSummary(
            itemData,
            org.flashNight.arki.item.ItemUtil.getRawBalanceData(resolved.itemName),
            "data"
        );
        if (balanceSummary != null) catalogItem.balanceSummary = balanceSummary;
        var procurement:Object = procurementIndex.byItem[resolved.itemName];
        if (procurement != undefined) catalogItem.procurement = procurement;
        result.push(catalogItem);
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
    var seen:Object = {};
    var values:Object = collection == undefined ? {} : collection.getItems();
    var names:Array = [];
    for (var name in values) {
        var rawQuantity = values[name];
        var projectedQuantity:Number = Number(rawQuantity);
        if (typeof rawQuantity == "number" && !isNaN(projectedQuantity)
                && isFinite(projectedQuantity) && projectedQuantity > 0
                && Math.floor(projectedQuantity) == projectedQuantity
                && projectedQuantity <= 9007199254740991) names.push(String(name));
    }
    names.sort();
    for (var i:Number = 0; i < names.length; i++) {
        var itemName:String = names[i];
        var quantity:Number = Number(values[itemName]);
        var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(itemName);
        if (itemData == null) continue;
        seen["$" + itemName] = true;
        slots.push({
            physicalSlot:i,
            collectionKey:itemName,
            occupied:true,
            slotLease:this.issueCollectionLease(viewId, itemName, quantity),
            item:{
                itemKind:"stack",
                name:itemName,
                displayName:this.projectLegacyIdentityField(itemData.displayname, itemName),
                icon:this.projectLegacyIdentityField(itemData.icon, itemName),
                majorType:String(itemData.type || "收集品"),
                use:String(itemData.use || ""),
                quantity:quantity,
                enhancementLevel:0,
                rarity:String(itemData.rarity || itemData.品质 || "")
            }
        });
    }
    this.pruneCollectionLeases(viewId, seen);
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

_root.UI系统.NPC商店WebView.getCollectionQuarantineCount = function(collection:Object):Number {
    if (collection == undefined) return 0;
    var count:Number = collection.getQuarantinedEntryCount == undefined
        ? 0 : Number(collection.getQuarantinedEntryCount());
    if (isNaN(count) || !isFinite(count) || count < 0 || Math.floor(count) != count) count = 0;
    // getItems() 正常只含合法活跃值；仍扫描一次，统计绕过 collection API 的直接污染。
    // 只输出总数，绝不输出键名或原值。
    var values:Object = collection.getItems == undefined ? {} : collection.getItems();
    for (var key in values) {
        var rawValue = values[key];
        var value:Number = Number(rawValue);
        if (Number(rawValue) > 0 && (typeof rawValue != "number"
                || isNaN(value) || !isFinite(value) || Math.floor(value) != value
                || value > 9007199254740991)) count++;
    }
    return count;
};

_root.UI系统.NPC商店WebView.logCollectionQuarantineState = function():Void {
    var materialCount:Number = this.getCollectionQuarantineCount(_root.收集品栏.材料);
    var intelligenceCount:Number = this.getCollectionQuarantineCount(_root.收集品栏.情报);
    var signature:String = materialCount + ":" + intelligenceCount;
    if (signature == this.collectionQuarantineSignature) return;
    this.collectionQuarantineSignature = signature;
    this.log("diagnostic event=collection_quarantine_state materialCount="
        + materialCount + " intelligenceCount=" + intelligenceCount);
};

_root.UI系统.NPC商店WebView.buildState = function(shopId:String):Object {
    // 背包只由 inventory-domain 投影；NPC 域不再嵌套第二份背包快照与 lease 生命周期。
    this.beginCollectionSnapshot(shopId);
    this.logCollectionQuarantineState();
    var balance:Number = Number(_root.金钱);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(balance)) {
        return this.fail("invalid_price");
    }
    var buyRatePermille:Number = this.getBuyRatePermille();
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(buyRatePermille)) {
        return this.fail("invalid_price");
    }
    var catalog:Array = this.buildCatalog(shopId, buyRatePermille);
    if (catalog == null) return this.fail("invalid_price");
    var materialView:Object = this.buildCollectionView("material", _root.收集品栏.材料);
    var intelligenceView:Object = this.buildCollectionView("intelligence", _root.收集品栏.情报);
    return {
        success:true,
        v:1,
        shopId:shopId,
        balance:balance,
        buyRatePermille:buyRatePermille,
        catalog:catalog,
        layout:this.buildLayout(shopId),
        views:{
            material:materialView,
            intelligence:intelligenceView
        }
    };
};

// 资产提交后的快照只是响应投影。它失败时仍返回成功 finality，要求 Web 主动刷新；
// 绝不能把已经完成的买卖伪装成失败并诱发同一请求重放。
_root.UI系统.NPC商店WebView.buildPostCommitState = function(
        shopId:String, operation:String):Object {
    try {
        var state:Object = this.buildState(shopId);
        if (state != null && state.success === true) {
            state.operation = operation;
            return state;
        }
        trace("[NpcShop] post-commit state unavailable operation=" + operation);
    } catch (postCommitStateError) {
        trace("[NpcShop] post-commit state failed operation=" + operation
            + " error=" + postCommitStateError);
    }
    return {success:true, v:1, operation:operation,
        shopId:shopId, refreshDeferred:true};
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
        displayname:this.projectLegacyIdentityField(tt.displayname, itemName),
        // wire 由 sendResponse 的 stringifySafe 统一转义；保留原始 htmlText 双引号属性。
        descHTML:String(tt.descHTML || ""),
        introHTML:String(tt.introHTML || "")
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
    var maxQuantity:Number = org.flashNight.arki.item.ItemUtil.isEquipment(itemName)
        ? 1 : this.getPurchaseLimit(resolved);
    if (quantity > maxQuantity) return this.fail("invalid_quantity");
    var requiredInfo:String = typeof resolved.raw == "string" || resolved.raw.requiredInfo == undefined
        ? "" : String(resolved.raw.requiredInfo);
    if (requiredInfo != "" && _root.收集品栏.情报.getValue(requiredInfo) <= 0) return this.fail("locked");
    var basePrice:Number = Number(itemData.price);
    var baseAmount:Number = org.flashNight.gesh.number.NumberUtil.multiplySafeNonNegativeIntegers(
        basePrice, quantity);
    var total:Number = org.flashNight.gesh.number.NumberUtil.floorPermille(
        baseAmount, this.getBuyRatePermille());
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(total)) {
        return this.fail("invalid_price");
    }
    var balance:Number = Number(_root.金钱);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(balance)) {
        return this.fail("invalid_price");
    }
    if (total > balance) return this.fail("insufficient_money");
    var projectedBalance:Number = org.flashNight.gesh.number.NumberUtil.subtractSafeIntegers(
        balance, total);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(projectedBalance)) {
        return this.fail("invalid_price");
    }
    var destination:String = this.resolvePurchaseDestination(itemName);
    var assetContext:Object = {
        source:"npc_shop_purchase", reason:"legacy_buy", mergeScope:"operation"
    };
    var buyAssetSnapshot:Object =
        org.flashNight.arki.item.ItemUtil.capturePlayerAssetSnapshot();
    var assetTransaction:Object =
        org.flashNight.arki.item.PlayerAssetTransaction.begin(assetContext);
    try {
        // 入包与扣款共享存档权威；缺少存档系统时首写前失败。
        org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
            _root.存档系统);
        if (!org.flashNight.arki.item.ItemUtil.singleAcquire(itemName, quantity, assetContext)) {
            org.flashNight.arki.item.ItemUtil.restorePlayerAssetSnapshot(
                buyAssetSnapshot);
            org.flashNight.arki.item.PlayerAssetTransaction.rollback(assetTransaction);
            return this.fail(destination == "intelligence" ? "destination_full" : "inventory_full");
        }
        var moneyBeforeBuy:Number = balance;
        try {
            _root.金钱 = projectedBalance;
        } finally {
            var committedBuyLoss:Number = moneyBeforeBuy - Number(_root.金钱);
            if (committedBuyLoss > total) committedBuyLoss = total;
            if (committedBuyLoss > 0 && !isNaN(committedBuyLoss)) {
                org.flashNight.arki.item.PlayerAssetTransaction.recordEffect(
                    "loss", "money", "金钱", committedBuyLoss, assetContext);
            }
        }
        org.flashNight.arki.item.PlayerAssetTransaction.commit(assetTransaction);
    } catch (buyAssetError) {
        var buyRestored:Boolean =
            org.flashNight.arki.item.ItemUtil.restorePlayerAssetSnapshot(
                buyAssetSnapshot);
        org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
            assetTransaction, !buyRestored);
        throw buyAssetError;
    }
    try {
        if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
            org.flashNight.arki.achievement.AchievementMetrics.record("购买物品次数", 1);
            org.flashNight.arki.achievement.AchievementMetrics.record("购买花费金币", total);
        }
    } catch (buyMetricError) {
        trace("[NpcShop] post-commit buy metric failed: " + buyMetricError);
    }
    try {
        if (_root.soundEffectManager != undefined) {
            _root.soundEffectManager.playSound("收银机.mp3");
        }
    } catch (buySoundError) {
        trace("[NpcShop] post-commit buy sound failed: " + buySoundError);
    }
    var state:Object = this.buildPostCommitState(shopId, "buy");
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
    if (lease == undefined || lease.shopId != this.activeShopId
            || lease.viewId != "material" || lease.key != key) return this.fail("stale_state");
    var count:Number = Number(_root.收集品栏.材料.getValue(key));
    if (count != Number(lease.count)) return this.fail("stale_state");
    return {success:true, collection:_root.收集品栏.材料, key:key, count:count};
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
    var balance:Number = Number(_root.金钱);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(balance)) {
        return this.fail("invalid_price");
    }
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
            var money:Number = Number(price.总价);
            if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(quantity)
                    || !org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(money)) {
                return this.fail("invalid_price");
            }
            entries.push({slot:slot, ref:item, name:itemName, count:quantity, money:money});
            nameQuantity = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
                nameQuantity, quantity);
            nameMoney = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
                nameMoney, money);
            if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(nameQuantity)
                    || !org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(nameMoney)) {
                return this.fail("invalid_price");
            }
        }
        if (nameQuantity > 0) {
            var data:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(itemName);
            summary.push({itemName:itemName,
                displayName:this.projectLegacyIdentityField(
                    data == null ? undefined : data.displayname, itemName),
                icon:this.projectLegacyIdentityField(
                    data == null ? undefined : data.icon, itemName),
                quantity:nameQuantity, money:nameMoney});
            totalQuantity = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
                totalQuantity, nameQuantity);
            totalMoney = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
                totalMoney, nameMoney);
            if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(totalQuantity)
                    || !org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(totalMoney)) {
                return this.fail("invalid_price");
            }
        }
    }
    if (entries.length == 0) return this.fail("nothing_to_sell");
    this.batchSeq++;
    var token:String = "npcbatch" + getTimer() + "." + this.batchSeq;
    this.batchPlan = {token:token, entries:entries, totalMoney:totalMoney,
        totalQuantity:totalQuantity, balance:balance};
    return {success:true, v:1, batchToken:token, balance:balance,
        summary:summary, totalQuantity:totalQuantity, totalMoney:totalMoney, skipped:skipped};
};

_root.UI系统.NPC商店WebView.executeBatchSell = function(params:Object):Object {
    var shopId:String = params == undefined ? "" : String(params.shopId);
    if (shopId == "" || _root.shops == undefined || _root.shops[shopId] == undefined) return this.fail("shop_not_found");
    if (shopId != this.activeShopId) return this.fail("stale_state");
    var plan:Object = this.batchPlan;
    if (plan == null || String(params.expectedBatchToken || "") != String(plan.token)) return this.fail("stale_state");
    var balance:Number = Number(_root.金钱);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(balance)
            || !org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(Number(plan.totalMoney))) {
        this.batchPlan = null;
        return this.fail("invalid_price");
    }
    if (balance != Number(plan.balance)) {
        this.batchPlan = null;
        return this.fail("stale_state");
    }
    var projectedBalance:Number = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
        balance, Number(plan.totalMoney));
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(projectedBalance)) {
        this.batchPlan = null;
        return this.fail("invalid_price");
    }
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
    var assetContext:Object = {
        source:"npc_shop_sale", reason:"batch_sell", mergeScope:"operation"
    };
    var batchAssetSnapshot:Object =
        org.flashNight.arki.item.ItemUtil.capturePlayerAssetSnapshot();
    var assetTransaction:Object =
        org.flashNight.arki.item.PlayerAssetTransaction.begin(assetContext);
    try {
        // 从首个 remove 开始已可能在同步监听器抛错前完成写入。
        org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
            _root.存档系统);
        for (var j:Number = 0; j < plan.entries.length; j++) {
            var sellEntry:Object = plan.entries[j];
            var soldBefore:Object = bag.getItem(String(sellEntry.slot));
            try {
                bag.remove(String(sellEntry.slot));
            } finally {
                var soldAfter:Object = bag.getItem(String(sellEntry.slot));
                if (soldBefore != null && soldAfter !== soldBefore) {
                    var soldIsEquipment:Boolean =
                        org.flashNight.arki.item.ItemUtil.isEquipment(String(sellEntry.name));
                    var soldContext:Object = assetContext;
                    if (soldIsEquipment && sellEntry.ref.value != undefined
                            && sellEntry.ref.value.tier != undefined) {
                        soldContext = {
                            source:assetContext.source, reason:assetContext.reason,
                            mergeScope:assetContext.mergeScope,
                            tier:String(sellEntry.ref.value.tier)
                        };
                    }
                    org.flashNight.arki.item.PlayerAssetTransaction.recordEffect(
                        "loss", soldIsEquipment ? "equip" : "item",
                        String(sellEntry.name), soldIsEquipment ? 1 : Number(sellEntry.count),
                        soldContext);
                }
            }
        }
        var moneyBeforeBatchSale:Number = balance;
        try {
            _root.金钱 = projectedBalance;
        } finally {
            var committedBatchMoney:Number = Number(_root.金钱) - moneyBeforeBatchSale;
            if (committedBatchMoney > Number(plan.totalMoney)) {
                committedBatchMoney = Number(plan.totalMoney);
            }
            if (committedBatchMoney > 0 && !isNaN(committedBatchMoney)) {
                org.flashNight.arki.item.PlayerAssetTransaction.recordEffect(
                    "gain", "money", "金钱", committedBatchMoney, assetContext);
            }
        }
        org.flashNight.arki.item.PlayerAssetTransaction.commit(assetTransaction);
    } catch (batchSaleError) {
        // 批售是多资源领域操作；listener fault 时必须恢复出售前容器/余额，
        // 不能把“已删物品、未加金币”当成可接受的 partial finality。
        var batchRestored:Boolean =
            org.flashNight.arki.item.ItemUtil.restorePlayerAssetSnapshot(
                batchAssetSnapshot);
        org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
            assetTransaction, !batchRestored);
        this.batchPlan = null;
        // ArrayInventory.remove 的 ItemRemoved 在索引维护前同步派发；
        // listener fault 时立即按权威 items 重建，不能把脏索引留给下一请求。
        try {
            if (bag != undefined && bag.setIndexes != undefined) bag.setIndexes(null);
        } catch (batchIndexRepairError) {
            this.log("batch sale index repair failed: " + String(batchIndexRepairError));
        }
        throw batchSaleError;
    }
    for (j = 0; j < plan.entries.length; j++) {
        sellEntry = plan.entries[j];
        try {
            org.flashNight.arki.item.InventoryPanelService.invalidateExternalSlot(
                "背包", Number(sellEntry.slot));
        } catch (batchInvalidateError) {
            // 失效通知只是已提交资产的观察投影；单个监听器不能阻断其余通知和回包。
            trace("[NpcShop] post-commit batch invalidation failed: "
                + batchInvalidateError);
        }
    }
    try {
        if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
            org.flashNight.arki.achievement.AchievementMetrics.record("出售次数", plan.entries.length);
            org.flashNight.arki.achievement.AchievementMetrics.record("出售所得金币", Number(plan.totalMoney));
        }
    } catch (batchSaleMetricError) {
        trace("[NpcShop] post-commit batch-sale metric failed: " + batchSaleMetricError);
    }
    try {
        if (_root.soundEffectManager != undefined) {
            _root.soundEffectManager.playSound("收银机.mp3");
        }
    } catch (batchSaleSoundError) {
        trace("[NpcShop] post-commit batch-sale sound failed: " + batchSaleSoundError);
    }
    this.batchPlan = null;
    var state:Object = this.buildPostCommitState(
        String(params.shopId), "batchSell");
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
    var buyRatePermille:Number = this.getBuyRatePermille();
    var baseAmount:Number = org.flashNight.gesh.number.NumberUtil.multiplySafeNonNegativeIntegers(
        basePrice, quantity);
    var unitPrice:Number = org.flashNight.gesh.number.NumberUtil.floorPermille(
        basePrice, buyRatePermille);
    var total:Number = org.flashNight.gesh.number.NumberUtil.floorPermille(
        baseAmount, buyRatePermille);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(unitPrice)
            || !org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(total)) {
        return this.fail("invalid_price");
    }
    return {
        success:true,
        catalogIndex:catalogIndex,
        itemName:resolved.itemName,
        displayName:this.projectLegacyIdentityField(itemData.displayname, resolved.itemName),
        icon:this.projectLegacyIdentityField(itemData.icon, resolved.itemName),
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
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(quantity)) {
        return this.fail("invalid_price");
    }
    var priceInfo:Object = _root.物品UI函数.计算售卖总价(item, quantity);
    var money:Number = Number(priceInfo.总价);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(money)) {
        return this.fail("invalid_price");
    }
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
        displayName:this.projectLegacyIdentityField(itemData.displayname, itemName),
        icon:this.projectLegacyIdentityField(itemData.icon, itemName),
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
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(quantity)) {
            return this.fail("invalid_price");
        }
        var priceInfo:Object = _root.物品UI函数.计算售卖总价(current, quantity);
        var money:Number = Number(priceInfo.总价);
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(money)) {
            return this.fail("invalid_price");
        }
        entries.push({
            success:true,
            identity:"bag:" + slot,
            kind:"bag",
            collection:bag,
            key:String(slot),
            slot:slot,
            ref:current,
            itemName:itemName,
            displayName:this.projectLegacyIdentityField(itemData.displayname, itemName),
            icon:this.projectLegacyIdentityField(itemData.icon, itemName),
            oldCount:quantity,
            quantity:quantity,
            money:money,
            full:true,
            plainOnly:true,
            returnedMods:[]
        });
        totalQuantity = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
            totalQuantity, quantity);
        totalMoney = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
            totalMoney, money);
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(totalQuantity)
                || !org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(totalMoney)) {
            return this.fail("invalid_price");
        }
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
        displayName:this.projectLegacyIdentityField(itemData.displayname, itemName),
        icon:this.projectLegacyIdentityField(itemData.icon, itemName),
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
    var ownershipTotals:Object = {};
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
            ownershipTotals[purchase.itemName] = Number(ownershipTotals[purchase.itemName] || 0)
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
        // returnedMods 是玩家原已拥有的装备内嵌配件，只迁回 collection；
        // ownershipDelta 仅保留本次真正购买的数量，防止迁移被播成新获得。
        result.push({
            name:collectionName,
            value:Number(collectionTotals[collectionName]),
            ownershipDelta:Number(ownershipTotals[collectionName] || 0)
        });
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
    var missingCollection:Number = 0;
    var mergeable:Object = {};
    var informationTotals:Object = {};
    for (var j:Number = 0; j < plan.acquireItems.length; j++) {
        var requested:Object = plan.acquireItems[j];
        var name:String = String(requested.name);
        var quantity:Number = Number(requested.value);
        if (org.flashNight.arki.item.ItemUtil.isInformation(name)) {
            informationTotals[name] = Number(informationTotals[name] || 0) + quantity;
            continue;
        }
        if (org.flashNight.arki.item.ItemUtil.isMaterial(name)
                || this.resolvePurchaseDestination(name) == "quickslot") continue;
        if (org.flashNight.arki.item.ItemUtil.isEquipment(name)) {
            required += quantity;
        } else {
            mergeable[name] = true;
        }
    }
    // buildAcquireItems 已聚合同名 collection；这里仍按函数自身契约防御任意内部调用方，
    // 避免同一情报拆成多行时逐行低于剩余、合计却超限而误报 inventory_full。
    for (var informationName:String in informationTotals) {
        missingCollection += Math.max(0, Number(informationTotals[informationName])
            - org.flashNight.arki.item.ItemUtil.getInformationRemaining(informationName));
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
    return {
        requiredSlots:required,
        availableSlots:available,
        missingSlots:Math.max(0, required - available),
        missingCollection:missingCollection,
        enough:required <= available && missingCollection <= 0,
        error:missingCollection > 0 ? "destination_full" : (required <= available ? "" : "inventory_full")
    };
};

_root.UI系统.NPC商店WebView.checkTradeCapacity = function(plan:Object):Boolean {
    return this.analyzeTradeCapacity(plan).enough;
};

_root.UI系统.NPC商店WebView.getPurchaseBounds = function(plan:Object, target:Object):Object {
    var otherBuyTotal:Number = org.flashNight.gesh.number.NumberUtil.subtractSafeIntegers(
        Number(plan.buyTotal), Number(target.total));
    var budget:Number = org.flashNight.gesh.number.NumberUtil.subtractSafeIntegers(
        Number(plan.grossBalance), otherBuyTotal);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(otherBuyTotal)
            || !org.flashNight.gesh.number.NumberUtil.isSafeInteger(budget)) return null;
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
        maxPurchasable:Math.min(limit, Math.min(maxAffordable, maxByCapacity)),
        limitingReason:Math.min(maxAffordable, maxByCapacity) < limit
            ? (maxByCapacity <= maxAffordable
                ? (target.destinationView == "intelligence" ? "destination_full" : "inventory_full")
                : "insufficient_money")
            : ""
    };
};

_root.UI系统.NPC商店WebView.executeTradePreview = function(params:Object):Object {
    var shopId:String = params == undefined ? "" : String(params.shopId);
    if (shopId == "" || _root.shops == undefined || _root.shops[shopId] == undefined) return this.fail("shop_not_found");
    if (shopId != this.activeShopId) return this.fail("stale_state");
    var purchases:Array = params.purchases instanceof Array ? params.purchases : [];
    var sales:Array = params.sales instanceof Array ? params.sales : [];
    if (purchases.length > 40 || sales.length > 50 || purchases.length + sales.length < 1) return this.fail("invalid_payload");
    var balance:Number = Number(_root.金钱);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(balance)) {
        return this.fail("invalid_price");
    }
    var plan:Object = {shopId:shopId, purchases:[], sales:[], publicSales:[],
        acquireItems:[], buyTotal:0, sellTotal:0, balance:balance};
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
        plan.buyTotal = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
            Number(plan.buyTotal), Number(purchase.total));
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(plan.buyTotal)) {
            return this.fail("invalid_price");
        }
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
        plan.sellTotal = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
            Number(plan.sellTotal), Number(saleGroup.money));
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(plan.sellTotal)) {
            return this.fail("invalid_price");
        }
    }
    plan.grossBalance = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
        plan.balance, plan.sellTotal);
    plan.netDelta = org.flashNight.gesh.number.NumberUtil.subtractSafeIntegers(
        plan.sellTotal, plan.buyTotal);
    plan.projectedBalance = org.flashNight.gesh.number.NumberUtil.addSafeIntegers(
        plan.balance, plan.netDelta);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(plan.grossBalance)
            || !org.flashNight.gesh.number.NumberUtil.isSafeInteger(plan.netDelta)
            || !org.flashNight.gesh.number.NumberUtil.isSafeInteger(plan.projectedBalance)) {
        return this.fail("invalid_price");
    }
    plan.acquireItems = this.buildAcquireItems(plan.purchases, plan.sales);
    var enoughMoney:Boolean = plan.projectedBalance >= 0;
    var capacity:Object = this.analyzeTradeCapacity(plan);
    var enoughSpace:Boolean = capacity.enough;
    for (var purchaseIndex:Number = 0; purchaseIndex < plan.purchases.length; purchaseIndex++) {
        var bounds:Object = this.getPurchaseBounds(plan, plan.purchases[purchaseIndex]);
        if (bounds == null) return this.fail("invalid_price");
        plan.purchases[purchaseIndex].purchaseLimit = bounds.purchaseLimit;
        plan.purchases[purchaseIndex].maxAffordable = bounds.maxAffordable;
        plan.purchases[purchaseIndex].maxByCapacity = bounds.maxByCapacity;
        plan.purchases[purchaseIndex].maxPurchasable = bounds.maxPurchasable;
        plan.purchases[purchaseIndex].limitingReason = bounds.limitingReason;
    }
    // 与 publicSales 同理：内部 purchase 对象残留 success 等私有键，
    // 桥层白名单只认契约字段，出站前必须投影，否则含购买的预览会被判为回包不完整。
    var publicPurchases:Array = [];
    for (var publicIndex:Number = 0; publicIndex < plan.purchases.length; publicIndex++) {
        var publicPurchase:Object = plan.purchases[publicIndex];
        publicPurchases.push({
            catalogIndex:publicPurchase.catalogIndex,
            itemName:publicPurchase.itemName,
            displayName:publicPurchase.displayName,
            icon:publicPurchase.icon,
            quantity:publicPurchase.quantity,
            unitPrice:publicPurchase.unitPrice,
            total:publicPurchase.total,
            maxQuantity:publicPurchase.maxQuantity,
            itemKind:publicPurchase.itemKind,
            destinationView:publicPurchase.destinationView,
            purchaseLimit:publicPurchase.purchaseLimit,
            maxAffordable:publicPurchase.maxAffordable,
            maxByCapacity:publicPurchase.maxByCapacity,
            maxPurchasable:publicPurchase.maxPurchasable,
            limitingReason:publicPurchase.limitingReason
        });
    }
    this.tradeSeq++;
    plan.token = "npctrade" + getTimer() + "." + this.tradeSeq;
    this.tradePlan = plan;
    return {
        success:true,
        v:1,
        shopId:plan.shopId,
        tradeToken:plan.token,
        purchaseLines:publicPurchases,
        saleLines:plan.publicSales,
        buyTotal:plan.buyTotal,
        sellTotal:plan.sellTotal,
        netDelta:plan.netDelta,
        projectedBalance:plan.projectedBalance,
        requiredSlots:capacity.requiredSlots,
        availableSlots:capacity.availableSlots,
        missingSlots:capacity.missingSlots,
        canCommit:enoughMoney && enoughSpace,
        blockingError:enoughMoney ? (enoughSpace ? "" : capacity.error) : "insufficient_money"
    };
};

_root.UI系统.NPC商店WebView.validateTradePlan = function(plan:Object):Object {
    if (plan == null || String(plan.shopId) != this.activeShopId) {
        return this.fail("stale_state");
    }
    var currentBalance:Number = Number(_root.金钱);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(currentBalance)
            || !org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(Number(plan.balance))) {
        return this.fail("invalid_price");
    }
    if (currentBalance != Number(plan.balance)) return this.fail("stale_state");
    var buyTotal:Number = 0;
    for (var i:Number = 0; i < plan.purchases.length; i++) {
        var oldPurchase:Object = plan.purchases[i];
        var purchase:Object = this.resolveTradePurchase(plan.shopId, oldPurchase);
        if (!purchase.success || purchase.itemName != oldPurchase.itemName
                || Number(purchase.total) != Number(oldPurchase.total)) return this.fail("stale_state");
        buyTotal = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
            buyTotal, Number(purchase.total));
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(buyTotal)) {
            return this.fail("invalid_price");
        }
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
        var saleMoney:Number = Number(price.总价);
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(saleMoney)) {
            return this.fail("invalid_price");
        }
        if (saleMoney != Number(sale.money)) return this.fail("stale_state");
        sellTotal = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
            sellTotal, Number(sale.money));
        if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(sellTotal)) {
            return this.fail("invalid_price");
        }
    }
    if (buyTotal != Number(plan.buyTotal) || sellTotal != Number(plan.sellTotal)) return this.fail("stale_state");
    var grossBalance:Number = org.flashNight.gesh.number.NumberUtil.addSafeNonNegativeIntegers(
        currentBalance, sellTotal);
    var netDelta:Number = org.flashNight.gesh.number.NumberUtil.subtractSafeIntegers(
        sellTotal, buyTotal);
    var projectedBalance:Number = org.flashNight.gesh.number.NumberUtil.addSafeIntegers(
        currentBalance, netDelta);
    if (!org.flashNight.gesh.number.NumberUtil.isSafeNonNegativeInteger(grossBalance)
            || !org.flashNight.gesh.number.NumberUtil.isSafeInteger(netDelta)
            || !org.flashNight.gesh.number.NumberUtil.isSafeInteger(projectedBalance)) {
        return this.fail("invalid_price");
    }
    if (grossBalance != Number(plan.grossBalance)
            || netDelta != Number(plan.netDelta)
            || projectedBalance != Number(plan.projectedBalance)) return this.fail("stale_state");
    if (projectedBalance < 0) return this.fail("insufficient_money");
    var capacity:Object = this.analyzeTradeCapacity(plan);
    if (!capacity.enough) return this.fail(capacity.error);
    return {success:true};
};

_root.UI系统.NPC商店WebView.rollbackTradeSales = function(plan:Object):Boolean {
    for (var i:Number = plan.sales.length - 1; i >= 0; i--) {
        var sale:Object = plan.sales[i];
        if (sale.kind == "bag") {
            // acquire 预检失败时尚未产生购买写入；销售补偿使用
            // 无事件事务写，避免补偿 publish 再次抛错留下半恢复。
            var current:Object = sale.collection.getItem(sale.key);
            if (sale.full) {
                if (current != null && current !== sale.ref) return false;
                if (current == null
                        && sale.collection.transactionWrite(Number(sale.key), sale.ref) !== true) {
                    return false;
                }
            } else {
                if (current !== sale.ref) return false;
                var rollbackValueBefore:Number = Number(current.value);
                current.value = Number(sale.oldCount);
                if (sale.collection.transactionWrite(Number(sale.key), current) !== true) {
                    // transactionWrite 捕获的是同一对象引用；失败时显式把预写值
                    // 恢复到销售后的事实，随后由异常结算发布真实 loss。
                    current.value = rollbackValueBefore;
                    return false;
                }
            }
        } else {
            var current:Number = Number(sale.collection.getValue(sale.key));
            var restoreDelta:Number = Number(sale.oldCount) - current;
            if (restoreDelta != 0) {
                var restoreDeltas:Object = {};
                restoreDeltas[String(sale.key)] = restoreDelta;
                var restoreReceipt:Object = sale.collection.transactionApplyDeltas(restoreDeltas);
                if (restoreReceipt == null || restoreReceipt.success !== true) return false;
            }
        }
    }
    for (i = 0; i < plan.sales.length; i++) {
        sale = plan.sales[i];
        if (sale.kind == "bag") {
            var restoredItem:Object = sale.collection.getItem(sale.key);
            if (restoredItem !== sale.ref
                    || (!sale.full && Number(restoredItem.value) != Number(sale.oldCount))) return false;
        } else if (Number(sale.collection.getValue(sale.key)) != Number(sale.oldCount)) {
            return false;
        }
    }
    return true;
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
    var purchaseContext:Object = {
        source:"npc_shop_purchase", reason:"trade_commit", mergeScope:"operation"
    };
    var saleContext:Object = {
        source:"npc_shop_sale", reason:"trade_commit", mergeScope:"operation"
    };
    var tradeAssetSnapshot:Object =
        org.flashNight.arki.item.ItemUtil.capturePlayerAssetSnapshot();
    var assetTransaction:Object =
        org.flashNight.arki.item.PlayerAssetTransaction.begin(purchaseContext);
    try {
        org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
            _root.存档系统);
        for (var i:Number = 0; i < plan.sales.length; i++) {
            var sale:Object = plan.sales[i];
            var saleBeforeItem:Object = sale.kind == "bag"
                ? sale.collection.getItem(sale.key) : null;
            var saleBeforeCount:Number = sale.kind == "material"
                ? Number(sale.collection.getValue(sale.key))
                : (saleBeforeItem == null ? 0 : Number(saleBeforeItem.value));
            try {
                if (sale.full) sale.collection.remove(sale.key);
                else sale.collection.addValue(sale.key, -sale.quantity);
            } finally {
                var saleAfterItem:Object = sale.kind == "bag"
                    ? sale.collection.getItem(sale.key) : null;
                var committedSaleLoss:Number = 0;
                if (sale.kind == "material") {
                    committedSaleLoss = saleBeforeCount
                        - Number(sale.collection.getValue(sale.key));
                } else if (org.flashNight.arki.item.ItemUtil.isEquipment(
                        String(sale.itemName))) {
                    if (saleBeforeItem != null && saleAfterItem !== saleBeforeItem) {
                        committedSaleLoss = 1;
                    }
                } else if (saleBeforeItem != null) {
                    var saleAfterCount:Number = saleAfterItem == null
                        ? 0 : Number(saleAfterItem.value);
                    committedSaleLoss = saleBeforeCount - saleAfterCount;
                }
                if (committedSaleLoss > Number(sale.quantity)) {
                    committedSaleLoss = Number(sale.quantity);
                }
                if (committedSaleLoss > 0 && !isNaN(committedSaleLoss)) {
                    var saleIsEquipment:Boolean = sale.kind != "material"
                        && org.flashNight.arki.item.ItemUtil.isEquipment(String(sale.itemName));
                    var committedSaleContext:Object = saleContext;
                    if (saleIsEquipment && sale.ref.value != undefined
                            && sale.ref.value.tier != undefined) {
                        committedSaleContext = {
                            source:saleContext.source, reason:saleContext.reason,
                            mergeScope:saleContext.mergeScope,
                            tier:String(sale.ref.value.tier)
                        };
                    }
                    org.flashNight.arki.item.PlayerAssetTransaction.recordEffect(
                        "loss", sale.kind == "material" ? "material"
                            : (saleIsEquipment ? "equip" : "item"),
                        String(sale.itemName), committedSaleLoss,
                        committedSaleContext);
                }
            }
        }
        if (!org.flashNight.arki.item.ItemUtil.acquire(plan.acquireItems, purchaseContext)) {
            if (!org.flashNight.arki.item.ItemUtil.restorePlayerAssetSnapshot(
                    tradeAssetSnapshot)) throw "trade_sale_rollback_incomplete";
            org.flashNight.arki.item.PlayerAssetTransaction.rollback(assetTransaction);
            return this.fail("inventory_full");
        }
        for (var j:Number = 0; j < plan.sales.length; j++) {
            var sold:Object = plan.sales[j];
            if (sold.kind == "bag") {
                if (typeof sold.ref.value == "object" && sold.ref.value.mods instanceof Array) sold.ref.value.mods = [];
            }
        }
        var moneyBeforeTrade:Number = Number(_root.金钱);
        try {
            _root.金钱 = Number(plan.projectedBalance);
        } finally {
            var committedMoneyDelta:Number = Number(_root.金钱) - moneyBeforeTrade;
            if (committedMoneyDelta != 0 && !isNaN(committedMoneyDelta)) {
                org.flashNight.arki.item.PlayerAssetTransaction.recordEffect(
                    committedMoneyDelta > 0 ? "gain" : "loss", "money", "金钱",
                    Math.abs(committedMoneyDelta),
                    committedMoneyDelta > 0 ? saleContext : purchaseContext);
            }
        }
        // 买卖和余额已共同提交后才允许 durability；commit 隔离保存异常并
        // 保留 dirty，避免未知成功被客户端重放为第二次交易。
        org.flashNight.arki.item.PlayerAssetTransaction.requestStrongSave();
        org.flashNight.arki.item.PlayerAssetTransaction.commit(assetTransaction);
    } catch (tradeAssetError) {
        var tradeRestored:Boolean =
            org.flashNight.arki.item.ItemUtil.restorePlayerAssetSnapshot(
                tradeAssetSnapshot);
        org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
            assetTransaction, !tradeRestored);
        try {
            var tradeBag:Object = _root.物品栏 == undefined
                ? null : _root.物品栏.背包;
            if (tradeBag != null && tradeBag.setIndexes != undefined) {
                tradeBag.setIndexes(null);
            }
        } catch (tradeIndexRepairError) {
            this.log("trade index repair failed: " + String(tradeIndexRepairError));
        }
        throw tradeAssetError;
    }
    for (j = 0; j < plan.sales.length; j++) {
        sold = plan.sales[j];
        if (sold.kind == "bag") {
            try {
                org.flashNight.arki.item.InventoryPanelService.invalidateExternalSlot(
                    "背包", sold.slot);
            } catch (tradeInvalidateError) {
                trace("[NpcShop] post-commit trade invalidation failed: "
                    + tradeInvalidateError);
            }
        }
    }
    try {
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
    } catch (tradeMetricError) {
        trace("[NpcShop] post-commit trade metric failed: " + tradeMetricError);
    }
    try {
        if (_root.soundEffectManager != undefined) {
            _root.soundEffectManager.playSound("收银机.mp3");
        }
    } catch (tradeSoundError) {
        trace("[NpcShop] post-commit trade sound failed: " + tradeSoundError);
    }
    var state:Object = this.buildPostCommitState(shopId, "tradeCommit");
    state.trade = {buyTotal:plan.buyTotal, sellTotal:plan.sellTotal,
        netDelta:plan.netDelta};
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
    try {
        if (commandName == "buy") result = this.executeBuy(params);
        else if (commandName == "batchSell") result = this.executeBatchSell(params);
        else if (commandName == "tradeCommit") result = this.executeTradeCommit(params);
        else result = this.fail("unsupported_cmd");
    } finally {
        // 同步生命周期监听器仍可 let-it-crash，但不得将领域服务
        // 永久留在 busy，否则下一个已恢复的资产事务仍无法进入。
        this.busy = false;
    }
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
// A3: ordinary sell was never consumed by the production Web UI and its
// cross-domain postcondition could not be proven without an unnecessary global
// Inventory registry. Remove any stale hot-reload binding; tradeCommit is the
// sole production sale write.
delete _root.gameCommands["npcShopSell"];
_root.gameCommands["npcShopSnapshot"] = function(params) { _root.UI系统.NPC商店WebView.handle("snapshot", params); };
_root.gameCommands["npcShopTooltip"] = function(params) { _root.UI系统.NPC商店WebView.handle("tooltip", params); };
_root.gameCommands["npcShopBuy"] = function(params) { _root.UI系统.NPC商店WebView.handle("buy", params); };
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
            && source != "tablet_contacts" && source != "npc_shop_refresh") source = "world_npc";
    var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
        "npcshop",
        source,
        [],
        [{name:"shopId", value:shopId}]
    );
    return _root.server.sendSocketMessage(payload);
};
