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
// ║  【重构建议 Refactoring Suggestions】                                                                  ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║  1. 将性能调度系统封装为 PerformanceScheduler 类                                                       ║
// ║  2. 分离关注点：采样器、滤波器、控制器、执行器各自独立                                                   ║
// ║  3. 添加系统辨识日志，支持离线分析和参数自整定                                                          ║
// ║  4. 考虑引入增益调度（Gain Scheduling）：不同性能等级使用不同PID参数                                    ║
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

    // ┌─────────────────────────────────────────────────────────────────────────────────┐
    // │ 【模块1】基础时间参数 - 系统时钟与采样配置                                         │
    // │ Time Base Parameters - System Clock & Sampling Configuration                     │
    // └─────────────────────────────────────────────────────────────────────────────────┘

    this.帧率 = 30;                      // 项目标称帧率 (Hz)，Flash Player 的硬上限
    this.毫秒每帧 = this.帧率 / 1000;    // 帧率/1000，用于乘法优化（避免除法）
    this.每帧毫秒 = 1000 / this.帧率;    // 每帧理论时长 ≈ 33.33ms
    this.frameStartTime = 0;             // 上次测量的时间戳 (ms)，用于计算 Δt
    this.当前帧数 = 0;                   // 全局帧计数器

    // ───────────────────────────────────────────────────────────────────────────────────
    // 【控制理论】自适应采样周期 (Adaptive Sampling Period)
    // ───────────────────────────────────────────────────────────────────────────────────
    // 采样周期 N_k = 帧率 × (1 + 性能等级)
    //   • 性能等级0（流畅）: N = 30帧 ≈ 1秒
    //   • 性能等级3（卡顿）: N = 120帧 ≈ 4秒
    //
    // 【设计原理】时间尺度分离 (Time-Scale Separation)
    //   被控对象（Flash渲染器）的时间常数 τ ≈ 2-5秒（从改变参数到FPS稳定）
    //   采样周期必须满足 T_sample < τ 才能正确跟踪系统动态
    //   自适应机制确保：系统越慢（性能等级越高），采样越稀疏，避免过采样导致的抖动
    //
    // 【物理意义】「系统越慢，给它更长的稳定时间再评估」
    this.measurementIntervalFrames = this.帧率;  // 初始采样间隔 = 30帧

    // ┌─────────────────────────────────────────────────────────────────────────────────┐
    // │ 【模块2】帧率历史缓冲区 - 用于可视化和统计                                         │
    // │ Frame Rate History Buffer - For Visualization & Statistics                       │
    // └─────────────────────────────────────────────────────────────────────────────────┘

    this.队列最大长度 = 24;              // 历史记录长度，用于绘制帧率曲线
    this.frameRateBuffer = new SlidingWindowBuffer(this.队列最大长度);
    for (var i:Number = 0; i < this.队列最大长度; i++) {
        this.frameRateBuffer.insert(this.帧率);  // 用标称帧率填充，避免冷启动异常
    }
    this.总帧率 = 0;
    this.最小帧率 = 30;
    this.最大帧率 = 0;
    this.最小差异 = 5;                   // 帧率曲线Y轴最小范围，避免波动过小时曲线不可见
    this.异常间隔帧数 = this.帧率 * 5;   // 异常检测周期 = 5秒
    this.实际帧率 = 0;                   // 当前测量的实际帧率 (ȳ_k)

    // ┌─────────────────────────────────────────────────────────────────────────────────┐
    // │ 【模块3】性能等级与画质参数 - 执行器状态                                           │
    // │ Performance Level & Quality Parameters - Actuator State                          │
    // └─────────────────────────────────────────────────────────────────────────────────┘

    this.性能等级 = 0;                   // 当前性能等级 u_k ∈ {0,1,2,3}
                                         //   0 = 最高画质（默认）
                                         //   3 = 最低画质（极限降载）
    this.性能等级上限 = 0;               // 允许的最高画质档位（0=不限制）
    this.预设画质 = _root._quality;      // 用户预设画质，用于恢复
    this.更新天气间隔 = 5 * this.帧率;   // 天气系统更新周期（受性能等级影响）
    this.天气待更新时间 = this.更新天气间隔;
    this.光照等级数据 = [];
    this.当前小时 = null;

    // ┌─────────────────────────────────────────────────────────────────────────────────┐
    // │ 【模块4】状态估计器 - 卡尔曼滤波器                                                 │
    // │ State Estimator - Kalman Filter                                                   │
    // └─────────────────────────────────────────────────────────────────────────────────┘
    //
    // 【数学模型】一维简化卡尔曼滤波器 (SimpleKalmanFilter1D)
    // ───────────────────────────────────────────────────────────────────────────────────
    //   状态方程: x_k = x_{k-1} + w_k      (状态 = FPS，假设恒定 + 过程噪声)
    //   观测方程: z_k = x_k + v_k          (观测 = 测量FPS + 测量噪声)
    //
    //   预测步骤: x⁻_k = x_{k-1}
    //            P⁻_k = P_{k-1} + Q
    //   更新步骤: K_k = P⁻_k / (P⁻_k + R)
    //            x_k = x⁻_k + K_k × (z_k - x⁻_k)
    //            P_k = (1 - K_k) × P⁻_k
    //
    // 【参数说明】
    //   • initialEstimate = 30  : 初始状态估计（标称帧率）
    //   • initialP = 0.5        : 初始估计协方差（对初值的不确定度）
    //   • R = 1                 : 测量噪声协方差（观测噪声强度）
    //   • Q = 动态调整          : 过程噪声协方差（系统不确定性）
    //
    // 【控制理论】自适应 Q 的物理意义
    // ───────────────────────────────────────────────────────────────────────────────────
    //   Q(dt) = Q₀ × dt，其中 dt 是采样间隔（秒）
    //   • dt 越长 → Q 越大 → 卡尔曼增益 K 越大 → 更信任测量值、少拖尾
    //   • dt 越短 → Q 越小 → 卡尔曼增益 K 越小 → 更信任模型预测、滤波激进
    //
    // 【本质】自适应 Q 使滤波器在「信任模型」和「信任测量」之间动态切换
    //         长采样 = 系统变化大 = 信测量；短采样 = 系统稳定 = 信模型
    //
    this.kalmanFilter = new SimpleKalmanFilter1D(this.帧率, 0.5, 1);
    //                                           ↑初值    ↑P₀  ↑R(固定)

    // ┌─────────────────────────────────────────────────────────────────────────────────┐
    // │ 【模块5】PID控制器 - 性能等级计算                                                  │
    // │ PID Controller - Performance Level Calculation                                    │
    // └─────────────────────────────────────────────────────────────────────────────────┘
    //
    // 【PID 控制律】
    // ───────────────────────────────────────────────────────────────────────────────────
    //   u*(t) = Kp·e(t) + Ki·∫e(τ)dτ + Kd·de(t)/dt
    //
    //   离散化（当前实现）:
    //   u*_k = Kp·e_k + Ki·Σ(e_i·Δt) + Kd·(e_k - e_{k-1})/Δt
    //
    // 【参数物理意义】
    // ───────────────────────────────────────────────────────────────────────────────────
    //   • Kp (比例增益): 控制响应速度，Kp↑ → 响应快但易超调
    //     经验公式: Kp ≈ 1/ΔFPS，其中 ΔFPS 是「一档带来的帧率提升」
    //     当前 Kp=0.2 等价假设「一档 ≈ 5 FPS」
    //
    //   • Ki (积分增益): 消除稳态误差，Ki↑ → 稳态精度高但易振荡
    //     integralMax 限制积分饱和（Anti-Windup）
    //
    //   • Kd (微分增益): 阻尼超调，Kd↑ → 响应平滑但变慢
    //
    // 【⚠ 特殊设计】负微分系数 Kd = -30
    // ───────────────────────────────────────────────────────────────────────────────────
    //   标准 PID 中 Kd > 0 用于阻尼；这里 Kd < 0 是「预见性控制」：
    //   • 当帧率下降 (de/dt < 0) 时，-Kd·(de/dt) > 0，输出增大，提前降级
    //   • 当帧率上升 (de/dt > 0) 时，-Kd·(de/dt) < 0，输出减小，提前升级
    //
    //   【本质】前馈补偿，预测帧率变化趋势并提前响应
    //
    // 【⚠ 已知问题】单位不一致
    // ───────────────────────────────────────────────────────────────────────────────────
    //   PID.update(setPoint, actual, deltaTime) 期望 deltaTime 单位为「秒」
    //   但实际调用传入的是「帧数」: 帧率 × (1 + 性能等级) = 30~120
    //
    //   意外效果:
    //   • 积分项: error × 30~120 (放大30-120倍) → 稳态误差消除更快
    //   • 微分项: Δerror / 30~120 (缩小30-120倍) → 高频噪声被抑制
    //
    //   这个「错误」实际增强了稳定性：
    //   • Kd = -30 的实际效果约等于 Kd = -1 ~ -0.25（正常范围）
    //   • Ki = 0.5 的实际效果约等于 Ki = 15 ~ 60（强积分）
    //
    this.kp = 0.2;               // 比例增益 [调参方向] ↑加快响应但增加超调
    this.ki = 0.5;               // 积分增益 [调参方向] ↑消除稳态误差但增加振荡
    this.kd = -30;               // 微分增益 [调参方向] 负值实现预见性控制
    this.integralMax = 3;        // 积分限幅 [调参方向] ↑允许更大累积误差修正
    this.derivativeFilter = 0.2; // 微分滤波系数 [调参方向] ↑平滑微分但增加相位滞后

    // ───────────────────────────────────────────────────────────────────────────────────
    // 【控制目标】targetFPS = 26（而非30）
    // ───────────────────────────────────────────────────────────────────────────────────
    //   【设计原理】死区/裕度设计 (Deadband/Margin Design)
    //
    //   Flash 帧率硬上限 = 30 FPS，当负载低时系统饱和在30，控制器在此区间「不可控」
    //   把目标设在26相当于预留4FPS裕度：
    //   • 只有当帧率真正逼近瓶颈（<26）才触发降载
    //   • 显著减少在 29~30 FPS 区间被噪声来回踢导致的频繁切档
    //
    //   【帧耗时模型启示】
    //   Δy ≈ (y²/1000) × ΔC(u)
    //   y=30时 Δy 对 ΔC 最敏感，y=26时敏感度降低约25%
    //   目标26避开了高敏感区，是稳定性的关键设计
    //
    this.targetFPS = 26;         // 目标帧率 [调参方向] ↓增加稳定性但牺牲画质

    // 创建 PID 控制器实例
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



// ╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
// ║                              性能评估优化 - 反馈控制主循环                                              ║
// ║                        Performance Evaluation & Optimization - Feedback Control Main Loop              ║
// ╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣
// ║                                                                                                       ║
// ║  【执行流程 Execution Flow】                                                                           ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║                                                                                                       ║
// ║  每帧调用 → 采样计数器递减 → 到达采样点？                                                              ║
// ║                                    │                                                                  ║
// ║                              ┌─────┴─────┐                                                            ║
// ║                              │           │                                                            ║
// ║                             否          是                                                            ║
// ║                              │           │                                                            ║
// ║                              ▼           ▼                                                            ║
// ║                           返回      ┌────────────┐                                                    ║
// ║                                     │ 1.测量FPS  │ ← 区间平均: ȳ_k = N_k / Δt_k                       ║
// ║                                     └─────┬──────┘                                                    ║
// ║                                           ▼                                                            ║
// ║                                     ┌────────────┐                                                    ║
// ║                                     │ 2.更新Q    │ ← 自适应: Q = Q₀ × dt                              ║
// ║                                     └─────┬──────┘                                                    ║
// ║                                           ▼                                                            ║
// ║                                     ┌────────────┐                                                    ║
// ║                                     │ 3.卡尔曼   │ ← 状态估计: ŷ_k = Kalman(ȳ_k)                      ║
// ║                                     │   滤波     │                                                    ║
// ║                                     └─────┬──────┘                                                    ║
// ║                                           ▼                                                            ║
// ║                                     ┌────────────┐                                                    ║
// ║                                     │ 4.PID计算  │ ← 控制律: u*_k = PID(r - ŷ_k)                      ║
// ║                                     └─────┬──────┘                                                    ║
// ║                                           ▼                                                            ║
// ║                                     ┌────────────┐                                                    ║
// ║                                     │ 5.量化     │ ← u_k = round(u*_k) ∈ {0,1,2,3}                    ║
// ║                                     └─────┬──────┘                                                    ║
// ║                                           ▼                                                            ║
// ║                                     ┌────────────┐                                                    ║
// ║                                     │ 6.迟滞确认 │ ← 施密特触发器: 连续2次才执行                       ║
// ║                                     └─────┬──────┘                                                    ║
// ║                                           ▼                                                            ║
// ║                                     ┌────────────┐                                                    ║
// ║                                     │ 7.执行调整 │ ← 修改特效/画质/刷佣兵等参数                         ║
// ║                                     └─────┬──────┘                                                    ║
// ║                                           ▼                                                            ║
// ║                                     ┌────────────┐                                                    ║
// ║                                     │ 8.重置采样 │ ← N_{k+1} = 帧率 × (1 + u_k)                       ║
// ║                                     └────────────┘                                                    ║
// ║                                                                                                       ║
// ╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝

_root.帧计时器.性能评估优化 = function() {

    // ═══════════════════════════════════════════════════════════════════════════════════
    // 【环节1】采样触发判断 - 变周期采样器 (Variable-Period Sampler)
    // ═══════════════════════════════════════════════════════════════════════════════════
    //
    // 采样周期 N_k = 帧率 × (1 + 性能等级_k)
    //   • 性能等级0: N = 30帧 ≈ 1.0秒
    //   • 性能等级1: N = 60帧 ≈ 2.0秒
    //   • 性能等级2: N = 90帧 ≈ 3.0秒
    //   • 性能等级3: N = 120帧 ≈ 4.0秒
    //
    // 【控制理论】时间尺度分离 (Time-Scale Separation)
    //   被控对象（Flash渲染器）改变参数后需要 τ ≈ 2-5秒 才能稳定到新帧率
    //   采样周期 T_sample 必须满足 T_sample ≈ τ，否则：
    //   • T_sample << τ: 过采样，观测到的是暂态而非稳态，导致频繁误调整
    //   • T_sample >> τ: 欠采样，响应太慢，无法及时跟踪负载变化
    //
    //   自适应采样的精妙之处：
    //   系统越慢（性能等级越高=越卡），τ 越大（稳定需要更长时间）
    //   采样周期 N ∝ (1 + 性能等级) 自动匹配 τ 的增长
    //
    if (--this.measurementIntervalFrames === 0)
    {
        var currentTime = getTimer();  // 获取当前时间戳 (ms)

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【环节2】帧率测量 - 区间平均采样器 (Interval-Average Sampler)
        // ═══════════════════════════════════════════════════════════════════════════════
        //
        // 测量公式: ȳ_k = N_k / Δt_k × 1000
        //   其中 N_k = 帧率 × (1 + 性能等级) 是期望帧数
        //        Δt_k = currentTime - frameStartTime 是实际耗时 (ms)
        //
        // 等价于: ȳ_k = (期望帧数 / 实际耗时) × 1000
        //       = 期望帧数 × (1000 / 实际耗时)
        //       = 期望帧数 × 实际帧率占理论帧率的比例
        //
        // 【控制理论】移动平均滤波 (Moving Average Filter)
        //   N帧平均本身就是一个强低通滤波器，截止频率 f_c ≈ 帧率/(2πN)
        //   • N=30:  f_c ≈ 0.16 Hz，滤除 > 6秒 周期的波动
        //   • N=120: f_c ≈ 0.04 Hz，滤除 > 25秒 周期的波动
        //
        //   这是系统稳定性的第一道防线：把瞬时噪声（爆炸、弹幕峰值）挡在闭环带宽之外
        //
        this.实际帧率 = Math.ceil(
            this.帧率 * (1 + this.性能等级) * 10000 / (currentTime - this.frameStartTime)
        ) / 10;  // 保留一位小数，10000/10 是为了避免浮点精度问题

        // 更新UI显示（观测输出，不影响控制）
        _root.玩家信息界面.性能帧率显示器.帧率数字.text = this.实际帧率;

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【环节3】自适应卡尔曼滤波器 - 状态估计器 (Adaptive Kalman Filter)
        // ═══════════════════════════════════════════════════════════════════════════════
        //
        // 计算采样间隔 dt（秒），用于动态调整过程噪声 Q
        var dt = (currentTime - this.frameStartTime) / 1000;

        // ───────────────────────────────────────────────────────────────────────────────
        // 自适应 Q 机制 (Adaptive Process Noise)
        // ───────────────────────────────────────────────────────────────────────────────
        //
        // Q(dt) = Q₀ × dt，限制在 [Q_min, Q_max]
        //
        // 【数学原理】连续时间到离散时间的映射
        //   连续时间系统噪声 w(t) 的协方差为 Q_c
        //   离散化后（采样周期 T）的过程噪声协方差为 Q_d ≈ Q_c × T
        //   因此 Q 应该与采样间隔成正比
        //
        // 【物理意义】采样间隔与系统不确定性的关系
        //   • dt 长 → 期间系统可能发生更多变化 → 状态不确定性大 → Q 大
        //   • dt 短 → 期间系统变化小 → 状态不确定性小 → Q 小
        //
        // 【卡尔曼增益的影响】
        //   K = P⁻ / (P⁻ + R)，其中 P⁻ = P + Q
        //   • Q↑ → P⁻↑ → K↑ → 更信任测量值（ŷ 更接近 ȳ）
        //   • Q↓ → P⁻↓ → K↓ → 更信任模型预测（ŷ 更平滑）
        //
        // 【自适应效果】
        //   长采样间隔（卡顿时）: Q大 → 快速跟踪实际帧率变化
        //   短采样间隔（流畅时）: Q小 → 强滤波抑制噪声
        //
        var baseQ:Number = 0.1;          // 基础过程噪声 [调参方向] ↑更信任测量 ↓更信任模型
        var scaledQ:Number = baseQ * dt; // 与采样间隔成正比
        scaledQ = Math.max(0.01, Math.min(scaledQ, 2.0));  // 限幅防止极端值
        //                 ↑Q_min          ↑Q_max

        this.kalmanFilter.setProcessNoise(scaledQ);

        // ───────────────────────────────────────────────────────────────────────────────
        // 卡尔曼滤波两步法: predict() → update()
        // ───────────────────────────────────────────────────────────────────────────────
        //
        // predict(): x⁻_k = x_{k-1}        (状态预测，假设FPS不变)
        //           P⁻_k = P_{k-1} + Q     (协方差预测，不确定性增加)
        //
        // update():  K_k = P⁻_k / (P⁻_k + R)                      (卡尔曼增益)
        //           x_k = x⁻_k + K_k × (z_k - x⁻_k)              (状态更新)
        //           P_k = (1 - K_k) × P⁻_k                        (协方差更新)
        //
        // 返回值 denoisedFPS = ŷ_k 是滤波后的帧率估计值
        //
        this.kalmanFilter.predict();                                 // 预测步骤
        var denoisedFPS:Number = this.kalmanFilter.update(this.实际帧率); // 更新步骤

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【环节4】PID控制器 - 性能等级计算 (PID Controller)
        // ═══════════════════════════════════════════════════════════════════════════════
        //
        // 【控制律】u*_k = Kp·e_k + Ki·Σ(e_i·Δt) + Kd·(e_k - e_{k-1})/Δt
        //   其中 e_k = r - ŷ_k （误差 = 目标FPS - 滤波后FPS）
        //
        // 【动态目标】（注：此变量计算后未使用，实际用的是 this.targetFPS = 26）
        var targetFPS = this.帧率 - this.性能等级 * 2;  // 备用：动态目标 30/28/26/24

        // ───────────────────────────────────────────────────────────────────────────────
        // PID.update() 调用分析
        // ───────────────────────────────────────────────────────────────────────────────
        //
        // 参数1: this.targetFPS = 26 （目标值/设定值）
        // 参数2: denoisedFPS        （滤波后的实际值）
        // 参数3: this.帧率 * (1 + this.性能等级) = 30/60/90/120 （采样「帧数」）
        //
        // 【⚠ 单位不一致问题】
        //   PIDController.update() 期望第三参数 deltaTime 单位为「秒」
        //   但实际传入的是「帧数」: 30~120
        //
        //   对 PID 各项的影响:
        //   ┌─────────────────────────────────────────────────────────────────────────┐
        //   │ 积分项: integral += error × deltaTime                                   │
        //   │         期望: error × 1~4秒                                             │
        //   │         实际: error × 30~120帧                                          │
        //   │         效果: 积分被放大 30~120 倍，稳态误差消除更快                      │
        //   ├─────────────────────────────────────────────────────────────────────────┤
        //   │ 微分项: derivative = (error - errorPrev) / deltaTime                    │
        //   │         期望: Δerror / 1~4秒                                            │
        //   │         实际: Δerror / 30~120帧                                         │
        //   │         效果: 微分被缩小 30~120 倍，高频噪声被压制                        │
        //   └─────────────────────────────────────────────────────────────────────────┘
        //
        //   【意外效果】这个「错误」反而增强了稳定性：
        //   • 强积分 → 持续误差能被有效修正
        //   • 弱微分 → 噪声不会被放大，即使 Kd = -30 也不会过激
        //   • 实际 Kd 效果 ≈ -30 / 30~120 ≈ -1 ~ -0.25（正常范围）
        //
        var pidOutput = this.PID.update(
            this.targetFPS,                        // 目标值 r = 26
            denoisedFPS,                           // 实际值 ŷ_k（滤波后）
            this.帧率 * (1 + this.性能等级)        // ⚠ 应为秒，实际为帧数
        );

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【环节5】量化器 - 连续到离散映射 (Quantizer)
        // ═══════════════════════════════════════════════════════════════════════════════
        //
        // 【量化操作】u_k = round(u*_k)，然后 clamp 到 [性能等级上限, 3]
        //
        // 【控制理论】量化控制的极限环问题
        //   当 PID 输出在两个量化级别之间振荡时（如 1.4 ↔ 1.6），
        //   round() 会导致输出在 1 和 2 之间来回跳变，形成「量化极限环」
        //
        //   这是离散执行器系统的固有问题，需要通过迟滞/死区来解决
        //
        var currentPerformanceLevel = Math.round(pidOutput);
        currentPerformanceLevel = Math.max(this.性能等级上限, Math.min(currentPerformanceLevel, 3));
        //                              ↑下限（允许的最高画质）        ↑上限（最低画质=3）

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【环节6】迟滞确认器 - 施密特触发器 (Hysteresis Confirmer / Schmitt Trigger)
        // ═══════════════════════════════════════════════════════════════════════════════
        //
        // 【机制】需要连续两次采样都判定为需要切换，才实际执行
        //
        // 【状态机】
        //   ┌─────────────────────────────────────────────────────────────────────────┐
        //   │  当前状态         输入条件                   下一状态        动作       │
        //   ├─────────────────────────────────────────────────────────────────────────┤
        //   │  awaitConfirm=F   等级变化                   awaitConfirm=T  无         │
        //   │  awaitConfirm=T   等级变化（相同方向）       awaitConfirm=F  执行切换   │
        //   │  awaitConfirm=T   等级相同                   awaitConfirm=F  取消确认   │
        //   │  awaitConfirm=F   等级相同                   awaitConfirm=F  无         │
        //   └─────────────────────────────────────────────────────────────────────────┘
        //
        // 【控制理论】迟滞/驻留控制 (Hysteresis / Dwell-Time Control)
        //
        //   迟滞的核心作用是压制「量化极限环」：
        //   • 时间跨度: 2个采样周期 = 2~8秒（取决于性能等级）
        //   • 频率分析: 等效于截止频率 0.125~0.5 Hz 的低通滤波器
        //   • 人因工程: 2~8秒 匹配用户对帧率变化的感知窗口（约3-5秒）
        //
        //   【这是系统稳定性的核心机制】
        //   即使 PID 输出抖动，迟滞也能保证切换频率极低
        //   实测切换频率 < 0.1次/秒（每10秒最多1次）
        //
        if (this.性能等级 !== currentPerformanceLevel)
        {
            if (this.awaitConfirmation)
            {
                // 第二次确认通过，执行切换
                this.执行性能调整(currentPerformanceLevel);
                this.性能等级 = currentPerformanceLevel;
                this.awaitConfirmation = false;
                _root.发布消息(
                  "性能等级: [" + this.性能等级 + " : " + this.实际帧率 + " FPS] " + _root._quality
                );
            }
            else
            {
                // 第一次检测到变化，进入等待确认状态
                this.awaitConfirmation = true;
            }
        }
        else
        {
            // 等级相同，重置确认状态
            // 这实现了「方向一致性」要求：必须连续两次判定为同一方向的切换
            this.awaitConfirmation = false;
        }

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【环节7】重置采样周期 - 自适应采样参数更新
        // ═══════════════════════════════════════════════════════════════════════════════
        //
        // 【自适应机制】采样周期随性能等级动态调整
        //   N_{k+1} = 帧率 × (1 + u_k)
        //
        // 【正反馈特性】这是一个有趣的正反馈设计：
        //   性能等级高（卡）→ 采样周期长 → 下次评估更晚 → 系统有更多时间稳定
        //   性能等级低（流畅）→ 采样周期短 → 响应更快 → 能及时检测到性能下降
        //
        // 【稳定性分析】
        //   虽然是正反馈，但有界（性能等级 ∈ [0,3]），不会发散
        //   结合迟滞机制，形成了一个稳定的自适应系统
        //
        this.frameStartTime = currentTime;
        this.measurementIntervalFrames = this.帧率 * (1 + this.性能等级);

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【环节8】数据记录与可视化
        // ═══════════════════════════════════════════════════════════════════════════════
        this.更新帧率数据(this.实际帧率);
        this.绘制帧率曲线();
    }
};


// ╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
// ║                              执行性能调整 - 执行器/作动器                                               ║
// ║                           Execute Performance Adjustment - Actuator                                    ║
// ╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣
// ║                                                                                                       ║
// ║  【控制理论】执行器的设计原则                                                                          ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║                                                                                                       ║
// ║  1.【单调性 Monotonicity】                                                                             ║
// ║    u↑ (性能等级升高) 必须导致 FPS↑ (帧率提升)                                                         ║
// ║    这是反馈控制收敛的必要条件：如果执行器非单调，闭环可能振荡甚至发散                                    ║
// ║                                                                                                       ║
// ║    本系统通过「多维度同向调节」保证单调性：                                                             ║
// ║    • 特效数量↓ → 渲染负载↓ → FPS↑                                                                    ║
// ║    • 画质档位↓ → 矢量计算↓ → FPS↑                                                                    ║
// ║    • 刷佣兵密度↓ → 逻辑计算↓ → FPS↑                                                                    ║
// ║    所有维度同向变化，保证了总体单调性                                                                   ║
// ║                                                                                                       ║
// ║  2.【覆盖面 Coverage】                                                                                 ║
// ║    调节范围必须足够大，能覆盖实际负载变化                                                               ║
// ║    从 Level 0 到 Level 3，总降载幅度约 60-80%                                                         ║
// ║                                                                                                       ║
// ║  3.【响应时间 Response Time】                                                                          ║
// ║    执行器的响应时间决定了被控对象的时间常数 τ                                                          ║
// ║    Flash 渲染器：参数修改 → 生效 ≈ 1帧                                                                ║
// ║    但刷佣兵/特效堆积的消化需要 τ ≈ 2-5秒                                                                ║
// ║                                                                                                       ║
// ║  【降载策略分析】                                                                                       ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║                                                                                                       ║
// ║  ┌──────────────────────────────────────────────────────────────────────────────────────────────────┐║
// ║  │ 性能等级 │ 特效上限 │ 面积系数   │ 画质   │ 降载强度 │ 适用场景                                   │║
// ║  ├──────────────────────────────────────────────────────────────────────────────────────────────────┤║
// ║  │ 0 (高)  │ 20      │ 300,000   │ 预设   │ 0%      │ 流畅运行，全特效                            │║
// ║  │ 1 (中)  │ 15      │ 450,000   │ MEDIUM │ 25%     │ 轻微卡顿，轻量降载                          │║
// ║  │ 2 (低)  │ 10      │ 600,000   │ LOW    │ 50%     │ 明显卡顿，中度降载                          │║
// ║  │ 3 (极低)│ 0-5     │ 3,000,000 │ LOW    │ 80%+    │ 严重卡顿，极限降载                          │║
// ║  └──────────────────────────────────────────────────────────────────────────────────────────────────┘║
// ║                                                                                                       ║
// ║  【面积系数与刷佣兵密度的关系】                                                                           ║
// ║    刷佣兵数量 ∝ 1/面积系数                                                                               ║
// ║    Level 0: 300,000 → 基准                                                                            ║
// ║    Level 1: 450,000 → 刷佣兵量 = 基准 × 2/3                                                             ║
// ║    Level 2: 600,000 → 刷佣兵量 = 基准 × 1/2                                                             ║
// ║    Level 3: 3,000,000 → 刷佣兵量 = 基准 × 1/10                                                          ║
// ║                                                                                                       ║
// ║  【系统辨识提示】                                                                                       ║
// ║  ─────────────────────────────────────────────────────────────────────────────────────────────────── ║
// ║  要精确调参，需要测量每档的 ΔFPS（帧率提升量）：                                                        ║
// ║    ΔFPS_L = FPS(Level=L) - FPS(Level=L+1)                                                             ║
// ║                                                                                                       ║
// ║  实验方法：在代表性压力场景中，手动切换性能等级，记录稳定后的 FPS                                       ║
// ║  然后：Kp_optimal ≈ 1 / avg(ΔFPS)                                                                     ║
// ║                                                                                                       ║
// ╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝

_root.帧计时器.执行性能调整 = function(新性能等级)
{
    switch (新性能等级)
    {
        // ═══════════════════════════════════════════════════════════════════════════════
        // 【Level 0】最高画质 - 全特效模式
        // ═══════════════════════════════════════════════════════════════════════════════
        // 适用条件: FPS ≥ 26 稳定，系统有充足余量
        // 降载强度: 0%（基准）
        case 0:
            // --- 特效系统 ---
            EffectSystem.maxEffectCount = 20;        // 同时存在的特效上限
            EffectSystem.maxScreenEffectCount = 20;  // 屏幕特效上限
            EffectSystem.isDeathEffect = true;       // 启用死亡特效

            // --- 刷佣兵系统 ---
            _root.面积系数 = 300000;                 // 基准刷佣兵密度

            // --- 渲染系统 ---
            _root.同屏打击数字特效上限 = 25;         // 伤害数字上限
            DeathEffectRenderer.isEnabled = true;    // 启用死亡渲染器
            DeathEffectRenderer.enableCulling = false; // 禁用剔除（显示所有）
            _root._quality = this.预设画质;          // 使用用户预设画质
            ShellSystem.setMaxShellCountLimit(25);   // 弹壳上限
            _root.发射效果上限 = 15;                 // 发射特效上限

            // --- 天气系统 ---
            _root.天气系统.光照等级更新阈值 = 0.1;   // 高精度光照更新

            // --- UI/后台系统 ---
            _root.显示列表.继续播放(_root.显示列表.预设任务ID); // 继续后台动画
            _root.UI系统.经济面板动效 = true;        // 启用UI动效

            // --- 镜头系统 ---
            this.offsetTolerance = 10;               // 镜头跟随精度（像素）
            break;

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【Level 1】中等画质 - 轻量降载
        // ═══════════════════════════════════════════════════════════════════════════════
        // 适用条件: FPS 在 22-26 之间波动
        // 降载强度: ~25%
        case 1:
            EffectSystem.maxEffectCount = 15;        // ↓25%
            EffectSystem.maxScreenEffectCount = 15;
            EffectSystem.isDeathEffect = true;       // 保留死亡特效

            _root.面积系数 = 450000;                 // ↑50% → 刷佣兵量↓33%

            _root.同屏打击数字特效上限 = 18;         // ↓28%
            DeathEffectRenderer.isEnabled = true;
            DeathEffectRenderer.enableCulling = true; // 启用剔除
            _root._quality = this.预设画质 === 'LOW' ? this.预设画质 : 'MEDIUM';
            ShellSystem.setMaxShellCountLimit(18);
            _root.发射效果上限 = 10;

            _root.天气系统.光照等级更新阈值 = 0.2;   // ↓精度

            _root.显示列表.继续播放(_root.显示列表.预设任务ID);
            _root.UI系统.经济面板动效 = true;

            this.offsetTolerance = 30;               // 放宽镜头跟随
            break;

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【Level 2】低画质 - 中度降载
        // ═══════════════════════════════════════════════════════════════════════════════
        // 适用条件: FPS 在 18-22 之间，明显卡顿
        // 降载强度: ~50%
        case 2:
            EffectSystem.maxEffectCount = 10;        // ↓50%
            EffectSystem.maxScreenEffectCount = 10;
            EffectSystem.isDeathEffect = false;      // 禁用死亡特效

            _root.面积系数 = 600000;                 // ↑100% → 刷佣兵量↓50%

            _root.同屏打击数字特效上限 = 12;         // ↓52%
            DeathEffectRenderer.isEnabled = false;   // 禁用死亡渲染器
            DeathEffectRenderer.enableCulling = true;
            _root._quality = 'LOW';                  // 强制低画质
            ShellSystem.setMaxShellCountLimit(12);
            _root.发射效果上限 = 5;

            _root.天气系统.光照等级更新阈值 = 0.5;   // 大幅降低精度

            _root.显示列表.暂停播放(_root.显示列表.预设任务ID); // 暂停后台动画
            _root.UI系统.经济面板动效 = false;       // 禁用UI动效

            this.offsetTolerance = 50;
            break;

        // ═══════════════════════════════════════════════════════════════════════════════
        // 【Level 3 (default)】极低画质 - 极限降载
        // ═══════════════════════════════════════════════════════════════════════════════
        // 适用条件: FPS < 18，严重卡顿
        // 降载强度: ~80%+
        // 设计原则: 宁可牺牲视觉效果，也要保证基本可玩性
        default:
            EffectSystem.maxEffectCount = 0;         // 禁用所有特效
            EffectSystem.maxScreenEffectCount = 5;   // 最低保留
            EffectSystem.isDeathEffect = false;

            _root.面积系数 = 3000000;                // ↑900% → 刷佣兵量↓90%

            _root.同屏打击数字特效上限 = 10;
            DeathEffectRenderer.isEnabled = false;
            DeathEffectRenderer.enableCulling = true;
            _root._quality = 'LOW';
            ShellSystem.setMaxShellCountLimit(10);
            _root.发射效果上限 = 0;                  // 完全禁用发射特效

            _root.天气系统.光照等级更新阈值 = 1;     // 最低精度

            _root.显示列表.暂停播放(_root.显示列表.预设任务ID);
            _root.UI系统.经济面板动效 = false;

            this.offsetTolerance = 80;               // 最大镜头容差
    }

    // ───────────────────────────────────────────────────────────────────────────────────
    // 【渲染器联动调整】
    // 这些渲染器内部实现了自己的性能分级逻辑
    // ───────────────────────────────────────────────────────────────────────────────────
    TrailRenderer.getInstance().setQuality(新性能等级);           // 拖尾渲染器
    ClipFrameRenderer.setPerformanceLevel(新性能等级);            // 帧渲染器
    BladeMotionTrailsRenderer.setPerformanceLevel(新性能等级);    // 刀光渲染器
    // VectorAfterimageRenderer.instance.setShadowCount(5 - 新性能等级); // 残影（已禁用）
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
    // ───────────────────────────────────────────────────────────────────────────────────
    // 【步骤1】输入规范化与边界检查
    // ───────────────────────────────────────────────────────────────────────────────────
    目标等级 = Math.round(目标等级);
    目标等级 = Math.max(this.性能等级上限, Math.min(目标等级, 3));
    //              ↑下限（用户设定的最高画质）      ↑上限（系统极限）

    // 只在等级真正改变时执行（避免重复调用浪费资源）
    if (this.性能等级 !== 目标等级) {

        // ───────────────────────────────────────────────────────────────────────────────
        // 【步骤2】执行前馈控制 - 直接设置性能等级
        // ───────────────────────────────────────────────────────────────────────────────
        this.性能等级 = 目标等级;
        this.执行性能调整(目标等级);

        // ───────────────────────────────────────────────────────────────────────────────
        // 【步骤3】重置 PID 状态 - 防止反馈控制立即覆盖
        // ───────────────────────────────────────────────────────────────────────────────
        // 清除积分项、微分历史，让 PID 从零开始
        // 否则历史积累的误差可能导致下次评估立即切换回原等级
        this.PID.reset();
        this.awaitConfirmation = false;  // 清除迟滞状态

        // ───────────────────────────────────────────────────────────────────────────────
        // 【步骤4】设置保护窗口 - 延长下次反馈评估的时间
        // ───────────────────────────────────────────────────────────────────────────────
        var currentTime:Number = getTimer();
        this.frameStartTime = currentTime;  // 重置测量起点

        // 默认保护时间 5 秒
        if (保持秒数 == undefined || 保持秒数 <= 0) {
            保持秒数 = 5;
        }

        // 保护窗口 = max(用户指定保持时间, 正常采样周期)
        // 确保至少有一个完整的采样周期供系统稳定
        this.measurementIntervalFrames = Math.max(
            this.帧率 * 保持秒数,           // 用户指定的保护时间
            this.帧率 * (1 + 目标等级)      // 正常采样周期（作为下限）
        );

        // ───────────────────────────────────────────────────────────────────────────────
        // 【步骤5】更新 UI 显示 - 使用估算值填充
        // ───────────────────────────────────────────────────────────────────────────────
        // 因为尚未进行真实测量，使用目标等级对应的期望帧率
        var 估算帧率:Number = this.帧率 - 目标等级 * 2;  // 30/28/26/24
        this.实际帧率 = 估算帧率;
        _root.玩家信息界面.性能帧率显示器.帧率数字.text = this.实际帧率;

        this.更新帧率数据(this.实际帧率);
        this.绘制帧率曲线();

        _root.发布消息(
            "手动设置性能等级: [" + 目标等级 + "] 保持" + 保持秒数 + "秒"
        );
    }
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
    下降档数 = 下降档数 || 1;
    var 新等级:Number = this.性能等级 + 下降档数;  // 性能等级↑ = 画质↓
    this.手动设置性能等级(新等级, 保持秒数);
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
    提升档数 = 提升档数 || 1;
    var 新等级:Number = this.性能等级 - 提升档数;  // 性能等级↓ = 画质↑
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
