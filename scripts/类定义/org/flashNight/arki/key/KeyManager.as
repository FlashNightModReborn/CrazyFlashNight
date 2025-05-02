import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.object.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.neur.Timer.*;
import org.flashNight.neur.Event.Delegate;

/*
 * =============================================================================
 *  KeyManager (进一步优化版，带详细中文文档注释)
 * -----------------------------------------------------------------------------
 *  功能说明：
 *    本类用于管理键盘事件监听，支持如下功能：
 *      1. 单键按下/松开 (KeyDown/KeyUp)
 *      2. 长按 (LongPress)
 *      3. 组合键 (Combination)
 *      4. 双击 (DoubleTap)
 *      5. 重复触发 (Repeat)
 *
 *  优化思路：
 *    1. 避免遍历所有键码，采用 watchedKeys 限定需要监听的按键集合，
 *       通过 updateWatchedKeys() 和 ensureWatchedKey() 方法动态管理监听范围。
 *    2. 采用事件名缓存 (watchedEventNames 及各功能的 eventName 字段)，
 *       将 "KeyDown_键名"、"KeyUp_键名" 等字符串提前拼接好，减少每帧轮询时的字符串拼接开销。
 *    3. 在 pollKeys() 方法中分三大部分：
 *         (1) 遍历 watchedKeys，检测按键状态变化（按下/松开），并同步处理双击、长按、重复的初始状态；
 *         (2) 对本帧持续按下的键统一处理长按与重复触发逻辑；
 *         (3) 针对组合键配置进行检查，通过快速查表 pressedThisFrame 判断是否满足所有按键同时按下。
 *    4. 各 onXxx 方法调用时自动调用 ensureWatchedKey() 保证对应按键被加入监听集合，同时更新事件名缓存。
 *
 *  使用说明：
 *    - 外部通过 onKeyDown、onKeyUp、onLongPress、onCombination、onDoubleTap、onRepeat 等方法
 *      订阅相应事件，事件名在内部缓存，不需要额外担心字符串拼接性能问题。
 *    - 通过 refreshKeySettings() 方法刷新按键映射，同时更新 _root 上的键值设定。
 *    - updateWatchedKeys() 方法允许动态调整需要监听的按键范围。
 *
 *  注意：
 *    - 本类为静态类，不建议实例化，所有方法均以静态方式调用。
 *    - 详细的内部字段说明及流程注释已在代码中标明，便于后续维护和扩展。
 * =============================================================================
 */
class org.flashNight.arki.key.KeyManager {

    //============================
    // 基础字段定义
    //============================

    /**
     * keyMap: 键码到键名的映射表，初始在 init() 方法中构建。
     */
    private static var keyMap:Object = KeyManager.init(); 

    /**
     * keySettingsCache: 键位设定缓存，通过 refreshKeySettings() 更新，存储 [键名 -> 键码] 映射。
     */
    private static var keySettingsCache:Object; 

    /**
     * watchedKeys: 用于记录需要轮询的键（keycode），目的是避免遍历全部键码以提高性能。
     * 例如：{ 69:true, ... }
     */
    private static var watchedKeys:Object = initWatchedKeys();

    /**
     * watchedKeyNames: 存储每个 watchedKeys 中的键码对应的键名，如 { 69:"互动键" }。
     */
    private static var watchedKeyNames:Object = initWatchedKeyNames();

    /**
     * watchedEventNames: 存储每个 watchedKeys 中按键的事件名缓存，
     * 格式： { 69:{ down:"KeyDown_互动键", up:"KeyUp_互动键" } }
     * 这样可避免每次轮询时拼接字符串。
     */
    private static var watchedEventNames:Object = {};

    /**
     * keyStates: 存储每个键的当前按下状态，true表示按下，false表示松开。
     * 格式： { 69:true/false, ... }
     */
    private static var keyStates:Object = initKeyStates();

    /**
     * 初始化 watchedKeys，默认监听一个示例按键（69）。
     */
    private static function initWatchedKeys():Object {
        var obj:Object = new Object();
        obj[69] = true; // 示例：69（E键）被默认监听
        return obj;
    }

    /**
     * 初始化 watchedKeyNames，默认记录按键 69 对应的键名。
     */
    private static function initWatchedKeyNames():Object {
        var obj:Object = new Object();
        obj[69] = "互动键";
        return obj;
    }

    /**
     * 初始化 keyStates，默认将示例按键设为未按下状态。
     */
    private static function initKeyStates():Object {
        var obj:Object = new Object();
        obj[69] = false;
        return obj;
    }

    //============================
    // 帧计数器及定时器
    //============================

    /**
     * frameCount: 帧计数器，每帧增加，用于时间计算（基于帧数）。
     */
    private static var frameCount:Number = 0;

    /**
     * frameTimer: 可选的帧定时器引用，目前未使用，预留扩展接口。
     */
    private static var frameTimer:FrameTimer;

    //============================
    // 事件总线实例
    //============================

    /**
     * eventBus: 事件总线实例，所有事件通过此总线发布。
     */
    private static var eventBus:EventBus = EventBus.getInstance();

    //============================
    // 各功能配置表及开关标志
    //============================

    /**
     * hasLongPress: 长按功能是否已启用。
     */
    private static var hasLongPress:Boolean = false;
    /**
     * longPressConfigs: 长按功能配置表，按键码为 key。
     * 每项格式：
     * {
     *   threshold: Number,    // 需要达到的帧数阈值
     *   startFrame: Number,   // 按下时的帧计数
     *   triggered: Boolean,   // 是否已触发长按事件，防止重复触发
     *   eventName: String     // 缓存的事件名（例如 "LongPress_互动键"）
     * }
     */
    private static var longPressConfigs:Object = {};

    /**
     * hasCombination: 组合键功能是否已启用。
     */
    private static var hasCombination:Boolean = false;
    /**
     * combinationConfigs: 组合键配置数组，每项格式：
     * {
     *   combinationName: String, // 组合键名称（例如 "Ctrl+C"）
     *   keyCodes: Array,         // 参与组合的键码数组（例如 [17,67]）
     *   continuous: Boolean,     // 是否连续触发（每帧触发）
     *   active: Boolean,         // 用于记录上一次是否已经触发过（防止重复触发）
     *   eventName: String        // 缓存的事件名（例如 "Combination_Ctrl+C"）
     * }
     */
    private static var combinationConfigs:Array = [];

    /**
     * hasDoubleTap: 双击功能是否已启用。
     */
    private static var hasDoubleTap:Boolean = false;
    /**
     * doubleTapConfigs: 双击功能配置表，按键码为 key。
     * 每项格式：
     * {
     *   interval: Number,      // 两次按下间隔最大帧数
     *   lastTapFrame: Number,  // 上一次按下记录的帧计数
     *   eventName: String      // 缓存的事件名（例如 "DoubleTap_互动键"）
     * }
     */
    private static var doubleTapConfigs:Object = {};

    /**
     * hasRepeat: 重复触发功能是否已启用。
     */
    private static var hasRepeat:Boolean = false;
    /**
     * repeatConfigs: 重复触发功能配置表，按键码为 key。
     * 每项格式：
     * {
     *   interval: Number,         // 每次重复触发的间隔帧数
     *   lastTriggerFrame: Number, // 上一次触发时的帧计数
     *   eventName: String         // 缓存的事件名（例如 "Repeat_互动键"）
     * }
     */
    private static var repeatConfigs:Object = {};

    //============================
    // 构造函数
    //============================
    /**
     * 构造函数：本类为静态类，不建议实例化。
     */
    public function KeyManager() {
        // 一般不会调用此构造函数
    }

    //============================
    // init() 方法：初始化与帧轮询
    //============================
    /**
     * init(): 初始化键盘映射表，并设置每帧轮询机制。
     *   1. 构建 keyMap：键码 -> 键名 的映射。
     *   2. 在 _root 创建一个空 MovieClip(keyPollMC)，
     *      并将其 onEnterFrame 方法设为调用 pollKeys()。
     *   3. 每帧自动增加 frameCount，基于帧数计算时间间隔。
     *
     * 返回值：
     *   返回构建好的 keyMap 对象。
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

        // 在 _root 中创建 keyPollMC 以便每帧调用 pollKeys() 进行轮询
        if (_root.keyPollMC == undefined) {
            _root.createEmptyMovieClip("keyPollMC", _root.getNextHighestDepth());
        }
        _root.keyPollMC.onEnterFrame = function() {
            KeyManager.frameCount++;
            KeyManager.pollKeys();
        };

        return keyMap;
    }

    //============================
    // pollKeys() 方法：每帧检测按键状态变化及功能处理
    //============================
    /**
     * pollKeys(): 每帧调用，用于检测 watchedKeys 中每个键的状态变化，
     * 处理以下逻辑：
     *   1. 检测按键状态变化（KeyDown/KeyUp），并发布相应事件（直接使用缓存的事件名）。
     *   2. 若按下状态变化，初始化双击、长按、重复触发的计时状态。
     *   3. 针对本帧仍处于按下状态的键，统一判断长按与重复触发是否满足条件，
     *      并发布对应事件（采用配置表中的缓存 eventName）。
     *   4. 针对组合键配置，通过检查所有组合键中各键是否同时按下，
     *      若满足则根据连续触发或一次性触发的逻辑发布组合键事件。
     */
    private static function pollKeys():Void {
        var nowFrame:Number = frameCount;

        // 若没有任何监听按键，则快速返回，避免无意义的循环
        if (!hasAnyWatchedKey()) {
            return;
        }

        var eb:EventBus = eventBus;
        var pressedThisFrame:Object = {}; // 用于记录本帧按下的键，便于组合键判断

        // --- 1) 遍历 watchedKeys 检测 KeyDown / KeyUp 变化 ---
        for (var keycodeStr:String in watchedKeys) {
            var keycode:Number = Number(keycodeStr);
            var wasDown:Boolean = (keyStates[keycode] == true);
            var isDownNow:Boolean = Key.isDown(keycode);

            // 当按键状态发生变化时（按下或松开）
            if (isDownNow != wasDown) {
                keyStates[keycode] = isDownNow;

                // 使用缓存的事件名（例如 watchedEventNames[69].down 或 .up）发布事件
                var eNames:Object = watchedEventNames[keycode];
                if (eNames) {
                    var evtName:String = isDownNow ? eNames.down : eNames.up;
                    eb.publish(evtName);
                }

                // 当按下时，初始化双击、长按、重复触发的计时状态
                if (isDownNow) {
                    // 处理双击 (DoubleTap)
                    if (hasDoubleTap) {
                        var dtCfg:Object = doubleTapConfigs[keycode];
                        if (dtCfg) {
                            if (dtCfg.lastTapFrame >= 0 &&
                                (nowFrame - dtCfg.lastTapFrame) <= dtCfg.interval) {
                                // 满足双击条件，发布事件并重置计时器
                                eb.publish(dtCfg.eventName);
                                dtCfg.lastTapFrame = -1;
                            } else {
                                dtCfg.lastTapFrame = nowFrame;
                            }
                        }
                    }
                    // 处理长按 (LongPress)
                    if (hasLongPress) {
                        var lpCfg:Object = longPressConfigs[keycode];
                        if (lpCfg) {
                            lpCfg.startFrame = nowFrame;
                            lpCfg.triggered = false;
                        }
                    }
                    // 处理重复触发 (Repeat)
                    if (hasRepeat) {
                        var rptCfg:Object = repeatConfigs[keycode];
                        if (rptCfg) {
                            rptCfg.lastTriggerFrame = nowFrame;
                        }
                    }
                } else {
                    // 当键松开时，若配置了长按，则重置其计时状态
                    if (hasLongPress) {
                        var lpCfg2:Object = longPressConfigs[keycode];
                        if (lpCfg2) {
                            lpCfg2.startFrame = -1;
                            lpCfg2.triggered = false;
                        }
                    }
                }
            }

            // 记录本帧仍处于按下状态的键，便于后续统一处理长按与重复触发
            if (isDownNow) {
                pressedThisFrame[keycode] = true;
            }
        }

        // --- 2) 针对本帧按下的键处理长按与重复触发 ---
        var needSecondPass:Boolean = (hasLongPress || hasRepeat);
        if (needSecondPass) {
            for (var codeStr:String in pressedThisFrame) {
                var code:Number = Number(codeStr);
                var elapsedFrames:Number;

                // 处理长按 (LongPress)
                if (hasLongPress) {
                    var lpObj:Object = longPressConfigs[code];
                    if (lpObj && !lpObj.triggered && lpObj.startFrame >= 0) {
                        elapsedFrames = nowFrame - lpObj.startFrame;
                        if (elapsedFrames >= lpObj.threshold) {
                            // 达到长按阈值，发布长按事件
                            eventBus.publish(lpObj.eventName); 
                            lpObj.triggered = true;
                        }
                    }
                }

                // 处理重复触发 (Repeat)
                if (hasRepeat) {
                    var rptObj:Object = repeatConfigs[code];
                    if (rptObj) {
                        elapsedFrames = nowFrame - rptObj.lastTriggerFrame;
                        if (elapsedFrames >= rptObj.interval) {
                            eventBus.publish(rptObj.eventName);
                            rptObj.lastTriggerFrame = nowFrame;
                        }
                    }
                }
            }
        }

        // --- 3) 处理组合键 (Combination) ---
        if (hasCombination && combinationConfigs.length > 0) {
            for (var i:Number = 0; i < combinationConfigs.length; i++) {
                var combo:Object = combinationConfigs[i];
                var codes:Array = combo.keyCodes;
                var allPressed:Boolean = true;
                // 检查组合键中每个按键是否均在本帧处于按下状态
                for (var j:Number = 0; j < codes.length; j++) {
                    if (!pressedThisFrame[codes[j]]) {
                        allPressed = false;
                        break;
                    }
                }
                // 如果所有按键均按下，则根据是否连续触发决定是否发布事件
                if (allPressed) {
                    if (combo.continuous) {
                        eventBus.publish(combo.eventName);
                    } else {
                        if (!combo.active) {
                            combo.active = true;
                            eventBus.publish(combo.eventName);
                        }
                    }
                } else {
                    combo.active = false;
                }
            }
        }
    }

    /**
     * hasAnyWatchedKey(): 判断 watchedKeys 是否存在任何监听按键。
     * 用于在 pollKeys() 中快速判断是否需要进行轮询操作。
     *
     * 返回值：
     *   Boolean，若存在任一键则返回 true，否则返回 false。
     */
    private static function hasAnyWatchedKey():Boolean {
        for (var k:String in watchedKeys) {
            return true;
        }
        return false;
    }

    //============================
    // 键位映射及刷新接口
    //============================
    /**
     * getKeyName(keycode): 根据键码获取对应的键名。
     *
     * @param keycode:Number - 键码
     * @return String - 对应的键名，如不存在返回空字符串。
     */
    public static function getKeyName(keycode:Number):String {
        return keyMap[keycode] || "";
    }

    /**
     * addKeyMapping(keycode, keyname): 添加键码与键名映射。
     *
     * @param keycode:Number - 键码
     * @param keyname:String - 键名
     */
    public static function addKeyMapping(keycode:Number, keyname:String):Void {
        keyMap[keycode] = keyname;
    }

    /**
     * removeKeyMapping(keycode): 移除指定键码的映射关系。
     *
     * @param keycode:Number - 键码
     */
    public static function removeKeyMapping(keycode:Number):Void {
        if (keyMap[keycode] != undefined) {
            delete keyMap[keycode];
        }
    }

    /**
     * hasKeyName(keycode): 检查指定键码是否存在映射。
     *
     * @param keycode:Number - 键码
     * @return Boolean - 存在返回 true，否则返回 false。
     */
    public static function hasKeyName(keycode:Number):Boolean {
        return keyMap[keycode] != undefined;
    }

    /**
     * getAllKeycodes(): 获取所有映射的键码。
     *
     * @return Array - 所有键码的数组。
     */
    public static function getAllKeycodes():Array {
        var keycodes:Array = [];
        for (var keycode in keyMap) {
            keycodes.push(Number(keycode));
        }
        return keycodes;
    }

    /**
     * getAllKeynames(): 获取所有映射的键名。
     *
     * @return Array - 所有键名的数组。
     */
    public static function getAllKeynames():Array {
        var keynames:Array = [];
        for (var keycode in keyMap) {
            keynames.push(keyMap[keycode]);
        }
        return keynames;
    }

    /**
     * refreshKeySettings(keySettings, translationFunction, controlSettings):
     *   刷新键位设定，包括更新 _root 上的键值设定、更新 keySettingsCache 以及
     *   重新设置控制表（例如 上键、下键、左键、右键）。
     *
     * @param keySettings:Array - 键位设定数组，格式如 [[显示名称, 唯一标识, 键码], ...]
     * @param translationFunction:Function - 翻译函数，可用于转换显示名称
     * @param controlSettings:Array - 控制表数组，如 [上键, 下键, 左键, 右键]
     */
    public static function refreshKeySettings(
        keySettings:Array, 
        translationFunction:Function, 
        controlSettings:Array
    ):Void {
        // 如果提供的键位数组长度较短，则自动追加默认按键配置
        // if (keySettings.length < 30) {
        //     var newKeys:Array = [
        //         [translationFunction("互动键"), "互动键", 69],
        //         [translationFunction("武器技能键"), "武器技能键", 70],
        //         [translationFunction("飞行键"), "飞行键", 18],
        //         [translationFunction("武器变形键"), "武器变形键", 81],
        //         [translationFunction("奔跑键"), "奔跑键", 16],
        //         [translationFunction("组合键"), "组合键", 17]
        //     ];
        //     keySettings = keySettings.concat(newKeys);
        //     _root.键值设定 = keySettings;
        // }

        //逻辑改为如果键位数组长度小于默认键位长度，则重置为默认按键
        if (keySettings.length < _root.默认键值设定.length) {
            keySettings = _root.默认键值设定;
            _root.键值设定 = keySettings;
        }

        // 更新或重置 keySettingsCache
        if (!KeyManager.keySettingsCache) {
            KeyManager.keySettingsCache = {};
        } else {
            for (var k in KeyManager.keySettingsCache) {
                delete KeyManager.keySettingsCache[k];
            }
        }

        // 遍历键位设定数组，更新 _root 与 keySettingsCache
        for (var i:Number = 0; i < keySettings.length; i++) {
            var keyName:String = keySettings[i][1];
            var keyValue:Number = keySettings[i][2];
            _root[keyName] = keyValue;
            KeyManager.keySettingsCache[keyName] = keyValue;
        }

        // 更新控制表（例如方向键），保持原有逻辑
        controlSettings[0] = _root.上键;
        controlSettings[1] = _root.下键;
        controlSettings[2] = _root.左键;
        controlSettings[3] = _root.右键;
    }

    /**
     * getKeySetting(keyName): 根据键名获取对应的键码。
     *
     * @param keyName:String - 键名
     * @return Number - 对应的键码，如不存在返回 NaN。
     */
    public static function getKeySetting(keyName:String):Number {
        return KeyManager.keySettingsCache[keyName];
    }

    /**
     * isKeyDown(keyName): 判断指定键是否处于按下状态。
     *
     * @param keyName:String - 键名
     * @return Boolean - 如果键被按下返回 true，否则返回 false。
     */
    public static function isKeyDown(keyName:String):Boolean {
        var code:Number = getKeySetting(keyName);
        if (isNaN(code)) {
            return false;
        }
        return keyStates[code] === true;
    }

    //============================
    // KeyDown / KeyUp 事件的订阅及取消接口
    //============================
    /**
     * onKeyDown(keyName, callback, scope):
     *   订阅指定键按下事件，事件名格式为 "KeyDown_键名"，
     *   同时通过 ensureWatchedKey() 确保该键加入监听范围。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 回调函数
     * @param scope:Object - 回调执行时的作用域
     */
    public static function onKeyDown(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribe("KeyDown_" + keyName, callback, scope);
        ensureWatchedKey(keyName);
    }
    /**
     * offKeyDown(keyName, callback): 取消订阅指定键的按下事件。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 之前订阅时的回调函数
     */
    public static function offKeyDown(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("KeyDown_" + keyName, callback);
    }
    /**
     * onceKeyDown(keyName, callback, scope): 订阅一次性按下事件，
     *   回调触发一次后自动取消订阅，同时确保键在监听范围内。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 回调函数
     * @param scope:Object - 作用域
     */
    public static function onceKeyDown(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribeOnce("KeyDown_" + keyName, callback, scope);
        ensureWatchedKey(keyName);
    }

    /**
     * onKeyUp(keyName, callback, scope):
     *   订阅指定键松开事件，事件名格式为 "KeyUp_键名"，
     *   同时确保该键加入监听范围。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 回调函数
     * @param scope:Object - 作用域
     */
    public static function onKeyUp(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribe("KeyUp_" + keyName, callback, scope);
        ensureWatchedKey(keyName);
    }
    /**
     * offKeyUp(keyName, callback): 取消订阅指定键的松开事件。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 回调函数
     */
    public static function offKeyUp(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("KeyUp_" + keyName, callback);
    }
    /**
     * onceKeyUp(keyName, callback, scope): 订阅一次性松开事件，
     *   回调触发一次后自动取消订阅，同时确保该键加入监听范围。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 回调函数
     * @param scope:Object - 作用域
     */
    public static function onceKeyUp(keyName:String, callback:Function, scope:Object):Void {
        eventBus.subscribeOnce("KeyUp_" + keyName, callback, scope);
        ensureWatchedKey(keyName);
    }

    /**
     * ensureWatchedKey(keyName):
     *   确保指定的键加入 watchedKeys，并更新 watchedKeyNames 与事件名缓存 watchedEventNames。
     *
     * @param keyName:String - 键名
     */
    private static function ensureWatchedKey(keyName:String):Void {
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            // 如果键不在监听集合中，则添加进去
            if (!watchedKeys[code]) {
                watchedKeys[code] = true;
                watchedKeyNames[code] = keyName;
                keyStates[code] = false;
            }
            // 更新按下/松开事件名缓存，避免后续拼接字符串
            if (!watchedEventNames[code]) {
                watchedEventNames[code] = {};
            }
            watchedEventNames[code].down = "KeyDown_" + keyName;
            watchedEventNames[code].up   = "KeyUp_" + keyName;
        }
    }

    //============================
    // 长按 (LongPress) 事件接口
    //============================
    /**
     * onLongPress(keyName, thresholdFrames, callback, scope):
     *   订阅长按事件，当指定键持续按下达到 thresholdFrames 帧时，
     *   触发事件，事件名为 "LongPress_键名"（已缓存）。
     *   同时确保该键加入监听范围。
     *
     * @param keyName:String - 键名
     * @param thresholdFrames:Number - 长按阈值（帧数）
     * @param callback:Function - 回调函数
     * @param scope:Object - 作用域
     */
    public static function onLongPress(
        keyName:String, 
        thresholdFrames:Number, 
        callback:Function, 
        scope:Object
    ):Void {
        eventBus.subscribe("LongPress_" + keyName, callback, scope);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            // 在配置表中记录长按相关参数与缓存事件名
            longPressConfigs[code] = {
                threshold: thresholdFrames,
                startFrame: -1,
                triggered: false,
                eventName: "LongPress_" + keyName
            };
            hasLongPress = true;
            ensureWatchedKey(keyName);
        }
    }
    /**
     * offLongPress(keyName, callback): 取消指定键的长按事件订阅。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 回调函数
     */
    public static function offLongPress(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("LongPress_" + keyName, callback);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            delete longPressConfigs[code];
        }
        checkLongPressEmpty();
    }
    /**
     * checkLongPressEmpty(): 检查长按配置表是否为空，若为空则关闭长按功能标志。
     */
    private static function checkLongPressEmpty():Void {
        for (var k:String in longPressConfigs) {
            return;
        }
        hasLongPress = false;
    }

    //============================
    // 组合键 (Combination) 事件接口
    //============================
    /**
     * onCombination(combinationName, keyNames, callback, scope, continuous):
     *   订阅组合键事件，当 keyNames 数组中所有键同时按下时，
     *   触发事件，事件名格式为 "Combination_组合名称"（已缓存）。
     *   参数 continuous 控制是否连续触发（每帧触发）或仅触发一次。
     *
     * @param combinationName:String - 组合键事件名称，如 "Ctrl+C"
     * @param keyNames:Array - 参与组合的键名数组
     * @param callback:Function - 回调函数
     * @param scope:Object - 作用域
     * @param continuous:Boolean - 是否连续触发（可选，默认 false）
     */
    public static function onCombination(
        combinationName:String,
        keyNames:Array,
        callback:Function,
        scope:Object,
        continuous:Boolean
    ):Void {
        if (continuous == undefined) continuous = false;
        var eventN:String = "Combination_" + combinationName;
        eventBus.subscribe(eventN, callback, scope);

        var codes:Array = [];
        // 将 keyNames 转换为键码，并确保每个键加入监听集合
        for (var i:Number = 0; i < keyNames.length; i++) {
            var c:Number = getKeySetting(keyNames[i]);
            if (!isNaN(c)) {
                codes.push(c);
                ensureWatchedKey(keyNames[i]);
            }
        }
        // 添加组合键配置到数组中
        combinationConfigs.push({
            combinationName: combinationName,
            keyCodes: codes,
            continuous: continuous,
            active: false,
            eventName: eventN
        });
        hasCombination = true;
    }
    /**
     * offCombination(combinationName, callback): 取消指定组合键事件订阅。
     *
     * @param combinationName:String - 组合键事件名称
     * @param callback:Function - 回调函数
     */
    public static function offCombination(
        combinationName:String, 
        callback:Function
    ):Void {
        eventBus.unsubscribe("Combination_" + combinationName, callback);
        // 遍历组合键配置数组，移除匹配的项
        for (var i:Number = combinationConfigs.length - 1; i >= 0; i--) {
            if (combinationConfigs[i].combinationName == combinationName) {
                combinationConfigs.splice(i, 1);
            }
        }
        checkCombinationEmpty();
    }
    /**
     * checkCombinationEmpty(): 检查组合键配置数组是否为空，更新 hasCombination 标志。
     */
    private static function checkCombinationEmpty():Void {
        hasCombination = (combinationConfigs.length > 0);
    }

    //============================
    // 双击 (DoubleTap) 事件接口
    //============================
    /**
     * onDoubleTap(keyName, intervalFrames, callback, scope):
     *   订阅双击事件，当指定键在 intervalFrames 帧内连续按下两次时，
     *   触发事件，事件名格式为 "DoubleTap_键名"（已缓存）。
     *
     * @param keyName:String - 键名
     * @param intervalFrames:Number - 双击允许的最大帧间隔
     * @param callback:Function - 回调函数
     * @param scope:Object - 作用域
     */
    public static function onDoubleTap(
        keyName:String, 
        intervalFrames:Number, 
        callback:Function, 
        scope:Object
    ):Void {
        eventBus.subscribe("DoubleTap_" + keyName, callback, scope);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            doubleTapConfigs[code] = {
                interval: intervalFrames,
                lastTapFrame: -1,
                eventName: "DoubleTap_" + keyName
            };
            hasDoubleTap = true;
            ensureWatchedKey(keyName);
        }
    }
    /**
     * offDoubleTap(keyName, callback): 取消指定键的双击事件订阅。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 回调函数
     */
    public static function offDoubleTap(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("DoubleTap_" + keyName, callback);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            delete doubleTapConfigs[code];
        }
        checkDoubleTapEmpty();
    }
    /**
     * checkDoubleTapEmpty(): 检查双击配置表是否为空，更新 hasDoubleTap 标志。
     */
    private static function checkDoubleTapEmpty():Void {
        for (var k:String in doubleTapConfigs) {
            return;
        }
        hasDoubleTap = false;
    }

    //============================
    // 重复触发 (Repeat) 事件接口
    //============================
    /**
     * onRepeat(keyName, intervalFrames, callback, scope):
     *   订阅重复触发事件，当指定键持续按下，每隔 intervalFrames 帧触发一次，
     *   事件名格式为 "Repeat_键名"（已缓存）。
     *
     * @param keyName:String - 键名
     * @param intervalFrames:Number - 重复触发的间隔帧数
     * @param callback:Function - 回调函数
     * @param scope:Object - 作用域
     */
    public static function onRepeat(
        keyName:String, 
        intervalFrames:Number, 
        callback:Function, 
        scope:Object
    ):Void {
        eventBus.subscribe("Repeat_" + keyName, callback, scope);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            repeatConfigs[code] = {
                interval: intervalFrames,
                lastTriggerFrame: -1,
                eventName: "Repeat_" + keyName
            };
            hasRepeat = true;
            ensureWatchedKey(keyName);
        }
    }
    /**
     * offRepeat(keyName, callback): 取消指定键的重复触发事件订阅。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 回调函数
     */
    public static function offRepeat(keyName:String, callback:Function):Void {
        eventBus.unsubscribe("Repeat_" + keyName, callback);
        var code:Number = getKeySetting(keyName);
        if (!isNaN(code)) {
            delete repeatConfigs[code];
        }
        checkRepeatEmpty();
    }
    /**
     * checkRepeatEmpty(): 检查重复触发配置表是否为空，更新 hasRepeat 标志。
     */
    private static function checkRepeatEmpty():Void {
        for (var k:String in repeatConfigs) {
            return;
        }
        hasRepeat = false;
    }

    //============================
    // 动态修改监听按键范围接口
    //============================
    /**
     * updateWatchedKeys(newKeyNames):
     *   通过传入的键名数组，重新构建 watchedKeys、watchedKeyNames、keyStates 以及
     *   watchedEventNames 的内容。便于只监听指定的按键，避免不必要的轮询消耗。
     *
     * @param newKeyNames:Array - 需要监听的键名数组，例如 ["互动键", "武器技能键"]
     */
    public static function updateWatchedKeys(newKeyNames:Array):Void {
        // 清空当前所有相关数据
        for (var codeStr:String in watchedKeys) {
            delete watchedKeys[codeStr];
        }
        for (var codeStr2:String in watchedKeyNames) {
            delete watchedKeyNames[codeStr2];
        }
        for (var codeStr3:String in keyStates) {
            delete keyStates[codeStr3];
        }
        for (var codeStr4:String in watchedEventNames) {
            delete watchedEventNames[codeStr4];
        }

        // 根据 newKeyNames 重构各数据结构
        for (var i:Number = 0; i < newKeyNames.length; i++) {
            var name:String = newKeyNames[i];
            var code:Number = getKeySetting(name);
            if (!isNaN(code)) {
                watchedKeys[code] = true;
                watchedKeyNames[code] = name;
                keyStates[code] = false;
                if (!watchedEventNames[code]) {
                    watchedEventNames[code] = {};
                }
                watchedEventNames[code].down = "KeyDown_" + name;
                watchedEventNames[code].up   = "KeyUp_" + name;
            }
        }
    }

    //============================
    // 带生命周期管理的扩展方法（自动取消订阅）
    //============================
    /**
     * onKeyDownL(keyName, callback, scope, host):
     *   带生命周期管理的 KeyDown 事件订阅，
     *   当 host MovieClip 卸载时自动取消订阅。
     *
     * @param keyName:String - 键名
     * @param callback:Function - 回调函数
     * @param scope:Object - 作用域
     * @param host:MovieClip - 托管生命周期的 MovieClip 对象
     */
    public static function onKeyDownL(keyName:String, callback:Function, scope:Object, host:MovieClip):Void {
        onKeyDown(keyName, callback, scope);
        var unsubFunc:Function = function() {
            KeyManager.offKeyDown(keyName, callback);
        };
        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    /**
     * onceKeyDownL(keyName, callback, scope, host):
     *   带生命周期管理的一次性 KeyDown 事件订阅，
     *   回调触发后自动取消订阅，并在 host 卸载时取消订阅。
     */
    public static function onceKeyDownL(keyName:String, callback:Function, scope:Object, host:MovieClip):Void {
        onceKeyDown(keyName, callback, scope);
        var unsubFunc:Function = function() {
            KeyManager.offKeyDown(keyName, callback);
        };
        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    /**
     * onKeyUpL(keyName, callback, scope, host):
     *   带生命周期管理的 KeyUp 事件订阅，
     *   当 host 卸载时自动取消订阅。
     */
    public static function onKeyUpL(keyName:String, callback:Function, scope:Object, host:MovieClip):Void {
        onKeyUp(keyName, callback, scope);
        var unsubFunc:Function = function() {
            KeyManager.offKeyUp(keyName, callback);
        };
        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    /**
     * onceKeyUpL(keyName, callback, scope, host):
     *   带生命周期管理的一次性 KeyUp 事件订阅，触发后自动取消订阅。
     */
    public static function onceKeyUpL(keyName:String, callback:Function, scope:Object, host:MovieClip):Void {
        onceKeyUp(keyName, callback, scope);
        var unsubFunc:Function = function() {
            KeyManager.offKeyUp(keyName, callback);
        };
        host = host || scope || _root;
        EventCoordinator.addUnloadCallback(host, unsubFunc);
    }

    /**
     * onLongPressL(keyName, thresholdFrames, callback, scope, host):
     *   带生命周期管理的长按事件订阅，自动管理订阅生命周期。
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
     * onCombinationL(combinationName, keyNames, callback, scope, continuous, host):
     *   带生命周期管理的组合键事件订阅。
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
     * onDoubleTapL(keyName, intervalFrames, callback, scope, host):
     *   带生命周期管理的双击事件订阅。
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
     * onRepeatL(keyName, intervalFrames, callback, scope, host):
     *   带生命周期管理的重复触发事件订阅。
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
