import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.corpse.DeathEffectRenderer;
import org.flashNight.arki.bullet.BulletComponent.Shell.ShellSystem;
import org.flashNight.arki.render.TrailRenderer;
import org.flashNight.arki.render.ClipFrameRenderer;
import org.flashNight.arki.render.BladeMotionTrailsRenderer;
import org.flashNight.arki.render.WeatherParticleRenderer;
import org.flashNight.arki.render.SkyboxRenderer;
import org.flashNight.arki.render.GameWorldOverlayRenderer;

/**
 * PerformanceActuator - 性能执行器/作动器
 *
 * 【控制理论】执行器的设计原则（2 档 + softU 连续调节）
 * ───────────────────────────────────────────────────────────
 *   执行器接收两个控制量：
 *   - tier ∈ {0, 1}：硬切换 _quality（唯一决定性降载手段）
 *   - softU ∈ [0, 1]：连续调节特效/弹壳/面积/渲染器等"软旋钮"
 *
 *   tier 0: _quality = 用户预设（HIGH/MEDIUM），显示列表继续播放
 *   tier 1: _quality = LOW（矢量渲染简化），显示列表暂停播放
 *
 * 1.【单调性 Monotonicity】
 *   softU↑ 必须导致 FPS↑（所有软旋钮同向降载）。
 *   tier 1 的 _quality=LOW 贡献 56-86% 降载幅度（实测数据）。
 *
 * 2.【为何从 4 档简化为 2 档】
 *   实测中 L0≈L1、L2≈L3（CPU 瓶颈下），4 档退化为等效 2 档。
 *   显式承认这一现实，用 tier + softU 替代离散 4 档。
 *   软旋钮通过连续插值覆盖原 L1/L3 的微调空间。
 *
 * 3.【面积系数 — 仅影响非战斗环境】
 *   面积系数控制非战斗环境的 NPC 刷新密度（∝ 1/面积系数）。
 *   战斗关卡中敌人由脚本直接生成，面积系数不参与性能调节。
 *
 * 可测试性：通过 env 注入替换全局依赖。
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
        if (env.WeatherParticleRenderer == undefined) env.WeatherParticleRenderer = WeatherParticleRenderer;
        if (env.SkyboxRenderer == undefined) env.SkyboxRenderer = SkyboxRenderer;
        if (env.GameWorldOverlayRenderer == undefined) env.GameWorldOverlayRenderer = GameWorldOverlayRenderer;
        this._env = env;
    }

    /**
     * 应用 2 档 + 连续软参数的降载策略
     * @param tier:Number   硬切换档位（0=用户预设画质, 1=LOW）
     * @param softU:Number  软旋钮插值 [0,1]（0=全质量, 1=最大降载）
     */
    public function apply(tier:Number, softU:Number):Void {
        var root:Object = this._env.root;
        var es:Object = this._env.EffectSystem;
        var dr:Object = this._env.DeathEffectRenderer;
        var ss:Object = this._env.ShellSystem;
        var inv:Number = 1 - softU;

        // ── 硬切换: _quality（唯一决定性降载手段，贡献 56-86% ΔFPS）──
        if (tier === 0) {
            root._quality = this._presetQuality;
            root.显示列表.继续播放(root.显示列表.预设任务ID);
        } else {
            root._quality = "LOW";
            root.显示列表.暂停播放(root.显示列表.预设任务ID);
        }

        // ── 软参数: lerp(high, low, softU)，所有旋钮同向降载保证单调性 ──
        es.maxEffectCount        = (20 * inv + 0.5) >> 0;             // 20→0
        es.maxScreenEffectCount  = (15 * inv + 5 + 0.5) >> 0;        // 20→5
        root.面积系数             = (300000 * inv + 3000000 * softU + 0.5) >> 0;
        root.天气系统.lightUpdateThreshold = 0.1 + 0.9 * softU;       // 0.1→1.0
        ss.setMaxShellCountLimit((15 * inv + 10 + 0.5) >> 0);        // 25→10
        root.发射效果上限          = (15 * inv + 0.5) >> 0;            // 15→0
        this._host.offsetTolerance = (10 + 70 * softU + 0.5) >> 0;   // 10→80

        // ── 永久开启（画质性价比高，非持续性开销，不受 softU 控制）──
        es.isDeathEffect         = true;
        dr.isEnabled             = true;
        dr.enableCulling         = true;  // 离屏剔除始终开启，零代价减少无用 draw

        // ── 渲染器档位: softU → 0-3 离散映射（保留渲染器内部 4 档分辨率）──
        var rl:Number = (softU * 4) >> 0;
        if (rl > 3) rl = 3;
        this._env.TrailRenderer.getInstance().setQuality(rl);
        this._env.ClipFrameRenderer.setPerformanceLevel(rl);
        this._env.BladeMotionTrailsRenderer.setPerformanceLevel(rl);
        this._env.WeatherParticleRenderer.setPerformanceLevel(rl);
        this._env.SkyboxRenderer.setPerformanceLevel(rl);
        this._env.GameWorldOverlayRenderer.setPerformanceLevel(rl);
    }

    public function setHost(host:Object):Void { this._host = host; }
    public function getHost():Object { return this._host; }

    public function setPresetQuality(q:String):Void { this._presetQuality = q; }
    public function getPresetQuality():String { return this._presetQuality; }

    public function getEnv():Object { return this._env; }
}
