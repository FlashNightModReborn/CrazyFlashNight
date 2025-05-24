import org.flashNight.neur.Controller.SimpleKalmanFilter1D;

class org.flashNight.neur.Controller.TestSimpleKalmanFilter1D {
    private var kf:org.flashNight.neur.Controller.SimpleKalmanFilter1D;

    public function TestSimpleKalmanFilter1D() {
        // 初始化 SimpleKalmanFilter1D 实例
        // 假设初始帧率为30 FPS，过程噪声Q=0.1，测量噪声R=2
        kf = new SimpleKalmanFilter1D(30, 0.1, 2);
    }

    /**
     * 运行所有测试
     */
    public function runTests():Void {
        trace("Running SimpleKalmanFilter1D Tests...");
        testInitialState();
        testPredictionStep();
        testUpdateStep();
        testFullFilteringProcess();
        testBoundaryConditions();
        testPerformance();
    }

    /**
     * 测试初始状态
     */
    private function testInitialState():Void {
        trace("Testing initial state...");

        var expectedEstimate:Number = 30;
        var expectedErrorCov:Number = 1;

        assertAlmostEqual(kf.getEstimate(), expectedEstimate, 0.0001, "Initial state estimate");
        assertAlmostEqual(kf.getErrorCov(), expectedErrorCov, 0.0001, "Initial error covariance");
    }

    /**
     * 测试预测步骤
     */
    private function testPredictionStep():Void {
        trace("Testing prediction step...");

        // 记录当前状态
        var initialEstimate:Number = kf.getEstimate();
        var initialErrorCov:Number = kf.getErrorCov();

        // 执行预测步骤
        var predictedEstimate:Number = kf.predict();

        // 预测后的协方差
        var predictedErrorCov:Number = initialErrorCov + kf.getProcessNoise();

        // 检查预测后的状态和协方差
        assertAlmostEqual(predictedEstimate, initialEstimate, 0.0001, "Predict step - estimate remains unchanged");
        assertAlmostEqual(predictedErrorCov, kf.getErrorCov(), 0.0001, "Predict step - error covariance");
    }

    /**
     * 测试更新步骤
     */
    private function testUpdateStep():Void {
        trace("Testing update step...");

        // 设定一个已知的状态和协方差
        kf.reset(30, 1);

        // 执行预测
        var predictedEstimate:Number = kf.predict(); // 应保持为30
        var predictedErrorCov:Number = 1 + kf.getProcessNoise(); // 1 + 0.1 =1.1

        // 测量值
        var measuredValue:Number = 32;

        // 计算预期的卡尔曼增益
        var kalmanGain:Number = predictedErrorCov / (predictedErrorCov + kf.getMeasurementNoise()); // 1.1 / 3.1 ≈ 0.35483871

        // 计算预期的估计值和误差协方差
        var expectedEstimate:Number = 30 + kalmanGain * (32 - 30); // 30 + 0.35483871 * 2 ≈30.7096774
        var expectedErrorCov:Number = (1 - kalmanGain) * predictedErrorCov; // (1 - 0.35483871) *1.1 ≈0.7333333

        // 执行更新
        var updatedEstimate:Number = kf.update(measuredValue);

        // 检查更新后的状态和协方差
        assertAlmostEqual(updatedEstimate, expectedEstimate, 0.0001, "Update step - estimate");
        assertAlmostEqual(kf.getErrorCov(), expectedErrorCov, 0.0001, "Update step - error covariance");
    }

    /**
     * 测试完整的滤波过程
     */
    private function testFullFilteringProcess():Void {
        trace("Testing full filtering process...");

        // 重置滤波器
        kf.reset(30, 1);

        // 第一次预测与更新
        var predictedEstimate1:Number = kf.predict(); // 30
        var predictedErrorCov1:Number = 1 + kf.getProcessNoise(); // 1 + 0.1 =1.1

        var measurement1:Number = 32;
        var K1:Number = predictedErrorCov1 / (predictedErrorCov1 + kf.getMeasurementNoise()); // 1.1 /3.1 ≈0.35483871
        var expectedEstimate1:Number = 30 + K1 * (32 - 30); // 30 +0.35483871 *2 ≈30.7096774
        var expectedErrorCov1:Number = (1 - K1) * predictedErrorCov1; // (1 -0.35483871)*1.1≈0.7333333

        var estimate1:Number = kf.update(measurement1);

        // 检查第一次更新
        assertAlmostEqual(estimate1, expectedEstimate1, 0.0001, "Full process - first update - estimate");
        assertAlmostEqual(kf.getErrorCov(), expectedErrorCov1, 0.0001, "Full process - first update - error covariance");

        // 第二次预测与更新
        var predictedEstimate2:Number = kf.predict(); // 30.7096774
        var predictedErrorCov2:Number = kf.getErrorCov() + kf.getProcessNoise(); //0.7333333 +0.1=0.8333333

        var measurement2:Number = 31;
        var K2:Number = predictedErrorCov2 / (predictedErrorCov2 + kf.getMeasurementNoise()); //0.8333333 /2.8333333≈0.2941176
        var expectedEstimate2:Number = 30.7096774 + K2 * (31 - 30.7096774); //≈30.7096774 + 0.2941176 * 0.2903226 ≈30.7947837
        var expectedErrorCov2:Number = (1 - K2) * predictedErrorCov2; //≈(1 -0.2941176) *0.8333333≈0.5882353

        var estimate2:Number = kf.update(measurement2);

        // 检查第二次更新
        assertAlmostEqual(estimate2, expectedEstimate2, 0.1, "Full process - second update - estimate");
        assertAlmostEqual(kf.getErrorCov(), expectedErrorCov2, 0.1, "Full process - second update - error covariance");
    }

    /**
     * 测试边界条件
     */
    private function testBoundaryConditions():Void {
        trace("Testing boundary conditions...");

        // 测试异常输入
        try {
            kf.update(NaN);
            trace("[FAIL] Update with NaN measurement should throw error");
        } catch (e:Error) {
            trace("[PASS] Update with NaN measurement threw error: " + e.message);
        }

        try {
            kf.reset(NaN, 1);
            trace("[FAIL] Reset with NaN initial estimate should throw error");
        } catch (e:Error) {
            trace("[PASS] Reset with NaN initial estimate threw error: " + e.message);
        }

        try {
            kf.reset(30, -1); // 无效的协方差
            trace("[FAIL] Reset with negative error covariance should throw error");
        } catch (e:Error) {
            trace("[PASS] Reset with negative error covariance threw error: " + e.message);
        }
    }

    /**
     * 测试性能
     */
    private function testPerformance():Void {
        trace("Testing performance...");

        var iterations:Number = 100000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            // 假设每次测量值略有波动
            var measuredFPS:Number = 30 + Math.random() * 2 - 1; // 29 ~ 31
            kf.predict();
            kf.update(measuredFPS);
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;

        trace("Performance Test Duration: " + duration + "ms for " + iterations + " iterations.");
        assertTrue(duration < 5000, "Performance benchmark < 5000ms"); // 根据环境调整阈值
    }

    /**
     * 断言两个数值几乎相等
     */
    private function assertAlmostEqual(actual:Number, expected:Number, epsilon:Number, message:String):Void {
        if (Math.abs(actual - expected) > epsilon) {
            trace("[FAIL] " + message + " | Expected: " + expected + ", Actual: " + actual);
        } else {
            trace("[PASS] " + message);
        }
    }

    /**
     * 断言条件为真
     */
    private function assertTrue(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("[FAIL] " + message);
        } else {
            trace("[PASS] " + message);
        }
    }
}
