/**
 * KeyManager 类用于管理键盘键码与键名的映射关系，并提供键值设定的刷新和查询功能。
 * 该类为静态类，所有方法和属性均为静态，无需实例化即可使用。
 * 
 * @class org.flashNight.arki.key.KeyManager
 * @author 作者名
 * @version 1.0
 * @date 创建日期
 */
class org.flashNight.arki.key.KeyManager {
    /**
     * 静态属性：存储键码与键名的映射关系。
     * 键为键码（Number），值为键名（String）。
     * @private
     * @static
     * @type Object
     */
    private static var keyMap:Object;

    /**
     * 静态属性：缓存键值设定，用于快速查询键名对应的键值。
     * 键为键名（String），值为键值（Number）。
     * @private
     * @static
     * @type Object
     */
    private static var keySettingsCache:Object;

    /**
     * 构造函数。初始化 KeyManager 时输出调试信息。
     * @constructor
     */
    public function KeyManager() {
        trace("KeyManager initialized.");
    }

    /**
     * 静态方法：初始化键码与键名的映射表。
     * 该方法应在使用 KeyManager 其他功能前调用。
     * @static
     * @return Void
     */
    public static function init():Void {
        keyMap = new Object();

        // 初始化键码与键名的映射
        keyMap[8] = "Backspace";
        keyMap[9] = "Tab";
        keyMap[12] = "Clear";
        keyMap[13] = "Enter";
        keyMap[16] = "Shift";
        keyMap[17] = "Control";
        keyMap[18] = "Alt";
        keyMap[20] = "Caps Lock";
        keyMap[27] = "Esc";
        keyMap[32] = "Spacebar";
        keyMap[33] = "Page Up";
        keyMap[34] = "Page Down";
        keyMap[35] = "End";
        keyMap[36] = "Home";
        keyMap[37] = "左方向键";
        keyMap[38] = "上方向键";
        keyMap[39] = "右方向键";
        keyMap[40] = "下方向键";
        keyMap[45] = "Insert";
        keyMap[46] = "Delete";
        keyMap[47] = "Help";
        keyMap[48] = "0";
        keyMap[49] = "1";
        keyMap[50] = "2";
        keyMap[51] = "3";
        keyMap[52] = "4";
        keyMap[53] = "5";
        keyMap[54] = "6";
        keyMap[55] = "7";
        keyMap[56] = "8";
        keyMap[57] = "9";
        keyMap[65] = "A";
        keyMap[66] = "B";
        keyMap[67] = "C";
        keyMap[68] = "D";
        keyMap[69] = "E";
        keyMap[70] = "F";
        keyMap[71] = "G";
        keyMap[72] = "H";
        keyMap[73] = "I";
        keyMap[74] = "J";
        keyMap[75] = "K";
        keyMap[76] = "L";
        keyMap[77] = "M";
        keyMap[78] = "N";
        keyMap[79] = "O";
        keyMap[80] = "P";
        keyMap[81] = "Q";
        keyMap[82] = "R";
        keyMap[83] = "S";
        keyMap[84] = "T";
        keyMap[85] = "U";
        keyMap[86] = "V";
        keyMap[87] = "W";
        keyMap[88] = "X";
        keyMap[89] = "Y";
        keyMap[90] = "Z";
        keyMap[96] = "Num0";
        keyMap[97] = "Num1";
        keyMap[98] = "Num2";
        keyMap[99] = "Num3";
        keyMap[100] = "Num4";
        keyMap[101] = "Num5";
        keyMap[102] = "Num6";
        keyMap[103] = "Num7";
        keyMap[104] = "Num8";
        keyMap[105] = "Num9";
        keyMap[106] = "*";
        keyMap[107] = "+";
        keyMap[108] = "Enter";
        keyMap[109] = "_";
        keyMap[110] = ".";
        keyMap[111] = "/";
        keyMap[112] = "F1";
        keyMap[113] = "F2";
        keyMap[114] = "F3";
        keyMap[115] = "F4";
        keyMap[116] = "F5";
        keyMap[117] = "F6";
        keyMap[118] = "F7";
        keyMap[119] = "F8";
        keyMap[120] = "F9";
        keyMap[121] = "F10";
        keyMap[122] = "F11";
        keyMap[123] = "F12";
        keyMap[144] = "Num Lock";
        keyMap[186] = ";:";
        keyMap[187] = "=+";
        keyMap[189] = "-_";
        keyMap[191] = "/?";
        keyMap[192] = "`~";
        keyMap[219] = "[{";
        keyMap[220] = "\\|";
        keyMap[221] = "]}";
        keyMap[222] = "‘”";
    }

    /**
     * 静态方法：根据键码获取对应的键名。
     * @static
     * @param {Number} keycode - 键码。
     * @return {String} 键名，如果键码不存在则返回空字符串。
     */
    public static function getKeyName(keycode:Number):String {
        return keyMap[keycode] || "";
    }

    /**
     * 静态方法：添加或更新键码与键名的映射。
     * @static
     * @param {Number} keycode - 键码。
     * @param {String} keyname - 键名。
     * @return Void
     */
    public static function addKeyMapping(keycode:Number, keyname:String):Void {
        keyMap[keycode] = keyname;
    }

    /**
     * 静态方法：移除键码与键名的映射。
     * @static
     * @param {Number} keycode - 键码。
     * @return Void
     */
    public static function removeKeyMapping(keycode:Number):Void {
        if (keyMap[keycode] != undefined) {
            delete keyMap[keycode];
        }
    }

    /**
     * 静态方法：检查键码是否存在映射。
     * @static
     * @param {Number} keycode - 键码。
     * @return {Boolean} 如果键码存在映射则返回 true，否则返回 false。
     */
    public static function hasKeyName(keycode:Number):Boolean {
        return keyMap[keycode] != undefined;
    }

    /**
     * 静态方法：获取所有键码。
     * @static
     * @return {Array} 包含所有键码的数组。
     */
    public static function getAllKeycodes():Array {
        var keycodes:Array = [];
        for (var keycode in keyMap) {
            keycodes.push(Number(keycode));
        }
        return keycodes;
    }

    /**
     * 静态方法：获取所有键名。
     * @static
     * @return {Array} 包含所有键名的数组。
     */
    public static function getAllKeynames():Array {
        var keynames:Array = [];
        for (var keycode in keyMap) {
            keynames.push(keyMap[keycode]);
        }
        return keynames;
    }

    /**
     * 静态方法：刷新键值设定。
     * 如果键值设定长度小于 30，会自动添加默认按键。
     * 同时会更新缓存字典和操控目标按键设定表。
     * @static
     * @param {Array} keySettings - 键值设定数组。
     * @param {Function} translationFunction - 翻译函数，用于翻译键名。
     * @param {Array} controlSettings - 操控目标按键设定表。
     * @return Void
     */
    public static function refreshKeySettings(keySettings:Array, translationFunction:Function, controlSettings:Array):Void {
        // 如果键值设定长度小于30，添加默认按键
        if (keySettings.length < 30) {
            var newKeys:Array = [
                [translationFunction("互动键"), "互动键", 69],
                [translationFunction("武器技能键"), "武器技能键", 70],
                [translationFunction("飞行键"), "飞行键", 18],
                [translationFunction("武器变形键"), "武器变形键", 81],
                [translationFunction("奔跑键"), "奔跑键", 16]
            ];
            keySettings = keySettings.concat(newKeys);
            // 更新全局变量，可能需要设置回 _root.键值设定
            _root.键值设定 = keySettings;
        }

        // 初始化缓存字典
        if (!KeyManager.keySettingsCache) {
            KeyManager.keySettingsCache = new Object();
        } else {
            // 清空缓存字典
            for (var key in KeyManager.keySettingsCache) {
                delete KeyManager.keySettingsCache[key];
            }
        }

        // 构建缓存字典
        for (var i:Number = 0; i < keySettings.length; i++) {
            var keyName:String = keySettings[i][1];
            var keyValue:Number = keySettings[i][2];
            _root[keyName] = keyValue; // 设置键值
            KeyManager.keySettingsCache[keyName] = keyValue; // 存入缓存
        }

        // 更新操控目标按键设定表
        controlSettings[0] = _root.上键;
        controlSettings[1] = _root.下键;
        controlSettings[2] = _root.左键;
        controlSettings[3] = _root.右键;
    }

    /**
     * 静态方法：根据键名获取对应的键值。
     * @static
     * @param {String} keyName - 键名。
     * @return {Number} 键值，如果键名不存在则返回 undefined。
     */
    public static function getKeySetting(keyName:String):Number {
        return KeyManager.keySettingsCache[keyName];
    }
}