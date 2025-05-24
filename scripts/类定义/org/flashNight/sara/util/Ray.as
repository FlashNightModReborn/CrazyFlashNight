import org.flashNight.sara.util.Vector;

/**
 * Ray - 射线类
 * 
 * 用于在游戏中进行射线投射和相关计算，基于 Vector 类实现。
 * 射线由一个起点（origin）、一个单位方向向量（direction）和一个最大长度（maxDistance）构成。
 * 
 * 提供常用的射线操作方法，包括：
 *  - 获取射线上指定距离处的点
 *  - 获取射线终点
 *  - 计算射线到某点的最短距离以及最近点
 *  - 与圆的碰撞检测（返回是否相交以及相交点）
 *  - 射线的反射计算
 * 
 */
class org.flashNight.sara.util.Ray {

    // 射线的起点
    public var origin:Vector;
    // 射线的方向（单位向量）
    public var direction:Vector;
    // 射线的最大长度
    public var maxDistance:Number;

    /**
     * 构造函数，初始化射线的起点、方向和最大长度。
     * @param origin 射线的起点
     * @param direction 射线的方向（传入后会单位化）
     * @param maxDistance 射线的最大长度
     */
    public function Ray(origin:Vector, direction:Vector, maxDistance:Number) {
        this.origin = origin.clone();
        this.direction = direction.clone().normalize();
        this.maxDistance = maxDistance;
    }

    /**
     * 设置射线的属性。
     * @param origin 新的起点
     * @param direction 新的方向（传入后会单位化）
     * @param maxDistance 新的最大长度
     */
    public function setTo(origin:Vector, direction:Vector, maxDistance:Number):Void {
        this.origin = origin.clone();
        this.direction = direction.clone().normalize();
        this.maxDistance = maxDistance;
    }

    /**
     * 获取射线上距离起点 t 距离处的点。
     * 如果 t 超出 [0, maxDistance] 区间，将进行相应的限制。
     * @param t 距离起点的距离
     * @return 射线上的点（Vector）
     */
    public function getPoint(t:Number):Vector {
        if (t < 0) t = 0;
        if (t > maxDistance) t = maxDistance;
        return origin.plusNew(direction.multNew(t));
    }

    /**
     * 获取射线的终点，即起点加上方向向量乘以最大长度。
     * @return 射线的终点（Vector）
     */
    public function getEndpoint():Vector {
        return getPoint(maxDistance);
    }

    /**
     * 克隆当前射线，返回一个新的 Ray 实例，其属性与当前射线相同。
     * @return 当前射线的克隆
     */
    public function clone():Ray {
        return new Ray(origin, direction, maxDistance);
    }

    /**
     * 返回当前射线的字符串表示形式。
     * @return 射线的字符串表示
     */
    public function toString():String {
        return "[Ray: origin=" + origin.toString() + ", direction=" + direction.toString() + ", maxDistance=" + maxDistance + "]";
    }

    /**
     * 计算射线上到给定点最近的点。
     * @param point 目标点
     * @return 射线上到目标点最近的点（Vector）
     */
    public function closestPointTo(point:Vector):Vector {
        var op:Vector = point.minusNew(origin);
        var t:Number = op.dot(direction);
        if (t < 0) t = 0;
        if (t > maxDistance) t = maxDistance;
        return getPoint(t);
    }

    /**
     * 计算射线到给定点的最短距离。
     * @param point 目标点
     * @return 射线到目标点的距离
     */
    public function distanceToPoint(point:Vector):Number {
        var closest:Vector = closestPointTo(point);
        return point.distance(closest);
    }

    /**
     * 检测射线是否与以 center 为中心、radius 为半径的圆相交。
     * @param center 圆心（Vector）
     * @param radius 圆的半径
     * @return 如果射线相交返回 true，否则返回 false
     */
    public function intersectsCircle(center:Vector, radius:Number):Boolean {
        var m:Vector = origin.minusNew(center);
        var b:Number = m.dot(direction);
        var c:Number = m.dot(m) - radius * radius;
        if (c > 0 && b > 0) return false;
        var discriminant:Number = b * b - c;
        if (discriminant < 0) return false;
        var t:Number = -b - Math.sqrt(discriminant);
        if (t < 0) t = 0;
        if (t > maxDistance) return false;
        return true;
    }

    /**
     * 计算射线与圆的交点（如果存在且在射线有效范围内）。
     * @param center 圆心（Vector）
     * @param radius 圆的半径
     * @return 如果相交，返回第一个交点（Vector）；否则返回 null
     */
    public function intersectCirclePoint(center:Vector, radius:Number):Vector {
        var m:Vector = origin.minusNew(center);
        var b:Number = m.dot(direction);
        var c:Number = m.dot(m) - radius * radius;
        if (c > 0 && b > 0) return null;
        var discriminant:Number = b * b - c;
        if (discriminant < 0) return null;
        var t:Number = -b - Math.sqrt(discriminant);
        if (t < 0) t = 0;
        if (t > maxDistance) return null;
        return getPoint(t);
    }

    /**
     * 计算射线关于给定法线的反射射线。
     * 反射公式：r = d - 2*(d · n)*n，其中 d 为当前射线方向，n 为法线（应为单位向量）。
     * @param normal 法线向量（应单位化）
     * @return 反射后的新射线
     */
    public function reflect(normal:Vector):Ray {
        var dotProduct:Number = direction.dot(normal);
        var reflectedDir:Vector = direction.minusNew(normal.multNew(2 * dotProduct)).normalize();
        return new Ray(origin, reflectedDir, maxDistance);
    }
}
