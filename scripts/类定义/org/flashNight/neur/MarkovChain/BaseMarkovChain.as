import org.flashNight.naki.DataStructures.*;

/**
 * 基础马尔科夫链类
 * 该类实现了一个基本的马尔科夫链，用于模拟状态转移过程。马尔科夫链通过一个状态转移矩阵和一个状态向量来表示，
 * 并且可以应用于多种场景，如天气系统、AI决策等。
 */
class org.flashNight.neur.MarkovChain.BaseMarkovChain {
    private var transitionMatrix:AdvancedMatrix; // 状态转移概率矩阵
    private var stateVector:AdvancedMatrix; // 当前状态向量
    private var convergenceThreshold:Number; // 判断收敛的阈值

    /**
     * 构造函数
     * 
     * @param initialTransitionMatrix 初始状态转移矩阵，定义各状态之间的转移概率
     * @param initialStateVector 初始状态向量，表示系统当前的状态
     * @param threshold 收敛阈值，用于判断状态向量是否稳定
     * 
     * 此构造函数初始化马尔科夫链的状态转移矩阵和状态向量，threshold 用于控制判断系统是否达到稳定状态（即不再发生明显变化）。
     */
    public function BaseMarkovChain(initialTransitionMatrix:AdvancedMatrix, initialStateVector:AdvancedMatrix, threshold:Number) {
        this.transitionMatrix = initialTransitionMatrix;
        this.stateVector = initialStateVector;
        this.convergenceThreshold = threshold;
    }

    /**
     * 行归一化方法
     * 
     * 直接调用 `AdvancedMatrix` 中的 `normalizeRows` 方法来归一化状态转移矩阵。
     */
    public function normalizeRows():Void {
        this.transitionMatrix = this.transitionMatrix.normalizeRows();
    }

    /**
     * 更新状态向量方法
     * 
     * 该方法根据状态转移矩阵，计算当前状态向量的下一步状态。
     * 直接使用 `AdvancedMatrix` 类中的 `multiply` 方法进行状态更新。
     */
    public function updateState():Void {
        this.stateVector = this.stateVector.multiply(this.transitionMatrix);
    }

    /**
     * 判断马尔科夫链是否收敛
     * 
     * @param previousStateVector 前一步的状态向量，用于比较当前状态
     * @return Boolean 如果当前状态向量和前一步的状态向量之间的差异小于阈值，则返回true，表示已收敛
     * 
     * 此方法用于判断马尔科夫链的状态向量是否达到稳定（收敛）。通过比较当前状态向量与前一状态向量的差异，判断是否
     * 达到设定的阈值。这里直接使用 `AdvancedMatrix` 中的 `hasConverged` 方法。
     */
    public function hasConverged(previousStateVector:AdvancedMatrix):Boolean {
        return this.stateVector.hasConverged(previousStateVector, this.convergenceThreshold);
    }

    /**
     * 获取当前状态向量
     * 
     * @return AdvancedMatrix 返回当前状态向量，表示系统的当前状态分布
     */
    public function getStateVector():AdvancedMatrix {
        return this.stateVector;
    }

    /**
     * 获取状态转移矩阵
     * 
     * @return AdvancedMatrix 返回当前的状态转移矩阵，用于查看各状态之间的转移概率
     */
    public function getTransitionMatrix():AdvancedMatrix {
        return this.transitionMatrix;
    }

    /**
     * 设置新的状态转移矩阵
     * 
     * @param newTransitionMatrix 新的状态转移矩阵，用于更新系统的状态转移规则
     * 
     * 此方法允许用户动态更改马尔科夫链的状态转移矩阵，适用于在系统运行过程中需要调整转移概率的场景。
     */
    public function setTransitionMatrix(newTransitionMatrix:AdvancedMatrix):Void {
        this.transitionMatrix = newTransitionMatrix;
    }
}
