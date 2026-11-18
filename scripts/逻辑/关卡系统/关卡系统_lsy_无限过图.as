//迁移了所有生存模式与无限过图的函数，以及4个难度关卡按钮里的函数
_root.开启生存模式 = function() {
	org.flashNight.arki.scene.SceneTransitionGuard.initializeStage(_root, StageManager.instance);
}
_root.生存模式关闭 = function(){
	StageManager.instance.closeStage();
}
_root.解析敌人属性 = function(敌人){
	return StageInfo.parseEnemyAttribute(敌人);
};


//选关界面按钮
_root.选关界面进入关卡 = function(关卡难度){
    var 名称:String = String(this.当前关卡名 || "");
    var 难度:String = String(关卡难度 || _root.当前关卡难度 || "");
    return org.flashNight.arki.stageSelect.StageSelectPanelService.enterFromWorld(名称, 难度, "legacy_difficulty",
        "legacy."+org.flashNight.arki.stageSelect.StageAdmissionBridge.nextId(), function(ok:Boolean, error:String):Void {
            if (!ok && typeof _root.发布消息 == "function") _root.发布消息("关卡暂不可进入。");
        });
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
    var stageManager = StageManager.instance;
    if (!stageManager || !stageManager.isActive) return false;
    if (stageManager.isFailed) {
        _root.最上层发布文字提示("本次行动已失败，请返回原处后重新进入，再测试后续地图。");
        return false;
    }
    return stageManager.debugClearStage();
};
