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
        assertEq(0, mid.edge1.x, "mid edge1 x stays inside left bound");
        assertEq(10, mid.edge2.x, "mid edge2 x stays inside right bound");
        assertEq(50, mid.edge1.y, "mid edge1 y stays on upper bound");
        assertEq(40, mid.edge2.y, "mid edge2 y stays on lower bound");

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
