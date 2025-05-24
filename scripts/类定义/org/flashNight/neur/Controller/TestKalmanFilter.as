import org.flashNight.naki.DataStructures.AdvancedMatrix;
import org.flashNight.neur.Controller.KalmanFilter;

class org.flashNight.neur.Controller.TestKalmanFilter {
    private var kf:org.flashNight.neur.Controller.KalmanFilter;
    public var A:AdvancedMatrix;
    public var H:AdvancedMatrix;
    public var Q:AdvancedMatrix;
    public var R:AdvancedMatrix;
    public var B:AdvancedMatrix;
    public var initialState:AdvancedMatrix;

    public function TestKalmanFilter() {
        // 初始化 KalmanFilter 实例
        A = new AdvancedMatrix([1, 0, 0, 1]).init(2, 2); // 状态转移矩阵
        H = new AdvancedMatrix([1, 0, 0, 1]).init(2, 2); // 测量矩阵
        Q = new AdvancedMatrix([0.1, 0, 0, 0.1]).init(2, 2); // 过程噪声协方差
        R = new AdvancedMatrix([1, 0, 0, 1]).init(2, 2); // 测量噪声协方差
        B = new AdvancedMatrix([0, 0]).init(2, 1); // 控制输入矩阵（2x1）
        initialState = new AdvancedMatrix([0, 0]).init(2, 1); // 初始状态估计

        kf = new KalmanFilter(A, H, Q, R, B, initialState, new AdvancedMatrix([1, 0, 0, 1]).init(2, 2));
    }

    public function runTests():Void {
        trace("Running KalmanFilter Tests...");
        testPredictionStep();
        testUpdateStep();
        testFullFilteringProcess();
        testBoundaryConditions();
        testPerformance();
    }

    private function testPredictionStep():Void {
        trace("Testing prediction step...");

        var initial_state:AdvancedMatrix = kf.getStateEstimate().clone();
        var initial_covariance:AdvancedMatrix = kf.getCovarianceEstimate().clone();

        var control_input:AdvancedMatrix = new AdvancedMatrix([0]).init(1, 1); // 控制输入（1x1）
        kf.predict(control_input);

        var expected_state:AdvancedMatrix = A.multiply(initial_state).add(B.multiply(control_input));
        var expected_covariance:AdvancedMatrix = A.multiply(initial_covariance.multiply(A.transpose())).add(Q);

        assertMatrixEqual(kf.getStateEstimate(), expected_state, "State prediction");
        assertMatrixEqual(kf.getCovarianceEstimate(), expected_covariance, "Covariance prediction");
    }

    private function testUpdateStep():Void {
        trace("Testing update step...");

        var predicted_state:AdvancedMatrix = new AdvancedMatrix([1, 1]).init(2, 1);
        var predicted_covariance:AdvancedMatrix = new AdvancedMatrix([1, 0, 0, 1]).init(2, 2);
        kf.setStateEstimate(predicted_state.clone());
        kf.setCovarianceEstimate(predicted_covariance.clone());

        var measurement:AdvancedMatrix = new AdvancedMatrix([1.1, 0.9]).init(2, 1);
        kf.update(measurement);

        var K:AdvancedMatrix = predicted_covariance.multiply(H.transpose()).multiply((H.multiply(predicted_covariance.multiply(H.transpose())).add(R)).inverse());
        var expected_state:AdvancedMatrix = predicted_state.add(K.multiply(measurement.subtract(H.multiply(predicted_state))));
        var expected_covariance:AdvancedMatrix = createIdentityMatrix(2).subtract(K.multiply(H)).multiply(predicted_covariance);

        assertMatrixEqual(kf.getStateEstimate(), expected_state, "State update");
        assertMatrixEqual(kf.getCovarianceEstimate(), expected_covariance, "Covariance update");
    }

    private function testFullFilteringProcess():Void {
        trace("Testing full filtering process...");

        resetKalmanFilter();

        var control_input:AdvancedMatrix = new AdvancedMatrix([0]).init(1, 1); // 控制输入（1x1）
        var measurement1:AdvancedMatrix = new AdvancedMatrix([1, 1]).init(2, 1); // 第一次测量值
        var measurement2:AdvancedMatrix = new AdvancedMatrix([1.1, 0.9]).init(2, 1); // 第二次测量值

        // 第一次预测和更新
        kf.predict(control_input);
        kf.update(measurement1);

        // 第二次预测和更新
        kf.predict(control_input);
        kf.update(measurement2);

        // 期望的状态估计
        var expected_state:AdvancedMatrix = new AdvancedMatrix([0.75, 0.67]).init(2, 1);
        assertMatrixAlmostEqual(kf.getStateEstimate(), expected_state, 0.01, "Full filtering process - state");
    }

    private function testBoundaryConditions():Void {
        trace("Testing boundary conditions...");

        var measurement:AdvancedMatrix = new AdvancedMatrix([1, 1]).init(2, 1);
        var control_input:AdvancedMatrix = new AdvancedMatrix([0]).init(1, 1);

        var singular_H:AdvancedMatrix = new AdvancedMatrix([1, 0, 0, 0]).init(2, 2);
        var singular_kf:KalmanFilter = new KalmanFilter(A, singular_H, Q, R, B, initialState, new AdvancedMatrix([1, 0, 0, 1]).init(2, 2));

        singular_kf.predict(control_input);
        try {
            singular_kf.update(measurement);
            trace("[PASS] Singular H matrix handled without error");
        } catch (e:Error) {
            trace("[FAIL] Singular H matrix caused error: " + e.message);
        }
    }

    private function testPerformance():Void {
        trace("Testing performance...");

        var iterations:Number = 1000;
        var startTime:Number = getTimer();

        for (var i:Number = 0; i < iterations; i++) {
            kf.predict(new AdvancedMatrix([0]).init(1, 1));
            kf.update(new AdvancedMatrix([1, 1]).init(2, 1));
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;

        trace("Performance Test Duration: " + duration + "ms for " + iterations + " iterations.");
        assertTrue(duration < 500, "Performance benchmark < 500ms");
    }

    private function resetKalmanFilter():Void {
        kf.setStateEstimate(initialState.clone());
        // 将协方差初始化为单位矩阵，而不是 0 矩阵
        kf.setCovarianceEstimate(new AdvancedMatrix([1, 0, 0, 1]).init(2, 2));
    }


    private function matricesEqual(a:AdvancedMatrix, b:AdvancedMatrix):Boolean {
        if (a.getRows() != b.getRows() || a.getCols() != b.getCols()) {
            return false;
        }
        for (var i:Number = 0; i < a.getRows(); i++) {
            for (var j:Number = 0; j < a.getCols(); j++) {
                if (a.getElement(i, j) != b.getElement(i, j)) {
                    return false;
                }
            }
        }
        return true;
    }

    private function matricesAlmostEqual(a:AdvancedMatrix, b:AdvancedMatrix, epsilon:Number):Boolean {
        if (a.getRows() != b.getRows() || a.getCols() != b.getCols()) {
            return false;
        }
        for (var i:Number = 0; i < a.getRows(); i++) {
            for (var j:Number = 0; j < a.getCols(); j++) {
                if (Math.abs(a.getElement(i, j) - b.getElement(i, j)) > epsilon) {
                    return false;
                }
            }
        }
        return true;
    }

    private function createIdentityMatrix(size:Number):AdvancedMatrix {
        // 创建一个一维数组来存储单位矩阵的数据
        var identityData:Array = [];
        for (var i:Number = 0; i < size; i++) {
            for (var j:Number = 0; j < size; j++) {
                // 对角线元素为 1，其余为 0
                identityData.push(i == j ? 1 : 0);
            }
        }
        // 使用 AdvancedMatrix 的构造函数创建矩阵，并初始化行数和列数
        var I:AdvancedMatrix = new AdvancedMatrix(identityData);
        I.init(size, size); // 初始化矩阵的行数和列数
        return I;
    }

    private function assertMatrixEqual(actual:AdvancedMatrix, expected:AdvancedMatrix, message:String):Void {
        if (!matricesEqual(actual, expected)) {
            trace("[FAIL] " + message + " | Expected: " + expected.toString() + ", Actual: " + actual.toString());
        } else {
            trace("[PASS] " + message);
        }
    }

    private function assertMatrixAlmostEqual(actual:AdvancedMatrix, expected:AdvancedMatrix, epsilon:Number, message:String):Void {
        if (!matricesAlmostEqual(actual, expected, epsilon)) {
            trace("[FAIL] " + message + " | Expected: " + expected.toString() + ", Actual: " + actual.toString());
        } else {
            trace("[PASS] " + message);
        }
    }

    private function assertTrue(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("[FAIL] " + message);
        } else {
            trace("[PASS] " + message);
        }
    }
}