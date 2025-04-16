import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.gesh.object.*;
import org.flashNight.naki.DataStructures.RingBuffer;
import org.flashNight.arki.render.VectorAfterimageRenderer;
import org.flashNight.sara.util.* ;

/**
 * TrailRenderer 拖影渲染器（单例）
 *
 * 用于记录并渲染攻击刀口、子弹轨迹等动态残影效果，支持样式配置、轨迹平滑、
 * 历史帧限制与自动内存清理等功能。通过批量绘制的方式减少反复创建画布的开销，
 * 并提供多种质量（画质）模式以适应不同性能需求。
 *
 * 优化要点：
 * 1. 在需要的时候声明局部变量，并在循环开始之前统一 var 声明，避免循环体内部重复声明；
 * 2. 合理使用 do...while 结构，减少不必要的循环判断或重复逻辑；
 * 3. 提前中止判断减少不必要的平滑或插值计算，在性能和可读性之间取得平衡。
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
     * 0：最高画质（高敏感、最多历史帧、曲线平滑精细）
     * 1：高画质
     * 2：中画质（默认）
     * 3：低画质（低敏感、少历史帧、数据采样/简单平滑）
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

    /** 移动最小差异阈值的平方（用于避免频繁调用 Math.sqrt） */
    private var _movementThresholdSqr:Number;

    // --------------------------
    // 构造与初始化
    // --------------------------

    /**
     * 私有构造函数，禁止外部直接创建实例，请使用 getInstance() 获取单例。
     * 默认使用中等画质 (2)。
     */
    private function TrailRenderer() {
        this._trackRecords = {};
        this._maxFrames = 3;             // 与 _quality=2 对应的默认值
        this._movementThreshold = 5.0;    // 与 _quality=2 对应的默认值
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
     * 初始化拖影样式。
     * 尝试通过 TrailStylesLoader 加载样式配置；若加载失败，则使用默认样式。
     */
    public function initStyles():Void {
        var loader:TrailStylesLoader = TrailStylesLoader.getInstance();
        var self:TrailRenderer = this;

        loader.loadStyles(
            function(styles:Object):Void {
                self._styles = styles;
                // 样式加载成功，不做额外处理
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
        switch (q) {
            case 0: // 最高画质
                this._movementThreshold = 3.0;
                this._maxFrames = 5;
                break;
            case 1:
                this._movementThreshold = 5.0;
                this._maxFrames = 4;
                break;
            case 2: // 中画质
                this._movementThreshold = 8.0;
                this._maxFrames = 3;
                break;
            case 3: // 低画质
                this._movementThreshold = 10.0;
                this._maxFrames = 2;
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
     * 添加并记录发射者当前帧的轨迹数据，并根据需要触发渲染操作。
     * 
     * - 若当前输入点与上次记录末尾数据变化不足（低于设定阈值），则跳过更新与渲染；
     * - 在低画质模式下对数据进行采样，以减少数据点数量；
     * - 当轨迹数据确有变化时，会调用 _renderTrails 进行批量绘制。
     *
     * @param emitterId 发射者唯一标识（例如影片剪辑的 _name）
     * @param edgeArray 当前帧边缘点数组，每项包含 {edge1:{x,y}, edge2:{x,y}}
     * @param styleName 拖影样式名称（须存在于样式表中）
     */
    public function addTrailData(emitterId:String, edgeArray:Array, styleName:String):Void {
        var quality:Number = this._quality;
        var len:Number = edgeArray.length;

        // 低画质模式下做简单采样，减少数据量
        if (quality == 3 && len > 0) {
            edgeArray = _subsampleEdges(edgeArray, 2);
            len = edgeArray.length;
        }

        // 若没有有效点，直接返回
        if (len == 0) {
            return;
        }

        var currentFrame:Number = _root.帧计时器.当前帧数;
        var trackRecords:Object = this._trackRecords;
        var record:Object = trackRecords[emitterId];

        // 如果是首次记录，初始化轨迹结构
        if (record == undefined) {
            trackRecords[emitterId] = _initializeRecord(edgeArray, currentFrame);
            return;
        }

        // 超过一定帧数未更新则重置，以避免残影跳变
        if (currentFrame - record._lastFrame > (10 - quality)) {
            var resetIdx:Number = 0;
            var resetTraj:Object;
            var resetEdge:Object;
            do {
                resetTraj = record[resetIdx];
                resetEdge = edgeArray[resetIdx];
                resetTraj.edge1.replaceSingle(resetEdge.edge1);
                resetTraj.edge2.replaceSingle(resetEdge.edge2);
            } while (++resetIdx < len);

            record._lastFrame = currentFrame;
            return;
        }

        // ------------ 阈值判断逻辑（变量提前声明） ------------
        var thrSqr:Number = this._movementThresholdSqr;
        var needUpdate:Boolean = false;
        var j:Number = 0;
        var trajCheck:Object, lastE1:Object, lastE2:Object;
        var newE1:Object, newE2:Object;
        var dx1:Number, dy1:Number, dx2:Number, dy2:Number;

        do {
            trajCheck = record[j];
            lastE1 = trajCheck.edge1.tail;  // 最新一帧记录
            lastE2 = trajCheck.edge2.tail;
            newE1 = edgeArray[j].edge1;
            newE2 = edgeArray[j].edge2;

            dx1 = lastE1.x - newE1.x;
            dy1 = lastE1.y - newE1.y;
            if ((dx1 * dx1 + dy1 * dy1) > thrSqr) {
                needUpdate = true;
                break;
            }

            dx2 = lastE2.x - newE2.x;
            dy2 = lastE2.y - newE2.y;
            if ((dx2 * dx2 + dy2 * dy2) > thrSqr) {
                needUpdate = true;
                break;
            }
        } while (++j < len);

        // 若没有超出阈值则不更新也不渲染
        if (!needUpdate) {
            return;
        }

        // ------------ 将新数据压入 RingBuffer ------------
        var pushIdx:Number = 0;
        var trajUpdate:Object, edgeData:Object;
        do {
            trajUpdate = record[pushIdx];
            edgeData = edgeArray[pushIdx];
            trajUpdate.edge1.push(edgeData.edge1);
            trajUpdate.edge2.push(edgeData.edge2);
        } while (++pushIdx < len);

        // 进行批量绘制
        _renderTrails(record, edgeArray, styleName, currentFrame);
        record._lastFrame = currentFrame;
    }

    /**
     * 对指定的 edgeArray 进行采样（每隔 factor 个保留一个）。
     * @param edgeArray 原始边缘点数组
     * @param factor 采样因子，例如 2 表示间隔 1 个采样一次
     * @return 采样后的边缘点数组
     */
    private function _subsampleEdges(edgeArray:Array, factor:Number):Array {
        var sampled:Array = [];
        var i:Number = 0;
        var len:Number = edgeArray.length;
        for (; i < len; i += factor) {
            sampled.push(edgeArray[i]);
        }
        return sampled;
    }

    /**
     * 渲染指定发射者的轨迹记录，生成多边形或曲线形状数组后一次性调用批量绘制方法。
     * @param record 当前发射者的历史轨迹记录（包含 RingBuffer）
     * @param edgeArray 当前帧边缘点数组（用于确定轨迹数量）
     * @param styleName 拖影样式名称
     * @param currentFrame 当前帧数
     */
    private function _renderTrails(record:Object, edgeArray:Array, styleName:String, currentFrame:Number):Void {
        var quality:Number = this._quality;
        var alphaValue:Number = (quality == 3) ? 50 : 100;

        // 准备两个数组分别收集需要混合曲线绘制与简单多边形绘制的点集
        var mixedPolygons:Array = [];
        var simplePolygons:Array = [];

        var len:Number = edgeArray.length;
        var i:Number = 0;
        var traj:Object, edge1Arr:Array, edge2Arr:Array;
        var size1:Number, size2:Number;
        var mergedPoints:Array;

        do {
            traj = record[i];
            edge1Arr = traj.edge1.toArray();
            edge2Arr = traj.edge2.toArray();
            size1 = edge1Arr.length;
            size2 = edge2Arr.length;
            
            // 数据量不足无法形成有效多边形
            if (size1 < 2 || size2 < 2) {
                continue;
            }

            // 在一定帧频率下或高质量时进行平滑
            if (quality <= 1 || currentFrame % quality == 0) {
                if (quality <= 1) {
                    // Catmull-Rom 高质量平滑
                    _catmullRomSmooth(traj.edge1);
                    _catmullRomSmooth(traj.edge2);
                } else {
                    // 简单平滑
                    _simpleSmooth(traj.edge1);
                    _simpleSmooth(traj.edge2);
                }
            }

            // 再次获取平滑后的点
            edge1Arr = traj.edge1.toArray();
            edge2Arr = traj.edge2.toReversedArray();

            // 构建闭合多边形：先 edge1 正序，再 edge2 反序
            mergedPoints = [];
            mergedPoints = mergedPoints.concat(edge1Arr);
            mergedPoints = mergedPoints.concat(edge2Arr);

            // 若合并后有效点 >= 3，才能形成多边形
            if (mergedPoints.length >= 3) {
                // 闭合首尾
                mergedPoints.push(mergedPoints[0]);

                // 高画质 (0 或 1) -> mixedPolygons，否则 simplePolygons
                if (quality <= 1) {
                    mixedPolygons.push(mergedPoints);
                } else {
                    simplePolygons.push(mergedPoints);
                }
            }
        } while (++i < len);

        // 批量调用矢量绘制接口
        if (mixedPolygons.length > 0) {
            _drawMixedTrailBatch(mixedPolygons, alphaValue, styleName);
        }
        if (simplePolygons.length > 0) {
            _drawSimpleTrailBatch(simplePolygons, styleName, alphaValue);
        }
    }

    /**
     * 使用 VectorAfterimageRenderer 的 drawMixedShapes 方法批量绘制混合曲线多边形。
     * @param polygonList 多个多边形点数组
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
            style.color,
            style.lineColor,
            style.lineWidth,
            fillAlpha,
            lineAlpha,
            true,   // 是否闭合每个形状
            5       // 残影数量示例，可按需求调整或使用默认
        );
    }

    /**
     * 使用 VectorAfterimageRenderer 的 drawShapes 方法批量绘制简单多边形。
     * @param polygonList 多个多边形点数组
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
            style.color,
            style.lineColor,
            style.lineWidth,
            fillAlpha,
            lineAlpha,
            3       // 残影数量示例
        );
    }

    /**
     * 使用简单平滑算法，利用相邻三个点的平均值减少抖动。
     * @param ring 包含 {x, y} 坐标点的 RingBuffer
     */
    private function _simpleSmooth(ring:RingBuffer):Void {
        var pts:Array = ring.toArray();
        var count:Number = pts.length;
        if (count < 3) return;

        var i:Number;
        var pi:Vector, pi0:Vector, pi1:Vector;
        for (i = 1; i < count - 1; i++) {
            pi = pts[i];
            pi0 = pts[i - 1];
            pi1 = pts[i + 1];

            pts[i].x = (pi0.x + pi.x + pi1.x) / 3;
            pts[i].y = (pi0.y + pi.y + pi1.y) / 3;
        }
        ring.reset(pts);
    }

    /**
     * 使用 Catmull-Rom 样条插值对 RingBuffer 数据进行平滑。
     * @param ring 包含 {x, y} 坐标点的 RingBuffer
     * @param tension 曲线张力参数（0~1），默认 0.5
     */
    private function _catmullRomSmooth(ring:RingBuffer, tension:Number):Void {
        if (tension == undefined) tension = 0.5;

        var pts:Array = ring.toArray();
        var count:Number = pts.length;
        if (count < 4) return; // 至少需要4个点

        // 构建带首尾附加点的序列
        var points:Array = [];
        var i:Number = 0;
        var len:Number;
        points.push(pts[count - 1]);
        for (; i < count; i++) {
            points.push(pts[i]);
        }
        points.push(pts[0]);

        var newPoints:Array = [];
        var p0:Object, p1:Object, p2:Object, p3:Object;
        var d01:Number, d12:Number, d23:Number;
        var t01:Number, t12:Number, t23:Number;
        var t:Number, t2:Number, t3:Number;
        var h1:Number, h2:Number, h3:Number, h4:Number;
        var m1x:Number, m2x:Number, m1y:Number, m2y:Number;
        var x:Number, y:Number;

        // 采用固定插入两个点的做法：t=0.25, 0.75
        var stepList:Array = [0.25, 0.75];

        len = points.length - 2;
        var idx:Number = 1;
        for (; idx < len; idx++) {
            p0 = points[idx - 1];
            p1 = points[idx];
            p2 = points[idx + 1];
            p3 = points[idx + 2];

            d01 = _distance(p0, p1);
            d12 = _distance(p1, p2);
            d23 = _distance(p2, p3);

            t01 = Math.pow(d01, tension);
            t12 = Math.pow(d12, tension);
            t23 = Math.pow(d23, tension);

            // 对 p1 ~ p2 内进行曲线插值
            var s:Number = 0;
            var stepCount:Number = stepList.length;
            for (; s < stepCount; s++) {
                t = stepList[s];
                t2 = t * t;
                t3 = t2 * t;

                h1 =  2 * t3 - 3 * t2 + 1;
                h2 = -2 * t3 + 3 * t2;
                h3 =      t3 - 2 * t2 + t;
                h4 =      t3 -     t2;

                m1x = (p2.x - p1.x) + t12 * (((p1.x - p0.x) / t01) - ((p2.x - p0.x) / (t01 + t12)));
                m2x = (p2.x - p1.x) + t12 * (((p3.x - p2.x) / t23) - ((p3.x - p1.x) / (t12 + t23)));
                m1y = (p2.y - p1.y) + t12 * (((p1.y - p0.y) / t01) - ((p2.y - p0.y) / (t01 + t12)));
                m2y = (p2.y - p1.y) + t12 * (((p3.y - p2.y) / t23) - ((p3.y - p1.y) / (t12 + t23)));

                x = h1 * p1.x + h2 * p2.x + h3 * m1x + h4 * m2x;
                y = h1 * p1.y + h2 * p2.y + h3 * m1y + h4 * m2y;

                newPoints.push({ x: x, y: y });
            }
        }

        ring.reset(newPoints);
    }

    /**
     * 获取两点间距离。
     * @param a {x, y}
     * @param b {x, y}
     * @return 距离值
     */
    private function _distance(a:Object, b:Object):Number {
        var dx:Number = a.x - b.x;
        var dy:Number = a.y - b.y;
        return Math.sqrt(dx * dx + dy * dy);
    }

    /**
     * 初始化新的发射者轨迹记录，为每个 edge 坐标创建 RingBuffer。
     * @param edgeArray 当帧边缘点数组
     * @param currentFrame 当前帧数
     * @return 发射者的轨迹记录对象
     */
    private function _initializeRecord(edgeArray:Array, currentFrame:Number):Object {
        var rec:Object = { _lastFrame: currentFrame };
        var len:Number = edgeArray.length;
        var i:Number = 0;
        do {
            var edg:Object = edgeArray[i];
            rec[i] = {
                edge1: new RingBuffer(this._maxFrames, null, [edg.edge1]),
                edge2: new RingBuffer(this._maxFrames, null, [edg.edge2])
            };
        } while (++i < len);

        return rec;
    }

    // --------------------------
    // 内存管理
    // --------------------------

    /**
     * 清理未活跃或闲置的发射者轨迹数据，释放内存。
     * 此处演示为全量清理，可根据项目逻辑进行筛选。
     * @return 被清理的发射者数量
     */
    public function cleanMemory():Number {
        var cleanedCount:Number = 0;
        for (var emitterId:String in this._trackRecords) {
            delete this._trackRecords[emitterId];
            cleanedCount++;
        }
        trace("[TrailRenderer] 已清理 " + cleanedCount + " 个闲置发射者轨迹数据");
        return cleanedCount;
    }
}
