class org.flashNight.gesh.iterator.IterationResult {
    public var _value: Object;  // 当前迭代的值
    public var _done: Boolean;  // 是否完成迭代

    /**
     * 构造函数
     * @param value 迭代值
     * @param done 是否完成迭代
     */
    public function IterationResult(value: Object, done: Boolean) {
        this._value = value;
        this._done = done;
    }

    /**
     * 获取迭代的值
     */
    public function getValue(): Object {
        return this._value;
    }

    /**
     * 判断迭代是否完成
     */
    public function isDone(): Boolean {
        return this._done;
    }

    public function toString(): String {
        return "[IterationResult value=" + this._value + ", done=" + this._done + "]";
    }
}
