/**
 * InputEvent - 输入事件常量定义
 *
 * 定义搓招系统使用的所有输入事件类型。
 * 采用方向归一化设计：前/后/上/下，不区分左右。
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.neur.InputCommand.InputEvent {

    // ========== 事件ID常量 ==========

    // 无事件
    public static var NONE:Number = 0;

    // === 方向事件（归一化：前/后，不区分左右）===
    public static var FORWARD:Number      = 1;  // 前（面向方向）
    public static var BACK:Number         = 2;  // 后（背向方向）
    public static var DOWN:Number         = 3;  // 下
    public static var UP:Number           = 4;  // 上
    public static var DOWN_FORWARD:Number = 5;  // 下前（↘ 或 ↙）
    public static var DOWN_BACK:Number    = 6;  // 下后
    public static var UP_FORWARD:Number   = 7;  // 上前
    public static var UP_BACK:Number      = 8;  // 上后

    // === 按键边沿事件（按下瞬间触发）===
    public static var A_PRESS:Number      = 9;   // A键（攻击/动作A）
    public static var B_PRESS:Number      = 10;  // B键（跳跃/动作B）
    public static var C_PRESS:Number      = 11;  // C键（预留）

    // === 复合事件（特殊输入模式）===
    public static var DOUBLE_TAP_FORWARD:Number = 12;  // 双击前
    public static var DOUBLE_TAP_BACK:Number    = 13;  // 双击后
    public static var SHIFT_HOLD:Number         = 14;  // Shift持续按住
    public static var SHIFT_FORWARD:Number      = 15;  // Shift + 前
    public static var SHIFT_BACK:Number         = 16;  // Shift + 后
    public static var SHIFT_DOWN:Number         = 17;  // Shift + 下

    // === 事件总数（用于DFA数组分配）===
    public static var COUNT:Number = 18;

    // ========== 事件名称映射（用于调试和UI）==========

    private static var _names:Array = null;

    /**
     * 获取事件名称数组（延迟初始化）
     */
    public static function getNames():Array {
        if (_names == null) {
            _names = [];
            _names[NONE]              = "NONE";
            _names[FORWARD]           = "→";
            _names[BACK]              = "←";
            _names[DOWN]              = "↓";
            _names[UP]                = "↑";
            _names[DOWN_FORWARD]      = "↘";
            _names[DOWN_BACK]         = "↙";
            _names[UP_FORWARD]        = "↗";
            _names[UP_BACK]           = "↖";
            _names[A_PRESS]           = "A";
            _names[B_PRESS]           = "B";
            _names[C_PRESS]           = "C";
            _names[DOUBLE_TAP_FORWARD]= "→→";
            _names[DOUBLE_TAP_BACK]   = "←←";
            _names[SHIFT_HOLD]        = "Shift";
            _names[SHIFT_FORWARD]     = "Shift+→";
            _names[SHIFT_BACK]        = "Shift+←";
            _names[SHIFT_DOWN]        = "Shift+↓";
        }
        return _names;
    }

    /**
     * 获取单个事件的显示名称
     */
    public static function getName(eventId:Number):String {
        var names:Array = getNames();
        if (eventId >= 0 && eventId < names.length) {
            return names[eventId];
        }
        return "?";
    }

    /**
     * 将事件序列转换为可读字符串
     * @param events 事件ID数组
     * @return 格式如 "↓↘→A"
     */
    public static function sequenceToString(events:Array):String {
        var result:String = "";
        for (var i:Number = 0; i < events.length; i++) {
            result += getName(events[i]);
        }
        return result;
    }
}
