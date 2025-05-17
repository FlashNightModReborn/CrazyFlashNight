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
    
    // 用于计算复用
    public static var IMPACT:DamageResult = new DamageResult();

    // 只用于传递无伤害的情况，注意不可更改
    public static var NULL:DamageResult = new DamageResult();
    
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

    public static function getIMPACT():DamageResult
    {
        var r:DamageResult = DamageResult.IMPACT;

        r.totalDamageList = [];
        r.damageColor = null;
        r.damageSize = 28;
        r.damageEffects = "";
        r.finalScatterValue = 0;
        r.dodgeStatus = "";
        r.actualScatterUsed = 1;
        r.displayCount = 1;
        r.displayFunction = _root.打击数字特效;

        return r;
    }
    
    /**
     * 添加一个伤害值到伤害列表中。
     * @param {Number} damage - 要添加的伤害值。
     */
    public function addDamageValue(damage:Number):Void {
        var list = this.totalDamageList;
        list[list.length] = damage;
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
     * 兼容联弹处理逻辑，将伤害结果推入堆栈准备显示
     * 
     * @param remainingDamage 待处理的伤害数值
     * @param damageSize 伤害数字大小
     * @return 
     */
    public function calculateScatterDamage(remainingDamage:Number):Void {
        // 设置显示次数为实际使用的霰弹值
        this.displayCount = this.actualScatterUsed;
        
        var actualScatterUsed:Number = this.actualScatterUsed;
        
        if (actualScatterUsed > 1) {
            // 分割总伤害为多个散射伤害
            for (var i:Number = 0; i < actualScatterUsed - 1; i++) {
                // 计算波动伤害（保留原随机逻辑）
                var fluctuatedDamage:Number = (remainingDamage / (actualScatterUsed - i)) 
                    * (100 + _root.随机偏移(50 / actualScatterUsed)) / 100;
                
                // 处理非法值并添加伤害
                fluctuatedDamage = isNaN(fluctuatedDamage) ? 0 : fluctuatedDamage;
                this.addDamageValue(Math.floor(fluctuatedDamage));
                remainingDamage -= fluctuatedDamage;
            }
        }
        
        // 添加最后的剩余伤害
        this.addDamageValue(isNaN(remainingDamage) ? 0 : Math.floor(remainingDamage));
    }
    
    /**
     * 触发伤害显示功能，将伤害值显示在指定的坐标位置。
     * @param {Number} targetX - 伤害显示的X坐标。
     * @param {Number} targetY - 伤害显示的Y坐标。
     */
    public function triggerDisplay(targetX:Number, targetY:Number):Void {
        var list:Array = this.totalDamageList;
        var len:Number = list.length;

        if (len === 0) {
            return; // 如果没有伤害值，直接返回
        }

        // 缓存常用属性到局部变量
        var dmgColor:String = this.damageColor || "#FFFFFF"; // 提供默认颜色
        var dmgSize:Number = Math.floor(this.damageSize); // 将字体大小设为整数
        var dmgEffects:String = this.damageEffects;
        var dodgeStatus:String = this.dodgeStatus;
        var displayFn:Function = this.displayFunction;

        // 预构建不变的字符串部分
        var fontStart:String = '<font color="' + dmgColor + '" size="' + dmgSize + '">';
        var fontEnd:String = '</font>';

        var i:Number = 0;
        do {
            var damage:Number = list[i];
            var displayNumber:String;

            if (damage <= 0) {
                displayNumber = fontStart + 'MISS' + fontEnd;
            } else {
                // 使用位运算优化 Math.floor
                var flooredDamage:Number = damage | 0; // 或者使用 damage >> 0
                displayNumber = fontStart + dodgeStatus + flooredDamage + fontEnd;
            }

            // 拼接伤害效果
            var finalDisplay:String = displayNumber + dmgEffects;

            // 调用显示函数
            displayFn("", finalDisplay, targetX, targetY);

            i++;
        } while (i < len);
    }

    /**
     * 返回一个字符串，表示当前 DamageResult 对象的状态。
     * @return {String} 包含所有伤害相关信息的字符串。
     */
    public function toString():String {
        var result:String = "DamageResult {\n";
        result += "  totalDamageList: " + this.totalDamageList.toString() + ",\n";
        result += "  damageColor: " + this.damageColor + ",\n";
        result += "  damageSize: " + this.damageSize + ",\n";
        result += "  damageEffects: " + this.damageEffects + ",\n";
        result += "  finalScatterValue: " + this.finalScatterValue + ",\n";
        result += "  dodgeStatus: " + this.dodgeStatus + ",\n";
        result += "  actualScatterUsed: " + this.actualScatterUsed + ",\n";
        result += "  displayCount: " + this.displayCount + ",\n";
        result += "  displayFunction: " + (this.displayFunction != null ? "[Function]" : "null") + "\n";
        result += "}";
        return result;
    }
}