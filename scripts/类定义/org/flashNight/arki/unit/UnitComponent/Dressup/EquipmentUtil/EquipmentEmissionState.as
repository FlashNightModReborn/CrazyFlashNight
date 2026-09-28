import org.flashNight.arki.render.EquipmentLightBridge;

// Read-only adapter access to the authoritative equipment lifecycle ref.
// Cleanup touches a captured plain map, never a path-rebound actor MovieClip.
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentEmissionState {
    public static function bind(ref:Object, adapter:String):Void {
        release(ref);
        var actor:MovieClip = ref.自机, world:MovieClip = _root.gameworld;
        if (!actor._parent || !world._parent || !actor[ref.装备类型]) return;
        if (!actor.__equipmentLightIdentity) actor.__equipmentLightIdentity = {};
        if (!world.__equipmentLightIdentity) world.__equipmentLightIdentity = {};
        var map:Object = actor.__equipmentEmissionStates;
        if (!map || map.actorIdentity !== actor.__equipmentLightIdentity || map.worldIdentity !== world.__equipmentLightIdentity) {
            map = {actorIdentity:actor.__equipmentLightIdentity,worldIdentity:world.__equipmentLightIdentity,sources:{}};
            actor.__equipmentEmissionStates = map;
        }
        var key:String = "$" + ref.装备类型 + ":" + adapter;
        var token:Object = {map:map,key:key,ref:ref,version:actor.version,equipment:actor[ref.装备类型],
            modNames:EquipmentLightBridge.copyMods(actor[ref.装备类型]),active:true};
        map.sources[key] = token; ref.emissionStateToken = token;
        if (!ref.emissionStateCleanup) ref.emissionStateCleanup = {动作:release,额外参数:ref};
        if (!ref.生命周期函数列表) ref.生命周期函数列表 = [];
        for (var i:Number = 0; i < ref.生命周期函数列表.length; i++) {
            if (ref.生命周期函数列表[i] === ref.emissionStateCleanup) return;
        }
        ref.生命周期函数列表.push(ref.emissionStateCleanup);
    }
    public static function lookup(ref:Object, adapter:String):Object {
        var actor:MovieClip = ref.自机, world:MovieClip = _root.gameworld;
        var map:Object = actor.__equipmentEmissionStates;
        if (!map || map.actorIdentity !== actor.__equipmentLightIdentity || map.worldIdentity !== world.__equipmentLightIdentity) return null;
        var token:Object = map.sources["$" + ref.装备类型 + ":" + adapter];
        if (!token || !token.active || token.version !== actor.version || token.equipment !== actor[ref.装备类型]
            || !EquipmentLightBridge.matchesMods(actor[ref.装备类型],token.modNames)) return null;
        return token.ref;
    }
    public static function release(ref:Object):Void {
        var token:Object = ref.emissionStateToken;
        if (!token) return;
        token.active = false;
        if (token.map.sources[token.key] === token) delete token.map.sources[token.key];
        ref.emissionStateToken = null;
    }
}
