import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.neur.Event.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;


//新版物品栏
_root.物品UI函数 = new Object();

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
	UI.刷新强化装备界面 = this.刷新强化装备界面;
	UI.计算强化装备等级 = this.计算强化装备等级;
	UI.执行强化装备 = this.执行强化装备;

	UI.gotoAndStop("空");
}

_root.物品UI函数.刷新强化物品 = function(item, itemIcon){
	if(this.当前物品 != null) return;
	this.gotoAndStop("默认");
	this.当前物品 = item;
	this.当前物品图标 = itemIcon;
	this.强化物品图标.itemIcon = new ItemIcon(this.强化物品图标, item.name, item);
	this.强化物品图标.itemIcon.RollOver = function(){
		//
	};
	itemIcon.lock();
	this.名字文本.text = this.强化物品图标.itemIcon.itemData.displayname;
	if(item.value.level > 1){
		this.名字文本.text += " +" + item.value.level;
	}
	this.外观改造文本.text = "";
	this.配件文本.text = "配件系统（开发中）";
}

_root.物品UI函数.清空强化物品 = function(){
	this.强化物品图标.itemIcon.init(null, null);
	this.当前物品图标.unlock();
	this.当前物品图标 = null;
	this.当前物品 = null;
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
		this.强化数值文字.htmlText = "";
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
	for(var i = 当前等级; i < 目标等级; i++){
		强化石需要个数 += Math.floor(强化石倍率 * (i - 1) * (i - 1) * (i - 1) + 1);
		强化石节省个数 += Math.ceil((1 - 强化石倍率) * (i - 1) * (i - 1) * (i - 1));
	}
	//
	this.目标强化等级文字.text = "强化到" + 目标等级 + "级";
	var color = 强化石持有数 >= 强化石需要个数 ? "#33FF33" : "#FF3333";
	this.强化详情文字.htmlText = "需要强化石： <FONT COLOR='" + color + "'>" + 强化石需要个数 + " / " + 强化石持有数 + "<FONT>";
	if(强化石节省个数 > 0) this.强化详情文字.htmlText += "<BR>铁匠被动技能已节省 " + 强化石节省个数 + " 个";
	this.强化数值文字.htmlText = org.flashNight.gesh.tooltip.TooltipTextBuilder.buildEnhancementStats(this.当前物品图标.itemData, 目标等级).join("");
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
		this.gotoAndStop("默认");
	}else{
		_root.发布消息("强化石不足！");
	}
}



_root.物品UI函数.强化上限检测 = function(){
	if(_root.主线任务进度 > 129) return 13;
	var 强化度上限 = _root.主线任务进度 > 74 ? 9 : 7;
	if (_root.主角被动技能.铁匠.启用 && _root.主角被动技能.铁匠.等级 >= 10) 强化度上限++;
	return 强化度上限;
}