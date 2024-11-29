import org.flashNight.sara.util.*;

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

        // In AABBTester constructor or before tests
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
        this.testContainsPoint();
        this.testClosestPoint();
        this.testIntersectsLine();
        this.testIntersectsCircle();
        this.testIntersectsRay();
        this.testMerge();
        this.testMergeWith();
        this.testMergeBatch();
        this.testSubdivide();
        this.testGetArea();
        this.testFromMovieClip();
        this.testFromBullet();
        // Note: draw() method involves graphical output and is not suitable for automated testing

        // Run performance tests
        this.performanceTestIntersects();
        this.performanceTestGetMTV();
        this.performanceTestContainsPoint();
        this.performanceTestClosestPoint();
        this.performanceTestIntersectsLine();
        this.performanceTestIntersectsCircle();
        this.performanceTestIntersectsRay();
        this.performanceTestMerge();
        this.performanceTestMergeWith();
        this.performanceTestMergeBatch();
        this.performanceTestSubdivide();
        this.performanceTestGetArea();

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

        // MTV should be minimal on the x-axis: overlapX = 100 - 90 = 10
        this.assert(mtv.dx == 10 && mtv.dy == 0, "getMTV() - minimal x-axis overlap");

        var box3:AABB = new AABB(-50, 0, -50, 0); // Touching at the corner

        mtv = box1.getMTV(box3);
        this.assert(mtv == null, "getMTV() - corner-touching boxes (no overlap)");

        var box4:AABB = new AABB(80, 120, -10, 20); // Overlaps only on the x-axis
        mtv = box1.getMTV(box4);
        this.assert(mtv.dx == 20 && mtv.dy == 0, "getMTV() - x-axis only overlap");
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

    // Performance Test Methods

    // Helper method to format milliseconds
    private function formatTime(ms:Number):String {
        return ms + " ms";
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
}
