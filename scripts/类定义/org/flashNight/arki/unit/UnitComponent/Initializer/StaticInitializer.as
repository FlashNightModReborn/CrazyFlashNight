import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.gesh.arguments.*;
import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Initializer.StaticInitializer implements IInitializer {

    public function initialize():Void
    {
        throw new Error("工具类待实现");
    }

    public static function onSceneChanged():Void
    {
        var gameworld = _root.gameworld;
        var factory:IColliderFactory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.AABBFactory);
        for (var each in gameworld) 
        {
            var target = gameworld[each];
            if(target.hp > 0)
            {
                if(!target.aabbCollider) target.aabbCollider = factory.createFromUnitArea(target);
                if(isNaN(target.重量)) target.重量 = 60;
                if(isNaN(target.韧性系数)) target.韧性系数 = 1;
                if(isNaN(target.残余冲击力)) target.残余冲击力 = 0;
                if(isNaN(target.命中率)) target.命中率 = 10;

            }
        }
    }
}
