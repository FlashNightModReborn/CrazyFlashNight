import org.flashNight.gesh.iterator.BaseIterator;
import org.flashNight.gesh.iterator.IIterator;
import org.flashNight.gesh.iterator.IterationResult;

class org.flashNight.gesh.iterator.ArrayIterator extends BaseIterator implements IIterator {
    private var _data: Array;

    /**
        * 构造函数，接受一个数组作为迭代对象。
        * @param data Array 要迭代的数组
        */
    public function ArrayIterator(data: Array) {
        super();          // 调用父类构造
        this._data = data;
    }

    /**
        * 检查是否有下一个元素。
        * @return Boolean 是否存在下一个元素
        */
    public function hasNext(): Boolean {
        return this.getIndex() < this._data.length;
    }

    /**
        * 返回下一个迭代结果，并递增索引。
        * @return IterationResult 下一个元素及其完成状态
        */
    public function next(): IterationResult {
        var idx: Number = this.getIndex();
        if (this.hasNext()) {
            this.setIndex(idx + 1); // 递增索引
            return new IterationResult(this._data[idx], false);
        }
        return new IterationResult(undefined, true);
    }

    /**
        * 显式释放资源，避免循环引用。
        */
    public function dispose(): Void {
        super.dispose();  // 调用父类的 dispose
        this._data = null;
    }
}

