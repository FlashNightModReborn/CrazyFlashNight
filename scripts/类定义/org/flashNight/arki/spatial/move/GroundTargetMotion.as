/**
 * 特殊位移的目标身份、地面路径与提交。时间轴保留方向、索敌和攻击策略。
 * 坐标与普通移动器一致，Z 表示脚点，_y 可以包含跳跃高度。
 */
class org.flashNight.arki.spatial.move.GroundTargetMotion {
    private static function finite(n:Number):Boolean {
        return typeof n == "number" && isFinite(n);
    }

    private static function onMap(x:Number, z:Number):Boolean {
        return typeof x == "number" && typeof z == "number" && isFinite(x) && isFinite(z)
            && finite(_root.Xmin) && finite(_root.Xmax) && _root.Xmin < _root.Xmax
            && finite(_root.Ymin) && finite(_root.Ymax) && _root.Ymin < _root.Ymax
            && x >= _root.Xmin && x <= _root.Xmax && z >= _root.Ymin && z <= _root.Ymax;
    }

    private static function openPoint(x:Number, z:Number):Boolean {
        return onMap(x, z) && typeof _root.collisionLayer.hitTest == "function"
            && !_root.collisionLayer.hitTest(x, z, true);
    }

    private static function targetOf(unit:MovieClip, action:MovieClip):MovieClip {
        var world:MovieClip = _root.gameworld;
        if (!world || unit._parent !== world || world[unit._name] !== unit
                || !(unit.hp > 0) || !isFinite(unit._y)) return undefined;
        var target:MovieClip = world[unit.攻击目标];
        if (!openPoint(unit._x, unit.Z轴坐标)) {
            if (action) action.motionReject = "invalid-origin";
            return undefined;
        }
        if (action && action.motionReject !== undefined) delete action.motionReject;
        if (!target || target === unit || target._parent !== world || !(target.hp > 0)
                || !openPoint(target._x, target.Z轴坐标)) return undefined;
        return target;
    }

    public static function targetID(target:MovieClip):Number {
        if (!target) return NaN;
        // 使用当前游戏世界的字典。其数值身份在同名 MovieClip 重建时会改变。
        return _global.org.flashNight.naki.DataStructures.Dictionary.getStaticUID(target);
    }

    // 移动按原动作的两条轴段依次执行。先检查整个实际路径，再调用移动器。
    private static function openSegment(x0:Number, z0:Number, x1:Number, z1:Number):Boolean {
        if (!openPoint(x1, z1)) return false;
        var dx:Number = x1 - x0;
        var dz:Number = z1 - z0;
        // 所有调用均传入单轴段。提前保存层与步距，逐样点只计算变化的轴。
        if (dx != 0 && dz != 0) return false;
        var distance:Number = dx == 0 ? dz : dx;
        var samples:Number = Math.ceil(Math.abs(distance) / 2);
        if (samples > 384) return false;
        if (samples <= 1) return true;
        var step:Number = distance / samples;
        var layer:MovieClip = _root.collisionLayer;
        var i:Number;
        if (dx == 0) {
            for (i = 1; i < samples; i++) {
                if (layer.hitTest(x0, z0 + i * step, true)) return false;
            }
        } else {
            for (i = 1; i < samples; i++) {
                if (layer.hitTest(x0 + i * step, z0, true)) return false;
            }
        }
        return true;
    }

    private static function forgetTarget(action:MovieClip):Void {
        action.追踪编号 = NaN;
        action.motionWorld = action.motionActor = action.motionAction = NaN;
        action.motionTargetName = undefined;
        action.敌方目标 = undefined;
    }

    public static function captureTarget(action:MovieClip):MovieClip {
        forgetTarget(action);
        var unit:MovieClip = action._parent;
        var target:MovieClip = targetOf(unit, action);
        if (!target || unit[action._name] !== action || !finite(target._y)) return undefined;
        action.motionWorld = targetID(_root.gameworld);
        action.motionActor = targetID(unit);
        action.motionAction = targetID(action);
        action.motionTargetName = unit.攻击目标;
        action.追踪编号 = targetID(target);
        action.敌方目标 = target;
        return target;
    }

    private static function currentTarget(action:MovieClip, owner:Number):MovieClip {
        var unit:MovieClip = action._parent;
        var world:MovieClip = _root.gameworld;
        if (!finite(owner) || owner !== action.motionAction || owner !== action.__dictUID
                || world.__dictUID !== action.motionWorld || unit.__dictUID !== action.motionActor
                || unit[action._name] !== action || unit.攻击目标 !== action.motionTargetName) return undefined;
        var target:MovieClip = targetOf(unit, action);
        if (!target || target.__dictUID !== action.追踪编号 || !finite(target._y)) return undefined;
        return target;
    }

    public static function captureCandidates(action:MovieClip):Void {
        var list:Array = action._parent.索敌目标列表;
        var ids:Array = action.motionCandidateIDs;
        if (ids === undefined) ids = action.motionCandidateIDs = [];
        ids.length = 0;
        action.motionCandidates = list;
        for (var i:Number = 0; i < list.length; i++) {
            var enemy:MovieClip = list[i].敌人;
            ids[i] = enemy._parent === _root.gameworld && enemy.hp > 0 ? targetID(enemy) : NaN;
        }
    }

    public static function isCandidateCurrent(action:MovieClip, index:Number):Boolean {
        var list:Array = action._parent.索敌目标列表;
        var id:Number = action.motionCandidateIDs[index];
        var enemy:MovieClip = list[index].敌人;
        return list === action.motionCandidates && finite(id) && id === enemy.__dictUID
            && enemy.hp > 0 && enemy._parent === _root.gameworld
            && _root.gameworld[enemy._name] === enemy;
    }

    private static function zeroSpeed(action:MovieClip):Void {
        action.速度X = action.速度Z = 0;
        action.上速度 = action.下速度 = action.左速度 = action.右速度 = 0;
    }

    public static function lockRush(action:MovieClip):Void {
        zeroSpeed(action);
        var target:MovieClip = captureTarget(action);
        if (!target) return;
        var frames:Number = action.追踪持续帧;
        var minSpeed:Number = action.速度下限;
        var cap:Number = action.速度上限;
        var dx:Number = action._parent._x - target._x;
        var dz:Number = action._parent.Z轴坐标 - target.Z轴坐标;
        if (!finite(frames) || frames <= 0 || !finite(minSpeed) || !finite(cap)
                || minSpeed < 0 || cap < minSpeed || !finite(dx) || !finite(dz)) {
            forgetTarget(action);
            return;
        }
        var speed:Number = Math.max(minSpeed, Math.min(cap, Math.abs(dx) / frames));
        var span:Number = Math.max(Math.max(Math.abs(dx), Math.abs(dz)), speed);
        var vz:Number = span > 0 ? speed * (dz / span) : 0;
        action.距离X = dx;
        action.距离Z = dz;
        action.速度X = dx >= 0 ? speed : -speed;
        action.速度Z = vz;
        action.上速度 = Math.max(0, vz);
        action.下速度 = Math.max(0, -vz);
        action.左速度 = dx >= 0 ? speed : 0;
        action.右速度 = dx < 0 ? speed : 0;
        action.锁定脚点Z = target.Z轴坐标;
    }

    public static function chaseScale(dx:Number, cap:Number, frames:Number):Number {
        if (!finite(dx) || !finite(cap) || cap < 0 || !finite(frames) || frames <= 0) return NaN;
        if (cap == 0) return 0;
        var distance:Number = Math.abs(dx);
        var scale:Number = distance / frames > cap ? cap / distance : 1 / frames;
        return isFinite(scale) ? scale : NaN;
    }

    public static function lockChase(action:MovieClip, rx:Number, rz:Number):Void {
        zeroSpeed(action);
        var target:MovieClip = captureTarget(action);
        if (!target) return;
        var dx:Number = action._parent._x - target._x;
        var dz:Number = action._parent.Z轴坐标 - target.Z轴坐标;
        var scale:Number = chaseScale(dx, action.速度上限, action.追踪持续帧);
        var vx:Number = dx * scale * rx;
        var vz:Number = dz * scale * rx * rz;
        if (!finite(vx) || !finite(vz)) {
            forgetTarget(action);
            return;
        }
        action.距离X = dx;
        action.距离Z = dz;
        action.速度X = vx;
        action.速度Z = vz;
    }

    public static function advanceRush(action:MovieClip, xSign:Number, zSign:Number,
            stopAtLockedZ:Boolean, owner:Number):Boolean {
        if (arguments.length == 1) {
            xSign = zSign = 1;
            stopAtLockedZ = true;
        }
        if (arguments.length == 1 || arguments.length == 4) owner = action.motionAction;
        if ((xSign !== 1 && xSign !== -1) || (zSign !== 1 && zSign !== -1)
                || typeof stopAtLockedZ != "boolean") return false;
        var up:Number = action.上速度;
        var down:Number = action.下速度;
        if (stopAtLockedZ) {
            var gap:Number = action._parent.Z轴坐标 - action.锁定脚点Z;
            up = Math.min(up, Math.max(0, gap));
            down = Math.min(down, Math.max(0, -gap));
        }
        return checkedFourWay(action, up * zSign, down * zSign,
                              action.左速度 * xSign, action.右速度 * xSign, owner);
    }

    public static function checkedFourWay(action:MovieClip, up:Number, down:Number,
            left:Number, right:Number, owner:Number):Boolean {
        if (arguments.length == 5) owner = action.motionAction;
        if (!finite(up) || !finite(down) || !finite(left) || !finite(right)
                || !currentTarget(action, owner)) return false;
        var direction:String = left != 0 ? "左" : (right != 0 ? "右" : undefined);
        return tryCommitAxes(action._parent, left != 0 ? -left : right,
                             up != 0 ? -up : down, false, direction);
    }

    public static function followAxes(action:MovieClip, keep:Number, minX:Number,
            maxX:Number, maxZ:Number, owner:Number):Boolean {
        // 瞬时 load 调用同步消费。跨帧调用显式传入元件放置时保存的编号。
        if (arguments.length < 6) owner = action.motionAction;
        var target:MovieClip = currentTarget(action, owner);
        var unit:MovieClip = action._parent;
        if (!target || unit.飞行浮空 || (unit.方向 !== "左" && unit.方向 !== "右")
                || !finite(keep) || (arguments.length > 2 && !finite(minX))
                || (arguments.length > 3 && !finite(maxX)) || (arguments.length > 4 && !finite(maxZ))) return false;
        var facing:Number = unit.方向 === "右" ? 1 : -1;
        var d:Number = facing * (target._x - unit._x) - keep;
        if (minX !== undefined && d < minX) d = minX;
        if (maxX > 0 && d > maxX) d = maxX;
        var dz:Number = target.Z轴坐标 - unit.Z轴坐标;
        if (maxZ > 0) dz = Math.max(-maxZ, Math.min(maxZ, dz));
        return tryCommitAxes(unit, facing * d, dz, true, undefined);
    }

    private static function tryCommitAxes(unit:MovieClip, dx:Number, dz:Number,
            xFirst:Boolean, direction:String):Boolean {
        var x:Number = unit._x;
        var z:Number = unit.Z轴坐标;
        var y:Number = unit._y + dz;
        var endX:Number = x + dx;
        var endZ:Number = z + dz;
        var syncY:Boolean = dz != 0 && unit.浮空;
        var startY:Number;
        if (syncY) {
            if (!finite(unit.起始Y)) return false;
            startY = unit.起始Y + dz;
            if (!finite(startY)) return false;
        }
        if (!onMap(endX, endZ) || !finite(y) || !finite(z - unit._y)
                || Math.abs(dx) > 768 || Math.abs(dz) > 768
                || typeof unit.area.getRect != "function" || typeof unit.aabbCollider.updateFromUnitArea != "function"
                || (direction !== undefined && typeof unit.方向改变 != "function")) return false;
        var depth:Object = _global.org.flashNight.gesh.depth.DepthManager.instance;
        if (dz != 0 && typeof depth.updateDepth != "function") return false;
        var layer:MovieClip = _root.collisionLayer;
        var revision:Number = _global.org.flashNight.arki.collision.CollisionLayerRenderer.revision;
        var midX:Number = xFirst ? endX : x;
        var midZ:Number = xFirst ? z : endZ;
        if ((midX != x || midZ != z) && !openSegment(x, z, midX, midZ)) return false;
        if ((endX != midX || endZ != midZ) && !openSegment(midX, midZ, endX, endZ)) return false;
        if (layer !== _root.collisionLayer || revision !== _global.org.flashNight.arki.collision.CollisionLayerRenderer.revision) return false;

        if (direction !== undefined) unit.方向改变(direction);
        if (dx != 0) unit._x = endX;
        if (dz != 0) {
            unit.Z轴坐标 = endZ;
            unit._y = y;
            if (syncY) unit.起始Y = startY;
            depth.updateDepth(unit, y);
        }
        if (dx != 0 || dz != 0 || direction !== undefined) unit.aabbCollider.updateFromUnitArea(unit);
        return true;
    }

    public static function counterBlink(action:MovieClip, offset:Number):Void {
        var unit:MovieClip = action._parent;
        var target:MovieClip = targetOf(unit);
        if (!target || unit.飞行浮空 || (unit.方向 != "左" && unit.方向 != "右")) return;
        var distance:Number = Math.abs(target._x - unit._x) + offset;
        var x:Number = unit._x + (unit.方向 == "左" ? -distance : distance);
        var z:Number = target.Z轴坐标;
        if (!openPoint(x, z)) return;
        var dz:Number = z - unit.Z轴坐标;
        unit._x = x;
        unit.Z轴坐标 = z;
        unit._y += dz;
        if (unit.浮空 && isFinite(unit.起始Y)) unit.起始Y += dz;
        unit.swapDepths(z);
        unit.aabbCollider.updateFromUnitArea(unit);
    }

    public static function followSlash(unit:MovieClip, offset:Number, id:Number):Void {
        var target:MovieClip = targetOf(unit);
        if (!target || !isFinite(id) || target.__dictUID !== id || (unit.方向 != "左" && unit.方向 != "右")) return;
        var left:Boolean = unit.方向 == "左";
        var x:Number = target._x + (left ? offset : -offset);
        var z:Number = target.Z轴坐标;
        if (!openSegment(unit._x, unit.Z轴坐标, x, unit.Z轴坐标) || !openSegment(x, unit.Z轴坐标, x, z)) return;
        var dx:Number = left ? unit._x - x : x - unit._x;
        var dz:Number = z - unit.Z轴坐标;
        if (dx != 0) unit.移动(unit.方向, dx);
        if (dz != 0 && Math.abs(unit._x - x) <= 0.05) unit.移动(dz < 0 ? "上" : "下", Math.abs(dz));
    }
}
