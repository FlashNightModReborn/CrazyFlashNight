import org.flashNight.neur.Controller.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.sara.*;
import org.flashNight.neur.Server.*; 
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.gesh.arguments.*;
import org.flashNight.naki.Sort.InsertionSort;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.key.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*
import org.flashNight.arki.bullet.Factory.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.render.*;

// 初始化全局帧计时器对象
_root.帧计时器 = {};

// 调用 ColliderFactoryRegistry 初始化
ColliderFactoryRegistry.init();

// 帧计时器初始化函数：初始化所有与帧、性能、任务调度有关的参数，并创建 TaskManager 实例
_root.帧计时器.初始化任务栈 = function():Void {
    // --------------------------
    // 帧率、时间相关参数
    // --------------------------
    this.帧率 = 30;                    // 设置项目帧率为 30 帧/s
    this.毫秒每帧 = this.帧率 / 1000;    // 每帧对应的毫秒（用于乘法优化）
    this.每帧毫秒 = 1000 / this.帧率;    // 每帧真实时长（毫秒）
    this.frameStartTime = 0;
    this.measurementIntervalFrames = this.帧率;
    this.当前帧数 = 0; 
    
    // --------------------------
    // 帧率平滑缓冲区相关（SlidingWindowBuffer 用于记录历史帧率）
    // --------------------------
    this.队列最大长度 = 24;
    this.frameRateBuffer = new SlidingWindowBuffer(this.队列最大长度);
    for (var i:Number = 0; i < this.队列最大长度; i++) {
        this.frameRateBuffer.insert(this.帧率);
    }
    this.总帧率 = 0;
    this.最小帧率 = 30;
    this.最大帧率 = 0;
    this.最小差异 = 5;
    this.异常间隔帧数 = this.帧率 * 5;
    this.实际帧率 = 0;
    
    // --------------------------
    // 性能与画质相关（如预设画质、天气更新等）
    // --------------------------
    this.性能等级 = 0;
    this.预设画质 = _root._quality;
    this.更新天气间隔 = 5 * this.帧率;
    this.天气待更新时间 = this.更新天气间隔;
    this.光照等级数据 = [];
    this.当前小时 = null;

    // --------------------------
    // 初始化滤波器和 PID 控制器（帧率稳定性控制等）
    // --------------------------
    this.kalmanFilter = new SimpleKalmanFilter1D(this.帧率, 0.5, 1);
    this.kp = 0.2;
    this.ki = 0.5;
    this.kd = -30;
    this.integralMax = 3;
    this.derivativeFilter = 0.2;
    this.targetFPS = 26;
    // 先生成一个初始 PIDController 实例，后续通过 PIDControllerFactory 更新
    this.PID = new PIDController(this.kp, this.ki, this.kd, this.integralMax, this.derivativeFilter);
    
    var pidFactory:PIDControllerFactory = PIDControllerFactory.getInstance();
    function onPIDSuccess(pid:PIDController):Void {
        _root.帧计时器.PID = pid;
    }
    function onPIDFailure():Void {
        trace("主程序：PIDControllerConfig.xml 加载失败");
    }
    pidFactory.createPIDController(onPIDSuccess, onPIDFailure);
    
    // --------------------------
    // 初始化任务调度部分：创建 ScheduleTimer 和 TaskManager 实例
    // --------------------------
    this.ScheduleTimer = new CerberusScheduler();
    this.singleWheelSize = 150;
    this.multiLevelSecondsSize = 60;
    this.multiLevelMinutesSize = 60;
    this.precisionThreshold = 0.1;
    this.ScheduleTimer.initialize(this.singleWheelSize,
                                  this.multiLevelSecondsSize, 
                                  this.multiLevelMinutesSize, 
                                  this.帧率, 
                                  this.precisionThreshold);
    // 用 TaskManager 统一管理任务调度，内部会维护任务表和零帧任务
    this.taskManager = new TaskManager(this.ScheduleTimer, this.帧率);

    // 创建冷却时间轮，用于调度轻量化的ui任务
    this.cooldownWheel = CooldownWheel.I();

    // 创建单位update时间轮
    this.unitUpdateWheel = UnitUpdateWheel.I();
    
    // --------------------------
    // 其他相关初始化
    // --------------------------
    this.server = ServerManager.getInstance();
    this.eventBus = EventBus.getInstance();
    TargetCacheManager.initialize();
    
    // --------------------------
    // 注册帧更新事件：每次帧更新时调用 TaskManager.updateFrame() 来处理任务
    // --------------------------
    this.eventBus.subscribe("frameUpdate", function():Void {
        _root.帧计时器.taskManager.updateFrame();
        _root.帧计时器.unitUpdateWheel.tick(); // 单位的 update 事件发布后于调度器执行
        // _root.服务器.发布服务器消息(_root.场景进入位置名)
    }, this);
};

// 调用初始化方法
_root.帧计时器.初始化任务栈();

/**
 * 更新帧率数据
 * @param 当前帧率 当前的帧率值
 */
_root.帧计时器.更新帧率数据 = function(当前帧率:Number):Void {
    // 插入新的帧率数据到缓冲区
    this.frameRateBuffer.insert(当前帧率);
    
    // 获取当前缓冲区的最小值、最大值和平均值
    var 当前最小帧率:Number = this.frameRateBuffer.min;
    var 当前最大帧率:Number = this.frameRateBuffer.max;
    var 当前平均帧率:Number = this.frameRateBuffer.average;
    
    // 更新总帧率
    this.总帧率 = 当前平均帧率 * this.队列最大长度;
    
    // 更新最小和最大帧率
    if (当前最大帧率 > this.最大帧率) this.最大帧率 = 当前最大帧率;
    if (当前最小帧率 < this.最小帧率) this.最小帧率 = 当前最小帧率;
    
    // 更新帧率差
    if (this.最大帧率 - this.最小帧率 < this.最小差异) {
        var 差额:Number = (this.最小差异 - (this.最大帧率 - this.最小帧率)) / 2;
        this.最小帧率 -= 差额;
        this.最大帧率 += 差额;
        this.帧率差 = this.最小差异;
    } else {
        this.帧率差 = this.最大帧率 - this.最小帧率;
    }
    
    // 处理光照数据（保持原有逻辑）
    var 光照起点小时:Number = Math.floor(_root.天气系统.当前时间);
    if (this.当前小时 !== 光照起点小时) {
        this.光照等级数据 = []; // 清空光照等级数据
        this.当前小时 = 光照起点小时;
        for (var i:Number = 0; i < this.队列最大长度; i++) {
            // 推入未来队列最大长度的光照等级
            this.光照等级数据.push(_root.天气系统.昼夜光照[(光照起点小时 + i) % 24]);
        }
    }
};

/**
 * 绘制帧率曲线
 */
_root.帧计时器.绘制帧率曲线 = function():Void {
    var 画布:MovieClip = _root.玩家信息界面.性能帧率显示器.画布;
    var 高度:Number = 14;  // 曲线图的高度
    var 宽度:Number = 72;  // 曲线图的宽度
    var 步进长度:Number = 宽度 / this.队列最大长度;
    
    画布._x = 2;  // 设置画布位置
    画布._y = 2;
    画布.clear(); // 重置绘图区
    
    // 开始绘制光照等级曲线
    var 光照线条颜色:Number = 0x333333; // 灰色线条表示光照等级
    画布.beginFill(光照线条颜色, 100); // 开始填充区域
    var 光照步进高度:Number = 高度 / 9;
    var x0:Number = 0;
    var y0:Number = 高度 - (this.光照等级数据[0] * 光照步进高度);
    
    画布.moveTo(x0, 高度); // 移动到起点底部
    画布.lineTo(x0, y0); // 移动到起点
    
    for (var i:Number = 1; i < this.队列最大长度; i++) {
        var x1:Number = x0 + 步进长度;
        var y1:Number = 高度 - (this.光照等级数据[i] * 光照步进高度);
        
        // 绘制二次贝塞尔曲线
        画布.curveTo((x0 + x1) / 2, (y0 + y1) / 2, x1, y1);
        
        x0 = x1; // 更新起点
        y0 = y1;
    }
    
    画布.lineTo(x0, 高度); // 从最后一个点连接到底部
    画布.endFill(); // 完成填充区域
    
    // 设置帧率曲线的颜色根据性能等级变化
    var 帧率线条颜色:Number;
    switch(this.性能等级) {
        case 0: 
            帧率线条颜色 = 0x00FF00; // 绿色
            break;
        case 1: 
            帧率线条颜色 = 0x00CCFF; // 蓝绿色
            break;
        case 2: 
            帧率线条颜色 = 0xFFFF00; // 黄色
            break;
        default: 
            帧率线条颜色 = 0xFF0000; // 红色
    }
    画布.lineStyle(1.5, 帧率线条颜色, 100); // 设置线条样式
    
    // 绘制帧率曲线
    var 帧率步进高度:Number = 高度 / this.帧率差;
    var 起点X:Number = 0;
    var 起点Y:Number = 高度 - ((this.frameRateBuffer.min <= 0) ? 0 : (this.frameRateBuffer.min - this.最小帧率) * 帧率步进高度);
    
    画布.moveTo(起点X, 起点Y);
    
    // 使用 forEach 方法确保顺序遍历帧率数据
    var self = this; // 保存当前上下文以在闭包中使用
    this.frameRateBuffer.forEach(function(value:Number):Void {
        var x1:Number = 起点X + 步进长度;
        var y1:Number = 高度 - ((value - self.最小帧率) * 帧率步进高度);
        
        // 绘制二次贝塞尔曲线
        画布.curveTo((起点X + x1) / 2, (起点Y + y1) / 2, x1, y1);
        
        起点X = x1; // 更新起点
        起点Y = y1;
    });
};


_root.帧计时器.性能评估优化 = function() {

    // --- 1. 判断是否到达测量间隔 ---
    if (--this.measurementIntervalFrames === 0) 
    {
        var currentTime = getTimer();  // 获取当前时间

        // === 2. 计算本次测量的实际帧率 ===
        // measurementIntervalFrames = this.帧率 * (1 + this.性能等级)
        // 两次测量间隔越长，(当前时间 - this.frameStartTime) 就越大
        this.实际帧率 = Math.ceil(
            this.帧率 * (1 + this.性能等级) * 10000 / (currentTime - this.frameStartTime)
        ) / 10;
        
        // 可视化显示
        _root.玩家信息界面.性能帧率显示器.帧率数字.text = this.实际帧率;

        // === 3. 计算本次测量和上次测量间的时间差 (ms -> s) ===
        var dt = (currentTime - this.frameStartTime) / 1000;  // 单位：秒

        // === 4. 动态调整滤波器的过程噪声 Q ===
        //   - dt 越大，Q 也适当变大；dt 越小，Q 变小
        //   - 当前还需要根据实验结果确定设定值
        var baseQ:Number = 0.1;          // 原本的Q
        var scaledQ:Number = baseQ * dt; // 跟时间间隔成正比
        // 下限与上限可做限制，避免Q过大过小：
        scaledQ = Math.max(0.01, Math.min(scaledQ, 2.0)); 

        // 设置新的过程噪声
        this.kalmanFilter.setProcessNoise(scaledQ);

        // --- 5. 卡尔曼滤波器：先 predict() 再 update() ---
        this.kalmanFilter.predict();                // 预测(使用动态Q)
        var denoisedFPS:Number = this.kalmanFilter.update(this.实际帧率); // 更新
        // _root.发布消息("滤波后FPS: " + denoisedFPS);

        // === 6. 使用平滑后的FPS进行 PID 控制 ===
        var targetFPS = this.帧率 - this.性能等级 * 2;
        var pidOutput = this.PID.update(
            this.targetFPS,
            denoisedFPS,
            this.帧率 * (1 + this.性能等级)
        );

        var currentPerformanceLevel = Math.round(pidOutput);
        currentPerformanceLevel = Math.max(0, Math.min(currentPerformanceLevel, 3));

        // === 7. 引入确认步骤，避免过于频繁调整 ===
        if (this.性能等级 !== currentPerformanceLevel) 
        {
            if (this.awaitConfirmation ) 
            {
                // this.eventBus.publish("PerformanceAdjustmentTriggered", currentPerformanceLevel);
                this.执行性能调整(currentPerformanceLevel);
                this.性能等级 = currentPerformanceLevel;
                this.awaitConfirmation  = false;
                _root.发布消息(
                  "性能等级: [" + this.性能等级 + " : " + this.实际帧率 + " FPS] " + _root._quality
                );
            } 
            else 
            {
                this.awaitConfirmation  = true;
            }
        } 
        else 
        {
            this.awaitConfirmation  = false;
        }

        // === 8. 重置计时和measurementIntervalFrames ===
        this.frameStartTime = currentTime;
        this.measurementIntervalFrames = this.帧率 * (1 + this.性能等级);

        // 更新数据、绘图
        this.更新帧率数据(this.实际帧率);
        this.绘制帧率曲线();
    }
};


_root.帧计时器.执行性能调整 = function(新性能等级) 
{
    switch (新性能等级) 
    {
        case 0:
            EffectSystem.maxEffectCount = 20;
            EffectSystem.maxScreenEffectCount = 20;
            _root.面积系数 = 300000;
            _root.同屏打击数字特效上限 = 25;
            EffectSystem.isDeathEffect = true;
            _root._quality = this.预设画质;
            _root.天气系统.光照等级更新阈值 = 0.1;
            ShellSystem.setMaxShellCountLimit(25);
            _root.发射效果上限 = 15;
            _root.显示列表.继续播放(_root.显示列表.预设任务ID);
            _root.UI系统.经济面板动效 = true;
            // this.scrollDelay = 1;
            this.offsetTolerance = 10;
            break;
        case 1:
            EffectSystem.maxEffectCount = 15;
            EffectSystem.maxScreenEffectCount = 15;
            _root.面积系数 = 450000; 
            _root.同屏打击数字特效上限 = 18;
            EffectSystem.isDeathEffect = true;
            _root._quality = this.预设画质 === 'LOW' ? this.预设画质 : 'MEDIUM';
            _root.天气系统.光照等级更新阈值 = 0.2;
            ShellSystem.setMaxShellCountLimit(18);
            _root.发射效果上限 = 10;
            _root.显示列表.继续播放(_root.显示列表.预设任务ID);
            _root.UI系统.经济面板动效 = true;
            // this.scrollDelay = 1;
            this.offsetTolerance = 30;
            break;
        case 2:
            EffectSystem.maxEffectCount = 10;
            EffectSystem.maxScreenEffectCount = 10;
            _root.面积系数 = 600000; //刷佣兵数量砍半
            _root.同屏打击数字特效上限 = 12;
            EffectSystem.isDeathEffect = false;
            _root.天气系统.光照等级更新阈值 = 0.5;
            _root._quality = 'LOW';
            ShellSystem.setMaxShellCountLimit(12);
            _root.发射效果上限 = 5;
            _root.显示列表.暂停播放(_root.显示列表.预设任务ID);
            _root.UI系统.经济面板动效 = false;
            // this.scrollDelay = 1;
            this.offsetTolerance = 50;
            break;
        default:
            EffectSystem.maxEffectCount = 0;  // 禁用效果
            EffectSystem.maxScreenEffectCount = 5;  // 最低上限
            _root.面积系数 = 3000000;  //刷佣兵为原先十分之一
            _root.同屏打击数字特效上限 = 10;
            EffectSystem.isDeathEffect = false;
            _root.天气系统.光照等级更新阈值 = 1;
            _root._quality = 'LOW';
            ShellSystem.setMaxShellCountLimit(10);
            _root.发射效果上限 = 0;
            _root.显示列表.暂停播放(_root.显示列表.预设任务ID);
            _root.UI系统.经济面板动效 = false;
            // this.scrollDelay = 2;
            this.offsetTolerance = 80;
    }

    TrailRenderer.getInstance().setQuality(新性能等级);
    ClipFrameRenderer.setPerformanceLevel(新性能等级);
    BladeMotionTrailsRenderer.setPerformanceLevel(新性能等级);
    // VectorAfterimageRenderer.instance.setShadowCount(5 - 新性能等级);
};

_root.帧计时器.执行性能调整(0);

_root.帧计时器.定期异常检查 = function()
{
    if (--this.异常间隔帧数 === 0) 
    {
        var 游戏世界 = _root.gameworld;

        for (var 待选目标 in 游戏世界) 
        {
            var 目标 = 游戏世界[待选目标];
            if(目标.hp > 0)
            {
                目标.异常指标 = 0;
            }
            else if(目标.hp <= 0 and 目标.hp !== undefinded)
            {
                if(++目标.异常指标 > 2)
                {
                    if(++目标.移除指标 > 2)
                    {
                        目标.removeMovieClip();
                        _root.发布消息("remove " + 目标);
                    }
                    else if(目标.异常指标 === 3)
                    {
                        目标.死亡检测();
                        _root.发布消息("kill " + 目标);
                    }
                }
            }

        }   
        _root.服务器.发布服务器消息("正在检查异常");
        this.异常间隔帧数 = this.帧率 * 5;
    }
};

_root.帧计时器.定期更新天气 = function()
{
    var gameWorld:MovieClip = _root.gameworld;
    if(!gameWorld) return;
    if (--this.天气待更新时间 === 0 || !gameWorld.已更新天气) 
    {
        this.eventBus.publish("WeatherUpdated");
        if(!gameWorld.已更新天气){            
            gameWorld.已更新天气 = true;//保证换场景可切换
            _global.ASSetPropFlags(gameWorld, ["已更新天气"], 1, true);

            // 清理缓存，避免循环引用

            Delegate.clearCache();
            Dictionary.destroyStatic();
            // _root.服务器.发布服务器消息("SceneChanged")
        }
        
        this.天气待更新时间 = this.更新天气间隔 * (1 + this.性能等级);

    }
};



_root.帧计时器.键盘输入控制目标 = function()
{
    var 控制对象 = TargetCacheManager.findHero()
    if(!控制对象) return;

    if(_root.暂停){
        // 清空所有状态
        控制对象.左行 = false;
        控制对象.右行 = false;
        控制对象.上行 = false;
        控制对象.下行 = false;
        控制对象.动作A = false;
        控制对象.动作B = false;
        控制对象.动作C = false;
        控制对象.强制奔跑 = false;
    }else{
        // 使用位掩码存储按键状态
        var mask:Number =
            (Key.isDown(控制对象.左键) ? 1 : 0) |
            (Key.isDown(控制对象.右键) ? 2 : 0) |
            (Key.isDown(控制对象.上键) ? 4 : 0) |
            (Key.isDown(控制对象.下键) ? 8 : 0) |
            (Key.isDown(控制对象.A键) ? 16 : 0) |
            (Key.isDown(控制对象.B键) ? 32 : 0) |
            (Key.isDown(控制对象.C键) ? 64 : 0) |
            (Key.isDown(_root.奔跑键) ? 128 : 0); 

        // 解码位掩码更新控制对象状态
        控制对象.左行 = (mask & 1) != 0;
        控制对象.右行 = (mask & 2) != 0;
        控制对象.上行 = (mask & 4) != 0;
        控制对象.下行 = (mask & 8) != 0;
        控制对象.动作A = (mask & 16) != 0;
        控制对象.动作B = (mask & 32) != 0;
        控制对象.动作C = (mask & 64) != 0;
        控制对象.强制奔跑 = !((mask & (16 | 32 | 64)) != 0) && (mask & 128) != 0;

    }
};




// 定义按键事件
// _root.帧计时器.onKeyDown = _root.帧计时器.onKeyUp = _root.帧计时器.键盘输入控制目标;

// 注册监听器
// Key.addListener(_root.帧计时器);

_root.帧计时器.eventBus.subscribe("frameUpdate", function() {
    this.性能评估优化();
    this.定期更新天气();
    this.键盘输入控制目标();
    this.当前帧数 = this.server.currentFrame;
}, _root.帧计时器);

_root.帧计时器.eventBus.subscribe("frameUpdate", function() {
    _root.显示列表.播放列表();
}, _root.帧计时器);

// 监听面板是否初始化，初始化完成后自动取消订阅
_root.帧计时器.eventBus.subscribe("frameUpdate", function() {
    var 系统 = _root.UI系统;
    if(系统.虚拟币刷新() or 系统.金钱刷新()){
        _root.帧计时器.eventBus.unsubscribe("frameUpdate");
    }

}, _root.帧计时器);



// ---------------------------------------------------
// 以下为对外公开的任务调度方法，均为包装 TaskManager 方法
// ---------------------------------------------------

// 【添加任务】（通用版：可指定执行次数或无限循环）
_root.帧计时器.添加任务 = function(action:Function, interval:Number, repeatCount):Number {
    // 提取额外动态参数
    var parameters:Array = (arguments.length > 3) ? ArgumentsUtil.sliceArgs(arguments, 3) : [];
    return this.taskManager.addTask(action, interval, repeatCount, parameters);
};

// 【添加单次任务】（间隔 <= 0 时直接执行，返回 null）
_root.帧计时器.添加单次任务 = function(action:Function, interval:Number):Number {
    var parameters:Array = (arguments.length > 2) ? ArgumentsUtil.sliceArgs(arguments, 2) : [];
    return this.taskManager.addSingleTask(action, interval, parameters);
};

// 【添加循环任务】（无限重复执行）
_root.帧计时器.添加循环任务 = function(action:Function, interval:Number):Number {
    var parameters:Array = (arguments.length > 2) ? ArgumentsUtil.sliceArgs(arguments, 2) : [];
    return this.taskManager.addLoopTask(action, interval, parameters);
};

// 【添加或更新任务】（相同对象+标签，只会存在一个任务）
_root.帧计时器.添加或更新任务 = function(obj:Object, labelName:String, action:Function, interval:Number):Number {
    var parameters:Array = (arguments.length > 4) ? ArgumentsUtil.sliceArgs(arguments, 4) : [];
    return this.taskManager.addOrUpdateTask(obj, labelName, action, interval, parameters);
};

// 【添加生命周期任务】（无限循环，并绑定对象卸载时的清理回调）
_root.帧计时器.添加生命周期任务 = function(obj:Object, labelName:String, action:Function, interval:Number):Number {
    var parameters:Array = (arguments.length > 4) ? ArgumentsUtil.sliceArgs(arguments, 4) : [];
    return this.taskManager.addLifecycleTask(obj, labelName, action, interval, parameters);
};

// 【移除任务】（根据任务ID删除任务，内部会通知 ScheduleTimer 移除）
_root.帧计时器.移除任务 = function(taskID:Number):Void {
    this.taskManager.removeTask(taskID);
};

// 【定位任务】（根据任务ID获取 Task 对象，用于检查或后续操作）
_root.帧计时器.定位任务 = function(taskID:Number):Task {
    return this.taskManager.locateTask(taskID);
};

// 【延迟执行任务】（给已有任务延迟一段时间后执行）
_root.帧计时器.延迟执行任务 = function(taskID:Number, delayTime):Boolean {
    return this.taskManager.delayTask(taskID, delayTime);
};


_root.帧计时器.添加冷却任务 = function(delay:Number, callback:Function):Void {
    this.cooldownWheel.add(delay, callback);
};



EventBus.getInstance().subscribe("SceneChanged", StaticInitializer.onSceneChanged, StaticInitializer); 

_root.帧计时器.获取敌人缓存 = Delegate.create(TargetCacheManager, TargetCacheManager.getCachedEnemy);
_root.帧计时器.获取友军缓存 = Delegate.create(TargetCacheManager, TargetCacheManager.getCachedAlly);

_root.帧计时器.添加主动战技cd = function(动作, 间隔时间){
    return _root.帧计时器.添加单次任务(动作, 间隔时间); // 返回任务ID
};


_root.帧计时器.eventBus.subscribe("SceneChanged", SceneCoordinateManager.update
, SceneCoordinateManager); 

_root.帧计时器.eventBus.subscribe("SceneChanged", function() {
    _root.帧计时器.kalmanFilter.reset(30,1);
    _root.帧计时器.PID.reset();
    _root.帧计时器.执行性能调整(0);
}, null); 


//开始对在线奖励计时
var 检测在线奖励 = function(){
    _root.在线时间计数++;
    if(_root.主线任务进度 > 28){
        if (_root.在线时间计数 == 2) _root.奖励10分钟._visible = true;
        else if (_root.在线时间计数 == 4) _root.奖励20分钟._visible = true;
        else if (_root.在线时间计数 == 8) _root.奖励40分钟._visible = true;
        else if (_root.在线时间计数 == 12) _root.奖励60分钟._visible = true;
        else if (_root.在线时间计数 == 24) _root.奖励120分钟._visible = true;
    }
}
_root.在线时间计数 = 0;
_root.帧计时器.添加任务(检测在线奖励, 300000, 24); // 每5分钟检测一次，共24次
_root.帧计时器.添加循环任务(BulletFactory.resetCount, 1000 * 60 * 5); // 每5分钟重置一次子弹深度计数


EventBus.getInstance().subscribe("SceneChanged", function() {
	// _root.服务器.发布服务器消息("准备清理地图信息")
	_root.帧计时器.添加或更新任务(_root.gameworld, "ASSetPropFlags", function() {
		var arr:Array = [   "效果", 
							"子弹区域", 
							"已更新天气",
							"动画",
							"背景",
							"地图",
							"出生地",
							"deadbody",
							"允许通行"
		]

        /*
		_root.服务器.发布服务器消息("开始清理地图信息")

		for(var each in _root.gameworld) {
			_root.服务器.发布服务器消息("key " + each)
		}

		for(var i:Number = 0; i < arr.length; i++) {
			if(_root.gameworld[arr[i]]) {
				_global.ASSetPropFlags(_root.gameworld, [arr[i]], 1, false);
				_root.服务器.发布服务器消息("ASSetPropFlags " + arr[i])
			}
		}

		for(var each in _root.gameworld) {
			_root.服务器.发布服务器消息("key " + each)
		}

        _root.服务器.发布服务器消息("结束清理地图信息");

        */
        _global.ASSetPropFlags(_root.gameworld, arr, 1, false);
	}, 5000)
}, null); // 地图变动时，将需要设置的部件设置成不可枚举以避免进入遍历范围