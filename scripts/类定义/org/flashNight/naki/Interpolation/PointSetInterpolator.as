import org.flashNight.naki.Interpolation.Interpolatior;
import org.flashNight.naki.Sort.InsertionSort;
import org.flashNight.sara.util.PointSet;
import org.flashNight.sara.util.Vector;

class org.flashNight.naki.Interpolation.PointSetInterpolator {

    private var pointSet:PointSet;  // 使用 PointSet 存储点集
    private var mode:String;        // 插值模式

    /**
     * 构造函数，初始化点集和插值模式，并对点集进行 x 坐标排序
     * 
     * @param pointSet PointSet 实例
     * @param mode 插值模式，接受 "linear", "cubic", "bezier", "catmullRom", "easeInOut", "bilinear", "bicubic", "exponential", "sine", "elastic", "logarithmic"
     */
    public function PointSetInterpolator(pointSet:PointSet, mode:String) {
        this.pointSet = pointSet;
        this.mode = mode;

        // 对 PointSet 的点按照 x 坐标排序
        this.sortPoints();
    }

    /**
     * 对点集进行按 x 坐标排序
     */
    private function sortPoints():Void {
        var pointsArray:Array = []; // 临时存储点的数组

        // 将 PointSet 中的点提取为普通数组
        for (var i:Number = 0; i < pointSet.size(); i++) {
            var point:Vector = pointSet.getPoint(i);
            pointsArray.push([point.x, point.y]);
        }

        // 使用插入排序按 x 坐标排序
        var sortedPoints:Array = InsertionSort.sort(pointsArray, sortByX);

        // 清空 PointSet 并重新添加排序后的点
        pointSet = new PointSet();
        for (var j:Number = 0; j < sortedPoints.length; j++) {
            pointSet.addPoint(sortedPoints[j][0], sortedPoints[j][1]);
        }
    }

    /**
     * 点集排序函数，按照 x 坐标进行升序排序
     * 
     * @param a 点 a 的坐标 [x, y]
     * @param b 点 b 的坐标 [x, y]
     * @return 返回 -1, 0 或 1 表示比较结果
     */
    private function sortByX(a:Array, b:Array):Number {
        return a[0] - b[0];  // 按 x 坐标升序排序
    }

    /**
     * 进行插值计算
     * 
     * @param t 插值进度参数，范围 [0, 1]
     * @return 返回插值计算结果
     */
    public function interpolate(t:Number):Object {
        return this.applyInterpolatior(this.mode, t);
    }

    /**
     * 通用插值方法，调用 Interpolatior 中的方法来计算结果
     * 
     * @param method 插值方法名称，对应于 Interpolatior 中的方法名
     * @param t 插值进度参数，范围 [0, 1]
     * @return 返回插值计算结果
     */
    private function applyInterpolatior(method:String, t:Number):Object {
        if (pointSet.size() < 2) {
            trace("至少需要两个点进行插值");
            return null;
        }

        var p0:Vector = pointSet.getPoint(0);  // 起点
        var p1:Vector = pointSet.getPoint(1);  // 终点
        var result:Object = {x: 0, y: 0};

        // 判断插值方法并调用相应的 Interpolatior 方法
        switch (method) {
            case "linear":
                result.x = Interpolatior.linear(t, 0, 1, p0.x, p1.x);
                result.y = Interpolatior.linear(t, 0, 1, p0.y, p1.y);
                break;
            case "cubic":
                if (pointSet.size() < 4) {
                    trace("三次插值需要至少4个点");
                    return null;
                }
                result.x = Interpolatior.cubic(t, p0.x, pointSet.getPoint(1).x, pointSet.getPoint(2).x, pointSet.getPoint(3).x);
                result.y = Interpolatior.cubic(t, p0.y, pointSet.getPoint(1).y, pointSet.getPoint(2).y, pointSet.getPoint(3).y);
                break;
            case "bezier":
                if (pointSet.size() < 4) {
                    trace("贝塞尔插值需要至少4个点");
                    return null;
                }
                result.x = Interpolatior.bezier(t, p0.x, pointSet.getPoint(1).x, pointSet.getPoint(2).x, pointSet.getPoint(3).x);
                result.y = Interpolatior.bezier(t, p0.y, pointSet.getPoint(1).y, pointSet.getPoint(2).y, pointSet.getPoint(3).y);
                break;
            case "catmullRom":
                if (pointSet.size() < 4) {
                    trace("Catmull-Rom 样条插值需要至少4个点");
                    return null;
                }
                result.x = Interpolatior.catmullRom(t, p0.x, pointSet.getPoint(1).x, pointSet.getPoint(2).x, pointSet.getPoint(3).x);
                result.y = Interpolatior.catmullRom(t, p0.y, pointSet.getPoint(1).y, pointSet.getPoint(2).y, pointSet.getPoint(3).y);
                break;
            case "easeInOut":
                result.x = Interpolatior.easeInOut(t) * (p1.x - p0.x) + p0.x;
                result.y = Interpolatior.easeInOut(t) * (p1.y - p0.y) + p0.y;
                break;
            case "bilinear":
                if (pointSet.size() < 4) {
                    trace("双线性插值需要至少4个点");
                    return null;
                }
                result.x = Interpolatior.bilinear(t, t, p0.x, pointSet.getPoint(1).x, pointSet.getPoint(2).x, pointSet.getPoint(3).x, 0, 1, 0, 1);
                result.y = Interpolatior.bilinear(t, t, p0.y, pointSet.getPoint(1).y, pointSet.getPoint(2).y, pointSet.getPoint(3).y, 0, 1, 0, 1);
                break;
            case "bicubic":
                if (pointSet.size() < 4) {
                    trace("双三次插值需要至少4个点");
                    return null;
                }
                result.x = Interpolatior.bicubic(t, p0.x, pointSet.getPoint(1).x, pointSet.getPoint(2).x, pointSet.getPoint(3).x);
                result.y = Interpolatior.bicubic(t, p0.y, pointSet.getPoint(1).y, pointSet.getPoint(2).y, pointSet.getPoint(3).y);
                break;
            case "exponential":
                result.x = Interpolatior.exponential(t, 2) * (p1.x - p0.x) + p0.x;
                result.y = Interpolatior.exponential(t, 2) * (p1.y - p0.y) + p0.y;
                break;
            case "sine":
                result.x = Interpolatior.sine(t) * (p1.x - p0.x) + p0.x;
                result.y = Interpolatior.sine(t) * (p1.y - p0.y) + p0.y;
                break;
            case "elastic":
                result.x = Interpolatior.elastic(t) * (p1.x - p0.x) + p0.x;
                result.y = Interpolatior.elastic(t) * (p1.y - p0.y) + p0.y;
                break;
            case "logarithmic":
                result.x = Interpolatior.logarithmic(t, 2) * (p1.x - p0.x) + p0.x;
                result.y = Interpolatior.logarithmic(t, 2) * (p1.y - p0.y) + p0.y;
                break;
            default:
                trace("未知的插值方法: " + method);
                return null;
        }

        return result;
    }
}
