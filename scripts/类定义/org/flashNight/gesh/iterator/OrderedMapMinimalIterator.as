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
    private var _result:IterationResult;          // 复用的结果对象
    private var _entry:Object;                    // 复用的键值对对象

    /**
     * 构造函数
     * @param map 要迭代的OrderedMap实例
     */
    public function OrderedMapMinimalIterator(map:OrderedMap) {
        this._map = map;
        this._initialVersion = map.getVersion();
        // 预创建复用对象
        this._result = new IterationResult(null, false);
        this._entry = { key: null, value: null };
        // 延迟初始化键迭代器
        reset(); // 调用 reset() 初始化 _keyIterator
    }

    /**
     * 获取下一个迭代结果
     * @return IterationResult 包含键值对或结束标志
     *
     * 【优化说明】
     * 复用 _result 和 _entry 对象，避免每次调用都创建新对象。
     * 注意：调用方不应缓存返回的对象，因为下次 next() 会覆盖其内容。
     */
    public function next():IterationResult {
        checkConcurrentModification();
        var keyResult:IterationResult = _keyIterator.next();
        var result:IterationResult = this._result;

        if (keyResult._done) {
            result._value = undefined;
            result._done = true;
            return result;
        }

        var k = keyResult._value;
        var entry:Object = this._entry;
        entry.key = k;
        entry.value = _map.get(k);

        result._value = entry;
        result._done = false;
        return result;
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
        _result = null;
        _entry = null;
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
