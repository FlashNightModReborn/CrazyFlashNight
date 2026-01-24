_root.装备生命周期函数.主唱光剑初始化 = function(ref:Object, param:Object) 
{
   var target:MovieClip = ref.自机;
   var saberLabel:String = "武器类型名" + target.刀;
   var animFrameName:String = target.刀 + "动画帧";
   
   ref.saberLabel = saberLabel;
   ref.animFrameName = animFrameName;
   ref.animDuration = 15;
   ref.transformInterval = 1000;
   ref.timestampName = target.刀 + "时间戳";

   // 初始化基础伤害数据
   if (isNaN(target.话筒支架基础伤害)) {
       target.话筒支架基础伤害 = target.刀属性.power;
       target[saberLabel] = "光剑";
       
       // 读取保存的武器类型
       if (_root.控制目标 == target._name && _root[saberLabel] == "话筒支架") {
           target[saberLabel] = "话筒支架";
           target.刀属性.power = target.话筒支架基础伤害 * 0.8;
       }
   }
   
   // 初始化动画帧
   if (target[animFrameName] == undefined) {
       target[animFrameName] = 1;
   }

   var saberBladeYOffset1:Array = [363, 164];
   var saberBladeYOffset3:Array = [216, 102];
   ref.saberBladeYOffset1 = saberBladeYOffset1;
   ref.saberBladeYOffset3 = saberBladeYOffset3;


   target.syncRefs.刀_引用 = true;
   target.dispatcher.subscribe("刀_引用", function(unit) {
       _root.装备生命周期函数.主唱光剑动画更新(ref);
   });
};

_root.装备生命周期函数.主唱光剑周期 = function(ref:Object, param:Object) {
   //_root.装备生命周期函数.移除异常周期函数(ref);
   
   var target:MovieClip = ref.自机;
   var saber:MovieClip = target.刀_引用;
   
   // 武器形态切换检测
   if (Key.isDown(_root.武器变形键) && target.攻击模式 == "兵器") {
       if (!target[ref.timestampName] || getTimer() - target[ref.timestampName] > ref.transformInterval) {
           target[ref.timestampName] = getTimer();
           _root.装备生命周期函数.主唱光剑切换武器形态(ref);
       }
   }
   
   // 动画控制和更新
   _root.装备生命周期函数.主唱光剑动画控制(ref);
}


// 武器形态切换函数
_root.装备生命周期函数.主唱光剑切换武器形态 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   
   if (target[ref.saberLabel] == "光剑") {
       // 切换为话筒支架
       target[ref.saberLabel] = "话筒支架";
       target.刀属性.power = target.话筒支架基础伤害 * 0.8;
   } else {
       // 切换为光剑
       target[ref.saberLabel] = "光剑";
       target.刀属性.power = target.话筒支架基础伤害;
   }
   
   _root.发布消息("话筒支架武器类型切换为[" + target[ref.saberLabel] + "]");
   
   // 保存武器类型到全局
   if (_root.控制目标 == target._name) {
       _root[ref.saberLabel] = target[ref.saberLabel];
   }
};

// 动画控制函数 - 负责决定动画状态
_root.装备生命周期函数.主唱光剑动画控制 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   
   // 判断是否应该展开光剑
   var shouldExpand = function() {
       if (!_root.兵器使用检测(target) && target.攻击模式 != "兵器" || target[ref.saberLabel] == "话筒支架") {
           return false;
       }
       
       var currentFrame = target.man._currentframe;
       if (currentFrame >= 370 && currentFrame <= 413) {
           // 攻击动作中快速展开到2/3
           target[ref.animFrameName] = Math.max(target[ref.animFrameName], Math.floor(ref.animDuration * 2 / 3));
       }
       
       return true;
   };
   
   // 根据状态调整动画帧值
   if (shouldExpand()) {
       if (target[ref.animFrameName] < ref.animDuration) {
           target[ref.animFrameName]++;
       }
   } else {
       if (target[ref.animFrameName] > 1) {
           target[ref.animFrameName]--;
       }
   }
   
   // 调用动画更新函数
   _root.装备生命周期函数.主唱光剑动画更新(ref);
};

// 动画更新函数 - 负责实际更新动画显示（包括动画帧和刀口位置）
_root.装备生命周期函数.主唱光剑动画更新 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   var saber:MovieClip = target.刀_引用;
   
   // 更新动画帧
   if (saber.动画) {
       saber.动画.gotoAndStop(target[ref.animFrameName]);
   }
   
   // 更新刀口位置
   var isLightsaber:Boolean = (target[ref.saberLabel] == "光剑");
   var yOffsetIndex:Number = Number(isLightsaber);

   if (saber.刀口位置1) {
       saber.刀口位置1._y = ref.saberBladeYOffset1[yOffsetIndex];
   }
   
   if (saber.刀口位置3) {
       saber.刀口位置3._y = ref.saberBladeYOffset3[yOffsetIndex];
   }
};

/*
onClipEvent (load) {
	var 耗蓝比例 = 1;
	var 坐标偏移范围 = 10;
	var 自机 = _root.获得父节点(this, 5);
	var 武器类型名 = "武器类型名" + 自机.刀;
	var 主唱光刃类型 = "主唱光刃上轮斩";
	if (自机[增幅次数] == undefined)
	{
		自机[增幅次数] = {};
	}
	
	this.是否兵器跳 = function()
	{
		if (自机._currentframe >= 599 and 自机._currentframe <= 618)
		{
			return true;
		}
		else
		{
			return false;
		}
	};
	this.获得随机时间间隔 = function()
	{
		return _root.随机整数(0, 1 * 1000);
	};
	this.检查并执行时间间隔动作 = _root.检查并执行时间间隔动作;
	this.获得随机坐标偏离 = function()
	{
		var xOffset = (_root.basic_random() - 0.5) * 2 * 坐标偏移范围;
		var yOffset = (_root.basic_random() - 0.5) * 2 * 坐标偏移范围;
		return {x:自机._x + xOffset, y:自机._y + yOffset};
	};

	var 红色音符标识 = 自机.刀 + "红色音符";
	var 红色音符时间戳名 = 红色音符标识 + "时间戳";
	var 红色音符时间间隔 = this.获得随机时间间隔();
	var 红色音符耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例);
	var 红色音符最大增幅次数 = 24;
	var 红色音符攻击力增幅百分比 = 2.5;
	this.创建主唱伙伴 = function()
	{
		var 扭蛋点 = _root.随机整数(1, 100);
		if (扭蛋点 <= 75)
		{
			兵种库 = ["敌人-僵尸1-狗"];
			名字 = "主唱的狗";
		}
		else if (扭蛋点 <= 85)
		{
			兵种库 = ["敌人-辫子姑娘"];
			名字 = "主唱的战斗少女";
		}
		else if (扭蛋点 <= 95)
		{
			兵种库 = ["敌人-狂野玫瑰马尾姑娘"];
			名字 = "主唱的街舞少女";
		}
		else if (扭蛋点 <= 97)
		{
			兵种库 = ["敌人-精英战术少女"];
			名字 = "主唱的精英少女";
		}
		else if (扭蛋点 <= 98)
		{
			兵种库 = ["敌人-双喷少女"];
			名字 = "主唱的学姐";
		}
		else if (扭蛋点 <= 99)
		{
			兵种库 = ["敌人-摇滚公园少女"];
			名字 = "主唱的少女键盘";
		}
		else
		{
			兵种库 = ["敌人-摇滚公园萝莉"];
			名字 = "主唱的萝莉吉他";
		}

		兵种 = 兵种库[random(兵种库.length)];
		等级 = 自机.等级;
		身高 = 自机.身高 + _root.随机整数(-30, -15);
		是否为敌人 = 自机.是否为敌人;
		僵尸型敌人newname = 自机[增幅次数][增幅名] + 兵种;
		_root.加载游戏世界人物(兵种,僵尸型敌人newname,_root.gameworld.getNextHighestDepth(),{_x:自机._x, _y:自机._y, 等级:this.等级, 名字:this.名字 + "[" + 扭蛋点 + "]", 是否为敌人:this.是否为敌人, 身高:this.身高});
		EffectSystem.Effect("升级动画2",自机._x,自机._y,100);
		_root.发布消息("召唤主唱的伙伴[" + 名字 + "]！");
	};
	this.释放红色音符 = function()
	{
		var myPoint = this.获得随机坐标偏离();
		var 增幅名 = 红色音符标识 + "攻击增幅";

		if (自机[增幅次数][增幅名] === undefined)
		{
			自机[增幅次数][增幅名] = 1;
		}
		if (自机[增幅次数][增幅名] <= 红色音符最大增幅次数)
		{
			自机.空手攻击力 *= (100 + 红色音符攻击力增幅百分比) / 100;
			_root.发布消息("攻击力第" + 自机[增幅次数][增幅名] + "次上升" + 红色音符攻击力增幅百分比 + "%！目前攻击力为" + Math.floor(自机.空手攻击力) + "点！");
			自机[增幅次数][增幅名] += 1;
		}
		if (自机[增幅次数][增幅名] == 12 or 自机[增幅次数][增幅名] == 24)
		{
			this.创建主唱伙伴();
		}
		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 360;
		发射效果 = "";
		子弹种类 = "红色音符";
		子弹威力 = 红色音符耗蓝量 * 10;
		子弹速度 = 3;
		击中地图效果 = "";
		Z轴攻击范围 = 20;
		击倒率 = 100;
		击中后子弹的效果 = "";
		子弹敌我属性 = true;
		发射者名 = 自机._name;
		子弹敌我属性值 = !自机.是否为敌人;
		shootX = myPoint.x;
		Z轴坐标 = shootY = 自机._y;
		_root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,子弹敌我属性值,击倒率,击中后子弹的效果);
		自机.mp -= 红色音符耗蓝量;
		红色音符时间间隔 = this.获得随机时间间隔();
	};

	var 猩红增幅标识 = 自机.刀 + "猩红增幅";
	var 猩红增幅时间戳名 = 猩红增幅标识 + "时间戳";
	var 猩红增幅时间间隔 = this.获得随机时间间隔() * 6;
	var 猩红增幅耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例 / 2);

	this.集体加血 = function(加血距离X, 加血距离Y)
	{
		var 是否加血成功:Boolean = false;
		for (each in _root.gameworld)
		{
			if (_root.gameworld[each].是否为敌人 == 自机.是否为敌人)
			{
				if (Math.abs(_root.gameworld[each]._x - 自机._x) < 加血距离X and Math.abs(_root.gameworld[each]._y - 自机._y) < 加血距离Y)
				{
					if (_root.gameworld[each].hp > 0 and _root.gameworld[each].hp < _root.gameworld[each].hp满血值)
					{
						_root.gameworld[each].hp += 猩红增幅耗蓝量 * 4 + Math.floor(_root.gameworld[each].hp满血值 * 0.03);
						if (_root.gameworld[each].hp > _root.gameworld[each].hp满血值)
						{
							_root.gameworld[each].hp = _root.gameworld[each].hp满血值;
						}
						EffectSystem.Effect("猩红增幅",_root.gameworld[each]._x,_root.gameworld[each]._y,100,true);
						是否加血成功 = true;
					}
				}
			}
		}
		自机.mp -= 猩红增幅耗蓝量;
	};

	this.释放猩红增幅 = function()
	{
		var 回血量 = 猩红增幅耗蓝量 * 8;
		this.集体加血(900,600,回血量);

	};
	var 主唱光刃标识 = 自机.刀 + "主唱光刃";
	var 主唱光刃时间戳名 = 主唱光刃标识 + "时间戳";
	var 主唱光刃时间间隔 = 500;
	var 主唱光刃耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例);
	if (自机.上次主唱光刃类型 == undefined)
	{
		自机.上次主唱光刃类型 = "主唱光刃突刺";
	}
	this.释放主唱光刃 = function()
	{
		var myPoint = {x:this._x, y:this._y};
		_parent.localToGlobal(myPoint);
		_root.gameworld.globalToLocal(myPoint);

		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 0;
		发射效果 = "";
		子弹种类 = 主唱光刃类型;
		子弹威力 = 自机.空手攻击力 * 0.5 + 自机.话筒支架基础伤害 * 2;
		子弹速度 = 0;
		击中地图效果 = "";
		Z轴攻击范围 = 50;
		击倒率 = 10;
		击中后子弹的效果 = "";
		子弹敌我属性 = true;
		发射者名 = 自机._name;
		子弹敌我属性值 = !自机.是否为敌人;
		shootX = myPoint.x;
		Z轴坐标 = shootY = 自机._y;
		_root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,子弹敌我属性值,击倒率,击中后子弹的效果);
		if (主唱光刃类型 == "主唱光刃突刺")
		{
			自机.mp -= 主唱光刃耗蓝量;
		}
	};
	this.onEnterFrame = function()
	{
		if (_root.兵器攻击检测(自机) and 自机.mp >= 主唱光刃耗蓝量)
		{
			if (自机[武器类型名] == "光剑")
			{
				if (this.是否兵器跳())
				{
					if (自机.man._currentframe == 4)
					{
						主唱光刃时间间隔 = 300;
						主唱光刃类型 = "主唱光刃上劈斩";//保证每一刀都能触发且仅触发一次
					}
					else
					{
						主唱光刃时间间隔 = 1000;
						主唱光刃类型 = "主唱光刃";//其他情况不触发
					}
				}
				else
				{
					switch (自机.getSmallState())
					{
						case "兵器一段前" :
							主唱光刃类型 = "主唱光刃上轮斩";
							break;
						case "兵器一段中" :
							主唱光刃类型 = "主唱光刃";//一段中无特效
							break;
						case "兵器二段中" :
							主唱光刃类型 = "主唱光刃下轮斩";
							break;
						case "兵器三段中" :
							主唱光刃类型 = "主唱光刃上挑斩";
							break;
						case "兵器四段中" :
							主唱光刃类型 = "主唱光刃下撩斩";
							break;
						case "兵器五段中" :
							主唱光刃类型 = "主唱光刃下圈斩";
							break;
						default :
							主唱光刃类型 = "主唱光刃突刺";

					}

					if (主唱光刃类型 != "主唱光刃突刺" and 自机.上次主唱光刃类型 != 主唱光刃类型)
					{
						主唱光刃时间间隔 = 0;//保证每一刀都能触发且仅触发一次
						//_root.调试模式 = true;
						//_root.发布调试消息(自机.getSmallState() + " " + 主唱光刃类型 + " " + 自机.上次主唱光刃类型);
					}
					else
					{
						主唱光刃时间间隔 = 1200;
					}

					自机.上次主唱光刃类型 = 主唱光刃类型;
				}
				this.检查并执行时间间隔动作(自机,主唱光刃时间间隔,"释放主唱光刃",主唱光刃时间戳名);
			}
			else
			{
				if (自机.mp >= 红色音符耗蓝量)
				{
					this.检查并执行时间间隔动作(自机,红色音符时间间隔,"释放红色音符",红色音符时间戳名);
				}
			}

			if (自机.mp >= 猩红增幅耗蓝量)
			{
				this.检查并执行时间间隔动作(自机,猩红增幅时间间隔,"释放猩红增幅",猩红增幅时间戳名);
			}

		}
	};
}
*/