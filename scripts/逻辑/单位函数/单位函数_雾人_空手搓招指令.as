import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.unit.Action.Skill.*;

_root.技能函数.空手攻击搓招 = function() {
	var 自机 = _parent;
	var 能量喷泉所需MP = 自机.mp满血值 * 0.1;
	if(自机.被动技能.裂地拳 && 自机.被动技能.裂地拳.等级 >= 1 && 自机.mp >= 能量喷泉所需MP)
	{
		if(自机.下行 && 自机.动作B)//下K
		{gotoAndPlay("能量喷泉1段");}
	}
	// 双击方向键后触发
	if(自机.方向 == "右")
	{
		if(自机.被动技能.拳脚攻击 && 自机.被动技能.拳脚攻击.启用)
		{
			if (自机.doubleTapRunDirection == 1) //双击右键
			{gotoAndPlay("诛杀步");}
			if (Key.isDown(_root.奔跑键) && 自机.左行)//Shift + 左键
			{gotoAndPlay("后撤步");}
				
			if(自机.被动技能.拳脚攻击.等级 >= 5)
			{
				if(自机.下行 && 自机.右行 && 自机.动作A)//下右J
				{gotoAndPlay("波动拳");}
			}
		}
	}
	else if(自机.方向 == "左")
	{
		if(自机.被动技能.拳脚攻击 && 自机.被动技能.拳脚攻击.启用)
		{
			if (自机.doubleTapRunDirection == -1)//双击左键
			{_parent.gotoAndPlay("诛杀步");}
			if (Key.isDown(_root.奔跑键) && 自机.右行)//Shift + 右键
			{gotoAndPlay("后撤步");}
				
			if(自机.被动技能.拳脚攻击.等级 >= 5)
			{
				if(自机.下行 && 自机.左行 && 自机.动作A)//下左J
				{gotoAndPlay("波动拳");}
			}
		}
	}
};

_root.技能函数.波动拳可派生搓招 = function() {
	var 自机 = _parent;
	var 能量喷泉所需MP = 自机.mp满血值 * 0.1;
	if(自机.被动技能.裂地拳 && 自机.被动技能.裂地拳.等级 >= 1 && 自机.mp >= 能量喷泉所需MP)
	{
		if(自机.下行 && 自机.动作B)//下K
		{gotoAndPlay("能量喷泉1段");}
	}
	// 双击方向键后触发
	if(自机.方向 == "右")
	{
		if(自机.被动技能.拳脚攻击 && 自机.被动技能.拳脚攻击.启用)
		{
			if (自机.doubleTapRunDirection == 1) //双击右键
			{gotoAndPlay("诛杀步");}
			if (Key.isDown(_root.奔跑键) && 自机.左行)//Shift + 左键
			{gotoAndPlay("后撤步");}
		}
	}
	else if(自机.方向 == "左")
	{
		if(自机.被动技能.拳脚攻击 && 自机.被动技能.拳脚攻击.启用)
		{
			if (自机.doubleTapRunDirection == -1)//双击左键
			{_parent.gotoAndPlay("诛杀步");}
			if (Key.isDown(_root.奔跑键) && 自机.右行)//Shift + 右键
			{gotoAndPlay("后撤步");}
		}
	}
};


_root.技能函数.诛杀步可派生搓招 = function() {
	var 自机 = _parent;
	
	
};
_root.技能函数.后撤步可派生搓招 = function() {
	var 自机 = _parent;
	
	
};