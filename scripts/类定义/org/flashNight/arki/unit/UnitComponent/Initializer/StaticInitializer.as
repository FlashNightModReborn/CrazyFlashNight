import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.gesh.arguments.*;
import org.flashNight.naki.Sort.InsertionSort;
import org.flashNight.gesh.func.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer implements IInitializer
{
    public static var factory:IColliderFactory;

    public function initialize(target:MovieClip):Void {
        throw new Error("工具类待实现");
    }

    public static function initializeUnit(target:MovieClip):Void 
    {
        if (!target.aabbCollider) target.aabbCollider = StaticInitializer.factory.createFromUnitArea(target);
        if (isNaN(target.重量)) target.重量 = 60;
        if (isNaN(target.韧性系数)) target.韧性系数 = 1;
        if (isNaN(target.remainingImpactForce)) target.remainingImpactForce = 0;
        if (isNaN(target.命中率)) target.命中率 = 10;
        if (isNaN(target.躲闪率)) target.躲闪率 = 999;
        if (isNaN(target.等级)) target.等级 = 1;
    }

    public static function initializeGameWorldUnit():Void 
    {
        var gameworld:MovieClip = _root.gameworld;
        for (var each in gameworld) {
            var target = gameworld[each];
            if (target.hp > 0) {
                StaticInitializer.initializeUnit(target);
            }
        }
    }

    public static function onSceneChanged():Void 
    {
        if(!_root.gameworld) return;
        StaticInitializer.factory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.AABBFactory);
        StaticInitializer.onSceneChanged = StaticInitializer.initializeGameWorldUnit;
        StaticInitializer.initializeGameWorldUnit();
    }
}
