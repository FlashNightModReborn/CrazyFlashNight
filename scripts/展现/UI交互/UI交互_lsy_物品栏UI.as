

//新版物品栏
_root.物品UI函数 = new Object();

// === 强化面板状态保持系统（简化版）===
/**
 * 强化面板状态对象 - 只保存帧号
 * 用于在热切换装备时保留当前操作子项（强化/强化度转换/插件改装等）
 */
_root.物品UI函数.强化面板状态 = {
	lastFrame: null  // 上一次所在帧号
};

/**
 * 绑定强化面板实例，自动跟踪帧变化
 * @param {MovieClip} panel 强化面板MC实例
 */
_root.物品UI函数.强化面板_注册 = function(panel:MovieClip):Void {
	if (!panel) return;
	var self = _root.物品UI函数;

	// 初始化lastFrame
	if (self.强化面板状态.lastFrame == null) {
		self.强化面板状态.lastFrame = panel._currentframe;
	}

	// 记录当前帧，用于检测变化
	panel.__enhance__last = panel._currentframe;

	// 监听帧变化
	panel.onEnterFrame = function():Void {
		if (this.__enhance__last != this._currentframe) {
			self.强化面板状态.lastFrame = this._currentframe;
			this.__enhance__last = this._currentframe;
		}
	};

	// 面板卸载时保存状态
	panel.onUnload = function():Void {
		self.强化面板状态.lastFrame = this._currentframe;
	};
};

/**
 * 主动保存（在热切换前显式调用）
 * @param {MovieClip} panel 强化面板MC实例
 */
_root.物品UI函数.强化面板_保存 = function(panel:MovieClip):Void {
	if (!panel) return;
	_root.物品UI函数.强化面板状态.lastFrame = panel._currentframe;
};

/**
 * 恢复状态（在刷新/重建面板之后调用）
 * @param {MovieClip} panel 强化面板MC实例
 */
_root.物品UI函数.强化面板_恢复 = function(panel:MovieClip):Void {
	if (!panel) return;
	var lastFrame = _root.物品UI函数.强化面板状态.lastFrame;

	// 用帧号恢复，确保在有效范围内
	if (!isNaN(lastFrame) && lastFrame > 0 && lastFrame <= panel._totalframes) {
		panel.gotoAndStop(lastFrame);

		// 手动调用对应帧的初始化函数，刷新业务数据
		// 因为gotoAndStop到当前已在的帧时，帧脚本不会重新执行
		if (lastFrame >= 6 && lastFrame <= 11) {
			// "默认" 帧 (6-11)
			panel.刷新默认界面();
		} else if (lastFrame >= 12 && lastFrame <= 19) {
			// "强化装备" 帧 (12-19)
			panel.刷新强化装备界面();
		} else if (lastFrame >= 20 && lastFrame <= 28) {
			// "强化度转换" 帧 (20-28)
			panel.初始化强化度转换界面();
		} else if (lastFrame >= 29 && lastFrame <= 36) {
			// "插件改装" 帧 (29-36)
			panel.初始化插件改装界面();
		}
	} else {
		// 兜底：回到第1帧
		panel.gotoAndStop(1);
	}
};

_root.物品UI函数.背包 = new Object();
_root.物品UI函数.装备栏 = new Object();
_root.物品UI函数.药剂栏 = new Object();

//对ItemIcon相关函数的包装
_root.createItemIcon = function(mc, name, value){
	return new ItemIcon(mc, name, value);
}

EventBus.getInstance().subscribe("物品栏排序图标点击",function(methodName:String){
	ItemSortUtil.sortInventory(_root.物品栏.背包, methodName, function(){
		var info = {
			startindex: 0, 
			startdepth: 0, 
			row: 5, 
			col: 10, 
			padding: 28
		};
		IconFactory.createInventoryLayout(_root.物品栏.背包, 物品栏界面.物品图标, info);
	});
},null);

EventBus.getInstance().subscribe("材料栏排序图标点击",function(methodName:String){
	_root.物品UI函数.删除材料图标();
	// _root.发布消息(methodName)
	_root.物品UI函数.创建材料图标(methodName);
},null);

// === 材料栏分页系统 ===
_root.物品UI函数.材料栏分页 = {
	当前页: 0,
	总页数: 1,
	每页数量: 100,  // 10列 × 10行
	材料列表缓存: null  // 缓存排序后的材料列表，避免翻页时重新排序
};

//商店购买售卖函数

_root.物品UI函数.购买物品 = function(){
	// if(this.购买等级 > _root.等级){
	// 	pricetext.htmlText = "你的等级不足，无法购买！";
	// 	return false;
	// }
	if(this.总价 > _root.金钱 || isNaN(_root.金钱) || isNaN(this.总价)){
		pricetext.htmlText = "金钱不足！";
		return false;
	}
	if(ItemUtil.singleAcquire(this.物品名,this.数量) != true){
		pricetext.htmlText = "物品栏空间不足！";
		return false;
	}
	_root.金钱 -= this.总价;
	// 成就记账（埋点 #3，NPC 金币购买成功分支；守卫为纯防御——同属 asLoader 发布物恒真）
	if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
		org.flashNight.arki.achievement.AchievementMetrics.record("购买物品次数", 1);
		org.flashNight.arki.achievement.AchievementMetrics.record("购买花费金币", this.总价);
	}
	_root.soundEffectManager.playSound("收银机.mp3");
	_root.最上层发布文字提示(this.displayname + " X " + this.数量 + "已放入物品栏");
	this.gotoAndStop("空");
	this.showtext.text = "购买成功，花费 $" + this.总价;
	this.物品名 = null;
	_root.存档系统.dirtyMark = true;
	return true;
}

_root.物品UI函数.出售物品 = function(){
	// 检查是否为样品栏触发的批量出售（一次清空整个样品栏）
	if(this.来自样品栏) {
		// 调用批量出售样品栏，卖出所有样品对应的同名物品
		_root.物品UI函数.批量出售样品栏();

		// 关闭确认界面
		this.gotoAndStop("空");

		// 清除标记
		this.来自样品栏 = false;
		this.物品名 = null;
		this.sellCollection = null;
		this.sellIndex = null;

		return true;
	}

	// 原有单件出售逻辑
	var item = this.sellCollection.getItem(this.sellIndex);
	if(item !== this.sellItem) {
		this.gotoAndStop("空");
		this.showtext.text = "出售失败：物品已不在原位"
		return false;
	}

	// 自动拆除装备上的配件
	if(item.value && item.value.mods && item.value.mods.length > 0){
		var mods = item.value.mods.slice(); // 复制数组，避免循环中修改原数组
		var 卸载数量 = mods.length;

		// 将所有配件返还到材料栏
		var arr = [];
		for(var i = 0; i < mods.length; i++){
			arr.push({name: mods[i], value: 1});
		}
		ItemUtil.acquire(arr);

		// 清空配件槽（进阶插件tier不受影响）
		item.value.mods = [];

		// 播放卸下配件音效
		_root.播放音效("9mmclip2.wav");

		// 显示拆除的具体配件名称
		var 配件列表 = mods.join("、");
		_root.最上层发布文字提示("已自动卸下配件：" + 配件列表);
	}

	if(isNaN(this.物品强化度)){
		var totalValue = this.sellCollection.isDict ? item : item.value;
		if(totalValue < this.数量){
			this.gotoAndStop("空");
			this.showtext.text = "出售失败：物品数量不足"
			return false;
		}
		if(totalValue > this.数量) this.sellCollection.addValue(this.sellIndex,-this.数量);
		else this.sellCollection.remove(this.sellIndex);
	}else{
		if(item.value.level != this.物品强化度) {
			this.showtext.text = "出售失败：物品强化度改变"
			return false;
		}
		this.sellCollection.remove(this.sellIndex);
	}
	_root.金钱 += this.总价;
	// 成就记账（埋点 #4，单件出售成功分支；批量出售走 批量出售样品栏=埋点 #5，两路互斥不双计）
	if (org.flashNight.arki.achievement.AchievementMetrics != undefined) {
		org.flashNight.arki.achievement.AchievementMetrics.record("出售次数", 1);
		org.flashNight.arki.achievement.AchievementMetrics.record("出售所得金币", this.总价);
	}
	_root.soundEffectManager.playSound("收银机.mp3");
	this.gotoAndStop("空");
	this.showtext.text = "出售成功，获得 $" + this.总价;
	this.物品名 = null;
	this.sellCollection = null;
	this.sellIndex = null;
	_root.存档系统.dirtyMark = true;
	return true;
}

_root.物品UI函数.计算强化收益 = function(当前总价, 强化等级){
	if(isNaN(强化等级)) 强化等级 = 1;
	var 每石最大收益 = 强化等级 * 100 + 700;
	var 强化石个数 = Math.pow((强化等级-2) * (强化等级-1)/2,2) + 强化等级 - 1;
	var 最大收益 = 强化石个数 * 每石最大收益;
	var 强化收益 = Math.floor(当前总价 * (Math.pow((强化等级 - 1), 4.2) / 216 ));
	if(强化收益 > 最大收益) 强化收益 = 最大收益;
	return 强化收益;
}

/**
 * 计算售卖总价（统一的售卖价格计算函数）
 * @param item 物品对象（可以是装备或普通物品）
 * @param 数量 售卖数量
 * @return 返回一个对象，包含：{总价, 原总价, 基础价格, 售卖倍率, tier价格, 强化收益}
 */
_root.物品UI函数.计算售卖总价 = function(item, 数量){
	var result = {
		总价: 0,
		原总价: 0,        // 基础25%折扣价（不含口才加成）
		基础价格: 0,      // 装备价格 * 售卖倍率（含口才加成）
		售卖倍率: 0.25,
		tier价格: 0,      // tier价格 * 售卖倍率（含口才加成）
		强化收益: 0
	};

	// 获取物品名称和数据
	var 物品名 = item.name;
	var itemData = ItemUtil.getRawItemData(物品名);
	if(!itemData || !itemData.price){
		return result;
	}

	// 计算售卖倍率（基础25% + 口才加成）
	if(_root.主角被动技能.口才 && _root.主角被动技能.口才.启用){
		result.售卖倍率 += _root.主角被动技能.口才.等级 * 0.025;
	}

	// 计算基础价格（物品价格 * 数量 * 售卖倍率）
	var 单价 = parseInt(itemData.price);
	result.基础价格 = Math.floor(单价 * 数量 * result.售卖倍率);
	result.总价 = result.基础价格;

	// 计算原总价（装备基础25%售卖价）
	result.原总价 = Math.floor(单价 * 数量 * 0.25);

	// 如果是装备，计算 tier 进阶插件价格
	if(item.value && item.value.tier){
		var tierName = item.value.tier;
		var tierMaterialName = EquipmentUtil.tierNameToMaterialDict[tierName];
		if(tierMaterialName){
			var tierMaterialData = ItemUtil.getRawItemData(tierMaterialName);
			if(tierMaterialData && tierMaterialData.price){
				var tierPrice = parseInt(tierMaterialData.price);
				if(!isNaN(tierPrice)){
					// tier 插件价格也应用相同的售卖倍率
					result.tier价格 = Math.floor(tierPrice * result.售卖倍率);
					result.总价 += result.tier价格;

					// 原总价也要加上tier的基础25%售卖价
					result.原总价 += Math.floor(tierPrice * 0.25);
				}
			}
		}
	}

	// 如果是装备且有强化等级，计算强化收益
	if(item.value && item.value.level && item.value.level > 1){
		// 强化收益基于基础价格（不包含tier）计算
		result.强化收益 = this.计算强化收益(result.基础价格, item.value.level);
		result.总价 += result.强化收益;
	}

	return result;
}



//排列背包图标
_root.物品UI函数.创建背包图标 = function(){
	if(_root.物品栏界面.界面 != "物品栏") return;
	var 物品栏界面 = _root.物品栏界面;

	var info = {
		startindex: 0, 
		startdepth: 0, 
		row: 5, 
		col: 10, 
		padding: 28
	};
	IconFactory.createInventoryLayout(_root.物品栏.背包, 物品栏界面.物品图标, info);

	var 装备栏 = _root.物品栏.装备栏;
	var 装备栏位列表 = ["头部装备","上装装备","下装装备","手部装备","脚部装备","颈部装备","长枪","手枪","手枪2","刀","手雷"];
	//设置装备栏事件分发器
	var equipmentDispatcher = new LifecycleEventDispatcher(物品栏界面.物品图标);
	装备栏.setDispatcher(equipmentDispatcher);

	for (var i = 0; i < 装备栏位列表.length; i++){
		var 装备类型 = 装备栏位列表[i];
		var 物品图标 = 物品栏界面[装备类型];
		物品图标.itemIcon = new EquipmentIcon(物品图标,装备栏,装备类型);
	}
}


//初始化药剂栏图标
_root.物品UI函数.初始化药剂栏图标 = function(){
	var 快捷药剂界面 = _root.玩家信息界面.快捷药剂界面;
	if(快捷药剂界面.药剂图标列表.length == 4) return;
	
	var list = [快捷药剂界面.位置示意0,快捷药剂界面.位置示意1,快捷药剂界面.位置示意2,快捷药剂界面.位置示意3];
	快捷药剂界面.药剂图标列表 = [];
	var 控制器列表 = [快捷药剂界面.控制器0,快捷药剂界面.控制器1,快捷药剂界面.控制器2,快捷药剂界面.控制器3];
	var 进度条列表 = [快捷药剂界面.进度条0,快捷药剂界面.进度条1,快捷药剂界面.进度条2,快捷药剂界面.进度条3];
	//设置事件分发器
	var dispatcher = new LifecycleEventDispatcher(快捷药剂界面);
	_root.物品栏.药剂栏.setDispatcher(dispatcher);

	for (var i = 0; i < 4; i++){
		var depth = list[i].getDepth();
		var posx = list[i]._x;
		var posy = list[i]._y;
		list[i].removeMovieClip();
		var 药剂图标 = 快捷药剂界面.attachMovie("物品图标", "快捷物品栏"+i, depth);
		药剂图标._x = posx;
		药剂图标._y = posy;
		快捷药剂界面.药剂图标列表.push(药剂图标);
		// 药剂图标.itemIcon = new DrugIcon(药剂图标, _root.物品栏.药剂栏, i, 进度条列表[i]);
		控制器列表[i].药剂栏 = 药剂图标;
		_root["快捷物品栏" + this.index] = 药剂图标.itemIcon.name;
	}
	for (var i = 0; i < 4; i++){
		快捷药剂界面.药剂图标列表[i].itemIcon = new DrugIcon(快捷药剂界面.药剂图标列表[i], _root.物品栏.药剂栏, i, 进度条列表[i]);
	}
}

//排列商店图标
_root.物品UI函数.创建商店图标 = function(NPC物品栏){
	var 购买物品界面 = _root.购买物品界面;
	购买物品界面._visible = true;
	购买物品界面.gotoAndStop("选择物品");

	// 初始化样品栏
	_root.物品UI函数.初始化商店样品栏();

	var onIconRollOver = function(){
		var saleData = this.icon.saleData;
		if(saleData.requiredInfo != null){
			if(_root.收集品栏.情报.getValue(saleData.requiredInfo) <= 0){
				this.lock();
				var str = "<B>" + this.itemData.displayname + "</B><BR>获得情报<B>" + _root.getItemData(saleData.requiredInfo).displayname + "</B>后解锁购买";
				_root.注释(180, str);
				return;
			}else{
				this.unlock();
				_root.物品图标注释(this.name, this.value);
			}
		}else{
			_root.物品图标注释(this.name, this.value);
		}
	}
	var onIconPress = function(){
		_root.购买物品界面.准备购买的物品 = this.name;
		// _root.购买物品界面.准备购买的物品单价 = this.itemData.price;
		// _root.购买物品界面.准备购买的物品等级限制 = this.itemData.level;
		_root.购买物品界面.购买执行界面.购买确认(this.name);
	}
	var func = function(iconMC, i){
		iconMC.saleData = NPC物品栏[i];
		var saleItemName = typeof iconMC.saleData == "string" ? iconMC.saleData : iconMC.saleData.name;
		var itemIcon = new ItemIcon(iconMC, saleItemName, 1);
		itemIcon.RollOver = onIconRollOver;
		itemIcon.Press = onIconPress;
		// 检查需求情报
		if(iconMC.saleData.requiredInfo != null){
			if(_root.收集品栏.情报.getValue(iconMC.saleData.requiredInfo) <= 0){
				itemIcon.lock();
			}
		}
		return itemIcon;
	}

	var info = {
		startindex: 0,
		startdepth: 0,
		row: 10,
		col: 8,
		padding: 28,
		unloadCallback: function(){
			_root.购买物品界面.图标列表 = null;
			// 关闭商店时清空样品栏并移除动态创建的图标
			_root.物品UI函数.清空样品栏(true);
		}
	}

	var iconList = IconFactory.createIconLayout(购买物品界面.物品图标, func, info);
	_root.购买物品界面.图标列表 = iconList;
}

_root.物品UI函数.刷新商店图标 = function(NPC物品栏){
	// 旧场景 NPC/素材入口只传目录对象；先按 _root.shops 的对象身份反查 shopId，
	// 统一导向 NPC 商店 Web Panel。Launcher/协议不可用时继续执行原版 UI 回退。
	var NPC商店服务 = _root.UI系统 == undefined ? undefined : _root.UI系统.NPC商店WebView;
	if (NPC商店服务 != undefined && NPC商店服务.resolveShopIdByCatalog != undefined
			&& _root.gameCommands != undefined && _root.gameCommands["openNpcShop"] != undefined) {
		var NPC商店ID = NPC商店服务.resolveShopIdByCatalog(NPC物品栏);
		if (NPC商店ID != "" && _root.gameCommands["openNpcShop"]({shopId:NPC商店ID, source:"legacy_shop_refresh"})) {
			return true;
		}
	}
	if(!_root.购买物品界面.图标列表) {
		_root.物品UI函数.创建商店图标(NPC物品栏);
	}else{
		var 图标列表 = _root.购买物品界面.图标列表;
		for(var i=0; i<图标列表.length; i++){
			var iconMC = 图标列表[i];
			iconMC.saleData = NPC物品栏[i];
			var saleItemName = typeof NPC物品栏[i] == "string" ? iconMC.saleData : iconMC.saleData.name;
			iconMC.itemIcon.init(saleItemName, 1);
			// 检查需求情报
			if(iconMC.saleData.requiredInfo != null && _root.收集品栏.情报.getValue(iconMC.saleData.requiredInfo) <= 0){
				iconMC.itemIcon.lock();
			}else{
				iconMC.itemIcon.unlock();
			}
		}
	}
	_root.购买物品界面.NPC物品栏 = NPC物品栏;
	return false;
}



//排列仓库图标
_root.物品UI函数.刷新仓库图标 = function(inventory,page){
	var 仓库界面 = _root.仓库界面;
	var maxpage = 30;
	if(_root.仓库名称 == "后勤战备箱") maxpage = _root.物品UI函数.计算战备箱总页数();
	if(page < 0 || page >= maxpage) return;

	仓库界面.inventory = inventory;
	仓库界面.page = page;
	仓库界面.maxpage = maxpage;
	仓库界面.仓库页数显示 = String(page + 1)+" / "+String(maxpage);

	_root.物品UI函数.创建仓库图标(inventory,page);
}

_root.物品UI函数.创建仓库图标 = function(inventory, page){
	var 仓库界面 = _root.仓库界面;
	仓库界面.gotoAndStop("完毕");

	var info = {
		startindex: page * InventoryIcon.PAGE_SIZE,
		startdepth: 0,
		row: 5,
		col: 8,
		padding: 28,
		unloadCallback: function(){
			仓库界面.inventory = null;
			仓库界面.page = -1;
			仓库界面.maxpage = 0;
			仓库界面.仓库页数显示 = "";
			_root.仓库名称 = null;
		}
	}
	IconFactory.createInventoryLayout(inventory, 仓库界面.物品图标, info);
	仓库界面._visible = true;
}


_root.物品UI函数.计算战备箱总页数 = function():Number{
	return org.flashNight.arki.item.InventoryPanelService.getAccessibleCapacity("战备箱") / 40;
}


//收集品栏相关（临时）
_root.物品UI函数.创建材料图标 = function(methodName:String, keepPage:Boolean){
	if(_root.物品栏界面.界面 != "材料") return;

	// 允许事件未携带 methodName 时使用上次选择的排序方式，避免出现"点击整理但看起来没整理"的情况
	methodName = methodName || _root.物品UI函数.材料栏排序方式 || "byPrice";
	_root.物品UI函数.材料栏排序方式 = methodName;

	var 物品栏界面 = _root.物品栏界面;
	var 材料 = _root.收集品栏.材料;
	var 分页数据 = _root.物品UI函数.材料栏分页;

	// 挂载翻页函数到物品栏界面，供按钮调用
	物品栏界面.材料页面向前翻页 = _root.物品UI函数.材料页面向前翻页;
	物品栏界面.材料页面向后翻页 = _root.物品UI函数.材料页面向后翻页;

	//设置新的事件分发器
	var dispatcher = new LifecycleEventDispatcher(物品栏界面.材料图标);
	材料.setDispatcher(dispatcher);

	var 起始x = 物品栏界面.材料图标._x;
	var 起始y = 物品栏界面.材料图标._y;
	var 图标高度 = 28;
	var 图标宽度 = 28;
	var 列数 = 10;
	var 行数 = 10;
	var 总格数 = 行数*列数;
	var 换行计数 = 0;

	var 层级错位 = 50;

	物品栏界面.材料图标列表 = new Array(总格数);

	var 材料数据:Object = 材料.getItems();

	// 排序并缓存材料列表
	var sortedArray:Array = ItemSortUtil.sortObject(材料数据, methodName);
	var 材料列表 = [];
	for (var i:Number = 0; i < sortedArray.length; ++i) {
		材料列表.push(sortedArray[i].name);
	}
	分页数据.材料列表缓存 = 材料列表;

	// 计算总页数
	var 材料总数 = 材料列表.length;
	分页数据.总页数 = Math.max(1, Math.ceil(材料总数 / 分页数据.每页数量));

	// 如果不保留页码或当前页超出范围，重置到第一页
	if(!keepPage || 分页数据.当前页 >= 分页数据.总页数){
		分页数据.当前页 = 0;
	}

	// 计算当前页的起始索引
	var 起始索引 = 分页数据.当前页 * 分页数据.每页数量;

	for (var i = 0; i < 总格数; i++){
		var 物品图标 = 物品栏界面.attachMovie("物品图标","物品图标" + i,i + 层级错位);
		物品图标._x = 起始x;
		物品图标._y = 起始y;
		起始x += 图标宽度;
		换行计数++;
		if (换行计数 == 列数)
		{
			换行计数 = 0;
			起始x = 物品栏界面.材料图标._x;
			起始y += 图标高度;
		}
		物品栏界面.材料图标列表[i] = 物品图标;
		// 根据当前页计算实际的材料索引
		var 材料索引 = 起始索引 + i;
		var 材料名 = (材料索引 < 材料列表.length) ? 材料列表[材料索引] : null;
		物品图标.itemIcon = new CollectionIcon(物品图标,材料,材料名);
		物品图标.itemIcon.RollOver = function(){
			_root.物品图标注释(this.name, this.value);
			if (_root.购买物品界面._visible && _root.购买物品界面.购买执行界面.idle) _root.鼠标.gotoAndStop("手型准备抓取");
		}
		物品图标.itemIcon.Press = function(){
			if (_root.购买物品界面._visible && _root.购买物品界面.购买执行界面.idle){
				var dragIcon = _root.鼠标.物品图标容器.attachMovie("图标-" + this.itemData.displayname, "物品图标", 0);
				dragIcon.gotoAndStop(2);
				this.icon._alpha = 30;
				_root.鼠标.gotoAndStop("手型抓取");
			}
		}
		物品图标.itemIcon.Release = function(){
			_root.鼠标.物品图标容器.物品图标.removeMovieClip();
			this.icon._alpha = 100;
			if (_root.购买物品界面._visible && _root.购买物品界面.购买执行界面.idle && _root.购买物品界面.购买执行界面.hitTest(_root._xmouse, _root._ymouse)){
				_root.购买物品界面.购买执行界面.售卖确认(this.collection,this.index);
				return;
			}
		}
	}

	// 更新页码显示
	_root.物品UI函数.更新材料页码显示();

	//若出现添加物品行为则刷新整个材料栏
	dispatcher.subscribe("ItemAdded", function(){
		dispatcher.destroy();
		_root.物品UI函数.删除材料图标();
		_root.物品UI函数.创建材料图标(null, true); // 保留当前页码
	}, 物品栏界面.材料图标);
}

_root.物品UI函数.删除材料图标 = function(){
	var 材料图标列表 = _root.物品栏界面.材料图标列表;
	for(var i=0; i<材料图标列表.length; i++){
		材料图标列表[i].itemIcon.dispose();
		材料图标列表[i].removeMovieClip();
	}
	_root.物品栏界面.材料图标列表 = null;
}

// 材料页面向前翻页（上一页）
_root.物品UI函数.材料页面向前翻页 = function(){
	var 分页数据 = _root.物品UI函数.材料栏分页;
	if(分页数据.当前页 > 0){
		分页数据.当前页--;
		_root.物品UI函数.刷新材料页面();
	}
}

// 材料页面向后翻页（下一页）
_root.物品UI函数.材料页面向后翻页 = function(){
	var 分页数据 = _root.物品UI函数.材料栏分页;
	if(分页数据.当前页 < 分页数据.总页数 - 1){
		分页数据.当前页++;
		_root.物品UI函数.刷新材料页面();
	}
}

// 刷新材料页面（翻页时调用，复用缓存的材料列表）
_root.物品UI函数.刷新材料页面 = function(){
	var 物品栏界面 = _root.物品栏界面;
	var 材料 = _root.收集品栏.材料;
	var 分页数据 = _root.物品UI函数.材料栏分页;
	var 材料列表 = 分页数据.材料列表缓存;
	var 材料图标列表 = 物品栏界面.材料图标列表;

	if(!材料列表 || !材料图标列表) return;

	// 计算当前页的起始索引
	var 起始索引 = 分页数据.当前页 * 分页数据.每页数量;

	// 更新每个图标的显示内容
	for(var i = 0; i < 材料图标列表.length; i++){
		var 材料索引 = 起始索引 + i;
		var 材料名 = (材料索引 < 材料列表.length) ? 材料列表[材料索引] : null;
		// CollectionIcon 需要修改 index 后调用 init()
		var iconObj = 材料图标列表[i].itemIcon;
		iconObj.index = 材料名;
		iconObj.init();
	}

	// 更新页码显示
	_root.物品UI函数.更新材料页码显示();
}

// 更新材料页码显示
_root.物品UI函数.更新材料页码显示 = function(){
	var 分页数据 = _root.物品UI函数.材料栏分页;
	var 物品栏界面 = _root.物品栏界面;
	// 页码从1开始显示给用户
	物品栏界面.材料页面当前页数.text = (分页数据.当前页 + 1) + "/" + 分页数据.总页数;
}

_root.物品UI函数.创建情报图标 = function(){
	if(_root.物品栏界面.界面 != "情报") return;

	var 物品栏界面 = _root.物品栏界面;
	var 情报 = _root.收集品栏.情报;

	//设置新的事件分发器
	var dispatcher = new LifecycleEventDispatcher(物品栏界面.情报物品图标);
	情报.setDispatcher(dispatcher);
	
	var 起始x = 物品栏界面.情报物品图标._x;
	var 起始y = 物品栏界面.情报物品图标._y;
	var 图标高度 = 28;
	var 图标宽度 = 28;
	var 列数 = 10;
	var 行数 = 10;
	var 总格数 = 行数*列数;
	var 换行计数 = 0;

	var 层级错位 = 150;

	物品栏界面.情报图标列表 = new Array(总格数);
	
	for (var i = 0; i < 列数 * 行数; i++){
		var 情报名 = _root.图鉴信息.情报显示位置表[i];
		if(!情报名) {
			起始x += 图标宽度;
			换行计数++;
			if (换行计数 == 列数){
				换行计数 = 0;
				起始x = 物品栏界面.情报物品图标._x;
				起始y += 图标高度;
			}
			continue;
		}
		var 物品图标 = 物品栏界面.attachMovie("物品图标","情报物品图标" + i,i + 层级错位);
		物品图标._x = 起始x;
		物品图标._y = 起始y;
		起始x += 图标宽度;
		换行计数++;
		if (换行计数 == 列数){
			换行计数 = 0;
			起始x = 物品栏界面.情报物品图标._x;
			起始y += 图标高度;
		}
		物品栏界面.情报图标列表[i] = 物品图标;
		物品图标.itemIcon = new CollectionIcon(物品图标, 情报, 情报名);
		物品图标.itemIcon.Press = function(){
			_root.通用UI层.情报信息界面.显示情报信息(this.name,this.item);
		}
	}
}

_root.物品UI函数.删除情报图标 = function(){
	var 情报图标列表 = _root.物品栏界面.情报图标列表;
	for(var i=0; i<情报图标列表.length; i++){
		情报图标列表[i].itemIcon.dispose();
		情报图标列表[i].removeMovieClip();
	}
	_root.物品栏界面.情报图标列表 = null;
}

_root.物品UI函数.初始化情报信息界面 = function(){
	this.nametext.text = "";
	this.valuetext.text = "";
	this.infovaluetext.text = "";
	this.pagetext.text = "";
	this.hinttext.text = "点击右侧情报物品查看详细信息";
	var 当前情报物品图标 = this.attachMovie("物品图标", "当前情报物品图标", 0);
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
	//
	this.显示解密后文本 = true;
	//
	this._x = -550;
	this.onEnterFrame = function(){
		var movex = -this._x * 0.15;
		if(movex < 1) movex = 1;
		this._x += movex;
		if(this._x >= 0){
			this._x = 0;
			delete this.onEnterFrame;
		}
	}
}

_root.物品UI函数.显示情报信息 = function(name,value){
	this._visible = true;
	var itemData = ItemUtil.getItemData(name);
	this.当前情报物品图标.itemIcon.init(name, 1);
	this.当前情报物品名称 = name; // 保存物品名称供刷新情报信息使用
	this.情报信息表 = [];
	this.EncryptReplace = _root.图鉴信息.情报信息[name].EncryptReplace;
	this.EncryptCut = _root.图鉴信息.情报信息[name].EncryptCut;
	var info = _root.图鉴信息.情报信息[name].Information;
	for(var i = 0; i < info.length; i++){
		if(info[i].Value <= value){
			this.情报信息表.push(info[i]);
		}
	}
	this.当前信息序号 = 0;
	this.已发现数量 = this.情报信息表.length;
	this.总信息数量 = info.length;
	//
	this.btn1._visible = true;
	this.btn2._visible = true;
	this.nametext.text = itemData.displayname;
	this.valuetext.text = "收集进度：" + value + " / " + itemData.maxvalue;
	if(this.已发现数量 == this.总信息数量) this.infovaluetext.text = "已发现全部 " + this.已发现数量 + " 页信息"
	else this.infovaluetext.text = "已发现 " + this.已发现数量 + " 页信息";
	this.刷新情报信息();
}

_root.物品UI函数.刷新情报信息 = function(){
	this.滑动按钮._visible = false;
	this.滑动按钮btn._visible = false;
	this.pagetext.text = String(this.当前信息序号 + 1) + " / " + this.已发现数量 + " 页";

	var 当前信息 = this.情报信息表[this.当前信息序号];
	var 加密等级 = 当前信息.EncryptLevel;
	var 解密等级 = _root.主角被动技能.解密.启用 ? _root.主角被动技能.解密.等级 : 0;
	var targetUI = this; // 保存当前UI的MovieClip引用
	var itemName = this.当前情报物品名称; // 获取物品名称

	// 从合并文件加载指定页
	this.infotext.htmlText = "<font color='#888888'>加载中...</font>";

	IntelligenceTextLoader.getPageText(itemName, String(当前信息.PageKey), function(loadedText:String):Void {
		_root.物品UI函数.渲染情报文本.call(targetUI, loadedText, 加密等级, 解密等级);
	}, function():Void {
		targetUI.infotext.htmlText = "<font color='#ff0000'>文本加载失败</font>";
	});
}

// 渲染情报文本（处理加密和显示）
_root.物品UI函数.渲染情报文本 = function(txt:String, 加密等级:Number, 解密等级:Number):Void {
	// 兜底处理：空文本显示提示
	if (txt == undefined || txt == null || txt == "") {
		this.infotext.htmlText = "<font color='#888888'>无文本数据</font>";
		this.hinttext.text = "";
		return;
	}

	if(加密等级 > 解密等级){
		txt = _root.加密html剧情文本(txt, this.EncryptReplace, this.EncryptCut);
		this.hinttext.text = "信息未完全解明。需要解密技能达到 " + 加密等级 + " 级";
	}else if(加密等级 > 0){
		this.滑动按钮._visible = true;
		this.滑动按钮.gotoAndStop(this.显示解密后文本 ? 2 : 1);
		this.滑动按钮btn._visible = true;
		if(!this.显示解密后文本) txt = _root.加密html剧情文本(txt, this.EncryptReplace, this.EncryptCut);
		this.hinttext.text = this.显示解密后文本 ? "信息已解明。点击按钮切换未解明的文本" : "信息未完全解明。点击按钮切换已解明的文本";
	}else{
		this.hinttext.text = "";
	}
	txt = _root.处理html剧情文本(txt);
	this.infotext.htmlText = txt;
}
