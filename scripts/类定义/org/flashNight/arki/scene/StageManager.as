import org.flashNight.arki.scene.*;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.component.Effect.*;

import org.flashNight.neur.Event.EventBus;

/**
StageManager 管理关卡的基础行为。
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.StageManager {
    public static var instance:StageManager; // 单例引用
    private var sceneManager:SceneManager; // SceneManager单例
    public var spawner:WaveSpawner; // 当前使用的刷怪器单例引用
    private var stageEventHandler:StageEventHandler; // StageEventHandler单例

    public var gameworld:MovieClip; // 当前gameworld
    public var environment;

    private var stageInfoList:Array;
    private var currentStageInfo:StageInfo;
    public var currentStage:Number = -1;

    public var spawnPoints:Array; // 出生点影片剪辑列表

    public var isActive = false;
    public var isCleared = false; // 当前地图是否通过
    public var isFinished = false; // 关卡是否完成
    public var isFailed = false; // 关卡是否失败
    
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
        spawner = WaveSpawner.instance;
        stageEventHandler = StageEventHandler.instance;

        data = ObjectUtil.toArray(data);
        stageInfoList = new Array(data.length);
        for(var i = 0; i < data.length; i++){
            stageInfoList[i] = new StageInfo(data[i]);
        }
        currentStage = -1;
        isActive = true;
        isFinished = false;
        isFailed = false;
    }
    
    public function initStage():Void{
        _root.当前为战斗地图 = true;
        // 进入战斗地图时卸载非战斗用数据以节省内存
        _root.NPC对话_unload("enter_battle");
        _root.佣兵配置_unload("enter_battle");
        isCleared = false;
        currentStage++;

        currentStageInfo = stageInfoList[currentStage];

        var basicInfo = currentStageInfo.basicInfo;
        var instanceInfo = currentStageInfo.instanceInfo;
        var spawnPointInfo = currentStageInfo.spawnPointInfo;
        
        gameworld = sceneManager.gameworld;
        _root.d_倒计时显示._visible = false;

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
            sp.NoCount = spinfo.NoCount === true ? true : false;
            sp.Hide = spinfo.Hide === true ? true : false;
            if(spinfo.BiasX > 0 && spinfo.BiasY > 0){
                sp.BiasX = spinfo.BiasX;
                sp.BiasY = spinfo.BiasY;
            }
        }
        gameworld.地图.僵尸型敌人总个数 = 0;
        gameworld.地图.僵尸型敌人场上实际人数 = 0;

        // 侦听玩家位置更新事件
        if(currentStageInfo.triggerInfo.length > 0){
            gameworld.dispatcher.subscribe("HeroMoved", this.handleTriggers, this);
        }

        // 将上述影片剪辑实例设置为不可枚举
        _global.ASSetPropFlags(gameworld, unIterables, 1, false);
        

        // 加载进图动画
        if (basicInfo.Animation.Load == 1) {
            _root.最上层加载外部动画(basicInfo.Animation.Path);
            if (basicInfo.Animation.Pause == 1) {
                _root.暂停 = true;
            }
        }

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

        // 注册关卡事件
        if(currentStageInfo.eventInfo.length > 0){
            for(var i=0; i<currentStageInfo.eventInfo.length; i++){
                stageEventHandler.subscribeStageEvent(currentStageInfo.eventInfo[i]);
            }
        }

        // 加载玩家
        gameworld.出生地.是否从门加载角色();

        // 重置场景切换冷却计数，防止加载期间持续按键导致的穿墙问题
        _root.场景转换函数.上次切换帧数 = _root.帧计时器.当前帧数;

        // 监听关卡完成，失败，直接进入下一张图事件
        gameworld.dispatcher.subscribeOnce("StageFinished", this.finishStage, this);
        gameworld.dispatcher.subscribeOnce("StageFailed", this.failStage, this);
        gameworld.dispatcher.subscribeOnce("NextStage", this.nextStage, this);

        // 发布开始事件
        gameworld.dispatcher.publish("Start");

        // 开始刷怪
        if(currentStageInfo.waveInfo != null) spawner.init(currentStageInfo);
    }

    public function clearStage():Void{
        if(isFinished || isFailed) return;
        isCleared = true;

        gameworld.关卡结束 = true;
        _root.无限过图计时器.刷新计时器("隐藏");
        gameworld.dispatcher.publish("Clear");

        // 加载结束动画
        var animInfo = currentStageInfo.basicInfo.Animation;
        if (animInfo.Load == 0){
            _root.最上层加载外部动画(animInfo.Path);
            if (animInfo.Pause == 1) _root.暂停 = true;
        }

        if (currentStage >= stageInfoList.length - 1){
            _root.gameworld.dispatcher.publish("StageFinished");
        }else{
            gameworld.允许通行 = true;
            var hero:MovieClip = TargetCacheManager.findHero();
            EffectSystem.Effect("小过关提示动画", hero._x, hero._y, 100);
        }
    }

    public function finishStage():Void{
        if(isFinished || isFailed) return;
        isFinished = true;
        _root.关卡结束();
        //设置返回地图帧值
        if(currentStageInfo.basicInfo.EndFrame) _root.关卡地图帧值 = currentStageInfo.basicInfo.EndFrame;
    }

    public function failStage():Void{
        if(isFinished || isFailed) return;
        isFailed = true;

        gameworld.允许通行 = false;
        gameworld.关卡结束 = false;
        _root.关卡结束界面.关卡失败();
        
        _root.无限过图计时器.刷新计时器("隐藏");
        gameworld.dispatcher.publish("StageFailed");

        gameworld.通关箭头._visible = false;
    }

    public function nextStage():Void{
        if(isFinished || isFailed) return;
        if(currentStage < stageInfoList.length - 1){
            _root.场景进入位置名 = "出生地";
            _root.转场景记录数据();
            _root.淡出动画.淡出跳转帧("wuxianguotu_1");
        }else{
            _root.返回基地();
        }
    }

    public function closeStage():Void{
        gameworld = null;
        environment = null;
        currentStageInfo = null;
        spawnPoints = null;

        spawner.close();
        stageEventHandler.clear();
        isCleared = false;
    }

    public function clear():Void{
        _root.当前为战斗地图 = false;
        isActive = false;
        stageInfoList = null;
        currentStage = -1;
    }

    /**
     * 完整清理方法（幂等）
     * 断开所有循环引用，释放对gameworld、MovieClip的强引用
     * 用于游戏重启时的彻底清理
     */
    public function dispose():Void {
        // 幂等检查：如果已经清理过则直接返回
        if (sceneManager == null && spawner == null && stageEventHandler == null) {
            return;
        }

        // 先调用普通清理
        if (isActive) {
            clear();
        }

        // 调用关卡关闭清理
        closeStage();

        // 断开与其他单例的循环引用
        sceneManager = null;
        spawner = null;
        stageEventHandler = null;

        // 重置状态标志
        isCleared = false;
        isFinished = false;
        isFailed = false;
    }

    /**
     * 重置单例状态（用于游戏重启后重新初始化）
     */
    public function reset():Void {
        dispose();
        // 单例保持存在，但状态重置为初始
        currentStage = -1;
        isActive = false;
        isCleared = false;
        isFinished = false;
        isFailed = false;
    }



    // 执行压力板事件，目前每个压力板只能被踩下一次
    private function handleTriggers(heroX:Number, heroZ:Number){
        if(currentStageInfo.triggerInfo.length <= 0){
            return;
        }

        for(var i = currentStageInfo.triggerInfo.length - 1; i > -1; i--){
            var trigger = currentStageInfo.triggerInfo[i];
            if(!isNaN(trigger.Xmin) && heroX <= trigger.Xmin) continue;
            if(!isNaN(trigger.Xmax) && heroX >= trigger.Xmax) continue;
            if(!isNaN(trigger.Ymin) && heroZ <= trigger.Ymin) continue;
            if(!isNaN(trigger.Ymax) && heroZ >= trigger.Ymax) continue;
            // 发布压力板事件并移除压力板
            gameworld.dispatcher.publish("TriggerPressed", trigger.id);
            currentStageInfo.triggerInfo.splice(i,1);
        }
    }

}