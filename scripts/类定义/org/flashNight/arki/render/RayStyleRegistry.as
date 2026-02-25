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
 * 新增风格只需在 ensureRegistry() 中添加一行 reg(...) 调用。
 *
 * @author FlashNight
 * @version 1.2
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

        // ─── 逐条注册（新增风格只改这里） ──────────────────────
        //     style          renderer.render            preset name       cost
        reg("tesla",     TeslaRenderer.render,          "ra2_tesla",       1.5);
        reg("prism",     PrismRenderer.render,          "ra2_prism",       1.0);
        reg("radiance",  RadianceRenderer.render,       "radiance",        1.0);
        reg("spectrum",  SpectrumRenderer.render,       "ra3_spectrum",    2.5);
        reg("resonance", PhaseResonanceRenderer.render, "resonance",       2.5);
        reg("wave",      WaveRenderer.render,           "ra3_wave",        2.0);
        reg("thermal",   ThermalRenderer.render,        "thermal",         2.0);
        reg("vortex",    VortexRenderer.render,         "vortex",          2.0);
        reg("plasma",    PlasmaRenderer.render,         "plasma",          2.0);
    }

    /** 注册一条风格记录（内部 helper） */
    private static function reg(style:String, renderFn:Function,
                                 preset:String, cost:Number):Void {
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
            entry = _registry["tesla"]; // fallback
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
