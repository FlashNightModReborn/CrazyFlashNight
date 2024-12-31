/**
 * 惰性求值类：LazyValue
 * 允许延迟计算，并缓存结果，支持链式调用。
 */
class org.flashNight.gesh.func.LazyValue {
    private var value;                      // 存储计算结果
    private var evaluator:Function;           // 计算逻辑
    private var isEvaluated:Boolean = false;  // 是否已经计算完成

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
     * @return {*} 返回计算结果
     */
    public function get() {
        if (!isEvaluated) {           // 第一次调用时执行计算
            value = evaluator();
            isEvaluated = true;       // 标记为已计算
        }
        return value;                 // 返回结果
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
        isEvaluated = false;  // 重置状态，允许重新计算
    }
}
