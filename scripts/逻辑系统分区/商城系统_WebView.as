// 商城系统_WebView.as — WebView 面板侧商城命令
// JSON 序列化器挂到 _root.UI系统 命名空间，确保 gameCommands 闭包能访问且不污染 root 顶层
// 使用 LiteJSON 而非 FastJSON：FastJSON 按对象身份缓存，同一数组引用内容变化后仍返回旧字符串
_root.UI系统 = _root.UI系统 || {};
_root.UI系统.商城WebView = _root.UI系统.商城WebView || {};
_root.UI系统.商城WebView.json = new LiteJSON();
_root.UI系统.商城WebView.purchasedTokenSeq = Number(_root.UI系统.商城WebView.purchasedTokenSeq) || 0;
_root.UI系统.商城WebView.checkoutSeq = Number(_root.UI系统.商城WebView.checkoutSeq) || 0;
_root.UI系统.商城WebView.checkoutPlan = null;
_root.UI系统.商城WebView.rotatePurchasedToken = function():String {
    this.purchasedTokenSeq++;
    this.purchasedToken = "shop" + getTimer() + "." + this.purchasedTokenSeq;
    return this.purchasedToken;
};
_root.UI系统.商城WebView.rotatePurchasedToken();
// 暂停 lease id（由 PauseManager.lease 返回；undefined 表示当前未持有 lease）
_root.UI系统.商城WebView.pauseLeaseId = undefined;
// JSON/AS2 Number 安全域内的单行技术护栏；不是设计配额。装备与情报另受动态容量约束。
_root.UI系统.商城WebView.maxStackPurchaseQuantity = 999999;

// KShop 的旧数据兼容只发生在 AS2 权威投影入口。越过本层后，
// Host/Web 必须把 displayname/icon 当作已经完整的独立字段，不能再猜内部名。
_root.UI系统.商城WebView.projectLegacyIdentityField = function(value, itemName:String):String {
    if (typeof value != "string") return itemName;
    var projected:String = String(value);
    var start:Number = 0;
    var end:Number = projected.length - 1;
    while (start <= end && this.isLegacyIdentityWhitespace(projected.charCodeAt(start))) start++;
    while (end >= start && this.isLegacyIdentityWhitespace(projected.charCodeAt(end))) end--;
    if (start > end || projected.substring(start, end + 1).toLowerCase() == "undefined") return itemName;
    return projected;
};

_root.UI系统.商城WebView.isLegacyIdentityWhitespace = function(code:Number):Boolean {
    return code <= 32 || code == 160;
};

_root.UI系统.商城WebView.getPurchaseLimit = function(itemName:String):Number {
    if (org.flashNight.arki.item.ItemUtil.isEquipment(itemName)) return 1;
    if (org.flashNight.arki.item.ItemUtil.isInformation(itemName)) {
        return Math.min(this.maxStackPurchaseQuantity,
            org.flashNight.arki.item.ItemUtil.getInformationRemaining(itemName));
    }
    return this.maxStackPurchaseQuantity;
};

_root.UI系统.商城WebView.buildCatalog = function():Array {
    var catalog:Array = [];
    for (var i:Number = 0; i < _root.kshop_list.length; i++) {
        var entry:Object = _root.kshop_list[i];
        var itemData:Object = org.flashNight.arki.item.ItemUtil.getItemData(entry.item);
        var rawItemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(entry.item);
        var attrs:Object = _root.根据物品名查找全部属性(entry.item);
        if (itemData != undefined && attrs != undefined) {
            var catalogItem:Object = {
                idx:         i,
                id:          entry.id,
                item:        entry.item,
                type:        entry.type,
                // data/kshop 的历史文件把 price 存成 JSON 字符串；canonical
                // AS2 投影在权威边界归一化为 Number，Host/Web 只接收单一类型。
                price:       Number(entry.price),
                displayname: this.projectLegacyIdentityField(itemData.displayname, String(entry.item)),
                majorType:   String(attrs[2]),
                subType:     String(attrs[3]),
                actionType:  String(itemData.actiontype || ""),
                weaponType:  String(itemData.weapontype || ""),
                setId:       String(itemData.setId || ""),
                setName:     String(itemData.setName || ""),
                setOrder:    Number(itemData.setOrder || 0),
                level:       Number(attrs[9]),
                icon:        this.projectLegacyIdentityField(attrs[1], String(entry.item)),
                maxQuantity: this.getPurchaseLimit(String(entry.item))
            };
            var balanceSummary:Object = org.flashNight.arki.item.InventoryPanelService.buildBalanceSummary(
                rawItemData,
                org.flashNight.arki.item.ItemUtil.getRawBalanceData(entry.item),
                "data"
            );
            if (balanceSummary != null) catalogItem.balanceSummary = balanceSummary;
            catalog.push(catalogItem);
        } else {
            this.log("WARNING: skipped [" + i + "] item=" + entry.item);
        }
    }
    return catalog;
};

// 诊断日志 helper
_root.UI系统.商城WebView.log = function(msg):Void {
    _root.server.sendServerMessage("[ShopWV] " + msg);
};

_root.UI系统.商城WebView.ensureState = function():Void {
    if (_root.商城购物车 == undefined || _root.商城购物车.length == undefined) {
        _root.商城购物车 = [];
    }
    if (_root.商城已购买物品 == undefined || _root.商城已购买物品.length == undefined) {
        _root.商城已购买物品 = [];
    }
    if (isNaN(_root.虚拟币)) {
        _root.虚拟币 = 0;
    }
};

// 历史待领取记录继续沿用存档中的五元数组；Web 只消费这份显式投影。
// 任一旧记录无法解析时返回 null，让 Host fail-closed，禁止把内部名猜成显示名或图标名。
_root.UI系统.商城WebView.buildPurchasedView = function():Array {
    var result:Array = [];
    for (var i:Number = 0; i < _root.商城已购买物品.length; i++) {
        var row:Object = _root.商城已购买物品[i];
        if (!(row instanceof Array) || row.length != 5) return null;
        var itemName:String = String(row[1]);
        var quantity:Number = Number(row[4]);
        var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(itemName);
        var attrs:Object = _root.根据物品名查找全部属性(itemName);
        if (itemName == "" || isNaN(quantity) || quantity <= 0
                || quantity != Math.floor(quantity) || itemData == undefined
                || itemData.displayname == undefined || attrs == undefined
                || attrs[1] == undefined || String(itemData.displayname) == ""
                || String(attrs[1]) == "") return null;
        result.push({
            purchasedIdx:i,
            item:itemName,
            displayname:String(itemData.displayname),
            icon:String(attrs[1]),
            quantity:quantity
        });
    }
    return result;
};

// sendResponse 是所有 Web panel 共用的 socket 出口（命名沿袭历史；语义上是 "WebView 通用响应"，不仅商城）
_root.UI系统.商城WebView.sendResponse = function(resp:Object):Void {
    _root.server.sendSocketMessage(_root.UI系统.商城WebView.json.stringify(resp));
};

_root.UI系统.商城WebView.log("loaded, gameCommands=" + typeof(_root.gameCommands) + " server=" + typeof(_root.server) + " shopJson=" + typeof(_root.UI系统.商城WebView.json));

_root.gameCommands["shopPanelOpen"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    _root.UI系统.商城WebView.checkoutPlan = null;
    _root.UI系统.商城WebView.log("shopPanelOpen, 暂停=" + _root.暂停);
    // 防御性：如果上一次 close 没走通（异常关 panel / Launcher 重连），先释放旧 lease 再申请新的。
    // 先清 pauseLeaseId 再 release：releaseLease 若抛错也不会留下"已释放的旧 id"假态。
    if (_root.UI系统.商城WebView.pauseLeaseId !== undefined) {
        var staleId:String = _root.UI系统.商城WebView.pauseLeaseId;
        _root.UI系统.商城WebView.pauseLeaseId = undefined;
        org.flashNight.arki.pause.PauseManager.releaseLease(staleId);
    }
    _root.UI系统.商城WebView.pauseLeaseId = org.flashNight.arki.pause.PauseManager.lease(true, "shop");
};

_root.gameCommands["shopPanelClose"] = function(params) {
    _root.UI系统.商城WebView.log("shopPanelClose");
    // TODO Plan A2/C: 可改 if(dirtyMark) 守卫或直接删除（checkout/claim 已 flushNow）
    // 本轮保留 _root.自动存盘() 作为 SOL 子层兜底；走 debounce 不会立即落盘
    _root.自动存盘();
    if (_root.UI系统.商城WebView.pauseLeaseId !== undefined) {
        org.flashNight.arki.pause.PauseManager.releaseLease(_root.UI系统.商城WebView.pauseLeaseId);
        _root.UI系统.商城WebView.pauseLeaseId = undefined;
    }
};

// ========== 批量查询 ==========
_root.gameCommands["shopBulkQuery"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    _root.UI系统.商城WebView.checkoutPlan = null;
    // bulkQuery 是 purchased-list snapshot 边界：铸新 token，让旧 Web 会话的 index 失效。
    _root.UI系统.商城WebView.rotatePurchasedToken();
    var callId = params.callId;
    _root.UI系统.商城WebView.log("shopBulkQuery callId=" + callId + " kshop_list.length=" + _root.kshop_list.length);
    var catalog:Array = _root.UI系统.商城WebView.buildCatalog();
    // 将旧格式购物车转为 idx 格式（M2: 精确匹配 + first-match 回退）
    var cartMigrated = [];
    var cartAdjusted:Boolean = false;
    for (var c = 0; c < _root.商城购物车.length; c++) {
        var cartItem = _root.商城购物车[c];
        var matched = -1;
        for (var k = 0; k < _root.kshop_list.length; k++) {
            if (_root.kshop_list[k].id == cartItem[0]) {
                if (matched < 0) matched = k;
                if (_root.kshop_list[k].type == cartItem[2]) { matched = k; break; }
            }
        }
        if (matched >= 0) {
            var migratedQuantity:Number = Number(cartItem[cartItem.length - 1]);
            var migratedMaximum:Number = _root.UI系统.商城WebView.getPurchaseLimit(String(_root.kshop_list[matched].item));
            if (isNaN(migratedQuantity) || migratedQuantity <= 0 || migratedQuantity != Math.floor(migratedQuantity)
                    || migratedMaximum <= 0) cartAdjusted = true;
            else {
                if (migratedQuantity > migratedMaximum) {
                    migratedQuantity = migratedMaximum;
                    cartAdjusted = true;
                }
                cartMigrated.push({idx: matched, qty: migratedQuantity});
            }
        } else cartAdjusted = true;
    }
    var resp = {
        task: "shop_response", callId: callId, success: true,
        catalog: catalog,
        playerLevel: Number(_root.等级),
        reverseLevel: Number(_root.主角被动技能.逆向.启用 ? _root.主角被动技能.逆向.等级 : 0),
        kpoints: Number(_root.虚拟币),
        cart: cartMigrated,
        cartAdjusted: cartAdjusted,
        purchased: _root.商城已购买物品,
        purchasedView: _root.UI系统.商城WebView.buildPurchasedView(),
        purchasedToken: _root.UI系统.商城WebView.purchasedToken
    };
    var respStr = _root.UI系统.商城WebView.json.stringify(resp);
    _root.UI系统.商城WebView.log("bulkQuery resp type=" + typeof(respStr) + " len=" + respStr.length + " catalog=" + catalog.length);
    _root.server.sendSocketMessage(respStr);
};

// ========== 新结算：权威预览 -> token 单次提交 -> 直接交付 ==========
// 旧“结账后进入商城已购买物品，再逐项 claim”只保留历史存档兼容。
// 新 Web 不再生成待领取记录；余额或容量不足时整单不扣 K 点。
_root.UI系统.商城WebView.isWholeNumber = function(value):Boolean {
    var number:Number = Number(value);
    return !isNaN(number) && number != Infinity && number != -Infinity && number == Math.floor(number);
};

_root.UI系统.商城WebView.resolveCheckoutLine = function(request:Object):Object {
    if (request == undefined || !this.isWholeNumber(request.idx)
            || !this.isWholeNumber(request.qty) || Number(request.qty) <= 0) {
        return {success:false, error:"invalid_payload"};
    }
    var idx:Number = Number(request.idx);
    var quantity:Number = Number(request.qty);
    if (idx < 0 || idx >= _root.kshop_list.length) return {success:false, error:"item_not_found"};
    var entry:Object = _root.kshop_list[idx];
    if (String(entry.type) == "非卖品") return {success:false, error:"not_for_sale"};
    var itemName:String = String(entry.item);
    var itemData:Object = org.flashNight.arki.item.ItemUtil.getRawItemData(itemName);
    var attrs:Object = _root.根据物品名查找全部属性(itemName);
    if (itemData == undefined || attrs == undefined) return {success:false, error:"item_not_found"};
    var reverseLevel:Number = Number(_root.主角被动技能.逆向.启用 ? _root.主角被动技能.逆向.等级 : 0);
    if (isNaN(reverseLevel)) reverseLevel = 0;
    if (Number(attrs[9]) > Number(_root.等级) + reverseLevel) return {success:false, error:"locked"};
    var equipment:Boolean = org.flashNight.arki.item.ItemUtil.isEquipment(itemName);
    var information:Boolean = org.flashNight.arki.item.ItemUtil.isInformation(itemName);
    var maxQuantity:Number = this.getPurchaseLimit(itemName);
    if (quantity > maxQuantity) return {success:false, error:"invalid_quantity"};
    var unitPrice:Number = Number(entry.price);
    if (isNaN(unitPrice) || unitPrice < 0) return {success:false, error:"invalid_price"};
    return {
        success:true,
        catalogIndex:idx,
        itemName:itemName,
        displayName:this.projectLegacyIdentityField(itemData.displayname, itemName),
        icon:this.projectLegacyIdentityField(attrs[1], itemName),
        quantity:quantity,
        unitPrice:unitPrice,
        total:unitPrice * quantity,
        maxQuantity:maxQuantity,
        itemKind:equipment ? "equipment" : (information ? "information" : "stack")
    };
};

_root.UI系统.商城WebView.buildCheckoutAcquireItems = function(lines:Array):Array {
    var result:Array = [];
    for (var i:Number = 0; i < lines.length; i++) {
        var line:Object = lines[i];
        if (line.itemKind == "equipment") {
            for (var instance:Number = 0; instance < Number(line.quantity); instance++) {
                result.push({name:line.itemName, value:1});
            }
        } else {
            result.push({name:line.itemName, value:Number(line.quantity)});
        }
    }
    return result;
};

_root.UI系统.商城WebView.canAcquireCheckoutLines = function(lines:Array):Boolean {
    return org.flashNight.arki.item.ItemUtil.require(this.buildCheckoutAcquireItems(lines)) != null;
};

_root.UI系统.商城WebView.checkoutCapacityBound = function(lines:Array, targetIndex:Number):Number {
    var target:Object = lines[targetIndex];
    var low:Number = 1;
    var high:Number = Number(target.maxQuantity);
    var maximum:Number = 0;
    while (low <= high) {
        var middle:Number = Math.floor((low + high) / 2);
        var trial:Array = [];
        for (var i:Number = 0; i < lines.length; i++) {
            var source:Object = lines[i];
            trial.push({
                itemName:source.itemName,
                quantity:i == targetIndex ? middle : source.quantity,
                itemKind:source.itemKind
            });
        }
        if (this.canAcquireCheckoutLines(trial)) {
            maximum = middle;
            low = middle + 1;
        } else {
            high = middle - 1;
        }
    }
    return maximum;
};

_root.UI系统.商城WebView.buildCheckoutPreview = function(cart:Array, issueToken:Boolean):Object {
    if (!(cart instanceof Array) || cart.length < 1 || cart.length > 40) {
        return {success:false, error:"invalid_payload"};
    }
    var lines:Array = [];
    var seen:Object = {};
    var total:Number = 0;
    for (var i:Number = 0; i < cart.length; i++) {
        var line:Object = this.resolveCheckoutLine(cart[i]);
        if (!line.success) return line;
        var key:String = String(line.catalogIndex);
        if (seen[key]) return {success:false, error:"duplicate_line"};
        seen[key] = true;
        delete line.success;
        lines.push(line);
        total += Number(line.total);
    }
    var balance:Number = Number(_root.虚拟币);
    if (isNaN(balance)) balance = 0;
    var enoughSpace:Boolean = this.canAcquireCheckoutLines(lines);
    var capacityError:String = "inventory_full";
    for (var boundIndex:Number = 0; boundIndex < lines.length; boundIndex++) {
        var bounded:Object = lines[boundIndex];
        var otherTotal:Number = total - Number(bounded.total);
        var remaining:Number = balance - otherTotal;
        var maxAffordable:Number = bounded.unitPrice <= 0
            ? Number(bounded.maxQuantity)
            : Math.max(0, Math.min(Number(bounded.maxQuantity), Math.floor(remaining / Number(bounded.unitPrice))));
        bounded.maxAffordable = maxAffordable;
        bounded.maxByCapacity = this.checkoutCapacityBound(lines, boundIndex);
        bounded.maxPurchasable = Math.min(maxAffordable, Number(bounded.maxByCapacity));
        if (bounded.itemKind == "information" && Number(bounded.maxByCapacity) < Number(bounded.quantity)) {
            capacityError = "destination_full";
        }
    }
    var token:String = "";
    if (issueToken) {
        this.checkoutSeq++;
        token = "kcheckout" + getTimer() + "." + this.checkoutSeq;
        this.checkoutPlan = {token:token, balance:balance, total:total, lines:lines};
    }
    return {
        success:true,
        v:1,
        checkoutToken:token,
        purchaseLines:lines,
        total:total,
        balance:balance,
        projectedBalance:balance - total,
        canCommit:balance >= total && enoughSpace,
        blockingError:balance < total ? "insufficient_kpoints" : (enoughSpace ? "" : capacityError)
    };
};

// 新旧 checkout wire 共用唯一写入实现。历史待领取列表只读兼容，不再由任何结账入口增长。
_root.UI系统.商城WebView.finalizeCheckout = function(preview:Object, resp:Object):Object {
    if (!org.flashNight.arki.item.ItemUtil.acquire(this.buildCheckoutAcquireItems(preview.purchaseLines))) {
        resp.success = false;
        resp.error = String(preview.blockingError || "inventory_full");
        return resp;
    }
    _root.虚拟币 = Number(preview.balance) - Number(preview.total);
    _root.商城购物车 = [];
    _root.soundEffectManager.playSound("收银机.mp3");
    if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
        org.flashNight.arki.achievement.AchievementMetrics.record("商城结账次数", 1);
        org.flashNight.arki.achievement.AchievementMetrics.record("商城花费K点", Number(preview.total));
    }
    _root.强制存盘();
    resp.success = true;
    resp.v = 1;
    resp.newBalance = _root.虚拟币;
    resp.delivered = preview.purchaseLines;
    resp.cart = [];
    resp.purchased = _root.商城已购买物品;
    resp.purchasedView = this.buildPurchasedView();
    resp.purchasedToken = _root.UI系统.商城WebView.purchasedToken;
    // 动态 maxQuantity 依赖本次交付后的情报剩余容量，成功回包必须同步刷新目录。
    resp.catalog = this.buildCatalog();
    return resp;
};

_root.gameCommands["shopCheckoutPreview"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    // 任意新预览请求都先废弃旧 token；畸形新请求也不能让旧计划继续可提交。
    _root.UI系统.商城WebView.checkoutPlan = null;
    var callId = params.callId;
    var result:Object = Number(params.v) == 1
        ? _root.UI系统.商城WebView.buildCheckoutPreview(params.cart, true)
        : {success:false, error:"unsupported_version"};
    result.task = "shop_response";
    result.callId = callId;
    _root.UI系统.商城WebView.sendResponse(result);
};

_root.gameCommands["shopCheckoutCommit"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    var callId = params.callId;
    var plan:Object = _root.UI系统.商城WebView.checkoutPlan;
    var expectedToken:String = String(params.expectedCheckoutToken || "");
    var resp:Object = {task:"shop_response", callId:callId};
    if (Number(params.v) != 1) {
        resp.success = false;
        resp.error = "unsupported_version";
        _root.UI系统.商城WebView.sendResponse(resp);
        return;
    }
    if (plan == null || expectedToken != String(plan.token)) {
        resp.success = false;
        resp.error = "stale_state";
        _root.UI系统.商城WebView.sendResponse(resp);
        return;
    }
    // token 单次消费。即使后续校验失败也必须重新预览，禁止重放提交。
    _root.UI系统.商城WebView.checkoutPlan = null;
    var requests:Array = [];
    for (var i:Number = 0; i < plan.lines.length; i++) {
        requests.push({idx:plan.lines[i].catalogIndex, qty:plan.lines[i].quantity});
    }
    var current:Object = _root.UI系统.商城WebView.buildCheckoutPreview(requests, false);
    var planMatches:Boolean = current.success && current.purchaseLines.length == plan.lines.length;
    if (planMatches) {
        for (var matchIndex:Number = 0; matchIndex < plan.lines.length; matchIndex++) {
            var oldLine:Object = plan.lines[matchIndex];
            var newLine:Object = current.purchaseLines[matchIndex];
            if (Number(newLine.catalogIndex) != Number(oldLine.catalogIndex)
                    || String(newLine.itemName) != String(oldLine.itemName)
                    || Number(newLine.quantity) != Number(oldLine.quantity)
                    || Number(newLine.unitPrice) != Number(oldLine.unitPrice)
                    || Number(newLine.total) != Number(oldLine.total)) {
                planMatches = false;
                break;
            }
        }
    }
    if (!planMatches || Number(current.balance) != Number(plan.balance)
            || Number(current.total) != Number(plan.total)) {
        resp.success = false;
        resp.error = "stale_state";
    } else if (!current.canCommit) {
        resp.success = false;
        resp.error = String(current.blockingError);
    } else {
        _root.UI系统.商城WebView.finalizeCheckout(current, resp);
    }
    _root.UI系统.商城WebView.sendResponse(resp);
};

// ========== legacy 结账：只供旧 Flash/旧 Host 入口 ==========
_root.gameCommands["shopCheckout"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    _root.UI系统.商城WebView.checkoutPlan = null;
    var items = (params.cart != undefined && params.cart.length != undefined) ? params.cart : [];
    var callId = params.callId;
    _root.UI系统.商城WebView.log("shopCheckout callId=" + callId + " items=" + items.length);
    var resp = { task: "shop_response", callId: callId };
    var preview:Object = _root.UI系统.商城WebView.buildCheckoutPreview(items, false);
    if (!preview.success) {
        resp.success = false;
        resp.error = String(preview.error);
    } else if (!preview.canCommit) {
        resp.success = false;
        resp.error = String(preview.blockingError);
        resp.balance = Number(preview.balance);
    } else {
        _root.UI系统.商城WebView.finalizeCheckout(preview, resp);
    }
    _root.UI系统.商城WebView.sendResponse(resp);
};

// ========== 领取 ==========
_root.gameCommands["shopClaim"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    _root.UI系统.商城WebView.checkoutPlan = null;
    var claimIdx = params.purchasedIdx;
    var callId = params.callId;
    _root.UI系统.商城WebView.log("shopClaim callId=" + callId + " idx=" + claimIdx);
    var resp = { task: "shop_response", callId: callId };

    if (String(params.expectedPurchasedToken) != String(_root.UI系统.商城WebView.purchasedToken)) {
        resp.success = false; resp.error = "stale_state";
        resp.purchasedToken = _root.UI系统.商城WebView.purchasedToken;
    } else if (claimIdx < 0 || claimIdx >= _root.商城已购买物品.length) {
        resp.success = false; resp.error = "item_not_found";
        resp.purchasedToken = _root.UI系统.商城WebView.purchasedToken;
    } else {
        var item = _root.商城已购买物品[claimIdx];
        var itemName = item[1];
        var qty = Number(item[item.length - 1]);
        if (isNaN(qty) || qty <= 0) qty = 1;

        if (org.flashNight.arki.item.ItemUtil.singleAcquire(itemName, qty)) {
            _root.商城已购买物品.splice(claimIdx, 1);
            resp.success = true;
            resp.purchased = _root.商城已购买物品;
            resp.purchasedView = _root.UI系统.商城WebView.buildPurchasedView();
            resp.purchasedToken = _root.UI系统.商城WebView.rotatePurchasedToken();
            resp.catalog = _root.UI系统.商城WebView.buildCatalog();
            // Plan A: 商城 claim 真实从已购列表移除 + 物品入背包，必达。
            // 删除原本的 _root.存盘商城已购买物品() 子层 flush：
            // 子层 SOL 写入与下方 mydata 顶层 flushNow 之间存在崩溃窗口
            // （子层已移除已购但 mydata 没存背包）。改为只走一次 _root.强制存盘() 写完整 mydata。
            // 成就记账（埋点 #2，acquire true 后；领取=入包计数，与 #1 结账两段式口径不双计「购买」）
            if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
                org.flashNight.arki.achievement.AchievementMetrics.record("商城领取次数", 1);
            }
            _root.强制存盘();
        } else {
            resp.success = false;
            resp.error = org.flashNight.arki.item.ItemUtil.isInformation(itemName)
                ? "destination_full" : "inventory_full";
            resp.purchasedToken = _root.UI系统.商城WebView.purchasedToken;
        }
    }
    _root.UI系统.商城WebView.sendResponse(resp);
};

// ========== 保存购物车 ==========
_root.gameCommands["shopSaveCart"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    var cart = (params.cart != undefined && params.cart.length != undefined) ? params.cart : [];
    var callId = params.callId;
    _root.UI系统.商城WebView.log("shopSaveCart callId=" + callId + " items=" + cart.length);
    _root.商城购物车 = [];
    var savedCart:Array = [];
    for (var i = 0; i < cart.length; i++) {
        var idx = Number(cart[i].idx);
        var qty = Number(cart[i].qty);
        if (isNaN(idx) || idx < 0 || idx >= _root.kshop_list.length) continue;
        if (isNaN(qty) || qty <= 0 || qty != Math.floor(qty)) continue;
        var entry = _root.kshop_list[idx];
        var maximum:Number = _root.UI系统.商城WebView.getPurchaseLimit(String(entry.item));
        if (maximum <= 0) continue;
        if (qty > maximum) qty = maximum;
        _root.商城购物车.push([entry.id, entry.item, entry.type, entry.price, qty]);
        savedCart.push({idx:idx, qty:qty});
    }
    // Plan A audit: shopSaveCart 写 _root.商城购物车（save-relevant）。
    // 删除原本的 _root.保存购物车() 子层 flush（仅写 cart 子层 SOL，与 mydata 顶层
    // 长期 desync 风险）。改为标脏 + 自动存盘 debounce：购物车连续编辑被合并；
    // 后续 checkout/claim 会走 flushNow 一次性写完整 mydata；玩家离开商城面板
    // 时 shopPanelClose 兜底 + SceneChanged hook unconditional flushNow 兜底。
    _root.存档系统.dirtyMark = true;
    _root.自动存盘();
    var resp = { task: "shop_response", callId: callId, success: true, v:1, cart:savedCart };
    _root.UI系统.商城WebView.sendResponse(resp);
};

// ========== 物品注释（Bridge 到 WebView） ==========
// 仅商城面板使用，其他场景走原有 Flash 注释框
_root.gameCommands["shopTooltip"] = function(params) {
    var idx = Number(params.idx);
    var callId = params.callId;

    if (isNaN(idx) || idx < 0 || idx >= _root.kshop_list.length) {
        var errResp = { task: "shop_response", callId: callId, success: false, error: "invalid_idx" };
        _root.UI系统.商城WebView.sendResponse(errResp);
        return;
    }

    var entry = _root.kshop_list[idx];
    var itemName = entry.item;
    var tt = _root.Web物品注释HTML(itemName);
    var attrs = _root.根据物品名查找全部属性(itemName);
    if (tt == null || attrs == undefined) {
        _root.UI系统.商城WebView.sendResponse({ task: "shop_response", callId: callId, success: false, error: "item_not_found" });
        return;
    }
    _root.UI系统.商城WebView.sendResponse({
        task: "shop_response",
        callId: callId,
        success: true,
        descHTML: tt.descHTML,
        introHTML: tt.introHTML,
        itemName: itemName,
        displayname: _root.UI系统.商城WebView.projectLegacyIdentityField(tt.displayname, String(itemName)),
        iconName: _root.UI系统.商城WebView.projectLegacyIdentityField(attrs[1], String(itemName))
    });
};

// ========== 情报 Web 面板运行态状态 ==========
// 正式情报 Web panel 只向 Flash 读取收集值、解密等级和玩家名；正文仍由 Launcher/C# 读取 txt。
_root.gameCommands["intelligenceState"] = function(params) {
    var callId = params.callId;
    var values = {};
    if (_root.收集品栏 != undefined && _root.收集品栏.情报 != undefined &&
        typeof(_root.收集品栏.情报.toObject) == "function") {
        values = _root.收集品栏.情报.toObject();
    }

    var decryptLevel = 0;
    if (_root.主角被动技能 != undefined && _root.主角被动技能.解密 != undefined &&
        _root.主角被动技能.解密.启用) {
        decryptLevel = Number(_root.主角被动技能.解密.等级);
        if (isNaN(decryptLevel)) decryptLevel = 0;
    }

    var pcName = "";
    if (_root.角色名 != undefined) pcName = String(_root.角色名);

    var resp = {
        task: "intelligence_response",
        callId: callId,
        success: true,
        values: values,
        decryptLevel: decryptLevel,
        pcName: pcName
    };
    _root.UI系统.商城WebView.sendResponse(resp);
};

// ========== 情报 Web 面板物品注释 ==========
// 与 shopTooltip 共用 _root.Web物品注释HTML（定义于 UI交互_鸡蛋_fs_aka_物品图标注释.as），本文件只做 response 包封。
_root.gameCommands["intelligenceTooltip"] = function(params) {
    var callId = params.callId;
    var itemName = String(params.itemName || "");
    var tt = _root.Web物品注释HTML(itemName);
    if (tt == null) {
        _root.UI系统.商城WebView.sendResponse({ task: "intelligence_response", callId: callId, success: false, itemName: itemName, error: "item_not_found" });
        return;
    }
    _root.UI系统.商城WebView.sendResponse({
        task: "intelligence_response",
        callId: callId,
        success: true,
        itemName: itemName,
        displayname: tt.displayname,
        descHTML: tt.descHTML,
        introHTML: tt.introHTML
    });
};
