import org.flashNight.sara.util.*;

class org.flashNight.sara.util.RectanglePointSet extends PointSet {

    /**
     * 构造函数，初始化矩形点集，直接接收 4 个 Vector 对象。
     * @param point1 矩形的第一个点
     * @param point2 矩形的第二个点
     * @param point3 矩形的第三个点
     * @param point4 矩形的第四个点
     */
    public function RectanglePointSet(point1:Vector, point2:Vector, point3:Vector, point4:Vector) {
        super(); // 调用父类的构造函数
        
        // 初始化点集，直接设置 4 个点
        this.points = [point1, point2, point3, point4];
    }

    /**
     * 重写 addPoint 方法，使其不可用。
     * 矩形点集必须保持 4 个点，不允许动态添加。
     */
    public function addPoint(x:Number, y:Number):Void {
        trace("RectanglePointSet does not support adding points dynamically.");
    }

    /**
     * 重写 removePoint 方法，使其不可用。
     * 矩形点集必须保持 4 个点，不允许移除点。
     */
    public function removePoint(index:Number):Void {
        trace("RectanglePointSet does not support removing points.");
    }

    /**
     * 获取矩形的 4 个点
     * @return 返回包含 4 个点的数组
     */
    public function getRectanglePoints():Array {
        return this.toArray(); // 返回点集的副本
    }

    /**
     * 判断矩形是否有效（所有点不重合）
     * @return 如果有效返回 true，否则返回 false
     */
    public function isValidRectangle():Boolean {
        if (this.points.length != 4) {
            return false; // 必须包含 4 个点
        }

        // 判断是否有任意两个点相同
        for (var i:Number = 0; i < 4; i++) {
            for (var j:Number = i + 1; j < 4; j++) {
                if (this.points[i].x == this.points[j].x && this.points[i].y == this.points[j].y) {
                    return false; // 有点重合
                }
            }
        }
        return true;
    }

    /**
     * 获取矩形的边向量数组
     * @return 返回包含 4 个边向量的数组
     */
    public function getEdgeVectors():Array {
        var edges:Array = [];
        edges.push(new Vector(this.points[1].x - this.points[0].x, this.points[1].y - this.points[0].y)); // 边1
        edges.push(new Vector(this.points[2].x - this.points[1].x, this.points[2].y - this.points[1].y)); // 边2
        edges.push(new Vector(this.points[3].x - this.points[2].x, this.points[3].y - this.points[2].y)); // 边3
        edges.push(new Vector(this.points[0].x - this.points[3].x, this.points[0].y - this.points[3].y)); // 边4
        return edges;
    }
}