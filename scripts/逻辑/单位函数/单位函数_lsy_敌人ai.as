import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.敌人ai函数 = new Object();

_root.敌人ai函数.思考 = function()
{
	if (_root.暂停)
	{
		gotoAndPlay(_parent.命令);
		return;
	}
	if (_root.控制目标 == _parent._name and _root.控制目标全自动 == false)
	{
		this.gotoAndPlay("不思考");
		return;
	}

	_parent.命令 = _root.命令;
	if (_parent.攻击模式 === "空手")
	{
		_parent.x轴攻击范围 = 100;
		_parent.y轴攻击范围 = 10;
		_parent.x轴保持距离 = 100;
	}
	// else if (_parent.攻击模式 == "兵器")
	// {
	// 	_parent.x轴攻击范围 = 200;
	// 	_parent.y轴攻击范围 = 10;
	// 	_parent.x轴保持距离 = 150;
	// }
	// else if (_parent.攻击模式 == "长枪" || _parent.攻击模式 == "手枪" || _parent.攻击模式 == "手枪2" || _parent.攻击模式 == "双枪")
	// {
	// 	_parent.x轴攻击范围 = 400;
	// 	_parent.y轴攻击范围 = 10;
	// 	_parent.x轴保持距离 = 200;
	// }
	// else if (_parent.攻击模式 == "手雷")
	// {
	// 	_parent.x轴攻击范围 = 300;
	// 	_parent.y轴攻击范围 = 10;
	// 	_parent.x轴保持距离 = 200;
	// }
	寻找攻击目标();
	if (_parent.是否为敌人 == false)
	{
		if (_root.集中攻击目标 === "无")
		{
			if (_parent.攻击目标 === "无")
			{
				_parent.移动目标 = _root.控制目标;
				gotoAndPlay(_parent.命令);
			}
			else
			{
				gotoAndPlay("攻击");
			}
		}
		else
		{
			_parent.dispatcher.publish("aggroSet", _parent, _root.gameworld[_root.集中攻击目标]);
			gotoAndPlay("攻击");
		}
	}
	else if (_parent.是否为敌人 == true)
	{
		if (_parent.攻击目标 === "无")
		{
			_parent.移动目标 = _root.控制目标;
			gotoAndPlay("跟随");
		}
		else
		{
			gotoAndPlay("攻击");
		}
	}
}

_root.敌人ai函数.攻击 = function(x轴攻击范围, y轴攻击范围, x轴保持距离)
{
	if (_root.暂停)
	{
		_parent.左行 = 0;
		_parent.右行 = 0;
		_parent.上行 = 0;
		_parent.下行 = 0;
		return;
	}

	var 攻击对象 = _root.gameworld[_parent.攻击目标];
	if (Math.abs(_parent._y - 攻击对象.Z轴坐标) > y轴攻击范围 || Math.abs(_parent._x - 攻击对象._x) > x轴攻击范围)
	{
		if (random(_parent.停止机率) == 0)
		{
			gotoAndPlay("停止");
		}
		else if (random(_parent.随机移动机率) == 0)
		{
			gotoAndPlay("随机移动");
		}
		else
		{
			if (random(3) == 0)
			{
				_parent.状态改变(_parent.攻击模式 + "跑");
			}
			if (_parent._y > 攻击对象.Z轴坐标)
			{
				_parent.上行 = 1;
				_parent.下行 = 0;
			}
			else
			{
				_parent.上行 = 0;
				_parent.下行 = 1;
			}
			if (_parent._x > 攻击对象._x + x轴保持距离)
			{
				_parent.左行 = 1;
				_parent.右行 = 0;
			}
			else if (_parent._x < 攻击对象._x - x轴保持距离)
			{
				_parent.左行 = 0;
				_parent.右行 = 1;
			}
		}
	}
	else
	{
		_parent.左行 = 0;
		_parent.右行 = 0;
		_parent.上行 = 0;
		_parent.下行 = 0;
		if (_parent._x > 攻击对象._x)
		{
			_parent.方向改变("左");
		}
		else if (_parent._x < 攻击对象._x)
		{
			_parent.方向改变("右");
		}
		_parent.状态改变(_parent.攻击模式 + "攻击");
		// 使用 !(hp > 0) 可同时处理 undefined/NaN/<=0 的情况
		if (!(攻击对象.hp > 0))
		{
			_parent.dispatcher.publish("aggroClear", _parent);
		}
	}
}

_root.敌人ai函数.寻找攻击目标 = function() {
    // 如果没有攻击目标，或者当前目标已死亡/被删除，则寻找新目标
    // 使用 !(hp > 0) 可同时处理 undefined/NaN/<=0 的情况
    if (_parent.攻击目标 === "无" || (_parent.攻击目标 !== "无" && !(_root.gameworld[_parent.攻击目标].hp > 0))) {
        // 直接使用TargetCacheManager的findNearestEnemy方法查找X轴上最近的敌人
        var enemy = TargetCacheManager.findNearestEnemy(_parent, 5);

        // 设置攻击目标
        if (enemy) {
            _parent.dispatcher.publish("aggroSet", _parent, enemy);
        } else {
            _parent.dispatcher.publish("aggroClear", _parent);
        }
    }
};


//敌人佣兵
_root.敌人ai函数.思考_佣兵 = function()
{
	if(_parent.移动目标 && _parent.移动目标 !== "无"){
		if(_root.gameworld[_parent.移动目标].hitTest(_parent.area))
		{
			_parent.removeMovieClip();
			_root.gameworld.可雇用敌人在场数量--;
			return;
		}
	}else{
		var 目标名单 = [];
		for (var each in _root.gameworld)
		{
			var 对象 = _root.gameworld[each];
			if (对象.是否从门加载主角 && each != "出生地") 目标名单.push(对象._name);
		}
		_parent.移动目标 = 目标名单[random(目标名单.length)];
	}

	var 命令 = random(5);
	switch (命令){
		case 0 :
		case 1 :
			break;
		case 2 :
			_parent.命令 = "停止";
			break;
		case 3 :
			_parent.命令 = "跟随";
			break;
		case 4 :
			_parent.命令 = "跟随";
	}
	gotoAndPlay(_parent.命令);
}


//初始化
_root.初始化敌人ai = function(){
	if(_parent.佣兵数据){
		this.思考 = _root.敌人ai函数.思考_佣兵;
		_parent.命令 = "停止";
		_parent.dispatcher.publish("aggroClear", _parent);
		_parent.移动目标 = "无";
		return;
	}
	this.思考 = _root.敌人ai函数.思考;
	this.攻击 = _root.敌人ai函数.攻击;
	this.寻找攻击目标 = _root.敌人ai函数.寻找攻击目标;
	this.随机移动 = _root.敌人ai函数.随机移动;
}


_root.初始化思考标签 = function(target){
	target._name = "思考标签";
	target.stop();
	target._visible = false;
}
// _root.初始化思考标签(this);
