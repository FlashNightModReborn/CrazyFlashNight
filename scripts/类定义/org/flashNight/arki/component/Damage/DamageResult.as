// File: org/flashNight/arki/component/Damage/DamageResult.as

/**
 * DamageResult 类用于存储和处理伤害计算结果。
 * 它包含了伤害值、伤害颜色、伤害大小、伤害效果等信息，并提供了触发伤害显示的功能。
 */
class org.flashNight.arki.component.Damage.DamageResult {
    
    /**
     * 存储所有伤害值的数组。
     * @type {Array}
     */
    public var totalDamageList:Array;
    
    /**
     * 伤害显示的颜色。
     * @type {String}
     */
    public var damageColor:String;
    
    /**
     * 伤害显示的字体大小。
     * @type {Number}
     */
    public var damageSize:Number;
    
    /**
     * 伤害显示的附加效果。
     * @type {String}
     */
    public var damageEffects:String;
    
    /**
     * 最终的散射值，用于计算伤害的散射效果。
     * @type {Number}
     */
    public var finalScatterValue:Number;
    
    /**
     * 闪避状态，用于显示是否成功闪避伤害。
     * @type {String}
     */
    public var dodgeStatus:String;
    
    /**
     * 实际使用的霰弹值。
     * @type {Number}
     */
    public var actualScatterUsed:Number;
    
    /**
     * 伤害显示的次数。
     * @type {Number}
     */
    public var displayCount:Number;
    
    /**
     * 用于显示伤害的函数。
     * @type {Function}
     */
    public var displayFunction:Function;
    
    /**
     * 静态实例，表示一个默认的伤害结果。
     * @type {DamageResult}
     */
    public static var IMPACT:DamageResult = new DamageResult();
    
    /**
     * DamageResult 类的构造函数。
     * 初始化所有属性为默认值。
     */
    public function DamageResult() {
        this.reset();
    }
    
    /**
     * 重置所有属性为默认值。
     */
    public function reset():Void {
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
     * 添加一个伤害值到伤害列表中。
     * @param {Number} damage - 要添加的伤害值。
     */
    public function addDamageValue(damage:Number):Void {
        this.totalDamageList.push(damage);
    }
    
    /**
     * 设置伤害显示的颜色。
     * @param {String} color - 伤害显示的颜色。
     */
    public function setDamageColor(color:String):Void {
        this.damageColor = color;
    }
    
    /**
     * 添加一个伤害效果到伤害效果字符串中。
     * @param {String} effect - 要添加的伤害效果。
     */
    public function addDamageEffect(effect:String):Void {
        this.damageEffects += effect;
    }
    
    /**
     * 触发伤害显示功能，将伤害值显示在指定的坐标位置。
     * @param {Number} targetX - 伤害显示的X坐标。
     * @param {Number} targetY - 伤害显示的Y坐标。
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
}