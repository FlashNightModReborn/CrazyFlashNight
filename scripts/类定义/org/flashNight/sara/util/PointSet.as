import org.flashNight.sara.util.*;
import org.flashNight.naki.Sort.*;

class org.flashNight.sara.util.PointSet 
{
    private var points:Array;

    public function PointSet() {
        points = [];
    }

    public function addPoint(x:Number, y:Number):Void {
        var point:Vector = new Vector(x, y);
        points.push(point);
    }

    public function getPoint(index:Number):Vector {
        if (index >= 0 && index < points.length) {
            return points[index];
        }
        return null;
    }

    public function removePoint(index:Number):Void {
        if (index >= 0 && index < points.length) {
            points.splice(index, 1);
        }
    }

    public function size():Number {
        return points.length;
    }

    public function getCentroid():Vector {
        var totalPoints:Number = points.length;
        if (totalPoints == 0) {
            return null; // 空点集，无法计算质心
        }

        var sumX:Number = 0;
        var sumY:Number = 0;
        for (var i:Number = 0; i < totalPoints; i++) {
            sumX += points[i].x;
            sumY += points[i].y;
        }
        return new Vector(sumX / totalPoints, sumY / totalPoints);
    }

    public function getBoundingBox():AABB {
        if (points.length == 0) return null;

        var minX:Number = points[0].x;
        var maxX:Number = points[0].x;
        var minY:Number = points[0].y;
        var maxY:Number = points[0].y;

        for (var i:Number = 1; i < points.length; i++) {
            if (points[i].x < minX) minX = points[i].x;
            if (points[i].x > maxX) maxX = points[i].x;
            if (points[i].y < minY) minY = points[i].y;
            if (points[i].y > maxY) maxY = points[i].y;
        }

        return new AABB(minX, maxX, minY, maxY);
    }

    public function getMinDistanceTo(other:PointSet):Number {
        var minDistance:Number = Number.MAX_VALUE;
        for (var i:Number = 0; i < this.points.length; i++) {
            for (var j:Number = 0; j < other.size(); j++) {
                var pointA:Vector = this.points[i];
                var pointB:Vector = other.getPoint(j);
                var distance:Number = pointA.distance(pointB);
                if (distance < minDistance) {
                    minDistance = distance;
                }
            }
        }
        return minDistance;
    }

    public function toArray():Array {
        return points.concat();
    }

    public function fromArray(sortedArray:Array):Void {
        this.points = sortedArray.concat();
    }
    
    //==================================================
    // 凸包相关函数开始
    //==================================================

    /**
     * 判断从 a->b->c 这条折线是否为左转 (使用叉积判断)
     */
    private static function isLeftTurn(a:Vector, b:Vector, c:Vector):Boolean {
        return ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) > 0;
    }

    /**
     * 通过 Graham 扫描算法获取当前点集的凸包
     * @return 返回一个新的 PointSet，表示凸包点集
     */
    public function getConvexHullGraham():PointSet {
        var arr:Array = this.toArray();
        var len:Number = arr.length;
        if (len < 3) {
            // 不足3点无需计算凸包，直接返回自身副本
            var smallHull:PointSet = new PointSet();
            for (var i:Number=0; i<len; i++) {
                smallHull.addPoint(arr[i].x, arr[i].y);
            }
            return smallHull;
        }

        // 1. 找到最低点（Y最小，若相同则X最小）
        var lowest:Vector = arr[0];
        for (var i:Number = 1; i < len; i++) {
            var p:Vector = arr[i];
            if (p.y < lowest.y || (p.y == lowest.y && p.x < lowest.x)) {
                lowest = p;
            }
        }

        // 2. 以最低点为参考点对数组根据极角排序
        arr = InsertionSort.sort(arr, function(a:Vector, b:Vector) {
            var angleA:Number = Math.atan2(a.y - lowest.y, a.x - lowest.x);
            var angleB:Number = Math.atan2(b.y - lowest.y, b.x - lowest.x);
            return angleA - angleB;
        });

        // 3. 构建凸包
        var hull:Array = [arr[0], arr[1]];
        for (var j:Number = 2; j < len; j++) {
            while (hull.length >= 2 && !isLeftTurn(hull[hull.length - 2], hull[hull.length - 1], arr[j])) {
                hull.pop();
            }
            hull.push(arr[j]);
        }

        // 将 hull 转换为 PointSet 返回
        var hullSet:PointSet = new PointSet();
        for (var k:Number=0; k<hull.length; k++) {
            hullSet.addPoint(hull[k].x, hull[k].y);
        }
        return hullSet;
    }

    /**
     * 通过 Jarvis 步进（礼物包装）算法获取当前点集的凸包
     * @return 返回一个新的 PointSet，表示凸包点集
     */
    public function getConvexHullJarvis():PointSet {
        var arr:Array = this.toArray();
        var len:Number = arr.length;

        // 对少于4点的情况直接返回副本
        if (len < 4) {
            var smallHull:PointSet = new PointSet();
            for (var i:Number=0; i<len; i++) {
                smallHull.addPoint(arr[i].x, arr[i].y);
            }
            return smallHull;
        }

        // 1. 找到Y最小的点（如有并列，取X最小的）
        var startIndex:Number = 0;
        for (var i:Number = 1; i < len; i++) {
            if (arr[i].y < arr[startIndex].y || (arr[i].y == arr[startIndex].y && arr[i].x < arr[startIndex].x)) {
                startIndex = i;
            }
        }

        // 2. 构建凸包
        var hull:Array = [];
        var index:Number = startIndex;
        do {
            hull.push(arr[index]);
            var nextIndex:Number = (index + 1 == len) ? 0 : index + 1;

            for (var j:Number = 0; j < len; j++) {
                if (j == index) continue;
                if (isLeftTurn(arr[index], arr[j], arr[nextIndex])) {
                    nextIndex = j;
                }
            }

            index = nextIndex;
        } while (index != startIndex);

        var hullSet:PointSet = new PointSet();
        for (var k:Number=0; k<hull.length; k++) {
            hullSet.addPoint(hull[k].x, hull[k].y);
        }
        return hullSet;
    }

    //==================================================
    // 凸包相关函数结束
    //==================================================

    public function toString():String {
        var result:String = "PointSet [";
        for (var i:Number = 0; i < points.length; i++) {
            var point:Vector = points[i];
            result += "(" + point.x + ", " + point.y + ")";
            if (i < points.length - 1) {
                result += ", ";
            }
        }
        result += "]";
        return result;
    }

}
