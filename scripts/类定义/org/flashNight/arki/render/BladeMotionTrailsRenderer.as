import org.flashNight.arki.render.*;
import org.flashNight.sara.util.*;

/**
 * BladeMotionTrailsRenderer 刀口残影渲染器
 *
 * 根据刀口碰撞箱数据采样刀刃端点，生成弧形刀光轨迹。
 *
 * 三档性能实现：
 *   - HIGH:   localToGlobal 精确采样，5个刀口位置，保留旋转弧线
 *   - MEDIUM: localToGlobal 精确采样，4个刀口位置
 *   - LOW:    localToGlobal 精确采样，3个刀口位置（保留旋转信息，仅减少采样点）
 *
 * localToGlobal 方案保留碰撞箱旋转信息：挥刀时 edge1(刀口侧) 划过大弧、
 * edge2(刀柄侧) 划过小弧，天然形成从宽到窄的弧形刀光，而非等宽飘带。
 *
 * 刀口方向约定：刀口MC局部坐标系中，yMax = 刀口方向（外弧），yMin = 刀柄方向（内弧）。
 */
class org.flashNight.arki.render.BladeMotionTrailsRenderer {

    // ---------------------------
    // 性能等级常量
    // ---------------------------
    public static var PERFORMANCE_LEVEL_HIGH:Number   = 0;
    public static var PERFORMANCE_LEVEL_MEDIUM:Number = 1;
    public static var PERFORMANCE_LEVEL_LOW:Number    = 2;

    /** 当前选定的刀口残影计算方法（默认为高性能实现） */
    public static var processBladeTrail:Function = processBladeTrailHigh;

    // --- 静态复用对象，避免每帧 GC 分配 ---
    private static var _tipPt:Object  = {x: 0, y: 0};
    private static var _basePt:Object = {x: 0, y: 0};
    private static var _clipScratch:Array = [];
    private static var _rectScratch:Array = [];
    private static var _clipXScratch:Array = [];
    private static var _clipYScratch:Array = [];
    private static var _trailScratch:Array = [];
    private static var _pairDistSqScratch:Array = [];

    // --- [P0-4] 帧级引用缓存 ---
    private static var _mapCache:MovieClip;
    private static var _rendererCache:Object;
    private static var _cacheFrame:Number = -1;

    private static function _ensureCache():Void {
        var f:Number = _root.帧计时器.当前帧数;
        if (f !== _cacheFrame) {
            _mapCache = _root.gameworld.deadbody;
            _rendererCache = TrailRenderer.getInstance();
            _cacheFrame = f;
        }
    }

    // --- [P0-3] 刀口 slot 引用缓存（固定 5 槽，不随画质截断） ---
    private static function _getSlots(mc:MovieClip):Array {
        var s:Array = mc.__bsl;
        if (s != undefined) return s;
        s = [mc.刀口位置1, mc.刀口位置2, mc.刀口位置3, mc.刀口位置4, mc.刀口位置5];
        mc.__bsl = s;
        return s;
    }

    private function BladeMotionTrailsRenderer() {
    }

    // ---------------------------
    // 性能调控接口
    // ---------------------------
    /**
     * 设置刀口残影计算的性能档位。
     * 同步更新 TrailRenderer 画质以匹配渲染复杂度。
     * @param level 可传入 PERFORMANCE_LEVEL_HIGH / PERFORMANCE_LEVEL_MEDIUM / PERFORMANCE_LEVEL_LOW
     */
    public static function setPerformanceLevel(level:Number):Void {
        switch(level) {
            case PERFORMANCE_LEVEL_HIGH:
                processBladeTrail = processBladeTrailHigh;
                break;
            case PERFORMANCE_LEVEL_MEDIUM:
                processBladeTrail = processBladeTrailMedium;
                break;
            case PERFORMANCE_LEVEL_LOW:
            default:
                processBladeTrail = processBladeTrailLow;
                break;
        }
        TrailRenderer.getInstance().setQuality(level);
    }

    // ---------------------------
    // 精确采样：localToGlobal
    // ---------------------------
    /**
     * 通过 localToGlobal 精确采样刀刃端点，保留旋转信息。
     * 每个刀口MC的局部Y轴：yMax = 刀口侧(外弧 edge1)，yMin = 刀柄侧(内弧 edge2)。
     *
     * @param mc            包含刀口位置子MC的父MovieClip
     * @param map           目标坐标系参考对象
     * @param maxPositions  最大采样刀口数
     * @param trail         输出数组，接收 {edge1:Vector, edge2:Vector}
     * @returns             有效刀口序号拼接的 bladeId；无有效刀口时返回 null
     */
    /** 膨胀系数上限（安全封顶，正常武器通常不会触及） */
    private static var EDGE_SPREAD:Number = 2.5;
    /** 膨胀系数下限（防止极端收缩导致刀光消失） */
    private static var MIN_SPREAD:Number = 0.3;
    /** 间隙填充比（黄金比例 φ ≈ 0.618：膨胀到间隙的 61.8%，留 38.2% 负空间） */
    private static var FILL_RATIO:Number = 0.618;
    /** FILL_RATIO * 0.5 预计算，供平方域 sqrt 合并使用 */
    private static var HALF_FILL_RATIO:Number = 0.309;

    /**
     * 自适应膨胀采样：三阶段流程
     *
     * Phase 1 — 收集有效刀口位置，缓存 MC 引用与局部 rect
     * Phase 2 — 双重约束计算膨胀系数：
     *   2B  相邻间距约束：spread = halfNeighborDist / naturalHalfDiag * FILL_RATIO
     *       · FILL_RATIO = φ ≈ 0.618（黄金比例），留 38% 负空间暗示运动
     *       · 对角线综合 X/Y 两轴，几何上匹配对角采样方向
     *       · 小碰撞箱、稀疏排列 → ratio 大 → 命中 EDGE_SPREAD 上限
     *       · 大碰撞箱、密集排列 → ratio 低 → 自动收缩，防止相邻重叠
     *   2C  刀身范围约束：采样点不得超出所有碰撞箱自然边界的并集
     *       · 端点位置向外膨胀受限 → 防止刀光外溢超出武器轮廓
     *       · 中间位置通常不受此约束（离边界远）
     *   最终 spread = clamp(min(2B, 2C), MIN_SPREAD, EDGE_SPREAD)
     * Phase 3 — 按自适应系数执行 localToGlobal 边缘采样
     *
     * 前提：刀口位置MC为纯平移变换（无旋缩），局部尺寸≈父空间尺寸。
     * 额外开销：n 次 sqrt（预计算成对距离平方 + 平方域合并，从 3n 降至 n），零额外 localToGlobal。
     */
    private static function _sampleBladeEdges(
        mc:MovieClip, map:MovieClip, maxPositions:Number,
        trail:Array
    ):String {
        var tipPt:Object  = _tipPt;
        var basePt:Object = _basePt;
        var clips:Array = _clipScratch;
        var localRects:Array = _rectScratch;
        var clipX:Array = _clipXScratch;
        var clipY:Array = _clipYScratch;
        var sqrt:Function = Math.sqrt;
        var current:MovieClip;
        var rect:Object;
        var cx:Number, cy:Number;
        var centerPX:Number, centerPY:Number;
        var e1x:Number, e1y:Number;
        var spread:Number;
        var bladeId:String = "";

        // ==== Phase 1: 收集有效刀口位置 ====
        var n:Number = 0;
        var minBladeX:Number = 1e8;
        var maxBladeX:Number = -1e8;
        var minBladeY:Number = 1e8;
        var maxBladeY:Number = -1e8;
        var lo:Number, hi:Number;

        // [P0-3] 使用缓存的 slot 引用数组，消除每帧字符串拼接
        var slots:Array = _getSlots(mc);
        for (var i:Number = 0; i < maxPositions; i++) {
            current = slots[i];
            if (current && current._x != undefined) {
                bladeId += String(i + 1);
                // H03: MC 属性批量读取后缓存，避免重复 native 访问(~170ns/次)
                var px:Number = current._x;
                var py:Number = current._y;
                clips[n] = current;
                clipX[n] = px;
                clipY[n] = py;
                rect = current.getRect(current);
                localRects[n] = rect;

                lo = px + rect.xMin;
                hi = px + rect.xMax;
                if (lo < minBladeX) minBladeX = lo;
                if (hi > maxBladeX) maxBladeX = hi;

                lo = py + rect.yMin;
                hi = py + rect.yMax;
                if (lo < minBladeY) minBladeY = lo;
                if (hi > maxBladeY) maxBladeY = hi;
                n++;
            }
        }
        if (n == 0) return null;
        clips.length = n;
        localRects.length = n;
        clipX.length = n;
        clipY.length = n;

        // ==== 预计算相邻成对距离平方（消除主循环 sqrt）====
        var pairDistSq:Array = _pairDistSqScratch;
        var maxSpread:Number = EDGE_SPREAD;
        var minSpread:Number = MIN_SPREAD;
        var hw:Number, hh:Number;
        var dx:Number, dy:Number;
        var j:Number;

        if (n > 1) {
            var prevPX:Number = clipX[0];
            var prevPY:Number = clipY[0];
            for (j = 1; j < n; j++) {
                var curPX:Number = clipX[j];
                var curPY:Number = clipY[j];
                dx = curPX - prevPX;
                dy = curPY - prevPY;
                pairDistSq[j - 1] = dx * dx + dy * dy;
                prevPX = curPX;
                prevPY = curPY;
            }
            pairDistSq.length = n - 1;
        }

        // ==== Phase 2 + 3: 计算膨胀系数并采样 ====
        var expandLeft:Number, expandRight:Number;
        var expandUp:Number, expandDown:Number;
        var sLeft:Number, sRight:Number;
        var sUp:Number, sDown:Number;
        // H01: rect 字段缓存到局部变量（每字段 GetMember ~144ns，每位置访问 2~4 次）
        var rxMin:Number, rxMax:Number, ryMin:Number, ryMax:Number;
        var k:Number = 0;
        for (j = 0; j < n; j++) {
            current = clips[j];
            rect = localRects[j];
            rxMin = rect.xMin;
            rxMax = rect.xMax;
            ryMin = rect.yMin;
            ryMax = rect.yMax;

            // --- 2B: 相邻间距约束（平方域运算，1 次 sqrt 替代 3 次）---
            if (n == 1) {
                spread = maxSpread;
            } else {
                hw = (rxMax - rxMin) * 0.5;
                hh = (ryMax - ryMin) * 0.5;
                var hdSq:Number = hw * hw + hh * hh;
                if (hdSq < 0.01) {
                    spread = maxSpread;
                } else {
                    // 取最近相邻距离平方（预计算，零 sqrt）
                    var nearDistSq:Number = 1e16;
                    if (j > 0) {
                        var leftSq:Number = pairDistSq[j - 1];
                        if (leftSq < nearDistSq) nearDistSq = leftSq;
                    }
                    if (j < n - 1) {
                        var rightSq:Number = pairDistSq[j];
                        if (rightSq < nearDistSq) nearDistSq = rightSq;
                    }
                    // sqrt(nearDistSq) * 0.5 / sqrt(hdSq) * φ
                    // = sqrt(nearDistSq / hdSq) * (0.5 * φ)  — 合并 3 次 sqrt 为 1 次
                    spread = sqrt(nearDistSq / hdSq) * HALF_FILL_RATIO;
                    if (spread > maxSpread) spread = maxSpread;
                }
            }

            // --- 2C: 刀身范围约束（各向异性：X/Y 轴独立约束）---
            // 武器刀口通常沿 Y 轴(刀口-刀柄)排列，X 方向极窄。
            // 单一 spread 会导致 X 轴紧约束压制 Y 轴膨胀，
            // 使中间刀口无法获得应有的黄金比例间隙填充。
            cy = (ryMin + ryMax) * 0.5;
            cx = (rxMin + rxMax) * 0.5;
            centerPX = clipX[j] + cx;
            centerPY = clipY[j] + cy;

            var spreadX:Number = spread;
            var spreadY:Number = spread;

            expandLeft = cx - rxMin;
            if (expandLeft > 0.1) {
                sLeft = (centerPX - minBladeX) / expandLeft;
                if (sLeft < spreadX) spreadX = sLeft;
            }
            expandRight = rxMax - cx;
            if (expandRight > 0.1) {
                sRight = (maxBladeX - centerPX) / expandRight;
                if (sRight < spreadX) spreadX = sRight;
            }
            expandUp = ryMax - cy;
            if (expandUp > 0.1) {
                sUp = (maxBladeY - centerPY) / expandUp;
                if (sUp < spreadY) spreadY = sUp;
            }
            expandDown = cy - ryMin;
            if (expandDown > 0.1) {
                sDown = (centerPY - minBladeY) / expandDown;
                if (sDown < spreadY) spreadY = sDown;
            }
            if (spreadX < minSpread) spreadX = minSpread;
            if (spreadY < minSpread) spreadY = minSpread;

            // Phase 3: 各向异性采样——X/Y 轴使用独立 spread
            tipPt.x = cx + (rxMin - cx) * spreadX;
            tipPt.y = cy + (ryMax - cy) * spreadY;
            current.localToGlobal(tipPt);
            map.globalToLocal(tipPt);
            e1x = tipPt.x;
            e1y = tipPt.y;

            basePt.x = cx + (rxMax - cx) * spreadX;
            basePt.y = cy + (ryMin - cy) * spreadY;
            current.localToGlobal(basePt);
            map.globalToLocal(basePt);

            var edge:Object = trail[k];
            if (edge == undefined) {
                edge = {};
                trail[k] = edge;
            }
            // [P0-5] 对象字面量替代 new Vector (~350ns vs ~847ns)
            // 下游只访问 .x/.y，AS2 类型声明为软提示，兼容
            edge.edge1 = {x: e1x, y: e1y};
            edge.edge2 = {x: basePt.x, y: basePt.y};
            k++;
        }
        trail.length = k;
        return bladeId;
    }

    // ---------------------------
    // 三档残影计算实现
    // ---------------------------

    /** 高性能：localToGlobal 精确采样，5个刀口位置 */
    private static function processBladeTrailHigh(target:MovieClip, mc:MovieClip, style:String):Void {
        _ensureCache();
        var trail:Array = _trailScratch;
        var bladeId:String = _sampleBladeEdges(mc, _mapCache, 5, trail);
        if (bladeId == null) return;

        var key:String = target._name + target.version + bladeId;
        _rendererCache.addTrailData(key, trail, style);
    }

    /** 中性能：localToGlobal 精确采样，4个刀口位置 */
    private static function processBladeTrailMedium(target:MovieClip, mc:MovieClip, style:String):Void {
        _ensureCache();
        var trail:Array = _trailScratch;
        var bladeId:String = _sampleBladeEdges(mc, _mapCache, 4, trail);
        if (bladeId == null) return;

        var key:String = target._name + target.version + bladeId;
        _rendererCache.addTrailData(key, trail, style);
    }

    /** 低性能：localToGlobal 精确采样，3个刀口位置
     *  [P1-3] 重排：保留 localToGlobal 路径（保持旋转信息），仅减少采样点数
     *  原 getRect(map) 方案丢失旋转信息导致几何断崖 */
    private static function processBladeTrailLow(target:MovieClip, mc:MovieClip, style:String):Void {
        _ensureCache();
        var trail:Array = _trailScratch;
        var bladeId:String = _sampleBladeEdges(mc, _mapCache, 3, trail);
        if (bladeId == null) return;

        var key:String = target._name + target.version + bladeId;
        _rendererCache.addTrailData(key, trail, style);
    }
}
