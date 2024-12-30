import org.flashNight.arki.item.itemIcon.*;

_root.物品图标UI函数 = new Object();
_root.物品图标UI函数.点击函数 = new Object();
_root.物品图标UI函数.释放函数 = new Object();

_root.物品图标UI函数.点击函数.物品栏界面 = function()
{
	_root.注释结束();
	if (是否装备 == undefined && _root.物品栏[this.对应数组号][2] == 0)
	{
		this.图标壳.图标.gotoAndStop(2);
		startDrag(this,1);

		_root.鼠标.gotoAndStop("手型抓取");
		if (_root.物品栏界面.getDepth() < _root.仓库界面.getDepth())
		{
			_root.物品栏界面.swapDepths(_root.仓库界面);
		}
		this.swapDepths(500 + random(100));
		this.点击xmouse = _root._xmouse;
		this.点击ymouse = _root._ymouse;
	}
}

_root.物品图标UI函数.点击函数.仓库界面 = function()
{
	_root.注释结束();
	this.图标壳.图标.gotoAndStop(2);
	startDrag(this,1);

	_root.鼠标.gotoAndStop("手型抓取");
	if (_root.物品栏界面.getDepth() > _root.仓库界面.getDepth())
	{
		_root.仓库界面.swapDepths(_root.物品栏界面);
	}
	this.swapDepths(500 + random(100));
}

_root.物品图标UI函数.释放函数.物品栏界面 = function()
{
	stopDrag();
	var 当前物品格 = _root.物品栏[this.对应数组号];
	// if(this.点击xmouse == _root._xmouse && this.点击ymouse == _root._ymouse){
	// 	var type = _root.getItemData(当前物品格[0]).type;
	// 	if (是否装备 && 当前物品格[2] == 1){
	// 		_root.物品栏卸载装备(type);
	// 	}else{
	// 		this.each = type;
	// 		装备槽对应物品类别(type,数量);
	// 	}
	// 	return;
	// }
	
	var flag = false;
	if (_root.装备强化界面._visible)
	{
		var 当前物品 = _root.物品栏[this.对应数组号];
		var 强化图标 = _root.装备强化界面.强化图标;
		var 强化图标左 = _root.装备强化界面.强化图标左;
		var 强化图标右 = _root.装备强化界面.强化图标右;
		if (强化图标.hitTest(_root._xmouse, _root._ymouse, true))
		{
			强化图标.图标 = this.图标;
			强化图标.对应数组号 = this.对应数组号;
			强化图标.临时物品名称 = 当前物品[0];
			强化图标.数量 = 当前物品[1];
			强化图标.gotoAndStop("刷新");
			_root.装备强化界面.是否可强化检测();
			flag = true;
		}
		if (强化图标左.hitTest(_root._xmouse, _root._ymouse, true))
		{
			强化图标左.图标 = this.图标;
			强化图标左.对应数组号 = this.对应数组号;
			强化图标左.临时物品名称 = 当前物品[0];
			强化图标左.数量 = 当前物品[1];
			强化图标左.gotoAndStop("刷新");
			_root.装备强化界面.是否可强化度转换检测();
			flag = true;
		}
		if (强化图标右.hitTest(_root._xmouse, _root._ymouse, true))
		{
			强化图标右.图标 = this.图标;
			强化图标右.对应数组号 = this.对应数组号;
			强化图标右.临时物品名称 = 当前物品[0];
			强化图标右.数量 = 当前物品[1];
			强化图标右.gotoAndStop("刷新");
			_root.装备强化界面.是否可强化度转换检测();
			flag = true;
		}
	}
	var 仓库界面 = _root.仓库界面;
	if (仓库界面._visible  && 仓库界面.hitTest(_root._xmouse, _root._ymouse, true))
	{
		for (eachs in 仓库界面)
		{
			if (仓库界面[eachs].area.hitTest(_root._xmouse, _root._ymouse, true))
			{
				var 目标物品格 = _root.仓库栏[仓库界面[eachs].对应数组号];
				if (tmp物品大类型 == "消耗品" && 当前物品格[0] === 目标物品格[0])
				{
					_root.合并物品格(当前物品格,目标物品格);
				}
				else
				{
					_root.交换物品格(当前物品格,目标物品格);
				}
				_root.排列仓库物品图标();
				flag = true;
				break;
			}
		}
	}
	if (!flag)
	{
		for (each in _root.物品栏界面)
		{
			var 目标元件 = _root.物品栏界面[each];
			if(!目标元件.area.hitTest(_root._xmouse, _root._ymouse, true)){
				continue;
			}
			if (目标元件.装备槽类别)
			{
				if(this === 目标元件){
					_root.物品栏卸载装备(目标元件.装备槽类别);
					return;
				}else{
					装备槽对应物品类别(目标元件.装备槽类别,数量);
				}
				break;
			}
			var 目标物品格 = _root.物品栏[目标元件.对应数组号];
			if (目标元件._name != this._name)
			{
				if (目标元件.图标是否可对换位置 == 1 && 目标物品格[2] != 1)
				{
					if (tmp物品大类型 == "消耗品" && 当前物品格[0] === 目标物品格[0])
					{
						_root.合并物品格(当前物品格,目标物品格);
					}
					else
					{
						_root.交换物品格(当前物品格,目标物品格);
					}
					break;
				}
			}
			if (目标元件._name === "垃圾箱")
			{
				_root.发布消息(_root.获得翻译("丢弃物品") + _root.获得翻译(当前物品格[0]));
				_root.清空物品格(当前物品格);
				break;
			}
			if (tmp_sz[3] === "药剂" && _root.玩家信息界面.快捷药剂界面.hitTest(_root._xmouse, _root._ymouse, true))
			{
				for (var i=1; i<=4; i++){
					var 当前快捷物品栏 = _root.玩家信息界面.快捷药剂界面["快捷物品栏" + i];
					if(当前快捷物品栏.hitTest(_root._xmouse, _root._ymouse, true)){
						当前快捷物品栏.对应数组号 = this.对应数组号;
						当前快捷物品栏.已装备名 = 当前物品格[0];
						当前快捷物品栏.是否装备 = 1;
						_root["快捷物品栏" + i] = 当前物品格[0];
						当前快捷物品栏.图标 = "图标-" + _root.getItemData(_root.快捷物品栏1).icon;
						当前快捷物品栏.gotoAndStop("默认图标");
						当前快捷物品栏.数量 = 当前物品格[1];
						当前物品格[2] = 1;
						_root.玩家信息界面.快捷药剂界面.gotoAndPlay("刷新");
						break;
					}
				}
			}
		}
		if (_root.购买物品界面._visible && _root.购买物品界面.hitTest(_root._xmouse, _root._ymouse, true) && _root.物品栏界面.hitTest(_root._xmouse, _root._ymouse, true) && !_root.物品栏界面.窗体area.hitTest(_root._xmouse, _root._ymouse, true))
		{
			if (!isNaN(tmp_sz[5]))
			{
				var 售卖倍率 = 0.25;
				if(_root.主角被动技能.口才 && _root.主角被动技能.口才.启用){
					售卖倍率 += _root.主角被动技能.口才.等级 * 0.025;
				}
				if(tmp物品大类型 == "武器" || tmp物品大类型 == "防具"){
					var 每石最大收益 = 当前物品格[1] * 200 + 600;
					// var 强化石个数 = 0;
					// for(var i = 0; i < 当前物品格[1]-1; i++){
					// 	强化石个数 += Math.floor(i * i * i + 1);
					// }
					var 强化石个数 = Math.pow((当前物品格[1]-2) * (当前物品格[1]-1)/2,2) + 当前物品格[1]-1;
					var 最大收益 = 强化石个数 * 每石最大收益;
					var 强化收益 = Math.min(最大收益,(售卖倍率 * tmp_sz[5] * (Math.pow((当前物品格[1] - 1),4.2) / 216 )))
					_root.金钱 += Math.floor(Number(售卖倍率 * tmp_sz[5] +  强化收益));
					//_root.金钱 += Math.floor(Number(tmp_sz[5] * 售卖倍率 * (1 + Math.pow((当前物品格[1] - 1),4.2) / 216 ) ));
				}else{
					_root.金钱 += Math.floor(Number(tmp_sz[5] * 售卖倍率 * 当前物品格[1]));
				}
			}
			_root.清空物品格(当前物品格);
			_root.播放音效("收银机.mp3");
		}
	}
	_root.排列物品图标();
	this.removeMovieClip();
}

_root.物品图标UI函数.释放函数.购买物品界面 = function()
{
	物品名 = _root.购买物品界面.物品栏[this.对应数组号][0];
	_root.购买物品界面.准备购买的物品 = 物品名;
	_root.购买物品界面.准备购买的物品单价 = tmp_sz[5];
	_root.购买物品界面.准备购买的物品等级限制 = tmp_sz[9];
	if (tmp_sz[2] == "消耗品")
	{
		_root.购买物品界面.gotoAndStop("购买数量");
	}
	else
	{
		_root.购买物品界面.gotoAndStop("结算");
	}
}

_root.物品图标UI函数.释放函数.快捷药剂界面 = function()
{
	if(_root.全鼠标控制){
		_parent[this.控制器].gotoAndStop("已扣扳机");
	}
}

_root.物品图标UI函数.释放函数.仓库界面 = function()
{
	stopDrag();
	var 当前物品格 = _root.仓库栏[this.对应数组号];
	for (each in _root.仓库界面)
	{
		var 目标元件 = _root.仓库界面[each];
		if(!目标元件.area.hitTest(_root._xmouse, _root._ymouse, true)){
			continue;
		}
		var 目标物品格 = _root.仓库栏[目标元件.对应数组号];
		// if (目标物品格._name === "垃圾箱")
		if (目标元件._name === "垃圾箱")
		{
			_root.发布消息(_root.获得翻译("丢弃物品") + _root.获得翻译(当前物品格[0]));
			_root.清空物品格(当前物品格);
			break;
		}
		if (目标元件._name != this._name)
		{
			if (目标元件.图标是否可对换位置 == 1 && 目标物品格[2] != 1)
			{
				if (tmp物品大类型 === "消耗品" && 当前物品格[0] === 目标物品格[0])
				{
					_root.合并物品格(当前物品格,目标物品格);
				}
				else
				{
					_root.交换物品格(当前物品格,目标物品格);
				}
				break;
			}
		}
	}
	for (eachs in _root.物品栏界面)
	{
		var 目标元件 = _root.物品栏界面[eachs];
		if (!目标元件.area.hitTest(_root._xmouse, _root._ymouse, true)){
			continue;
		}
		var 目标物品格 = _root.物品栏[目标元件.对应数组号];
		if(目标物品格[2] === 0){
			if (tmp物品大类型 == "消耗品" && 当前物品格[0] === 目标物品格[0])
			{
				_root.合并物品格(当前物品格,目标物品格);
			}
			else
			{
				_root.交换物品格(当前物品格,目标物品格);
			}
			_root.排列物品图标();
			break;
		}
	}//尝试仓库直接售卖 
	if (_root.购买物品界面._visible && _root.购买物品界面.hitTest(_root._xmouse, _root._ymouse, true) && _root.仓库界面.hitTest(_root._xmouse, _root._ymouse, true) && !_root.仓库界面.窗体area.hitTest(_root._xmouse, _root._ymouse, true))
	{
		if (!isNaN(tmp_sz[5]))
		{
			var 售卖倍率 = 0.25;
			if(_root.主角被动技能.口才 && _root.主角被动技能.口才.启用){
				售卖倍率 += _root.主角被动技能.口才.等级 * 0.025;
			}
			if(tmp物品大类型 == "武器" || tmp物品大类型 == "防具"){
				var 每石最大收益 = 当前物品格[1] * 200 + 600;
				// var 强化石个数 = 0;
				// for(var i = 1; i < 当前物品格[1]; i++){
				// 	强化石个数 += Math.floor((i - 1) * (i - 1) * (i - 1) + 1);
				// }
				var 强化石个数 = Math.pow((当前物品格[1]-2) * (当前物品格[1]-1)/2,2) + 当前物品格[1]-1;
				var 最大收益 = 强化石个数 * 每石最大收益;
				var 强化收益 = Math.min(最大收益,(售卖倍率 * tmp_sz[5] * (Math.pow((当前物品格[1] - 1),4.2) / 216 )))
				_root.金钱 += Math.floor(Number(售卖倍率 * tmp_sz[5] +  强化收益));
				//_root.金钱 += Math.floor(Number(tmp_sz[5] * 售卖倍率 * (1 + Math.pow((当前物品格[1] - 1),4.2) / 216 ) ));
			}else{
				_root.金钱 += Math.floor(Number(tmp_sz[5] * 售卖倍率 * 当前物品格[1]));
			}
		}
		_root.清空物品格(当前物品格);
		_root.播放音效("收银机.mp3");
	}
	_root.排列仓库物品图标();
	this.removeMovieClip();
}



//
_root.物品图标UI函数.装备槽对应物品类别 = function(类别, 强化等级)
{
	if (_parent._name != "物品栏界面"){
		return;
	}
	var 目标元件 = _root.物品栏界面[each];
	var 当前物品格 = _root.物品栏[this.对应数组号];
	if (目标元件.装备槽类别 === 类别)
	{
		if (_root.根据物品名查找属性(当前物品格[0], 9) > _root.等级)
		{
			_root.发布消息("等级低于装备限制，无法装备！");
			return;
		}
		temp类别 = _root.根据物品名查找属性(当前物品格[0], 3);
		if (temp类别 == 类别)
		{
			if (目标元件.是否装备 == 0)
			{
				目标元件.是否装备 = 1;
				当前物品格[2] = 1;
			}
			else if (目标元件.是否装备 == 1)
			{
				_root.物品栏[目标元件.对应数组号][2] = 0;
				当前物品格[2] = 1;
			}
			_root[目标元件.对应装备] = 当前物品格[0];
			对应装备 = 目标元件.对应装备;
			_root[目标元件.数量] = 当前物品格[1];
			目标元件.对应数组号 = this.对应数组号;
			目标元件.数量 = 强化等级;
			目标元件.mytext2 = 强化等级;
			if (当前物品格[0] == "空")
			{
				目标元件.gotoAndStop(当前物品格[0]);
			}
			else
			{
				目标元件.图标 = "图标-" + _root.getItemData(当前物品格[0]).icon;
				目标元件.gotoAndStop("默认图标");
			}
			_root.发布消息(_root.获得翻译("成功装备") + "[" + _root.获得翻译(类别) + "][" + _root.获得翻译(_root.getItemData(当前物品格[0]).displayname) + "]");
			if (类别 == "长枪")
			{
				_root.长枪强化等级 = 当前物品格[1];
				_root.长枪配置(_root.控制目标,当前物品格[0],当前物品格[1]);
				_root.播放音效("9mmclip2.wav");
				_root.client.sendData(DataPackage.换装备(类别, 当前物品格[0]));
			}
			else if (类别 == "手枪")
			{
				_root.播放音效("9mmclip2.wav");
				if (对应装备 == "手枪")
				{
					_root.手枪强化等级 = 当前物品格[1];
					_root.手枪配置(_root.控制目标,当前物品格[0],当前物品格[1]);
					_root.client.sendData(DataPackage.换装备("手枪", 当前物品格[0]));
				}
				else if (对应装备 == "手枪2")
				{
					_root.手枪2强化等级 = 当前物品格[1];
					_root.手枪2配置(_root.控制目标,当前物品格[0],当前物品格[1]);
					_root.client.sendData(DataPackage.换装备("手枪2", 当前物品格[0]));
				}
			}
			else if (类别 == "手雷")
			{
				_root.手雷配置(_root.控制目标,当前物品格[0]);
				_root.播放音效("9mmclip2.wav");
				_root.client.sendData(DataPackage.换装备(类别, 当前物品格[0]));
			}
			else if (类别 == "刀")
			{
				_root.刀强化等级 = 当前物品格[1];
				_root.刀配置(_root.控制目标,当前物品格[0],当前物品格[1]);
				_root.播放音效("9mmclip2.wav");
				_root.client.sendData(DataPackage.换装备(类别, 当前物品格[0]));
			}
			else if (类别 == "颈部装备")
			{
				var 控制对象 = _root.gameworld[_root.控制目标];
				控制对象.称号 = _root.根据物品名查找属性(当前物品格[0], 14);
				控制对象.称号 = 控制对象.称号[0];
				_root.玩家称号 = 控制对象.称号;
				_root.播放音效("9mmclip2.wav");
				_root.client.sendData(DataPackage.换装备(类别, 当前物品格[0]));
			}
			else
			{
				_root.播放音效("ammopickup1.wav");
				_root.client.sendData(DataPackage.换装备(类别, 当前物品格[0]));
			}
			_root.刷新人物装扮(_root.控制目标);
		}
	}
}






//新版物品栏
_root.物品UI函数 = new Object();

_root.物品UI函数.背包 = new Object();
_root.物品UI函数.装备栏 = new Object();
_root.物品UI函数.药剂栏 = new Object();

//UI层面的移动操作

_root.物品UI函数.出售物品 = function(name,value){
	var itemData = _root.getItemData(name);
	var price = itemData.price;
	if (isNaN(price)) return;
	var 售卖倍率 = 0.25;
	var type = itemData.type;
	if(_root.主角被动技能.口才 && _root.主角被动技能.口才.启用){
		售卖倍率 += _root.主角被动技能.口才.等级 * 0.025;
	}
	if(type == "武器" || type == "防具"){
		var 强化等级 = value.level;
		if(isNaN(强化等级)) 强化等级 = 1;
		var 每石最大收益 = 强化等级 * 200 + 600;
		var 强化石个数 = Math.pow((强化等级-2) * (强化等级-1)/2,2) + 强化等级-1;
		var 最大收益 = 强化石个数 * 每石最大收益;
		var 强化收益 = Math.min(最大收益,(售卖倍率 * price * (Math.pow((强化等级 - 1),4.2) / 216 )))
		_root.金钱 += Math.floor(Number(售卖倍率 * price + 强化收益));
	}else{
		_root.金钱 += Math.floor(Number(price * 售卖倍率 * value));
	}
	_root.播放音效("收银机.mp3");
}


//排列背包图标
_root.物品UI函数.创建背包图标 = function(){
	if(_root.物品栏界面.界面 != "物品栏") return;

	var 物品栏界面 = _root.物品栏界面;
	var 背包 = _root.物品栏.背包;
	
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
	_root.物品栏.背包.clearIcon();
	_root.物品栏.装备栏.clearIcon();
}


//初始化药剂栏图标
_root.物品UI函数.初始化药剂栏图标 = function(){
	var 快捷药剂界面 = _root.玩家信息界面.快捷药剂界面;
	if(快捷药剂界面.药剂图标列表.length == 4) return;
	
	var list = [快捷药剂界面.位置示意0,快捷药剂界面.位置示意1,快捷药剂界面.位置示意2,快捷药剂界面.位置示意3];
	快捷药剂界面.药剂图标列表 = [];
	var 控制器列表 = [快捷药剂界面.控制器0,快捷药剂界面.控制器1,快捷药剂界面.控制器2,快捷药剂界面.控制器3];
	var 进度条列表 = [快捷药剂界面.进度条0,快捷药剂界面.进度条1,快捷药剂界面.进度条2,快捷药剂界面.进度条3];

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
			if (this.itemData.type != "武器" && this.itemData.type != "防具"){
				_root.购买物品界面.gotoAndStop("购买数量");
			}else{
				_root.购买物品界面.gotoAndStop("结算");
			}
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
	_root.发布消息("frame "+_root.购买物品界面._currentframe);
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

	仓库界面.inventory = inventory;
	仓库界面.page = page;
	仓库界面.maxpage = maxpage;
	仓库界面.仓库页数显示 = String(page + 1)+" / "+String(maxpage);

	if(!仓库界面.图标列表) {
		_root.物品UI函数.创建仓库图标(inventory,page);
		return;
	}
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
	仓库界面.inventory.clearIcon();
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
	return 页数;
}


//收集品栏相关（临时）
_root.物品UI函数.创建收集品图标 = function(){
	if(_root.物品栏界面.界面 != "收集品栏") return;

	var 物品栏界面 = _root.物品栏界面;
	var 材料 = _root.收集品栏.材料;
	var 情报 = _root.收集品栏.情报;
	
	var 起始x = 物品栏界面.收集品图标._x;
	var 起始y = 物品栏界面.收集品图标._y;
	var 图标高度 = 28;
	var 图标宽度 = 28;
	var 列数 = 10;
	var 行数 = 8;
	var 总格数 = 行数*列数;
	var 换行计数 = 0;

	var 层级错位 = 50;

	物品栏界面.收集品图标列表 = new Array(总格数);

	var 材料列表 = [];
	for(var key in 材料.getItems()){
		材料列表.push(key);
	}
	var 情报列表 = [];
	for(var key in 情报.getItems()){
		情报列表.push(key);
	}
	
	for (var i = 0; i < 40; i++){
		var 物品图标 = 物品栏界面.attachMovie("物品图标","物品图标" + i,i + 层级错位);
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
		物品栏界面.收集品图标列表[i] = 物品图标;
		物品图标.itemIcon = new CollectionIcon(物品图标,材料,材料列表[i]);
	}
	var 起始x = 物品栏界面.收集品图标._x;
	var 换行计数 = 0;
	for (var i = 40; i < 80; i++){
		var 物品图标 = 物品栏界面.attachMovie("物品图标","物品图标" + i,i + 层级错位);
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
		物品栏界面.收集品图标列表[i] = 物品图标;
		物品图标.itemIcon = new CollectionIcon(物品图标,情报,情报列表[i - 40]);
	}
}

_root.物品UI函数.删除收集品图标 = function(){
	var 收集品图标列表 = _root.物品栏界面.收集品图标列表;
	for(var i=0; i<收集品图标列表.length; i++){
		收集品图标列表[i].removeMovieClip();
	}
	_root.物品栏界面.收集品图标列表 = null;
	_root.收集品栏.材料.clearIcon();
}