import org.flashNight.sara.util.*;
import org.flashNight.arki.component.Collider.*;

class org.flashNight.sara.util.RectanglePointSet extends PointSet {
    private var p1:Vector;
    private var p2:Vector;
    private var p3:Vector;
    private var p4:Vector;

    public function RectanglePointSet(p1:Vector, p2:Vector, p3:Vector, p4:Vector) {
        super();
        this.p1 = p1;
        this.p2 = p2;
        this.p3 = p3;
        this.p4 = p4;
    }

    // 重写size()，固定为4
    public function size():Number {
        return 4;
    }

    // 重写addPoint：不允许添加
    public function addPoint(x:Number, y:Number):Void {
        trace("RectanglePointSet: 已有4点，无法添加更多点。");
    }

    // 重写removePoint：不允许移除
    public function removePoint(index:Number):Void {
        trace("RectanglePointSet: 不允许移除点。");
    }

    public function setRectangle(p1:Vector, p2:Vector, p3:Vector, p4:Vector):Void {
        this.p1 = p1;
        this.p2 = p2;
        this.p3 = p3;
        this.p4 = p4;
    }

    public function getPoint(index:Number):Vector {
        switch(index) {
            case 0: return p1;
            case 1: return p2;
            case 2: return p3;
            case 3: return p4;
            default: return null;
        }
    }

    public function getCentroid():Vector {
        // 直接计算4点平均值
        var cx:Number = (p1.x + p2.x + p3.x + p4.x) * 0.25;
        var cy:Number = (p1.y + p2.y + p3.y + p4.y) * 0.25;
        return new Vector(cx, cy);
    }

    public function getBoundingBox():AABB {
        // 从4个点中计算AABB
        var minX:Number = p1.x;
        var maxX:Number = p1.x;
        var minY:Number = p1.y;
        var maxY:Number = p1.y;

        // 检查p2
        if (p2.x < minX) minX = p2.x;
        if (p2.x > maxX) maxX = p2.x;
        if (p2.y < minY) minY = p2.y;
        if (p2.y > maxY) maxY = p2.y;

        // 检查p3
        if (p3.x < minX) minX = p3.x;
        if (p3.x > maxX) maxX = p3.x;
        if (p3.y < minY) minY = p3.y;
        if (p3.y > maxY) maxY = p3.y;

        // 检查p4
        if (p4.x < minX) minX = p4.x;
        if (p4.x > maxX) maxX = p4.x;
        if (p4.y < minY) minY = p4.y;
        if (p4.y > maxY) maxY = p4.y;

        return new AABB(minX, maxX, minY, maxY);
    }

    // 重写toArray，将4点打包为数组返回
    public function toArray():Array {
        return [p1, p2, p3, p4];
    }

    // 重写fromArray，用传入的数组重设4点
    public function fromArray(arr:Array):Void {
        if (arr.length != 4) {
            trace("RectanglePointSet: 数组必须有4个点。");
            return;
        }
        p1 = arr[0];
        p2 = arr[1];
        p3 = arr[2];
        p4 = arr[3];
    }

    // 对于凸包方法直接返回自身克隆
    public function getConvexHullGraham():PointSet {
        return this.clone();
    }

    public function getConvexHullJarvis():PointSet {
        return this.clone();
    }

    public function clone():RectanglePointSet {
        return new RectanglePointSet(
            new Vector(p1.x, p1.y),
            new Vector(p2.x, p2.y),
            new Vector(p3.x, p3.y),
            new Vector(p4.x, p4.y)
        );
    }

    public function toString():String {
        return "RectanglePointSet [(" + p1.x + "," + p1.y + "), (" + p2.x + "," + p2.y + "), (" + p3.x + "," + p3.y + "), (" + p4.x + "," + p4.y + ")]";
    }
}
