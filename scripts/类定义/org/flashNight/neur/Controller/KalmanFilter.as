import org.flashNight.naki.DataStructures.*;

class org.flashNight.neur.Controller.KalmanFilter {
    private var state_estimate:AdvancedMatrix; // 状态向量
    private var covariance_estimate:AdvancedMatrix; // 协方差矩阵
    private var A:AdvancedMatrix; // 状态转移矩阵
    private var H:AdvancedMatrix; // 测量矩阵
    private var Q:AdvancedMatrix; // 过程噪声协方差矩阵
    private var R:AdvancedMatrix; // 测量噪声协方差矩阵
    private var B:AdvancedMatrix; // 控制输入矩阵（可选）
    private var control_input:AdvancedMatrix; // 控制输入向量（可选）

    /**
     * 构造函数，初始化卡尔曼滤波器。
     *
     * @param A 状态转移矩阵
     * @param H 测量矩阵
     * @param Q 过程噪声协方差矩阵
     * @param R 测量噪声协方差矩阵
     * @param B 控制输入矩阵（可选）
     * @param initialState 初始状态估计
     * @param initialCovariance 初始协方差矩阵（可选，默认为单位矩阵）
     */
    public function KalmanFilter(
        A:AdvancedMatrix,
        H:AdvancedMatrix,
        Q:AdvancedMatrix,
        R:AdvancedMatrix,
        B:AdvancedMatrix,
        initialState:AdvancedMatrix,
        initialCovariance:AdvancedMatrix
    ) {
        // 初始化矩阵
        this.A = A;
        this.H = H;
        this.Q = Q;
        this.R = R;
        this.B = B;
        this.state_estimate = initialState.clone();

        // 如果未提供初始协方差矩阵，则使用单位矩阵
        if (initialCovariance == null) {
            var size:Number = initialState.getRows();
            this.covariance_estimate = new AdvancedMatrix(createIdentityData(size)).init(size, size);
        } else {
            this.covariance_estimate = initialCovariance.clone();
        }
    }

    /**
     * 获取当前状态估计。
     *
     * @return 当前状态估计的副本
     */
    public function getStateEstimate():AdvancedMatrix {
        return this.state_estimate.clone();
    }

    /**
     * 设置新的状态估计。
     *
     * @param newState 新的状态估计
     * @throws Error 如果新状态的维度不匹配
     */
    public function setStateEstimate(newState:AdvancedMatrix):Void {
        if (newState.getRows() != this.state_estimate.getRows() || newState.getCols() != this.state_estimate.getCols()) {
            throw new Error("状态估计的维度不匹配。");
        }
        this.state_estimate = newState.clone();
    }

    /**
     * 获取当前协方差估计。
     *
     * @return 当前协方差估计的副本
     */
    public function getCovarianceEstimate():AdvancedMatrix {
        return this.covariance_estimate.clone();
    }

    /**
     * 设置新的协方差估计。
     *
     * @param newCovariance 新的协方差估计
     * @throws Error 如果新协方差的维度不匹配
     */
    public function setCovarianceEstimate(newCovariance:AdvancedMatrix):Void {
        if (newCovariance.getRows() != this.covariance_estimate.getRows() || newCovariance.getCols() != this.covariance_estimate.getCols()) {
            throw new Error("协方差估计的维度不匹配。");
        }
        this.covariance_estimate = newCovariance.clone();
    }

    /**
     * 预测步骤：根据当前状态和控制输入预测下一状态。
     *
     * @param control_input 控制输入向量
     * @return 预测的状态
     * @throws Error 如果控制输入或控制矩阵未定义
     */
    public function predict(control_input:AdvancedMatrix):AdvancedMatrix {
        if (B == null || control_input == null) {
            throw new Error("控制输入或控制矩阵未定义。");
        }
        if (control_input.getRows() != B.getCols() || control_input.getCols() != 1) {
            throw new Error("控制输入的维度不匹配。期望: (" + B.getCols() + ", 1)，实际: (" + control_input.getRows() + ", " + control_input.getCols() + ")");
        }

        // 预测状态
        var state_predict:AdvancedMatrix = A.multiply(state_estimate).add(B.multiply(control_input));

        // 预测协方差
        var covariance_predict:AdvancedMatrix = A.multiply(covariance_estimate.multiply(A.transpose())).add(Q);

        // 更新状态和协方差
        this.state_estimate = state_predict;
        this.covariance_estimate = covariance_predict;

        return state_predict;
    }

    /**
     * 更新步骤：根据测量值更新状态估计。
     *
     * @param measurement 测量值
     * @return 更新后的状态
     * @throws Error 如果矩阵不可逆
     */
    public function update(measurement:AdvancedMatrix):AdvancedMatrix {
        // 计算卡尔曼增益
        var tempMatrix:AdvancedMatrix = H.multiply(covariance_estimate.multiply(H.transpose())).add(R);
        if (tempMatrix.determinant() == 0) {
            throw new Error("矩阵是奇异的，无法求逆。");
        }
        var K:AdvancedMatrix = covariance_estimate.multiply(H.transpose()).multiply(tempMatrix.inverse());

        // 计算新息
        var innovation:AdvancedMatrix = measurement.subtract(H.multiply(state_estimate));

        // 更新状态
        var state_update:AdvancedMatrix = state_estimate.add(K.multiply(innovation));

        // 更新协方差
        var identityMatrix:AdvancedMatrix = new AdvancedMatrix(createIdentityData(state_estimate.getRows())).init(state_estimate.getRows(), state_estimate.getRows());
        var covariance_update:AdvancedMatrix = identityMatrix.subtract(K.multiply(H)).multiply(covariance_estimate);

        // 更新状态和协方差
        this.state_estimate = state_update;
        this.covariance_estimate = covariance_update;

        return state_update;
    }

    /**
     * 辅助方法：生成单位矩阵的数据。
     *
     * @param size 矩阵的大小
     * @return 单位矩阵的数据（一维数组）
     */
    private function createIdentityData(size:Number):Array {
        var data:Array = [];
        for (var i:Number = 0; i < size; i++) {
            for (var j:Number = 0; j < size; j++) {
                data.push(i == j ? 1 : 0);
            }
        }
        return data;
    }
}