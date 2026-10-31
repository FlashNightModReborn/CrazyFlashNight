import org.flashNight.arki.item.equipment.EquipmentConfigManager;

/** 火凤数值与有效冷兵器上下文；2026-10-28 用户确认普攻 30 段修订。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengRules {
    public static var SET_ID:String = "huofeng";
    public static var SLOTS:Array = ["头部装备","上装装备","下装装备","手部装备","脚部装备"];
    public static var NORMAL_FRAMES:Array = [15,12,14,20,22];
    public static var NORMAL_PULSES:Array = [[8,9,10,11,12],[2,3,4,5,6],[4,5,6,7,8],[4,5,6,7,8,14,15,16,17,18],[5,6,7,8,9]];
    public static var NORMAL_COEFFICIENTS:Array = [0.70,0.70,0.75,0.65,0.90];
    public static var NORMAL_CANCEL:Array = [[13,15],[7,9],[9,11],[19,20],[10,13]];
    // Sample the authored return poses when chaining held J. Damage windows
    // and all five stages remain unchanged; no idle/reattach between cycles.
    public static var NORMAL_REPEAT_POSES:Array = [84,88,92,95];
    // Native sword uses 10 for ordinary hits and 1 for its finishing windows.
    // Pulse damage is already split; dividing impact again weakened it twice.
    public static var HIT_KNOCK_RATE:Number = 10;
    public static var FINISH_KNOCK_RATE:Number = 1;
    public static var RUN_PULSES:Array = [8,10,12,14,16,18,20,22,24,26,28,30];
    public static var SPIN_PULSES:Array = [14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46,48,50,52,54,56,58,60,68,70,72,74,76,78,80,82,84,86,88,90,92,94,96,98,100,102,104,106,108,110,112,114];
    public static var NIRVANA_PULSES:Array = [[],[35,37,39],[78,80,82,84,86,88]];
    public static var NIRVANA_FRAMES:Array = [0,92,113];
    public static var HP_FACTORS:Array = [1,0.70,0.50];
    public static var HEAL_RATES:Array = [0,0.03,0.06];
    public static var BLAST_B:Array = [0,0.30,0.40];
    public static var BLAST_F:Array = [0,0.50,0.75];
    public static var BLAST_RADIUS:Array = [0,75,90];
    public static var BLAST_DEPTH:Array = [0,25,30];

    public static function finite(value):Boolean {
        return typeof value == "number" && isFinite(value);
    }
    public static function numberOrZero(value):Number {
        return finite(value) ? Number(value) : 0;
    }
    public static function hasFivePieces(unit:Object):Boolean {
        for (var i:Number=0;i<SLOTS.length;i++) {
            var slot:String=SLOTS[i];
            if (!unit[slot] || unit[slot+"数据"].setId !== SET_ID) return false;
        }
        return true;
    }
    public static function profileActive(unit:Object):Boolean {
        return unit.攻击模式 === "空手" && unit.__huofeng != undefined && unit.__huofeng.isActive();
    }
    public static function coldMode(unit:Object):Boolean {
        return unit.攻击模式 === "兵器" || profileActive(unit);
    }
    public static function bladePower(unit:Object):Number {
        var snapshot:Object=unit.man.__huofengColdSnapshot;
        if (snapshot!=null && HuofengRules.profileActive(unit)) return snapshot.power;
        return liveBladePower(unit);
    }
    public static function liveBladePower(unit:Object):Number {
        if (!profileActive(unit)) return unit.刀属性.power;
        var level:Number=Number(unit.手部装备.value.level);
        if (!finite(level) || level != Math.floor(level) || level < 1 || level > EquipmentConfigManager.getMaxLevel()) level=1;
        return 270 * EquipmentConfigManager.getLevelMultiplier(level) + numberOrZero(unit.装备刀锋利度加成);
    }
    public static function unarmedTerm(unit:Object):Number {
        return profileActive(unit) ? 0 : unit.空手攻击力;
    }
    public static function attackUnit(unit:Object):Number {
        var passive:Object=unit.被动技能.刀剑攻击;
        var level:Number=passive.启用 ? numberOrZero(passive.等级) : 0;
        level=Math.max(0,Math.min(20,level));
        return bladePower(unit)*(1+0.075*level)+numberOrZero(unit.mp攻击加成)+numberOrZero(unit.伤害加成);
    }
    public static function pulseIndex(frames:Array, frame:Number):Number {
        for(var i:Number=0;i<frames.length;i++) if(frames[i]==frame) return i;
        return -1;
    }
}
