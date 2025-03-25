import org.flashNight.naki.RandomNumberEngine.*;

_root.佣兵思考时间间隔 = 1.5 * _root.帧计时器.帧率;


_root.主角模板ai函数 = new Object();

_root.主角模板ai函数.思考 = function()
{
	if (_root.暂停)
	{
		gotoAndPlay(_parent.命令);
		return;
	}
	if (_parent.hp <= 0)
	{
		if (_root.血腥开关 == false)
		{
			_parent.状态改变("击倒");
		}
		else
		{
			_parent.状态改变("血腥死");
		}
		return;
	}
	if (_parent.操控编号 != -1 and _root.控制目标全自动 == false)
	{
		this.gotoAndPlay("不思考");
		return;
	}
	_parent.随机切换攻击模式();
	var 游戏世界 = _root.gameworld;

	_parent.命令 = _root.命令;
	switch (_parent.攻击模式)
	{
		case "空手" :
			_parent.x轴攻击范围 = 90;
			_parent.y轴攻击范围 = 20;
			_parent.x轴保持距离 = 100;
			break;
		case "兵器" :
			_parent.x轴攻击范围 = 150;
			_parent.y轴攻击范围 = 20;
			_parent.x轴保持距离 = 150;
			break;
		case "长枪" :
		case "手枪" :
		case "手枪2" :
		case "双枪" :
			_parent.x轴攻击范围 = 400;
			_parent.y轴攻击范围 = 20;
			_parent.x轴保持距离 = 200;
			break;
		case "手雷" :
			_parent.x轴攻击范围 = 300;
			_parent.y轴攻击范围 = 10;
			_parent.x轴保持距离 = 200;
			break;
		default :// 写了再说
			break;
	}//使用血包流程，血量越低使用血包概率越高
	var 当前时间:Number = _root.帧计时器.当前帧数;
	if (_parent.血包数量 > 0 and 当前时间 - _parent.上次使用血包时间 > _parent.血包使用间隔)
	{
		var 自机肉度 = _parent.hp / _root.防御减伤比(_parent.防御力);
		var 敌机肉度 = 游戏世界[_parent.攻击目标].hp / _root.防御减伤比(游戏世界[_parent.攻击目标].防御力);
		敌机肉度 = isNaN(敌机肉度) ? 自机肉度 / 5 : 敌机肉度;
		var 强弱修正系数 = 敌机肉度 / 自机肉度;
		var 喝血系数 = 100 + 强弱修正系数 * 2 - _parent.血包恢复比例 * (100 - _parent.血包恢复比例) / 100;
		var 损血补正:Number = _parent.hp满血值 * 喝血系数 / 100;
		var 使用血包概率 = Math.min((损血补正 - _parent.hp) * 100 / _parent.hp满血值 * 强弱修正系数, 喝血系数);//_root.发布调试消息("使用血包概率为 " + 使用血包概率 +"  损血补正 " + 损血补正 + "自机肉度" + 自机肉度 + "敌机肉度" + 敌机肉度);
		if (_root.成功率(使用血包概率) and _parent.hp满血值 > _parent.hp * (100 + _parent.血包恢复比例 / 8) / 100 or (游戏世界.允许通行 and _parent.hp满血值 > _parent.hp))
		{
			_parent.血包数量 -= 1;
			var 佣兵血量缓存:Number = _parent.hp;
			_root.佣兵使用血包(_parent._name);
			_parent.上次使用血包时间 = 当前时间;
			_root.发布消息(_parent.名字 + "[" + 佣兵血量缓存 + "/" + _parent.hp满血值 + "] 紧急治疗后还剩[" + _parent.血包数量 + "]个治疗包");
		}
	}


	_parent.攻击目标 = "无";
	寻找攻击目标();
	if (_parent.是否为敌人 == false)
	{
		if (_root.集中攻击目标 == "无")
		{
			if (_parent.攻击目标 == "无")
			{
				gotoAndPlay(_parent.命令);
			}
			else
			{
				gotoAndStop("攻击");
				play();
			}
		}
		else
		{
			_parent.攻击目标 = _root.集中攻击目标;
			gotoAndStop("攻击");
			play();
		}
	}
	else if (_parent.是否为敌人 == true)
	{
		if (_parent.攻击目标 == "无")
		{
			gotoAndStop("跟随");
			play();
		}
		else
		{
			gotoAndStop("攻击");
			play();
		}
	}
};

_root.主角模板ai函数.攻击 = function(x轴攻击范围, y轴攻击范围, x轴保持距离)
{
	_parent.左行 = false;
	_parent.右行 = false;
	_parent.上行 = false;
	_parent.下行 = false;
	_parent.动作A = false;
	_parent.动作B = false;
	if (_root.暂停) return;
	var 游戏世界 = _root.gameworld;
	var 攻击对象 = 游戏世界[_parent.攻击目标];
	if(!攻击对象._x) return;

	var X轴距离 = Math.abs(_parent._x - 攻击对象._x);
	var Y轴距离 = Math.abs(_parent._y - 攻击对象.Z轴坐标);
	if (Y轴距离 > y轴攻击范围 || X轴距离 > x轴攻击范围)
	{
		if (!_parent.射击中 && !_parent.换弹中 && random(3) === 0)
		{
			_parent.状态改变(_parent.攻击模式 + "跑");
		}
		if (_parent._y > 攻击对象.Z轴坐标)
		{
			_parent.上行 = true;
			_parent.下行 = false;
		}
		else
		{
			_parent.上行 = false;
			_parent.下行 = true;
		}
		if (_parent._x > 攻击对象._x + x轴保持距离)
		{
			_parent.左行 = true;
			_parent.右行 = false;
		}
		else if (_parent._x < 攻击对象._x - x轴保持距离)
		{
			_parent.左行 = false;
			_parent.右行 = true;
		}
	}
	else
	{
		if (_parent._x > 攻击对象._x)
		{
			_parent.方向改变("左");
		}
		else if (_parent._x < 攻击对象._x)
		{
			_parent.方向改变("右");
		}
		var 技能使用概率 = Math.max(60 / X轴距离 * _parent.等级, 20);//距离越近越倾向于使用技能
		if (_parent.名字 == "尾上世莉架")
		{
			技能使用概率 *= 3;
		}
		if (_root.成功率(技能使用概率))
		{
			技能攻击();
		}
		else
		{
			_parent.动作A = true;
			if(_parent.攻击模式 === "双枪") _parent.动作B = true;
		}
		if (攻击对象.hp <= 0 or 攻击对象.hp == undefined)
		{
			_parent.攻击目标 = "无";
		}
	}
};

_root.主角模板ai函数.寻找攻击目标 = function()
{
	_root.寻找攻击目标基础函数(this._parent);
	
	/*
	if (_parent.攻击目标 == "无")
	{
		var 最近的距离:Number = Infinity;
		var 最近的敌人名:String = undefined;
		for (var 待选目标 in 游戏世界)
		{
			var 待检测目标 = 游戏世界[待选目标];
			var 满足筛选条件:Boolean = (_parent.是否为敌人 and !待检测目标.是否为敌人 and 待检测目标.hp > 0) or (!_parent.是否为敌人 and 待检测目标.是否为敌人 and 待检测目标.hp > 0);
			if (满足筛选条件)
			{
				var d = Math.abs(待检测目标._x - _parent._x);
				if (d < 最近的距离)
				{
					最近的距离 = d;
					最近的敌人名 = 待检测目标._name;
				}
			}
		}


		_parent.攻击目标 = 最近的敌人名 ? 最近的敌人名 : "无";
	} */
};

_root.主角模板ai函数.技能攻击 = function()
{
	激发技能 = 根据等级取得随机技能();
	if (激发技能 != undefined and 激发技能 != null)
	{
		_parent.技能名 = 激发技能;
		_parent.状态改变("技能");
	}
};


_root.主角模板ai函数.根据等级取得随机技能 = function() {
    var 当前时间:Number = getTimer();
    var 当前角色 = _parent;
    var 攻击目标 = 当前角色.攻击目标;
    var 游戏世界 = _root.gameworld;
    
    // 防御性检查
    if (!游戏世界[攻击目标] || !游戏世界[攻击目标]._x) return null;

    // 预先计算关键参数
    var 攻击者X:Number = 当前角色._x;
    var 被攻击者X:Number = 游戏世界[攻击目标]._x;
    var X轴距离:Number = Math.abs(攻击者X - 被攻击者X);

    // 使用新抽样方法
    var 候选技能池:Array = LinearCongruentialEngine.getInstance().reservoirSampleWithFilter(
        当前角色.已学技能表,
        1, // 只需1个技能
        function(技能:Object):Boolean {
            // 过滤条件函数封装
            var 距离有效:Boolean = (X轴距离 >= 技能.距离min && X轴距离 <= 技能.距离max);
            var 冷却就绪:Boolean = (isNaN(技能.上次使用时间) || 
                (当前时间 - 技能.上次使用时间 > 技能.冷却 * 1000));
            return 距离有效 && 冷却就绪;
        }
    );

    // 处理抽样结果
    if (候选技能池.length > 0) {
        var 选中技能:Object = 候选技能池[0];
        当前角色.技能等级 = 选中技能.技能等级;
        选中技能.上次使用时间 = 当前时间;
        return 选中技能.技能名;
    }
    return null;
};





_root.初始化主角模板ai = function(){
	if(_parent._name == _root.控制目标){
		this.stop();
		return;
	}
	this.思考 = _root.主角模板ai函数.思考;
	this.攻击 = _root.主角模板ai函数.攻击;
	this.寻找攻击目标 = _root.主角模板ai函数.寻找攻击目标;
	this.技能攻击 = _root.主角模板ai函数.技能攻击;
	this.根据等级取得随机技能 = _root.主角模板ai函数.根据等级取得随机技能;
	this.onUnload = function(){
		_parent.左行 = false;
		_parent.右行 = false;
		_parent.上行 = false;
		_parent.下行 = false;
		_parent.强制奔跑 = false;
		_parent.动作A = false;
		_parent.动作B = false;
		_parent.动作C = false;
	}
}