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
        trace("WorldLightingBridgeTest Tests Passed: "+passed);
        trace("WorldLightingBridgeTest Tests Failed: "+failed);
    }
}
