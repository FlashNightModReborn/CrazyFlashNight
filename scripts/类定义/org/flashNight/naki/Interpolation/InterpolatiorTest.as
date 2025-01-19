import org.flashNight.naki.Interpolation.*;

class org.flashNight.naki.Interpolation.InterpolatiorTest {
    private var testsPassed:Number = 0;
    private var testsFailed:Number = 0;
    private var performanceResults:Object = {};

    // Assertion method to check equality with a tolerance for floating point comparisons
    private function assertEqual(expected:Number, actual:Number, tolerance:Number, message:String):Void {
        if (Math.abs(expected - actual) > tolerance) {
            trace("FAIL: " + message + " | Expected: " + expected + ", Actual: " + actual);
            testsFailed++;
        } else {
            trace("PASS: " + message);
            testsPassed++;
        }
    }

    // Assertion method to check boolean conditions
    private function assertTrue(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("FAIL: " + message);
            testsFailed++;
        } else {
            trace("PASS: " + message);
            testsPassed++;
        }
    }

    // Test method for linear interpolation
    private function testLinear():Void {
        trace("\nTesting Linear Interpolation...");
        var result:Number;

        // Test case 1
        result = Interpolatior.linear(5, 0, 10, 0, 100);
        this.assertEqual(50, result, 0.0001, "Linear: Mapping 5 from [0,10] to [0,100]");

        // Test case 2: srcLow == srcHigh
        result = Interpolatior.linear(5, 10, 10, 0, 100);
        this.assertEqual(0, result, 0.0001, "Linear: srcLow == srcHigh");

        // Test case 3: value at dstHigh
        result = Interpolatior.linear(10, 0, 10, 0, 100);
        this.assertEqual(100, result, 0.0001, "Linear: Mapping 10 from [0,10] to [0,100]");
    }

    // Test method for slerp interpolation
    private function testSlerp():Void {
        trace("\nTesting Slerp Interpolation...");
        var result:Number;

        // Test case 1: t = 0 should return start
        result = Interpolatior.slerp(1, 0, 0);
        this.assertEqual(1, result, 0.0001, "Slerp: t=0 should return start");

        // Test case 2: t = 1 should return end
        result = Interpolatior.slerp(1, 0, 1);
        this.assertEqual(0, result, 0.0001, "Slerp: t=1 should return end");

        // Test case 3: t = 0.5 should return average
        result = Interpolatior.slerp(1, 0, 0.5);
        this.assertEqual(Math.cos(Math.PI / 4), result, 0.0001, "Slerp: t=0.5 midpoint");
    }

    // Test method for cubic interpolation
    private function testCubic():Void {
        trace("\nTesting Cubic Interpolation...");
        var result:Number;

        // Example: Catmull-Rom with p0=0, p1=1, p2=2, p3=3 at t=0.5 should be 1.5
        result = Interpolatior.cubic(0.5, 0, 1, 2, 3);
        this.assertEqual(1.5, result, 0.0001, "Cubic: t=0.5 with linear points");

        // Additional test cases can be added as needed
    }

    // Test method for hermite interpolation
    private function testHermite():Void {
        trace("\nTesting Hermite Interpolation...");
        var result:Number;

        // Test case 1: t=0 should return p0
        result = Interpolatior.hermite(0, 0, 10, 0, 0);
        this.assertEqual(0, result, 0.0001, "Hermite: t=0 should return p0");

        // Test case 2: t=1 should return p1
        result = Interpolatior.hermite(1, 0, 10, 0, 0);
        this.assertEqual(10, result, 0.0001, "Hermite: t=1 should return p1");

        // Test case 3: t=0.5 with zero tangents should return midpoint
        result = Interpolatior.hermite(0.5, 0, 10, 0, 0);
        this.assertEqual(5, result, 0.0001, "Hermite: t=0.5 with zero tangents");
    }

    // Test method for bezier interpolation
    private function testBezier():Void {
        trace("\nTesting Bezier Interpolation...");
        var result:Number;

        // Test case 1: t=0 should return p0
        result = Interpolatior.bezier(0, 0, 0, 0, 0);
        this.assertEqual(0, result, 0.0001, "Bezier: t=0 should return p0");

        // Test case 2: t=1 should return p3
        result = Interpolatior.bezier(1, 0, 0, 0, 10);
        this.assertEqual(10, result, 0.0001, "Bezier: t=1 should return p3");

        // Test case 3: t=0.5 with linear control points should return midpoint
        result = Interpolatior.bezier(0.5, 0, 5, 5, 10);
        this.assertEqual(5, result, 0.0001, "Bezier: t=0.5 with linear control points");
    }

    // Test method for easeInOut interpolation
    private function testEaseInOut():Void {
        trace("\nTesting Ease-In-Out Interpolation...");
        var result:Number;

        // Test case 1: t=0 should return 0
        result = Interpolatior.easeInOut(0);
        this.assertEqual(0, result, 0.0001, "EaseInOut: t=0 should return 0");

        // Test case 2: t=0.5 should return 0.5
        result = Interpolatior.easeInOut(0.5);
        this.assertEqual(0.5, result, 0.0001, "EaseInOut: t=0.5 should return 0.5");

        // Test case 3: t=1 should return 1
        result = Interpolatior.easeInOut(1);
        this.assertEqual(1, result, 0.0001, "EaseInOut: t=1 should return 1");
    }

    // Test method for bilinear interpolation
    private function testBilinear():Void {
        trace("\nTesting Bilinear Interpolation...");
        var result:Number;

        // Test case 1: center point
        result = Interpolatior.bilinear(5, 5, 0, 10, 10, 20, 0, 10, 0, 10);
        this.assertEqual(15, result, 0.0001, "Bilinear: center point");

        // Test case 2: corner point (x1, y1)
        result = Interpolatior.bilinear(0, 0, 5, 10, 15, 20, 0, 10, 0, 10);
        this.assertEqual(5, result, 0.0001, "Bilinear: corner point (x1, y1)");

        // Test case 3: corner point (x2, y2)
        result = Interpolatior.bilinear(10, 10, 5, 10, 15, 20, 0, 10, 0, 10);
        this.assertEqual(20, result, 0.0001, "Bilinear: corner point (x2, y2)");
    }

    // Test method for bicubic interpolation
    private function testBicubic():Void {
        trace("\nTesting Bicubic Interpolation...");
        var result:Number;

        // Test case 1: linear points
        result = Interpolatior.bicubic(0.5, 0, 1, 2, 3);
        this.assertEqual(1.5, result, 0.0001, "Bicubic: t=0.5 with linear points");

        // Additional test cases can be added as needed
    }

    // Test method for Catmull-Rom spline interpolation
    private function testCatmullRom():Void {
        trace("\nTesting Catmull-Rom Spline Interpolation...");
        var result:Number;

        // Test case 1: simple spline
        result = Interpolatior.catmullRom(0.5, 0, 10, 20, 30);
        this.assertEqual(15, result, 0.0001, "Catmull-Rom: t=0.5 simple spline");
    }

    // Test method for exponential interpolation
    private function testExponential():Void {
        trace("\nTesting Exponential Interpolation...");
        var result:Number;

        // Test case 1: base=2, value=1 should return 1
        result = Interpolatior.exponential(1, 2);
        this.assertEqual(1, result, 0.0001, "Exponential: base=2, value=1");

        // Test case 2: base=3, value=2 should return 8
        result = Interpolatior.exponential(2, 3);
        this.assertEqual(8, result, 0.0001, "Exponential: base=3, value=2");
    }

    // Test method for sine interpolation
    private function testSine():Void {
        trace("\nTesting Sinusoidal Interpolation...");
        var result:Number;

        // Test case 1: t=0 should return 0
        result = Interpolatior.sine(0);
        this.assertEqual(0, result, 0.0001, "Sine: t=0 should return 0");

        // Test case 2: t=1 should return 1
        result = Interpolatior.sine(1);
        this.assertEqual(1, result, 0.0001, "Sine: t=1 should return 1");

        // Test case 3: t=0.5 should return sin(π/4) ≈ 0.7071
        result = Interpolatior.sine(0.5);
        this.assertEqual(Math.sin(Math.PI / 4), result, 0.0001, "Sine: t=0.5 should return sin(π/4)");
    }

    // Test method for elastic interpolation
    private function testElastic():Void {
        trace("\nTesting Elastic Interpolation...");
        var result:Number;

        // Test case 1: t=0 should return 0
        result = Interpolatior.elastic(0);
        this.assertEqual(0, result, 0.0001, "Elastic: t=0 should return 0");

        // Test case 2: t=1 should return 1
        result = Interpolatior.elastic(1);
        this.assertEqual(1, result, 0.0001, "Elastic: t=1 should return 1");

        // Test case 3: t=0.5 should be approximately 0.5 with elastic behavior
        // Exact value depends on the implementation; here we check it's within a reasonable range
        result = Interpolatior.elastic(0.5);
        this.assertTrue(result > 0 && result < 1, "Elastic: t=0.5 should be between 0 and 1");
    }

    // Test method for logarithmic interpolation
    private function testLogarithmic():Void {
        trace("\nTesting Logarithmic Interpolation...");
        var result:Number;

        // Test case 1: value=0, base=2 should return 0
        result = Interpolatior.logarithmic(0, 2);
        this.assertEqual(0, result, 0.0001, "Logarithmic: value=0, base=2");

        // Test case 2: value=1, base=2 should return 1
        result = Interpolatior.logarithmic(1, 2);
        this.assertEqual(1, result, 0.0001, "Logarithmic: value=1, base=2");

        // Test case 3: value=3, base=2 should return ~1.585
        result = Interpolatior.logarithmic(3, 2);
        this.assertEqual(Math.log(4) / Math.log(2), result, 0.0001, "Logarithmic: value=3, base=2");
    }

    // Test method for Perlin noise interpolation
    private function testPerlin():Void {
        trace("\nTesting Perlin Noise Interpolation...");
        var result:Number;

        // Test case 1: t=0 should return 0
        result = Interpolatior.perlin(0);
        this.assertEqual(0, result, 0.0001, "Perlin: t=0 should return 0");

        // Test case 2: t=1 should return 1
        result = Interpolatior.perlin(1);
        this.assertEqual(1, result, 0.0001, "Perlin: t=1 should return 1");

        // Test case 3: t=0.5 should return 0.5
        result = Interpolatior.perlin(0.5);
        this.assertEqual(0.5, result, 0.0001, "Perlin: t=0.5 should return 0.5");
    }

    // Performance evaluation for a given method
    private function evaluatePerformance(methodName:String, method:Function, iterations:Number):Void {
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            method.apply(null, arguments.slice(3)); // Pass additional arguments if any
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;
        performanceResults[methodName] = elapsed;
    }

    // Run all tests and performance evaluations
    public function runTests():Void {
        trace("=== Starting Interpolatior Tests ===");

        // Correctness Tests
        this.testLinear();
        this.testSlerp();
        this.testCubic();
        this.testHermite();
        this.testBezier();
        this.testEaseInOut();
        this.testBilinear();
        this.testBicubic();
        this.testCatmullRom();
        this.testExponential();
        this.testSine();
        this.testElastic();
        this.testLogarithmic();
        this.testPerlin();

        // Performance Tests
        trace("\n=== Starting Performance Tests ===");
        var iterations:Number = 100000;

        // Define a helper function to bind methods with fixed parameters for performance testing
        var bindMethod = function(method:Function, args:Array):Function {
            return function():Void {
                method.apply(null, args);
            };
        };

        // List of methods to test performance
        var methods:Object = {
            linear: bindMethod(Interpolatior.linear, [5, 0, 10, 0, 100]),
            slerp: bindMethod(Interpolatior.slerp, [1, 0, 0.5]),
            cubic: bindMethod(Interpolatior.cubic, [0.5, 0, 1, 2, 3]),
            hermite: bindMethod(Interpolatior.hermite, [0.5, 0, 10, 0, 0]),
            bezier: bindMethod(Interpolatior.bezier, [0.5, 0, 5, 5, 10]),
            easeInOut: bindMethod(Interpolatior.easeInOut, [0.5]),
            bilinear: bindMethod(Interpolatior.bilinear, [5, 5, 0, 10, 10, 20, 0, 10, 0, 10]),
            bicubic: bindMethod(Interpolatior.bicubic, [0.5, 0, 1, 2, 3]),
            catmullRom: bindMethod(Interpolatior.catmullRom, [0.5, 0, 10, 20, 30]),
            exponential: bindMethod(Interpolatior.exponential, [2, 1]),
            sine: bindMethod(Interpolatior.sine, [0.5]),
            elastic: bindMethod(Interpolatior.elastic, [0.5]),
            logarithmic: bindMethod(Interpolatior.logarithmic, [3, 2]),
            perlin: bindMethod(Interpolatior.perlin, [0.5])
        };

        // Evaluate performance for each method
        for (var methodName:String in methods) {
            var method:Function = methods[methodName];
            var startTime:Number = getTimer();
            for (var i:Number = 0; i < iterations; i++) {
                method();
            }
            var endTime:Number = getTimer();
            var elapsed:Number = endTime - startTime;
            performanceResults[methodName] = elapsed;
            trace("Performance: " + methodName + " executed " + iterations + " times in " + elapsed + " ms");
        }

        // Summary
        trace("\n=== Test Summary ===");
        trace("Tests Passed: " + this.testsPassed);
        trace("Tests Failed: " + this.testsFailed);

        if (this.testsFailed > 0) {
            trace("Some tests failed. Please review the above messages.");
        } else {
            trace("All tests passed successfully!");
        }

        // Performance Summary
        trace("\n=== Performance Summary (ms) ===");
        for (var methodName:String in performanceResults) {
            trace(methodName + ": " + performanceResults[methodName] + " ms for " + iterations + " iterations");
        }

        trace("\n=== Interpolatior Tests Completed ===");
    }
}
