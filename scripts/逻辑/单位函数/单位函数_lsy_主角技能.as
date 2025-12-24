import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.unit.Action.Skill.*;
import org.flashNight.arki.unit.*;

_root.技能函数 = new Object();

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
	this.技能等级 = 技能等级;
	_root.技能路由.技能标签跳转_旧(this, 技能名);
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
	// 快速度==6时允许上下微调移动，用于以下技能动画（调用方式：_parent.攻击时移动(0,6)）：
	// - flashswf/arts/things0/LIBRARY/sprite/技能容器.xml:10570, 11710, 262306
	// - flashswf/arts/things0/LIBRARY/技能容器/！技能容器-龙斩.xml:1091
	// - flashswf/arts/things0/LIBRARY/技能容器/！技能容器-火舞旋风.xml:178
	// - flashswf/arts/things0/LIBRARY/技能容器/！技能容器-地震.xml:10763
	// 2024-12-24 扫描记录，共6处调用。后续如需重构可参考 攻击时按键四向移动 函数
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

// 注：速度转伤害、获取技能乘数、传递兵器属性到子弹等工具函数已迁移至 SkillDamageCore 和 SkillAttributeCore
// 业务代码请直接调用静态方法，无需通过代理层

//小跳移动距离计算函数，统一处理不同类型小跳的距离和超重惩罚
//参数：跳跃类型("后跳"/"上下跳"/"前跳")、技能等级、重量、等级
_root.技能函数.小跳移动距离计算 = function(跳跃类型:String, 技能等级:Number, 重量:Number, 等级:Number):Number {
	var 基准移动距离:Number = 0;

	// 根据跳跃类型计算基准移动距离
	switch(跳跃类型) {
		case "后跳":
			基准移动距离 = -20 * (1 + 技能等级 / 10);
			break;
		case "上下跳":
			基准移动距离 = 10 * (1 + 技能等级 / 10);
			break;
		case "前跳":
			基准移动距离 = 20 * (1 + 技能等级 / 10);
			break;
		default:
			基准移动距离 = 0;
			break;
	}

	// 使用重量速度关系计算惩罚（只惩罚不收益）
	var 速度系数:Number = UnitUtil.getWeightSpeedRatio(重量, 等级);
	if (速度系数 > 1) {
		速度系数 = 1; // 截断到1，只惩罚不收益
	}

	// _root.发布消息("小跳类型：" + 跳跃类型 + "，基准距离：" + 基准移动距离 + "，速度系数：" + 速度系数);

	return 基准移动距离 * 速度系数;
}

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
	子弹属性.子弹威力 += _parent.空手攻击力 * 0.3 * Math.min((_parent.重量 + _parent.体重)/100 , 2);
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
	子弹属性.子弹威力 += _parent.空手攻击力 * Math.min((_parent.重量 + _parent.体重)/100 , 2);
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
	子弹属性.子弹威力 += _parent.空手攻击力 * 0.5 * Math.min((_parent.重量 + _parent.体重)/100 , 2);
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

// 注：凶斩伤害乘数表已迁移至 data/items/武器_刀.xml 中的 <skillmultipliers> 标签

_root.技能函数.凶斩攻击 = function(不硬直)
{
	var 子弹参数 = new Object();
	// 从XML配置读取技能乘数（使用工具函数）
	var temp = SkillDamageCore.getSkillMultiplier(_parent, "凶斩");

	子弹参数.子弹威力 = _parent.空手攻击力 * 0.1 + 1.5 * _parent.内力 * (5 + _parent.技能等级) + _parent.刀属性.power * temp * 0.125 * (10 + _parent.技能等级);
	if (_parent.mp攻击加成)
	{
		子弹参数.子弹威力 += _parent.mp攻击加成;
	}
	子弹参数.Z轴攻击范围 = 30;
	子弹参数.击倒率 = 10;
	子弹参数.不硬直 = 不硬直;

	// 传递兵器特殊属性到子弹
	SkillAttributeCore.transferWeaponAttributes(_parent, 子弹参数);

	_parent.刀口位置生成子弹(子弹参数);
}

// 注：瞬步斩伤害乘数表已迁移至 data/items/武器_刀.xml 中的 <skillmultipliers> 标签

_root.技能函数.瞬步斩攻击 = function()
{
	var 子弹参数 = new Object();
	// 从XML配置读取技能乘数（使用工具函数）
	var temp = SkillDamageCore.getSkillMultiplier(_parent, "瞬步斩");

	子弹参数.子弹威力 = _parent.空手攻击力 * 0.1 + 0.5 * _parent.内力 * (5 + _parent.技能等级) + _parent.刀属性.power * temp * 0.1 * (10 + _parent.技能等级);
	// 添加速度转伤害加成
	if (_parent.行走X速度) {
		子弹参数.子弹威力 += SkillDamageCore.speedToDamage(_parent.行走X速度);
	}
	if (_parent.mp攻击加成)
	{
		子弹参数.子弹威力 += _parent.mp攻击加成;
	}
	子弹参数.Z轴攻击范围 = 30;
	子弹参数.击倒率 = 10;
	子弹参数.不硬直 = true;

	// 传递兵器特殊属性到子弹
	SkillAttributeCore.transferWeaponAttributes(_parent, 子弹参数);

	_parent.刀口位置生成子弹(子弹参数);
}

// 注：龙斩刀伤乘数表已迁移至 data/items/武器_刀.xml 中的 <skillmultipliers> 标签

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
	// 从XML配置读取技能乘数（使用工具函数）
	var temp = SkillDamageCore.getSkillMultiplier(_parent, "龙斩");

	子弹.子弹威力 = 12 * _parent.内力 + _parent.空手攻击力 * 0.1 + (_parent.内力 + _parent.刀属性.power * 0.2) * 0.5 * _parent.技能等级 + _parent.刀属性.power * temp * 0.12 * (10 + _parent.技能等级);
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
	SkillAttributeCore.transferWeaponAttributes(_parent, 子弹);
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
	子弹属性.子弹威力 += _parent.空手攻击力 * 0.3 * Math.min((_parent.重量 + _parent.体重)/100 , 2);
	子弹.子弹速度 = 0;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = isNaN(Z轴攻击范围) ? 30 : Z轴攻击范围;
	子弹.击倒率 = 1;
	子弹.击中后子弹的效果 = "空手攻击火花";
	//子弹.水平击退速度 = 15;
	子弹.区域定位area = this.攻击点;

	_root.子弹区域shoot传递(子弹);
}

// 注：拔刀术伤害乘数表已迁移至 data/items/武器_刀.xml 中的 <skillmultipliers> 标签

_root.技能函数.拔刀术攻击 = function()
{
	var 子弹 = _root.子弹属性初始化(this.攻击点);
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.子弹种类 = "近战子弹";

	// 从XML配置读取技能乘数（使用工具函数）
	var temp = SkillDamageCore.getSkillMultiplier(_parent, "拔刀术");

	if (_parent.刀属性.power != undefined && _parent.刀属性.power != NaN)
	{
		子弹.子弹威力 = _parent.空手攻击力 * 0.1 + (0.5 * _parent.内力 + _parent.刀属性.power * 0.12) * (4 + _parent.技能等级) + _parent.刀属性.power * temp * 0.12 * (10 + _parent.技能等级);
	}
	else
	{
		子弹.子弹威力 = _parent.空手攻击力 * 0.1 + 0.85 * _parent.内力 * (4 + _parent.技能等级);
	}
	// 添加速度转伤害加成
	if (_parent.行走X速度) {
		子弹.子弹威力 += SkillDamageCore.speedToDamage(_parent.行走X速度);
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
	SkillAttributeCore.transferWeaponAttributes(_parent, 子弹);
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

	if (_parent.刀属性.power != undefined && _parent.刀属性.power != NaN)
	{
		子弹.子弹威力 = _parent.空手攻击力 * 0.1 + (0.5 * _parent.内力 + _parent.刀属性.power * 0.1) * (4 + _parent.技能等级) + _parent.刀属性.power * 0.1 * (10 + _parent.技能等级);
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
	SkillAttributeCore.transferWeaponAttributes(_parent, 子弹);
	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.迅斩攻击 = function(){
	var 子弹参数 = new Object();

	子弹参数.子弹威力 = _parent.空手攻击力 * 0.1 + _parent.刀属性.power * (3 + _parent.技能等级 * 0.35);
	// 添加速度转伤害加成
	if (_parent.行走X速度) {
		子弹参数.子弹威力 += SkillDamageCore.speedToDamage(_parent.行走X速度);
	}
	// if (_parent.mp攻击加成)
	// {
	// 	子弹参数.子弹威力 += _parent.mp攻击加成;
	// }
	子弹参数.Z轴攻击范围 = 50;
	子弹参数.击倒率 = 2/(10 + _parent.技能等级);
	子弹参数.不硬直 = true;
	SkillAttributeCore.transferWeaponAttributes(_parent, 子弹参数);
	_parent.刀口位置生成子弹(子弹参数);
}

// 注：单个武器换弹工具函数已迁移至 SkillReloadCore.reloadWeapon，业务代码请直接调用

// 翻滚换弹（SWF资源接口，保留用于资源文件调用）
_root.技能函数.翻滚换弹 = function(){
	SkillReloadCore.reloadAllWeapons(_parent);
}

_root.技能函数.火舞旋风攻击 = function(){
	子弹属性 = _root.子弹属性初始化(this.攻击点);

	子弹属性.声音 = "";
	子弹属性.霰弹值 = 1;
	子弹属性.子弹散射度 = 0;
	子弹属性.子弹种类 = "常规旋风";
	子弹属性.子弹速度 = 0;
	if (_parent.刀属性.power){
		子弹属性.子弹威力 = _parent.空手攻击力 * 0.1 + 2 * _parent.内力 * (3 + _parent.技能等级 * 0.5) + _parent.刀属性.power * (10 + _parent.技能等级) / 10;
	}else{
		子弹属性.子弹威力 = _parent.空手攻击力 * 0.1 + 2 * _parent.内力 * (3 + _parent.技能等级 * 0.5);
	}
	if (_parent.mp攻击加成){
		子弹属性.子弹威力 += _parent.mp攻击加成;
	}
	//消耗燃料罐
	if (_parent._name == _root.控制目标){
		if (ItemUtil.singleSubmit("火焰喷射器燃料罐",1)){
			子弹属性.子弹种类 = "火舞旋风";
			子弹属性.伤害类型 = "魔法";
			子弹属性.魔法伤害属性 = "热";
				_root.发布消息("消耗火焰喷射器燃料罐");
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

_root.技能函数.掌炮攻击 = function(){

	var 子弹 = _root.子弹属性初始化(this.攻击点);
	
	子弹.声音 = "铁血飞弹.mp3";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.发射效果 = "";
	子弹.子弹种类 = "铁血飞弹";
	子弹.子弹威力 =  1 * _parent.内力 +  (_parent.内力 + _parent.装备枪械威力加成) * (掌炮蓄力 + 2) * 1;
	子弹.子弹速度 = 35;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = 30;
	子弹.击倒率 = 0.1;
	子弹.击中后子弹的效果 = "";
	子弹.击中地图效果 = "";
	if(_parent.Mark3消耗能量电池 && _parent._name == _root.控制目标 && ItemUtil.singleSubmit("能量电池",1)){
		子弹.击倒率 = 0.01;
		子弹.子弹威力 += 8000;
		子弹.伤害类型 = "魔法";
		子弹.魔法伤害属性 = undefined;
		子弹.击中后子弹的效果 = "铁血弹爆炸";
		子弹.击中地图效果 = "铁血弹爆炸";
		if(掌炮蓄力 >= 3){
			子弹.子弹速度 += 掌炮蓄力;
			子弹.子弹种类 = "追踪铁血飞弹";
			子弹.霰弹值 = 2;
			子弹.子弹威力 *= 0.7;
			子弹.子弹散射度 = 15;
		}
		if(掌炮蓄力 >= 6){
			子弹.声音 = "dominator枪声2.wav";
			子弹.子弹种类 = "电浆球";
			子弹.Z轴攻击范围 = 50;
			子弹.子弹速度 = 50;
			子弹.子弹威力 *= 0.7;
			子弹.子弹散射度 = 0;
			子弹.击中后子弹的效果 = "";
			子弹.击中地图效果 = "";
			子弹.霰弹值 = 1;
		}
		_root.发布消息("消耗能量电池");
	}else{
		子弹.子弹种类 = "气功弹";
		子弹.声音 = "气动波.wav";
		if(掌炮蓄力 >= 5){
			子弹.爆炸冲伤 = true;
			子弹.子弹速度 += Math.floor( 掌炮蓄力 * 0.5 );
		}
		if(掌炮蓄力 >= 10){
			子弹.伤害类型 = "魔法";
			子弹.魔法伤害属性 = "冲";
		}
		if(掌炮蓄力 >= 18){
			子弹.声音 = "dominator枪声2.wav";
			子弹.子弹种类 = "电浆球";
			子弹.伤害类型 = "魔法";
			子弹.魔法伤害属性 = "电";
			子弹.Z轴攻击范围 = 50;
			子弹.子弹速度 += 5;
			子弹.子弹威力 *= 0.5;
		}
	}
	if (_parent.上行){
		子弹.角度偏移 = -30;
	}else if (_parent.下行){
		子弹.角度偏移 = 30;
	}
	
	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.手部发射攻击 = function(){

	var 子弹 = _root.子弹属性初始化(this.攻击点);
	
	子弹.声音 = "";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.发射效果 = "";
	子弹.子弹种类 = "普通子弹";
	子弹.子弹威力 =  10 * _parent.内力;
	子弹.子弹速度 = 35;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = 30;
	子弹.击倒率 = 1;
	子弹.击中后子弹的效果 = "";
	子弹.击中地图效果 = "";
	if (_parent.上行){
		子弹.角度偏移 = -30;
	}else if (_parent.下行){
		子弹.角度偏移 = 30;
	}
	if(_parent.手部发射子弹属性){
		for (var key in _parent.手部发射子弹属性) {
			子弹[key] = _parent.手部发射子弹属性[key];
		}
	}
	
	_root.子弹区域shoot传递(子弹);
}

_root.技能函数.登上明星攻击 = function(){

	var 子弹 = _root.子弹属性初始化(this.攻击点);
	
	子弹.声音 = "登上明星音效.wav";
	子弹.霰弹值 = 1;
	子弹.子弹散射度 = 0;
	子弹.发射效果 = "";
	子弹.子弹种类 = "登上明星子弹";
	子弹.子弹威力 =  10 * _parent.内力;
	子弹.子弹速度 = 60;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = 60;
	子弹.击倒率 = 0.5;
	子弹.击中后子弹的效果 = "";
	子弹.击中地图效果 = "";
	子弹.伤害类型 = "魔法";
	子弹.魔法伤害属性 = undefined;
	if(登上明星蓄力){
		子弹.声音 = "登上明星音效.wav";
		子弹.子弹种类 = "登上明星子弹";
		子弹.Z轴攻击范围 = 70;
		子弹.子弹速度 += 5;
		子弹.霰弹值 = 3;
		子弹.子弹散射度 = 20;
		子弹.预填充节点 = 1;
		if(_parent.登上明星消耗mp &&  _parent.mp>= _parent.登上明星消耗mp){
			_parent.mp -= _parent.登上明星消耗mp;
			子弹.子弹威力 += _parent.登上明星消耗mp * 20;
			if(_parent.登上明星消耗mp >= 100){
				子弹.伤害类型 = "真伤";
				子弹.子弹威力 *= 0.9;
			}
		}
	}else{
		子弹.声音 = "登上明星音效.wav";
		子弹.子弹种类 = "登上明星子弹";
	}
	if (_parent.上行){
		子弹.角度偏移 = -30;
		子弹.预填充节点 = 1;
	}else if (_parent.下行){
		子弹.角度偏移 = 30;
		子弹.预填充节点 = 1;
	}
	
	_root.子弹区域shoot传递(子弹);
}


