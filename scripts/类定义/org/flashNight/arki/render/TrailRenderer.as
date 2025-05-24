// 文件路径：org/flashNight/arki/render/TrailRenderer.as

import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.gesh.object.*;
import org.flashNight.naki.DataStructures.RingBuffer;
import org.flashNight.arki.render.VectorAfterimageRenderer;
import org.flashNight.arki.render.TrailStyleManager;
import org.flashNight.sara.util.*;
import org.flashNight.naki.Smooth.SmoothingUtil;

/**
 * TrailRenderer
 * =============
 * 拖影渲染器（单例）
 *
 * 功能概述：
 *   - 记录并渲染攻击刀口、子弹运动等动态残影轨迹；
 *   - 支持 4 档画质、历史帧长度限制、Catmull‑Rom 平滑、低画质采样；
 *   - 通过批量绘制接口减少 MovieClip 创建与 beginFill/endFill 频率；
 *   - 平滑算法由 org.flashNight.naki.Smooth.SmoothingUtil 提供，实现渲染与算法解耦；
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
 * 3. **平滑解耦**  
 *    将平滑相关算法提取到 SmoothingUtil，简化 Renderer，实现单一职责。
 *
 * 4. **其他逻辑保持不变**  
 *    轨迹采样、阈值判断、RingBuffer 历史帧、性能优化策略原样保留。
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
                    SmoothingUtil.catmullRomSmooth(traj.edge1);
                    SmoothingUtil.catmullRomSmooth(traj.edge2);
                }
                else
                {
                    SmoothingUtil.simpleSmooth(traj.edge1);
                    SmoothingUtil.simpleSmooth(traj.edge2);
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
    // 私有工具：采样算法
    // --------------------------
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
        trace("[TrailRenderer] 已清理 " + n + " 个发射者轨迹数据");
        return n;
    }
}

