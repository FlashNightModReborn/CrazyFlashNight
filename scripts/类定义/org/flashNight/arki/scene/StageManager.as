import org.flashNight.arki.scene.*;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.arki.weather.EnvironmentConfig;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.arki.merc.ArenaCalibrationService;

/**
StageManager 管理关卡的基础行为。
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.StageManager {
    public static var instance:StageManager; // 单例引用
    private var sceneManager:SceneManager; // SceneManager单例
    public var spawner:WaveSpawner; // 当前使用的刷怪器单例引用
    private var stageEventHandler:StageEventHandler; // StageEventHandler单例
    private var timePoolController:StageTimePoolController; // GameStage 会话级跨图计时池

    public var gameworld:MovieClip; // 当前gameworld
    public var environment;

    private var stageInfoList:Array;
    private var currentStageInfo:StageInfo;
    private var stageStartToken:String = "";
    private var calibrationHostInitialization:Boolean = false;
    // XML loader 只把奖励/掉落数据交给 exact 预载 owner。选关 final gate 与淡出
    // 尚未接受前不得覆盖旧场景缓存；首个 gameplay init 消费 token 后才提交。
    private var hasPreparedStageRewardCache:Boolean = false;
    private var preparedStageRewards:Array;
    private var preparedStageRewardConfig:Array;
    private var preparedStageDropName:String = "";
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

    
    public function initialize(data, timePoolData, reservationToken:String,
            allowCalibrationHost:Boolean, stageRewards:Array,
            stageDropName:String, stageRewardConfig:Array):Boolean{
        var incomingToken:String = String(reservationToken || "");
        var calibrationAdmission:Boolean = allowCalibrationHost === true;
        // 所有无限过图（含不创建 run 的斗兽标定 host）都必须携带 exact
        // reservation，确保晚失败只能撤销自己，不能误清随后到达的 B 请求。
        if (incomingToken == ""
                || !StageRunSession.isStageStartReservationValid(incomingToken)
                || (calibrationAdmission
                    && !StageRunSession.matchesStageStartReservation(
                        incomingToken, "arena_calibration", "DEATH MATCH角斗场"))) {
            trace("[StageManager] stage-start admission rejected at initialize");
            return false;
        }
        stageStartToken = incomingToken;
        calibrationHostInitialization = calibrationAdmission;
        clearPreparedStageRewardCache();
        if (stageRewards != undefined) {
            hasPreparedStageRewardCache = true;
            preparedStageRewards = stageRewards instanceof Array
                ? stageRewards.slice() : [];
            preparedStageRewardConfig = stageRewardConfig instanceof Array
                ? stageRewardConfig.slice() : [];
            preparedStageDropName = String(stageDropName || "");
        }
        var initialized:Boolean = false;
        var previousTimePool:StageTimePoolController = timePoolController;
        // 先从权威 manager 脱钩旧投影；清 HUD 或 Host socket 抛错不得留下
        // “新 token + 旧 manager”半初始化状态。
        timePoolController = null;
        try {
            clearTimePoolBestEffort(previousTimePool);
            sceneManager = SceneManager.instance;
            spawner = WaveSpawner.instance;
            stageEventHandler = StageEventHandler.instance;
            data = ObjectUtil.toArray(data);
            if (data == null || data.length == 0) {
                throw new Error("stage list is empty");
            }
            stageInfoList = new Array(data.length);
            for(var i = 0; i < data.length; i++){
                stageInfoList[i] = new StageInfo(data[i]);
            }

            var refsByStage:Array = new Array(stageInfoList.length);
            for (var j:Number = 0; j < stageInfoList.length; j++) {
                refsByStage[j] = stageInfoList[j].timePoolRefs;
            }
            timePoolController = new StageTimePoolController();
            initialized = timePoolController.initialize(timePoolData, refsByStage);
        } catch (initializeError) {
            trace("[StageManager] initialize exception: " + initializeError);
            initialized = false;
        }
        if (!initialized) {
            trace("[StageTimePool] invalid config: "
                + getTimePoolValidationError());
            var rejectedTimePool:StageTimePoolController = timePoolController;
            timePoolController = null;
            stageInfoList = null;
            currentStageInfo = null;
            currentStage = -1;
            isActive = false;
            calibrationHostInitialization = false;
            cancelStoredStageStart();
            clearTimePoolBestEffort(rejectedTimePool);
            return false;
        }
        currentStage = -1;
        isActive = true;
        isFinished = false;
        isFailed = false;
        return true;
    }

    public function initStage():Void{
        // initialize 可能只是在选关/角斗场内异步预载。真正进入首个 substage 时才消费
        // stage-start reservation 并建立 run；后续 nextStage 的 currentStage >= 0，沿用同一 run。
        var calibrationFirstStage:Boolean = currentStage < 0
            && calibrationHostInitialization && isCalibrationHostStage();
        var initStageToken:String = stageStartToken;
        try {
        if (currentStage < 0 && !calibrationFirstStage
                && !StageRunSession.begin(String(_root.当前关卡名),
                    String(_root.当前关卡难度), stageStartToken)) {
            trace("[StageManager] stage run admission rejected at first initStage");
            var rejectedRunTimePool:StageTimePoolController = timePoolController;
            timePoolController = null;
            stageInfoList = null;
            currentStageInfo = null;
            isActive = false;
            calibrationHostInitialization = false;
            cancelStoredStageStart();
            clearTimePoolBestEffort(rejectedRunTimePool);
            return;
        }
        if (currentStage < 0) {
            if (calibrationFirstStage
                    && !StageRunSession.cancelStageStart(stageStartToken)) {
                trace("[StageManager] calibration admission token was already cancelled");
                // globals 已在 fade 前提交；即使 exact token 被外部取消，也要把
                // 本 calibration 请求交回服务端状态机恢复 snapshot，不能留下
                // calibration_active 永久挡住后续普通关卡。
                try {
                    ArenaCalibrationService.onCalibrationStageInitializationFailed(
                        stageStartToken);
                } catch (cancelledCalibrationHandoffError) {
                    trace("[StageManager] cancelled calibration handoff failed: "
                        + cancelledCalibrationHandoffError);
                }
                var rejectedCalibrationTimePool:StageTimePoolController = timePoolController;
                timePoolController = null;
                stageInfoList = null;
                currentStageInfo = null;
                isActive = false;
                stageStartToken = "";
                calibrationHostInitialization = false;
                clearTimePoolBestEffort(rejectedCalibrationTimePool);
                return;
            }
            stageStartToken = "";
            calibrationHostInitialization = false;
        }
        if (currentStage < 0 && !commitPreparedStageRewardCache()) {
            throw new Error("prepared stage reward cache commit failed");
        }
        _root.当前为战斗地图 = true;
        // [Phase 3] NPC对话/佣兵配置 unload 已移除 — Launcher 是唯一数据源
        // NPC对话存在 MC 上（随 MC 销毁 GC），佣兵数据由 _withCleanup refcount 管理
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

        var envConfig:EnvironmentConfig = WeatherSystem.getInstance().getEnvConfig();
        environment = envConfig.getStageEnv(url);
        if (!environment) {
            environment = envConfig.getStageEnvDefault();
        }
        //配置关卡环境参数
        if (basicInfo.Environment) {
            environment = EnvironmentConfig.parseEnvironmentInfo(basicInfo.Environment, environment);
        }
        envConfig.setInfiniteMapEnvInfo(environment);

        if (environment.对齐原点) {
            gameworld.背景._x = 0;
            gameworld.背景._y = 0;
        }
        _root.Xmax = environment.Xmax;
        _root.Xmin = environment.Xmin;
        _root.Ymax = environment.Ymax;
        _root.Ymin = environment.Ymin;
        // 用精确场景边界覆盖 initGameWorld 的默认标定
        DepthManager.instance.calibrate(_root.Ymin, _root.Ymax);
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
            DepthManager.instance.updateDepth(door1inst, door1inst._y);
        }
        gameworld.允许通行 = false;
        gameworld.关卡结束 = false;

        // 添加动态尺寸的位图层
        sceneManager.addBodyLayers(gameworld.背景长, gameworld.背景高);

        // 绘制碰撞箱
        _root.绘制地图碰撞箱();
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

        // 放置可拾取物
        if (currentStageInfo.pickupInfo.length > 0){
            for (var i = 0; i < currentStageInfo.pickupInfo.length; i++) {
                var pickup = currentStageInfo.pickupInfo[i];
                var params = pickup.Parameters != null ? ObjectUtil.clone(pickup.Parameters) : {};
                if(pickup.OnPickup){
                    params.onPickup = pickup.OnPickup;
                }
                _root.pickupItemManager.createCollectible(
                    pickup.Name, pickup.Value, pickup.x, pickup.y, false, params
                );
            }
        }

        // 侦听玩家位置更新事件
        if(currentStageInfo.triggerInfo.length > 0){
            gameworld.dispatcher.subscribe("HeroMoved", this.handleTriggers, this);
        }

        // 将上述影片剪辑实例设置为不可枚举
        _global.ASSetPropFlags(gameworld, unIterables, 1, false);

        if (isCalibrationHostStage()) {
            initCalibrationHostStage(basicInfo);
            return;
        }

        timePoolController.enterStage(currentStage);
        flushTimePoolUi();
        

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
                _root.soundEffectManager.playBGMWithSource(basicInfo.BGM.Title, "stage", basicInfo.BGM.Loop, null);
            }else if (basicInfo.BGM.Command == "stop"){
                _root.soundEffectManager.stopBGMWithSource("stage");
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
        } catch (stageSetupError) {
            handleInitStageFailure(calibrationFirstStage, initStageToken, stageSetupError);
        }
    }

    /** 每帧在 WaveSpawner.tick() 之后调用，使同帧通关优先于超时。 */
    public function tick():Void {
        if (isActive && !isFinished && !isFailed && _root.暂停 !== true) {
            StageRunSession.tick();
        }
        if (!isActive || isCleared || isFinished || isFailed
                || gameworld == null || timePoolController == null
                || _root.暂停 === true) {
            return;
        }

        var expiredPoolId:String = timePoolController.tick(true);
        flushTimePoolUi();
        if (expiredPoolId != null && !isCleared && !isFinished && !isFailed) {
            trace("[StageTimePool] expired: " + expiredPoolId);
            failStage();
        }
    }

    public function clearStage():Void{
        if(isFinished || isFailed) return;
        isCleared = true;

        leaveTimePoolBestEffort(timePoolController);

        gameworld.关卡结束 = true;
        // 快车道隐藏刘海计时器
        hideNativeStageUiBestEffort();
        publishStageEventBestEffort(gameworld.dispatcher, "Clear");

        // 加载结束动画
        var animInfo = currentStageInfo.basicInfo.Animation;
        if (animInfo.Load == 0){
            try {
                _root.最上层加载外部动画(animInfo.Path);
                if (animInfo.Pause == 1) _root.暂停 = true;
            } catch (clearAnimationError) {
                trace("[StageManager] clear animation projection failed: "
                    + clearAnimationError);
            }
        }

        if (currentStage >= stageInfoList.length - 1){
            publishStageEventBestEffort(_root.gameworld.dispatcher, "StageFinished");
            // EventBus 任一较早 listener 抛错都可能阻断本 manager 的 once
            // listener；无条件走一次幂等权威提交，不能只相信事件投影。
            finishStage();
        }else{
            try {
                gameworld.允许通行 = true;
                var hero:MovieClip = TargetCacheManager.findHero();
                EffectSystem.Effect("小过关提示动画", hero._x, hero._y, 100);
            } catch (clearProjectionError) {
                trace("[StageManager] clear projection failed: " + clearProjectionError);
            }
        }
    }

    public function finishStage():Void{
        if(isFinished || isFailed) return;
        isFinished = true;
        clearTimePoolBestEffort(timePoolController);
        StageRunSession.finish("victory");
        try {
            _root.关卡结束();
        } catch (finishCallbackError) {
            trace("[StageManager] finish callback failed: " + finishCallbackError);
        }
        //设置返回地图帧值
        if(currentStageInfo.basicInfo.EndFrame) _root.关卡地图帧值 = currentStageInfo.basicInfo.EndFrame;
    }

    public function failStage():Void{
        if(isFinished || isFailed) return;
        isFailed = true;

        clearTimePoolBestEffort(timePoolController);

        gameworld.允许通行 = false;
        gameworld.关卡结束 = false;
        StageRunSession.finish("failure");
        
        // 快车道隐藏刘海计时器
        hideNativeStageUiBestEffort();
        publishStageEventBestEffort(gameworld.dispatcher, "StageFailed");

        try {
            gameworld.通关箭头._visible = false;
        } catch (failureProjectionError) {
            trace("[StageManager] failure projection failed: " + failureProjectionError);
        }
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
        if (timePoolController != null) {
            leaveTimePoolBestEffort(timePoolController);
        }
        gameworld = null;
        environment = null;
        currentStageInfo = null;
        spawnPoints = null;
        isCleared = false;

        try {
            if (spawner != null) spawner.close();
        } catch (spawnerCloseError) {
            trace("[StageManager] spawner close failed: " + spawnerCloseError);
        }
        try {
            if (stageEventHandler != null) stageEventHandler.clear();
        } catch (handlerClearError) {
            trace("[StageManager] stage handler clear failed: " + handlerClearError);
        }
    }

    public function clear():Void{
        if (!StageRunSession.canClearStageManager()) {
            trace("[StageManager] clear rejected before StageRunSession return started");
            return;
        }
        if (currentStage < 0) {
            cancelStoredStageStart();
        }
        _root.当前为战斗地图 = false;
        var clearedTimePool:StageTimePoolController = timePoolController;
        timePoolController = null;
        isActive = false;
        stageInfoList = null;
        currentStageInfo = null;
        currentStage = -1;
        calibrationHostInitialization = false;
        clearTimePoolBestEffort(clearedTimePool);
    }

    public function getTimePoolValidationError():String {
        return timePoolController == null
            ? "计时池控制器未初始化" : timePoolController.getValidationError();
    }

    private function cancelStoredStageStart():Void {
        var token:String = stageStartToken;
        stageStartToken = "";
        clearPreparedStageRewardCache();
        if (token != "") StageRunSession.cancelStageStart(token);
    }

    private function clearPreparedStageRewardCache():Void {
        hasPreparedStageRewardCache = false;
        preparedStageRewards = null;
        preparedStageRewardConfig = null;
        preparedStageDropName = "";
    }

    /** 首帧接管后的唯一奖励/掉落缓存提交点。 */
    private function commitPreparedStageRewardCache():Boolean {
        if (!hasPreparedStageRewardCache) return true;
        var rewards:Array = preparedStageRewards;
        var rewardConfig:Array = preparedStageRewardConfig;
        var stageName:String = preparedStageDropName;
        try {
            // 先完成可能抛错的索引更新，再发布奖励数组。否则索引失败会把旧场景
            // 奖励替换成一个并未成功接管 gameplay 的候选关卡奖励，形成半提交。
            if (stageName != "" && rewardConfig instanceof Array
                    && rewardConfig.length > 0 && rewardConfig[0] != null) {
                org.flashNight.arki.item.obtain.ItemObtainIndex.getInstance()
                    .updateStageDrops(stageName, rewardConfig);
            }
            _root.关卡可获得奖励品 = rewards instanceof Array ? rewards : [];
        } catch (rewardCacheError) {
            trace("[StageManager] prepared reward cache commit failed: "
                + rewardCacheError);
            return false;
        }
        clearPreparedStageRewardCache();
        return true;
    }

    /**
     * 只撤销尚未进入首帧、且 exact token 仍属于本 manager 的预载。
     * A 的迟到错误遇到已经覆盖为 B 的 token 时必须保持零副作用。
     */
    public function abortPreparedStage(token:String):Boolean {
        var exactToken:String = String(token || "");
        if (currentStage >= 0 || exactToken == ""
                || stageStartToken == "" || stageStartToken !== exactToken) {
            return false;
        }
        StageRunSession.cancelStageStart(exactToken);
        stageStartToken = "";
        var abandonedTimePool:StageTimePoolController = timePoolController;
        timePoolController = null;
        stageInfoList = null;
        currentStageInfo = null;
        currentStage = -1;
        isActive = false;
        calibrationHostInitialization = false;
        clearPreparedStageRewardCache();
        clearTimePoolBestEffort(abandonedTimePool);
        return true;
    }

    /**
     * initStage 的同步 setup 已可能触及场景对象。普通关卡先提交 failure，再走
     * canonical 返回；若 fade 未接受则保留 fail-stopped manager 供同一返回动作重试，
     * 不能把画面留在战斗帧、却把权威状态伪装成已经离场。标定 host 无玩家关卡，
     * 继续走自身 exact failure 入口并完整撤销预载。
     */
    private function handleInitStageFailure(calibrationFirstStage:Boolean,
            expectedToken:String, setupError):Void {
        trace("[StageManager] initStage setup failed: " + setupError);
        clearPreparedStageRewardCache();
        if (calibrationFirstStage) {
            try {
                ArenaCalibrationService.onCalibrationStageInitializationFailed(
                    expectedToken);
            } catch (calibrationFailureError) {
                trace("[StageManager] calibration setup failure handoff failed: "
                    + calibrationFailureError);
                try { StageRunSession.cancelStageStart(expectedToken); }
                catch (ignoredCalibrationCancel) {}
            }
            finalizeInitStageFailureCleanup();
            return;
        } else {
            try { StageRunSession.cancelStageStart(expectedToken); }
            catch (ignoredStageCancel) {}
            try {
                StageRunSession.finish("failure");
            } catch (terminalizeError) {
                trace("[StageManager] failed setup terminalization failed: "
                    + terminalizeError);
            }

            var returnAccepted:Boolean = false;
            try {
                if (typeof _root.返回基地 == "function") {
                    returnAccepted = _root.返回基地() === true;
                }
            } catch (returnError) {
                trace("[StageManager] failed setup canonical return failed: "
                    + returnError);
            }
            if (!returnAccepted) {
                preserveFailedStageForReturnRetry();
                return;
            }
        }

        finalizeInitStageFailureCleanup();
    }

    /** canonical fade 已接受后，幂等清掉 setup 留下的所有 manager 引用。 */
    private function finalizeInitStageFailureCleanup():Void {
        var failedTimePool:StageTimePoolController = timePoolController;
        timePoolController = null;
        stageStartToken = "";
        calibrationHostInitialization = false;
        _root.当前为战斗地图 = false;
        isActive = false;
        isCleared = false;
        isFinished = false;
        isFailed = true;
        stageInfoList = null;
        currentStageInfo = null;
        currentStage = -1;
        gameworld = null;
        environment = null;
        spawnPoints = null;

        try {
            if (spawner != null) spawner.close();
        } catch (failedSpawnerClose) {
            trace("[StageManager] failed setup spawner close failed: "
                + failedSpawnerClose);
        }
        try {
            if (stageEventHandler != null) stageEventHandler.clear();
        } catch (failedHandlerClear) {
            trace("[StageManager] failed setup handler clear failed: "
                + failedHandlerClear);
        }
        clearTimePoolBestEffort(failedTimePool);
    }

    /**
     * canonical return/fade 暂未接受：停止 tick/spawn，但保留战斗帧与 manager
     * identity，使玩家第二次返回可重试同一 StageRunSession 冻结与 fade。
     */
    private function preserveFailedStageForReturnRetry():Void {
        var failedTimePool:StageTimePoolController = timePoolController;
        timePoolController = null;
        stageStartToken = "";
        calibrationHostInitialization = false;
        isActive = true;
        isCleared = false;
        isFinished = false;
        isFailed = true;
        _root.当前为战斗地图 = true;

        try {
            if (gameworld != null) {
                gameworld.允许通行 = false;
                gameworld.关卡结束 = false;
            }
        } catch (failedWorldStopError) {
            trace("[StageManager] failed setup world stop failed: "
                + failedWorldStopError);
        }
        try {
            if (spawner != null) spawner.close();
        } catch (failedSpawnerStop) {
            trace("[StageManager] failed setup spawner stop failed: "
                + failedSpawnerStop);
        }
        try {
            if (stageEventHandler != null) stageEventHandler.clear();
        } catch (failedHandlerStop) {
            trace("[StageManager] failed setup handler stop failed: "
                + failedHandlerStop);
        }
        clearTimePoolBestEffort(failedTimePool);
    }

    private function publishStageEventBestEffort(dispatcher:Object,
            eventName:String):Void {
        try {
            if (dispatcher != null && typeof dispatcher.publish == "function") {
                dispatcher.publish(eventName);
            }
        } catch (publishError) {
            trace("[StageManager] stage event " + eventName + " failed: "
                + publishError);
        }
    }

    private function clearTimePoolBestEffort(controller:StageTimePoolController):Void {
        if (controller == null) return;
        try {
            controller.clear();
        } catch (clearError) {
            trace("[StageTimePool] clear projection failed: " + clearError);
        }
        flushTimePoolUi(controller);
    }

    private function leaveTimePoolBestEffort(controller:StageTimePoolController):Void {
        if (controller == null) return;
        try {
            controller.leaveStage();
        } catch (leaveError) {
            trace("[StageTimePool] leave projection failed: " + leaveError);
        }
        flushTimePoolUi(controller);
    }

    private function flushTimePoolUi(controllerOverride):Void {
        var controller:StageTimePoolController = controllerOverride == undefined
            ? timePoolController : controllerOverride;
        if (controller == null) return;
        var commands:Array;
        try {
            commands = controller.drainUiCommands();
        } catch (drainError) {
            trace("[StageTimePool] UI drain failed: " + drainError);
            return;
        }
        if (commands == null) return;
        if (commands.length == 0) return;

        var sm:Object;
        try {
            sm = _root.server;
            if (sm == null || sm.isSocketConnected !== true) return;
        } catch (socketStateError) {
            trace("[StageTimePool] socket state projection failed: " + socketStateError);
            return;
        }
        for (var i:Number = 0; i < commands.length; i++) {
            var command:Object = commands[i];
            try {
                if (command.type == "set") {
                    sm.sendSocketMessage("T+|" + command.id + "|"
                        + command.remainingSeconds + "|" + command.label);
                } else if (command.type == "clear") {
                    sm.sendSocketMessage("T-|" + command.id);
                } else if (command.type == "clearAll") {
                    sm.sendSocketMessage("T!");
                }
            } catch (socketSendError) {
                trace("[StageTimePool] UI send failed: " + socketSendError);
            }
        }
    }

    private function hideNativeStageUiBestEffort():Void {
        try {
            var sm:Object = _root.server;
            if (sm != null && sm.isSocketConnected === true) {
                sm.sendSocketMessage("W隐藏");
            }
        } catch (hideError) {
            trace("[StageManager] native stage UI hide failed: " + hideError);
        }
    }

    /**
     * 完整清理方法（幂等）
     * 断开所有循环引用，释放对gameworld、MovieClip的强引用
     * 用于游戏重启时的彻底清理
     */
    public function dispose():Void {
        // restart 是唯一允许强制废弃 run/reservation 的边界。不调普通
        // clear()，因为它必须对活动 run fail closed，否则会出现“拒绝后继续断引用”。
        StageRunSession.resetForRestart();
        cancelStoredStageStart();
        closeStage();
        var disposedTimePool:StageTimePoolController = timePoolController;
        timePoolController = null;
        _root.当前为战斗地图 = false;
        stageInfoList = null;
        currentStageInfo = null;
        currentStage = -1;
        isActive = false;
        calibrationHostInitialization = false;
        clearTimePoolBestEffort(disposedTimePool);

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

    private function isCalibrationHostStage():Boolean {
        return _root.斗兽标定模式 === true && _root.角斗场对手类型 == "calibration";
    }

    private function initCalibrationHostStage(basicInfo:Object):Void {
        _root.当前通关的关卡 = "";
        _root.当前关卡名 = "斗兽标定竞技场";
        _root.关卡类型 = "斗兽标定";
        _root.敌人同伴数 = 0;
        _root.敌人总数 = 0;

        gameworld._arenaCalibrationStage = true;
        gameworld.允许通行 = false;
        gameworld.关卡结束 = false;
        gameworld.佣兵已进场 = false;
        gameworld.出生地.是否从门加载主角 = false;
        _global.ASSetPropFlags(gameworld, ["_arenaCalibrationStage", "佣兵已进场"], 1, false);

        _root.加载场景背景(basicInfo.Background);
        _root.加载后景(environment);

        if (_root.场景转换函数 != undefined && _root.帧计时器 != undefined) {
            _root.场景转换函数.上次切换帧数 = _root.帧计时器.当前帧数;
        }
        gameworld.dispatcher.publish("Start");
        ArenaCalibrationService.onCalibrationStageReady();
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
