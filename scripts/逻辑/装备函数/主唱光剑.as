_root.装备生命周期函数.主唱光剑初始化 = function(ref:Object, param:Object) 
{
   var target:MovieClip = ref.自机;

   ref.saberLabel = "武器类型名" + target.刀;
   ref.animDuration = 15;
   ref.transformInterval = 1000;

   // 初始化基础伤害数据（首次加载时缓存到ref）
   if (isNaN(ref.baseDamage)) {
       ref.baseDamage = target.刀属性.power;
       ref.weaponMode = "光剑";

       // 读取保存的武器类型
       if (_root.控制目标 == target._name && _root[ref.saberLabel] == "话筒支架") {
           ref.weaponMode = "话筒支架";
           target.刀属性.power = ref.baseDamage * 0.8;
       }
   }

   // 初始化动画帧
   if (ref.animFrame == undefined) {
       ref.animFrame = 1;
   }

   var saberBladeYOffset1:Array = [363, 164];
   var saberBladeYOffset3:Array = [216, 102];
   ref.saberBladeYOffset1 = saberBladeYOffset1;
   ref.saberBladeYOffset3 = saberBladeYOffset3;


   target.syncRefs.刀_引用 = true;
   target.dispatcher.subscribe("刀_引用", function(unit) {
       _root.装备生命周期函数.主唱光剑动画更新(ref);
   });

   // ===== 战斗系统变量初始化 =====
   ref.耗蓝比例 = 1;
   ref.坐标偏移范围 = 10;
   ref.主唱光刃类型 = "主唱光刃上轮斩";

   if (ref.增幅次数 == undefined) {
       ref.增幅次数 = {};
   }

   // 红色音符系统变量
   ref.红色音符标识 = target.刀 + "红色音符";
   ref.红色音符时间戳名 = ref.红色音符标识 + "时间戳";
   ref.红色音符时间间隔 = _root.随机整数(0, 1000);
   ref.红色音符耗蓝量 = Math.floor(target.mp满血值 / 100 * ref.耗蓝比例);
   ref.红色音符最大增幅次数 = 24;
   ref.红色音符攻击力增幅百分比 = 2.5;

   // 猩红增幅系统变量
   ref.猩红增幅标识 = target.刀 + "猩红增幅";
   ref.猩红增幅时间戳名 = ref.猩红增幅标识 + "时间戳";
   ref.猩红增幅时间间隔 = _root.随机整数(0, 1000) * 6;
   ref.猩红增幅耗蓝量 = Math.floor(target.mp满血值 / 100 * ref.耗蓝比例 / 2);

   // 主唱光刃系统变量
   ref.主唱光刃标识 = target.刀 + "主唱光刃";
   ref.主唱光刃时间戳名 = ref.主唱光刃标识 + "时间戳";
   ref.主唱光刃时间间隔 = 500;
   ref.主唱光刃耗蓝量 = Math.floor(target.mp满血值 / 100 * ref.耗蓝比例);

   if (ref.上次主唱光刃类型 == undefined) {
       ref.上次主唱光刃类型 = "主唱光刃突刺";
   }

   // ===== 子弹属性模板 =====
   ref.光刃子弹属性 = {
       声音: "",
       霰弹值: 1,
       子弹散射度: 0,
       发射效果: "",
       子弹速度: 0,
       击中地图效果: "",
       Z轴攻击范围: 50,
       击倒率: 10,
       击中后子弹的效果: ""
   };

   ref.红色音符子弹属性 = {
       声音: "",
       霰弹值: 1,
       子弹散射度: 360,
       发射效果: "",
       子弹种类: "红色音符",
       子弹速度: 3,
       击中地图效果: "",
       Z轴攻击范围: 20,
       击倒率: 100,
       击中后子弹的效果: ""
   };

   // 伙伴召唤权重表: [累计权重阈值, 兵种, 名字]
   ref.伙伴表 = [
       [75,  "敌人-僵尸1-狗",         "主唱的狗"],
       [85,  "敌人-辫子姑娘",          "主唱的战斗少女"],
       [95,  "敌人-狂野玫瑰马尾姑娘",  "主唱的街舞少女"],
       [97,  "敌人-精英战术少女",      "主唱的精英少女"],
       [98,  "敌人-双喷少女",          "主唱的学姐"],
       [99,  "敌人-摇滚公园少女",      "主唱的少女键盘"],
       [100, "敌人-摇滚公园萝莉",      "主唱的萝莉吉他"]
   ];
};

_root.装备生命周期函数.主唱光剑周期 = function(ref:Object, param:Object) {
   //_root.装备生命周期函数.移除异常周期函数(ref);
   
   var target:MovieClip = ref.自机;
   var saber:MovieClip = target.刀_引用;
   
   // 武器形态切换检测
   if (Key.isDown(_root.武器变形键) && target.攻击模式 == "兵器") {
       if (!ref.formSwitchTimestamp || getTimer() - ref.formSwitchTimestamp > ref.transformInterval) {
           ref.formSwitchTimestamp = getTimer();
           _root.装备生命周期函数.主唱光剑切换武器形态(ref);
       }
   }
   
   // 动画控制和更新
   _root.装备生命周期函数.主唱光剑动画控制(ref);

   // 战斗逻辑
   _root.装备生命周期函数.主唱光剑战斗周期(ref);
}


// 武器形态切换函数
_root.装备生命周期函数.主唱光剑切换武器形态 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   
   if (ref.weaponMode == "光剑") {
       // 切换为话筒支架
       ref.weaponMode = "话筒支架";
       target.刀属性.power = ref.baseDamage * 0.8;
   } else {
       // 切换为光剑
       ref.weaponMode = "光剑";
       target.刀属性.power = ref.baseDamage;
   }

   _root.发布消息("话筒支架武器类型切换为[" + ref.weaponMode + "]");

   // 保存武器类型到全局
   if (_root.控制目标 == target._name) {
       _root[ref.saberLabel] = ref.weaponMode;
   }
};

// 动画控制函数 - 负责决定动画状态
_root.装备生命周期函数.主唱光剑动画控制 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   
   // 判断是否应该展开光剑
   var shouldExpand = function() {
       if (!_root.兵器使用检测(target) && target.攻击模式 != "兵器" || ref.weaponMode == "话筒支架") {
           return false;
       }

       var currentFrame = target.man._currentframe;
       if (currentFrame >= 370 && currentFrame <= 413) {
           // 攻击动作中快速展开到2/3
           ref.animFrame = Math.max(ref.animFrame, Math.floor(ref.animDuration * 2 / 3));
       }

       return true;
   };

   // 根据状态调整动画帧值
   if (shouldExpand()) {
       if (ref.animFrame < ref.animDuration) {
           ref.animFrame++;
       }
   } else {
       if (ref.animFrame > 1) {
           ref.animFrame--;
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
       saber.动画.gotoAndStop(ref.animFrame);
   }

   // 更新刀口位置
   var isLightsaber:Boolean = (ref.weaponMode == "光剑");
   var yOffsetIndex:Number = Number(isLightsaber);

   if (saber.刀口位置1) {
       saber.刀口位置1._y = ref.saberBladeYOffset1[yOffsetIndex];
   }
   
   if (saber.刀口位置3) {
       saber.刀口位置3._y = ref.saberBladeYOffset3[yOffsetIndex];
   }
};

// 工具函数：判断是否处于兵器跳状态
_root.装备生命周期函数.主唱光剑是否兵器跳 = function(ref:Object):Boolean {
   var target:MovieClip = ref.自机;
   return (target.状态 == "兵器跳");
};

// 工具函数：获得随机坐标偏离
_root.装备生命周期函数.主唱光剑获得随机坐标偏离 = function(ref:Object):Object {
   var target:MovieClip = ref.自机;
   var xOffset:Number = (_root.basic_random() - 0.5) * 2 * ref.坐标偏移范围;
   var yOffset:Number = (_root.basic_random() - 0.5) * 2 * ref.坐标偏移范围;
   return {x: target._x + xOffset, y: target._y + yOffset};
};

// ===== 模块C：红色音符系统 =====
_root.装备生命周期函数.主唱光剑释放红色音符 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   var myPoint:Object = _root.装备生命周期函数.主唱光剑获得随机坐标偏离(ref);
   var 增幅名:String = ref.红色音符标识 + "攻击增幅";

   if (ref.增幅次数[增幅名] === undefined) {
       ref.增幅次数[增幅名] = 1;
   }
   if (ref.增幅次数[增幅名] <= ref.红色音符最大增幅次数) {
       // 使用buff系统：累计倍率 = 1.025^N
       var 倍率:Number = Math.pow((100 + ref.红色音符攻击力增幅百分比) / 100, ref.增幅次数[增幅名]);
       var podBuff:PodBuff = new PodBuff("空手攻击力", BuffCalculationType.MULT_POSITIVE, 倍率);
       var metaBuff:MetaBuff = new MetaBuff([podBuff], [], 0);
       target.buffManager.addBuff(metaBuff, 增幅名);

       _root.发布消息("攻击力第" + ref.增幅次数[增幅名] + "次上升" + ref.红色音符攻击力增幅百分比 + "%！");
       ref.增幅次数[增幅名] += 1;
   }
   if (ref.增幅次数[增幅名] == 12 || ref.增幅次数[增幅名] == 24) {
       _root.装备生命周期函数.主唱光剑创建伙伴(ref);
   }

   var 子弹属性:Object = ref.红色音符子弹属性;
   子弹属性.子弹威力 = ref.红色音符耗蓝量 * 10;
   子弹属性.发射者 = target._name;
   子弹属性.shootX = myPoint.x;
   子弹属性.shootY = target._y;
   子弹属性.shootZ = target._y;
   _root.子弹区域shoot传递(子弹属性);
   target.mp -= ref.红色音符耗蓝量;
   ref.红色音符时间间隔 = _root.随机整数(0, 1000);
};

_root.装备生命周期函数.主唱光剑创建伙伴 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   var 扭蛋点:Number = _root.随机整数(1, 100);

   // 从权重表中查找对应伙伴
   var 伙伴表:Array = ref.伙伴表;
   var entry:Array;
   for (var i:Number = 0; i < 伙伴表.length; i++) {
       if (扭蛋点 <= 伙伴表[i][0]) {
           entry = 伙伴表[i];
           break;
       }
   }

   var 兵种:String = entry[1];
   var 名字:String = entry[2];
   var 增幅名:String = ref.红色音符标识 + "攻击增幅";
   var 僵尸型敌人newname:String = ref.增幅次数[增幅名] + 兵种;

   _root.加载游戏世界人物(兵种, 僵尸型敌人newname, _root.gameworld.getNextHighestDepth(), {_x: target._x, _y: target._y, 等级: target.等级, 名字: 名字 + "[" + 扭蛋点 + "]", 是否为敌人: target.是否为敌人, 身高: target.身高 + _root.随机整数(-30, -15)});
   _root.效果("升级动画2", target._x, target._y, 100);
   _root.发布消息("召唤主唱的伙伴[" + 名字 + "]！");
};

// ===== 模块D：猩红增幅系统 =====
_root.装备生命周期函数.主唱光剑释放猩红增幅 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   _root.加血动作._范围治疗(target, 900, 600, 0.05, true, "猩红增幅");
   target.mp -= ref.猩红增幅耗蓝量;
};

// ===== 模块B：主唱光刃释放 =====
_root.装备生命周期函数.主唱光剑释放光刃 = function(ref:Object) {
   var target:MovieClip = ref.自机;
   var saber:MovieClip = target.刀_引用;
   var bladePos:MovieClip = saber.刀口位置3;

   var myPoint:Object = {x: bladePos._x, y: bladePos._y};
   saber.localToGlobal(myPoint);
   _root.gameworld.globalToLocal(myPoint);

   var 子弹属性:Object = ref.光刃子弹属性;
   子弹属性.子弹种类 = ref.主唱光刃类型;
   子弹属性.子弹威力 = target.空手攻击力 * 0.5 + ref.baseDamage * 2;
   子弹属性.发射者 = target._name;
   子弹属性.shootX = myPoint.x;
   子弹属性.shootY = target._y;
   子弹属性.shootZ = target._y;
   _root.子弹区域shoot传递(子弹属性);

   if (ref.主唱光刃类型 == "主唱光刃突刺") {
       target.mp -= ref.主唱光刃耗蓝量;
   }
};

// ===== 模块E：战斗主循环 =====
_root.装备生命周期函数.主唱光剑战斗周期 = function(ref:Object) {
   var target:MovieClip = ref.自机;

   // _root.发布消息("主唱光剑战斗周期执行");

   if (!_root.兵器攻击检测(target) || target.mp < ref.主唱光刃耗蓝量) {
       return;
   }

   // _root.发布消息("主唱光剑战斗逻辑执行");

   if (ref.weaponMode == "光剑") {
       // 光剑模式：释放光刃
       if (_root.装备生命周期函数.主唱光剑是否兵器跳(ref)) {
           if (target.man._currentframe == 4) {
               ref.主唱光刃时间间隔 = 300;
               ref.主唱光刃类型 = "主唱光刃上劈斩";
           } else {
               ref.主唱光刃时间间隔 = 1000;
               ref.主唱光刃类型 = "主唱光刃";
           }
       } else {
           switch (target.getSmallState()) {
               case "兵器一段前":
                   ref.主唱光刃类型 = "主唱光刃上轮斩";
                   break;
               case "兵器一段中":
                   ref.主唱光刃类型 = "主唱光刃";
                   break;
               case "兵器二段中":
                   ref.主唱光刃类型 = "主唱光刃下轮斩";
                   break;
               case "兵器三段中":
                   ref.主唱光刃类型 = "主唱光刃上挑斩";
                   break;
               case "兵器四段中":
                   ref.主唱光刃类型 = "主唱光刃下撩斩";
                   break;
               case "兵器五段中":
                   ref.主唱光刃类型 = "主唱光刃下圈斩";
                   break;
               default:
                   ref.主唱光刃类型 = "主唱光刃突刺";
           }

           if (ref.主唱光刃类型 != "主唱光刃突刺" && ref.上次主唱光刃类型 != ref.主唱光刃类型) {
               ref.主唱光刃时间间隔 = 0;
           } else {
               ref.主唱光刃时间间隔 = 1200;
           }

           ref.上次主唱光刃类型 = ref.主唱光刃类型;
       }

       if (_root.更新时间间隔(target, ref.主唱光刃时间戳名, ref.主唱光刃时间间隔)) {
           _root.装备生命周期函数.主唱光剑释放光刃(ref);
       }
   } else {
       // 话筒支架模式：释放红色音符
       if (target.mp >= ref.红色音符耗蓝量) {
		
           if (_root.更新时间间隔(target, ref.红色音符时间戳名, ref.红色音符时间间隔)) {
               _root.装备生命周期函数.主唱光剑释放红色音符(ref);
           }
       }
   }

   // 猩红增幅（两种模式通用）
   if (target.mp >= ref.猩红增幅耗蓝量) {
       if (_root.更新时间间隔(target, ref.猩红增幅时间戳名, ref.猩红增幅时间间隔)) {
           _root.装备生命周期函数.主唱光剑释放猩红增幅(ref);
       }
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