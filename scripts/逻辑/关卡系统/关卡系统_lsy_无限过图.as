//迁移了所有生存模式与无限过图的函数，以及4个难度关卡按钮里的函数
_root.开启生存模式 = function() {
	StageManager.instance.initStage();
}
_root.生存模式关闭 = function(){
	StageManager.instance.closeStage();
}
_root.解析敌人属性 = function(敌人){
	return StageInfo.parseEnemyAttribute(敌人);
};


//选关界面按钮
_root.选关界面进入关卡 = function(关卡难度){
	if (typeof _root.载入关卡数据 != "function"
			|| typeof _root.计算难度等级 != "function"
			|| _root.淡出动画 == undefined
			|| typeof _root.淡出动画.淡出跳转帧 != "function") return false;
	var 入口:Object = this;
	var 入场难度 = 关卡难度 ? 关卡难度 : _root.当前关卡难度;
	var 入场关卡名:String = String(入口.当前关卡名 || 当前关卡名 || "");
	var 入场类型:String = String(入口.关卡类型 || 关卡类型 || "");
	var 入场路径:String = String(入口.关卡路径 || 关卡路径 || "");
	var 入场淡出帧 = 入口.淡出跳转帧 != undefined ? 入口.淡出跳转帧 : 淡出跳转帧;
	var 入场起点帧 = 入口.起点帧 != undefined ? 入口.起点帧 : 起点帧;
	var 入场限制:Array = 入口.限制词条 instanceof Array ? 入口.限制词条.slice() : [];
	var 入场限制等级 = 入口.限制难度等级;
	var 入场难度等级:Number;
	try {
		入场难度等级 = _root.计算难度等级(入场难度);
	} catch (预检错误) {
		return false;
	}
	if (入场关卡名 == "" || 入场类型 == "" || 入场路径 == ""
			|| 入场淡出帧 == undefined || 入场淡出帧 == "") return false;
	var 入场令牌 = org.flashNight.arki.scene.StageRunSession.reserveStageStart(
		"legacy_stage_select", 入场关卡名, String(入场难度));
	if (入场令牌 == "") {
		_root.发布消息(_root.获得翻译("请先领取或放弃上一关尚未处理的奖励。"));
		return false;
	}
	var 已结束:Boolean = false;
	var 已失败:Boolean = false;
	var 失败一次:Function = function():Void {
		if (已结束) return;
		已结束 = true;
		已失败 = true;
		var 管理器:org.flashNight.arki.scene.StageManager =
			org.flashNight.arki.scene.StageManager.instance;
		if (管理器 != null) 管理器.abortPreparedStage(入场令牌);
		org.flashNight.arki.scene.StageRunSession.cancelStageStart(入场令牌);
	};
	try {
		_root.载入关卡数据(入场类型, 入场路径, function():Void {
			if (已结束) return;
			if (!org.flashNight.arki.scene.StageRunSession.isStageStartReservationValid(入场令牌)) {
				失败一次();
				return;
			}
			try {
				_root.当前通关的关卡 = "";
				_root.当前关卡难度 = 入场难度;
				_root.难度等级 = 入场难度等级;
				_root.当前关卡名 = 入场关卡名;
				_root.场景进入位置名 = "出生地";
				_root.关卡类型 = 入场类型;
				if(入场限制.length > 0) _root.限制系统.openEntries(入场限制);
				if(入场限制等级) _root.限制系统.addLimitLevel(入场限制等级);
				if(入场起点帧) _root.关卡地图帧值 = 入场起点帧;
				_root.soundEffectManager.stopBGMForTransition();
				_root.淡出动画.淡出跳转帧(入场淡出帧);
			} catch (提交错误) {
				失败一次();
				return;
			}
			已结束 = true;
		}, 失败一次, 入场令牌);
	} catch (载入错误) {
		失败一次();
		return false;
	}
	return !已失败;
};

_root.委托界面进入关卡 = function(关卡难度){
	if (typeof _root.载入关卡数据 != "function"
			|| typeof _root.计算难度等级 != "function"
			|| _root.淡出动画 == undefined
			|| typeof _root.淡出动画.淡出跳转帧 != "function") return false;
	var 入口:Object = this;
	var 入场难度 = 关卡难度 ? 关卡难度 : _root.当前关卡难度;
	var 旧式起始帧 = NPC任务_任务_起始帧;
	var 旧式任务 = NPC任务_任务;
	var 入场关卡名:String = String(旧式起始帧 ? 旧式任务[12]
		: (入口.当前关卡名 || 当前关卡名 || ""));
	var 入场类型:String = String(入口.关卡类型 || 关卡类型 || "");
	var 入场路径:String = String(入口.关卡路径 || 关卡路径 || "");
	var 入场淡出帧 = 旧式起始帧 ? 旧式起始帧
		: (入口.淡出跳转帧 != undefined ? 入口.淡出跳转帧 : 淡出跳转帧);
	var 入场起点帧 = 入口.起点帧 != undefined ? 入口.起点帧 : 起点帧;
	var 入场限制:Array = 入口.限制词条 instanceof Array ? 入口.限制词条.slice() : [];
	var 挑战限制:Array = 入口.挑战限制词条 instanceof Array ? 入口.挑战限制词条.slice() : [];
	var 进入挑战:Boolean = 入口.进入挑战 === true;
	var 入场限制等级 = 入口.限制难度等级;
	var 入场难度等级:Number;
	try {
		入场难度等级 = _root.计算难度等级(入场难度);
	} catch (预检错误) {
		return false;
	}
	if (入场关卡名 == "" || 入场类型 == "" || 入场路径 == ""
			|| 入场淡出帧 == undefined || 入场淡出帧 == "") return false;
	var 入场令牌 = org.flashNight.arki.scene.StageRunSession.reserveStageStart(
		"legacy_dungeon", 入场关卡名, String(入场难度));
	if (入场令牌 == "") {
		_root.发布消息(_root.获得翻译("请先领取或放弃上一关尚未处理的奖励。"));
		return false;
	}
	var 已结束:Boolean = false;
	var 已失败:Boolean = false;
	var 失败一次:Function = function():Void {
		if (已结束) return;
		已结束 = true;
		已失败 = true;
		var 管理器:org.flashNight.arki.scene.StageManager =
			org.flashNight.arki.scene.StageManager.instance;
		if (管理器 != null) 管理器.abortPreparedStage(入场令牌);
		org.flashNight.arki.scene.StageRunSession.cancelStageStart(入场令牌);
	};
	try {
		_root.载入关卡数据(入场类型, 入场路径, function():Void {
			if (已结束) return;
			if (!org.flashNight.arki.scene.StageRunSession.isStageStartReservationValid(入场令牌)) {
				失败一次();
				return;
			}
			try {
				_root.当前通关的关卡 = "";
				_root.当前关卡难度 = 入场难度;
				_root.难度等级 = 入场难度等级;
				_root.当前关卡名 = 入场关卡名;
				_root.场景进入位置名 = "出生地";
				_root.关卡类型 = 入场类型;
				if(入场起点帧) _root.关卡地图帧值 = 入场起点帧;
				if(入场限制.length > 0) _root.限制系统.openEntries(入场限制);
				if(入场限制等级) _root.限制系统.addLimitLevel(入场限制等级);
				if(进入挑战 && 挑战限制.length > 0) _root.限制系统.openEntries(挑战限制);
				_root.soundEffectManager.stopBGMForTransition();
				_root.淡出动画.淡出跳转帧(入场淡出帧);
			} catch (提交错误) {
				失败一次();
				return;
			}
			已结束 = true;
		}, 失败一次, 入场令牌);
	} catch (载入错误) {
		失败一次();
		return false;
	}
	return !已失败;
};

_root.调试_敌人全死 = function() {
	var player = _root.gameworld[_root.控制目标];
	if (player.是否为敌人 == null)
	{
		_root.发布消息("无法执行敌人全死：玩家不在场上");
		return;
	}
	var 遍历敌人表 = _root.帧计时器.获取敌人缓存(player, 1);
	for (var i = 0; i < 遍历敌人表.length; i++)
	{
		var target = 遍历敌人表[i];
		if (target.element == null)
		{
			target.hp = 0;
			target.dispatcher.publish("kill",target);
		}

	}
}

//调试功能：直接完成当前波次
_root.调试_完成当前波次 = function() {
	var spawner = WaveSpawner.instance;
	if(!spawner || !spawner.isActive) {
		return false;
	}
	
	//强制完成当前波次
	spawner.finishWave();
	return true;
};

//调试功能：直接完成当前地图
_root.调试_完成当前地图 = function() {
	// _root.发布消息("调试：直接完成当前地图");
	var stageManager = StageManager.instance;
	if(!stageManager || !stageManager.isActive) {
		return false;
	}
	
	//将刷怪器的波次设置为最后一波并完成
	var spawner = WaveSpawner.instance;
	// _root.发布消息("调试：完成刷怪器 " + (spawner ? spawner._name : "无"));
	if(spawner && spawner.isActive) {
		spawner.currentWave = spawner.waveInfoList.length - 1;
		spawner.isFinished = true;
	}
	
	//直接清除当前地图
	stageManager.clearStage();
	return true;
};
