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

    public static var IMPACT:DamageResult = new DamageResult();
    
    public function DamageResult() {
        this.reset();
    }

    /**
     * 重置 DamageResult 的所有属性
     */
    public function reset():Void
    {
        this.totalDamageList = [];
        this.damageColor = null;
        this.damageSize = 28;
        this.damageEffects = "";
        this.finalScatterValue = 0;
        this.dodgeStatus = "";
        this.actualScatterUsed = 1;
        this.displayCount = 1;
        this.displayFunction = _root.打击数字特效;
    }
    
    /**
     * 添加一个伤害值到列表
     * @param damage Number 伤害值
     */
    public function addDamageValue(damage:Number):Void {
        this.totalDamageList.push(damage);
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
        for (var i:Number = 0; i < this.totalDamageList.length; i++) {
            var displayNumber:String;
            if (this.totalDamageList[i] <= 0) {
                displayNumber = '<font color="' + this.damageColor + '" size="' + this.damageSize + '">MISS</font>';
            } else {
                displayNumber = '<font color="' + this.damageColor + '" size="' + this.damageSize + '">' 
                              + this.dodgeStatus 
                              + Math.floor(this.totalDamageList[i]) 
                              + "</font>";
            }
            this.displayFunction("", displayNumber + this.damageEffects, targetX, targetY);
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
