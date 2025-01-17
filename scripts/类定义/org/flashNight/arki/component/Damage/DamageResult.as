// File: org/flashNight/arki/component/Damage/DamageResult.as

class org.flashNight.arki.component.Damage.DamageResult {
    public var totalDamageList:Array;
    public var damageColor:String;
    public var damageSize:Number;
    public var damageEffects:String;
    public var finalScatterValue:Number;
    public var dodgeStatus:String;
    public var actualScatterUsed:Number;
    public var displayCount:Number;
    public var displayFunction:Function;

    private static var DEFAULT_DISPLAY_FUNCTION:Function = _root.打击数字特效;

    public static var IMPACT:DamageResult = new DamageResult();
    
    public function DamageResult() {
        this.reset();
    }

    /**
     * 重置 DamageResult 的所有属性
     */


    public function reset():Void {
        // 复用数组，避免频繁创建新对象
        this.totalDamageList.length = 0;
        
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
     * 添加一个伤害值到列表
     * @param damage Number 伤害值
     */
    public function addDamageValue(damage:Number):Void {
        var list:Array = this.totalDamageList;
        list[list.length] = damage;
    }
    
    /**
     * 设置伤害显示颜色
     * @param color String 颜色值，如 "#FF0000"
     */
    public function setDamageColor(color:String):Void {
        this.damageColor = color;
    }
    
    /**
     * 添加伤害效果描述
     * @param effect String 伤害效果，如 "<font color='#FF0000'>暴击</font>"
     */
    public function addDamageEffect(effect:String):Void {
        this.damageEffects += effect;
    }
    
    /**
     * 触发伤害数字的显示
     * @param targetX Number 目标的 X 坐标
     * @param targetY Number 目标的 Y 坐标
     */
    public function triggerDisplay(targetX:Number, targetY:Number):Void {
        var list:Array = this.totalDamageList;
        var len:Number = list.length
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
     * 将 DamageResult 的当前状态转换为字符串格式
     * 便于调试时输出对象状态
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
