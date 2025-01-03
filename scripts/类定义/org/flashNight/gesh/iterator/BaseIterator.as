import org.flashNight.gesh.iterator.IIterator;
import org.flashNight.gesh.iterator.IterationResult;

class org.flashNight.gesh.iterator.BaseIterator implements IIterator {
    private var _index: Number;

    public function BaseIterator() {
        this._index = 0;
    }

    /**
     * 默认 next() 实现：返回 done=true
     */
    public function next(): IterationResult {
        return new IterationResult(undefined, true);
    }

    /**
     * 默认返回 false，表示无元素可迭代。
     */
    public function hasNext(): Boolean {
        return false;
    }

    /**
     * 将 index 重置为 0
     */
    public function reset(): Void {
        this._index = 0;
    }

    /**
     * 显式释放资源，避免循环引用
     */
    public function dispose(): Void {
        this._index = null;
    }

    /**
     * getter / setter for _index
     */
    public function getIndex(): Number {
        return this._index;
    }
    public function setIndex(value: Number): Void {
        this._index = value;
    }
}
