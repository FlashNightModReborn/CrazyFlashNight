/**
 * TeslaRayConfig - 磁暴射线配置类
 *
 * 封装射线子弹的所有可配置参数，包括：
 * • 射线物理参数（长度）
 * • 电弧视觉参数（颜色、粗细、分支、抖动）
 * • 时间参数（持续时间、淡出时间）
 * • 命中效果（hitEffect库链接名）
 *
 * 使用方式：
 * 1. XML配置通过 AttributeLoader 解析后调用 fromXML() 创建实例
 * 2. 实例存储在 bullet.rayConfig 属性上
 * 3. TeslaRayLifecycle 和 LightningRenderer 读取配置执行逻辑
 */
class org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig {

    // ========== 射线物理参数 ==========

    /** 射线长度（像素），必须配置 */
    public var rayLength:Number;

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

    // ========== 命中效果 ==========

    /** 命中特效的库链接名（用户需在库中创建对应MC） */
    public var hitEffect:String;

    // ========== 默认值常量 ==========

    private static var DEFAULT_RAY_LENGTH:Number = 900;
    private static var DEFAULT_PRIMARY_COLOR:Number = 0x00FFFF;
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFFFFF;
    private static var DEFAULT_THICKNESS:Number = 3;
    private static var DEFAULT_BRANCH_COUNT:Number = 3;
    private static var DEFAULT_BRANCH_PROBABILITY:Number = 0.4;
    private static var DEFAULT_SEGMENT_LENGTH:Number = 25;
    private static var DEFAULT_JITTER:Number = 15;
    private static var DEFAULT_VISUAL_DURATION:Number = 120;
    private static var DEFAULT_FADE_OUT_DURATION:Number = 30;

    /**
     * 构造函数
     * 初始化所有参数为默认值
     */
    public function TeslaRayConfig() {
        rayLength = DEFAULT_RAY_LENGTH;
        primaryColor = DEFAULT_PRIMARY_COLOR;
        secondaryColor = DEFAULT_SECONDARY_COLOR;
        thickness = DEFAULT_THICKNESS;
        branchCount = DEFAULT_BRANCH_COUNT;
        branchProbability = DEFAULT_BRANCH_PROBABILITY;
        segmentLength = DEFAULT_SEGMENT_LENGTH;
        jitter = DEFAULT_JITTER;
        visualDuration = DEFAULT_VISUAL_DURATION;
        fadeOutDuration = DEFAULT_FADE_OUT_DURATION;
        hitEffect = null;
    }

    /**
     * 从XML节点解析配置
     *
     * @param node XML节点对象（attributeNode.rayConfig）
     * @return TeslaRayConfig 配置实例
     *
     * XML结构示例：
     * <rayConfig>
     *     <rayLength>900</rayLength>
     *     <primaryColor>0x00FFFF</primaryColor>
     *     <secondaryColor>0xFFFFFF</secondaryColor>
     *     <thickness>3</thickness>
     *     <branchCount>4</branchCount>
     *     <branchProbability>0.5</branchProbability>
     *     <segmentLength>25</segmentLength>
     *     <jitter>18</jitter>
     *     <visualDuration>180</visualDuration>
     *     <fadeOutDuration>60</fadeOutDuration>
     *     <hitEffect>电击火花</hitEffect>
     * </rayConfig>
     */
    public static function fromXML(node:Object):TeslaRayConfig {
        var config:TeslaRayConfig = new TeslaRayConfig();

        if (node == undefined || node == null) {
            return config;
        }

        // 射线长度（必须参数，有默认值兜底）
        if (node.rayLength != undefined) {
            config.rayLength = Number(node.rayLength);
        }

        // 主电弧颜色（支持十六进制字符串如 "0x00FFFF"）
        if (node.primaryColor != undefined) {
            config.primaryColor = parseColor(node.primaryColor);
        }

        // 辉光颜色
        if (node.secondaryColor != undefined) {
            config.secondaryColor = parseColor(node.secondaryColor);
        }

        // 线条粗细
        if (node.thickness != undefined) {
            config.thickness = Number(node.thickness);
        }

        // 分支数量
        if (node.branchCount != undefined) {
            config.branchCount = Number(node.branchCount);
        }

        // 分支概率
        if (node.branchProbability != undefined) {
            config.branchProbability = Number(node.branchProbability);
        }

        // 分段长度
        if (node.segmentLength != undefined) {
            config.segmentLength = Number(node.segmentLength);
        }

        // 抖动幅度
        if (node.jitter != undefined) {
            config.jitter = Number(node.jitter);
        }

        // 视觉持续时间
        if (node.visualDuration != undefined) {
            config.visualDuration = Number(node.visualDuration);
        }

        // 淡出时间
        if (node.fadeOutDuration != undefined) {
            config.fadeOutDuration = Number(node.fadeOutDuration);
        }

        // 命中特效
        if (node.hitEffect != undefined) {
            config.hitEffect = String(node.hitEffect);
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
        // 处理 "0x" 前缀的十六进制字符串
        if (str.indexOf("0x") == 0 || str.indexOf("0X") == 0) {
            return parseInt(str, 16);
        }
        // 处理 "#" 前缀的十六进制字符串
        if (str.charAt(0) == "#") {
            return parseInt("0x" + str.substr(1), 16);
        }
        // 尝试直接转换为数字
        return Number(value);
    }

    /**
     * 调试输出
     * @return String 配置的字符串表示
     */
    public function toString():String {
        return "[TeslaRayConfig rayLength=" + rayLength +
               " primaryColor=0x" + primaryColor.toString(16) +
               " thickness=" + thickness +
               " branchCount=" + branchCount +
               " visualDuration=" + visualDuration +
               " fadeOutDuration=" + fadeOutDuration +
               " hitEffect=" + hitEffect + "]";
    }
}
