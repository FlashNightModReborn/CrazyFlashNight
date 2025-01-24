import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.object.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.neur.Timer.*;
import org.flashNight.neur.Event.Delegate;

/*
 * =============================================================================
 *  KeyManager
 * -----------------------------------------------------------------------------
 *  这是一个用于管理键盘事件的 AS2 类，支持多种键盘事件的监听和管理:
 *    1. 按下 / 松开 (KeyDown / KeyUp)
 *    2. 长按 (LongPress)
 *    3. 组合键 (Combination)
 *    4. 双击 (DoubleTap)
 *    5. 重复触发 (Repeat)
 *
 *  并提供以下功能:
 *    - 自定义帧计数器，避免依赖 getTimer()
 *    - 动态刷新键位设定 (refreshKeySettings)
 *    - 查询按键是否按下 (isKeyDown)
 *    - 新增接口 updateWatchedKeys(...) 用于动态重建需要监听的按键
 *
 *  该类使用 EventBus 作为事件总线，通过发布事件的方式通知外部监听器。
 *  事件名示例:
 *    KeyDown_互动键 / KeyUp_互动键
 *    LongPress_互动键
 *    Combination_Ctrl+C
 *    DoubleTap_互动键
 *    Repeat_互动键
 *
 *  其他说明:
 *    - 所有时长/间隔以 "帧" 为单位 (frame-based timing)。
 *    - 只有在调用对应的 onXxx(...) 方法时，相关功能才会启用，
 *      以确保在没有订阅时不会产生额外的性能消耗。
 *
 * -----------------------------------------------------------------------------
 *  使用示例:
 *
 *  1) 在项目开始时初始化 KeyManager:
 *     KeyManager.init();
 *
 *  2) 刷新键位设置:
 *     KeyManager.refreshKeySettings(
 *       _root.键值设定, // 例如 [[显示名称, 唯一标识, 键码], ...]
 *       myTranslationFunc, // 翻译函数 (可自行实现或传入空函数)
 *       controlSettings    // 控制表 (如 [上键, 下键, 左键, 右键])
 *     );
 *
 *  3) 修改监听的按键列表（可选）:
 *     KeyManager.updateWatchedKeys(["互动键", "武器技能键"]); 
 *       // 仅监听“互动键”和“武器技能键”两种
 *
 *  4) 监听键按下/松开事件:
 *     KeyManager.onKeyDown("互动键", function() {
 *       trace("按下 互动键");
 *     }, this);
 *
 *     KeyManager.onKeyUp("互动键", function() {
 *       trace("松开 互动键");
 *     }, this);
 *
 *  5) 监听长按事件 (阈值=30帧):
 *     KeyManager.onLongPress("互动键", 30, function() {
 *       trace("长按 互动键 30帧");
 *     }, this);
 *
 *  6) 监听组合键 Ctrl+C (一次触发，不连续):
 *     KeyManager.onCombination(
 *       "Ctrl+C",
 *       ["Control", "C"],
 *       function() { trace("触发组合键 Ctrl+C"); },
 *       this,
 *       false
 *     );
 *
 *  7) 监听双击事件 (两次按下间隔 <= 15帧):
 *     KeyManager.onDoubleTap("互动键", 15, function() {
 *       trace("双击 互动键");
 *     }, this);
 *
 *  8) 监听重复触发事件 (每10帧触发一次):
 *     KeyManager.onRepeat("互动键", 10, function() {
 *       trace("Repeat_互动键");
 *     }, this);
 *
 *  9) 查询按键是否按下:
 *     if (KeyManager.isKeyDown("互动键")) {
 *       trace("互动键 正在被按住...");
 *     }
 *
 *  10) 取消监听事件:
 *     KeyManager.offKeyDown("互动键", myKeyDownFunc);
 *     KeyManager.offLongPress("互动键", myLongPressFunc);
 *     KeyManager.offCombination("Ctrl+C", myComboFunc);
 *     // ... 其他事件的取消监听
 *
 * -----------------------------------------------------------------------------
 *  后续计划:
 *    - 将内部的帧计时器迁移到外部模块，以增强模块化和可维护性。
 *
 *  整体结构说明:
 *    - 映射表 & 缓存  (keyMap / keySettingsCache): 存储键码与键名的映射关系。
 *    - watchedKeys     (仅监听这些键，避免遍历全部键码，提升性能)。
 *    - watchedKeyNames (记录每个键码对应的字符串标识，用于生成事件名)。
 *    - keyStates       (记录每个键的当前按下状态 true/false)。
 *    - frameCount      (帧计数器，每帧自增，用于基于帧的时间判断)。
 *    - 长按 / 组合键 / 双击 / 重复 等功能对应的配置表。
 *    - 提供对应的 on/off 方法，以及在主循环中检测这些功能的 pollKeys 方法。
 *    - 新增 updateWatchedKeys(...) 用于动态修改监听的按键范围。
 * =============================================================================
 */
class org.flashNight.arki.key.KeyManager {

    //============================
    // 基础字段定义
    //============================

    private static var keyMap:Object = KeyManager.init(); 
    private static var keySettingsCache:Object; // 键位设定的缓存

    /*
     * watchedKeys:
     *   用于记录需要轮询的键，避免遍历全部键码造成性能浪费。
     * watchedKeyNames:
     *   存储每个键码对应的字符串标识（如 "互动键"），用于拼接事件名。
     * keyStates:
     *   记录每个键的当前按下状态（true=按下, false=抬起）。
     *
     * 在此处，将其默认设置为只监听“互动键”(示例键码：69)，
     * 也可以根据实际需求调整。
     */
    private static var watchedKeys:Object = initWatchedKeys();
    private static var watchedKeyNames:Object = initWatchedKeyNames();
    private static var keyStates:Object = initKeyStates();

    private static function initWatchedKeys():Object
    {
        var obj:Object = new Object();
        obj[69] = true;
        return obj;
    }

    private static function initWatchedKeyNames():Object
    {
        var obj:Object = new Object();
        obj[69] = "互动键";
        return obj;
    }

    private static function initKeyStates():Object
    {
        var obj:Object = new Object();
        obj[69] = false;
        return obj;
    }

    //============================
    // 帧计数器
    //============================

    /*
     * frameCount:
     *   每帧由 onEnterFrame 自增，用于以帧为单位进行时间判断。
     */
    private static var frameCount:Number = 0;
    private static var frameTimer:FrameTimer;

    //============================
    // 事件总线实例
    //============================

    private static var eventBus:EventBus = EventBus.getInstance();

    //============================
    // 长按 / 组合键 / 双击 / 重复功能的配置表
    //============================

    /*
     * 下列四个功能只有在对应的 "onXxx" 方法被调用时才真正启用，
     * 以 hasXxx 标志来控制是否在 pollKeys 中遍历相关逻辑。
     */

    private static var hasLongPress:Boolean = false;
    /*
     * longPressConfigs[keyCode] = {
     *   threshold: Number,   // 达到多少帧算长按
     *   startFrame: Number,  // 按下时的帧数
     *   triggered: Boolean   // 防止重复长按触发
     * }
     */
    private static var longPressConfigs:Object = {};

    private static var hasCombination:Boolean = false;
    /*
     * combinationConfigs 中每项:
     * {
     *   combinationName: "Ctrl+C",  // 用于事件名: Combination_Ctrl+C
     *   keyCodes: [17,67],         // 对应键码列表
     *   continuous: Boolean,       // 是否每帧触发
     *   active: Boolean            // 用于区分 "刚满足" 与 "已满足" 状态
     * }
     */
    private static var combinationConfigs:Array = [];

    private static var hasDoubleTap:Boolean = false;
    /*
     * doubleTapConfigs[keyCode] = {
     *   interval: Number,    // 两次按下间隔 <= interval（帧）
     *   lastTapFrame: Number // 记录上次按下的帧数
     * }
     */
    private static var doubleTapConfigs:Object = {};

    private static var hasRepeat:Boolean = false;
    /*
     * repeatConfigs[keyCode] = {
     *   interval: Number,         // 按住时，每隔多少帧触发一次
     *   lastTriggerFrame: Number  // 上一次触发的帧数
     * }
     */
    private static var repeatConfigs:Object = {};

    /*
     * 构造函数 (静态类，无实际作用)
     */
    public function KeyManager() {
        trace("KeyManager instance created. (通常不应实例化此类)");
    }

    /*
     * init():
     *   1. 构建键码到键名的映射表。
     *   2. 在 _root 上创建一个 keyPollMC，用于每帧轮询，并绑定 onEnterFrame 事件。
     *   3. 通过 onEnterFrame，每帧调用 pollKeys() 方法，并自增 frameCount。
     *      -> 若后续有更专业的帧计时器，可以移除此 MovieClip，手动调用 pollKeys()。
     * 返回值:
     *   键码到键名的映射表 keyMap。
     */
    public static function init():Object {
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

        // 创建 keyPollMC（用于帧计数和键轮询）
        if (_root.keyPollMC == undefined) {
            _root.createEmptyMovieClip("keyPollMC", _root.getNextHighestDepth());
        }
        _root.keyPollMC.onEnterFrame = function() {
            KeyManager.frameCount++;
            KeyManager.pollKeys();
        };

        /*

        KeyManager.frameTimer = FrameTimer.getInstance();
        var func:Function = Delegate.create(KeyManager, function() {
            KeyManager.frameCount++;
            KeyManager.pollKeys();
        });
        FrameTimer.getInstance().addTask(func)

        */

        // trace("[KeyManager] 初始化完成。使用基于帧的计时。keyPollMC 的 onEnterFrame 已设置。");
        return keyMap;
    }

    /*
     * pollKeys():
     *   每帧由 onEnterFrame 调用，检测 watchedKeys 中的键状态，
     *   并根据订阅的功能（长按 / 组合键 / 双击 / 重复）执行相应逻辑。
     */
    private static function pollKeys():Void {
        var nowFrame:Number = frameCount;

        // 检测 KeyDown / KeyUp 事件
        for (var keycodeStr:String in watchedKeys) {
            var keycode:Number = Number(keycodeStr);
            var isNowDown:Boolean = Key.isDown(keycode);
            var wasDown:Boolean = (keyStates[keycode] == true);

            // 如果键状态发生变化（按下 -> 松开 或 松开 -> 按下）
            if (isNowDown != wasDown) {
                keyStates[keycode] = isNowDown;
                var keyName:String = watchedKeyNames[keycode];
                var eventName:String = (isNowDown ? "KeyDown_" : "KeyUp_") + keyName;
                eventBus.publish(eventName);

                // 如果是按下，可能影响双击 / 长按 / 重复等功能
                if (isNowDown) {
                    // 处理 DoubleTap
                    if (hasDoubleTap && doubleTapConfigs[keycode]) {
                        var cfgD:Object = doubleTapConfigs[keycode];
                        if (cfgD.lastTapFrame >= 0 && (nowFrame - cfgD.lastTapFrame) <= cfgD.interval) {
                            eventBus.publish("DoubleTap_" + keyName);
                            cfgD.lastTapFrame = -1; // 重置
                        } else {
                            cfgD.lastTapFrame = nowFrame;
                        }
                    }
                    // 处理 LongPress
                    if (hasLongPress && longPressConfigs[keycode]) {
                        var cfgL:Object = longPressConfigs[keycode];
                        cfgL.startFrame = nowFrame;
                        cfgL.triggered = false;
                    }
                    // 处理 Repeat
                    if (hasRepeat && repeatConfigs[keycode]) {
                        var cfgR:Object = repeatConfigs[keycode];
                        cfgR.lastTriggerFrame = nowFrame;
                    }
                }
                // 如果是松开，可能需要重置长按
                else {
                    if (hasLongPress && longPressConfigs[keycode]) {
                        var cfgL2:Object = longPressConfigs[keycode];
                        cfgL2.startFrame = -1;
                        cfgL2.triggered = false;
                    }
                }
            }
        }

        // 处理长按（LongPress）事件
        if (hasLongPress) {
            for (var lCodeStr:String in longPressConfigs) {
                var lCode:Number = Number(lCodeStr);
                if (keyStates[lCode]) { // 若键仍处于按住状态
                    var lCfg:Object = longPressConfigs[lCode];
                    if (!lCfg.triggered && lCfg.startFrame >= 0) {
                        var elapsedFrames:Number = nowFrame - lCfg.startFrame;
                        if (elapsedFrames >= lCfg.threshold) {
                            var ln:String = watchedKeyNames[lCode];
                            eventBus.publish("LongPress_" + ln);
                            lCfg.triggered = true; // 防止多次触发
                        }
                    }
                }
            }
        }

        // 处理组合键（Combination）事件
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
                    if (combo.continuous) {
                        eventBus.publish("Combination_" + combo.combinationName);
                    } else {
                        if (!combo.active) {
                            combo.active = true;
                            eventBus.publish("Combination_" + combo.combinationName);
                        }
                    }
                } else {
                    combo.active = false;
                }
            }
        }

        // 处理重复触发（Repeat）事件
        if (hasRepeat) {
            for (var repKeyStr:String in repeatConfigs) {
                var repCode:Number = Number(repKeyStr);
                if (keyStates[repCode]) {
                    var repCfg:Object = repeatConfigs[repCode];
                    var elapsedR:Number = nowFrame - repCfg.lastTriggerFrame;
                    if (elapsedR >= repCfg.interval) {
                        var rName:String = watchedKeyNames[repCode];
                        eventBus.publish("Repeat_" + rName);
                        repCfg.lastTriggerFrame = nowFrame;
                    }
                }
            }
        }
    }

    /*
     * 提供一系列对键位映射和刷新功能的接口
     */

    /*
     * getKeyName(keycode):
     *   根据键码获取对应的键名。
     * 参数:
     *   keycode:Number - 键盘按键的键码。
     * 返回值:
     *   对应的键名字符串，如果未找到则返回空字符串。
     */
    public static function getKeyName(keycode:Number):String {
        return keyMap[keycode] || "";
    }

    /*
     * addKeyMapping(keycode, keyname):
     *   添加一个键码与键名的映射关系。
     * 参数:
     *   keycode:Number - 键盘按键的键码。
     *   keyname:String - 对应的键名。
     */
    public static function addKeyMapping(keycode:Number, keyname:String):Void {
        keyMap[keycode] = keyname;
    }

    /*
     * removeKeyMapping(keycode):
     *   移除一个键码与键名的映射关系。
     * 参数:
     *   keycode:Number - 键盘按键的键码。
     */
    public static function removeKeyMapping(keycode:Number):Void {
        if (keyMap[keycode] != undefined) {
            delete keyMap[keycode];
        }
    }

    /*
     * hasKeyName(keycode):
     *   检查是否存在指定键码的键名映射。
     * 参数:
     *   keycode:Number - 键盘按键的键码。
     * 返回值:
     *   Boolean - 如果存在则返回 true，否则返回 false。
     */
    public static function hasKeyName(keycode:Number):Boolean {
        return keyMap[keycode] != undefined;
    }

    /*
     * getAllKeycodes():
     *   获取所有映射的键码。
     * 返回值:
     *   Array - 包含所有键码的数组。
     */
    public static function getAllKeycodes():Array {
        var keycodes:Array = [];
        for (var keycode in keyMap) {
            keycodes.push(Number(keycode));
        }
        return keycodes;
    }

    /*
     * getAllKeynames():
     *   获取所有映射的键名。
     * 返回值:
     *   Array - 包含所有键名的数组。
     */
    public static function getAllKeynames():Array {
        var keynames:Array = [];
        for (var keycode in keyMap) {
            keynames.push(keyMap[keycode]);
        }
        return keynames;
    }

    /*
     * refreshKeySettings():
     *   刷新键位设定，包括添加默认键位、更新缓存和 watchedKeys。
     * 参数:
     *   keySettings:Array - 键位设定数组，例如 [[显示名称, 唯一标识, 键码], ...]。
     *   translationFunction:Function - 翻译函数，用于翻译键名（可自行实现或传入空函数）。
     *   controlSettings:Array - 控制表数组，如 [上键, 下键, 左键, 右键]。
     *
     * 具体操作:
     *    - 如果提供的键位数组长度小于 30，则自动添加一些默认键位（如 互动键、奔跑键等）。
     *    - 更新全局变量 _root.键值设定。
     *    - 构建本地的 keySettingsCache，并更新 _root 上的键值设定。
     *    - 外部可通过 onKeyDown 等方法订阅事件。但本函数并不会自动对所有键进行监听，
     *      如需指定监听范围，可再调用 updateWatchedKeys(...)。
     */
    public static function refreshKeySettings(keySettings:Array, translationFunction:Function, controlSettings:Array):Void {
        if (keySettings.length < 30) {
            trace("[KeyManager] 键位设定长度小于 30，添加默认键位。");
            var newKeys:Array = [
                [translationFunction("互动键"), "互动键", 69],
                [translationFunction("武器技能键"), "武器技能键", 70],
                [translationFunction("飞行键"), "飞行键", 18],
                [translationFunction("武器变形键"), "武器变形键", 81],
                [translationFunction("奔跑键"), "奔跑键", 16]
            ];
            keySettings = keySettings.concat(newKeys);
            _root.键值设定 = keySettings;
        }

        // 初始化或清空 keySettingsCache
        if (!KeyManager.keySettingsCache) {
            KeyManager.keySettingsCache = {};
        } else {
            for (var k in KeyManager.keySettingsCache) {
                delete KeyManager.keySettingsCache[k];
            }
        }

        // 构建 keySettingsCache 并更新 _root 上的键值设定
        for (var i:Number = 0; i < keySettings.length; i++) {
            var keyName:String = keySettings[i][1];
            var keyValue:Number = keySettings[i][2];
            _root[keyName] = keyValue;
            KeyManager.keySettingsCache[keyName] = keyValue;
        }

        // 更新控制表（保留原有逻辑）
        controlSettings[0] = _root.上键;
        controlSettings[1] = _root.下键;
        controlSettings[2] = _root.左键;
        controlSettings[3] = _root.右键;

        // 注意：此处不再自动更新 watchedKeys / watchedKeyNames / keyStates，
        // 如需监听全部或部分键，请通过 updateWatchedKeys(...) 手动指定。
    }

    /*
     * getKeySetting(keyName):
     *   根据键名获取对应的键码。
     * 参数:
     *   keyName:String - 键名。
     * 返回值:
     *   Number - 对应的键码，如果未找到则返回 NaN。
     */
    public static function getKeySetting(keyName:String):Number {
        return KeyManager.keySettingsCache[keyName];
    }

    /*
     * isKeyDown(keyName):
     *   用于外部随时查询指定键是否被按下。
     * 参数:
     *   keyName:String - 键名。
     * 返回值:
     *   Boolean - 如果键被按下则返回 true，否则返回 false。
     */
    public static function isKeyDown(keyName:String):Boolean {
        var code:Number = getKeySetting(keyName);
        if (isNaN(code)) {
            return false;
        }
        return keyStates[code] === true;
    }

    /*
     * =========================================================================
     *  KeyDown / KeyUp 事件的订阅与取消方法
     * =========================================================================
     *  onKeyDown(keyName, callback, scope):
     *    - 当 "keyName" 键被按下时触发回调函数。
     *    - 事件名格式为 "KeyDown_互动键"。
     *
     *  offKeyDown(keyName, callback):
     *    - 取消对 "KeyDown_互动键" 事件的订阅。
     *
     *  onceKeyDown(keyName, callback, scope):
     *    - 类似 onKeyDown，但回调只执行一次后自动取消订阅。
     *
     *  onKeyUp / offKeyUp / onceKeyUp 方法同理，事件名格式为 "KeyUp_互动键"。
     */
    public static function onKeyDown(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribe("KeyDown_" + keyName, callback, scope);
    }
    public static function offKeyDown(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("KeyDown_" + keyName, callback);
    }
    public static function onceKeyDown(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribeOnce("KeyDown_" + keyName, callback, scope);
    }

    public static function onKeyUp(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribe("KeyUp_" + keyName, callback, scope);
    }
    public static function offKeyUp(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("KeyUp_" + keyName, callback);
    }
    public static function onceKeyUp(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribeOnce("KeyUp_" + keyName, callback, scope);
    }

    /*
     * =========================================================================
     *  长按（LongPress）事件的订阅与取消方法
     * =========================================================================
     *  onLongPress(keyName, thresholdFrames, callback, scope):
     *    - 当连续按住 "keyName" 达到 "thresholdFrames" 帧后触发回调函数。
     *    - 事件名格式为 "LongPress_互动键"。
     *
     *  offLongPress(keyName, callback):
     *    - 取消对 "LongPress_互动键" 事件的订阅。
     */
    public static function onLongPress(keyName:String, thresholdFrames:Number, callback:Function, scope:Object):Void {
        eventBus.subscribe("LongPress_" + keyName, callback, scope);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            longPressConfigs[code] = { threshold: thresholdFrames, startFrame: -1, triggered: false };
            hasLongPress = true;
        }
    }
    public static function offLongPress(keyName:String, callback:Function):Void {
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

    /*
     * =========================================================================
     *  组合键（Combination）事件的订阅与取消方法
     * =========================================================================
     *  onCombination(combinationName, keyNames, callback, scope, continuous):
     *    - 当 keyNames 中所有键同时按下时，触发回调函数。
     *    - 事件名格式为 "Combination_Ctrl+C"。
     *    - 如果 continuous=true，则在按住状态下每帧都触发；否则仅在从不满足到满足时触发一次。
     *
     *  offCombination(combinationName, callback):
     *    - 取消对 "Combination_Ctrl+C" 事件的订阅。
     */
    public static function onCombination(
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
    public static function offCombination(combinationName:String, callback:Function):Void {
        eventBus.unsubscribe("Combination_" + combinationName, callback);
        for (var i:Number = combinationConfigs.length - 1; i >= 0; i--) {
            if (combinationConfigs[i].combinationName == combinationName) {
                combinationConfigs.splice(i, 1);
            }
        }
        checkCombinationEmpty();
    }
    private static function checkCombinationEmpty():Void {
        hasCombination = (combinationConfigs.length > 0);
    }

    /*
     * =========================================================================
     *  双击（DoubleTap）事件的订阅与取消方法
     * =========================================================================
     *  onDoubleTap(keyName, intervalFrames, callback, scope):
     *    - 如果在 intervalFrames 帧内，连续按下两次 "keyName"，
     *      则触发回调函数。
     *    - 事件名格式为 "DoubleTap_互动键"。
     *
     *  offDoubleTap(keyName, callback):
     *    - 取消对 "DoubleTap_互动键" 事件的订阅。
     */
    public static function onDoubleTap(keyName:String, intervalFrames:Number, callback:Function, scope:Object):Void {
        eventBus.subscribe("DoubleTap_" + keyName, callback, scope);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            doubleTapConfigs[code] = { interval: intervalFrames, lastTapFrame: -1 };
            hasDoubleTap = true;
        }
    }
    public static function offDoubleTap(keyName:String, callback:Function):Void {
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

    /*
     * =========================================================================
     *  重复触发（Repeat）事件的订阅与取消方法
     * =========================================================================
     *  onRepeat(keyName, intervalFrames, callback, scope):
     *    - 当按住 "keyName" 时，每隔 intervalFrames 帧触发一次回调函数。
     *    - 事件名格式为 "Repeat_互动键"。
     *
     *  offRepeat(keyName, callback):
     *    - 取消对 "Repeat_互动键" 事件的订阅。
     */
    public static function onRepeat(keyName:String, intervalFrames:Number, callback:Function, scope:Object):Void {
        eventBus.subscribe("Repeat_" + keyName, callback, scope);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            repeatConfigs[code] = { interval: intervalFrames, lastTriggerFrame: -1 };
            hasRepeat = true;
        }
    }
    public static function offRepeat(keyName:String, callback:Function):Void {
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

    /*
     * =========================================================================
     *  新增接口: 动态修改需要监听的按键范围
     * =========================================================================
     *  updateWatchedKeys(newKeyNames:Array):
     *    - 传入一个键名数组，仅监听这些键所对应的键码，其他按键将不再被轮询。
     *    - 同时重置 watchedKeys、watchedKeyNames、keyStates 中旧有的内容。
     *
     * 示例:
     *    KeyManager.updateWatchedKeys(["互动键", "武器技能键", "奔跑键"]);
     *    // 仅监听上述3个键名对应的键码
     */
    public static function updateWatchedKeys(newKeyNames:Array):Void {
        // 1. 清空当前的 watchedKeys, watchedKeyNames, keyStates
        for (var codeStr:String in watchedKeys) {
            delete watchedKeys[codeStr];
        }
        for (var codeStr2:String in watchedKeyNames) {
            delete watchedKeyNames[codeStr2];
        }
        for (var codeStr3:String in keyStates) {
            delete keyStates[codeStr3];
        }

        // 2. 根据 newKeyNames 重新填充
        for (var i:Number = 0; i < newKeyNames.length; i++) {
            var name:String = newKeyNames[i];
            var code:Number = getKeySetting(name);
            if (!isNaN(code)) {
                watchedKeys[code] = true;
                watchedKeyNames[code] = name;
                keyStates[code] = false;
            }
        }
    }


    // =========================================================================
    // 以下为 **新增** 的生命周期版方法 (示例名以 "L" 结尾) 
    // 利用 EventCoordinator.addUnloadCallback 在指定的 MovieClip 卸载时，
    // 自动执行取消订阅，避免不必要的事件残留。
    // -------------------------------------------------------------------------

    /**
     * 当 "keyName" 键被按下时触发回调（带生命周期管理）。
     * @param keyName  键名
     * @param callback 回调函数
     * @param scope    回调作用域
     * @param host     要托管生命周期的 MovieClip
     */
    public static function onKeyDownL(keyName:String, callback:Function, scope:Object, host:MovieClip):Void {
        onKeyDown(keyName, callback, scope);
        var eventName:String = "KeyDown_" + keyName;
        var unsubFunc:Function = function() {
            KeyManager.offKeyDown(keyName, callback);
        };

        host = host || scope || _root;
        // 当 host 被卸载时，自动执行 unsubFunc
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    public static function onceKeyDownL(keyName:String, callback:Function, scope:Object, host:MovieClip):Void {
        onceKeyDown(keyName, callback, scope);
        var eventName:String = "KeyDown_" + keyName;
        var unsubFunc:Function = function() {
            KeyManager.offKeyDown(keyName, callback);
        };

        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    public static function onKeyUpL(keyName:String, callback:Function, scope:Object, host:MovieClip):Void {
        onKeyUp(keyName, callback, scope);
        var eventName:String = "KeyUp_" + keyName;
        var unsubFunc:Function = function() {
            KeyManager.offKeyUp(keyName, callback);
        };

        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    public static function onceKeyUpL(keyName:String, callback:Function, scope:Object, host:MovieClip):Void {
        onceKeyUp(keyName, callback, scope);
        var eventName:String = "KeyUp_" + keyName;
        var unsubFunc:Function = function() {
            KeyManager.offKeyUp(keyName, callback);
        };
        
        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    /**
     * 当连续按住 "keyName" 达到 "thresholdFrames" 帧后触发回调（带生命周期）。
     */
    public static function onLongPressL(
        keyName:String, 
        thresholdFrames:Number, 
        callback:Function, 
        scope:Object, 
        host:MovieClip
    ):Void {
        onLongPress(keyName, thresholdFrames, callback, scope);
        var unsubFunc:Function = function() {
            KeyManager.offLongPress(keyName, callback);
        };
        
        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    /**
     * 带生命周期的组合键订阅。
     * @param combinationName 组合键事件名(如 "Ctrl+C")
     * @param keyNames        参与组合的键名数组(如 ["Control","C"])
     * @param callback        回调
     * @param scope           回调作用域
     * @param continuous      是否每帧都触发
     * @param host            托管生命周期的MC
     */
    public static function onCombinationL(
        combinationName:String,
        keyNames:Array,
        callback:Function,
        scope:Object,
        continuous:Boolean,
        host:MovieClip
    ):Void {
        onCombination(combinationName, keyNames, callback, scope, continuous);
        var unsubFunc:Function = function() {
            KeyManager.offCombination(combinationName, callback);
        };
        
        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    /**
     * 带生命周期的双击事件订阅。
     */
    public static function onDoubleTapL(
        keyName:String, 
        intervalFrames:Number, 
        callback:Function, 
        scope:Object, 
        host:MovieClip
    ):Void {
        onDoubleTap(keyName, intervalFrames, callback, scope);
        var unsubFunc:Function = function() {
            KeyManager.offDoubleTap(keyName, callback);
        };
        
        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    /**
     * 带生命周期的重复触发事件订阅。
     */
    public static function onRepeatL(
        keyName:String, 
        intervalFrames:Number, 
        callback:Function, 
        scope:Object, 
        host:MovieClip
    ):Void {
        onRepeat(keyName, intervalFrames, callback, scope);
        var unsubFunc:Function = function() {
            KeyManager.offRepeat(keyName, callback);
        };
        
        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }
}
