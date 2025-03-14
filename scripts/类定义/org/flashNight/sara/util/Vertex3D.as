/**
 * Vertex3D - 三维向量类，用于2.5d支持
 * 参考了 Vector 类的设计风格，提供常用的三维向量运算方法
 * 
 */
class org.flashNight.sara.util.Vertex3D {

    public var x:Number;
    public var y:Number;
    public var z:Number;
    
    /**
     * 构造函数，初始化三维向量的 x, y, z 分量
     * @param x 初始的 x 分量
     * @param y 初始的 y 分量
     * @param z 初始的 z 分量
     */
    public function Vertex3D(x:Number, y:Number, z:Number) {
        this.x = x;
        this.y = y;
        this.z = z;
    }
    
    /**
     * 设置向量的值
     * @param x 新的 x 分量
     * @param y 新的 y 分量
     * @param z 新的 z 分量
     */
    public function setTo(x:Number, y:Number, z:Number):Void {
        this.x = x;
        this.y = y;
        this.z = z;
    }
    
    /**
     * 复制另一个三维向量的值到当前向量
     * @param v 要复制的向量
     */
    public function copy(v:Vertex3D):Void {
        this.x = v.x;
        this.y = v.y;
        this.z = v.z;
    }
    
    /**
     * 克隆方法，返回当前三维向量的副本
     * @return 一个新的 Vertex3D 实例，x, y, z 分量与当前向量相同
     */
    public function clone():Vertex3D {
        return new Vertex3D(this.x, this.y, this.z);
    }
    
    /**
     * 向当前向量加上另一个向量（原位修改）
     * @param v 要相加的向量
     * @return 当前向量（已修改）
     */
    public function plus(v:Vertex3D):Vertex3D {
        this.x += v.x;
        this.y += v.y;
        this.z += v.z;
        return this;
    }
    
    /**
     * 返回当前向量与另一个向量相加后的新向量
     * @param v 要相加的向量
     * @return 一个新的向量，表示当前向量和 v 相加的结果
     */
    public function plusNew(v:Vertex3D):Vertex3D {
        return new Vertex3D(this.x + v.x, this.y + v.y, this.z + v.z);
    }
    
    /**
     * 向当前向量减去另一个向量（原位修改）
     * @param v 要减去的向量
     * @return 当前向量（已修改）
     */
    public function minus(v:Vertex3D):Vertex3D {
        this.x -= v.x;
        this.y -= v.y;
        this.z -= v.z;
        return this;
    }
    
    /**
     * 返回当前向量减去另一个向量后的新向量
     * @param v 要减去的向量
     * @return 一个新的向量，表示当前向量减去 v 的结果
     */
    public function minusNew(v:Vertex3D):Vertex3D {
        return new Vertex3D(this.x - v.x, this.y - v.y, this.z - v.z);
    }
    
    /**
     * 将当前向量乘以一个标量（原位修改）
     * @param s 要乘的标量
     * @return 当前向量（已修改）
     */
    public function mult(s:Number):Vertex3D {
        this.x *= s;
        this.y *= s;
        this.z *= s;
        return this;
    }
    
    /**
     * 返回当前向量乘以一个标量后的新向量
     * @param s 要乘的标量
     * @return 一个新的向量，表示当前向量乘以标量后的结果
     */
    public function multNew(s:Number):Vertex3D {
        return new Vertex3D(this.x * s, this.y * s, this.z * s);
    }
    
    /**
     * 计算当前向量和另一个向量的点积
     * @param v 另一个向量
     * @return 当前向量和 v 的点积结果
     */
    public function dot(v:Vertex3D):Number {
        return this.x * v.x + this.y * v.y + this.z * v.z;
    }
    
    /**
     * 计算当前向量和另一个向量的叉积
     * @param v 另一个向量
     * @return 当前向量和 v 的叉积结果（一个新的 Vertex3D 向量）
     */
    public function cross(v:Vertex3D):Vertex3D {
        return new Vertex3D(
            this.y * v.z - this.z * v.y,
            this.z * v.x - this.x * v.z,
            this.x * v.y - this.y * v.x
        );
    }
    
    /**
     * 计算当前向量与另一个向量之间的欧几里得距离
     * @param v 另一个向量
     * @return 两个向量之间的距离
     */
    public function distance(v:Vertex3D):Number {
        var dx:Number = this.x - v.x;
        var dy:Number = this.y - v.y;
        var dz:Number = this.z - v.z;
        return Math.sqrt(dx*dx + dy*dy + dz*dz);
    }
    
    /**
     * 计算当前向量的模长（长度）
     * @return 向量的模长
     */
    public function magnitude():Number {
        return Math.sqrt(this.x*this.x + this.y*this.y + this.z*this.z);
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
     * @param v 目标向量
     * @param t 插值因子，范围 0 <= t <= 1
     * @return 插值后的新向量
     */
    public function lerp(v:Vertex3D, t:Number):Vertex3D {
        return new Vertex3D(
            this.x + (v.x - this.x) * t,
            this.y + (v.y - this.y) * t,
            this.z + (v.z - this.z) * t
        );
    }
    
    /**
     * 计算当前向量与另一个向量之间的夹角（弧度）
     * @param v 另一个向量
     * @return 两个向量之间的夹角（弧度）
     */
    public function angleBetween(v:Vertex3D):Number {
        var mag1:Number = this.magnitude();
        var mag2:Number = v.magnitude();
        if(mag1 > 0 && mag2 > 0) {
            return Math.acos(this.dot(v) / (mag1 * mag2));
        } else {
            return 0;
        }
    }
    
    /**
     * 计算当前向量在另一个向量上的投影
     * @param v 要投影的向量
     * @return 投影后的新向量
     */
    public function project(v:Vertex3D):Vertex3D {
        var dotProduct:Number = this.dot(v);
        var lenSq:Number = v.x*v.x + v.y*v.y + v.z*v.z;
        return new Vertex3D((dotProduct / lenSq) * v.x, (dotProduct / lenSq) * v.y, (dotProduct / lenSq) * v.z);
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
     * @return 如果向量为零向量，返回 true，否则返回 false
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
