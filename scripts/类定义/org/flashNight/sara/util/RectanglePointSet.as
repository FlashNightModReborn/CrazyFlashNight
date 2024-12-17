import org.flashNight.sara.util.PointSet;
import org.flashNight.sara.util.Vector;
import org.flashNight.arki.component.Collider.AABB;

class org.flashNight.sara.util.RectanglePointSet extends PointSet {
    /**
     * 构造函数
     * 可选方式：
     * 1. 初始化为空（稍后通过setRectangle方法赋值）
     * 2. 构造时传入4个点（默认顺序为任意，但建议按矩形顶点顺序）
     * 
     * @param p1 可选参数，第1个顶点
     * @param p2 可选参数，第2个顶点
     * @param p3 可选参数，第3个顶点
     * @param p4 可选参数，第4个顶点
     */
    public function RectanglePointSet(p1:Vector, p2:Vector, p3:Vector, p4:Vector) {
        super();
        if (p1 && p2 && p3 && p4) {
            // 利用父类的addPoint，但须保证最终数量为4个
            super.addPoint(p1.x, p1.y);
            super.addPoint(p2.x, p2.y);
            super.addPoint(p3.x, p3.y);
            super.addPoint(p4.x, p4.y);
        }
    }

    /**
     * 设置矩形的4个点
     * @param p1 第1个顶点
     * @param p2 第2个顶点
     * @param p3 第3个顶点
     * @param p4 第4个顶点
     */
    public function setRectangle(p1:Vector, p2:Vector, p3:Vector, p4:Vector):Void {
        // 使用fromArray替换内部数组
        fromArray([p1, p2, p3, p4]);
    }

    /**
     * 覆写 addPoint 方法，禁止添加超过4点。
     */
    public function addPoint(x:Number, y:Number):Void {
        if (this.size() >= 4) {
            // 已满4点，不允许添加更多顶点
            trace("RectanglePointSet: 无法添加更多顶点，矩形始终只能有4个顶点。");
            return;
        }
        super.addPoint(x, y);
    }

    /**
     * 覆写 removePoint 方法，禁止移除点。
     * 如果需要调整矩形，请使用 setRectangle 方法直接重置4点。
     */
    public function removePoint(index:Number):Void {
        trace("RectanglePointSet: 不允许移除顶点。");
        // 不执行任何移除操作
    }

    /**
     * 覆写 getBoundingBox 方法，对4点矩形直接计算AABB
     */
    public function getBoundingBox():AABB {
        var pts:Array = this.toArray();
        // 假定已存在4点
        var minX:Number = pts[0].x;
        var maxX:Number = pts[0].x;
        var minY:Number = pts[0].y;
        var maxY:Number = pts[0].y;

        for (var i:Number = 1; i < 4; i++) {
            if (pts[i].x < minX) minX = pts[i].x;
            if (pts[i].x > maxX) maxX = pts[i].x;
            if (pts[i].y < minY) minY = pts[i].y;
            if (pts[i].y > maxY) maxY = pts[i].y;
        }

        return new AABB(minX, maxX, minY, maxY);
    }

    /**
     * 覆写 getCentroid 方法
     * 矩形的质心为4点的平均值
     */
    public function getCentroid():Vector {
        var pts:Array = this.toArray();
        if (pts.length < 4) {
            return super.getCentroid(); // 无法计算矩形质心，回退父类逻辑（实际不应出现）
        }
        var sumX:Number = pts[0].x + pts[1].x + pts[2].x + pts[3].x;
        var sumY:Number = pts[0].y + pts[1].y + pts[2].y + pts[3].y;
        return new Vector(sumX / 4, sumY / 4);
    }

    /**
     * 对某些方法的优化（如凸包计算）就不需要了，因为矩形本身就是凸包
     * 如果调用凸包方法，可以直接返回自身。
     */
    public function getConvexHullGraham():PointSet {
        // 矩形本身就是凸包
        return this.clone();
    }

    public function getConvexHullJarvis():PointSet {
        // 同上，直接返回自身
        return this.clone();
    }

    /**
     * 克隆当前矩形点集（辅助方法）
     */
    public function clone():RectanglePointSet {
        var pts:Array = this.toArray();
        return new RectanglePointSet(pts[0], pts[1], pts[2], pts[3]);
    }
}
