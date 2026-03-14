import org.flashNight.arki.render.BladeMotionTrailsRenderer;
import org.flashNight.arki.render.TrailRenderer;
import org.flashNight.arki.render.VectorAfterimageRenderer;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/**
 * Regression tests for blade trails and afterimage canvas reuse.
 */
class org.flashNight.arki.render.BladeTrailRenderRegressionTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;
    private static var nameSeed:Number = 0;

    private static function assertTrue(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) {
            testsPassed++;
            trace("[PASS] " + msg);
        } else {
            testsFailed++;
            trace("[FAIL] " + msg);
        }
    }

    private static function assertEq(expected:Number, actual:Number, msg:String):Void {
        var diff:Number = expected - actual;
        if (diff < 0) diff = -diff;
        assertTrue(diff < 0.001, msg + " expected=" + expected + " actual=" + actual);
    }

    private static function assertEqString(expected:String, actual:String, msg:String):Void {
        assertTrue(expected == actual, msg + " expected=" + expected + " actual=" + actual);
    }

    private static function nextName(prefix:String):String {
        nameSeed++;
        return prefix + nameSeed;
    }

    private static function bladeSlotName(index:Number):String {
        return String.fromCharCode(20992, 21475, 20301, 32622) + index;
    }

    private static function ensureDeadbody():MovieClip {
        var gameworld:MovieClip = _root.gameworld;
        if (gameworld == undefined || gameworld.createEmptyMovieClip == undefined) {
            gameworld = _root.createEmptyMovieClip("gameworld", _root.getNextHighestDepth());
        }

        var deadbody:MovieClip = gameworld.deadbody;
        if (deadbody == undefined || deadbody.createEmptyMovieClip == undefined) {
            deadbody = gameworld.createEmptyMovieClip("deadbody", gameworld.getNextHighestDepth());
        }
        return deadbody;
    }

    private static function makeBladeNode(parent:MovieClip, name:String, px:Number, py:Number):MovieClip {
        var node:MovieClip = parent.createEmptyMovieClip(name, parent.getNextHighestDepth());
        node._x = px;
        node._y = py;
        node.beginFill(0xFFFFFF, 100);
        node.moveTo(0, 0);
        node.lineTo(10, 0);
        node.lineTo(10, 10);
        node.lineTo(0, 10);
        node.lineTo(0, 0);
        node.endFill();
        return node;
    }

    private static function testCanvasPoolReuseAndBlendReset():Void {
        trace("--- testCanvasPoolReuseAndBlendReset ---");
        ensureDeadbody();
        EnhancedCooldownWheel.I().reset();

        var renderer = new VectorAfterimageRenderer();
        var normal1:MovieClip = renderer["getAvailableCanvas"](1);
        assertEqString("normal", String(normal1.blendMode), "first normal canvas blend");

        renderer["recycleCanvas"](normal1);
        var normal2:MovieClip = renderer["getAvailableCanvas"](1);
        assertTrue(normal1 === normal2, "normal canvas is reused from pool");
        assertEqString("normal", String(normal2.blendMode), "reused normal canvas blend");

        renderer["recycleCanvas"](normal2);
        var additive:MovieClip = renderer.getAdditiveCanvas(1);
        assertEqString("add", String(additive.blendMode), "additive canvas blend");

        renderer["recycleCanvas"](additive);
        var normal3:MovieClip = renderer["getAvailableCanvas"](1);
        assertTrue(additive === normal3, "additive canvas reused as normal");
        assertEqString("normal", String(normal3.blendMode), "reused additive canvas resets to normal");

        renderer["recycleCanvas"](normal3);
        renderer.onSceneChanged();
        EnhancedCooldownWheel.I().reset();
    }

    private static function testBladeSpreadClampedOnBothAxes():Void {
        trace("--- testBladeSpreadClampedOnBothAxes ---");
        var deadbody:MovieClip = ensureDeadbody();
        var holder:MovieClip = deadbody.createEmptyMovieClip(nextName("bladeTrailHolder_"), deadbody.getNextHighestDepth());
        var target:MovieClip;
        var captured:Object = {};
        var trailClass = TrailRenderer;
        var originalTrailInstance = trailClass["_instance"];

        if (_root.bladeTrailTarget != undefined && _root.bladeTrailTarget.removeMovieClip != undefined) {
            _root.bladeTrailTarget.removeMovieClip();
        }
        target = _root.createEmptyMovieClip("bladeTrailTarget", _root.getNextHighestDepth());
        target.version = "_v1";

        makeBladeNode(holder, bladeSlotName(1), 0, 0);
        makeBladeNode(holder, bladeSlotName(2), 0, 40);
        makeBladeNode(holder, bladeSlotName(3), 0, 80);

        trailClass["_instance"] = {
            addTrailData: function(key, trail, style) {
                captured.key = key;
                captured.trail = trail;
                captured.style = style;
            },
            setQuality: function(level) {
                captured.level = level;
            }
        };

        BladeMotionTrailsRenderer.setPerformanceLevel(BladeMotionTrailsRenderer.PERFORMANCE_LEVEL_HIGH);
        BladeMotionTrailsRenderer.processBladeTrail(target, holder, "blade_style");

        assertEq(BladeMotionTrailsRenderer.PERFORMANCE_LEVEL_HIGH, captured.level, "quality sync");
        assertTrue(captured.trail != undefined, "trail forwarded to renderer");
        assertEq(3, captured.trail.length, "all blade slots are sampled");
        assertEqString("bladeTrailTarget_v1123", String(captured.key), "trail key");
        assertEqString("blade_style", String(captured.style), "style passthrough");

        var mid:Object = captured.trail[1];
        // 各向异性 spread 后 X 仍受边界约束（窄轴），Y 可膨胀（宽轴）
        // X 方向：所有刀口在 x=0，边界 0~10，spreadX 被约束
        assertEq(0, mid.edge1.x, "mid edge1 x stays inside left bound");
        assertEq(10, mid.edge2.x, "mid edge2 x stays inside right bound");
        // Y 方向：中间刀口远离边界，spreadY 可保持 Phase 2B 值
        // Phase 2B spread = sqrt(nearDistSq/hdSq) * HALF_FILL_RATIO
        // nearDistSq = 40^2 = 1600, hdSq = 5^2+5^2 = 50
        // spread = sqrt(32) * 0.309 ≈ 1.748
        // spreadY ≈ 1.748: tipPt.y = 5 + (10-5)*1.748 = 13.74 → global = 40+13.74 = 53.74
        // 验证 Y 膨胀超出原始 rect 边界（即 spreadY > 1）
        assertTrue(mid.edge1.y > 50, "mid edge1 y expanded beyond rect (y=" + mid.edge1.y + ")");
        assertTrue(mid.edge2.y < 40, "mid edge2 y expanded beyond rect (y=" + mid.edge2.y + ")");

        trailClass["_instance"] = originalTrailInstance;
        holder.removeMovieClip();
        target.removeMovieClip();
    }

    /**
     * 验证黄金比例膨胀的边界约束差异：中间刀口远离所有边界，保持高 spread；
     * 边缘刀口靠近边界，spread 被 Phase 2C 约束压缩。
     *
     * 布局：对角线放置 3 个 10x10 刀口
     *   blade1 (0,0)   — 左下角，靠近 minBladeX/minBladeY 边界
     *   blade2 (50,40)  — 中心，远离所有边界
     *   blade3 (100,80) — 右上角，靠近 maxBladeX/maxBladeY 边界
     *
     * 预期：
     *   Phase 2B 给所有刀口 spread ≈ 2.5 (EDGE_SPREAD cap)
     *   Phase 2C 将 blade1/3 压缩到 ~1.0, blade2 保持 ~2.5
     *   中间刀口 edge 距离平方应 > 边缘刀口的 3 倍
     */
    private static function testMiddleBladeSpreadWiderThanEdges():Void {
        trace("--- testMiddleBladeSpreadWiderThanEdges ---");
        var deadbody:MovieClip = ensureDeadbody();
        var holder:MovieClip = deadbody.createEmptyMovieClip(nextName("spreadHolder_"), deadbody.getNextHighestDepth());
        var target:MovieClip;
        var captured:Object = {};
        var trailClass = TrailRenderer;
        var originalTrailInstance = trailClass["_instance"];

        if (_root.bladeTrailTarget != undefined && _root.bladeTrailTarget.removeMovieClip != undefined) {
            _root.bladeTrailTarget.removeMovieClip();
        }
        target = _root.createEmptyMovieClip("bladeTrailTarget", _root.getNextHighestDepth());
        target.version = "_v1";

        // 对角线放置 3 个刀口
        makeBladeNode(holder, bladeSlotName(1), 0, 0);
        makeBladeNode(holder, bladeSlotName(2), 50, 40);
        makeBladeNode(holder, bladeSlotName(3), 100, 80);

        trailClass["_instance"] = {
            addTrailData: function(key, trail, style) {
                captured.key = key;
                captured.trail = trail;
                captured.style = style;
            },
            setQuality: function(level) {}
        };

        // 强制刷新帧级缓存：推进帧计时器使 _ensureCache 重新读取
        if (_root.帧计时器 == undefined) _root.帧计时器 = {当前帧数: 0};
        _root.帧计时器.当前帧数 = (_root.帧计时器.当前帧数 || 0) + 1;
        BladeMotionTrailsRenderer.setPerformanceLevel(BladeMotionTrailsRenderer.PERFORMANCE_LEVEL_HIGH);
        BladeMotionTrailsRenderer.processBladeTrail(target, holder, "spread_test");

        assertTrue(captured.trail != undefined && captured.trail.length == 3,
            "3 blades sampled for diagonal layout");

        // 计算每个刀口的 edge-to-edge 距离平方
        var b1:Object = captured.trail[0];
        var b2:Object = captured.trail[1];
        var b3:Object = captured.trail[2];

        var dx1:Number = b1.edge2.x - b1.edge1.x;
        var dy1:Number = b1.edge2.y - b1.edge1.y;
        var distSq1:Number = dx1 * dx1 + dy1 * dy1;

        var dx2:Number = b2.edge2.x - b2.edge1.x;
        var dy2:Number = b2.edge2.y - b2.edge1.y;
        var distSq2:Number = dx2 * dx2 + dy2 * dy2;

        var dx3:Number = b3.edge2.x - b3.edge1.x;
        var dy3:Number = b3.edge2.y - b3.edge1.y;
        var distSq3:Number = dx3 * dx3 + dy3 * dy3;

        // 中间刀口 spread ≈ 2.5, 边缘 ≈ 1.0 → 距离比 ≈ 2.5:1 → 距离平方比 ≈ 6.25:1
        // 用 3:1 平方比作为保守下限
        assertTrue(distSq2 > distSq1 * 3,
            "middle blade wider than blade1 (distSq mid=" + distSq2 + " edge1=" + distSq1 + " ratio=" + (distSq2 / distSq1) + ")");
        assertTrue(distSq2 > distSq3 * 3,
            "middle blade wider than blade3 (distSq mid=" + distSq2 + " edge3=" + distSq3 + " ratio=" + (distSq2 / distSq3) + ")");

        // 输出实际值供调试
        trace("  spread diagnostic: b1_distSq=" + distSq1 + " b2_distSq=" + distSq2 + " b3_distSq=" + distSq3);

        trailClass["_instance"] = originalTrailInstance;
        holder.removeMovieClip();
        target.removeMovieClip();
    }

    public static function runAllTests():Void {
        testsRun = 0;
        testsPassed = 0;
        testsFailed = 0;

        trace("===== BladeTrailRenderRegressionTest START =====");
        testCanvasPoolReuseAndBlendReset();
        testBladeSpreadClampedOnBothAxes();
        testMiddleBladeSpreadWiderThanEdges();
        trace("===== BladeTrailRenderRegressionTest END: run=" + testsRun
            + ", pass=" + testsPassed + ", fail=" + testsFailed + " =====");

        if (testsFailed > 0) {
            trace("!!! " + testsFailed + " tests failed !!!");
        }
    }

    public static function main():Void {
        runAllTests();
    }
}
