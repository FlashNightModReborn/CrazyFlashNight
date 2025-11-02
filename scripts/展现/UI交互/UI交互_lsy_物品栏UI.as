import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.neur.Event.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;


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
	_root.最上层发布文字提示(this.displayname + " X " + this.数量 + "已放入物品栏");
	this.gotoAndStop("空");
	this.showtext.text = "购买成功，花费 $" + this.总价;
	this.物品名 = null;
	_root.存档系统.dirtyMark = true;
	return true;
}

_root.物品UI函数.出售物品 = function(){
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
		startindex: page * 40, 
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
_root.物品UI函数.创建材料图标 = function(methodName:String){
	if(_root.物品栏界面.界面 != "材料") return;

	var 物品栏界面 = _root.物品栏界面;
	var 材料 = _root.收集品栏.材料;

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

	var 材料列表 = [];

	/*
	for(var key in 材料.getItems()){
		材料列表.push(key);
	}
	*/

	// _root.服务器.发布服务器消息(ObjectUtil.toString(材料列表));

	// methodName = methodName || "byPrice";

	var sortedArray:Array = ItemSortUtil.sortObject(材料数据, methodName);

	// _root.服务器.发布服务器消息(ObjectUtil.toString(sortedArray));

	for (var i:Number = 0; i < sortedArray.length; ++i) {
		材料列表.push(sortedArray[i].name);
	}
	
	for (var i = 0; i < 100; i++){
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
		物品图标.itemIcon = new CollectionIcon(物品图标,材料,材料列表[i]);
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
	//若出现添加物品行为则刷新整个材料栏
	dispatcher.subscribe("ItemAdded", function(){
		dispatcher.destroy();
		_root.物品UI函数.删除材料图标();
		_root.物品UI函数.创建材料图标();
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
	var txt = this.情报信息表[this.当前信息序号].Text;
	var 加密等级 = this.情报信息表[this.当前信息序号].EncryptLevel;
	var 解密等级 = _root.主角被动技能.解密.启用 ? _root.主角被动技能.解密.等级 : 0;
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
		if(this.当前物品栏 != null){
			this.当前物品栏.getDispatcher().unsubscribe("ItemRemoved", _root.物品UI函数.检查强化物品是否移动);
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
	this.当前物品栏.getDispatcher().unsubscribe("ItemRemoved", _root.物品UI函数.检查强化物品是否移动);
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
	if(this.强化度转换物品栏 != null){
		this.强化度转换物品栏.getDispatcher().unsubscribe("ItemRemoved", _root.物品UI函数.检查强化度转换物品是否移动);
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

	var currentTier = this.当前物品.value.tier;

	var 材料栏 = _root.收集品栏.材料;
	var iconIndex = 0;
	for(var i=0; i<this.进阶材料列表.length; i++){
		var itemName = this.进阶材料列表[i];
		var val = 材料栏.getValue(itemName);
		if(val > 0){
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
		}
	}

	for(iconIndex; iconIndex<this.材料选择图标列表.length; iconIndex++){
		var icon = this.材料选择图标列表[iconIndex].itemIcon;
		icon.unlock();
		icon.init(null,null);
	}
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

	var currentTier = this.当前物品.value.tier;

	var 材料栏 = _root.收集品栏.材料;
	var iconIndex = 0;
	for(var i=0; i<this.配件材料列表.length; i++){
		var itemName = this.配件材料列表[i];
		var val = 材料栏.getValue(itemName);
		if(val > 0){
			var icon = this.材料选择图标列表[iconIndex].itemIcon;
			icon.unlock();
			icon.init(itemName, val);
			// 检查是否能安装
			var avail = this.modAvailabilityDict[itemName];
			if(avail !== 1) {
				icon.lock();
			}
			iconIndex++;
		}
	}

	for(iconIndex; iconIndex<this.材料选择图标列表.length; iconIndex++){
		var icon = this.材料选择图标列表[iconIndex].itemIcon;
		icon.unlock();
		icon.init(null,null);
	}
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

_root.物品UI函数.特殊卸下配件列表 = {
	战术导轨: true,
	战术背带: true,
	战术鱼骨零件: true
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
		if(_root.物品UI函数.特殊卸下配件列表[matName]){
			var arr = [];
			for(var i=0; i< mods.length; i++){
				arr.push({name:mods[i],value:1});
			}
			ItemUtil.acquire(arr);
			item.value.mods = [];
		}else{
			ItemUtil.singleAcquire(matName, 1);
			mods.splice(index, 1);
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




_root.物品UI函数.强化上限检测 = function(){
	if(_root.主线任务进度 > 129) return 13;
	var 强化度上限 = _root.主线任务进度 > 74 ? 9 : 7;
	if (_root.主角被动技能.铁匠.启用 && _root.主角被动技能.铁匠.等级 >= 10) 强化度上限++;
	return 强化度上限;
}