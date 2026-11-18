import org.flashNight.arki.scene.Cf6VehicleCombat;

/** The two following rounds of each accepted A07 barrel shot. */
class org.flashNight.arki.scene.Cf6RoadsterBurst {
    private static var slotsPerGun:Number = 8;
    private static var flightFrames:Number = 14;

    public static function open(s:Object):Void {
        var name:String = "__cf6RoadsterTrails" + s.serial;
        var layer:MovieClip = s.world.createEmptyMovieClip(name, s.world.getNextHighestDepth());
        if (typeof layer != "movieclip") return;
        layer.__cf6VehicleOwner = s.token;
        layer._xscale = layer._yscale = 100 * s.spec.scale;
        var slots:Array = [];
        for (var i:Number = 0; i < 2 * slotsPerGun; i++) {
            var trail:MovieClip = layer.createEmptyMovieClip("trail" + i, i + 1);
            trail.lineStyle(1.15, 0xFFC774, 80);
            trail.moveTo(-22, 0);
            trail.lineTo(0, 0);
            trail._visible = false;
            slots.push({due:0, age:0, clip:trail});
        }
        var flashes:Array = [];
        for (i = 0; i < 2; i++) {
            var spark:MovieClip = layer.createEmptyMovieClip("spark" + i, slots.length + i + 1);
            spark.lineStyle(1.15, 0xFFE8AE, 70);
            spark.moveTo(-5, 1);
            spark.lineTo(0, 0);
            spark._visible = false;
            flashes.push({until:0, x:0, y:0, clip:spark});
        }
        s.roadsterBurst = {layer:layer, slots:slots, active:0, painted:false,
            flashes:flashes};
    }

    public static function schedule(s:Object, barrel:Number, dx:Number, dy:Number):Void {
        var state:Object = s.roadsterBurst;
        if (state == null) return;
        var slots:Array = state.slots;
        var first:Object, second:Object;
        var start:Number = barrel * slotsPerGun;
        for (var i:Number = start; i < start + slotsPerGun; i++) {
            var slot:Object = slots[i];
            if (slot.due !== 0) continue;
            if (first == null) first = slot;
            else { second = slot; break; }
        }
        if (second == null) return;
        // Use the same integer remainder as Cf6VehicleRules (1000 units per
        // tick). Successive 150-ms groups alternate the fractional lead step.
        var credit:Number = s.rules.fireCredit;
        first.due = s.age + Math.ceil((1500 - credit) / 1000);
        second.due = s.age + Math.ceil((3000 - credit) / 1000);
        first.dx = second.dx = dx;
        first.dy = second.dy = dy;
        first.age = second.age = 0;
        state.active += 2;
    }

    public static function advance(s:Object):Void {
        var state:Object = s.roadsterBurst;
        if (state == null) return;
        var slots:Array = state.slots, flashes:Array = state.flashes;
        var frame:Number = s.age;
        if (state.active === 0 && !state.painted) return;
        var layer:MovieClip = state.layer;
        if (!Cf6VehicleCombat.owned(s, layer)) { s.roadsterBurst = null; return; }
        state.painted = false;

        var data:Object = s.data;
        var box:Array = data.bullet;
        var scale:Number = s.spec.scale;
        var hero:MovieClip = s.actorAdapter.hero;
        var hx:Number = hero._x / scale, hy:Number = hero.Z轴坐标 / scale;
        var phase:String = s.rules.phase;
        var road:Boolean = phase === "road" || phase === "tail";
        var boss:MovieClip = s.boss;
        var allowFlash:Boolean = phase === "boss" && Cf6VehicleCombat.owned(s, boss) && boss.hp > 0;
        if (allowFlash && layer.getDepth() <= boss.getDepth()) layer.swapDepths(s.world.getNextHighestDepth());
        var bx:Number = allowFlash ? boss._x / scale : 0;
        var by:Number = allowFlash ? boss._y / scale : 0;
        var oldBX:Number = s.bossPreviousX, oldBY:Number = s.bossPreviousY;
        var bossBox:Array = data.boss;
        var bossLeft:Number = (oldBX < bx ? oldBX : bx) + bossBox[0];
        var bossRight:Number = (oldBX > bx ? oldBX : bx) + bossBox[2];
        var back:Number = box[0], tip:Number = box[2], centerY:Number = (box[1] + box[3]) * 0.5;
        var lifetime:Number = flightFrames;
        for (var i:Number = 0; i < 2 * slotsPerGun; i++) {
            var slot:Object = slots[i];
            if (slot.due === 0 || slot.due > frame) continue;
            var barrel:Number = i < slotsPerGun ? 0 : 1;
            var dx:Number = slot.dx, dy:Number = slot.dy;
            var trail:MovieClip = slot.clip;
            if (slot.age === 0) {
                var muzzle:Array = data.muzzles[barrel];
                slot.x = hx + muzzle[0]; slot.y = hy + muzzle[1];
                slot.wallAt = wallFrame(box, data.walls, slot.x, slot.y, dx * lifetime, dy * lifetime);
                trail._rotation = Math.atan2(dy, dx) * 180 / Math.PI;
            }
            var ox:Number = slot.x, oy:Number = slot.y;
            var nx:Number = ox + dx, ny:Number = oy + dy;
            var stopTime:Number = slot.wallAt - slot.age;
            if (stopTime > 1) stopTime = 2;
            if (road) stopTime = hitRoad(s, box, ox, oy, nx, ny, stopTime);
            // The swept X bounds only skip non-overlapping trails. The same
            // relative-motion slab test decides an actual contact.
            if (allowFlash && (ox < nx ? nx : ox) + tip >= bossLeft
                    && (ox < nx ? ox : nx) + back <= bossRight) {
                var bt:Number = Cf6VehicleCombat.hitTime(box, ox, oy, nx, ny, bossBox, oldBX, oldBY, bx, by);
                if (bt < stopTime) {
                    var mark:Object = flashes[barrel];
                    mark.x = ox + dx * bt + tip;
                    var frontY:Number = oldBY + (by - oldBY) * bt;
                    mark.y = Math.max(frontY + bossBox[1], Math.min(frontY + bossBox[3], oy + dy * bt + centerY));
                    mark.until = frame + 2;
                    stopTime = bt;
                }
            }
            slot.age++;
            slot.x = nx; slot.y = ny;
            if (stopTime < 2 || slot.age >= lifetime || Math.abs(nx - hx) > 800 || Math.abs(ny - hy) > 800) {
                trail._visible = false;
                slot.due = 0;
                state.active--;
                continue;
            }
            trail._x = nx + tip;
            trail._y = ny + centerY;
            if (slot.age === 1) trail._visible = true;
            state.painted = true;
        }
        for (i = 0; i < 2; i++) {
            var flash:Object = flashes[i];
            var spark:MovieClip = flash.clip;
            if (flash.until <= frame) {
                if (spark._visible) spark._visible = false;
                continue;
            }
            if (flash.until === frame + 2) {
                spark._x = flash.x;
                spark._y = flash.y;
                spark._visible = true;
            }
            state.painted = true;
        }
    }

    // The four authored walls are static throughout A07. Compute the first
    // contact once on birth and reuse it while sweeping the moving Boss.
    private static function wallFrame(box:Array, walls:Array, x:Number, y:Number,
                                      travelX:Number, travelY:Number):Number {
        var nx:Number = x + travelX, ny:Number = y + travelY;
        var count:Number = walls.length, first:Number = 2;
        for (var i:Number = 0; i < count; i++) {
            var time:Number = Cf6VehicleCombat.hitTime(box, x, y, nx, ny, walls[i], 0, 0, 0, 0);
            if (time < first) first = time;
        }
        return first * flightFrames;
    }

    private static function hitRoad(s:Object, box:Array, ox:Number, oy:Number,
                                    nx:Number, ny:Number, stopTime:Number):Number {
        var actors:Array = s.actors, scale:Number = s.spec.scale;
        var count:Number = actors.length, data:Object = s.data;
        var blocker:Object;
        for (var i:Number = 0; i < count; i++) {
            var row:Object = actors[i];
            var clip:MovieClip = row.clip;
            if (row.kind === "raider" || row.closed || row.resolved || !Cf6VehicleCombat.owned(s, clip)) continue;
            var time:Number = Cf6VehicleCombat.hitTime(box, ox, oy, nx, ny, data[row.kind],
                row.previousX, row.previousY, clip._x / scale, clip._y / scale);
            if (time < stopTime) { stopTime = time; blocker = row; }
        }
        // A raider terminates once, then subsequent sweeps skip its corpse.
        // Hard bodies and world walls retain occlusion for the extra rounds.
        for (i = 0; i < count; i++) {
            row = actors[i]; clip = row.clip;
            if (row.kind !== "raider" || row.closed || row.resolved || !Cf6VehicleCombat.owned(s, clip)) continue;
            time = Cf6VehicleCombat.hitTime(box, ox, oy, nx, ny, data.raider,
                row.previousX, row.previousY, clip._x / scale, clip._y / scale);
            if (time < stopTime) Cf6VehicleCombat.hitRoad(s, row, false);
        }
        if (blocker != null) Cf6VehicleCombat.hitRoad(s, blocker, false);
        return stopTime;
    }

    public static function clear(s:Object):Void {
        var state:Object = s.roadsterBurst;
        if (state == null) return;
        var slots:Array = state.slots, flashes:Array = state.flashes;
        var ownsLayer:Boolean = Cf6VehicleCombat.owned(s, state.layer);
        for (var i:Number = 0; i < 2 * slotsPerGun; i++) {
            slots[i].due = 0;
            if (ownsLayer) slots[i].clip._visible = false;
        }
        state.active = 0;
        for (i = 0; i < 2; i++) {
            flashes[i].until = 0;
            if (ownsLayer) flashes[i].clip._visible = false;
        }
        state.painted = false;
    }

    public static function close(s:Object):Void {
        var state:Object = s.roadsterBurst;
        if (state == null) return;
        if (Cf6VehicleCombat.owned(s, state.layer)) state.layer.removeMovieClip();
        s.roadsterBurst = null;
    }
}
