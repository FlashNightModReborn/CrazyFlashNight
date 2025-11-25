import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.unit.Action.Skill.*;

_root.技能函数.轻型武器攻击搓招 = function() {
    var 自机 = _parent;
    
	if(自机.被动技能.下劈 && 自机.被动技能.下劈.等级 >= 1)
	{
		if(Key.isDown(_root.奔跑键) && 自机.下行 && 自机.动作A)//Shift下J
		{gotoAndPlay("蓄力重劈");}
	}

    if (自机.被动技能.刀剑攻击 && 自机.被动技能.刀剑攻击.启用) {
        if (自机.方向 == "右")
		{
            // 下右J 搓招（等级≥3 + 下+右+动作A）
            if (自机.被动技能.刀剑攻击.等级 >= 3 && 自机.下行 && 自机.右行 && 自机.动作A)
			{gotoAndPlay("剑气释放");}

            // 左J 搓招（等级≥1 + 下+左+动作A）
            if (自机.被动技能.上挑.等级 >= 1 && 自机.左行 && 自机.动作A)
			{gotoAndPlay("十六夜月华");}

            // 双击右键搓招
            if (自机.doubleTapRunDirection == 1)
			{gotoAndPlay("百万突刺"); }
		}
		else if (自机.方向 == "左")
		{
            // 下左J 搓招（等级≥3 + 下+左+动作A）
            if (自机.被动技能.刀剑攻击.等级 >= 3 && 自机.下行 && 自机.左行 && 自机.动作A)
			{gotoAndPlay("剑气释放");}

            // 右J 搓招（等级≥1 + 下+右+动作A）
            if (自机.被动技能.上挑.等级 >= 1 && 自机.右行 && 自机.动作A)
			{gotoAndPlay("十六夜月华");}

            // 双击左键搓招
            if (自机.doubleTapRunDirection == -1)
			{gotoAndPlay("百万突刺");}
        }
    }
	if (!自机.飞行浮空 && 自机.动作B)
	{自机.状态改变("兵器跳");}
};
_root.技能函数.大型武器攻击搓招 = function() {
    var 自机 = _parent;
    
	if(自机.被动技能.下劈 && 自机.被动技能.下劈.等级 >= 1)
	{
		if(Key.isDown(_root.奔跑键) && 自机.下行 && 自机.动作A)//Shift下J
		{gotoAndPlay("蓄力重劈");}
	}

    if (自机.被动技能.刀剑攻击 && 自机.被动技能.刀剑攻击.启用) {
        if (自机.方向 == "右")
		{
            // 下右J 搓招（等级≥1 + 下+右+动作A）
            if (自机.被动技能.刀剑攻击.等级 >= 1 && 自机.下行 && 自机.右行 && 自机.动作A)
			{gotoAndPlay("飞沙走石");}

            // 左J 搓招（等级≥1 + 左+动作A）
            if (自机.被动技能.上挑.等级 >= 1 && 自机.左行 && 自机.动作A)
			{gotoAndPlay("十六夜月华");}
			
            // 双击右键搓招
            if (自机.doubleTapRunDirection == 1)
			{gotoAndPlay("百万突刺"); }
		}
		else if (自机.方向 == "左")
		{
            // 下左J 搓招（等级≥1 + 下+左+动作A）
            if (自机.被动技能.刀剑攻击.等级 >= 1 && 自机.下行 && 自机.左行 && 自机.动作A)
			{gotoAndPlay("飞沙走石");}

            // 右J 搓招（等级≥1 + 右+动作A）
            if (自机.被动技能.上挑.等级 >= 1 && 自机.右行 && 自机.动作A)
			{gotoAndPlay("十六夜月华");}

            // 双击左键搓招
            if (自机.doubleTapRunDirection == -1)
			{gotoAndPlay("百万突刺");}
        }
    }
	if (!自机.飞行浮空 && 自机.动作B)
	{自机.状态改变("兵器跳");}
};

_root.技能函数.剑气释放搓招窗口 = function() {
    var 自机 = _parent;

	if(自机.被动技能.下劈 && 自机.被动技能.下劈.等级 >= 1)
	{
		if(Key.isDown(_root.奔跑键) && 自机.下行 && 自机.动作A)//Shift下J
		{gotoAndPlay("蓄力重劈");}
	}
	if(自机.方向 == "右")
	{
		// 左J
		if(自机.被动技能.上挑.等级 >= 1 && 自机.左行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}
		// 双击右键
		if(自机.doubleTapRunDirection == 1)
		{gotoAndPlay("百万突刺");}
	}
	else if(自机.方向 == "左")
	{
		// 右J
		if(自机.被动技能.上挑.等级 >= 1 && 自机.右行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}
		// 双击左键
		if(自机.doubleTapRunDirection == -1)
		{gotoAndPlay("百万突刺");}
	}
	if (!自机.飞行浮空 && 自机.动作B)
	{自机.状态改变("兵器跳");}
};

_root.技能函数.飞沙走石搓招窗口 = function() {
    var 自机 = _parent;

	if(自机.被动技能.下劈 && 自机.被动技能.下劈.等级 >= 1)
	{
		if(Key.isDown(_root.奔跑键) && 自机.下行 && 自机.动作A)//Shift下J
		{gotoAndPlay("蓄力重劈");}
	}
	if(自机.方向 == "右")
	{
		// 左J
		if(自机.被动技能.上挑.等级 >= 1 && 自机.左行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}
		// 双击右键
		if(自机.doubleTapRunDirection == 1)
		{gotoAndPlay("百万突刺");}
	}
	else if(自机.方向 == "左")
	{
		// 右J
		if(自机.被动技能.上挑.等级 >= 1 && 自机.右行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}
		// 双击左键
		if(自机.doubleTapRunDirection == -1)
		{gotoAndPlay("百万突刺");}
	}
	if (!自机.飞行浮空 && 自机.动作B)
	{自机.状态改变("兵器跳");}
};

_root.技能函数.百万突刺搓招窗口 = function(){
    var 自机 = _parent;
	
	//下劈派生
	if(自机.被动技能.下劈 && 自机.被动技能.下劈.等级 >= 1)
	{
		if(Key.isDown(_root.奔跑键) && 自机.下行 && 自机.动作A)//Shift下J
		{gotoAndPlay("蓄力重劈");}
	}
	//方向派生
	if(自机.方向 == "右")
	{
		// 下左J
		if(自机.被动技能.上挑.等级 >= 1 && 自机.左行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}

		//下右J
		if(自机.下行 && 自机.右行 && 自机.动作A)
		{
			if(自机.兵器动作类型=="长柄" || 自机.兵器动作类型=="长枪" || 自机.兵器动作类型=="长棍" || 自机.兵器动作类型=="狂野")
			{gotoAndPlay("飞沙走石");}
			else if (自机.被动技能.刀剑攻击.等级 >= 3)
			{gotoAndPlay("剑气释放");}
		}
		if(自机.doubleTapRunDirection == 1)//双击右键
		{自机.状态改变("兵器跑");}
	}
	else if(自机.方向 == "左")
	{
		// 下右J
		if(自机.被动技能.上挑.等级 >= 1 && 自机.右行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}
		
		// 下左J
		if(自机.下行 && 自机.左行 && 自机.动作A)
		{
			if(自机.兵器动作类型=="长柄" || 自机.兵器动作类型=="长枪" || 自机.兵器动作类型=="长棍" || 自机.兵器动作类型=="狂野")
			{gotoAndPlay("飞沙走石");}
			else if (自机.被动技能.刀剑攻击.等级 >= 3)
			{gotoAndPlay("剑气释放");}
		}
		if(自机.doubleTapRunDirection == -1)//双击左键
		{自机.状态改变("兵器跑");}
	}
	if (!自机.飞行浮空 && 自机.动作B)
	{自机.状态改变("兵器跳");}
}
_root.技能函数.蓄力重劈搓招窗口 = function(){
    var 自机 = _parent;
	
	if (自机.方向 == "右")
	{// 双击右键搓招
		if (自机.doubleTapRunDirection == 1)
		{gotoAndPlay("百万突刺");}
		
		// 左J  
		if (自机.被动技能.上挑.等级 >= 1 && 自机.左行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}
		
		// 下右J  
		if (自机.下行 && 自机.右行 && 自机.动作A)
		{
			if (自机.兵器动作类型 == "长柄" || 自机.兵器动作类型 == "长枪" || 自机.兵器动作类型 == "长棍" || 自机.兵器动作类型 == "狂野")
			{gotoAndPlay("飞沙走石");}
			else if (自机.被动技能.刀剑攻击 >= 3)
			{gotoAndPlay("剑气释放");}
		}
	}
	else if (自机.方向 == "左")
	{// 双击左键搓招
		if (自机.doubleTapRunDirection == -1)
		{gotoAndPlay("百万突刺");}
		
		// 右J  
		if (自机.被动技能.上挑.等级 >= 1 && 自机.右行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}
		
		// 下左J  
		if (自机.下行 && 自机.左行 && 自机.动作A)
		{
			if (自机.兵器动作类型 == "长柄" || 自机.兵器动作类型 == "长枪" || 自机.兵器动作类型 == "长棍" || 自机.兵器动作类型 == "狂野")
			{gotoAndPlay("飞沙走石");}
			else if (自机.被动技能.刀剑攻击 >= 3)
			{gotoAndPlay("剑气释放");}
		}
	}
	if (!自机.飞行浮空 && 自机.动作B)
	{自机.状态改变("兵器跳");}
};

_root.技能函数.十六夜月华可派生 = function(){
    var 自机 = _parent;
	
	//下劈派生
	if(自机.被动技能.下劈 && 自机.被动技能.下劈.等级 >= 1)
	{
		if(Key.isDown(_root.奔跑键) && 自机.下行 && 自机.动作A)//Shift下J
		{gotoAndPlay("蓄力重劈");}
	}

	if (自机.方向 == "右")
	{// 双击右键搓招
		if (自机.doubleTapRunDirection == 1)
		{gotoAndPlay("百万突刺");}
		
		// 左J  
		if (自机.被动技能.上挑.等级 >= 1 && 自机.左行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}
		
		// 下右J  
		if (自机.下行 && 自机.右行 && 自机.动作A)
		{
			if(自机.兵器动作类型=="长柄" || 自机.兵器动作类型=="长枪" || 自机.兵器动作类型=="长棍" || 自机.兵器动作类型=="狂野")
			{gotoAndPlay("飞沙走石");}
			else if (自机.被动技能.刀剑攻击 >= 3)
			{gotoAndPlay("剑气释放");}
		}
	}
	else if (自机.方向 == "左")
	{// 双击左键搓招
		if (自机.doubleTapRunDirection == -1)
		{gotoAndPlay("百万突刺");}
		
		// 右J  
		if (自机.被动技能.上挑.等级 >= 1 && 自机.右行 && 自机.动作A)
		{gotoAndPlay("十六夜月华");}
		
		// 下左J  
		if (自机.下行 && 自机.左行 && 自机.动作A)
		{
			if(自机.兵器动作类型=="长柄" || 自机.兵器动作类型=="长枪" || 自机.兵器动作类型=="长棍" || 自机.兵器动作类型=="狂野")
			{gotoAndPlay("飞沙走石");}
			else if (自机.被动技能.刀剑攻击 >= 3)
			{gotoAndPlay("剑气释放");}
		}
	}
	if (!自机.飞行浮空 && 自机.动作B)
	{自机.状态改变("兵器跳");}
};
