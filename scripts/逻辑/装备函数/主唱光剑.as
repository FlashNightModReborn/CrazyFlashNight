_root.装备生命周期函数.主唱光剑初始化 = function(ref:Object, param:Object)
{
   var target:MovieClip = ref.自机;

   // ===== 从XML参数对象读取配置 =====
   ref.animDuration = param.animDuration || 15;
   ref.transformInterval = param.transformInterval || 1000;

   var 耗蓝比例:Number = param.mpCostRatio || 1;
   ref.坐标偏移范围 = param.coordOffsetRange || 10;
   ref.红色音符最大增幅次数 = param.redNoteMaxStacks || 24;
   ref.红色音符攻击力增幅百分比 = param.redNoteAtkBoostPercent || 2.5;
   ref.光刃攻击力系数 = param.bladeAtkCoefficient || 0.5;
   ref.光刃基础伤害系数 = param.bladeBaseDmgCoefficient || 2;
   ref.红色音符威力倍率 = param.redNotePowerMultiplier || 10;
   ref.actionTypeSaber = param.actionTypeSaber || "直剑";
   ref.actionTypeMic = param.actionTypeMic || "长棍";

   // 刀口位置偏移量
   ref.saberBladeYOffset1 = [param.saberBladeYOffset1_0 || 363, param.saberBladeYOffset1_1 || 164];
   ref.saberBladeYOffset3 = [param.saberBladeYOffset3_0 || 216, param.saberBladeYOffset3_1 || 102];

   // 初始化基础伤害数据（首次加载时缓存到ref）
   if (isNaN(ref.baseDamage)) {
       ref.baseDamage = target.刀属性.power;
       ref.weaponMode = "光剑";
   }

   // 同步主角武器形态状态（使用全局参数持久化）
   if (ref.是否为主角) {
       var key:String = ref.标签名 + ref.初始化函数;
       if (!_root.装备生命周期函数.全局参数[key]) {
           _root.装备生命周期函数.全局参数[key] = {};
       }
       var gl:Object = _root.装备生命周期函数.全局参数[key];
       ref.weaponMode = gl.weaponMode || "光剑";
       ref.globalParam = gl;
       if (ref.weaponMode == "话筒支架") {
           target.刀属性.power = ref.baseDamage * 0.8;
       }
   }

   // 根据当前武器形态设置动作模组
   target.兵器动作类型 = (ref.weaponMode == "光剑") ? ref.actionTypeSaber : ref.actionTypeMic;

   // 初始化动画帧
   if (ref.animFrame == undefined) {
       ref.animFrame = 1;
   }

   target.syncRefs.刀_引用 = true;
   target.dispatcher.subscribe("刀_引用", function(unit) {
       _root.装备生命周期函数.主唱光剑动画更新(ref);
   });

   // ===== 战斗系统变量初始化 =====
   if (ref.增幅次数 == undefined) {
       ref.增幅次数 = {};
   }

   // 红色音符系统变量
   ref.红色音符标识 = target.刀 + "红色音符";
   ref.红色音符时间戳名 = ref.红色音符标识 + "时间戳";
   ref.红色音符时间间隔 = _root.随机整数(0, 1000);
   ref.红色音符耗蓝量 = Math.floor(target.mp满血值 / 100 * 耗蓝比例);

   // 猩红增幅系统变量
   ref.猩红增幅标识 = target.刀 + "猩红增幅";
   ref.猩红增幅时间戳名 = ref.猩红增幅标识 + "时间戳";
   ref.猩红增幅时间间隔 = _root.随机整数(0, 1000) * (param.crimsonBoostIntervalMultiplier || 6);
   ref.猩红增幅耗蓝量 = Math.floor(target.mp满血值 / 100 * 耗蓝比例 / 2);

   // 主唱光刃系统变量（由刀口触发特效系统驱动）
   ref.主唱光刃耗蓝量 = Math.floor(target.mp满血值 / 100 * 耗蓝比例);
   ref.defaultBladeType = param.defaultBladeType || "主唱光刃突刺";
   ref.光刃特殊时间戳名 = target.刀 + "光刃特殊时间戳";

   // 解析光刃状态映射表（auto-array → hash lookup）
   var bladeMapRaw = param.bladeStateMap ? param.bladeStateMap.entry : null;
   ref.bladeStateMap = {};
   if (bladeMapRaw) {
       if (!(bladeMapRaw instanceof Array)) {
           bladeMapRaw = [bladeMapRaw];
       }
       for (var i:Number = 0; i < bladeMapRaw.length; i++) {
           ref.bladeStateMap[bladeMapRaw[i].state] = bladeMapRaw[i].blade;
       }
   }

   // 解析光刃冷却状态表（state → interval，用于战斗周期轮询触发）
   var cooldownRaw = param.bladeCooldownStates ? param.bladeCooldownStates.entry : null;
   ref.bladeCooldownStates = {};
   if (cooldownRaw) {
       if (!(cooldownRaw instanceof Array)) {
           cooldownRaw = [cooldownRaw];
       }
       for (var i:Number = 0; i < cooldownRaw.length; i++) {
           ref.bladeCooldownStates[cooldownRaw[i].state] = Number(cooldownRaw[i].interval);
       }
   }

   // 订阅光刃事件（由刀口触发特效系统 publish，通过闭包访问 ref）
   target.dispatcher.subscribe("主唱光剑光刃", function(状态名:String) {
       if (ref.weaponMode != "光剑") return;
       if (target.mp < ref.主唱光刃耗蓝量) return;

       var bladeType:String = ref.bladeStateMap[状态名] || ref.defaultBladeType;
       if (!bladeType) return;

       var saber:MovieClip = target.刀_引用;
       var bladePos:MovieClip = saber.刀口位置3;
       var myPoint:Object = {x: bladePos._x, y: bladePos._y};
       saber.localToGlobal(myPoint);
       _root.gameworld.globalToLocal(myPoint);

       var 子弹属性:Object = ref.光刃子弹属性;
       子弹属性.子弹种类 = bladeType;
       子弹属性.子弹威力 = target.空手攻击力 * ref.光刃攻击力系数 + ref.baseDamage * ref.光刃基础伤害系数;
       子弹属性.发射者 = target._name;
       子弹属性.shootX = myPoint.x;
       子弹属性.shootY = target._y;
       子弹属性.shootZ = target._y;
       _root.子弹区域shoot传递(子弹属性);

       if (bladeType == ref.defaultBladeType) {
           target.mp -= ref.主唱光刃耗蓝量;
       }

	   // _root.发布消息("主唱光刃发射[" + bladeType + "]，消耗MP：" + ref.主唱光刃耗蓝量);
   });

   // ===== 子弹属性（由生命周期系统从XML bullet节点自动初始化） =====
   ref.光刃子弹属性 = ref.子弹配置.bullet_1;
   ref.红色音符子弹属性 = ref.子弹配置.bullet_2;

   // ===== 伙伴召唤系统 =====
   // XMLParser auto-array: 多个同名<entry>自动合并为数组，单个则为标量，需确保数组格式
   var 伙伴表Raw = param.companionTable ? param.companionTable.entry : null;
   ref.伙伴表 = [];
   if (伙伴表Raw) {
       if (!(伙伴表Raw instanceof Array)) {
           伙伴表Raw = [伙伴表Raw];
       }
       for (var i:Number = 0; i < 伙伴表Raw.length; i++) {
           var entry:Object = 伙伴表Raw[i];
           ref.伙伴表.push([Number(entry.weight), entry.unit, entry.name]);
       }
       // 按权重升序排列
       ref.伙伴表.sort(function(a, b) { return a[0] - b[0]; });
   }

   // 自适应计算召唤阈值：均匀分布，最后一次必须在最大增幅次数时触发
   var 召唤次数:Number = param.companionSummonCount || 2;
   var 最大增幅:Number = ref.红色音符最大增幅次数;
   ref.伙伴召唤阈值 = {};
   var 间隔:Number = 最大增幅 / 召唤次数;
   for (var i:Number = 1; i <= 召唤次数; i++) {
       ref.伙伴召唤阈值[Math.round(间隔 * i)] = true;
   }
};

_root.装备生命周期函数.主唱光剑周期 = function(ref:Object, param:Object) {
   //_root.装备生命周期函数.移除异常周期函数(ref);
   
   var target:MovieClip = ref.自机;
   var saber:MovieClip = target.刀_引用;
   
   // 武器形态切换检测
   if (target.攻击模式 == "兵器" && _root.按键输入检测(target, _root.武器变形键)) {
       _root.更新并执行时间间隔动作(
           ref,
           "武器形态切换",
           function() { _root.装备生命周期函数.主唱光剑切换武器形态(ref); },
           ref.transformInterval,
           false
       );
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
       target.兵器动作类型 = ref.actionTypeMic;
   } else {
       // 切换为光剑
       ref.weaponMode = "光剑";
       target.刀属性.power = ref.baseDamage;
       target.兵器动作类型 = ref.actionTypeSaber;
   }

   _root.发布消息("话筒支架武器类型切换为[" + ref.weaponMode + "]");

   // 保存武器类型到全局参数
   if (ref.globalParam) ref.globalParam.weaponMode = ref.weaponMode;
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

       // 在当前层数检查是否触发召唤（确保最后一层必定触发）
       if (ref.伙伴召唤阈值[ref.增幅次数[增幅名]]) {
           _root.装备生命周期函数.主唱光剑创建伙伴(ref);
       }
       ref.增幅次数[增幅名] += 1;
   }

   var 子弹属性:Object = ref.红色音符子弹属性;
   子弹属性.子弹威力 = ref.红色音符耗蓝量 * ref.红色音符威力倍率;
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

// ===== 模块E：战斗主循环 =====
_root.装备生命周期函数.主唱光剑战斗周期 = function(ref:Object) {
   var target:MovieClip = ref.自机;

   if (!_root.兵器攻击检测(target)) return;

   // 光剑模式：按冷却状态表触发光刃（通过事件触发订阅者处理）
   if (ref.weaponMode == "光剑" && target.mp >= ref.主唱光刃耗蓝量) {
       var 间隔:Number = ref.bladeCooldownStates[target.状态];
       if (间隔 != undefined) {
           if (_root.更新时间间隔(target, ref.光刃特殊时间戳名, 间隔)) {
               target.dispatcher.publish("主唱光剑光刃", target.状态);
           }
       }
   }

   // 话筒支架模式：释放红色音符
   if (ref.weaponMode == "话筒支架" && target.mp >= ref.红色音符耗蓝量) {
       if (_root.更新时间间隔(target, ref.红色音符时间戳名, ref.红色音符时间间隔)) {
           _root.装备生命周期函数.主唱光剑释放红色音符(ref);
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