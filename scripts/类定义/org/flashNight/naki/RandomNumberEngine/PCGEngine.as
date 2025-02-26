import org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine;

class org.flashNight.naki.RandomNumberEngine.PCGEngine extends BaseRandomNumberEngine {
    // 静态单例实例
    private static var instance:PCGEngine;

    // 实例变量
    private var stateHigh:Number = 0;    // 状态高位（模拟64位）
    private var stateLow:Number = 0;     // 状态低位（模拟64位）
    private var incHigh:Number = 0;      // 增量高位（必须为奇数）
    private var incLow:Number = 0;       // 增量低位（必须为奇数）
    
    // PCG常数（根据官方推荐值）
    static private var MULTIPLIER_HIGH:Number = 0x4c95_7f2d; // 6364136223846793005高32位
    static private var MULTIPLIER_LOW:Number  = 0x5851_f42d; // 6364136223846793005低32位

    // 私有构造函数，防止外部直接实例化
    private function PCGEngine() {
        // 使用默认种子初始化
        var timeStamp:Number = new Date().getTime();
        init(0, timeStamp, 0x853c_49e6, 0x768a_0f2b); // 推荐初始化模式
    }

    // 静态方法获取单例实例
    public static function getInstance():PCGEngine {
        if (instance == null) {
            instance = new PCGEngine();
            getInstance = function():PCGEngine { return instance; }; // 热替换优化
        }
        return instance;
    }

    /**
     * 初始化生成器（64位种子+64位序列）
     * @param initHigh 初始状态高32位
     * @param initLow  初始状态低32位
     * @param seqHigh  序列号高32位（最低位必须置1）
     * @param seqLow   序列号低32位（最低位必须置1）
     */
    public function init(initHigh:Number, initLow:Number, seqHigh:Number, seqLow:Number):Void {
        // 确保增量是奇数（低两位强制置1）
        incHigh = seqHigh | 0x80000000;
        incLow  = (seqLow | 0x00000001) >>> 0;
        
        // 初始化状态
        stateHigh = initHigh >>> 0;
        stateLow  = initLow >>> 0;
        
        // 预热状态（推进一次保证初始状态质量）
        next();
    }

    /**
     * 64位状态推进（核心算法）
     * 实现：state = state * MULTIPLIER + INCREMENT
     */
    private function advanceState():Void {
        // 分解64位乘法（a*b = (a_high*b_high<<64) + (a_high*b_low + a_low*b_high)<<32 + a_low*b_low)
        var oldHigh:Number = stateHigh;
        var oldLow:Number  = stateLow;
        
        // 计算低32位乘积
        var mulLow:Number = oldLow * MULTIPLIER_LOW;
        var carry:Number = (mulLow / 0x100000000) >>> 0;
        
        // 计算交叉乘积项
        var term1:Number = oldHigh * MULTIPLIER_LOW;
        var term2:Number = oldLow * MULTIPLIER_HIGH;
        var cross:Number = (term1 + term2) >>> 0;
        
        // 计算高位乘积
        stateHigh = (oldHigh * MULTIPLIER_HIGH + ((cross + carry) / 0x100000000) >>> 0) >>> 0;
        
        // 合成最终结果并加上增量
        var newLow:Number = (mulLow & 0xFFFFFFFF) + incLow;
        var newHigh:Number = (stateHigh + cross + carry + incHigh + (newLow / 0x100000000 >>> 0)) >>> 0;
        
        stateLow = newLow >>> 0;
        stateHigh = newHigh >>> 0;
    }

    /**
     * XSH-RR输出变换（官方推荐32位输出模式）
     * 实现：ROT32((stateHigh ^ (stateHigh >>> 18)) >>> 27, stateHigh >>> 27)
     */
    private function outputXshRr():Number {
        var high:Number = stateHigh;
        var xorShifted:Number = (high ^ (high >>> 18)) >>> 27;
        var rot:Number = high >>> 27;
        return ((xorShifted >>> rot) | (xorShifted << (32 - rot))) >>> 0;
    }

    // 生成下一个32位随机整数
    public function next():Number {
        advanceState();
        return outputXshRr();
    }

    // 生成[0,1)区间的高精度浮点数（使用全32位精度）
    public function nextFloat():Number {
        advanceState();
        return (outputXshRr() / 0x100000000) + (outputXshRr() / 0x10000000000000000);
    }
}
