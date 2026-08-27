// 旧物品栏/仓库/商店 renderer 已退役。
// 本文件只保留仍被现役 Web 领域服务或独立 HUD 使用的兼容门面。
_root.物品UI函数 = new Object();

_root.物品UI函数.计算强化收益 = function(当前总价, 强化等级) {
	if (isNaN(强化等级)) 强化等级 = 1;
	var 每石最大收益 = 强化等级 * 100 + 700;
	var 强化石个数 = Math.pow((强化等级 - 2) * (强化等级 - 1) / 2, 2) + 强化等级 - 1;
	var 最大收益 = 强化石个数 * 每石最大收益;
	var 强化收益 = Math.floor(当前总价 * (Math.pow(强化等级 - 1, 4.2) / 216));
	if (强化收益 > 最大收益) 强化收益 = 最大收益;
	return 强化收益;
};

/**
 * NPC 商店领域仍以 AS2 数据为权威；Web 只消费计算结果。
 */
_root.物品UI函数.计算售卖总价 = function(item, 数量) {
	var result = {
		总价: 0,
		原总价: 0,
		基础价格: 0,
		售卖倍率: 0.25,
		tier价格: 0,
		强化收益: 0
	};

	if (!item || !item.name) return result;
	var itemData = ItemUtil.getRawItemData(item.name);
	if (!itemData || !itemData.price) return result;

	if (_root.主角被动技能.口才 && _root.主角被动技能.口才.启用) {
		result.售卖倍率 += _root.主角被动技能.口才.等级 * 0.025;
	}

	var 单价 = parseInt(itemData.price);
	result.基础价格 = Math.floor(单价 * 数量 * result.售卖倍率);
	result.总价 = result.基础价格;
	result.原总价 = Math.floor(单价 * 数量 * 0.25);

	if (item.value && item.value.tier) {
		var tierMaterialName = EquipmentUtil.tierNameToMaterialDict[item.value.tier];
		if (tierMaterialName) {
			var tierMaterialData = ItemUtil.getRawItemData(tierMaterialName);
			if (tierMaterialData && tierMaterialData.price) {
				var tierPrice = parseInt(tierMaterialData.price);
				if (!isNaN(tierPrice)) {
					result.tier价格 = Math.floor(tierPrice * result.售卖倍率);
					result.总价 += result.tier价格;
					result.原总价 += Math.floor(tierPrice * 0.25);
				}
			}
		}
	}

	if (item.value && item.value.level && item.value.level > 1) {
		result.强化收益 = this.计算强化收益(result.基础价格, item.value.level);
		result.总价 += result.强化收益;
	}
	return result;
};

/**
 * Web 批量售卖的 plain_only 策略判定。
 */
_root.物品UI函数.是否普通物品 = function(item:Object):Boolean {
	if (!item || !item.name) return false;
	var itemData = ItemUtil.getItemData(item.name);
	if (!itemData) return false;
	if (itemData.type != "武器" && itemData.type != "防具") return true;

	var val = item.value;
	if (!val) return true;
	if (val.level != null && val.level != undefined && val.level > 1) return false;
	if (val.tier != null && val.tier != undefined) return false;
	if (val.mods && val.mods.length > 0) return false;
	return true;
};

/**
 * 快捷药剂 HUD 是独立常驻组件，不属于已退役双栏工作台。
 */
_root.物品UI函数.初始化药剂栏图标 = function():Void {
	var 快捷药剂界面 = _root.玩家信息界面.快捷药剂界面;
	if (!快捷药剂界面) return;
	if (快捷药剂界面.药剂图标列表 && 快捷药剂界面.药剂图标列表.length == 4) {
		DrugInputService.syncBankView(快捷药剂界面, _root.物品栏.药剂栏);
		DrugInputService.syncSwitchView(
			快捷药剂界面, Number(_root.药剂组切换键), _root);
		return;
	}

	var list = [
		快捷药剂界面.位置示意0,
		快捷药剂界面.位置示意1,
		快捷药剂界面.位置示意2,
		快捷药剂界面.位置示意3
	];
	var 控制器列表 = [
		快捷药剂界面.控制器0,
		快捷药剂界面.控制器1,
		快捷药剂界面.控制器2,
		快捷药剂界面.控制器3
	];
	var 进度条列表 = [
		快捷药剂界面.进度条0,
		快捷药剂界面.进度条1,
		快捷药剂界面.进度条2,
		快捷药剂界面.进度条3
	];

	快捷药剂界面.药剂图标列表 = [];
	var dispatcher = new LifecycleEventDispatcher(快捷药剂界面);
	_root.物品栏.药剂栏.setDispatcher(dispatcher);

	for (var i = 0; i < 4; i++) {
		var depth = list[i].getDepth();
		var posx = list[i]._x;
		var posy = list[i]._y;
		list[i].removeMovieClip();
		var 药剂图标 = 快捷药剂界面.attachMovie("HUD物品图标", "快捷物品栏" + i, depth);
		if (!药剂图标) {
			_root.发布消息("快捷药剂图标资源不可用");
			return;
		}
		药剂图标._x = posx;
		药剂图标._y = posy;
		快捷药剂界面.药剂图标列表.push(药剂图标);
		控制器列表[i].药剂栏 = 药剂图标;
	}
	var activeBank = DrugInputService.getActiveBank();
	for (i = 0; i < 4; i++) {
		var physicalSlot = DrugInputService.physicalSlotFor(activeBank, i);
		快捷药剂界面.药剂图标列表[i].itemIcon =
			new DrugIcon(快捷药剂界面.药剂图标列表[i], _root.物品栏.药剂栏, physicalSlot, 进度条列表[i]);
	}
	DrugInputService.syncBankView(快捷药剂界面, _root.物品栏.药剂栏);
	DrugInputService.syncSwitchView(
		快捷药剂界面, Number(_root.药剂组切换键), _root);
};

/**
 * 老地图/平板入口只做 shopId 解析；失败时不得再打开 Flash 商店。
 */
_root.物品UI函数.刷新商店图标 = function(NPC物品栏):Boolean {
	var NPC商店服务 = _root.UI系统 == undefined ? undefined : _root.UI系统.NPC商店WebView;
	if (NPC商店服务 != undefined && NPC商店服务.resolveShopIdByCatalog != undefined
			&& _root.gameCommands != undefined && _root.gameCommands["openNpcShop"] != undefined) {
		var NPC商店ID = NPC商店服务.resolveShopIdByCatalog(NPC物品栏);
		if (NPC商店ID != ""
				&& _root.gameCommands["openNpcShop"]({shopId:NPC商店ID, source:"npc_shop_refresh"})) {
			return true;
		}
	}
	if (typeof _root.发布消息 == "function") _root.发布消息("商店面板暂时不可用");
	return false;
};

// 独立情报阅读面板仍在服役；它不依赖双栏工作台。
_root.物品UI函数.初始化情报信息界面 = function():Void {
	this.nametext.text = "";
	this.valuetext.text = "";
	this.infovaluetext.text = "";
	this.pagetext.text = "";
	this.hinttext.text = "点击右侧情报物品查看详细信息";
	var 当前情报物品图标 = this.attachMovie("HUD物品图标", "当前情报物品图标", 0);
	当前情报物品图标._x = 45;
	当前情报物品图标._y = 105;
	当前情报物品图标._xscale = 200;
	当前情报物品图标._yscale = 200;
	当前情报物品图标.itemIcon = new ItemIcon(当前情报物品图标, null, null);
	当前情报物品图标.itemIcon.RollOver = null;
	当前情报物品图标.itemIcon.RollOut = null;
	this.btn1._visible = false;
	this.btn2._visible = false;
	this.滑动按钮._visible = false;
	this.滑动按钮btn._visible = false;
	this.显示解密后文本 = true;
	this._x = -550;
	this.onEnterFrame = function():Void {
		var movex = -this._x * 0.15;
		if (movex < 1) movex = 1;
		this._x += movex;
		if (this._x >= 0) {
			this._x = 0;
			delete this.onEnterFrame;
		}
	};
};

_root.物品UI函数.显示情报信息 = function(name, value):Void {
	this._visible = true;
	var itemData = ItemUtil.getItemData(name);
	this.当前情报物品图标.itemIcon.init(name, 1);
	this.当前情报物品名称 = name;
	this.情报信息表 = [];
	this.EncryptReplace = _root.图鉴信息.情报信息[name].EncryptReplace;
	this.EncryptCut = _root.图鉴信息.情报信息[name].EncryptCut;
	var info = _root.图鉴信息.情报信息[name].Information;
	for (var i = 0; i < info.length; i++) {
		if (info[i].Value <= value) this.情报信息表.push(info[i]);
	}
	this.当前信息序号 = 0;
	this.已发现数量 = this.情报信息表.length;
	this.总信息数量 = info.length;
	this.btn1._visible = true;
	this.btn2._visible = true;
	this.nametext.text = itemData.displayname;
	this.valuetext.text = "收集进度：" + value + " / " + itemData.maxvalue;
	this.infovaluetext.text = this.已发现数量 == this.总信息数量
		? "已发现全部 " + this.已发现数量 + " 页信息"
		: "已发现 " + this.已发现数量 + " 页信息";
	this.刷新情报信息();
};

_root.物品UI函数.刷新情报信息 = function():Void {
	this.滑动按钮._visible = false;
	this.滑动按钮btn._visible = false;
	this.pagetext.text = String(this.当前信息序号 + 1) + " / " + this.已发现数量 + " 页";

	var 当前信息 = this.情报信息表[this.当前信息序号];
	var 加密等级 = 当前信息.EncryptLevel;
	var 解密等级 = _root.主角被动技能.解密.启用 ? _root.主角被动技能.解密.等级 : 0;
	var targetUI = this;
	var itemName = this.当前情报物品名称;
	this.infotext.htmlText = "<font color='#888888'>加载中...</font>";

	IntelligenceTextLoader.getPageText(itemName, String(当前信息.PageKey), function(loadedText:String):Void {
		_root.物品UI函数.渲染情报文本.call(targetUI, loadedText, 加密等级, 解密等级);
	}, function():Void {
		targetUI.infotext.htmlText = "<font color='#ff0000'>文本加载失败</font>";
	});
};

_root.物品UI函数.渲染情报文本 = function(txt:String, 加密等级:Number, 解密等级:Number):Void {
	if (txt == undefined || txt == null || txt == "") {
		this.infotext.htmlText = "<font color='#888888'>无文本数据</font>";
		this.hinttext.text = "";
		return;
	}

	if (加密等级 > 解密等级) {
		txt = _root.加密html剧情文本(txt, this.EncryptReplace, this.EncryptCut);
		this.hinttext.text = "信息未完全解明。需要解密技能达到 " + 加密等级 + " 级";
	} else if (加密等级 > 0) {
		this.滑动按钮._visible = true;
		this.滑动按钮.gotoAndStop(this.显示解密后文本 ? 2 : 1);
		this.滑动按钮btn._visible = true;
		if (!this.显示解密后文本) txt = _root.加密html剧情文本(txt, this.EncryptReplace, this.EncryptCut);
		this.hinttext.text = this.显示解密后文本
			? "信息已解明。点击按钮切换未解明的文本"
			: "信息未完全解明。点击按钮切换已解明的文本";
	} else {
		this.hinttext.text = "";
	}
	this.infotext.htmlText = _root.处理html剧情文本(txt);
};
