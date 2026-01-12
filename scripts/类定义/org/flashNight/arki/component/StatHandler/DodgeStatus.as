/**
 * DodgeStatus
 * 存储所有可能的躲闪状态字符串作为静态常量。
 */
class org.flashNight.arki.component.StatHandler.DodgeStatus
{
    public static var INSTANT_FEEL:String = "直感";
    public static var DODGE:String = "躲闪";
    public static var JUMP_BOUNCE:String = "跳弹";
    public static var PENETRATION:String = "过穿";
    public static var BLOCK:String = "格挡";
    public static var NOT_DODGE:String = "未躲闪";

    /**
     * 联弹分段躲闪建模适用状态查找表
     * 用于 O(1) 判断某个 dodgeState 是否需要走分段建模路径
     * 包含：躲闪、跳弹、过穿、直感（懒闪避）
     */
    public static var CHAIN_DODGE_MODEL:Object = createChainDodgeModelLookup();

    private static function createChainDodgeModelLookup():Object {
        var lookup:Object = {};
        lookup[INSTANT_FEEL] = true;
        lookup[DODGE] = true;
        lookup[JUMP_BOUNCE] = true;
        lookup[PENETRATION] = true;
        return lookup;
    }
}
