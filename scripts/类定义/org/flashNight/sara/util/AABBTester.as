import org.flashNight.sara.util.*;
import org.flashNight.sara.graphics.*;

class org.flashNight.sara.util.AABBTester {
    private var totalTests:Number = 0;
    private var passedTests:Number = 0;
    private var failedTests:Number = 0;

    // Constructor
    public function AABBTester() {
        // Initialize test counts
        this.totalTests = 0;
        this.passedTests = 0;
        this.failedTests = 0;

        // Initialize gameworld if not present
        if (_root.gameworld == undefined) {
            _root.createEmptyMovieClip("gameworld", _root.getNextHighestDepth());
        }
    }

    // Method to run all tests
    public function runAllTests():Void {
        trace("=== Starting AABB Class Tests ===");

        // Run correctness tests
        this.testClone();
        this.testIntersects();
        this.testGetMTV();
        this.testGetMTVV();
        this.testGetMTVCornerOverlap();
        this.testGetMTVNestedBoxes();
        this.testGetMTVIdenticalBoxes();
        this.testGetMTVZeroOverlap();
        this.testGetMTVMinimalOverlap();
        this.testGetMTVNegativeCoordinates();
        this.testGetMTVEqualPenetrations();
        this.testContainsPoint();
        this.testContainsPointV(); // New
        this.testClosestPoint();
        this.testClosestPointV(); // New
        this.testIntersectsLine();
        this.testIntersectsLineV(); // New
        this.testIntersectsCircle();
        this.testIntersectsCircleV(); // New
        this.testIntersectsRay();
        this.testIntersectsRayV(); // New
        this.testMerge();
        this.testMergeWith();
        this.testMergeBatch();
        this.testSubdivide();
        this.testGetArea();
        this.testFromMovieClip();
        this.testFromBullet();
        this.testGetCenter(); // New
        this.testGetVertices(); // New

        // Run performance tests
        this.performanceTestClone();
        this.performanceTestGetWidthAndLength();
        this.performanceTestGetCenter();
        this.performanceTestGetCenterV(); // New
        this.performanceTestGetVertices(); // New
        this.performanceTestGetMTV();
        this.performanceTestGetMTVV();
        this.performanceTestContainsPoint();
        this.performanceTestContainsPointV(); // New
        this.performanceTestClosestPoint();
        this.performanceTestClosestPointV(); // New
        this.performanceTestIntersectsLine();
        this.performanceTestIntersectsLineV(); // New
        this.performanceTestIntersectsCircle();
        this.performanceTestIntersectsCircleV(); // New
        this.performanceTestIntersectsRay();
        this.performanceTestIntersectsRayV(); // New
        this.performanceTestIntersects();
        this.performanceTestMerge();
        this.performanceTestMergeWith();
        this.performanceTestMergeBatch();
        this.performanceTestSubdivide();
        this.performanceTestGetArea();
        this.performanceTestFromMovieClip();
        this.performanceTestFromBullet();
        // Note: draw() method involves graphical output and is not suitable for automated testing

        // Summary of tests
        trace("=== Test Summary ===");
        trace("Total Tests: " + this.totalTests);
        trace("Passed Tests: " + this.passedTests);
        trace("Failed Tests: " + this.failedTests);
        if (this.failedTests == 0) {
            trace("All tests passed successfully!");
        } else {
            trace("Some tests failed. Please review the failed test cases.");
        }
    }

    // Helper method to assert conditions
    private function assert(condition:Boolean, testName:String):Void {
        this.totalTests++;
        if (condition) {
            this.passedTests++;
            trace("[PASS] " + testName);
        } else {
            this.failedTests++;
            trace("[FAIL] " + testName);
        }
    }

    // ===================
    // Correctness Tests
    // ===================

    // Test clone() method
    private function testClone():Void {
        var original:AABB = new AABB(0, 100, 0, 50);
        var cloned:AABB = original.clone();

        // Check if cloned values match original
        this.assert(cloned.left == original.left, "clone() - left");
        this.assert(cloned.right == original.right, "clone() - right");
        this.assert(cloned.top == original.top, "clone() - top");
        this.assert(cloned.bottom == original.bottom, "clone() - bottom");

        // Modify cloned and check independence
        cloned.left = -50;
        this.assert(original.left == 0, "clone() - independence after modification");
    }

    // Test intersects() method
    private function testIntersects():Void {
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(50, 150, 25, 75);
        var box3:AABB = new AABB(200, 300, 200, 300);

        // box1 intersects box2
        this.assert(box1.intersects(box2) == true, "intersects() - overlapping boxes");

        // box1 does not intersect box3
        this.assert(box1.intersects(box3) == false, "intersects() - non-overlapping boxes");

        // Edge-touching boxes
        var box4:AABB = new AABB(100, 200, 0, 50);
        this.assert(box1.intersects(box4) == true, "intersects() - edge-touching boxes");
    }

    // Test getMTV() method
    private function testGetMTV():Void {
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(90, 150, 40, 90); // Overlaps on both axes

        var mtv:Object = box1.getMTV(box2);

        // Minimal overlap is along the x-axis
        this.assert(mtv.dx == -10 && mtv.dy == 0, "getMTV() - minimal x-axis overlap");

        var box3:AABB = new AABB(-50, 0, -50, 0); // Touching at the corner
        mtv = box1.getMTV(box3);
        this.assert(mtv == null, "getMTV() - corner-touching boxes (no overlap)");

        var box4:AABB = new AABB(80, 120, -10, 20); // Overlaps only on the x-axis
        mtv = box1.getMTV(box4);
        this.assert(mtv.dx == -20 && mtv.dy == 0, "getMTV() - x-axis only overlap");
    }

    // Test getMTV() method
    private function testGetMTVV():Void {
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(90, 150, 40, 90); // Overlaps on both axes

        var mtv:Vector = box1.getMTVV(box2);

        // Minimal overlap is along the x-axis
        this.assert(mtv.x == -10 && mtv.y == 0, "getMTVV() - minimal x-axis overlap");

        var box3:AABB = new AABB(-50, 0, -50, 0); // Touching at the corner
        mtv = box1.getMTVV(box3);
        this.assert(mtv == null, "getMTVV() - corner-touching boxes (no overlap)");

        var box4:AABB = new AABB(80, 120, -10, 20); // Overlaps only on the x-axis
        mtv = box1.getMTVV(box4);
        this.assert(mtv.x == -20 && mtv.y == 0, "getMTVV() - x-axis only overlap");
    }

    // Test getMTVCornerOverlap
    private function testGetMTVCornerOverlap():Void {
        var box1:AABB = new AABB(0, 100, 0, 100);
        var box2:AABB = new AABB(100, 200, 100, 200); // Touching at the corner

        var mtv:Object = box1.getMTV(box2);
        this.assert(mtv == null, "getMTV() - corner-touching boxes (no overlap)");
    }

    // Test getMTVNestedBoxes
    private function testGetMTVNestedBoxes():Void {
        var outer:AABB = new AABB(0, 100, 0, 100);
        var inner:AABB = new AABB(25, 75, 25, 75);

        var mtv:Object = inner.getMTV(outer);

        // Expect MTV to move inner box outwards by 75 units along either axis
        this.assert(
            (mtv.dx == -75 && mtv.dy == 0) || 
            (mtv.dx == 75 && mtv.dy == 0) || 
            (mtv.dx == 0 && mtv.dy == -75) || 
            (mtv.dx == 0 && mtv.dy == 75), 
            "getMTV() - nested boxes"
        );
    }

    // Test getMTVIdenticalBoxes
    private function testGetMTVIdenticalBoxes():Void {
        var box1:AABB = new AABB(0, 100, 0, 100);
        var box2:AABB = new AABB(0, 100, 0, 100);

        var mtv:Object = box1.getMTV(box2);
        // Expect MTV to resolve along any axis with a value of 100
        this.assert(
            mtv != null && (Math.abs(mtv.dx) == 100 || Math.abs(mtv.dy) == 100),
            "getMTV() - identical boxes"
        );
    }

    // Test getMTVZeroOverlap
    private function testGetMTVZeroOverlap():Void {
        var box1:AABB = new AABB(0, 100, 0, 100);
        var box2:AABB = new AABB(100, 200, 0, 100); // Touching on the edge

        var mtv:Object = box1.getMTV(box2);
        this.assert(mtv == null, "getMTV() - edge-touching boxes (no overlap)");
    }

    // Test getMTVMinimalOverlap
    private function testGetMTVMinimalOverlap():Void {
        var box1:AABB = new AABB(0, 100, 0, 100);
        var box2:AABB = new AABB(99.99, 200, 50, 150); // Overlaps by 0.01 on x-axis

        var mtv:Object = box1.getMTV(box2);
        this.assert(Math.abs(mtv.dx + 0.01) < 0.0001 && mtv.dy == 0, "getMTV() - minimal x-axis overlap");
    }

    // Test getMTVNegativeCoordinates
    private function testGetMTVNegativeCoordinates():Void {
        var box1:AABB = new AABB(-100, 0, -100, 0);
        var box2:AABB = new AABB(-50, 50, -50, 50); // Overlaps on both axes

        var mtv:Object = box1.getMTV(box2);

        // Minimal MTV should resolve along x-axis by 50 units
        this.assert(mtv.dx == -50 && mtv.dy == 0, "getMTV() - negative coordinates overlap");
    }

    // Test getMTVEqualPenetrations
    private function testGetMTVEqualPenetrations():Void {
        var box1:AABB = new AABB(0, 100, 0, 100);
        var box2:AABB = new AABB(90, 190, 90, 190); // Overlaps by 10 on both axes

        var mtv:Object = box1.getMTV(box2);

        // Minimal MTV resolves along the x-axis by 10 units
        this.assert(mtv.dx == -10 && mtv.dy == 0, "getMTV() - equal penetration on both axes");
    }

    // Test containsPoint() method
    private function testContainsPoint():Void {
        var box:AABB = new AABB(0, 100, 0, 50);

        // Points inside
        this.assert(box.containsPoint(50, 25) == true, "containsPoint() - point inside");
        this.assert(box.containsPoint(0, 0) == true, "containsPoint() - point on top-left corner");
        this.assert(box.containsPoint(100, 50) == true, "containsPoint() - point on bottom-right corner");

        // Points outside
        this.assert(box.containsPoint(-10, 25) == false, "containsPoint() - point left outside");
        this.assert(box.containsPoint(50, 60) == false, "containsPoint() - point below outside");
    }

    // Test closestPoint() method
    private function testClosestPoint():Void {
        var box:AABB = new AABB(0, 100, 0, 50);

        // Point inside
        var closest:Object = box.closestPoint(50, 25);
        this.assert(closest.x == 50 && closest.y == 25, "closestPoint() - point inside");

        // Point to the left
        closest = box.closestPoint(-10, 25);
        this.assert(closest.x == 0 && closest.y == 25, "closestPoint() - point left outside");

        // Point above
        closest = box.closestPoint(50, -20);
        this.assert(closest.x == 50 && closest.y == 0, "closestPoint() - point above outside");

        // Point to the bottom-right
        closest = box.closestPoint(150, 100);
        this.assert(closest.x == 100 && closest.y == 50, "closestPoint() - point bottom-right outside");
    }

    // Test intersectsLine() method
    private function testIntersectsLine():Void {
        var box:AABB = new AABB(0, 100, 0, 50);

        // Line entirely inside
        this.assert(box.intersectsLine(10, 10, 90, 40) == true, "intersectsLine() - line inside");

        // Line partially inside
        this.assert(box.intersectsLine(-50, 25, 50, 25) == true, "intersectsLine() - line partially inside");

        // Line entirely outside
        this.assert(box.intersectsLine(-50, -50, -10, -10) == false, "intersectsLine() - line outside");

        // Line touching the edge
        this.assert(box.intersectsLine(100, 0, 200, 50) == true, "intersectsLine() - line touching edge");
    }

    // Test intersectsCircle() method
    private function testIntersectsCircle():Void {
        var box:AABB = new AABB(0, 100, 0, 50);

        // Circle entirely inside
        this.assert(box.intersectsCircle(50, 25, 10) == true, "intersectsCircle() - circle inside");

        // Circle overlapping on the edge
        this.assert(box.intersectsCircle(100, 25, 10) == true, "intersectsCircle() - circle overlapping edge");

        // Circle entirely outside
        this.assert(box.intersectsCircle(150, 25, 10) == false, "intersectsCircle() - circle outside");

        // Circle overlapping corner
        this.assert(box.intersectsCircle(-10, -10, 15) == true, "intersectsCircle() - circle overlapping corner");
    }

    // Test intersectsRay() method
    private function testIntersectsRay():Void {
        var box:AABB = new AABB(0, 100, 0, 50);

        // Ray originating inside and going out
        this.assert(box.intersectsRay(50, 25, 1, 0) == true, "intersectsRay() - ray from inside");

        // Ray originating outside and intersecting
        this.assert(box.intersectsRay(-50, 25, 1, 0) == true, "intersectsRay() - ray intersecting box");

        // Ray originating outside and not intersecting
        this.assert(box.intersectsRay(-50, -50, 1, 0) == false, "intersectsRay() - ray not intersecting box");

        // Corrected ray parallel to x-axis and not intersecting
        this.assert(box.intersectsRay(150, 25, 0, 1) == false, "intersectsRay() - ray parallel and not intersecting");
    }

    // Test merge() method
    private function testMerge():Void {
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(50, 150, 25, 75);
        var merged:AABB = box1.merge(box2);

        this.assert(merged.left == 0, "merge() - left");
        this.assert(merged.right == 150, "merge() - right");
        this.assert(merged.top == 0, "merge() - top");
        this.assert(merged.bottom == 75, "merge() - bottom");
    }

    // Test mergeWith() method
    private function testMergeWith():Void {
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(50, 150, 25, 75);
        box1.mergeWith(box2);

        this.assert(box1.left == 0, "mergeWith() - left");
        this.assert(box1.right == 150, "mergeWith() - right");
        this.assert(box1.top == 0, "mergeWith() - top");
        this.assert(box1.bottom == 75, "mergeWith() - bottom");
    }

    // Test mergeBatch() method
    private function testMergeBatch():Void {
        var boxes:Array = [
            new AABB(0, 100, 0, 50),
            new AABB(50, 150, 25, 75),
            new AABB(-50, 50, -25, 25)
        ];

        var merged:AABB = AABB.mergeBatch(boxes);

        this.assert(merged.left == -50, "mergeBatch() - left");
        this.assert(merged.right == 150 + 1, "mergeBatch() - right (including +1)");
        this.assert(merged.top == -25, "mergeBatch() - top");
        this.assert(merged.bottom == 75 + 1, "mergeBatch() - bottom (including +1)");
    }

    // Test subdivide() method
    private function testSubdivide():Void {
        var box:AABB = new AABB(0, 100, 0, 100);
        var quads:Array = box.subdivide();

        this.assert(quads.length == 4, "subdivide() - number of quads");

        // Check the properties of each quad
        var expectedQuads:Array = [
            {left: 50, right: 100, top: 0, bottom: 50},    // quad1
            {left: 0, right: 50, top: 0, bottom: 50},      // quad2
            {left: 0, right: 50, top: 50, bottom: 100},    // quad3
            {left: 50, right: 100, top: 50, bottom: 100}   // quad4
        ];

        for (var i:Number = 0; i < quads.length; i++) {
            var quad:AABB = quads[i];
            var expected:Object = expectedQuads[i];
            this.assert(quad.left == expected.left, "subdivide() - quad" + (i+1) + " left");
            this.assert(quad.right == expected.right, "subdivide() - quad" + (i+1) + " right");
            this.assert(quad.top == expected.top, "subdivide() - quad" + (i+1) + " top");
            this.assert(quad.bottom == expected.bottom, "subdivide() - quad" + (i+1) + " bottom");
        }
    }

    // Test getArea() method
    private function testGetArea():Void {
        var box:AABB = new AABB(0, 100, 0, 50);
        var area:Number = box.getArea();

        this.assert(area == 5000, "getArea() - correct area calculation");

        // Test with zero area
        var zeroBox:AABB = new AABB(10, 10, 20, 20);
        area = zeroBox.getArea();
        this.assert(area == 0, "getArea() - zero area");
    }

    // Test fromMovieClip() method
    private function testFromMovieClip():Void {
        // Create a dummy MovieClip with predefined dimensions
        var dummyMC:MovieClip = _root.createEmptyMovieClip("dummyMC", _root.getNextHighestDepth());
        dummyMC._x = 100;
        dummyMC._y = 100;
        dummyMC.beginFill(0xFF0000);
        dummyMC.moveTo(-50, -25);
        dummyMC.lineTo(50, -25);
        dummyMC.lineTo(50, 25);
        dummyMC.lineTo(-50, 25);
        dummyMC.lineTo(-50, -25);
        dummyMC.endFill();

        var z_offset:Number = 10;
        var aabb:AABB = AABB.fromMovieClip(dummyMC, z_offset);

        // Expected values
        var expectedLeft:Number = 100 - 50;
        var expectedRight:Number = 100 + 50;
        var expectedTop:Number = 100 - 25 + z_offset;
        var expectedBottom:Number = 100 + 25 + z_offset;

        this.assert(aabb.left == expectedLeft, "fromMovieClip() - left");
        this.assert(aabb.right == expectedRight, "fromMovieClip() - right");
        this.assert(aabb.top == expectedTop, "fromMovieClip() - top");
        this.assert(aabb.bottom == expectedBottom, "fromMovieClip() - bottom");

        // Clean up
        _root.removeMovieClip(dummyMC);
    }

    // Test fromBullet() method
    private function testFromBullet():Void {
        // Create a dummy bullet MovieClip with predefined dimensions
        var bulletMC:MovieClip = _root.createEmptyMovieClip("bulletMC", _root.getNextHighestDepth());
        bulletMC._x = 200;
        bulletMC._y = 200;
        bulletMC.beginFill(0x00FF00);
        bulletMC.moveTo(-10, -10);
        bulletMC.lineTo(10, -10);
        bulletMC.lineTo(10, 10);
        bulletMC.lineTo(-10, 10);
        bulletMC.lineTo(-10, -10);
        bulletMC.endFill();

        var aabb:AABB = AABB.fromBullet(bulletMC);

        // Expected values
        var expectedLeft:Number = 200 - 10;
        var expectedRight:Number = 200 + 10;
        var expectedTop:Number = 200 - 10;
        var expectedBottom:Number = 200 + 10;

        this.assert(aabb.left == expectedLeft, "fromBullet() - left");
        this.assert(aabb.right == expectedRight, "fromBullet() - right");
        this.assert(aabb.top == expectedTop, "fromBullet() - top");
        this.assert(aabb.bottom == expectedBottom, "fromBullet() - bottom");

        // Clean up
        _root.removeMovieClip(bulletMC);
    }

    // ===================
    // Performance Tests
    // ===================

    // Helper method to format milliseconds
    private function formatTime(ms:Number):String {
        return ms + " ms";
    }

    // Performance test for clone()
    private function performanceTestClone():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            var cloned:AABB = box.clone();
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] clone() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // Performance test for getWidth() and getLength()
    private function performanceTestGetWidthAndLength():Void {
        var iterations:Number = 100000;
        var box:AABB = new AABB(0, 100, 0, 50);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            var width:Number = box.getWidth();
            var length:Number = box.getLength();
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] getWidth() and getLength() executed " + (iterations * 2) + " times in " + this.formatTime(elapsed));
    }


    // Performance test for getMTV()
    private function performanceTestGetMTV():Void {
        var iterations:Number = 10000;
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(50, 150, 25, 75);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            box1.getMTV(box2);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] getMTV() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // Performance test for getMTV()
    private function performanceTestGetMTVV():Void {
        var iterations:Number = 10000;
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(50, 150, 25, 75);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            box1.getMTVV(box2);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] getMTVV() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // Performance test for intersects()
    private function performanceTestIntersects():Void {
        var iterations:Number = 10000;
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(50, 150, 25, 75);
        var box3:AABB = new AABB(200, 300, 200, 300);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            box1.intersects(box2);
            box1.intersects(box3);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] intersects() executed " + (iterations * 2) + " times in " + this.formatTime(elapsed));
    }

    // Test getCenter() method (returns Vector)
    private function testGetCenter():Void {
        var box:AABB = new AABB(0, 100, 0, 50);
        var center:Vector = box.getCenter();

        this.assert(center.x == 50 && center.y == 25, "getCenter() - correct center");
    }

    // New Correctness Test: getCenterV() is not needed since getCenter() already returns Vector

    // Test getVertices() method
    private function testGetVertices():Void {
        var box:AABB = new AABB(0, 100, 0, 50);
        var vertices:Array = box.getVertices();

        var expectedVertices:Array = [
            new Vector(0, 0),
            new Vector(100, 0),
            new Vector(100, 50),
            new Vector(0, 50)
        ];

        this.assert(vertices.length == 4, "getVertices() - number of vertices");

        for (var i:Number = 0; i < vertices.length; i++) {
            var v:Vector = vertices[i];
            var expected:Vector = expectedVertices[i];
            this.assert(v.x == expected.x && v.y == expected.y, "getVertices() - vertex " + (i+1));
        }
    }

    // Test containsPointV() method
    private function testContainsPointV():Void {
        var box:AABB = new AABB(0, 100, 0, 50);
        var insidePoint:Vector = new Vector(50, 25);
        var edgePoint:Vector = new Vector(100, 50);
        var outsidePoint:Vector = new Vector(150, 75);

        this.assert(box.containsPointV(insidePoint) == true, "containsPointV() - point inside");
        this.assert(box.containsPointV(edgePoint) == true, "containsPointV() - point on edge");
        this.assert(box.containsPointV(outsidePoint) == false, "containsPointV() - point outside");
    }

    // Test closestPointV() method
    private function testClosestPointV():Void {
        var box:AABB = new AABB(0, 100, 0, 50);

        // Point inside
        var insidePoint:Vector = new Vector(50, 25);
        var closest:Vector = box.closestPointV(insidePoint);
        this.assert(closest.x == 50 && closest.y == 25, "closestPointV() - point inside");

        // Point to the left
        var leftPoint:Vector = new Vector(-10, 25);
        closest = box.closestPointV(leftPoint);
        this.assert(closest.x == 0 && closest.y == 25, "closestPointV() - point left outside");

        // Point above
        var abovePoint:Vector = new Vector(50, -20);
        closest = box.closestPointV(abovePoint);
        this.assert(closest.x == 50 && closest.y == 0, "closestPointV() - point above outside");

        // Point to the bottom-right
        var bottomRightPoint:Vector = new Vector(150, 100);
        closest = box.closestPointV(bottomRightPoint);
        this.assert(closest.x == 100 && closest.y == 50, "closestPointV() - point bottom-right outside");
    }

    // Test intersectsLineV() method
    private function testIntersectsLineV():Void {
        var box:AABB = new AABB(0, 100, 0, 50);

        // Line entirely inside
        var lineStart:Vector = new Vector(10, 10);
        var lineEnd:Vector = new Vector(90, 40);
        this.assert(box.intersectsLineV(lineStart, lineEnd) == true, "intersectsLineV() - line inside");

        // Line partially inside
        lineStart = new Vector(-50, 25);
        lineEnd = new Vector(50, 25);
        this.assert(box.intersectsLineV(lineStart, lineEnd) == true, "intersectsLineV() - line partially inside");

        // Line entirely outside
        lineStart = new Vector(-50, -50);
        lineEnd = new Vector(-10, -10);
        this.assert(box.intersectsLineV(lineStart, lineEnd) == false, "intersectsLineV() - line outside");

        // Line touching the edge
        lineStart = new Vector(100, 0);
        lineEnd = new Vector(200, 50);
        this.assert(box.intersectsLineV(lineStart, lineEnd) == true, "intersectsLineV() - line touching edge");
    }

    // Test intersectsCircleV() method
    private function testIntersectsCircleV():Void {
        var box:AABB = new AABB(0, 100, 0, 50);

        // Circle entirely inside
        var circleCenter:Vector = new Vector(50, 25);
        var radius:Number = 10;
        this.assert(box.intersectsCircleV(circleCenter, radius) == true, "intersectsCircleV() - circle inside");

        // Circle overlapping on the edge
        circleCenter = new Vector(100, 25);
        radius = 10;
        this.assert(box.intersectsCircleV(circleCenter, radius) == true, "intersectsCircleV() - circle overlapping edge");

        // Circle entirely outside
        circleCenter = new Vector(150, 25);
        radius = 10;
        this.assert(box.intersectsCircleV(circleCenter, radius) == false, "intersectsCircleV() - circle outside");

        // Circle overlapping corner
        circleCenter = new Vector(-10, -10);
        radius = 15;
        this.assert(box.intersectsCircleV(circleCenter, radius) == true, "intersectsCircleV() - circle overlapping corner");
    }

    // Test intersectsRayV() method
    private function testIntersectsRayV():Void {
        var box:AABB = new AABB(0, 100, 0, 50);

        // Ray originating inside and going out
        var rayOrigin:Vector = new Vector(50, 25);
        var rayDir:Vector = new Vector(1, 0);
        this.assert(box.intersectsRayV(rayOrigin, rayDir) == true, "intersectsRayV() - ray from inside");

        // Ray originating outside and intersecting
        rayOrigin = new Vector(-50, 25);
        rayDir = new Vector(1, 0);
        this.assert(box.intersectsRayV(rayOrigin, rayDir) == true, "intersectsRayV() - ray intersecting box");

        // Ray originating outside and not intersecting
        rayOrigin = new Vector(-50, -50);
        rayDir = new Vector(1, 0);
        this.assert(box.intersectsRayV(rayOrigin, rayDir) == false, "intersectsRayV() - ray not intersecting box");

        // Ray parallel to y-axis and not intersecting
        rayOrigin = new Vector(150, 25);
        rayDir = new Vector(0, 1);
        this.assert(box.intersectsRayV(rayOrigin, rayDir) == false, "intersectsRayV() - ray parallel and not intersecting");
    }

    // ===================
    // Performance Tests
    // ===================

    // Performance test for getCenter()
    private function performanceTestGetCenter():Void {
        var iterations:Number = 100000;
        var box:AABB = new AABB(0, 100, 0, 50);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            var center:Object = box.getCenter();
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] getCenter() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // New Performance Test: getCenter() returning Vector
    private function performanceTestGetCenterV():Void {
        var iterations:Number = 100000;
        var box:AABB = new AABB(0, 100, 0, 50);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            var center:Vector = box.getCenter();
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] getCenter() returning Vector executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // New Performance Test: getVertices()
    private function performanceTestGetVertices():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            var vertices:Array = box.getVertices();
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] getVertices() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // Performance test for containsPoint()
    private function performanceTestContainsPoint():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var insidePoint:Object = {x: 50, y: 25};
        var outsidePoint:Object = {x: 150, y: 75};

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            box.containsPoint(insidePoint.x, insidePoint.y);
            box.containsPoint(outsidePoint.x, outsidePoint.y);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] containsPoint() executed " + (iterations * 2) + " times in " + this.formatTime(elapsed));
    }

    // New Performance Test: containsPointV()
    private function performanceTestContainsPointV():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var insidePoint:Vector = new Vector(50, 25);
        var outsidePoint:Vector = new Vector(150, 75);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            box.containsPointV(insidePoint);
            box.containsPointV(outsidePoint);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] containsPointV() executed " + (iterations * 2) + " times in " + this.formatTime(elapsed));
    }

    // Performance test for closestPoint()
    private function performanceTestClosestPoint():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var points:Array = [
            {x: 50, y: 25},
            {x: -50, y: -25},
            {x: 150, y: 75}
        ];

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            for (var j:Number = 0; j < points.length; j++) {
                box.closestPoint(points[j].x, points[j].y);
            }
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] closestPoint() executed " + (iterations * points.length) + " times in " + this.formatTime(elapsed));
    }

    // New Performance Test: closestPointV()
    private function performanceTestClosestPointV():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var points:Array = [
            new Vector(50, 25),
            new Vector(-50, -25),
            new Vector(150, 75)
        ];

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            for (var j:Number = 0; j < points.length; j++) {
                box.closestPointV(points[j]);
            }
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] closestPointV() executed " + (iterations * points.length) + " times in " + this.formatTime(elapsed));
    }

    // Performance test for intersectsLine()
    private function performanceTestIntersectsLine():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var lines:Array = [
            {x1: 10, y1: 10, x2: 90, y2: 40},
            {x1: -50, y1: 25, x2: 50, y2: 25},
            {x1: -50, y1: -50, x2: -10, y2: -10},
            {x1: 100, y1: 0, x2: 200, y2: 50}
        ];

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            for (var j:Number = 0; j < lines.length; j++) {
                box.intersectsLine(lines[j].x1, lines[j].y1, lines[j].x2, lines[j].y2);
            }
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] intersectsLine() executed " + (iterations * lines.length) + " times in " + this.formatTime(elapsed));
    }

    // New Performance Test: intersectsLineV()
    private function performanceTestIntersectsLineV():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var lines:Array = [
            {start: new Vector(10, 10), end: new Vector(90, 40)},
            {start: new Vector(-50, 25), end: new Vector(50, 25)},
            {start: new Vector(-50, -50), end: new Vector(-10, -10)},
            {start: new Vector(100, 0), end: new Vector(200, 50)}
        ];

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            for (var j:Number = 0; j < lines.length; j++) {
                box.intersectsLineV(lines[j].start, lines[j].end);
            }
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] intersectsLineV() executed " + (iterations * lines.length) + " times in " + this.formatTime(elapsed));
    }

    // Performance test for intersectsCircle()
    private function performanceTestIntersectsCircle():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var circles:Array = [
            {x: 50, y: 25, r: 10},
            {x: 150, y: 75, r: 10},
            {x: -10, y: -10, r: 15}
        ];

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            for (var j:Number = 0; j < circles.length; j++) {
                box.intersectsCircle(circles[j].x, circles[j].y, circles[j].r);
            }
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] intersectsCircle() executed " + (iterations * circles.length) + " times in " + this.formatTime(elapsed));
    }

    // New Performance Test: intersectsCircleV()
    private function performanceTestIntersectsCircleV():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var circles:Array = [
            {center: new Vector(50, 25), r: 10},
            {center: new Vector(150, 75), r: 10},
            {center: new Vector(-10, -10), r: 15}
        ];

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            for (var j:Number = 0; j < circles.length; j++) {
                box.intersectsCircleV(circles[j].center, circles[j].r);
            }
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] intersectsCircleV() executed " + (iterations * circles.length) + " times in " + this.formatTime(elapsed));
    }

    // Performance test for intersectsRay()
    private function performanceTestIntersectsRay():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var rays:Array = [
            {ox: 50, oy: 25, dx: 1, dy: 0},
            {ox: -50, oy: 25, dx: 1, dy: 0},
            {ox: 50, oy: -10, dx: 0, dy: 1}
        ];

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            for (var j:Number = 0; j < rays.length; j++) {
                box.intersectsRay(rays[j].ox, rays[j].oy, rays[j].dx, rays[j].dy);
            }
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] intersectsRay() executed " + (iterations * rays.length) + " times in " + this.formatTime(elapsed));
    }

    // New Performance Test: intersectsRayV()
    private function performanceTestIntersectsRayV():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 50);
        var rays:Array = [
            {origin: new Vector(50, 25), dir: new Vector(1, 0)},
            {origin: new Vector(-50, 25), dir: new Vector(1, 0)},
            {origin: new Vector(50, -10), dir: new Vector(0, 1)}
        ];

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            for (var j:Number = 0; j < rays.length; j++) {
                box.intersectsRayV(rays[j].origin, rays[j].dir);
            }
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] intersectsRayV() executed " + (iterations * rays.length) + " times in " + this.formatTime(elapsed));
    }

    // Performance test for merge()
    private function performanceTestMerge():Void {
        var iterations:Number = 10000;
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(50, 150, 25, 75);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            box1.merge(box2);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] merge() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // Performance test for mergeWith()
    private function performanceTestMergeWith():Void {
        var iterations:Number = 10000;
        var box1:AABB = new AABB(0, 100, 0, 50);
        var box2:AABB = new AABB(50, 150, 25, 75);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            box1.mergeWith(box2);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] mergeWith() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // Performance test for mergeBatch()
    private function performanceTestMergeBatch():Void {
        var iterations:Number = 1000; // Reduced iterations for mergeBatch due to higher computational load
        var aabbs:Array = [];
        for (var i:Number = 0; i < 100; i++) { // Create 100 AABBs
            aabbs.push(new AABB(i, i + 10, i, i + 5));
        }

        var startTime:Number = getTimer();
        for (var j:Number = 0; j < iterations; j++) {
            AABB.mergeBatch(aabbs);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] mergeBatch() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // Performance test for subdivide()
    private function performanceTestSubdivide():Void {
        var iterations:Number = 10000;
        var box:AABB = new AABB(0, 100, 0, 100);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            box.subdivide();
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] subdivide() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // Performance test for getArea()
    private function performanceTestGetArea():Void {
        var iterations:Number = 100000;
        var box:AABB = new AABB(0, 100, 0, 50);

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            box.getArea();
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] getArea() executed " + iterations + " times in " + this.formatTime(elapsed));
    }

    // Performance test for fromMovieClip()
    private function performanceTestFromMovieClip():Void {
        var iterations:Number = 10000;
        var dummyMC:MovieClip = _root.createEmptyMovieClip("dummyMC_PERF", _root.getNextHighestDepth());
        dummyMC._x = 100;
        dummyMC._y = 100;
        dummyMC.beginFill(0xFF0000);
        dummyMC.moveTo(-50, -25);
        dummyMC.lineTo(50, -25);
        dummyMC.lineTo(50, 25);
        dummyMC.lineTo(-50, 25);
        dummyMC.lineTo(-50, -25);
        dummyMC.endFill();

        var z_offset:Number = 10;

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            var aabb:AABB = AABB.fromMovieClip(dummyMC, z_offset);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] fromMovieClip() executed " + iterations + " times in " + this.formatTime(elapsed));

        // Clean up
        _root.removeMovieClip(dummyMC);
    }

    // Performance test for fromBullet()
    private function performanceTestFromBullet():Void {
        var iterations:Number = 10000;
        var bulletMC:MovieClip = _root.createEmptyMovieClip("bulletMC_PERF", _root.getNextHighestDepth());
        bulletMC._x = 200;
        bulletMC._y = 200;
        bulletMC.beginFill(0x00FF00);
        bulletMC.moveTo(-10, -10);
        bulletMC.lineTo(10, -10);
        bulletMC.lineTo(10, 10);
        bulletMC.lineTo(-10, 10);
        bulletMC.lineTo(-10, -10);
        bulletMC.endFill();

        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            var aabb:AABB = AABB.fromBullet(bulletMC);
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;

        trace("[PERF] fromBullet() executed " + iterations + " times in " + this.formatTime(elapsed));

        // Clean up
        _root.removeMovieClip(bulletMC);
    }
}
