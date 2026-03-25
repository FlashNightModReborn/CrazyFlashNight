import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangCache {
    private var _data:Object;
    private var _queue:Array;
    private var _size:Number;
    private var _capacity:Number;
    private var _head:Number;
    private var _tail:Number;

    public function GobangCache(capacity:Number) {
        if (capacity === undefined) capacity = 100000;
        _capacity = capacity;
        _size = 0;
        _head = 0;
        _tail = 0;
        _data = {};
        _data.__proto__ = null;
        _queue = [];
    }

    public function get(key) {
        if (!GobangConfig.enableCache) return null;
        var val = _data[key];
        if (val !== undefined) return val;
        return null;
    }

    public function put(key, value):Void {
        if (!GobangConfig.enableCache) return;
        var existing = _data[key];
        if (existing !== undefined) {
            // depth 优先：新旧都带 depth 时，浅搜不覆盖深搜结果
            if (existing.depth !== undefined && value.depth !== undefined) {
                if (value.depth < existing.depth) return;
            }
            _data[key] = value;
            return;
        }
        if (_capacity <= 0) return;

        if (_size >= _capacity) {
            var oldKey = _queue[_head];
            delete _data[oldKey];
            _queue[_head] = key;
            _head++;
            if (_head >= _capacity) _head = 0;
        } else {
            _queue[_tail] = key;
            _tail++;
            if (_tail >= _capacity) _tail = 0;
            _size++;
        }
        _data[key] = value;
    }

    public function has(key):Boolean {
        if (!GobangConfig.enableCache) return false;
        return _data[key] !== undefined;
    }
}
