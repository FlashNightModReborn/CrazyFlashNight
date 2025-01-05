// File: org/flashNight/gesh/iterator/ObjectIterator.as
import org.flashNight.gesh.iterator.BaseIterator;
import org.flashNight.gesh.iterator.IIterator;
import org.flashNight.gesh.iterator.IterationResult;

/**
 * ObjectIterator 是一个用于遍历对象属性的迭代器。
 */
class org.flashNight.gesh.iterator.ObjectIterator extends BaseIterator implements IIterator {
    private var _keys: Array;   // 存储对象的键
    private var _values: Array; // 存储对象的值

    /**
     * 构造函数
     * @param obj Object 要迭代的对象
     */
    public function ObjectIterator(obj: Object) {
        super(); // 调用父类构造函数
        this._keys = [];
        this._values = [];

        // 遍历对象的键值对，存入数组
        for (var key in obj) {
            if (obj.hasOwnProperty(key)) { // 增强健壮性：只处理自身属性
                this._keys.push(key);
                this._values.push(obj[key]);
            }
        }
    }

    /**
     * 返回下一个迭代结果。
     * @return IterationResult 包含键值对 {key, value} 或 done=true
     */
    public function next(): IterationResult {
        var idx: Number = this.getIndex();
        if (this.hasNext()) {
            var result: Object = {
                key: this._keys[idx],
                value: this._values[idx]
            };
            this.setIndex(idx + 1); // 负责递增索引
            return new IterationResult(result, false);
        }
        return new IterationResult(undefined, true);
    }

    /**
     * 检查是否有下一个元素。
     * @return Boolean 是否还有未迭代的元素
     */
    public function hasNext(): Boolean {
        return this.getIndex() < this._keys.length;
    }

    /**
     * 重置迭代器状态，将索引归零。
     */
    public function reset(): Void {
        super.reset(); // 调用父类的 reset 方法
    }

    /**
     * 显式释放资源，避免循环引用。
     */
    public function dispose(): Void {
        super.dispose(); // 调用父类的 dispose 方法
        this._keys = null;
        this._values = null;
    }
}
