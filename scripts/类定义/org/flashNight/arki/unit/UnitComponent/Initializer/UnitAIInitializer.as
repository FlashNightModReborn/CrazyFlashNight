import org.flashNight.arki.unit.UnitAI.BaseUnitAI;

class org.flashNight.arki.unit.UnitComponent.Initializer.UnitAIInitializer {
    public static function initialize(target:MovieClip):Void {
        if(target._name != _root.控制目标 && target.兵种 != "主角-男" && target.unitAI == null) {
            target.unitAI = new BaseUnitAI(target);
        }
    }
}
