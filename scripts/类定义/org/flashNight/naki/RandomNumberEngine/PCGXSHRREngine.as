import org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine;

/**
 * PCG-XSH-RS 32位高随机性算法实现
 * 
 * 基于PCG家族算法设计，具有以下特性：
 * 1. 通过XSH-RS输出变换实现32位输出
 * 2. 通过LCG线性同余生成器更新状态
 * 3. 符合PCG官方规范的无符号32位输出
 * 
 * AS2位运算特殊说明：
 * - ActionScript 2没有无符号整数类型，所有位运算操作数都会转换为32位有符号整数
 * - 右移运算符(>>)会保留符号位，而无符号右移(>>>)会用0填充高位
 * - 超过0x7FFFFFFF的数值会被视为负数，需要特殊处理
 * - 位运算操作会自动将Number类型转换为32位整数
 */
class org.flashNight.naki.RandomNumberEngine.PCGXSHRREngine extends BaseRandomNumberEngine {
    private static var instance:PCGXSHRREngine;

    // region 算法常量
    /**
     * LCG乘数 (来自PCG官方推荐参数)
     * 注意：AS2中必须显式声明为Number类型以避免整数溢出
     */
    private static var MULTIPLIER:Number = 0x5851F42D; // 32位无符号值：1481765933
    
    /**
     * 默认增量值 (必须为奇数)
     * 设计要点：保证增量与2^32互质
     */
    private static var DEFAULT_INCREMENT:Number = 0x14057B7E; // 32位无符号值：336157630
    
    /**
     * 32位无符号整数最大值+1 (2^32)
     * 特殊处理：使用十六进制表示避免精度丢失
     */
    private static var UINT32_MAX:Number = 0x100000000; // 4294967296
    // endregion

    // region 实例变量
    /** 
     * 当前状态值
     * 存储策略：始终存储为无符号32位值的Number表示
     * 示例：0xFFFFFFFF存储为-1，但通过toUInt32转换后视为4294967295
     */
    private var state:Number;
    
    /**
     * LCG增量值
     * 初始化要求：必须为奇数，通过initialize方法保证
     */
    private var increment:Number;
    // endregion

    // region 构造函数
    /**
     * 私有构造函数（单例模式）
     * 种子生成策略：
     * 1. 使用当前时间戳作为基础种子
     * 2. 与魔数0xCAFEBABE异或增加熵
     * 3. 强制转换为无符号32位
     */
    private function PCGXSHRREngine() {
        var seed:Number = new Date().getTime();
        seed = toUInt32(seed ^ 0xCAFEBABE);
        initialize(seed, DEFAULT_INCREMENT);
    }
    // endregion

    // region 公共接口
    /**
     * 获取单例实例
     * @return PCGXSHRREngine 全局唯一实例
     */
    public static function getInstance():PCGXSHRREngine {
        if (!instance) instance = new PCGXSHRREngine();
        return instance;
    }

    /**
     * 生成下一个32位无符号整数
     * 算法步骤：
     * 1. 保存当前状态
     * 2. 使用LCG公式更新状态
     * 3. 应用XSH-RS变换生成输出
     * 
     * @return Number [0, 0xFFFFFFFF]范围内的无符号32位整数
     */
    public function next():Number {
        var oldState:Number = state;
        
        // 状态更新：state = (oldState * MULTIPLIER + increment) mod 2^32
        // AS2处理：显式转换为无符号32位
        state = toUInt32(oldState * MULTIPLIER + increment);
        
        // XSH-RS输出变换（PCG官方规范实现）
        // 步骤分解：
        // 1. 高位移位：保留高5位(bit 27-31)并移至低位
        var rotated:Number = toUInt32(oldState >>> 27); // 无符号右移获取高5位
        
        // 2. 异或移位：消除低位相关性
        var xorShifted:Number = toUInt32((oldState ^ (oldState >>> 18)) >>> 5);
        
        // 3. 合并结果：(rotated << 27) | xorShifted
        return toUInt32((rotated << 27) | xorShifted);
    }

    /**
     * 生成[0,1)范围内的浮点数
     * 精度优化策略：
     * - 将32位数分割为高16位和低16位分别处理
     * - 避免直接除法导致的精度丢失
     * 
     * @return Number 均匀分布的浮点数，范围[0,1)
     */
    public function nextFloat():Number {
        var n:Number = next();
        // 高16位计算：0xFFFF0000部分转换为0.0-0.9999847412109375
        var high:Number = (n >>> 16) * 0.0000152587890625; // 精确等于 1/65536
        
        // 低16位计算：0x0000FFFF部分添加精细小数
        var low:Number = (n & 0xFFFF) * 0.00000000023283064365386962890625; // 精确等于 1/4294967296
        
        return high + low;
    }

    /**
     * 生成指定范围的整数
     * @param min 最小值（包含）
     * @param max 最大值（包含）
     * @return Number [min, max]范围内的整数
     */
    public function nextInt(min:Number, max:Number):Number {
        var range:Number = max - min + 1;
        // 计算拒绝阈值，避免模运算偏差
        var threshold:Number = toUInt32(UINT32_MAX - UINT32_MAX % range);
        var r:Number;
        do {
            r = next();
        } while (r >= threshold);
        return min + (r % range);
    }
    // endregion

    // region 私有方法
    /**
     * 初始化随机数生成器
     * @param seed 初始种子值
     * @param inc 增量值（将被转换为奇数）
     */
    private function initialize(seed:Number, inc:Number):Void {
        // 确保增量为奇数：(inc << 1) | 1 保证最低位为1
        this.increment = toUInt32((inc << 1) | 1);
        
        // 初始状态计算：state = seed + increment
        this.state = toUInt32(seed + this.increment);
        
        // 状态混洗：增强初始随机性
        next(); // 初始混洗
        for (var i:Number = 0; i < 16; i++) next(); // 额外16次混洗
    }

    /**
     * 将数值转换为无符号32位表示
     * AS2特殊处理说明：
     * - 负数转换：当输入为负数时，实际表示的是大于0x7FFFFFFF的无符号值
     * - 示例：-1 → 0xFFFFFFFF，-2147483648 → 0x80000000
     * 
     * @param n 输入数值
     * @return Number 无符号32位数值的Number表示
     */
    private function toUInt32(n:Number):Number {
        // 处理负数情况：将32位有符号转换为无符号
        // 方法：取低32位，负数时通过补码转换
        return n < 0 ? (n & 0x7FFFFFFF) + 0x80000000 : n & 0xFFFFFFFF;
    }

    /**
     * 反序列化时保持单例
     */
    private function readResolve():Object {
        return getInstance();
    }
    // endregion
}
