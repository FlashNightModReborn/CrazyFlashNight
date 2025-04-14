import org.flashNight.arki.render.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.gesh.object.*;
import org.flashNight.naki.DataStructures.RingBuffer;

/**
 * TrailRenderer 拖影渲染器（单例）
 *
 * 用于记录并渲染攻击刀口、子弹轨迹等动态残影效果，支持样式配置、轨迹平滑、历史帧限制与自动内存清理。
 *
 * 本版本主要优化内容：
 * 1. 利用 pushMany 批量添加数据，减少循环调用和函数调用开销；
 * 2. 缓存 frequently used 属性（如 size、tail、_movementThresholdSqr、_quality等）；
 * 3. 利用 toArray 一次性生成合并路径，降低多次索引计算开销；
 * 4. 平滑算法中将 RingBuffer 数据转换为数组进行运算，结果统一用 pushMany 更新；
 * 5. 减少冗余数据转换与属性查找，提升整体性能。
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
    
    /** 拖影样式表，按样式名称存储视觉配置 */
    private var _styles:Object;
    
    /** 发射者轨迹记录表，以发射者ID为键，记录历史轨迹数据 */
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
     * 私有构造函数，禁止外部直接创建实例，请使用 getInstance() 获取单例。
     * 默认使用中等画质配置。
     */
    private function TrailRenderer() {
        this._trackRecords = {};
        this._maxFrames = 3;
        this._movementThreshold = 5.0;
        this._movementThresholdSqr = this._movementThreshold * this._movementThreshold;
    }
    
    /**
     * 获取 TrailRenderer 单例实例（懒汉式创建）。
     * @return TrailRenderer 单例实例。
     */
    public static function getInstance():TrailRenderer {
        if (_instance == null) {
            _instance = new TrailRenderer();
        }
        return _instance;
    }
    
    /**
     * 初始化可用拖影样式。
     * 通过 TrailStylesLoader 加载样式配置；若加载失败，则使用默认样式。
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
     * 设置拖影质量参数，并根据质量动态调整移动阈值与历史轨迹帧数。
     * @param q 质量参数（0~3），数值越小画质越高
     */
    public function setQuality(q:Number):Void {
        this._quality = q;
        switch(q) {
            case 0:
                this._movementThreshold = 3.0;  // 高敏感度
                this._maxFrames = 5;           // 延长历史轨迹
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
     * 添加并记录发射者当前帧的轨迹数据，并触发渲染操作。
     * 若当前输入点与上次记录末尾数据变化不足（低于设定阈值），则跳过更新与渲染，
     * 同时在低画质模式下对数据进行采样以降低计算量。
     * @param emitterId 发射者唯一标识（例如影片剪辑的 _name）
     * @param edgeArray 当前帧边缘点数组，每项包含 edge1 与 edge2 坐标对象
     * @param styleName 拖影样式名称（须存在于样式表中）
     */
    public function addTrailData(emitterId:String, edgeArray:Array, styleName:String):Void {
        var quality:Number = this._quality; // 缓存画质参数
        // 在低画质模式下采样边缘点数据（例如每隔 1 个采样一次）
        if (quality == 3 && edgeArray.length > 0) {
            edgeArray = this._subsampleEdges(edgeArray, 2);
        }
        
        var currentFrame:Number = _root.帧计时器.当前帧数;
        var trackRecords:Object = this._trackRecords;
        var record:Object = trackRecords[emitterId];
        var len:Number = edgeArray.length;
        
        // 若为首次记录，初始化轨迹记录结构
        if (record == undefined) {
            record = this._initializeRecord(edgeArray, currentFrame);
            trackRecords[emitterId] = record;
            return;
        }
        
        // 超过一定帧数未更新则重置历史轨迹，避免拖影突然跳变
        if (currentFrame - record._lastFrame > (10 - quality)) {
            for (var i:Number = 0; i < len; i++) {
                var traj:Object = record[i];
                traj.edge1.clear();
                traj.edge1.push(edgeArray[i].edge1);
                traj.edge2.clear();
                traj.edge2.push(edgeArray[i].edge2);
            }
            record._lastFrame = currentFrame;
            return;
        }
        
        // 检查当前帧数据与上一次记录末尾数据的变化是否达到阈值
        var needUpdate:Boolean = false;
        var thrSqr:Number = this._movementThresholdSqr;
        for (i = 0; i < len; i++) {
            var trajCheck:Object = record[i];
            // 利用 tail 属性直接获取最新记录，避免重复索引计算
            var lastEdge1:Object = trajCheck.edge1.tail;
            var lastEdge2:Object = trajCheck.edge2.tail;
            var newE1:Object = edgeArray[i].edge1;
            var newE2:Object = edgeArray[i].edge2;
            
            var dx1:Number = lastEdge1.x - newE1.x;
            var dy1:Number = lastEdge1.y - newE1.y;
            if (dx1 * dx1 + dy1 * dy1 > thrSqr) {
                needUpdate = true;
                break;
            }
            var dx2:Number = lastEdge2.x - newE2.x;
            var dy2:Number = lastEdge2.y - newE2.y;
            if (dx2 * dx2 + dy2 * dy2 > thrSqr) {
                needUpdate = true;
                break;
            }
        }
        
        // 数据变化不足则跳过更新和渲染
        if (!needUpdate) {
            return;
        }
        
        // 更新当前轨迹，将新帧数据添加到各个 RingBuffer 中
        for (i = 0; i < len; i++) {
            var trajUpdate:Object = record[i];
            trajUpdate.edge1.push(edgeArray[i].edge1);
            trajUpdate.edge2.push(edgeArray[i].edge2);
        }
        
        // 执行渲染操作
        this._renderTrails(record, edgeArray, styleName, currentFrame);
        
        // 更新最后活跃帧数
        record._lastFrame = currentFrame;
    }
    
    /**
     * 对原始边缘点数组进行采样，返回采样后的数组。
     * @param edgeArray 原始边缘点数组
     * @param factor 采样因子（例如 2 表示每隔 1 个采样一次）
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
     * 渲染指定发射者的轨迹记录，生成连续多边形。
     * 根据画质参数选择不同的平滑处理与透明度计算策略。
     * @param record 当前发射者的历史轨迹记录（包含 RingBuffer 数据）
     * @param edgeArray 当前帧边缘点数组（用于确定轨迹数量）
     * @param styleName 拖影样式名称
     * @param currentFrame 当前帧数
     */
    private function _renderTrails(record:Object, edgeArray:Array, styleName:String, currentFrame:Number):Void {
        var len:Number = edgeArray.length;
        var quality:Number = this._quality;
        // 统一透明度因子：低画质模式使用 50，其它使用 100
        var alphaValue:Number = (quality == 3) ? 50 : 100;
        
        for (var i:Number = 0; i < len; i++) {
            var traj:Object = record[i];
            // 获取平滑前的所有点（转换为数组，减少重复 get 调用）
            var edge1Arr:Array = traj.edge1.toArray();
            var edge2Arr:Array = traj.edge2.toArray();
            var size1:Number = edge1Arr.length;
            var size2:Number = edge2Arr.length;
            if (size1 < 2 || size2 < 2) continue;
            
            // 根据画质选择平滑策略，每隔 quality 帧执行一次平滑
            if (quality == 0 || currentFrame % quality == 0) {
                if (quality <= 1) {
                    // Catmull-Rom 平滑（批量更新）
                    this._catmullRomSmooth(traj.edge1);
                    this._catmullRomSmooth(traj.edge2);
                } else {
                    // 简单平滑
                    this._simpleSmooth(traj.edge1);
                    this._simpleSmooth(traj.edge2);
                }
            }
            
            // 重新获取平滑后的点
            edge1Arr = traj.edge1.toArray();
            edge2Arr = traj.edge2.toArray();
            
            // 合并两个边缘点数组：先 edge1 正序，再 edge2 反序，构成闭合多边形
            var mergedPoints:Array = [];
            mergedPoints = mergedPoints.concat(edge1Arr);
            mergedPoints = mergedPoints.concat(this._reverseArray(edge2Arr));
            if (mergedPoints.length > 0) {
                mergedPoints.push(mergedPoints[0]);
            }
            
            // 根据画质调用不同绘制方法
            if (quality <= 1) {
                this._drawMergedTrail(mergedPoints, alphaValue, styleName);
            } else {
                this._drawQuad(mergedPoints, styleName, alphaValue);
            }
        }
    }
    
    /**
     * 辅助方法：反转数组，不改变原数组。
     * @param arr 原数组
     * @return 反转后的新数组
     */
    private function _reverseArray(arr:Array):Array {
        var rev:Array = [];
        for (var i:Number = arr.length - 1; i >= 0; i--) {
            rev.push(arr[i]);
        }
        return rev;
    }
    
    /**
     * 绘制合并后的多边形轨迹，采用贝塞尔与直线混合绘制方式。
     * @param points 多边形点数组（edge1 正序 + edge2 反序 + 闭合首尾）
     * @param alphaValue 透明度因子（0~100）
     * @param styleName 样式名称（用于获取视觉配置）
     */
    private function _drawMergedTrail(points:Array, alphaValue:Number, styleName:String):Void {
        if (points.length < 3) return;
        var style:Object = this._styles[styleName] || this._styles["预设"];
        var fillAlpha:Number = style.fillOpacity * (alphaValue / 100);
        var lineAlpha:Number = style.lineOpacity * (alphaValue / 100);
        // 调用渲染器绘制混合形状（可包含贝塞尔曲线）
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
     * 绘制多边形（或四边形）轨迹。
     * @param quadPoints 多边形或四边形顶点数组（顺或逆时针排列，支持首尾闭合）
     * @param styleName 样式名称，用于获取视觉配置
     * @param alphaValue 当前透明衰减值（0~100）
     */
    private function _drawQuad(quadPoints:Array, styleName:String, alphaValue:Number):Void {
        if (quadPoints.length < 3) return;
        var style:Object = this._styles[styleName] || this._styles["预设"];
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
    
    /**
     * 简单平滑算法：利用相邻三个点的平均值减少轨迹抖动。
     * 先将 RingBuffer 数据转换为数组，计算完后用 pushMany 统一更新数据。
     * @param ring 包含多个 {x, y} 坐标点的 RingBuffer
     */
    private function _simpleSmooth(ring:RingBuffer):Void {
        var pts:Array = ring.toArray();
        var count:Number = pts.length;
        if (count < 3) return;
        for (var i:Number = 1; i < count - 1; i++) {
            pts[i].x = (pts[i - 1].x + pts[i].x + pts[i + 1].x) / 3;
            pts[i].y = (pts[i - 1].y + pts[i].y + pts[i + 1].y) / 3;
        }
        ring.clear();
        ring.pushMany(pts);
    }
    
    /**
     * 基于 Catmull-Rom 样条的平滑算法。
     * 先将 RingBuffer 数据转换为数组后进行插值计算，再用 pushMany 更新原数据。
     * @param ring 包含多个 {x, y} 坐标点的 RingBuffer
     * @param tension 曲线张力参数，范围 0-1，默认 0.5
     */
    private function _catmullRomSmooth(ring:RingBuffer, tension:Number):Void {
        if (tension == undefined) tension = 0.5;
        var pts:Array = ring.toArray();
        var count:Number = pts.length;
        if (count < 4) return; // 至少需要 4 个点才能有效插值
        
        // 构造带环形边界条件的数组（末尾添加到首部、首部添加到尾部）
        var points:Array = [];
        points.push(pts[pts.length - 1]);
        for (var i:Number = 0; i < count; i++) {
            points.push(pts[i]);
        }
        points.push(pts[0]);
        
        var newPoints:Array = [];
        // 核心 Catmull-Rom 插值循环：在每段内插入两个点（t=0.25, 0.75）
        for (i = 1; i < points.length - 2; i++) {
            var p0:Object = points[i - 1];
            var p1:Object = points[i];
            var p2:Object = points[i + 1];
            var p3:Object = points[i + 2];
            
            // 计算相邻点的欧氏距离
            var d01:Number = Math.sqrt((p1.x - p0.x) * (p1.x - p0.x) + (p1.y - p0.y) * (p1.y - p0.y));
            var d12:Number = Math.sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
            var d23:Number = Math.sqrt((p3.x - p2.x) * (p3.x - p2.x) + (p3.y - p2.y) * (p3.y - p2.y));
            
            var t01:Number = Math.pow(d01, tension);
            var t12:Number = Math.pow(d12, tension);
            var t23:Number = Math.pow(d23, tension);
            
            // 对 p1~p2 之间进行两次插值（t = 0.25, 0.75）
            for (var t:Number = 0.25; t < 1; t += 0.5) {
                var t2:Number = t * t;
                var t3:Number = t2 * t;
                var h1:Number = 2 * t3 - 3 * t2 + 1;
                var h2:Number = -2 * t3 + 3 * t2;
                var h3:Number = t3 - 2 * t2 + t;
                var h4:Number = t3 - t2;
                
                var m1x:Number = (p2.x - p1.x) + t12 * (((p1.x - p0.x) / t01) - ((p2.x - p0.x) / (t01 + t12)));
                var m2x:Number = (p2.x - p1.x) + t12 * (((p3.x - p2.x) / t23) - ((p3.x - p1.x) / (t12 + t23)));
                var m1y:Number = (p2.y - p1.y) + t12 * (((p1.y - p0.y) / t01) - ((p2.y - p0.y) / (t01 + t12)));
                var m2y:Number = (p2.y - p1.y) + t12 * (((p3.y - p2.y) / t23) - ((p3.y - p1.y) / (t12 + t23)));
                
                var x:Number = h1 * p1.x + h2 * p2.x + h3 * m1x + h4 * m2x;
                var y:Number = h1 * p1.y + h2 * p2.y + h3 * m1y + h4 * m2y;
                
                newPoints.push({ x: x, y: y });
            }
        }
        ring.clear();
        ring.pushMany(newPoints);
    }
    
    /**
     * 初始化新的发射者轨迹记录。
     * 为每个边缘点单独创建 RingBuffer 存储其历史轨迹数据。
     * @param edgeArray 当前帧边缘点数组，每项包含 edge1 与 edge2 坐标对象
     * @param currentFrame 当前帧数
     * @return 初始化后的记录对象，包含各边缘的 RingBuffer 数据及最后活跃帧数
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
     * 清理未活跃的发射者轨迹数据，释放内存。
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
