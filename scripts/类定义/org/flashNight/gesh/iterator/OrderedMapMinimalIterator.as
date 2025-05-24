// OrderedMapMinimalIterator.as
import org.flashNight.gesh.iterator.BaseIterator;
import org.flashNight.gesh.iterator.IIterator;
import org.flashNight.gesh.iterator.IterationResult;
import org.flashNight.naki.DataStructures.OrderedMap;
import org.flashNight.gesh.iterator.TreeSetMinimalIterator;

/**
 * @class OrderedMapMinimalIterator
 * @package org.flashNight.gesh.iterator
 * @description 基于TreeSetMinimalIterator实现的有序映射迭代器，支持结构修改检测
 */
class org.flashNight.gesh.iterator.OrderedMapMinimalIterator extends BaseIterator implements IIterator {
    private var _map:OrderedMap;                  // 关联的OrderedMap实例
    private var _keyIterator:TreeSetMinimalIterator; // 键集合迭代器
    private var _initialVersion:Number;           // 迭代器创建时的版本号

    /**
     * 构造函数
     * @param map 要迭代的OrderedMap实例
     */
    public function OrderedMapMinimalIterator(map:OrderedMap) {
        this._map = map;
        this._initialVersion = map.getVersion();
        // 延迟初始化键迭代器
        reset(); // 调用 reset() 初始化 _keyIterator
    }

    /**
     * 获取下一个迭代结果
     * @return IterationResult 包含键值对或结束标志
     */
    public function next():IterationResult {
        checkConcurrentModification();
        var keyResult:IterationResult = _keyIterator.next();
        if (keyResult._done) {
            return new IterationResult(undefined, true);
        }

        var v = keyResult._value;
        return new IterationResult({
            key: v,
            value: _map.get(v)
        }, false);
    }

    /**
     * 检查是否还有更多元素
     * @return Boolean 存在未迭代元素返回true
     */
    public function hasNext():Boolean {
        checkConcurrentModification();
        return _keyIterator.hasNext();
    }

    /**
     * 重置迭代器到初始状态
     */
    public function reset():Void {
        // 强制刷新键集合迭代器和版本号
        this._keyIterator = new TreeSetMinimalIterator(_map.getKeySet());
        this._initialVersion = _map.getVersion(); // 同步最新版本号
        _keyIterator.reset();
    }


    /**
     * 释放资源
     */
    public function dispose():Void {
        _keyIterator.dispose();
        _map = null;
    }

    /**
     * 检查并发修改
     * @throws Error 检测到结构修改时抛出异常
     */
    private function checkConcurrentModification():Void {
        if (_map.getVersion() != _initialVersion) {
            throw new Error("ConcurrentModificationError: OrderedMap在迭代期间被修改");
        }
    }

}
