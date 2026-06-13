import org.flashNight.arki.scene.*;
import org.flashNight.arki.weather.*;
// import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.关卡回调函数 = new Object();

_root.关卡回调函数.AVP_重设光照 = function(最大光照, 最小光照){
	if(_root.难度等级 >= 2){
		var envInfo:Object = WeatherSystem.getInstance().getEnvConfig().getInfiniteMapEnvInfo();
		envInfo.最大光照 = 最大光照;
		envInfo.最小光照 = 最小光照;
	}
}

// 角斗场
_root.关卡回调函数.角斗场加载 = function(){
	var playerX = _root.linearEngine.randomIntegerStrict(420,760);
	var playerY = _root.linearEngine.randomIntegerStrict(250,600);
	var enemyX = _root.linearEngine.randomIntegerStrict(420,760);
	var enemyY = _root.linearEngine.randomIntegerStrict(250,600);
	if(_root.linearEngine.randomCheckHalf()) playerX += 540;
	else enemyX += 540;
	_root.gameworld.出生地._x = playerX;
	_root.gameworld.出生地._y = playerY;
	// 对手类型分叉：escalation=爬升模式（无限波+奖池）, roster=元战队非人形怪, merc/默认=人形佣兵（原行为）
	if(_root.角斗场对手类型 == "escalation"){
		// 爬升固定布局（覆盖上面的随机左右分配）：玩家左侧 + 怪物右侧刷出。
		// 好处①相机跟随玩家→怪在右侧屏外刷出，玩家看不到刷怪过程不突兀；②与"走最右拿钱离场"叙事一致。
		var cfg = _root.角斗场爬升配置;
		_root.gameworld.出生地._x = cfg.玩家出生X;
		_root.gameworld.出生地._y = cfg.玩家出生Y;
		_root.角斗场爬升初始化(cfg.怪物出生X, cfg.怪物出生Y);
	}else if(_root.角斗场对手类型 == "roster"){
		_root.加载角斗场怪物(enemyX, enemyY);
	}else{
		_root.加载敌方人物(enemyX, enemyY);
	}
}

// dev 验证：用 兵种库 直接造一支测试小队走 roster 入场，验证非人形生成通路+判胜+发奖。
// 控制台调用：_root.测试角斗场怪物()  或  _root.测试角斗场怪物(等级)
// 默认堕落城 4 盗贼（兵种44/45/48/49）。押金 0、奖金 1000，不动真经济。
_root.测试角斗场怪物 = function(等级){
	if(等级 == undefined) 等级 = 30;
	var 兵种表 = ["兵种44", "兵种45", "兵种48", "兵种49"];
	var squad = [];
	for(var i = 0; i < 兵种表.length; i++){
		if(_root.兵种库[兵种表[i]] != undefined) squad.push({兵种: 兵种表[i], 等级: 等级});
	}
	if(squad.length == 0){ _root.最上层发布文字提示("测试小队为空（兵种库未就绪？）"); return; }
	if(!org.flashNight.arki.merc.ArenaController.prepareArenaStage(0, 1000, "")){
		_root.最上层发布文字提示("角斗场场景数据缺失"); return;
	}
	_root.角斗场入场中 = true;
	org.flashNight.arki.merc.ArenaController.commitRoster(squad);
}
_root.关卡回调函数.角斗场计算敌人数 = function(){
	if(_root.角斗场对手类型 == "escalation"){
		// 爬升模式自管波次循环（轮询清空 + 压力板决策），WaveSpawner 全程 inert：
		// finishRequirement 设极小负值使 clockTick 永不触发 finishWave（仅保留其 HUD 推送）。
		WaveSpawner.instance.finishRequirement = -99999;
		return;
	}
	WaveSpawner.instance.finishRequirement = -_root.敌人同伴数;
}
_root.关卡回调函数.角斗场获胜 = function(){
	if(_root.角斗场对手类型 == "escalation") return; // 爬升走奖池/拿钱台结算，不在此处发奖
	_root.金钱 += _root.角斗场奖金;
	_root.最上层发布文字提示("你赢了！获得奖金" + _root.角斗场奖金 + "元！");
}

// ════════════════════════════════════════════════════════════════════════════
// 角斗场·爬升模式（Phase 3）：势力主题无限爬升 + 奖池押注
//   循环：刷一波该势力怪 → 清空 → 两侧地台亮起 → 走最左台=续战(更强一波) / 走最右台=拿钱离场
//   经济：每波奖金进奖池（不直接进钱，指数增长）；战死=奖池清零（押金已扣）；拿钱台=奖池入账+返回主城
//   驱动：自挂 onEnterFrame 轮询（清空检测）+ 订阅 HeroMoved（决策期按 heroX 判左右台），
//         全程不依赖 WaveSpawner 波次推进（finishReq=-99999 使其 inert）。无新建类，纯 _root 函数。
//   计数：每波刷怪后 gameworld.地图.僵尸型敌人总个数 += 本波数，死亡递减 → <=0 即清空（HUD 显示存活数）。
// ────────────────────────────────────────────────────────────────────────────
// 数值（陡峭高风险高回报，业务可调）：
_root.角斗场爬升配置 = {
	对手增量: 2,      // 每波对手数 +N
	对手上限: 8,
	等级增量: 6,      // 每波全员等级 +N（陡峭）
	等级上限: 130,
	奖金增长: 1.4,    // 每波奖金 ×N（指数累积进奖池）
	精英周期: 3,      // 每 N 波额外刷 1 个精英
	精英等级加成: 15,
	// 固定布局（真机反馈调整：玩家左/怪物右；左台从 280 内收，右台 1280 保持）
	玩家出生X: 520,   // 玩家固定左侧中心刷出（相机跟随→右侧刷怪屏外不突兀）
	玩家出生Y: 440,
	怪物出生X: 1100,  // 怪物固定右侧刷出（约 580px 右于玩家→刷怪过程基本在屏外 + 与右台离场叙事吻合）
	怪物出生Y: 440,
	// 三段式决策（防战斗误触发）：清空后只亮"中央抉择台"，玩家踏入中央带才亮左右台→从中央出发走左/右皆为刻意动作。
	中央台界限低: 760, // 清空后玩家走回 [低,高] 中央带 → 亮左右决策台（中央带在怪物刷出 990~1210 之左、玩家刷出 520 之右）
	中央台界限高: 960,
	左台界限: 440,    // heroX <= 此值 → 续战（向左回撤）；从 280 内收，玩家左刷后不必走到极左边缘
	右台界限: 1280    // heroX >= 此值 → 拿钱离场（向右推进出场，怪刷在其左侧）
};

// 进场初始化（由 角斗场加载 在 escalation 模式下调用）：订阅移动 + 挂轮询时钟 + 刷第 1 波
_root.角斗场爬升初始化 = function(地点X, 地点Y){
	var st = _root.角斗场爬升;
	if(st == undefined) return;
	st.enemyX = 地点X;
	st.enemyY = 地点Y;
	st.round = 0;
	st.pot = 0;
	st.phase = "combat";
	st.pollFrame = 0;
	st.active = true;
	// 订阅玩家移动事件（决策期据 heroX 判定走左/右台）
	_root.gameworld.dispatcher.subscribe("HeroMoved", _root.角斗场爬升玩家移动, null);
	// 自挂轮询时钟（清空检测）：gameworld 上一个空剪辑的 onEnterFrame
	var clip = _root.gameworld.createEmptyMovieClip("角斗场爬升时钟", _root.gameworld.getNextHighestDepth());
	clip.onEnterFrame = function(){ _root.角斗场爬升轮询(); };
	st.clock = clip;
	_root.角斗场爬升刷波();
}

// 加权随机取一个池内单位（{type,minLevel,maxLevel,weight}）
_root.角斗场爬升采样 = function(pool){
	if(pool == undefined || pool.length == 0) return undefined;
	var totalW = 0;
	var i;
	for(i = 0; i < pool.length; i++){
		totalW += (pool[i].weight > 0 ? pool[i].weight : 1);
	}
	var r = Math.random() * totalW;
	var acc = 0;
	for(i = 0; i < pool.length; i++){
		acc += (pool[i].weight > 0 ? pool[i].weight : 1);
		if(r <= acc) return pool[i];
	}
	return pool[pool.length - 1];
}

// 刷一个怪（复刻 加载角斗场怪物 单体逻辑，独立波号命名避免跨波重名覆盖）
_root.角斗场爬升刷一个 = function(兵种, 等级, 地点X, 地点Y, idx){
	var 属性 = _root.兵种库[兵种];
	if(属性 == undefined) return false;
	var 初始化 = _root.duplicateOf(属性);
	初始化.兵种名 = null;
	初始化.等级 = 等级;
	初始化.是否为敌人 = true;
	初始化.产生源 = "地图";
	初始化._x = 地点X + random(220) - 110;
	初始化._y = 地点Y + random(150) - 75;
	// 仅在 attachMovie 成功（返回有效 MC）时计入存活数：否则计数永不归零→卡死在战斗相
	var mc = _root.加载游戏世界人物(属性.兵种名, "爬升敌人" + _root.角斗场爬升.round + "_" + idx, _root.gameworld.getNextHighestDepth(), 初始化);
	return (mc != undefined);
}

// 刷当前波（round++ → 按数值表算数量/等级 → 采样刷怪 → 每精英周期加一个精英 → 置存活计数）
_root.角斗场爬升刷波 = function(){
	var st = _root.角斗场爬升;
	var cfg = _root.角斗场爬升配置;
	st.round++;
	var R = st.round;
	var count = st.baseCount + cfg.对手增量 * (R - 1);
	if(count > cfg.对手上限) count = cfg.对手上限;
	var lvlBase = st.baseLevelMin + cfg.等级增量 * (R - 1);
	if(lvlBase > cfg.等级上限) lvlBase = cfg.等级上限;
	if(lvlBase < 1) lvlBase = 1;
	var spawned = 0;
	var idx = 0;
	var i;
	for(i = 0; i < count; i++){
		var unit = _root.角斗场爬升采样(st.pool);
		if(unit == undefined) continue;
		var lvl = lvlBase + random(5);
		if(lvl > cfg.等级上限) lvl = cfg.等级上限;
		if(lvl < 1) lvl = 1;
		if(_root.角斗场爬升刷一个(unit.type, lvl, st.enemyX, st.enemyY, idx)){ spawned++; idx++; }
	}
	var isElite = (cfg.精英周期 > 0 && (R % cfg.精英周期) == 0);
	if(isElite){
		var eu = _root.角斗场爬升采样(st.pool);
		if(eu != undefined){
			var elvl = lvlBase + cfg.精英等级加成;
			if(elvl > cfg.等级上限) elvl = cfg.等级上限;
			if(_root.角斗场爬升刷一个(eu.type, elvl, st.enemyX, st.enemyY, idx)){ spawned++; idx++; }
		}
	}
	_root.gameworld.地图.僵尸型敌人总个数 += spawned;
	st.alive = spawned;
	st.phase = "combat";
	if(isElite) _root.最上层发布文字提示("⚠ 第 " + R + " 波 · 精英波！对手 ×" + spawned + "　Lv" + lvlBase);
	else _root.最上层发布文字提示("第 " + R + " 波　对手 ×" + spawned + "　Lv" + lvlBase);
}

// 轮询时钟（onEnterFrame）：仅战斗相，约每 6 帧查一次，全灭即进入决策
_root.角斗场爬升轮询 = function(){
	var st = _root.角斗场爬升;
	if(st == undefined || !st.active) return;
	if(st.phase != "combat") return;
	st.pollFrame++;
	if(st.pollFrame < 6) return;
	st.pollFrame = 0;
	if(_root.gameworld.地图.僵尸型敌人总个数 <= 0){
		_root.角斗场清空回中();
	}
}

// 清空 → 回中相：本波奖金入奖池 + 只亮"中央抉择台"（左右台先不亮，防战斗末误触发）+ 提示走回中央
_root.角斗场清空回中 = function(){
	var st = _root.角斗场爬升;
	var cfg = _root.角斗场爬升配置;
	st.phase = "回中";
	var reward = Math.round(st.baseReward * Math.pow(cfg.奖金增长, st.round - 1));
	reward = Math.round(reward / 100) * 100;
	if(reward < 0) reward = 0;
	st.pot += reward;
	_root.角斗场绘制中央台();
	_root.最上层发布文字提示("第 " + st.round + " 波清空！本波 +" + reward + "，奖池 " + st.pot + "　走回中央抉择台开始选择");
}

// 进入决策相：踏入中央带后才亮左右台（从中央出发，走左/右皆为刻意动作）
_root.角斗场进入决策 = function(){
	var st = _root.角斗场爬升;
	st.phase = "decision";
	_root.角斗场绘制决策台();
	_root.最上层发布文字提示("奖池 " + st.pot + "　← 走最左续战（更强一波） / 走最右拿钱离场 →");
}

// 玩家移动回调：回中相→踏入中央带亮决策台；决策相→到最左台续战 / 最右台拿钱
_root.角斗场爬升玩家移动 = function(heroX, heroZ){
	var st = _root.角斗场爬升;
	var cfg = _root.角斗场爬升配置;
	if(st == undefined || !st.active) return;
	if(st.phase == "回中"){
		if(heroX >= cfg.中央台界限低 && heroX <= cfg.中央台界限高){
			_root.角斗场进入决策();
		}
	}else if(st.phase == "decision"){
		if(heroX <= cfg.左台界限){
			_root.角斗场续战();
		}else if(heroX >= cfg.右台界限){
			_root.角斗场拿钱();
		}
	}
}

// 续战（走最左台）：清地台 → 刷更强的下一波（刷波内置 round++ 与 phase=combat）
_root.角斗场续战 = function(){
	var st = _root.角斗场爬升;
	if(st == undefined || st.phase != "decision") return;
	_root.角斗场清除地台();
	_root.角斗场爬升刷波();
}

// 拿钱离场（走最右台）：奖池入账 → 清理 → 走通关返回主城（与普通过关同路）
_root.角斗场拿钱 = function(){
	var st = _root.角斗场爬升;
	if(st == undefined || st.phase != "decision") return;
	st.phase = "done";
	_root.金钱 += st.pot;
	_root.最上层发布文字提示("拿钱离场！获得奖池 " + st.pot + " 元（共闯 " + st.round + " 波）");
	_root.角斗场爬升清理();
	StageManager.instance.clearStage();
}

// 清理：停轮询时钟 + 退订移动 + 移除地台 + 失活
_root.角斗场爬升清理 = function(){
	var st = _root.角斗场爬升;
	if(st == undefined) return;
	st.active = false;
	if(st.clock != undefined){
		st.clock.onEnterFrame = null;
		st.clock.removeMovieClip();
		st.clock = undefined;
	}
	_root.角斗场清除地台();
	if(_root.gameworld.dispatcher != undefined && _root.gameworld.dispatcher.unsubscribe != undefined){
		_root.gameworld.dispatcher.unsubscribe("HeroMoved", _root.角斗场爬升玩家移动, null);
	}
}

// 地台视觉（程序化绘制，无需美术）。中央抉择台(青)=回中相；左台绿(续战)/右台金(拿钱)=决策相。
_root.角斗场绘制中央台 = function(){
	var st = _root.角斗场爬升;
	var cfg = _root.角斗场爬升配置;
	_root.角斗场清除地台();
	var gw = _root.gameworld;
	var C = gw.createEmptyMovieClip("角斗场中央台", gw.getNextHighestDepth());
	_root.角斗场画台(C, cfg.中央台界限低, cfg.中央台界限高, 0x5ad0ff, "★ 踏入此处开始抉择");
	st.plateC = C;
}
_root.角斗场绘制决策台 = function(){
	var st = _root.角斗场爬升;
	var cfg = _root.角斗场爬升配置;
	_root.角斗场清除地台();
	var gw = _root.gameworld;
	var L = gw.createEmptyMovieClip("角斗场左台", gw.getNextHighestDepth());
	_root.角斗场画台(L, 0, cfg.左台界限, 0x6cd06c, "← 续战 (更强一波)");
	var Rt = gw.createEmptyMovieClip("角斗场右台", gw.getNextHighestDepth());
	_root.角斗场画台(Rt, cfg.右台界限, cfg.右台界限 + 300, 0xffc94a, "拿钱离场 →");
	st.plateL = L;
	st.plateR = Rt;
}
_root.角斗场画台 = function(clip, x1, x2, color, label){
	clip.beginFill(color, 26);
	clip.moveTo(x1, 180);
	clip.lineTo(x2, 180);
	clip.lineTo(x2, 640);
	clip.lineTo(x1, 640);
	clip.lineTo(x1, 180);
	clip.endFill();
	clip.createTextField("lbl", 1, x1 + 6, 130, (x2 - x1) - 12, 40);
	var tf = clip.lbl;
	tf.selectable = false;
	tf.embedFonts = false;
	tf.text = label;
	var fmt = new TextFormat();
	fmt.size = 22;
	fmt.bold = true;
	fmt.color = color;
	fmt.align = "center";
	tf.setTextFormat(fmt);
}
_root.角斗场清除地台 = function(){
	var st = _root.角斗场爬升;
	if(st == undefined) return;
	if(st.plateC != undefined){ st.plateC.removeMovieClip(); st.plateC = undefined; }
	if(st.plateL != undefined){ st.plateL.removeMovieClip(); st.plateL = undefined; }
	if(st.plateR != undefined){ st.plateR.removeMovieClip(); st.plateR = undefined; }
}

// dev 手测钩子：游戏内（基地，StageInfoDict 就绪）控制台
//   _root.测试角斗场爬升()         默认堕落城风格 4 盗贼池
//   _root.测试角斗场爬升(势力名)   若 web rosters 数据未注入 AS2，此处用兵种库直造一个小池演示
_root.测试角斗场爬升 = function(){
	var pool = [
		{type:"兵种44", minLevel:20, maxLevel:45, weight:85},
		{type:"兵种45", minLevel:20, maxLevel:45, weight:81},
		{type:"兵种48", minLevel:20, maxLevel:45, weight:72},
		{type:"兵种49", minLevel:20, maxLevel:45, weight:82}
	];
	var clean = [];
	for(var i = 0; i < pool.length; i++){
		if(_root.兵种库[pool[i].type] != undefined) clean.push(pool[i]);
	}
	if(clean.length == 0){ _root.最上层发布文字提示("测试池为空（兵种库未就绪？）"); return; }
	if(!org.flashNight.arki.merc.ArenaController.prepareArenaStage(0, 2000, "")){
		_root.最上层发布文字提示("角斗场场景数据缺失"); return;
	}
	_root.角斗场入场中 = true;
	org.flashNight.arki.merc.ArenaController.commitEscalation("堕落城", clean, 4, 20, 30, 0, 2000);
}


