import org.flashNight.arki.component.Collider.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.aven.Coordinator.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.ComponentInitializer {

    public static function initialize(target:MovieClip):Void {
        if (!target.aabbCollider) {
            target.aabbCollider = StaticInitializer.factory.createFromUnitArea(target);
        }
        if (!target.dispatcher) {
            target.dispatcher = new LifecycleEventDispatcher(target);
        }
        if(!target.unitAI){
            UnitAIInitializer.initialize(target);
        }

        EventCoordinator.addUnloadCallback(target, function():Void {
            StaticDeinitializer.deInitializeUnit(target);
        });
    }
}
