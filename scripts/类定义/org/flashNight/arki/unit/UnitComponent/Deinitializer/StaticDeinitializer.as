

class org.flashNight.arki.unit.UnitComponent.Deinitializer.StaticDeinitializer
{

    public function deInitialize(target:MovieClip):Void
    {
        throw new Error("工具类待实现");
    }

    public static function deInitializeUnit(target:MovieClip):Void 
    {
        target.aabbCollider.getFactory().releaseCollider(target.aabbCollider);
    }
}
