import org.flashNight.gesh.iterator.BaseIterator;
import org.flashNight.gesh.iterator.IIterator;
import org.flashNight.gesh.iterator.IterationResult;

class org.flashNight.gesh.iterator.ArrayIterator extends BaseIterator {
    private var _data: Array;

    public function ArrayIterator(data: Array) {
        super();          // 调用父类构造
        this._data = data;
    }

    public function next(): IterationResult {
        var idx: Number = this.getIndex();
        if (this.hasNext()) {
            this.setIndex(idx + 1);
            return new IterationResult(this._data[idx], false);
        }
        return new IterationResult(undefined, true);
    }

    public function hasNext(): Boolean {
        return this.getIndex() < this._data.length;
    }

    /**
     * 释放资源，避免循环引用
     */
    public function dispose(): Void {
        super.dispose();  // 调用父类的 dispose
        this._data = null;
    }
}
