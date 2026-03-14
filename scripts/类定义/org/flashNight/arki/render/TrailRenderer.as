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

    /** 增强渲染复用的 scratch 缓冲，减少热路径 GC 分配 */
    private var _scratchMidX:Array;
    private var _scratchMidY:Array;
    private var _scratchPolyX:Array;
    private var _scratchPolyY:Array;
    private var _scratchEdge1:Array;
    private var _scratchEdge2:Array;
    private var _scratchSrcEdge1:Array;
    private var _scratchSrcEdge2:Array;
    private var _scratchSubsample:Array;
    private var _scratchInUse:Boolean;

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
        _scratchMidX = [];
        _scratchMidY = [];
        _scratchPolyX = [];
        _scratchPolyY = [];
        _scratchEdge1 = [];
        _scratchEdge2 = [];
        _scratchSrcEdge1 = [];
        _scratchSrcEdge2 = [];
        _scratchSubsample = [];
        _scratchInUse = false;
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
            case 0: _movementThresholdSqr = 5  * 5;  _maxFrames = 8; break;
            case 1: _movementThresholdSqr = 6  * 6;  _maxFrames = 6; break;
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
            edgeArray = _subsampleEdges(edgeArray, 2, _scratchSubsample);
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
        // 高画质走增强渲染路径（分段alpha + 宽度渐变 + 多层叠加 + additive blend）
        if (_quality <= 1) {
            _renderTrailsEnhanced(record, edgeArray, styleName);
            return;
        }

        var quality:Number  = _quality;
        var alphaValue:Number = (quality == 3) ? 50 : 100;
        var shouldSmooth:Boolean = (currentFrame % quality == 0);

        var simplePolygons:Array  = [];
        var edge1:Array = [];
        var edge2:Array = [];

        var len:Number = edgeArray.length;
        var i:Number   = 0;
        do
        {
            var traj:Object   = record[i];
            traj.edge1.copyToArray(edge1);
            traj.edge2.copyToReversedArray(edge2);
            var edge1Len:Number = edge1.length;
            var edge2Len:Number = edge2.length;

            if (edge1Len < 2 || edge2Len < 2) continue;

            // 视画质做平滑
            if (shouldSmooth)
            {
                SmoothingUtil.simpleSmooth(traj.edge1);
                SmoothingUtil.simpleSmooth(traj.edge2);
                traj.edge1.copyToArray(edge1);
                traj.edge2.copyToReversedArray(edge2);
                edge1Len = edge1.length;
                edge2Len = edge2.length;
            }

            var poly:Array = [];
            var p:Number = 0;
            var j:Number;
            for (j = 0; j < edge1Len; j++) poly[p++] = edge1[j];
            for (j = 0; j < edge2Len; j++) poly[p++] = edge2[j];
            if (p > 2) poly[p] = poly[0]; // 闭合

            if (p > 2)
            {
                simplePolygons.push(poly);
            }
        } while (++i < len);

        // ----------- 批量绘制 -----------
        if (simplePolygons.length > 0)
        {
            _drawSimpleTrailBatch(simplePolygons, styleName, alphaValue);
        }
    }

    // --------------------------
    // 增强渲染：单一填充多边形 + 宽度渐变 + 多层叠加
    // --------------------------

    /**
     * 增强渲染路径 (quality 0-1)
     *
     * 与旧版分段四边形不同，本方法为每个刀口位置构建单一闭合多边形
     * （edge1 正序 + edge2 逆序），一次 beginFill/endFill 覆盖整个挥刀弧面。
     *
     * 特性：
     *   - 单一闭合多边形填充，视觉饱满度与旧方案一致
     *   - 宽度渐变（Taper）：最旧帧收窄，最新帧全宽
     *   - curveTo 平滑曲线（复用 drawMixedShape 的首尾直线+中间曲线模式）
     *   - Additive blend 画布，叠加产生辉光
     *   - 双层同色渲染：外扩辉光层(宽、低alpha) + 核心层(窄、高alpha)
     *   - Additive 叠加使中心自然最亮、边缘柔和衰减，不干扰样式配色
     *   - 法线重建：按轨迹切线法线方向重建 edge 宽度，消除挥刀角度退化
     */
    private function _renderTrailsEnhanced(record:Object, edgeArray:Array, styleName:String):Void
    {
        var quality:Number = _quality;
        var highQuality:Boolean = (quality == 0);
        var style:Object   = _styleManager.getStyle(styleName);
        var len:Number     = edgeArray.length;
        var fillColor:Number   = style.color;
        // H01: style 成员在 do-while 循环内使用，预缓存到局部(GetMember ~144ns/次)
        var lineWidth:Number   = style.lineWidth;
        var lineColor:Number   = style.lineColor;
        var outerFillAlpha:Number = style.fillOpacity * 0.3;
        var innerFillAlpha:Number = style.fillOpacity * 0.6;
        var outerLineAlpha:Number = style.lineOpacity * 0.14;

        // 获取 additive blend 画布
        var shadowCount:Number = highQuality ? 5 : 3;
        var canvas:MovieClip = VectorAfterimageRenderer.instance.getAdditiveCanvas(shadowCount);
        var sqrt:Function = Math.sqrt;
        var midx:Array, midy:Array, ptx:Array, pty:Array, drawE1:Array, drawE2:Array, srcE1:Array, srcE2:Array;
        var useSharedScratch:Boolean = !_scratchInUse;

        if (useSharedScratch) {
            _scratchInUse = true;
            midx = _scratchMidX;
            midy = _scratchMidY;
            ptx = _scratchPolyX;
            pty = _scratchPolyY;
            drawE1 = _scratchEdge1;
            drawE2 = _scratchEdge2;
            srcE1 = _scratchSrcEdge1;
            srcE2 = _scratchSrcEdge2;
        } else {
            midx = [];
            midy = [];
            ptx = [];
            pty = [];
            drawE1 = [];
            drawE2 = [];
            srcE1 = [];
            srcE2 = [];
        }

        var i:Number = 0;
        do {
            var traj:Object = record[i];

            // 平滑
            if (highQuality) {
                SmoothingUtil.catmullRomSmooth(traj.edge1);
                SmoothingUtil.catmullRomSmooth(traj.edge2);
            } else {
                SmoothingUtil.simpleSmooth(traj.edge1);
                SmoothingUtil.simpleSmooth(traj.edge2);
            }

            traj.edge1.copyToArray(srcE1);
            traj.edge2.copyToArray(srcE2);
            var histLen:Number = srcE1.length;
            if (histLen < 2) continue;

            // 按轨迹切线法线重建 edge 宽度，消除角度退化
            _rebuildPerpEdges(srcE1, srcE2, histLen, midx, midy, drawE1, drawE2, sqrt);

            // 外扩辉光层：全采样宽度，低 alpha
            // additive blend 下多帧画布叠加会累积亮度，alpha 需远低于 normal blend
            canvas.lineStyle(lineWidth, lineColor, outerLineAlpha);
            _drawTaperedTrail(canvas, drawE1, drawE2, midx, midy, histLen, fillColor, outerFillAlpha, 0.3, 1.0, ptx, pty);

            // 核心层：收窄，适度 alpha，additive 叠加自然趋亮
            if (highQuality) {
                canvas.lineStyle(0, 0, 0);
                _drawTaperedTrail(canvas, drawE1, drawE2, midx, midy, histLen, fillColor, innerFillAlpha, 0.1, 0.5, ptx, pty);
            }
        } while (++i < len);

        if (useSharedScratch) _scratchInUse = false;
    }

    /**
     * 按轨迹切线法线方向重建 edge1/edge2，消除挥刀角度导致的宽度退化。
     *
     * 原理：
     *   1. 计算每帧 edge1-edge2 中点 → 得到轨迹曲线
     *   2. 相邻中点差分 → 切线方向 → 逆时针旋转90° → 法线方向
     *   3. 取 edge1-edge2 距离的最大值作为 halfDiag（旋转不变量）
     *   4. 沿法线方向 ±halfDiag 放置新 edge1/edge2
     *
     * 效果：无论挥刀角度如何，edge 宽度始终垂直于运动方向，不会退化。
     * 开销：1 次 sqrt（halfDiag）+ histLen 次 sqrt（切线归一化），quality 0 下约 7 次/刀口。
     *
     * @param srcE1   edge1 历史点数组（原始历史，不直接修改）
     * @param srcE2   edge2 历史点数组（原始历史，不直接修改）
     * @param histLen 历史帧数
     */
    private function _rebuildPerpEdges(
        srcE1:Array, srcE2:Array, histLen:Number,
        midx:Array, midy:Array, outE1:Array, outE2:Array, sqrt:Function
    ):Void
    {
        var s:Number, edx:Number, edy:Number;
        var p1:Object, p2:Object;

        // ---- 计算 halfDiag：取各帧 edge 距离的最大值 ----
        var maxDistSq:Number = 0;
        for (s = 0; s < histLen; s++) {
            p1 = srcE1[s];
            p2 = srcE2[s];
            edx = p1.x - p2.x;
            edy = p1.y - p2.y;
            var dSq:Number = edx * edx + edy * edy;
            if (dSq > maxDistSq) maxDistSq = dSq;
            midx[s] = (p1.x + p2.x) * 0.5;
            midy[s] = (p1.y + p2.y) * 0.5;
        }
        midx.length = histLen;
        midy.length = histLen;

        var hd:Number = sqrt(maxDistSq) * 0.5;
        if (hd < 1) {
            for (s = 0; s < histLen; s++) {
                outE1[s] = srcE1[s];
                outE2[s] = srcE2[s];
            }
            outE1.length = histLen;
            outE2.length = histLen;
            return;
        }

        // ---- 按切线法线方向重建 edge1/edge2 ----
        var tx:Number, ty:Number, tlen:Number, px:Number, py:Number;
        // H01: midx[s]/midy[s] 每轮访问 3~4 次(~35ns/次)，缓存到局部
        var mx:Number, my:Number;
        var lastS:Number = histLen - 1;
        for (s = 0; s < histLen; s++) {
            mx = midx[s];
            my = midy[s];
            // 切线：前向差分；末帧用后向差分
            if (s < lastS) {
                tx = midx[s + 1] - mx;
                ty = midy[s + 1] - my;
            } else {
                tx = mx - midx[s - 1];
                ty = my - midy[s - 1];
            }
            tlen = sqrt(tx * tx + ty * ty);

            if (tlen > 0.5) {
                px = (-ty / tlen) * hd;
                py = (tx / tlen) * hd;
            } else {
                p1 = srcE1[s];
                px = p1.x - mx;
                py = p1.y - my;
            }

            p1 = outE1[s];
            if (p1 == undefined) {
                p1 = {x: 0, y: 0};
                outE1[s] = p1;
            }
            p2 = outE2[s];
            if (p2 == undefined) {
                p2 = {x: 0, y: 0};
                outE2[s] = p2;
            }

            p1.x = mx + px;
            p1.y = my + py;
            p2.x = mx - px;
            p2.y = my - py;
        }
        outE1.length = histLen;
        outE2.length = histLen;
    }

    /**
     * 绘制带宽度渐变的闭合多边形轨迹。
     *
     * 构建路径：tapered_edge1[0→n] + tapered_edge2[n→0]，
     * 首尾段用 lineTo，中间段用 curveTo 平滑。
     * 顶点坐标存入 flat 数组（ptx/pty）避免对象分配。
     *
     * @param canvas    目标画布
     * @param e1        edge1 历史点数组（index 0=最旧, last=最新）
     * @param e2        edge2 历史点数组
     * @param histLen   历史帧数
     * @param color     填充色
     * @param alpha     填充 alpha (0-100)
     * @param taperMin  最旧帧宽度比例 (0-1)
     * @param taperMax  最新帧宽度比例 (0-1)
     */
    private function _drawTaperedTrail(
        canvas:MovieClip, e1:Array, e2:Array, midx:Array, midy:Array, histLen:Number,
        color:Number, alpha:Number, taperMin:Number, taperMax:Number,
        ptx:Array, pty:Array
    ):Void
    {
        var taperRange:Number = taperMax - taperMin;
        var invHist:Number = (histLen > 1) ? 1.0 / (histLen - 1) : 1;
        var totalPts:Number = histLen * 2;

        var s:Number, f:Number, tap:Number;
        var p:Object;
        // H01: midx[s]/midy[s] 每轮 2 次访问，缓存到局部
        var mx:Number, my:Number;

        // Edge1 正序（最旧→最新）
        for (s = 0; s < histLen; s++) {
            f = s * invHist;
            tap = taperMin + f * taperRange;
            p = e1[s];
            mx = midx[s];
            my = midy[s];
            ptx[s] = mx + (p.x - mx) * tap;
            pty[s] = my + (p.y - my) * tap;
        }

        // Edge2 逆序（最新→最旧）
        var writeIndex:Number = histLen;
        for (s = histLen - 1; s >= 0; s--) {
            f = s * invHist;
            tap = taperMin + f * taperRange;
            p = e2[s];
            mx = midx[s];
            my = midy[s];
            ptx[writeIndex] = mx + (p.x - mx) * tap;
            pty[writeIndex] = my + (p.y - my) * tap;
            writeIndex++;
        }
        ptx.length = totalPts;
        pty.length = totalPts;

        if (totalPts < 3) return;

        // 绘制闭合多边形：首尾直线，中间 curveTo 平滑
        // 滑动窗口：缓存当前点坐标，每轮减少 2 次数组读取
        var last:Number = totalPts - 2;
        var j:Number;

        canvas.beginFill(color, alpha);
        canvas.moveTo(ptx[0], pty[0]);

        var curX:Number = ptx[1];
        var curY:Number = pty[1];
        canvas.lineTo(curX, curY);

        var nextX:Number, nextY:Number;
        for (j = 1; j < last; j++) {
            nextX = ptx[j + 1];
            nextY = pty[j + 1];
            canvas.curveTo(curX, curY, (curX + nextX) * 0.5, (curY + nextY) * 0.5);
            curX = nextX;
            curY = nextY;
        }

        canvas.lineTo(ptx[totalPts - 1], pty[totalPts - 1]);
        canvas.lineTo(ptx[0], pty[0]);
        canvas.endFill();
    }

    // --------------------------
    // 私有工具：绘制封装
    // --------------------------
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
    private function _subsampleEdges(edges:Array, factor:Number, out:Array):Array
    {
        if (out == null) out = [];
        var writeIndex:Number = 0;
        for (var i:Number = 0; i < edges.length; i += factor) {
            out[writeIndex] = edges[i];
            writeIndex++;
        }
        out.length = writeIndex;
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

