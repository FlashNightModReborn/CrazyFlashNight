import org.flashNight.aven.Coordinator.EventCoordinator;
import org.flashNight.neur.ScheduleTimer.*;

/** FP20 资格：稳定身份反例、旧粗截止期/顺序差分、零阶段、生命周期、长时和负载。 */
class org.flashNight.dev.SchedulerDebtTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,name:String):Void {
        if(value) passed++;else {failed++;trace("[FAIL] SchedulerDebt "+name);}
    }
    private static function make(legacy:Boolean):Object {
        if(legacy) {
            var old:org.flashNight.dev.schedulerLegacy.CerberusScheduler=new org.flashNight.dev.schedulerLegacy.CerberusScheduler();
            old.initialize(150,60,60,30,0.1);
            return new org.flashNight.dev.schedulerLegacy.TaskManager(old,30);
        }
        var scheduler:CerberusScheduler=new CerberusScheduler();
        return new TaskManager(scheduler,30);
    }
    private static function tick(tm:Object,count:Number):Void {for(var i:Number=0;i<count;i++) tm.updateFrame();}
    private static function alias(mode:String):Void {
        var tm:Object=make(false);var a:String;var d:String;var aCalls:Number=0;var dCalls:Number=0;var dFrame:Number=0;var frame:Number=0;
        a=tm.addTask(function():Void {aCalls++;if(mode=="cancel")tm.removeTask(a);else if(mode=="delay")tm.delayTask(a,300);},1,mode=="delay"?true:1,[]);
        var original:Object=tm.locateTask(a);
        tm.addTask(function():Void {d=tm.addTask(function():Void{dCalls++;dFrame=frame;},1000,1,[]);},1,1,[]);
        frame++;tm.updateFrame();
        check(tm.locateTask(d)!==original,"distinct Task identity "+mode);
        for(var i:Number=0;i<100;i++){frame++;tm.updateFrame();}
        check(dCalls==1&&dFrame==31,"D never orphaned or advanced "+mode);
        check(aCalls==(mode=="delay"?5:1),"A exact repeat count "+mode);
        trace("SchedulerStableProbe mode="+mode+" dCalls="+dCalls+" dFrame="+dFrame+" aCalls="+aCalls);
    }
    private static function deadlineRun(legacy:Boolean,phase:Number):String {
        var tm:Object=make(legacy);var frame:Number=0;var log:Array=[];
        for(var p:Number=0;p<phase;p++){frame++;tm.updateFrame();}
        // 包含 single/second/third/overflow；同一截止期来自不同 lane。
        var delays:Array=[1,149,150,151,1800,1830,108000,108001];
        for(var i:Number=0;i<delays.length;i++) addRecorded(tm,delays[i]*1000/30,String(delays[i]),log,function():Number{return frame;});
        for(var n:Number=0;n<109850;n++){frame++;tm.updateFrame();}
        return log.join(",");
    }
    private static function addRecorded(tm:Object,ms:Number,label:String,log:Array,frame:Function):Void {
        tm.addTask(function():Void{log.push(label+"@"+frame());},ms,1,[]);
    }
    private static function deadlines():Void {
        for(var p:Number=0;p<2;p++) {
            var phase:Number=p==0?0:17;
            var a:String=deadlineRun(true,phase);var b:String=deadlineRun(false,phase);
            check(a==b,"coarse deadline/lane difference phase "+phase+" old="+a+" new="+b);
            trace("SchedulerDeadlineParity phase="+phase+" events="+b);
        }
        var scheduler:CerberusScheduler=new CerberusScheduler();var tm:TaskManager=new TaskManager(scheduler,30);
        scheduler.currentFrame=2147483647;
        var calls:Number=0;tm.addTask(function():Void{calls++;},1000,1,[]);tick(tm,30);
        check(calls==1&&scheduler.currentFrame==2147483677,"frame clock not int32 truncated");
        var id:String=tm.addTask(function():Void{},100000000000,1,[]);
        check(tm.locateTask(id).intervalFrames==3000000000,"large delay not int32 truncated");
        var rejected:Boolean=false;try{tm.addTask(function():Void{},Infinity,1,[]);}catch(error){rejected=true;}
        check(rejected,"nonfinite initial interval rejected");
    }
    public static function runOrderingTests():Void {
        passed=0;failed=0;
        var tm:Object=make(false);var owner:Object={};var order:Array=[];
        tm.addLifecycleTask(owner,"a",function():Void{order.push("a");},0,[]);
        var b:String=tm.addLifecycleTask(owner,"b",function():Void{order.push("b");},0,[]);
        tm.addLifecycleTask(owner,"c",function():Void{order.push("c");},0,[]);
        tm.updateFrame();check(order.join(",")=="a,b,c","zero registration order");order.length=0;
        check(b==tm.addOrUpdateTask(owner,"b",function():Void{order.push("B");},0,[]),"zero update same ID");
        tm.updateFrame();check(order.join(",")=="a,B,c","zero 0->0 same position");order.length=0;
        tm.delayTask(b,true);tm.delayTask(b,false);tm.updateFrame();check(order.join(",")=="a,c,B","leave/reenter at tail");
        tm=make(false);owner={};order=[];var added:Boolean=false;
        tm.addLifecycleTask(owner,"producer",function():Void {order.push("p");if(!added){added=true;tm.addLifecycleTask(owner,"late",function():Void{order.push("l");},0,[]);}},0,[]);
        tm.addLifecycleTask(owner,"consumer",function():Void{order.push("c");},0,[]);
        tm.updateFrame();check(order.join(",")=="p,c","new zero ID after snapshot waits");order.length=0;
        tm.updateFrame();check(order.join(",")=="p,c,l","late zero next frame");
        tm=make(false);owner={};order=[];
        tm.addLifecycleTask(owner,"consumer",function():Void{order.push("c");},0,[]);
        tm.addSingleTask(function():Void {tm.addLifecycleTask(owner,"timedProducer",function():Void{order.push("p");},0,[]);},1,[]);
        tm.updateFrame();check(order.join(",")=="c,p","timed-created zero joins current phase");
        trace("SchedulerOrderingTests passed="+passed+" failed="+failed);
    }
    private static function api():Void {
        var tm:Object=make(false);var synchronous:Number=0;
        check(tm.addSingleTask(function():Void{synchronous++;},0,[])==null&&synchronous==1,"single zero synchronous");
        var queued:Number=0;tm.addTask(function():Void{queued++;},0,1,[]);check(queued==0,"addTask zero asynchronous");tm.updateFrame();check(queued==1,"zero once");
        for(var n:Number=0;n<7;n++) {
            var owner:Object={sum:0};var params:Array=[];for(var j:Number=0;j<n;j++)params.push(j+1);
            var id:String=tm.addOrUpdateTask(owner,"params",function():Void{this.sum=0;for(var k:Number=0;k<arguments.length;k++)this.sum+=arguments[k];},1,params);
            if(n>0)params[0]=10;
            tm.updateFrame();check(owner.sum==(n==0?0:n*(n+1)/2+9),"receiver/parameter reference "+n);
            check(tm.locateTask(id)==null,"single label consumed "+n);
        }
        owner={};var calls:Number=0;
        id=tm.addOrUpdateTask(owner,"repeat",function():Void{calls++;},1,[]);
        tm.locateTask(id).repeatCount=4;
        tm.addOrUpdateTask(owner,"repeat",function():Void{calls++;},1,[]);
        check(tm.locateTask(id).repeatCount==4,"upsert preserves repeatCount");tick(tm,4);check(calls==4,"finite repetitions");
        var next:String=tm.addOrUpdateTask(owner,"repeat",function():Void{},1,[]);check(next!=id,"ghost label new ID");tm.removeTask(next);
        owner={};calls=0;
        id=tm.addOrUpdateTask(owner,"self",function():Void{calls++;tm.addOrUpdateTask(owner,"self",arguments.callee,1,[]);},1,[]);
        tm.locateTask(id).repeatCount=3;tick(tm,10);check(calls==3&&tm.locateTask(id)==null,"self upsert counts actual invocations");
        calls=0;id=tm.addTask(function():Void{calls++;tm.delayTask(id,100);},1,3,[]);tick(tm,20);check(calls==3&&tm.locateTask(id)==null,"self delay finite repetitions");
        calls=0;id=tm.addLoopTask(function():Void{calls++;},100,[]);tm.delayTask(id,true);tick(tm,100);check(calls==0&&tm.getStats().paused==1,"pause off heap");
        check(tm.getStats().heap==0,"pause has no heap entry");tm.delayTask(id,false);tick(tm,3);check(calls==1,"resume original interval");tm.removeTask(id);
        var later:String;var cancelled:Number=0;
        tm.addSingleTask(function():Void{tm.removeTask(later);},1,[]);later=tm.addSingleTask(function():Void{cancelled++;},1,[]);tm.updateFrame();check(cancelled==0,"cancel next due callback");
        later=null;var after:Number=0;
        tm.addSingleTask(function():Void{tm.delayTask(later,100);},1,[]);later=tm.addSingleTask(function():Void{after++;},1,[]);tm.updateFrame();check(after==0,"delay next due callback");tick(tm,4);check(after==1,"delayed peer fires once");
        owner={};id=tm.addLifecycleTask(owner,"life",function():Void{},0,[]);owner.onUnload();check(tm.locateTask(id)==null,"unload removes lifecycle");
        // 捕获真正注册给 EventCoordinator 的旧闭包，避免调用空 receiver 制造假通过。
        var coordinator:Object=org.flashNight.aven.Coordinator.EventCoordinator;
        var originalRegistration:Function=coordinator.addUnloadCallback;
        var saved:Array=[];
        coordinator.addUnloadCallback=function(target:Object, callback:Function):String {
            saved.push(callback);return originalRegistration.call(coordinator,target,callback);
        };
        owner={};
        try {
            id=tm.addLifecycleTask(owner,"life",function():Void{},0,[]);
            var oldUnload:Function=saved[0];tm.clear();
            next=tm.addLifecycleTask(owner,"life",function():Void{},0,[]);oldUnload();
        } finally { coordinator.addUnloadCallback=originalRegistration; }
        check(tm.locateTask(next)!=null,"old generation unload cannot remove new task");tm.removeTask(next);
        var first:Number=0;var second:Number=0;
        tm.addSingleTask(function():Void{first++;tm.updateFrame(2);},1,[]);tm.addSingleTask(function():Void{second++;},100,[]);
        tm.updateFrame(1);check(first==1&&second==0&&tm.getStats().frame==1,"recursive update rejected");tm.updateFrame(1);check(tm.getStats().frame==1,"duplicate token rejected");
        tm.updateFrame(2);tm.updateFrame(3);check(second==1,"fresh tokens advance once");
        tm=make(false);calls=0;tm.addSingleTask(function():Void{tm.clear();},1,[]);tm.addSingleTask(function():Void{calls++;},1,[]);tm.updateFrame();check(calls==0&&tm.getStats().n==0,"clear interrupts old stack");
        tm=make(false);tm.addLoopTask(function():Void{},1,[]);tm.destroy();check(tm.getStats().n==0&&!tm.getStats().alive,"destroy clears ownership");
        var threw:Boolean=false;try{tm.addLoopTask(function():Void{},1,[]);}catch(error){threw=true;}check(threw,"destroy rejects new registrations");
    }
    private static function exceptionalAndProbe():Void {
        var tm:Object=make(false);var after:Number=0;var before:Number=0;
        tm.addSingleTask(function():Void {before++;throw new Error("fixture propagation");},1,[]);
        tm.addSingleTask(function():Void {after++;},1,[]);
        var propagated:Boolean=false;
        try {tm.updateFrame(1);}catch(error) {propagated=true;}
        check(propagated&&before==1&&after==0,"callback exception propagates without pretending later callbacks ran");
        check(tm.getStats().n==1&&tm.getStats().short==1,"remaining snapshot restored after exception");
        tm.updateFrame(2);check(after==1&&tm.getStats().n==0,"later callback remains owned and fires once");
        check(tm.getProbeSnapshot()==null,"sampling defaults off");
        tm.setProbeCapacity(3);tm.addLoopTask(function():Void{},0,[]);tick(tm,5);
        var probe:Object=tm.getProbeSnapshot();
        check(probe.count==3&&probe.n.length==3&&probe.z[0]==1&&probe.k[0]==1,"bounded numeric sampling");
        tm.setProbeCapacity(0);check(tm.getProbeSnapshot()==null,"sampling disabled explicitly");tm.clear();
    }
    /** 真正的 FP20 MovieClip 路径重用：script-phase remove，下一 enterFrame 核对旧 unload 与新 owner。 */
    public static function runMovieClipTests(complete:Function):Void {
        var tm:Object=make(false);var name:String="schedulerDebtOwner";
        var oldClip:MovieClip=_root.createEmptyMovieClip(name,_root.getNextHighestDepth());
        var oldCalls:Number=0;var newCalls:Number=0;
        var oldId:String=tm.addLifecycleTask(oldClip,"pulse",function():Void{oldCalls++;},0,[]);
        oldClip.removeMovieClip();
        var nextClip:MovieClip=_root.createEmptyMovieClip(name,_root.getNextHighestDepth());
        var newId:String=tm.addLifecycleTask(nextClip,"pulse",function():Void{newCalls++;},0,[]);
        var driver:MovieClip=_root.createEmptyMovieClip("schedulerDebtDriver",_root.getNextHighestDepth());
        var frames:Number=0;
        driver.onEnterFrame=function():Void {
            frames++;tm.updateFrame(frames);
            if(frames<3)return;
            check(oldCalls==0&&tm.locateTask(oldId)==null,"real clip stale owner cancelled");
            check(newCalls==3&&tm.locateTask(newId)!=null,"old clip unload cannot cancel replacement owner");
            tm.destroy();driver.removeMovieClip();nextClip.removeMovieClip();
            trace("SchedulerMovieClipTests passed="+passed+" failed="+failed);complete();
        };
    }
    public static function runBoundaryTests():Void {
        passed=failed=0;
        var tm:Object=make(false);var calls:Number=0;
        var id:String=tm.addSingleTask(function():Void{calls++;},100,[]);
        var task:Object=tm.locateTask(id);var due:Number=task.due;
        check(!tm.delayTask(id,1e30)&&tm.locateTask(id)===task&&task.due==due,"oversized delay leaves existing task intact");
        var rejected:Boolean=false;try{tm.addLoopTask(function():Void{},1e30,[]);}catch(error){rejected=true;}
        check(rejected&&tm.getStats().n==1,"oversized registration leaves no orphan");
        tick(tm,3);check(calls==1&&tm.getStats().n==0,"existing task still executes exactly once");
        var scheduler:CerberusScheduler=new CerberusScheduler();var direct:Task=new Task("direct",30,1);
        scheduler.scheduleTask(direct,30);var slot:Number=direct.timedSlot;
        rejected=false;try{scheduler.scheduleTask(direct,1e30);}catch(error){rejected=true;}
        check(rejected&&direct.timedSlot==slot&&scheduler.validateHeap(),"invalid direct reschedule validates before detach");
        trace("SchedulerBoundaryTests passed="+passed+" failed="+failed);
    }
    private static function heapStress():Void {
        var scheduler:CerberusScheduler=new CerberusScheduler();var tasks:Array=[];var seed:Number=17;
        for(var i:Number=0;i<512;i++) {
            seed=(seed*48271)%2147483647;var task:Task=new Task(String(i),1,1);tasks.push(task);scheduler.scheduleTask(task,seed%5000+150000);
        }
        check(scheduler.validateHeap(),"heap insertion indexes");
        for(var n:Number=0;n<700;n++) {
            seed=(seed*48271)%2147483647;var t:Task=tasks[seed%512];
            if(n%3==0) scheduler.removeTask(t);else scheduler.scheduleTask(t,seed%7000+150000);
            if(n%20==0)check(scheduler.validateHeap(),"heap mutation indexes "+n);
        }
        var expected:Array=[];for(i=0;i<tasks.length;i++)if(tasks[i].heapIndex>=0)expected.push(tasks[i]);
        expected.sort(function(a:Task,b:Task):Number{if(a.due!=b.due)return a.due-b.due;if(a.lane!=b.lane)return a.lane-b.lane;return a.order-b.order;});
        scheduler.currentFrame=1000000;
        for(i=0;i<expected.length;i++)check(scheduler.popDue()===expected[i],"heap ordered pop "+i);
        check(scheduler.getHeapSize()==0&&scheduler.validateHeap(),"heap drained without aliases");
    }
    private static function load(legacy:Boolean,n:Number,frames:Number):Object {
        var tm:Object=make(legacy);var calls:Number=0;var delays:Array=[1,5,30,150,1830];
        for(var i:Number=0;i<n;i++)tm.addLoopTask(function():Void{calls++;},delays[i%delays.length]*1000/30,[]);
        var start:Number=getTimer();tick(tm,frames);return {ms:getTimer()-start,calls:calls};
    }
    private static function benchmark():Void {
        load(true,16,100);load(false,16,100);
        var sizes:Array=[32,128,512];
        for(var s:Number=0;s<sizes.length;s++) {
            var a:Array=[];var b:Array=[];var k:Number=0;
            for(var r:Number=0;r<3;r++) {
                var old:Object=load(true,sizes[s],1000);var next:Object=load(false,sizes[s],1000);
                a.push(old.ms);b.push(next.ms);k=next.calls;check(old.calls==next.calls,"benchmark callback parity "+s+"/"+r);
            }
            a.sort(Array.NUMERIC);b.sort(Array.NUMERIC);
            trace("SchedulerBenchmark n="+sizes[s]+" frames=1000 k="+k+" oldMedianMs="+a[1]+" newMedianMs="+b[1]+" oldSamples="+a.join(",")+" newSamples="+b.join(","));
        }
    }
    public static function runAllTests():Void {
        runOrderingTests();alias("control");alias("cancel");alias("delay");api();exceptionalAndProbe();heapStress();deadlines();benchmark();
        trace("SchedulerDebtTest passed="+passed+" failed="+failed);
    }
}
