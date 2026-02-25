import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.render.renderer.TeslaRenderer;
import org.flashNight.arki.render.renderer.PrismRenderer;
import org.flashNight.arki.render.renderer.RadianceRenderer;
import org.flashNight.arki.render.renderer.SpectrumRenderer;
import org.flashNight.arki.render.renderer.WaveRenderer;
import org.flashNight.arki.render.renderer.PhaseResonanceRenderer;
import org.flashNight.arki.render.renderer.ThermalRenderer;
import org.flashNight.arki.render.renderer.VortexRenderer;
import org.flashNight.arki.render.renderer.PlasmaRenderer;

/**
 * RayStyleRegistry - 射线视觉风格注册表（单一事实来源）
 *
 * 集中管理所有 vfxStyle 相关元数据，新增风格只需修改本文件。
 *
 * 提供：
 * - isValidStyle(style)              合法性校验
 * - renderArc(style, arc, lod, mc)   渲染路由（函数引用查表）
 * - getDefaultPreset(style)          默认预设名
 * - getStyleCost(style)              LOD 成本权重
 * - getStyleNames()                  所有已注册风格列表
 *
 * 新增风格只需在 ensureRegistry() 中添加一行 reg(...) 调用，
 * 并在 TeslaRayConfig 中添加对应的 VFX_xxx 常量。
 *
 * 注意：所有 reg() 调用使用 TeslaRayConfig.VFX_xxx 常量作为风格键，
 * 确保风格字符串只在 TeslaRayConfig 中定义一次（单一事实来源）。
 * 渲染方法必须为静态方法（函数引用不依赖 this 绑定）。
 *
 * @author FlashNight
 * @version 1.3
 */
class org.flashNight.arki.render.RayStyleRegistry {

    // ════════════════════════════════════════════════════════════════════════
    // 注册表数据（一处定义）
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 风格注册表：style → { render:Function, preset:String, cost:Number }
     *
     * AS2 中 ClassName.method 返回的是绑定到类原型的 Function 对象，
     * 可以存入 Object 并通过 entry.render(args) 正常调用。
     */
    private static var _registry:Object = null;

    /** 已注册的风格名列表（缓存） */
    private static var _styleNames:Array = null;

    /**
     * 延迟初始化注册表
     *
     * 选择 lazy-init 而非 static initializer，确保所有 Renderer 类
     * 已完成初始化后再捕获函数引用（AS2 静态初始化顺序不可控）。
     */
    private static function ensureRegistry():Void {
        if (_registry != null) return;

        _registry = {};
        _styleNames = [];

        // ─── 逐条注册（新增风格只改这里 + TeslaRayConfig 常量） ────
        var C:Function = TeslaRayConfig; // 缩写，减少行宽
        //     style (VFX_xxx)     renderer.render            preset name       cost
        reg(C.VFX_TESLA,     TeslaRenderer.render,          "ra2_tesla",       1.5);
        reg(C.VFX_PRISM,     PrismRenderer.render,          "ra2_prism",       1.0);
        reg(C.VFX_RADIANCE,  RadianceRenderer.render,       "radiance",        1.0);
        reg(C.VFX_SPECTRUM,  SpectrumRenderer.render,       "ra3_spectrum",    2.5);
        reg(C.VFX_RESONANCE, PhaseResonanceRenderer.render, "resonance",       2.5);
        reg(C.VFX_WAVE,      WaveRenderer.render,           "ra3_wave",        2.0);
        reg(C.VFX_THERMAL,   ThermalRenderer.render,        "thermal",         2.0);
        reg(C.VFX_VORTEX,    VortexRenderer.render,         "vortex",          2.0);
        reg(C.VFX_PLASMA,    PlasmaRenderer.render,         "plasma",          2.0);
    }

    /** 注册一条风格记录（内部 helper，重复注册静默忽略） */
    private static function reg(style:String, renderFn:Function,
                                 preset:String, cost:Number):Void {
        if (_registry[style] != undefined) return; // 防止重复注册导致 _styleNames 出现重复项
        _registry[style] = { render: renderFn, preset: preset, cost: cost };
        _styleNames.push(style);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 公共 API
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 判断 vfxStyle 是否已注册
     */
    public static function isValidStyle(style:String):Boolean {
        ensureRegistry();
        return _registry[style] != undefined;
    }

    /**
     * 路由渲染：根据 style 查表调用对应渲染器
     *
     * @param style  vfxStyle 字符串
     * @param arc    电弧数据对象
     * @param lod    当前 LOD 等级
     * @param mc     目标 MovieClip
     */
    public static function renderArc(style:String, arc:Object,
                                      lod:Number, mc:MovieClip):Void {
        ensureRegistry();
        var entry:Object = _registry[style];
        if (entry == null) {
            entry = _registry[TeslaRayConfig.VFX_TESLA]; // fallback
        }
        entry.render(arc, lod, mc);
    }

    /**
     * 获取风格的默认预设名
     *
     * @param style vfxStyle 字符串
     * @return 对应的预设名，未知风格返回 "ra2_tesla"
     */
    public static function getDefaultPreset(style:String):String {
        ensureRegistry();
        var entry:Object = _registry[style];
        return (entry != null) ? entry.preset : "ra2_tesla";
    }

    /**
     * 获取风格的 LOD 成本权重
     *
     * @param style vfxStyle 字符串
     * @return 成本值，未知风格返回 1.0
     */
    public static function getStyleCost(style:String):Number {
        ensureRegistry();
        var entry:Object = _registry[style];
        return (entry != null) ? entry.cost : 1.0;
    }

    /**
     * 获取所有已注册的风格名列表
     *
     * @return 风格名数组（返回拷贝，防止外部修改原表）
     */
    public static function getStyleNames():Array {
        ensureRegistry();
        return _styleNames.slice(0);
    }
}
