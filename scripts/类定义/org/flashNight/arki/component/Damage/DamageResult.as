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
    
    public function addDamageValue(damage:Number):Void {
        this.totalDamageList.push(damage);
    }
    
    public function setDamageColor(color:String):Void {
        this.damageColor = color;
    }
    
    public function addDamageEffect(effect:String):Void {
        this.damageEffects += effect;
    }
    
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
