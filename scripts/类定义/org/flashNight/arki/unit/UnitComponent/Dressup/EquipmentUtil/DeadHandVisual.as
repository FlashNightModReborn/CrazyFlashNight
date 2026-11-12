import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandTuning;

/** 只消费装扮系统当前登记的死者之手素材；不接管共享枪挂点或改写规范引用。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.DeadHandVisual {
    public static function sync(ref:Object, mode:String, hasAlias:Boolean):Void {
        var unit:MovieClip = ref.自机;
        var registry:Object = unit.dressupRegistry;
        if (!ref.visualEntries || ref.visualRegistry !== registry
                || ref.visualRevision !== unit.dressupPlacementVersion) {
            ref.visualEntries = [];
            ref.visualRegistry = registry;
            ref.visualRevision = unit.dressupPlacementVersion;
            // registry 仅在 placement 变化时重建索引，逐帧同步不用 for-in。
            for (var key:String in registry) {
                var candidate:Object = registry[key];
                if (candidate.baseReferenceName == "刀_引用" || candidate.baseReferenceName == "长枪_引用") {
                    ref.visualEntries.push(candidate);
                }
            }
        }
        var gunMode:Boolean = hasAlias && mode == "长枪" && unit.状态 != "攻击模式切换";
        var config:Object = ref.形态配置表[ref.冷兵器模式] || ref.形态配置表["钝器"];
        var blade:MovieClip = null, gun:MovieClip = null;
        var bladeHolder:MovieClip = unit.man.刀.刀;
        var gunHolder:MovieClip = unit.man.枪.枪;
        var entries:Array = ref.visualEntries;
        for (var i:Number = 0; i < entries.length; i++) {
            var entry:Object = entries[i];
            var holder:MovieClip = entry.mc;
            if (!holder._parent || holder._parent._parent !== unit.man) continue;
            var skin:MovieClip = holder[entry.instanceName];
            if (!skin._parent || entry.identity == undefined
                    || skin.__dressupPlacementIdentity !== entry.identity) continue;
            var isGun:Boolean = entry.baseReferenceName == "长枪_引用";
            if (isGun && !hasAlias) continue;
            var state:Object = bind(ref, skin, isGun, entry.identity);
            if (state == null) continue;
            if (isGun) {
                DeadHandTuning.syncGunClip(skin, ref, gunMode);
                if (!gun || holder === gunHolder) gun = skin;
                var marker:MovieClip = skin.枪口位置;
                if (!state.marker && marker) {
                    state.marker = marker; state.createdMarker = true;
                    marker.__deadHandMuzzleOwner = state;
                }
                state.lastMuzzleX = marker._x; state.lastMuzzleY = marker._y;
            } else {
                DeadHandTuning.syncBladeClip(skin, ref, !gunMode, config);
                if (!blade || holder === bladeHolder) blade = skin;
            }
            state.lastVisible = skin._visible; state.lastRotation = skin._rotation;
            state.lastX = skin._x; state.lastY = skin._y;
        }
        ref.长枪视觉 = gun;
        ref.武器 = gunMode ? gun : blade;
    }

    private static function bind(ref:Object, skin:MovieClip, isGun:Boolean, identity:Object):Object {
        var state:Object = skin.__deadHandVisualState;
        if (state != null) return state.owner === ref && state.placement === identity ? state : null;
        state = {
            owner:ref, skin:skin, placement:identity,
            visible:skin._visible, rotation:skin._rotation, x:skin._x, y:skin._y,
            marker:null, createdMarker:false
        };
        if (isGun && skin.枪口位置) {
            var marker:MovieClip = skin.枪口位置;
            if (marker.__deadHandMuzzleOwner != undefined) return null;
            state.marker = marker; state.muzzleX = marker._x; state.muzzleY = marker._y;
            marker.__deadHandMuzzleOwner = state;
        }
        skin.__deadHandVisualState = state;
        if (!ref.visualStates) ref.visualStates = [];
        ref.visualStates.push(state);
        return state;
    }

    public static function release(ref:Object):Void {
        var states:Array = ref.visualStates;
        var count:Number = states ? states.length : 0;
        while (count--) {
            var state:Object = states[count];
            var skin:MovieClip = state.skin;
            if (!skin._parent || skin.__deadHandVisualState !== state
                    || skin.__dressupPlacementIdentity !== state.placement) continue;
            // 后来的写入者已改变的属性保持原值；同路径重建也不能恢复到新素材。
            if (skin._visible === state.lastVisible) skin._visible = state.visible;
            if (skin._rotation === state.lastRotation) skin._rotation = state.rotation;
            if (skin._x === state.lastX) skin._x = state.x;
            if (skin._y === state.lastY) skin._y = state.y;
            var marker:MovieClip = state.marker;
            if (marker.__deadHandMuzzleOwner === state) {
                if (state.createdMarker) {
                    if (marker._x === state.lastMuzzleX && marker._y === state.lastMuzzleY) marker.removeMovieClip();
                } else {
                    if (marker._x === state.lastMuzzleX) marker._x = state.muzzleX;
                    if (marker._y === state.lastMuzzleY) marker._y = state.muzzleY;
                }
                delete marker.__deadHandMuzzleOwner;
            }
            delete skin.__deadHandVisualState;
        }
        if (states) states.length = 0;
        ref.visualEntries = null; ref.visualRegistry = null;
        ref.长枪视觉 = ref.武器 = null;
    }
}