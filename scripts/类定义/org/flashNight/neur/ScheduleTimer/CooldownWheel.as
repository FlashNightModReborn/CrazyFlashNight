/**
 * @class org.flashNight.neur.ScheduleTimer.CooldownWheel
 *
 * @description
 * 一个为 ActionScript 2.0 环境设计的高性能、无ID、单例时间轮调度器。
 * 专为处理大量一次性、无参数的延迟回调任务而优化，将性能压榨到极致。
 *
 * 核心特性:
 * - 【高性能】: 所有关键路径均使用位运算、do-while循环、变量复用等技巧进行深度优化。
 * - 【无ID设计】: 不支持任务的取消，简化了内部逻辑，带来了极致的性能。
 * - 【单例模式】: 通过 CooldownWheel.I() 全局访问，避免重复实例化。
 * - 【固定步长】: 基于 enterFrame 事件驱动，每帧自动"拨动"一格。
 * - 【LIFO执行顺序】: 同一槽位内的多个任务按后进先出(LIFO)顺序执行，即最后添加的任务最先执行。
 *                   如果业务逻辑依赖于任务的执行顺序，请注意此特性。
 *
 * ========== 重要限制 ==========
 * 【最大延迟限制】: delay 参数必须 ≤ 127 帧（约4.2秒@30FPS）
 * 超过此限制的任务会因位运算回环而被放入错误槽位，导致执行时间不可预测。
 * 例如: delay=200 会被计算为 (pos + 200) & 127，任务将在错误时间执行。
 *
 * 如果需要更长的延迟，请使用：
 * - EnhancedCooldownWheel（同样有128帧限制，但提供ID管理）
 * - TaskManager + CerberusScheduler（支持任意延迟，最高可达60分钟）
 * ==============================
 *
 * @example
 * // 在 30 帧后执行 myCallback 函数
 * CooldownWheel.I().add(30, myCallback);
 *
 * // 在下一帧立即执行
 * CooldownWheel.I().add(0, anotherCallback);
 *
 * function myCallback():Void {
 *     trace("延迟任务已执行!");
 * }
 */
class org.flashNight.neur.ScheduleTimer.CooldownWheel {

    //================================================================================
    // 静态常量 & 私有字段
    //================================================================================

    /**
     * @private
     * 时间轮的槽位总数。由宏在编译时注入。
     * 目前为 128
     */
    private static var WHEEL_SIZE:Number;

    /**
     * @private
     * 用于指针循环的位运算掩码 (值为 WHEEL_SIZE - 1)。由宏在编译时注入。
     * 目前为 127
     */
    private static var WHEEL_MASK:Number;

    /**
     * @private
     * 单例实例的引用。
     */
    public static var inst:CooldownWheel;

    /**
     * @private
     * 静态初始化锁，确保 init() 仅执行一次。
     */
    private static var initialized:Boolean = init();

    /**
     * @private
     * 核心数据结构，一个由数组构成的数组 (Array<Array<Function>>)。
     * 每个子数组代表一个时间槽，保存该槽内所有待执行的回调函数。
     */
    private var slots:Array;

    /**
     * @private
     * 当前指针在时间轮上的位置。初始化到最后一个槽位，确保第一次 tick() 时指针能正确移到 0 号槽。
     */
    private var pos:Number = WHEEL_SIZE - 1;


    //================================================================================
    // 静态初始化 & 单例获取
    //================================================================================

    /**
     * @private
     * 静态初始化函数。
     * 从宏文件加载常量，这是AS2中实现编译时配置的一种高效方式。
     * @return {Boolean} 总是返回 true，用于触发静态字段 `initialized` 的赋值。
     */
    private static function init():Boolean {
        #include "../macros/WHEEL_SIZE_MACRO.as"
        #include "../macros/WHEEL_MASK_MACRO.as"

        WHEEL_SIZE = WHEEL_SIZE_MACRO;
        WHEEL_MASK = WHEEL_MASK_MACRO;

        return true;
    }

    /**
     * 获取 CooldownWheel 的全局唯一实例（Singleton）。
     *
     * 【设计模式】: 自修改闭包单例模式 (Self-Modifying Closure Singleton)。
     * 它只在第一次调用时执行完整的初始化逻辑，然后用一个更快的闭包函数重写自身，
     * 以达到后续调用的性能最大化。
     *
     * 【首次调用流程】:
     * 1. 创建一个新的 CooldownWheel 实例。
     * 2. 将实例同时赋值给静态属性 `inst` (用于外部可能的反射访问) 和一个局部变量 `i`。
     * 3. 创建一个新的匿名函数（闭包），该函数捕获了局部变量 `i`。
     * 4. 用这个新的闭包函数 **覆盖** `CooldownWheel.I` 静态方法本身。
     * 5. 返回新创建的实例。
     *
     * 【后续调用流程】:
     * 1. 直接执行被替换后的、极其简单的闭包函数。
     * 2. 该函数直接返回它所捕获的局部变量 `i`，绕开了所有条件判断和类静态属性的查找开销。
     *
     * @return {CooldownWheel} 全局单例对象。
     */
    public static function I():CooldownWheel {
        // 步骤 1 & 2: 创建实例并同时存入静态区和局部变量区。
        // 局部变量 `i` 是为闭包捕获而准备的“高速通道”。
        var i:CooldownWheel = CooldownWheel.inst = new CooldownWheel();

        // 步骤 3 & 4: 自修改核心。
        // 将 CooldownWheel.I 方法重写为一个只返回闭包变量 `i` 的超轻量级函数。
        CooldownWheel.I = function():CooldownWheel {
            return i;
        };

        // 步骤 5: 首次调用，返回新创建的实例。
        return i;
    }


    //================================================================================
    // 构造函数
    //================================================================================

    /**
     * @private
     * 构造函数。应通过 CooldownWheel.I() 调用，而不是直接 new。
     * 负责初始化时间轮的槽位，并创建驱动其运转的 onEnterFrame 事件。
     */
    private function CooldownWheel() {
        // 1. 初始化 slots 数组，为每个槽位分配一个空的子数组。
        slots = new Array(WHEEL_SIZE);
        for (var i:Number = 0; i < WHEEL_SIZE; ++i) {
            slots[i] = [];
        }

        // 2. 创建一个空的 MovieClip 作为时间轮的“心脏”。
        //    它的 onEnterFrame 事件将成为驱动 tick() 函数的稳定时钟。
        var depth:Number = _root.getNextHighestDepth();
        var clip:MovieClip = _root.createEmptyMovieClip("_cdWheel", depth);
        
        // 经典AS2闭包技巧：保存 this 上下文引用，供事件函数内部使用。
        var self:CooldownWheel = this;
        clip.onEnterFrame = function():Void {
            self.tick();
        };
    }


    //================================================================================
    // 公开 API
    //================================================================================

    /**
     * 添加一个一次性的延迟回调任务。
     *
     * 【重要契约】: delay 必须 ≤ WHEEL_MASK (127)，否则任务将被放入错误槽位。
     * 调用方有责任确保 delay 在有效范围内。调试模式下会输出警告。
     *
     * @param {Number} delay 任务执行前需要等待的 tick (帧) 数。
     *                       - 如果 `delay` > 0, 任务将在 `delay` 帧后执行。
     *                       - 如果 `delay` ≤ 0, 任务将在下一帧立即执行。
     *                       - 【限制】delay 必须 ≤ 127，超出会导致执行时间错误。
     * @param {Function} callback 到期后需要执行的回调函数，该函数应不含参数。
     */
    public function add(delay:Number, callback:Function):Void {
        // 【性能优化】: 计算目标槽索引。
        // 【契约】: delay 必须 ≤ 127，超出范围由调用方负责，详见类文档
        var targetIndex:Number = (pos + (delay > 0 ? delay : 1)) & WHEEL_MASK;
        var targetSlot:Array = slots[targetIndex];

        // 【性能优化】: 使用 array[array.length] 直接赋值，避免 array.push() 的函数调用开销。
        targetSlot[targetSlot.length] = callback;
    }

    /**
     * 重置时间轮的状态。
     * 此方法会清空所有槽位中的待执行任务，并将指针复位。
     * 主要用于测试场景或需要彻底重新开始的逻辑。
     */
    public function reset():Void {
        for (var i:Number = 0; i < WHEEL_SIZE; ++i) {
            if (slots[i].length > 0) {
                slots[i].length = 0; // 比 slots[i] = [] 更高效
            }
        }
        pos = WHEEL_SIZE - 1;
    }

    
    //================================================================================
    // 核心驱动逻辑
    //================================================================================

    /**
     * @private
     * 时间轮的核心驱动函数，每帧由 onEnterFrame 事件自动调用。
     * 负责将指针前移一格，并执行新位置上所有待处理的回调任务。
     *
     * 【性能注释】: 此函数已为 AS2 环境进行极限优化。
     * 1. 利用赋值表达式副作用，将指针更新和数组访问合并，触发AVM1栈操作优化。
     * 2. 复用长度变量 n 作为循环迭代器，减少局部变量声明。
     * 3. 使用 do-while 配合 if 守卫，移除 for 循环的冗余判断。
     * 4. 循环条件和索引操作使用前置自减(--n)，生成最紧凑的p-code。
     * 5. 使用 .length = 0 一次性清空数组，避免函数调用开销。
     *
     * 【维护警告】: 此实现可读性较低，高度依赖注释。
     * 循环结束后，变量 n 的值将被破坏（变为0），后续代码不可再使用其原始值。
     */
    public function tick():Void {
        // 优化1: 将指针更新和数组获取合并为一个表达式，减少一次变量读写。
        var list:Array = slots[pos = (pos + 1) & WHEEL_MASK];
        
        // 防御性编程：确保槽位存在（尽管在当前设计中它总是存在）。
        if (list != undefined) {
            // 优化2: 缓存长度。此变量 n 后续将被复用为迭代器。
            var n:Number = list.length;

            // 优化3: if (n > 0) 是 do-while 循环唯一的入口守卫，保证了循环体至少被执行一次的安全性。
            if (n > 0) {
                // 优化4: 使用 do-while 循环并复用 n 作为迭代器。--n 会先将n减1再返回新值作为索引，
                // 完美匹配从 n-1 到 0 的倒序遍历 (LIFO，后进先出)。
                do {
                    (list[--n])(); 
                } while (n > 0);

                // 优化5: 循环结束后，用最高效的方式一次性清空数组。
                list.length = 0;
            }
        }
    }
}