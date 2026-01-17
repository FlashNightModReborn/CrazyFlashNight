/**
 * BuffBitFlags.as - Buff计算类型位标志常量宏使用指南
 *
 * ===========================================
 * AS2 宏展开机制使用指南
 * ===========================================
 *
 * 背景：
 * AS2 的 #include 机制允许将外部文件内容直接展开到当前位置，
 * 类似于 C/C++ 的宏预处理。这种方式可以实现零运行时成本的常量引用，
 * 完全消除静态变量的索引开销。
 *
 * ===========================================
 * 位标志宏文件
 * ===========================================
 *
 * 单独位标志：
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
 * 类型字符串常量：
 * - BUFF_TYPE_ADD.as           → var BUFF_TYPE_ADD:String = "add";
 * - BUFF_TYPE_MULTIPLY.as      → var BUFF_TYPE_MULTIPLY:String = "multiply";
 * - BUFF_TYPE_PERCENT.as       → var BUFF_TYPE_PERCENT:String = "percent";
 * - BUFF_TYPE_ADD_POSITIVE.as  → var BUFF_TYPE_ADD_POSITIVE:String = "add_positive";
 * - BUFF_TYPE_ADD_NEGATIVE.as  → var BUFF_TYPE_ADD_NEGATIVE:String = "add_negative";
 * - BUFF_TYPE_MULT_POSITIVE.as → var BUFF_TYPE_MULT_POSITIVE:String = "mult_positive";
 * - BUFF_TYPE_MULT_NEGATIVE.as → var BUFF_TYPE_MULT_NEGATIVE:String = "mult_negative";
 * - BUFF_TYPE_MAX.as           → var BUFF_TYPE_MAX:String = "max";
 * - BUFF_TYPE_MIN.as           → var BUFF_TYPE_MIN:String = "min";
 * - BUFF_TYPE_OVERRIDE.as      → var BUFF_TYPE_OVERRIDE:String = "override";
 *
 * 组合掩码：
 * - BUFF_MASK_COMMON.as       → var BUFF_MASK_COMMON:Number = 7;     // ADD|MULTIPLY|PERCENT
 * - BUFF_MASK_BOUNDS.as       → var BUFF_MASK_BOUNDS:Number = 896;   // MAX|MIN|OVERRIDE
 * - BUFF_MASK_CONSERVATIVE.as → var BUFF_MASK_CONSERVATIVE:Number = 120; // 保守语义类型
 *
 * 映射表：
 * - BUFF_TYPE_TO_BIT.as       → var BUFF_TYPE_TO_BIT:Object = {...}; // 类型→位值映射
 *
 * ===========================================
 * 使用方式
 * ===========================================
 *
 * 1. 在函数内部按需引用（推荐）：
 *
 *    public function calculate(baseValue:Number):Number {
 *        // 引入需要的位标志
 *        #include "../macros/BUFF_BIT_ADD.as"
 *        #include "../macros/BUFF_MASK_COMMON.as"
 *
 *        // 快速路径检测
 *        if (_typeMask == BUFF_BIT_ADD) {
 *            return baseValue + _totalAdd;
 *        }
 *        // ...
 *    }
 *
 * 2. 在 addModification 中使用映射表：
 *
 *    public function addModification(type:String, value:Number):Void {
 *        #include "../macros/BUFF_TYPE_TO_BIT.as"
 *
 *        var bit:Number = BUFF_TYPE_TO_BIT[type];
 *        if (bit != undefined) {
 *            _typeMask |= bit;
 *        }
 *        // ...
 *    }
 *
 * 3. 使用类型字符串常量进行比较：
 *
 *    public function addModification(type:String, value:Number):Void {
 *        #include "../macros/BUFF_TYPE_ADD.as"
 *        #include "../macros/BUFF_TYPE_MULTIPLY.as"
 *
 *        if (type == BUFF_TYPE_ADD) {
 *            _totalAdd += value;
 *        } else if (type == BUFF_TYPE_MULTIPLY) {
 *            _totalMultiplier += (value - 1);
 *        }
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
 *
 * ===========================================
 * 优势
 * ===========================================
 *
 * - 零运行时成本：编译时展开，不产生额外的内存开销
 * - 消除静态变量开销：避免 AS2 静态变量的高索引成本
 * - 按需加载：只引用实际使用的标志位
 * - 维护性强：单一常量定义，统一修改
 * - 作用域控制：可以在特定作用域内定义，避免全局污染
 *
 * ===========================================
 * 注意事项
 * ===========================================
 *
 * - #include 路径相对于当前文件位置
 * - 同一作用域内不要重复引用同一宏文件
 * - 宏展开后的变量名不要与现有变量冲突
 * - 使用 BUFF_TYPE_TO_BIT 映射表时确保只引用一次
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
    "add":           1,
    "multiply":      2,
    "percent":       4,
    "add_positive":  8,
    "add_negative":  16,
    "mult_positive": 32,
    "mult_negative": 64,
    "max":           128,
    "min":           256,
    "override":      512
};
