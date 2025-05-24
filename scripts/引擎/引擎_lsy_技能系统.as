_root.根据技能名查找主角技能等级 = function(技能名){
	var 主角技能表 = _root.主角技能表;
	for(var i = 0; i < 主角技能表.length; i++){
		if (主角技能表[i][0] == 技能名){
			return 主角技能表[i][1];
		}
	}
	return 0;
};

_root.学习技能 = function(技能名, 等级){
	var 主角技能表 = _root.主角技能表;
	var 技能信息 = _root.技能表对象[技能名];
	var 已获得该技能 = false;
	for(var i = 0; i < 主角技能表.length; i++){
		var 技能 = 主角技能表[i];
		if (技能[0] == 技能名){
			已获得该技能 = true;
			if (技能[1] < 等级){
				技能[1] = 等级;
				_root.排列技能图标();
				_root.发布消息(_root.获得翻译(技能名) + "，" + _root.获得翻译("技能升级成功！"));
				if(技能信息.Passive){
					_root.更新主角被动技能();
				}
				return true;
			}
		}
	}
	for(var i = 0; i < 主角技能表.length; i++){
		var 技能 = 主角技能表[i];
		if (技能[0] == "" && !已获得该技能){
			技能[0] = 技能名;
			技能[1] = 等级;
			技能[2] = false;
			技能[3] = 技能信息.Type;
			技能[4] = false;
			//被动技能学习时默认开启
			if(!技能信息.Equippable){
				技能[2] = true;
				技能[4] = true;
			}
			_root.排列技能图标();
			_root.发布消息(_root.获得翻译(技能名) + "，" + _root.获得翻译("新技能获得！"));
			if(技能信息.Passive){
				_root.更新主角被动技能();
			}
			return true;
		}
	}
	_root.发布消息(_root.获得翻译("技能槽已满！"));
	return false;
}

_root.更新主角被动技能 = function(){
	_root.主角被动技能 = {};
	for(var i = 0; i < _root.主角技能表.length; i++){
		var 技能 = _root.主角技能表[i];
		if(技能[0] != ""){
			if(_root.技能表对象[技能[0]].Passive){
				_root.主角被动技能[技能[0]] = {技能名:技能[0], 等级:技能[1], 启用:技能[4]};
			}
		}
	}
	_root.gameworld[_root.控制目标].被动技能 = _root.主角被动技能;
	_root.gameworld[_root.控制目标].读取被动效果();
}

_root.排列技能图标 = function(){
	var 物品栏界面 = _root.物品栏界面;
	_root.玩家信息界面.刷新技能等级显示();
	if (_root.物品栏界面.界面 == "技能"){
		var 图标x = 物品栏界面.技能图标._x;
		var 图标y = 物品栏界面.技能图标._y;
		var 图标高度 = 28;
		var 图标宽度 = 28;
		var 列数 = 8;
		var 行数 = 10;
		var 换行计数 = 0;
		
		for(var i = 0; i < 列数 * 行数; i++){
			var 技能信息 = 主角技能表[i];

			物品栏界面["技能图标" + i].removeMovieClip();
			var 当前技能图标 = 物品栏界面.attachMovie("技能图标","技能图标" + i,物品栏界面.getNextHighestDepth(),{数量:技能信息[1]});

			当前技能图标._x = 图标x;
			当前技能图标._y = 图标y;
			图标x += 图标宽度;
			换行计数++;
			if (换行计数 == 列数){
				换行计数 = 0;
				图标x = 物品栏界面.技能图标._x;
				图标y += 图标高度;
			}

			当前技能图标.数量 = 技能信息[1];
			当前技能图标.对应数组号 = i;
			当前技能图标.图标是否可对换位置 = 1;

			if (技能信息[0] && 技能信息[0] != ""){
				当前技能图标.图标 = "图标-" + 技能信息[0];
				当前技能图标.gotoAndStop("默认图标");
			}
		}
	}
	_root.gameworld[_root.控制目标].读取被动效果();
}

_root.删除技能图标 = function(){
	for(var i = 0; i < 80; i ++) _root.物品栏界面["技能图标" + i].removeMovieClip();
}

_root.根据技能名查找全部属性 = function(技能名){
	return _root.技能表对象[技能名];
}


_root.主角是否已学 = function(技能名){
	var 主角技能表 = _root.主角技能表;
	for (var i = 0; i < 主角技能表.length; i++){
		if (主角技能表[i][0] == 技能名) return 主角技能表[i][1];
	}
	return false;
}


_root.主角技能表总数 = 80;

_root.初始化主角技能表 = function(){
	if(_root.主角技能表.length > 0) return;
	_root.主角技能表 = new Array(_root.主角技能表总数);
	for (var i = 0; i < _root.主角技能表总数; i++) _root.主角技能表[i] = ["", 0, false,"",true];
}
_root.初始化主角技能表();


_root.getNPCSkills = function(NPCName){
	return _root.NPC技能表[NPCName];
}
