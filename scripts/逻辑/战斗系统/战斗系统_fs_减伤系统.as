_root.is119 = function(x:Number):Boolean 
{
	return x == _root.闪客之夜;
};

//sigmoid函数
_root.sigmoid = function(x:Number):Number 
{
	return 1 / (1 + Math.exp(-x));
};

//relu函数
_root.relu = function(x:Number):Number 
{
	return Math.max(0, x);
};

//softplus函数
_root.softplus = function(x:Number):Number 
{
	return Math.log(1 + Math.exp(x));
};

//防御计算公式
_root.防御减伤比 = function(防御力:Number):Number 
{
    return 300 / (防御力 + 300);
};


//跳弹模式可以减法过滤掉轻火力，最低伤害为1
_root.跳弹伤害计算 = function(伤害:Number, 防御力:Number):Number 
{
	return Math.max(Math.floor(伤害 - 防御力 / _root.跳弹防御系数), 1);
};

//过穿模式可以二次减伤重火力，最低伤害为1
_root.过穿伤害计算 = function(伤害:Number, 防御力:Number):Number 
{
	return Math.max(Math.floor(伤害 * _root.防御减伤比(防御力)), 1);
};

_root.sig_tyler = function(x:Number):Number 
{
	//_root.发布调试消息(3 * x / 40 + 0.5 - x * x * x / 4000);
	return 3 * x / 40 + 0.5 - x * x * x / 4000;
};//展开节约性能

//计算闪避
_root.躲闪率极限 = 0.01;
_root.命中率极限 = 0.01;
_root.闪避系统闪避率上限 = 0.5 * 100;
_root.基准躲闪率 = 3;
_root.基准命中率 = 10;
_root.根据等级计算闪避率 = function(攻击者等级, 闪避者等级, 躲闪率, 命中率)
{
	//_root.调试模式 = true;
	//_root.发布调试消息(攻击者等级 + " " + 闪避者等级 + " " + 躲闪率 + " " + 命中率);
	;
	if (躲闪率 < 0 or isNaN(躲闪率))
	{
		return 0;
	}
	var 闪避指数 = (闪避者等级 * _root.基准命中率 / 躲闪率 - 攻击者等级 * 命中率 / _root.基准躲闪率) / 40;
	闪避率 = _root.sigmoid(闪避指数) * _root.闪避系统闪避率上限;//通过
	//_root.发布调试消息(闪避率);
	return 闪避率;
};

_root.根据命中计算闪避结果 = function(发射者对象, 命中者对象, 命中率)
{
	//命中未赋值则查找发射者属性
	
	/*
	if (_root.is119(_root.gameworld[命中者].躲闪率))
	{
		//_root.调试模式 = true;
		//_root.发布调试消息("119注视着你");

		return false;
	}
	*/
	var 游戏世界 = _root.gameworld;

	闪避率 = _root.根据等级计算闪避率(发射者对象.等级, 命中者对象.等级, 命中者对象.躲闪率, 命中率);//

	if(isNaN(闪避率))
	{
		发射者对象.等级 = isNaN(发射者对象.等级) ? 1 : 发射者对象.等级; 
		发射者对象.命中率 = isNaN(发射者对象.命中率) ? _root.基准命中率 : 发射者对象.命中率;  
		命中者对象.等级 = isNaN(命中者对象.等级) ? 1 : 命中者对象.等级;  
		命中者对象.躲闪率 = isNaN(命中者对象.躲闪率) ? 999 : 命中者对象.躲闪率;  //规范化数值
		
		闪避率 = _root.根据等级计算闪避率(发射者对象.等级, 命中者对象.等级, 命中者对象.躲闪率, 发射者对象.命中率);
	}

	//_root.发布调试消息(发射者对象.等级 + " " + 发射者对象.命中率 + " " + 命中者对象.等级 + " " + 命中者对象.躲闪率 + " " + 命中率 + " " + 闪避率);
	return _root.成功率(闪避率);
};


//目前已弃用

_root.根据等级计算闪避结果 = function(发射者, 命中者)
{

	if (isNaN(_root.gameworld[发射者].命中率))
	{
		_root.gameworld[发射者].命中率 = 10;
	}
	if (isNaN(_root.gameworld[发射者].等级))
	{
		_root.gameworld[发射者].等级 = 1;
	}
	if (isNaN(_root.gameworld[命中者].等级))
	{
		_root.gameworld[命中者].等级 = 1;
	}
	if (isNaN(_root.gameworld[命中者].躲闪率))
	{
		_root.gameworld[命中者].躲闪率 = 999;
	}
	if (_root.is119(_root.gameworld[命中者].躲闪率))
	{
		//_root.调试模式 = true;
		//_root.发布调试消息("119注视着你");

		return false;
	}


	闪避率 = _root.根据等级计算闪避率(_root.gameworld[发射者].等级, _root.gameworld[命中者].等级, _root.gameworld[命中者].躲闪率, _root.gameworld[发射者].命中率);
	return _root.成功率(闪避率);
};