import org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine;

class org.flashNight.naki.RandomNumberEngine.MersenneTwister extends BaseRandomNumberEngine {
    // 静态单例实例
    private static var instance:MersenneTwister;

    // 实例变量
    private var mt:Array; // 状态数组
    private var index:Number = 625; // 初始化触发的索引值
    private var N:Number = 624; // 状态数组的长度
    private var M:Number = 397; // 用于"twist"变换的中间变量
    private var MATRIX_A:Number = 0x9908b0df; // 常量向量a
    private var UPPER_MASK:Number = 0x80000000; // 用于获取高位的掩码
    private var LOWER_MASK:Number = 0x7fffffff; // 用于获取低位的掩码

    // 私有构造函数，防止外部直接实例化
    private function MersenneTwister() {
        initialize(new Date().getTime()); // 使用当前时间初始化种子
    }

    // 静态方法获取单例实例
    // 如果实例不存在则创建一个新的实例
    public static function getInstance():MersenneTwister {
        if (instance == null) {
            instance = new MersenneTwister();
            // redefine getInstance to return instance directly
            getInstance = function():MersenneTwister {
                return instance;
            };
        }
        return instance;
    }

    // 初始化随机数生成器
    // @param seed: 用于初始化的种子
    public function initialize(seed:Number):Void {
        mt = new Array(N); // 初始化状态数组
        if (isNaN(seed)) {
            seed = new Date().getTime(); // 如果种子不是数字，使用当前时间作为默认种子
        }
        mt[0] = seed & 0xffffffff; // 初始化状态数组的第一个值
        for (var i:Number = 1; i < N; i++) {
            mt[i] = (1812433253 * (mt[i - 1] ^ (mt[i - 1] >> 30)) + i) & 0xffffffff; // 初始化其他值
        }
        index = N; // 确保在下次使用前执行"twist"变换
    }

    // 执行"twist"变换
    // 这是 Mersenne Twister 算法的核心部分，用于产生新的随机数序列
    private function twist():Void {
        var kk:Number;
        var y:Number;
        for (kk = 0; kk < N - M; kk++) {
            y = (mt[kk] & UPPER_MASK) | (mt[kk + 1] & LOWER_MASK); // 获取当前和下一个数的高位和低位
            mt[kk] = mt[kk + M] ^ (y >> 1) ^ ((y & 1) * MATRIX_A); // 执行变换
        }
        for (; kk < N - 1; kk++) {
            y = (mt[kk] & UPPER_MASK) | (mt[kk + 1] & LOWER_MASK);
            mt[kk] = mt[kk + (M - N)] ^ (y >> 1) ^ ((y & 1) * MATRIX_A);
        }
        y = (mt[N - 1] & UPPER_MASK) | (mt[0] & LOWER_MASK);
        mt[N - 1] = mt[M - 1] ^ (y >> 1) ^ ((y & 1) * MATRIX_A);

        index = 0; // 重置索引
    }

    // 生成下一个随机数
    // @return 下一个随机数
    public function next():Number {
        if (index >= N) {
            twist(); // 如果所有数都被用过，执行"twist"变换生成新的数列
        }

        var y:Number = mt[index++]; // 获取当前的随机数
        y ^= (y >> 11); // 执行一系列的位操作
        y ^= (y << 7) & 0x9d2c5680;
        y ^= (y << 15) & 0xefc60000;
        y ^= (y >> 18);

        // trace("mersenne next: " + y); // 输出当前生成的随机数

        return y;
    }

    // 生成一个0到1之间的随机浮点数
    // @return 0到1之间的随机浮点数
    public function nextFloat():Number {
        return next() / 2147483648; // 归一化到 [0, 1) 区间
    }
}
