import org.flashNight.arki.unit.UnitAI.BaseUnitAI;

class org.flashNight.arki.unit.UnitComponent.Initializer.UnitAIInitializer {
    public static function initialize(target:MovieClip):Void {
        if(target._name != _root.控制目标 && target.unitAI == null && target._parent === _root.gameworld) {
            if(target.unitAIType == "None"){
                return;
            }
            if(target.unitAIType != null){
                target.unitAI = new BaseUnitAI(target, target.unitAIType);
                return;
            }
            if(target.兵种 != "主角-男"){
                if(target.佣兵数据 != null){
                    target.unitAI = new BaseUnitAI(target, "Mecenary");
                }else if(target.允许拾取 === true){
                    target.unitAI = new BaseUnitAI(target, "PickupEnemy");
                }else{
                    target.unitAI = new BaseUnitAI(target, "Enemy");
                }
            }
        }
    }
}
