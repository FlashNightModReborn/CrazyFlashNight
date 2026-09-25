/**
 * Weather presentation state projected to the paired native compositor.
 * AS2 owns selection and intensity; it never draws weather pixels.
 */
class org.flashNight.arki.render.WeatherParticleRenderer {
    private static var _type:String = "none";
    private static var _intensity:Number = 0;
    private static var _performanceLevel:Number = 0;
    private static var _nativeEnabled:Boolean = false;

    public static function dispose():Void {
        _type = "none";
        _intensity = 0;
    }

    // Retained as a wire-compatible diagnostic value. Native uses its own
    // bounded particle budget and ignores the AS2 performance level.
    public static function setPerformanceLevel(level:Number):Void {
        _performanceLevel = level;
    }
    public static function getPerformanceLevel():Number { return _performanceLevel; }

    // Capability is scoped to the current Host connection. A lost capability
    // leaves the selected weather state intact for a later native recovery.
    public static function setNativeEnabled(enabled:Boolean):Void {
        _nativeEnabled = enabled;
    }
    private static function _isNativeType(type:String):Boolean {
        return type == "rain" || type == "snow" || type == "dust"
            || type == "fog" || type == "slash";
    }
    public static function isNativeEnabled():Boolean {
        return _nativeEnabled && _isNativeType(_type);
    }
    public static function getWeatherType():String { return _type; }
    public static function getWeatherIntensity():Number { return _intensity; }

    public static function setWeather(type:String, intensity:Number):Void {
        if (type == "none" || type == undefined || intensity <= 0) {
            _type = "none";
            _intensity = 0;
            return;
        }
        _type = type;
        _intensity = intensity;
    }
}
