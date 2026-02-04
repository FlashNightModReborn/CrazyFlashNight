import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.corpse.DeathEffectRenderer;
import org.flashNight.arki.bullet.BulletComponent.Shell.ShellSystem;
import org.flashNight.arki.render.TrailRenderer;
import org.flashNight.arki.render.ClipFrameRenderer;
import org.flashNight.arki.render.BladeMotionTrailsRenderer;

/**
 * PerformanceActuator - 性能执行器/作动器
 *
 * 控制理论视角：
 * - 这是闭环系统中的“执行器/作动器”，将离散控制量 u ∈ {0,1,2,3}
 *   映射为具体的降载动作（特效/画质/刷怪密度/后台任务等）。
 *
 * 设计要求：
 * 1) 单调性（必要）：u↑ 必须总体上使负载↓，从而使 FPS↑；
 * 2) 覆盖面：Level跨度要足够覆盖负载扰动；
 * 3) 行为等价：apply() 的 switch 逻辑需与工作版本逐字对齐。
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
        this._host = host;
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

                if (this._host != undefined) {
                    this._host.offsetTolerance = 10;
                }
                break;

            case 1:
                effectSystem.maxEffectCount = 15;
                effectSystem.maxScreenEffectCount = 15;
                effectSystem.isDeathEffect = true;

                root.面积系数 = 450000;

                root.同屏打击数字特效上限 = 18;
                deathRenderer.isEnabled = true;
                deathRenderer.enableCulling = true;
                root._quality = (this._presetQuality === 'LOW') ? this._presetQuality : 'MEDIUM';
                root.天气系统.光照等级更新阈值 = 0.2;
                shellSystem.setMaxShellCountLimit(18);
                root.发射效果上限 = 10;
                root.显示列表.继续播放(root.显示列表.预设任务ID);
                root.UI系统.经济面板动效 = true;

                if (this._host != undefined) {
                    this._host.offsetTolerance = 30;
                }
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

                if (this._host != undefined) {
                    this._host.offsetTolerance = 50;
                }
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

                if (this._host != undefined) {
                    this._host.offsetTolerance = 80;
                }
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
