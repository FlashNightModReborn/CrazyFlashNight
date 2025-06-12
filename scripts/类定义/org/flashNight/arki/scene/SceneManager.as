import org.flashNight.gesh.object.ObjectUtil;

/**
SceneManager.as
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.SceneManager {
    private static var instance:SceneManager; // 单例引用

    public var gameworld:MovieClip; // 当前gameworld
    private var environment:Object; // 环境信息

    public var totalWave = 0; // 总波次
    public var currentWave:Number = -1; // 当前波次
    public var countDownTime:Number = 0; // 当前计时
    public var waveTime:Number = 0; // 当前波次总时长

    private var basicInfo:Object; // 基本信息
    private var instanceInfo:Array; // 实例信息
    private var spawnPointInfo:Array; // 出生点信息

    public var spawnPoints:Array; // 出生点影片剪辑列表

    // public var 
    
    /**
     * 单例获取：返回全局唯一实例
     */
    public static function getInstance():SceneManager {
        return instance || (instance = new SceneManager());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function SceneManager() {
        gameworld = null;
        basicInfo = null;
    }

    /*
     * 对新附加的gameworld进行初始化，并附加必要组件。
     */
    public function initGameWorld(_gw:MovieClip):Void{
        gameworld = _gw;
        // gameworld地图碰撞箱层已经弃用，为防止错误附加一个空影片剪辑作为地图层
        if(gameworld.地图 == null) gameworld.createEmptyMovieClip("地图", -2);
        // 附加子弹层，层级在所有人物之下
        if(gameworld.子弹区域 == null) gameworld.createEmptyMovieClip("子弹区域", -1);
        // 附加效果层，层级在所有人物之上
        if(gameworld.效果 == null) gameworld.createEmptyMovieClip("效果", 32767);

        // 将上述属性设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["效果", "子弹区域", "地图"], 1, false);
    }


    public function addBodyLayers(w:Number ,h:Number):Void{
        var deadbody = gameworld.deadbody;
        if(deadbody.layers != null) return;
        //位图层的大小范围在(1024,512)到(2880,1024)之间
        if(w < 1024) w = 1024;
        else if(w >= 2880) w = 2880;
        if(h < 512) h = 512;
        else if(h >= 1024) h = 1024;
        deadbody.layers = new Array(3);
        deadbody.layers[0] = new flash.display.BitmapData(w, h, true, 13421772);
        deadbody.layers[1] = null; // 从未被使用的deadbody1不添加
        deadbody.layers[2] = new flash.display.BitmapData(w, h, true, 13421772);
        deadbody.attachBitmap(deadbody.layers[0], 0);
        deadbody.attachBitmap(deadbody.layers[2], 2);

        // 将 'deadbody' 设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["deadbody"], 1, false);
    }


    public function addInstance(info:Object, name:String):MovieClip{
        var inst;
        // 优先检测url参数载入外部swf，若无则根据identifier从库中加载元件
        if (info.url != null) {
            inst = gameworld.createEmptyMovieClip(name, gameworld.getNextHighestDepth());
            inst.loadMovie(info.url);
        } else if(info.Identifier != null) {
            inst = gameworld.attachMovie(info.Identifier, name, gameworld.getNextHighestDepth());
        }else{
            inst = gameworld.createEmptyMovieClip(name, gameworld.getNextHighestDepth());
        }
        inst._x = info.x;
        inst._y = info.y;
        inst.swapDepths(isNaN(info.Depth) ? info.y : info.Depth);
        if (info.Parameters) ObjectUtil.cloneParameters(inst, info.Parameters);
        return inst;
    }

    /*
    public function initStage(){
        _root.当前为战斗地图 = true;
        _root.d_倒计时显示._visible = false;
        currentWave = 0;
        countDownTime = 0;
        waveTime = 0;

        var 时钟 = _root.生存模式OBJ.时钟;
        if (时钟 != undefined || 时钟.length > 0) {
            for (var i = 0; i < 时钟.length; i++) {
                for (var j = 0; j < 时钟[i].length; j++) {
                    _root.帧计时器.移除任务(时钟[i][j]);
                }
            }
        }
        _root.生存模式OBJ.时钟 = [];
        _root.生存模式OBJ.模式部署 = 模式;

        basicInfo = _root.无限过图基本配置[_root.无限过图模式关卡计数];
        var gameworld = _root.gameworld;

        // 创建事件分发器
        _root.stageDispatcher = new LifecycleEventDispatcher(gameworld);
        _root.stageDispatcher.subscribeOnce("StageFinished", function() {
            this.显示箭头();
        },gameworld.通关箭头);

        // 设置本张图结束后的过场背景
        if (basicInfo.LoadingImage) {
            _root.加载背景列表.本次背景 = basicInfo.LoadingImage;
        }

        // 设置地图尺寸
        var bglist = basicInfo.Background.split("/");
        var url = bglist[bglist.length - 1];
        var 环境信息 = ObjectUtil.clone(_root.天气系统.关卡环境设置[url]);
        if (!环境信息) {
            环境信息 = ObjectUtil.clone(_root.天气系统.关卡环境设置.Default);
        }
        //配置关卡环境参数
        if (basicInfo.Environment) {
            环境信息 = _root.配置环境信息(basicInfo.Environment, 环境信息);
        }
        _root.天气系统.无限过图环境信息 = 环境信息;

        if (环境信息.对齐原点) {
            gameworld.背景._x = 0;
            gameworld.背景._y = 0;
        }
        _root.Xmax = 环境信息.Xmax;
        _root.Xmin = 环境信息.Xmin;
        _root.Ymax = 环境信息.Ymax;
        _root.Ymin = 环境信息.Ymin;
        gameworld.背景长 = 环境信息.背景长;
        gameworld.背景高 = 环境信息.背景高;
        
        var 游戏世界门1 = gameworld.门1;
        var 门1数据 = 环境信息.门[1];
        gameworld.门朝向 = 门1数据.Direction ? 门1数据.Direction : "右";
        // gameworld.门朝向 = 环境信息.门朝向;
        
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
        if(门1数据.Identifier){
            var identifier = gameworld.attachMovie(门1数据.Identifier,"DoorIdentifier1",gameworld.getNextHighestDepth());
            identifier._x = (门1数据.x1 + 门1数据.x0) * 0.5;
            identifier._y = (门1数据.y1 + 门1数据.y0) * 0.5;
            identifier.swapDepths(identifier._y);
        }
        gameworld.允许通行 = false;
        gameworld.关卡结束 = false;

        // 将上述属性设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["背景", "背景长", "背景高", "门朝向", "允许通行", "关卡结束", "Xmax", "Xmin", "Ymax", "Ymin"], 1, false);

        _root.发布消息("环境信息.地图碰撞箱")
        // 绘制地图碰撞箱
        var 地图碰撞箱数组 = 环境信息.地图碰撞箱;
        var 游戏世界地图 = _root.collisionLayer;
        if (地图碰撞箱数组.length > 0) {
            for (var i = 0; i < 地图碰撞箱数组.length; i++) {
                var 多边形 = 地图碰撞箱数组[i].Point;
                if (多边形.length < 3) continue;
                游戏世界地图.beginFill(0x000000);
                var pt = 多边形[0].split(",");
                var px = Number(pt[0]);
                var py = Number(pt[1]);
                游戏世界地图.moveTo(px, py);
                for (var j = 多边形.length - 1; j >= 0; j--) {
                    var pt = 多边形[j].split(",");
                    var px = Number(pt[0]);
                    var py = Number(pt[1]);
                    游戏世界地图.lineTo(px, py);
                }
                游戏世界地图.endFill();
            }
        }
        游戏世界地图._visible = false;

        // 将 '地图' 设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["collisionLayer"], 1, false);

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
        if (isNaN(basicInfo.PlayerX) || isNaN(basicInfo.PlayerY)) {
            basicInfo.PlayerX = _root.Xmin + 50;
            basicInfo.PlayerY = _root.Ymin + 60;
        }
        gameworld.出生地._x = basicInfo.PlayerX;
        gameworld.出生地._y = basicInfo.PlayerY;
        gameworld.出生地.是否从门加载角色();
        
        // 将 '出生地' 设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["出生地"], 1, false);

        // 放置地图元件
        var instanceInfo = _root.无限过图实例[_root.无限过图模式关卡计数];
        for (var i = 0; i < instanceInfo.length; i++) {
            var 实例对象;
            // 优先检测url参数载入外部swf，若无则根据identifier从库中加载元件
            if (instanceInfo[i].url) {
                实例对象 = gameworld.createEmptyMovieClip("instance" + i, gameworld.getNextHighestDepth());
                实例对象.loadMovie(instanceInfo[i].url);
            } else {
                实例对象 = gameworld.attachMovie(instanceInfo[i].Identifier, "instance" + i, gameworld.getNextHighestDepth());
            }
            实例对象._x = instanceInfo[i].x;
            实例对象._y = instanceInfo[i].y;
            实例对象.swapDepths(instanceInfo[i].y);
            if (instanceInfo[i].Parameters) {
                _root.无限过图解析额外参数(实例对象, instanceInfo[i].Parameters);
            }
        }

        // 放置出生点，初始化各个刷怪点的总个数和场上人数
        spawnPointInfo = _root.无限过图出生点[_root.无限过图模式关卡计数];
        spawnPoints = new Array(spawnPointInfo.length);
        for (var i = 0; i < spawnPointInfo.length; i++) {
            if (spawnPointInfo[i].Identifier) {
                spawnPoints[i] = gameworld.attachMovie(spawnPointInfo[i].Identifier, "door" + i, gameworld.getNextHighestDepth(), {_x: spawnPointInfo[i].x, _y: spawnPointInfo[i].y});
                spawnPoints[i].swapDepths(spawnPointInfo[i].y);
                if (spawnPointInfo[i].Parameters) {
                    _root.无限过图解析额外参数(spawnPoints[i], spawnPointInfo[i].Parameters);
                }
            } else {
                spawnPoints[i] = gameworld.createEmptyMovieClip("door" + i, gameworld.getNextHighestDepth());
            }
            spawnPoints[i].僵尸型敌人总个数 = 0;
            spawnPoints[i].僵尸型敌人场上实际人数 = 0;
        }
        gameworld.地图.僵尸型敌人总个数 = 0;

        // 加载进图动画
        if (basicInfo.Animation.Load == 1) {
            _root.最上层加载外部动画(basicInfo.Animation.Path);
            if (basicInfo.Animation.Pause == 1) {
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
        if(basicInfo.BGM){
            if(basicInfo.BGM.Command == "play"){
                _root.soundEffectManager.playBGM(basicInfo.BGM.Title, basicInfo.BGM.Loop, null);
            }else if (basicInfo.BGM.Command == "stop"){
                _root.soundEffectManager.stopBGM();
            }
        }

        //调用回调函数
        if(basicInfo.CallbackFunction.Name){
            if(basicInfo.CallbackFunction.Parameter){
                var para = _root.配置数据为数组(basicInfo.CallbackFunction.Parameter);
                _root.关卡回调函数[basicInfo.CallbackFunction.Name].apply(_root.关卡回调函数,para);
            }else{
                _root.关卡回调函数[basicInfo.CallbackFunction.Name]();
            }
        }
        
        //加载场景
        _root.加载场景背景(basicInfo.Background);
        _root.加载后景(环境信息);

        // 开始刷怪
        if (!basicInfo.RogueMode) _root.生存模式OBJ.模式部署.总波数 = _root.生存模式OBJ.模式部署.length;
        _root.生存模式进攻();
    }
    */
    

    public function removeGameWorld():Void{
        gameworld.deadbody.layers[0].dispose();
        gameworld.deadbody.layers[2].dispose();
        gameworld.swapDepths(_root.getNextHighestDepth());
        gameworld.removeMovieClip();
        gameworld = null;
    }
}