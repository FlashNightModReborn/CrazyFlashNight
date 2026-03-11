import org.flashNight.gesh.string.EvalParser;
import org.flashNight.gesh.pratt.PrattEvaluator;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.cheatFunction = new Object();

_root.cheatFunction.hardmode = function(){
	_root.difficultyMode = 0;
	_root.最上层发布文字提示("更改为困难模式！");
	_root.修改工具按钮._visible = true;
}
_root.cheatFunction.easymode = function(){
	_root.difficultyMode = 1;
	_root.最上层发布文字提示("更改为简单模式！");
	_root.修改工具按钮._visible = true;
}
_root.cheatFunction.challengemode = function(){
	_root.difficultyMode = 2;
	_root.最上层发布文字提示("更改为挑战模式！");
	_root.修改工具按钮._visible = false;
}

_root.cheatFunction.test = function(){
	if(!_root.调试模式){
		_root.调试模式 = true;
		_root.最上层发布文字提示("调试模式开启！");
	}else{
		_root.调试模式 = false;
		_root.最上层发布文字提示("调试模式关闭！");
	}
}

_root.cheatFunction.add1 = function(){
	var add1僵尸兵种 = "敌人-光头军人僵尸1";
	var add1僵尸等级 = 1;
	var add1僵尸名字 = "僵尸";
	var add1僵尸是否为敌人 = true;
	var add1僵尸身高 = 175;
	var add1僵尸僵尸型敌人newname = this._name + 兵种;

	var hero:MovieClip = TargetCacheManager.findHero();
	_root.加载游戏世界人物(add1僵尸兵种,add1僵尸僵尸型敌人newname,_root.gameworld.getNextHighestDepth(),{_x: hero._x ,_y:hero._y,等级:add1僵尸等级,名字:add1僵尸名字,是否为敌人:add1僵尸是否为敌人,身高:add1僵尸身高,产生源:null});
	_root.最上层发布文字提示("添加一个僵尸！");
}

_root.cheatFunction.ultrarapidfire = function(){
	for(var key in _root.技能表对象){
		_root.技能表对象[key].MaxLevel = 99;
		if(_root.技能表对象[key].CD > 1000){
			_root.技能表对象[key].CD = 1000;
		}
	}for (var i = 1; i < 13; i++){
		var 当前技能栏 = _root.玩家信息界面.快捷技能界面["快捷技能栏" + i];
		if(当前技能栏.冷却时间 > 1000){
			当前技能栏.冷却时间 = 1000;
		}
	}
	_root.玩家信息界面.刷新技能等级显示();
	_root.最上层发布文字提示("无限火力开启！");
	_root.发布消息("开启无限火力模式，所有技能的升级上限提升至99级，cd降低为1秒。部分技能可能产生bug。退出游戏后技能cd恢复正常。");
}
_root.cheatFunction.fire = _root.cheatFunction.ultrarapidfire;

_root.cheatFunction.getallmods = function(){
	var modlist = org.flashNight.arki.item.EquipmentUtil.modList;
	var acarr = [];
	for(var i=0; i<modlist.length; i++){
		acarr.push({name:modlist[i], value:1});
	}
	org.flashNight.arki.item.ItemUtil.acquire(acarr);
	_root.最上层发布文字提示("获得所有配件材料各1个");
}

_root.cheatFunction.getallintelligence = function(){
	var intelligenceDict = org.flashNight.arki.item.ItemUtil.informationMaxValueDict;
	var acarr = [];
	for(var name in intelligenceDict){
		var maxValue = intelligenceDict[name]; // 获取该情报的最大值
		acarr.push({name: name, value: maxValue});
	}
	org.flashNight.arki.item.ItemUtil.acquire(acarr);
	_root.最上层发布文字提示("获得所有情报(满额)");
}

// ============================================================
// A. 查询类命令
// ============================================================

_root.cheatFunction.status = function() {
	var hero:MovieClip = TargetCacheManager.findHero();
	var lines:Array = [];
	lines.push("=== 玩家状态 ===");
	lines.push("等级: " + _root.等级 + " | 经验: " + _root.经验值 + "/" + _root.升级需要经验值);
	if (hero != undefined) {
		lines.push("HP: " + hero.hp + "/" + hero.hp满血值 + " | MP: " + hero.mp + "/" + hero.mp满血值);
		lines.push("坐标: (" + Math.round(hero._x) + ", " + Math.round(hero._y) + ")");
		lines.push("攻击力: " + hero.空手攻击力 + " | 防御力: " + hero.防御力);
	}
	lines.push("难度: " + (["困难","简单","挑战"])[_root.difficultyMode]);
	lines.push("调试模式: " + (_root.调试模式 ? "开" : "关"));
	_root.最上层发布文字提示(lines.join("\n"));
};

_root.cheatFunction.scene = function() {
	var lines:Array = [];
	lines.push("=== 场景信息 ===");
	lines.push("当前关卡: " + _root.当前通关的关卡);
	lines.push("地图帧值: " + _root.关卡地图帧值);
	if (_root.gameworld != undefined) {
		lines.push("gameworld: " + _root.gameworld);
	}
	_root.最上层发布文字提示(lines.join("\n"));
};

// ============================================================
// B. 状态修改类命令
// ============================================================

_root.cheatFunction.god = function() {
	if (!_root._godMode) {
		_root._godMode = true;
		var hero:MovieClip = TargetCacheManager.findHero();
		if (hero != undefined) {
			hero.hp = hero.hp满血值;
			hero.mp = hero.mp满血值;
		}
		_root._godInterval = setInterval(function() {
			var h:MovieClip = TargetCacheManager.findHero();
			if (h != undefined) {
				h.hp = h.hp满血值;
				h.mp = h.mp满血值;
			}
		}, 200);
		_root.最上层发布文字提示("无敌模式开启！");
	} else {
		_root._godMode = false;
		clearInterval(_root._godInterval);
		_root.最上层发布文字提示("无敌模式关闭！");
	}
};

_root.cheatFunction.heal = function() {
	var hero:MovieClip = TargetCacheManager.findHero();
	if (hero != undefined) {
		hero.hp = hero.hp满血值;
		hero.mp = hero.mp满血值;
		_root.最上层发布文字提示("HP/MP 已回满！HP:" + hero.hp + " MP:" + hero.mp);
	} else {
		_root.最上层发布文字提示("找不到主角单位");
	}
};

_root.cheatFunction.sp = function() {
	// 通过 cheatCode 的 #sp:数量 语法调用
	_root.最上层发布文字提示("当前技能点: " + _root.技能点数);
};

// ============================================================
// C. 世界控制类命令
// ============================================================

_root.cheatFunction.killall = function() {
	var count:Number = 0;
	for (var name in _root.gameworld) {
		var unit:MovieClip = _root.gameworld[name];
		if (unit.是否为敌人 == true && unit.hp > 0) {
			unit.hp = 0;
			count++;
		}
	}
	_root.最上层发布文字提示("已击杀 " + count + " 个敌人");
};

// ============================================================
// D. 表达式求值类命令（通过 #eval: #get: #set: 前缀触发）
// ============================================================
// 用法详见 cheatCode 函数中新增的分支

// ============================================================
// 系统辨识：开环阶跃响应自动化测试
// ============================================================
//
// 用法：
//   输入 sysid  → 自动执行 7 阶段开环阶跃测试（0→1→2→3→2→1→0）
//   输入 stopsysid → 中止测试并导出已收集的日志
//
// 原理：
//   forceLevel() 切换性能等级但不创建保护窗口，evaluate() 持续采样；
//   量化器锁定（minLevel = maxLevel = targetLevel）阻止 PID 改变等级，
//   实现开环条件下的阶跃响应数据采集。
//
// 每阶段保持 30 秒（30000ms），总测试时长 ≈ 3.5 分钟。
// 日志包含 EVT_SAMPLE + EVT_PID_DETAIL，标签格式 "OL:from>to"。
// ============================================================

_root.cheatFunction.sysid = function() {
	var ft = _root.帧计时器;
	var scheduler = ft.scheduler;

	if (scheduler == undefined) {
		_root.最上层发布文字提示("性能调度器未初始化！");
		return;
	}

	// 如果已有测试在运行，先停止
	if (_root._sysidRunning) {
		_root.cheatFunction.stopsysid();
	}

	// 确保日志容量足够（4096 条）并清空旧数据
	if (ft.performanceLogger == null || ft.performanceLogger.getCapacity() < 4096) {
		ft.performanceLogger = new org.flashNight.neur.PerformanceOptimizer.PerformanceLogger(4096);
	}
	ft.performanceLogger.setEnabled(true);
	ft.performanceLogger.clear();
	scheduler.setLogger(ft.performanceLogger);

	// 测试序列定义：开环阶跃 0→1→2→3→2→1→0
	var levels = [0, 1, 2, 3, 2, 1, 0];
	var HOLD = 30000; // 每相位保持时间（30000ms = 30秒）
	var phase = 0;

	_root._sysidRunning = true;
	_root._sysidTaskID = null;

	var runPhase = function() {
		if (!_root._sysidRunning || phase >= levels.length) {
			// 测试完成
			_root._sysidRunning = false;
			_root._sysidTaskID = null;

			// 恢复量化器
			ft.性能等级上限 = 0;
			scheduler.getQuantizer().setMaxLevel(3);
			scheduler.setLoggerTag(null);

			// 导出日志
			scheduler.getLogger().dump();
			_root.发布消息("═══ 系统辨识测试完成，共 " + levels.length + " 阶段 ═══");
			_root.最上层发布文字提示("系统辨识测试完成！日志已导出。");
			return;
		}

		var targetLevel = levels[phase];
		var prevLevel = (phase > 0) ? levels[phase - 1] : 0;
		var tag = "OL:" + prevLevel + ">" + targetLevel;

		// 锁定量化器：minLevel = maxLevel = targetLevel
		ft.性能等级上限 = targetLevel;
		scheduler.getQuantizer().setMaxLevel(targetLevel);

		// 设置标签
		scheduler.setLoggerTag(tag);

		// 强制切换等级（不创建保护窗口）
		scheduler.forceLevel(targetLevel);

		_root.发布消息("系统辨识 Phase " + (phase + 1) + "/" + levels.length +
			": Level " + prevLevel + " → " + targetLevel +
			" (保持" + (HOLD / 1000) + "秒)");

		phase++;

		// 调度下一阶段（或收尾）
		_root._sysidTaskID = ft.添加单次任务(runPhase, HOLD);
	};

	_root.发布消息("═══ 开始系统辨识测试 ═══");
	_root.发布消息("序列: " + levels.join("→") + " | 每相位 " + (HOLD / 1000) + " 秒");
	_root.最上层发布文字提示("系统辨识测试开始！输入 stopsysid 停止。");

	// 立即开始第一阶段
	runPhase();
};

_root.cheatFunction.stopsysid = function() {
	if (!_root._sysidRunning) {
		_root.最上层发布文字提示("没有正在运行的系统辨识测试。");
		return;
	}

	var ft = _root.帧计时器;
	var scheduler = ft.scheduler;

	_root._sysidRunning = false;

	// 移除待执行任务
	if (_root._sysidTaskID != null) {
		ft.移除任务(_root._sysidTaskID);
		_root._sysidTaskID = null;
	}

	// 恢复量化器
	ft.性能等级上限 = 0;
	scheduler.getQuantizer().setMaxLevel(3);
	scheduler.setLoggerTag(null);

	// 导出已收集的日志
	if (scheduler.getLogger() != null) {
		scheduler.getLogger().dump();
	}

	_root.发布消息("═══ 系统辨识测试已中止，部分日志已导出 ═══");
	_root.最上层发布文字提示("系统辨识测试已停止！部分日志已导出。");
};

// ============================================================
// 闭环日志：记录正常闭环运行时的性能调度数据
// ============================================================
//
// 用法：
//   输入 cllog    → 开始记录闭环日志（不干预调度逻辑）
//   输入 stopcllog → 停止记录并导出日志
//
// 与 sysid 的区别：
//   sysid  锁定量化器 + 强制等级 = 开环测试
//   cllog  不做任何干预 = 闭环观察
//
// 日志包含 EVT_SAMPLE + EVT_PID_DETAIL + EVT_LEVEL_CHANGED，
// 用于评估迟滞确认、切档频率、极限环等闭环行为。
// ============================================================

_root.cheatFunction.cllog = function() {
	var ft = _root.帧计时器;
	var scheduler = ft.scheduler;

	if (scheduler == undefined) {
		_root.最上层发布文字提示("性能调度器未初始化！");
		return;
	}

	// 确保日志容量足够（4096 条）并清空旧数据
	if (ft.performanceLogger == null || ft.performanceLogger.getCapacity() < 4096) {
		ft.performanceLogger = new org.flashNight.neur.PerformanceOptimizer.PerformanceLogger(4096);
	}
	ft.performanceLogger.setEnabled(true);
	ft.performanceLogger.clear();
	scheduler.setLogger(ft.performanceLogger);
	scheduler.setLoggerTag("CL");

	_root._cllogRunning = true;

	_root.发布消息("═══ 闭环日志记录开始 ═══");
	_root.发布消息("当前等级: " + scheduler.getPerformanceLevel() +
		" | 目标FPS: " + scheduler.getTargetFPS());
	_root.最上层发布文字提示("闭环日志记录中！输入 stopcllog 停止。");
};

_root.cheatFunction.stopcllog = function() {
	if (!_root._cllogRunning) {
		_root.最上层发布文字提示("没有正在运行的闭环日志记录。");
		return;
	}

	var ft = _root.帧计时器;
	var scheduler = ft.scheduler;

	_root._cllogRunning = false;
	scheduler.setLoggerTag(null);

	if (scheduler.getLogger() != null) {
		scheduler.getLogger().dump();
	}

	_root.发布消息("═══ 闭环日志记录已停止，日志已导出 ═══");
	_root.最上层发布文字提示("闭环日志已导出！");
};

_root.cheatCode = function(作弊码){
	if(typeof _root.cheatFunction[作弊码] === "function"){
		_root.cheatFunction[作弊码]();
		return;
	}

	var 执行代码;
	if(作弊码.indexOf("#code:")>-1){
		执行代码  = 作弊码.split("#code:")[1];
		_root.发布消息("执行代码："+执行代码);
		//eval(执行代码);
		//_root.发布消息("执行失败！因为as2不支持eval()直接解析，等fs处理吧");
		EvalParser.getPropertyValue(testObj, "user.name");
	}else if(作弊码.indexOf("#_root.")>-1){
		执行代码  = 作弊码.split("#_root.")[1].split("=");
		var 变量名  = 执行代码[0].split(" ").join("");
		var 变量值  = 执行代码[1];
		if(变量值.indexOf(";")>-1){
			var 变量值初始值 = 变量值.split(";");
			变量值=变量值初始值[0];
			var 参数类型 = 变量值初始值[1];
			if(参数类型.indexOf("int")>-1  or 参数类型.indexOf("数")>-1  or 参数类型.indexOf("float")>-1  or 参数类型.indexOf("number")>-1  or 参数类型.indexOf("Number")>-1 ){
				变量值 = Number(变量值);
				_root.发布消息("传入数字型");
			}else if(参数类型.indexOf("bool")>-1  or 参数类型.indexOf("布尔")>-1 ){
				if(变量值=="false" or 变量值=="0" or !变量值){
					变量值 = false;
				}else{
					变量值 = true;
				}
				_root.发布消息("传入布尔型："+变量值);
			}
		}
		_root.发布消息("变更变量：_root."+变量名);
		_root[变量名] = 变量值;
		_root.发布消息("值已变更为:"+变量值);
	}else if(作弊码.indexOf("#func:_root.")>-1){
		执行代码  = 作弊码.split("#func:_root.")[1].split("(");
		var 执行函数  = 执行代码[0].split(" ").join("");
		var 执行参数初始值  = 执行代码[1].split(")");
		var 执行参数  = 执行参数初始值[0];
		var 参数类型  = 执行参数初始值[1];
		_root.发布消息("执行函数：_root."+执行函数+"("+执行参数+")");
		var 执行参数数组 = 执行参数.split(",");
		for(var i=0;i<执行参数数组.length;i++){
			if(执行参数数组.length==1){
				var 前缀="";
			}else{
				前缀=i+1;
				前缀=前缀+":"
			}
			if(参数类型.indexOf(前缀+"int")>-1  or 参数类型.indexOf(前缀+"数")>-1  or 参数类型.indexOf(前缀+"float")>-1  or 参数类型.indexOf(前缀+"num")>-1  or 参数类型.indexOf(前缀+"Num")>-1 ){
				执行参数数组[i] = Number(执行参数数组[i]);
				_root.发布消息("传入数字型:"+执行参数数组[i]);
			}else if(参数类型.indexOf(前缀+"变量")>-1 or 参数类型.indexOf(前缀+"var")>-1){
				if(作弊码.indexOf("_root.")>-1){
					执行参数数组[i] = 执行参数数组[i].split("_root.")[1].split(" ").join("");
				}else{
					执行参数数组[i] = 执行参数数组[i].split(" ").join("");
				}
				_root.发布消息("传入root变量:_root."+执行参数数组[i]);
				执行参数数组[i] = _root[执行参数数组[i]];
			}else if(参数类型.indexOf(前缀+"bool")>-1  or 参数类型.indexOf(前缀+"布尔")>-1 ){
					if(执行参数数组[i]=="false" or 执行参数数组[i]=="0" or !执行参数数组[i]){
						执行参数数组[i] = false;
					}else{
						执行参数数组[i] = true;
					}
					_root.发布消息("传入布尔型："+执行参数数组[i]);
			}
		}
		
		//_root[执行函数](执行参数);
		_root[执行函数].apply(this, 执行参数数组);
		_root.发布消息("执行完毕！");
	}else if(作弊码.indexOf("#change:")>-1){
		执行代码  = 作弊码.split("#change:")[1];
		_root.特殊操作单位 = 执行代码;
		if(_root.特殊操作单位=="false" or _root.特殊操作单位=="0"){
			_root.特殊操作单位="";
		}
		_root.加载我方人物(_root.gameworld.出生地._x,_root.gameworld.出生地._y);
		if(_root.特殊操作单位){
			_root.最上层发布文字提示("当前操作目标变更为："+_root.特殊操作单位+"-切换场景生效");
		}else{
			_root.最上层发布文字提示("当前操作目标恢复！"+"-切换场景生效");
		}
	}else if(作弊码.indexOf("#level:")>-1){
		执行代码  = 作弊码.split("#level:")[1].split(" ").join("");

		_root.等级 = Number(执行代码);
		_root.经验值 = _root.根据等级得升级所需经验(_root.等级-1);
		_root.升级需要经验值 = _root.根据等级得升级所需经验(_root.等级);
		_root.上次升级需要经验值 = _root.等级 > 1 ? _root.根据等级得升级所需经验(_root.等级 - 1) : 0;
		_root.玩家信息界面.刷新经验值显示();
		_root.最上层发布文字提示("当前等级变更为："+_root.等级+",经验值变更为："+_root.经验值+"-切换场景生效");

	}else if(作弊码.indexOf("#eval:")>-1){
		// 表达式求值：#eval:player.stats.attack + 10
		var evalExpr:String = 作弊码.split("#eval:")[1];
		var evaluator:PrattEvaluator = PrattEvaluator.createStandard();
		evaluator.setVariable("root", _root);
		evaluator.setVariable("hero", TargetCacheManager.findHero());
		evaluator.setVariable("gameworld", _root.gameworld);
		var evalResult = evaluator.evaluateSafe(evalExpr, "[eval error]");
		_root.发布消息("eval(" + evalExpr + ") = " + evalResult);
	}else if(作弊码.indexOf("#get:")>-1){
		// 属性读取：#get:等级  或  #get:gameworld.出生地._x
		var getPath:String = 作弊码.split("#get:")[1].split(" ").join("");
		var getResult = EvalParser.getPropertyValue(_root, getPath);
		_root.发布消息("_root." + getPath + " = " + getResult);
	}else if(作弊码.indexOf("#set:")>-1){
		// 属性写入：#set:等级=50
		var setParts:Array = 作弊码.split("#set:")[1].split("=");
		var setPath:String = setParts[0].split(" ").join("");
		var setVal:String = setParts[1];
		// 尝试数字转换
		if (!isNaN(Number(setVal)) && setVal.length > 0) {
			EvalParser.setPropertyValue(_root, setPath, Number(setVal));
		} else if (setVal == "true") {
			EvalParser.setPropertyValue(_root, setPath, true);
		} else if (setVal == "false") {
			EvalParser.setPropertyValue(_root, setPath, false);
		} else {
			EvalParser.setPropertyValue(_root, setPath, setVal);
		}
		_root.发布消息("_root." + setPath + " = " + EvalParser.getPropertyValue(_root, setPath));
	}else if(作弊码.indexOf("#gold:")>-1){
		var goldVal:Number = Number(作弊码.split("#gold:")[1].split(" ").join(""));
		_root.金钱 = goldVal;
		_root.最上层发布文字提示("金钱设置为: " + _root.金钱);
	}else if(作弊码.indexOf("#sp:")>-1){
		var spVal:Number = Number(作弊码.split("#sp:")[1].split(" ").join(""));
		_root.技能点数 = spVal;
		_root.最上层发布文字提示("技能点设置为: " + _root.技能点数);
	}else if(作弊码.indexOf("#give:")>-1){
		var giveParts:Array = 作弊码.split("#give:")[1].split(",");
		var giveName:String = giveParts[0];
		var giveCount:Number = (giveParts.length > 1) ? Number(giveParts[1]) : 1;
		org.flashNight.arki.item.ItemUtil.acquire([{name: giveName, value: giveCount}]);
		_root.最上层发布文字提示("获得: " + giveName + " x" + giveCount);
	}else if(作弊码.indexOf("#spawn:")>-1){
		var spawnParts:Array = 作弊码.split("#spawn:")[1].split(",");
		var spawnType:String = spawnParts[0];
		var spawnLevel:Number = (spawnParts.length > 1) ? Number(spawnParts[1]) : 1;
		var hero:MovieClip = TargetCacheManager.findHero();
		var spawnX:Number = (hero != undefined) ? hero._x : 0;
		var spawnY:Number = (hero != undefined) ? hero._y : 0;
		_root.加载游戏世界人物(spawnType, spawnType + "_spawn" + getTimer(), _root.gameworld.getNextHighestDepth(), {_x: spawnX, _y: spawnY, 等级: spawnLevel, 名字: spawnType, 是否为敌人: true, 身高: 175, 产生源: null});
		_root.最上层发布文字提示("召唤: " + spawnType + " Lv." + spawnLevel);
	}else if(作弊码.indexOf("#tp:")>-1){
		var tpParts:Array = 作弊码.split("#tp:")[1].split(",");
		var tpHero:MovieClip = TargetCacheManager.findHero();
		if (tpHero != undefined && tpParts.length >= 2) {
			tpHero._x = Number(tpParts[0]);
			tpHero._y = Number(tpParts[1]);
			_root.最上层发布文字提示("传送到: (" + tpHero._x + ", " + tpHero._y + ")");
		}
	}else if(作弊码.substring(0,2)==".."){
		执行代码  = 作弊码.split("..")[1].split(" ").join("");
		if(!isNaN(Number(执行代码))){
			_root.等级 = Number(执行代码);
			_root.经验值 = _root.根据等级得升级所需经验(_root.等级-1);
			_root.升级需要经验值 = _root.根据等级得升级所需经验(_root.等级);
			_root.上次升级需要经验值 = _root.等级 > 1 ? _root.根据等级得升级所需经验(_root.等级 - 1) : 0;
			_root.玩家信息界面.刷新经验值显示();
			_root.最上层发布文字提示("当前等级变更为："+_root.等级+",经验值变更为："+_root.经验值+"-切换场景生效");
		}

	}
	//_root.发布消息(作弊码.substring(0,2));
}

/*
作弊码语法参考：

=== 快捷命令 ===
test                调试模式开关
easymode            简单模式
hardmode            困难模式
challengemode       挑战模式
status              查看玩家状态（等级/HP/MP/坐标/攻防）
scene               查看场景信息
heal                满血满蓝
god                 无敌模式开关（持续锁血）
killall             击杀所有敌人
add1                召唤一个僵尸
fire                无限火力（技能CD降为1秒）
getallmods          获得所有配件
getallintelligence  获得所有情报

=== 前缀命令 ===
#level:15           设置等级为15
..15                设置等级的简写
#gold:99999         设置金钱
#sp:99              设置技能点
#give:物品名,数量   给予物品（如 #give:急救包,10）
#spawn:兵种,等级    召唤单位（如 #spawn:敌人-光头军人僵尸1,5）
#tp:100,200         传送到坐标
#change:兵种名      变更操控单位

=== 变量操作 ===
#_root.变量=值;类型  设置_root变量（如 #_root.abc=123;int）
#get:变量路径        读取属性（如 #get:等级）
#set:路径=值         设置属性（如 #set:等级=50）
#eval:表达式         Pratt求值（如 #eval:hero.hp * 2 + 100）

=== 函数调用 ===
#func:_root.函数(参数);类型

=== 性能测试 ===
sysid / stopsysid   系统辨识开环测试
cllog / stopcllog   闭环性能日志

=== Agent 远程控制 ===
通过 HTTP POST /console 发送命令：
  curl -X POST http://localhost:1192/console -d "command=status"
*/
