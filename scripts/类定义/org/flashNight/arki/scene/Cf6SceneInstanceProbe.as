/** Constructor-only observer attached to the existing TestProbeLeaf test linkage. */
class org.flashNight.arki.scene.Cf6SceneInstanceProbe extends MovieClip {
    public static var constructions:Number=0;
    public var atConstruction:Object;
    public function Cf6SceneInstanceProbe() {
        constructions++;
        atConstruction={shop:this["商店检索名"],skillSource:this["技能检索名"],taskSource:this["任务名"],
            skills:this["可学的技能"],dialogue:this["默认对话"],x:this._x,y:this._y};
    }
}
