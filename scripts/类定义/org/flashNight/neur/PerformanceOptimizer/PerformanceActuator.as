import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.corpse.DeathEffectRenderer;
import org.flashNight.arki.bullet.BulletComponent.Shell.ShellSystem;
import org.flashNight.arki.render.TrailRenderer;
import org.flashNight.arki.render.ClipFrameRenderer;
import org.flashNight.arki.render.BladeMotionTrailsRenderer;

/**
 * PerformanceActuator - 性能执行器/作动器
 *
 * 【控制理论】执行器的设计原则
 * ───────────────────────────────────────────────────────────
 *   这是闭环系统中的"执行器/作动器"，将离散控制量 u ∈ {0,1,2,3}
 *   映射为具体的降载动作（特效/画质/刷怪密度/后台任务等）。
 *
 * 1.【单调性 Monotonicity】
 *   u↑ (性能等级升高) 必须导致 FPS↑ (帧率提升)
 *   这是反馈控制收敛的必要条件：如果执行器非单调，闭环可能振荡甚至发散
 *   本系统通过「多维度同向调节」保证单调性：
 *     • 特效数量↓ → 渲染负载↓ → FPS↑
 *     • 画质档位↓ → 矢量计算↓ → FPS↑
 *     • 刷佣兵密度↓ → 逻辑计算↓ → FPS↑
 *   所有维度同向变化，保证了总体单调性。
 *
 * 2.【覆盖面 Coverage】
 *   调节范围必须足够大，能覆盖实际负载变化。
 *   从 Level 0 到 Level 3，总降载幅度约 60-80%。
 *
 * 3.【响应时间 Response Time】
 *   执行器的响应时间决定了被控对象的时间常数 τ。
 *   Flash 渲染器参数修改 → 生效 ≈ 1帧，但刷佣兵/特效堆积的消化需要 τ ≈ 2-5秒。
 *
 * 【挡位设计理念 Tier Design Philosophy】
 * ───────────────────────────────────────────────────────────
 *   L0（理想挡位）：展示最好的画质。玩家在非高压场景下应稳定于此。
 *   L1（缓冲挡位）：小性能波动时的过渡缓冲。正常刷怪战斗压力下保持视觉体验，微降负载参数。
 *   L2（高压挡位）：演出需求下大规模团战的默认运行状态。核心降载手段生效。
 *   L3（兜底挡位）：理论上不应出现，仅作为关卡配置失衡极端情况的安全网。
 *
 * 【实测关键发现 — _quality=LOW 是主要降载手段】
 * ───────────────────────────────────────────────────────────
 *   堕落城保卫战实测数据：
 *     L0→L1 平均 ΔFPS ≈ +1.7（效果不显著）
 *     L1→L2 平均 ΔFPS ≈ +6.1（效果是 L0→L1 的 3.5 倍）
 *     极端样本: L1 时 18.0 FPS → L2 切换后 30.3 FPS（+12.3）
 *   结论：L1 的特效数量、弹壳限制等参数调整对帧率影响有限；
 *   L2 引入的 _quality='LOW' 才是真正拉开性能差距的主要手段。
 *   L1 的价值更多在于「保护画质的缓冲区」而非「显著提升帧率」。
 *
 * 【降载策略参数表】
 * ┌──────────┬─────────┬───────────┬────────┬──────────┐
 * │ 性能等级 │ 特效上限 │ 面积系数   │ 画质   │ 降载强度 │
 * ├──────────┼─────────┼───────────┼────────┼──────────┤
 * │ 0 (高)  │ 20      │ 300,000   │ 预设   │ 0%       │
 * │ 1 (中)  │ 12      │ 450,000   │ MEDIUM │ ~15%     │
 * │ 2 (低)  │ 10      │ 600,000   │ LOW    │ ~50%     │
 * │ 3 (极低)│ 0-5     │ 3,000,000 │ LOW    │ ~80%+    │
 * └──────────┴─────────┴───────────┴────────┴──────────┘
 *   注：L1 降载强度由 ~25% 修正为 ~15%，基于实测 ΔFPS 数据。
 *
 * 【面积系数 — 仅影响非战斗环境】
 * ───────────────────────────────────────────────────────────
 *   面积系数控制的是非战斗环境下的 NPC 刷新密度（刷佣兵数量 ∝ 1/面积系数）。
 *   在脚本化刷怪的战斗关卡（如堕落城保卫战等 wave-based 关卡）中，
 *   敌人由关卡脚本直接生成，面积系数不参与战斗中的性能调节。
 *   因此面积系数的调整对战斗帧率没有直接影响，其降载效果仅体现在
 *   自由探索、基地巡逻等非战斗场景。
 *
 *   Level 0: 300,000  → 基准
 *   Level 1: 450,000  → 刷佣兵量 = 基准 × 2/3
 *   Level 2: 600,000  → 刷佣兵量 = 基准 × 1/2
 *   Level 3: 3,000,000 → 刷佣兵量 = 基准 × 1/10
 *
 * 【系统辨识提示】
 *   要精确调参，需要测量每档的 ΔFPS（帧率提升量）：
 *     ΔFPS_L = FPS(Level=L) - FPS(Level=L+1)
 *   实验方法：在代表性压力场景中，手动切换性能等级，记录稳定后的 FPS
 *   然后：Kp_optimal ≈ 1 / avg(ΔFPS)
 *
 * 可测试性：
 * - 通过 env 注入把全局依赖（_root、EffectSystem 等）替换为 mock。
 */
class org.flashNight.neur.PerformanceOptimizer.PerformanceActuator {

    /** 承载宿主（通常为 _root.帧计时器），用于写入 offsetTolerance 等兼容字段 */
    private var _host:Object;
    /** 用户预设画质（用于 level=0 恢复） */
    private var _presetQuality:String;
    /** 依赖注入环境 */
    private var _env:Object;

    /**
     * 构造函数
     * @param host:Object 宿主对象（推荐传 _root.帧计时器）
     * @param presetQuality:String 初始预设画质（通常为 _root._quality）
     * @param env:Object （可选）依赖注入：{root, EffectSystem, DeathEffectRenderer, ShellSystem, TrailRenderer, ClipFrameRenderer, BladeMotionTrailsRenderer}
     */
    public function PerformanceActuator(host:Object, presetQuality:String, env:Object) {
        // 空对象默认值：host 未传时 offsetTolerance 赋值静默无害，消除 apply() 内 4 处重复检查
        this._host = (host != undefined) ? host : {};
        this._presetQuality = presetQuality;

        // 允许传入部分env（用于测试注入）；缺失项自动回退到默认实现
        if (env == undefined) env = {};
        if (env.root == undefined) env.root = _root;
        if (env.EffectSystem == undefined) env.EffectSystem = EffectSystem;
        if (env.DeathEffectRenderer == undefined) env.DeathEffectRenderer = DeathEffectRenderer;
        if (env.ShellSystem == undefined) env.ShellSystem = ShellSystem;
        if (env.TrailRenderer == undefined) env.TrailRenderer = TrailRenderer;
        if (env.ClipFrameRenderer == undefined) env.ClipFrameRenderer = ClipFrameRenderer;
        if (env.BladeMotionTrailsRenderer == undefined) env.BladeMotionTrailsRenderer = BladeMotionTrailsRenderer;
        this._env = env;
    }

    /**
     * 应用性能等级对应的降载策略
     * @param level:Number 目标性能等级（0-3）
     */
    public function apply(level:Number):Void {
        var root:Object = this._env.root;
        var effectSystem:Object = this._env.EffectSystem;
        var deathRenderer:Object = this._env.DeathEffectRenderer;
        var shellSystem:Object = this._env.ShellSystem;

        switch (level) {
            case 0:
                effectSystem.maxEffectCount = 20;
                effectSystem.maxScreenEffectCount = 20;
                effectSystem.isDeathEffect = true;

                root.面积系数 = 300000;

                root.同屏打击数字特效上限 = 25;
                deathRenderer.isEnabled = true;
                deathRenderer.enableCulling = false;
                root._quality = this._presetQuality;
                root.天气系统.光照等级更新阈值 = 0.1;
                shellSystem.setMaxShellCountLimit(25);
                root.发射效果上限 = 15;
                root.显示列表.继续播放(root.显示列表.预设任务ID);
                root.UI系统.经济面板动效 = true;

                this._host.offsetTolerance = 10;
                break;

            case 1:
                effectSystem.maxEffectCount = 12;
                effectSystem.maxScreenEffectCount = 12;
                effectSystem.isDeathEffect = true;

                root.面积系数 = 450000;

                root.同屏打击数字特效上限 = 15;
                deathRenderer.isEnabled = true;
                deathRenderer.enableCulling = true;
                root._quality = (this._presetQuality === 'LOW') ? this._presetQuality : 'MEDIUM';
                root.天气系统.光照等级更新阈值 = 0.2;
                shellSystem.setMaxShellCountLimit(12);
                root.发射效果上限 = 10;
                root.显示列表.继续播放(root.显示列表.预设任务ID);
                root.UI系统.经济面板动效 = true;

                this._host.offsetTolerance = 30;
                break;

            case 2:
                effectSystem.maxEffectCount = 10;
                effectSystem.maxScreenEffectCount = 10;
                effectSystem.isDeathEffect = false;

                root.面积系数 = 600000; // 刷佣兵数量砍半
                root.同屏打击数字特效上限 = 12;
                deathRenderer.isEnabled = false;
                deathRenderer.enableCulling = true;
                root.天气系统.光照等级更新阈值 = 0.5;
                root._quality = 'LOW';
                shellSystem.setMaxShellCountLimit(12);
                root.发射效果上限 = 5;
                root.显示列表.暂停播放(root.显示列表.预设任务ID);
                root.UI系统.经济面板动效 = false;

                this._host.offsetTolerance = 50;
                break;

            default:
                effectSystem.maxEffectCount = 0;  // 禁用效果
                effectSystem.maxScreenEffectCount = 5;  // 最低上限
                effectSystem.isDeathEffect = false;

                root.面积系数 = 3000000;  // 刷佣兵为原先十分之一
                root.同屏打击数字特效上限 = 10;
                deathRenderer.isEnabled = false;
                deathRenderer.enableCulling = true;
                root.天气系统.光照等级更新阈值 = 1;
                root._quality = 'LOW';
                shellSystem.setMaxShellCountLimit(10);
                root.发射效果上限 = 0;
                root.显示列表.暂停播放(root.显示列表.预设任务ID);
                root.UI系统.经济面板动效 = false;

                this._host.offsetTolerance = 80;
        }

        // 渲染器联动调整（与工作版本一致）
        this._env.TrailRenderer.getInstance().setQuality(level);
        this._env.ClipFrameRenderer.setPerformanceLevel(level);
        this._env.BladeMotionTrailsRenderer.setPerformanceLevel(level);
    }

    public function setHost(host:Object):Void { this._host = host; }
    public function getHost():Object { return this._host; }

    public function setPresetQuality(q:String):Void { this._presetQuality = q; }
    public function getPresetQuality():String { return this._presetQuality; }

    public function getEnv():Object { return this._env; }
}
