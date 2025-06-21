import org.flashNight.arki.scene.*;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/**
StageManager 管理关卡的基础行为。
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.StageManager {
    public static var instance:StageManager; // 单例引用
    private var sceneManager:SceneManager; // SceneManager单例
    private var waveSpawner:WaveSpawner; // WaveSpawner单例
    private var stageEventHandler:StageEventHandler; // StageEventHandler单例

    public var gameworld:MovieClip; // 当前gameworld
    public var environment;

    private var stageInfoList:Array;
    private var currentStageInfo:StageInfo;
    public var currentStage:Number = -1;

    public var spawnPoints:Array; // 出生点影片剪辑列表

    public var isFinished = false;
    public var isFailed = false;
    
    /**
     * 单例获取：返回全局唯一实例
     */
    public static function getInstance():StageManager {
        return instance || (instance = new StageManager());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function StageManager() {
    }

    
    public function initialize(data):Void{
        sceneManager = SceneManager.instance;
        waveSpawner = WaveSpawner.instance;
        stageEventHandler = StageEventHandler.instance;

        data = ObjectUtil.toArray(data);
        stageInfoList = new Array(data.length);
        for(var i = 0; i < data.length; i++){
            stageInfoList[i] = new StageInfo(data[i]);
        }
        currentStage = -1;
    }
    
    public function initStage():Void{
        _root.当前为战斗地图 = true;
        currentStage++;

        currentStageInfo = stageInfoList[currentStage];

        var basicInfo = currentStageInfo.basicInfo;
        var instanceInfo = currentStageInfo.instanceInfo;
        var spawnPointInfo = currentStageInfo.spawnPointInfo;
        // var dialogues = currentStageInfo.dialogues;
        
        gameworld = sceneManager.gameworld;

        isFinished = false;
        isFailed = false;

        stageEventHandler.init(gameworld);

        // 附加箭头出现事件
        if(currentStage < stageInfoList.length - 1){
            gameworld.dispatcher.subscribeOnce("Clear", function() {
                this.显示箭头();
            }, gameworld.通关箭头);
        }

        // 设置本张图结束后的过场背景
        if (basicInfo.LoadingImage) {
            _root.加载背景列表.本次背景 = basicInfo.LoadingImage;
        }

        // 设置地图尺寸
        var bglist = basicInfo.Background.split("/");
        var url = bglist[bglist.length - 1];

        environment = ObjectUtil.clone(_root.天气系统.关卡环境设置[url]);
        if (!environment) {
            environment = ObjectUtil.clone(_root.天气系统.关卡环境设置.Default);
        }
        //配置关卡环境参数
        if (basicInfo.Environment) {
            environment = _root.配置环境信息(basicInfo.Environment, environment);
        }
        _root.天气系统.无限过图环境信息 = environment;

        if (environment.对齐原点) {
            gameworld.背景._x = 0;
            gameworld.背景._y = 0;
        }
        _root.Xmax = environment.Xmax;
        _root.Xmin = environment.Xmin;
        _root.Ymax = environment.Ymax;
        _root.Ymin = environment.Ymin;
        gameworld.背景长 = environment.背景长;
        gameworld.背景高 = environment.背景高;
        
        var 游戏世界门1 = gameworld.门1;
        var 门1数据 = environment.门[1];
        gameworld.门朝向 = 门1数据.Direction ? 门1数据.Direction : "右";
        
        if(门1数据.x0 && 门1数据.y0 && 门1数据.x1 && 门1数据.y1){
            游戏世界门1._x = 门1数据.x0;
            游戏世界门1._y = 门1数据.y0;
            游戏世界门1._width = 门1数据.x1 - 门1数据.x0;
            游戏世界门1._height = 门1数据.y1 - 门1数据.y0;
        }else if(gameworld.门朝向 === "左"){
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
        if(门1数据.Identifier || 门1数据.url){
            var door1inst = sceneManager.addInstance(门1数据, "Door1Instance");
            door1inst._x = (门1数据.x1 + 门1数据.x0) * 0.5;
            door1inst._y = (门1数据.y1 + 门1数据.y0) * 0.5;
            door1inst.swapDepths(door1inst._y);
        }
        gameworld.允许通行 = false;
        gameworld.关卡结束 = false;

        // 添加动态尺寸的位图层
        sceneManager.addBodyLayers(gameworld.背景长, gameworld.背景高);

        // 绘制碰撞箱
        _root.通过数组绘制地图碰撞箱(environment.地图碰撞箱);
        
        
        // 设置玩家出生地，若未配置PlayerX或PlayerY则设置为无限过图默认位置(90,390)
        if (isNaN(basicInfo.PlayerX) || isNaN(basicInfo.PlayerY)) {
            basicInfo.PlayerX = _root.Xmin + 50;
            basicInfo.PlayerY = _root.Ymin + 60;
        }
        gameworld.出生地.是否从门加载主角 = true;
        gameworld.出生地._x = basicInfo.PlayerX;
        gameworld.出生地._y = basicInfo.PlayerY;
        gameworld.出生地.是否从门加载角色 = _root.场景转换函数.是否从门加载角色;
        gameworld.出生地.是否从门加载角色();
        
        // 将上述属性设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["背景", "背景长", "背景高", "门朝向", "允许通行", "关卡结束", "Xmax", "Xmin", "Ymax", "Ymin", "通关箭头", "出生地"], 1, false);

        
        var unIterables = []; // 记录无需枚举的影片剪辑实例名
        var instName;
        // 放置环境地图元件
        if(environment.背景元素){
            for(var i = 0; i < environment.背景元素.length; i++){
                unIterables.push(instName = environment.背景元素[i].name ? environment.背景元素[i].name : "bgInstance" + i);
                sceneManager.addInstance(environment.背景元素[i], instName);
            }
        }
        // 放置关卡地图元件
        for (var i = 0; i < instanceInfo.length; i++) {
            unIterables.push(instName = "stageInstance" + i);
            sceneManager.addInstance(instanceInfo[i], instName);
        }

        // 放置出生点，初始化各个刷怪点的总个数和场上人数
        spawnPoints = new Array(spawnPointInfo.length);
        for (var i = 0; i < spawnPointInfo.length; i++) {
            var spinfo = spawnPointInfo[i];
            unIterables.push(instName = "door" + i)
            var sp = spawnPoints[i] = sceneManager.addInstance(spinfo, instName);
            sp.僵尸型敌人总个数 = 0;
            sp.僵尸型敌人场上实际人数 = 0;
            if(spinfo.Identifier){
                sp.Identifier = spinfo.Identifier;
                if(!isNaN(spinfo.Offset)) sp.Offset = spinfo.Offset;
            }
            sp.QuantityMax = spinfo.QuantityMax;
            sp.NoCount = spinfo.NoCount ? true: false;
            if(spinfo.BiasX > 0 && spinfo.BiasY > 0){
                sp.BiasX = spinfo.BiasX;
                sp.BiasY = spinfo.BiasY;
            }
        }
        gameworld.地图.僵尸型敌人总个数 = 0;
        gameworld.地图.僵尸型敌人场上实际人数 = 0;

        // 将上述影片剪辑实例设置为不可枚举
        _global.ASSetPropFlags(gameworld, unIterables, 1, false);
        

        // 加载进图动画
        if (basicInfo.Animation.Load == 1) {
            _root.最上层加载外部动画(basicInfo.Animation.Path);
            if (basicInfo.Animation.Pause == 1) {
                _root.暂停 = true;
            }
        }

        // 加载进图对话
        // var 本轮对话 = dialogues[0];
        // if (本轮对话.length > 0) {
        //     _root.暂停 = true;
        //     _root.SetDialogue(本轮对话);
        // }

        //播放场景bgm
        if(basicInfo.BGM){
            if(basicInfo.BGM.Command == "play"){
                _root.soundEffectManager.playBGM(basicInfo.BGM.Title, basicInfo.BGM.Loop, null);
            }else if (basicInfo.BGM.Command == "stop"){
                _root.soundEffectManager.stopBGM();
            }
        }

        // 调用回调函数
        if(basicInfo.CallbackFunction.Name){
            if(basicInfo.CallbackFunction.Parameter){
                var para = _root.配置数据为数组(basicInfo.CallbackFunction.Parameter);
                _root.关卡回调函数[basicInfo.CallbackFunction.Name].apply(_root.关卡回调函数,para);
            }else{
                _root.关卡回调函数[basicInfo.CallbackFunction.Name]();
            }
        }
        
        // 加载场景
        _root.加载场景背景(basicInfo.Background);
        _root.加载后景(environment);

        // 侦听关卡事件
        if(currentStageInfo.eventInfo.length > 0){
            for(var i=0; i<currentStageInfo.eventInfo.length; i++){
                stageEventHandler.subscribeStageEvent(currentStageInfo.eventInfo[i]);
            }
        }

        // 发布开始事件
        gameworld.dispatcher.publish("Start");

        // 开始刷怪
        if(currentStageInfo.waveInfo != null) waveSpawner.init(currentStageInfo);
    }

    public function finishStage():Void{
        if(isFailed) return;
        isFinished = true;

        gameworld.关卡结束 = true;
        _root.d_波次._visible = false;
        _root.d_剩余敌人数._visible = false;
        gameworld.dispatcher.publish("Clear");

        // 加载结束动画
        var animInfo = currentStageInfo.basicInfo.Animation;
        if (animInfo.Load == 0){
            _root.最上层加载外部动画(animInfo.Path);
            if (animInfo.Pause == 1) _root.暂停 = true;
        }

        if (currentStage >= stageInfoList.length - 1){
            _root.关卡结束();
            //设置返回地图帧值
            if(currentStageInfo.basicInfo.EndFrame) _root.关卡地图帧值 = currentStageInfo.basicInfo.EndFrame;
        }else{
            gameworld.允许通行 = true;
            var hero:MovieClip = TargetCacheManager.findHero();
            _root.效果("小过关提示动画", hero._x, hero._y,100);
        }
    }

    public function failStage():Void{
        if(isFinished) return;
        isFailed = true;

        gameworld.允许通行 = false;
        gameworld.关卡结束 = false;
        _root.d_波次._visible = false;
        _root.d_剩余敌人数._visible = false;
        gameworld.dispatcher.publish("StageFailed");
    }

    public function closeStage():Void{
        gameworld = null;
        environment = null;
        currentStageInfo = null;
        spawnPoints = null;

        waveSpawner.close();
        stageEventHandler.clear();
    }

    public function clear():Void{
        stageInfoList = null;
        currentStage = -1;
    }

}