/**
 * 原体的地面追击、反制换位和黑铁剑追踪五连共用的脚点检查。
 * 坐标与普通移动器一致，Z 表示脚点，_y 可以包含跳跃高度。
 */
class org.flashNight.arki.spatial.move.GroundTargetMotion {
    private static function onMap(x:Number, z:Number):Boolean {
        return typeof x == "number" && typeof z == "number" && isFinite(x) && isFinite(z)
            && isFinite(_root.Xmin) && isFinite(_root.Xmax) && _root.Xmin < _root.Xmax
            && isFinite(_root.Ymin) && isFinite(_root.Ymax) && _root.Ymin < _root.Ymax
            && x >= _root.Xmin && x <= _root.Xmax && z >= _root.Ymin && z <= _root.Ymax;
    }

    private static function openPoint(x:Number, z:Number):Boolean {
        return onMap(x, z) && typeof _root.collisionLayer.hitTest == "function"
            && !_root.collisionLayer.hitTest(x, z, true);
    }

    private static function targetOf(unit:MovieClip):MovieClip {
        var world:MovieClip = _root.gameworld;
        if (!world || unit._parent !== world || world[unit._name] !== unit
                || !(unit.hp > 0) || !isFinite(unit._y)) return undefined;
        var target:MovieClip = world[unit.攻击目标];
        if (!target || target === unit || target._parent !== world || !(target.hp > 0)
                || !openPoint(unit._x, unit.Z轴坐标) || !openPoint(target._x, target.Z轴坐标)) return undefined;
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
        var samples:Number = Math.ceil(Math.max(Math.abs(dx), Math.abs(dz)) / 2);
        // 五连索敌 550，最远偏移 150。超出正常单段预算时取消这段。
        if (samples > 384) return false;
        for (var i:Number = 1; i < samples; i++) {
            if (_root.collisionLayer.hitTest(x0 + dx * i / samples, z0 + dz * i / samples, true)) return false;
        }
        return true;
    }

    public static function lockRush(action:MovieClip):Void {
        var unit:MovieClip = action._parent;
        var target:MovieClip = targetOf(unit);
        action.速度X = action.速度Z = 0;
        action.上速度 = action.下速度 = action.左速度 = action.右速度 = 0;
        action.追踪编号 = NaN;
        action.敌方目标 = target;
        if (!target || !isFinite(action.速度上限) || !isFinite(action.速度下限)
                || !isFinite(action.追踪持续帧) || action.追踪持续帧 <= 0
                || action.速度下限 < 0 || action.速度上限 < 0) return;

        var dx:Number = unit._x - target._x;
        var dz:Number = unit.Z轴坐标 - target.Z轴坐标;
        var speed:Number = Math.max(action.速度下限, Math.min(action.速度上限, Math.abs(dx) / action.追踪持续帧));
        // 远距离保留原斜率；近同列时纵速不超过冲刺速度，也不超过到目标行的距离。
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
        action.追踪编号 = targetID(target);
    }

    public static function advanceRush(action:MovieClip):Void {
        var unit:MovieClip = action._parent;
        var target:MovieClip = targetOf(unit);
        if (!target || !isFinite(action.追踪编号) || target.__dictUID !== action.追踪编号) return;
        var x:Number = unit._x;
        var z:Number = unit.Z轴坐标;
        var up:Number = Math.min(action.上速度, Math.max(0, z - action.锁定脚点Z));
        var down:Number = Math.min(action.下速度, Math.max(0, action.锁定脚点Z - z));
        var nextZ:Number = z - up + down;
        var nextX:Number = x - action.左速度 + action.右速度;
        if (!openSegment(x, z, x, nextZ) || !openSegment(x, nextZ, nextX, nextZ)) return;
        action.攻击时四向移动(up, down, action.左速度, action.右速度);
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
