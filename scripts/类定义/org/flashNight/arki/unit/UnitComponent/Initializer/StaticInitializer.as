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
    private static var factory:IColliderFactory;
    private static var lazyOnSceneChanged:LazyFunction;

    public function initialize(target:MovieClip):Void
    {
        throw new Error("工具类待实现");
    }

    public static function onSceneChanged():Void
    {
        var gameworld = _root.gameworld;
        if(!gameworld)
        {
            return;
        }
        else
        {
            StaticInitializer.factory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.AABBFactory);
            StaticInitializer.onSceneChanged = function(){
                var gameworld = _root.gameworld;
                for (var each in gameworld) 
                {
                    var target = gameworld[each];
                    if(target.hp > 0)
                    {
                        if(!target.aabbCollider) target.aabbCollider = StaticInitializer.factory.createFromUnitArea(target);
                        if(isNaN(target.重量)) target.重量 = 60;
                        if(isNaN(target.韧性系数)) target.韧性系数 = 1;
                        if(isNaN(target.残余冲击力)) target.残余冲击力 = 0;
                        if(isNaN(target.命中率)) target.命中率 = 10;

                    }
                }
            }
        }

        for (var each in gameworld) 
        {
            var target = gameworld[each];
            if(target.hp > 0)
            {
                if(!target.aabbCollider) target.aabbCollider = StaticInitializer.factory.createFromUnitArea(target);
                if(isNaN(target.重量)) target.重量 = 60;
                if(isNaN(target.韧性系数)) target.韧性系数 = 1;
                if(isNaN(target.残余冲击力)) target.残余冲击力 = 0;
                if(isNaN(target.命中率)) target.命中率 = 10;

            }
        }
    }
}
