import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.gesh.arguments.*;
import org.flashNight.naki.Sort.InsertionSort;
import org.flashNight.gesh.func.*;
import org.flashNight.arki.unit.UnitComponent.Updater.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer implements IInitializer {
    public static var factory:IColliderFactory;

    public function initialize(target:MovieClip):Void {
        throw new Error("工具类待实现");
    }

    public static function initializeUnit(target:MovieClip):Void {
        // 排除从非gameworld召唤出的单位
        if(target._parent !== _root.gameworld) return;
        
        ComponentInitializer.initialize(target);
        ParameterInitializer.initialize(target);
        EventInitializer.initialize(target);
        DisplayNameInitializer.initialize(target);
        TargetCacheUpdater.addUnit(target);
    }

    public static function initializeGameWorldUnit():Void {
        var gameworld:MovieClip = _root.gameworld;
        for (var each in gameworld) {
            var target = gameworld[each];
            if (target.hp > 0) StaticInitializer.initializeUnit(target);
        }
    }

    public static function onSceneChanged():Void {
        if (!_root.gameworld) return;
        StaticInitializer.factory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.AABBFactory);
        StaticInitializer.onSceneChanged = StaticInitializer.initializeGameWorldUnit;
        StaticInitializer.initializeGameWorldUnit();
    }
}
