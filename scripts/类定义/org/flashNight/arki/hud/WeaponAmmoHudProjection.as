import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;

/** 纯读投影：来源、余额与本发风险由 AS2 提供，旧 Host 未索取时不发送。 */
class org.flashNight.arki.hud.WeaponAmmoHudProjection {
    public static function read(unit:Object, slot:String, previous:Object):Object {
        var value:Object = unit[slot].value;
        if (value == null && slot == "长枪副武器") value = unit.长枪副武器状态;
        var cap:Number = WeaponAmmoRuntime.capacity(unit, slot);
        if (!(cap > 0) && slot == "长枪副武器") cap = WeaponAmmoRuntime.count(unit.长枪副武器状态.capacity);
        if (value == null || !(cap > 0)) return null;
        var state:Object = value.ammoState;
        var loaded:Number;
        var ordinary:Number;
        var chamber:Number = 0;
        var ghost:Number = 0;
        var reward:Number = 0;
        var reserve:Number = 0;
        var spread:Number = 1;
        if (state && state.v == 1) {
            loaded = WeaponAmmoRuntime.count(cap - value.shot);
            ordinary = WeaponAmmoRuntime.normal(value, cap);
            chamber = WeaponAmmoRuntime.count(state.chamber);
            ghost = WeaponAmmoRuntime.count(state.ghost);
            reward = WeaponAmmoRuntime.count(state.reward);
            reserve = WeaponAmmoRuntime.reserve(unit, slot);
            spread = WeaponAmmoRuntime.ghostMultiplier(unit, slot);
        } else {
            var rawShot:Number = Number(value.shot);
            if (!isFinite(rawShot)) return null;
            loaded = Math.min(cap * 2, WeaponAmmoRuntime.count(cap - rawShot));
            ordinary = Math.min(cap, loaded);
            reward = Math.max(0, loaded - ordinary);
            reserve = unit[slot] != null ? WeaponAmmoRuntime.reserve(unit, slot) : 0;
        }
        var overflow:Number = Math.max(0, loaded - cap);
        if (previous != null && previous.capacity === cap && previous.loaded === loaded
                && previous.normal === ordinary && previous.chamber === chamber
                && previous.ghost === ghost && previous.reward === reward && previous.reserve === reserve
                && previous.spread === spread && previous.overflow === overflow) return previous;
        return {capacity:cap, loaded:loaded, normal:ordinary, chamber:chamber,
            ghost:ghost, reward:reward, reserve:reserve, spread:spread, overflow:overflow};
    }
}