// 文件路径: org/flashNight/gesh/array/PrimeSpectrumMapperTest.as
import org.flashNight.gesh.array.*;

class org.flashNight.gesh.array.PrimeSpectrumMapperTest {
    
    private static function assert(condition:Boolean, message:String, actual, expected):Void {
        if (condition) {
            trace("[PASS] " + message);
        } else {
            trace("[FAIL] " + message);
            trace("  Actual:   " + actual);
            trace("  Expected: " + expected);
        }
    }
    
    // 测试 1: 基本功能
    private static function testBasicFunctionality():Void {
        var mapper:PrimeSpectrumMapper = new PrimeSpectrumMapper(null);
        var sourceArr:Array = [1,2,3,4,5];
        var result:Array = mapper.mapToPrimeSpectrum(sourceArr, "fit");
        var expected:Array = [2,3,5,7,11];
        
        trace("\n--- Testing Basic Functionality ---");
        trace("Input Array: " + sourceArr);
        assert(
            result.toString() == expected.toString(),
            "Basic Functionality",
            result,
            expected
        );
    }
    
    // 测试 2: 边界值
    private static function testBoundaryValues():Void {
        var mapper:PrimeSpectrumMapper = new PrimeSpectrumMapper(null);
        var sourceArr:Array = [0, 97, 1000];
        var result:Array = mapper.mapToPrimeSpectrum(sourceArr, "fit");
        var expectedValues:Array = [2, 97, 97];
        
        trace("\n--- Testing Boundary Values ---");
        trace("Input Array: " + sourceArr);
        for (var i:Number = 0; i < result.length; i++) {
            assert(
                result[i] == expectedValues[i],
                "Element " + i + " (Input=" + sourceArr[i] + ")",
                result[i],
                expectedValues[i]
            );
        }
    }
    
    // 测试 3: 动态生成质数
    private static function testDynamicPrimeGeneration():Void {
        var mapper:PrimeSpectrumMapper = new PrimeSpectrumMapper(null);
        var sourceArr:Array = [100, 200, 300];
        var result:Array = mapper.mapToPrimeSpectrum(sourceArr, "expand");
        var expected:Array = [101, 199, 293];
        
        trace("\n--- Testing Dynamic Prime Generation ---");
        trace("Input Array: " + sourceArr);
        for (var i:Number = 0; i < result.length; i++) {
            assert(
                result[i] == expected[i],
                "Element " + i + " (Input=" + sourceArr[i] + ")",
                result[i],
                expected[i]
            );
        }
    }
    
    // 测试 4: 缩放模式
    private static function testScaleModes():Void {
        var mapper:PrimeSpectrumMapper = new PrimeSpectrumMapper(null);
        var sourceArr:Array = [10, 20, 30];
        
        trace("\n--- Testing Scale Modes ---");
        
        // Fit 模式
        var fitResult:Array = mapper.mapToPrimeSpectrum(sourceArr, "fit");
        var fitExpected:Array = [11, 23, 37];
        trace("\nFit Mode:");
        trace("Input Array: " + sourceArr);
        for (var i:Number = 0; i < fitResult.length; i++) {
            assert(
                fitResult[i] == fitExpected[i],
                "Fit Mode - Element " + i,
                fitResult[i],
                fitExpected[i]
            );
        }
        
        // Clip 模式
        var clipResult:Array = mapper.mapToPrimeSpectrum(sourceArr, "clip");
        var clipExpected:Array = [11, 19, 29];
        trace("\nClip Mode:");
        trace("Input Array: " + sourceArr);
        for (var i:Number = 0; i < clipResult.length; i++) {
            assert(
                clipResult[i] == clipExpected[i],
                "Clip Mode - Element " + i,
                clipResult[i],
                clipExpected[i]
            );
        }
        
        // Expand 模式
        var expandResult:Array = mapper.mapToPrimeSpectrum(sourceArr, "expand");
        var expandExpected:Array = [11, 23, 37];
        trace("\nExpand Mode:");
        trace("Input Array: " + sourceArr);
        for (var i:Number = 0; i < expandResult.length; i++) {
            assert(
                expandResult[i] == expandExpected[i],
                "Expand Mode - Element " + i,
                expandResult[i],
                expandExpected[i]
            );
        }
    }
    
    public static function runAllTests():Void {
        trace("===== Starting Tests =====");
        testBasicFunctionality();
        testBoundaryValues();
        testDynamicPrimeGeneration();
        testScaleModes();
        trace("===== Tests Completed =====");
    }
}