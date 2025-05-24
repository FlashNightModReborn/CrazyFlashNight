/**
 * 优化后的惰性求值类：LazyValue
 * 采用函数重定义的方式，减少每次调用get时的判断开销。
 */
class org.flashNight.gesh.func.LazyValue {
    private var value;                // 存储计算结果
    private var evaluator:Function;   // 计算逻辑

    /**
     * 构造函数
     * @param {Function} evaluator 计算函数，用于生成值
     */
    public function LazyValue(evaluator:Function) {
        if (typeof(evaluator) != "function") {
            throw new Error("LazyValue requires a function as an evaluator.");
        }
        this.evaluator = evaluator;
    }

    /**
     * 获取值
     * 第一次调用时执行计算，并重定义get方法以直接返回缓存值。
     * @return {*} 返回计算结果
     */
    public function get() {
        // 执行计算并缓存结果
        value = evaluator();
        // 将get方法重定义为直接返回缓存值的函数
        this.get = function() {
            return value;
        };
        // 清理引用，帮助垃圾回收
        evaluator = null;
        return value;
    }

    /**
     * 转换当前值并返回新的 LazyValue
     * @param {Function} transformer 转换函数，用于处理当前值并生成新的 LazyValue
     * @return {LazyValue} 返回一个新的惰性求值对象
     */
    public function map(transformer:Function):LazyValue {
        var self = this;  // 保持当前实例引用
        return new LazyValue(function() {
            return transformer(self.get());  // 使用当前值进行转换
        });
    }

    /**
     * 强制重新计算值
     * @param {Function} newEvaluator 新计算函数
     * @return {Void}
     */
    public function reset(newEvaluator:Function):Void {
        if (typeof(newEvaluator) == "function") {
            this.evaluator = newEvaluator;  // 替换计算逻辑
        }
        // 将get方法重定义为重新计算的初始状态
        this.get = function() {
            value = evaluator();
            this.get = function() {
                return value;
            };
            evaluator = null;
            return value;
        };
    }
}
