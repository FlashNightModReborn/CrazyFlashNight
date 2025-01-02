import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.gesh.arguments.*;
import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Initializer.BaseInitializer implements IInitializer {

    private var factory:IColliderFactory;

    public function BaseInitializer()
    {
        
    }

    public function initialize(target:MovieClip):Void {
        var factory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.AABBFactory);
        if (!target.aabbCollider)
            target.aabbCollider = this.factory.createFromUnitArea(target);
        if (isNaN(target.重量))
            target.重量 = 60;
        if (isNaN(target.韧性系数))
            target.韧性系数 = 1;
        if (isNaN(target.remainingImpactForce))
            target.remainingImpactForce = 0;
        if (isNaN(target.命中率))
            target.命中率 = 10;
    }
}
