import org.flashNight.arki.render.EquipmentLightBridge;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PlacementVisual;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentTick;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightDefense;

// One lifecycle owns the authored beam's visibility; native only supplies illumination.
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController {
    public static function initialize(ref:Object, param:Object):Boolean {
        dispose(ref);
        if (param == undefined) param = {};
        if (param.kind != "flashlight" && param.kind != "laser") return false;
        var kind:Number = String(param.kind) == "flashlight" ? 1 : 2;
        if (!EquipmentLightBridge.bind(ref, kind, param)) return false;
        EquipmentLightDefense.bind(ref, param);
        ref.lightContainer = ref.装备类型 + "_引用";
        ref.lightAnchorPath = String(param.anchor != undefined ? param.anchor
            : (kind == 1 ? "手电口" : "激光发射器.出光位置")).split(".");
        ref.lightBeamPath = param.beamPath != undefined ? String(param.beamPath).split(".") : null;
        ref.lightFallback = param.fallbackVisual !== false;
        if (!ref.lightCleanup) ref.lightCleanup = {动作:dispose, 额外参数:ref};
        if (!ref.生命周期函数列表) ref.生命周期函数列表 = [];
        var registered:Boolean = false;
        for (var i:Number = 0; i < ref.生命周期函数列表.length; i++) {
            if (ref.生命周期函数列表[i] === ref.lightCleanup) registered = true;
        }
        if (!registered) ref.生命周期函数列表.push(ref.lightCleanup);
        ref.lightPlacement = PlacementVisual.hookVisualUpdate(ref.自机, ref.lightContainer, ref, update, ref);
        ref.lightActionChannel = ref.lightContainer + ":light";
        ref.自机.dispatcher.subscribe(ref.lightActionChannel, ref.lightPlacement, ref);
        update(ref);
        return true;
    }

    // A routed action can move the SAME equipped light onto its authored prop.
    // Keep firearm/dressup references untouched; the lease belongs to this man
    // and a plain cast token, so an old unload cannot retarget a replacement.
    public static function setActionVisual(actor:MovieClip, slot:String, owner:Object, visual:MovieClip, sync:Function):Void {
        var man:MovieClip = actor.man;
        if (!owner || !man._parent || visual._parent !== man) return;
        if (!man.__equipmentLightVisuals) man.__equipmentLightVisuals = {};
        var lease:Object = man.__equipmentLightVisuals[slot];
        if (!lease || lease.owner !== owner) {
            lease = {owner:owner, item:actor[slot], visual:visual, sync:sync};
            man.__equipmentLightVisuals[slot] = lease;
        }
        if (lease.item !== actor[slot]) return;
        lease.visual = visual;
        visual.__equipmentLightVisualOwner = owner;
        actor.dispatcher.publish(slot + "_引用:light");
    }

    public static function clearActionVisual(actor:MovieClip, slot:String, owner:Object):Void {
        var leases:Object = actor.man.__equipmentLightVisuals;
        var lease:Object = leases[slot];
        if (!lease || lease.owner !== owner) return;
        if (lease.visual.__equipmentLightVisualOwner === owner) delete lease.visual.__equipmentLightVisualOwner;
        delete leases[slot];
        actor.dispatcher.publish(slot + "_引用:light");
    }

    public static function beamLoaded(beam:MovieClip, slot:String):Void {
        // A replacement man can expose its named clips before their complete
        // parent transform chain is live. Resample in the authored load flush,
        // in the same render frame, without retaining a stale MovieClip path.
        var actor:MovieClip = beam._parent;
        while (actor && !actor.dispatcher) actor = actor._parent;
        if (actor._parent) actor.dispatcher.publish(slot + "_引用:light");
    }

    private static function resolve(container:MovieClip, path:Array):MovieClip {
        if (!path) return null;
        var result:MovieClip = container;
        for (var i:Number = 0; i < path.length; i++) result = result[path[i]];
        return result;
    }

    private static function visible(gun:MovieClip, actor:MovieClip):Boolean {
        var node:MovieClip = gun;
        while (node && node !== actor) {
            if (!node._visible) return false;
            node = node._parent;
        }
        return node === actor && actor._visible;
    }

    public static function tick(ref:Object):Void {
        if (!EquipmentTick.open(ref)) return;
        update(ref);
    }

    public static function update(ref:Object):Void {
        if (!EquipmentLightBridge.isValid(ref)) { dispose(ref); return; }
        var actor:MovieClip = ref.自机;
        var gun:MovieClip = actor[ref.lightContainer];
        var lease:Object = actor.man.__equipmentLightVisuals[ref.装备类型];
        if (lease && lease.item === ref.equipmentLight.equipment
                && lease.visual._parent === actor.man
                && lease.visual.__equipmentLightVisualOwner === lease.owner) {
            gun = lease.visual;
            if (lease.sync != undefined) lease.sync(lease.owner);
        }
        if (!EquipmentLightBridge.isDrawn(ref) || !gun._parent || !visible(gun, actor)) {
            EquipmentLightDefense.setActive(ref, false);
            EquipmentLightBridge.hide(ref); hideBeam(ref); return;
        }
        var outlet:MovieClip = resolve(gun, ref.lightAnchorPath);
        if (!outlet._parent) outlet = gun.枪口位置;
        EquipmentLightDefense.setActive(ref, outlet._parent != undefined);
        if (!EquipmentLightBridge.sample(ref, outlet, 1, gun)) { hideBeam(ref); return; }
        var beam:MovieClip = resolve(gun, ref.lightBeamPath);
        if (!beam._parent && ref.lightFallback) {
            if (!ref.lightGenerated._parent || ref.lightGenerated._cf7EquipmentLightOwner !== ref) {
                releaseBeam(ref);
                beam = gun.createEmptyMovieClip("__equipmentLight_" + ref.equipmentLight.id, gun.getNextHighestDepth());
                beam._cf7EquipmentLightOwner = ref;
                ref.lightGenerated = beam;
                drawFallback(beam, ref.equipmentLight);
            } else beam = ref.lightGenerated;
            positionFallback(beam, gun, ref.equipmentLight);
        }
        if (!beam._parent) return;
        if (ref.lightBeam !== beam) releaseBeam(ref);
        if (beam._cf7EquipmentLightOwner && beam._cf7EquipmentLightOwner !== ref) return;
        beam._cf7EquipmentLightOwner = ref;
        ref.lightBeam = beam;
        beam._visible = true;
    }

    private static function drawFallback(beam:MovieClip, entry:Object):Void {
        var color:Number = entry.beamColor;
        if (entry.kind == 1) {
            beam.beginGradientFill("linear", [color, color], [6, 0], [0, 255],
                {matrixType:"box", x:0, y:-entry.width, w:250, h:entry.width * 2, r:0});
            beam.moveTo(0, 0); beam.lineTo(250, -entry.width); beam.lineTo(250, entry.width);
            beam.lineTo(0, 0); beam.endFill();
        } else {
            beam.lineStyle(5, color, 8); beam.moveTo(0, 0); beam.lineTo(250, 0);
            beam.lineStyle(1.5, color, 45); beam.moveTo(0, 0); beam.lineTo(250, 0);
            beam.lineStyle(0.3, 16777215, 45); beam.moveTo(0, 0); beam.lineTo(250, 0);
        }
        beam._visible = false;
    }

    private static function positionFallback(beam:MovieClip, gun:MovieClip, entry:Object):Void {
        var origin:Object = {x:entry.x, y:entry.y};
        var end:Object = {x:entry.x + entry.dx * entry.length, y:entry.y + entry.dy * entry.length};
        _root.gameworld.localToGlobal(origin); _root.gameworld.localToGlobal(end);
        gun.globalToLocal(origin); gun.globalToLocal(end);
        var dx:Number = end.x - origin.x, dy:Number = end.y - origin.y;
        beam._x = origin.x; beam._y = origin.y;
        beam._rotation = Math.atan2(dy, dx) * 180 / Math.PI;
        beam._xscale = Math.sqrt(dx * dx + dy * dy) / 250 * 100;
    }

    private static function hideBeam(ref:Object):Void {
        if (ref.lightBeam._cf7EquipmentLightOwner === ref) ref.lightBeam._visible = false;
    }

    private static function releaseBeam(ref:Object):Void {
        var beam:MovieClip = ref.lightBeam;
        if (beam._parent && beam._cf7EquipmentLightOwner === ref) {
            if (beam === ref.lightGenerated) beam.removeMovieClip();
            else { beam._visible = false; delete beam._cf7EquipmentLightOwner; }
        }
        ref.lightBeam = null;
    }

    public static function dispose(ref:Object):Void {
        if (!ref) return;
        EquipmentLightDefense.release(ref);
        EquipmentLightBridge.release(ref);
        releaseBeam(ref);
        if (ref.lightGenerated._parent && ref.lightGenerated._cf7EquipmentLightOwner === ref) ref.lightGenerated.removeMovieClip();
        ref.lightGenerated = null;
        if (ref.lightPlacement) ref.自机.dispatcher.unsubscribe(ref.lightContainer, ref.lightPlacement, ref);
        if (ref.lightPlacement) ref.自机.dispatcher.unsubscribe(ref.lightActionChannel, ref.lightPlacement, ref);
        ref.lightPlacement = null;
        // Teardown iterates the shared callback array. Never splice it from a callback.
    }
}
