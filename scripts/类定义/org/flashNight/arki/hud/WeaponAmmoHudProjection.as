import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;

/** 纯读投影：来源、余额与本发风险由 AS2 提供，旧 Host 未索取时不发送。 */
class org.flashNight.arki.hud.WeaponAmmoHudProjection {
    public static function read(unit:Object, slot:String, previous:Object):Object {
        var value:Object = unit[slot].value;
        var state:Object = value.ammoState;
        var cap:Number = WeaponAmmoRuntime.capacity(unit, slot);
        if (!state || state.v != 1 || !(cap > 0)) return null;
        var loaded:Number = WeaponAmmoRuntime.count(cap - value.shot);
        var ordinary:Number = WeaponAmmoRuntime.normal(value, cap);
        var chamber:Number = WeaponAmmoRuntime.count(state.chamber);
        var ghost:Number = WeaponAmmoRuntime.count(state.ghost);
        var reward:Number = WeaponAmmoRuntime.count(state.reward);
        var reserve:Number = WeaponAmmoRuntime.reserve(unit, slot);
        var spread:Number = WeaponAmmoRuntime.ghostMultiplier(unit, slot);
        var overflow:Number = Math.max(0, loaded - cap);
        if (previous != null && previous.capacity === cap && previous.loaded === loaded
                && previous.normal === ordinary && previous.chamber === chamber
                && previous.ghost === ghost && previous.reward === reward && previous.reserve === reserve
                && previous.spread === spread && previous.overflow === overflow) return previous;
        return {capacity:cap, loaded:loaded, normal:ordinary, chamber:chamber,
            ghost:ghost, reward:reward, reserve:reserve, spread:spread, overflow:overflow};
    }
}
