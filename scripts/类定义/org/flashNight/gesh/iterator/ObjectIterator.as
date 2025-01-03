import org.flashNight.gesh.iterator.BaseIterator;
import org.flashNight.gesh.iterator.IIterator;
import org.flashNight.gesh.iterator.IterationResult;

class org.flashNight.gesh.iterator.ObjectIterator extends BaseIterator {
    private var _keys: Array;
    private var _values: Array;

    public function ObjectIterator(obj: Object) {
        super();
        this._keys = [];
        this._values = [];

        for (var key in obj) {
            this._keys.push(key);
            this._values.push(obj[key]);
        }
    }

    public function next(): IterationResult {
        var idx: Number = this.getIndex();
        if (this.hasNext()) {
            var result: Object = {
                key: this._keys[idx],
                value: this._values[idx]
            };
            this.setIndex(idx + 1);
            return new IterationResult(result, false);
        }
        return new IterationResult(undefined, true);
    }

    public function hasNext(): Boolean {
        return this.getIndex() < this._keys.length;
    }

    /**
     * 重置迭代器状态
     */
    public function reset(): Void {
        super.reset();
    }

    /**
     * 释放资源，避免循环引用
     */
    public function dispose(): Void {
        super.dispose();
        this._keys = null;
        this._values = null;
    }
}
