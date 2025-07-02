import org.flashNight.arki.scene.*;

import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/*
WaveSpawner 波次刷怪器，通过波次控制关卡流程，完全覆盖原版无限过图的功能。
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.WaveSpawner {
    public static var instance:WaveSpawner; // 单例引用
    private var sceneManager:SceneManager; // SceneManager单例
    private var stageManager:StageManager; // StageManager单例
    private var linearEngine:LinearCongruentialEngine; // 线性插值随机数引擎单例
    private var waveSpawnWheel:WaveSpawnWheel; // WaveSpawnWheel实例
    public var gameworld:MovieClip; // 当前gameworld

    private var stageInfo:StageInfo; // 关卡信息
    private var waveInfo:Array; // 波次信息

    private var finishRequirement:Number;

    public var totalWave = 0; // 总波次
    public var currentWave:Number = -1; // 当前波次
    public var countDownTime:Number = 0; // 当前计时
    public var waveTime:Number = 0; // 当前波次总时长

    public var tickCount:Number;

    public var spawnPoints:Array; // 出生点影片剪辑列表

    public var getLeft:Function; // 左侧出怪位置函数
    public var getRight:Function; // 右侧出怪位置函数

    public var isActive:Boolean;
    public var isFinished:Boolean;

    
    /**
     * 单例获取：返回全局唯一实例
     */
    public static function getInstance():WaveSpawner {
        return instance || (instance = new WaveSpawner());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function WaveSpawner() {
        linearEngine = LinearCongruentialEngine.getInstance();
    }

    
    public function init(_stageInfo:StageInfo):Void{
        sceneManager = SceneManager.instance;
        stageManager = StageManager.instance;
        waveSpawnWheel = WaveSpawnWheel.instance;
        waveSpawnWheel.init();

        gameworld = sceneManager.gameworld;

        spawnPoints = stageManager.spawnPoints;
        
        stageInfo = _stageInfo;
        waveInfo = stageInfo.waveInfo;

        totalWave = waveInfo.length;
        currentWave = 0;
        countDownTime = 0;
        waveTime = 0;
        
        isActive = true;
        isFinished = false;
        tickCount = 0;

        _root.d_倒计时显示._visible = false;

        // 确定左右刷怪线
        var environment = stageManager.environment;
        if (environment.左侧出生线) {
            var left = environment.左侧出生线;
            this.getLeft = function() {
                return {
                    x: linearEngine.randomIntegerStrict(left.x0, left.x1), 
                    y: linearEngine.randomIntegerStrict(left.y0, left.y1)
                };
            };
        } else {
            this.getLeft = this.defaultGetLeft;
        }
        if (environment.右侧出生线) {
            var right = environment.右侧出生线;
            this.getRight = function() {
                return {
                    x: linearEngine.randomIntegerStrict(right.x0, right.x1), 
                    y: linearEngine.randomIntegerStrict(right.y0, right.y1)
                };
            };
        } else {
            this.getRight = this.defaultGetRight;
        }

        // 订阅frameUpdate事件，以控制刷怪和计时
        // gameworld.dispatcher.subscribeGlobal("frameUpdate", this.tick, this);

        // 开始刷怪
        startWave();
    }

    public function close():Void{
        _root.当前为战斗地图 = false;
        _root.d_剩余敌人数._visible = false;
        
        waveSpawnWheel.clear();

        isActive = false;

        // gameworld.dispatcher.unsubscribeGlobal("frameUpdate", this.tick);
        gameworld = null;

        stageInfo = null;
        waveInfo = null;
        spawnPoints = null;

        finishRequirement = 0;

        getLeft = null;
        getRight = null;
    }
    

    public function startWave():Void{
        tickCount = 0;
        var subWaveInfo = waveInfo[currentWave];
        if(subWaveInfo == null) _root.发布消息("敌人波次数据异常！");

        _root.d_波次.text = _root.获得翻译("波次") + (currentWave + 1) + " / " + totalWave + "";
        if(totalWave > 1){
            _root.最上层发布文字提示(_root.获得翻译("战斗开始！剩余波数：") + (totalWave - (currentWave + 1)) + "！");
        }

        finishRequirement = isNaN(subWaveInfo[0].FinishRequirement) ? 0 : subWaveInfo[0].FinishRequirement;
        countDownTime = 0;
        if(currentWave < currentWave - 1 || Number(subWaveInfo[0].Duration) > 0){
            waveTime = Number(subWaveInfo[0].Duration);
        }else{
            waveTime = 0;
        }
        _root.d_倒计时显示._visible = waveTime > 0;

        // 对于本轮要生成的出生点，记录其生成所需时长
        var hideSpawnPoints = {};
        // 遍历刷怪列表
        for (var i = 1; i < subWaveInfo.length; i++){
            var 兵种信息 = subWaveInfo[i];
            //根据难度决定是否刷怪
            if (兵种信息.DifficultyMax && _root.计算难度等级(兵种信息.DifficultyMax) < _root.难度等级){
                continue;
            }
            if(兵种信息.DifficultyMin && _root.计算难度等级(兵种信息.DifficultyMin) > _root.难度等级){
                continue;
            }
            //计算总敌人数
            var quantity = 兵种信息.Quantity;
            var spawnIndex = 兵种信息.SpawnIndex;
            if(spawnIndex > -1){
                var spawnPoint = spawnPoints[spawnIndex];
                spawnPoint.僵尸型敌人总个数 += quantity;
                // 若该出生点隐藏则令其生成，并根据其生成时长自动为该波次敌人附加延迟
                if(spawnPoint.Hide){
                    spawnPoint.Hide = false;
                    spawnPoint.gotoAndPlay("生成");
                    hideSpawnPoints[spawnIndex] = spawnPoint.Delay > 0 ? spawnPoint.Delay : 1000;
                }
                if(hideSpawnPoints[spawnIndex] > 0 && 兵种信息.Delay < hideSpawnPoints[spawnIndex]) 兵种信息.Delay = hideSpawnPoints[spawnIndex];
            }else{
                gameworld.地图.僵尸型敌人总个数 += quantity;
            }
            //将刷怪托管到专用时间轮
            if(兵种信息.TriggerEvent.EventName){
                if(兵种信息.TriggerEvent.Parameters) 兵种信息.TriggerEvent.Parameters = ObjectUtil.toArray(兵种信息.TriggerEvent.Parameters);
                waveSpawnWheel.subscribeSpawnEvent(quantity, 兵种信息.Interval, 兵种信息.Delay, 兵种信息.Attribute, i, currentWave, 兵种信息.TriggerEvent);
            }else{
                waveSpawnWheel.addTask(quantity, 兵种信息.Interval, 兵种信息.Delay, 兵种信息.Attribute, i, currentWave);
            }
        }

        // 发布波次开始事件
        gameworld.dispatcher.publish("WaveStarted", currentWave);
    }

    public function tick():Void{
        if(!this.isActive) return;
        this.tickCount++;
        this.waveSpawnWheel.minHeapTick();
        if(this.tickCount % 3 == 0) {
            this.waveSpawnWheel.slotTick();
            if(this.tickCount % 30 == 0) {
                this.waveSpawnWheel.longDelaySlotTick();
                this.clockTick();
            }
        }
    }


    public function clockTick():Void{
        if(!isActive || isFinished) return;
        countDownTime++;
        if(waveTime > 0){
            var total_sec = waveTime - countDownTime;
            var min = Math.floor(total_sec / 60);
            var sec = total_sec % 60;
            var min_str = min < 10 ? "0" + min.toString() : min.toString();
            var sec_str = sec < 10 ? "0" + sec.toString() : sec.toString();
            _root.d_倒计时显示.text = min_str + ":" + sec_str;
        }
        
        var emenyCount = getEnemyCount();
        _root.d_剩余敌人数.text = _root.获得翻译("剩余敌人数：") + emenyCount;
        
        if (emenyCount <= finishRequirement || (waveTime > 0 && total_sec <= 0)){
            finishWave();
        }
    }

    public function finishWave():Void{
        // 发布波次结束事件
        gameworld.dispatcher.publish("WaveFinished", currentWave);
        currentWave++;
        if (currentWave < totalWave){
            startWave();
        }else{
            isFinished = true;
            stageManager.clearStage();
        }
    }


    public function spawn(attribute:Object, index:Number, waveIndex:Number, quantity:Number):Boolean{
        var 兵种信息 = waveInfo[waveIndex][index];
        var spawnIndex = 兵种信息.SpawnIndex;
        var spawnPiontInstance = spawnIndex > -1 ? spawnPoints[spawnIndex] : gameworld.地图;
        var enemyPara = ObjectUtil.clone(attribute);
        enemyPara.等级 = isNaN(兵种信息.Level) ? 1: Number(兵种信息.Level);
        enemyPara.兵种名 = null;

        // 设置front的敌人默认左向
        if(spawnIndex === "front"){
            enemyPara.方向 = "左";
        }
        if (spawnIndex > -1){
            // 若敌方单位大等于场上最大容纳量则不刷怪
            if(enemyPara.是否为敌人 && spawnPiontInstance.QuantityMax > 0 && spawnPiontInstance.僵尸型敌人场上实际人数 >= spawnPiontInstance.QuantityMax){
                return false;
            }
        }
        // 加载额外参数
        if(兵种信息.Parameters){
            ObjectUtil.cloneParameters(enemyPara, 兵种信息.Parameters);
        }

        var id = attribute.兵种名;
        var instanceName:String;
        if(兵种信息.InstanceName){
            instanceName = 兵种信息.InstanceName;
            enemyPara.publishStageEvent = true;
        }else{
            instanceName = attribute.名字 + "_" + waveIndex + "_" + index + "_" + quantity;
        }

        spawnEnemy(id, instanceName, enemyPara, spawnIndex, 兵种信息.x, 兵种信息.y);

        if (enemyPara.是否为敌人 === true){
            spawnPiontInstance.僵尸型敌人场上实际人数++;
        }else{
            spawnPiontInstance.僵尸型敌人总个数--;
        }
        return true;
    }

    public function spawnEnemy(id:String, instanceName:String, initObject, spawnIndex, x:Number, y:Number):Void{
        // 优先使用兵种自带的坐标
        var spawnPiontInstance = spawnIndex > -1 ? spawnPoints[spawnIndex] : gameworld.地图;
        if (spawnIndex > -1){
            //优先使用兵种自带的坐标，若无自带坐标则使用出生点坐标并调用开门动画
            if(isNaN(x) || isNaN(y)){
                x = spawnPiontInstance._x;
                y = spawnPiontInstance._y;
                if(spawnPiontInstance.Identifier){
                    y += isNaN(spawnPiontInstance.Offset) ? 2 : spawnPiontInstance.Offset; //生成位置从出生点向下平移2像素避免被出生点碰撞箱卡住，也可手动设置
                    spawnPiontInstance.开门();
                }
                if(spawnPiontInstance.BiasX && spawnPiontInstance.BiasY){
                    x += linearEngine.randomIntegerStrict(-spawnPiontInstance.BiasX, spawnPiontInstance.BiasX);
                    y += linearEngine.randomIntegerStrict(-spawnPiontInstance.BiasY, spawnPiontInstance.BiasY);
                }
            }
        }else if(isNaN(x) || isNaN(y)){
            switch(spawnIndex){
                case "left":
                //左侧刷新
                var pt = this.getLeft();
                x = pt.x;
                y = pt.y;
                break;
                case "right":
                //右侧刷新
                var pt = this.getRight();
                x = pt.x;
                y = pt.y;
                break;
                case "front":
                //在x∈(PlayerX+150,PlayerX+700)，y∈(Ymin+30,PlayerY-30)∪(PlayerY+30,Ymax-30)范围内随机刷新
                var bounding = _root.Ymax - _root.Ymin > 200 ? 30 : 0;
                x = stageInfo.basicInfo.PlayerX + 150 + random(550);
                x = x >= _root.Xmax ? _root.Xmax : x;
                y = _root.Ymin + bounding + random(_root.Ymax - _root.Ymin - 60 - 2*bounding);
                if(Math.abs(stageInfo.basicInfo.PlayerY - y) < 30){
                    y += 60;
                }
                break;
                case "back":
                //在x∈(1024,Xmax-200)，y∈(Ymin+30,Ymax-30)范围内随机刷新
                x = _root.Xmax > 1224 ? 1024 + random(_root.Xmax - 1224) : _root.Xmax - random(50);
                y = linearEngine.randomIntegerStrict(_root.Ymin + 30, _root.Ymax - 30);
                break;
                case "door":
                //在关卡出口处刷新
                x = gameworld.门1._x + 0.5 * gameworld.门1._width;
                y = gameworld.门1._y + 0.5 * gameworld.门1._height;
                break;
                default:
                //默认设置，1/3概率在左侧刷新，2/3概率在右侧刷新
                var pt = (random(3) === 0) ? this.getLeft() : this.getRight();
                x = pt.x;
                y = pt.y;
            }
        }
        if(initObject.产生源 == null) initObject.产生源 = spawnPiontInstance._name;
        initObject._x = x;
        initObject._y = y;

        _root.加载游戏世界人物(id, instanceName, gameworld.getNextHighestDepth(), initObject);
    }



    public function getEnemyCount():Number{
        var waveInformation = waveInfo[currentWave][0];
        var count = waveInformation.MapNoCount ? 0 : gameworld.地图.僵尸型敌人总个数;
        for(var i = 0; i < spawnPoints.length; i++){
            if(!spawnPoints[i].NoCount && spawnPoints[i].僵尸型敌人总个数 > 0){
                count += spawnPoints[i].僵尸型敌人总个数;
            }
        }
        return count;
    }



    public function defaultGetLeft():Object{
        return {
            x: _root.Xmin + linearEngine.randomIntegerStrict(0, 50),
            y: linearEngine.randomIntegerStrict(_root.Ymin, _root.Ymax)
        };
    }

    public function defaultGetRight():Object{
        return {
            x: _root.Xmax - linearEngine.randomIntegerStrict(0, 50),
            y: linearEngine.randomIntegerStrict(_root.Ymin, _root.Ymax)
        };
    }
}