//迁移了所有生存模式与无限过图的函数，以及4个难度关卡按钮里的函数
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

import org.flashNight.arki.scene.*;

_root.开启生存模式 = function(模式) {
    _root.当前为战斗地图 = true;

    //_root.d_波次._visible = _root.调试模式;
    //_root.d_剩余敌人数._visible = _root.调试模式;
    _root.d_倒计时显示._visible = false;
    _root.生存模式OBJ = new Object();
    _root.生存模式OBJ.波次 = 0;
    _root.生存模式OBJ.当前时间 = 0;
    _root.生存模式OBJ.总时间 = 0;

    var 时钟 = _root.生存模式OBJ.时钟;
    if (时钟 != undefined || 时钟.length > 0) {
        for (var i = 0; i < 时钟.length; i++) {
            for (var j = 0; j < 时钟[i].length; j++) {
                _root.帧计时器.移除任务(时钟[i][j]);
            }
        }
    }
    _root.生存模式OBJ.时钟 = [];
    _root.生存模式OBJ.已出兵记录 = [];
    _root.生存模式OBJ.模式部署 = 模式;

    var 基本配置 = _root.无限过图基本配置[_root.无限过图模式关卡计数];
    var 游戏世界 = _root.gameworld;

	// 创建事件分发器
	_root.stageDispatcher = new LifecycleEventDispatcher(游戏世界);
	_root.stageDispatcher.subscribeOnce("StageFinished", function() {
		this.显示箭头();
	},游戏世界.通关箭头);

    // 设置本张图结束后的过场背景
    if (基本配置.LoadingImage) {
        _root.加载背景列表.本次背景 = 基本配置.LoadingImage;
    }

    // 设置地图尺寸
    var bglist = 基本配置.Background.split("/");
    var url = bglist[bglist.length - 1];
    var 环境信息 = _root.duplicateOf(_root.天气系统.关卡环境设置[url]);
    if (!环境信息) {
        环境信息 = _root.duplicateOf(_root.天气系统.关卡环境设置.Default);
    }
	//配置关卡环境参数
    if (基本配置.Environment) {
		环境信息 = _root.配置环境信息(基本配置.Environment, 环境信息);
    }
    _root.天气系统.无限过图环境信息 = 环境信息;

    if (环境信息.对齐原点) {
        游戏世界.背景._x = 0;
        游戏世界.背景._y = 0;
    }
    _root.Xmax = 环境信息.Xmax;
    _root.Xmin = 环境信息.Xmin;
    _root.Ymax = 环境信息.Ymax;
    _root.Ymin = 环境信息.Ymin;
    游戏世界.背景长 = 环境信息.背景长;
    游戏世界.背景高 = 环境信息.背景高;
    
    var 游戏世界门1 = 游戏世界.门1;
	var 门1数据 = 环境信息.门[1];
	游戏世界.门朝向 = 门1数据.Direction ? 门1数据.Direction : "右";
	// 游戏世界.门朝向 = 环境信息.门朝向;
	
	if(门1数据.x0 && 门1数据.y0 && 门1数据.x1 && 门1数据.y1){
		游戏世界门1._x = 门1数据.x0;
		游戏世界门1._y = 门1数据.y0;
		游戏世界门1._width = 门1数据.x1 - 门1数据.x0;
		游戏世界门1._height = 门1数据.y1 - 门1数据.y0;
	}else if(游戏世界.门朝向 === "左"){
		//默认过图位置为地图左边缘或右边缘
		游戏世界门1._x = _root.Xmin;
		游戏世界门1._y = _root.Ymin;
		游戏世界门1._width = 50;
		游戏世界门1._height = _root.Ymax - _root.Ymin;
	}else{
		游戏世界门1._x = _root.Xmax - 50;
		游戏世界门1._y = _root.Ymin;
		游戏世界门1._width = 50;
		游戏世界门1._height = _root.Ymax - _root.Ymin;
	}
	if(门1数据.Identifier){
		var identifier = 游戏世界.attachMovie(门1数据.Identifier,"DoorIdentifier1",游戏世界.getNextHighestDepth());
		identifier._x = (门1数据.x1 + 门1数据.x0) * 0.5;
		identifier._y = (门1数据.y1 + 门1数据.y0) * 0.5;
		identifier.swapDepths(identifier._y);
	}
    游戏世界.允许通行 = false;
    游戏世界.关卡结束 = false;

    // 将上述属性设置为不可枚举
    _global.ASSetPropFlags(游戏世界, ["背景", "背景长", "背景高", "门朝向", "允许通行", "关卡结束", "Xmax", "Xmin", "Ymax", "Ymin"], 1, false);

    // 添加动态尺寸的位图层
    var 尸体层 = 游戏世界.deadbody;
    尸体层.layers = new Array(3);
    var 位图宽度 = 游戏世界.背景长 < 2880 ? 游戏世界.背景长 : 2880;
    var 位图高度 = 游戏世界.背景高 < 1000 ? 游戏世界.背景高 : 1000;
    尸体层.layers[0] = new flash.display.BitmapData(位图宽度, 位图高度, true, 13421772);
    尸体层.layers[1] = null; // 从未被使用的尸体层1不添加
    尸体层.layers[2] = new flash.display.BitmapData(位图宽度, 位图高度, true, 13421772);
    尸体层.attachBitmap(尸体层.layers[0], 尸体层.getNextHighestDepth());
    尸体层.attachBitmap(尸体层.layers[2], 尸体层.getNextHighestDepth());

    // 将 'deadbody' 设置为不可枚举
    _global.ASSetPropFlags(游戏世界, ["deadbody"], 1, false);

	_root.通过数组绘制地图碰撞箱(环境信息.地图碰撞箱);

    // 将 '地图' 设置为不可枚举
    _global.ASSetPropFlags(游戏世界, ["地图"], 1, false);

    // 确定左右刷怪线
    if (环境信息.左侧出生线) {
        _root.生存模式OBJ.左侧出生线 = 环境信息.左侧出生线;
        _root.生存模式OBJ.获取左侧随机出生点 = function() {
            var rand = _root.basic_random();
            var px = Math.floor(this.左侧出生线.x0 + (this.左侧出生线.x1 - this.左侧出生线.x0) * rand);
            var py = Math.floor(this.左侧出生线.y0 + (this.左侧出生线.y1 - this.左侧出生线.y0) * rand);
            return {x: px, y: py};
        };
    } else {
        _root.生存模式OBJ.获取左侧随机出生点 = function() {
            var px = _root.Xmin + random(50);
            var py = _root.Ymin + random(_root.Ymax - _root.Ymin);
            return {x: px, y: py};
        };
    }
    if (环境信息.右侧出生线) {
        _root.生存模式OBJ.右侧出生线 = 环境信息.右侧出生线;
        _root.生存模式OBJ.获取右侧随机出生点 = function() {
            var rand = _root.basic_random();
            var px = Math.floor(this.右侧出生线.x0 + (this.右侧出生线.x1 - this.右侧出生线.x0) * rand);
            var py = Math.floor(this.右侧出生线.y0 + (this.右侧出生线.y1 - this.右侧出生线.y0) * rand);
            return {x: px, y: py};
        };
    } else {
        _root.生存模式OBJ.获取右侧随机出生点 = function() {
            var px = _root.Xmax - random(50);
            var py = _root.Ymin + random(_root.Ymax - _root.Ymin);
            return {x: px, y: py};
        };
    }
    
    // 设置玩家出生地，若未配置PlayerX或PlayerY则设置为无限过图默认位置(90,390)
    if (isNaN(基本配置.PlayerX) || isNaN(基本配置.PlayerY)) {
        基本配置.PlayerX = _root.Xmin + 50;
        基本配置.PlayerY = _root.Ymin + 60;
    }
	游戏世界.出生地.是否从门加载主角 = true;
    游戏世界.出生地._x = 基本配置.PlayerX;
    游戏世界.出生地._y = 基本配置.PlayerY;
	游戏世界.出生地.是否从门加载角色 = _root.场景转换函数.是否从门加载角色;
    游戏世界.出生地.是否从门加载角色();
    
    // 将 '出生地' 设置为不可枚举
    _global.ASSetPropFlags(游戏世界, ["出生地"], 1, false);

    // 放置环境地图元件
	_root.发布消息(SceneManager.getInstance());
	if(环境信息.背景元素){
		for(var i = 0; i < 环境信息.背景元素.length; i++){
			var name = 环境配置.背景元素[i].name ? 环境配置.背景元素[i].name : "bgInstance" + i;
			SceneManager.getInstance().addInstance(环境信息.背景元素[i], name);
		}
	}
	// 放置关卡地图元件
    var 实例列表 = _root.无限过图实例[_root.无限过图模式关卡计数];
    for (var i = 0; i < 实例列表.length; i++) {
        SceneManager.getInstance().addInstance(实例列表[i], "stageInstance" + i);
    }

    // 放置出生点，初始化各个刷怪点的总个数和场上人数
    var 出生点列表 = _root.无限过图出生点[_root.无限过图模式关卡计数];
    for (var i = 0; i < 出生点列表.length; i++) {
		var 出生点 = SceneManager.getInstance().addInstance(出生点列表[i], "door" + i);
        出生点.僵尸型敌人总个数 = 0;
        出生点.僵尸型敌人场上实际人数 = 0;
    }
    游戏世界.地图.僵尸型敌人总个数 = 0;

    // 加载进图动画
    if (基本配置.Animation.Load == 1) {
        _root.最上层加载外部动画(基本配置.Animation.Path);
        if (基本配置.Animation.Pause == 1) {
            _root.暂停 = true;
        }
    }

    // 加载进图对话
    var 本轮对话 = _root.副本对话[_root.无限过图模式关卡计数][0];
    if (本轮对话.length > 0) {
        _root.暂停 = true;
        _root.SetDialogue(本轮对话);
    }

	//播放场景bgm
	if(基本配置.BGM){
		if(基本配置.BGM.Command == "play"){
			_root.soundEffectManager.playBGM(基本配置.BGM.Title, 基本配置.BGM.Loop, null);
		}else if (基本配置.BGM.Command == "stop"){
			_root.soundEffectManager.stopBGM();
		}
	}

	//调用回调函数
	if(基本配置.CallbackFunction.Name){
		if(基本配置.CallbackFunction.Parameter){
			var para = _root.配置数据为数组(基本配置.CallbackFunction.Parameter);
			_root.关卡回调函数[基本配置.CallbackFunction.Name].apply(_root.关卡回调函数,para);
		}else{
			_root.关卡回调函数[基本配置.CallbackFunction.Name]();
		}
	}
    
	//加载场景
	_root.加载场景背景(基本配置.Background);
	_root.加载后景(环境信息);

    // 开始刷怪
    if (!基本配置.RogueMode) _root.生存模式OBJ.模式部署.总波数 = _root.生存模式OBJ.模式部署.length;
    _root.生存模式进攻();
};


_root.生存模式关闭 = function(){
	_root.当前为战斗地图 = false;
	_root.d_剩余敌人数._visible = false;
	_root.帧计时器.移除任务(_root.生存模式OBJ.波次时钟);
	var 时钟 = _root.生存模式OBJ.时钟;
	if (时钟 != undefined || 时钟.length > 0){
		for (var i = 0; i < 时钟.length; i++){
			for (var j = 0; j < 时钟[i].length; j++){
				_root.帧计时器.移除任务(时钟[i][j]);
			}
		}
	}
	_root.stageDispatcher.destroy();
	_root.stageDispatcher = null;
};

/*
_root.生存模式直接下一波 = function()
{
	if (_root.生存模式OBJ.当前时间 < _root.生存模式OBJ.总时间 - 10)
	{
		_root.生存模式OBJ.当前时间 = _root.生存模式OBJ.总时间 - 10;
	}
};
*/

_root.生存模式进攻 = function(){
	var 基本配置 = _root.无限过图基本配置[_root.无限过图模式关卡计数];
	if(!基本配置.RogueMode || _root.生存模式OBJ.模式部署[_root.生存模式OBJ.波次]){
		_root.无限过图进攻();
	}else{
		_root.rogue模式进攻();
	}
}

_root.无限过图进攻 = function(){
	var 游戏世界 = _root.gameworld;
	var 总波数 = _root.生存模式OBJ.模式部署.总波数;
	var 当前波次 = _root.生存模式OBJ.波次;
	var 本波信息 = _root.生存模式OBJ.模式部署[当前波次];
	var 此波总人数 = 0;
	if(!本波信息) _root.发布消息("敌人波次数据异常！");

	_root.d_波次.text = _root.获得翻译("波次") + (当前波次 + 1) + " / " + 总波数 + "";
	if(总波数 > 1){
		_root.最上层发布文字提示(_root.获得翻译("战斗开始！剩余波数：") + (总波数 - (当前波次 + 1)) + "！");
	}
	_root.生存模式OBJ.波次时钟 = 0;
	_root.生存模式OBJ.当前时间 = 0;
	_root.生存模式OBJ.FinishRequirement = Number(本波信息[0].FinishRequirement) > 0 ? Number(本波信息[0].FinishRequirement) : 0;
	if(当前波次 < 当前波次 - 1 || Number(本波信息[0].Duration) > 0){
		_root.生存模式OBJ.总时间 = Number(本波信息[0].Duration);
	}else{
		_root.生存模式OBJ.总时间 = 0;
	}
	_root.d_倒计时显示._visible = _root.生存模式OBJ.总时间 > 0;

	_root.生存模式OBJ.时钟.push([]);
	for (var i = 1; i < 本波信息.length; i++)
	{
		var 兵种信息 = 本波信息[i];
		//根据难度决定是否刷怪
		if (兵种信息.DifficultyMax && _root.计算难度等级(兵种信息.DifficultyMax) < _root.难度等级){
			_root.生存模式OBJ.时钟[当前波次].push(null);
			continue;
		}
		if(兵种信息.DifficultyMin && _root.计算难度等级(兵种信息.DifficultyMin) > _root.难度等级){
			_root.生存模式OBJ.时钟[当前波次].push(null);
			continue;
		}
		//计算总敌人数
		var quantity = 兵种信息.Quantity;
		var SpawnIndex = 兵种信息.SpawnIndex;
		此波总人数 += quantity;
		if(!isNaN(SpawnIndex) && SpawnIndex > -1){
			游戏世界["door"+SpawnIndex].僵尸型敌人总个数 += quantity;
		}else{
			游戏世界.地图.僵尸型敌人总个数 += quantity;
		}
		//将刷怪托管到帧计时器
		var Attribute = 兵种信息.RandomType ? _root.兵种库[_root.随机选择数组元素(兵种信息.RandomType)] : 兵种信息.Attribute;
		var interval = 兵种信息.Interval;
		if(interval <= 100) interval = 34;//小等于100的刷怪首帧直接加载
		if(interval < 1000) interval += i * 34;//让高频率刷怪隔帧进行
		var _loc3_ = _root.帧计时器.添加循环任务(_root.生存模式出兵, interval, Attribute, i, 当前波次);
		_root.生存模式OBJ.时钟[当前波次].push(_loc3_);
	}

	_root.stageDispatcher.publish("WaveStarted", 当前波次);
	_root.生存模式OBJ.波次时钟 = _root.帧计时器.添加生命周期任务(游戏世界, "生存模式计时", _root.生存模式计时, 1000);
};

_root.rogue模式进攻 = function(){
	var 游戏世界 = _root.gameworld;
	var rogue敌人集合表 = _root.rogue敌人集合表;
	var 波次信息 = _root.生存模式OBJ.模式部署;
	var 总波数 = 波次信息.总波数;
	var 当前波次 = _root.生存模式OBJ.波次;
	var 此波总人数 = 0;

	_root.d_波次.text = _root.获得翻译("波次") + (当前波次 + 1) + " / " + 总波数 + "";
	if(总波数 > 1){
		_root.最上层发布文字提示(_root.获得翻译("战斗开始！剩余波数：") + (总波数 - (当前波次 + 1)) + "！");
	}
	var 上波剩余时间 = _root.生存模式OBJ.总时间 - _root.生存模式OBJ.当前时间;
	_root.生存模式OBJ.当前时间 = 0;
	_root.生存模式OBJ.波次时钟 = 0;
	// _root.生存模式OBJ.FinishRequirement = Number(本波信息[0].FinishRequirement) > 0 ? Number(本波信息[0].FinishRequirement) : 0;
	_root.生存模式OBJ.FinishRequirement = 0;
	var 本波时长 = Math.floor(波次信息.初始时长 + (波次信息.最终时长 - 波次信息.初始时长) * (当前波次 + 1) / 总波数);
	if(当前波次 < 当前波次 - 1 || 本波时长 > 0){
		_root.生存模式OBJ.总时间 = 本波时长;
		var 场上剩余人数 = _root.无限地图获取剩余敌人数();
		if(当前波次 > 0 && 场上剩余人数 == 0 && 上波剩余时间 > 3){
			_root.生存模式OBJ.总时间 -= 5;//若上一波杀完且剩余时间超过3秒则减少本波时长
		}else if(场上剩余人数 > 9){
			var 加时 = 场上剩余人数 - 5;//若场上敌人到达10个则增加本波时长
			if(加时 > 30) 加时 = 30;
			_root.生存模式OBJ.总时间 += 加时;
		}
		if (_root.生存模式OBJ.总时间 < 5) _root.生存模式OBJ.总时间 = 5;
	}else{
		_root.生存模式OBJ.总时间 = 0;
	}
	_root.d_倒计时显示._visible = _root.生存模式OBJ.总时间 > 0;

	_root.生存模式OBJ.时钟.push([]);

	var 本波等级 = Math.floor(波次信息.初始敌人等级 + (波次信息.最终敌人等级 - 波次信息.初始敌人等级) * (当前波次 + 1) / 总波数);
	if(本波等级 < 1) 本波等级 = 1;
	var 本波权重 = Math.floor(波次信息.初始权重 + (波次信息.最终权重 - 波次信息.初始权重) * (当前波次 + 1) / 总波数);
	
	//根据权重随机选取一个分组
	var 分组表 = [];
	for(var i = 0; i < 波次信息.敌人分组.length; i++){
		if(波次信息.敌人分组[i].起始波次 <= 当前波次 && 波次信息.敌人分组[i].终止波次 > 当前波次) 分组表.push(波次信息.敌人分组[i]);
	}
	var 敌人集合索引表 = _root.duplicateOf(_root.根据权重获取随机对象(分组表).分类索引表);

	//从分组中选取随机1-m个集合，从每个可重复刷怪的集合中选出1-n个敌人
	_root.常用工具函数.洗牌(敌人集合索引表);
	var 敌人集合表 = [];
	var rand_len = _root.随机整数(1, 敌人集合索引表.length);
	for (var i = 0; i < rand_len; i++){
		var 敌人集合 = _root.duplicateOf(rogue敌人集合表[敌人集合索引表[i]]);
		_root.常用工具函数.洗牌(敌人集合.类型表);
		if(!(敌人集合.唯一性 && rand_len === 1)) 敌人集合.类型表.splice(_root.随机整数(1, 敌人集合.类型表.length));
		敌人集合表.push(敌人集合);
	}
	var 刷怪列表 = [];
	for(var i = 0; i < 波次信息.单波最大生成数; i++){
		var 敌人集合 = _root.根据权重反比获取随机对象(敌人集合表);
		本波权重 -= 敌人集合.权重;
		var rand = _root.随机整数(0, 敌人集合.类型表.length - 1);
		刷怪列表.push({
			Type: 敌人集合.类型表[rand],
			Weight: 敌人集合.权重
		});
		if(敌人集合.唯一性){
			敌人集合.类型表.splice(rand, 1);
			if(敌人集合.类型表.length == 0){
				for(var i = 0; i < 敌人集合表.length; i++){
					if(敌人集合表[i].length == 0) 敌人集合表.splice(i,1);
				}
				if(敌人集合表.length == 0) break;
			}
		}
		if(本波权重 <= 0) break;
	}
	if(_root.生存模式OBJ.总时间 > 0){
		if(本波权重 > 1) _root.生存模式OBJ.总时间 -= Math.floor(本波权重 * 0.5);//若权重有剩余减短本波时长
		_root.生存模式OBJ.总时间 -= _root.生存模式OBJ.总时间 % 5;//将总时长规范为5的倍数
		if (_root.生存模式OBJ.总时间 < 5) _root.生存模式OBJ.总时间 = 5;
	}

	var Quantity = 刷怪列表.length;
	for(var i = 0; i < Quantity; i++){
		var 兵种信息 = 刷怪列表[i];
		var level = 本波等级;
		// if(本波权重 > 1) level += Math.floor(本波权重 * 0.5);
		if(本波权重 < -1) level -= Math.floor(Math.sqrt(-兵种信息.Weight * 本波权重));//若权重溢出则降低本波所有敌人的等级
		if(level < 1) level = 1;
		if(level > 100) level = 100;
		兵种信息.Level = level;
		兵种信息.Attribute = _root.解析敌人属性(兵种信息);
		兵种信息.SpawnIndex = -1;
	}
	var 本波敌人 = {
		Quantity: Quantity,
		Current: 0,
		Enemies: 刷怪列表
	};

	游戏世界.地图.僵尸型敌人总个数 += Quantity;
	var interval = 500;
	var _loc3_ = _root.帧计时器.添加循环任务(_root.rogue模式出兵, interval, 本波敌人, 当前波次);
	_root.生存模式OBJ.时钟[当前波次].push(_loc3_);

	_root.stageDispatcher.publish("WaveStarted", 当前波次);
	_root.生存模式OBJ.波次时钟 = _root.帧计时器.添加生命周期任务(游戏世界, "生存模式计时", _root.生存模式计时, 1000);
};

_root.生存模式计时 = function(){
	_root.生存模式OBJ.当前时间++;
	if(_root.生存模式OBJ.总时间 > 0){
		var total_sec = _root.生存模式OBJ.总时间 - _root.生存模式OBJ.当前时间;
		var min = Math.floor(total_sec / 60);
		var sec = total_sec % 60;
		var min_str = "";
		var sec_str = "";
		if (min < 10) min_str += "0";
		min_str += min;
		if (sec < 10) sec_str += "0";
		sec_str += sec;
		_root.d_倒计时显示.text = min_str + ":" + sec_str;
	}
	_root.d_剩余敌人数.text = _root.获得翻译("剩余敌人数：") + _root.无限地图获取剩余敌人数();
	//if (_root.生存模式OBJ.总时间 - _root.生存模式OBJ.当前时间 == 5){}
	if (_root.无限地图获取剩余敌人数() <= _root.生存模式OBJ.FinishRequirement || (_root.生存模式OBJ.总时间 > 0 && total_sec <= 0))
	{
		_root.帧计时器.移除任务(_root.生存模式OBJ.波次时钟);
		_root.生存模式OBJ.波次++;
		if (_root.生存模式OBJ.波次 < _root.生存模式OBJ.模式部署.总波数){
			_root.生存模式进攻();
		}else{
			_root.无限过图模式过关();
		}
		var 本轮对话 = _root.副本对话[_root.无限过图模式关卡计数][_root.生存模式OBJ.波次];
		if (本轮对话.length > 0){
			_root.暂停 = true;
			_root.SetDialogue(本轮对话);
		}
	}
	
};

_root.无限过图模式过关 = function(){
	_root.gameworld.关卡结束 = true;
	_root.帧计时器.移除任务(_root.生存模式OBJ.波次时钟);
	_root.d_波次._visible = false;
	_root.d_剩余敌人数._visible = false;

	//加载结束动画
	var 基本配置 = _root.无限过图基本配置[_root.无限过图模式关卡计数];
	if (基本配置.Animation.Load == 0){
		_root.最上层加载外部动画(基本配置.Animation.Path);
		if (基本配置.Animation.Pause == 1){
			_root.暂停 = true;
		}
	}

	if (_root.无限过图模式关卡计数 >= _root.无限过图总关卡.length - 1){
		_root.关卡结束();
		//设置返回地图帧值
		if(基本配置.EndFrame) _root.关卡地图帧值 = 基本配置.EndFrame;
	}else{
		// _root.最上层发布文字提示(_root.获得翻译("GOGOGO！剩余战场数：") + (_root.无限过图总关卡.length - _root.无限过图模式关卡计数 - 1) + "！"); //已经不需要这种东西了
		_root.gameworld.允许通行 = true;
		var hero:MovieClip = TargetCacheManager.findHero();
		_root.效果("小过关提示动画", hero._x, hero._y,100);
		_root.stageDispatcher.publish("StageFinished");
	}
};

/*
_root.生存模式过关 = function()
{
	_root.d_剩余敌人数.text = _root.获得翻译("所有波次结束");
	_root.最上层发布文字提示(_root.d_剩余敌人数.text);
	_root.d_剩余敌人数._visible = false;
	if (_root.gameworld[_root.控制目标].hp > 0)
	{
		_root.关卡结束界面.mytext = "关卡结束！";
		_root.关卡结束界面._visible = 1;
		_root.画面效果("过关提示动画",Stage.width / 2,Stage.height / 2,100);
		_root.FinishStage(_root.当前关卡名,_root.当前关卡难度);
	}
};*/

_root.生存模式出兵 = function(兵种, 序列, 波次){
	if (!_root.生存模式OBJ.已出兵记录[波次]) _root.生存模式OBJ.已出兵记录[波次] = [];
	var 当前波次出兵记录 = _root.生存模式OBJ.已出兵记录[波次];
	if (!当前波次出兵记录[序列]) 当前波次出兵记录[序列] = 1;

	var 兵种信息 = _root.生存模式OBJ.模式部署[波次][序列];
	var 游戏世界 = _root.gameworld;
	var SpawnIndex = 兵种信息.SpawnIndex;
	var 出兵tmp等级 = isNaN(兵种信息.Level) ? 1: Number(兵种信息.Level);
	var 敌人参数 = {等级:出兵tmp等级, 名字:兵种.名字, 是否为敌人:兵种.是否为敌人, 身高:兵种.身高, 长枪:兵种.长枪, 手枪:兵种.手枪, 手枪2:兵种.手枪2, 刀:兵种.刀, 手雷:兵种.手雷, 脸型:兵种.脸型, 发型:兵种.发型, 头部装备:兵种.头部装备, 上装装备:兵种.上装装备, 下装装备:兵种.下装装备, 手部装备:兵种.手部装备, 脚部装备:兵种.脚部装备, 颈部装备:兵种.颈部装备, 性别:兵种.性别, NPC:兵种.NPC};
	//设置front的敌人默认左向
	if(SpawnIndex === "front"){
		敌人参数.方向 = "左";
	}
	//加载额外参数
	if(兵种信息.Parameters){
		_root.无限过图解析额外参数(敌人参数, 兵种信息.Parameters);
	}
	//游戏世界.attachMovie("单个敌人加载器2", "第" + 波次 + "波" + 兵种.名字 + "-" + _root.生存模式OBJ.已出兵记录[波次][序列] + random(100), _root.gameworld.getNextHighestDepth(), 敌人参数);

	do{
		var 敌人实例名:String = 兵种信息.InstanceName ? 兵种信息.InstanceName : 兵种.名字 + "_" + 波次 + "_" + 序列 + "_" + 当前波次出兵记录[序列];
		var 生成结果 = _root.无限过图生成敌人(兵种, 敌人实例名, 敌人参数, SpawnIndex, 兵种信息.x, 兵种信息.y);
		if(!生成结果) return;
		当前波次出兵记录[序列]++;
		if (当前波次出兵记录[序列] > 兵种信息.Quantity && 当前波次出兵记录[序列])
		{
			_root.帧计时器.移除任务(_root.生存模式OBJ.时钟[波次][序列 - 1]);
			return;
		}
	}while(SpawnIndex === "front" || SpawnIndex === "back");
	//若SpawnIndex设置front或back则一次性刷完
	
};

_root.rogue模式出兵 = function(本波敌人, 波次){
	if (!_root.生存模式OBJ.已出兵记录[波次]) _root.生存模式OBJ.已出兵记录[波次] = [];
	var 当前波次出兵记录 = _root.生存模式OBJ.已出兵记录[波次];
	if (!当前波次出兵记录[0]) 当前波次出兵记录[0] = 1;

	var 兵种信息 = 本波敌人.Enemies[本波敌人.Current];
	var 游戏世界 = _root.gameworld;
	var SpawnIndex = 兵种信息.SpawnIndex;
	var 出兵tmp等级 = isNaN(兵种信息.Level) ? 1: Number(兵种信息.Level);
	var Attribute = 兵种信息.Attribute;
	var 敌人参数 = {等级:出兵tmp等级, 名字:Attribute.名字, 是否为敌人:Attribute.是否为敌人, 身高:Attribute.身高, 长枪:Attribute.长枪, 手枪:Attribute.手枪, 手枪2:Attribute.手枪2, 刀:Attribute.刀, 手雷:Attribute.手雷, 脸型:Attribute.脸型, 发型:Attribute.发型, 头部装备:Attribute.头部装备, 上装装备:Attribute.上装装备, 下装装备:Attribute.下装装备, 手部装备:Attribute.手部装备, 脚部装备:Attribute.脚部装备, 颈部装备:Attribute.颈部装备, 性别:Attribute.性别, NPC:Attribute.NPC};
	//设置front的敌人默认左向
	// if(SpawnIndex === "front"){
	// 	敌人参数.方向 = "左";
	// }
	// //加载额外参数
	// if(兵种信息.Parameters){
	// 	_root.无限过图解析额外参数(敌人参数, 兵种信息.Parameters);
	// }
	
	var 敌人实例名:String = Attribute.名字 + "_" + 波次 + "_0_" + 本波敌人.Current;
	var 生成结果 = _root.无限过图生成敌人(Attribute, 敌人实例名, 敌人参数, SpawnIndex, 兵种信息.x, 兵种信息.y);
	if(!生成结果) return;
	当前波次出兵记录[0]++;
	本波敌人.Current++;
	if (本波敌人.Current >= 本波敌人.Quantity)
	{
		_root.帧计时器.移除任务(_root.生存模式OBJ.时钟[波次][0]);
		return;
	}
};


_root.无限过图生成敌人 = function(兵种, 敌人实例名, 敌人参数, SpawnIndex, 生存模式出生X, 生存模式出生Y){
	//优先使用兵种自带的坐标
	var 游戏世界 = _root.gameworld;
	var 产生源 = "地图";
	if (Number(SpawnIndex) > -1)
	{
		var 出生点 = _root.无限过图出生点[_root.无限过图模式关卡计数][Number(SpawnIndex)];
		产生源 = "door" + SpawnIndex;
		//若敌方单位大等于场上最大容纳量则不刷怪
		if(出生点.QuantityMax > 0 && 兵种.是否为敌人 && 游戏世界[产生源].僵尸型敌人场上实际人数 >= 出生点.QuantityMax){
			return false;
		}
		//优先使用兵种自带的坐标，若无自带坐标则使用出生点坐标并调用开门动画
		if(isNaN(生存模式出生X) || isNaN(生存模式出生Y)){
			生存模式出生X = 出生点.x;
			生存模式出生Y = 出生点.y;
			if(出生点.Identifier){
				生存模式出生Y += isNaN(出生点.Offset) ? 2 : 出生点.Offset; //生成位置从出生点向下平移2像素避免被出生点碰撞箱卡住，也可手动设置
				游戏世界["door"+SpawnIndex].开门();
			}
			if(出生点.BiasX && 出生点.BiasY){
				生存模式出生X += random(2*出生点.BiasX+1) - 出生点.BiasX;
				生存模式出生Y += random(2*出生点.BiasY+1) - 出生点.BiasY;
			}
		}
	}else if(isNaN(生存模式出生Y) || isNaN(生存模式出生Y)){
		switch(SpawnIndex){
			case "left":
			//左侧刷新
			var pt = _root.生存模式OBJ.获取左侧随机出生点();
			生存模式出生X = pt.x;
			生存模式出生Y = pt.y;
			break;
			case "right":
			//右侧刷新
			var pt = _root.生存模式OBJ.获取右侧随机出生点();
			生存模式出生X = pt.x;
			生存模式出生Y = pt.y;
			break;
			case "front":
			//在x∈(PlayerX+150,PlayerX+700)，y∈(Ymin+30,PlayerY-30)∪(PlayerY+30,Ymax-30)范围内随机刷新
			var 基本配置 = _root.无限过图基本配置[_root.无限过图模式关卡计数];
			var bounding = _root.Ymax - _root.Ymin > 200 ? 30 : 0;
			生存模式出生X = 基本配置.PlayerX + 150 + random(550);
			生存模式出生X = 生存模式出生X >= _root.Xmax ? _root.Xmax : 生存模式出生X;
			生存模式出生Y = _root.Ymin + bounding + random(_root.Ymax - _root.Ymin - 60 - 2*bounding);
			if(Math.abs(基本配置.PlayerY - 生存模式出生Y) < 30){
				生存模式出生Y += 60;
			}
			break;
			case "back":
			//在x∈(1024,Xmax-200)，y∈(Ymin+30,Ymax-30)范围内随机刷新
			生存模式出生X = _root.Xmax > 1224 ? 1024 + random(_root.Xmax - 1224) : _root.Xmax - random(50);
			生存模式出生Y = _root.Ymin + 30 + random(_root.Ymax - _root.Ymin - 60);
			break;
			case "door":
			//在关卡出口处刷新
			生存模式出生X = 游戏世界.门1._x + 0.5 * 游戏世界.门1._width;
			生存模式出生Y = 游戏世界.门1._y + 0.5 * 游戏世界.门1._height;
			break;
			default:
			//默认设置，1/3概率在左侧刷新，2/3概率在右侧刷新
			var pt = (random(3) === 0) ? _root.生存模式OBJ.获取左侧随机出生点() : _root.生存模式OBJ.获取右侧随机出生点();
			生存模式出生X = pt.x;
			生存模式出生Y = pt.y;
		}
	}
	敌人参数.产生源 = 产生源;
	敌人参数._x = 生存模式出生X;
	敌人参数._y = 生存模式出生Y;
	var 敌人层级 = 游戏世界.getNextHighestDepth();
	_root.加载游戏世界人物(兵种.兵种名, 敌人实例名, 敌人层级, 敌人参数);
	if (兵种.是否为敌人 === true || 兵种.是否为敌人 === null){
		游戏世界[产生源].僵尸型敌人场上实际人数++;
	}else{
		游戏世界[产生源].僵尸型敌人总个数--;
	}
	return true;
};

_root.无限地图获取剩余敌人数 = function(){
	var 游戏世界 = _root.gameworld;
	var 出生点列表 = _root.无限过图出生点[_root.无限过图模式关卡计数];
	var WaveInformation = _root.生存模式OBJ.模式部署[_root.生存模式OBJ.波次][0];
	
	var count = WaveInformation.MapNoCount ? 0 : 游戏世界.地图.僵尸型敌人总个数;
	var 出生点总数 = 出生点列表.length;
	for(var i = 0; i < 出生点总数; i++){
		if(!出生点列表[i].NoCount && 游戏世界["door"+i].僵尸型敌人总个数 > 0){
			count += 游戏世界["door"+i].僵尸型敌人总个数;
		}
	}
	return count;
}

//解析额外参数
_root.无限过图解析额外参数 = function(目标对象:Object, 参数对象:Object){
	if(typeof(参数对象) === "string"){
		var 参数表 = 参数对象.split(",");
		for(var i = 0; i < 参数表.length; i++){
			var 参数 = 参数表[i].split(":");
			if(参数.length === 2){
				var key = 参数[0];
				var val = 参数[1];
				val = isNaN(val) ? val : Number(val);
				val = val === "true" ? true: val;
				val = val === "false" ? false: val;
				目标对象[key] = val;
			}
		}
	}else{
		for(var key in 参数对象){ 
			目标对象[key] = _root.duplicateOf(参数对象[key]);
		}
	}
}


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