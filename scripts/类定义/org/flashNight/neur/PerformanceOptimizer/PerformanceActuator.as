import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.corpse.DeathEffectRenderer;
import org.flashNight.arki.bullet.BulletComponent.Shell.ShellSystem;
import org.flashNight.arki.render.TrailRenderer;
import org.flashNight.arki.render.ClipFrameRenderer;
import org.flashNight.arki.render.BladeMotionTrailsRenderer;
import org.flashNight.arki.render.WeatherParticleRenderer;
import org.flashNight.arki.render.SkyboxRenderer;

/**
 * 执行 C# 指定的 Flash 画质与表现预算。softU 仅是现有 wire 的预算编码，
 * 不在 AS2 做连续反馈。NPC 密度与镜头容差由业务初始化，不随画质变化。
 */
class org.flashNight.neur.PerformanceOptimizer.PerformanceActuator {
    private var _env:Object;

    /** 保留构造签名便于旧测试/初始化装配；host 与 preset 不再约束目标。 */
    public function PerformanceActuator(host:Object, presetQuality:String, env:Object) {
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
        this._env = env;
    }

    /** 显式画质是权威；返回 true 才允许 scheduler 记录执行确认。 */
    public function apply(tier:Number, softU:Number, renderQuality:String):Boolean {
        if (tier != 0 && tier != 1) return false;
        if ((softU - softU) != 0 || softU < 0 || softU > 1) return false;
        if (renderQuality != "LOW" && renderQuality != "MEDIUM" && renderQuality != "HIGH" && renderQuality != "BEST") return false;
        if ((renderQuality == "LOW") != (tier == 1)) return false;
        var root:Object = this._env.root;
        root._quality = renderQuality;
        if (root._quality != renderQuality) return false;
        root.__nativeHudDecorations = tier === 0;
        if (tier === 0) root.显示列表.继续播放(root.显示列表.预设任务ID);
        else root.显示列表.暂停播放(root.显示列表.预设任务ID);

        var es:Object = this._env.EffectSystem;
        var dr:Object = this._env.DeathEffectRenderer;
        var inv:Number = 1 - softU;
        es.maxEffectCount = (20 * inv + 0.5) >> 0;
        es.maxScreenEffectCount = (15 * inv + 5 + 0.5) >> 0;
        root.天气系统.lightUpdateThreshold = 0.1 + 0.9 * softU;
        this._env.ShellSystem.setMaxShellCountLimit((15 * inv + 10 + 0.5) >> 0);
        root.发射效果上限 = (15 * inv + 0.5) >> 0;

        // 一次性死亡表现与离屏剔除维持现有合同。
        es.isDeathEffect = true;
        dr.isEnabled = true;
        dr.enableCulling = true;

        var rendererLevel:Number = (softU * 4) >> 0;
        if (rendererLevel > 3) rendererLevel = 3;
        this._env.TrailRenderer.getInstance().setQuality(rendererLevel);
        this._env.ClipFrameRenderer.setPerformanceLevel(rendererLevel);
        this._env.BladeMotionTrailsRenderer.setPerformanceLevel(rendererLevel);
        this._env.WeatherParticleRenderer.setPerformanceLevel(rendererLevel);
        this._env.SkyboxRenderer.setPerformanceLevel(rendererLevel);
        return true;
    }
}
