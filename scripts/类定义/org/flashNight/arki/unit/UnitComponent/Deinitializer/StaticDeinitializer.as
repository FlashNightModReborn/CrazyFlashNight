

import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

class org.flashNight.arki.unit.UnitComponent.Deinitializer.StaticDeinitializer
{

    public function deInitialize(target:MovieClip):Void
    {
        throw new Error("工具类待实现");
    }

    public static function deInitializeUnit(target:MovieClip):Void 
    {
        if(!target._deInitialized)
        {
            target.aabbCollider.getFactory().releaseCollider(target.aabbCollider);
            TargetCacheUpdater.removeUnit(target);

            target._deInitialized = true;
        } 
    }
}
