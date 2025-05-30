/**
 * 碎片尺寸信息数据类
 * 
 * 此类用于存储和计算碎片MovieClip的尺寸相关信息，包括宽度、高度和面积。
 * 这些信息主要用于物理质量计算和碰撞检测半径的确定。
 * 
 * 设计目标：
 * - 封装尺寸数据：提供统一的尺寸信息访问接口
 * - 自动计算面积：避免重复计算，提高性能
 * - 支持比较操作：便于排序和筛选
 * - 提供实用方法：计算对角线、长宽比等衍生数据
 * 
 * 应用场景：
 * - 物理质量计算：面积越大的碎片质量越大
 * - 碰撞半径计算：基于面积计算等效圆形半径
 * - 渲染优化：根据尺寸决定渲染优先级
 * - 动画参数调整：大小不同的碎片使用不同的物理参数
 * 
 */
class org.flashNight.arki.spatial.animation.FragmentSize {
    
    /**
     * 碎片宽度（像素）
     * 
     * 表示碎片MovieClip在X轴方向的尺寸。此值通过
     * getBounds()方法计算得出：width = bounds.xMax - bounds.xMin
     * 
     * 注意：这是视觉宽度，不考虑旋转变换的影响。
     */
    public var width:Number;
    
    /**
     * 碎片高度（像素）
     * 
     * 表示碎片MovieClip在Y轴方向的尺寸。此值通过
     * getBounds()方法计算得出：height = bounds.yMax - bounds.yMin
     * 
     * 注意：这是视觉高度，不考虑旋转变换的影响。
     */
    public var height:Number;
    
    /**
     * 碎片面积（平方像素）
     * 
     * 碎片的矩形面积，计算公式：area = width × height
     * 此值主要用于：
     * - 物理质量计算：mass = area / massScale
     * - 碰撞半径计算：radius = sqrt(area) / 4
     * - 渲染优先级判断：面积大的优先渲染
     */
    public var area:Number;
    
    /**
     * 构造函数
     * 
     * 创建一个碎片尺寸信息对象，并自动计算面积。
     * 
     * @param width:Number 碎片宽度（像素）
     * @param height:Number 碎片高度（像素）
     * 
     * @throws Error 当宽度或高度为负数时抛出异常
     * 
     * @example
     * var size:FragmentSize = new FragmentSize(50, 30);
     * trace("面积: " + size.area); // 输出: 面积: 1500
     */
    public function FragmentSize(width:Number, height:Number) {
        // 参数有效性验证
        if (width < 0 || height < 0) {
            trace("[FragmentSize] 错误：宽度和高度不能为负数");
            width = Math.max(0, width);
            height = Math.max(0, height);
        }
        
        this.width = width;
        this.height = height;
        this.area = width * height;
    }
    
    /**
     * 计算等效圆形半径
     * 
     * 将矩形碎片等效为同面积的圆形，计算其半径。
     * 这个半径常用于碰撞检测，因为圆形碰撞检测比矩形更高效。
     * 
     * 计算公式：radius = sqrt(area / π)
     * 
     * @return Number 等效圆形的半径（像素）
     * 
     * @example
     * var size:FragmentSize = new FragmentSize(20, 20);
     * var radius:Number = size.getEquivalentCircleRadius();
     * // 对于20x20的正方形，半径约为11.28像素
     */
    public function getEquivalentCircleRadius():Number {
        return Math.sqrt(area / Math.PI);
    }
    
    /**
     * 计算简化碰撞半径
     * 
     * 使用简化公式计算碰撞半径，性能比等效圆形半径更好。
     * 这是动画系统实际使用的碰撞半径计算方法。
     * 
     * 计算公式：radius = sqrt(area) / 4
     * 
     * @return Number 简化碰撞半径（像素）
     * 
     * @example
     * var size:FragmentSize = new FragmentSize(40, 30);
     * var radius:Number = size.getCollisionRadius();
     * // 半径约为8.66像素
     */
    public function getCollisionRadius():Number {
        return Math.sqrt(area) / 4;
    }
    
    /**
     * 计算对角线长度
     * 
     * 计算矩形碎片的对角线长度，可用于判断碎片的整体大小。
     * 
     * 计算公式：diagonal = sqrt(width² + height²)
     * 
     * @return Number 对角线长度（像素）
     * 
     * @example
     * var size:FragmentSize = new FragmentSize(30, 40);
     * var diagonal:Number = size.getDiagonal();
     * // 对角线长度为50像素
     */
    public function getDiagonal():Number {
        return Math.sqrt(width * width + height * height);
    }
    
    /**
     * 计算长宽比
     * 
     * 计算碎片的长宽比（较长边/较短边），用于判断碎片的形状特征。
     * 
     * @return Number 长宽比，值域为[1, +∞)，1表示正方形
     * 
     * @example
     * var size1:FragmentSize = new FragmentSize(20, 20);
     * trace(size1.getAspectRatio()); // 输出: 1 (正方形)
     * 
     * var size2:FragmentSize = new FragmentSize(40, 20);
     * trace(size2.getAspectRatio()); // 输出: 2 (长方形)
     */
    public function getAspectRatio():Number {
        if (width == 0 || height == 0) {
            return 1;
        }
        
        var longer:Number = Math.max(width, height);
        var shorter:Number = Math.min(width, height);
        
        return longer / shorter;
    }
    
    /**
     * 获取最大尺寸
     * 
     * 返回宽度和高度中的较大值。
     * 
     * @return Number 最大尺寸（像素）
     */
    public function getMaxDimension():Number {
        return Math.max(width, height);
    }
    
    /**
     * 获取最小尺寸
     * 
     * 返回宽度和高度中的较小值。
     * 
     * @return Number 最小尺寸（像素）
     */
    public function getMinDimension():Number {
        return Math.min(width, height);
    }
    
    /**
     * 判断是否为正方形
     * 
     * 判断碎片是否接近正方形。由于浮点数精度问题，
     * 使用容差值进行比较。
     * 
     * @param tolerance:Number 容差值，默认为1像素
     * @return Boolean true表示是正方形，false表示不是
     * 
     * @example
     * var size1:FragmentSize = new FragmentSize(20, 20);
     * trace(size1.isSquare()); // 输出: true
     * 
     * var size2:FragmentSize = new FragmentSize(20, 21);
     * trace(size2.isSquare()); // 输出: true（在默认容差范围内）
     * trace(size2.isSquare(0.5)); // 输出: false（容差更严格）
     */
    public function isSquare(tolerance:Number):Boolean {
        if (tolerance == undefined) {
            tolerance = 1;
        }
        
        return Math.abs(width - height) <= tolerance;
    }
    
    /**
     * 比较两个尺寸对象的面积
     * 
     * 比较当前对象与另一个尺寸对象的面积大小。
     * 
     * @param other:FragmentSize 要比较的尺寸对象
     * @return Number 比较结果：负数表示当前对象较小，0表示相等，正数表示当前对象较大
     * 
     * @example
     * var size1:FragmentSize = new FragmentSize(20, 20);
     * var size2:FragmentSize = new FragmentSize(30, 30);
     * var result:Number = size1.compareArea(size2);
     * // result为负数，表示size1面积小于size2
     */
    public function compareArea(other:FragmentSize):Number {
        if (!other) {
            return 1; // 当前对象较大
        }
        
        return this.area - other.area;
    }
    
    /**
     * 缩放尺寸
     * 
     * 创建一个缩放后的新尺寸对象，不修改当前对象。
     * 
     * @param scaleX:Number X轴缩放因子
     * @param scaleY:Number Y轴缩放因子，如果未提供则使用scaleX的值
     * @return FragmentSize 缩放后的新尺寸对象
     * 
     * @example
     * var originalSize:FragmentSize = new FragmentSize(20, 30);
     * var scaledSize:FragmentSize = originalSize.scale(2, 1.5);
     * // scaledSize的尺寸为40x45
     */
    public function scale(scaleX:Number, scaleY:Number):FragmentSize {
        if (scaleY == undefined) {
            scaleY = scaleX;
        }
        
        return new FragmentSize(width * scaleX, height * scaleY);
    }
    
    /**
     * 克隆尺寸对象
     * 
     * 创建当前尺寸对象的完整副本。
     * 
     * @return FragmentSize 当前对象的副本
     */
    public function clone():FragmentSize {
        return new FragmentSize(width, height);
    }
    
    /**
     * 转换为字符串表示
     * 
     * 返回尺寸信息的字符串表示，便于调试和日志输出。
     * 
     * @return String 格式为"宽度x高度 (面积)"的字符串
     * 
     * @example
     * var size:FragmentSize = new FragmentSize(20, 30);
     * trace(size.toString()); // 输出: "20x30 (600)"
     */
    public function toString():String {
        return width + "x" + height + " (" + area + ")";
    }
    
    /**
     * 检查尺寸是否有效
     * 
     * 验证宽度、高度和面积是否都为有效的正数。
     * 
     * @return Boolean true表示尺寸有效，false表示存在无效值
     */
    public function isValid():Boolean {
        return (width >= 0 && height >= 0 && area >= 0 && 
                !isNaN(width) && !isNaN(height) && !isNaN(area));
    }
    
    /**
     * 获取尺寸类别
     * 
     * 根据面积大小返回尺寸类别，便于分类处理。
     * 
     * @return String 尺寸类别："tiny"、"small"、"medium"、"large"、"huge"
     * 
     * @example
     * var size:FragmentSize = new FragmentSize(50, 50);
     * trace(size.getSizeCategory()); // 可能输出: "medium"
     */
    public function getSizeCategory():String {
        if (area < 100) {
            return "tiny";
        } else if (area < 400) {
            return "small";
        } else if (area < 1600) {
            return "medium";
        } else if (area < 6400) {
            return "large";
        } else {
            return "huge";
        }
    }
}