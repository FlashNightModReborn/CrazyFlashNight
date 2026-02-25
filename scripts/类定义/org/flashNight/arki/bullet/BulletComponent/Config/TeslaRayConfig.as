import org.flashNight.arki.render.VfxPresets;
import org.flashNight.arki.render.RayStyleRegistry;

/**
 * TeslaRayConfig - 射线配置类 (扩展版)
 *
 * 封装射线子弹的所有可配置参数，包括：
 * • 射线物理参数（长度）
 * • 射线模式与多目标控制（模式、目标数、衰减）
 * • 模式特有参数（连锁/折射搜索半径等）
 * • 视觉风格参数（vfxStyle、vfxPreset、vfxParams）
 * • 公共视觉参数（颜色、粗细）
 * • 风格专用参数（Tesla/Prism/Spectrum/Wave）
 * • 时间参数（持续时间、淡出时间）
 *
 * 使用方式：
 * 1. XML配置通过 AttributeLoader 解析后调用 fromXML() 创建实例
 * 2. fromXML() 在解析阶段完成预设合并，spawn 时仅读取（避免高频 GC）
 * 3. 实例存储在 bullet.rayConfig 属性上
 * 4. RayVfxManager 根据 vfxStyle 路由到对应渲染器
 *
 * 射线模式说明 (rayMode - 命中拓扑)：
 * • "single" - 默认，命中最近单目标
 * • "chain"  - 连锁弹跳，命中后从命中点搜索附近下一目标继续连锁
 * • "pierce" - 穿透射线，一条射线命中路径上所有目标
 * • "fork"   - 光棱折射，命中后从命中点搜索附近目标定向折射
 *
 * 视觉风格说明 (vfxStyle - 渲染风格，与 rayMode 完全正交)：
 * • "tesla"    - 磁暴风格：高频抖动电弧 + 随机分叉 + 闪烁
 * • "prism"    - 光棱风格：稳定直束 + 强高光 + 呼吸动画
 * • "radiance" - 辉光风格：三层泛光渲染 + 呼吸脉冲 + 色散偏移
 * • "spectrum" - 光谱风格：彩虹渐变 + 颜色滚动 + 流动感
 * • "wave"     - 波能风格：正弦波路径 + 脉冲膨胀 + 命中点增亮
 *
 * 预设系统：
 * • vfxPreset 指定预设名（如 "ra2_tesla"），自动加载默认参数
 * • XML 显式值覆盖预设
 * • vfxParams 提供额外覆盖（用于风格专用参数）
 *
 * 多目标控制设计：
 * 目标数量由 bullet.pierceLimit（<attribute> 层）控制，与普通子弹共用同一字段。
 * 射线子弹不进入主循环，因此该字段不会与普通穿透机制冲突。
 *
 *   bullet.pierceLimit = 1（默认）→ 任何模式都退化为 single 行为
 *   bullet.pierceLimit = N →
 *     pierce: 沿路径命中 N 个目标
 *     chain:  主命中 + (N-1) 次弹跳
 *     fork:   主命中 + (N-1) 条折射光束
 */
class org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig {

    // ========== 射线模式常量 ==========

    /** 单发模式（默认）：命中最近目标 */
    public static var MODE_SINGLE:String = "single";
    /** 连锁模式：命中后弹跳到附近目标 */
    public static var MODE_CHAIN:String = "chain";
    /** 穿透模式：射线贯穿路径上所有目标 */
    public static var MODE_PIERCE:String = "pierce";
    /** 光棱折射模式：命中后从命中点搜索附近目标定向折射 */
    public static var MODE_FORK:String = "fork";

    // ========== 视觉风格常量 ==========

    /** 磁暴风格：高频抖动电弧 + 随机分叉 */
    public static var VFX_TESLA:String = "tesla";
    /** 光棱风格：稳定直束 + 强高光 + 呼吸动画 */
    public static var VFX_PRISM:String = "prism";
    /** 辉光风格：三层泛光渲染 + 呼吸脉冲 + 色散偏移 */
    public static var VFX_RADIANCE:String = "radiance";
    /** 光谱风格：彩虹渐变 + 颜色滚动 */
    public static var VFX_SPECTRUM:String = "spectrum";
    /** 相位谐振风格：密集多色短波螺旋 */
    public static var VFX_RESONANCE:String = "resonance";
    /** 波能风格：正弦波路径 + 脉冲膨胀 */
    public static var VFX_WAVE:String = "wave";
    /** 热能风格：红橙正弦波 + 脉冲宽度调制 */
    public static var VFX_THERMAL:String = "thermal";
    /** 涡旋风格：宽展双螺旋缠绕 */
    public static var VFX_VORTEX:String = "vortex";
    /** 等离子风格：湍流双螺旋 + 高频扰动 */
    public static var VFX_PLASMA:String = "plasma";

    // ========== 射线物理参数 ==========

    /** 射线长度（像素），必须配置 */
    public var rayLength:Number;

    // ========== 射线模式控制 ==========

    /**
     * 射线模式标识 (命中拓扑)
     * 可选值: "single" | "chain" | "pierce" | "fork"
     * 默认 "single"
     */
    public var rayMode:String;

    // ========== 视觉风格参数 ==========

    /**
     * 渲染风格标识 (与 rayMode 完全正交)
     * 可选值: "tesla" | "prism" | "radiance" | "spectrum" | "resonance" | "wave" | "thermal" | "vortex" | "plasma"
     * 默认 "tesla"
     * @see RayStyleRegistry 所有合法风格的注册表（单一事实来源）
     */
    public var vfxStyle:String;

    /**
     * 预设名称
     * 可选值: "ra2_tesla" | "ra2_prism" | "radiance" | "ra3_spectrum" | "resonance" | "ra3_wave" | "thermal" | "vortex" | "plasma"
     * 若未指定，根据 vfxStyle 自动选择默认预设
     * @see RayStyleRegistry.getDefaultPreset()
     */
    public var vfxPreset:String;

    /**
     * 风格专用参数覆盖 (松散对象)
     * 用于覆盖预设中的特定参数，如 { shimmerAmp: 0.2, stripeCount: 5 }
     */
    public var vfxParams:Object;

    // ========== 多目标伤害衰减 ==========

    /**
     * 每额外命中一个目标的伤害衰减系数（所有模式通用）
     *
     * 应用方式：
     * - pierce: 第 i 个目标伤害 = 原始伤害 × damageFalloff^(i-1)
     * - chain:  第 i 次弹跳伤害 = 原始伤害 × damageFalloff^i
     * - fork:   第 j 条子射线伤害 = 原始伤害 × damageFalloff
     *           （fork 不做累积衰减，所有子射线使用相同系数）
     *
     * 默认 1.0 → 无伤害衰减
     */
    public var damageFalloff:Number;

    // ========== 连锁/折射 共用参数 ==========

    /**
     * 目标搜索半径（像素）
     * chain 模式：每次弹跳从当前命中点搜索下一目标的半径
     * fork 模式：从主命中点搜索折射目标的半径
     */
    public var chainRadius:Number;

    /**
     * 弹跳间视觉延迟帧数（0 = 即时全部显示）
     * 【预留字段】当前 processRayBullets 未消费，所有弹跳在同一帧即时渲染。
     * 未来如需逐帧展示连锁动画，可在 RayVfxManager 中读取此值。
     */
    public var chainDelay:Number;

    // ========== 电弧视觉参数 ==========

    /** 主电弧颜色（十六进制，如 0x00FFFF） */
    public var primaryColor:Number;

    /** 辉光/分支颜色（十六进制） */
    public var secondaryColor:Number;

    /** 电弧线条粗细（像素） */
    public var thickness:Number;

    /** 分支数量 */
    public var branchCount:Number;

    /** 分支生成概率（0-1） */
    public var branchProbability:Number;

    /** 电弧分段长度（像素），越小越细腻 */
    public var segmentLength:Number;

    /** 抖动幅度（像素），控制电弧锯齿程度 */
    public var jitter:Number;

    /** 是否启用随机爆闪 (true = 启用，Tesla 默认开，其他风格默认关) */
    public var flickerEnabled:Boolean;

    /** 爆闪范围 [minAlpha, maxAlpha]，如 [70, 100] 表示 alpha 在 70~100 之间随机 */
    public var flickerMin:Number;
    public var flickerMax:Number;

    // ========== Prism 专用参数 ==========

    /** 呼吸亮度幅度 (0~1) */
    public var shimmerAmp:Number;

    /** 呼吸频率 (周期/帧) */
    public var shimmerFreq:Number;

    /** 折射线粗细倍率 (0.5~1.0) */
    public var forkThicknessMul:Number;

    // ========== Spectrum 专用参数 ==========

    /** 调色板数组 (十六进制颜色值) */
    public var palette:Array;

    /** 调色板滚动速度 (hue/帧) */
    public var paletteScrollSpeed:Number;

    /** 条纹数量 */
    public var stripeCount:Number;

    /** 波形抖动幅度 (像素) */
    public var distortAmp:Number;

    /** 波形抖动波长 (像素) */
    public var distortWaveLen:Number;

    // ========== Wave 专用参数 ==========

    /** 波形幅度 (像素) */
    public var waveAmp:Number;

    /** 波长 (像素) */
    public var waveLen:Number;

    /** 波传播速度 (像素/帧) */
    public var waveSpeed:Number;

    /** 脉冲幅度 (粗细倍率) */
    public var pulseAmp:Number;

    /** 脉冲速率 (周期/帧) */
    public var pulseRate:Number;

    /** 命中点波纹大小 (像素) */
    public var hitRippleSize:Number;

    /** 命中点波纹透明度 (0~100) */
    public var hitRippleAlpha:Number;

    // ========== 时间参数 ==========

    /** 视觉持续帧数（电弧保持显示的时间） */
    public var visualDuration:Number;

    /** 淡出帧数（alpha从100渐变到0的时间） */
    public var fadeOutDuration:Number;

    // ========== 默认值常量 ==========

    // 基础物理参数默认值
    private static var DEFAULT_RAY_LENGTH:Number = 900;
    private static var DEFAULT_RAY_MODE:String = "single";
    private static var DEFAULT_VFX_STYLE:String = "tesla";

    // 公共视觉参数默认值
    private static var DEFAULT_PRIMARY_COLOR:Number = 0x00FFFF;
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFFFFF;
    private static var DEFAULT_THICKNESS:Number = 3;
    private static var DEFAULT_VISUAL_DURATION:Number = 5;
    private static var DEFAULT_FADE_OUT_DURATION:Number = 3;

    // Tesla 专用默认值
    private static var DEFAULT_BRANCH_COUNT:Number = 4;
    private static var DEFAULT_BRANCH_PROBABILITY:Number = 0.5;
    private static var DEFAULT_SEGMENT_LENGTH:Number = 35;
    private static var DEFAULT_JITTER:Number = 40;
    private static var DEFAULT_FLICKER_ENABLED:Boolean = true;   // Tesla 默认开启爆闪
    private static var DEFAULT_FLICKER_MIN:Number = 70;
    private static var DEFAULT_FLICKER_MAX:Number = 100;

    // Prism 专用默认值
    private static var DEFAULT_SHIMMER_AMP:Number = 0.1;
    private static var DEFAULT_SHIMMER_FREQ:Number = 0.08;  // 约12帧一个周期，避免整数帧归零
    private static var DEFAULT_FORK_THICKNESS_MUL:Number = 0.7;

    // Spectrum 专用默认值
    private static var DEFAULT_PALETTE_SCROLL_SPEED:Number = 20;
    private static var DEFAULT_STRIPE_COUNT:Number = 7;
    private static var DEFAULT_DISTORT_AMP:Number = 3;
    private static var DEFAULT_DISTORT_WAVE_LEN:Number = 60;

    // Wave 专用默认值
    private static var DEFAULT_WAVE_AMP:Number = 8;
    private static var DEFAULT_WAVE_LEN:Number = 40;
    private static var DEFAULT_WAVE_SPEED:Number = 0.15;
    private static var DEFAULT_PULSE_AMP:Number = 0.2;
    private static var DEFAULT_PULSE_RATE:Number = 0.3;
    private static var DEFAULT_HIT_RIPPLE_SIZE:Number = 15;
    private static var DEFAULT_HIT_RIPPLE_ALPHA:Number = 50;

    // 多目标伤害衰减默认值
    private static var DEFAULT_DAMAGE_FALLOFF:Number = 1.0;

    // 连锁/折射共用默认值
    private static var DEFAULT_CHAIN_RADIUS:Number = 200;
    private static var DEFAULT_CHAIN_DELAY:Number = 0;

    // 合法风格校验已迁入 RayStyleRegistry（单一事实来源）

    private static var VALID_MODES:Object = {
        single: true,
        chain: true,
        pierce: true,
        fork: true
    };

    /**
     * 构造函数
     * 初始化所有参数为默认值
     * pierceLimit=1 + damageFalloff=1.0 等价于 "single" 模式行为
     */
    public function TeslaRayConfig() {
        // 基础物理参数
        rayLength = DEFAULT_RAY_LENGTH;
        rayMode = DEFAULT_RAY_MODE;

        // 视觉风格（默认 tesla）
        vfxStyle = DEFAULT_VFX_STYLE;
        vfxPreset = null;  // null 表示使用 vfxStyle 的默认预设
        vfxParams = null;

        // 公共视觉参数
        primaryColor = DEFAULT_PRIMARY_COLOR;
        secondaryColor = DEFAULT_SECONDARY_COLOR;
        thickness = DEFAULT_THICKNESS;
        visualDuration = DEFAULT_VISUAL_DURATION;
        fadeOutDuration = DEFAULT_FADE_OUT_DURATION;

        // Tesla 专用
        branchCount = DEFAULT_BRANCH_COUNT;
        branchProbability = DEFAULT_BRANCH_PROBABILITY;
        segmentLength = DEFAULT_SEGMENT_LENGTH;
        jitter = DEFAULT_JITTER;
        flickerEnabled = DEFAULT_FLICKER_ENABLED;
        flickerMin = DEFAULT_FLICKER_MIN;
        flickerMax = DEFAULT_FLICKER_MAX;

        // Prism 专用
        shimmerAmp = DEFAULT_SHIMMER_AMP;
        shimmerFreq = DEFAULT_SHIMMER_FREQ;
        forkThicknessMul = DEFAULT_FORK_THICKNESS_MUL;

        // Spectrum 专用
        palette = null;  // 延迟初始化
        paletteScrollSpeed = DEFAULT_PALETTE_SCROLL_SPEED;
        stripeCount = DEFAULT_STRIPE_COUNT;
        distortAmp = DEFAULT_DISTORT_AMP;
        distortWaveLen = DEFAULT_DISTORT_WAVE_LEN;

        // Wave 专用
        waveAmp = DEFAULT_WAVE_AMP;
        waveLen = DEFAULT_WAVE_LEN;
        waveSpeed = DEFAULT_WAVE_SPEED;
        pulseAmp = DEFAULT_PULSE_AMP;
        pulseRate = DEFAULT_PULSE_RATE;
        hitRippleSize = DEFAULT_HIT_RIPPLE_SIZE;
        hitRippleAlpha = DEFAULT_HIT_RIPPLE_ALPHA;

        // 伤害衰减（damageFalloff=1.0 → 无衰减）
        damageFalloff = DEFAULT_DAMAGE_FALLOFF;

        // 连锁/折射共用
        chainRadius = DEFAULT_CHAIN_RADIUS;
        chainDelay = DEFAULT_CHAIN_DELAY;
    }

    /**
     * 从XML节点解析配置
     *
     * 【关键设计】预设合并在此阶段一次性完成，spawn 时仅读取，
     * 避免高频 for-in 循环的 GC 开销。
     *
     * 解析优先级（从低到高）：
     * 1. 构造函数默认值
     * 2. vfxPreset 预设值
     * 3. XML 显式值
     * 4. vfxParams 覆盖
     *
     * @param node XML节点对象（attributeNode.rayConfig）
     * @return TeslaRayConfig 配置实例
     *
     * XML结构示例：
     * <rayConfig>
     *     <rayLength>900</rayLength>
     *     <rayMode>chain</rayMode>
     *     <vfxStyle>prism</vfxStyle>
     *     <vfxPreset>ra2_prism</vfxPreset>
     *     <vfxParams>
     *         <shimmerAmp>0.15</shimmerAmp>
     *     </vfxParams>
     *     <damageFalloff>0.7</damageFalloff>
     *     <chainRadius>200</chainRadius>
     *     <chainDelay>2</chainDelay>
     *     <primaryColor>0xFFDD00</primaryColor>
     *     <secondaryColor>0xFFFFAA</secondaryColor>
     *     <thickness>3</thickness>
     *     <visualDuration>5</visualDuration>
     *     <fadeOutDuration>3</fadeOutDuration>
     * </rayConfig>
     */
    public static function fromXML(node:Object):TeslaRayConfig {
        var config:TeslaRayConfig = new TeslaRayConfig();

        if (node == undefined || node == null) {
            return config;
        }

        // ====== 第1步：解析 vfxStyle ======

        if (node.vfxStyle != undefined) {
            var style:String = normalizeToken(String(node.vfxStyle));
            if (isValidStyle(style)) {
                config.vfxStyle = style;
            }
        }

        // ====== 第2步：加载预设 ======

        var presetName:String = null;
        if (node.vfxPreset != undefined) {
            presetName = String(node.vfxPreset);
        } else {
            // 未指定预设时，根据 vfxStyle 获取默认预设
            presetName = VfxPresets.getDefaultPresetForStyle(config.vfxStyle);
        }
        config.vfxPreset = presetName;

        // 加载预设并应用到 config
        var preset:Object = VfxPresets.get(presetName);
        if (preset != null) {
            applyPreset(config, preset);
        }

        // ====== 第3步：XML 显式值覆盖预设 ======

        // 基础物理参数
        if (node.rayLength != undefined) {
            config.rayLength = Number(node.rayLength);
        }

        // 射线模式
        if (node.rayMode != undefined) {
            var mode:String = normalizeToken(String(node.rayMode));
            if (isValidMode(mode)) {
                config.rayMode = mode;
            }
        }

        // 伤害衰减
        if (node.damageFalloff != undefined) {
            config.damageFalloff = Number(node.damageFalloff);
        }

        // 连锁/折射共用参数
        if (node.chainRadius != undefined) {
            config.chainRadius = Number(node.chainRadius);
        }
        if (node.chainDelay != undefined) {
            config.chainDelay = Number(node.chainDelay);
        }

        // 公共视觉参数
        if (node.primaryColor != undefined) {
            config.primaryColor = parseColor(node.primaryColor);
        }
        if (node.secondaryColor != undefined) {
            config.secondaryColor = parseColor(node.secondaryColor);
        }
        if (node.thickness != undefined) {
            config.thickness = Number(node.thickness);
        }
        if (node.visualDuration != undefined) {
            config.visualDuration = Number(node.visualDuration);
        }
        if (node.fadeOutDuration != undefined) {
            config.fadeOutDuration = Number(node.fadeOutDuration);
        }

        // Tesla 专用参数
        if (node.branchCount != undefined) {
            config.branchCount = Number(node.branchCount);
        }
        if (node.branchProbability != undefined) {
            config.branchProbability = Number(node.branchProbability);
        }
        if (node.segmentLength != undefined) {
            config.segmentLength = Number(node.segmentLength);
        }
        if (node.jitter != undefined) {
            config.jitter = Number(node.jitter);
        }
        if (node.flickerEnabled != undefined) {
            config.flickerEnabled = (String(node.flickerEnabled).toLowerCase() == "true");
        }
        if (node.flickerMin != undefined) {
            config.flickerMin = Number(node.flickerMin);
        }
        if (node.flickerMax != undefined) {
            config.flickerMax = Number(node.flickerMax);
        }

        // Prism 专用参数
        if (node.shimmerAmp != undefined) {
            config.shimmerAmp = Number(node.shimmerAmp);
        }
        if (node.shimmerFreq != undefined) {
            config.shimmerFreq = Number(node.shimmerFreq);
        }
        if (node.forkThicknessMul != undefined) {
            config.forkThicknessMul = Number(node.forkThicknessMul);
        }

        // Spectrum 专用参数
        if (node.palette != undefined) {
            config.palette = parsePalette(node.palette);
        }
        if (node.paletteScrollSpeed != undefined) {
            config.paletteScrollSpeed = Number(node.paletteScrollSpeed);
        }
        if (node.stripeCount != undefined) {
            config.stripeCount = Number(node.stripeCount);
        }
        if (node.distortAmp != undefined) {
            config.distortAmp = Number(node.distortAmp);
        }
        if (node.distortWaveLen != undefined) {
            config.distortWaveLen = Number(node.distortWaveLen);
        }

        // Wave 专用参数
        if (node.waveAmp != undefined) {
            config.waveAmp = Number(node.waveAmp);
        }
        if (node.waveLen != undefined) {
            config.waveLen = Number(node.waveLen);
        }
        if (node.waveSpeed != undefined) {
            config.waveSpeed = Number(node.waveSpeed);
        }
        if (node.pulseAmp != undefined) {
            config.pulseAmp = Number(node.pulseAmp);
        }
        if (node.pulseRate != undefined) {
            config.pulseRate = Number(node.pulseRate);
        }
        if (node.hitRippleSize != undefined) {
            config.hitRippleSize = Number(node.hitRippleSize);
        }
        if (node.hitRippleAlpha != undefined) {
            config.hitRippleAlpha = Number(node.hitRippleAlpha);
        }

        // ====== 第4步：vfxParams 覆盖 ======

        if (node.vfxParams != undefined) {
            config.vfxParams = parseVfxParams(node.vfxParams);
            // 将 vfxParams 中的值应用到 config
            applyVfxParams(config, config.vfxParams);
        }

        return config;
    }

    /**
     * 将预设值应用到配置对象
     *
     * @param config 目标配置对象
     * @param preset 预设对象
     */
    private static function applyPreset(config:TeslaRayConfig, preset:Object):Void {
        // 公共字段
        if (preset.primaryColor != undefined) config.primaryColor = preset.primaryColor;
        if (preset.secondaryColor != undefined) config.secondaryColor = preset.secondaryColor;
        if (preset.thickness != undefined) config.thickness = preset.thickness;
        if (preset.visualDuration != undefined) config.visualDuration = preset.visualDuration;
        if (preset.fadeOutDuration != undefined) config.fadeOutDuration = preset.fadeOutDuration;

        // Tesla 专用
        if (preset.branchCount != undefined) config.branchCount = preset.branchCount;
        if (preset.branchProbability != undefined) config.branchProbability = preset.branchProbability;
        if (preset.segmentLength != undefined) config.segmentLength = preset.segmentLength;
        if (preset.jitter != undefined) config.jitter = preset.jitter;
        if (preset.flickerEnabled != undefined) config.flickerEnabled = preset.flickerEnabled;
        if (preset.flickerMin != undefined) config.flickerMin = preset.flickerMin;
        if (preset.flickerMax != undefined) config.flickerMax = preset.flickerMax;

        // Prism 专用
        if (preset.shimmerAmp != undefined) config.shimmerAmp = preset.shimmerAmp;
        if (preset.shimmerFreq != undefined) config.shimmerFreq = preset.shimmerFreq;
        if (preset.forkThicknessMul != undefined) config.forkThicknessMul = preset.forkThicknessMul;

        // Spectrum 专用
        if (preset.palette != undefined) {
            // 复制数组以避免共享引用
            config.palette = preset.palette.slice(0);
        }
        if (preset.paletteScrollSpeed != undefined) config.paletteScrollSpeed = preset.paletteScrollSpeed;
        if (preset.stripeCount != undefined) config.stripeCount = preset.stripeCount;
        if (preset.distortAmp != undefined) config.distortAmp = preset.distortAmp;
        if (preset.distortWaveLen != undefined) config.distortWaveLen = preset.distortWaveLen;

        // Wave 专用
        if (preset.waveAmp != undefined) config.waveAmp = preset.waveAmp;
        if (preset.waveLen != undefined) config.waveLen = preset.waveLen;
        if (preset.waveSpeed != undefined) config.waveSpeed = preset.waveSpeed;
        if (preset.pulseAmp != undefined) config.pulseAmp = preset.pulseAmp;
        if (preset.pulseRate != undefined) config.pulseRate = preset.pulseRate;
        if (preset.hitRippleSize != undefined) config.hitRippleSize = preset.hitRippleSize;
        if (preset.hitRippleAlpha != undefined) config.hitRippleAlpha = preset.hitRippleAlpha;
    }

    /**
     * 解析 vfxParams 节点
     *
     * @param vfxParamsNode XML 节点
     * @return 解析后的对象
     */
    private static function parseVfxParams(vfxParamsNode:Object):Object {
        var result:Object = {};
        for (var key:String in vfxParamsNode) {
            var value = vfxParamsNode[key];

            // 颜色参数
            if (key == "palette") {
                result[key] = parsePalette(value);
            } else if (key.indexOf("Color") >= 0) {
                result[key] = parseColor(value);
            // 显式布尔字段
            } else if (key == "flickerEnabled") {
                result[key] = parseBoolean(value, false);
            } else {
                var numericValue:Number = Number(value);
                // 数值字段解析失败时保留原值，避免把 NaN 写入配置
                result[key] = isNaN(numericValue) ? value : numericValue;
            }
        }
        return result;
    }

    /**
     * 将 vfxParams 应用到配置对象
     *
     * @param config 目标配置对象
     * @param params vfxParams 对象
     */
    private static function applyVfxParams(config:TeslaRayConfig, params:Object):Void {
        for (var key:String in params) {
            if (config[key] != undefined) {
                var currentValue = config[key];
                var nextValue = params[key];
                var currentType:String = typeof(currentValue);

                if (currentType == "number") {
                    // 仅接受有效数值，拒绝 NaN
                    if (typeof(nextValue) == "number" && !isNaN(nextValue)) {
                        config[key] = Number(nextValue);
                    }
                } else if (currentType == "boolean") {
                    if (typeof(nextValue) == "boolean") {
                        config[key] = nextValue;
                    } else {
                        config[key] = parseBoolean(nextValue, currentValue);
                    }
                } else if (currentValue instanceof Array) {
                    if (nextValue instanceof Array) {
                        config[key] = nextValue.slice(0);
                    }
                } else {
                    config[key] = nextValue;
                }
            }
        }
    }

    /**
     * 解析调色板配置
     *
     * 支持格式：
     * - 逗号分隔的颜色字符串: "0xFF0000,0x00FF00,0x0000FF"
     * - 数组节点
     *
     * @param value 调色板配置值
     * @return 颜色数组
     */
    private static function parsePalette(value):Array {
        if (value instanceof Array) {
            var result:Array = [];
            for (var i:Number = 0; i < value.length; i++) {
                result.push(parseColor(value[i]));
            }
            return result;
        }
        // 尝试解析逗号分隔的字符串
        var str:String = String(value);
        var parts:Array = str.split(",");
        var palette:Array = [];
        for (var j:Number = 0; j < parts.length; j++) {
            var trimmed:String = parts[j];
            // 移除首尾空白 (AS2 无 trim，手动处理)
            while (trimmed.charAt(0) == " ") trimmed = trimmed.substr(1);
            while (trimmed.charAt(trimmed.length - 1) == " ") trimmed = trimmed.substr(0, trimmed.length - 1);
            if (trimmed.length > 0) {
                palette.push(parseColor(trimmed));
            }
        }
        return palette;
    }

    /**
     * 解析颜色值
     * 支持十六进制字符串（如 "0x00FFFF"）或数字
     *
     * @param value 颜色值（字符串或数字）
     * @return Number 颜色的数字表示
     */
    private static function parseColor(value):Number {
        if (typeof(value) == "number") {
            return value;
        }
        var str:String = String(value);
        if (str.indexOf("0x") == 0 || str.indexOf("0X") == 0) {
            return parseInt(str, 16);
        }
        if (str.charAt(0) == "#") {
            return parseInt("0x" + str.substr(1), 16);
        }
        return Number(value);
    }

    /**
     * 解析布尔值（支持 true/false/1/0）
     */
    private static function parseBoolean(value, defaultValue:Boolean):Boolean {
        if (typeof(value) == "boolean") return Boolean(value);
        if (typeof(value) == "number") return Number(value) != 0;
        var str:String = normalizeToken(String(value));
        if (str == "true" || str == "1") return true;
        if (str == "false" || str == "0") return false;
        return defaultValue;
    }

    /**
     * 规范化字符串标记（去除首尾空白并转小写）
     */
    private static function normalizeToken(value:String):String {
        var str:String = value;
        var start:Number = 0;
        var end:Number = str.length - 1;

        while (start <= end && str.charCodeAt(start) <= 32) start++;
        while (end >= start && str.charCodeAt(end) <= 32) end--;

        if (start > end) return "";
        return str.substring(start, end + 1).toLowerCase();
    }

    /**
     * 判断渲染风格是否合法（委托给 RayStyleRegistry）
     */
    private static function isValidStyle(style:String):Boolean {
        return RayStyleRegistry.isValidStyle(style);
    }

    /**
     * 判断射线模式是否合法
     */
    private static function isValidMode(mode:String):Boolean {
        return VALID_MODES[mode] == true;
    }

    /**
     * 判断是否为 single 模式（默认行为）
     * 当 rayMode 未配置或为 "single" 时返回 true
     */
    public function isSingle():Boolean {
        return rayMode == "single";
    }

    /**
     * 调试输出
     * @return String 配置的字符串表示
     */
    public function toString():String {
        var s:String = "[TeslaRayConfig" +
               " rayMode=" + rayMode +
               " vfxStyle=" + vfxStyle +
               " vfxPreset=" + vfxPreset +
               " rayLength=" + rayLength +
               " damageFalloff=" + damageFalloff +
               " primaryColor=0x" + primaryColor.toString(16) +
               " thickness=" + thickness +
               " visualDuration=" + visualDuration +
               " fadeOutDuration=" + fadeOutDuration;

        // 模式特有参数
        if (rayMode == "chain" || rayMode == "fork") {
            s += " chainRadius=" + chainRadius + " chainDelay=" + chainDelay;
        }

        // 风格特有参数
        switch (vfxStyle) {
            case "tesla":
                s += " branchCount=" + branchCount + " jitter=" + jitter;
                break;
            case "prism":
                s += " shimmerAmp=" + shimmerAmp + " forkThicknessMul=" + forkThicknessMul;
                break;
            case "radiance":
                s += " shimmerAmp=" + shimmerAmp + " forkThicknessMul=" + forkThicknessMul;
                break;
            case "spectrum":
                s += " stripeCount=" + stripeCount + " paletteScrollSpeed=" + paletteScrollSpeed;
                break;
            case "resonance":
                s += " stripeCount=" + stripeCount + " paletteScrollSpeed=" + paletteScrollSpeed + " distortWaveLen=" + distortWaveLen;
                break;
            case "wave":
                s += " waveAmp=" + waveAmp + " pulseAmp=" + pulseAmp;
                break;
            case "thermal":
                s += " waveAmp=" + waveAmp + " pulseAmp=" + pulseAmp;
                break;
            case "vortex":
                s += " waveAmp=" + waveAmp + " waveLen=" + waveLen + " pulseAmp=" + pulseAmp;
                break;
            case "plasma":
                s += " waveAmp=" + waveAmp + " waveLen=" + waveLen + " pulseAmp=" + pulseAmp;
                break;
        }

        return s + "]";
    }

    /**
     * 判断是否为 Tesla 风格
     */
    public function isTesla():Boolean {
        return vfxStyle == "tesla";
    }

    /**
     * 判断是否为 Prism 风格
     */
    public function isPrism():Boolean {
        return vfxStyle == "prism";
    }

    /**
     * 判断是否为 Spectrum 风格
     */
    public function isSpectrum():Boolean {
        return vfxStyle == "spectrum";
    }

    /**
     * 判断是否为 Radiance 风格
     */
    public function isRadiance():Boolean {
        return vfxStyle == "radiance";
    }

    /**
     * 判断是否为 PhaseResonance 风格
     */
    public function isResonance():Boolean {
        return vfxStyle == "resonance";
    }

    /**
     * 判断是否为 Thermal 风格
     */
    public function isThermal():Boolean {
        return vfxStyle == "thermal";
    }

    /**
     * 判断是否为 Vortex 风格
     */
    public function isVortex():Boolean {
        return vfxStyle == "vortex";
    }

    /**
     * 判断是否为 Plasma 风格
     */
    public function isPlasma():Boolean {
        return vfxStyle == "plasma";
    }

    /**
     * 判断是否为 Wave 风格
     */
    public function isWave():Boolean {
        return vfxStyle == "wave";
    }
}
