class org.flashNight.arki.weather.WorldLightingBridgeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,name:String):Void {
        if(value) passed++; else { failed++; trace("FAIL WorldLightingBridgeTest: "+name); }
    }
    public static function runAllTests():Void {
        passed=0; failed=0;
        var levels:Array=[0,0,1,4,7,7,7,7,7,7,7,7,9,7,7,7,7,7,7,4,1,0,0,0];
        var ws:Object={enableDayNightCycle:true,pauseDayNightCycle:false,currentTime:2,currentFrame:0,hourFrames:100,dayNightLightLevels:levels,minLight:0,maxLight:9};
        check(Math.abs(org.flashNight.arki.weather.WorldLightingBridge.visualLight(ws,1)-1.03)<0.00001,"continuous without 0.1 quantization");
        check(ws.currentTime===2 && ws.currentFrame===0,"does not mutate clock");
        ws.pauseDayNightCycle=true;
        check(org.flashNight.arki.weather.WorldLightingBridge.visualLight(ws,50)===1,"pause freezes progression");
        ws.enableDayNightCycle=false;
        check(org.flashNight.arki.weather.WorldLightingBridge.visualLight(ws,50)===7,"disabled neutral");
        ws.maxLight=2.5;
        check(org.flashNight.arki.weather.WorldLightingBridge.visualLight(ws,50)===2.5,"disabled cycle retains environment clamp");
        ws.maxLight=9;ws.enableDayNightCycle=true;ws.minLight=3;
        check(org.flashNight.arki.weather.WorldLightingBridge.visualLight(ws,50)===3,"environment clamp");
        var table:Object={};
        table[1]={红色乘数:0.5,绿色乘数:0.6,蓝色乘数:0.7,透明乘数:1,亮度:-20,对比度:10,饱和度:-40,色相:20};
        table[2]={红色乘数:1,绿色乘数:1,蓝色乘数:1,透明乘数:1,亮度:0,对比度:20,饱和度:0,色相:0};
        var values:Array=org.flashNight.arki.weather.WorldLightingBridge.parameters(table,1.5);
        check(values.length===8,"closed eight-parameter wire");
        check(values[0]===0.75 && values[4]===-10 && values[6]===-20,"legacy parameter interpolation");
        check(org.flashNight.arki.weather.WorldLightingBridge.parameters(table,3)===null,"missing preset rejected");
        values=org.flashNight.arki.weather.WorldLightingBridge.parameters(null,7);
        check(values[0]===1 && values[4]===0,"neutral independent of table");
        var clip:MovieClip=_root.createEmptyMovieClip("lightingTest",76543);
        clip.filters=[new flash.filters.BlurFilter(),new flash.filters.ColorMatrixFilter()];
        var transform:flash.geom.ColorTransform=new flash.geom.ColorTransform();transform.redMultiplier=0.3;
        clip.transform.colorTransform=transform;
        org.flashNight.arki.weather.WorldLightingBridge.neutralize(clip);
        check(clip.transform.colorTransform.redMultiplier===1,"old color transform removed");
        check(clip.filters.length===1 && clip.filters[0] instanceof flash.filters.BlurFilter,"only old matrix filter removed");
        clip.removeMovieClip();
        // Weather selection survives connection loss; neither state draws an AS2 clip.
        var oldWorld:MovieClip=_root.gameworld;
        var weatherWorld:MovieClip=_root.createEmptyMovieClip("weatherBridgeTestWorld",76544);
        _root.gameworld=weatherWorld;
        org.flashNight.arki.render.GameWorldOverlayRenderer.configure(null,"医疗警报");
        var atmosphereState:Object=org.flashNight.arki.render.GameWorldOverlayRenderer.getState();
        check(atmosphereState.preset=="医疗警报" && atmosphereState.alpha===0,
            "named atmosphere projects only the catalog identity");
        check(weatherWorld.__gwOverlay===undefined,"atmosphere projection creates no AS2 drawing clip");
        org.flashNight.arki.render.GameWorldOverlayRenderer.configure(null,"新预设");
        check(org.flashNight.arki.render.GameWorldOverlayRenderer.getState().preset=="新预设",
            "new named atmosphere needs no AS2 whitelist");
        org.flashNight.arki.render.GameWorldOverlayRenderer.configure(null,"雨");
        check(org.flashNight.arki.render.GameWorldOverlayRenderer.getState().preset=="none",
            "weather-only shortcut is not an atmosphere look");
        org.flashNight.arki.render.GameWorldOverlayRenderer.configure({
            r:150,g:70,b:25,alpha:12,mode:"flat",pulse:false
        },undefined);
        check(org.flashNight.arki.render.GameWorldOverlayRenderer.getState().preset=="custom",
            "direct overlay uses native custom look");
        org.flashNight.arki.render.GameWorldOverlayRenderer.configure(null,"医疗警报");
        org.flashNight.arki.render.WeatherParticleRenderer.setWeather("snow",0.7);
        org.flashNight.arki.render.WeatherParticleRenderer.setNativeEnabled(true);
        check(org.flashNight.arki.render.WeatherParticleRenderer.isNativeEnabled()
            && weatherWorld.__weatherParticles===undefined,"native weather projects state without AS2 drawing");
        org.flashNight.arki.render.WeatherParticleRenderer.setNativeEnabled(false);
        check(!org.flashNight.arki.render.WeatherParticleRenderer.isNativeEnabled()
            && weatherWorld.__weatherParticles===undefined,"disconnect does not restore AS2 weather drawing");
        check(org.flashNight.arki.render.WeatherParticleRenderer.getWeatherType()=="snow"
            && org.flashNight.arki.render.WeatherParticleRenderer.getWeatherIntensity()===0.7,
            "native switch preserves authoritative weather selection");
        org.flashNight.arki.render.WeatherParticleRenderer.dispose();
        weatherWorld.removeMovieClip();
        _root.gameworld=oldWorld;
        // The weather projection shares the existing lighting packet and closes
        // its numeric quality field before crossing the socket boundary.
        var oldServer:Object=_root.server;
        var oldTimer:Object=_root.帧计时器;
        var oldColor:Object=_root.色彩引擎;
        var oldYmin:Number=_root.Ymin;
        var oldYmax:Number=_root.Ymax;
        _root.__weatherWireObserved=null;
        _root.server={isSocketConnected:true,sendTaskToNode:function(task:String,payload:Object,callback:Function):Boolean {
            if(task=="world_lighting") _root.__weatherWireObserved=payload;
            return true;
        }};
        _root.帧计时器={当前帧数:0};
        _root.色彩引擎={光照等级映射表:{光照:{}}};
        _root.Ymin=220; _root.Ymax=500;
        ws.enableDayNightCycle=false;ws.minLight=0;ws.maxLight=9;
        org.flashNight.arki.render.WeatherParticleRenderer.setWeather("snow",0.7);
        org.flashNight.arki.render.WeatherParticleRenderer.setPerformanceLevel(1.5);
        org.flashNight.arki.render.WeatherParticleRenderer.setNativeEnabled(true);
        org.flashNight.arki.weather.WorldLightingBridge.sceneReady();
        org.flashNight.arki.weather.WorldLightingBridge.publish(ws,true);
        var weatherWire:Object=_root.__weatherWireObserved;
        check(weatherWire != null && weatherWire.weatherNative===true && weatherWire.weatherType=="snow"
            && weatherWire.weatherIntensity===0.7,"native weather is projected with light state");
        check(weatherWire != null && weatherWire.weatherQuality===1 && weatherWire.ready===true,
            "weather quality is integral and scene ready is retained");
        check(weatherWire != null && weatherWire.weatherGroundMin===220 && weatherWire.weatherGroundMax===500,
            "native rain receives the legacy depth ground band");
        check(weatherWire != null && weatherWire.atmosphere.preset=="医疗警报"
            && weatherWire.atmosphere.alpha===0,"native atmosphere shares scene lighting packet");
        org.flashNight.arki.render.GameWorldOverlayRenderer.dispose();
        check(org.flashNight.arki.render.GameWorldOverlayRenderer.getState().preset=="none",
            "scene disposal clears native atmosphere state");
        org.flashNight.arki.render.WeatherParticleRenderer.setNativeEnabled(false);
        org.flashNight.arki.render.WeatherParticleRenderer.setWeather("none",0);
        org.flashNight.arki.render.WeatherParticleRenderer.setPerformanceLevel(0);
        _root.server=oldServer;_root.帧计时器=oldTimer;_root.色彩引擎=oldColor;
        _root.Ymin=oldYmin; _root.Ymax=oldYmax;
        delete _root.__weatherWireObserved;
        trace("WorldLightingBridgeTest Tests Passed: "+passed);
        trace("WorldLightingBridgeTest Tests Failed: "+failed);
    }
}
