/**
 * TeslaRayConfig - 磁暴射线配置类
 *
 * 封装射线子弹的所有可配置参数，包括：
 * • 射线物理参数（长度）
 * • 射线模式与多目标控制（模式、目标数、衰减）
 * • 模式特有参数（连锁/折射搜索半径等）
 * • 电弧视觉参数（颜色、粗细、分支、抖动）
 * • 时间参数（持续时间、淡出时间）
 *
 * 使用方式：
 * 1. XML配置通过 AttributeLoader 解析后调用 fromXML() 创建实例
 * 2. 实例存储在 bullet.rayConfig 属性上
 * 3. TeslaRayLifecycle 和 LightningRenderer 读取配置执行逻辑
 *
 * 射线模式说明：
 * • "single" - 默认，命中最近单目标（现有行为，无需配置 rayMode）
 * • "chain"  - 连锁弹跳，命中后从命中点搜索附近下一目标继续连锁
 * • "pierce" - 穿透射线，一条射线命中路径上所有目标，按 tEntry 距离排序
 * • "fork"   - 光棱折射，命中后从命中点搜索附近目标定向折射（复用 chainRadius）
 *
 * 多目标控制设计：
 * 目标数量由 bullet.pierceLimit（<attribute> 层）控制，与普通子弹共用同一字段。
 * 射线子弹不进入主循环，因此该字段不会与普通穿透机制冲突。
 * damageFalloff 在 <rayConfig> 内配置，控制每额外命中一个目标的伤害衰减。
 *
 *   bullet.pierceLimit = 1（默认）→ 任何模式都退化为 single 行为
 *   bullet.pierceLimit = N →
 *     pierce: 沿路径命中 N 个目标
 *     chain:  主命中 + (N-1) 次弹跳
 *     fork:   主命中 + (N-1) 条折射光束（搜索半径内最近的 N-1 个目标）
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

    // ========== 射线物理参数 ==========

    /** 射线长度（像素），必须配置 */
    public var rayLength:Number;

    // ========== 射线模式控制 ==========

    /**
     * 射线模式标识
     * 可选值: "single" | "chain" | "pierce" | "fork"
     * 默认 "single"，与现有行为完全一致
     */
    public var rayMode:String;

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
     * 未来如需逐帧展示连锁动画，可在 LightningRenderer 中读取此值。
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

    // ========== 时间参数 ==========

    /** 视觉持续帧数（电弧保持显示的时间） */
    public var visualDuration:Number;

    /** 淡出帧数（alpha从100渐变到0的时间） */
    public var fadeOutDuration:Number;

    // ========== 默认值常量 ==========

    private static var DEFAULT_RAY_LENGTH:Number = 900;
    private static var DEFAULT_RAY_MODE:String = "single";
    private static var DEFAULT_PRIMARY_COLOR:Number = 0x00FFFF;
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFFFFF;
    private static var DEFAULT_THICKNESS:Number = 3;
    private static var DEFAULT_BRANCH_COUNT:Number = 4;
    private static var DEFAULT_BRANCH_PROBABILITY:Number = 0.5;
    private static var DEFAULT_SEGMENT_LENGTH:Number = 35;
    private static var DEFAULT_JITTER:Number = 40;
    private static var DEFAULT_VISUAL_DURATION:Number = 5;
    private static var DEFAULT_FADE_OUT_DURATION:Number = 3;

    // 多目标伤害衰减默认值
    private static var DEFAULT_DAMAGE_FALLOFF:Number = 1.0;

    // 连锁/折射共用默认值
    private static var DEFAULT_CHAIN_RADIUS:Number = 200;
    private static var DEFAULT_CHAIN_DELAY:Number = 0;

    /**
     * 构造函数
     * 初始化所有参数为默认值
     * pierceLimit=1 + damageFalloff=1.0 等价于 "single" 模式行为
     */
    public function TeslaRayConfig() {
        rayLength = DEFAULT_RAY_LENGTH;
        rayMode = DEFAULT_RAY_MODE;
        primaryColor = DEFAULT_PRIMARY_COLOR;
        secondaryColor = DEFAULT_SECONDARY_COLOR;
        thickness = DEFAULT_THICKNESS;
        branchCount = DEFAULT_BRANCH_COUNT;
        branchProbability = DEFAULT_BRANCH_PROBABILITY;
        segmentLength = DEFAULT_SEGMENT_LENGTH;
        jitter = DEFAULT_JITTER;
        visualDuration = DEFAULT_VISUAL_DURATION;
        fadeOutDuration = DEFAULT_FADE_OUT_DURATION;

        // 伤害衰减（damageFalloff=1.0 → 无衰减）
        damageFalloff = DEFAULT_DAMAGE_FALLOFF;

        // 连锁/折射共用
        chainRadius = DEFAULT_CHAIN_RADIUS;
        chainDelay = DEFAULT_CHAIN_DELAY;
    }

    /**
     * 从XML节点解析配置
     *
     * @param node XML节点对象（attributeNode.rayConfig）
     * @return TeslaRayConfig 配置实例
     *
     * XML结构示例（现有字段完全向后兼容，新字段均可选）：
     * <rayConfig>
     *     <rayLength>900</rayLength>
     *     <rayMode>chain</rayMode>
     *     <damageFalloff>0.7</damageFalloff>
     *     <chainRadius>200</chainRadius>
     *     <primaryColor>0x00FFFF</primaryColor>
     *     <secondaryColor>0xFFFFFF</secondaryColor>
     *     <thickness>3</thickness>
     *     <branchCount>4</branchCount>
     *     <branchProbability>0.5</branchProbability>
     *     <segmentLength>25</segmentLength>
     *     <jitter>18</jitter>
     *     <visualDuration>5</visualDuration>
     *     <fadeOutDuration>3</fadeOutDuration>
     * </rayConfig>
     */
    public static function fromXML(node:Object):TeslaRayConfig {
        var config:TeslaRayConfig = new TeslaRayConfig();

        if (node == undefined || node == null) {
            return config;
        }

        // ====== 基础物理参数 ======

        if (node.rayLength != undefined) {
            config.rayLength = Number(node.rayLength);
        }

        // ====== 射线模式 ======

        if (node.rayMode != undefined) {
            var mode:String = String(node.rayMode);
            if (mode == "chain" || mode == "pierce" || mode == "fork") {
                config.rayMode = mode;
            }
        }

        // ====== 伤害衰减 ======

        if (node.damageFalloff != undefined) {
            config.damageFalloff = Number(node.damageFalloff);
        }

        // ====== 连锁/折射共用参数 ======

        if (node.chainRadius != undefined) {
            config.chainRadius = Number(node.chainRadius);
        }
        if (node.chainDelay != undefined) {
            config.chainDelay = Number(node.chainDelay);
        }

        // ====== 电弧视觉参数 ======

        if (node.primaryColor != undefined) {
            config.primaryColor = parseColor(node.primaryColor);
        }
        if (node.secondaryColor != undefined) {
            config.secondaryColor = parseColor(node.secondaryColor);
        }
        if (node.thickness != undefined) {
            config.thickness = Number(node.thickness);
        }
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

        // ====== 时间参数 ======

        if (node.visualDuration != undefined) {
            config.visualDuration = Number(node.visualDuration);
        }
        if (node.fadeOutDuration != undefined) {
            config.fadeOutDuration = Number(node.fadeOutDuration);
        }

        return config;
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
        var s:String = "[TeslaRayConfig mode=" + rayMode +
               " rayLength=" + rayLength +
               " damageFalloff=" + damageFalloff +
               " primaryColor=0x" + primaryColor.toString(16) +
               " thickness=" + thickness +
               " branchCount=" + branchCount +
               " visualDuration=" + visualDuration +
               " fadeOutDuration=" + fadeOutDuration;
        if (rayMode == "chain" || rayMode == "fork") {
            s += " chainRadius=" + chainRadius;
        }
        return s + "]";
    }
}
