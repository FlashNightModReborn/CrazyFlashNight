import org.flashNight.neur.PerformanceOptimizer.PerformanceActuator;

/** 显式画质、表现预算和业务参数隔离。 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceActuatorTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var report:String;
    private static function check(value:Boolean,name:String):Void {
        if (value) passed++; else failed++;
        report += (value ? "  ✓ " : "  ✗ ") + name + "\n";
    }
    public static function getPassedCount():Number { return passed; }
    public static function getFailedCount():Number { return failed; }

    private static function makeMocks():Object {
        var displayList:Object = {预设任务ID:"TASK", playing:false,
            继续播放:function(id):Void {this.playing=true;},
            暂停播放:function(id):Void {this.playing=false;}};
        var root:Object = {_quality:"MEDIUM",面积系数:543210,发射效果上限:15,
            天气系统:{lightUpdateThreshold:0.1},显示列表:displayList};
        var es:Object = {};
        var dr:Object = {};
        var shell:Object = {limit:0,setMaxShellCountLimit:function(v):Void {this.limit=v;}};
        var trail:Object = {q:0,setQuality:function(v):Void {this.q=v;}};
        var trailFactory:Object = {instance:trail,getInstance:function():Object {return this.instance;}};
        var clip:Object = {level:0,setPerformanceLevel:function(v):Void {this.level=v;}};
        var blade:Object = {level:0,setPerformanceLevel:function(v):Void {this.level=v;}};
        var weather:Object = {level:0,setPerformanceLevel:function(v):Void {this.level=v;}};
        var sky:Object = {level:0,setPerformanceLevel:function(v):Void {this.level=v;}};
        var host:Object = {offsetTolerance:23};
        var actuator:PerformanceActuator = new PerformanceActuator(host,"LOW",{
            root:root,EffectSystem:es,DeathEffectRenderer:dr,ShellSystem:shell,
            TrailRenderer:trailFactory,ClipFrameRenderer:clip,BladeMotionTrailsRenderer:blade,
            WeatherParticleRenderer:weather,SkyboxRenderer:sky});
        return {actuator:actuator,root:root,host:host,display:displayList,es:es,dr:dr,
            shell:shell,trail:trail,clip:clip,blade:blade,weather:weather,sky:sky};
    }

    public static function runAllTests():String {
        passed=0; failed=0; report="=== PerformanceActuatorTest ===\n";
        var m:Object = makeMocks();
        var qualities:Array = ["LOW","MEDIUM","HIGH","BEST"];
        for(var i:Number=0;i<qualities.length;i++) {
            var quality:String = qualities[i];
            var tier:Number = quality == "LOW" ? 1 : 0;
            check(m.actuator.apply(tier,0,quality) === true && m.root._quality == quality,
                "显式画质不受旧 LOW 预设限制："+quality);
        }
        check(m.display.playing && m.root.__nativeHudDecorations,"非 LOW 继续播放并启用既有 HUD 装饰");
        m.actuator.apply(1,0,"LOW");
        check(!m.display.playing && !m.root.__nativeHudDecorations,"LOW 使用既有显示列表与装饰预算");
        m.actuator.apply(0,0,"HIGH");
        check(m.es.maxEffectCount==20 && m.es.maxScreenEffectCount==20 && m.shell.limit==25
            && m.root.发射效果上限==15 && m.trail.q==0,"完整表现预算");
        m.actuator.apply(0,0.5,"MEDIUM");
        check(m.es.maxEffectCount==10 && m.es.maxScreenEffectCount==13 && m.shell.limit==18
            && m.root.发射效果上限==8 && m.trail.q==2,"中等表现预算");
        m.actuator.apply(1,1,"LOW");
        check(m.es.maxEffectCount==0 && m.es.maxScreenEffectCount==5 && m.shell.limit==10
            && m.root.发射效果上限==0 && m.trail.q==3,"最低表现预算");
        check(m.clip.level==3 && m.blade.level==3 && m.weather.level==3 && m.sky.level==3,"剩余 Flash 渲染器接收同一预算");
        check(m.es.isDeathEffect && m.dr.isEnabled && m.dr.enableCulling,"死亡表现与离屏剔除始终保留");
        check(m.root.面积系数==543210 && m.host.offsetTolerance==23,"表现预算不改 NPC 密度或镜头业务参数");
        check(m.actuator.apply(0,0,"INVALID") === false && m.root._quality=="LOW","非法画质不写运行态");
        check(m.actuator.apply(0,0) === false && m.root._quality=="LOW","不接受缺失显式画质的旧调用");
        check(m.actuator.apply(0,0,"LOW") === false && m.root._quality=="LOW","画质与 tier 不一致时拒绝");
        check(m.actuator.apply(0,Number("bad"),"HIGH") === false && m.root._quality=="LOW","非法预算不写运行态");
        m.root.addProperty("_quality",function():String {return "MEDIUM";},function(value:String):Void {});
        check(m.actuator.apply(0,0,"HIGH") === false && m.es.maxEffectCount==0,"Flash 未接受画质时不假报成功或继续写预算");
        return report;
    }
}
