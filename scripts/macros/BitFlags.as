/**
 * BitFlags.as - 子弹类型位标志常量宏使用指南
 * 
 * ===========================================
 * AS2 宏展开机制使用指南
 * ===========================================
 * 
 * 背景：
 * AS2 的 #include 机制允许将外部文件内容直接展开到当前位置，
 * 类似于 C/C++ 的宏预处理。这种方式可以实现零运行时成本的常量引用。
 * 
 * 可用的单独宏文件：
 * - FLAG_MELEE.as        → var FLAG_MELEE:Number = 1 << 0;
 * - FLAG_CHAIN.as        → var FLAG_CHAIN:Number = 1 << 1;
 * - FLAG_PIERCE.as       → var FLAG_PIERCE:Number = 1 << 2;
 * - FLAG_TRANSPARENCY.as → var FLAG_TRANSPARENCY:Number = 1 << 3;
 * - FLAG_GRENADE.as      → var FLAG_GRENADE:Number = 1 << 4;
 * - FLAG_EXPLOSIVE.as    → var FLAG_EXPLOSIVE:Number = 1 << 5;
 * - FLAG_NORMAL.as       → var FLAG_NORMAL:Number = 1 << 6;
 * - FLAG_VERTICAL.as     → var FLAG_VERTICAL:Number = 1 << 7;
 * 
 * 使用方式：
 * 
 * 1. 在函数内部按需引用：
 *    function checkBulletType(bullet) {
 *        #include "../macros/FLAG_MELEE.as"
 *        #include "../macros/FLAG_CHAIN.as"
 *        
 *        if (bullet.flags & FLAG_MELEE) {
 *            // 处理近战子弹逻辑
 *        }
 *    }
 * 
 * 2. 在类方法中引用：
 *    public static function setTypeFlags(bullet:Object):Number {
 *        if (cachedData == undefined) {
 *            #include "../macros/FLAG_MELEE.as"
 *            #include "../macros/FLAG_CHAIN.as"
 *            #include "../macros/FLAG_PIERCE.as"
 *            // ... 根据需要引用其他标志
 *            
 *            var flags:Number = ((isMelee ? FLAG_MELEE : 0)
 *                              | (isChain ? FLAG_CHAIN : 0)
 *                              | (isPierce ? FLAG_PIERCE : 0));
 *        }
 *    }
 * 
 * 3. 按需引用原则：
 *    只在需要使用特定标志位的作用域内引用对应的宏文件，
 *    避免不必要的常量定义，保持代码简洁。
 * 
 * 优势：
 * - 零运行时成本：编译时展开，不产生额外的内存开销
 * - 按需加载：只引用实际使用的标志位
 * - 维护性强：单一常量定义，统一修改
 * - 作用域控制：可以在特定作用域内定义，避免全局污染
 * 
 * 注意事项：
 * - #include 路径相对于当前文件位置
 * - 同一作用域内不要重复引用同一宏文件
 * - 宏展开后的变量名不要与现有变量冲突
 */

// 为了向后兼容，保留完整的标志位定义
var FLAG_MELEE:Number        = 1 << 0;
var FLAG_CHAIN:Number        = 1 << 1;
var FLAG_PIERCE:Number       = 1 << 2;
var FLAG_TRANSPARENCY:Number = 1 << 3;
var FLAG_GRENADE:Number      = 1 << 4;
var FLAG_EXPLOSIVE:Number    = 1 << 5;
var FLAG_NORMAL:Number       = 1 << 6;
var FLAG_VERTICAL:Number     = 1 << 7;
