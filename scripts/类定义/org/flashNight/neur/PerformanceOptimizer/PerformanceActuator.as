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
 *   实测总降载幅度: +10.8 FPS (前次) / +3.8 FPS (低端机)。
 *   受限于 Flash _quality 枚举的离散性，降载手段不可连续化。
 *
 * 3.【响应时间 Response Time】
 *   执行器的响应时间决定了被控对象的时间常数 τ。
 *   Flash 渲染器参数修改 → 生效 ≈ 1帧，但刷佣兵/特效堆积的消化需要 τ ≈ 2-5秒。
 *
 * 【离散分档的根本原因 — 为什么不是连续调节】
 * ───────────────────────────────────────────────────────────
 *   Flash 平台可用的核心画质参数只有 Stage._quality 预设值：
 *     HIGH / MEDIUM / LOW / BEST
 *   这是一个不可细分的离散枚举，没有中间态。
 *   在实测中，真正能产生决定性帧率差异的只有两种状态：
 *     • 默认画质 (用户预设，通常 MEDIUM 或 HIGH)
 *     • LOW（矢量渲染大幅简化，帧率显著提升）
 *   特效数量、弹壳上限、面积系数等参数只能做微调，
 *   无法像 _quality 那样带来量级性的帧率变化，因此无法实现平滑连续干预。
 *
 *   这意味着执行器本质上只有 2 个核心锚点：
 *     L0 (默认画质) ←→ L2 (_quality=LOW)
 *   L1 和 L3 是围绕这两个锚点的补充挡位。
 *
 * 【挡位设计理念 Tier Design Philosophy】
 * ───────────────────────────────────────────────────────────
 *   L0（理想挡位 · 核心锚点）：
 *     使用用户预设画质，展示最好的视觉效果。
 *     玩家在非高压场景下应稳定于此。
 *
 *   L1（缓冲挡位 · L0 的补充）：
 *     画质仍为 MEDIUM，仅微降特效/弹壳等辅助参数。
 *     设计意图是在小幅性能波动时提供过渡缓冲，避免画质直接跳变到 LOW。
 *     实测降载效果有限（ΔFPS₀₁ ≈ 0.5~1.7），在 CPU 瓶颈机器上几乎为零。
 *
 *   L2（高压挡位 · 核心锚点）：
 *     _quality=LOW 生效，这是唯一能带来决定性帧率提升的手段。
 *     大规模团战的默认运行状态。
 *
 *   L3（兜底挡位 · L2 的补充）：
 *     _quality 与 L2 相同（仍为 LOW），仅进一步裁剪特效至极限。
 *     理论上不应长期驻留，仅作为关卡配置失衡时的安全网。
 *     实测 ΔFPS₂₃ ≈ 0~3.0，在 CPU 瓶颈机器上与 L2 几乎无差异。
 *
 * 【实测关键发现 — _quality=LOW 是主要降载手段】
 * ───────────────────────────────────────────────────────────
 *   多轮实测数据（堕落城保卫战）：
 *                        前次测试    低端机(fs)
 *     ΔFPS₀₁ (L0→L1):    +1.7         +0.5      ← 微调参数，效果不显著
 *     ΔFPS₁₂ (L1→L2):    +6.1         +3.3      ← _quality=LOW，决定性差异
 *     ΔFPS₂₃ (L2→L3):    +3.0          ≈0       ← _quality 不变，仅辅助裁剪
 *
 *   结论：
 *   1. _quality=LOW (L1→L2) 贡献了 56%~86% 的总降载幅度，是唯一决定性手段。
 *   2. 特效/弹壳/面积系数等参数只能微调，不能替代画质预设的作用。
 *   3. 在 CPU 瓶颈机器上，4 档退化为等效 2 档（L0≈L1, L2≈L3），
 *      系统通过 PID+量化器的跳级行为自动适应了这一退化。
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
 *   注：降载强度为理论设计值。实测中 L1 降载效果仅 ~5%（低端机接近 0%），
 *   L2 的 _quality=LOW 是唯一产生决定性帧率差异的参数。
 *   L3 与 L2 的 _quality 相同，额外裁剪在 CPU 瓶颈下效果极小。
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
