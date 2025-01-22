import org.flashNight.neur.Event.EventBus;

/**
 * KeyManager 类用于管理键盘键码与键名的映射关系，并提供键值设定的刷新和查询功能。
 * 现在新增对 EventBus 的集成，以实现基于事件的按键按下、释放侦听。
 *
 * @class org.flashNight.arki.key.KeyManager
 * @author fs
 * @version 2.0 (在原有1.0基础上，增加EventBus机制)
 */
class org.flashNight.arki.key.KeyManager {
    /** @private */
    private static var keyMap:Object = KeyManager.init(); // 静态初始化映射表
    /** @private */
    private static var keySettingsCache:Object;

    // === 新增字段 ===
    /** 
     * 存储要监听的按键(只对这些按键做轮询检测)。
     * key: 键码, value: true/false(是否需要监听)
     */
    private static var watchedKeys:Object = {};
    
    /** 
     * 存储按键当前状态(上一次检测时是否处于按下)。
     * key: 键码, value: Boolean (true=按下, false=未按下)
     */
    private static var keyStates:Object = {};

    // 事件总线实例(懒得每次getInstance()，直接缓存)
    private static var eventBus:EventBus = EventBus.getInstance();

    /**
     * 构造函数(无实际意义，静态类)。
     */
    public function KeyManager() {
        trace("KeyManager instance created. (Usually should not be instantiated)");
    }

    /**
     * 初始化键码与键名的映射表，并且设置MovieClip进行按键检测。
     * 在使用 KeyManager 的其他功能前应确保调用一次。
     *
     * @static
     * @return Object 返回内部的keyMap对象
     */
    public static function init():Object {
        // 1. 构建键码->键名映射 (保持原有功能)
        keyMap = {};
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

        // 2. 与 EventBus 整合：在根上创建一个用于轮询按键状态的Clip
        if (_root.keyPollMC == undefined) {
            _root.createEmptyMovieClip("keyPollMC", _root.getNextHighestDepth());
        }
        // 3. 在 onEnterFrame 中轮询
        _root.keyPollMC.onEnterFrame = function() {
            KeyManager.pollKeys();
        };

        trace("[KeyManager] init completed and keyPollMC onEnterFrame set.");

        return keyMap;
    }

    /**
     * 每帧轮询按键状态，只针对 watchedKeys 中的按键。
     * 如果检测到按下/释放切换，则通过 eventBus 发布事件：
     *  - "KeyDown_键名"
     *  - "KeyUp_键名"
     */
    private static function pollKeys():Void {
        for (var keycodeStr:String in watchedKeys) {
            var keycode:Number = Number(keycodeStr);
            var isNowDown:Boolean = Key.isDown(keycode);
            var wasDown:Boolean = (keyStates[keycode] == true);

            if (isNowDown != wasDown) {
                // 状态变化
                keyStates[keycode] = isNowDown; // 更新记录

                // 发布事件
                var keyName:String = getKeyName(keycode); // 原有方法
                if (isNowDown) {
                    // 按下事件
                    eventBus.publish("KeyDown_" + keyName);
                } else {
                    // 释放事件
                    eventBus.publish("KeyUp_" + keyName);
                }
            }
        }
    }

    /**
     * 返回键码对应的键名。
     * @param {Number} keycode
     * @return {String}
     */
    public static function getKeyName(keycode:Number):String {
        return keyMap[keycode] || "";
    }

    /**
     * 添加或更新键码与键名的映射（保留原功能）。
     */
    public static function addKeyMapping(keycode:Number, keyname:String):Void {
        keyMap[keycode] = keyname;
    }

    /**
     * 移除键码与键名的映射（保留原功能）。
     */
    public static function removeKeyMapping(keycode:Number):Void {
        if (keyMap[keycode] != undefined) {
            delete keyMap[keycode];
        }
    }

    /**
     * 检查键码是否存在映射（保留原功能）。
     */
    public static function hasKeyName(keycode:Number):Boolean {
        return keyMap[keycode] != undefined;
    }

    /**
     * 获取所有键码（保留原功能）。
     */
    public static function getAllKeycodes():Array {
        var keycodes:Array = [];
        for (var keycode in keyMap) {
            keycodes.push(Number(keycode));
        }
        return keycodes;
    }

    /**
     * 获取所有键名（保留原功能）。
     */
    public static function getAllKeynames():Array {
        var keynames:Array = [];
        for (var keycode in keyMap) {
            keynames.push(keyMap[keycode]);
        }
        return keynames;
    }

    /**
     * 刷新键值设定，如果键值设定长度小于30会自动添加默认按键。
     * 同时更新缓存字典、可用的按键设置，以及需要监听的按键列表 `watchedKeys`。
     *
     * @param {Array} keySettings - 键值设定数组。元素格式类似 [可显示名称, 唯一标识, keycode]
     * @param {Function} translationFunction - 翻译函数，用于翻译键名。
     * @param {Array} controlSettings - 操控目标按键设定表。例：controlSettings[0] = _root.上键 ...
     */
    public static function refreshKeySettings(keySettings:Array, translationFunction:Function, controlSettings:Array):Void {
        // 1. 如果键值设定长度小于30，添加默认按键（保留原逻辑）
        if (keySettings.length < 30) {
            var newKeys:Array = [
                [translationFunction("互动键"), "互动键", 69],
                [translationFunction("武器技能键"), "武器技能键", 70],
                [translationFunction("飞行键"), "飞行键", 18],
                [translationFunction("武器变形键"), "武器变形键", 81],
                [translationFunction("奔跑键"), "奔跑键", 16]
            ];
            keySettings = keySettings.concat(newKeys);
            _root.键值设定 = keySettings; // 更新全局
        }

        // 2. 初始化缓存字典
        if (!KeyManager.keySettingsCache) {
            KeyManager.keySettingsCache = {};
        } else {
            for (var k in KeyManager.keySettingsCache) {
                delete KeyManager.keySettingsCache[k];
            }
        }

        // 3. 构建缓存字典并更新 _root
        for (var i:Number = 0; i < keySettings.length; i++) {
            var keyName:String = keySettings[i][1];  // "互动键" 等
            var keyValue:Number = keySettings[i][2]; // 69 等
            _root[keyName] = keyValue;
            KeyManager.keySettingsCache[keyName] = keyValue;
        }

        // 4. 更新操控目标按键设定表（保留原逻辑）
        controlSettings[0] = _root.上键;
        controlSettings[1] = _root.下键;
        controlSettings[2] = _root.左键;
        controlSettings[3] = _root.右键;

        // ========== 新增：重新注册要监听的按键 ==========
        // 5. 清空并重新构建 watchedKeys
        for (var kc:String in watchedKeys) {
            delete watchedKeys[kc];
        }

        for (i = 0; i < keySettings.length; i++) {
            var code:Number = keySettings[i][2];
            // 若想让所有列在 keySettings 的按键都被监听，则直接 set true
            // 如果只想监听部分按键，可加筛选逻辑(比如: 只监听“互动键”和“武器技能键”)。
            watchedKeys[code] = true;

            // 顺带初始化 keyStates，避免旧状态干扰
            keyStates[code] = false; 
        }
    }

    /**
     * 根据键名获取对应的键值（保留原功能）。
     */
    public static function getKeySetting(keyName:String):Number {
        return KeyManager.keySettingsCache[keyName];
    }
}
