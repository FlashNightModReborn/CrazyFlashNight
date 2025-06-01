import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

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
				var 控制对象 = TargetCacheManager.findHero();
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
