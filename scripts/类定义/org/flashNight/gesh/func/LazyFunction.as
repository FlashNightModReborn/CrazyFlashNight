/**
 * org.flashNight.gesh.func.LazyFunction
 * 延迟初始化函数类。
 * 
 * 该类提供了一种机制，允许在首次调用时执行初始化逻辑，并在初始化完成后将函数调用行为切换为目标函数的直接调用。
 * 
 * @类说明
 * - `LazyFunction` 设计用于性能优化场景，避免重复执行初始化逻辑。
 * - 初始化完成后，`execute` 方法会被替换为目标函数的直接调用。
 * 
 * @作者
 * flashNight
 * 
 * @构造函数
 * LazyFunction(initializer:Function, targetFunction:Function)
 * 
 * @参数
 * @param {Function} initializer - 初始化函数，首次调用时执行，用于完成初始化逻辑。
 * @param {Function} targetFunction - 目标函数，在初始化完成后每次调用时执行。
 * 
 * @异常
 * 如果 `initializer` 或 `targetFunction` 参数不是函数类型，则抛出错误。
 * 
 * @方法
 * execute():Void
 * 
 * @说明
 * - 当首次调用 `execute` 方法时，会执行 `initializer` 初始化逻辑。
 * - 初始化完成后，`execute` 方法会被动态替换为目标函数的直接调用。
 * - 每次调用时，直接将参数传递给目标函数。
 * 
 * @错误处理
 * - 如果 `initializer` 在执行过程中抛出错误，该错误会被捕获并重新抛出。
 */
class org.flashNight.gesh.func.LazyFunction {
    private var initializer:Function;
    private var initialized:Boolean = false;
    private var targetFunction:Function;

    /**
     * 构造函数：创建一个新的 LazyFunction 实例。
     * @param {Function} initializer 初始化函数
     * @param {Function} targetFunction 目标函数
     */
    public function LazyFunction(initializer:Function, targetFunction:Function) {
        if (typeof(initializer) != "function" || typeof(targetFunction) != "function") {
            throw new Error("Invalid parameters: initializer and targetFunction must be functions.");
        }
        this.initializer = initializer;
        this.targetFunction = targetFunction;
    }

    /**
     * 执行方法：延迟初始化并调用目标函数。
     * @方法说明
     * - 如果未初始化，则执行初始化函数，并将 `execute` 替换为目标函数。
     * - 初始化完成后，每次调用直接执行目标函数。
     */
    public function execute():Void {
        if (!initialized) {
            try {
                // 调用初始化函数
                initializer.apply(this, arguments);
                initialized = true;
                // 替换 execute 方法为目标函数
                var self = this;
                this.execute = function() {
                    targetFunction.apply(self, arguments);
                };
            } catch (e:Error) {
                trace("Error during initialization: " + e.message);
                throw e;
            }
        }
        // 调用目标函数
        this.execute.apply(this, arguments);
    }
}
