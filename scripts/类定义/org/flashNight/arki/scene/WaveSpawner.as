import org.flashNight.arki.scene.*;

import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
WaveSpawner 通过波次控制关卡流程完全覆盖原版无限过图的功能
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

        finishRequirement = Number(subWaveInfo[0].FinishRequirement) > 0 ? Number(subWaveInfo[0].FinishRequirement) : 0;
        countDownTime = 0;
        if(currentWave < currentWave - 1 || Number(subWaveInfo[0].Duration) > 0){
            waveTime = Number(subWaveInfo[0].Duration);
        }else{
            waveTime = 0;
        }
        _root.d_倒计时显示._visible = waveTime > 0;

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
            if(!isNaN(spawnIndex) && spawnIndex > -1){
                spawnPoints[spawnIndex].僵尸型敌人总个数 += quantity;
            }else{
                gameworld.地图.僵尸型敌人总个数 += quantity;
            }
            //将刷怪托管到专用时间轮
            var interval = Math.floor(兵种信息.Interval / 100);
            waveSpawnWheel.addTask(quantity, interval, 兵种信息.Attribute, i, currentWave);
        }

        gameworld.dispatcher.publish("WaveStarted", currentWave);
    }

    public function tick():Void{
        if(!isActive) return;
        tickCount++;
        if(tickCount % 3 == 0) waveSpawnWheel.tick();
        if(tickCount % 30 == 0) clockTick();
    }


    public function clockTick():Void{
        if(!isActive || isFinished) return;
        countDownTime++;
        if(waveTime > 0){
            var total_sec = waveTime - countDownTime;
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
        
        var emenyCount = getEnemyCount();
        _root.d_剩余敌人数.text = _root.获得翻译("剩余敌人数：") + emenyCount;
        
        if (emenyCount <= finishRequirement || (waveTime > 0 && total_sec <= 0)){
            currentWave++;
            if (currentWave < totalWave){
                startWave();
            }else{
                isFinished = true;
                stageManager.finishStage();
            }
            var 本轮对话 = stageInfo.dialogues[currentWave];
            if (本轮对话.length > 0){
                _root.暂停 = true;
                _root.SetDialogue(本轮对话);
            }
        }
    }


    public function spawn(attribute:Object, index:Number, waveIndex:Number, quantity:Number):Number{
        var 兵种信息 = waveInfo[waveIndex][index];
        var SpawnIndex = 兵种信息.SpawnIndex;
        var enemyPara = ObjectUtil.clone(attribute);
        enemyPara.等级 = isNaN(兵种信息.Level) ? 1: Number(兵种信息.Level);
        enemyPara.兵种名 = null;

        //设置front的敌人默认左向
        if(SpawnIndex === "front"){
            enemyPara.方向 = "左";
        }
        //加载额外参数
        if(兵种信息.Parameters){
            ObjectUtil.cloneParameters(enemyPara, 兵种信息.Parameters);
        }

        do{
            var instanceName:String = 兵种信息.InstanceName ? 兵种信息.InstanceName : attribute.名字 + "_" + waveIndex + "_" + index + "_" + quantity;
            var result = attachEnemy(attribute.兵种名, instanceName, enemyPara, SpawnIndex, 兵种信息.x, 兵种信息.y);
            if(!result) return quantity;
            quantity--;
            if(quantity <= 0) return 0;
        }while(SpawnIndex === "front" || SpawnIndex === "back");
        //若SpawnIndex设置front或back则一次性刷完
        return quantity;
    }

    public function attachEnemy(id:String, instanceName:String, enemyPara:Object, spawnIndex, x:Number, y:Number):Boolean{
        //优先使用兵种自带的坐标
        var 产生源 = "地图";
        if (Number(spawnIndex) > -1)
        {
            var 出生点 = stageInfo.spawnPointInfo[Number(spawnIndex)];
            产生源 = "door" + spawnIndex;
            //若敌方单位大等于场上最大容纳量则不刷怪
            if(出生点.QuantityMax > 0 && enemyPara.是否为敌人 && gameworld[产生源].僵尸型敌人场上实际人数 >= 出生点.QuantityMax){
                return false;
            }
            //优先使用兵种自带的坐标，若无自带坐标则使用出生点坐标并调用开门动画
            if(isNaN(x) || isNaN(y)){
                x = 出生点.x;
                y = 出生点.y;
                if(出生点.Identifier){
                    y += isNaN(出生点.Offset) ? 2 : 出生点.Offset; //生成位置从出生点向下平移2像素避免被出生点碰撞箱卡住，也可手动设置
                    gameworld["door"+spawnIndex].开门();
                }
                if(出生点.BiasX && 出生点.BiasY){
                    x += random(2*出生点.BiasX+1) - 出生点.BiasX;
                    y += random(2*出生点.BiasY+1) - 出生点.BiasY;
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
                y = _root.Ymin + 30 + random(_root.Ymax - _root.Ymin - 60);
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
        enemyPara.产生源 = 产生源;
        enemyPara._x = x;
        enemyPara._y = y;
        _root.加载游戏世界人物(id, instanceName, gameworld.getNextHighestDepth(), enemyPara);
        if (enemyPara.是否为敌人 === true){
            gameworld[产生源].僵尸型敌人场上实际人数++;
        }else{
            gameworld[产生源].僵尸型敌人总个数--;
        }
        return true;
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