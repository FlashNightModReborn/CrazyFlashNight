import org.flashNight.sara.util.*;

/**
 * Vertex3D - 三维向量类，用于2.5d支持
 * 参考了 Vector 类的设计风格，提供常用的三维向量运算方法
 */
class org.flashNight.sara.util.Vertex3D extends Vector{

    public var x:Number;
    public var y:Number;
    public var z:Number;
    
    /**
     * 构造函数，初始化三维向量的 x, y, z 分量
     * @param px 初始的 x 分量
     * @param py 初始的 y 分量
     * @param pz 初始的 z 分量
     */
    public function Vertex3D(px:Number, py:Number, pz:Number) {
        this.x = px;
        this.y = py;
        this.z = pz;
    }

    /**
     * 设置向量的值
     * @param px 新的 x 分量
     * @param py 新的 y 分量
     * @param pz 新的 z 分量
     */
    public function setTo(px:Number, py:Number, pz:Number):Void {
        this.x = px;
        this.y = py;
        this.z = pz;
    }
    
    /**
     * 复制另一个三维向量的值到当前向量
     * @param other 要复制的向量
     */
    public function copy(other:Vertex3D):Void {
        this.x = other.x;
        this.y = other.y;
        this.z = other.z;
    }
    
    /**
     * 克隆方法，返回当前三维向量的副本
     * @return 一个新的 Vertex3D 实例，其 x, y, z 分量与当前向量相同
     */
    public function clone():Vertex3D {
        return new Vertex3D(this.x, this.y, this.z);
    }
    
    /**
     * 向当前向量加上另一个向量（原位修改）
     * @param other 要相加的向量
     * @return 当前向量（已修改）
     */
    public function plus(other:Vertex3D):Vertex3D {
        this.x += other.x;
        this.y += other.y;
        this.z += other.z;
        return this;
    }
    
    /**
     * 返回当前向量与另一个向量相加后的新向量
     * @param other 要相加的向量
     * @return 一个新的向量，表示当前向量与 other 相加的结果
     */
    public function plusNew(other:Vertex3D):Vertex3D {
        return new Vertex3D(this.x + other.x, this.y + other.y, this.z + other.z);
    }
    
    /**
     * 向当前向量减去另一个向量（原位修改）
     * @param other 要减去的向量
     * @return 当前向量（已修改）
     */
    public function minus(other:Vertex3D):Vertex3D {
        this.x -= other.x;
        this.y -= other.y;
        this.z -= other.z;
        return this;
    }
    
    /**
     * 返回当前向量减去另一个向量后的新向量
     * @param other 要减去的向量
     * @return 一个新的向量，表示当前向量减去 other 的结果
     */
    public function minusNew(other:Vertex3D):Vertex3D {
        return new Vertex3D(this.x - other.x, this.y - other.y, this.z - other.z);
    }
    
    /**
     * 将当前向量乘以一个标量（原位修改）
     * @param scalar 要乘的标量
     * @return 当前向量（已修改）
     */
    public function mult(scalar:Number):Vertex3D {
        this.x *= scalar;
        this.y *= scalar;
        this.z *= scalar;
        return this;
    }
    
    /**
     * 返回当前向量乘以一个标量后的新向量
     * @param scalar 要乘的标量
     * @return 一个新的向量，表示当前向量乘以标量后的结果
     */
    public function multNew(scalar:Number):Vertex3D {
        return new Vertex3D(this.x * scalar, this.y * scalar, this.z * scalar);
    }
    
    /**
     * 计算当前向量和另一个向量的点积
     * @param other 另一个向量
     * @return 当前向量和 other 的点积结果
     */
    public function dot(other:Vertex3D):Number {
        return this.x * other.x + this.y * other.y + this.z * other.z;
    }
    
    /**
     * 计算当前向量和另一个向量的叉积
     * @param other 另一个向量
     * @return 当前向量和 other 的叉积结果（一个新的 Vertex3D 向量）
     */
    public function cross(other:Vertex3D):Vertex3D {
        return new Vertex3D(
            this.y * other.z - this.z * other.y,
            this.z * other.x - this.x * other.z,
            this.x * other.y - this.y * other.x
        );
    }
    
    /**
     * 计算当前向量与另一个向量之间的欧几里得距离
     * @param other 另一个向量
     * @return 两个向量之间的距离
     */
    public function distance(other:Vertex3D):Number {
        var dx:Number = this.x - other.x;
        var dy:Number = this.y - other.y;
        var dz:Number = this.z - other.z;
        return Math.sqrt(dx * dx + dy * dy + dz * dz);
    }
    
    /**
     * 计算当前向量的模长（长度）
     * @return 向量的模长
     */
    public function magnitude():Number {
        return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z);
    }
    
    /**
     * 将当前向量归一化，使其模长为 1（原位修改）
     * @return 当前向量（已归一化）
     */
    public function normalize():Vertex3D {
        var mag:Number = this.magnitude();
        if (mag > 0) {
            this.x /= mag;
            this.y /= mag;
            this.z /= mag;
        }
        return this;
    }
    
    /**
     * 线性插值 (Lerp) 当前向量和另一个向量之间的插值
     * @param other 目标向量
     * @param t 插值因子，范围 0 <= t <= 1
     * @return 插值后的新向量
     */
    public function lerp(other:Vertex3D, t:Number):Vertex3D {
        return new Vertex3D(
            this.x + (other.x - this.x) * t,
            this.y + (other.y - this.y) * t,
            this.z + (other.z - this.z) * t
        );
    }
    
    /**
     * 计算当前向量与另一个向量之间的夹角（弧度）
     * @param other 另一个向量
     * @return 两个向量之间的夹角（弧度）
     */
    public function angleBetween(other:Vertex3D):Number {
        var mag1:Number = this.magnitude();
        var mag2:Number = other.magnitude();
        if (mag1 > 0 && mag2 > 0) {
            return Math.acos(this.dot(other) / (mag1 * mag2));
        } else {
            return 0;
        }
    }
    
    /**
     * 计算当前向量在另一个向量上的投影
     * @param other 要投影的向量
     * @return 投影后的新向量
     */
    public function project(other:Vertex3D):Vertex3D {
        var dotProduct:Number = this.dot(other);
        var lenSq:Number = other.x * other.x + other.y * other.y + other.z * other.z;
        return new Vertex3D((dotProduct / lenSq) * other.x, (dotProduct / lenSq) * other.y, (dotProduct / lenSq) * other.z);
    }
    
    /**
     * 反射当前向量关于一个法线向量
     * @param normal 法线向量（应为单位向量）
     * @return 反射后的新向量
     */
    public function reflect(normal:Vertex3D):Vertex3D {
        var dotProduct:Number = this.dot(normal);
        return this.minusNew(normal.multNew(2 * dotProduct));
    }
    
    /**
     * 限制当前向量的最大长度
     * @param max 最大长度
     * @return 当前向量（已限制长度）
     */
    public function limit(max:Number):Vertex3D {
        if (this.magnitude() > max) {
            this.normalize();
            this.mult(max);
        }
        return this;
    }
    
    /**
     * 检查当前向量是否为零向量
     * @return 如果向量为零向量，返回 true；否则返回 false
     */
    public function isZero():Boolean {
        return (this.x == 0 && this.y == 0 && this.z == 0);
    }
    
    /**
     * 将当前向量绕 X 轴旋转指定角度（弧度），返回旋转后的新向量
     * @param angle 旋转角度（弧度）
     * @return 旋转后的新向量
     */
    public function rotateX(angle:Number):Vertex3D {
        var cosVal:Number = Math.cos(angle);
        var sinVal:Number = Math.sin(angle);
        return new Vertex3D(this.x, this.y * cosVal - this.z * sinVal, this.y * sinVal + this.z * cosVal);
    }
    
    /**
     * 将当前向量绕 Y 轴旋转指定角度（弧度），返回旋转后的新向量
     * @param angle 旋转角度（弧度）
     * @return 旋转后的新向量
     */
    public function rotateY(angle:Number):Vertex3D {
        var cosVal:Number = Math.cos(angle);
        var sinVal:Number = Math.sin(angle);
        return new Vertex3D(this.x * cosVal + this.z * sinVal, this.y, -this.x * sinVal + this.z * cosVal);
    }
    
    /**
     * 将当前向量绕 Z 轴旋转指定角度（弧度），返回旋转后的新向量
     * @param angle 旋转角度（弧度）
     * @return 旋转后的新向量
     */
    public function rotateZ(angle:Number):Vertex3D {
        var cosVal:Number = Math.cos(angle);
        var sinVal:Number = Math.sin(angle);
        return new Vertex3D(this.x * cosVal - this.y * sinVal, this.x * sinVal + this.y * cosVal, this.z);
    }
    
    /**
     * 返回当前向量的字符串表示
     * @return 字符串表示的当前向量
     */
    public function toString():String {
        return "(" + this.x + ", " + this.y + ", " + this.z + ")";
    }
}
