// 文件路径：org/flashNight/aven/test/Logger.as
class org.flashNight.aven.test.Logger {
    public static var LEVEL_INFO:Number = 1;
    public static var LEVEL_WARN:Number = 2;
    public static var LEVEL_ERROR:Number = 3;

    private static var currentLevel:Number = LEVEL_INFO;
    private static var isMuted:Boolean = false;

    public static function setLevel(level:Number):Void {
        currentLevel = level;
    }

    public static function mute():Void {
        isMuted = true;
    }

    public static function unmute():Void {
        isMuted = false;
    }

    public static function info(message:String):Void {
        if (!isMuted && currentLevel <= LEVEL_INFO) {
            trace("[INFO] " + message);
        }
    }

    public static function warn(message:String):Void {
        if (!isMuted && currentLevel <= LEVEL_WARN) {
            trace("[WARN] " + message);
        }
    }

    public static function error(message:String):Void {
        if (!isMuted && currentLevel <= LEVEL_ERROR) {
            trace("[ERROR] " + message);
        }
    }
}
