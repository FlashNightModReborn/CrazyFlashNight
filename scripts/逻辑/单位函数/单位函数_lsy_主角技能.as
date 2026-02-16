import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.unit.Action.Skill.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

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

// 能量盾释放条件：玩家需要消耗能量电池，NPC无条件可释放
// 将消耗品检查前置到释放条件中，避免进入动画后才发现缺少消耗品
_root.技能函数.释放条件.能量盾 = function():Boolean {

	// _root.发布消息("检查能量盾释放条件");
	// 非玩家单位无条件可释放
	if (this._name != _root.控制目标) {
		return !this.倒地;  // 仍需满足默认的不倒地条件
	}
	// 玩家需检查消耗品
	if (this.倒地) return false;
	if (_root.singleContain("能量电池", 1) == null) {
		_root.发布消息("缺少能量电池！");
		return false;
	}
	return true;
};

// 铁布衫释放条件
_root.技能函数.释放条件.铁布衫 = function():Boolean {
	if (this.倒地) return false;
	return true;
};

// 兴奋剂释放条件
_root.技能函数.释放条件.兴奋剂 = function():Boolean {
	if (this.倒地) return false;
	return true;
};



//释放行为函数
_root.技能函数.释放行为 = new Object();

//传入技能名和技能等级两个参数
//默认释放行为，进入技能动画并跳转到对应标签帧
_root.技能函数.释放行为.默认 = function(技能名, 技能等级){
	this.技能等级 = 技能等级;
	_root.技能路由.技能标签跳转_旧(this, 技能名);
}
//buff系统实装后，部分技能可以通过更改释放行为函数，不进技能动画释放


// ── AI 辅助标记：预战buff属性 ──
// UtilityEvaluator.selectPreCombatBuff 读取此表决定预战buff策略
// priority: 预战使用优先级（越高越优先）
// global: true 表示全场/全场景生效，不需要重复使用
// buffId: buff 在 BuffManager 中的注册 ID（用于查询是否已激活）
_root.技能函数.预战buff标记 = {};
_root.技能函数.预战buff标记["兴奋剂"] = { priority: 3, global: true, buffId: "兴奋剂" };
_root.技能函数.预战buff标记["铁布衫"] = { priority: 2, global: true, buffId: "铁布衫" };
_root.技能函数.预战buff标记["霸体"]   = { priority: 1, global: false, buffId: "霸体" };
_root.技能函数.预战buff标记["能量盾"] = { priority: 1, global: false, buffId: null };


//主角技能的移动相关函数

/**
 * 兵器攻击专用移动函数
 *
 * 与技能移动函数的区别：
 * - 始终按角色朝向移动，由速度正负决定前进/后退
 * - 负数速度 = 后退，正数速度 = 前进
 * - 按键只影响快/慢速度的选择，不改变移动方向
 *
 * 用于兵器攻击容器中的招式移动（如见切后撤、见切追斩等）
 *
 * @param 慢速度 不按方向键时的移动速度（负数后退，正数前进）
 * @param 快速度 按方向键时的移动速度（负数后退，正数前进）
 */
_root.技能函数.兵器攻击时移动 = function(慢速度, 快速度){
	var parent:MovieClip = _parent;
	var 方向:String = parent.方向;

	// 非控制目标或无快速度：直接按朝向移动
	if(parent._name != _root.控制目标 || isNaN(快速度)){
		Mover.move2D(parent, 方向, 慢速度);
		return;
	}

	// 判断是否按下朝向方向的按键
	var 按下朝向键:Boolean = (方向 == "右" && parent.右行) || (方向 == "左" && parent.左行);

	if(按下朝向键){
		// 按下朝向键时使用快速度
		Mover.move2D(parent, 方向, 快速度);
	} else {
		// 未按键或按反方向键时使用慢速度
		Mover.move2D(parent, 方向, 慢速度);
	}
}

/**
 * 兵器攻击专用四向移动函数
 *
 * 与技能版本的区别：
 * - 无按键时调用兵器攻击时移动，支持负数后退
 *
 * @param 慢速度 不按方向键时的移动速度（负数后退，正数前进）
 * @param 快速度 按方向键时的移动速度
 */
_root.技能函数.兵器攻击时按键四向移动 = function(慢速度, 快速度){
	var parent:MovieClip = _parent;

	if(parent._name != _root.控制目标){
		Mover.move2D(parent, parent.方向, 慢速度);
		return;
	}
	var 上下未按键 = false;
	var 左右未按键 = false;
	// 检测上下是否按键
	if (parent.上行) Mover.move2D(parent, "上", 快速度 / 2);
	else if (parent.下行) Mover.move2D(parent, "下", 快速度 / 2);
	else 上下未按键 = true;
	// 检测左右是否按键
	if (parent.左行) Mover.move2D(parent, "左", 快速度);
	else if (parent.右行) Mover.move2D(parent, "右", 快速度);
	else 左右未按键 = true;
	// 无按键时调用兵器攻击时移动（支持负数后退）
	if (上下未按键 && 左右未按键){
		_root.技能函数.兵器攻击时移动.call(this, 慢速度, 快速度);
	}
}

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

_root.技能函数.攻击时按键四向空中移动 = function(慢速度, 快速度)
{
	var 上下未按键 = 0;
	var 左右未按键 = 0;
	if (Key.isDown(_parent.上键) == true)
	{
		_parent.跳跃上下移动("上",快速度 / 2);
	}
	else if (Key.isDown(_parent.下键) == true)
	{
		_parent.跳跃上下移动("下",快速度 / 2);
	}
	else
	{
		上下未按键 = 1;
	}
	if (Key.isDown(_parent.左键) == true)
	{
		_parent.跳跃上下移动("左",快速度);
	}
	else if (Key.isDown(_parent.右键) == true)
	{
		_parent.跳跃上下移动("右",快速度);
	}
	else
	{
		左右未按键 = 1;
	}
	if (上下未按键 && 左右未按键)
	{
		攻击时移动(慢速度,快速度);
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

/**
 * 变招判定 - 兵器攻击中的招式切换判定
 * 用于普攻连招中判断是否触发跳跃、切换招式或移动
 *
 * @param 招式名:String 可派生的目标招式名（若为空则不允许连招）
 * @param 招式是否结束:Boolean 当前招式是否已结束（用于AI连招判定）
 */
_root.技能函数.变招判定 = function(招式名:String, 招式是否结束:Boolean):Void {
	var unit:MovieClip = _parent;
	if (unit.操控编号 != -1 && _root.控制目标全自动 == false) {
		// 玩家控制
		if (!unit.飞行浮空 && unit.动作B) {
			unit.状态改变("兵器跳");
		} else if (unit.动作A && 招式名) {
			if (unit.左行) {
				unit.右行 = 0;
				unit.方向改变("左");
			} else if (unit.右行) {
				unit.左行 = 0;
				unit.方向改变("右");
			}
			gotoAndPlay(招式名);
		} else if (unit.左行 || unit.右行 || unit.上行 || unit.下行) {
			unit.动画完毕();
		}
	} else if (招式名 && !招式是否结束) {
		// AI控制：继续连招
		gotoAndPlay(招式名);
	}
}

/**
 * 刀口触发特效 - 触发刀口位置上的特效
 *
 * @param 状态名:String 要触发的特效状态名
 */
_root.技能函数.刀口触发特效 = function(状态名:String):Void {
	if (_parent.特效刀口) {
		_parent.特效刀口.特效刀口触发(状态名);
	}
}

/**
 * 兵器攻击 - 兵器近战攻击子弹生成
 * 用于普攻连招中的伤害生成
 *
 * @param 子弹威力:Number 基础子弹威力
 * @param Z轴攻击范围:Number Z轴攻击范围
 * @param 击倒率:Number 击倒率
 * @param 水平击退速度:Number 水平击退速度
 * @param 垂直击退速度:Number 垂直击退速度（可选）
 */
_root.技能函数.兵器攻击 = function(子弹威力:Number, Z轴攻击范围:Number, 击倒率:Number, 水平击退速度:Number, 垂直击退速度:Number):Void {
	var unit:MovieClip = _parent;
	var 子弹参数:Object = new Object();
	子弹参数.子弹威力 = 子弹威力;
	// 刀剑攻击被动技能加成
	if (unit.被动技能.刀剑攻击 && unit.被动技能.刀剑攻击.启用) {
		子弹参数.子弹威力 += unit.刀属性.power * unit.被动技能.刀剑攻击.等级 * 0.075;
	}
	// mp攻击加成
	if (unit.mp攻击加成) {
		子弹参数.子弹威力 += unit.mp攻击加成;
	}
	子弹参数.Z轴攻击范围 = Z轴攻击范围;
	子弹参数.击中后子弹的效果 = "斩打命中特效";
	子弹参数.击倒率 = 击倒率;
	子弹参数.水平击退速度 = 水平击退速度;
	if (垂直击退速度) {
		子弹参数.垂直击退速度 = 垂直击退速度;
	}

	unit.刀口位置生成子弹(unit, 子弹参数);
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

_root.技能函数.震血攻击 = function(当前攻击点, Z轴攻击范围, 是否为衍生段数)
{
	if(_parent.hp > 10 && _parent.被动技能.内力爆发 && _parent.被动技能.内力爆发.启用){
		var 消耗血量 = Math.min (Math.floor(_parent.hp * 0.1),3000);
		if(!是否为衍生段数){
			_parent.hp -= 消耗血量;
		}
		var 子弹 = _root.子弹属性初始化(当前攻击点);
		子弹.声音 = "砸地.wav";
		子弹.霰弹值 = 1;
		子弹.子弹散射度 = 0;
		子弹.子弹种类 = "震血";
		子弹.子弹威力 = 消耗血量 * (1 + 0.1 * _parent.被动技能.内力爆发.等级) + _parent.内力 * 0.25 * _parent.被动技能.内力爆发.等级;
		子弹属性.子弹威力 += _parent.内力 * 0.3 * Math.min((_parent.重量 + _parent.体重)/100 , 2);
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
		子弹.伤害类型 = "真伤";

		_root.子弹区域shoot传递(子弹);
	}
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
	if(_parent.被动技能.内力爆发 && _parent.被动技能.内力爆发.启用){
		if(_parent.mp >= _parent.被动技能.内力爆发.等级 * 2){
			_parent.mp -= _parent.被动技能.内力爆发.等级 * 2;
			子弹.子弹威力 += (_parent.内力 * 0.2 + _parent.被动技能.内力爆发.等级 * 2) * _parent.被动技能.内力爆发.等级;
			if(_parent.被动技能.内力爆发.等级 >= 5){
				子弹.伤害类型 = "魔法";
				子弹.魔法伤害属性 = "冲";
			}
			if(_parent.被动技能.内力爆发.等级 >= 10){
				子弹.魔法伤害属性 = undefined;
			}
		}
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

_root.技能函数.龟派气功攻击 = function(当前攻击点, 段数类型, 霰弹值)
{
	var 子弹 = _root.子弹属性初始化(当前攻击点);
	子弹.声音 = "";
	子弹.霰弹值 = 霰弹值? 霰弹值 : 3;
	子弹.最小霰弹值 = 3;
	子弹.子弹散射度 = 0;
	子弹.子弹种类 = "近战联弹";
	子弹.子弹威力 = 10 * _parent.内力 + _parent.空手攻击力 * 0.2 + 3.5 * _parent.内力 * _parent.技能等级;
	if(循环次数 > 0){
 		子弹.子弹威力 += 循环百分比消耗 * (20 + _parent.技能等级 * 3);
		if(_parent.被动技能.内力爆发 && _parent.被动技能.内力爆发.启用){
			子弹.子弹威力 += 循环百分比消耗 * 2 * _parent.被动技能.内力爆发.等级;
		}
	}
	if(_parent.hp攻击加成){
		子弹.子弹威力 += _parent.hp攻击加成;
	}
	if(_parent.mp攻击加成){
		子弹.子弹威力 += _parent.mp攻击加成;
	}
	子弹.子弹速度 = 0;
	子弹.击中地图效果 = "";
	子弹.Z轴攻击范围 = 80;
	子弹.击倒率 = 0.1;
	子弹.击中后子弹的效果 = "空手攻击火花";
	子弹.区域定位area = 当前攻击点;
	子弹.水平击退速度 = 12;
	子弹.不硬直 = true;
	if (_parent.技能等级 >= 10 && 段数类型 != 2)
	{
		子弹.伤害类型 = "魔法";
		子弹.魔法伤害属性 = "冲";
		子弹.子弹威力 *= 0.8;
	}
	if(段数类型 == 1){
		子弹.水平击退速度 = 15;
	}else if(段数类型 == 2){
		if(_parent.被动技能.内力爆发 && _parent.被动技能.内力爆发.启用 && _parent.被动技能.内力爆发.等级 >= 10){
			子弹.伤害类型 = "魔法";
			子弹.魔法伤害属性 = undefined;
		}
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

	_parent.刀口位置生成子弹(_parent, 子弹参数);
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

	_parent.刀口位置生成子弹(_parent, 子弹参数);
}

_root.技能函数.刀剑乱舞判定 = function()
{
	var 自机 = _parent;

	// === 第一段：攻击点子弹（空手模式属性）===
	var 子弹属性 = _root.子弹属性初始化(this.攻击点);
	子弹属性.声音 = "";
	子弹属性.霰弹值 = 2;
	子弹属性.子弹散射度 = 0;
	子弹属性.子弹种类 = "近战联弹";
	// 空手模式伤害公式：基于空手攻击力
	子弹属性.子弹威力 = 自机.空手攻击力 * 1.5 + 自机.等级 * 20;
	子弹属性.子弹速度 = 0;
	子弹属性.Z轴攻击范围 = 60;
	子弹属性.击倒率 = 10;
	子弹属性.区域定位area = this.攻击点;
	// 空手模式：传递空手战斗属性
	SkillAttributeCore.transferUnarmedAttributes(自机, 子弹属性);
	// _root.发布消息(自机.空手伤害类型, 自机.空手魔法伤害属性, 子弹属性.伤害类型, 子弹属性.魔法伤害属性);
	_root.子弹区域shoot传递(子弹属性);

	// === 第二段：刀子弹（兵器模式属性）===
	var 刀子弹属性 = _root.子弹属性初始化(this.刀);
	刀子弹属性.声音 = "";
	刀子弹属性.霰弹值 = 1;
	刀子弹属性.子弹散射度 = 0;
	刀子弹属性.子弹种类 = "近战子弹";
	// 兵器模式伤害公式：基于刀属性.power
	刀子弹属性.子弹威力 = (自机.空手攻击力 + 自机.刀属性.power) * 1.25 + 自机.等级 * 25;
	刀子弹属性.子弹速度 = 0;
	刀子弹属性.Z轴攻击范围 = 60;
	刀子弹属性.击倒率 = 10;
	刀子弹属性.区域定位area = this.刀;
	// 兵器模式：传递兵器特殊属性
	SkillAttributeCore.transferWeaponAttributes(自机, 刀子弹属性);
	
	_root.子弹区域shoot传递(刀子弹属性);

	// === 消弹效果 ===
	var 消弹属性 = _root.消弹属性初始化(this.攻击点);
	消弹属性.消弹方向 = 自机.方向 == "右" ? "左" : "右";
	消弹属性.Z轴攻击范围 = 30;
	消弹属性.区域定位area = this.攻击点;
	_root.消除子弹(消弹属性);
}

_root.技能函数.一文字落雷居合 = function()
{
	子弹属性 = _root.子弹属性初始化(this.攻击点);
	自机 = _parent;


	子弹属性.声音 = "";
	子弹属性.霰弹值 = 居合段数 || 2;

	子弹属性.子弹散射度 = 0;
	子弹属性.子弹种类 = "近战联弹";

	子弹属性.子弹威力 = 自机.空手攻击力 * 0.2 + 自机.等级 * 10 + 自机.刀属性.power * 2.5;
	子弹属性.子弹速度 = 0;
	子弹属性.Z轴攻击范围 = 30;
	子弹属性.击倒率 = 5;

	子弹属性.区域定位area = this.攻击点.area;

	_root.子弹区域shoot传递(子弹属性);

	// 刀口位置生成子弹（纯刀属性伤害）
	var 刀口子弹参数 = {子弹威力: 自机.刀属性.power};
	if (自机.行走X速度) {
		刀口子弹参数.子弹威力 += SkillDamageCore.speedToDamage(自机.行走X速度);
	}
	刀口子弹参数.Z轴攻击范围 = 30;
	刀口子弹参数.击倒率 = 10;

	SkillAttributeCore.transferWeaponAttributes(自机, 刀口子弹参数);
	自机.刀口位置生成子弹(自机, 刀口子弹参数);

	var 消弹属性 = _root.消弹属性初始化(this.攻击点);
	消弹属性.消弹方向 = 自机.方向 == "右" ? "左" : "右";
	消弹属性.Z轴攻击范围 = 30;
	消弹属性.区域定位area = this.攻击点;
	消弹属性.反弹 = !!自机.man.消弹反弹;
	_root.消除子弹(消弹属性);
}

_root.技能函数.一文字落雷跳劈 = function()
{
	子弹属性 = _root.子弹属性初始化(this.攻击点);
	自机 = _parent;


	//以下部分只需要更改需要更改的属性,其余部分可注释掉
	子弹属性.声音 = "";
	子弹属性.霰弹值 = 落雷段数 || 4;
	子弹属性.最小霰弹值 = 3;
	子弹属性.子弹散射度 = 0;
	子弹属性.子弹种类 = "近战联弹";


	子弹属性.子弹威力 = 自机.空手攻击力 * 1 + 自机.等级 * 15 + 自机.刀属性.power * 3.5;
	子弹属性.子弹速度 = 0;
	子弹属性.Z轴攻击范围 = 50;
	子弹属性.击倒率 = 1.5;

	子弹属性.区域定位area = this.攻击点.area;

	_root.子弹区域shoot传递(子弹属性);

	// 刀口位置生成子弹（纯刀属性伤害）
	var 刀口子弹参数 = {子弹威力: 自机.刀属性.power};
	if (自机.行走X速度) {
		刀口子弹参数.子弹威力 += SkillDamageCore.speedToDamage(自机.行走X速度);
	}

	刀口子弹参数.Z轴攻击范围 = 40;
	刀口子弹参数.击倒率 = 2;
	SkillAttributeCore.transferWeaponAttributes(自机, 刀口子弹参数);
	自机.刀口位置生成子弹(自机, 刀口子弹参数);

	var 消弹属性 = _root.消弹属性初始化(this.攻击点);
	消弹属性.消弹方向 = 自机.方向 == "右" ? "左" : "右";
	消弹属性.Z轴攻击范围 = 30;
	消弹属性.区域定位area = this.攻击点;
	消弹属性.反弹 = !!自机.man.消弹反弹;
	_root.消除子弹(消弹属性);
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
	_parent.刀口位置生成子弹(_parent, 子弹参数);
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
		delete _parent.手部发射子弹属性;
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

/**
 * 能量盾技能释放逻辑
 *
 * 【功能说明】
 * 1. 消耗能量电池（玩家）或无消耗（NPC）
 *    - 消耗品检查已前置到 _root.技能函数.释放条件.能量盾
 *    - 此处仅执行实际扣除
 * 2. 给予全属性魔法抗性加成buff（32-50点，持续21-39秒）
 * 3. 添加衰减护盾作为视觉提示和保底防御
 *
 * 【衰减护盾设计】
 * - 超高容量：(hp满血值+1000) × (10+技能等级)，确保战斗消耗不会导致提前破碎
 * - 低强度（10-100）：提供保底防御，不破坏平衡
 * - 衰减速率与buff持续时间同步：buff结束时盾刚好消失
 * - 视觉反馈：玩家可通过盾槽条直观看到buff剩余时间
 *
 * @param target 目标单位（_parent）
 * @param 技能等级 技能等级 (1-10)
 * @return Boolean 是否成功释放
 */
_root.技能函数.能量盾释放 = function(target:Object, 技能等级:Number):Boolean {
	var isPlayer:Boolean = (target._name == _root.控制目标);

	// === 消耗扣除（玩家需要能量电池，NPC无消耗） ===
	// 注：消耗品存在性已在释放条件中检查，此处直接扣除
	if (isPlayer && !_root.singleSubmit("能量电池", 1)) {
		return false;  // 理论上不会到这里，除非释放条件检查后物品被消耗
	}

	// === 参数计算 ===
	var 增加值:Number = 30 + 技能等级 * 2;  // 等级1-10 → 32-50
	var 持续毫秒:Number = (19 + 技能等级 * 2) * 1000;  // 等级1-10 → 21-39秒 → 21000-39000毫秒
	var 持续帧数:Number = 持续毫秒 / 1000 * 30;  // 转换为帧数（30fps）

	// === 应用Buff效果 ===
	target.buff.限时赋值(持续毫秒, "魔法抗性", "加算", 增加值, "增益");

	// === 添加衰减护盾（视觉提示+保底防御） ===
	var 护盾容量:Number = (target.hp满血值 + 1000) * (10 + 技能等级);  // 等级1→11倍，等级10→20倍
	var 护盾强度:Number = 10 * 技能等级;  // 等级1→10, 等级10→100
	var 衰减速率:Number = 护盾容量 / 持续帧数;

	_root.护盾函数.添加衰减护盾(
		target,
		护盾容量,
		护盾强度,
		衰减速率,
		"能量护盾",
		{
			onBreak: function(s) {
				if(isPlayer){
					_root.发布消息("能量盾效果结束");
				}
			}
		}
	);

	// === 显示提示 ===
	var 持续秒数:Number = Math.round(持续帧数 / 30);
	if(isPlayer){
		_root.发布消息("能量护盾启动！全属性抗性+" + 增加值 + "，持续" + 持续秒数 + "秒");
	}

	return true;
};

/**
 * 霸体减伤 - 通过 BuffManager 使用 MetaBuff + TimeLimitComponent 实现带自动移除的减伤
 *
 * @param target Object 目标单位
 * @param 减伤率 Number 减伤百分比（1-99），如 50 表示减伤50%
 * @param 持续帧数 Number 可选，buff持续的帧数。若不提供则为永久buff（需手动移除）
 *
 * 使用方式：
 *   _root.技能函数.霸体减伤(target, 50, 300);  // 启用50%减伤，持续300帧后自动移除
 *   _root.技能函数.霸体减伤(target, 50);       // 启用50%减伤，永久生效直到手动移除
 *   _root.技能函数.移除霸体减伤(target);       // 手动移除减伤效果
 *
 * 原理：
 *   通过 BuffManager 添加一个 MetaBuff，内部包含一个修改 damageTakenMultiplier 的 PodBuff
 *   使用 MULT_NEGATIVE（保守语义）确保多个减伤效果只取最强（承伤系数最小）
 *   使用 TimeLimitComponent 控制生命周期，到期后自动移除
 *   例如：减伤率=50 → 承伤系数=0.5 → 受到伤害减半
 *
 * 多来源减伤说明：
 *   使用 MULT_NEGATIVE 保守语义，多个减伤buff自动取最强效果：
 *   - 霸体减伤 50%（承伤0.5）+ 铁布衫 30%（承伤0.7）→ 只生效 0.5（最强减伤）
 *   - 当最强效果过期后，次强效果自动生效（回落机制）
 *   - 不同来源可通过 来源ID 参数区分，同来源会替换，不同来源可共存
 *
 * 刚体控制器持续帧数参考（从"刚体开始"帧算起）：
 *   等级1: 299帧, 等级2: 328帧, 等级3: 358帧, 等级4: 389帧, 等级5: 419帧
 *   等级6: 449帧, 等级7: 479帧, 等级8: 510帧, 等级9: 540帧, 等级10: 570帧
 *   公式: 299 + (技能等级 - 1) * 30 （近似值）
 */
_root.技能函数.霸体减伤 = function(target:Object, 减伤率:Number, 持续帧数:Number, 来源ID:String):Void {
	// 参数校验
	if (!target || !减伤率 || 减伤率 <= 0) return;

	// 限制减伤率范围 (1-99)
	减伤率 = Math.max(Math.min(减伤率, 99), 1);

	// 计算承伤系数：减伤率50% → 承伤系数0.5
	var 承伤系数:Number = (100 - 减伤率) / 100;

	// 通过 BuffManager 设置减伤
	// 创建内部 PodBuff：修改 damageTakenMultiplier
	// 使用 MULT_NEGATIVE 保守语义：多个减伤buff自动取最小值（最强减伤）
	var podBuff:PodBuff = new PodBuff(
		"damageTakenMultiplier",           // 目标属性
		BuffCalculationType.MULT_NEGATIVE, // 保守语义：取最小值（最强减伤）
		承伤系数                             // 承伤系数值
	);

	// 准备组件数组
	var components:Array = [];

	// 如果提供了持续帧数，添加 TimeLimitComponent 实现自动移除
	if (持续帧数 > 0) {
		components.push(new TimeLimitComponent(持续帧数));
	}

	// 创建 MetaBuff 包装 PodBuff
	var metaBuff:MetaBuff = new MetaBuff(
		[podBuff],    // 子 PodBuff 数组
		components,   // 组件数组（可能包含 TimeLimitComponent）
		0             // 优先级
	);

	// 根据来源ID生成buffId：不同来源可共存，同来源会替换
	// 保守语义MULT_NEGATIVE会自动取所有减伤效果中的最小值（最强减伤）
	var buffId:String = 来源ID ? ("霸体减伤_" + 来源ID) : "霸体减伤";
	target.buffManager.addBuff(metaBuff, buffId);

};

/**
 * 移除霸体减伤效果
 * @param target Object 目标单位
 * @param 来源ID String 来源标识（可选，需与添加时一致）
 */
_root.技能函数.移除霸体减伤 = function(target:Object, 来源ID:String):Void {
	if (!target) return;

	if (target.buffManager) {
		var buffId:String = 来源ID ? ("霸体减伤_" + 来源ID) : "霸体减伤";
		target.buffManager.removeBuff(buffId);
	}
};

/**
 * 兴奋剂释放 - 注射兴奋剂提升攻击力和移动速度
 *
 * @param target Object 目标单位
 * @param 技能等级 Number 技能等级 (1-10)
 * @return Boolean 是否成功释放
 *
 * 效果：
 *   - 消耗10点HP
 *   - 空手攻击力 +10×技能等级
 *   - 行走X速度 ×(1 + 0.05×技能等级)，其他速度通过getter自动派生
 *   - 使用固定ID添加buff，重复使用会替换而非叠加
 */
_root.技能函数.兴奋剂释放 = function(target:Object, 技能等级:Number):Boolean {
	if (!target) return false;
	if (!target.buffManager) return false;

	// 消耗HP
	target.hp -= 10;
	_root.主角hp显示界面.刷新显示();

	// 计算buff值
	var 技能空手攻击力加成:Number = 10 * 技能等级;
	var 技能速度倍率:Number = 1 + 0.05 * 技能等级;

	// 构建MetaBuff：空手攻击力加算 + 行走X速度倍率
	// 由于行走Y速度、跑X速度、跑Y速度已通过getter从行走X速度派生，
	// 只需修改行走X速度即可自动影响所有速度
	// 使用保守语义：多个同类buff只取最强效果，避免数值膨胀
	var childBuffs:Array = [
		new PodBuff("空手攻击力", BuffCalculationType.ADD_POSITIVE, 技能空手攻击力加成),
		new PodBuff("行走X速度", BuffCalculationType.MULT_POSITIVE, 技能速度倍率)
	];

	// 无时间限制（场景有效）
	var components:Array = [];

	var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);
	target.buffManager.addBuff(metaBuff, "兴奋剂");
	if(target._name == _root.控制目标){
		_root.发布消息("已注射兴奋剂，移动速度提升,一个场景内有效。");
	}

	return true;
};

/**
 * 铁布衫释放 - 通过 BuffManager 提升防御力
 *
 * @param target Object 目标单位
 * @param 技能等级 Number 技能等级 (1-10)
 * @return Boolean 是否成功释放
 *
 * 效果：
 *   - 防御力倍率 = 0.99 + 0.08×技能等级 + min(内力/7000, 0.1)
 *   - 实际加成比例 = -1 + 8×技能等级 + floor(min(内力/70, 10)) %
 *   - 使用固定ID添加buff，重复使用会替换而非叠加
 */
_root.技能函数.铁布衫释放 = function(target:Object, 技能等级:Number):Boolean {
	if (!target) return false;

	// 计算防御力加成倍率
	var 技能防御力加成:Number = 0.99 + 0.08 * 技能等级 + Math.min(target.内力 / 7000, 0.1);

	// 通过 BuffManager 设置防御力加成（使用保守语义，多个防御buff只取最强效果）
	var podBuff:PodBuff = new PodBuff(
		"防御力",                           // 目标属性
		BuffCalculationType.MULT_POSITIVE, // 保守乘算：多个增益取max
		技能防御力加成                        // 倍率值
	);

	var metaBuff:MetaBuff = new MetaBuff(
		[podBuff],  // 子 PodBuff 数组
		[],         // 无组件（永久生效）
		0           // 优先级
	);

	// 使用 addBuffImmediate 立即应用，以便后续播报正确的防御力值
	target.buffManager.addBuffImmediate(metaBuff, "铁布衫");

	// 计算并显示加成比例
	var 加成比例:Number = -1 + 8 * 技能等级 + Math.floor(Math.min(target.内力 / 60, 11));
	if(target._name == _root.控制目标){
		_root.发布消息("防御力上升" + 加成比例 + "%！目前防御力为" + Math.floor(target.防御力) + "点！");
	}

	return true;
};

_root.技能函数.铁布衫护盾释放 = function(target:Object):Boolean {

	if(target.被动技能.内力爆发 && target.被动技能.内力爆发.启用 && target.被动技能.内力爆发.等级 >=1 && target.mp >= 30){
		target.mp -= 30;
		var 技能等级 = target.被动技能.内力爆发.等级;
		if (target.铁布衫护盾ID != undefined) {
			// 注意顺序：先保存ID，再回滚状态（回滚会清空ID），最后用保存的ID移除护盾
			var 旧护盾ID:Number = target.铁布衫护盾ID;
			target.shield.removeShieldById(旧护盾ID);
		}
		// === 参数计算 ===
		var 持续帧数:Number = 30 + 技能等级 * 6;  // 转换为帧数（30fps）

		var 护盾容量:Number = target.mp / 4 + target.内力;
		var 护盾强度:Number = target.内力 * (技能等级 * 0.1 + 1) / 2;

		var 当前护盾ID:Number = _root.护盾函数.添加临时护盾(target, 护盾容量, 护盾强度, 持续帧数, "铁布衫护盾");


		// 记录护盾ID
		target.铁布衫护盾ID = 当前护盾ID;

		return true;
	}else{
		return true;
	}
};


_root.技能函数.龟派气功护盾释放 = function(target:Object, 技能等级:Number):Boolean {
	if (target.龟派气功护盾ID != undefined) {
		// 注意顺序：先保存ID，再回滚状态（回滚会清空ID），最后用保存的ID移除护盾
		var 旧护盾ID:Number = target.龟派气功护盾ID;
		target.shield.removeShieldById(旧护盾ID);
	}

	// === 参数计算 ===
	var 持续帧数:Number = 20;  // 转换为帧数（30fps）

	var 护盾容量:Number = (target.mp满血值 + target.内力 * 技能等级) * (循环次数 + 1) / 50;
	var 护盾强度:Number = (target.mp满血值 + target.内力 * 技能等级) * (循环次数 + 1) / 100;
	// var 当前护盾ID:Number = _root.护盾函数.添加临时护盾(target, 护盾容量, 护盾强度, 持续帧数, "龟派气功护盾", {
	// 	onBreak: function(shield):Void {
	// 		//_root.发布消息("能量盾效果结束");
	// 	}
	// });
	var 当前护盾ID:Number = _root.护盾函数.添加临时护盾(target, 护盾容量, 护盾强度, 持续帧数, "龟派气功护盾");
	//替换掉 添加抗真伤护盾

	// 记录护盾ID
	target.龟派气功护盾ID = 当前护盾ID;

	return true;
};


_root.技能函数.扭转乾坤护盾释放 = function(target:Object, 技能等级:Number):Boolean {
	if (target.扭转乾坤护盾ID != undefined) {
		// 注意顺序：先保存ID，再获取护盾对象，读取剩余容量，最后移除护盾
		
		var 旧护盾ID:Number = target.扭转乾坤护盾ID;
		var 护盾对象:Object = target.shield.getShieldById(旧护盾ID);
		
		if (护盾对象 != null) {
			// 移除前读取剩余容量
			var 剩余容量:Number = 护盾对象.getCapacity();
			// 计算实际承伤量 = 总容量 - 剩余容量
			target.man.扭转乾坤护盾承伤量 = target.man.扭转乾坤护盾容量 - 剩余容量;
			target.man.许可 = false;
		}
		
		// 移除护盾
		target.shield.removeShieldById(旧护盾ID);
	}

	// === 参数计算 ===
	var 持续帧数:Number = 50 + 技能等级 * 12;  // 转换为帧数（30fps）

	var 护盾容量:Number = target.hp满血值 * (5 + 技能等级)/30 +  target.mp满血值 + target.内力 * 技能等级;
	var 护盾强度:Number = 99999999;
	target.man.扭转乾坤护盾容量 = 护盾容量;
	
	// 创建护盾时记录onExpire回调
	var 当前护盾ID:Number = _root.护盾函数.添加抗真伤护盾(target, 护盾容量, 护盾强度, 持续帧数, "扭转乾坤护盾", {
		onBreak: function(shield):Void {
			if(target.man.扭转乾坤护盾容量){
				target.man.扭转乾坤护盾承伤量 = target.man.扭转乾坤护盾容量;
			}
			target.man.许可 = false;
		},
		onExpire: function(shield):Void {
			// 时间到期时，读取剩余容量并计算承伤量
			var 剩余容量:Number = shield.getCapacity();
			target.man.扭转乾坤护盾承伤量 = target.man.扭转乾坤护盾容量 - 剩余容量;
			target.man.许可 = false;
		}
	});

	// 记录护盾ID
	target.扭转乾坤护盾ID = 当前护盾ID;

	return true;
};

_root.技能函数.扭转乾坤恢复 = function(扭转乾坤护盾承伤量:Number, 技能等级:Number):Boolean {
	if(扭转乾坤护盾承伤量 && 技能等级 && _parent.hp > 0){
		var mp恢复量 = Math.ceil(扭转乾坤护盾承伤量 * (0.05 + 0.005 * 技能等级 + Math.min(_parent.内力/7000,0.15)));
		if(_parent.mp + mp恢复量 >= _parent.mp满血值){
			_parent.mp = Math.ceil(_parent.mp满血值);
		}else{
			_parent.mp += mp恢复量;
		}
		var hp恢复量 = Math.ceil(扭转乾坤护盾承伤量 * (0.1 + 0.01 * 技能等级+ Math.min(_parent.内力/7000,0.05)));
		if(_parent.hp + hp恢复量 >= _parent.hp满血值 * 1.5){
			_parent.hp = Math.ceil(_parent.hp满血值 * 1.5);
		}else{
			_parent.hp += hp恢复量;
		}
	}
	return true;
}

// ============================================================================
// 升龙拳浮空逻辑（从 XML 迁移，方便调试）
// ============================================================================

/**
 * 升龙拳浮空初始化（原始版本，使用 onEnterFrame）
 * @param man:MovieClip 技能容器 man
 * @param unit:MovieClip 单位
 */
_root.技能函数.升龙拳浮空初始化_原始 = function(man:MovieClip, unit:MovieClip):Void {
	if (!unit.技能浮空 && !unit.浮空) {
		unit.起始Y = unit.Z轴坐标;
		unit.temp_y = unit._y;
		unit.技能浮空 = true;
		man.落地 = false;
		unit.浮空 = true;
		if (!unit.跳跃中移动速度) {
			unit.跳跃中移动速度 = unit.行走X速度;
		}
		if (!unit.跳横移速度) {
			unit.跳横移速度 = unit.行走X速度;
		}
		man.onEnterFrame = function() {
			unit._y += unit.垂直速度;
			unit.temp_y = unit._y;
			unit.垂直速度 += _root.重力加速度;

			if (unit._y >= unit.Z轴坐标) {
				unit._y = unit.Z轴坐标;
				unit.temp_y = unit._y;
				this.落地 = true;
				unit.浮空 = false;
				unit.技能浮空 = false;
				delete this.onEnterFrame;
			}
		};
	}
};

/**
 * 升龙拳浮空初始化（空中控制器版本）
 * @param man:MovieClip 技能容器 man
 * @param unit:MovieClip 单位
 */
_root.技能函数.升龙拳浮空初始化_控制器 = function(man:MovieClip, unit:MovieClip):Void {
	// 地面触发时：可能残留了 浮空/技能浮空 标记，导致初始化被跳过（表现为“偶发不升空”）
	// 这里用“贴地判定”强制重置一次，保证升龙拳稳定获得上升阶段。
	var z:Number = unit.Z轴坐标;
	var onGround:Boolean = (!isNaN(z) && unit._y >= z - 0.5);
	if (onGround) {
		unit.技能浮空 = false;
		unit.浮空 = false;
		delete unit.__preserveFloatFlagOnUnload;
	}

	if (!unit.技能浮空 && !unit.浮空) {
		unit.起始Y = unit.Z轴坐标;
		unit.temp_y = unit._y;
		// 保底：如果本帧没有被容器帧脚本写入垂直速度，先给一个起跳速度，避免“原地不动”
		// （容器帧上若设置了更强的垂直速度，会在本帧/后续帧覆盖这里的值）
		if (onGround && (isNaN(unit.垂直速度) || unit.垂直速度 >= 0)) {
			unit.垂直速度 = unit.起跳速度;
		}
		unit.技能浮空 = true;
		man.落地 = false;
		unit.浮空 = true;
		if (!unit.跳跃中移动速度) {
			unit.跳跃中移动速度 = unit.行走X速度;
		}
		if (!unit.跳横移速度) {
			unit.跳横移速度 = unit.行走X速度;
		}
		// 使用空中控制器统一处理重力
		_root.空中控制器.启用技能浮空(unit, "技能浮空", man);
	}
};

/**
 * 升龙拳浮空初始化（当前使用版本）
 * 切换此函数指向可快速切换两种实现
 */
_root.技能函数.升龙拳浮空初始化 = _root.技能函数.升龙拳浮空初始化_控制器;


_root.技能函数.移动射击释放 =  function(){
	if(_parent.技能等级 >= 10){
		_parent.上下移动射击 = !_parent.上下移动射击;
	}else{
		_parent.上下移动射击 = true;
		var 持续时间 = 10000 + 1000 * _parent.技能等级;
		_root.帧计时器.添加或更新任务(_parent,"主角上下移动射击",function ()
		{
			//_root.gameworld[自机].上下移动射击 = false;
			_root.gameworld[this._name].上下移动射击 = false;
		},持续时间);
	}
}