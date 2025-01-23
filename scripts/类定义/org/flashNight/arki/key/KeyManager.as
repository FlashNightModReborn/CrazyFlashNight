import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.object.*;

/**
 * KeyManager 类用于管理键盘键码与键名的映射关系，并提供键值设定的刷新和查询功能。
 * 在原有基础上，集成 EventBus，实现基于事件的按键：
 *   - 按下/松开 (KeyDown/KeyUp)
 *   - 长按 (LongPress)
 *   - 组合键 (Combination)
 *   - 双击 (DoubleTap)
 *   - 重复 (Repeat)
 * 并提供按键状态查询接口 (isKeyDown)。
 *
 * @class org.flashNight.arki.key.KeyManager
 * @author fs
 * @version 2.0
 */
class org.flashNight.arki.key.KeyManager {
    //============================
    // 原有字段
    //============================
    /** @private */
    private static var keyMap:Object = KeyManager.init(); // 静态初始化映射表
    /** @private */
    private static var keySettingsCache:Object;

    /**
     * 存储要监听的按键(只对这些按键做轮询检测)。
     * key: 键码, value: Boolean (是否需要监听)
     */
    private static var watchedKeys:Object = {};
    /**
     * 存储每个键码对应的“唯一标识”(keyName)，在发布事件时需要用它拼接事件名
     */
    private static var watchedKeyNames:Object = {};
    /**
     * 存储按键当前状态(上一次检测时是否处于按下)。
     * key: 键码, value: Boolean (true=按下, false=未按下)
     */
    private static var keyStates:Object = {};

    // 事件总线实例
    private static var eventBus:EventBus = EventBus.getInstance();

    //============================
    // 新增字段：长按 / 组合键 / 双击 / 重复 / 状态
    //============================

    // --- LongPress ---
    private static var hasLongPress:Boolean = false;
    private static var longPressConfigs:Object = {}; 
    // 形如: longPressConfigs[keyCode] = { threshold:Number, startTime:Number, triggered:Boolean }

    // --- Combination ---
    private static var hasCombination:Boolean = false;
    private static var combinationConfigs:Array = []; 
    // 形如: { combinationName:"Ctrl+C", keyCodes:[17,67], continuous:false, active:false }

    // --- DoubleTap ---
    private static var hasDoubleTap:Boolean = false;
    private static var doubleTapConfigs:Object = {}; 
    // 形如: doubleTapConfigs[keyCode] = { interval:Number, lastTapTime:Number }

    // --- Repeat ---
    private static var hasRepeat:Boolean = false;
    private static var repeatConfigs:Object = {};
    // 形如: repeatConfigs[keyCode] = { interval:Number, lastTriggerTime:Number }


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

        // 2. 与 EventBus 整合：在 _root 上创建一个用于轮询按键状态的 Clip
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
     * 如果检测到按下/释放切换，则通过 eventBus 发布：
     *   KeyDown_键名 / KeyUp_键名
     * 额外还会根据是否订阅 LongPress / Combination / DoubleTap / Repeat 等进行检测。
     */
    private static function pollKeys():Void {
        var nowTime:Number = getTimer(); // 取当前时间(毫秒)，AS2可用getTimer()；若需帧计数，可自行实现

        //==============================
        // 1) 检测基础按下/松开
        //==============================
        for (var keycodeStr:String in watchedKeys) {
            var keycode:Number = Number(keycodeStr);
            var isNowDown:Boolean = Key.isDown(keycode);
            var wasDown:Boolean = (keyStates[keycode] == true);

            if (isNowDown != wasDown) {
                // 状态变化
                keyStates[keycode] = isNowDown; // 更新记录
                var keyName:String = watchedKeyNames[keycode];
                var eventName:String = (isNowDown ? "KeyDown_" : "KeyUp_") + keyName;
                eventBus.publish(eventName);

                //=== 如果是按下 ===
                if (isNowDown) {
                    // DoubleTap
                    if (hasDoubleTap && doubleTapConfigs[keycode]) {
                        var cfgD:Object = doubleTapConfigs[keycode];
                        if (cfgD.lastTapTime > 0 && (nowTime - cfgD.lastTapTime) <= cfgD.interval) {
                            // 触发双击
                            eventBus.publish("DoubleTap_" + keyName);
                            // 重置，避免多次叠加
                            cfgD.lastTapTime = -1;
                        } else {
                            cfgD.lastTapTime = nowTime;
                        }
                    }
                    // LongPress: 重置标记
                    if (hasLongPress && longPressConfigs[keycode]) {
                        var cfgL:Object = longPressConfigs[keycode];
                        cfgL.startTime = nowTime;
                        cfgL.triggered = false;
                    }
                    // Repeat: 重置触发时间
                    if (hasRepeat && repeatConfigs[keycode]) {
                        var cfgR:Object = repeatConfigs[keycode];
                        cfgR.lastTriggerTime = nowTime;
                        // 如果需要立即触发一次，可在此publish
                        // eventBus.publish("Repeat_" + keyName);
                    }
                }
                //=== 如果是松开 ===
                else {
                    // LongPress: 释放后重置
                    if (hasLongPress && longPressConfigs[keycode]) {
                        var cfgL2:Object = longPressConfigs[keycode];
                        cfgL2.startTime = -1;
                        cfgL2.triggered = false;
                    }
                }
            }
        }

        //==============================
        // 2) 长按检测
        //==============================
        if (hasLongPress) {
            for (var lCodeStr:String in longPressConfigs) {
                var lCode:Number = Number(lCodeStr);
                if (keyStates[lCode]) { // 按住中
                    var lCfg:Object = longPressConfigs[lCode];
                    if (!lCfg.triggered && lCfg.startTime >= 0) {
                        var elapsed:Number = nowTime - lCfg.startTime;
                        if (elapsed >= lCfg.threshold) {
                            var ln:String = watchedKeyNames[lCode];
                            eventBus.publish("LongPress_" + ln);
                            lCfg.triggered = true; // 避免重复触发
                        }
                    }
                }
            }
        }

        //==============================
        // 3) 组合键检测
        //==============================
        if (hasCombination && combinationConfigs.length > 0) {
            for (var i:Number = 0; i < combinationConfigs.length; i++) {
                var combo:Object = combinationConfigs[i];
                var codes:Array = combo.keyCodes;
                var allPressed:Boolean = true;
                for (var j:Number = 0; j < codes.length; j++) {
                    if (!keyStates[codes[j]]) {
                        allPressed = false;
                        break;
                    }
                }
                if (allPressed) {
                    // 若已经全部按下
                    if (combo.continuous) {
                        // 每帧触发
                        eventBus.publish("Combination_" + combo.combinationName);
                    } else {
                        // 只从不满足->满足时触发一次
                        if (!combo.active) {
                            combo.active = true;
                            eventBus.publish("Combination_" + combo.combinationName);
                        }
                    }
                } else {
                    // 不满足
                    combo.active = false;
                }
            }
        }

        //==============================
        // 4) Repeat 检测
        //==============================
        if (hasRepeat) {
            for (var repKeyStr:String in repeatConfigs) {
                var repCode:Number = Number(repKeyStr);
                if (keyStates[repCode]) {
                    // 正在按住
                    var repCfg:Object = repeatConfigs[repCode];
                    var elapsedRep:Number = nowTime - repCfg.lastTriggerTime;
                    if (elapsedRep >= repCfg.interval) {
                        // 触发
                        var rName:String = watchedKeyNames[repCode];
                        eventBus.publish("Repeat_" + rName);
                        // 更新lastTriggerTime
                        repCfg.lastTriggerTime = nowTime;
                    }
                }
            }
        }

        // (其他需要的逻辑可继续在这里扩展) ...
    }

    //============================
    // 原有功能接口
    //============================

    /**
     * 返回键码对应的键名。
     * @param {Number} keycode
     * @return {String}
     */
    public static function getKeyName(keycode:Number):String {
        return keyMap[keycode] || "";
    }

    /**
     * 添加或更新键码与键名的映射。
     */
    public static function addKeyMapping(keycode:Number, keyname:String):Void {
        keyMap[keycode] = keyname;
    }

    /**
     * 移除键码与键名的映射。
     */
    public static function removeKeyMapping(keycode:Number):Void {
        if (keyMap[keycode] != undefined) {
            delete keyMap[keycode];
        }
    }

    /**
     * 检查键码是否存在映射。
     */
    public static function hasKeyName(keycode:Number):Boolean {
        return keyMap[keycode] != undefined;
    }

    /**
     * 获取所有键码。
     */
    public static function getAllKeycodes():Array {
        var keycodes:Array = [];
        for (var keycode in keyMap) {
            keycodes.push(Number(keycode));
        }
        return keycodes;
    }

    /**
     * 获取所有键名。
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
     * 同时更新缓存字典、可用的按键设置，以及需要监听的按键列表 watchedKeys。
     *
     * @param {Array} keySettings - 键值设定数组。[可显示名称, 唯一标识, keycode]
     * @param {Function} translationFunction - 翻译函数，用于翻译键名。
     * @param {Array} controlSettings - 操控目标按键设定表。例：controlSettings[0] = _root.上键 ...
     */
    public static function refreshKeySettings(keySettings:Array, translationFunction:Function, controlSettings:Array):Void {
        // 1. 如果键值设定长度小于30，添加默认按键（保留原逻辑）
        if (keySettings.length < 30) {
            trace("[KeyManager] keySettings length < 30, adding defaults.");
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

        // 5. 清空并重新构建 watchedKeys
        for (var kc:String in watchedKeys) {
            delete watchedKeys[kc];
            delete watchedKeyNames[kc];
        }

        // 6. 对新 settings 内的所有键进行监听 (可自定义筛选)
        for (i = 0; i < keySettings.length; i++) {
            var code:Number = keySettings[i][2];
            watchedKeys[code] = true;
            watchedKeyNames[code] = keySettings[i][1];
            keyStates[code] = false;
        }
    }

    /**
     * 根据键名获取对应的键值。
     */
    public static function getKeySetting(keyName:String):Number {
        return KeyManager.keySettingsCache[keyName];
    }

    //============================
    // 按键状态查询
    //============================
    /**
     * 判断给定键名是否按下
     * @param keyName
     * @return Boolean
     */
    public static function isKeyDown(keyName:String):Boolean {
        var code:Number = getKeySetting(keyName);
        if (isNaN(code)) {
            return false;
        }
        return keyStates[code] === true;
    }

    //============================
    // 简化 KeyDown/KeyUp 订阅接口
    //============================
    public static function onKeyDown(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribe("KeyDown_" + keyName, callback, scope);
    }
    public static function onKeyUp(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribe("KeyUp_" + keyName, callback, scope);
    }
    public static function offKeyDown(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("KeyDown_" + keyName, callback);
    }
    public static function offKeyUp(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("KeyUp_" + keyName, callback);
    }
    public static function onceKeyDown(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribeOnce("KeyDown_" + keyName, callback, scope);
    }
    public static function onceKeyUp(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribeOnce("KeyUp_" + keyName, callback, scope);
    }

    //============================
    // 长按 LongPress
    //============================
    public static function subscribeLongPress(keyName:String, threshold:Number, callback:Function, scope:Object):Void {
        eventBus.subscribe("LongPress_" + keyName, callback, scope);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            longPressConfigs[code] = { threshold: threshold, startTime: -1, triggered: false };
            hasLongPress = true;
        }
    }
    public static function unsubscribeLongPress(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("LongPress_" + keyName, callback);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            delete longPressConfigs[code];
        }
        checkLongPressEmpty();
    }
    private static function checkLongPressEmpty():Void {
        for (var k:String in longPressConfigs) {
            return; 
        }
        hasLongPress = false;
    }

    //============================
    // 组合键 Combination
    //============================
    public static function subscribeCombination(
        combinationName:String, 
        keyNames:Array, 
        callback:Function, 
        scope:Object, 
        continuous:Boolean
    ):Void {
        if (continuous == undefined) continuous = false;
        eventBus.subscribe("Combination_" + combinationName, callback, scope);

        var codes:Array = [];
        for (var i:Number = 0; i < keyNames.length; i++) {
            var c:Number = getKeySetting(keyNames[i]);
            if (!isNaN(c)) {
                codes.push(c);
            }
        }
        combinationConfigs.push({
            combinationName: combinationName,
            keyCodes: codes,
            continuous: continuous,
            active: false
        });
        hasCombination = true;
    }
    public static function unsubscribeCombination(combinationName:String, callback:Function):Void {
        eventBus.unsubscribe("Combination_" + combinationName, callback);
        for (var i:Number=combinationConfigs.length-1; i>=0; i--) {
            if (combinationConfigs[i].combinationName == combinationName) {
                combinationConfigs.splice(i,1);
            }
        }
        checkCombinationEmpty();
    }
    private static function checkCombinationEmpty():Void {
        hasCombination = (combinationConfigs.length > 0);
    }

    //============================
    // 双击 DoubleTap
    //============================
    public static function subscribeDoubleTap(keyName:String, interval:Number, callback:Function, scope:Object):Void {
        eventBus.subscribe("DoubleTap_" + keyName, callback, scope);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            doubleTapConfigs[code] = { interval: interval, lastTapTime: -1 };
            hasDoubleTap = true;
        }
    }
    public static function unsubscribeDoubleTap(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("DoubleTap_" + keyName, callback);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            delete doubleTapConfigs[code];
        }
        checkDoubleTapEmpty();
    }
    private static function checkDoubleTapEmpty():Void {
        for (var k:String in doubleTapConfigs) {
            return;
        }
        hasDoubleTap = false;
    }

    //============================
    // 重复 Repeat
    //============================
    public static function subscribeRepeat(keyName:String, interval:Number, callback:Function, scope:Object):Void {
        eventBus.subscribe("Repeat_" + keyName, callback, scope);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            repeatConfigs[code] = { interval: interval, lastTriggerTime: -1 };
            hasRepeat = true;
        }
    }
    public static function unsubscribeRepeat(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("Repeat_" + keyName, callback);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            delete repeatConfigs[code];
        }
        checkRepeatEmpty();
    }
    private static function checkRepeatEmpty():Void {
        for (var k:String in repeatConfigs) {
            return;
        }
        hasRepeat = false;
    }
}
