_root.技能函数 = new Object();
import org.flashNight.arki.spatial.move.*;

//释放条件函数
_root.技能函数.释放条件 = new Object();

//默认释放条件是不处于倒地状态
_root.技能函数.释放条件.默认 = function(){
	return !this.倒地 ? true : false;
}
//小跳、闪现与震地类技能无任何释放条件
var 无条件 = function(){
	return true;
}
_root.技能函数.释放条件.小跳 = 无条件;
_root.技能函数.释放条件.闪现 = 无条件;
_root.技能函数.释放条件.震地 = 无条件;
_root.技能函数.释放条件.地震 = 无条件;
_root.技能函数.释放条件.觉醒震地 = 无条件;



//释放行为函数
_root.技能函数.释放行为 = new Object();

//传入技能名和技能等级两个参数
//默认释放行为，进入技能动画并跳转到对应标签帧
_root.技能函数.释放行为.默认 = function(技能名, 技能等级){
	this.技能名 = 技能名;
	this.技能等级 = 技能等级;
	this.状态改变("技能");
	this.man.gotoAndPlay(技能名);
}
//buff系统实装后，部分技能可以通过更改释放行为函数，不进技能动画释放




//主角技能的移动相关函数
_root.技能函数.攻击时移动 = function(慢速度, 快速度){
	var parent:MovieClip = _parent;

	if(parent._name != _root.控制目标 || isNaN(快速度)){
		Mover.move2D(parent, parent.方向, 慢速度);
		return;
	}

	var func:Function = 快速度 > 100 ? Mover.move2D : Mover.move2DStrict;
	if (parent.右行) func(parent, "右", 快速度);
	else if (parent.左行) func(parent, "左", 快速度);
	else Mover.move2D(parent, parent.方向, 慢速度);
	//忘了给哪里用的硬代码
	if (快速度 == 6){
		if (parent.上行) Mover.move2D(parent, "上", 1);
		else if (parent.下行) Mover.move2D(parent, "下", 1);
	}
}
//
_root.技能函数.攻击时按键四向移动 = function(慢速度, 快速度){
	var parent:MovieClip = _parent;

	if(parent._name != _root.控制目标){
		Mover.move2D(parent, parent.方向, 慢速度);
		return;
	}
	var 上下未按键 = false;
	var 左右未按键 = false;
	//检测上下是否按键
	if (parent.上行) Mover.move2D(parent, "上", 快速度 / 2);
	else if (parent.下行) Mover.move2D(parent, "下", 快速度 / 2);
	else 上下未按键 = true;
	//检测左右是否按键
	if (parent.左行) Mover.move2D(parent, "左", 快速度);
	else if (parent.右行) Mover.move2D(parent, "右", 快速度);
	else 左右未按键 = true;
	if (上下未按键 && 左右未按键){
		Mover.move2D(parent, parent.方向, 慢速度);
	}
}

_root.技能函数.攻击时可改变移动方向 = function(速度){
	var parent:MovieClip = _parent;

	if(parent._name != _root.控制目标){
		Mover.move2D(parent, parent.方向, 速度);
		return;
	}
	//根据按键改变方向后执行移动
	if (parent.右行) parent.方向改变("右");
	else if (parent.左行) parent.方向改变("左");
	Mover.move2D(parent, parent.方向, 速度);
}

_root.技能函数.攻击时可斜向改变移动方向 = function(速度){
	var parent:MovieClip = _parent;

	if(parent._name != _root.控制目标){
		Mover.move2D(parent, parent.方向, 速度);
		return;
	}
	//根据按键改变方向后执行移动
	if (parent.右行) parent.方向改变("右");
	else if (parent.左行) parent.方向改变("左");
	Mover.move2D(parent, parent.方向, 速度);
	if (parent.上行) Mover.move2D(parent, "上", 速度 / 2);
	else if (parent.下行) Mover.move2D(parent, "下", 速度 / 2);
}

_root.技能函数.攻击时斜向移动 = function(慢速度, 快速度){
	var parent:MovieClip = _parent;

	if(parent._name != _root.控制目标){
		Mover.move2D(parent, parent.方向, 慢速度);
		return;
	}
	if (parent.方向 == "右"){
		if (parent.右行) Mover.move2D(parent, "右", 快速度);
		else Mover.move2D(parent, "右", 慢速度);
	}else if (parent.方向 == "左"){
		if (parent.左行) Mover.move2D(parent, "左", 快速度);
		else Mover.move2D(parent, "左", 慢速度);
	}
	if (parent.上行) Mover.move2D(parent, "上", 快速度);
	else if (parent.下行) Mover.move2D(parent, "下", 快速度);;
}

_root.技能函数.攻击时可斜向改变移动方向2 = function(速度, 上下){
	var parent:MovieClip = _parent;

	if(_parent._name != _root.控制目标){
		Mover.move2D(parent, parent.方向, 速度);
		return;
	}
	//根据按键改变方向后执行水平移动，但水平移动的距离为速度/2
	if (_parent.右行) _parent.方向改变("右");
	else if (_parent.左行) _parent.方向改变("左");
	Mover.move2D(parent, parent.方向, 速度 / 2);
	//根据上下的正负性决定移动方向
	if (上下 > 0){
		Mover.move2D(parent, "上", 速度);
	}else if (上下 < 0){
		Mover.move2D(parent, "下", 速度);
	}
}

_root.技能函数.获取移动方向 = function(){
	if(_parent._name != _root.控制目标){
		return _parent.方向;
	}
	if(_parent.左行){
		return "左";
	}else if(_parent.右行){
		return "右";
	}else{
		return "无";
	}
}





//技能具体执行内容与伤害函数

_root.技能函数.寸拳攻击 = function(联弹霰弹值){
	子弹属性 = _root.子弹属性初始化(this.攻击点);
	
	子弹属性.声音 = "";
	子弹属性.霰弹值 = 联弹霰弹值 > 1 ? Number(联弹霰弹值) : 1;
	子弹属性.子弹散射度 = 0;
	子弹属性.子弹种类 = "近战联弹";
	子弹属性.子弹威力 =  (_parent.空手攻击力 + 0.2 * _parent.内力) * (2 + _parent.技能等级);
	if(_parent.mp攻击加成){
		子弹属性.子弹威力 += _parent.mp攻击加成;
	}
	子弹属性.子弹速度 = 0;
	子弹属性.Z轴攻击范围 = 30;
	子弹属性.击倒率 = 0.01;
	
	子弹属性.区域定位area = this.攻击点;

	_root.子弹区域shoot传递(子弹属性);
}

_root.技能函数.震地攻击 = function(Z轴攻击范围)
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.子弹种类 = "近战子弹";
	子弹.子弹威力 = _parent.空手攻击力 * 0.2 + _parent.内力 * 1.2 * (5.5 + _parent.技能等级);
	子弹属性.子弹威力 += _parent.空手攻击力 * 0.3 * Math.min((_parent.重量 + _parent.身高 - 105)/100 , 2);
	if(_parent.hp攻击加成){
		子弹.子弹威力 += _parent.hp攻击加成 * 0.5;
	}
	if(_parent.mp攻击加成){
		子弹.子弹威力 += _parent.mp攻击加成;
	}
	子弹.子弹速度 = 0;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = Z轴攻击范围;
	子弹.击倒率 = 0.01;
	子弹.击中后子弹的效果 = "空手攻击火花";
	子弹.水平击退速度 = 15;
	子弹.区域定位area = this.攻击点;

	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.组合拳攻击 = function(技能等级乘数)
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.子弹种类 = "近战子弹";
	子弹.子弹威力 = _parent.内力 + _parent.空手攻击力 * (1 + _parent.技能等级 * 技能等级乘数);
	子弹.子弹速度 = 0;
	子弹.Z轴攻击范围 = 30;
	子弹.击倒率 = 10 / _parent.技能等级;
	子弹.不硬直 = true;
	
	子弹.区域定位area = this.攻击点;
	
	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.组合拳重击 = function()
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.发射效果 = "";
	子弹.子弹种类 = "近战子弹";
	子弹.子弹威力 = 5 * _parent.内力 + 3 * (_parent.空手攻击力 + 300) * (3 + _parent.技能等级);
	子弹.子弹速度 = 0;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = 30;
	子弹.击倒率 = 0.01;
	子弹.击中后子弹的效果 = "空手攻击火花";
	子弹.水平击退速度 = 15;
	
	子弹.区域定位area = this.攻击点;
	
	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.日字冲拳攻击 = function(技能等级乘数)
{
	子弹属性 = _root.子弹属性初始化(this.攻击点);

	子弹属性.声音 = "";
	子弹属性.霰弹值 = 1;
	子弹属性.子弹散射度 = 0;
	子弹属性.子弹种类 = "近战子弹";
	子弹属性.子弹威力 = ( _parent.空手攻击力 * 0.7 + _parent.内力 * 0.5) * (1 + _parent.技能等级 * 技能等级乘数);
	子弹属性.子弹速度 = 0;
	子弹属性.Z轴攻击范围 = 30;
	子弹属性.击倒率 = 5;
	子弹属性.伤害类型 = "魔法";
	子弹属性.魔法伤害属性 = "冲";
	
	子弹属性.区域定位area = this.攻击点;

	_root.子弹区域shoot传递(子弹属性);
}

_root.技能函数.日字冲拳重击 = function()
{
	//其实比起前几段只有击倒率改成了1
	子弹属性 = _root.子弹属性初始化(this.攻击点);
	
	子弹属性.声音 = "";
	子弹属性.霰弹值 = 1;
	子弹属性.子弹散射度 = 0;
	子弹属性.子弹种类 = "近战子弹";
	子弹属性.子弹威力 = ( _parent.空手攻击力 * 0.7 + _parent.内力 * 0.6) * (1 + _parent.技能等级 * 1.2);
	子弹属性.子弹速度 = 0;
	子弹属性.Z轴攻击范围 = 30;
	子弹属性.击倒率 = 1;
	子弹属性.伤害类型 = "魔法";
	子弹属性.魔法伤害属性 = "冲";
	
	子弹属性.区域定位area = this.攻击点;

	_root.子弹区域shoot传递(子弹属性);
}

_root.技能函数.踩人中心攻击 = function(){
	子弹属性 = _root.子弹属性初始化(this.攻击点);

	子弹属性.声音 = "";
	子弹属性.霰弹值 = 1;
	子弹属性.子弹散射度 = 0;
	子弹属性.发射效果 = "";
	子弹属性.子弹种类 = "近战子弹";
	var _temp = 0.5;
	var 成长值 = 700;
	if (_parent.浮空 && _parent.垂直速度 > _parent.起跳速度 + 1)
	{
		_temp = 1;
		成长值 = 1000 + 5 * _parent.内力;
		if (_parent.垂直速度 > -_parent.起跳速度)
		{
			_temp = 2;
		}
	}
	if(_parent.技能等级 <= 1) _parent.技能等级 = 1;
	子弹属性.子弹威力 = (_parent.空手攻击力 + 成长值) * (_parent.技能等级 * 2 - 1);
	if (_parent.mp攻击加成)
	{
		子弹属性.子弹威力 += _parent.mp攻击加成;
	}
	子弹属性.子弹威力 *= _temp;
	子弹属性.子弹威力 += _parent.空手攻击力 * Math.min((_parent.重量 + _parent.身高 - 105)/100 , 2);
	子弹属性.子弹速度 = 0;
	子弹属性.击中地图效果 = "";
	子弹属性.Z轴攻击范围 = 30;
	子弹属性.击倒率 = 20;
	子弹属性.暴击 = function(当前子弹){
		if (当前子弹.发射者名 == "玩家0" && _root.gameworld[当前子弹.发射者名].getSmallState() == "踩人中" && (当前子弹.命中对象.状态 == "击倒" || 当前子弹.命中对象.状态 == "倒地"))
		{
			//当前子弹.命中对象.损伤值 *= 1.5;
			return 1.5;
		}
		return 1;
	};
	_root.子弹区域shoot传递(子弹属性);
}

_root.技能函数.踩人攻击 = function(){
	子弹属性 = _root.子弹属性初始化(this.攻击点);
	
	子弹属性.声音 = "";
	子弹属性.霰弹值 = 1;
	子弹属性.子弹散射度 = 0;
	子弹属性.子弹种类 = "近战子弹";
	子弹属性.子弹威力 =  _parent.空手攻击力 * (1 + _parent.技能等级);
	子弹属性.子弹威力 += _parent.空手攻击力 * 0.5 * Math.min((_parent.重量 + _parent.身高 - 105)/100 , 2);
	子弹属性.子弹速度 = 0;
	子弹属性.Z轴攻击范围 = 30;
	子弹属性.击倒率 = 10;

	子弹属性.区域定位area = this.攻击点;

	_root.子弹区域shoot传递(子弹属性);
}

_root.技能函数.气动波攻击 = function()
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.发射效果 = "";
	子弹.子弹种类 = "气功弹";
	子弹.子弹威力 = _parent.空手攻击力 * 0.3 + 3 * _parent.内力 + 6.3 * _parent.内力 * _parent.技能等级;
	if (_parent.hp攻击加成)
	{
		子弹.子弹威力 += _parent.hp攻击加成;
	}
	if (_parent.mp攻击加成)
	{
		子弹.子弹威力 += _parent.mp攻击加成;
	}
	子弹.子弹速度 = 15;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = 30;
	子弹.击倒率 = 0.01;
	子弹.击中后子弹的效果 = "";
	子弹.水平击退速度 = 12;
	if(_parent.技能等级 == 10){
		子弹.爆炸冲伤 = true;
	}
	if (_parent.上行){
		子弹.角度偏移 = -30;
	}else if (_parent.下行){
		子弹.角度偏移 = 30;
	}
	
	_root.子弹区域shoot传递(子弹);
}


_root.技能函数.凶斩伤害乘数表 = {
	砍刀:3,
	单刀:3,
	大剑:2.5,
	金蛇剑:2.5,
	棒球棍:3,
	双面斧:3,
	单刃斧头:3,
	拆迁铁锤:3,
	中国战刀:3,
	西洋重剑:3.5,
	斩马刀:3.5,
	烈焰斩马刀:3,
	雷神之锤:2,
	光斧金牛:2,
	光刀狮子:2,
	血色光剑天秤:2,
	电子音乐键盘:2,
	红色电子吉他:2,
	桔色电子吉他:2
};

_root.技能函数.凶斩攻击 = function(不硬直)
{
	var 子弹参数 = new Object();
	var temp = 1;
	if(_root.技能函数.凶斩伤害乘数表[_parent.刀] > 1) temp = _root.技能函数.凶斩伤害乘数表[_parent.刀];
	
	子弹参数.子弹威力 = _parent.空手攻击力 * 0.1 + 1.5 * _parent.内力 * (5 + _parent.技能等级) + _parent.刀属性数组[13] * temp * 0.125 * (10 + _parent.技能等级);
	if (_parent.mp攻击加成)
	{
		子弹参数.子弹威力 += _parent.mp攻击加成;
	}
	子弹参数.Z轴攻击范围 = 30;
	子弹参数.击倒率 = 10;
	子弹参数.不硬直 = 不硬直;

	if(_parent.兵器伤害类型){
		子弹参数.伤害类型 = _parent.兵器伤害类型;
	}
	if(_parent.兵器魔法伤害属性){
		子弹参数.魔法伤害属性 = _parent.兵器魔法伤害属性;
	}
	if(_parent.兵器毒){
		子弹参数.毒 = _parent.兵器毒;
	}
	if(_parent.兵器吸血){
		子弹参数.吸血 = _parent.兵器吸血;
	}
	if(_parent.兵器击溃){
		子弹参数.血量上限击溃 = _parent.兵器击溃;
	}
	
	_parent.刀口位置生成子弹(子弹参数);
}

_root.技能函数.瞬步斩伤害乘数表 = {
	匕首:3.5,
	大剑:2.5,
	短棒:3,
	水管:3,
	棒球棒:1.5,
	破旧军刀:3,
	光刃摩羯:2,
	光剑天秤:2,
	战术狗腿刀:2,
	金蛇剑:2,
	// 秋月:3,
	虎彻:3,
	镜之虎彻:3,
	饮血野太刀:2
};

_root.技能函数.瞬步斩攻击 = function()
{
	var 子弹参数 = new Object();
	var temp = 1;
	if(_root.技能函数.瞬步斩伤害乘数表[_parent.刀] > 1) temp = _root.技能函数.瞬步斩伤害乘数表[_parent.刀];
	
	子弹参数.子弹威力 = _parent.空手攻击力 * 0.1 + 0.5 * _parent.内力 * (5 + _parent.技能等级) + _parent.刀属性数组[13] * temp * 0.1 * (10 + _parent.技能等级);
	if (_parent.mp攻击加成)
	{
		子弹参数.子弹威力 += _parent.mp攻击加成;
	}
	子弹参数.Z轴攻击范围 = 30;
	子弹参数.击倒率 = 10;
	子弹参数.不硬直 = true;

	if(_parent.兵器伤害类型){
		子弹参数.伤害类型 = _parent.兵器伤害类型;
	}
	if(_parent.兵器魔法伤害属性){
		子弹参数.魔法伤害属性 = _parent.兵器魔法伤害属性;
	}
	if(_parent.兵器毒){
		子弹参数.毒 = _parent.兵器毒;
	}
	if(_parent.兵器吸血){
		子弹参数.吸血 = _parent.兵器吸血;
	}
	if(_parent.兵器击溃){
		子弹参数.血量上限击溃 = _parent.兵器击溃;
	}

	_parent.刀口位置生成子弹(子弹参数);
}

_root.技能函数.龙斩刀伤乘数表 = {
	青萍元气剑:2,
	黑铁的剑:2,
	中国战刀:3,
	金蛇剑:2
};

_root.技能函数.龙斩气伤 = function(Z轴攻击范围)
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.子弹种类 = "近战子弹";
	子弹.子弹威力 = 12 * _parent.内力 + _parent.空手攻击力 * 0.3 + 1.6 * _parent.内力 * _parent.技能等级;
	if (_parent.mp攻击加成)
	{
		子弹.子弹威力 += _parent.mp攻击加成 * 0.5;
	}
	子弹.子弹速度 = 0;
	子弹.击中地图效果 = "";
	if (Z轴攻击范围)
	{
		子弹.Z轴攻击范围 = Z轴攻击范围;
	}
	else
	{
		子弹.Z轴攻击范围 = 60;
	}
	子弹.击倒率 = 10;
	子弹.击中后子弹的效果 = "空手攻击火花";
	子弹.水平击退速度 = 15;
	子弹.区域定位area = this.攻击点;
	子弹.伤害类型 = "物理";

	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.龙斩刀伤 = function(Z轴攻击范围)
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	子弹.声音 = "";
	子弹.霰弹值 = 5;
	子弹.子弹散射度 = 0;
	子弹.子弹种类 = "近战联弹";
	var temp = 1;
	if(_root.技能函数.龙斩刀伤乘数表[_parent.刀] > 1) temp = _root.技能函数.龙斩刀伤乘数表[_parent.刀];
	
	子弹.子弹威力 = 12 * _parent.内力 + _parent.空手攻击力 * 0.1 + (_parent.内力 + _parent.刀属性数组[13] * 0.2) * 0.5 * _parent.技能等级 + _parent.刀属性数组[13] * temp * 0.12 * (10 + _parent.技能等级);
	if (_parent.mp攻击加成)
	{
		子弹.子弹威力 += _parent.mp攻击加成 * 0.5;
	}
	子弹.子弹速度 = 0;
	子弹.击中地图效果 = "";
	if (Z轴攻击范围)
	{
		子弹.Z轴攻击范围 = Z轴攻击范围;
	}
	else
	{
		子弹.Z轴攻击范围 = 30;
	}
	子弹.击倒率 = 1;
	子弹.击中后子弹的效果 = "空手攻击火花";
	子弹.水平击退速度 = 15;
	子弹.区域定位area = this.攻击点;
	if(_parent.兵器伤害类型){
		子弹.伤害类型 = _parent.兵器伤害类型;
	}
	if(_parent.兵器魔法伤害属性){
		子弹.魔法伤害属性 = _parent.兵器魔法伤害属性;
	}
	if(_parent.兵器毒){
		子弹.毒 = _parent.兵器毒;
	}
	if(_parent.兵器吸血){
		子弹.吸血 = _parent.兵器吸血;
	}
	if(_parent.兵器击溃){
		子弹.血量上限击溃 = _parent.兵器击溃;
	}

	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.地震攻击 = function(Z轴攻击范围)
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.子弹种类 = "近战子弹";
	子弹.子弹威力 = 8 * _parent.内力 + _parent.空手攻击力 * 0.2 + 3 * _parent.内力 * _parent.技能等级;
	if(_parent.hp攻击加成){
		子弹.子弹威力 += _parent.hp攻击加成;
	}
	if(_parent.mp攻击加成){
		子弹.子弹威力 += _parent.mp攻击加成;
	}
	子弹属性.子弹威力 += _parent.空手攻击力 * 0.3 * Math.min((_parent.重量 + _parent.身高 - 105)/100 , 2);
	子弹.子弹速度 = 0;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = isNaN(Z轴攻击范围) ? 30 : Z轴攻击范围;
	子弹.击倒率 = 1;
	子弹.击中后子弹的效果 = "空手攻击火花";
	//子弹.水平击退速度 = 15;
	子弹.区域定位area = this.攻击点;

	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.拔刀术伤害乘数表 = {
	饮血野太刀:2,
	光刃摩羯:2,
	虎彻:3,
	镜之虎彻:2.5,
	// 秋月:2,
	金蛇剑:2
};

_root.技能函数.拔刀术攻击 = function()
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.子弹种类 = "近战子弹";

	var temp = 1;
	if(_root.技能函数.拔刀术伤害乘数表[_parent.刀] > 1) temp = _root.技能函数.拔刀术伤害乘数表[_parent.刀];
	
	if (_parent.刀属性数组[13] != undefined && _parent.刀属性数组[13] != NaN)
	{
		子弹.子弹威力 = _parent.空手攻击力 * 0.1 + (0.25 * _parent.内力 + _parent.刀属性数组[13] * 0.12) * (4 + _parent.技能等级) + _parent.刀属性数组[13] * temp * 0.12 * (10 + _parent.技能等级);
	}
	else
	{
		子弹.子弹威力 = _parent.空手攻击力 * 0.1 + 0.85 * _parent.内力 * (4 + _parent.技能等级);
	}
	if (_parent.mp攻击加成)
	{
		子弹.子弹威力 += _parent.mp攻击加成 * 0.5;
	}

	子弹.子弹速度 = 0;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = 60;
	子弹.击倒率 = 1;
	子弹.击中后子弹的效果 = "空手攻击火花";
	子弹.区域定位area = this.攻击点;
	if(_parent.兵器伤害类型){
		子弹.伤害类型 = _parent.兵器伤害类型;
	}
	if(_parent.兵器魔法伤害属性){
		子弹.魔法伤害属性 = _parent.兵器魔法伤害属性;
	}
	if(_parent.兵器毒){
		子弹.毒 = _parent.兵器毒;
	}
	if(_parent.兵器吸血){
		子弹.吸血 = _parent.兵器吸血;
	}
	if(_parent.兵器击溃){
		子弹.血量上限击溃 = _parent.兵器击溃;
	}

	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.六连攻击 = function()
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.子弹种类 = "近战子弹";
	子弹.不硬直 = true;
	
	if (_parent.刀属性数组[13] != undefined && _parent.刀属性数组[13] != NaN)
	{
		子弹.子弹威力 = _parent.空手攻击力 * 0.1 + (0.25 * _parent.内力 + _parent.刀属性数组[13] * 0.1) * (4 + _parent.技能等级) + _parent.刀属性数组[13] * 0.1 * (10 + _parent.技能等级);
	}
	else
	{
		子弹.子弹威力 =  _parent.空手攻击力 * 0.1 + 0.75 * _parent.内力 * (4 + _parent.技能等级);
	}
	if (_parent.mp攻击加成)
	{
		子弹.子弹威力 += _parent.mp攻击加成 * 0.5;
	}

	子弹.子弹速度 = 0;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = 60;
	子弹.击倒率 = 1;
	子弹.击中后子弹的效果 = "空手攻击火花";
	子弹.区域定位area = this.攻击点;
	if(_parent.兵器伤害类型){
		子弹.伤害类型 = _parent.兵器伤害类型;
	}
	if(_parent.兵器魔法伤害属性){
		子弹.魔法伤害属性 = _parent.兵器魔法伤害属性;
	}
	if(_parent.兵器毒){
		子弹.毒 = _parent.兵器毒;
	}
	if(_parent.兵器吸血){
		子弹.吸血 = _parent.兵器吸血;
	}
	if(_parent.兵器击溃){
		子弹.血量上限击溃 = _parent.兵器击溃;
	}

	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.迅斩攻击 = function()
{
	var 子弹参数 = new Object();
	
	子弹参数.子弹威力 = _parent.空手攻击力 * 0.1 + _parent.刀属性数组[13] * 0.5 * (3 + _parent.技能等级);
	// if (_parent.mp攻击加成)
	// {
	// 	子弹参数.子弹威力 += _parent.mp攻击加成;
	// }
	子弹参数.Z轴攻击范围 = 50;
	子弹参数.击倒率 = 1/_parent.技能等级;
	子弹参数.不硬直 = true;

	if(_parent.兵器伤害类型){
		子弹参数.伤害类型 = _parent.兵器伤害类型;
	}
	if(_parent.兵器魔法伤害属性){
		子弹参数.魔法伤害属性 = _parent.兵器魔法伤害属性;
	}
	if(_parent.兵器毒){
		子弹参数.毒 = _parent.兵器毒;
	}
	if(_parent.兵器吸血){
		子弹参数.吸血 = _parent.兵器吸血;
	}
	if(_parent.兵器击溃){
		子弹参数.血量上限击溃 = _parent.兵器击溃;
	}

	_parent.刀口位置生成子弹(子弹参数);
}

_root.技能函数.翻滚换弹 = function(){
	if (_root.控制目标 != _parent._name) {
		_parent.长枪射击次数[_parent.长枪] = 0;
		_parent.当前弹夹副武器已发射数 = 0;
		_parent.手枪射击次数[_parent.手枪] = 0;
		_parent.手枪2射击次数[_parent.手枪2] = 0;
		return;
	}
	
	var 长枪使用弹夹名称 = _parent.长枪属性数组[14][11];
	if (_parent.长枪射击次数[_parent.长枪] > 0){
		if(org.flashNight.arki.item.ItemUtil.singleSubmit(长枪使用弹夹名称,1)){
			_parent.长枪射击次数[_parent.长枪] = 0;
			_parent.当前弹夹副武器已发射数 = 0;
		}
	}
	var 手枪使用弹夹名称 = _parent.手枪属性数组[14][11];
	if (_parent.手枪射击次数[_parent.手枪] > 0){
		if(org.flashNight.arki.item.ItemUtil.singleSubmit(手枪使用弹夹名称,1)){
			_parent.手枪射击次数[_parent.手枪] = 0;
			_parent.当前弹夹副武器已发射数 = 0;
		}
	}
	var 手枪2使用弹夹名称 = _parent.手枪2属性数组[14][11];
	if (_parent.手枪2射击次数[_parent.手枪2] > 0){
		if(org.flashNight.arki.item.ItemUtil.singleSubmit(手枪2使用弹夹名称,1)){
			_parent.手枪2射击次数[_parent.手枪2] = 0;
			_parent.当前弹夹副武器已发射数 = 0;
		}
	}
}

_root.技能函数.火舞旋风攻击 = function(){
	子弹属性 = _root.子弹属性初始化(this.攻击点);

	子弹属性.声音 = "";
	子弹属性.霰弹值 = 1;
	子弹属性.子弹散射度 = 0;
	子弹属性.子弹种类 = "常规旋风";
	子弹属性.子弹速度 = 0;
	if (_parent.刀属性数组[13]){
		子弹属性.子弹威力 = _parent.空手攻击力 * 0.1 + 2 * _parent.内力 * (3 + _parent.技能等级 * 0.5) + _parent.刀属性数组[13] * (10 + _parent.技能等级) / 10;
	}else{
		子弹属性.子弹威力 = _parent.空手攻击力 * 0.1 + 2 * _parent.内力 * (3 + _parent.技能等级 * 0.5);
	}
	if (_parent.mp攻击加成){
		子弹属性.子弹威力 += _parent.mp攻击加成;
	}
	//消耗燃料罐
	if (_parent._name == _root.控制目标){
		if (org.flashNight.arki.item.ItemUtil.singleSubmit("火焰喷射器燃料罐",1)){
			子弹属性.子弹种类 = "火舞旋风";
			子弹属性.伤害类型 = "魔法";
			子弹属性.魔法伤害属性 = "热";
		}
		if (Key.isDown(_parent.左键) || Key.isDown(_parent.右键)){
			子弹属性.子弹速度 = 13;
		}
	}else{
		子弹属性.子弹速度 = 13;
	}
	子弹属性.Z轴攻击范围 = 50;
	子弹属性.击倒率 = 10;

	_root.子弹区域shoot传递(子弹属性);
}
