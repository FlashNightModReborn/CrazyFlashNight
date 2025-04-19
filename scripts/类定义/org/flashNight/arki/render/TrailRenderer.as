// 文件路径：org/flashNight/arki/render/TrailRenderer.as

import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.gesh.object.*;
import org.flashNight.naki.DataStructures.RingBuffer;
import org.flashNight.arki.render.VectorAfterimageRenderer;
import org.flashNight.arki.render.TrailStyleManager;
import org.flashNight.sara.util.*;

/**
 * TrailRenderer
 * =============
 * 拖影渲染器（单例）
 *
 * 功能概述：
 *   - 记录并渲染攻击刀口、子弹运动等动态残影轨迹；
 *   - 支持 4 档画质、历史帧长度限制、Catmull‑Rom 平滑、低画质采样；
 *   - 通过批量绘制接口减少 MovieClip 创建与 beginFill/endFill 频率；
 *   - 内置内存清理接口，便于长时间运行下的资源回收。
 *
 * 改动亮点（相对旧版）：
 * ------------------------------------------------------------
 * 1. **样式完全解耦**  
 *    渲染器不再维护 _styles，而是通过 _styleManager.getStyle(styleName)
 *    动态获取配置，单一职责更清晰。
 *
 * 2. **可扩展样式加载**  
 *    TrailStyleManager 支持外部 XML/JSON 加载与运行时 update，
 *    TrailRenderer 无需改动即可接受新样式。
 *
 * 3. **其他逻辑保持不变**  
 *    轨迹采样、阈值判断、RingBuffer 历史帧、平滑算法等性能优化策略原样保留。
 *
 * 使用步骤（示例）：
 * ------------------------------------------------------------
 *   // 1) 启动时加载样式，仅需一次
 *   TrailStyleManager.getInstance().loadStyles();
 *
 *   // 2) 游戏循环中不断投喂轨迹
 *   TrailRenderer.getInstance().addTrailData(emitterId, edges, "刀光");
 *
 *   // 3) 某个时机做内存清理
 *   TrailRenderer.getInstance().cleanMemory();
 *
 * @author flashNight
 */
class org.flashNight.arki.render.TrailRenderer
{
    // --------------------------
    // 静态 ‑ 单例
    // --------------------------
    private static var _instance:TrailRenderer;

    /**
     * 获取 TrailRenderer 单例实例（懒汉式）。
     */
    public static function getInstance():TrailRenderer
    {
        if (_instance == null) _instance = new TrailRenderer();
        return _instance;
    }

    // --------------------------
    // 成员变量
    // --------------------------
    /** 画质等级（0=最高, 3=最低） */
    private var _quality:Number = 2;

    /** 发射者 -> 轨迹记录表 */
    private var _trackRecords:Object;

    /** 单条轨迹允许的最大历史帧数 */
    private var _maxFrames:Number;

    /** 移动阈值平方（像素^2）；低画质阈值更大 */
    private var _movementThresholdSqr:Number;

    /** 样式管理器引用（单例） */
    private var _styleManager:TrailStyleManager;

    // --------------------------
    // 构造函数
    // --------------------------
    /**
     * 私有构造函数 —— 请使用 getInstance()。
     */
    private function TrailRenderer()
    {
        _trackRecords = {};
        _styleManager = TrailStyleManager.getInstance();
        setQuality(_quality); // 根据默认画质初始化阈值
    }

    // --------------------------
    // 画质与阈值设置
    // --------------------------
    /**
     * 设置画质，并同步更新移动阈值与历史帧长度。
     *
     * @param q 画质等级 (0‑3)
     */
    public function setQuality(q:Number):Void
    {
        _quality = q;

        switch (q)
        {
            case 0: _movementThresholdSqr = 3  * 3;  _maxFrames = 5; break;
            case 1: _movementThresholdSqr = 5  * 5;  _maxFrames = 4; break;
            case 2: _movementThresholdSqr = 8  * 8;  _maxFrames = 3; break;
            case 3: _movementThresholdSqr = 10 * 10; _maxFrames = 2; break;
            default:_movementThresholdSqr = 5  * 5;  _maxFrames = 3;
        }
    }

    // --------------------------
    // 轨迹记录与渲染入口
    // --------------------------
    /**
     * 将当前帧边缘数据写入记录，并在必要时触发渲染。
     *
     * @param emitterId  发射者唯一标识
     * @param edgeArray  [{edge1:{x,y}, edge2:{x,y}}, ...]
     * @param styleName  样式名称（交由 TrailStyleManager 管理）
     */
    public function addTrailData(emitterId:String, edgeArray:Array, styleName:String):Void
    {
        var quality:Number = _quality;
        var len:Number     = edgeArray.length;

        // 低画质采样：每 2 个点保留 1 个
        if (quality == 3 && len > 0)
        {
            edgeArray = _subsampleEdges(edgeArray, 2);
            len       = edgeArray.length;
        }
        if (len == 0) return;

        var currentFrame:Number = _root.帧计时器.当前帧数;
        var record:Object       = _trackRecords[emitterId];

        // 首次创建
        if (record == undefined)
        {
            _trackRecords[emitterId] = _initializeRecord(edgeArray, currentFrame);
            return;
        }

        // 若长时间未更新则强制重置
        if (currentFrame - record._lastFrame > (10 - quality))
        {
            var ri:Number = 0;
            do
            {
                var traj:Object = record[ri];
                var edg:Object  = edgeArray[ri];
                traj.edge1.replaceSingle(edg.edge1);
                traj.edge2.replaceSingle(edg.edge2);
            } while (++ri < len);

            record._lastFrame = currentFrame;
            return;
        }

        // ----------- 阈值检查：判断是否需要追加历史帧 -----------
        var needUpdate:Boolean = false;
        var ti:Number          = 0;
        do
        {
            var track:Object = record[ti];
            var last1:Object = track.edge1.tail;
            var last2:Object = track.edge2.tail;
            var new1:Object  = edgeArray[ti].edge1;
            var new2:Object  = edgeArray[ti].edge2;

            // edge1
            var dx:Number = last1.x - new1.x;
            var dy:Number = last1.y - new1.y;
            if ((dx*dx + dy*dy) > _movementThresholdSqr) { needUpdate = true; break; }

            // edge2
            dx = last2.x - new2.x;
            dy = last2.y - new2.y;
            if ((dx*dx + dy*dy) > _movementThresholdSqr) { needUpdate = true; break; }
        } while (++ti < len);

        if (!needUpdate) return;

        // ----------- 写入历史帧 -----------
        var wi:Number = 0;
        do
        {
            var trajUp:Object = record[wi];
            var edgUp:Object  = edgeArray[wi];
            trajUp.edge1.push(edgUp.edge1);
            trajUp.edge2.push(edgUp.edge2);
        } while (++wi < len);

        // ----------- 批量渲染 -----------
        _renderTrails(record, edgeArray, styleName, currentFrame);
        record._lastFrame = currentFrame;
    }

    // --------------------------
    // 私有工具：渲染实现
    // --------------------------
    private function _renderTrails(record:Object, edgeArray:Array, styleName:String, currentFrame:Number):Void
    {
        var quality:Number  = _quality;
        var alphaValue:Number = (quality == 3) ? 50 : 100;

        var mixedPolygons:Array   = [];
        var simplePolygons:Array  = [];

        var len:Number = edgeArray.length;
        var i:Number   = 0;
        do
        {
            var traj:Object   = record[i];
            var edge1:Array   = traj.edge1.toArray();
            var edge2:Array   = traj.edge2.toArray().reverse();

            if (edge1.length < 2 || edge2.length < 2) continue;

            // 视画质做平滑
            if (quality <= 1 || currentFrame % quality == 0)
            {
                if (quality <= 1)
                {
                    _catmullRomSmooth(traj.edge1);
                    _catmullRomSmooth(traj.edge2);
                }
                else
                {
                    _simpleSmooth(traj.edge1);
                    _simpleSmooth(traj.edge2);
                }
                edge1 = traj.edge1.toArray();
                edge2 = traj.edge2.toArray().reverse();
            }

            var poly:Array = [];
            poly = poly.concat(edge1);
            poly = poly.concat(edge2);
            if (poly.length >= 3) poly.push(poly[0]); // 闭合

            if (poly.length >= 3)
            {
                if (quality <= 1) mixedPolygons.push(poly);
                else              simplePolygons.push(poly);
            }
        } while (++i < len);

        // ----------- 批量绘制 -----------
        if (mixedPolygons.length > 0)
        {
            _drawMixedTrailBatch(mixedPolygons, alphaValue, styleName);
        }
        if (simplePolygons.length > 0)
        {
            _drawSimpleTrailBatch(simplePolygons, styleName, alphaValue);
        }
    }

    // --------------------------
    // 私有工具：绘制封装
    // --------------------------
    private function _drawMixedTrailBatch(polys:Array, alphaVal:Number, styleName:String):Void
    {
        if (polys.length == 0) return;

        var style:Object  = _styleManager.getStyle(styleName);
        var fillAlpha:Number = style.fillOpacity * (alphaVal / 100);
        var lineAlpha:Number = style.lineOpacity * (alphaVal / 100);

        VectorAfterimageRenderer.instance.drawMixedShapes(
            polys,
            style.color,
            style.lineColor,
            style.lineWidth,
            fillAlpha,
            lineAlpha,
            true,   // 闭合
            5       // 残影数量示例
        );
    }

    private function _drawSimpleTrailBatch(polys:Array, styleName:String, alphaVal:Number):Void
    {
        if (polys.length == 0) return;

        var style:Object  = _styleManager.getStyle(styleName);
        var fillAlpha:Number = style.fillOpacity * (alphaVal / 100);
        var lineAlpha:Number = style.lineOpacity * (alphaVal / 100);

        VectorAfterimageRenderer.instance.drawShapes(
            polys,
            style.color,
            style.lineColor,
            style.lineWidth,
            fillAlpha,
            lineAlpha,
            3   // 残影数量示例
        );
    }

    // --------------------------
    // 私有工具：平滑、采样等算法
    // --------------------------
    private function _simpleSmooth(ring:RingBuffer):Void
    {
        var pts:Array = ring.toArray();
        var n:Number  = pts.length;
        if (n < 3) return;

        for (var k:Number = 1; k < n - 1; k++)
        {
            var p0:Object = pts[k - 1], p:Object = pts[k], p1:Object = pts[k + 1];
            p.x = (p0.x + p.x + p1.x) / 3;
            p.y = (p0.y + p.y + p1.y) / 3;
        }
        ring.reset(pts);
    }

    private function _catmullRomSmooth(ring:RingBuffer, tension:Number):Void
    {
        if (tension == undefined) tension = 0.5;

        var pts:Array = ring.toArray();
        var n:Number  = pts.length;
        if (n < 4) return;

        // 带首尾环绕
        var ptsWrap:Array = [];
        ptsWrap.push(pts[n-1]);
        for (var a:Number=0; a<n; a++) ptsWrap.push(pts[a]);
        ptsWrap.push(pts[0]);

        var newPts:Array   = [];
        var stepList:Array = [0.25, 0.75];

        for (var i:Number = 1; i < ptsWrap.length - 2; i++)
        {
            var p0:Object = ptsWrap[i-1], p1:Object = ptsWrap[i], p2:Object = ptsWrap[i+1], p3:Object = ptsWrap[i+2];
            var d01:Number = _dist(p0,p1), d12:Number = _dist(p1,p2), d23:Number = _dist(p2,p3);
            var t01:Number = Math.pow(d01,tension), t12:Number = Math.pow(d12,tension), t23:Number = Math.pow(d23,tension);

            for (var s:Number = 0; s < stepList.length; s++)
            {
                var t:Number  = stepList[s], t2:Number = t*t, t3:Number = t2*t;
                var h1:Number =  2*t3 - 3*t2 + 1;
                var h2:Number = -2*t3 + 3*t2;
                var h3:Number =      t3 - 2*t2 + t;
                var h4:Number =      t3 -     t2;

                var m1x:Number = (p2.x - p1.x) + t12*((p1.x - p0.x)/t01 - (p2.x - p0.x)/(t01 + t12));
                var m2x:Number = (p2.x - p1.x) + t12*((p3.x - p2.x)/t23 - (p3.x - p1.x)/(t12 + t23));
                var m1y:Number = (p2.y - p1.y) + t12*((p1.y - p0.y)/t01 - (p2.y - p0.y)/(t01 + t12));
                var m2y:Number = (p2.y - p1.y) + t12*((p3.y - p2.y)/t23 - (p3.y - p1.y)/(t12 + t23));

                var nx:Number = h1*p1.x + h2*p2.x + h3*m1x + h4*m2x;
                var ny:Number = h1*p1.y + h2*p2.y + h3*m1y + h4*m2y;
                newPts.push({x:nx, y:ny});
            }
        }
        ring.reset(newPts);
    }

    private function _dist(a:Object,b:Object):Number
    {
        var dx:Number = a.x-b.x, dy:Number = a.y-b.y;
        return Math.sqrt(dx*dx + dy*dy);
    }

    private function _subsampleEdges(edges:Array, factor:Number):Array
    {
        var out:Array = [];
        for (var i:Number=0; i<edges.length; i+=factor) out.push(edges[i]);
        return out;
    }

    private function _initializeRecord(edges:Array, frame:Number):Object
    {
        var rec:Object = { _lastFrame: frame };
        for (var i:Number=0; i<edges.length; i++)
        {
            var e:Object = edges[i];
            rec[i] = {
                edge1: new RingBuffer(_maxFrames, null, [e.edge1]),
                edge2: new RingBuffer(_maxFrames, null, [e.edge2])
            };
        }
        return rec;
    }

    // --------------------------
    // 内存管理
    // --------------------------
    /**
     * 清除全部发射者轨迹数据，可在切场景或长时间运行后调用。
     *
     * @return 被清理的发射者数量
     */
    public function cleanMemory():Number
    {
        var n:Number = 0;
        for (var id:String in _trackRecords) { delete _trackRecords[id]; n++; }
        trace("[TrailRenderer] 已清理 "+n+" 个发射者轨迹数据");
        return n;
    }
}
