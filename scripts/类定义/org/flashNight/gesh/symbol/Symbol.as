// 文件路径: org/flashNight/gesh/symbol/Symbol.as

import org.flashNight.naki.RandomNumberEngine.MersenneTwister;

class org.flashNight.gesh.symbol.Symbol {
    private var _key: String;
    private var _description: String;

    // 私有静态变量用于全局注册表
    private static var _globalRegistry: Object = {};

    // 静态构造函数
    private static function __static_constructor__(): Void {
        _global.ASSetPropFlags(_globalRegistry, null, 1, false); // 设置为不可枚举
    }

    private static var __static_init__ = __static_constructor__();

    /**
     * 构造函数（完全兼容AS2的UUID v4实现）
     * @param description 描述符，可选
     */
    private function Symbol(description: String) {
        this._description = description || "";
        var mt:MersenneTwister = MersenneTwister.getInstance();
        
        // 补零函数确保固定长度
        function toHex(num:Number, len:Number):String {
            var hex:String = num.toString(16);
            while (hex.length < len) hex = "0" + hex;
            return hex.substring(hex.length - len); // 确保截断超长部分
        }

        // 严格遵循UUID v4规范
        this._key = "Symbol(" + this._description + "):" +
                    toHex(mt.next(), 8) + "-" +
                    toHex(mt.next(), 4) + "-" +
                    toHex((mt.next() & 0x0fff) | 0x4000, 4) + "-" +
                    toHex((mt.next() & 0x3fff) | 0x8000, 4) + "-" +
                    toHex(mt.next(), 4) + toHex(mt.next(), 8);
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
     * 全局注册 Symbol（增强描述符冲突检测）
     * @param key 唯一标识符
     * @param description 描述符，可选
     * @return Symbol 实例
     */
    public static function forKey(key: String, description: String): Symbol {
        if (typeof(key) !== "string") {
            throw new Error("Symbol.forKey: key必须为字符串类型");
        }
        
        if (_globalRegistry[key] === undefined) {
            _globalRegistry[key] = new Symbol(description);
        } else {
            // 严格描述符一致性检查
            var existingDesc:String = _globalRegistry[key].getDescription();
            if (existingDesc !== description) {
                throw new Error("Symbol.forKey: 描述符冲突，key '" + key + "' 已存在");
            }
        }
        return _globalRegistry[key];
    }

    /**
     * 删除全局注册的 Symbol（增强类型检查）
     * @param key 唯一标识符
     * @return Boolean 是否成功删除
     */
    public static function deleteSymbol(key: String): Boolean {
        if (typeof(key) !== "string") {
            throw new Error("Symbol.deleteSymbol: key必须为字符串类型");
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
     * 获取 Symbol 的字符串表示
     * @return 字符串表示
     */
    public function toString(): String {
        return "Symbol(" + this._description + ")";
    }

    /**
     * 比较两个 Symbol 是否相同（强化类型安全）
     * @param other 另一个 Symbol
     * @return 是否相同
     */
    public function equals(other: Symbol): Boolean {
        if (other == null) {
            throw new Error("Symbol.equals()参数不能为null");
        }
        if (!(other instanceof Symbol)) {
            throw new Error("Symbol.equals()参数类型必须为Symbol");
        }
        return this._key === other._key;
    }

    /**
     * 调试用方法：获取内部_key值
     * @return 内部唯一标识符
     */
    public function getKey():String {
        return this._key;
    }
}