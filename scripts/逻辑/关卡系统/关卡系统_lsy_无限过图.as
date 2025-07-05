//迁移了所有生存模式与无限过图的函数，以及4个难度关卡按钮里的函数
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