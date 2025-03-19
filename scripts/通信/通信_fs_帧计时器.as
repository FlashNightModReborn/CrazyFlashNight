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


_root.帧计时器 = {};
ColliderFactoryRegistry.init();

/**
 * 初始化任务栈和相关参数
 */
_root.帧计时器.初始化任务栈 = function() {  
    // 初始化各种任务相关的表和参数
    this.任务哈希表 = {}; // 频繁更新的任务利用键值对单独维护
    this.当前帧数 = 0; 
    this.任务ID计数器 = 0;

    this.帧率 = 30; // 当前项目为30帧/s
    this.毫秒每帧 = this.帧率 / 1000; // 用于乘法优化性能
    this.每帧毫秒 = 1000 / this.帧率;
    this.frameStartTime = 0;
    this.measurementIntervalFrames = this.帧率;
    
    // 使用 SlidingWindowBuffer 替代原有的帧率数据队列
    this.队列最大长度 = 24; // 队列最大长度
    this.frameRateBuffer = new SlidingWindowBuffer(this.队列最大长度);
    
    // 初始化帧率缓冲区，填充默认值
    for (var i:Number = 0; i < this.队列最大长度; i++) {
        this.frameRateBuffer.insert(this.帧率); // 填充默认帧率
    }
    
    this.总帧率 = 0;  // 存储所有帧率之和
    this.最小帧率 = 30;  // 初始化为一个合理的默认最大值
    this.最大帧率 = 0;  // 初始化为0
    this.最小差异 = 5; // 最大最小帧率差的最小值
    this.异常间隔帧数 = this.帧率 * 5;
    this.实际帧率 = 0;
    this.性能等级 = 0;
    this.预设画质 = _root._quality;
    this.更新天气间隔 = 5 * this.帧率;
    this.天气待更新时间 = this.更新天气间隔;
    this.光照等级数据 = []; // 存储短期内的天气情况
    this.当前小时 = null;
    

    this.kalmanFilter = new SimpleKalmanFilter1D(this.帧率, 0.5, 1);
    
    // PID控制器参数初始化
    this.kp = 0.2;
    this.ki = 0.5;
    this.kd = -30;
    this.integralMax = 3; // 设定积分限幅
    this.derivativeFilter = 0.2; // 平滑误差
    this.targetFPS = 26;
    this.PID = new PIDController(this.kp, this.ki, this.kd, this.integralMax, this.derivativeFilter);

    var pidFactory:PIDControllerFactory = PIDControllerFactory.getInstance();

    // 定义成功回调函数
    function onPIDSuccess(pid:PIDController):Void {
        // 保存 PIDController 实例
        _root.帧计时器.PID = pid;
    }

    // 定义失败回调函数
    function onPIDFailure():Void {
        trace("主程序：PIDControllerConfig.xml 加载失败");
    }

    // 创建并配置 PIDController 实例
    pidFactory.createPIDController(onPIDSuccess, onPIDFailure);
    
    // 任务调度器初始化
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
    
    this.zeroFrameTasks = {}; // 使用对象存储任务
    this.server = ServerManager.getInstance();
    this.eventBus = EventBus.getInstance();

    TargetCacheManager.initialize();
};

_root.帧计时器.初始化任务栈(); // 调用初始化方法

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
    var 游戏世界 = _root.gameworld;
    if (--this.天气待更新时间 === 0 || !游戏世界.已更新天气) 
    {
        this.eventBus.publish("WeatherUpdated");
        if(!游戏世界.已更新天气){            
            游戏世界.已更新天气 = true;//保证换场景可切换
            _global.ASSetPropFlags(游戏世界, ["已更新天气"], 1, true);

            // 清理缓存，避免循环引用

            Delegate.clearCache();
            Dictionary.destroyStatic();

            this.eventBus.publish("SceneChanged");

            // 游戏世界.onUnload = function()
            // {
            //     _root.常用工具函数.释放对象绘图内存(游戏世界);
            //     //_root.服务器.发布服务器消息("游戏世界卸载");	
            // };

        }
        
        this.天气待更新时间 = this.更新天气间隔 * (1 + this.性能等级);

    }
};



_root.帧计时器.键盘输入控制目标 = function()
{
    var 控制对象 = _root.gameworld[_root.控制目标];
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

_root.帧计时器.eventBus.subscribe("frameUpdate", function() {
    this.当前帧数 = this.server.currentFrame;
}, _root.帧计时器);

_root.帧计时器.eventBus.subscribe("frameUpdate", function() {
    var tasks = this.ScheduleTimer.tick();
    // this.server.sendServerMessage("schedule tasks");
    if (tasks != null) {
        var node = tasks.getFirst();
        while (node != null) {
            var nextNode = node.next;
            var taskID = node.taskID;
            var 任务 = this.任务哈希表[taskID];
            if (任务) {
                任务.动作();
                // this.server.sendServerMessage(taskID + " " + 任务.重复次数)
                // 处理任务重复逻辑
                if (任务.重复次数 === 1) {
                    delete this.任务哈希表[taskID];
                } else if (任务.重复次数 === true || 任务.重复次数 > 1) {
                    if (任务.重复次数 !== true) {
                        任务.重复次数 -= 1;
                    }
                    任务.待执行帧数 = 任务.间隔帧数;
                    任务.node = this.ScheduleTimer.evaluateAndInsertTask(taskID, 任务.待执行帧数);
                } else {
                    delete this.任务哈希表[taskID];
                }
            }
            node = nextNode;
        }
    }

    // 处理零帧任务
    for (var taskID in this.zeroFrameTasks) {
        var 任务 = this.zeroFrameTasks[taskID];
        任务.动作();
        if (任务.重复次数 !== true) {
            任务.重复次数 -= 1;
            if (任务.重复次数 <= 0) {
                delete this.zeroFrameTasks[taskID];
            }
        }
    }
}, _root.帧计时器);

_root.帧计时器.移除任务 = function(任务ID)
{
    var 任务 = this.任务哈希表[任务ID];
    // this.server.sendServerMessage("remove task " + 任务ID);
    if (任务) 
    {
        var 节点 = 任务.节点;
        this.ScheduleTimer.removeTaskByNode(节点);
        delete this.任务哈希表[任务ID];  // Remove from hash table
    } else if (this.zeroFrameTasks[任务ID]) {
        delete this.zeroFrameTasks[任务ID]; // Remove from zero-frame tasks
    }
};



// 添加任务函数
_root.帧计时器.添加任务 = function(动作, 间隔时间, 重复次数) {
    var 任务ID = ++this.任务ID计数器;
    var 间隔帧数 = Math.ceil(间隔时间 * this.毫秒每帧);
    
    // 提取额外参数（动态参数）
    var 参数数组 = arguments.length > 3 ? ArgumentsUtil.sliceArgs(arguments, 3) : [];
    // this.server.sendServerMessage("add task " + 参数数组 + " " + 间隔时间 + " " + 重复次数);
    // 创建任务对象
    var 任务 = {
        id: 任务ID,
        间隔帧数: 间隔帧数,
        重复次数: 重复次数 === undefined || 重复次数 === null ? 1 : 重复次数
    };

    任务.动作 = Delegate.createWithParams(任务, 动作, 参数数组);

    if (间隔帧数 <= 0) {
        this.zeroFrameTasks[任务ID] = 任务; // 立即执行任务
    } else {
        任务.待执行帧数 = 间隔帧数;
        任务.节点 = this.ScheduleTimer.evaluateAndInsertTask(任务ID, 间隔帧数);  // 调度任务
        this.任务哈希表[任务ID] = 任务; // 将任务存储在哈希表中
    }

    return 任务ID; // 返回任务 ID
};




_root.帧计时器.添加单次任务 = function(动作, 间隔时间) 
{
    var 参数数组 = arguments.length > 2 ? ArgumentsUtil.sliceArgs(arguments, 2) : [];
    // this.server.sendServerMessage("add once task " + 参数数组 + " " + 间隔时间);
    // 检查间隔时间是否小于或等于0
    if (间隔时间 <= 0) {
        // 使用 Delegate.createWithParams 预绑定参数
        var 绑定动作 = Delegate.createWithParams(null, 动作, 参数数组);
        绑定动作(); // 执行预绑定的动作函数


        return null; // 返回特殊值，表示任务已立即执行
    } else {
        // 任务ID生成
        var 任务ID = ++this.任务ID计数器;
        var 间隔帧数 = Math.ceil(间隔时间 * this.毫秒每帧);

        // 创建任务对象
        var 任务 = {
            id: 任务ID,
            间隔帧数: 间隔帧数,
            重复次数: 1
        };
        
        任务.动作 = Delegate.createWithParams(任务, 动作, 参数数组);

        // 判断是否需要立即执行
        if (间隔帧数 <= 0) {
            this.zeroFrameTasks[任务ID] = 任务; // 立即执行任务
        } else {
            任务.待执行帧数 = 间隔帧数;
            任务.节点 = this.ScheduleTimer.evaluateAndInsertTask(任务ID, 间隔帧数); // 调度任务
            this.任务哈希表[任务ID] = 任务; // 将任务存储在哈希表中
        }

        return 任务ID; // 返回任务ID
    }
};




_root.帧计时器.添加循环任务 = function(动作, 间隔时间) {
    // 任务ID生成
    var 任务ID = ++this.任务ID计数器;
    var 间隔帧数 = Math.ceil(间隔时间 * this.毫秒每帧);

    // 提取额外参数（动态参数）
    var 参数数组 = arguments.length > 2 ? ArgumentsUtil.sliceArgs(arguments, 2) : [];
    // this.server.sendServerMessage("add loop task " + 参数数组 + " " + 间隔时间);
    // 创建任务对象
    var 任务 = {
        id: 任务ID,
        间隔帧数: 间隔帧数,
        重复次数: true  // 循环任务的标志
    };

    任务.动作 = Delegate.createWithParams(任务, 动作, 参数数组);

    // 判断是否需要立即执行
    if (间隔帧数 <= 0) {
        this.zeroFrameTasks[任务ID] = 任务; // 立即执行任务
    } else {
        任务.待执行帧数 = 间隔帧数;
        任务.节点 = this.ScheduleTimer.evaluateAndInsertTask(任务ID, 间隔帧数); // 调度任务
        this.任务哈希表[任务ID] = 任务; // 将任务存储在哈希表中
    }

    return 任务ID; // 返回任务ID
};


_root.帧计时器.添加或更新任务 = function(对象, 标签名, 动作, 间隔时间) {
    if(!对象) return;
    if (!对象.任务标识) 对象.任务标识 = {};
    if (!对象.任务标识[标签名]) {
        对象.任务标识[标签名] = ++this.任务ID计数器;
    }

    var 任务ID = 对象.任务标识[标签名];
    var 间隔帧数 = Math.ceil(间隔时间 * this.毫秒每帧);
    
    // 提取额外参数（动态参数）
    var 参数数组 = arguments.length > 4 ? ArgumentsUtil.sliceArgs(arguments, 4) : [];
    // this.server.sendServerMessage("update " + 任务ID + " " + 标签名 + 参数数组 + " " + 间隔时间);
    // 获取任务，从任务哈希表或者 zeroFrameTasks
    var 任务 = this.任务哈希表[任务ID] || this.zeroFrameTasks[任务ID];
    if (任务) {
        // 更新现有任务
        任务.动作 = Delegate.createWithParams(对象, 动作, 参数数组);
        任务.间隔帧数 = 间隔帧数;
        任务.参数数组 = 参数数组;

        if (间隔帧数 === 0) {
            // 将任务移到 zeroFrameTasks
            if (this.任务哈希表[任务ID]) {
                this.ScheduleTimer.removeTaskByNode(任务.节点);
                delete 任务.节点;
                delete this.任务哈希表[任务ID];
                this.zeroFrameTasks[任务ID] = 任务;
            }
        } else {
            if (this.zeroFrameTasks[任务ID]) {
                // 从 zeroFrameTasks 移动到任务哈希表
                delete this.zeroFrameTasks[任务ID];
                任务.待执行帧数 = 间隔帧数;
                任务.节点 = this.ScheduleTimer.evaluateAndInsertTask(任务ID, 间隔帧数);
                this.任务哈希表[任务ID] = 任务;
            } else {
                // 重新调度任务
                任务.待执行帧数 = 间隔帧数;
                this.ScheduleTimer.rescheduleTaskByNode(任务.节点, 间隔帧数);
            }
        }
    } else {
        // 如果任务不存在，创建新任务
        任务 = {
            id: 任务ID,
            间隔帧数: 间隔帧数,
            重复次数: 1,
            参数数组: 参数数组
        };

        任务.动作 = Delegate.createWithParams(对象, 动作, 参数数组);

        if (间隔帧数 === 0) {
            this.zeroFrameTasks[任务ID] = 任务;
        } else {
            任务.待执行帧数 = 间隔帧数;
            任务.节点 = this.ScheduleTimer.evaluateAndInsertTask(任务ID, 间隔帧数);
            this.任务哈希表[任务ID] = 任务;
        }
    }

    return 任务ID;
};



_root.帧计时器.添加生命周期任务 = function(对象, 标签名, 动作, 间隔时间) {
    if(!对象) return;
    if (!对象.任务标识) 对象.任务标识 = {};
    if (!对象.任务标识[标签名]) {
        对象.任务标识[标签名] = ++this.任务ID计数器;
    }

    var 任务ID = 对象.任务标识[标签名];
    var 间隔帧数 = Math.ceil(间隔时间 * this.毫秒每帧);

    // 提取额外参数（动态参数）
    var 参数数组 = arguments.length > 4 ? ArgumentsUtil.sliceArgs(arguments, 4) : [];
    // this.server.sendServerMessage("life " + 任务ID + " " + 标签名 + 参数数组 + " " + 间隔时间);
    // 使用 Delegate.createWithParams 预绑定参数
    var 绑定动作 = Delegate.createWithParams(对象, 动作, 参数数组);

    // 获取或创建任务
    var 任务 = this.任务哈希表[任务ID] || this.zeroFrameTasks[任务ID];
    if (任务) {
        // 更新现有任务
        任务.动作 = 绑定动作;
        任务.间隔帧数 = 间隔帧数;
        任务.参数数组 = 参数数组;
        任务.重复次数 = true; // 无限循环

        if (间隔帧数 === 0) {
            if (this.任务哈希表[任务ID]) {
                // 移动任务到 zeroFrameTasks
                this.ScheduleTimer.removeTaskByNode(任务.节点);
                delete 任务.节点;
                delete this.任务哈希表[任务ID];
                this.zeroFrameTasks[任务ID] = 任务;
            }
        } else {
            if (this.zeroFrameTasks[任务ID]) {
                // 从 zeroFrameTasks 移到任务哈希表
                delete this.zeroFrameTasks[任务ID];
                任务.待执行帧数 = 间隔帧数;
                任务.节点 = this.ScheduleTimer.evaluateAndInsertTask(任务ID, 间隔帧数);
                this.任务哈希表[任务ID] = 任务;
            } else {
                // 重新调度任务
                任务.待执行帧数 = 间隔帧数;
                this.ScheduleTimer.rescheduleTaskByNode(任务.节点, 间隔帧数);
            }
        }
    } else {
        // 创建新任务
        任务 = {
            id: 任务ID,
            动作: 绑定动作,
            间隔帧数: 间隔帧数,
            重复次数: true, // 无限循环
            参数数组: 参数数组
        };

        if (间隔帧数 === 0) {
            this.zeroFrameTasks[任务ID] = 任务;
        } else {
            任务.待执行帧数 = 间隔帧数;
            任务.节点 = this.ScheduleTimer.evaluateAndInsertTask(任务ID, 间隔帧数);
            this.任务哈希表[任务ID] = 任务;
        }
    }

    // 设置卸载回调函数
    _root.常用工具函数.设置卸载回调(对象, function() {
        _root.帧计时器.移除任务(任务ID);
        delete this.任务标识[标签名];
    });

    return 任务ID;
};




_root.帧计时器.定位任务 = function(任务ID)
{  
    return this.任务哈希表[任务ID] || this.zeroFrameTasks[任务ID] || null;
};



_root.帧计时器.延迟执行任务 = function(任务ID, 延迟时间) 
{  
    var 任务 = this.任务哈希表[任务ID] || this.zeroFrameTasks[任务ID];

    if (任务) 
    {  
        var 延迟帧数;
        if (isNaN(延迟时间))
        {
            任务.待执行帧数 = 延迟时间 === true ? Infinity : 任务.间隔帧数;
        }
        else
        {
            延迟帧数 = Math.ceil(延迟时间 * this.毫秒每帧);
            任务.待执行帧数 += 延迟帧数;
        }

        if (任务.待执行帧数 <= 0) {
            // Should be a zero-frame task
            if (this.任务哈希表[任务ID]) {
                // Move to zeroFrameTasks
                this.ScheduleTimer.removeTaskByNode(任务.节点);
                delete 任务.节点;
                delete this.任务哈希表[任务ID];
                this.zeroFrameTasks[任务ID] = 任务;
            }
            // Else, already in zeroFrameTasks
        } else {
            // Should be in ScheduleTimer
            if (this.zeroFrameTasks[任务ID]) {
                // Move to 任务哈希表 and schedule
                delete this.zeroFrameTasks[任务ID];
                任务.节点 = this.ScheduleTimer.evaluateAndInsertTask(任务ID, 任务.待执行帧数);
                this.任务哈希表[任务ID] = 任务;
            } else {
                // Reschedule in ScheduleTimer
                this.ScheduleTimer.rescheduleTaskByNode(任务.节点, 任务.待执行帧数);
            }
        }

        return true; // Delay set successfully
    }  
    return false; // Task not found, delay set failed
};

EventBus.getInstance().subscribe("SceneChanged", StaticInitializer.onSceneChanged, StaticInitializer); 

_root.帧计时器.获取敌人缓存 = Delegate.create(TargetCacheManager, TargetCacheManager.getCachedEnemy);
_root.帧计时器.获取友军缓存 = Delegate.create(TargetCacheManager, TargetCacheManager.getCachedAlly);

_root.帧计时器.添加主动战技cd = function(动作, 间隔时间){
    return _root.帧计时器.添加单次任务(动作, 间隔时间); // 返回任务ID
};


_root.帧计时器.eventBus.subscribe("SceneChanged", SceneCoordinateManager.update
, SceneCoordinateManager); 




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
