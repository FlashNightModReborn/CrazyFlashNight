import org.flashNight.arki.render.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.gesh.object.*;
import org.flashNight.naki.DataStructures.*;

/**
 * TrailRenderer 拖影渲染器（单例）
 *
 * 用于记录并渲染攻击刀口、子弹轨迹等动态残影效果，
 * 支持样式配置、轨迹平滑处理、历史帧限制与自动内存清理。
 *
 * 主要优化与改进：
 * 1. 移除逐点透明度 (alphaArray) 的无效计算，改为统一的整体透明度处理；
 * 2. 使用通用环形队列（RingBuffer）替代 Array.shift() 操作，提升性能；
 * 3. 坐标比较采用平方距离计算，避免频繁调用 Math.sqrt；
 * 4. 缓存对象引用减少属性查找；
 * 5. 初始化逻辑统一封装；
 * 6. 阈值作为类属性，避免重复计算；
 * 7. 根据 _quality 动态调整历史帧数、数据采样、平滑处理与透明度计算，进一步性能调控；
 * 8. 在渲染时对 RingBuffer.size 做本地缓存，减少重复调用。
 */
class org.flashNight.arki.render.TrailRenderer {
    
    // --------------------------
    // 静态变量
    // --------------------------
    
    /** TrailRenderer 单例实例 */
    private static var _instance:TrailRenderer;
    
    /**
     * 拖影质量参数，共有四个取值：
     * 0：最高画质（高敏感、最长历史轨迹、更精细平滑）
     * 1：高画质
     * 2：中等画质
     * 3：低画质（低敏感、最短历史轨迹、数据采样、简单透明度计算）
     */
    private var _quality:Number = 2;
    
    // --------------------------
    // 成员变量
    // --------------------------
    
    /** 拖影样式表，按样式名称存储不同的视觉配置 */
    private var _styles:Object;
    
    /** 轨迹记录表，以发射者ID为键，记录历史轨迹数据 */
    private var _trackRecords:Object;
    
    /** 每条轨迹记录允许保留的最大历史帧数（根据 _quality 动态调整） */
    private var _maxFrames:Number;
    
    /** 移动最小差异阈值（单位：像素） */
    private var _movementThreshold:Number;
    
    /** 移动最小差异阈值的平方，用于避免频繁调用 Math.sqrt */
    private var _movementThresholdSqr:Number;
    
    // --------------------------
    // 构造与初始化
    // --------------------------
    
    /**
     * 私有构造函数，禁止外部直接创建实例，请使用 getInstance()
     */
    private function TrailRenderer() {
        // 默认使用中等画质时的设置
        this._trackRecords = {};
        this._maxFrames = 3;
        this._movementThreshold = 5.0;
        this._movementThresholdSqr = this._movementThreshold * this._movementThreshold;
    }
    
    /**
     * 获取 TrailRenderer 单例实例（懒汉式创建）
     * @return TrailRenderer 单例实例
     */
    public static function getInstance():TrailRenderer {
        if (_instance == null) {
            _instance = new TrailRenderer();
        }
        return _instance;
    }
    
    /**
     * 初始化可用拖影样式（颜色、透明度、线宽等）
     */
    public function initStyles():Void {
        var loader:TrailStylesLoader = TrailStylesLoader.getInstance();
        var self = this;
        loader.loadStyles(function(styles:Object):Void {
            self._styles = styles;
            // 样式加载成功
        }, function():Void {
            _root.服务器.发布服务器消息("TrailRenderer: 样式加载失败，使用默认样式！");
            self._styles = {
                预设: {
                    color: 0xFFFFFF,
                    lineColor: 0xFFFFFF,
                    lineWidth: 2,
                    fillOpacity: 100,
                    lineOpacity: 100
                }
            };
        });
    }
    
    /**
     * 设置拖影质量参数，同时根据质量调整阈值与历史帧数
     * @param q 质量参数（0~3），数值越小画质越高
     */
    public function setQuality(q:Number):Void {
        this._quality = q;
        // 根据 _quality 调整移动阈值与历史帧数
        switch(q) {
            case 0:
                this._movementThreshold = 3.0;  // 高敏感度
                this._maxFrames = 5;           // 历史轨迹延长
                break;
            case 1:
                this._movementThreshold = 5.0;
                this._maxFrames = 4;
                break;
            case 2:
                this._movementThreshold = 8.0;
                this._maxFrames = 3;
                break;
            case 3:
                this._movementThreshold = 10.0; // 低敏感度
                this._maxFrames = 2;            // 缩短历史轨迹
                break;
            default:
                // 若传入未知值，则使用中等配置
                this._movementThreshold = 5.0;
                this._maxFrames = 3;
                break;
        }
        this._movementThresholdSqr = this._movementThreshold * this._movementThreshold;
    }
    
    // --------------------------
    // 轨迹数据记录与渲染
    // --------------------------
    
    /**
     * 添加并记录一个发射者当前帧的轨迹数据，并触发渲染。
     * 若当前输入点集与上一次记录末尾数据变化非常小（低于设定阈值），则跳过更新与渲染，
     * 节省性能。同时，在最低画质下对数据进行采样以降低计算量。
     * 
     * @param emitterId   发射者唯一标识（例如影片剪辑的 _name）
     * @param edgeArray   边缘点数组，每项包含 edge1 和 edge2 坐标对象
     * @param styleName   拖影样式名称（必须存在于样式表中）
     */
    public function addTrailData(emitterId:String, edgeArray:Array, styleName:String):Void {
        // 在低画质模式下，对输入边缘点数据进行采样（例如每隔一个采样一次）
        if (this._quality == 3 && edgeArray.length > 0) {
            edgeArray = this._subsampleEdges(edgeArray, 2);
        }
        
        var currentFrame:Number = _root.帧计时器.当前帧数;
        var trackRecords:Object = this._trackRecords; // 缓存引用，减少属性查找
        var record:Object = trackRecords[emitterId];
        var len:Number = edgeArray.length;
        var i:Number;
        
        // 若发射者第一次出现，初始化记录结构
        if (!record) {
            record = this._initializeRecord(edgeArray, currentFrame);
            trackRecords[emitterId] = record;
            return;
        }
        
        // 超过一定帧数未更新，则清空历史轨迹（避免突变造成拖影跳变）
        if (currentFrame - record._lastFrame > (10 - this._quality)) {
            for (i = 0; i < len; i++) {
                // 使用通用 RingBuffer 的 clear()，然后再 push 初始数据
                record[i].edge1.clear();
                record[i].edge1.push(edgeArray[i].edge1);
                record[i].edge2.clear();
                record[i].edge2.push(edgeArray[i].edge2);
            }
            record._lastFrame = currentFrame;
            return;
        }
        
        // 对比当前输入的轨迹数据与上一次记录末尾的数据，
        // 如果对应点变化幅度均低于设定阈值，则认为变化很小，跳过更新与渲染
        var needUpdate:Boolean = false;
        for (i = 0; i < len; i++) {
            var traj:Object = record[i];
            var ringE1:RingBuffer = traj.edge1;
            var ringE2:RingBuffer = traj.edge2;
            
            var lastEdge1:Object = ringE1.get(ringE1.size - 1);
            var lastEdge2:Object = ringE2.get(ringE2.size - 1);
            var newE1:Object = edgeArray[i].edge1;
            var newE2:Object = edgeArray[i].edge2;
            
            var dx1:Number = lastEdge1.x - newE1.x;
            var dy1:Number = lastEdge1.y - newE1.y;
            if (dx1 * dx1 + dy1 * dy1 > this._movementThresholdSqr) {
                needUpdate = true;
                break;
            }
            var dx2:Number = lastEdge2.x - newE2.x;
            var dy2:Number = lastEdge2.y - newE2.y;
            if (dx2 * dx2 + dy2 * dy2 > this._movementThresholdSqr) {
                needUpdate = true;
                break;
            }
        }
        
        // 如果数据变化非常小，则跳过此次更新与渲染
        if (!needUpdate) {
            return;
        }
        
        // 更新当前轨迹信息，将新帧数据插入各个环形队列中
        for (i = 0; i < len; i++) {
            var trajUpdate:Object = record[i];
            trajUpdate.edge1.push(edgeArray[i].edge1);
            trajUpdate.edge2.push(edgeArray[i].edge2);
        }
        
        // 执行渲染逻辑
        this._renderTrails(record, edgeArray, styleName, currentFrame);
        
        // 更新记录最后活跃的帧数
        record._lastFrame = currentFrame;
    }
    
    /**
     * 根据 _quality 设置对数据进行采样
     * @param edgeArray 原始边缘点数组，每项包含 edge1 与 edge2
     * @param factor    采样因子（例如 2 表示每隔 1 个采样一次）
     * @return 采样后的边缘点数组
     */
    private function _subsampleEdges(edgeArray:Array, factor:Number):Array {
        var sampled:Array = [];
        for (var i:Number = 0; i < edgeArray.length; i += factor) {
            sampled.push(edgeArray[i]);
        }
        return sampled;
    }
    
    /**
     * 渲染指定发射者的轨迹记录，合并为连续多边形
     * 根据 _quality 采用不同平滑处理及透明度计算策略。
     *
     * @param record         当前发射者的历史轨迹记录（包含 RingBuffer 环形队列）
     * @param edgeArray      当前帧边缘点数组（用于遍历轨迹数量）
     * @param styleName      拖影样式名称（用于获取样式配置）
     * @param currentFrame   当前帧数（用于控制平滑处理频率）
     */
    private function _renderTrails(record:Object, edgeArray:Array, styleName:String, currentFrame:Number):Void {
        var len:Number = edgeArray.length;
        var i:Number;
        
        // 统一的整体透明度因子（简化后：低画质=50，其它=100）
        // 也可以根据需要自定义更复杂的计算规则
        var alphaValue:Number = (this._quality == 3) ? 50 : 100;
        
        for (i = 0; i < len; i++) {
            var traj:Object = record[i];
            var size1:Number = traj.edge1.size;
            var size2:Number = traj.edge2.size;
            
            // 至少有 2 个点才能形成有效轨迹
            if (size1 < 2 || size2 < 2) {
                continue;
            }
            
            // 根据画质决定平滑算法的执行
            // _quality == 0 或者每隔 _quality 帧平滑一次
            if (this._quality == 0 || currentFrame % this._quality == 0) {
                if (this._quality <= 1) {
                    // 高质量平滑
                    this._catmullRomSmooth(traj.edge1);
                    this._catmullRomSmooth(traj.edge2);
                } else {
                    // 简单平滑
                    this._simpleSmooth(traj.edge1);
                    this._simpleSmooth(traj.edge2);
                }
            }
            
            // 创建合并多边形点集
            // 先正序添加 edge1，再逆序添加 edge2
            var mergedPoints:Array = [];
            var j:Number;
            
            // edge1 正序
            for (j = 0; j < size1; j++) {
                var ptE1:Object = traj.edge1.get(j);
                mergedPoints.push({ x: ptE1.x, y: ptE1.y });
            }
            // edge2 逆序
            for (j = size2 - 1; j >= 0; j--) {
                var ptE2:Object = traj.edge2.get(j);
                mergedPoints.push({ x: ptE2.x, y: ptE2.y });
            }
            
            // 闭合多边形（连接首尾）
            // 若 mergedPoints 不为空，则将第一个点再 push 一次
            if (mergedPoints.length > 0) {
                mergedPoints.push(mergedPoints[0]);
            }
            
            // 根据画质选择不同的绘制方式
            if (this._quality <= 1) {
                // 高质量渲染逻辑
                this._drawMergedTrail(mergedPoints, alphaValue, styleName);
            } else {
                // 低画质渲染逻辑，简单绘制四边形或多边形
                this._drawQuad(mergedPoints, styleName, alphaValue);
            }
        }
    }
    
    /**
     * 绘制合并后的多边形轨迹（采用贝塞尔与直线混合绘制）
     *
     * @param points      多边形点数组（包含 edge1 正序 + edge2 逆序 + 首尾闭合）
     * @param alphaValue  当前透明度因子（0~100）
     * @param styleName   样式名称（用于获取样式配置）
     */
    private function _drawMergedTrail(points:Array, alphaValue:Number, styleName:String):Void {
        if (points.length < 3) return;
        
        var style:Object = this._styles[styleName] || this._styles["预设"];
        var fillAlpha:Number = style.fillOpacity * (alphaValue / 100);
        var lineAlpha:Number = style.lineOpacity * (alphaValue / 100);
        
        // 调用渲染器绘制混合形状（向量或贝塞尔）
        VectorAfterimageRenderer.instance.drawMixedShape(
            points,
            style.color,
            style.lineColor,
            style.lineWidth,
            fillAlpha,
            lineAlpha,
            true,
            5
        );
    }
    
    /**
     * 调用渲染系统绘制多边形（或四边形）拖影
     * 
     * @param quadPoints  多边形或四边形顶点数组（顺时针或逆时针排列，首尾可闭合）
     * @param styleName   样式名称（用于获取视觉配置）
     * @param alphaValue  当前透明衰减值（0~100）
     */
    private function _drawQuad(quadPoints:Array, styleName:String, alphaValue:Number):Void {
        if (quadPoints.length < 3) return;
        
        var style:Object = this._styles[styleName];
        if (style == undefined) {
            style = this._styles["预设"];
        }
        var fillAlpha:Number = style.fillOpacity * (alphaValue / 100);
        var lineAlpha:Number = style.lineOpacity * (alphaValue / 100);
        
        VectorAfterimageRenderer.instance.drawShape(
            quadPoints,
            style.color,
            style.lineColor,
            style.lineWidth,
            fillAlpha,
            lineAlpha,
            3
        );
    }
    
    // --------------------------
    // 平滑算法
    // --------------------------
    
    /**
     * 简单平滑算法：利用相邻三个点的平均值减少轨迹抖动（作用于 RingBuffer 数据）
     * 
     * @param ring 包含多个 {x, y} 坐标点的 RingBuffer
     */
    private function _simpleSmooth(ring:RingBuffer):Void {
        var count:Number = ring.size;
        if (count < 3) return;
        
        for (var i:Number = 1; i < count - 1; i++) {
            var pPrev:Object = ring.get(i - 1);
            var pCurr:Object = ring.get(i);
            var pNext:Object = ring.get(i + 1);
            pCurr.x = (pPrev.x + pCurr.x + pNext.x) / 3;
            pCurr.y = (pPrev.y + pCurr.y + pNext.y) / 3;
        }
    }
    
/**
 * 基于 Catmull-Rom 样条的平滑算法（内联展开插值公式以优化性能），作用于 RingBuffer 数据
 * @param ring    包含多个 {x, y} 坐标点的 RingBuffer
 * @param tension 曲线张力参数 (0-1)，默认 0.5
 */
private function _catmullRomSmooth(ring:RingBuffer, tension:Number):Void {
    if (tension == undefined) tension = 0.5;
    var count:Number = ring.size;
    if (count < 4) return; // 至少需要 4 个点

    // 将 RingBuffer 数据转换为普通数组，扩展边界条件视为环形
    var points:Array = [];
    for (var i:Number = 0; i < count; i++) {
        points.push(ring.get(i));
    }
    points.unshift(ring.get(count - 1)); // 在首部添加末尾点
    points.push(ring.get(0));            // 在尾部添加首点

    // 插值生成新点数组（可根据需求减少插值数量）
    var newPoints:Array = [];
    for (i = 1; i < points.length - 2; i++) {
        var p0:Object = points[i - 1];
        var p1:Object = points[i];
        var p2:Object = points[i + 1];
        var p3:Object = points[i + 2];

        // 每段插值生成 2 个点 (t=0.25, 0.75)
        for (var t:Number = 0.25; t < 1; t += 0.5) {
            // --- 内联计算 x 坐标部分 ---
            // 使用 Math.abs() 替换 _distance 计算两点差的绝对值
            var t01_x:Number = Math.pow(Math.abs(p1.x - p0.x), tension);
            var t12_x:Number = Math.pow(Math.abs(p2.x - p1.x), tension);
            var t23_x:Number = Math.pow(Math.abs(p3.x - p2.x), tension);
            
            var m1_x:Number = (p2.x - p1.x + t12_x * ((p1.x - p0.x) / t01_x - (p2.x - p0.x) / (t01_x + t12_x)));
            var m2_x:Number = (p2.x - p1.x + t12_x * ((p3.x - p2.x) / t23_x - (p3.x - p1.x) / (t12_x + t23_x)));
            
            var t2:Number = t * t;
            var t3:Number = t2 * t;
            var x:Number = (2 * t3 - 3 * t2 + 1) * p1.x
                         + (t3 - 2 * t2 + t) * m1_x
                         + (-2 * t3 + 3 * t2) * p2.x
                         + (t3 - t2) * m2_x;
                         
            // --- 内联计算 y 坐标部分 ---
            var t01_y:Number = Math.pow(Math.abs(p1.y - p0.y), tension);
            var t12_y:Number = Math.pow(Math.abs(p2.y - p1.y), tension);
            var t23_y:Number = Math.pow(Math.abs(p3.y - p2.y), tension);
            
            var m1_y:Number = (p2.y - p1.y + t12_y * ((p1.y - p0.y) / t01_y - (p2.y - p0.y) / (t01_y + t12_y)));
            var m2_y:Number = (p2.y - p1.y + t12_y * ((p3.y - p2.y) / t23_y - (p3.y - p1.y) / (t12_y + t23_y)));
            
            var y:Number = (2 * t3 - 3 * t2 + 1) * p1.y
                         + (t3 - 2 * t2 + t) * m1_y
                         + (-2 * t3 + 3 * t2) * p2.y
                         + (t3 - t2) * m2_y;
                         
            newPoints.push({ x: x, y: y });
        }
    }
    
    // 重置 RingBuffer：先清空，再依次添加新生成的数据
    ring.clear();
    for (i = 0; i < newPoints.length; i++) {
        ring.push(newPoints[i]);
    }
}

    
    // --------------------------
    // 发射者轨迹记录（环形队列）辅助方法
    // --------------------------
    
    /**
     * 初始化新的发射者轨迹记录，统一使用 RingBuffer 存储边缘点数据
     *
     * @param edgeArray    当前帧边缘点数组（每项包含 edge1 与 edge2 坐标）
     * @param currentFrame 当前帧数
     * @return 初始化后的记录对象，包含每个边缘的 RingBuffer 数据
     */
    private function _initializeRecord(edgeArray:Array, currentFrame:Number):Object {
        var rec:Object = { _lastFrame: currentFrame };
        var len:Number = edgeArray.length;
        for (var i:Number = 0; i < len; i++) {
            rec[i] = { 
                edge1: new RingBuffer(this._maxFrames, null, [edgeArray[i].edge1]),
                edge2: new RingBuffer(this._maxFrames, null, [edgeArray[i].edge2])
            };
        }
        return rec;
    }
    
    // --------------------------
    // 内存管理
    // --------------------------
    
    /**
     * 清理未活跃的轨迹数据，释放内存
     *
     * @return 被清理的发射者数量
     */
    public function cleanMemory():Number {
        var cleanedCount:Number = 0;
        for (var emitterId:String in this._trackRecords) {
            delete this._trackRecords[emitterId];
            cleanedCount++;
        }
        trace("[TrailRenderer] 已清理 " + cleanedCount + " 个闲置发射者轨迹");
        return cleanedCount;
    }
}
