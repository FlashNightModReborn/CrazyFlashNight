import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/*
 * PinkNoiseEngine 粉红噪音生成器
 *
 * 设计理念：
 * -------------------------------
 * 该类基于线性同余生成器（LCG）生成的均匀随机数，通过多层叠加（分层法）产生粉红噪音。
 * 粉红噪音具有 1/f 的功率谱特性，即频域能量与频率成反比分布。
 *
 * 分层机制与能量补偿：
 * -------------------------------
 * 1. 分层结构：使用 5 层（numStages=5）的随机数，每一层更新周期为 2^i（i=0~4）。
 *    - 较低层（低频部分）更新频率低，承载长时程相关性；较高层（高频部分）更新频率高。
 * 2. 权重设计：采用公式 weights[i] = 1/(numStages - i + c) 给每层分配权重，
 *    其中平滑因子 c 经实验与数学推导（频域能量补偿分析、拉普拉斯变换等方法）确定为 8.54，
 *    使得各层噪声能量在频域内得到均衡补偿，最终合成的总噪音满足 1/f 特性。
 *
 * 性能优化：
 * -------------------------------
 * 1. 内联展开：将 for 循环及数组访问全部展开为静态成员变量（s0, s1, s2, s3, s4），
 *    减少数组索引和动态查找带来的额外开销。
 * 2. 固化参数：numStages 固定为 5，平滑因子 c 固定为 8.54，所有与分层相关的参数（更新周期、权重）
 *    均在编译时固化，确保运行时只进行必要的数值更新。
 * 3. 内联展开 super.nextFloat()：直接展开调用，减少函数调用开销。
 *
 * 单例模式：
 * -------------------------------
 * 该类采用单例模式，确保系统中只有一个粉红噪音生成器实例，从而避免静态变量索引开销。
 *
 * 数学与工程调参：
 * -------------------------------
 * - 理论上，通过能量补偿，理想粉红噪音 PSD 对数谱斜率应为 -1。
 * - 对应权重的选择和更新周期的设计保证各层在不同倍频程内能量均衡分布。
 * - 通过实验和离散傅里叶变换验证，固定参数 c=8.54 在 5 层结构下使得生成噪音的 PSD 斜率接近 -1，
 *   实现了理想粉红噪音的特性。
 *
 * 注意：
 * -------------------------------
 * 1. 由于 AS2 中静态变量开销较高，本实现尽量避免静态成员，将状态保存在成员变量中以提高性能。
 * 2. 所有的数值常量（如权重系数及归一化因子）均为预先计算好，确保每次调用 nextFloat() 时只进行最少量的计算。
 */

class org.flashNight.naki.RandomNumberEngine.PinkNoiseEngine extends LinearCongruentialEngine {
    // 单例实例（仅用于获取实例，不参与频繁访问计算）
    public static var instance:PinkNoiseEngine;

    // 分层状态：各层随机数值，采用成员变量而非数组以降低索引开销
    private var s0:Number, s1:Number, s2:Number, s3:Number, s4:Number;
    // 更新计数器，用于控制各层的更新频率
    private var counter:Number;

    // 私有构造函数，禁止外部直接实例化，保证单例模式
    private function PinkNoiseEngine() {
        super();
        reset();
    }

    /*
     * reset() 方法
     * -------------------------------
     * 用于初始化各层状态，直接内联展开 super.nextFloat() 调用以减少函数调用开销，
     * 同时更新种子（seed）并归一化到 [0,1) 区间。
     */
    private function reset():Void {
        s0 = (seed = (a * seed + c) % m) / m;
        s1 = (seed = (a * seed + c) % m) / m;
        s2 = (seed = (a * seed + c) % m) / m;
        s3 = (seed = (a * seed + c) % m) / m;
        s4 = (seed = (a * seed + c) % m) / m;
        counter = 0;
    }

    /*
     * getInstance() 方法（单例获取）
     * -------------------------------
     * 保证系统中只有一个 PinkNoiseEngine 实例，
     * 避免静态变量频繁访问带来的性能损耗。
     */
    public static function getInstance():PinkNoiseEngine {
        if (instance == undefined) {
            instance = new PinkNoiseEngine();
            // 重定义 getInstance 以直接返回实例，进一步减少调用开销
            getInstance = function():PinkNoiseEngine {
                return instance;
            };
        }
        return instance;
    }

    /*
     * nextFloat() 方法
     * -------------------------------
     * 生成一个粉红噪音样本，使用内联展开所有 super.nextFloat() 调用，
     * 并根据 counter 控制各层的更新频率（利用按位与操作优化模运算）。
     *
     * 更新策略说明：
     * - modVal 为 counter 与 15 的按位与结果，相当于 counter % 16，
     *   根据不同的模值条件，决定更新多少层：
     *   - 当 modVal == 0 时：更新所有 5 层（s0, s1, s2, s3, s4）
     *   - 当 (modVal & 7) == 0 时：更新前 4 层（s0, s1, s2, s3）
     *   - 当 (modVal & 3) == 0 时：更新前 3 层（s0, s1, s2）
     *   - 当 (modVal & 1) == 0 时：更新前 2 层（s0, s1）
     *   - 否则只更新 s0
     *
     * 这样设计确保各层以不同的频率更新，模仿不同频段噪声的特性，
     * 同时结合预设的权重（内联固化的权重常量），实现频域能量的均衡分布。
     *
     * 加权求和：
     * - 返回值为加权求和结果，再除以归一化因子（0.43995），确保输出归一化到 [0,1) 区间。
     * - 加权系数分别为：
     *   s0 * 0.07386, s1 * 0.07975, s2 * 0.08664, s3 * 0.09488, s4 * 0.10482
     *   这些常数是根据数学推导和实验调参得到的最优参数，
     *   使得最终合成的噪音功率谱接近理想的 1/f 分布。
     */
    public function nextFloat():Number {
        // 利用按位与运算优化 mod 运算，counter++ 与 15 进行与运算
        var modVal:Number = ++counter & 15;

        if (modVal == 0) {
            // 当 modVal == 0 时，更新所有 5 层
            // 内联展开嵌套调用，依次更新 s0 到 s4
            s4 = (s3 = (s2 = (s1 = (
                // 最内层先更新 s0，并立即更新 seed，用于后续 s1 的赋值过程
                (s0 = (seed = (a * seed + c) % m) / m, (seed = (a * seed + c) % m))) / m, (seed = (a * seed + c) % m)) / m, (seed = (a * seed + c) % m)) / m, (seed = (a * seed + c) % m)) / m;
        } else if ((modVal & 7) == 0) {
            // 当 modVal 的低 3 位为 0 时（等价于 counter % 8 == 0），更新前 4 层
            s3 = (s2 = (s1 = ((s0 = (seed = (a * seed + c) % m) / m, (seed = (a * seed + c) % m))) / m, (seed = (a * seed + c) % m)) / m, (seed = (a * seed + c) % m)) / m;
        } else if ((modVal & 3) == 0) {
            // 当 modVal 的低 2 位为 0（等价于 counter % 4 == 0），更新前 3 层
            s2 = (s1 = ((s0 = (seed = (a * seed + c) % m) / m, (seed = (a * seed + c) % m))) / m, (seed = (a * seed + c) % m)) / m;
        } else if ((modVal & 1) == 0) {
            // 当 modVal 为偶数（但不满足以上条件），更新前 2 层
            s1 = ((s0 = (seed = (a * seed + c) % m) / m, (seed = (a * seed + c) % m))) / m;
        } else {
            // 其它情况下，只更新最低层 s0
            s0 = (seed = (a * seed + c) % m) / m;
        }

        // 加权求和，内联展开加权操作，归一化输出
        return (s0 * 0.07386 + s1 * 0.07975 + s2 * 0.08664 + s3 * 0.09488 + s4 * 0.10482) / 0.43995;
    }
}
