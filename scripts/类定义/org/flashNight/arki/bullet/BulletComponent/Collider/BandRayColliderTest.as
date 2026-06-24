import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * BandRayColliderTest —— 带宽射线碰撞器单元测试（golden 值）。
 *
 * 验证 BandRayCollider（RayCollider 的屏幕-Y 加宽子类，委托 super 跑 slab）：
 *   - 半宽把细线错过的矮目标捞回（近 miss → 命中，golden 入射点/tEntry）
 *   - 超出半宽仍 miss
 *   - 带宽是纯超集：细线本就命中的目标 tEntry/入射点不变
 *   - 半宽 0 == 父类细线（委托 super；与 RayColliderTest 同 golden）
 *   - setHalfWidth 守卫（负值/NaN 归零）
 *
 * 严格细线回归门在 RayColliderTest（RayCollider 已隔离回本特性出现前的状态）。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.BandRayColliderTest {

    private var _passed:Number;
    private var _failed:Number;
    private var _total:Number;
    private static var EPS:Number = 0.01;

    public function BandRayColliderTest() {
        _passed = 0; _failed = 0; _total = 0;
        trace("===== BandRayColliderTest Begin =====");
        testCatchesNearMiss();
        testBeyondBandStillMisses();
        testTEntryUnchangedForInBandHit();
        testZeroWidthEqualsThin();
        testSetHalfWidthClamps();
        trace("Results: " + _passed + " passed, " + _failed + " failed, " + _total + " total");
        trace("===== BandRayColliderTest End =====");
    }

    private function assertEqual(desc:String, expected:Number, actual:Number):Void {
        _total++;
        var diff:Number = expected - actual;
        if (diff < 0) diff = -diff;
        if (diff < EPS) { _passed++; trace("  [PASS] " + desc); }
        else { _failed++; trace("  [FAIL] " + desc + " | expected=" + expected + " actual=" + actual); }
    }

    private function assertBool(desc:String, expected:Boolean, actual:Boolean):Void {
        _total++;
        if (expected === actual) { _passed++; trace("  [PASS] " + desc); }
        else { _failed++; trace("  [FAIL] " + desc + " | expected=" + expected + " actual=" + actual); }
    }

    /** 半宽把细线错过的矮目标捞回：ray Y=50、target Y[70,90]（差 20），半宽 25 → 命中、入射(40,50) tEntry=40。 */
    private function testCatchesNearMiss():Void {
        trace(">>> testCatchesNearMiss");
        var rc:BandRayCollider = new BandRayCollider(new Vector(0, 50), new Vector(1, 0), 100);
        var target:AABBCollider = new AABBCollider(40, 60, 70, 90);

        // 半宽 0（默认）→ 委托 super 细线 → 错过
        var crThin:CollisionResult = rc.checkCollision(target, 0);
        assertBool("width=0 misses short target (delegates to thin)", false, crThin.isColliding);

        rc.setHalfWidth(25);
        var crBand:CollisionResult = rc.checkCollision(target, 0);
        assertBool("band catches near-miss", true, crBand.isColliding);
        assertEqual("band entryX", 40, crBand.overlapCenter.x);
        assertEqual("band entryY", 50, crBand.overlapCenter.y);
        assertEqual("band tEntry", 40, crBand.tEntry);
    }

    /** 超出半宽仍 miss：target Y[100,120]（差 50），半宽 25 → miss。 */
    private function testBeyondBandStillMisses():Void {
        trace(">>> testBeyondBandStillMisses");
        var rc:BandRayCollider = new BandRayCollider(new Vector(0, 50), new Vector(1, 0), 100);
        var target:AABBCollider = new AABBCollider(40, 60, 100, 120);
        rc.setHalfWidth(25);
        assertBool("beyond band still misses", false, rc.checkCollision(target, 0).isColliding);
    }

    /** 纯超集：细线本就命中的目标，加带宽 tEntry/入射点不变。 */
    private function testTEntryUnchangedForInBandHit():Void {
        trace(">>> testTEntryUnchangedForInBandHit");
        var rc:BandRayCollider = new BandRayCollider(new Vector(0, 50), new Vector(1, 0), 100);
        var target:AABBCollider = new AABBCollider(40, 60, 40, 60);

        var crThin:CollisionResult = rc.checkCollision(target, 0);   // 默认半宽 0 → 细线
        var thinTE:Number = crThin.tEntry;
        var thinX:Number = crThin.overlapCenter.x;
        var thinY:Number = crThin.overlapCenter.y;

        rc.setHalfWidth(30);
        var crBand:CollisionResult = rc.checkCollision(target, 0);
        assertBool("band still hits in-band target", true, crBand.isColliding);
        assertEqual("band tEntry == thin tEntry", thinTE, crBand.tEntry);
        assertEqual("band entryX == thin entryX", thinX, crBand.overlapCenter.x);
        assertEqual("band entryY == thin entryY", thinY, crBand.overlapCenter.y);
    }

    /** 半宽 0 == 父类细线（委托 super；BandRayCollider 与 RayCollider 同 golden）。 */
    private function testZeroWidthEqualsThin():Void {
        trace(">>> testZeroWidthEqualsThin");
        var band:BandRayCollider = new BandRayCollider(new Vector(0, 50), new Vector(1, 0), 100);
        var thin:RayCollider = new RayCollider(new Vector(0, 50), new Vector(1, 0), 100);
        var target:AABBCollider = new AABBCollider(40, 60, 40, 60);

        var crBand:CollisionResult = band.checkCollision(target, 0);  // 默认半宽 0
        var bHit:Boolean = crBand.isColliding;
        var bTE:Number = crBand.tEntry;
        var crThin:CollisionResult = thin.checkCollision(target, 0);  // 复用同一 static result，故先存 band 值
        assertBool("band(0) hit == thin hit", crThin.isColliding, bHit);
        assertEqual("band(0) tEntry == thin tEntry", crThin.tEntry, bTE);
    }

    /** setHalfWidth 守卫：负值/NaN 归零。 */
    private function testSetHalfWidthClamps():Void {
        trace(">>> testSetHalfWidthClamps");
        var rc:BandRayCollider = new BandRayCollider(new Vector(0, 0), new Vector(1, 0), 100);
        rc.setHalfWidth(20);
        assertEqual("setHalfWidth(20)", 20, rc.getHalfWidth());
        rc.setHalfWidth(-5);
        assertEqual("setHalfWidth(-5) clamps to 0", 0, rc.getHalfWidth());
        rc.setHalfWidth(Number(undefined));
        assertEqual("setHalfWidth(NaN) clamps to 0", 0, rc.getHalfWidth());
    }
}
