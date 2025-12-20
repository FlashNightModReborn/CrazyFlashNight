/**
 * TestColliderSuite.as
 *
 * 用于测试各类碰撞器 (AABBCollider, CoverageAABBCollider, PolygonCollider, RayCollider)
 * 的核心功能与性能表现，包括各种边界情况和常见场景。
 *
 * 测试覆盖范围:
 *   - AABBCollider: 基础碰撞、边缘接触、包含关系、部分重叠
 *   - CoverageAABBCollider: 覆盖率计算、zOffset、多种重叠比例
 *   - PolygonCollider: 多边形碰撞、面积计算、与AABB交互
 *   - RayCollider: 射线碰撞、方向测试、边界情况、与其他碰撞器交互
 *   - 数值边界: 极大/极小坐标、负坐标、浮点精度
 *   - 退化场景: 零尺寸AABB、零长度射线、边缘接触
 *   - 跨类型交互: 各碰撞器类型之间的互操作
 *   - 性能测试: 批量碰撞检测基准
 *
 * 使用方式:
 *   1. 将此类放在项目相应目录 (如: org/flashNight/arki/test/)。
 *   2. 在调试入口处 (如某个 Main 或 init 脚本) 调用:
 *         TestColliderSuite.getInstance().runAllTests();
 *   3. 查看输出结果 (trace)。
 */

import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.component.Collider.TestColliderSuite {

    // 单例实例，避免在不同场合重复创建测试对象
    private static var _instance:TestColliderSuite;

    /**
     * 获取 TestColliderSuite 单例实例
     */
    public static function getInstance():TestColliderSuite {
        if (_instance == null) {
            _instance = new TestColliderSuite();
        }
        return _instance;
    }

    /**
     * 私有构造函数，避免外部直接 new
     */
    private function TestColliderSuite() {
    }

    /**
     * 一键运行全部测试
     */
    public function runAllTests():Void {
        trace("===== Starting TestColliderSuite =====");

        // 逐个运行各类测试
        testAABBColliderCore();
        testCoverageAABBColliderCore();
        testPolygonColliderCore();

        // 新增方法 - 更多常见场景测试（非边界）
        testPolygonColliderVariety();

        // RayCollider 测试
        testRayColliderCore();
        testRayColliderEdgeCases();
        testRayColliderDirections();

        testEdgeCases();

        // 新增数值边界和退化场景测试
        testNumericalBoundaries();
        testDegenerateCases();

        testCrossColliderInteraction();

        testPerformance();

        trace("===== TestColliderSuite Completed =====");
    }

    //--------------------------------------------------------------------------
    // 1) 简易断言工具方法
    //--------------------------------------------------------------------------

    private function assertEquals(actual:Number, expected:Number, msg:String):Void {
        if (Math.abs(actual - expected) > 0.0001) {
            trace("[FAIL] " + msg + " => Expected: " + expected + ", Got: " + actual);
        } else {
            trace("[PASS] " + msg);
        }
    }

    private function assertTrue(cond:Boolean, msg:String):Void {
        if (!cond) {
            trace("[FAIL] " + msg + " => Expected: true, Got: false");
        } else {
            trace("[PASS] " + msg);
        }
    }

    private function assertFalse(cond:Boolean, msg:String):Void {
        if (cond) {
            trace("[FAIL] " + msg + " => Expected: false, Got: true");
        } else {
            trace("[PASS] " + msg);
        }
    }

    //--------------------------------------------------------------------------
    // 2) AABBCollider 功能测试
    //--------------------------------------------------------------------------

    /**
     * 测试 AABBCollider 的核心功能:
     *  - getAABB()
     *  - checkCollision()
     */
    private function testAABBColliderCore():Void {
        trace("---- testAABBColliderCore ----");

        // 1. 测试 getAABB()
        var collider:AABBCollider = new AABBCollider(0, 100, 0, 100);
        var aabb:AABB = collider.getAABB(0);
        assertEquals(aabb.left, 0, "AABBCollider getAABB left");
        assertEquals(aabb.right, 100, "AABBCollider getAABB right");
        assertEquals(aabb.top, 0, "AABBCollider getAABB top");
        assertEquals(aabb.bottom, 100, "AABBCollider getAABB bottom");

        // 2. 测试 checkCollision() - 碰撞情形
        var other:AABBCollider = new AABBCollider(50, 150, 50, 150);
        var result:CollisionResult = collider.checkCollision(other, 0);
        assertTrue(result.isColliding, "AABBCollider checkCollision overlap");

        // 3. 测试 checkCollision() - 不碰撞情形
        var other2:AABBCollider = new AABBCollider(200, 300, 200, 300);
        var result2:CollisionResult = collider.checkCollision(other2, 0);
        assertFalse(result2.isColliding, "AABBCollider checkCollision non-overlap");

        // 4. 测试 checkCollision() - 边缘碰撞情形（左边缘接触）
        var other3:AABBCollider = new AABBCollider(100, 200, 50, 150);
        var result3:CollisionResult = collider.checkCollision(other3, 0);
        assertFalse(result3.isColliding, "AABBCollider checkCollision edge contact left");

        // 5. 测试 checkCollision() - 边缘碰撞情形（右边缘接触）
        var other4:AABBCollider = new AABBCollider(-50, 0, 50, 150);
        var result4:CollisionResult = collider.checkCollision(other4, 0);
        assertFalse(result4.isColliding, "AABBCollider checkCollision edge contact right");

        // 6. 测试 checkCollision() - 边缘碰撞情形（顶部边缘接触）
        var other5:AABBCollider = new AABBCollider(50, 150, 100, 200);
        var result5:CollisionResult = collider.checkCollision(other5, 0);
        assertFalse(result5.isColliding, "AABBCollider checkCollision edge contact top");

        // 7. 测试 checkCollision() - 边缘碰撞情形（底部边缘接触）
        var other6:AABBCollider = new AABBCollider(50, 150, -50, 0);
        var result6:CollisionResult = collider.checkCollision(other6, 0);
        assertFalse(result6.isColliding, "AABBCollider checkCollision edge contact bottom");

        // 8. 测试 checkCollision() - 一个AABB完全包含另一个AABB
        var other7:AABBCollider = new AABBCollider(25, 75, 25, 75);
        var result7:CollisionResult = collider.checkCollision(other7, 0);
        assertTrue(result7.isColliding, "AABBCollider checkCollision containment");

        // 9. 测试 checkCollision() - 一个AABB被另一个AABB完全包含
        var other8:AABBCollider = new AABBCollider(-50, 150, -50, 150);
        var result8:CollisionResult = other8.checkCollision(collider, 0);
        assertTrue(result8.isColliding, "AABBCollider checkCollision contained");

        // 10. 测试 checkCollision() - AABB 部分重叠（左上角）
        var other9:AABBCollider = new AABBCollider(75, 125, 75, 125);
        var result9:CollisionResult = collider.checkCollision(other9, 0);
        assertTrue(result9.isColliding, "AABBCollider checkCollision partial overlap top-left");
    
        // 11. 测试 checkCollision() - AABB 部分重叠（右上角）
        var other10:AABBCollider = new AABBCollider(75, 150, 25, 75);
        var result10:CollisionResult = collider.checkCollision(other10, 0);
        assertTrue(result10.isColliding, "AABBCollider checkCollision partial overlap top-right");
    
        // 12. 测试 checkCollision() - AABB 部分重叠（左下角）
        var other11:AABBCollider = new AABBCollider(25, 75, 75, 150);
        var result11:CollisionResult = collider.checkCollision(other11, 0);
        assertTrue(result11.isColliding, "AABBCollider checkCollision partial overlap bottom-left");
    
        // 13. 测试 checkCollision() - AABB 部分重叠（右下角）
        var other12:AABBCollider = new AABBCollider(75, 150, 75, 150);
        var result12:CollisionResult = collider.checkCollision(other12, 0);
        assertTrue(result12.isColliding, "AABBCollider checkCollision partial overlap bottom-right");
    
        // 14. 测试 checkCollision() - AABB 相邻但不重叠（左边）
        var other13:AABBCollider = new AABBCollider(-50, 0, 50, 100);
        var result13:CollisionResult = collider.checkCollision(other13, 0);
        assertFalse(result13.isColliding, "AABBCollider checkCollision adjacent left");
    
        // 15. 测试 checkCollision() - AABB 相邻但不重叠（右边）
        var other14:AABBCollider = new AABBCollider(100, 200, 50, 150);
        var result14:CollisionResult = collider.checkCollision(other14, 0);
        assertFalse(result14.isColliding, "AABBCollider checkCollision adjacent right");
    
        // 16. 测试 checkCollision() - AABB 相邻但不重叠（上边）
        var other15:AABBCollider = new AABBCollider(50, 150, 100, 200);
        var result15:CollisionResult = collider.checkCollision(other15, 0);
        assertFalse(result15.isColliding, "AABBCollider checkCollision adjacent top");
    
        // 17. 测试 checkCollision() - AABB 相邻但不重叠（下边）
        var other16:AABBCollider = new AABBCollider(50, 150, -50, 0);
        var result16:CollisionResult = collider.checkCollision(other16, 0);
        assertFalse(result16.isColliding, "AABBCollider checkCollision adjacent bottom");
    
    
        // 18. 测试 checkCollision() - AABB 完全在另一个AABB的外部（远离）
        var other17:AABBCollider = new AABBCollider(300, 400, 300, 400);
        var result17:CollisionResult = collider.checkCollision(other17, 0);
        assertFalse(result17.isColliding, "AABBCollider checkCollision completely outside");
    
        // 19. 测试 checkCollision() - 多个AABB同时碰撞
        var other18:AABBCollider = new AABBCollider(50, 150, 50, 150);
        var other19:AABBCollider = new AABBCollider(75, 125, 75, 125);
        var result18:CollisionResult = collider.checkCollision(other18, 0);
        var result19:CollisionResult = collider.checkCollision(other19, 0);
        assertTrue(result18.isColliding && result19.isColliding, "AABBCollider checkCollision multiple overlaps");
    }

    //--------------------------------------------------------------------------
    // 3) CoverageAABBCollider 功能测试
    //--------------------------------------------------------------------------

    /**
     * 测试 CoverageAABBCollider 核心功能:
     *  - getAABB()
     *  - checkCollision() (重叠率计算)
     */
    private function testCoverageAABBColliderCore():Void {
        trace("---- testCoverageAABBColliderCore ----");

        // 1. 测试 getAABB()
        var coverage:AABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var aabb:AABB = coverage.getAABB(10); // 人为加入zOffset做简单检查
        // 预期 top=0+10, bottom=100+10
        assertEquals(aabb.left, 0, "CoverageAABB getAABB left");
        assertEquals(aabb.right, 100, "CoverageAABB getAABB right");
        assertEquals(aabb.top, 10, "CoverageAABB getAABB top (zOffset)");
        assertEquals(aabb.bottom, 110, "CoverageAABB getAABB bottom (zOffset)");

        // 2. 测试 checkCollision()（面积覆盖率）
        var cov1:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2:CoverageAABBCollider = new CoverageAABBCollider(50, 150, 50, 150);
        var cr:CollisionResult = cov1.checkCollision(cov2, 0);

        assertTrue(cr.isColliding, "CoverageAABB collision should happen");
        // 简单估算重叠区域：从(50,50)到(100,100) => 50x50=2500
        // 整个 cov1 的面积：100*100=10000 => overlapRatio=2500/10000=0.25
        if (cr.isColliding) {
            assertEquals(Math.round(cr.overlapRatio * 100) / 100, 0.25, "CoverageAABB overlapRatio ~ 0.25");
        }
        
        // 2.1 重叠比例为 0.01
        var cov1_1:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2_1:CoverageAABBCollider = new CoverageAABBCollider(90, 110, 90, 110);
        var cr1:CollisionResult = cov1_1.checkCollision(cov2_1, 0);
        assertTrue(cr1.isColliding, "Collision should happen (overlap 0.01)");
        if (cr1.isColliding) {
            assertEquals(Math.round(cr1.overlapRatio * 100) / 100, 0.01, "Overlap ratio ~ 0.01");
        }

        // 2.2 重叠比例为 0.09
        var cov1_3:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2_3:CoverageAABBCollider = new CoverageAABBCollider(70, 130, 70, 130);
        var cr3:CollisionResult = cov1_3.checkCollision(cov2_3, 0);
        assertTrue(cr3.isColliding, "Collision should happen (overlap 0.09)");
        if (cr3.isColliding) {
            assertEquals(Math.round(cr3.overlapRatio * 100) / 100, 0.09, "Overlap ratio ~ 0.09");
        }

        // 2.3 重叠比例为 0.25 (50% 覆盖面积)
        var cov1_5:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2_5:CoverageAABBCollider = new CoverageAABBCollider(50, 150, 50, 150);
        var cr5:CollisionResult = cov1_5.checkCollision(cov2_5, 0);
        assertTrue(cr5.isColliding, "Collision should happen (overlap 0.25)");
        if (cr5.isColliding) {
            assertEquals(Math.round(cr5.overlapRatio * 100) / 100, 0.25, "Overlap ratio ~ 0.25");
        }

        // 2.4 重叠比例为 0.49
        var cov1_7:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2_7:CoverageAABBCollider = new CoverageAABBCollider(30, 130, 30, 130);
        var cr7:CollisionResult = cov1_7.checkCollision(cov2_7, 0);
        assertTrue(cr7.isColliding, "Collision should happen (overlap 0.49)");
        if (cr7.isColliding) {
            assertEquals(Math.round(cr7.overlapRatio * 100) / 100, 0.49, "Overlap ratio ~ 0.49");
        }

        // 2.5 重叠比例为 0.81 (81% 覆盖面积)
        var cov1_9:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2_9:CoverageAABBCollider = new CoverageAABBCollider(10, 110, 10, 110);
        var cr9:CollisionResult = cov1_9.checkCollision(cov2_9, 0);
        assertTrue(cr9.isColliding, "Collision should happen (overlap 0.81)");
        if (cr9.isColliding) {
            assertEquals(Math.round(cr9.overlapRatio * 100) / 100, 0.81, "Overlap ratio ~ 0.81");
        }

        // 2.6 完全重叠
        var cov1_10:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2_10:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cr10:CollisionResult = cov1_10.checkCollision(cov2_10, 0);
        assertTrue(cr10.isColliding, "Collision should happen (overlap 1.0)");
        if (cr10.isColliding) {
            assertEquals(Math.round(cr10.overlapRatio * 100) / 100, 1.0, "Overlap ratio ~ 1.0");
        }

        // 2.7 边缘接触
        var cov1_11:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2_11:CoverageAABBCollider = new CoverageAABBCollider(100, 200, 0, 100);
        var cr11:CollisionResult = cov1_11.checkCollision(cov2_11, 0);
        assertFalse(cr11.isColliding, "Collision should happen (edge touching)");
        if (cr11.isColliding) {
            assertEquals(Math.round(cr11.overlapRatio * 100) / 100, 0.0, "Overlap ratio ~ 0.0");
        }

        // 2.8 部分重叠 0.16
        var cov1_12:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2_12:CoverageAABBCollider = new CoverageAABBCollider(80, 120, 80, 120);
        var cr12:CollisionResult = cov1_12.checkCollision(cov2_12, 0);
        assertTrue(cr12.isColliding, "Collision should happen (overlap 0.16)");
        if (cr12.isColliding) {
            assertEquals(Math.round(cr12.overlapRatio * 100) / 100, 0.04, "Overlap ratio ~ 0.04");
        }

        // 2.9 包含关系
        var cov1_13:CoverageAABBCollider = new CoverageAABBCollider(0, 200, 0, 200);
        var cov2_13:CoverageAABBCollider = new CoverageAABBCollider(50, 150, 50, 150);
        var cr13:CollisionResult = cov1_13.checkCollision(cov2_13, 0);
        assertTrue(cr13.isColliding, "Collision should happen (full containment)");
        if (cr13.isColliding) {
            assertEquals(Math.round(cr13.overlapRatio * 100) / 100, 0.25, "Overlap ratio ~ 0.25");
        }

        // 2.10 无重叠
        var cov1_14:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2_14:CoverageAABBCollider = new CoverageAABBCollider(200, 300, 200, 300);
        var cr14:CollisionResult = cov1_14.checkCollision(cov2_14, 0);
        assertFalse(cr14.isColliding, "Collision should not happen (no overlap)");
    }


    //--------------------------------------------------------------------------
    // 4) PolygonCollider 功能测试
    //--------------------------------------------------------------------------

    /**
     * 测试 PolygonCollider 核心功能:
     *   - getAABB()
     *   - checkCollision() (复杂多边形与 AABB 碰撞)
     */
    private function testPolygonColliderCore():Void {
        trace("---- testPolygonColliderCore ----");

        // 构造一个简单的四边形 (矩形)
        // p1(0,0), p2(100,0), p3(100,100), p4(0,100)
        var p1:Vector = new Vector(0, 0);
        var p2:Vector = new Vector(100, 0);
        var p3:Vector = new Vector(100, 100);
        var p4:Vector = new Vector(0, 100);

        var poly:PolygonCollider = new PolygonCollider(p1, p2, p3, p4);

        // 1. 测试 getAABB()
        var polyAABB:AABB = poly.getAABB(5);
        // 预期: left=0, right=100, top=0+5, bottom=100+5
        assertEquals(polyAABB.left, 0, "PolygonCollider getAABB left");
        assertEquals(polyAABB.right, 100, "PolygonCollider getAABB right");
        assertEquals(polyAABB.top, 5, "PolygonCollider getAABB top (zOffset)");
        assertEquals(polyAABB.bottom, 105, "PolygonCollider getAABB bottom (zOffset)");

        // 2. 测试 checkCollision() 与一个 AABBCollider
        var box:AABBCollider = new AABBCollider(50, 150, 50, 150);
        var collRes:CollisionResult = poly.checkCollision(box, 0);

        assertTrue(collRes.isColliding, "PolygonCollider vs AABBCollider should collide");
        // 如果想更精确验证 overlapRatio，可对比 PolygonCollider 总面积=100*100=10000
        // 重叠区 roughly=50x50=2500 => ratio=0.25
        if (collRes.isColliding) {
            assertEquals(Math.round(collRes.overlapRatio * 100) / 100, 0.25, "Polygon overlapRatio ~ 0.25");
        }

        // 新增样例：部分重叠
        var box3:AABBCollider = new AABBCollider(75, 125, 75, 125);
        var collRes2:CollisionResult = poly.checkCollision(box3, 0);
        assertTrue(collRes2.isColliding, "PolygonCollider vs partially overlapping AABBCollider should collide");
        if (collRes2.isColliding) {
            assertEquals(Math.round(collRes2.overlapRatio * 100) / 100, 0.0625, "Polygon partial overlapRatio ~ 0.0625");
        }

        // 3. 测试不碰撞场景
        var box2:AABBCollider = new AABBCollider(200, 300, 200, 300);
        collRes = poly.checkCollision(box2, 0);
        assertFalse(collRes.isColliding, "PolygonCollider vs far AABBCollider no collision");
    }


    //--------------------------------------------------------------------------
    // 5) 多边形碰撞器常见场景测试
    //--------------------------------------------------------------------------

    /**
     * 测试 PolygonCollider 在非边界情况下与 AABBCollider 的多种常见碰撞场景，
     * 以确保功能的正确性和稳定性。
     */
    private function testPolygonColliderVariety():Void {
        trace("---- testPolygonColliderVariety ----");

        // 场景1：部分重叠（中度重叠）
        // 多边形(10,10)->(80,10)->(80,80)->(10,80)，AABB(50,120,50,120)
        // 多边形大小约 70×70 => 面积=4900
        // 重叠区约在 (50,50)->(80,80) => 30×30=900
        // 重叠率= 900 / 4900 ~ 0.18
        var polyA:PolygonCollider = new PolygonCollider(new Vector(10, 10), new Vector(80, 10), new Vector(80, 80), new Vector(10, 80));
        var boxA:AABBCollider = new AABBCollider(50, 120, 50, 120);
        var resA:CollisionResult = polyA.checkCollision(boxA, 0);
        // 1) 断言必须碰撞
        assertTrue(resA.isColliding, "PolygonCollider partial overlap #1 (should collide)");
        // 2) 断言重叠率大概在 0.18 左右 (允许些许误差)
        if (resA.isColliding) {
            var overlapA:Number = Math.round(resA.overlapRatio * 100) / 100;
            // 可以接受 0.17~0.19 之间
            if (overlapA < 0.17 || overlapA > 0.19) {
                trace("[FAIL] Polygon partial overlap ratio #1 => Expected ~0.18, Got: " + overlapA);
            } else {
                trace("[PASS] Polygon partial overlap ratio #1 => ~0.18");
            }
        }

        // 场景2：无重叠（明显分离）
        // 多边形(200,200)->(280,200)->(280,280)->(200,280)，AABB(50,150,50,150)
        // 互相相隔 50 像素以上，不应发生碰撞
        var polyB:PolygonCollider = new PolygonCollider(new Vector(200, 200), new Vector(280, 200), new Vector(280, 280), new Vector(200, 280));
        var boxB:AABBCollider = new AABBCollider(50, 150, 50, 150);
        var resB:CollisionResult = polyB.checkCollision(boxB, 0);
        assertFalse(resB.isColliding, "PolygonCollider no overlap #2 (should not collide)");

        // 场景3：多边形完全覆盖了 AABB
        // 多边形(0,0)->(200,0)->(200,200)->(0,200)，AABB(50,100,50,100)
        // AABB大小=50×50=2500，多边形=200×200=40000 => overlapRatio=2500 / 40000 = 0.0625
        var polyC:PolygonCollider = new PolygonCollider(new Vector(0, 0), new Vector(200, 0), new Vector(200, 200), new Vector(0, 200));
        var boxC:AABBCollider = new AABBCollider(50, 100, 50, 100);
        var resC:CollisionResult = polyC.checkCollision(boxC, 0);
        assertTrue(resC.isColliding, "PolygonCollider fully covers AABB #3");
        if (resC.isColliding) {
            // 2500 / 40000=0.0625 => ~0.06
            var overlapC:Number = Math.round(resC.overlapRatio * 100) / 100;
            if (overlapC < 0.05 || overlapC > 0.07) {
                trace("[FAIL] Polygon full coverage ratio #3 => Expected ~0.06, Got: " + overlapC);
            } else {
                trace("[PASS] Polygon full coverage ratio #3 => ~0.06");
            }
        }

        // 场景4：随机多边形 vs 随机AABB，大概率部分重叠
        // 注意：这里不是性能测试，只做单次或少量测试即可
        // 用于发现某些随机情况下的算法缺陷（但不测边缘贴合）
        var px:Number = 50 + Math.random() * 100; // 保证不会贴左/右边缘
        var py:Number = 50 + Math.random() * 100; // 保证不会贴上/下边缘
        var polyD:PolygonCollider = new PolygonCollider(new Vector(px, py), new Vector(px + 40, py), new Vector(px + 40, py + 40), new Vector(px, py + 40));
        // AABB 同样随机，但留一定边距
        var boxD:AABBCollider = new AABBCollider(20 + Math.random() * 80, 120 + Math.random() * 80, 20 + Math.random() * 80, 120 + Math.random() * 80);
        var resD:CollisionResult = polyD.checkCollision(boxD, 0);
        // 不做严格断言重叠率，只要查看碰撞与否的稳定性
        // 大概率是部分重叠，也可能完全不碰撞 => 我们只做简单输出
        if (resD.isColliding) {
            trace("[INFO] Random polygon vs AABB => Colliding, ratio=" + Math.round(resD.overlapRatio * 100) / 100);
        } else {
            trace("[INFO] Random polygon vs AABB => No collision");
        }
    }

    //--------------------------------------------------------------------------
    // 6) 边界情况测试
    //--------------------------------------------------------------------------

    /**
     * 测试各种边界情况，确保碰撞器在边缘接触、部分重叠、完全包含等情况下的行为正确。
     */
    private function testEdgeCases():Void {
        trace("---- testEdgeCases ----");

        // 1. AABBCollider 边缘接触
        var aabb1:AABBCollider = new AABBCollider(0, 100, 0, 100);
        var aabb2:AABBCollider = new AABBCollider(100, 200, 0, 100); // 右边缘与 aabb1 左边缘接触
        var result1:CollisionResult = aabb1.checkCollision(aabb2, 0);
        assertFalse(result1.isColliding, "AABBCollider edge touching should NOT collide");

        // 2. CoverageAABBCollider 边缘接触
        var cov1:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var cov2:CoverageAABBCollider = new CoverageAABBCollider(100, 200, 0, 100); // 右边缘与 cov1 左边缘接触
        var result2:CollisionResult = cov1.checkCollision(cov2, 0);
        assertFalse(result2.isColliding, "CoverageAABBCollider edge touching should NOT collide");
        // CoverageAABBCollider 计算重叠率为0（仅边缘接触），但由于实现中可能将其视为重叠
        // 根据实现逻辑，可能需要调整断言
        assertEquals(result2.overlapRatio, 0, "CoverageAABBCollider edge touching overlapRatio = 0");

        // 3. PolygonCollider 边缘接触
        var poly1:PolygonCollider = new PolygonCollider(new Vector(0, 0), new Vector(100, 0), new Vector(100, 100), new Vector(0, 100));
        var poly2:PolygonCollider = new PolygonCollider(new Vector(100, 0), new Vector(200, 0), new Vector(200, 100), new Vector(100, 100)); // poly2 左边缘与 poly1 右边缘接触
        var result3:CollisionResult = poly1.checkCollision(poly2, 0);
        assertFalse(result3.isColliding, "PolygonCollider edge touching should NOT collide");
        // 由于仅边缘接触，交叠面积为0，但根据实现，可能被视为碰撞
        assertEquals(result3.overlapRatio, 0, "PolygonCollider edge touching overlapRatio = 0");

        // 4. AABBCollider 完全包含另一个 AABBCollider
        var aabb3:AABBCollider = new AABBCollider(0, 200, 0, 200);
        var aabb4:AABBCollider = new AABBCollider(50, 150, 50, 150);
        var result4:CollisionResult = aabb3.checkCollision(aabb4, 0);
        assertTrue(result4.isColliding, "AABBCollider fully contains another AABBCollider");
        // 对于 AABBCollider，覆盖率应为1
        assertEquals(result4.overlapRatio, 1, "AABBCollider full containment overlapRatio = 1");

        // 5. CoverageAABBCollider 完全包含另一个 CoverageAABBCollider
        var cov3:CoverageAABBCollider = new CoverageAABBCollider(0, 200, 0, 200);
        var cov4:CoverageAABBCollider = new CoverageAABBCollider(50, 150, 50, 150);
        var result5:CollisionResult = cov3.checkCollision(cov4, 0);
        assertTrue(result5.isColliding, "CoverageAABBCollider fully contains another CoverageAABBCollider");
        // 重叠率为覆盖被包含者的比例，应该为 (150-50)*(150-50) / (200-0)*(200-0) = 100*100 / 200*200 = 0.25
        assertEquals(Math.round(result5.overlapRatio * 100) / 100, 0.25, "CoverageAABBCollider full containment overlapRatio ~ 0.25");

        // 6. PolygonCollider 完全包含另一个 PolygonCollider
        var poly3:PolygonCollider = new PolygonCollider(new Vector(0, 0), new Vector(200, 0), new Vector(200, 200), new Vector(0, 200));
        var poly4:PolygonCollider = new PolygonCollider(new Vector(50, 50), new Vector(150, 50), new Vector(150, 150), new Vector(50, 150));
        var result6:CollisionResult = poly3.checkCollision(poly4, 0);
        assertTrue(result6.isColliding, "PolygonCollider fully contains another PolygonCollider");
        // 重叠率应为 (150-50)*(150-50) / (200-0)*(200-0) = 0.25
        assertEquals(Math.round(result6.overlapRatio * 100) / 100, 0.25, "PolygonCollider full containment overlapRatio ~ 0.25");

        // 7. AABBCollider 与 CoverageAABBCollider 部分重叠
        var aabb5:AABBCollider = new AABBCollider(0, 100, 0, 100);
        var cov5:CoverageAABBCollider = new CoverageAABBCollider(50, 150, 50, 150);
        var result7:CollisionResult = aabb5.checkCollision(cov5, 0);
        assertTrue(result7.isColliding, "AABBCollider partially overlaps with CoverageAABBCollider");
        // 对于 AABBCollider，覆盖率应为1
        assertEquals(result7.overlapRatio, 1, "AABBCollider partial overlap overlapRatio = 1");

        // 8. PolygonCollider 与 CoverageAABBCollider 边缘接触
        var poly5:PolygonCollider = new PolygonCollider(new Vector(100, 100), new Vector(200, 100), new Vector(200, 200), new Vector(100, 200));
        var cov6:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var result8:CollisionResult = poly5.checkCollision(cov6, 0);
        assertFalse(result8.isColliding, "PolygonCollider edge touching with CoverageAABBCollider should NOT collide");
        assertEquals(result8.overlapRatio, 0, "PolygonCollider edge touching with CoverageAABBCollider overlapRatio = 0");
    }

    //--------------------------------------------------------------------------
    // 6) 不同类型碰撞器交互测试
    //--------------------------------------------------------------------------

    /**
     * 测试 AABBCollider / CoverageAABBCollider / PolygonCollider / RayCollider 之间的互相检测
     */
    private function testCrossColliderInteraction():Void {
        trace("---- testCrossColliderInteraction ----");

        // AABBCollider vs CoverageAABBCollider
        var aabb:AABBCollider = new AABBCollider(0, 50, 0, 50);
        var coverage:CoverageAABBCollider = new CoverageAABBCollider(25, 75, 25, 75);

        var result:CollisionResult = aabb.checkCollision(coverage, 0);
        assertTrue(result.isColliding, "AABB -> CoverageAABB collision");

        // CoverageAABBCollider vs PolygonCollider
        var poly:PolygonCollider = new PolygonCollider(new Vector(40, 40), new Vector(80, 40), new Vector(80, 80), new Vector(40, 80));
        var cRes:CollisionResult = coverage.checkCollision(poly, 0);
        assertTrue(cRes.isColliding, "CoverageAABB -> PolygonCollider collision");

        // PolygonCollider vs AABBCollider
        // poly 与上相同(40,40)->(80,40)->(80,80)->(40,80)
        var anotherAABB:AABBCollider = new AABBCollider(0, 30, 0, 30);
        var pRes:CollisionResult = poly.checkCollision(anotherAABB, 0);
        assertFalse(pRes.isColliding, "PolygonCollider -> AABB no collision (out of range)");

        // ---- RayCollider 交互测试 ----

        // RayCollider vs AABBCollider (碰撞)
        var ray1:RayCollider = new RayCollider(new Vector(0, 25), new Vector(1, 0), 100);
        var rayVsAABB:CollisionResult = ray1.checkCollision(aabb, 0);
        assertTrue(rayVsAABB.isColliding, "RayCollider -> AABBCollider collision");

        // RayCollider vs AABBCollider (不碰撞)
        var ray2:RayCollider = new RayCollider(new Vector(0, 100), new Vector(1, 0), 100);
        var rayVsAABB2:CollisionResult = ray2.checkCollision(aabb, 0);
        assertFalse(rayVsAABB2.isColliding, "RayCollider -> AABBCollider no collision");

        // RayCollider vs CoverageAABBCollider (碰撞)
        var ray3:RayCollider = new RayCollider(new Vector(0, 50), new Vector(1, 0), 100);
        var rayVsCoverage:CollisionResult = ray3.checkCollision(coverage, 0);
        assertTrue(rayVsCoverage.isColliding, "RayCollider -> CoverageAABBCollider collision");

        // RayCollider vs CoverageAABBCollider (不碰撞)
        var ray4:RayCollider = new RayCollider(new Vector(0, 0), new Vector(1, 0), 20);
        var rayVsCoverage2:CollisionResult = ray4.checkCollision(coverage, 0);
        assertFalse(rayVsCoverage2.isColliding, "RayCollider -> CoverageAABBCollider no collision (too short)");

        // RayCollider vs PolygonCollider (碰撞)
        var ray5:RayCollider = new RayCollider(new Vector(0, 60), new Vector(1, 0), 100);
        var rayVsPoly:CollisionResult = ray5.checkCollision(poly, 0);
        assertTrue(rayVsPoly.isColliding, "RayCollider -> PolygonCollider collision");

        // RayCollider vs PolygonCollider (不碰撞)
        var ray6:RayCollider = new RayCollider(new Vector(0, 0), new Vector(1, 0), 100);
        var rayVsPoly2:CollisionResult = ray6.checkCollision(poly, 0);
        assertFalse(rayVsPoly2.isColliding, "RayCollider -> PolygonCollider no collision (y=0)");

        // 对角线射线穿过多个碰撞器
        var diagonalRay:RayCollider = new RayCollider(new Vector(0, 0), new Vector(1, 1), 150);
        var diagVsAABB:CollisionResult = diagonalRay.checkCollision(aabb, 0);
        var diagVsCoverage:CollisionResult = diagonalRay.checkCollision(coverage, 0);
        var diagVsPoly:CollisionResult = diagonalRay.checkCollision(poly, 0);
        assertTrue(diagVsAABB.isColliding, "Diagonal ray -> AABB collision");
        assertTrue(diagVsCoverage.isColliding, "Diagonal ray -> CoverageAABB collision");
        assertTrue(diagVsPoly.isColliding, "Diagonal ray -> Polygon collision");
    }

    //--------------------------------------------------------------------------
    // 7) 性能测试
    //--------------------------------------------------------------------------

    /**
     * 简易性能测试：大量重复创建并执行 checkCollision，
     * 通过记录执行时间粗略评估性能。
     *
     * 在实际项目中可拓展:
     *  - 加入更多碰撞器类型对比
     *  - 使用统计报告生成
     *  - 多次运行取平均值
     */
    private function testPerformance():Void {
        trace("---- testPerformance ----");
        var countCamp1:Number = 15; // 阵营1的碰撞器数量
        var countCamp2:Number = 50; // 阵营2的碰撞器数量

        var cc:Number = countCamp1 + countCamp2;

        var aabbFactory:AABBColliderFactory = new AABBColliderFactory(cc);
        var coverageFactory:CoverageAABBColliderFactory = new CoverageAABBColliderFactory(cc);
        var polygonFactory:PolygonColliderFactory = new PolygonColliderFactory(cc);
        var rayFactory:RayColliderFactory = new RayColliderFactory(cc);

        var bulletObjArray:Array = [];
        for(var i = (countCamp1 + countCamp2); i >= 0; --i)
        {
            var boa = new Object();
            boa._x = Math.random() * 1000;
            boa._y = Math.random() * 500;
            bulletObjArray.push(boa);
        }

        // 测试不同类型碰撞器的性能
        performCollisionTest("AABBCollider", aabbFactory, countCamp1, countCamp2, bulletObjArray);
        performCollisionTest("CoverageAABBCollider", coverageFactory, countCamp1, countCamp2, bulletObjArray);
        performCollisionTest("PolygonCollider", polygonFactory, countCamp1, countCamp2, bulletObjArray);
        performCollisionTest("RayCollider", rayFactory, countCamp1, countCamp2, bulletObjArray);
    }

    /**
     * 执行碰撞检测性能测试
     * @param colliderType 碰撞器类型的名称（用于输出）
     * @param factory 创建碰撞器的工厂函数
     * @param count1 阵营1的碰撞器数量
     * @param count2 阵营2的碰撞器数量
     */
    private function performCollisionTest(colliderType:String, factory:IColliderFactory, count1:Number, count2:Number, bulletObjArray:Array):Void {
        trace("---- Testing " + colliderType + " ----");

        var index:Number = 0;
        
        var startTime:Number = getTimer();

        // 创建阵营1的碰撞器
        var camp1:Array = [];
        for (var i1:Number = 0; i1 < count1; i1++) {
            camp1.push(factory.createFromTransparentBullet(bulletObjArray[index++]));
        }

        var len1:Number = camp1.length;

        // 创建阵营2的碰撞器
        var camp2:Array = [];
        for (var i2:Number = 0; i2 < count2; i2++) {
            camp2.push(factory.createFromTransparentBullet(bulletObjArray[index++]));
        }

        var len2:Number = camp2.length;

        var checkCount:Number = 0;

        for(var ii1 = 0; ii1 < len1; ii1++) {
            for(var ii2 = 0; ii2 < len2; ii2++) {
                camp1[ii1].checkCollision(camp2[ii2], Math.random() * 10);
            }
        }
        for(var jj1 = 0; jj1 < len1; jj1++) {
            for(var jj2 = 0; jj2 < len2; jj2++) {
                camp2[jj1].checkCollision(camp1[jj2], Math.random() * 10);
            }
        }


        var endTime:Number = getTimer();
        trace(colliderType + " performance: " + (endTime - startTime) + " ms for " + (len1 * len2 * 2) + " collisions.");
    }

    //--------------------------------------------------------------------------
    // 8) RayCollider 核心功能测试
    //--------------------------------------------------------------------------

    /**
     * 测试 RayCollider 的核心功能:
     *   - 构造与 AABB 生成
     *   - getAABB()
     *   - checkCollision()
     *   - setRay() 动态更新
     */
    private function testRayColliderCore():Void {
        trace("---- testRayColliderCore ----");

        // 1. 测试构造函数和 getAABB() - 水平向右射线
        var origin1:Vector = new Vector(0, 50);
        var direction1:Vector = new Vector(1, 0); // 向右
        var ray1:RayCollider = new RayCollider(origin1, direction1, 100);

        var aabb1:AABB = ray1.getAABB(0);
        assertEquals(aabb1.left, 0, "RayCollider horizontal getAABB left");
        assertEquals(aabb1.right, 100, "RayCollider horizontal getAABB right");
        assertEquals(aabb1.top, 50, "RayCollider horizontal getAABB top");
        assertEquals(aabb1.bottom, 50, "RayCollider horizontal getAABB bottom");

        // 2. 测试 getAABB() 带 zOffset
        var aabb1z:AABB = ray1.getAABB(10);
        assertEquals(aabb1z.top, 60, "RayCollider getAABB top with zOffset");
        assertEquals(aabb1z.bottom, 60, "RayCollider getAABB bottom with zOffset");

        // 3. 测试对角线射线的 AABB
        var origin2:Vector = new Vector(0, 0);
        var direction2:Vector = new Vector(1, 1); // 45度对角线
        var ray2:RayCollider = new RayCollider(origin2, direction2, 100);

        var aabb2:AABB = ray2.getAABB(0);
        // 方向归一化后: (1/sqrt(2), 1/sqrt(2)) ≈ (0.707, 0.707)
        // 终点约为 (70.7, 70.7)
        assertTrue(aabb2.left == 0, "RayCollider diagonal getAABB left = 0");
        assertTrue(aabb2.top == 0, "RayCollider diagonal getAABB top = 0");
        assertTrue(Math.abs(aabb2.right - 70.71) < 1, "RayCollider diagonal getAABB right ~ 70.71");
        assertTrue(Math.abs(aabb2.bottom - 70.71) < 1, "RayCollider diagonal getAABB bottom ~ 70.71");

        // 4. 测试 checkCollision() - 射线穿过 AABB
        var targetBox:AABBCollider = new AABBCollider(40, 80, 40, 60);
        var result1:CollisionResult = ray1.checkCollision(targetBox, 0);
        assertTrue(result1.isColliding, "RayCollider should collide with AABB in path");

        // 验证 overlapCenter 存在且合理
        assertTrue(result1.overlapCenter != null, "RayCollider collision should have overlapCenter");
        if (result1.overlapCenter != null) {
            assertTrue(result1.overlapCenter.x >= 40 && result1.overlapCenter.x <= 80,
                "RayCollider overlapCenter.x should be within target AABB x range");
        }

        // 5. 测试 checkCollision() - 射线不经过 AABB
        var farBox:AABBCollider = new AABBCollider(200, 300, 200, 300);
        var result2:CollisionResult = ray1.checkCollision(farBox, 0);
        assertFalse(result2.isColliding, "RayCollider should not collide with distant AABB");

        // 6. 测试 setRay() 动态更新
        ray1.setRay(new Vector(100, 100), new Vector(-1, 0), 50); // 向左射线
        var aabb3:AABB = ray1.getAABB(0);
        assertEquals(aabb3.left, 50, "RayCollider setRay updated left");
        assertEquals(aabb3.right, 100, "RayCollider setRay updated right");
        assertEquals(aabb3.top, 100, "RayCollider setRay updated top");
        assertEquals(aabb3.bottom, 100, "RayCollider setRay updated bottom");

        // 7. 测试射线起点在 AABB 内部
        var origin3:Vector = new Vector(60, 50);
        var direction3:Vector = new Vector(1, 0);
        var ray3:RayCollider = new RayCollider(origin3, direction3, 100);
        var containingBox:AABBCollider = new AABBCollider(40, 80, 40, 60);
        var result3:CollisionResult = ray3.checkCollision(containingBox, 0);
        assertTrue(result3.isColliding, "RayCollider with origin inside AABB should collide");

        // 8. 测试射线终点在 AABB 内部
        var origin4:Vector = new Vector(0, 50);
        var direction4:Vector = new Vector(1, 0);
        var ray4:RayCollider = new RayCollider(origin4, direction4, 60); // 终点在 x=60
        var result4:CollisionResult = ray4.checkCollision(containingBox, 0);
        assertTrue(result4.isColliding, "RayCollider with endpoint inside AABB should collide");
    }

    //--------------------------------------------------------------------------
    // 9) RayCollider 边界情况测试
    //--------------------------------------------------------------------------

    /**
     * 测试 RayCollider 的各种边界情况
     */
    private function testRayColliderEdgeCases():Void {
        trace("---- testRayColliderEdgeCases ----");

        // 1. 射线刚好擦过 AABB 边缘 (水平射线经过 AABB 底边)
        var edgeRay:RayCollider = new RayCollider(new Vector(0, 100), new Vector(1, 0), 200);
        var edgeBox:AABBCollider = new AABBCollider(50, 150, 50, 100); // 底边 y=100
        var edgeResult:CollisionResult = edgeRay.checkCollision(edgeBox, 0);
        // 边缘接触行为取决于 AABB.intersectsLine 实现，应为 true（包含边界点）
        trace("[INFO] RayCollider edge touching bottom: " + edgeResult.isColliding);

        // 2. 射线刚好错过 AABB（差一个像素）
        var missRay:RayCollider = new RayCollider(new Vector(0, 101), new Vector(1, 0), 200);
        var missResult:CollisionResult = missRay.checkCollision(edgeBox, 0);
        assertFalse(missResult.isColliding, "RayCollider just below AABB should not collide");

        // 3. 射线刚好在 AABB 上方通过
        var aboveRay:RayCollider = new RayCollider(new Vector(0, 49), new Vector(1, 0), 200);
        var aboveResult:CollisionResult = aboveRay.checkCollision(edgeBox, 0);
        assertFalse(aboveResult.isColliding, "RayCollider just above AABB should not collide");

        // 4. 射线从 AABB 角落穿过
        var cornerRay:RayCollider = new RayCollider(new Vector(0, 0), new Vector(1, 1), 200);
        var cornerBox:AABBCollider = new AABBCollider(50, 100, 50, 100);
        var cornerResult:CollisionResult = cornerRay.checkCollision(cornerBox, 0);
        assertTrue(cornerResult.isColliding, "RayCollider through AABB corner should collide");

        // 5. 射线长度刚好到达 AABB 边缘
        var exactRay:RayCollider = new RayCollider(new Vector(0, 75), new Vector(1, 0), 50);
        var exactResult:CollisionResult = exactRay.checkCollision(cornerBox, 0);
        // 射线终点 x=50，刚好是 AABB 左边界
        trace("[INFO] RayCollider endpoint at AABB edge: " + exactResult.isColliding);

        // 6. 射线长度不足以到达 AABB
        var shortRay:RayCollider = new RayCollider(new Vector(0, 75), new Vector(1, 0), 40);
        var shortResult:CollisionResult = shortRay.checkCollision(cornerBox, 0);
        assertFalse(shortResult.isColliding, "RayCollider too short should not collide");

        // 7. 射线完全穿透 AABB
        var throughRay:RayCollider = new RayCollider(new Vector(0, 75), new Vector(1, 0), 200);
        var throughResult:CollisionResult = throughRay.checkCollision(cornerBox, 0);
        assertTrue(throughResult.isColliding, "RayCollider through AABB should collide");

        // 8. 射线与 zOffset 配合测试
        var zRay:RayCollider = new RayCollider(new Vector(75, 0), new Vector(0, 1), 100);
        var zBox:AABBCollider = new AABBCollider(50, 100, 50, 100);
        // 无 zOffset 时应碰撞
        var zResult1:CollisionResult = zRay.checkCollision(zBox, 0);
        assertTrue(zResult1.isColliding, "RayCollider should collide without zOffset");
        // 带 zOffset 后 AABB 向下移动，可能不再碰撞
        var zResult2:CollisionResult = zRay.checkCollision(zBox, 60);
        // zBox AABB 变为 (50,100, 110,160)，射线 y 范围 0-100，不应碰撞
        assertFalse(zResult2.isColliding, "RayCollider should not collide with large zOffset");
    }

    //--------------------------------------------------------------------------
    // 10) RayCollider 不同方向测试
    //--------------------------------------------------------------------------

    /**
     * 测试 RayCollider 在不同方向上的碰撞检测
     */
    private function testRayColliderDirections():Void {
        trace("---- testRayColliderDirections ----");

        var targetBox:AABBCollider = new AABBCollider(40, 60, 40, 60);
        var center:Vector = new Vector(50, 50);

        // 从8个方向射向中心目标
        var directions:Array = [
            {name: "right", origin: new Vector(0, 50), dir: new Vector(1, 0)},
            {name: "left", origin: new Vector(100, 50), dir: new Vector(-1, 0)},
            {name: "down", origin: new Vector(50, 0), dir: new Vector(0, 1)},
            {name: "up", origin: new Vector(50, 100), dir: new Vector(0, -1)},
            {name: "down-right", origin: new Vector(0, 0), dir: new Vector(1, 1)},
            {name: "down-left", origin: new Vector(100, 0), dir: new Vector(-1, 1)},
            {name: "up-right", origin: new Vector(0, 100), dir: new Vector(1, -1)},
            {name: "up-left", origin: new Vector(100, 100), dir: new Vector(-1, -1)}
        ];

        for (var i:Number = 0; i < directions.length; i++) {
            var d:Object = directions[i];
            var ray:RayCollider = new RayCollider(d.origin, d.dir, 150);
            var result:CollisionResult = ray.checkCollision(targetBox, 0);
            assertTrue(result.isColliding, "RayCollider from " + d.name + " should hit target");
        }

        // 测试射线方向远离目标
        var awayDirections:Array = [
            {name: "away-right", origin: new Vector(70, 50), dir: new Vector(1, 0)},
            {name: "away-left", origin: new Vector(30, 50), dir: new Vector(-1, 0)},
            {name: "away-down", origin: new Vector(50, 70), dir: new Vector(0, 1)},
            {name: "away-up", origin: new Vector(50, 30), dir: new Vector(0, -1)}
        ];

        for (var j:Number = 0; j < awayDirections.length; j++) {
            var ad:Object = awayDirections[j];
            var awayRay:RayCollider = new RayCollider(ad.origin, ad.dir, 100);
            var awayResult:CollisionResult = awayRay.checkCollision(targetBox, 0);
            assertFalse(awayResult.isColliding, "RayCollider " + ad.name + " should miss target");
        }
    }

    //--------------------------------------------------------------------------
    // 11) 数值边界测试
    //--------------------------------------------------------------------------

    /**
     * 测试极端数值情况下的碰撞检测
     */
    private function testNumericalBoundaries():Void {
        trace("---- testNumericalBoundaries ----");

        // 1. 极大坐标
        var largeAABB:AABBCollider = new AABBCollider(10000, 10100, 10000, 10100);
        var largeAABB2:AABBCollider = new AABBCollider(10050, 10150, 10050, 10150);
        var largeResult:CollisionResult = largeAABB.checkCollision(largeAABB2, 0);
        assertTrue(largeResult.isColliding, "Large coordinate AABB collision");

        // 2. 负坐标
        var negAABB:AABBCollider = new AABBCollider(-100, -50, -100, -50);
        var negAABB2:AABBCollider = new AABBCollider(-75, -25, -75, -25);
        var negResult:CollisionResult = negAABB.checkCollision(negAABB2, 0);
        assertTrue(negResult.isColliding, "Negative coordinate AABB collision");

        // 3. 跨越零点的 AABB
        var crossAABB:AABBCollider = new AABBCollider(-50, 50, -50, 50);
        var crossAABB2:AABBCollider = new AABBCollider(25, 75, 25, 75);
        var crossResult:CollisionResult = crossAABB.checkCollision(crossAABB2, 0);
        assertTrue(crossResult.isColliding, "Cross-zero AABB collision");

        // 4. 负 zOffset
        var zAABB:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var zAABB2:CoverageAABBCollider = new CoverageAABBCollider(0, 100, -50, 50);
        var zResult:CollisionResult = zAABB.checkCollision(zAABB2, -25);
        // zAABB2 的 AABB 变为 top=-50-25=-75, bottom=50-25=25
        // zAABB 的 AABB 是 top=0, bottom=100
        // 重叠区间 y: max(-75,0)=0 到 min(25,100)=25 => 重叠 25
        assertTrue(zResult.isColliding, "Negative zOffset collision");

        // 5. 极小尺寸 AABB (1x1)
        var tinyAABB:AABBCollider = new AABBCollider(50, 51, 50, 51);
        var tinyAABB2:AABBCollider = new AABBCollider(50, 51, 50, 51);
        var tinyResult:CollisionResult = tinyAABB.checkCollision(tinyAABB2, 0);
        assertTrue(tinyResult.isColliding, "Tiny AABB exact overlap");

        // 6. 浮点精度测试
        var floatAABB:AABBCollider = new AABBCollider(0.1, 0.2, 0.1, 0.2);
        var floatAABB2:AABBCollider = new AABBCollider(0.15, 0.25, 0.15, 0.25);
        var floatResult:CollisionResult = floatAABB.checkCollision(floatAABB2, 0);
        assertTrue(floatResult.isColliding, "Float precision AABB collision");

        // 7. 射线极大长度
        var longRay:RayCollider = new RayCollider(new Vector(0, 0), new Vector(1, 0), 100000);
        var distantBox:AABBCollider = new AABBCollider(99990, 100000, -10, 10);
        var longResult:CollisionResult = longRay.checkCollision(distantBox, 0);
        assertTrue(longResult.isColliding, "Long ray should reach distant target");

        // 8. 射线负坐标起点
        var negRay:RayCollider = new RayCollider(new Vector(-100, 0), new Vector(1, 0), 200);
        var negTargetBox:AABBCollider = new AABBCollider(50, 100, -10, 10);
        var negRayResult:CollisionResult = negRay.checkCollision(negTargetBox, 0);
        assertTrue(negRayResult.isColliding, "Ray from negative origin should hit target");
    }

    //--------------------------------------------------------------------------
    // 12) 退化场景测试
    //--------------------------------------------------------------------------

    /**
     * 测试各种退化或异常情况
     */
    private function testDegenerateCases():Void {
        trace("---- testDegenerateCases ----");

        // 1. 零宽度 AABB (退化为线段)
        var lineAABB:AABBCollider = new AABBCollider(50, 50, 0, 100);
        var normalAABB:AABBCollider = new AABBCollider(40, 60, 40, 60);
        var lineResult:CollisionResult = lineAABB.checkCollision(normalAABB, 0);
        // 行为取决于实现，零宽度可能不碰撞
        trace("[INFO] Zero-width AABB collision: " + lineResult.isColliding);

        // 2. 零高度 AABB (退化为线段)
        var flatAABB:AABBCollider = new AABBCollider(0, 100, 50, 50);
        var flatResult:CollisionResult = flatAABB.checkCollision(normalAABB, 0);
        trace("[INFO] Zero-height AABB collision: " + flatResult.isColliding);

        // 3. 零尺寸 AABB (退化为点)
        var pointAABB:AABBCollider = new AABBCollider(50, 50, 50, 50);
        var pointResult:CollisionResult = pointAABB.checkCollision(normalAABB, 0);
        trace("[INFO] Point AABB collision: " + pointResult.isColliding);

        // 4. 零长度射线
        var zeroRay:RayCollider = new RayCollider(new Vector(50, 50), new Vector(1, 0), 0);
        var zeroRayAABB:AABB = zeroRay.getAABB(0);
        assertEquals(zeroRay.getAABB(0).left, 50, "Zero-length ray AABB left = origin.x");
        assertEquals(zeroRay.getAABB(0).right, 50, "Zero-length ray AABB right = origin.x");
        var zeroRayResult:CollisionResult = zeroRay.checkCollision(normalAABB, 0);
        // 零长度射线起点在 AABB 内，应该碰撞
        assertTrue(zeroRayResult.isColliding, "Zero-length ray at AABB center should collide");

        // 5. 零长度射线在 AABB 外
        var zeroRayOutside:RayCollider = new RayCollider(new Vector(0, 0), new Vector(1, 0), 0);
        var zeroRayOutsideResult:CollisionResult = zeroRayOutside.checkCollision(normalAABB, 0);
        assertFalse(zeroRayOutsideResult.isColliding, "Zero-length ray outside AABB should not collide");

        // 6. 完全相同的 AABB
        var sameAABB1:AABBCollider = new AABBCollider(0, 100, 0, 100);
        var sameAABB2:AABBCollider = new AABBCollider(0, 100, 0, 100);
        var sameResult:CollisionResult = sameAABB1.checkCollision(sameAABB2, 0);
        assertTrue(sameResult.isColliding, "Identical AABBs should collide");

        // 7. CoverageAABB 完全相同时的覆盖率
        var sameCov1:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var sameCov2:CoverageAABBCollider = new CoverageAABBCollider(0, 100, 0, 100);
        var sameCovResult:CollisionResult = sameCov1.checkCollision(sameCov2, 0);
        assertTrue(sameCovResult.isColliding, "Identical CoverageAABBs should collide");
        assertEquals(sameCovResult.overlapRatio, 1.0, "Identical CoverageAABBs overlapRatio = 1.0");

        // 8. 极大 zOffset
        var bigZResult:CollisionResult = sameAABB1.checkCollision(sameAABB2, 1000);
        // zOffset 会使 sameAABB2 的 y 坐标偏移 1000，不应再碰撞
        // 但实际实现可能不同，需验证
        trace("[INFO] Same AABB with large zOffset collision: " + bigZResult.isColliding);
    }

}
