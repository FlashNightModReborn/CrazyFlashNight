// 文件路径: org/flashNight/gesh/symbol/Symbol.as

import org.flashNight.naki.RandomNumberEngine.MersenneTwister;

class org.flashNight.gesh.symbol.Symbol {
    private var _key: String;
    private var _description: String;

    // 私有静态变量用于全局注册表
    private static var _globalRegistry: Object = {};

    // 静态构造函数
    private static function __static_constructor__(): Void {
        _global.ASSetPropFlags(_globalRegistry, null, 1, 0); // 设置为不可枚举
    }

    private static var __static_init__ = __static_constructor__();

    /**
     * 构造函数
     * @param description 描述符，可选
     */
    private function Symbol(description: String) {
        this._description = description || "";
        var mt:MersenneTwister = MersenneTwister.getInstance();
        this._key = "Symbol(" + this._description + "):" +
                    mt.next().toString(16) + "-" +
                    mt.next().toString(16) + "-" +
                    (mt.next() & 0x0fff | 0x4000).toString(16) + "-" +
                    (mt.next() & 0x3fff | 0x8000).toString(16) + "-" +
                    mt.next().toString(16) + mt.next().toString(16);
    }

    /**
     * 创建一个新的 Symbol
     * @param description 描述符，可选
     * @return Symbol 实例
     */
    public static function create(description: String): Symbol {
        return new Symbol(description);
    }

    /**
     * 全局注册 Symbol
     * @param key 唯一标识符
     * @param description 描述符，可选
     * @return Symbol 实例
     */
    public static function forKey(key: String, description: String): Symbol {
        if (typeof(key) !== "string") {
            throw new Error("Symbol.forKey: key must be a string.");
        }
        if (_globalRegistry[key] === undefined) {
            _globalRegistry[key] = new Symbol(description);
        }
        return _globalRegistry[key];
    }

    /**
     * 删除全局注册的 Symbol
     * @param key 唯一标识符
     * @return Boolean 是否成功删除
     */
    public static function deleteSymbol(key: String): Boolean {
        if (typeof(key) !== "string") {
            throw new Error("Symbol.deleteSymbol: key must be a string.");
        }
        if (_globalRegistry[key] !== undefined) {
            delete _globalRegistry[key];
            return true;
        }
        return false;
    }

    /**
     * 获取 Symbol 的描述符
     * @return 描述符
     */
    public function getDescription(): String {
        return this._description;
    }

    /**
     * 获取 Symbol 的唯一 key
     * @return 唯一 key
     */
    public function toString(): String {
        return "Symbol(" + this._description + ")";
    }

    /**
     * 比较两个 Symbol 是否相同
     * @param other 另一个 Symbol
     * @return 是否相同
     */
    public function equals(other: Symbol): Boolean {
        if (other == null || !(other instanceof Symbol)) {
            return false;
        }
        return this._key === other._key;
    }
}