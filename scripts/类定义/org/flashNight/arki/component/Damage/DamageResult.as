// File: org/flashNight/arki/component/Damage/DamageResult.as

/**
 * DamageResult 类是伤害结果的封装类。
 * - 用于存储和传递伤害计算结果，包括伤害值、颜色、效果等信息。
 * - 提供方法用于添加伤害值、设置颜色、添加效果描述，并触发伤害数字的显示。
 * - 通过复用数组和避免不必要的赋值操作，优化性能。
 */
class org.flashNight.arki.component.Damage.DamageResult {

    // ========== 公共属性 ==========

    /** 存储所有伤害值的列表 */
    public var totalDamageList:Array;

    /** 伤害数字的颜色值（如 "#FF0000"） */
    public var damageColor:String;

    /** 伤害数字的字体大小 */
    public var damageSize:Number;

    /** 伤害效果的描述（如 "<font color='#FF0000'>暴击</font>"） */
    public var damageEffects:String;

    /** 最终的散射值（用于多段伤害计算） */
    public var finalScatterValue:Number;

    /** 目标的躲闪状态（如 "MISS"） */
    public var dodgeStatus:String;

    /** 实际使用的散射值 */
    public var actualScatterUsed:Number;

    /** 伤害数字的显示次数 */
    public var displayCount:Number;

    /** 伤害数字的显示函数（默认为 _root.打击数字特效） */
    public var displayFunction:Function;

    // ========== 静态属性 ==========

    /** 默认的伤害数字显示函数 */
    private static var DEFAULT_DISPLAY_FUNCTION:Function = _root.打击数字特效;

    /** 预定义的 DamageResult 实例，用于快速访问 */
    public static var IMPACT:DamageResult = new DamageResult();

    // ========== 构造函数 ==========

    /**
     * 构造函数。
     * 初始化 DamageResult 实例并调用 reset 方法重置所有属性。
     */
    public function DamageResult() {
        this.reset();
    }

    // ========== 公共方法 ==========

    /**
     * 重置 DamageResult 的所有属性。
     * - 复用数组，避免频繁创建新对象。
     * - 避免不必要的重复赋值，优化性能。
     */
    public function reset():Void {
        // 复用数组，避免频繁创建新对象
        this.totalDamageList.length = 0;

        // 重置其他属性
        this.damageColor = null;
        this.damageEffects = "";
        this.dodgeStatus = "";

        // 避免不必要的重复赋值
        if (this.damageSize != 28) this.damageSize = 28;
        if (this.finalScatterValue != 0) this.finalScatterValue = 0;
        if (this.actualScatterUsed != 1) this.actualScatterUsed = 1;
        if (this.displayCount != 1) this.displayCount = 1;

        // 避免重复查询 _root.打击数字特效
        if (this.displayFunction !== DEFAULT_DISPLAY_FUNCTION) {
            this.displayFunction = DEFAULT_DISPLAY_FUNCTION;
        }
    }

    /**
     * 添加一个伤害值到列表。
     *
     * @param damage 伤害值
     */
    public function addDamageValue(damage:Number):Void {
        var list:Array = this.totalDamageList;
        list[list.length] = damage;
    }

    /**
     * 设置伤害数字的颜色。
     *
     * @param color 颜色值（如 "#FF0000"）
     */
    public function setDamageColor(color:String):Void {
        this.damageColor = color;
    }

    /**
     * 添加伤害效果描述。
     *
     * @param effect 伤害效果描述（如 "<font color='#FF0000'>暴击</font>"）
     */
    public function addDamageEffect(effect:String):Void {
        this.damageEffects += effect;
    }

    /**
     * 触发伤害数字的显示。
     * - 遍历伤害值列表，调用显示函数显示每个伤害值。
     * - 支持显示 "MISS" 状态。
     *
     * @param targetX 目标的 X 坐标
     * @param targetY 目标的 Y 坐标
     */
    public function triggerDisplay(targetX:Number, targetY:Number):Void {
        var list:Array = this.totalDamageList;
        var len:Number = list.length;
        var func:Function = this.displayFunction;

        for (var i:Number = 0; i < len; i++) {
            var displayNumber:String;
            if (list[i] <= 0) {
                displayNumber = '<font color="' + this.damageColor + '" size="' + this.damageSize + '">MISS</font>';
            } else {
                displayNumber = '<font color="' + this.damageColor + '" size="' + this.damageSize + '">'
                              + this.dodgeStatus
                              + Math.floor(list[i])
                              + "</font>";
            }
            func("", displayNumber + this.damageEffects, targetX, targetY);
        }
    }

    /**
     * 将 DamageResult 的当前状态转换为字符串格式。
     * - 便于调试时输出对象状态。
     *
     * @return String DamageResult 的字符串表示
     */
    public function toString():String {
        var damageListStr:String = this.totalDamageList.join(", ");
        var str:String = "";
        str += "DamageResult {\n";
        str += "  totalDamageList: [" + damageListStr + "],\n";
        str += "  damageColor: " + (this.damageColor != null ? this.damageColor : "null") + ",\n";
        str += "  damageSize: " + this.damageSize + ",\n";
        str += "  damageEffects: " + (this.damageEffects != "" ? this.damageEffects : "无") + ",\n";
        str += "  finalScatterValue: " + this.finalScatterValue + ",\n";
        str += "  dodgeStatus: " + (this.dodgeStatus != "" ? this.dodgeStatus : "无") + ",\n";
        str += "  actualScatterUsed: " + this.actualScatterUsed + ",\n";
        str += "  displayCount: " + this.displayCount + ",\n";
        str += "  displayFunction: " + (this.displayFunction != null ? "已设置" : "未设置") + "\n";
        str += "}";
        return str;
    }
}