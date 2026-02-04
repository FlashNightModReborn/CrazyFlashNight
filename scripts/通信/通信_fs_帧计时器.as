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
import org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler;

// ╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
// ║                         自适应性能调度系统 - 控制理论架构文档                                            ║
// ║                    Adaptive Performance Scheduling System - Control Theory Architecture               ║
// ╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣
// ║                                                                                                       ║
// ║  【系统概述 System Overview】                                                                          ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║  本系统是一个「反馈控制调度（Feedback Control Scheduling）」闭环系统，                                   ║
// ║  用帧率（FPS）作为被控量（QoS指标），通过调节性能等级/画质/特效上限/刷佣兵密度等                            ║
// ║  操纵量，将系统拉回到目标帧率附近运行。                                                                 ║
// ║                                                                                                       ║
// ║  【控制框图 Control Block Diagram】                                                                    ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║                                                                                                       ║
// ║    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                       ║
// ║    │   目标FPS   │ e_k │    PID      │u*_k │   量化器    │ u_k │   执行器    │                       ║
// ║    │  r = 26     ├────►│  控制器     ├────►│  + 迟滞    ├────►│ 性能调整    │                       ║
// ║    │ (targetFPS) │     │             │     │ (0~3档)    │     │             │                       ║
// ║    └─────────────┘     └─────────────┘     └─────────────┘     └──────┬──────┘                       ║
// ║           ▲                                                           │                               ║
// ║           │                                                           ▼                               ║
// ║           │            ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                       ║
// ║           │     ŷ_k   │   卡尔曼    │ȳ_k  │   采样器    │ y_k │  被控对象   │                       ║
// ║           └────────────┤   滤波器    │◄────┤  N帧平均   │◄────┤ Flash渲染  │                       ║
// ║                        │             │     │             │     │             │                       ║
// ║                        └─────────────┘     └─────────────┘     └─────────────┘                       ║
// ║                                                   ▲                   │                               ║
// ║                                                   │    d_k (扰动)     │                               ║
// ║                                                   └───────────────────┘                               ║
// ║                                                     关卡负载/特效峰值                                   ║
// ║                                                                                                       ║
// ║  【信号定义 Signal Definitions】                                                                       ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║  • y_k     : 真实FPS（被控量/输出）                                                                    ║
// ║  • ȳ_k     : 区间平均FPS = N_k / Δt_k （N帧内的平均帧率）                                              ║
// ║  • ŷ_k     : 滤波后FPS = Kalman(ȳ_k) （状态估计值）                                                   ║
// ║  • r       : 目标FPS = 26 （设定值/参考输入）                                                          ║
// ║  • e_k     : 误差 = r - ŷ_k                                                                           ║
// ║  • u*_k    : PID连续输出 （期望性能等级，浮点数）                                                       ║
// ║  • u_k     : 量化输出 = QuantizeWithDwell(u*_k) （实际性能等级，0~3整数）                              ║
// ║  • d_k     : 扰动输入 （关卡负载：怪物数量、特效峰值、弹幕密度等）                                       ║
// ║                                                                                                       ║
// ║  【离散状态方程 Discrete State Equation】                                                              ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║  被控对象可近似为一阶滞后系统：                                                                         ║
// ║                                                                                                       ║
// ║      ŷ_{k+1} = a·ŷ_k + b·u_k + w_k                                                                   ║
// ║                                                                                                       ║
// ║  其中：                                                                                                ║
// ║  • a ∈ (0,1) : 系统惯性系数，来自「区间平均 + Kalman滤波」的滞后效应                                    ║
// ║  • b < 0     : 控制增益，u_k↑ 导致 FPS↑（负号因为性能等级越高=画质越低=FPS越高）                        ║
// ║  • w_k       : 过程噪声/扰动，来自关卡负载的随机变化                                                    ║
// ║                                                                                                       ║
// ║  【等效帧耗时模型 Equivalent Frame-Time Model】                                                        ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║  用帧耗时 C(ms) 建模比 FPS 更线性：                                                                    ║
// ║                                                                                                       ║
// ║      y (FPS) = min(30, 1000 / C(u,d))                                                                 ║
// ║      C = C₀(d) - ΔC(u)      // 降档使帧耗时减少                                                        ║
// ║                                                                                                       ║
// ║  在瓶颈区（C > 帧预算）线性化：                                                                         ║
// ║      Δy ≈ (y² / 1000) × ΔC(u)                                                                         ║
// ║                                                                                                       ║
// ║  【关键洞察】越接近30FPS（高画质区），单位降载带来的FPS提升越明显，越容易抖动。                           ║
// ║  这就是 targetFPS=26（而非29-30）的理论依据：留出死区避开高敏感区。                                      ║
// ║                                                                                                       ║
// ║  【系统稳定性核心机制 - 按贡献度排序】                                                                   ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║  ┌────┬────────────────────┬───────┬──────────────────────────────────────────────────────────────┐ ║
// ║  │排名│ 机制                │ 贡献度 │ 说明                                                         │ ║
// ║  ├────┼────────────────────┼───────┼──────────────────────────────────────────────────────────────┤ ║
// ║  │ 1  │ 迟滞确认           │ ★★★★★ │ 压制量化极限环，是防抖动的核心                                 │ ║
// ║  │ 2  │ 目标裕度           │ ★★★★  │ targetFPS=26 形成死区，避开高FPS敏感区                        │ ║
// ║  │ 3  │ 区间平均           │ ★★★★  │ N帧平均是强低通滤波，滤除瞬时噪声                             │ ║
// ║  │ 4  │ 单调执行器         │ ★★★   │ 降载动作覆盖广且单调，保证反馈有效性                          │ ║
// ║  │ 5  │ 自适应采样         │ ★★★   │ 采样周期匹配系统响应时间                                     │ ║
// ║  │ 6  │ 卡尔曼滤波         │ ★★    │ 自适应EMA，作用不如区间平均大                                │ ║
// ║  │ 7  │ PID控制器          │ ★★    │ 在强滤波+迟滞下，参数敏感度降低                              │ ║
// ║  └────┴────────────────────┴───────┴──────────────────────────────────────────────────────────────┘ ║
// ║                                                                                                       ║
// ║  【核心结论】                                                                                          ║
// ║  这不是一个「精调PID」的系统，而是一个「迟滞+死区+强滤波」主导的鲁棒系统。                               ║
// ║  PID的作用更像是一个「带偏置的阈值生成器」，而非经典的连续控制器。                                       ║
// ║                                                                                                       ║
// ║  【已知问题 Known Issues】                                                                             ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║  1. [单位不一致] PID.update() 期望 deltaTime 单位为秒，但实际传入的是帧数                               ║
// ║     → 意外效果：积分被放大30-120倍，微分被缩小30-120倍                                                 ║
// ║     → 这个「错误」实际增强了稳定性（积分强化消除稳态误差 + 微分弱化抗噪声）                              ║
// ║  2. [配置未接通] PIDControllerConfig.xml 中的 targetFrameRate 只trace未实际使用                        ║
// ║                                                                                                       ║
// ║  【重构状态 Refactoring Status】                                                                       ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║  [✓] PerformanceScheduler 类封装完成（IntervalSampler / AdaptiveKalmanStage /                          ║
// ║      HysteresisQuantizer / PerformanceActuator）                                                       ║
// ║  [✓] PerformanceLogger 可插拔日志模块，支持 CSV 导出与离线分析                                         ║
// ║  [ ] 考虑引入增益调度（Gain Scheduling）：不同性能等级使用不同PID参数                                    ║
// ║                                                                                                       ║
// ╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝

// 初始化全局帧计时器对象
_root.帧计时器 = {};

// 调用 ColliderFactoryRegistry 初始化
ColliderFactoryRegistry.init();

// ═══════════════════════════════════════════════════════════════════════════════════════
// 帧计时器初始化函数：初始化所有与帧、性能、任务调度有关的参数，并创建 TaskManager 实例
// ═══════════════════════════════════════════════════════════════════════════════════════
_root.帧计时器.初始化任务栈 = function():Void {

    // ┌─────────────────────────────────────────────────────────┐
    // │ 【模块1】基础时间参数                                      │
    // └─────────────────────────────────────────────────────────┘

    this.帧率 = 30;                      // 项目标称帧率 (Hz)
    this.毫秒每帧 = this.帧率 / 1000;    // 帧率/1000，用于乘法优化
    this.当前帧数 = 0;                   // 全局帧计数器
    this.异常间隔帧数 = this.帧率 * 5;   // 异常检测周期 = 5秒

    // ┌─────────────────────────────────────────────────────────┐
    // │ 【模块2】性能与天气参数                                    │
    // └─────────────────────────────────────────────────────────┘

    this.性能等级上限 = 0;               // 允许的最高画质档位（存档系统读写）
    this.更新天气间隔 = 5 * this.帧率;   // 天气系统更新周期
    this.天气待更新时间 = this.更新天气间隔;

    // ┌─────────────────────────────────────────────────────────┐
    // │ 【模块3】性能调度器                                        │
    // │ → 控制理论详见 PerformanceScheduler.as 及其子模块           │
    // └─────────────────────────────────────────────────────────┘

    var pid:PIDController = new PIDController(0.2, 0.5, -30, 3, 0.2);
    var pidFactory:PIDControllerFactory = PIDControllerFactory.getInstance();
    function onPIDSuccess(newPID:PIDController):Void {
        _root.帧计时器.scheduler.setPID(newPID);
    }
    function onPIDFailure():Void {
        _root.服务器.发布服务器消息("主程序：PIDControllerConfig.xml 加载失败");
    }
    pidFactory.createPIDController(onPIDSuccess, onPIDFailure);

    this.scheduler = new PerformanceScheduler(this, this.帧率, 26, _root._quality, {root:_root}, pid);

    // --------------------------
    // 可插拔日志模块（默认不启用，零开销）
    // --------------------------
    //
    // 【系统辨识数据采集计划】
    //
    // 目标：收集结构化日志，供 AI (GPT Pro / Claude) 进行被控对象辨识与 PID 调参。
    //
    // 被控对象模型：G(s) ≈ K / (τs+1) · e^(-Ls)
    //   K = 每档稳态 ΔFPS（当前假设=2，需实测）
    //   τ = 时间常数（切档到 FPS 稳定的延迟，估计 2-5 秒）
    //   L = 纯延迟（切档到 FPS 开始变化，估计 <1 秒）
    //
    // 第一轮：开环阶跃响应（最高优先级，~27分钟）
    //   用 setPerformanceLevel(level, 999, getTimer()) 锁定等级，禁止控制器干预。
    //   每个阶跃方向(0→1,1→2,2→3,3→2,2→1,1→0) × 3场景类型 × 3次重复 × 30秒
    //   采集前设置标签：scheduler.setLoggerTag("OL:0>1")
    //   用途：辨识 K, τ, L
    //
    // 第二轮：闭环自由运行（~24分钟）
    //   正常游玩，控制器自动运行。4场景类型 × 2次 × 3分钟。
    //   采集前设置标签：scheduler.setLoggerTag("CL:heavy")
    //   用途：验证模型预测，评估闭环性能
    //
    // 第三轮：稳态噪声采集（~12分钟）
    //   锁定每个 level，同一场景保持静止 60 秒。4 level × 3 场景。
    //   用途：校准 Kalman 测量噪声 R
    //
    // 第四轮：参数敏感性测试（可选）
    //   准备 2-3 组 PID 参数通过 XML 加载，同一高压场景对比。
    //
    // 日志 CSV Schema（见 PerformanceLogger.as）：
    //   EVT=1 SAMPLE:     a=level, b=actualFPS, c=denoisedFPS, d=pidOutput,  s=tag
    //   EVT=2 LEVEL_CHG:  a=oldLevel, b=newLevel, c=actualFPS,  d=0,         s=quality
    //   EVT=3 MANUAL_SET: a=level,    b=holdSec,  c=0,          d=0,         s=null
    //   EVT=4 SCENE_CHG:  a=level,    b=actualFPS,c=targetFPS,  d=0,         s=quality
    //   EVT=5 PID_DETAIL: a=pTerm,    b=iTerm,    c=dTerm,      d=pidOutput, s=null
    //
    // 给 AI 建模者的提示：
    //   PID deltaTime 单位为帧数(30-120)而非秒（已知的单位不一致，为既定行为）
    //   targetFPS=26（非30），预留 4FPS 死区裕度
    //   Kd=-30（负微分=预见性控制，非标准 PID）
    //
    // --------------------------
    this.performanceLogger = null;
    this.启用性能日志 = function(capacity:Number):Void {
        if (this.performanceLogger == null) {
            this.performanceLogger = new org.flashNight.neur.PerformanceOptimizer.PerformanceLogger(capacity);
        }
        this.performanceLogger.setEnabled(true);
        this.scheduler.setLogger(this.performanceLogger);
    };
    this.禁用性能日志 = function():Void {
        this.scheduler.setLogger(null);
        if (this.performanceLogger != null) {
            this.performanceLogger.setEnabled(false);
        }
    };
    this.导出性能日志CSV = function(maxRows:Number):String {
        return (this.performanceLogger != null) ? this.performanceLogger.toCSV(maxRows) : "";
    };
    /** 设置日志标签（标注当前场景/模式，写入后续 EVT_SAMPLE 的 s 列） */
    this.设置日志标签 = function(tag:String):Void {
        this.scheduler.setLoggerTag(tag);
    };
    
    // --------------------------
    // 初始化任务调度部分：创建 ScheduleTimer 和 TaskManager 实例
    // --------------------------
    this.ScheduleTimer = new CerberusScheduler();
    var singleWheelSize:Number = 150;        // 单层时间轮大小（帧）
    var multiLevelSecondsSize:Number = 60;   // 二级时间轮大小（秒）
    var multiLevelMinutesSize:Number = 60;   // 三级时间轮大小（分）
    // [DEPRECATED v1.6] precisionThreshold 已废弃，保留仅为 API 兼容
    var precisionThreshold:Number = 0.1;
    this.ScheduleTimer.initialize(singleWheelSize,
                                  multiLevelSecondsSize,
                                  multiLevelMinutesSize,
                                  this.帧率,
                                  precisionThreshold);
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

_root.帧计时器.性能评估优化 = function() {

    // 固化单路径：由 PerformanceScheduler 接管
    this.scheduler.evaluate();
};


_root.帧计时器.执行性能调整 = function(新性能等级)
{
    // 固化单路径：执行器由 scheduler 持有
    this.scheduler.getActuator().apply(新性能等级);
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
        
        this.天气待更新时间 = this.更新天气间隔 * (1 + this.scheduler.getPerformanceLevel());

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

// 【日志采集启用入口】
// 调试/数据采集时取消下行注释，capacity 建议 4096（≈68分钟数据）
// _root.帧计时器.启用性能日志(4096);
//
// 【场景标签设置示例】
// 开环阶跃测试时：
//   _root.帧计时器.设置日志标签("OL:0>1");
//   _root.帧计时器.scheduler.setPerformanceLevel(1, 999, getTimer());
// 闭环场景标注时：
//   _root.帧计时器.设置日志标签("CL:heavy");
// 清除标签：
//   _root.帧计时器.设置日志标签(null);
//
_root.帧计时器.eventBus.subscribe("SceneChanged", function() {
    // 固化单路径：由 PerformanceScheduler 统一处理性能侧重置
    // onSceneChanged 内部会先记录重置前快照到日志，再执行重置
    _root.帧计时器.scheduler.onSceneChanged();

    // 场景切换时导出日志（调试/数据采集时取消注释）
    // _root.帧计时器.performanceLogger.dump();

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

// ╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
// ║                              关卡性能动态调控接口 - 前馈/手动干预                                        ║
// ║                     Stage Performance Control Interface - Feedforward / Manual Override               ║
// ╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣
// ║                                                                                                       ║
// ║  【控制理论】前馈控制 (Feedforward Control)                                                            ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║                                                                                                       ║
// ║  自动调控（反馈控制）的局限性：                                                                         ║
// ║    反馈控制是「事后调整」：必须先检测到 FPS 下降，才能降低画质                                           ║
// ║    存在不可避免的响应延迟：测量延迟 + 滤波延迟 + 执行延迟 ≈ 3-8秒                                        ║
// ║                                                                                                       ║
// ║  前馈控制（手动干预）的优势：                                                                           ║
// ║    关卡设计师「已知」即将到来的负载高峰（如 BOSS 战、大波次刷怪）                                         ║
// ║    可以「提前」降低画质，避免 FPS 波动被玩家感知                                                        ║
// ║                                                                                                       ║
// ║  【系统架构】反馈 + 前馈 的混合控制                                                                     ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║                                                                                                       ║
// ║    ┌─────────────────────────────────────────────────────────────────────────────────────────────┐  ║
// ║    │                                                                                             │  ║
// ║    │     ┌───────────────┐                       ┌───────────────┐                              │  ║
// ║    │     │  关卡事件     │ 前馈信号              │   执行器      │                              │  ║
// ║    │     │ (SubStage等) ├──────────────────────►│  性能调整     │                              │  ║
// ║    │     └───────────────┘      u_ff             └───────┬───────┘                              │  ║
// ║    │                              ↑                       │                                      │  ║
// ║    │                              │                       ▼                                      │  ║
// ║    │     ┌───────────────┐        │              ┌───────────────┐                              │  ║
// ║    │     │  PID控制器    │ 反馈信号              │   被控对象    │                              │  ║
// ║    │     │  (自动调控)   ├────────┴──────────────│  Flash渲染   │                              │  ║
// ║    │     └───────┬───────┘      u_fb             └───────────────┘                              │  ║
// ║    │             ↑                                        │                                      │  ║
// ║    │             │                                        │ y (FPS)                              │  ║
// ║    │             └────────────────────────────────────────┘                                      │  ║
// ║    │                           反馈回路                                                           │  ║
// ║    └─────────────────────────────────────────────────────────────────────────────────────────────┘  ║
// ║                                                                                                       ║
// ║  【前馈干预的实现机制】                                                                                 ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║                                                                                                       ║
// ║  1. 直接设置性能等级（绕过 PID 输出）                                                                  ║
// ║  2. 重置 PID 状态（清除积分项，避免历史误差影响）                                                       ║
// ║  3. 延长采样间隔（给前馈设定「保护时间」，防止被反馈立即覆盖）                                           ║
// ║  4. 保护时间结束后，反馈控制自动接管                                                                    ║
// ║                                                                                                       ║
// ║  【使用原则】                                                                                          ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║                                                                                                       ║
// ║  • 宁可过度降载，不要欠降载：过度降载只是画质差一点，欠降载会导致明显卡顿                                ║
// ║  • 提前降载优于事后补救：在负载高峰「之前」调用，而不是「之后」                                          ║
// ║  • 保持时间要覆盖高峰期：保持秒数应 >= 预期负载高峰持续时间                                             ║
// ║                                                                                                       ║
// ╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝

/**
 * 手动设置性能等级（关卡事件调用）- 前馈控制入口
 * 强制设置到指定档位，在保护时间内 PID 不会覆盖此设定
 *
 * @param 目标等级 0=高画质 1=中画质 2=低画质 3=最低画质
 * @param 保持秒数 （可选）前馈设定的保护时间（秒），默认5秒
 *
 * 【控制理论注解】
 *   这是一个「前馈 + 保护窗口」的实现：
 *   1. 直接设置 u = 目标等级（前馈）
 *   2. 重置 PID 状态（清除积分项）
 *   3. 设置 measurementIntervalFrames = 保持秒数 × 帧率
 *      → 下一次反馈评估将在保护时间后才进行
 *   4. 保护时间结束后，反馈控制自动接管
 *
 * 使用场景：
 *   - SubStage 4 开始时强制设为2档（预期高负载）
 *   - SubWave 2 开始时强制设为3档（极限负载）
 *   - 战斗结束时恢复到1档（负载降低）
 *
 * 示例：
 *   _root.帧计时器.手动设置性能等级(2);     // 强制降至低画质，保护5秒
 *   _root.帧计时器.手动设置性能等级(3, 10); // 强制最低画质，保护10秒
 */
_root.帧计时器.手动设置性能等级 = function(目标等级:Number, 保持秒数:Number):Void {
    // 固化单路径：由 PerformanceScheduler 接管（保持API不变）
    this.scheduler.setPerformanceLevel(目标等级, 保持秒数);
};

/**
 * 降低性能等级（预防性降档）- 相对前馈
 * 在当前等级基础上下降N档，适合不确定当前档位时使用
 *
 * 【控制理论注解】
 *   这是「增量式前馈」：Δu = +下降档数
 *   相比绝对式前馈（手动设置性能等级），增量式更稳健：
 *   • 如果当前已经在低画质，不会错误地提升到高画质
 *   • 适合「我知道要降，但不确定降到哪」的场景
 *
 * @param 下降档数 下降的档位数量，默认1档
 * @param 保持秒数 （可选）保护时间（秒），默认5秒
 *
 * 使用场景：
 *   - SubStage 1/3 开始时预防性降1档
 *   - 中等压力波次的柔和调控
 *
 * 示例：
 *   _root.帧计时器.降低性能等级(1);      // 降1档，保护5秒
 *   _root.帧计时器.降低性能等级(2, 10);  // 降2档，保护10秒
 */
_root.帧计时器.降低性能等级 = function(下降档数:Number, 保持秒数:Number):Void {
    // 固化单路径：由 PerformanceScheduler 接管（保持API不变）
    this.scheduler.decreaseLevel(下降档数, 保持秒数);
};

/**
 * 提升性能等级（恢复性升档）- 相对前馈
 * 在当前等级基础上提升N档，用于战斗结束后恢复画质
 *
 * 【控制理论注解】
 *   这是「增量式前馈」：Δu = -提升档数
 *   注意：提升画质应谨慎，因为可能导致 FPS 下降
 *   建议保持时间设短一些，让反馈控制快速接管
 *
 * @param 提升档数 提升的档位数量，默认1档
 * @param 保持秒数 （可选）保护时间（秒），默认5秒
 *
 * 使用场景：
 *   - 战斗结束后恢复画质
 *   - 低压力场景提升体验
 *
 * 示例：
 *   _root.帧计时器.提升性能等级(1);     // 升1档，保护5秒
 *   _root.帧计时器.提升性能等级(2, 3);  // 升2档，保护3秒（快速让反馈接管）
 */
_root.帧计时器.提升性能等级 = function(提升档数:Number, 保持秒数:Number):Void {
    // 固化单路径：由 PerformanceScheduler 接管（保持API不变）
    this.scheduler.increaseLevel(提升档数, 保持秒数);
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
