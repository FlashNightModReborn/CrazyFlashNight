/**
 * VfxPresets - 射线视觉效果预设定义
 *
 * 定义 4 种预设风格，致敬红色警戒系列的经典效果：
 * • ra2_tesla  - RA2/RA3 磁暴线圈风格（青色电弧，分叉抖动）
 * • ra2_prism  - RA2 光棱塔风格（金黄直线，几何感）
 * • ra3_spectrum - RA3 光谱塔风格（彩虹渐变，流动感）
 * • ra3_wave   - RA3 波能炮风格（红橙粗光柱，脉冲膨胀）
 *
 * 使用方式：
 *   var preset:Object = VfxPresets.get("ra2_tesla");
 *   // 或直接访问
 *   var preset:Object = VfxPresets.ra2_tesla;
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.render.VfxPresets {

    // ════════════════════════════════════════════════════════════════════════
    // 预设定义
    // ════════════════════════════════════════════════════════════════════════

    /**
     * RA2 磁暴线圈预设
     *
     * 视觉特征：青色电弧，高频抖动，随机分叉，模拟高压放电
     */
    public static var ra2_tesla:Object = {
        // 公共字段
        primaryColor: 0x00FFFF,      // 青色 - 电离空气色
        secondaryColor: 0xFFFFFF,    // 白色 - 高温等离子体
        thickness: 2,
        visualDuration: 5,
        fadeOutDuration: 3,
        // Tesla 专用
        branchCount: 4,
        branchProbability: 0.5,
        segmentLength: 25,
        jitter: 18,
        flickerEnabled: true,        // 启用随机爆闪（模拟高压放电不稳定）
        flickerMin: 70,              // alpha 最小值
        flickerMax: 100              // alpha 最大值
    };

    /**
     * RA2 光棱塔预设
     *
     * 视觉特征：纯黄亮束 + 纯白内核 + 高频微颤，致敬原版光棱塔
     */
    public static var ra2_prism:Object = {
        // 公共字段
        primaryColor: 0xFFFF00,      // 纯正亮黄（匹配RA2原版）
        secondaryColor: 0xFFFFAA,    // 淡黄过渡护套（v3三层光学：金黄外晕→淡黄护套→纯白内核）
        thickness: 4,                // 加粗基准（笔直射线需要更有力道）
        visualDuration: 4,
        fadeOutDuration: 2,
        // Prism v3 专用
        shimmerAmp: 0.25,            // 频闪幅度（控制粗细/亮度脉冲强度，非路径抖动）
        shimmerFreq: 0.08,           // 保留（v3未使用，向前兼容）
        forkThicknessMul: 0.6,       // 折射线更细（v3 加强色散对比）
        flickerEnabled: false        // v3自带脉冲频闪，无需额外爆闪
    };

    /**
     * 辉光射线预设
     *
     * 视觉特征：稳定金黄直束，三层辉光渲染，呼吸动画
     * 原 ra2_prism 的视觉风格独立保留
     */
    public static var radiance:Object = {
        // 公共字段
        primaryColor: 0xFFDD00,      // 金黄色
        secondaryColor: 0xFFFFAA,    // 淡黄高光
        thickness: 3,
        visualDuration: 4,
        fadeOutDuration: 2,
        // Radiance 专用
        shimmerAmp: 0.1,             // 呼吸幅度 (0~1)
        shimmerFreq: 0.08,           // 呼吸频率 (周期/帧，约12帧一个周期)
        forkThicknessMul: 0.7,       // 折射线粗细倍率
        flickerEnabled: false        // 禁用爆闪（辉光需要稳定的视觉感受）
    };

    /**
     * RA3 光谱塔预设
     *
     * 视觉特征：冷色螺旋交织 + 叠加泛光 + 笔直白核，致敬RA3光谱武器
     */
    public static var ra3_spectrum:Object = {
        // 公共字段
        primaryColor: 0xFFFFFF,      // 白色（核心层使用）
        secondaryColor: 0xFFFFFF,
        thickness: 4,                // 基准粗细（v3：配合少量线条保持清晰）
        visualDuration: 5,
        fadeOutDuration: 3,
        // Spectrum v3 专用
        palette: [0xFF00FF, 0x00FFFF, 0x0066FF],  // 精简三原色（洋红/亮青/湛蓝）
        paletteScrollSpeed: 30,      // 颜色流速
        stripeCount: 3,              // 3条：高饱和度不糊白，优雅交织
        distortAmp: 10,              // 大振幅：色条间留出镂空
        distortWaveLen: 300,         // 长波：优雅交织1~2次（告别紧绷弹簧感）
        flickerEnabled: false        // v3自带叠加泛光，无需额外爆闪
    };

    /**
     * 相位谐振波预设
     *
     * 视觉特征：短波密织 + 五色霓虹轮转 + 纺锤包络 + 叠加泛光
     */
    public static var resonance:Object = {
        // 公共字段
        primaryColor: 0xFFFFFF,      // 白色（核心层使用）
        secondaryColor: 0xFFFFFF,
        thickness: 4,
        visualDuration: 5,
        fadeOutDuration: 3,
        // PhaseResonance 专用
        palette: [0xFF00FF, 0x00FFFF, 0x8800FF, 0x0088FF, 0xFF66FF],  // 五色冷色霓虹
        paletteScrollSpeed: 30,      // 颜色流速
        stripeCount: 5,              // 5条螺旋（密织饱满感）
        distortAmp: 8,               // 交织振幅
        distortWaveLen: 80,          // 短波长（密集缠绕）
        flickerEnabled: false
    };

    /**
     * RA3 波能炮预设
     *
     * 视觉特征：宽能量束，波形传播，节律脉冲，强贯穿感
     */
    public static var ra3_wave:Object = {
        // 公共字段
        primaryColor: 0xFF4400,      // 红橙色
        secondaryColor: 0xFFAA00,    // 橙黄高光
        thickness: 5,
        visualDuration: 6,
        fadeOutDuration: 4,
        // Wave 专用
        waveAmp: 8,                  // 波形幅度 (像素)
        waveLen: 40,                 // 波长 (像素)
        waveSpeed: 0.15,             // 波传播速度 (像素/帧)
        pulseAmp: 0.2,               // 脉冲幅度 (粗细倍率)
        pulseRate: 0.3,              // 脉冲速率 (周期/帧)
        hitRippleSize: 15,           // 命中点波纹大小 (像素)
        hitRippleAlpha: 50,          // 命中点波纹透明度
        flickerEnabled: false        // 禁用爆闪（波能炮需要稳定的视觉感受）
    };

    // ════════════════════════════════════════════════════════════════════════
    // 预设查询 API
    // ════════════════════════════════════════════════════════════════════════

    /** 预设名到预设对象的映射表 */
    private static var _presetMap:Object = null;

    /**
     * 根据预设名获取预设对象
     *
     * @param presetName 预设名 ("ra2_tesla", "ra2_prism", "ra3_spectrum", "ra3_wave")
     * @return 预设对象，若不存在返回 null
     */
    public static function get(presetName:String):Object {
        // 延迟初始化映射表
        if (_presetMap == null) {
            _presetMap = {
                ra2_tesla: ra2_tesla,
                ra2_prism: ra2_prism,
                radiance: radiance,
                ra3_spectrum: ra3_spectrum,
                resonance: resonance,
                ra3_wave: ra3_wave
            };
        }
        return _presetMap[presetName];
    }

    /**
     * 检查预设名是否有效
     *
     * @param presetName 预设名
     * @return 是否为有效预设
     */
    public static function isValidPreset(presetName:String):Boolean {
        return get(presetName) != null;
    }

    /**
     * 获取所有可用预设名列表
     *
     * @return 预设名数组
     */
    public static function getPresetNames():Array {
        return ["ra2_tesla", "ra2_prism", "radiance", "ra3_spectrum", "resonance", "ra3_wave"];
    }

    /**
     * 根据 vfxStyle 获取默认预设名
     *
     * @param vfxStyle 渲染风格 ("tesla", "prism", "spectrum", "wave")
     * @return 对应的默认预设名
     */
    public static function getDefaultPresetForStyle(vfxStyle:String):String {
        switch (vfxStyle) {
            case "tesla":    return "ra2_tesla";
            case "prism":    return "ra2_prism";
            case "radiance": return "radiance";
            case "spectrum": return "ra3_spectrum";
            case "resonance": return "resonance";
            case "wave":     return "ra3_wave";
            default:         return "ra2_tesla";
        }
    }
}
