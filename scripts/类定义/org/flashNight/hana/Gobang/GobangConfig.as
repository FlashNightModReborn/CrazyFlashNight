class org.flashNight.hana.Gobang.GobangConfig {
    public static var enableCache:Boolean = true;
    public static var pointsLimit:Number = 20;
    public static var onlyInLine:Boolean = false;
    public static var inlineCount:Number = 4;
    public static var inLineDistance:Number = 5;
    public static var searchDepth:Number = 8;

    public static function roleIndex(role:Number):Number {
        return role === 1 ? 0 : 1;
    }
}
