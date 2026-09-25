/** Visual-only projection. Gameplay time, night vision and rewards stay in WeatherSystem. */
import org.flashNight.arki.render.WeatherParticleRenderer;
import org.flashNight.arki.render.GameWorldOverlayRenderer;
class org.flashNight.arki.weather.WorldLightingBridge {
    private static var _sequence:Number = 0;
    private static var _scene:Number = 1;
    private static var _ready:Boolean = false;
    private static var _lastSend:Number = -1000;
    private static var _mode:String = "光照";
    private static var _snap:Boolean = true;

    public static function sceneChanged():Void {
        _scene++; _snap=true;
        _ready = false;
        _lastSend = -1000;
        _mode = "光照";
    }
    public static function sceneReady():Void { _ready = true; _lastSend = -1000; }
    public static function setMode(mode:String):Void { if (_mode !== mode) _snap=true; _mode = mode; }
    public static function snapNext():Void { _snap=true; }

    // Pure continuous light calculation. Does not advance WeatherSystem's gameplay clock
    // or overwrite its quantized authoritative light/reward state.
    public static function visualLight(ws:Object, frame:Number):Number {
        var time:Number = ws.enableDayNightCycle ? ws.currentTime : 7;
        if (ws.enableDayNightCycle && !ws.pauseDayNightCycle) time = (time + (frame - ws.currentFrame) / ws.hourFrames) % 24;
        var level:Number = 0;
        if ((time < 4 && time > 1) || (time < 13 && time > 11) || (time < 21 && time > 18)) {
            var first:Number = Math.floor(time);
            var ratio:Number = time - first;
            level = ws.dayNightLightLevels[first] * (1-ratio) + ws.dayNightLightLevels[Math.ceil(time)] * ratio;
        } else if ((time <= 11 && time >= 4) || (time <= 18 && time >= 13)) level = 7;
        return Math.max(ws.minLight, Math.min(ws.maxLight, level));
    }
    public static function parameters(table:Object, light:Number):Array {
        if (light === 7) return [1,1,1,1,0,0,0,0];
        var first:Number = light > 9 ? 8 : Math.floor(light);
        var last:Number = light > 9 ? 9 : Math.ceil(light);
        var a:Object = table[first];
        var b:Object = table[last];
        if (a == null || b == null) return null;
        var keys:Array = ["红色乘数","绿色乘数","蓝色乘数","透明乘数","亮度","对比度","饱和度","色相"];
        var ratio:Number = first === last ? 0 : (light-first)/(last-first);
        var result:Array = [];
        for (var i:Number=0; i<keys.length; i++) {
            var value:Number = Number(a[keys[i]])*(1-ratio)+Number(b[keys[i]])*ratio;
            if (isNaN(value) || !isFinite(value)) return null;
            result.push(value);
        }
        return result;
    }
    public static function neutralize(target:MovieClip):Void {
        if (!target || target.__nativeLightScene === _scene) return;
        org.flashNight.arki.component.Effect.ColorEngine.checkAndRemoveFilter(target, flash.filters.ColorMatrixFilter);
        target.transform.colorTransform = new flash.geom.ColorTransform();
        target.__nativeLightScene = _scene;
        _global.ASSetPropFlags(target, ["__nativeLightScene"], 1, false);
    }
    public static function publish(ws:Object, force:Boolean):Void {
        var now:Number = getTimer();
        if (!force && now-_lastSend < 500 && now >= _lastSend) return;
        var server:Object = _root.server;
        if (!server.isSocketConnected || typeof server.sendTaskToNode != "function") return;
        var frame:Number = _root.帧计时器.当前帧数;
        var light:Number = visualLight(ws,frame);
        if (isNaN(light) || !isFinite(light)) return;
        var values:Array = parameters(_root.色彩引擎.光照等级映射表[_mode],light);
        if (values == null) return;
        neutralize(_root.gameworld);
        neutralize(_root.天空盒);
        var weatherType:String = WeatherParticleRenderer.getWeatherType();
        if (weatherType != "rain" && weatherType != "snow" && weatherType != "dust"
                && weatherType != "fog" && weatherType != "slash") weatherType = "none";
        var weatherIntensity:Number = WeatherParticleRenderer.getWeatherIntensity();
        if (isNaN(weatherIntensity) || !isFinite(weatherIntensity) || weatherIntensity < 0) weatherIntensity = 0;
        if (weatherIntensity > 1) weatherIntensity = 1;
        var weatherQuality:Number = WeatherParticleRenderer.getPerformanceLevel();
        if (isNaN(weatherQuality) || weatherQuality < 0 || weatherQuality > 3) weatherQuality = 3;
        weatherQuality = Math.floor(weatherQuality);
        // 仅投影旧雨花使用的 2.5D 地面带；无需逐粒子碰撞或复制碰撞箱。
        var groundMin:Number = Number(_root.Ymin);
        var groundMax:Number = Number(_root.Ymax);
        if (isNaN(groundMin) || !isFinite(groundMin) || isNaN(groundMax)
                || !isFinite(groundMax) || groundMax <= groundMin) {
            groundMin = 360; groundMax = 520;
        }
        var sent:Boolean = server.sendTaskToNode("world_lighting", {
            version:1, sequence:++_sequence, scene:_scene, ready:_ready,
            light:light, mode:_mode, parameters:values,
            paused:ws.pauseDayNightCycle === true, immediate:_snap,
            sourceNeutral:true,
            weatherNative:WeatherParticleRenderer.isNativeEnabled(),
            weatherType:weatherType, weatherIntensity:weatherIntensity,
            weatherQuality:weatherQuality,
            weatherGroundMin:groundMin, weatherGroundMax:groundMax,
            atmosphere:GameWorldOverlayRenderer.getState()
        }, null) === true;
        if (sent) { _lastSend = now; _snap=false; }
    }
}
