import org.flashNight.neur.Controller.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.sara.*;
import org.flashNight.neur.Server.*; 
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.corpse.DeathEffectRenderer;
import org.flashNight.gesh.arguments.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.key.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.bullet.Factory.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.gesh.object.*;
import org.flashNight.neur.InputCommand.CommandRegistry;
import org.flashNight.neur.InputCommand.CommandConfig;
import org.flashNight.neur.InputCommand.CommandDFA;
import org.flashNight.neur.InputCommand.InputSampler;
import org.flashNight.gesh.xml.LoadXml.InputCommandListXMLLoader;
import org.flashNight.gesh.xml.LoadXml.InputCommandRuntimeConfigLoader;
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
    this.性能等级上限 = 0;
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
        _root.服务器.发布服务器消息("主程序：PIDControllerConfig.xml 加载失败");
    }
    pidFactory.createPIDController(onPIDSuccess, onPIDFailure);
    
    // --------------------------
    // 初始化任务调度部分：创建 ScheduleTimer 和 TaskManager 实例
    // --------------------------
    this.ScheduleTimer = new CerberusScheduler();
    this.singleWheelSize = 150;        // 单层时间轮大小（帧），处理 0-149 帧的短期任务
    this.multiLevelSecondsSize = 60;   // 二级时间轮大小（秒），处理 5-60 秒的中期任务
    this.multiLevelMinutesSize = 60;   // 三级时间轮大小（分），处理 1-60 分钟的长期任务
    // [DEPRECATED v1.6] precisionThreshold 参数已废弃，不再影响任务路由
    // 保留此参数仅为 API 兼容性，任务路由现直接基于时间轮边界
    // 如需高精度调度，请使用 ScheduleTimer.addToMinHeapByID() 直接绕过时间轮
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
        WaveSpawner.instance.tick(); // 暂时把刷怪挂在这边
        // _root.服务器.发布服务器消息("frameUpdate")
        // _root.服务器.发布服务器消息(_root.场景进入位置名)
        // Mover.getWalkableDirections(TargetCacheManager.findHero());
    }, this);


    this.eventBus.subscribe("frameEnd", function():Void {
        // 帧末批量处理伤害数字显示
        HitNumberBatchProcessor.flush();
        // _root.服务器.发布服务器消息("frameEnd")
    }, this);
};

// 调用初始化方法
_root.帧计时器.初始化任务栈();

// ===================================================================
// 搓招输入系统初始化（多模组版本 + XML 异步加载）
// ===================================================================

/**
 * 构建搓招模组
 * 从 CommandConfig 获取配置并编译 DFA
 * 此方法在 XML 加载完成后或直接使用硬编码时调用
 */
_root.帧计时器.构建搓招模组 = function():Void {
    this.commandModules = {};

    // 空手模组
    var bareReg:CommandRegistry = new CommandRegistry(64);
    bareReg.loadConfig(CommandConfig.getBarehanded());
    bareReg.compile();
    this.commandModules["barehand"] = {
        registry: bareReg,
        dfa: bareReg.getDFA()
    };

    // 轻武器模组
    var lightReg:CommandRegistry = new CommandRegistry(64);
    lightReg.loadConfig(CommandConfig.getLightWeapon());
    lightReg.compile();
    this.commandModules["lightWeapon"] = {
        registry: lightReg,
        dfa: lightReg.getDFA()
    };

    // 重武器模组
    var heavyReg:CommandRegistry = new CommandRegistry(64);
    heavyReg.loadConfig(CommandConfig.getHeavyWeapon());
    heavyReg.compile();
    this.commandModules["heavyWeapon"] = {
        registry: heavyReg,
        dfa: heavyReg.getDFA()
    };

    _root.服务器.发布服务器消息("[帧计时器] 多模组搓招系统构建完成",bareReg.toString(),lightReg.toString(),heavyReg.toString());

    // 输入采样器（共用）
    this.inputSampler = new InputSampler();

    _root.服务器.发布服务器消息("[帧计时器] 多模组搓招系统构建完成");
};

/**
 * 初始化搓招输入系统（带 XML 异步加载）
 * 优先尝试从 XML 加载配置，失败则回退到硬编码
 */
_root.帧计时器.初始化输入搓招系统 = function():Void {
    var self = this;

    _root.服务器.发布服务器消息("[帧计时器] 开始加载搓招系统 XML 配置...");

    // 1. 先加载运行时配置
    var runtimeLoader:InputCommandRuntimeConfigLoader = new InputCommandRuntimeConfigLoader(
        "data/config/InputCommandRuntimeConfig.xml"
    );

    runtimeLoader.load(
        function(runtimeConfig:Object):Void {
            _root.服务器.发布服务器消息("[帧计时器] 运行时配置加载成功");

            // 2. 加载搓招命令配置列表
            var listLoader:InputCommandListXMLLoader = new InputCommandListXMLLoader(
                "data/inputCommand/list.xml"
            );

            listLoader.loadAll(
                function(configs:Object):Void {
                    _root.服务器.发布服务器消息("[帧计时器] 搓招配置 XML 加载成功");

                    // 注入到 CommandConfig
                    CommandConfig.setXMLConfigs(configs);

                    // 构建模组
                    self.构建搓招模组();
                },
                function():Void {
                    // XML 加载失败，使用硬编码
                    _root.服务器.发布服务器消息("[帧计时器] 搓招配置 XML 加载失败，使用硬编码");
                    self.构建搓招模组();
                }
            );
        },
        function():Void {
            // 运行时配置加载失败，继续尝试加载命令配置
            _root.服务器.发布服务器消息("[帧计时器] 运行时配置加载失败，使用默认值");

            var listLoader:InputCommandListXMLLoader = new InputCommandListXMLLoader(
                "data/inputCommand/list.xml"
            );

            listLoader.loadAll(
                function(configs:Object):Void {
                    _root.服务器.发布服务器消息("[帧计时器] 搓招配置 XML 加载成功");
                    CommandConfig.setXMLConfigs(configs);
                    self.构建搓招模组();
                },
                function():Void {
                    _root.服务器.发布服务器消息("[帧计时器] 搓招配置 XML 加载失败，使用硬编码");
                    self.构建搓招模组();
                }
            );
        }
    );
};

/**
 * 同步初始化搓招系统（不使用 XML，直接用硬编码）
 * 用于测试环境或需要立即可用的场景
 */
_root.帧计时器.初始化输入搓招系统同步 = function():Void {
    CommandConfig.disableXMLMode();
    this.构建搓招模组();
    _root.服务器.发布服务器消息("[帧计时器] 搓招系统同步初始化完成（硬编码模式）");
};

/**
 * 根据单位的 兵器动作类型 推断对应的搓招模组
 * @param unit 单位对象
 * @return 模组名: "barehand" | "lightWeapon" | "heavyWeapon"
 */
_root.帧计时器.推断动作模组 = function(unit:Object):String {
    var state:String = unit.攻击模式;

    // 空手模式 → barehand（最常见路径，最先判断并立即返回）
    if (state == "空手") {
        return "barehand";
    }

    // 非空手时才计算技能状态
    var isSkillState:Boolean = (state == "技能" || state == "战技");

    // 拳类技能/战技 → barehand
    if (isSkillState && HeroUtil.isFistSkill(unit.技能名)) {
        return "barehand";
    }

    // 兵器模式，或非拳技能/战技 → 根据兵器动作类型轻重划分
    if (state == "兵器" || isSkillState) {
        var actionType:String = unit.兵器动作类型;
        if (actionType == "长柄" || actionType == "长枪" ||
            actionType == "长棍" || actionType == "狂野" ||
            actionType == "重斩" || actionType == "镰刀") {
            return "heavyWeapon";
        }
        return "lightWeapon";
    }

};

// 调用搓招系统初始化（异步加载 XML）
_root.帧计时器.初始化输入搓招系统();

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
        currentPerformanceLevel = Math.max(this.性能等级上限, Math.min(currentPerformanceLevel, 3));

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
            EffectSystem.isDeathEffect = true;
            _root.面积系数 = 300000;
            _root.同屏打击数字特效上限 = 25;
            DeathEffectRenderer.isEnabled = true;
            DeathEffectRenderer.enableCulling = false;
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
            EffectSystem.isDeathEffect = true;
            _root.面积系数 = 450000;
            _root.同屏打击数字特效上限 = 18;
            DeathEffectRenderer.isEnabled = true;
            DeathEffectRenderer.enableCulling = true;
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
            EffectSystem.isDeathEffect = false;
            _root.面积系数 = 600000; //刷佣兵数量砍半
            _root.同屏打击数字特效上限 = 12;
            DeathEffectRenderer.isEnabled = false;
            DeathEffectRenderer.enableCulling = true;
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
            EffectSystem.isDeathEffect = false;
            _root.面积系数 = 3000000;  //刷佣兵为原先十分之一
            _root.同屏打击数字特效上限 = 10;
            DeathEffectRenderer.isEnabled = false;
            DeathEffectRenderer.enableCulling = true;
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
        // 暂停时重置搓招状态
        控制对象.commandId = 0;
        控制对象.当前搓招ID = 0;
        控制对象.当前搓招名 = "";
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
        // Shift 奔跑 与 双击方向奔跑 合并判定
        // - actionsPressed：按下任一 A/B/C 则不允许进入奔跑
        // - shiftRun：按住“奔跑键”（默认 Shift）时触发
        // - doubleRun：UI 层通过 KeyManager 订阅双击左右键后设置的方向意图
        //              ctrl.doubleTapRunDirection = -1（左）/ 1（右），松开方向键自动清零
        var actionsPressed:Boolean = (mask & (16 | 32 | 64)) != 0;
        var shiftRun:Boolean = !actionsPressed && ((mask & 128) != 0);

        var doubleRun:Boolean = false;
        var dir:Number = 控制对象.doubleTapRunDirection;
        if (dir) {  // dir 为 null/undefined/0 时都为 false
            var leftPressed:Boolean = (mask & 1) != 0;
            var rightPressed:Boolean = (mask & 2) != 0;
            doubleRun = !actionsPressed && ((dir < 0 && leftPressed) || (dir > 0 && rightPressed));
            // 若水平方向均未按下，则清除双击奔跑方向
            if (!leftPressed && !rightPressed) {
                控制对象.doubleTapRunDirection = 0;
            }
        }

        控制对象.强制奔跑 = shiftRun || doubleRun;

        // === 搓招系统刷新（多模组版本 + 缓冲机制）===
        var sampler:InputSampler = this.inputSampler;
        var 模组名:String = this.推断动作模组(控制对象);
        var module:Object = this.commandModules[模组名];
        var frame:Number = this.当前帧数;

        if (sampler != null && module != null) {
            var dfa:CommandDFA = module.dfa;

            // 模组切换时重置状态（不同DFA的state含义不同）
            if (控制对象.当前搓招模组 != 模组名) {
                控制对象.commandState = 0;
                控制对象.stepTimer = 0;
                // 模组切换也清空缓冲
                控制对象.搓招缓冲ID = 0;
                控制对象.搓招缓冲已消费 = true;
            }

            // 1. 从玩家对象采样本帧输入事件
            var events:Array = sampler.sample(控制对象);

            // 2. 更新搓招状态机（updateFast 性能最优）
            dfa.updateFast(控制对象, events, 5);

            // 3. 搓招缓冲机制：识别到新招式时写入缓冲
            if (控制对象.commandId != 0) {
                控制对象.搓招缓冲ID = 控制对象.commandId;
                控制对象.搓招缓冲帧 = frame;
                控制对象.搓招缓冲已消费 = false;
            }

            // 4. 根据宽容帧数决定当前帧是否有有效搓招
            var tolerance:Number = InputCommandRuntimeConfigLoader.bufferTolerance;
            var active:Boolean = false;

            if (控制对象.搓招缓冲ID != 0 &&
                !控制对象.搓招缓冲已消费 &&
                frame - 控制对象.搓招缓冲帧 <= tolerance) {
                active = true;
            }

            // 5. 为脚本层挂载易用字段
            控制对象.最近搓招ID = 控制对象.lastCommandId;
            控制对象.当前搓招模组 = 模组名;

            if (active) {
                控制对象.当前搓招ID = 控制对象.搓招缓冲ID;
                控制对象.当前搓招名 = dfa.getCommandName(控制对象.搓招缓冲ID);
            } else {
                控制对象.当前搓招ID = 0;
                控制对象.当前搓招名 = "";
                // 超过宽容帧数，清空缓冲
                if (控制对象.搓招缓冲ID != 0 && frame - 控制对象.搓招缓冲帧 > tolerance) {
                    控制对象.搓招缓冲ID = 0;
                }
            }
        }
        // 只在识别瞬间（缓冲帧=0）输出日志，避免刷屏
        if(控制对象.当前搓招名 !== "" && frame == 控制对象.搓招缓冲帧){
            var 输入序列:String = sampler.eventsToString(events);
            _root.发布消息(_root.帧计时器.当前帧数 + ":模组=" + 模组名 + " 搓招=" + 控制对象.当前搓招名 + " 输入=[" + 输入序列 + "]");
        }
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
    // _root.发布消息(System.IME.getEnabled())
}, _root.帧计时器);

_root.帧计时器.eventBus.subscribe("frameUpdate", function() {
    _root.显示列表.播放列表();
}, _root.帧计时器);


// ---------------------------------------------------
// 以下为对外公开的任务调度方法，均为包装 TaskManager 方法
// ---------------------------------------------------

// 【添加任务】（通用版：可指定执行次数或无限循环）
_root.帧计时器.添加任务 = function(action:Function, interval:Number, repeatCount):String {
    // 提取额外动态参数
    var parameters:Array = (arguments.length > 3) ? ArgumentsUtil.sliceArgs(arguments, 3) : [];
    return this.taskManager.addTask(action, interval, repeatCount, parameters);
};

// 【添加单次任务】（间隔 <= 0 时直接执行，返回 null）
_root.帧计时器.添加单次任务 = function(action:Function, interval:Number):String {
    var parameters:Array = (arguments.length > 2) ? ArgumentsUtil.sliceArgs(arguments, 2) : [];
    return this.taskManager.addSingleTask(action, interval, parameters);
};

// 【添加循环任务】（无限重复执行）
_root.帧计时器.添加循环任务 = function(action:Function, interval:Number):String {
    var parameters:Array = (arguments.length > 2) ? ArgumentsUtil.sliceArgs(arguments, 2) : [];
    return this.taskManager.addLoopTask(action, interval, parameters);
};

// 【添加或更新任务】（相同对象+标签，只会存在一个任务）
_root.帧计时器.添加或更新任务 = function(obj:Object, labelName:String, action:Function, interval:Number):String {
    var parameters:Array = (arguments.length > 4) ? ArgumentsUtil.sliceArgs(arguments, 4) : [];
    return this.taskManager.addOrUpdateTask(obj, labelName, action, interval, parameters);
};

// 【添加生命周期任务】（无限循环，并绑定对象卸载时的清理回调）
_root.帧计时器.添加生命周期任务 = function(obj:Object, labelName:String, action:Function, interval:Number):String {
    var parameters:Array = (arguments.length > 4) ? ArgumentsUtil.sliceArgs(arguments, 4) : [];
    return this.taskManager.addLifecycleTask(obj, labelName, action, interval, parameters);
};

// 【移除任务】（根据任务ID删除任务，内部会通知 ScheduleTimer 移除）
_root.帧计时器.移除任务 = function(taskID:Number):Void {
    this.taskManager.removeTask(taskID);
};

// 【移除生命周期任务】[NEW v1.6]（通过 obj + labelName 移除生命周期任务）
// 适用于不跟踪 taskID 的场景，会同时清理 obj.taskLabel[labelName]
_root.帧计时器.移除生命周期任务 = function(obj:Object, labelName:String):Boolean {
    return this.taskManager.removeLifecycleTask(obj, labelName);
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
    System.IME.setEnabled(false);
    _root.关卡结束界面._visible = false;
    // 清空打击数字批处理队列，避免跨场景残留
    HitNumberBatchProcessor.clear();
    // 重置 DamageResult 的 displayFunction 引用，确保类加载后引用正确
    // 这是解耦 _root 依赖后的初始化保障
    org.flashNight.arki.component.Damage.DamageResult.IMPACT.displayFunction = HitNumberSystem.effect;
    org.flashNight.arki.component.Damage.DamageResult.NULL.displayFunction = HitNumberSystem.effect;
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

// 保存 stageWatcher 到 _root.帧计时器 以便在 cleanupForRestart 时移除
_root.帧计时器.stageWatcher = {};

_root.帧计时器.stageWatcher.onFullScreen = function(nowFull:Boolean):Void {
    EventBus.getInstance().publish("FlashFullScreenChanged", nowFull);
};
_root.帧计时器.stageWatcher.onResize = function():Void {
    // 记录舞台大小变化
    _root.发布消息("Flash 大小状态变更: ", Stage.width, Stage.height);
};
Stage.addListener(_root.帧计时器.stageWatcher);

EventBus.getInstance().subscribe("SceneChanged", function() {
    /*
    // ══════════════════════════════════════════════════════════════════════════════
    // 刀口数量自动化检测脚本（仅执行一次）
    // 任务：遍历所有刀类武器，检测刀口数量并输出到服务器消息
    // ══════════════════════════════════════════════════════════════════════════════
    if (!_root.刀口检测已完成) {
        _root.刀口检测已完成 = true;

        var ItemUtil = org.flashNight.arki.item.ItemUtil;
        var MeleeStatsBuilder = org.flashNight.gesh.tooltip.builder.MeleeStatsBuilder;

        var itemDataDict:Object = ItemUtil.itemDataDict;
        var meleeWeapons:Array = [];
        var results:Array = [];

        // 第一步：收集所有刀类武器
        // 注意：dressup 在 itemData.data 内部，不在顶层
        for (var itemName:String in itemDataDict) {
            var itemData:Object = itemDataDict[itemName];
            if (itemData.use === "刀") {
                var dressup:String = (itemData.data && itemData.data.dressup) ? itemData.data.dressup : null;
                meleeWeapons.push({
                    name: itemName,
                    icon: itemData.icon,
                    dressup: dressup
                });
            }
        }

        _root.服务器.发布服务器消息("=== 刀口数量检测开始 ===");
        _root.服务器.发布服务器消息("共发现 " + meleeWeapons.length + " 把刀类武器");

        // 第二步：逐个检测刀口数量
        for (var i:Number = 0; i < meleeWeapons.length; i++) {
            var weapon:Object = meleeWeapons[i];
            var bladeCount:Number = MeleeStatsBuilder.getBladeCount(weapon.dressup, weapon.icon);

            results.push({
                name: weapon.name,
                icon: weapon.icon,
                dressup: weapon.dressup,
                bladeCount: bladeCount
            });

            // 输出检测结果
            var dressupInfo:String = weapon.dressup ? weapon.dressup : "(无)";
            _root.服务器.发布服务器消息(
                "[" + (i + 1) + "/" + meleeWeapons.length + "] " +
                weapon.name + " | 刀口数: " + bladeCount +
                " | dressup: " + dressupInfo +
                " | icon: " + weapon.icon
            );
        }

        // 第三步：统计汇总（使用数组，索引即刀口数）
        var countStats:Array = [0, 0, 0, 0, 0, 0, 0]; // 索引 0-6
        for (var j:Number = 0; j < results.length; j++) {
            var bc:Number = results[j].bladeCount;
            if (bc >= 0 && bc <= 6) {
                countStats[bc]++;
            }
        }

        _root.服务器.发布服务器消息("=== 刀口数量统计 ===");
        for (var k:Number = 0; k <= 6; k++) {
            if (countStats[k] > 0) {
                _root.服务器.发布服务器消息("刀口数 " + k + ": " + countStats[k] + " 把");
            }
        }
        _root.服务器.发布服务器消息("=== 刀口数量检测完成 ===");

        // 将结果存储到全局变量，便于后续处理
        _root.刀口检测结果 = results;
    }
    // ══════════════════════════════════════════════════════════════════════════════

    */
    
	// _root.服务器.发布服务器消息("准备清理地图信息")
    _root.gameworld.frameFlag = _root.帧计时器.当前帧数;
	_root.帧计时器.添加或更新任务(_root.gameworld, "ASSetPropFlags", function() {
		var arr:Array = [   "效果", 
							"子弹区域", 
							"已更新天气",
							"动画",
							"背景",
							"地图",
							"出生地",
							"deadbody",
							"允许通行",
                            "frameFlag"
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

// ===================================================================
// 关卡性能动态调控接口
// 用于在关卡事件中手动控制性能等级，配合PID自动调控系统使用
// ===================================================================

/**
 * 手动设置性能等级（关卡事件调用）
 * 强制设置到指定档位，PID系统会继续运行并自动回升
 *
 * @param 目标等级 0=高画质 1=中画质 2=低画质 3=最低画质
 * @param 保持秒数 （可选）手动设置的性能等级保持时间（秒），默认5秒
 *
 * 使用场景：
 *   - SubStage 4 开始时强制设为2档
 *   - SubWave 2 开始时强制设为3档（最低）
 *   - 战斗结束时恢复到1档
 *
 * 示例：
 *   _root.帧计时器.手动设置性能等级(2); // 强制降至低画质，保持5秒
 *   _root.帧计时器.手动设置性能等级(3, 10); // 强制最低画质，保持10秒
 */
_root.帧计时器.手动设置性能等级 = function(目标等级:Number, 保持秒数:Number):Void {
    // 规范化等级值
    目标等级 = Math.round(目标等级);
    目标等级 = Math.max(this.性能等级上限, Math.min(目标等级, 3));

    // 只在等级真正改变时执行
    if (this.性能等级 !== 目标等级) {
        // 执行性能调整
        this.性能等级 = 目标等级;
        this.执行性能调整(目标等级);

        // 重置PID状态，避免立即被自动调控覆盖
        this.PID.reset();
        this.awaitConfirmation = false;

        // 重要：同步更新帧率测量相关参数
        var currentTime:Number = getTimer();

        // 重置开始时间，确保下次帧率计算准确
        this.frameStartTime = currentTime;

        // 设置测量间隔：默认5秒，或使用指定的保持时间
        if (保持秒数 == undefined || 保持秒数 <= 0) {
            保持秒数 = 5; // 默认保持5秒
        }

        // 将保持时间转换为帧数
        // 使用更长的间隔来推迟下次性能评估
        this.measurementIntervalFrames = Math.max(
            this.帧率 * 保持秒数,  // 保持时间对应的帧数
            this.帧率 * (1 + 目标等级)  // 至少保持正常的测量间隔
        );

        // 更新实际帧率显示，使用合理的估算值
        // 基于目标性能等级估算期望帧率
        var 估算帧率:Number = this.帧率 - 目标等级 * 2;
        this.实际帧率 = 估算帧率;
        _root.玩家信息界面.性能帧率显示器.帧率数字.text = this.实际帧率;

        // 更新帧率数据和曲线
        this.更新帧率数据(this.实际帧率);
        this.绘制帧率曲线();

        // 发布消息提示
        _root.发布消息(
            "手动设置性能等级: [" + 目标等级 + "] 保持" + 保持秒数 + "秒"
        );
    }
};

/**
 * 降低性能等级（预防性降档）
 * 在当前等级基础上下降N档，适合不确定当前档位时使用
 *
 * @param 下降档数 下降的档位数量，默认1档
 * @param 保持秒数 （可选）性能等级保持时间（秒），默认5秒
 *
 * 使用场景：
 *   - SubStage 1/3 开始时预防性降1档
 *   - 中等压力波次的柔和调控
 *
 * 示例：
 *   _root.帧计时器.降低性能等级(1); // 降1档，保持5秒
 *   _root.帧计时器.降低性能等级(2, 10); // 降2档，保持10秒
 */
_root.帧计时器.降低性能等级 = function(下降档数:Number, 保持秒数:Number):Void {
    下降档数 = 下降档数 || 1;
    var 新等级:Number = this.性能等级 + 下降档数;
    this.手动设置性能等级(新等级, 保持秒数);
};

/**
 * 提升性能等级（恢复性升档）
 * 在当前等级基础上提升N档，用于战斗结束后恢复画质
 *
 * @param 提升档数 提升的档位数量，默认1档
 * @param 保持秒数 （可选）性能等级保持时间（秒），默认5秒
 *
 * 使用场景：
 *   - 战斗结束后恢复画质
 *   - 低压力场景提升体验
 *
 * 示例：
 *   _root.帧计时器.提升性能等级(1); // 升1档，保持5秒
 *   _root.帧计时器.提升性能等级(2, 3); // 升2档，保持3秒
 */
_root.帧计时器.提升性能等级 = function(提升档数:Number, 保持秒数:Number):Void {
    提升档数 = 提升档数 || 1;
    var 新等级:Number = this.性能等级 - 提升档数;
    this.手动设置性能等级(新等级, 保持秒数);
};

// ===================================================================
// cleanupForRestart - 游戏重启前的统一清理入口
// 用于 loadMovieNum(..., 0) 重载主 SWF 前清理所有持久状态
// ===================================================================

/**
 * 清理所有持久状态，为游戏重启做准备
 *
 * 调用时机：
 *   - 返回主菜单前
 *   - 重新开始游戏前
 *   - 任何需要 loadMovieNum 重载的场景前
 *
 * 清理顺序按依赖关系排列：
 *   1. StageManager (持有 WaveSpawner, StageEventHandler 引用)
 *   2. StageEventHandler (持有 gameworld.dispatcher 引用)
 *   3. WaveSpawnWheel (持有 WaveSpawner 引用)
 *   4. SceneManager (持有 gameworld MovieClip 引用)
 *   5. WaveSpawner (持有 StageManager, SceneManager, WaveSpawnWheel 引用)
 *   6. Stage/Key 监听器
 *   7. EventBus
 *   8. 音效、keyPollMC、_global 变量等
 */
_root.cleanupForRestart = function():Void {
    _root.发布消息("[cleanupForRestart] 开始清理持久状态...");

    // -------------------------
    // 1. 清理 StageManager (关卡管理器)
    // -------------------------
    if (StageManager.instance != null) {
        StageManager.instance.dispose();
        _root.发布消息("[cleanupForRestart] StageManager disposed");
    }

    // -------------------------
    // 2. 清理 StageEventHandler (关卡事件处理器)
    // -------------------------
    if (StageEventHandler.instance != null) {
        StageEventHandler.instance.dispose();
        _root.发布消息("[cleanupForRestart] StageEventHandler disposed");
    }

    // -------------------------
    // 3. 清理 WaveSpawnWheel (刷怪时间轮)
    // -------------------------
    if (WaveSpawnWheel.instance != null) {
        WaveSpawnWheel.instance.dispose();
        _root.发布消息("[cleanupForRestart] WaveSpawnWheel disposed");
    }

    // -------------------------
    // 4. 清理 SceneManager (场景管理器)
    // -------------------------
    if (SceneManager.instance != null) {
        SceneManager.instance.dispose();
        _root.发布消息("[cleanupForRestart] SceneManager disposed");
    }

    // -------------------------
    // 5. 清理 WaveSpawner (刷怪器)
    // -------------------------
    if (WaveSpawner.instance != null) {
        WaveSpawner.instance.dispose();
        _root.发布消息("[cleanupForRestart] WaveSpawner disposed");
    }

    // -------------------------
    // 6. 移除 Stage 监听器
    // -------------------------
    if (_root.帧计时器.stageWatcher != null) {
        Stage.removeListener(_root.帧计时器.stageWatcher);
        _root.帧计时器.stageWatcher = null;
        _root.发布消息("[cleanupForRestart] Stage listener removed");
    }

    // -------------------------
    // 7. 清理 EventBus
    // -------------------------
    if (EventBus.instance != null) {
        EventBus.instance.clear();
        _root.发布消息("[cleanupForRestart] EventBus cleared");
    }

    // -------------------------
    // 8. 停止所有音效
    // -------------------------
    stopAllSounds();
    _root.发布消息("[cleanupForRestart] All sounds stopped");

    // -------------------------
    // 9. 移除 keyPollMC (如果存在)
    // -------------------------
    if (_root.keyPollMC != null) {
        _root.keyPollMC.removeMovieClip();
        _root.keyPollMC = null;
        _root.发布消息("[cleanupForRestart] keyPollMC removed");
    }

    // -------------------------
    // 10. 清理 _global 持久变量
    // -------------------------
    if (_global.__HOLO_STRIPE__ != null) {
        // 释放 BitmapData
        if (_global.__HOLO_STRIPE__.dispose != null) {
            _global.__HOLO_STRIPE__.dispose();
        }
        _global.__HOLO_STRIPE__ = null;
        _root.发布消息("[cleanupForRestart] _global.__HOLO_STRIPE__ released");
    }

    // -------------------------
    // 11. 清理 TargetCacheManager
    // -------------------------
    TargetCacheManager.clear();
    _root.发布消息("[cleanupForRestart] TargetCacheManager cleared");

    // -------------------------
    // 11.5 清理 HitNumberBatchProcessor 队列
    // -------------------------
    HitNumberBatchProcessor.clear();
    _root.发布消息("[cleanupForRestart] HitNumberBatchProcessor cleared");

    // -------------------------
    // 12. 清理 CooldownWheel 和 UnitUpdateWheel
    // -------------------------
    if (_root.帧计时器.cooldownWheel != null) {
        _root.帧计时器.cooldownWheel.clear();
    }
    if (_root.帧计时器.unitUpdateWheel != null) {
        _root.帧计时器.unitUpdateWheel.clear();
    }

    // -------------------------
    // 13. 清理 TaskManager 和 ScheduleTimer
    // -------------------------
    if (_root.帧计时器.taskManager != null) {
        _root.帧计时器.taskManager.clear();
    }
    if (_root.帧计时器.ScheduleTimer != null) {
        _root.帧计时器.ScheduleTimer.clear();
    }

    _root.发布消息("[cleanupForRestart] 清理完成，可以安全重载");
};
