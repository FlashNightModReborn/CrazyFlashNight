this.stop();
var home:MovieClip = this;
var phase:String = "waiting";
var probeframes:Number = 0;
var framed:Number = 0;
var callbackCount:Number = 0;
var shots:Number = 0;
var simple:Object;
var fast:Object;
var enhanced:Object;
var shoot:Object;
var fighter:Object;
var lockOwner:Object;
var additive:MovieClip;
var ordinary:MovieClip;
var semi:Object;
var semiShots:Number=0;
var debounceCallbacks:Number=0;
var saveState:Object;
var originalDebounce:Function;
var beforeHandoff:MovieClip;
var capture:Array = [];
var label:String = String(home._url).split("/").slice(-2)[0];
function saveSample(msg:String):Void {
    var line:String = "WHEEL_PROBE " + label + " " + msg;
    trace(line);
    capture.push(line);
    var so:SharedObject = SharedObject.getLocal("cf7_wheel_fixture_9c65e2");
    so.data.report = capture.join("\n");
    so.flush();
}
function layers():String {
    var result:String = "";
    var depths:Array = [0,1,2,1024,65531,65532,65533,65534,65535,1048575,1048576];
    for (var j:Number=0; j<depths.length; j++) {
        var d:Number=depths[j];
        var occupant:MovieClip=home.getInstanceAtDepth(d);
        if (occupant != undefined) result+=" "+d+"="+occupant._name;
    }
    return result;
}
function sample(tag:String):Void {
    var p:Object = _global.org.flashNight;
    var cl:Object = p.neur.ScheduleTimer.CooldownWheel;
    var en:Object = p.neur.ScheduleTimer.EnhancedCooldownWheel;
    var clip:MovieClip = home._cdWheel;
    saveSample(tag+" clock="+clip+" depth="+clip.getDepth()+" frameFn="+typeof(clip.onEnterFrame)
        +" basePos="+cl.inst.pos+" size="+cl.WHEEL_SIZE+" mask="+cl.WHEEL_MASK
        +" enhanced="+(en.inst != undefined)+" fast="+(en.inst.fastWheel === cl.inst)+layers());
}
function startCases():Void {
    var p:Object = _global.org.flashNight;
    var cl:Object = p.neur.ScheduleTimer.CooldownWheel;
    var en:Object = p.neur.ScheduleTimer.EnhancedCooldownWheel;
    fast=cl.I();
    enhanced=en.I();
    simple={hits:0};
    fast.add(2,function():Void {simple.hits++;});
    enhanced.addTask(function():Void {callbackCount++;},33,3);
    shoot=p.arki.unit.Action.Shoot.ShootCore;
    lockOwner={_name:"probeLock"};
    shoot.armRateLimit(lockOwner,"rate",66);
    fighter={_name:"probeAuto",攻击模式:"长枪",长枪:{value:{shot:0}},长枪弹匣容量:50,
        长枪属性:{},射击中:false,dispatcher:{publish:function():Void {}}};
    var params:Object=shoot.primaryParams;
    fighter[params.actionFlagName]=true;
    fighter.man={射击许可标签:true,射击速度:66,是否单发:false,子弹属性:{ammoCost:1},
        prepareStandardShotPose:function():Void {}};
    fighter.长枪射击=function():Boolean {shots++; this.长枪.value.shot++; return true;};
    shoot.startShooting(fighter,fighter.man,params);
    var world:MovieClip=home.createEmptyMovieClip("gameworld",121);
    world.createEmptyMovieClip("deadbody",3);
    home.控制目标="probeSemi";
    semi=world.createEmptyMovieClip("probeSemi",11);
    semi.攻击模式="长枪";
    semi.长枪={value:{shot:0}};
    semi.长枪弹匣容量=50;
    semi.长枪属性={};
    semi.dispatcher={publish:function():Void {}};
    semi[params.actionFlagName]=true;
    semi.man={射击许可标签:true,射击速度:66,是否单发:true,子弹属性:{ammoCost:1},prepareStandardShotPose:function():Void {}};
    semi.长枪射击=function():Boolean {semiShots++;this.长枪.value.shot++;return true;};
    shoot.startShooting(semi,semi.man,params);
    // Exercise the real public debounce ingress and wheel with a counter at the
    // callback boundary. No serializer, player slot or host dispatch is invoked.
    home.允许存档=true;
    saveState=p.neur.Server.SaveManager.getInstance();
    originalDebounce=saveState._onDebounceFireGuarded;
    saveState._onDebounceFireGuarded=function():Void {debounceCallbacks++;};
    saveSample("debounce-start accepted="+saveState.saveAll());
    var renderer:Object=p.arki.render.VectorAfterimageRenderer.instance;
    renderer.onSceneChanged();
    additive=renderer.getAdditiveCanvas(3);
    ordinary=renderer.getAvailableCanvas(5);
    var cs:Array=[ordinary,additive];
    for (var i:Number=0;i<cs.length;i++) {
        var c:MovieClip=cs[i];
        c.beginFill(0xff0000,100); c.moveTo(0,0); c.lineTo(8,0); c.lineTo(0,8); c.endFill();
    }
    sample("cases-start");
    saveSample("initial shots="+shots+" lock="+(shoot._lastShotTimes.probeLock_rate!=undefined)
         +" semiShots="+semiShots+" ordinaryDepth="+ordinary.getDepth()+" additiveDepth="+additive.getDepth()+" sameCanvas="+(ordinary===additive)+" ordinaryBlend="+ordinary.blendMode+" addBlend="+additive.blendMode+" normal="+ordinary+" add="+additive+" alpha="+ordinary._alpha+","+additive._alpha);
    phase="cases";
    framed=0;
}
function installHook():Void {
    var bootClass:Function = _global.org.flashNight.boot.BootSequencer;
    if (typeof bootClass != "function" || phase!="waiting") return;
    phase="installed";
    sample("class-loaded");
    bootClass.run=function(definitions:MovieClip):Void {
        sample("before-S1");
        var b:Object=home.__boot;
        b.f2_1();
        sample("after-S1-f2_1");
        beforeHandoff=home._cdWheel;
        _global.org.flashNight.arki.cursor.MouseProxy.ensureContainer();
        sample("after-mouse");
        var seq:Object=new bootClass(definitions);
        seq.handoff();
        sample("after-handoff");
        startCases();
    };
}
saveSample("begin");
installHook();
home.onEnterFrame=function():Void {
    probeframes++;
    installHook();
    if (phase=="cases") {
        framed++;
        if(framed<=4) sample("authored-"+home._currentframe+"-tick"+framed);
        if(framed==5) {
            // Attempting again before a key-up must be rejected for ordinary semi auto.
            shoot.startShooting(semi,semi.man,shoot.primaryParams);
            saveSample("semi-held-t5 shots="+semiShots);
        }
        if(framed==9) semi[shoot.primaryParams.actionFlagName]=false;
        if(framed==12) fighter[shoot.primaryParams.actionFlagName]=false;
        if(framed==15) {
            semi[shoot.primaryParams.actionFlagName]=true;
            shoot.startShooting(semi,semi.man,shoot.primaryParams);
            saveSample("semi-retap-t15 shots="+semiShots+" callback="+debounceCallbacks);
        }
        if(framed==18) semi[shoot.primaryParams.actionFlagName]=false;
        if(framed==23) {
            semi[shoot.primaryParams.actionFlagName]=true;
            shoot.startShooting(semi,semi.man,shoot.primaryParams);
            saveSample("semi-retap-t23 shots="+semiShots+" callback="+debounceCallbacks);
        }
        if(framed==16 || framed==24) {
            sample("frame"+framed);
            saveSample("measure t="+framed+" plain="+simple.hits+" repeats="+callbackCount+
                " shots="+shots+" lock="+(shoot._lastShotTimes.probeLock_rate!=undefined)+
                " shooting="+fighter[shoot.primaryParams.shootingStateName]+
                " heldTask="+fighter[shoot.primaryParams.taskName]+
                " normal.visible="+ordinary._visible+" normal.alpha="+ordinary._alpha+
                " normal.cycle="+ordinary.cycleCount+" normal.bounds="+ordinary._width+
                " add.visible="+additive._visible+" add.alpha="+additive._alpha+
                " add.cycle="+additive.cycleCount+" add.bounds="+additive._width+
                " sameDriver="+(beforeHandoff===home._cdWheel));
            if (framed==16) {fighter[shoot.primaryParams.actionFlagName]=true; shoot.startShooting(fighter,fighter.man,shoot.primaryParams);}
            if (framed==24) {home.允许存档=false;saveState._onDebounceFireGuarded=originalDebounce;saveSample("complete");phase="done";fscommand("quit");}
        }
    }
    if(probeframes>500 && phase!="done") {saveSample("timeout "+phase);phase="done";fscommand("quit");}
};
