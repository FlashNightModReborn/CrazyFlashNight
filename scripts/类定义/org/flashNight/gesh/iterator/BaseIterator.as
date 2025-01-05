// File: org/flashNight/gesh/iterator/BaseIterator.as
import org.flashNight.gesh.iterator.IIterator;
import org.flashNight.gesh.iterator.IterationResult;

/**
 * BaseIterator 是 IIterator 接口的基础实现，提供了核心迭代功能和 ES6 风格的拓展方法。
 * 子类应继承此类并实现具体的迭代逻辑。
 */
class org.flashNight.gesh.iterator.BaseIterator implements IIterator {
    // 当前迭代的索引
    private var _index: Number;

    /**
        * 构造函数，初始化索引为 0。
        */
    public function BaseIterator() {
        this._index = 0;
    }

    /**
        * 返回下一个迭代结果。
        * 默认实现返回 done=true，表示没有更多元素。
        * 子类应重写此方法以提供具体的迭代逻辑。
        * @return IterationResult 下一个元素及其完成状态
        */
    public function next(): IterationResult {
        return new IterationResult(undefined, true);
    }

    /**
        * 检查是否有下一个元素。
        * 默认实现返回 false，表示迭代已结束。
        * 子类应重写此方法以提供具体的检查逻辑。
        * @return Boolean 是否存在下一个元素
        */
    public function hasNext(): Boolean {
        return false;
    }

    /**
        * 重置迭代器的索引到初始位置。
        */
    public function reset(): Void {
        this._index = 0;
    }

    /**
        * 显式释放资源，避免循环引用。
        */
    public function dispose(): Void {
        this._index = null;
    }

    /**
        * 获取当前的索引。
        * @return Number 当前迭代的索引
        */
    public function getIndex(): Number {
        return this._index;
    }

    /**
        * 设置当前的索引。
        * 包含边界检查，确保索引为非负有效数字。
        * @param value Number 要设置的索引值
        */
    public function setIndex(value: Number): Void {
        if (isNaN(value) || value < 0) {
            trace("Warning: Invalid index value provided to setIndex. Resetting to 0.");
            this._index = 0;
        } else {
            this._index = value;
        }
    }

    /**
        * 对每个元素执行回调函数。
        * @param callback Function 回调函数，接受参数 (value, index)
        */
    public function forEach(callback: Function): Void {
        if (typeof(callback) !== "function") {
            trace("Error: forEach expects a function as its argument.");
            return;
        }

        this.reset();
        var result: IterationResult;
        try {
            while (this.hasNext()) {
                result = this.next();
                callback(result._value, this.getIndex());
                // 移除了这里的索引递增
            }
        } catch (e: Error) {
            trace("Error in forEach callback: " + e.message);
        }
    }

    /**
        * 映射迭代器的每个元素到一个新数组。
        * @param callback Function 回调函数，接受参数 (value, index)
        * @return Array 映射后的新数组
        */
    public function map(callback: Function): Array {
        if (typeof(callback) !== "function") {
            trace("Error: map expects a function as its argument.");
            return [];
        }

        var mappedArray: Array = [];
        this.reset();
        var result: IterationResult;
        try {
            while (this.hasNext()) {
                result = this.next();
                mappedArray.push(callback(result._value, this.getIndex()));
                // 移除了这里的索引递增
            }
        } catch (e: Error) {
            trace("Error in map callback: " + e.message);
        }
        return mappedArray;
    }

    /**
        * 过滤迭代器的元素，返回满足条件的元素组成的新数组。
        * @param callback Function 回调函数，接受参数 (value, index) 并返回 Boolean
        * @return Array 过滤后的新数组
        */
    public function filter(callback: Function): Array {
        if (typeof(callback) !== "function") {
            trace("Error: filter expects a function as its argument.");
            return [];
        }

        var filteredArray: Array = [];
        this.reset();
        var result: IterationResult;
        try {
            while (this.hasNext()) {
                result = this.next();
                if (callback(result._value, this.getIndex())) {
                    filteredArray.push(result._value);
                }
                // 移除了这里的索引递增
            }
        } catch (e: Error) {
            trace("Error in filter callback: " + e.message);
        }
        return filteredArray;
    }

    /**
        * 查找第一个满足条件的元素。
        * @param callback Function 回调函数，接受参数 (value, index) 并返回 Boolean
        * @return * 满足条件的元素或 undefined
        */
    public function find(callback: Function) {
        if (typeof(callback) !== "function") {
            trace("Error: find expects a function as its argument.");
            return undefined;
        }

        this.reset();
        var result: IterationResult;
        try {
            while (this.hasNext()) {
                result = this.next();
                if (callback(result._value, this.getIndex())) {
                    return result._value;
                }
                // 移除了这里的索引递增
            }
        } catch (e: Error) {
            trace("Error in find callback: " + e.message);
        }
        return undefined;
    }

    /**
        * 将迭代器的元素通过累加器函数减少为单一值。
        * @param callback Function 累加器函数，接受参数 (accumulator, value, index)
        * @param initialValue * 初始值
        * @return * 累加后的最终值
        */
    public function reduce(callback: Function, initialValue){
        if (typeof(callback) !== "function") {
            trace("Error: reduce expects a function as its first argument.");
            return initialValue;
        }

        var accumulator= initialValue;
        this.reset();
        var result: IterationResult;
        try {
            while (this.hasNext()) {
                result = this.next();
                accumulator = callback(accumulator, result._value, this.getIndex());
                // 移除了这里的索引递增
            }
        } catch (e: Error) {
            trace("Error in reduce callback: " + e.message);
        }
        return accumulator;
    }

    /**
        * 检查是否有至少一个元素满足条件。
        * @param callback Function 回调函数，接受参数 (value, index) 并返回 Boolean
        * @return Boolean 是否存在满足条件的元素
        */
    public function some(callback: Function): Boolean {
        if (typeof(callback) !== "function") {
            trace("Error: some expects a function as its argument.");
            return false;
        }

        this.reset();
        var result: IterationResult;
        try {
            while (this.hasNext()) {
                result = this.next();
                if (callback(result._value, this.getIndex())) {
                    return true;
                }
                // 移除了这里的索引递增
            }
        } catch (e: Error) {
            trace("Error in some callback: " + e.message);
        }
        return false;
    }

    /**
        * 检查所有元素是否都满足条件。
        * @param callback Function 回调函数，接受参数 (value, index) 并返回 Boolean
        * @return Boolean 是否所有元素都满足条件
        */
    public function every(callback: Function): Boolean {
        if (typeof(callback) !== "function") {
            trace("Error: every expects a function as its argument.");
            return false;
        }

        this.reset();
        var result: IterationResult;
        try {
            while (this.hasNext()) {
                result = this.next();
                if (!callback(result._value, this.getIndex())) {
                    return false;
                }
                // 移除了这里的索引递增
            }
        } catch (e: Error) {
            trace("Error in every callback: " + e.message);
        }
        return true;
    }
}

