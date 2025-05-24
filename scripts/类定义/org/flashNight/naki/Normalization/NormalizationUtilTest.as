// File: org/flashNight/naki/Normalization/NormalizationUtilTest.as
import org.flashNight.naki.Normalization.*;

/**
 * NormalizationUtilTest
 * 用于测试 NormalizationUtil 类中各个数学函数的正确性、偏差及性能表现。
 */
class org.flashNight.naki.Normalization.NormalizationUtilTest
{
    /**
     * 构造函数
     * 在实例化时自动运行所有测试。
     */
    public function NormalizationUtilTest()
    {
        this.run();
    }

    /**
     * 简单的断言方法
     * 比较期望值与实际值，不相等时输出错误信息。
     * @param expected 期望值
     * @param actual 实际值
     * @param message 断言描述
     */
    private function assertEqual(expected:Number, actual:Number, message:String):Void
    {
        if (isNaN(expected) && isNaN(actual)) {
            trace("Assertion Passed: " + message + " (Both are NaN)");
            return;
        }

        if (expected !== actual)
        {
            trace("Assertion Failed: " + message + " | Expected: " + expected + ", Actual: " + actual);
        }
        else
        {
            trace("Assertion Passed: " + message);
        }
    }

    /**
     * 断言方法，允许浮点数在一定容差范围内相等
     * @param expected 期望值
     * @param actual 实际值
     * @param message 断言描述
     * @param epsilon 容差范围，默认为1e-10
     */
    private function assertAlmostEqual(expected:Number, actual:Number, message:String, epsilon:Number):Void
    {
        if (epsilon == undefined) {
            epsilon = 1e-10;
        }

        if (isNaN(expected) && isNaN(actual)) {
            trace("Assertion Passed: " + message + " (Both are NaN)");
            return;
        }

        if (Math.abs(expected - actual) > epsilon)
        {
            trace("Assertion Failed: " + message + " | Expected: " + expected + ", Actual: " + actual);
        }
        else
        {
            trace("Assertion Passed: " + message);
        }
    }

    /**
     * 运行所有测试
     */
    public function run():Void
    {
        this.runAssertions();
        this.runDeviationTest();
        this.runPerformanceTest();
    }

    /**
     * 部分1：正确性测试
     * 通过断言验证每个方法的输出是否符合预期。
     */
    private function runAssertions():Void
    {
        trace("\n=== Running Correctness Assertions ===");

        // 测试 sigmoid 函数
        this.assertEqual(0.5, NormalizationUtil.sigmoid(0), "sigmoid(0) should be 0.5");
        this.assertEqual(Math.exp(1)/(1 + Math.exp(1)), NormalizationUtil.sigmoid(1), "sigmoid(1)");
        this.assertEqual(Math.exp(-1)/(1 + Math.exp(-1)), NormalizationUtil.sigmoid(-1), "sigmoid(-1)");

        // 测试 ReLU 函数
        this.assertEqual(1, NormalizationUtil.relu(1), "relu(1) should be 1");
        this.assertEqual(0, NormalizationUtil.relu(-1), "relu(-1) should be 0");
        this.assertEqual(0, NormalizationUtil.relu(0), "relu(0) should be 0");

        // 测试 Leaky ReLU 函数
        this.assertEqual(1, NormalizationUtil.leakyRelu(1, 0.01), "leakyRelu(1,0.01) should be 1");
        this.assertEqual(-0.01, NormalizationUtil.leakyRelu(-1, 0.01), "leakyRelu(-1,0.01) should be -0.01");
        this.assertEqual(0, NormalizationUtil.leakyRelu(0, 0.01), "leakyRelu(0,0.01) should be 0");

        // 测试 softplus 函数
        this.assertAlmostEqual(Math.log(2), NormalizationUtil.softplus(0), "softplus(0) should be ln(2)");
        this.assertAlmostEqual(Math.log(1 + Math.exp(1)), NormalizationUtil.softplus(1), "softplus(1)");
        this.assertAlmostEqual(Math.log(1 + Math.exp(-1)), NormalizationUtil.softplus(-1), "softplus(-1)");

        // 测试 sig_tyler 函数
        this.assertEqual(0.5, NormalizationUtil.sig_tyler(0), "sig_tyler(0) should be 0.5");
        this.assertEqual(3*10/40 + 0.5 - (10*10*10)/4000, NormalizationUtil.sig_tyler(10), "sig_tyler(10)");
        this.assertEqual(3*(-10)/40 + 0.5 - ((-10)*(-10)*(-10))/4000, NormalizationUtil.sig_tyler(-10), "sig_tyler(-10)");

        // 测试 tanh 函数
        this.assertAlmostEqual(0, NormalizationUtil.tanh(0), "tanh(0) should be 0");
        this.assertAlmostEqual((Math.exp(1) - Math.exp(-1))/(Math.exp(1) + Math.exp(-1)), NormalizationUtil.tanh(1), "tanh(1)");
        this.assertAlmostEqual((Math.exp(-1) - Math.exp(1))/(Math.exp(-1) + Math.exp(1)), NormalizationUtil.tanh(-1), "tanh(-1)");

        // 测试 minMaxNormalize 函数
        this.assertAlmostEqual(0.5, NormalizationUtil.minMaxNormalize(5, 0, 10, 0, 1), "minMaxNormalize(5,0,10,0,1) should be 0.5");
        this.assertAlmostEqual(-1, NormalizationUtil.minMaxNormalize(0, 0, 10, -1, 1), "minMaxNormalize(0,0,10,-1,1) should be -1");
        this.assertAlmostEqual(1, NormalizationUtil.minMaxNormalize(10, 0, 10, -1, 1), "minMaxNormalize(10,0,10,-1,1) should be 1");

        // 测试 zScoreNormalize 函数
        this.assertAlmostEqual(2.5, NormalizationUtil.zScoreNormalize(10, 5, 2), "zScoreNormalize(10,5,2) should be 2.5");
        this.assertAlmostEqual(0, NormalizationUtil.zScoreNormalize(5, 5, 2), "zScoreNormalize(5,5,2) should be 0");
        this.assertAlmostEqual(-1, NormalizationUtil.zScoreNormalize(3, 5, 2), "zScoreNormalize(3,5,2) should be -1");

        // 测试 clamp 函数
        this.assertEqual(5, NormalizationUtil.clamp(5, 0, 10), "clamp(5,0,10) should be 5");
        this.assertEqual(0, NormalizationUtil.clamp(-5, 0, 10), "clamp(-5,0,10) should be 0");
        this.assertEqual(10, NormalizationUtil.clamp(15, 0, 10), "clamp(15,0,10) should be 10");

        // 测试 softmax 函数
        var softmaxInput:Array = [1, 2, 3];
        var softmaxOutput:Array = NormalizationUtil.softmax(softmaxInput);
        var expectedSoftmax:Array = [Math.exp(1 - 3), Math.exp(2 - 3), Math.exp(3 - 3)];
        var sumExp:Number = expectedSoftmax[0] + expectedSoftmax[1] + expectedSoftmax[2];
        expectedSoftmax = [expectedSoftmax[0]/sumExp, expectedSoftmax[1]/sumExp, expectedSoftmax[2]/sumExp];
        for (var j:Number = 0; j < softmaxOutput.length; j++)
        {
            this.assertAlmostEqual(expectedSoftmax[j], softmaxOutput[j], "softmax([1,2,3]) element " + j, 1e-10);
        }

        // 测试 normalizeVector 函数
        var normalizeInput:Array = [3, 4];
        var normalizeOutput:Array = NormalizationUtil.normalizeVector(normalizeInput);
        this.assertAlmostEqual(3/5, normalizeOutput[0], "normalizeVector([3,4]) first element should be 0.6", 1e-10);
        this.assertAlmostEqual(4/5, normalizeOutput[1], "normalizeVector([3,4]) second element should be 0.8", 1e-10);

        // 测试 linearScale 函数
        this.assertAlmostEqual(0, NormalizationUtil.linearScale(5, 5, 5, 0, 10), "linearScale with originalMin == originalMax should return targetMin");
        this.assertAlmostEqual(5, NormalizationUtil.linearScale(15, 10, 20, 0, 1), "linearScale(15,10,20,0,1) should be 0.5");
        this.assertAlmostEqual(1, NormalizationUtil.linearScale(20, 10, 20, 0, 1), "linearScale(20,10,20,0,1) should be 1");

        // 测试 exponentialScale 函数
        this.assertAlmostEqual(1, NormalizationUtil.exponentialScale(0, 2, 0, 1), "exponentialScale(0,2,0,1) should be 1");
        this.assertAlmostEqual(2, NormalizationUtil.exponentialScale(1, 2, 0, 2), "exponentialScale(1,2,0,2) should be 2");
        this.assertAlmostEqual(4, NormalizationUtil.exponentialScale(2, 2, 0, 4), "exponentialScale(2,2,0,4) should be 4");
    }

    /**
     * 部分2：偏差测试
     * 以 sigmoid 函数为基准，输出 flt 函数的偏差情况。
     */
    private function runDeviationTest():Void
    {
        trace("\n=== Running Deviation Test ===");
        var testValues:Array = [-10, -5, -1, -0.5, 0, 0.5, 1, 5, 10];
        for (var i:Number = 0; i < testValues.length; i++)
        {
            var x:Number = testValues[i];
            var sigmoidVal:Number = NormalizationUtil.sigmoid(x);
            var fltVal:Number = NormalizationUtil.flt(x);
            var deviation:Number = Math.abs(sigmoidVal - fltVal);
            trace("x: " + x + ", sigmoid(x): " + sigmoidVal + ", flt(x): " + fltVal + ", deviation: " + deviation);
        }
    }

    /**
     * 部分3：性能评估
     * 测试各个方法在大量调用下的执行时间。
     */
    private function runPerformanceTest():Void
    {
        trace("\n=== Running Performance Test ===");
        var iterations:Number = 10000;
        var testValues:Array = [0, 1, -1, 1.5, -1.5, 1000000, -1000000, 1.79769313486231e+308, -1.79769313486231e+308, 4.94065645841247e-324, -4.94065645841247e-324, Infinity, -Infinity, NaN];

        for (var i:Number = 0; i < testValues.length; i++)
        {
            var x:Number = testValues[i];
            
            // 测试 flt 函数
            var startTime:Number = getTimer();
            var fltVal:Number;
            for (var j:Number = 0; j < iterations; j++)
            {
                fltVal = NormalizationUtil.flt(x);
            }
            var fltTime:Number = getTimer() - startTime;
            
            // 测试 sigmoid 函数
            startTime = getTimer();
            var sigmoidVal:Number;
            for (j = 0; j < iterations; j++)
            {
                sigmoidVal = NormalizationUtil.sigmoid(x);
            }
            var sigmoidTime:Number = getTimer() - startTime;
            
            // 测试 ReLU 函数
            startTime = getTimer();
            var reluVal:Number;
            for (j = 0; j < iterations; j++)
            {
                reluVal = NormalizationUtil.relu(x);
            }
            var reluTime:Number = getTimer() - startTime;
            
            // 测试 Leaky ReLU 函数
            startTime = getTimer();
            var leakyReLuVal:Number;
            for (j = 0; j < iterations; j++)
            {
                leakyReLuVal = NormalizationUtil.leakyRelu(x, 0.01);
            }
            var leakyReLuTime:Number = getTimer() - startTime;
            
            // 测试 softplus 函数
            startTime = getTimer();
            var softplusVal:Number;
            for (j = 0; j < iterations; j++)
            {
                softplusVal = NormalizationUtil.softplus(x);
            }
            var softplusTime:Number = getTimer() - startTime;
            
            // 测试 sig_tyler 函数
            startTime = getTimer();
            var sigTylerVal:Number;
            for (j = 0; j < iterations; j++)
            {
                sigTylerVal = NormalizationUtil.sig_tyler(x);
            }
            var sigTylerTime:Number = getTimer() - startTime;
            
            // 测试 tanh 函数
            startTime = getTimer();
            var tanhVal:Number;
            for (j = 0; j < iterations; j++)
            {
                tanhVal = NormalizationUtil.tanh(x);
            }
            var tanhTime:Number = getTimer() - startTime;
            
            // 测试 minMaxNormalize 函数
            startTime = getTimer();
            var minMaxNormVal:Number;
            for (j = 0; j < iterations; j++)
            {
                minMaxNormVal = NormalizationUtil.minMaxNormalize(x, -10, 10, 0, 1);
            }
            var minMaxNormTime:Number = getTimer() - startTime;
            
            // 测试 zScoreNormalize 函数
            startTime = getTimer();
            var zScoreNormVal:Number;
            for (j = 0; j < iterations; j++)
            {
                zScoreNormVal = NormalizationUtil.zScoreNormalize(x, 0, 1);
            }
            var zScoreNormTime:Number = getTimer() - startTime;
            
            // 测试 clamp 函数
            startTime = getTimer();
            var clampVal:Number;
            for (j = 0; j < iterations; j++)
            {
                clampVal = NormalizationUtil.clamp(x, -5, 5);
            }
            var clampTime:Number = getTimer() - startTime;
            
            // 测试 softmax 函数
            // 由于 softmax 接受数组，需要定义一个固定数组
            var softmaxInput:Array = [1, 2, 3];
            startTime = getTimer();
            var softmaxOutput:Array;
            for (j = 0; j < iterations; j++)
            {
                softmaxOutput = NormalizationUtil.softmax(softmaxInput);
            }
            var softmaxTime:Number = getTimer() - startTime;
            
            // 测试 normalizeVector 函数
            // 由于 normalizeVector 接受数组，需要定义一个固定数组
            var vectorInput:Array = [3, 4];
            startTime = getTimer();
            var normalizeVectorOutput:Array;
            for (j = 0; j < iterations; j++)
            {
                normalizeVectorOutput = NormalizationUtil.normalizeVector(vectorInput);
            }
            var normalizeVectorTime:Number = getTimer() - startTime;
            
            // 测试 linearScale 函数
            startTime = getTimer();
            var linearScaleVal:Number;
            for (j = 0; j < iterations; j++)
            {
                linearScaleVal = NormalizationUtil.linearScale(x, -10, 10, 0, 1);
            }
            var linearScaleTime:Number = getTimer() - startTime;
            
            // 测试 exponentialScale 函数
            startTime = getTimer();
            var exponentialScaleVal:Number;
            for (j = 0; j < iterations; j++)
            {
                exponentialScaleVal = NormalizationUtil.exponentialScale(x, 2, 0, 1);
            }
            var exponentialScaleTime:Number = getTimer() - startTime;
            
            // 输出性能结果
            trace("x: " + x + 
                  ", flt Time: " + fltTime + "ms" + 
                  ", sigmoid Time: " + sigmoidTime + "ms" + 
                  ", relu Time: " + reluTime + "ms" + 
                  ", leakyRelu Time: " + leakyReLuTime + "ms" + 
                  ", softplus Time: " + softplusTime + "ms" + 
                  ", sig_tyler Time: " + sigTylerTime + "ms" + 
                  ", tanh Time: " + tanhTime + "ms" + 
                  ", minMaxNormalize Time: " + minMaxNormTime + "ms" + 
                  ", zScoreNormalize Time: " + zScoreNormTime + "ms" + 
                  ", clamp Time: " + clampTime + "ms" + 
                  ", softmax Time: " + softmaxTime + "ms" + 
                  ", normalizeVector Time: " + normalizeVectorTime + "ms" + 
                  ", linearScale Time: " + linearScaleTime + "ms" + 
                  ", exponentialScale Time: " + exponentialScaleTime + "ms");
        }
    }
}
