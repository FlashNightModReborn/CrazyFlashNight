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
		_root.物品UI函数.删除背包图标();
		_root.物品UI函数.创建背包图标();
	});
},null);

EventBus.getInstance().subscribe("材料栏排序图标点击",function(methodName:String){
	_root.物品UI函数.删除材料图标();
	// _root.发布消息(methodName)
	_root.物品UI函数.创建材料图标(methodName);
},null);


//商店购买售卖函数

_root.物品UI函数.购买物品 = function(){
	if(this.购买等级 > _root.等级){
		pricetext.htmlText = "你的等级不足，无法购买！";
		return false;
	}
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
	_root.播放音效("收银机.mp3");
	this.gotoAndStop("空");
	this.showtext.text = "出售成功，获得 $" + this.总价;
	this.物品名 = null;
	this.sellCollection = null;
	this.sellIndex = null;
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
	var 背包 = _root.物品栏.背包;
	//设置背包事件分发器
	var bagDispatcher = new LifecycleEventDispatcher(物品栏界面.物品图标);
	背包.setDispatcher(bagDispatcher);
	
	var 起始x = 物品栏界面.物品图标._x;
	var 起始y = 物品栏界面.物品图标._y;
	var 图标高度 = 28;
	var 图标宽度 = 28;
	var 列数 = 10;
	var 行数 = 5;
	var 总格数 = 行数*列数;
	var 换行计数 = 0;

	物品栏界面.背包图标列表 = new Array(总格数);
	
	for (var i = 0; i < 总格数; i++)
	{
		var 物品图标 = 物品栏界面.attachMovie("物品图标","物品图标" + i,i);
		物品图标._x = 起始x;
		物品图标._y = 起始y;
		起始x += 图标宽度;
		换行计数++;
		if (换行计数 == 列数)
		{
			换行计数 = 0;
			起始x = 物品栏界面.物品图标._x;
			起始y += 图标高度;
		}
		物品栏界面.背包图标列表[i] = 物品图标;
		物品图标.itemIcon = new InventoryIcon(物品图标,背包,i);
	}

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

_root.物品UI函数.删除背包图标 = function(){
	var 背包图标列表 = _root.物品栏界面.背包图标列表;
	for(var i=0; i<背包图标列表.length; i++){
		背包图标列表[i].removeMovieClip();
	}
	_root.物品栏界面.背包图标列表 = null;
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

	var 起始x = 购买物品界面.物品图标._x;
	var 起始y = 购买物品界面.物品图标._y;
	var 图标高度 = 28;
	var 图标宽度 = 28;
	var 列数 = 8;
	var 行数 = 10;
	var 总格数 = 行数*列数;
	var 换行计数 = 0;

	购买物品界面.图标列表 = new Array(总格数);

	for (var i = 0; i < 总格数; i++)
	{
		var 物品图标 = 购买物品界面.attachMovie("物品图标","物品图标" + i,i);
		物品图标._x = 起始x;
		物品图标._y = 起始y;
		起始x += 图标宽度;
		换行计数++;
		if (换行计数 == 列数)
		{
			换行计数 = 0;
			起始x = 购买物品界面.物品图标._x;
			起始y += 图标高度;
		}
		购买物品界面.图标列表[i] = 物品图标;
		物品图标.itemIcon = new ItemIcon(物品图标, NPC物品栏[i][0], 1);
		物品图标.itemIcon.Press = function(){
			_root.购买物品界面.准备购买的物品 = this.name;
			_root.购买物品界面.准备购买的物品单价 = this.itemData.price;
			_root.购买物品界面.准备购买的物品等级限制 = this.itemData.level;
			// if (this.itemData.type != "武器" && this.itemData.type != "防具"){
			// 	_root.购买物品界面.gotoAndStop("购买数量");
			// }else{
			// 	_root.购买物品界面.gotoAndStop("结算");
			// }
			_root.购买物品界面.购买执行界面.购买确认(this.name);
		}
	}
}

_root.物品UI函数.刷新商店图标 = function(NPC物品栏){
	if(!_root.购买物品界面.图标列表) {
		_root.物品UI函数.创建商店图标(NPC物品栏);
	}else{
		var 图标列表 = _root.购买物品界面.图标列表;
		for(var i=0; i<图标列表.length; i++){
			图标列表[i].itemIcon.init(NPC物品栏[i][0], 1);
		}
	}
	_root.购买物品界面.NPC物品栏 = NPC物品栏;
}

_root.物品UI函数.删除商店图标 = function(){
	var 图标列表 = _root.购买物品界面.图标列表;
	for(var i=0; i<图标列表.length; i++){
		图标列表[i].removeMovieClip();
	}
	_root.购买物品界面.图标列表 = null;
}

//排列仓库图标
_root.物品UI函数.刷新仓库图标 = function(inventory,page){
	var 仓库界面 = _root.仓库界面;
	var maxpage = 30;
	if(_root.仓库名称 == "后勤战备箱") maxpage = _root.物品UI函数.计算战备箱总页数();
	if(page < 0 || page >= maxpage) return;

	//销毁之前的事件分发器
	if(仓库界面.inventory.hasDispatcher()){
		仓库界面.inventory.getDispatcher().destroy();
	}
	仓库界面.inventory = inventory;
	仓库界面.page = page;
	仓库界面.maxpage = maxpage;
	仓库界面.仓库页数显示 = String(page + 1)+" / "+String(maxpage);

	//设置新的事件分发器
	var dispatcher = new LifecycleEventDispatcher(仓库界面.物品图标);
	inventory.setDispatcher(dispatcher);

	if(!仓库界面.图标列表) {
		_root.物品UI函数.创建仓库图标(inventory,page);
		return;
	}

	//重置物品图标
	for (var i = 0; i < 仓库界面.图标列表.length; i++){
		var index = i + 40 * page;
		var 物品图标 = 仓库界面.图标列表[i];
		物品图标.itemIcon.reset(inventory, index);
	}
}

_root.物品UI函数.创建仓库图标 = function(inventory,page){
	var 仓库界面 = _root.仓库界面;
	仓库界面.gotoAndStop("完毕");

	var 起始x = 仓库界面.物品图标._x;
	var 起始y = 仓库界面.物品图标._y;
	var 图标高度 = 28;
	var 图标宽度 = 28;
	var 列数 = 8;
	var 行数 = 5;
	var 总格数 = 行数*列数;
	var 换行计数 = 0;

	仓库界面.图标列表 = new Array(总格数);
	
	for (var i = 0; i < 总格数; i++){
		var index = i + 40 * page;
		var 物品图标 = 仓库界面.attachMovie("物品图标","物品图标" + i,i);
		物品图标._x = 起始x;
		物品图标._y = 起始y;
		起始x += 图标宽度;
		换行计数++;
		if (换行计数 == 列数)
		{
			换行计数 = 0;
			起始x = 仓库界面.物品图标._x;
			起始y += 图标高度;
		}
		仓库界面.图标列表[i] = 物品图标;
		物品图标.itemIcon = new InventoryIcon(物品图标, inventory, index);
	}
	仓库界面._visible = true;
}

_root.物品UI函数.删除仓库图标 = function(){
	var 仓库界面 = _root.仓库界面;
	var 图标列表 = 仓库界面.图标列表;
	for(var i=0; i<图标列表.length; i++){
		图标列表[i].removeMovieClip();
	}
	仓库界面.图标列表 = null;
	仓库界面.inventory = null;
	仓库界面.page = -1;
	仓库界面.maxpage = 0;
	仓库界面.仓库页数显示 = "";
	_root.仓库名称 = null;
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
		物品图标.itemIcon.Press = function(){
			if (_root.购买物品界面._visible && _root.购买物品界面.购买执行界面.idle){
				this.icon.originalDepth = this.icon.getDepth();
				this.icon.swapDepths(1023);
				this.icon.图标壳.图标.gotoAndStop(2);
				this.icon.startDrag(true);
				_root.鼠标.gotoAndStop("手型抓取");
			}
		}
		物品图标.itemIcon.Release = function(){
			this.icon.图标壳.图标.gotoAndStop(1);
			this.icon.swapDepths(this.icon.originalDepth);
			this.icon.stopDrag();
			this.icon._x = this.x;
			this.icon._y = this.y;
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
			_root.物品栏界面.情报信息界面.显示情报信息(this.name,this.item);
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
	this.当前情报物品图标.itemIcon = new ItemIcon(this.当前情报物品图标,null,null);
	this.当前情报物品图标.itemIcon.RollOver = null;
	this.当前情报物品图标.itemIcon.RollOut = null;
	this.btn1._visible = false;
	this.btn2._visible = false;
}

_root.物品UI函数.显示情报信息 = function(name,value){
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
	this.hinttext.text = "";
	this.pagetext.text = String(this.当前信息序号 + 1) + " / " + this.已发现数量;
	var txt = this.情报信息表[this.当前信息序号].Text;
	var 加密等级 = this.情报信息表[this.当前信息序号].EncryptLevel;
	if(加密等级 > 0){
		txt = _root.加密html剧情文本(txt, this.EncryptReplace, this.EncryptCut);
		this.hinttext.text = "信息未完全解明。需要解密技能达到 " + 加密等级 + " 级";
	}
	txt = _root.处理html剧情文本(txt);
	this.infotext.htmlText = txt;
}
