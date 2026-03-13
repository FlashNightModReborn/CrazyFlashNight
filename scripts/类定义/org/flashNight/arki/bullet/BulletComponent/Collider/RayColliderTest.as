import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * RayCollider 单元测试 + 性能基准
 *
 * 测试覆盖：
 * 1. 构造函数 AABB 计算
 * 2. setRay / setRayFast 更新
 * 3. getAABB zOffset 偏移
 * 4. checkCollision 各分支（命中、未命中、ORDERFALSE、YORDERFALSE、起点在AABB内、平行射线、tEntry精度）
 * 5. updateFromTransparentBullet / updateFromBullet
 * 6. 性能基准：checkCollision hit/miss、setRayFast、getAABB、updateFromTransparentBullet
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.RayColliderTest {

    private var _passed:Number;
    private var _failed:Number;
    private var _total:Number;

    private static var EPS:Number = 0.01;

    public function RayColliderTest() {
        _passed = 0;
        _failed = 0;
        _total = 0;

        trace("===== RayColliderTest Begin =====");

        testConstructor();
        testConstructorNegativeDirection();
        testSetRay();
        testSetRayFast();
        testSetRayFast_ZeroVectorPreservesPoint();
        testSetRayFast_NaNDirectionSafeMiss();
        testGetAABB();
        testCheckCollision_Hit();
        testCheckCollision_Miss();
        testCheckCollision_OrderFalse();
        testCheckCollision_YOrderFalse();
        testCheckCollision_RayInsideAABB();
        testCheckCollision_ParallelRay();
        testCheckCollision_TEntry();
        testCheckCollision_EdgeGraze();
        testUpdateFromTransparentBullet();
        testUpdateFromBullet();

        trace("");
        trace("Results: " + _passed + " passed, " + _failed + " failed, " + _total + " total");
        trace("");

        benchmarkCheckCollisionHit();
        benchmarkCheckCollisionMiss();
        benchmarkSetRayFast();
        benchmarkGetAABB();
        benchmarkUpdateFromTransparentBullet();

        trace("===== RayColliderTest End =====");
    }

    // ========================= 断言 =========================

    private function assertEqual(desc:String, expected:Number, actual:Number):Void {
        _total++;
        var diff:Number = expected - actual;
        if (diff < 0) diff = -diff;
        if (diff < EPS) {
            _passed++;
            trace("  [PASS] " + desc);
        } else {
            _failed++;
            trace("  [FAIL] " + desc + " | expected=" + expected + " actual=" + actual);
        }
    }

    private function assertBool(desc:String, expected:Boolean, actual:Boolean):Void {
        _total++;
        if (expected === actual) {
            _passed++;
            trace("  [PASS] " + desc);
        } else {
            _failed++;
            trace("  [FAIL] " + desc + " | expected=" + expected + " actual=" + actual);
        }
    }

    // ========================= 正确性测试 =========================

    private function testConstructor():Void {
        trace(">>> testConstructor");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 100
        );
        assertEqual("left", 0, rc.left);
        assertEqual("right", 60, rc.right);
        assertEqual("top", 0, rc.top);
        assertEqual("bottom", 80, rc.bottom);
    }

    private function testConstructorNegativeDirection():Void {
        trace(">>> testConstructorNegativeDirection");
        var rc:RayCollider = new RayCollider(
            new Vector(100, 50), new Vector(-1, 0), 80
        );
        assertEqual("left", 20, rc.left);
        assertEqual("right", 100, rc.right);
        assertEqual("top", 50, rc.top);
        assertEqual("bottom", 50, rc.bottom);
    }

    private function testSetRay():Void {
        trace(">>> testSetRay");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(1, 0), 10
        );
        rc.setRay(new Vector(10, 20), new Vector(0, 1), 50);
        assertEqual("left", 10, rc.left);
        assertEqual("right", 10, rc.right);
        assertEqual("top", 20, rc.top);
        assertEqual("bottom", 70, rc.bottom);
    }

    private function testSetRayFast():Void {
        trace(">>> testSetRayFast");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(1, 0), 10
        );
        rc.setRayFast(5, 10, 3, 4, 50);
        assertEqual("left", 5, rc.left);
        assertEqual("right", 35, rc.right);
        assertEqual("top", 10, rc.top);
        assertEqual("bottom", 50, rc.bottom);
    }

    private function testSetRayFast_ZeroVectorPreservesPoint():Void {
        trace(">>> testSetRayFast_ZeroVectorPreservesPoint");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(1, 0), 10
        );
        rc.setRayFast(10, 20, 0, 0, 50);
        assertEqual("left", 10, rc.left);
        assertEqual("right", 10, rc.right);
        assertEqual("top", 20, rc.top);
        assertEqual("bottom", 20, rc.bottom);

        var target:AABBCollider = new AABBCollider(0, 30, 10, 40);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("zero vector still behaves as point ray", true, cr.isColliding);
        assertEqual("zero vector tEntry=0", 0, cr.tEntry);
    }

    private function testSetRayFast_NaNDirectionSafeMiss():Void {
        trace(">>> testSetRayFast_NaNDirectionSafeMiss");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(1, 0), 10
        );
        rc.setRayFast(0, 0, Number(undefined), 1, 50);
        assertEqual("left", 0, rc.left);
        assertEqual("right", 0, rc.right);
        assertEqual("top", 0, rc.top);
        assertEqual("bottom", 0, rc.bottom);

        var target:AABBCollider = new AABBCollider(-10, 10, -10, 10);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("NaN direction becomes safe miss", false, cr.isColliding);
    }

    private function testGetAABB():Void {
        trace(">>> testGetAABB");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 100
        );
        var aabb:AABB = rc.getAABB(10);
        assertEqual("left", 0, aabb.left);
        assertEqual("right", 60, aabb.right);
        assertEqual("top", 10, aabb.top);
        assertEqual("bottom", 90, aabb.bottom);
    }

    private function testCheckCollision_Hit():Void {
        trace(">>> testCheckCollision_Hit");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 100
        );
        var target:AABBCollider = new AABBCollider(20, 40, 20, 60);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("isColliding", true, cr.isColliding);
        assertEqual("entryX", 20, cr.overlapCenter.x);
        assertEqual("entryY", 26.67, cr.overlapCenter.y);
        assertEqual("tEntry", 33.33, cr.tEntry);
    }

    private function testCheckCollision_Miss():Void {
        trace(">>> testCheckCollision_Miss");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 100
        );
        var target:AABBCollider = new AABBCollider(200, 300, 200, 300);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("isColliding", false, cr.isColliding);
    }

    private function testCheckCollision_OrderFalse():Void {
        trace(">>> testCheckCollision_OrderFalse");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 10
        );
        var target:AABBCollider = new AABBCollider(100, 200, 0, 100);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("isColliding", false, cr.isColliding);
        assertBool("isOrdered", false, cr.isOrdered);
    }

    private function testCheckCollision_YOrderFalse():Void {
        trace(">>> testCheckCollision_YOrderFalse");
        var rc:RayCollider = new RayCollider(
            new Vector(50, -50), new Vector(1, -1), 50
        );
        var target:AABBCollider = new AABBCollider(60, 80, 10, 50);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("isColliding", false, cr.isColliding);
        assertBool("isYOrdered", false, cr.isYOrdered);
    }

    private function testCheckCollision_RayInsideAABB():Void {
        trace(">>> testCheckCollision_RayInsideAABB");
        var rc:RayCollider = new RayCollider(
            new Vector(50, 50), new Vector(1, 1), 20
        );
        var target:AABBCollider = new AABBCollider(0, 200, 0, 200);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("isColliding", true, cr.isColliding);
        assertEqual("tEntry=0", 0, cr.tEntry);
        assertEqual("entryX=originX", 50, cr.overlapCenter.x);
        assertEqual("entryY=originY", 50, cr.overlapCenter.y);
    }

    private function testCheckCollision_ParallelRay():Void {
        trace(">>> testCheckCollision_ParallelRay");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 50), new Vector(1, 0), 100
        );
        var target:AABBCollider = new AABBCollider(20, 80, 40, 60);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("isColliding", true, cr.isColliding);
        assertEqual("tEntry", 20, cr.tEntry);
        assertEqual("entryX", 20, cr.overlapCenter.x);
        assertEqual("entryY", 50, cr.overlapCenter.y);
    }

    private function testCheckCollision_TEntry():Void {
        trace(">>> testCheckCollision_TEntry");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(1, 0), 200
        );
        var target:AABBCollider = new AABBCollider(50, 100, -10, 10);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("isColliding", true, cr.isColliding);
        assertEqual("tEntry=50", 50, cr.tEntry);
        assertEqual("entryX=50", 50, cr.overlapCenter.x);
        assertEqual("entryY=0", 0, cr.overlapCenter.y);
    }

    private function testCheckCollision_EdgeGraze():Void {
        trace(">>> testCheckCollision_EdgeGraze");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(1, 0), 50
        );
        var target:AABBCollider = new AABBCollider(50, 100, -10, 10);
        var cr:CollisionResult = rc.checkCollision(target, 0);
        assertBool("edge graze: not colliding", false, cr.isColliding);
    }

    private function testUpdateFromTransparentBullet():Void {
        trace(">>> testUpdateFromTransparentBullet");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 100
        );
        var bullet:Object = {_x: 200, _y: 300};
        rc.updateFromTransparentBullet(bullet);
        assertEqual("left", 200, rc.left);
        assertEqual("right", 260, rc.right);
        assertEqual("top", 300, rc.top);
        assertEqual("bottom", 380, rc.bottom);
    }

    private function testUpdateFromBullet():Void {
        trace(">>> testUpdateFromBullet");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(1, 0), 50
        );
        // 无类型变量绕过 AS2 编译期 MovieClip 类型检查
        var bullet = {_x: 100, _y: 200};
        rc.updateFromBullet(bullet, null);
        assertEqual("left", 100, rc.left);
        assertEqual("right", 150, rc.right);
        assertEqual("top", 200, rc.top);
        assertEqual("bottom", 200, rc.bottom);
    }

    // ========================= 性能基准 =========================

    private function benchmarkCheckCollisionHit():Void {
        trace(">>> Benchmark: checkCollision (hit path)");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 100
        );
        var target:AABBCollider = new AABBCollider(20, 40, 20, 60);
        var iterations:Number = 500000;
        var i:Number = iterations;
        var t0:Number = getTimer();
        while (i--) {
            rc.checkCollision(target, 0);
        }
        var dt:Number = getTimer() - t0;
        trace("  " + iterations + " ops, " + dt + "ms, " + Math.round((dt * 1000000) / iterations) + " ns/op");
    }

    private function benchmarkCheckCollisionMiss():Void {
        trace(">>> Benchmark: checkCollision (ORDERFALSE path)");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 10
        );
        var target:AABBCollider = new AABBCollider(100, 200, 0, 100);
        var iterations:Number = 500000;
        var i:Number = iterations;
        var t0:Number = getTimer();
        while (i--) {
            rc.checkCollision(target, 0);
        }
        var dt:Number = getTimer() - t0;
        trace("  " + iterations + " ops, " + dt + "ms, " + Math.round((dt * 1000000) / iterations) + " ns/op");
    }

    private function benchmarkSetRayFast():Void {
        trace(">>> Benchmark: setRayFast");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(1, 0), 10
        );
        var iterations:Number = 500000;
        var i:Number = iterations;
        var t0:Number = getTimer();
        while (i--) {
            rc.setRayFast(i, i, 3, 4, 100);
        }
        var dt:Number = getTimer() - t0;
        trace("  " + iterations + " ops, " + dt + "ms, " + Math.round((dt * 1000000) / iterations) + " ns/op");
    }

    private function benchmarkGetAABB():Void {
        trace(">>> Benchmark: getAABB");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 100
        );
        var iterations:Number = 500000;
        var i:Number = iterations;
        var t0:Number = getTimer();
        while (i--) {
            rc.getAABB(10);
        }
        var dt:Number = getTimer() - t0;
        trace("  " + iterations + " ops, " + dt + "ms, " + Math.round((dt * 1000000) / iterations) + " ns/op");
    }

    private function benchmarkUpdateFromTransparentBullet():Void {
        trace(">>> Benchmark: updateFromTransparentBullet");
        var rc:RayCollider = new RayCollider(
            new Vector(0, 0), new Vector(3, 4), 100
        );
        var bullet:Object = {_x: 100, _y: 200};
        var iterations:Number = 500000;
        var i:Number = iterations;
        var t0:Number = getTimer();
        while (i--) {
            bullet._x = i;
            rc.updateFromTransparentBullet(bullet);
        }
        var dt:Number = getTimer() - t0;
        trace("  " + iterations + " ops, " + dt + "ms, " + Math.round((dt * 1000000) / iterations) + " ns/op");
    }

    public static function main():Void {
        var test:RayColliderTest = new RayColliderTest();
    }
}
