import org.flashNight.gesh.depth.DepthManager;

/** 一文字落雷的无追踪移动。小步检测墙体，并在当前地图脚点边界内停止。 */
class org.flashNight.arki.unit.Action.Skill.IchimonjiMovement {
    public static function moveFree(unit:MovieClip):Void {
        if (unit == undefined || unit._parent !== _root.gameworld) return;
        if (unit._name != _root.控制目标) {moveAxis(unit, unit.方向 == "左" ? -1 : 1, 0, 25);return;}
        var vertical:Boolean = unit.上行 || unit.下行;
        var horizontal:Boolean = unit.左行 || unit.右行;
        if (vertical) moveAxis(unit, 0, unit.上行 ? -1 : 1, 37.5);
        if (horizontal) moveAxis(unit, unit.左行 ? -1 : 1, 0, 75);
        if (!vertical && !horizontal) moveAxis(unit, unit.方向 == "左" ? -1 : 1, 0, 25);
    }

    private static function finite(value):Boolean {
        return typeof value == "number" && (value - value) == 0;
    }

    private static function moveAxis(unit:MovieClip, dx:Number, dz:Number, distance:Number):Void {
        var minX:Number = _root.Xmin, maxX:Number = _root.Xmax;
        var minZ:Number = _root.Ymin, maxZ:Number = _root.Ymax;
        if (!finite(minX) || !finite(maxX) || !finite(minZ) || !finite(maxZ)
                || !(maxX > minX) || !(maxZ > minZ)
                || !finite(unit._x) || !finite(unit.Z轴坐标) || !finite(unit._y)
                || typeof _root.collisionLayer.hitTest != "function") return;
        var count:Number = Math.ceil(distance), step:Number = distance / count;
        var oldZ:Number = unit.Z轴坐标, moved:Boolean = false;
        // 最多75次一像素步进，只用于本战技六帧自由移动，不改变全局Mover。
        for (var i:Number = 0; i < count; i++) {
            var x:Number = unit._x + dx * step;
            var z:Number = unit.Z轴坐标 + dz * step;
            if (x < minX || x > maxX || z < minZ || z > maxZ
                    || _root.collisionLayer.hitTest(x, z, true)) break;
            unit._x = x;unit.Z轴坐标 = z;moved = true;
        }
        if (!moved) return;
        // 保留已有浮空高度；排序和碰撞仍以真实脚点更新。
        unit._y += unit.Z轴坐标 - oldZ;
        unit.aabbCollider.updateFromUnitArea(unit);
        if (unit.Z轴坐标 != oldZ) DepthManager.instance.updateDepth(unit, unit.Z轴坐标);
    }
}
