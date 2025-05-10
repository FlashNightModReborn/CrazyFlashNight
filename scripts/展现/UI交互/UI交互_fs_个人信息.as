_root.人物信息函数 = new Object();

_root.人物信息函数.获得韧性负荷 = function(自机){
	var 自机 = _root.gameworld[_root.控制目标];
	var 韧性上限 = 自机.韧性系数 * 自机.hp / _root.防御减伤比(自机.防御力 / 1000);
	return Math.floor(韧性上限 / 自机.躲闪率) + " / " + Math.floor(韧性上限);
};

_root.人物信息函数.获得综合防御力 = function(自机){
	var 自机 = _root.gameworld[_root.控制目标];
	var buff数值 = Math.floor(自机.防御力 - 自机.基本防御力 - 自机.装备防御力);
	var buff字符 = buff数值 > 1 ? " + " + buff数值 : ( buff数值 < -1? buff数值: "" );
	return 自机.基本防御力 + " + " + 自机.装备防御力 + buff字符;
};

_root.人物信息函数.获得最大HP = function(自机){
	return 自机.hp满血值;
};

_root.人物信息函数.获得最大MP = function(自机){
	return 自机.mp满血值;
};

_root.人物信息函数.获得空手攻击力 = function(自机){
	return 自机.空手攻击力;
};

_root.人物信息函数.获得内力 = function(自机){
	return 自机.内力;
};


_root.人物信息函数.获得命中力 = function(自机){
	return Math.floor(自机.命中率 * 10);
};

_root.人物信息函数.获得速度 = function(自机){
	return Math.floor(自机.行走X速度 * 20) / 10 + "m/s";
};

_root.人物信息函数.获得被击硬直度 = function(自机){
	return Math.floor(自机.被击硬直度) + "ms";
};

_root.人物信息函数.获得拆挡_坚稳 = function(自机){
	return Math.floor(50 / 自机.躲闪率) + " / " + Math.floor(100 * 自机.韧性系数);
};

_root.人物信息函数.获得身高 = function(自机){
	return _root.身高 + "cm";
};
_root.人物信息函数.获得称号 = function(自机){
	return 自机.称号;
};

_root.人物信息函数.获得装备重量 = function(自机){
	return 自机.重量 + "kg";
};

_root.人物信息函数.获得经验值 = function(){
	// return (String(_root.经验值) + " / " + String(_root.升级所需经验值));
	return (String(_root.经验值));
}

_root.人物信息函数.显示负重情况 = function(目标:MovieClip,自机:MovieClip){
	var 基准负重 = _root.主角函数.获取基准负重(自机._root.等级);
	目标.轻甲_中甲重量 = 基准负重 + "kg";
	目标.中甲_重甲重量 = 基准负重 * 2 + "kg";
	目标.重甲重量 = 基准负重 * 4 + "kg";
	var 重量比值 = 自机.重量 / 基准负重 / 4;
	if(重量比值 < 0) 重量比值 = 0;
	if(重量比值 > 1) 重量比值 = 1;
	目标.负重滑块._x = 20 + 重量比值 * 240;
}

_root.人物信息函数.获取人物信息 = function(目标:MovieClip){
	var 自机 = _root.gameworld[_root.控制目标];
	目标.等级 = _root.等级;
	目标.身高 = _root.人物信息函数.获得身高();
	目标.称号 = _root.人物信息函数.获得称号(自机);
	目标.经验值 = _root.人物信息函数.获得经验值();
	//
	目标.装备重量 = _root.人物信息函数.获得装备重量(自机);
	_root.人物信息函数.显示负重情况(目标,自机);
	//
	目标.韧性负荷 = _root.人物信息函数.获得韧性负荷(自机);
	目标.综合防御力 = _root.人物信息函数.获得综合防御力(自机);
	目标.最大HP = _root.人物信息函数.获得最大HP(自机);
	目标.最大MP = _root.人物信息函数.获得最大MP(自机);
	目标.空手攻击力 = _root.人物信息函数.获得空手攻击力(自机);
	目标.内力 = _root.人物信息函数.获得内力(自机);
	目标.命中力 = _root.人物信息函数.获得命中力(自机);
	目标.速度 = _root.人物信息函数.获得速度(自机);
	目标.被击硬直度 = _root.人物信息函数.获得被击硬直度(自机);
	目标.拆挡_坚稳 = _root.人物信息函数.获得拆挡_坚稳(自机);
}

// 速度 = Math.floor(自机.行走X速度 * 20) / 10 + "m/s";
// 被击硬直度 = Math.floor(自机.被击硬直度) + "ms";
// 拆挡_坚稳 = Math.floor(50 / 自机.躲闪率) + "/" + Math.floor(100 * 自机.韧性系数);
// 身高 = _root.身高 + "cm";
// 称号 = 自机.称号;
// 装备重量 = 自机.重量 + "kg";