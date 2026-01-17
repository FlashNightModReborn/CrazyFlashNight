/**
 * BuffBitFlags.as - Buff计算类型位标志常量宏使用指南
 *
 * ===========================================
 * 单一事实源
 * ===========================================
 *
 * 位值和类型字符串的权威定义在 BuffCalculator.as 中。
 * 本文件及相关宏文件均派生自该定义，修改时需保持一致。
 *
 * ===========================================
 * 热路径 vs 非热路径
 * ===========================================
 *
 * 热路径（高频调用，如 addModification）:
 * - 直接使用字面量常量，如 if (type == "add") _typeMask |= 1;
 * - 不要 #include 任何宏文件，避免创建运行时对象
 * - 参见 BuffCalculator.as 中的 addModification 实现
 *
 * 非热路径（初始化、调试、配置解析）:
 * - 可以使用 #include 引入宏文件
 * - Number 类型宏（BUFF_BIT_*.as）零成本
 * - Object 类型宏（BUFF_TYPE_TO_BIT.as）会创建对象，仅用于非热路径
 *
 * ===========================================
 * 位标志宏文件
 * ===========================================
 *
 * 单独位标志（Number 类型，零成本）：
 * - BUFF_BIT_ADD.as           → var BUFF_BIT_ADD:Number = 1 << 0;           // 1
 * - BUFF_BIT_MULTIPLY.as      → var BUFF_BIT_MULTIPLY:Number = 1 << 1;      // 2
 * - BUFF_BIT_PERCENT.as       → var BUFF_BIT_PERCENT:Number = 1 << 2;       // 4
 * - BUFF_BIT_ADD_POSITIVE.as  → var BUFF_BIT_ADD_POSITIVE:Number = 1 << 3;  // 8
 * - BUFF_BIT_ADD_NEGATIVE.as  → var BUFF_BIT_ADD_NEGATIVE:Number = 1 << 4;  // 16
 * - BUFF_BIT_MULT_POSITIVE.as → var BUFF_BIT_MULT_POSITIVE:Number = 1 << 5; // 32
 * - BUFF_BIT_MULT_NEGATIVE.as → var BUFF_BIT_MULT_NEGATIVE:Number = 1 << 6; // 64
 * - BUFF_BIT_MAX.as           → var BUFF_BIT_MAX:Number = 1 << 7;           // 128
 * - BUFF_BIT_MIN.as           → var BUFF_BIT_MIN:Number = 1 << 8;           // 256
 * - BUFF_BIT_OVERRIDE.as      → var BUFF_BIT_OVERRIDE:Number = 1 << 9;      // 512
 *
 * 类型字符串常量（String 类型，有字符串池化，较低成本）：
 * - BUFF_TYPE_ADD.as           → var BUFF_TYPE_ADD:String = "add";
 * - BUFF_TYPE_MULTIPLY.as      → var BUFF_TYPE_MULTIPLY:String = "multiply";
 * - (省略...)
 *
 * 组合掩码（Number 类型，零成本）：
 * - BUFF_MASK_COMMON.as       → var BUFF_MASK_COMMON:Number = 7;     // ADD|MULTIPLY|PERCENT
 * - BUFF_MASK_BOUNDS.as       → var BUFF_MASK_BOUNDS:Number = 896;   // MAX|MIN|OVERRIDE
 * - BUFF_MASK_CONSERVATIVE.as → var BUFF_MASK_CONSERVATIVE:Number = 120; // 保守语义类型
 *
 * 映射表（Object 类型，有运行时分配，仅用于非热路径）：
 * - BUFF_TYPE_TO_BIT.as       → var BUFF_TYPE_TO_BIT:Object = {...};
 *
 * ===========================================
 * 推荐使用方式
 * ===========================================
 *
 * 热路径（addModification 等高频调用）：
 *
 *    // 直接使用字面量，零分配
 *    if (type == "add") {
 *        _typeMask |= 1;
 *        _totalAdd += value;
 *    } else if (type == "multiply") {
 *        _typeMask |= 2;
 *        _totalMultiplier += (value - 1);
 *    }
 *
 * 非热路径（calculate 等中频调用）：
 *
 *    // 可以使用 Number 类型宏
 *    #include "../macros/BUFF_BIT_ADD.as"
 *    #include "../macros/BUFF_MASK_BOUNDS.as"
 *
 *    if (mask == BUFF_BIT_ADD) {
 *        return baseValue + _totalAdd;
 *    }
 *
 * ===========================================
 * 位标志布局
 * ===========================================
 *
 * 位置 | 位值 | 类型            | 语义
 * -----|------|-----------------|------------------
 *   0  |   1  | ADD             | 通用加算
 *   1  |   2  | MULTIPLY        | 通用乘算
 *   2  |   4  | PERCENT         | 百分比
 *   3  |   8  | ADD_POSITIVE    | 正向保守加法
 *   4  |  16  | ADD_NEGATIVE    | 负向保守加法
 *   5  |  32  | MULT_POSITIVE   | 正向保守乘法
 *   6  |  64  | MULT_NEGATIVE   | 负向保守乘法
 *   7  | 128  | MAX             | 最小保底
 *   8  | 256  | MIN             | 最大封顶
 *   9  | 512  | OVERRIDE        | 覆盖
 *
 * ===========================================
 * 快速路径策略
 * ===========================================
 *
 * 1. 仅 ADD:        mask == 1     → return base + totalAdd
 * 2. 仅 MULTIPLY:   mask == 2     → return base * (1 + totalMult)
 * 3. ADD+MULTIPLY:  mask == 3     → return base * (1 + totalMult) + totalAdd
 * 4. 通用三件套:    mask == 7     → 标准计算，跳过保守/边界
 * 5. 无边界控制:    mask & 896==0 → 跳过 MAX/MIN/OVERRIDE 检查
 */

// 为了向后兼容，保留完整的标志位定义
var BUFF_BIT_ADD:Number           = 1 << 0;
var BUFF_BIT_MULTIPLY:Number      = 1 << 1;
var BUFF_BIT_PERCENT:Number       = 1 << 2;
var BUFF_BIT_ADD_POSITIVE:Number  = 1 << 3;
var BUFF_BIT_ADD_NEGATIVE:Number  = 1 << 4;
var BUFF_BIT_MULT_POSITIVE:Number = 1 << 5;
var BUFF_BIT_MULT_NEGATIVE:Number = 1 << 6;
var BUFF_BIT_MAX:Number           = 1 << 7;
var BUFF_BIT_MIN:Number           = 1 << 8;
var BUFF_BIT_OVERRIDE:Number      = 1 << 9;

var BUFF_MASK_COMMON:Number       = 7;   // ADD | MULTIPLY | PERCENT
var BUFF_MASK_BOUNDS:Number       = 896; // MAX | MIN | OVERRIDE
var BUFF_MASK_CONSERVATIVE:Number = 120; // 保守语义类型

var BUFF_TYPE_TO_BIT:Object = {
    add:           1,
    multiply:      2,
    percent:       4,
    add_positive:  8,
    add_negative:  16,
    mult_positive: 32,
    mult_negative: 64,
    max:           128,
    min:           256,
    override:      512
};
