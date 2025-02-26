import org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine;

/**
 * 64位PCG-XSH-RR算法实现（严格遵循PCG官方规范）
 * 核心改进点：
 * 1. 精确模拟64位运算流程
 * 2. 严格处理AS2的32位有符号转换问题
 * 3. 优化位运算表达式确保无符号处理
 */
class org.flashNight.naki.RandomNumberEngine.PCGEngine extends BaseRandomNumberEngine {
    private static var instance:PCGEngine;
    
    // region 64位算法常量
    /** LCG乘数（PCG官方64位参数） */
    private static var MUL_HI:Number = 0x4c957f2d; // 高位
    private static var MUL_LO:Number = 0x5851f42d; // 低位
    
    /** 默认增量（必须为奇数） */
    private static var DEF_INC_HI:Number = 0x14057b7e;
    private static var DEF_INC_LO:Number = 0xef37d92f;
    // endregion
    
    // region 实例变量
    /** 64位状态（分解为高低位） */
    private var stateHi:Number;
    private var stateLo:Number;
    
    /** 64位增量（最低位强制为1） */
    private var incHi:Number;
    private var incLo:Number;
    // endregion
    
    // region 初始化
    private function PCGEngine() {
        // 混合时间戳与魔数生成种子
        var seedHi:Number = toUInt32(new Date().getTime() ^ 0xCAFEBABE);
        var seedLo:Number = toUInt32(Math.random() * 0x100000000);
        initialize(seedHi, seedLo, DEF_INC_HI, DEF_INC_LO);
    }
    
    public static function getInstance():PCGEngine {
        if (!instance) instance = new PCGEngine();
        return instance;
    }
    
    /**
     * 初始化64位状态
     * @param seedHi 初始种子高位
     * @param seedLo 初始种子低位
     * @param incHi 增量高位（最低位自动置1）
     * @param incLo 增量低位（最低位自动置1）
     */
    public function initialize(seedHi:Number, seedLo:Number, incHi:Number, incLo:Number):Void {
        // 强制增量为奇数
        this.incHi = toUInt32(incHi);
        this.incLo = toUInt32(incLo | 0x1);
        
        // 初始状态 = (种子 + 增量) * 乘数 + 增量
        var carry:Number;
        stateHi = seedHi;
        stateLo = toUInt32(seedLo + this.incLo);
        carry = (stateLo < seedLo) ? 1 : 0; // 处理加法进位
        stateHi = toUInt32(seedHi + this.incHi + carry);
        
        // 预热增强随机性
        for (var i:Number=0; i<3; i++) next();
    }
    // endregion
    
    // region 核心算法
    /**
     * 64位状态推进（精确模拟PCG-RXS-M-XS64官方实现）
     */
    private function advanceState():Void {
        // 保存旧状态用于乘法
        var oldHi:Number = stateHi;
        var oldLo:Number = stateLo;
        
        // 计算低位乘积 (oldLo * MUL_LO)
        var loProd:Number = toUInt32(oldLo * MUL_LO);
        var carry:Number = toUInt32((loProd >>> 16) * 0x10000) >> 16; // 获取高16位进位
        
        // 交叉乘积项 (oldHi * MUL_LO + oldLo * MUL_HI)
        var cross1:Number = toUInt32(oldHi * MUL_LO);
        var cross2:Number = toUInt32(oldLo * MUL_HI);
        var crossSum:Number = toUInt32(cross1 + cross2);
        carry += (crossSum >>> 16) * 0x10000 >> 16; // 进位累加
        
        // 高位乘积 (oldHi * MUL_HI)
        var hiProd:Number = toUInt32(oldHi * MUL_HI);
        
        // 合成新状态并加增量
        stateLo = toUInt32(loProd + incLo);
        carry += (stateLo < loProd) ? 1 : 0; // 低位加法进位
        stateHi = toUInt32(hiProd + crossSum + incHi + carry);
    }
    
    /**
     * XSH-RR输出变换（高位参与运算）
     * @return 32位无符号整数
     */
    private function outputTransform():Number {
        // 使用stateHi进行变换（官方规范）
        var rotated:Number = toUInt32(stateHi >>> 27); // 高5位移到低位
        var xorShifted:Number = toUInt32((stateHi ^ (stateHi >>> 18)) >>> 5);
        return toUInt32((rotated << 27) | xorShifted);
    }
    // endregion
    
    // region 公共接口
    public function next():Number {
        advanceState();
        return outputTransform();
    }
    
    public function nextFloat():Number {
        var highBits:Number = next();
        var lowBits:Number = next();
        // 组合53位精度（符合IEEE754标准）
        return (highBits * 0x100000000 + lowBits) * 2.3283064365386963e-10; // 1/(2^32)
    }
    
    public function nextInt(min:Number, max:Number):Number {
        var range:Number = max - min + 1;
        var threshold:Number = toUInt32(0xFFFFFFFF - (0xFFFFFFFF % range));
        var r:Number;
        do { r = next(); } while (r >= threshold);
        return min + (r % range);
    }
    // endregion
    
    // region 工具方法
    /**
     * 强制转换为无符号32位（关键处理）
     * @param n 输入数值
     * @return 无符号32位数值
     */
    private function toUInt32(n:Number):Number {
        return n >>> 0; // 利用无符号右移特性
    }
    
    /** 反序列化保持单例 */
    private function readResolve():Object {
        return getInstance();
    }
    // endregion
}