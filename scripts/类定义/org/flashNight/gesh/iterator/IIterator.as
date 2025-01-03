interface org.flashNight.gesh.iterator.IIterator {
    /**
     * 返回迭代的下一个结果。
     * @return IterationResult
     */
    function next(): org.flashNight.gesh.iterator.IterationResult;

    /**
     * 检查是否有更多元素可以迭代。
     * @return Boolean 是否有下一个元素
     */
    function hasNext(): Boolean;

    /**
     * 重置迭代器状态。
     */
    function reset(): Void;

    /**
     * 显式释放资源，用于避免循环引用。
     */
    function dispose(): Void;
}
