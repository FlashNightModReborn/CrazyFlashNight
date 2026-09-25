/** C1-I bootstrap installs this capability BEFORE loading any game classes.
 *  It suppresses legacy drivers at construction, never cleans them up after start.
 *  Absent capability preserves normal game behavior; malformed capability fails closed.
 */
class org.flashNight.arki.input.IsolatedInputPolicy {
    private static var _present:Boolean = _global.__cf7InputIsolationBootstrapV1 != undefined;
    private static var _valid:Boolean = _present && _global.__cf7InputIsolationBootstrapV1.v === 1
        && _global.__cf7InputIsolationBootstrapV1.mode === "closed-legacy-drivers"
        && _global.__cf7InputIsolationBootstrapV1.module === "C1Island.swf";
    private static var _denied:Number = 0;
    public static function forbidsLegacyDrivers():Boolean { return _present; }
    public static function isValid():Boolean { return _valid; }
    public static function rejectLegacyTask():Number { _denied++; return -1; }
    public static function snapshot():Object { return {present:_present, valid:_valid, deniedTasks:_denied}; }
}