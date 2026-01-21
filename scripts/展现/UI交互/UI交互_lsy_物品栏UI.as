import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.neur.Event.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.gesh.text.IntelligenceTextLoader;


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
	if(_root.主线任务进度 <= 13) return 0;
	var 页数 = 1;
	var 挑战 = _root.task_chains_progress.挑战;
	if (!isNaN(挑战)){
		if(挑战 > 0) 页数++;
		if(挑战 > 2) 页数++;
	}
	if (_root.主线任务进度 > 77) 页数 += 2;
	if (_root.基建系统.infrastructure.越野车) 页数++;
	return 页数;
}


_root.物品UI函数.创建资源箱图标 = function(inventory, name, row, col){
	if(row > 8) row = 8;
	if(col > 8) col = 8;
	var 资源箱界面 = _root.从库中加载外部UI("资源箱界面");
	资源箱界面.gotoAndStop("完毕");
	资源箱界面.资源箱名称.text = name;

	var 网格 = 资源箱界面.资源箱界面网格;
	网格.clear();
	网格.lineStyle(1, 0x3B3B39, 100);
	var padding = 28;
	var w = padding * col;
	var h = padding * row;
	for(var i=0; i < row+1; i++){
		网格.moveTo(0, i * padding);
		网格.lineTo(w, i * padding);
	}
	for(var i=0; i < col+1; i++){
		网格.moveTo(i * padding, 0);
		网格.lineTo(i * padding, h);
	}
	资源箱界面.窗体area._width = 16 + w;
	资源箱界面.窗体area._height = 48 + h;
	资源箱界面.分割线._width = 6 + w;
	资源箱界面.关闭按钮._x = 1 + w;

	var info = {
		startindex: 0, 
		startdepth: 0, 
		row: row, 
		col: col, 
		padding: 28
	}
	IconFactory.createInventoryLayout(inventory, 资源箱界面.物品图标, info);

	资源箱界面._x = 80;
	资源箱界面._y = 120;
	资源箱界面._visible = true;
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



// 新版强化界面

_root.物品UI函数.初始化强化界面 = function(UI:MovieClip){
	UI.当前物品 = null;
	// UI.涂装图标.itemIcon = new ItemIcon(UI.涂装图标, null, null);
	UI.物品选择框._visible = false;
	UI.刷新强化物品 = this.刷新强化物品;
	UI.清空强化物品 = this.清空强化物品;
	UI.刷新默认界面 = this.刷新默认界面;

	UI.刷新强化装备界面 = this.刷新强化装备界面;
	UI.计算强化装备等级 = this.计算强化装备等级;
	UI.执行强化装备 = this.执行强化装备;

	UI.初始化强化度转换界面 = this.初始化强化度转换界面;
	UI.刷新强化度转换界面 = this.刷新强化度转换界面;
	UI.添加强化度转换物品 = this.添加强化度转换物品;
	UI.执行强化度转换 = this.执行强化度转换;

	UI.初始化插件改装界面 = this.初始化插件改装界面;
	UI.刷新插件信息 = this.刷新插件信息;
	UI.选择槽位_进阶 = this.选择槽位_进阶;
	UI.执行进阶 = this.执行进阶;
	UI.选择槽位_配件 = this.选择槽位_配件;
	UI.执行安装配件 = this.执行安装配件;
	UI.执行卸下配件 = this.执行卸下配件;
	UI.一键卸下所有配件 = this.一键卸下所有配件;
	UI.插件改良向前翻页 = this.插件改良向前翻页;
	UI.插件改良向后翻页 = this.插件改良向后翻页;
	UI.刷新插件材料页面 = this.刷新插件材料页面;

	UI.gotoAndStop("空");
}

_root.物品UI函数.刷新强化物品 = function(item, index, itemIcon, inventory){
	// 判断是否为热切换（已有物品）还是首次加载（无物品）
	var isFirstLoad = (this.当前物品 == null);

	// 支持热切换：如果已有物品，先清理旧物品的事件监听并保存状态
	if(!isFirstLoad){
		// 保存当前面板状态（帧号）
		_root.物品UI函数.强化面板_保存(this);

		// 取消旧物品的ItemRemoved监听
		// [v2.3] 使用精确退订模式，传入 scope 参数
		if(this.当前物品栏 != null){
			this.当前物品栏.getDispatcher().unsubscribe("ItemRemoved", _root.物品UI函数.检查强化物品是否移动, this);
		}
		// 恢复旧物品图标的透明度（如果还存在）
		if(this.当前物品图标 != null && this.当前物品图标.icon != null){
			this.当前物品图标.icon._alpha = 100;
		}
		// 清空强化度转换界面的物品（切换主装备时重置转换界面）
		if(this.强化度转换物品 != null){
			this.刷新强化度转换界面();
		}
	}

	// 只在首次加载时跳转到默认帧，热切换时不跳（由恢复函数处理）
	if(isFirstLoad){
		this.gotoAndStop("默认");
	}

	// 设置新物品数据
	this.当前物品 = item;
	this.当前物品格 = index;
	this.当前物品图标 = itemIcon;
	this.当前物品栏 = inventory;
	this.强化物品图标.itemIcon = new ItemIcon(this.强化物品图标, item.name, item);
	this.强化物品图标.itemIcon.RollOver = function(){
		_root.物品图标注释(this.name, this.value, this.item);
	};
	this.强化物品图标.itemIcon.RollOut = function(){
		_root.注释结束();
	};

	// 刷新默认界面数据（更新装备信息显示）
	this.刷新默认界面();

	// 注册面板并在热切换时恢复状态
	_root.物品UI函数.强化面板_注册(this);
	if(!isFirstLoad){
		_root.物品UI函数.强化面板_恢复(this);
	}

	// 订阅新物品的ItemRemoved事件
	inventory.getDispatcher().subscribe("ItemRemoved", _root.物品UI函数.检查强化物品是否移动, this);
}

_root.物品UI函数.刷新默认界面 = function(){
	var item = this.当前物品;
	var itemData = item.getData();
	var tier = item.value.tier;
	var mods = item.value.mods;

	this.当前物品显示名字 = itemData.displayname;
	this.名字文本.htmlText = "<B>" + (tier ? "[" + tier + "]" : "" ) + this.当前物品显示名字;

	/*
	if(item.value.level > 1){
		this.名字文本.htmlText += " +" + item.value.level;
	}
	*/
	this.名字文本.htmlText += "</B>";

	var modslot = itemData.data.modslot;
	if(modslot > 0){
		this.配件物品格._visible = true;
		this.配件物品格.gotoAndStop(modslot);
	}else{
		this.配件物品格._visible = false;
	}
	var len = mods.length > 0 ? mods.length : 0;
	var modIconMCs = [this.配件图标1, this.配件图标2, this.配件图标3];
	for(var i=0; i < 3; i++){
		if(mods[i]){
			modIconMCs[i].itemIcon = new ItemIcon(modIconMCs[i], mods[i], 1);
		}else{
			modIconMCs[i].itemIcon = new ItemIcon(modIconMCs[i], null, null);
		}
	}
	this.配件材料列表 = EquipmentUtil.getAvailableModMaterials(item);

	this.插件文本.text = "配件槽：" + len + "/" + modslot + "\n进阶/涂装：";

	// 进阶
	this.进阶材料列表 = EquipmentUtil.getAvailableTierMaterials(item);
	if(tier){
		this.进阶图标框._visible = true;
		this.插件文本.text += "[" + tier + "]";
		this.进阶图标.itemIcon = new ItemIcon(this.进阶图标, EquipmentUtil.getTierItem(tier), 1);
	}else{
		if(this.进阶材料列表.length > 0){
			this.进阶图标框._visible = true;
			this.插件文本.text += "空";
		}else{
			this.进阶图标框._visible = false;
			this.插件文本.text += "不可用";
		}
		this.进阶图标.itemIcon = new ItemIcon(this.进阶图标, null, null);
	}
	this.插件改装按钮._visible = modslot > 0 || this.进阶材料列表.length > 0;
}

_root.物品UI函数.检查强化物品是否移动 = function(inventory, index){
	if(this.当前物品格 == index) this.清空强化物品();
}

_root.物品UI函数.清空强化物品 = function(){
	this.强化物品图标.itemIcon.init(null, null);
	this.当前物品图标 = null;
	this.当前物品 = null;
	this.当前物品格 = null;
	// [v2.3] 使用精确退订模式，传入 scope 参数
	this.当前物品栏.getDispatcher().unsubscribe("ItemRemoved", _root.物品UI函数.检查强化物品是否移动, this);
	this.当前物品栏 = null;
	this.当前物品显示名字 = null;

	this.进阶材料列表 = null;
	this.配件材料列表 = null;
	this.modAvailabilityDict = null;
	
	this.gotoAndStop("空");
}

_root.物品UI函数.刷新强化装备界面 = function(){
	var 当前等级 = this.当前物品.value.level;
	this.强化上限等级 = _root.物品UI函数.强化上限检测();
	this.强化上限文字.text = 强化上限等级;
	if(当前等级 >= this.强化上限等级){
		this.btn0._visible = false;
		this.btn1._visible = false;
		this.btn2._visible = false;
		this.btn3._visible = false;
		this.强化执行按钮._visible = false;
		this.目标强化等级 = null;
		this.目标强化等级文字.text = "";
		this.强化详情文字.htmlText = this.强化上限等级 == 13
			? "强化等级最高为13级，已经达到最大，不可继续强化！"
			: "强化等级已经达到当前阶段的上限，不可继续强化！推进流程可获得更高级别的强化技术";
	}else{
		this.btn0._visible = true;
		this.btn1._visible = true;
		this.btn2._visible = true;
		this.btn3._visible = true;
		this.强化执行按钮._visible = true;
		this.计算强化装备等级(当前等级 + 1);
	}
}

_root.物品UI函数.计算强化装备等级 = function(目标等级){
	var 当前等级 = this.当前物品.value.level;
	if(目标等级 > this.强化上限等级) 目标等级 = this.强化上限等级;
	else if(目标等级 <= 当前等级) 目标等级 = 当前等级 + 1;
	// 计算强化石倍率
	var 强化石倍率 = (_root.主角被动技能.铁匠 && _root.主角被动技能.铁匠.启用) ? Math.max(1 - _root.主角被动技能.铁匠.等级 * 0.05, 0) : 1;
	var 强化石持有数 = _root.收集品栏.材料.getValue("强化石");
	var 强化石需要个数 = 0;
	var 强化石节省个数 = 0;

	// 强化石个数公式：1 + (level - 1) ^ 3
	for(var i = 当前等级; i < 目标等级; i++){
		强化石需要个数 += Math.floor(强化石倍率 * (i - 1) * (i - 1) * (i - 1) + 1);
		强化石节省个数 += Math.ceil((1 - 强化石倍率) * (i - 1) * (i - 1) * (i - 1));
	}
	//
	// this.目标强化等级文字.text = "强化到" + 目标等级 + "级";
	this.目标强化等级文字.text = 目标等级;
	var color = 强化石持有数 >= 强化石需要个数 ? "#33FF33" : "#FF3333";
	this.强化详情文字.htmlText = "需要强化石： <FONT COLOR='" + color + "'>" + 强化石需要个数 + " / " + 强化石持有数 + "<FONT><BR>";
	if(强化石节省个数 > 0) this.强化详情文字.htmlText += "铁匠被动技能已节省 " + 强化石节省个数 + " 个<BR>";
	this.强化详情文字.htmlText += org.flashNight.gesh.tooltip.TooltipTextBuilder.buildEnhancementStats(this.当前物品图标.itemData, 目标等级).join("");
	//
	this.目标强化等级 = 目标等级;
	this.强化石需要个数 = 强化石需要个数;
}

_root.物品UI函数.执行强化装备 = function(){
	if(_root.singleSubmit("强化石", this.强化石需要个数)){
		this.当前物品.value.level = this.目标强化等级;
		_root.最上层发布文字提示(this.强化物品图标.itemIcon.itemData.displayname + " 成功强化到 +" + this.目标强化等级);
		this.当前物品图标.refreshValue();
		this.强化物品图标.itemIcon.refreshValue();

		// 重新刷新强化界面，重新计算下一级的目标等级和所需材料
		// 如果已达到强化上限，会自动隐藏按钮
		this.刷新强化装备界面();

		// this.gotoAndStop("默认");
	}else{
		_root.发布消息("强化石不足！");
	}
}


_root.物品UI函数.初始化强化度转换界面 = function(){
	var panel = this;
	// 创建强化度转换物品图标的ItemIcon实例（每次进入都重新创建以确保实例存在）
	this.强化度转换物品图标.itemIcon = new ItemIcon(this.强化度转换物品图标, null, null);
	// 设置tooltip显示（确保鼠标悬停时显示物品信息）
	this.强化度转换物品图标.itemIcon.RollOver = function(){
		// 如果有物品，显示tooltip和卸下提示
		if(this.name){
			_root.物品图标注释(this.name, this.value, this.item);
			this.icon.互动提示.gotoAndPlay("卸下");
		}
	};
	this.强化度转换物品图标.itemIcon.RollOut = function(){
		_root.注释结束();
		this.icon.互动提示.gotoAndStop("空");
	};
	this.强化度转换物品图标.itemIcon.Press = function(){
		// 点击时卸载转换物品
		if(this.name){
			this.icon.互动提示.gotoAndStop("空");
			panel.刷新强化度转换界面();
			_root.播放音效("9mmclip2.wav");
		}
	};
	// 初始化默认描述文本
	this.强化度转换描述文本.text = "同类型的装备可以交换强化度。";
	// 清空转换物品数据（防止上次遗留数据）
	this.刷新强化度转换界面();
}

_root.物品UI函数.刷新强化度转换界面 = function(){
	// 清空强化度转换物品相关数据
	// [v2.3] 使用精确退订模式，传入 scope 参数
	if(this.强化度转换物品栏 != null){
		this.强化度转换物品栏.getDispatcher().unsubscribe("ItemRemoved", _root.物品UI函数.检查强化度转换物品是否移动, this);
	}
	this.强化度转换物品 = null;
	this.强化度转换物品栏 = null;
	this.强化度转换物品格 = null;
	this.强化度转换物品图标原始图标 = null;  // 清空原始图标引用
	this.强化度转换物品图标.itemIcon.init(null, null);
	this.强化度转换名字文本.text = "将需转强化的装备拖至右框";
	// 重置描述文本为默认值
	this.强化度转换描述文本.text = "同类型的装备可以交换强化度。";
	this.强化度按钮背景._visible = true;
	this.强化执行按钮._visible = false;
}

_root.物品UI函数.添加强化度转换物品 = function(item, index, itemIcon, inventory){
	// 检查是否已有转换物品
	if(this.强化度转换物品 != null) return;

	// 检查类型是否匹配
	var 当前物品类型 = this.当前物品.getData().use;
	var 转换物品类型 = item.getData().use;
	if(当前物品类型 != 转换物品类型){
		_root.发布消息("只能在相同类型的装备之间转换强化度！");
		return;
	}

	// 检查是否为同一件物品
	if(inventory === this.当前物品栏 && index === this.当前物品格){
		_root.发布消息("不能选择同一件装备！");
		return;
	}

	// 设置强化度转换物品
	this.强化度转换物品 = item;
	this.强化度转换物品格 = index;
	this.强化度转换物品图标原始图标 = itemIcon;  // 保存原始图标引用
	this.强化度转换物品栏 = inventory;
	this.强化度转换物品图标.itemIcon.init(item.name, item);
	this.强化度按钮背景._visible = false;
	this.强化执行按钮._visible = true;

	// 订阅物品移除事件
	inventory.getDispatcher().subscribe("ItemRemoved", _root.物品UI函数.检查强化度转换物品是否移动, this);

	// 显示转换物品信息（名字文本，带进阶前缀）
	var itemData = item.getData();
	var tier = item.value.tier;
	this.强化度转换名字文本.text = (tier ? "[" + tier + "]" : "") + itemData.displayname;

	// 更新描述文本，显示详细的转换信息
	var 当前等级 = this.当前物品.value.level;
	var 转换等级 = item.value.level;
	var 当前名称 = this.当前物品显示名字;
	var 转换名称 = (tier ? "[" + tier + "]" : "") + itemData.displayname;

	var 描述文本 = "";
	描述文本 += "点击齿轮图标,互换强化度。\n\n";

	if(当前等级 == 转换等级){
		描述文本 += "<FONT COLOR='#999999'>两件装备强化度相同，转换无实际效果。</FONT>";
	}else if(当前等级 < 转换等级){
		描述文本 += "<FONT COLOR='#33FF33'>左侧装备强化度提升 " + (转换等级 - 当前等级) + " 级。</FONT>";
	}else{
		描述文本 += "<FONT COLOR='#FF9933'>左侧装备强化度下降 " + (当前等级 - 转换等级) + " 级。</FONT>";
	}

	this.强化度转换描述文本.htmlText = 描述文本;
	_root.播放音效("9mmclip2.wav");
}

_root.物品UI函数.检查强化度转换物品是否移动 = function(inventory, index){
	if(this.强化度转换物品格 == index){
		this.刷新强化度转换界面();
	}
}

_root.物品UI函数.执行强化度转换 = function(){
	if(this.强化度转换物品 == null){
		_root.发布消息("请先放入要转换的装备！");
		return;
	}

	// 交换强化度
	var 临时等级 = this.当前物品.value.level;
	this.当前物品.value.level = this.强化度转换物品.value.level;
	this.强化度转换物品.value.level = 临时等级;

	// 刷新所有相关图标显示
	this.当前物品图标.refreshValue();  // 刷新当前物品在背包中的图标
	this.强化物品图标.itemIcon.refreshValue();  // 刷新强化界面左边的大图标
	this.强化度转换物品图标.itemIcon.refreshValue();  // 刷新强化度转换界面右边的大图标
	if(this.强化度转换物品图标原始图标){  // 刷新转换物品在背包中的图标
		this.强化度转换物品图标原始图标.refreshValue();
	}

	_root.播放音效("9mmclip2.wav");
	_root.最上层发布文字提示("强化度转换成功！");

	// 清理并返回默认界面
	this.刷新强化度转换界面();
	this.gotoAndStop("默认");
}




_root.物品UI函数.初始化插件改装界面 = function(){
	var panel = this;

	this.槽位选择按钮_进阶._visible = false;
	this.槽位选择按钮_配件._visible = false;

	this.改装图标_进阶.itemIcon = new ItemIcon(this.改装图标_进阶, null, null);
	this.改装图标_进阶.itemIcon.RollOver = function(){
		_root.物品图标注释(this.name, this.value, this.item);
	};
	this.改装图标_进阶.itemIcon.RollOut = function(){
		_root.注释结束();
	};
	this.改装图标_进阶.itemIcon.Press = function(){
		panel.选择槽位_进阶();
	};

	var modslotMCs = [this.改装图标_配件1, this.改装图标_配件2, this.改装图标_配件3];
	for(var i=0; i<3; i++){
		modslotMCs[i].itemIcon = new ItemIcon(modslotMCs[i], null, null);
		modslotMCs[i].itemIcon.RollOver = function(){
			// 先显示物品tooltip
			_root.物品图标注释(this.name, this.value, this.item);
			// 再显示互动提示
			this.icon.互动提示.gotoAndPlay("卸下");
		};
		modslotMCs[i].itemIcon.RollOut = function(){
			// 关闭tooltip
			_root.注释结束();
			// 隐藏互动提示
			this.icon.互动提示.gotoAndStop("空");
		};
		modslotMCs[i].itemIcon.Press = function(){
			this.icon.互动提示.gotoAndStop("空");
			panel.执行卸下配件(this.name);
		};
	}

	// 创建选择图标
	var onIconRollOver = function(){
		if(panel.选中的槽位 === 1){
			var tierName = EquipmentUtil.tierMaterialToNameDict[this.name];
			var tierKey = EquipmentUtil.materialToTierDict[this.name];
			var tierData = ItemUtil.getItemData(panel.当前物品.name)[tierKey];
			var list = org.flashNight.gesh.tooltip.TooltipTextBuilder.buildTierInfo(panel.当前物品显示名字, this.name, tierName, tierData);
			if(list.length > 0){
				_root.注释(200, list.join(""));
			}
		}else if(panel.选中的槽位 === 2){
			var avail = panel.modAvailabilityDict[this.name]
			if(avail === 1){
				_root.物品图标注释(this.name, this.value);
			}else{
				_root.注释(200, EquipmentUtil.modAvailabilityResults[avail]);
			}
		}
	}
	var onIconPress = function(){
		if(!this.locked) {
			if(panel.选中的槽位 === 1) panel.执行进阶(this.name);
			else if(panel.选中的槽位 === 2) panel.执行安装配件(this.name);
		}
	}
	var func = function(iconMC, i){
		var itemIcon = new ItemIcon(iconMC, null, null);
		itemIcon.RollOver = onIconRollOver;
		itemIcon.Press = onIconPress;
		return itemIcon;
	}
	var info = {
		startindex: 0, 
		startdepth: 0, 
		row: 5, 
		col: 6, 
		padding: 28,
		unloadCallback: function(){
			this.材料选择图标列表 = null;
		}
	}
	this.材料选择图标列表 = IconFactory.createIconLayout(this.材料选择图标, func, info);

	// 初始化翻页状态（默认隐藏翻页控件）
	this.插件当前页 = 0;
	this.插件总页数 = 1;
	this.插件改装当前页数._visible = false;
	this.btn1._visible = false;
	this.btn2._visible = false;

	this.刷新插件信息();
}


_root.物品UI函数.刷新插件信息 = function(){
	// _root.发布消息("选中的槽位", this.选中的槽位);
	if(!this.选中的槽位) this.选中的槽位 = 0;
	if(this.cursor._currentLabel == "选中") {

		this.cursor.gotoAndPlay("消失");
		this.cursor._currentLabel = "消失";
	}

	this.进阶图标框._visible = true;
	this.插件描述文本._visible = true;
	var item = this.当前物品;
	var itemData = item.getData();

	// 进阶UI
	this.enableTier = false;
	if(item.value.tier){
		this.改装图标_进阶.itemIcon.init(EquipmentUtil.getTierItem(item.value.tier), 1);
	}else{
		this.改装图标_进阶.itemIcon.init(null,null);
		if(this.进阶材料列表.length > 0){
			this.enableTier = true;
		}
	}
	this.槽位选择按钮_进阶._visible = this.enableTier;

	// 配件UI
	this.enableMod = false;
	var modslot = itemData.data.modslot;
	var modslotMCs = [this.改装图标_配件1, this.改装图标_配件2, this.改装图标_配件3];
	if(modslot <= 0){
		this.配件物品格._visible = false;
		modslotMCs[0].itemIcon.init(null,null);
		modslotMCs[1].itemIcon.init(null,null);
		modslotMCs[2].itemIcon.init(null,null);
	}else{
		var mods = item.value.mods;
		var len = mods.length > 0 ? mods.length : 0;
		for(var i=0; i<3; i++){
			if(mods[i]) modslotMCs[i].itemIcon.init(mods[i], 1);
			else modslotMCs[i].itemIcon.init(null,null);
		}
		if(len < modslot){
			this.enableMod = true;
			this.槽位选择按钮_配件._x = modslotMCs[len]._x;
			this.槽位选择按钮_配件._y = modslotMCs[len]._y;
		}
		this.配件物品格._visible = true;
		this.配件物品格.gotoAndStop(modslot);
	}
	this.槽位选择按钮_配件._visible = this.enableMod;

	this.modAvailabilityDict = {};
	for(var i = 0; i < this.配件材料列表.length; i++){
		this.modAvailabilityDict[this.配件材料列表[i]] = EquipmentUtil.isModMaterialAvailable(item, itemData, this.配件材料列表[i]);
	}

	this.材料物品格._visible = false;
	for(var iconIndex=0; iconIndex<this.材料选择图标列表.length; iconIndex++){
		var icon = this.材料选择图标列表[iconIndex].itemIcon;
		icon.unlock();
		icon.init(null,null);
	}

	// 智能自动选择槽位：空位 > 普通插件 > 进阶插件
	if(this.enableMod){
		// 优先选择空的配件槽
		this.选择槽位_配件();
		this.槽位选择按钮_配件._visible = true;
	} else if(this.enableTier){
		// 配件槽满了，选择进阶槽
		this.选择槽位_进阶();
		this.槽位选择按钮_进阶._visible = true;
	}
	// 否则保持未选择状态（选中的槽位 = 0）
}

_root.物品UI函数.选择槽位_进阶 = function(){
	this.选中的槽位 = 1;
	this.插件描述文本._visible = false;
	this.槽位选择按钮_进阶._visible = false;
	this.材料物品格._visible = true;
	this.cursor.gotoAndPlay("选中");
	this.cursor._currentLabel = "选中";
	this.cursor._x = this.槽位选择按钮_进阶._x;
	this.cursor._y = this.槽位选择按钮_进阶._y;
	this.槽位选择按钮_配件._visible = this.enableMod;

	// 计算拥有的进阶材料数量
	var 材料栏 = _root.收集品栏.材料;
	var 拥有材料数 = 0;
	for(var i = 0; i < this.进阶材料列表.length; i++){
		if(材料栏.getValue(this.进阶材料列表[i]) > 0) 拥有材料数++;
	}

	// 计算总页数并初始化翻页
	var 每页数量 = this.材料选择图标列表.length;
	this.插件当前页 = 0;
	this.插件总页数 = Math.max(1, Math.ceil(拥有材料数 / 每页数量));

	// 使用分页刷新函数显示材料
	this.刷新插件材料页面();
}

_root.物品UI函数.执行进阶 = function(matName:String){
	var item = this.当前物品;
	if(EquipmentUtil.isTierMaterialAvailable(item, matName)){
		if(ItemUtil.singleSubmit(matName, 1)){
			var tierName = EquipmentUtil.tierMaterialToNameDict[matName];
			item.value.tier = tierName;

			// 重置物品名称
			this.名字文本.htmlText = "<B>" + (tierName ? "[" + tierName + "]" : "" ) + this.当前物品显示名字;
			if(item.value.level > 1){
				this.名字文本.htmlText += " +" + item.value.level;
			}
			this.名字文本.htmlText += "</B>";

			// 刷新图标（进阶会改变图标外观）
			// 刷新背包中的物品图标
			if(this.当前物品图标 != null){
				this.当前物品图标.init();
			}
			// 刷新强化界面左侧的大图标
			if(this.强化物品图标 && this.强化物品图标.itemIcon){
				this.强化物品图标.itemIcon.init(item.name, item);
			}

			// 完成
			_root.播放音效("9mmclip2.wav");
			this.cursor.gotoAndPlay("消失");
			this.cursor._currentLabel = "消失";
		}else{
			_root.发布消息("材料不足！")
			this.cursor.gotoAndStop("空");
			this.cursor._currentLabel = "空";
		}
		this.刷新插件信息();
	}
}


_root.物品UI函数.选择槽位_配件 = function(){
	this.选中的槽位 = 2;
	this.插件描述文本._visible = false;
	this.槽位选择按钮_配件._visible = false;
	this.材料物品格._visible = true;
	this.cursor.gotoAndPlay("选中");
	this.cursor._currentLabel = "选中";
	this.cursor._x = this.槽位选择按钮_配件._x;
	this.cursor._y = this.槽位选择按钮_配件._y;
	this.槽位选择按钮_进阶._visible = this.enableTier;

	// 计算拥有的配件材料数量
	var 材料栏 = _root.收集品栏.材料;
	var 拥有材料数 = 0;
	for(var i = 0; i < this.配件材料列表.length; i++){
		if(材料栏.getValue(this.配件材料列表[i]) > 0) 拥有材料数++;
	}

	// 计算总页数并初始化翻页
	var 每页数量 = this.材料选择图标列表.length;
	this.插件当前页 = 0;
	this.插件总页数 = Math.max(1, Math.ceil(拥有材料数 / 每页数量));

	// 使用分页刷新函数显示材料
	this.刷新插件材料页面();
}

_root.物品UI函数.执行安装配件 = function(matName:String){
	var item = this.当前物品;
	if(this.modAvailabilityDict[matName]){
		var mods = item.value.mods;
		if(!mods) mods = item.value.mods = [];
		if(ItemUtil.singleSubmit(matName, 1)){
			mods.push(matName);
			
			// 刷新可安装的配件
			this.配件材料列表 = EquipmentUtil.getAvailableModMaterials(item);

			// 完成
			_root.播放音效("9mmclip2.wav");
			this.cursor.gotoAndPlay("消失");
			this.cursor._currentLabel = "消失";
		}else{
			_root.发布消息("材料不足！")
			this.cursor.gotoAndStop("空");
			this.cursor._currentLabel = "空";
		}
		this.刷新插件信息();
	}
}

_root.物品UI函数.执行卸下配件 = function(matName:String){
	var item = this.当前物品;
	var mods = item.value.mods;
	for(var index=0; index < mods.length; index++){
		if(mods[index] === matName){
			break;
		}
	}
	if(mods.length > 0 && index < mods.length){
		// 检查是否有其他插件依赖此插件
		var dependentMods = EquipmentUtil.getDependentMods(item, matName);
		if(dependentMods.length > 0){
			// 有依赖关系，需要级联卸载所有依赖的插件
			_root.发布消息("以下插件依赖此插件，将一起卸载：" + dependentMods.join(", "));

			// 收集所有需要卸载的插件（包括被依赖的和要移除的）
			var toRemove = {};
			toRemove[matName] = true;
			for(var d=0; d < dependentMods.length; d++){
				toRemove[dependentMods[d]] = true;
			}

			// 返还所有要卸载的插件
			var returnItems = [];
			var newMods = [];
			for(var i=0; i < mods.length; i++){
				if(toRemove[mods[i]]){
					returnItems.push({name:mods[i], value:1});
				}else{
					newMods.push(mods[i]);
				}
			}
			ItemUtil.acquire(returnItems);
			item.value.mods = newMods;
		}else{
			// 从配置中读取卸载行为
			var modData = EquipmentUtil.modDict[matName];
			if(modData && modData.detachPolicy === "cascade"){
				// 级联卸载：卸下所有配件
				var arr = [];
				for(var i=0; i< mods.length; i++){
					arr.push({name:mods[i],value:1});
				}
				ItemUtil.acquire(arr);
				item.value.mods = [];
			}else{
				// 单个卸载：只卸下当前配件
				ItemUtil.singleAcquire(matName, 1);
				mods.splice(index, 1);
			}
		}

		// 刷新可安装的配件
		this.配件材料列表 = EquipmentUtil.getAvailableModMaterials(item);

		// 完成
		this.cursor.gotoAndPlay("消失");
		this.cursor._currentLabel = "消失";
		this.刷新插件信息();
	}
}

/**
 * 一键卸下所有配件（仅卸载配件槽mods，不影响进阶tier）
 * 将当前装备上的所有配件卸载并返还到材料栏
 */
_root.物品UI函数.一键卸下所有配件 = function(){
	var item = this.当前物品;
	if(!item || !item.value.mods || item.value.mods.length == 0){
		_root.发布消息("当前装备没有已安装的配件！");
		return false;
	}

	var mods = item.value.mods;
	var 卸载数量 = mods.length;

	// 将所有配件返还到材料栏
	var arr = [];
	for(var i = 0; i < mods.length; i++){
		arr.push({name: mods[i], value: 1});
	}
	ItemUtil.acquire(arr);

	// 清空配件槽（进阶插件tier不受影响）
	item.value.mods = [];

	// 刷新可安装的配件列表
	this.配件材料列表 = EquipmentUtil.getAvailableModMaterials(item);

	// 刷新界面显示
	this.刷新插件信息();

	// 音效和提示
	_root.播放音效("9mmclip2.wav");
	// _root.最上层发布文字提示("已卸下 " + 卸载数量 + " 个配件");

	return true;
}

/**
 * 插件改装向前翻页（显示上一页材料）
 */
_root.物品UI函数.插件改良向前翻页 = function(){
	if(this.插件当前页 > 0){
		this.插件当前页--;
		this.刷新插件材料页面();
	}
}

/**
 * 插件改装向后翻页（显示下一页材料）
 */
_root.物品UI函数.插件改良向后翻页 = function(){
	if(this.插件当前页 < this.插件总页数 - 1){
		this.插件当前页++;
		this.刷新插件材料页面();
	}
}

/**
 * 刷新插件材料页面显示
 * 根据当前选中的槽位和页码，显示对应的材料图标
 */
_root.物品UI函数.刷新插件材料页面 = function(){
	var 每页数量 = this.材料选择图标列表.length; // 30个图标位置
	var 起始索引 = this.插件当前页 * 每页数量;

	// 清空所有图标
	for(var i = 0; i < this.材料选择图标列表.length; i++){
		var icon = this.材料选择图标列表[i].itemIcon;
		icon.unlock();
		icon.init(null, null);
	}

	var 材料栏 = _root.收集品栏.材料;
	var iconIndex = 0;

	if(this.选中的槽位 === 1){
		// 进阶模式
		var currentTier = this.当前物品.value.tier;
		var 已显示数量 = 0;

		for(var i = 0; i < this.进阶材料列表.length; i++){
			var itemName = this.进阶材料列表[i];
			var val = 材料栏.getValue(itemName);
			if(val > 0){
				// 跳过前面页的材料
				if(已显示数量 < 起始索引){
					已显示数量++;
					continue;
				}
				// 当前页已满
				if(iconIndex >= 每页数量) break;

				var icon = this.材料选择图标列表[iconIndex].itemIcon;
				icon.unlock();
				icon.init(itemName, val);
				// 检查是否能安装
				if(currentTier) {
					if(!(currentTier === "二阶" && itemName === "三阶复合防御组件") && !(currentTier === "三阶" && itemName === "四阶复合防御组件")){
						icon.lock();
					}
				}else if(itemName === "三阶复合防御组件" || itemName === "四阶复合防御组件"){
					icon.lock();
				}
				iconIndex++;
				已显示数量++;
			}
		}
	}else if(this.选中的槽位 === 2){
		// 配件模式
		var 已显示数量 = 0;

		for(var i = 0; i < this.配件材料列表.length; i++){
			var itemName = this.配件材料列表[i];
			var val = 材料栏.getValue(itemName);
			if(val > 0){
				// 跳过前面页的材料
				if(已显示数量 < 起始索引){
					已显示数量++;
					continue;
				}
				// 当前页已满
				if(iconIndex >= 每页数量) break;

				var icon = this.材料选择图标列表[iconIndex].itemIcon;
				icon.unlock();
				icon.init(itemName, val);
				// 检查是否能安装
				var avail = this.modAvailabilityDict[itemName];
				if(avail !== 1) {
					icon.lock();
				}
				iconIndex++;
				已显示数量++;
			}
		}
	}

	// 更新页码显示和翻页按钮可见性（只在需要翻页时显示）
	var 需要翻页 = this.插件总页数 > 1;
	this.插件改装当前页数._visible = 需要翻页;
	this.btn1._visible = 需要翻页;
	this.btn2._visible = 需要翻页;
	if(需要翻页){
		this.插件改装当前页数.text = (this.插件当前页 + 1) + "/" + this.插件总页数;
	}
}


_root.物品UI函数.强化上限检测 = function(){
	if(_root.主线任务进度 > 129) return 13;
	var 强化度上限 = _root.主线任务进度 > 74 ? 9 : 7;
	if (_root.主角被动技能.铁匠.启用 && _root.主角被动技能.铁匠.等级 >= 10) 强化度上限++;
	return 强化度上限;
}


// ========== 商店样品栏批量售卖系统 ==========

/**
 * 判断物品是否为"普通物品"（可批量售卖）
 * 普通物品定义：
 * - 非装备类（材料、消耗品等）：直接返回true
 * - 装备类：必须满足以下所有条件：
 *   1. 强化等级为null/undefined或<=1
 *   2. 无进阶插件（tier为null/undefined）
 *   3. 无配件（mods为空或长度为0）
 *
 * @param item 物品对象，包含name和value属性
 * @return Boolean 是否为普通物品
 */
_root.物品UI函数.是否普通物品 = function(item:Object):Boolean {
	if(!item || !item.name) return false;

	var itemData = ItemUtil.getItemData(item.name);
	if(!itemData) return false;

	var type = itemData.type;

	// 非装备类直接返回true（材料、消耗品等）
	if(type != "武器" && type != "防具") {
		return true;
	}

	// 装备类需要检查强化/进阶/配件
	var val = item.value;
	if(!val) return true; // 无value对象视为普通装备

	// 强化等级检查：level必须为null/undefined或<=1
	if(val.level != null && val.level != undefined && val.level > 1) {
		return false;
	}

	// 进阶插件检查：tier必须为null/undefined
	if(val.tier != null && val.tier != undefined) {
		return false;
	}

	// 配件检查：mods必须为空或长度为0
	if(val.mods && val.mods.length > 0) {
		return false;
	}

	return true;
}

/**
 * 出售单格物品（封装核心出售逻辑，供批量出售复用）
 *
 * @param collection 物品所在的集合（背包/材料栏等）
 * @param index 物品在集合中的索引
 * @param 数量 要出售的数量
 * @return Object 返回出售结果 {success:Boolean, 金额:Number, 物品名:String, 数量:Number}
 */
_root.物品UI函数.出售单格 = function(collection, index, 数量:Number):Object {
	var result = {success: false, 金额: 0, 物品名: "", 数量: 0};

	var item = collection.getItem(index);
	if(!item) return result;

	result.物品名 = item.name;
	var itemData = ItemUtil.getItemData(item.name);
	if(!itemData) return result;

	// 计算售价
	var priceResult = this.计算售卖总价(item, 数量);
	if(priceResult.总价 <= 0) {
		// 价格为0的物品，仍然可以"出售"（相当于丢弃）
		// 但不计入金额
	}

	// 处理物品移除
	if(collection.isDict) {
		// 字典型集合（如材料栏）
		var totalValue = item;
		if(typeof totalValue == "object") totalValue = item.value;
		if(totalValue > 数量) {
			collection.addValue(index, -数量);
		} else {
			数量 = totalValue; // 修正实际出售数量
			collection.remove(index);
		}
	} else {
		// 数组型集合（如背包）
		var totalValue = item.value;
		if(typeof totalValue == "number" && !isNaN(totalValue)) {
			// 可堆叠物品
			if(totalValue > 数量) {
				collection.addValue(index, -数量);
			} else {
				数量 = totalValue;
				collection.remove(index);
			}
		} else {
			// 不可堆叠物品（装备等），数量固定为1
			数量 = 1;
			collection.remove(index);
		}
	}

	// 重新计算实际售价（数量可能被修正）
	priceResult = this.计算售卖总价(item, 数量);

	// 增加金钱
	_root.金钱 += priceResult.总价;

	result.success = true;
	result.金额 = priceResult.总价;
	result.数量 = 数量;

	return result;
}

/**
 * 批量出售背包中所有同名的普通物品
 *
 * @param 物品名 要出售的物品名称
 * @return Object 返回出售结果 {success:Boolean, 总金额:Number, 总数量:Number, 跳过数量:Number}
 */
_root.物品UI函数.批量出售同名 = function(物品名:String):Object {
	var result = {success: false, 总金额: 0, 总数量: 0, 跳过数量: 0};

	if(!物品名) return result;

	var 背包 = _root.物品栏.背包;
	if(!背包) return result;

	// 倒序遍历背包，避免删除元素导致索引偏移
	for(var i = 背包.capacity - 1; i >= 0; i--) {
		var item = 背包.getItem(String(i));
		if(!item || item.name != 物品名) continue;

		// 检查是否为普通物品
		if(!this.是否普通物品(item)) {
			result.跳过数量++;
			continue;
		}

		// 计算出售数量
		var 数量 = 1;
		if(typeof item.value == "number" && !isNaN(item.value)) {
			数量 = item.value;
		}

		// 执行出售
		var sellResult = this.出售单格(背包, String(i), 数量);
		if(sellResult.success) {
			result.总金额 += sellResult.金额;
			result.总数量 += sellResult.数量;
		}
	}

	result.success = result.总数量 > 0;
	return result;
}

/**
 * 初始化商店样品栏
 * 在打开商店时调用，使用侧栏物品图标作为模板动态创建5个样品格
 */
_root.物品UI函数.初始化商店样品栏 = function():Void {
	var shopUI = _root.购买物品界面;
	if(!shopUI || !shopUI.侧栏物品图标) return;

	// 初始化样品栏数据结构
	shopUI.样品栏物品名列表 = [null, null, null, null, null];
	shopUI.样品栏图标列表 = [];

	// 获取模板位置作为起始点（使用模板自身坐标）
	var 模板 = shopUI.侧栏物品图标;
	var 起始x = 模板._x;
	var 起始y = 模板._y; // 直接使用模板的Y坐标
	var 图标间距 = 28;

	// 动态创建5个样品格
	for(var i = 0; i < 5; i++) {
		var 样品格 = shopUI.attachMovie("物品图标", "样品格" + i, 100 + i);
		样品格._x = 起始x;
		样品格._y = 起始y + i * 图标间距;
		shopUI.样品栏图标列表[i] = 样品格;

		// 创建空的ItemIcon用于展示
		样品格.itemIcon = new ItemIcon(样品格, null, null);
		样品格.itemIcon.RollOver = function() {
			if(this.name) {
				_root.物品图标注释(this.name, this.value);
				this.icon.互动提示.gotoAndPlay("卸下");
			}
		};
		样品格.itemIcon.RollOut = function() {
			_root.注释结束();
			this.icon.互动提示.gotoAndStop("空");
		};
		// 点击样品格可以移除该样品
		样品格.itemIcon.Press = function() {
			if(this.name) {
				this.icon.互动提示.gotoAndStop("空");
				_root.物品UI函数.移除样品栏物品(this.icon.slotIndex);
			}
		};
		样品格.slotIndex = i;
	}

	// 创建样品栏容器引用（用于hitTest检测）
	shopUI.样品栏容器 = {
		hitTest: function(x, y) {
			// 检测是否在样品栏区域内
			return shopUI.批量出售侧栏.hitTest(x, y);
		}
	};
}

/**
 * 添加物品到样品栏
 *
 * @param item 物品对象
 * @param collection 物品来源集合（必须是背包）
 * @param index 物品在集合中的索引
 * @return Boolean 是否成功添加
 */
_root.物品UI函数.添加至样品栏 = function(item:Object, collection, index):Boolean {
	var shopUI = _root.购买物品界面;
	if(!shopUI || !shopUI.样品栏物品名列表) return false;

	// 检查是否处于购买模式（购买执行界面正在显示购买确认，而非售卖）
	// 购买模式下不允许往样品栏拖入物品，避免界面文案错位
	var confirmUI = shopUI.购买执行界面;
	if(confirmUI && !confirmUI.idle && !confirmUI.sellCollection) {
		// 正在购买确认中，拒绝拖入样品栏
		_root.发布消息("购买模式下不能使用批量售卖栏");
		return false;
	}

	// 只接受来自背包的物品
	if(collection !== _root.物品栏.背包) {
		_root.发布消息("只能从背包拖拽物品到样品栏");
		return false;
	}

	// 检查是否为普通物品
	if(!this.是否普通物品(item)) {
		_root.发布消息("强化、进阶或有配件的装备不能批量出售，请单独出售");
		return false;
	}

	var 物品名 = item.name;

	// 清除所有样品格的高亮状态
	for(var i = 0; i < 5; i++) {
		var 格子 = shopUI.样品栏图标列表[i];
		if(格子 && 格子.互动提示) {
			格子.互动提示.gotoAndStop(1);
		}
	}

	// 检查是否已在样品栏中（去重）
	for(var i = 0; i < 5; i++) {
		if(shopUI.样品栏物品名列表[i] == 物品名) {
			// 已存在，高亮提示该格
			var 样品格 = shopUI.样品栏图标列表[i];
			样品格.互动提示.gotoAndPlay("高亮");
			_root.发布消息("该物品已在样品栏中");
			return false;
		}
	}

	// 寻找第一个空格
	var emptySlot = -1;
	for(var i = 0; i < 5; i++) {
		if(shopUI.样品栏物品名列表[i] == null) {
			emptySlot = i;
			break;
		}
	}

	if(emptySlot == -1) {
		_root.发布消息("样品栏已满，请先清空或移除部分样品");
		return false;
	}

	// 写入样品栏
	shopUI.样品栏物品名列表[emptySlot] = 物品名;
	var 样品格 = shopUI.样品栏图标列表[emptySlot];
	if(样品格 && 样品格.itemIcon) {
		样品格.itemIcon.init(物品名, 1);
	}

	// 检查快速售卖模式
	if(shopUI.快速售卖 == true) {
		// 立即执行批量出售
		var sellResult = this.批量出售同名(物品名);
		if(sellResult.success) {
			_root.soundEffectManager.playSound("收银机.mp3");
			var itemData = ItemUtil.getItemData(物品名);
			var displayName = itemData ? itemData.displayname : 物品名;
			_root.最上层发布文字提示("快速售出：" + displayName + " × " + sellResult.总数量 + "，获得 $" + sellResult.总金额);
			if(sellResult.跳过数量 > 0) {
				_root.发布消息(sellResult.跳过数量 + " 件强化/进阶装备被跳过");
			}
		} else {
			var itemData = ItemUtil.getItemData(物品名);
			_root.发布消息("背包中没有可出售的 " + (itemData ? itemData.displayname : 物品名));
		}
		// 快速模式下售后清空该格
		this.移除样品栏物品(emptySlot);
		_root.存档系统.dirtyMark = true;
	} else {
		// 非快速模式：打开或更新确认界面
		var confirmUI = shopUI.购买执行界面;
		if(confirmUI) {
			// 标记这是样品栏触发的批量确认
			confirmUI.来自样品栏 = true;

			// 如果确认界面未打开，先初始化
			if(confirmUI.idle) {
				confirmUI.售卖确认(collection, index);
			}

			// 更新预览显示（无论是首次打开还是追加样品）
			this.刷新样品栏预览(confirmUI);
		}
	}

	return true;
}

/**
 * 刷新样品栏预览显示
 * 用于更新确认界面的摘要信息
 *
 * @param confirmUI 确认界面引用
 */
_root.物品UI函数.刷新样品栏预览 = function(confirmUI):Void {
	if(!confirmUI) return;

	var preview = this.预览批量出售样品栏();
	if(preview.售出汇总.length > 0) {
		// 摘要格式：X 种物品，共 N 件
		var 种类数 = preview.售出汇总.length;
		confirmUI.nametext.htmlText = "<FONT COLOR='#33FF00'>批量卖出</FONT> " + 种类数 + " 种物品，共 " + preview.总数量 + " 件";
		confirmUI.pricetext.htmlText = "共获得 $" + preview.总金额;
		confirmUI.typetext.htmlText = "批量<BR>售卖";

		// 如果有跳过的物品，显示提示
		if(preview.跳过数量 > 0) {
			confirmUI.leveltext.htmlText = "<FONT COLOR='#FF6600'>" + preview.跳过数量 + " 件强化/进阶将被跳过</FONT>";
		} else {
			confirmUI.leveltext.htmlText = "";
		}

		// 隐藏滚动条和图标（批量模式不需要）
		confirmUI.滚动按钮._visible = false;
		confirmUI.滚动槽._visible = false;
		confirmUI.图标._visible = false;
	} else {
		confirmUI.nametext.htmlText = "<FONT COLOR='#FF6600'>样品栏无可售物品</FONT>";
		confirmUI.pricetext.htmlText = "背包中没有对应的可出售物品";
		confirmUI.leveltext.htmlText = "";
	}
}

/**
 * 移除样品栏中指定位置的物品
 *
 * @param slotIndex 样品格索引 (0-4)
 * @param skipRefresh 是否跳过刷新（批量清空时使用）
 */
_root.物品UI函数.移除样品栏物品 = function(slotIndex:Number, skipRefresh:Boolean):Void {
	var shopUI = _root.购买物品界面;
	if(!shopUI || !shopUI.样品栏物品名列表) return;
	if(slotIndex < 0 || slotIndex >= 5) return;

	shopUI.样品栏物品名列表[slotIndex] = null;
	var 样品格 = shopUI.样品栏图标列表[slotIndex];
	if(样品格 && 样品格.itemIcon) {
		样品格.itemIcon.init(null, null);
	}

	// 刷新确认界面预览（除非跳过）
	if(!skipRefresh) {
		var confirmUI = shopUI.购买执行界面;
		if(confirmUI && confirmUI.来自样品栏 && !confirmUI.idle) {
			// 检查样品栏是否还有物品
			var hasItems = false;
			for(var i = 0; i < 5; i++) {
				if(shopUI.样品栏物品名列表[i] != null) {
					hasItems = true;
					break;
				}
			}
			if(hasItems) {
				// 还有物品，刷新预览
				this.刷新样品栏预览(confirmUI);
			} else {
				// 样品栏已空，关闭确认界面回到默认状态
				confirmUI.来自样品栏 = false;
				confirmUI.gotoAndStop("空");
			}
		}
	}
}

/**
 * 清空样品栏所有物品并移除动态创建的MC
 * @param removeIcons 是否移除动态创建的图标MC（关闭商店时传true）
 */
_root.物品UI函数.清空样品栏 = function(removeIcons:Boolean):Void {
	var shopUI = _root.购买物品界面;
	if(!shopUI) return;

	// 清空物品数据（批量清空时跳过刷新）
	if(shopUI.样品栏物品名列表) {
		for(var i = 0; i < 5; i++) {
			this.移除样品栏物品(i, true); // skipRefresh = true
		}
	}

	// 关闭确认界面（如果处于样品栏模式）
	var confirmUI = shopUI.购买执行界面;
	if(confirmUI && confirmUI.来自样品栏 && !confirmUI.idle) {
		confirmUI.来自样品栏 = false;
		confirmUI.gotoAndStop("空");
	}

	// 如果需要移除动态创建的图标（关闭商店时）
	if(removeIcons && shopUI.样品栏图标列表) {
		for(var i = 0; i < shopUI.样品栏图标列表.length; i++) {
			var 样品格 = shopUI.样品栏图标列表[i];
			if(样品格) {
				样品格.removeMovieClip();
			}
		}
		shopUI.样品栏图标列表 = null;
		shopUI.样品栏物品名列表 = null;
		shopUI.样品栏容器 = null;
	}
}

/**
 * 预览批量出售样品栏（只计算不执行）
 * 用于在确认界面显示预计卖出的数量和金额
 *
 * @return Object {总金额, 总数量, 跳过数量, 售出汇总:Array, 跳过汇总:Array}
 */
_root.物品UI函数.预览批量出售样品栏 = function():Object {
	var result = {
		总金额: 0,
		总数量: 0,
		跳过数量: 0,
		售出汇总: [], // [{name, displayname, count, money}]
		跳过汇总: []  // [{displayname, count}]
	};

	var shopUI = _root.购买物品界面;
	if(!shopUI || !shopUI.样品栏物品名列表) return result;

	var 背包 = _root.物品栏.背包;
	if(!背包) return result;

	// 遍历样品栏中所有非空项
	for(var i = 0; i < 5; i++) {
		var 物品名 = shopUI.样品栏物品名列表[i];
		if(!物品名) continue;

		var itemData = ItemUtil.getItemData(物品名);
		var displayName = itemData ? itemData.displayname : 物品名;

		var 该物品总数量 = 0;
		var 该物品总金额 = 0;
		var 该物品跳过数 = 0;

		// 遍历背包计算该物品的预计售出
		for(var j = 0; j < 背包.capacity; j++) {
			var item = 背包.getItem(String(j));
			if(!item || item.name != 物品名) continue;

			// 检查是否为普通物品
			if(!this.是否普通物品(item)) {
				该物品跳过数++;
				continue;
			}

			// 计算数量
			var 数量 = 1;
			if(typeof item.value == "number" && !isNaN(item.value)) {
				数量 = item.value;
			}

			// 计算价格（不实际扣除）
			var priceResult = this.计算售卖总价(item, 数量);
			该物品总数量 += 数量;
			该物品总金额 += priceResult.总价;
		}

		// 汇总
		if(该物品总数量 > 0) {
			result.售出汇总.push({
				name: 物品名,
				displayname: displayName,
				count: 该物品总数量,
				money: 该物品总金额
			});
			result.总数量 += 该物品总数量;
			result.总金额 += 该物品总金额;
		}

		if(该物品跳过数 > 0) {
			result.跳过汇总.push({
				displayname: displayName,
				count: 该物品跳过数
			});
			result.跳过数量 += 该物品跳过数;
		}
	}

	return result;
}

/**
 * 批量出售样品栏中所有样品对应的同名普通物品
 * 点击"批量出售"按钮时调用
 */
_root.物品UI函数.批量出售样品栏 = function():Void {
	var shopUI = _root.购买物品界面;
	if(!shopUI || !shopUI.样品栏物品名列表) return;

	var 总金额 = 0;
	var 售出汇总 = []; // [{name, displayname, count, money}]
	var 跳过汇总 = [];

	// 遍历样品栏中所有非空项
	for(var i = 0; i < 5; i++) {
		var 物品名 = shopUI.样品栏物品名列表[i];
		if(!物品名) continue;

		var sellResult = this.批量出售同名(物品名);
		var itemData = ItemUtil.getItemData(物品名);
		var displayName = itemData ? itemData.displayname : 物品名;

		if(sellResult.success) {
			总金额 += sellResult.总金额;
			售出汇总.push({
				name: 物品名,
				displayname: displayName,
				count: sellResult.总数量,
				money: sellResult.总金额
			});
		}

		if(sellResult.跳过数量 > 0) {
			跳过汇总.push({
				displayname: displayName,
				count: sellResult.跳过数量
			});
		}
	}

	// 输出结果
	if(售出汇总.length > 0) {
		_root.soundEffectManager.playSound("收银机.mp3");

		// 构建提示文本
		var 提示文本 = "批量售出：";
		for(var j = 0; j < 售出汇总.length; j++) {
			if(j > 0) 提示文本 += "，";
			提示文本 += 售出汇总[j].displayname + " × " + 售出汇总[j].count;
		}
		提示文本 += "，共获得 $" + 总金额;
		_root.最上层发布文字提示(提示文本);

		// 跳过提示
		if(跳过汇总.length > 0) {
			var 跳过文本 = "以下装备因强化/进阶被跳过：";
			for(var k = 0; k < 跳过汇总.length; k++) {
				if(k > 0) 跳过文本 += "，";
				跳过文本 += 跳过汇总[k].displayname + " × " + 跳过汇总[k].count;
			}
			_root.发布消息(跳过文本);
		}

		_root.存档系统.dirtyMark = true;
	} else {
		_root.发布消息("样品栏为空或背包中没有对应的可出售物品");
	}

	// 批量出售后清空样品栏
	this.清空样品栏();
}
