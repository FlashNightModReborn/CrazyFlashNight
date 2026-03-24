import org.flashNight.hana.Gobang.GobangConfig;

class org.flashNight.hana.Gobang.GobangCache {
    private var _data:Object;
    private var _queue:Array;
    private var _size:Number;
    private var _capacity:Number;

    public function GobangCache(capacity:Number) {
        if (capacity === undefined) capacity = 100000;
        _capacity = capacity;
        _size = 0;
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
        if (_size >= _capacity) {
            var oldKey = _queue.shift();
            delete _data[oldKey];
            _size--;
        }
        if (_data[key] === undefined) {
            _queue.push(key);
            _size++;
        }
        _data[key] = value;
    }

    public function has(key):Boolean {
        if (!GobangConfig.enableCache) return false;
        return _data[key] !== undefined;
    }
}