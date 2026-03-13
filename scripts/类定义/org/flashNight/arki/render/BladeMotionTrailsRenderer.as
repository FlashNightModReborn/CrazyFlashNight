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
 *   - LOW:    getRect 包围盒采样，3个刀口位置（最低开销）
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
     * @param validIndexes  输出数组，接收有效刀口序号
     */
    /** 膨胀系数上限（安全封顶，正常武器通常不会触及） */
    private static var EDGE_SPREAD:Number = 2.5;
    /** 膨胀系数下限（防止极端收缩导致刀光消失） */
    private static var MIN_SPREAD:Number = 0.3;
    /** 间隙填充比（黄金比例 φ ≈ 0.618：膨胀到间隙的 61.8%，留 38.2% 负空间） */
    private static var FILL_RATIO:Number = 0.618;

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
     * 额外开销：≤ n-1 次 sqrt + 少量算术，零额外 localToGlobal。
     */
    private static function _sampleBladeEdges(
        mc:MovieClip, map:MovieClip, maxPositions:Number,
        trail:Array, validIndexes:Array
    ):Void {
        var tipPt:Object  = _tipPt;
        var basePt:Object = _basePt;
        var current:MovieClip;
        var rect:Object;
        var cx:Number, cy:Number;
        var e1x:Number, e1y:Number;

        // ==== Phase 1: 收集有效刀口位置 ====
        var clips:Array = [];
        var localRects:Array = [];
        var n:Number = 0;

        for (var i:Number = 1; i <= maxPositions; i++) {
            current = mc["刀口位置" + i];
            if (current && current._x != undefined) {
                validIndexes.push(i);
                clips[n] = current;
                localRects[n] = current.getRect(current);
                n++;
            }
        }
        if (n == 0) return;

        // ==== Phase 2: 自适应膨胀系数 ====
        var spreads:Array = [];
        var maxSpread:Number = EDGE_SPREAD;
        var minSpread:Number = MIN_SPREAD;
        var j:Number;

        // --- 2A: 刀身自然范围（各位置碰撞箱 spread=1 的父空间 Y 并集）---
        var minBladeY:Number = 1e8;
        var maxBladeY:Number = -1e8;
        var lo:Number, hi:Number;
        for (j = 0; j < n; j++) {
            rect = localRects[j];
            lo = clips[j]._y + rect.yMin;
            hi = clips[j]._y + rect.yMax;
            if (lo < minBladeY) minBladeY = lo;
            if (hi > maxBladeY) maxBladeY = hi;
        }

        // --- 2B: 相邻间距约束（黄金比例填充）---
        // spread = halfNeighborDist / naturalHalfDiag * φ
        // φ ≈ 0.618：膨胀到间隙的 61.8%，留出 38.2% 负空间暗示运动感。
        // 对角线综合 X/Y 两轴贡献，几何上匹配对角采样方向。
        if (n == 1) {
            spreads[0] = maxSpread;
        } else {
            rect = localRects[0];
            var hw:Number = (rect.xMax - rect.xMin) * 0.5;
            var hh:Number = (rect.yMax - rect.yMin) * 0.5;
            var naturalHD:Number = Math.sqrt(hw * hw + hh * hh);

            if (naturalHD < 0.1) {
                for (j = 0; j < n; j++) spreads[j] = maxSpread;
            } else {
                var dx:Number, dy:Number, dist:Number, nearDist:Number, s:Number;
                for (j = 0; j < n; j++) {
                    nearDist = 1e8;
                    if (j > 0) {
                        dx = clips[j]._x - clips[j - 1]._x;
                        dy = clips[j]._y - clips[j - 1]._y;
                        dist = Math.sqrt(dx * dx + dy * dy);
                        if (dist < nearDist) nearDist = dist;
                    }
                    if (j < n - 1) {
                        dx = clips[j + 1]._x - clips[j]._x;
                        dy = clips[j + 1]._y - clips[j]._y;
                        dist = Math.sqrt(dx * dx + dy * dy);
                        if (dist < nearDist) nearDist = dist;
                    }
                    s = (nearDist * 0.5) / naturalHD * FILL_RATIO;
                    if (s > maxSpread) s = maxSpread;
                    spreads[j] = s;
                }
            }
        }

        // --- 2C: 刀身范围约束（限制膨胀不超出自然边界）---
        var centerPY:Number, expandUp:Number, expandDown:Number;
        var sUp:Number, sDown:Number;
        for (j = 0; j < n; j++) {
            rect = localRects[j];
            cy = (rect.yMin + rect.yMax) * 0.5;
            centerPY = clips[j]._y + cy;

            // 向 yMax（刀口方向）的膨胀不超过刀身上界
            expandUp = rect.yMax - cy;
            if (expandUp > 0.1) {
                sUp = (maxBladeY - centerPY) / expandUp;
                if (sUp < spreads[j]) spreads[j] = sUp;
            }
            // 向 yMin（刀柄方向）的膨胀不超过刀身下界
            expandDown = cy - rect.yMin;
            if (expandDown > 0.1) {
                sDown = (centerPY - minBladeY) / expandDown;
                if (sDown < spreads[j]) spreads[j] = sDown;
            }
            // 最终下限
            if (spreads[j] < minSpread) spreads[j] = minSpread;
        }

        // ==== Phase 3: 按自适应系数采样边缘 ====
        var spread:Number;
        for (var k:Number = 0; k < n; k++) {
            current = clips[k];
            rect = localRects[k];
            spread = spreads[k];

            cx = (rect.xMin + rect.xMax) * 0.5;
            cy = (rect.yMin + rect.yMax) * 0.5;

            // 刀口侧：从中心向 (xMin, yMax) 方向扩展
            tipPt.x = cx + (rect.xMin - cx) * spread;
            tipPt.y = cy + (rect.yMax - cy) * spread;
            current.localToGlobal(tipPt);
            map.globalToLocal(tipPt);
            e1x = tipPt.x;
            e1y = tipPt.y;

            // 刀柄侧：从中心向 (xMax, yMin) 方向扩展
            basePt.x = cx + (rect.xMax - cx) * spread;
            basePt.y = cy + (rect.yMin - cy) * spread;
            current.localToGlobal(basePt);
            map.globalToLocal(basePt);

            trail.push({
                edge1: new Vector(e1x, e1y),
                edge2: new Vector(basePt.x, basePt.y)
            });
        }
    }

    // ---------------------------
    // 三档残影计算实现
    // ---------------------------

    /** 高性能：localToGlobal 精确采样，5个刀口位置 */
    private static function processBladeTrailHigh(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody;
        var trail:Array = [];
        var validIndexes:Array = [];

        _sampleBladeEdges(mc, map, 5, trail, validIndexes);
        if (trail.length == 0) return;

        var key:String = target._name + target.version + validIndexes.join("");
        TrailRenderer.getInstance().addTrailData(key, trail, style);
    }

    /** 中性能：localToGlobal 精确采样，4个刀口位置 */
    private static function processBladeTrailMedium(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody;
        var trail:Array = [];
        var validIndexes:Array = [];

        _sampleBladeEdges(mc, map, 4, trail, validIndexes);
        if (trail.length == 0) return;

        var key:String = target._name + target.version + validIndexes.join("");
        TrailRenderer.getInstance().addTrailData(key, trail, style);
    }

    /** 低性能：getRect 包围盒采样，3个刀口位置，最低开销 */
    private static function processBladeTrailLow(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody;
        var trail:Array = [];
        var validIndexes:Array = [];

        var current:MovieClip;
        var rect:Object;

        for (var i:Number = 1; i <= 3; i++) {
            current = mc["刀口位置" + i];
            if (current && current._x != undefined) {
                validIndexes.push(i);
                rect = current.getRect(map);
                trail.push({
                    edge1: new Vector(rect.xMin, rect.yMax),
                    edge2: new Vector(rect.xMax, rect.yMin)
                });
            }
        }

        if (trail.length > 0) {
            var key:String = target._name + target.version + validIndexes.join("");
            TrailRenderer.getInstance().addTrailData(key, trail, style);
        }
    }
}
