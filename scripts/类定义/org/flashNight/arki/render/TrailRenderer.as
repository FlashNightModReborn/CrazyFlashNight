import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.gesh.object.*;
import org.flashNight.naki.DataStructures.RingBuffer;
import org.flashNight.arki.render.VectorAfterimageRenderer;

/**
 * TrailRenderer 拖影渲染器（单例）
 *
 * 用于记录并渲染攻击刀口、子弹轨迹等动态残影效果，支持样式配置、轨迹平滑、历史帧限制与自动内存清理。
 *
 * 优化目标：
 * 1. 局部化（Localize）：将变量声明尽可能靠近使用处，减少作用域污染并提升可读性；
 * 2. 复用（Reuse）：尽可能在需要的地方复用已创建的数据结构（如数组）而非频繁创建新对象，降低内存分配与 GC 压力；
 * 3. 变量声明提前（Hoisting Awareness）：显式在方法顶部声明需要的变量，避免 AS2 变量提升造成的潜在问题，也便于统一管理。
 *
 * 本版本相较原版本的主要修改：使用 VectorAfterimageRenderer 的批量绘制接口（drawShapes 与 drawMixedShapes），
 * 先将每条轨迹（多边形）收集到一个数组，再一次性调用批量绘制方法，以减少频繁切换画布的开销，提高性能。
 */
class org.flashNight.arki.render.TrailRenderer
{
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
        loader.loadStyles(
            function(styles:Object):Void {
                self._styles = styles;
                // 样式加载成功
            },
            function():Void {
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
            }
        );
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
     *
     * @param emitterId 发射者唯一标识（例如影片剪辑的 _name）
     * @param edgeArray 当前帧边缘点数组，每项包含 edge1 与 edge2 坐标对象，如：[{edge1:{x,y}, edge2:{x,y}}, ...]
     * @param styleName 拖影样式名称（须存在于样式表中）
     */
    public function addTrailData(emitterId:String, edgeArray:Array, styleName:String):Void {
        // 统一在方法顶部声明需要的变量，避免 AS2 变量提升造成的潜在干扰
        var quality:Number = this._quality;
        var currentFrame:Number;
        var trackRecords:Object;
        var record:Object;
        var len:Number;
        var i:Number;
        var needUpdate:Boolean = false;
        var thrSqr:Number;
        var trajCheck:Object;
        var lastEdge1:Object;
        var lastEdge2:Object;
        var newE1:Object;
        var newE2:Object;
        var dx1:Number;
        var dy1:Number;
        var dx2:Number;
        var dy2:Number;
        var trajUpdate:Object;
        var traj:Object;

        // 在低画质模式下采样边缘点数据
        if (quality == 3 && edgeArray.length > 0) {
            edgeArray = this._subsampleEdges(edgeArray, 2);
        }

        currentFrame = _root.帧计时器.当前帧数;
        trackRecords = this._trackRecords;
        record = trackRecords[emitterId];
        len = edgeArray.length;

        // 若为首次记录，初始化轨迹记录结构
        if (record == undefined) {
            record = this._initializeRecord(edgeArray, currentFrame);
            trackRecords[emitterId] = record;
            return;
        }

        // 若超过一定帧数未更新则重置历史轨迹，避免拖影突然跳变
        if (currentFrame - record._lastFrame > (10 - quality)) {
            for (i = 0; i < len; i++) {
                traj = record[i];
                traj.edge1.replaceSingle(edgeArray[i].edge1);
                traj.edge2.replaceSingle(edgeArray[i].edge2);
            }
            record._lastFrame = currentFrame;
            return;
        }

        // 检查当前帧数据与上一次记录末尾数据的变化是否达到阈值
        thrSqr = this._movementThresholdSqr;
        for (i = 0; i < len; i++) {
            trajCheck = record[i];
            // 直接利用 tail 获取最新记录
            lastEdge1 = trajCheck.edge1.tail;
            lastEdge2 = trajCheck.edge2.tail;
            newE1 = edgeArray[i].edge1;
            newE2 = edgeArray[i].edge2;

            dx1 = lastEdge1.x - newE1.x;
            dy1 = lastEdge1.y - newE1.y;
            if ((dx1 * dx1 + dy1 * dy1) > thrSqr) {
                needUpdate = true;
                break;
            }

            dx2 = lastEdge2.x - newE2.x;
            dy2 = lastEdge2.y - newE2.y;
            if ((dx2 * dx2 + dy2 * dy2) > thrSqr) {
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
            trajUpdate = record[i];
            trajUpdate.edge1.push(edgeArray[i].edge1);
            trajUpdate.edge2.push(edgeArray[i].edge2);
        }

        // 执行批量渲染操作
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
        var i:Number;
        for (i = 0; i < edgeArray.length; i += factor) {
            sampled.push(edgeArray[i]);
        }
        return sampled;
    }

    /**
     * 渲染指定发射者的轨迹记录，生成连续多边形数组后一次性调用矢量残影渲染器的批量绘制方法。
     *
     * 根据画质参数选择不同的平滑处理策略，同时在收集完所有轨迹多边形后，决定调用：
     *  - drawMixedShapes（可包含曲线插值，质量较高）
     *  - drawShapes（主要是简单折线/多边形绘制）
     *
     * @param record 当前发射者的历史轨迹记录（包含 RingBuffer 数据）
     * @param edgeArray 当前帧边缘点数组（用于确定轨迹数量）
     * @param styleName 拖影样式名称
     * @param currentFrame 当前帧数
     */
    private function _renderTrails(record:Object, edgeArray:Array, styleName:String, currentFrame:Number):Void {
        var len:Number = edgeArray.length;
        var quality:Number = this._quality;
        var alphaValue:Number = (quality == 3) ? 50 : 100;

        // 用两个数组分别收集：需要使用 drawMixedShapes 的多边形集合（mixedPolygons）
        // 和需要使用 drawShapes 的多边形集合（simplePolygons）
        var mixedPolygons:Array = [];
        var simplePolygons:Array = [];

        var i:Number;
        for (i = 0; i < len; i++) {
            var traj:Object = record[i];

            // 获取平滑前的所有点
            var edge1Arr:Array = traj.edge1.toArray();
            var edge2Arr:Array = traj.edge2.toArray();
            var size1:Number = edge1Arr.length;
            var size2:Number = edge2Arr.length;

            if (size1 < 2 || size2 < 2) {
                continue;
            }

            // 根据画质选择平滑策略
            if (quality == 0 || currentFrame % quality == 0) {
                if (quality <= 1) {
                    // Catmull-Rom 平滑
                    this._catmullRomSmooth(traj.edge1);
                    this._catmullRomSmooth(traj.edge2);
                } else {
                    // 简单平滑
                    this._simpleSmooth(traj.edge1);
                    this._simpleSmooth(traj.edge2);
                }
            }

            // 重新获取平滑后的点, 先 edge1 正序，再 edge2 反序
            edge1Arr = traj.edge1.toArray();
            edge2Arr = traj.edge2.toReversedArray();

            // 合并两个边缘点数组，构成闭合多边形
            var mergedPoints:Array = [];
            mergedPoints = mergedPoints.concat(edge1Arr);
            mergedPoints = mergedPoints.concat(edge2Arr);
            if (mergedPoints.length > 0) {
                // 闭合首尾
                mergedPoints.push(mergedPoints[0]);
            }

            // 根据画质区分：高画质(<=1) 使用 drawMixedShapes，低画质(>1) 使用 drawShapes
            if (quality <= 1) {
                // 收集到 mixedPolygons
                if (mergedPoints.length >= 3) {
                    mixedPolygons.push(mergedPoints);
                }
            } else {
                // 收集到 simplePolygons
                if (mergedPoints.length >= 3) {
                    simplePolygons.push(mergedPoints);
                }
            }
        }

        // 批量绘制：一次调用 drawMixedShapes 或 drawShapes
        if (mixedPolygons.length > 0) {
            this._drawMixedTrailBatch(mixedPolygons, alphaValue, styleName);
        }
        if (simplePolygons.length > 0) {
            this._drawSimpleTrailBatch(simplePolygons, styleName, alphaValue);
        }
    }

    /**
     * 使用 VectorAfterimageRenderer 的 drawMixedShapes 方法，批量绘制混合曲线形状。
     *
     * @param polygonList 多个多边形数组（每个元素均为点集合）
     * @param alphaValue 透明度因子（0~100）
     * @param styleName 拖影样式名称
     */
    private function _drawMixedTrailBatch(polygonList:Array, alphaValue:Number, styleName:String):Void {
        if (polygonList.length == 0) return;
        var style:Object = this._styles[styleName] || this._styles["预设"];
        var fillAlpha:Number = style.fillOpacity * (alphaValue / 100);
        var lineAlpha:Number = style.lineOpacity * (alphaValue / 100);

        VectorAfterimageRenderer.instance.drawMixedShapes(
            polygonList,
            style.color,        // 填充颜色
            style.lineColor,    // 线条颜色
            style.lineWidth,    // 线宽
            fillAlpha,          // 填充透明度
            lineAlpha,          // 线条透明度
            true,               // 是否闭合每个形状
            5                   // 残影数量（此处可根据需要自行调整或使用默认值）
        );
    }

    /**
     * 使用 VectorAfterimageRenderer 的 drawShapes 方法，批量绘制简单折线/多边形。
     *
     * @param polygonList 多个多边形数组（每个元素均为点集合）
     * @param styleName 拖影样式名称
     * @param alphaValue 透明度因子（0~100）
     */
    private function _drawSimpleTrailBatch(polygonList:Array, styleName:String, alphaValue:Number):Void {
        if (polygonList.length == 0) return;
        var style:Object = this._styles[styleName] || this._styles["预设"];
        var fillAlpha:Number = style.fillOpacity * (alphaValue / 100);
        var lineAlpha:Number = style.lineOpacity * (alphaValue / 100);

        VectorAfterimageRenderer.instance.drawShapes(
            polygonList,
            style.color,        // 填充颜色
            style.lineColor,    // 线条颜色
            style.lineWidth,    // 线宽
            fillAlpha,          // 填充透明度
            lineAlpha,          // 线条透明度
            3                   // 残影数量（此处示例写 3，可根据需要调整）
        );
    }

    /**
     * 简单平滑算法：利用相邻三个点的平均值减少轨迹抖动。
     * 先将 RingBuffer 数据转换为数组，计算完后用 reset 统一更新数据。
     * @param ring 包含多个 {x, y} 坐标点的 RingBuffer
     */
    private function _simpleSmooth(ring:RingBuffer):Void {
        var pts:Array = ring.toArray();
        var count:Number = pts.length;
        var i:Number;
        if (count < 3) return;

        for (i = 1; i < count - 1; i++) {
            pts[i].x = (pts[i - 1].x + pts[i].x + pts[i + 1].x) / 3;
            pts[i].y = (pts[i - 1].y + pts[i].y + pts[i + 1].y) / 3;
        }

        ring.reset(pts);
    }

    /**
     * 基于 Catmull-Rom 样条的平滑算法。
     * 先将 RingBuffer 数据转换为数组后进行插值计算，再用 reset 更新原数据。
     * @param ring 包含多个 {x, y} 坐标点的 RingBuffer
     * @param tension 曲线张力参数，范围 0-1，默认 0.5
     */
    private function _catmullRomSmooth(ring:RingBuffer, tension:Number):Void {
        var i:Number;
        var pts:Array;
        var count:Number;
        var points:Array;
        var newPoints:Array;
        var p0:Object, p1:Object, p2:Object, p3:Object;
        var d01:Number, d12:Number, d23:Number;
        var t01:Number, t12:Number, t23:Number;
        var t:Number, t2:Number, t3:Number;
        var h1:Number, h2:Number, h3:Number, h4:Number;
        var m1x:Number, m2x:Number, m1y:Number, m2y:Number;
        var x:Number, y:Number;

        if (tension == undefined) tension = 0.5;
        pts = ring.toArray();
        count = pts.length;
        if (count < 4) return; // 至少需要 4 个点才能有效插值

        // 构造带环形边界条件的数组（末尾添加到首部、首部添加到尾部）
        points = [];
        points.push(pts[pts.length - 1]);
        for (i = 0; i < count; i++) {
            points.push(pts[i]);
        }
        points.push(pts[0]);

        newPoints = [];

        // 核心 Catmull-Rom 插值循环：在每段内插入两个点（t=0.25, 0.75）
        for (i = 1; i < points.length - 2; i++) {
            p0 = points[i - 1];
            p1 = points[i];
            p2 = points[i + 1];
            p3 = points[i + 2];

            d01 = Math.sqrt((p1.x - p0.x)*(p1.x - p0.x) + (p1.y - p0.y)*(p1.y - p0.y));
            d12 = Math.sqrt((p2.x - p1.x)*(p2.x - p1.x) + (p2.y - p1.y)*(p2.y - p1.y));
            d23 = Math.sqrt((p3.x - p2.x)*(p3.x - p2.x) + (p3.y - p2.y)*(p3.y - p2.y));

            t01 = Math.pow(d01, tension);
            t12 = Math.pow(d12, tension);
            t23 = Math.pow(d23, tension);

            // 对 p1~p2 之间插值
            var stepList:Array = [0.25, 0.75]; // 这里插入两个点
            for (var s:Number = 0; s < stepList.length; s++) {
                t = stepList[s];
                t2 = t * t;
                t3 = t2 * t;
                h1 = 2 * t3 - 3 * t2 + 1;
                h2 = -2 * t3 + 3 * t2;
                h3 = t3 - 2 * t2 + t;
                h4 = t3 - t2;

                m1x = (p2.x - p1.x) + t12 * (((p1.x - p0.x)/t01) - ((p2.x - p0.x)/(t01 + t12)));
                m2x = (p2.x - p1.x) + t12 * (((p3.x - p2.x)/t23) - ((p3.x - p1.x)/(t12 + t23)));
                m1y = (p2.y - p1.y) + t12 * (((p1.y - p0.y)/t01) - ((p2.y - p0.y)/(t01 + t12)));
                m2y = (p2.y - p1.y) + t12 * (((p3.y - p2.y)/t23) - ((p3.y - p1.y)/(t12 + t23)));

                x = h1 * p1.x + h2 * p2.x + h3 * m1x + h4 * m2x;
                y = h1 * p1.y + h2 * p2.y + h3 * m1y + h4 * m2y;

                newPoints.push({ x: x, y: y });
            }
        }

        ring.reset(newPoints);
    }

    /**
     * 初始化新的发射者轨迹记录。
     * 为每个边缘点单独创建 RingBuffer 存储其历史轨迹数据。
     *
     * @param edgeArray 当前帧边缘点数组，每项包含 edge1 与 edge2 坐标对象
     * @param currentFrame 当前帧数
     * @return 初始化后的记录对象，包含各边缘的 RingBuffer 数据及最后活跃帧数
     */
    private function _initializeRecord(edgeArray:Array, currentFrame:Number):Object {
        var rec:Object = { _lastFrame: currentFrame };
        var len:Number = edgeArray.length;
        var i:Number;
        for (i = 0; i < len; i++) {
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
     *
     * 此处示例直接全部清理，如需区分“活跃”与“非活跃”可自行添加逻辑判断。
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
