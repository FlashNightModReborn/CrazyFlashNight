// 商城系统_WebView.as — WebView 面板侧商城命令
// JSON 序列化器挂到 _root.UI系统 命名空间，确保 gameCommands 闭包能访问且不污染 root 顶层
// 使用 LiteJSON 而非 FastJSON：FastJSON 按对象身份缓存，同一数组引用内容变化后仍返回旧字符串
_root.UI系统 = _root.UI系统 || {};
_root.UI系统.商城WebView = _root.UI系统.商城WebView || {};
_root.UI系统.商城WebView.json = new LiteJSON();
_root.UI系统.商城WebView.prevPause = undefined;

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

_root.UI系统.商城WebView.sendResponse = function(resp:Object):Void {
    _root.server.sendSocketMessage(_root.UI系统.商城WebView.json.stringify(resp));
};

_root.UI系统.商城WebView.log("loaded, gameCommands=" + typeof(_root.gameCommands) + " server=" + typeof(_root.server) + " shopJson=" + typeof(_root.UI系统.商城WebView.json));

_root.gameCommands["shopPanelOpen"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    _root.UI系统.商城WebView.log("shopPanelOpen, 暂停=" + _root.暂停);
    _root.UI系统.商城WebView.prevPause = _root.暂停;
    _root.暂停 = true;
};

_root.gameCommands["shopPanelClose"] = function(params) {
    _root.UI系统.商城WebView.log("shopPanelClose");
    _root.自动存盘();
    if (_root.UI系统.商城WebView.prevPause !== undefined) {
        _root.暂停 = _root.UI系统.商城WebView.prevPause;
        _root.UI系统.商城WebView.prevPause = undefined;
    }
};

// ========== 批量查询 ==========
_root.gameCommands["shopBulkQuery"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    var callId = params.callId;
    _root.UI系统.商城WebView.log("shopBulkQuery callId=" + callId + " kshop_list.length=" + _root.kshop_list.length);
    var catalog = [];
    for (var i = 0; i < _root.kshop_list.length; i++) {
        var entry = _root.kshop_list[i];
        var itemData = org.flashNight.arki.item.ItemUtil.getItemData(entry.item);
        var attrs = _root.根据物品名查找全部属性(entry.item);
        if (itemData != undefined && attrs != undefined) {
            catalog.push({
                idx:         i,
                id:          entry.id,
                item:        entry.item,
                type:        entry.type,
                price:       entry.price,
                displayname: String(itemData.displayname || entry.item),
                majorType:   String(attrs[2]),
                subType:     String(attrs[3]),
                level:       Number(attrs[9]),
                icon:        String(attrs[1])
            });
        } else {
            _root.UI系统.商城WebView.log("WARNING: skipped [" + i + "] item=" + entry.item);
        }
    }
    // 将旧格式购物车转为 idx 格式（M2: 精确匹配 + first-match 回退）
    var cartMigrated = [];
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
            cartMigrated.push({idx: matched, qty: Number(cartItem[cartItem.length - 1])});
        }
    }
    var resp = {
        task: "shop_response", callId: callId, success: true,
        catalog: catalog,
        playerLevel: Number(_root.等级),
        reverseLevel: Number(_root.主角被动技能.逆向.启用 ? _root.主角被动技能.逆向.等级 : 0),
        kpoints: Number(_root.虚拟币),
        cart: cartMigrated,
        purchased: _root.商城已购买物品
    };
    var respStr = _root.UI系统.商城WebView.json.stringify(resp);
    _root.UI系统.商城WebView.log("bulkQuery resp type=" + typeof(respStr) + " len=" + respStr.length + " catalog=" + catalog.length);
    _root.server.sendSocketMessage(respStr);
};

// ========== 结账 ==========
_root.gameCommands["shopCheckout"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    var items = (params.cart != undefined && params.cart.length != undefined) ? params.cart : [];
    var callId = params.callId;
    _root.UI系统.商城WebView.log("shopCheckout callId=" + callId + " items=" + items.length);
    var total = 0;
    var resolved = [];

    for (var i = 0; i < items.length; i++) {
        var idx = Number(items[i].idx);
        var qty = Number(items[i].qty);
        if (isNaN(idx) || idx < 0 || idx >= _root.kshop_list.length) continue;
        if (isNaN(qty) || qty <= 0 || qty != Math.floor(qty)) continue;
        var entry = _root.kshop_list[idx];
        total += Number(entry.price) * qty;
        resolved.push([entry.id, entry.item, entry.type, entry.price, qty]);
    }

    var resp = { task: "shop_response", callId: callId };
    if (_root.虚拟币 > total) {
        _root.虚拟币 -= total;
        for (var j = 0; j < resolved.length; j++) {
            _root.商城已购买物品.push(resolved[j]);
        }
        _root.存盘商城已购买物品();
        _root.商城购物车 = [];
        _root.保存购物车();
        _root.soundEffectManager.playSound("收银机.mp3");
        resp.success = true;
        resp.newBalance = _root.虚拟币;
        resp.purchased = _root.商城已购买物品;
    } else {
        resp.success = false;
        resp.error = "insufficient_kpoints";
        resp.balance = _root.虚拟币;
    }
    _root.UI系统.商城WebView.sendResponse(resp);
};

// ========== 领取 ==========
_root.gameCommands["shopClaim"] = function(params) {
    _root.UI系统.商城WebView.ensureState();
    var claimIdx = params.purchasedIdx;
    var callId = params.callId;
    _root.UI系统.商城WebView.log("shopClaim callId=" + callId + " idx=" + claimIdx);
    var resp = { task: "shop_response", callId: callId };

    if (claimIdx < 0 || claimIdx >= _root.商城已购买物品.length) {
        resp.success = false; resp.error = "item_not_found";
    } else {
        var item = _root.商城已购买物品[claimIdx];
        var itemName = item[1];
        var qty = Number(item[item.length - 1]);
        if (isNaN(qty) || qty <= 0) qty = 1;

        if (_root.物品栏.背包.getFirstVacancy() == -1) {
            resp.success = false; resp.error = "inventory_full";
        } else if (org.flashNight.arki.item.ItemUtil.singleAcquire(itemName, qty)) {
            _root.商城已购买物品.splice(claimIdx, 1);
            _root.存盘商城已购买物品();
            resp.success = true;
            resp.purchased = _root.商城已购买物品;
        } else {
            resp.success = false; resp.error = "acquire_failed";
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
    for (var i = 0; i < cart.length; i++) {
        var idx = Number(cart[i].idx);
        var qty = Number(cart[i].qty);
        if (isNaN(idx) || idx < 0 || idx >= _root.kshop_list.length) continue;
        if (isNaN(qty) || qty <= 0 || qty != Math.floor(qty)) continue;
        var entry = _root.kshop_list[idx];
        _root.商城购物车.push([entry.id, entry.item, entry.type, entry.price, qty]);
    }
    _root.保存购物车();
    var resp = { task: "shop_response", callId: callId, success: true };
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
    var itemData = org.flashNight.arki.item.ItemUtil.getItemData(itemName);
    if (itemData == undefined) {
        var errResp2 = { task: "shop_response", callId: callId, success: false, error: "item_not_found" };
        _root.UI系统.商城WebView.sendResponse(errResp2);
        return;
    }

    // value 对象：商城物品不涉及强化等级，默认 level=1
    var value = { level: 1 };

    // 生成两段 HTML（与 物品图标注释 同一调用链，但不渲染 Flash 注释框）
    var descHTML = org.flashNight.gesh.tooltip.TooltipComposer.generateItemDescriptionText(itemData, null);
    var introHTML = org.flashNight.gesh.tooltip.TooltipComposer.generateIntroPanelContent(null, itemData, value);

    // LiteJSON 不转义双引号，XML 数据中内嵌的 <font color="#xxx"> 会破坏 JSON 结构
    // 将双引号替换为单引号（AS2 TextField 两者等效）
    descHTML = descHTML.split('"').join("'");
    introHTML = introHTML.split('"').join("'");

    var resp = {
        task: "shop_response",
        callId: callId,
        success: true,
        descHTML: descHTML,
        introHTML: introHTML,
        itemName: itemName,
        displayname: String(itemData.displayname || itemName)
    };
    _root.UI系统.商城WebView.sendResponse(resp);
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
// 复用原 Flash 物品注释生成链路，Web 只负责显示容器和 AS2 HTML 兼容转换。
_root.gameCommands["intelligenceTooltip"] = function(params) {
    var callId = params.callId;
    var itemName = String(params.itemName || "");
    var itemData = org.flashNight.arki.item.ItemUtil.getItemData(itemName);
    if (itemData == undefined) {
        var errResp = { task: "intelligence_response", callId: callId, success: false, itemName: itemName, error: "item_not_found" };
        _root.UI系统.商城WebView.sendResponse(errResp);
        return;
    }

    var value = { level: 1 };
    var descHTML = org.flashNight.gesh.tooltip.TooltipComposer.generateItemDescriptionText(itemData, null);
    var introHTML = org.flashNight.gesh.tooltip.TooltipComposer.generateIntroPanelContent(null, itemData, value);
    descHTML = descHTML.split('"').join("'");
    introHTML = introHTML.split('"').join("'");

    var resp = {
        task: "intelligence_response",
        callId: callId,
        success: true,
        itemName: itemName,
        displayname: String(itemData.displayname || itemName),
        descHTML: descHTML,
        introHTML: introHTML
    };
    _root.UI系统.商城WebView.sendResponse(resp);
};
