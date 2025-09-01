//迁移了所有生存模式与无限过图的函数，以及4个难度关卡按钮里的函数
import org.flashNight.arki.scene.*;
import org.flashNight.arki.scene.*;
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
	_root.载入关卡数据(this.关卡类型, this.关卡路径);
	_root.当前通关的关卡 = "";
	_root.当前关卡难度 = 关卡难度 ? 关卡难度 : _root.当前关卡难度;
	_root.难度等级 = _root.计算难度等级(_root.当前关卡难度);
	_root.当前关卡名 = 当前关卡名;
	_root.场景进入位置名 = "出生地";
	_root.关卡类型 = 关卡类型;

	//应用限制词条
	if(this.限制词条.length > 0) _root.限制系统.openEntries(this.限制词条);
	if(this.限制难度等级) _root.限制系统.addLimitLevel(this.限制难度等级);

	if(起点帧) _root.关卡地图帧值 = 起点帧;

	_root.soundEffectManager.stopBGM();
	_root.淡出动画.淡出跳转帧(淡出跳转帧);
};

_root.委托界面进入关卡 = function(关卡难度){
	_root.载入关卡数据(this.关卡类型, this.关卡路径);
	_root.当前通关的关卡 = "";
	_root.当前关卡难度 = 关卡难度 ? 关卡难度 : _root.当前关卡难度;
	_root.难度等级 = _root.计算难度等级(_root.当前关卡难度);
	_root.当前关卡名 = 当前关卡名;
	_root.场景进入位置名 = "出生地";
	_root.关卡类型 = 关卡类型;
	if(起点帧) _root.关卡地图帧值 = 起点帧;

	//应用限制词条
	if(this.限制词条.length > 0) _root.限制系统.openEntries(this.限制词条);
	if(this.限制难度等级) _root.限制系统.addLimitLevel(this.限制难度等级);
	if(this.进入挑战 === true && this.挑战限制词条.length > 0) _root.限制系统.openEntries(this.挑战限制词条);
	
	//对尚未xml化的关卡打补丁
	if(NPC任务_任务_起始帧){
		淡出跳转帧 = NPC任务_任务_起始帧;
		_root.当前关卡名 = NPC任务_任务[12];
	}
	_root.soundEffectManager.stopBGM();
	_root.淡出动画.淡出跳转帧(淡出跳转帧);
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