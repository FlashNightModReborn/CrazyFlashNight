import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.unit.Action.Skill.*;

_root.技能函数.后摇可跳跃 = function() {
	var 自机 = _parent;
	if (!自机.飞行浮空 && 自机.动作B)
	{自机.状态改变("兵器跳");}
};

_root.技能函数.使用剑气释放 = function() {
	var 自机 = _parent;
	if(自机.被动技能.刀剑攻击 && 自机.被动技能.刀剑攻击.等级 >= 3)
	{
		if(自机.方向 == "右")
		{
			if (自机.下行 && 自机.右行 && 自机.动作A)//下右J
			{gotoAndPlay("剑气释放");}
		}
		else if(自机.方向 == "左")
		{
			if (自机.下行 && 自机.左行 && 自机.动作A)//下左J
			{gotoAndPlay("剑气释放");}
		}
	}
};

_root.技能函数.使用飞沙走石 = function() {
	var 自机 = _parent;
	if(自机.被动技能.刀剑攻击 && 自机.被动技能.刀剑攻击.等级 >= 1)
	{
		if(自机.方向 == "右")
		{
			if (自机.下行 && 自机.右行 && 自机.动作A)//下右J
			{gotoAndPlay("飞沙走石");}
		}
		else if(自机.方向 == "左")
		{
			if (自机.下行 && 自机.左行 && 自机.动作A)//下左J
			{gotoAndPlay("飞沙走石");}
		}
	}
};

_root.技能函数.判定剑气或飞沙 = function() {
	var 自机 = _parent;
	if(自机.兵器动作类型=="长柄" || 自机.兵器动作类型=="长枪" || 自机.兵器动作类型=="长棍" || 自机.兵器动作类型=="狂野")
	{_root.技能函数.使用飞沙走石();}
	else
	{_root.技能函数.使用剑气释放();}
};

_root.技能函数.使用百万突刺 = function() {
	var 自机 = _parent;
	if(自机.被动技能.刀剑攻击 && 自机.被动技能.刀剑攻击.等级 >= 1 && 自机.下行 == false)//防止多键按死卡里技
	{
		if(自机.方向 == "右")
		{
			if (自机.doubleTapRunDirection == 1)// 双击右键
			{gotoAndPlay("百万突刺");}
		}
		else if(自机.方向 == "左")
		{
			if (自机.doubleTapRunDirection == -1)//双击左键
			{gotoAndPlay("百万突刺");}
		}
	}
};

_root.技能函数.使用蓄力重劈 = function() {
	var 自机 = _parent;
	if(自机.被动技能.下劈 && 自机.被动技能.下劈.等级 >= 1)
	{
		if(Key.isDown(_root.奔跑键) && 自机.下行 && 自机.动作A)//Shift下J
		{gotoAndPlay("蓄力重劈");}
	}
};

_root.技能函数.使用十六夜月华 = function() {
	var 自机 = _parent;
	if(自机.被动技能.上挑 && 自机.被动技能.上挑.等级 >= 1)//后J
	{
		if(自机.方向 == "右")
		{
			if (自机.左行 && 自机.动作A)//左J
			{gotoAndPlay("十六夜月华");}
		}
		else if(自机.方向 == "左")
		{
			if (自机.右行 && 自机.动作A)//右J
			{gotoAndPlay("十六夜月华");}
		}
	}
};


_root.技能函数.轻型武器攻击搓招 = function() {
    var 自机 = _parent;
	_root.技能函数.使用剑气释放();
	_root.技能函数.使用百万突刺();
	_root.技能函数.使用蓄力重劈();
	_root.技能函数.使用十六夜月华();
	
	_root.技能函数.后摇可跳跃();
};
_root.技能函数.大型武器攻击搓招 = function() {
    var 自机 = _parent;
	_root.技能函数.使用飞沙走石();
	_root.技能函数.使用百万突刺();
	_root.技能函数.使用蓄力重劈();
	_root.技能函数.使用十六夜月华();
	
	_root.技能函数.后摇可跳跃();
};

_root.技能函数.剑气释放搓招窗口 = function() {
    var 自机 = _parent;
	_root.技能函数.使用蓄力重劈();
	_root.技能函数.使用百万突刺();
	_root.技能函数.使用十六夜月华();
	
	_root.技能函数.后摇可跳跃();
};

_root.技能函数.飞沙走石搓招窗口 = function() {
    var 自机 = _parent;
	_root.技能函数.使用蓄力重劈();
	_root.技能函数.使用百万突刺();
	_root.技能函数.使用十六夜月华();
	
	_root.技能函数.后摇可跳跃();
};

_root.技能函数.百万突刺搓招窗口 = function(){
    var 自机 = _parent;
	_root.技能函数.使用蓄力重劈();
	_root.技能函数.使用十六夜月华();
	_root.技能函数.判定剑气或飞沙();
	
	if(自机.方向 == "右" && 自机.doubleTapRunDirection == 1) //双击右键
	{自机.状态改变("兵器跑");}
	if(自机.方向 == "左" && 自机.doubleTapRunDirection == -1)//双击左键
	{自机.状态改变("兵器跑");}
	
	_root.技能函数.后摇可跳跃();
}
_root.技能函数.蓄力重劈搓招窗口 = function(){
    var 自机 = _parent;
	_root.技能函数.使用百万突刺();
	_root.技能函数.使用十六夜月华();
	_root.技能函数.判定剑气或飞沙();
	
	_root.技能函数.后摇可跳跃();
};

_root.技能函数.十六夜月华可派生 = function(){
    var 自机 = _parent;
	_root.技能函数.使用蓄力重劈();
	_root.技能函数.使用百万突刺();
	_root.技能函数.使用十六夜月华();
	_root.技能函数.判定剑气或飞沙();
	
	_root.技能函数.后摇可跳跃();
};
