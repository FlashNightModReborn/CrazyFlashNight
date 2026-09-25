/**
 * Pure atmosphere projection. WeatherSystem chooses the authored environment;
 * the paired Host renders it in the world compositor. No AS2 drawing path.
 */
class org.flashNight.arki.render.GameWorldOverlayRenderer {
    private static var _state:Object = {
        preset:"none", r:0, g:0, b:0, alpha:0,
        mode:"flat", pulse:false, pulseSpeed:0.08, pulseMin:5, pulseMax:20
    };

    private static function bounded(value:Number, fallback:Number, low:Number, high:Number):Number {
        var result:Number = Number(value);
        if (isNaN(result) || !isFinite(result)) return fallback;
        if (result < low) return low;
        if (result > high) return high;
        return result;
    }

    private static function presetName(value:String):String {
        if (value == null || value == undefined || value.length < 1 || value.length > 48
                || value == "雨" || value == "雪" || value == "沙尘") return "none";
        return value;
    }

    public static function configure(overlay:Object, preset:String):Void {
        var name:String = overlay != null ? "custom" : presetName(preset);
        if (name == "none") {
            dispose();
            return;
        }
        if (overlay == null) overlay = {};
        var minimum:Number = bounded(overlay.pulseMin, 5, 0, 100);
        var maximum:Number = bounded(overlay.pulseMax, 20, minimum, 100);
        _state = {
            preset:name,
            r:bounded(overlay.r, 0, 0, 255),
            g:bounded(overlay.g, 0, 0, 255),
            b:bounded(overlay.b, 0, 0, 255),
            alpha:bounded(overlay.alpha, 0, 0, 100),
            mode:overlay.mode == "radial" ? "radial" : "flat",
            pulse:overlay.pulse === true,
            pulseSpeed:bounded(overlay.pulseSpeed, 0.08, 0, 1),
            pulseMin:minimum,
            pulseMax:maximum
        };
    }

    public static function getState():Object {
        return {
            preset:_state.preset, r:_state.r, g:_state.g, b:_state.b,
            alpha:_state.alpha, mode:_state.mode, pulse:_state.pulse,
            pulseSpeed:_state.pulseSpeed, pulseMin:_state.pulseMin,
            pulseMax:_state.pulseMax
        };
    }

    public static function dispose():Void {
        _state = {
            preset:"none", r:0, g:0, b:0, alpha:0,
            mode:"flat", pulse:false, pulseSpeed:0.08, pulseMin:5, pulseMax:20
        };
    }
}
