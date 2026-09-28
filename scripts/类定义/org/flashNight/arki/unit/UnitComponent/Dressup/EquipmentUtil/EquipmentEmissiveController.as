import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentEmissionState;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentTick;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PlacementVisual;

// Does not alter authored art, battle skills, equipment stats or persistent data.
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentEmissiveController {
    public static function initialize(ref:Object,param:Object):Boolean {
        dispose(ref);
        if (!param || (param.group != "body" && param.group != "blade")) return false;
        var adapter:String = param.adapter == undefined ? "static" : String(param.adapter);
        if (adapter != "static" && adapter != "blood" && adapter != "vocalist" && adapter != "libra"
            && adapter != "inductor" && adapter != "lion" && adapter != "capricorn") return false;
        if (!EquipmentLightBridge.bind(ref,0,param)) return false;
        ref.emissiveAdapter = adapter;
        ref.emissiveAnchor = param.anchor == undefined ? "刀口位置1" : String(param.anchor);
        if (!ref.emissiveCleanup) ref.emissiveCleanup = {动作:dispose,额外参数:ref};
        if (!ref.生命周期函数列表) ref.生命周期函数列表 = [];
        var present:Boolean = false;
        for (var i:Number = 0; i < ref.生命周期函数列表.length; i++) if (ref.生命周期函数列表[i] === ref.emissiveCleanup) present = true;
        if (!present) ref.生命周期函数列表.push(ref.emissiveCleanup);
        if (param.group == "blade") ref.emissivePlacement = PlacementVisual.hookVisualUpdate(ref.自机,ref.装备类型 + "_引用",ref,update,ref);
        update(ref); return true;
    }
    public static function tick(ref:Object):Void {
        if (!EquipmentTick.open(ref)) return;
        update(ref);
    }
    private static function releaseWeapon(ref:Object):Void {
        var weapon:MovieClip = ref.emissiveWeapon;
        if (weapon._parent && weapon.__equipmentEmissiveOwner === ref) delete weapon.__equipmentEmissiveOwner;
        ref.emissiveWeapon = null;
    }
    public static function update(ref:Object):Void {
        if (!EquipmentLightBridge.isValid(ref)) { dispose(ref); return; }
        // Static armor is registered once. Central snapshot validation handles
        // motion, visibility, death, replacement and disconnect for the actor.
        if (ref.equipmentLight.role == "body") return;
        if (!EquipmentLightBridge.isDrawn(ref)) { EquipmentLightBridge.hide(ref); releaseWeapon(ref); return; }
        var entry:Object = ref.equipmentLight;
        var frozen:Boolean = _root.暂停 && entry.sampled;
        // Reconnect/reset while paused re-registers the frozen sample, without
        // advancing a conditional visual state or leaving the light absent.
        var strength:Number = frozen ? entry.strength : 1, color:Number = frozen ? entry.color : entry.baseColor;
        var adapter:String = ref.emissiveAdapter;
        if (!frozen && adapter != "static") {
            var state:Object = EquipmentEmissionState.lookup(ref,adapter);
            if (!state) strength = 0;
            else if (adapter == "blood") strength = state.bloodActive && state.bloodDrawn ? 1 : 0;
            else if (adapter == "vocalist") {
                strength = state.weaponMode == "光剑" ? Math.max(0,Math.min(1,(state.animFrame-1)/Math.max(1,state.animDuration-1))) : 0;
            } else if (adapter == "libra") {
                if (state.当前形态 == "攻势形态") color = 16736336;
                else if (state.当前形态 == "守御形态") color = 16765808;
                else { color = 8366847; strength = state.isSkillInCd ? 0.6 : 0; }
            } else if (adapter == "inductor") {
                strength = Math.max(0,Math.min(1,(state.当前帧-1)/Math.max(1,state.动画时长-1)));
                color = state.过载值 >= state.过载阈值 ? 16736336 : 7331583;
            } else if (adapter == "lion") strength = state.draw === true ? 1 : 0;
            else if (adapter == "capricorn") strength = state.draw > 0 ? 1 : 0;
        }
        if (!(strength > 0) || !isFinite(strength)) { EquipmentLightBridge.hide(ref); releaseWeapon(ref); return; }
        var weapon:MovieClip = ref.自机[ref.装备类型 + "_引用"];
        var anchor:MovieClip = weapon[ref.emissiveAnchor];
        if (!anchor._parent) anchor = weapon;
        if (!EquipmentLightBridge.sampleRadial(ref,anchor,strength,color)) { releaseWeapon(ref); return; }
        if (entry.role == "blade") {
            if (ref.emissiveWeapon !== weapon) releaseWeapon(ref);
            if (!weapon.__equipmentEmissiveOwner || weapon.__equipmentEmissiveOwner === ref) {
                weapon.__equipmentEmissiveOwner = ref; ref.emissiveWeapon = weapon;
            }
        }
    }
    // A whitelisted weapon contributes one envelope, regardless of trail segment
    // count or quality. Reuse the renderer's sampled edges instead of resampling.
    public static function noteTrail(actor:MovieClip,weapon:MovieClip,trail:Array,map:MovieClip):Void {
        var ref:Object = weapon.__equipmentEmissiveOwner;
        if (!ref || _root.暂停 || !trail.length || !EquipmentLightBridge.isDrawn(ref)
            || !(actor.man.兵器攻击标签 || actor.状态 == "兵器攻击")) return;
        var entry:Object = ref.equipmentLight;
        if (!entry.sampled || entry.kind != 0 || entry.role != "blade") return;
        var first:Object = trail[0], last:Object = trail[trail.length-1], point:Object = entry.forward;
        point.x = (first.edge1.x+first.edge2.x+last.edge1.x+last.edge2.x)*0.25;
        point.y = (first.edge1.y+first.edge2.y+last.edge1.y+last.edge2.y)*0.25;
        map.localToGlobal(point); _root.gameworld.globalToLocal(point);
        if (!isFinite(point.x+point.y) || Math.abs(point.x)>1000000 || Math.abs(point.y)>1000000) return;
        entry.trailX = point.x; entry.trailY = point.y; entry.trailTick = _root.帧计时器.当前帧数;
    }
    public static function dispose(ref:Object):Void {
        if (!ref) return;
        releaseWeapon(ref); EquipmentLightBridge.release(ref);
        if (ref.emissivePlacement) ref.自机.dispatcher.unsubscribe(ref.装备类型 + "_引用",ref.emissivePlacement,ref);
        ref.emissivePlacement = null;
    }
}
